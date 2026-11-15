import { supabase } from "../supabase";
import { el, mensagem } from "./dom";
import { carregarReferencias, todasEspecies } from "./dados";
import { textoPremio, type Premio } from "./engajamento";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;
interface Catalogo { itens: { slug: string; nome: string }[]; cosmeticos: { id: string; tipo: string; nome: string }[] }

const botao = (texto: string, fn: () => void, classe = ""): HTMLButtonElement => {
  const b = el("button", { type: "button", class: classe }, texto);
  b.addEventListener("click", fn);
  return b;
};
const msgPainel = (): HTMLElement => el("p", { class: "msg", role: "status" });
const num = (v: string): number => Math.max(0, Math.floor(Number(v) || 0));

/** Caixa de explicação no topo de cada tela. */
const ajuda = (titulo: string, ...linhas: string[]): HTMLElement =>
  el("div", { class: "eg-ajuda" }, el("strong", {}, titulo), ...linhas.map((l) => el("p", {}, l)));
/** Rodapé fixo com o botão de salvar e a mensagem de resultado. */
const rodape = (msg: HTMLElement, ...botoes: HTMLElement[]): HTMLElement => el("div", { class: "eg-rodape" }, msg, el("div", { class: "eg-rodape-bt" }, ...botoes));
const secao = (titulo: string, dica?: string): HTMLElement => el("div", { class: "eg-secao" }, el("h3", { class: "eg-cat" }, titulo), ...(dica ? [el("p", { class: "eg-dica" }, dica)] : []));
/** Campo com rótulo fixo (não some quando se digita). */
const campo = (rotulo: string, entrada: HTMLElement, dica?: string): HTMLElement =>
  el("label", { class: "eg-campo" }, el("span", { class: "eg-rot" }, rotulo), entrada, ...(dica ? [el("span", { class: "eg-dica" }, dica)] : []));
const entrada = (tipo: string, valor: string | number | undefined, extra: Record<string, string> = {}): HTMLInputElement =>
  el("input", { type: tipo, class: "eg-in", value: valor === undefined ? "" : String(valor), ...extra });

const grade = (...nos: Node[]): HTMLElement => el("div", { class: "eg-campos" }, ...nos);
const bloco = (titulo: string, ...nos: Node[]): HTMLElement => el("div", { class: "eg-bloco" }, el("strong", { class: "eg-bloco-tit" }, titulo), ...nos);

async function catalogo(): Promise<Catalogo> {
  const { data } = await supabase.rpc("mestre_catalogo_premios");
  return (data ?? { itens: [], cosmeticos: [] }) as Catalogo;
}

function campoNum(valor: number | undefined, ao: () => void, extra: Record<string, string> = {}): HTMLInputElement {
  const i = el("input", { type: "number", min: "0", class: "eg-in", value: valor ? String(valor) : "", ...extra });
  i.addEventListener("input", ao);
  return i;
}

/** Editor de um prêmio (dinheiro, XP, PA, até 2 itens, título, moldura, ovo), com rótulos e resumo ao vivo. */
export function editorPremio(inicial: Premio | null | undefined, cat: Catalogo, ao?: () => void): { no: HTMLElement; ler: () => Premio; resumo: () => string } {
  const p = inicial ?? {};
  const resumoEl = el("div", { class: "eg-resumo" });
  let ler: () => Premio = () => ({});
  const atualizar = (): void => { resumoEl.textContent = `Prêmio: ${textoPremio(ler())}`; ao?.(); };
  const din = campoNum(p.dinheiro, atualizar, { placeholder: "0" });
  const xp = campoNum(p.xp_treinador, atualizar, { placeholder: "0" });
  const pa = campoNum(p.pa, atualizar, { placeholder: "0" });
  const itemSel = (atual?: { item: string; qtd: number }): { s: HTMLSelectElement; q: HTMLInputElement } => {
    const s = el("select", { class: "eg-in" }, el("option", { value: "" }, "— nenhum —"), ...cat.itens.map((i) => el("option", { value: i.slug }, i.nome)));
    s.value = atual?.item ?? "";
    s.addEventListener("change", atualizar);
    return { s, q: campoNum(atual?.qtd, atualizar, { placeholder: "1" }) };
  };
  const i1 = itemSel(p.itens?.[0]);
  const i2 = itemSel(p.itens?.[1]);
  const cosSel = (tipo: string, atual?: string): HTMLSelectElement => {
    const s = el("select", { class: "eg-in" }, el("option", { value: "" }, "— nenhum —"), ...cat.cosmeticos.filter((c) => c.tipo === tipo).map((c) => el("option", { value: c.id }, c.nome)));
    s.value = atual ?? "";
    s.addEventListener("change", atualizar);
    return s;
  };
  const tit = cosSel("titulo", p.titulo);
  const mol = cosSel("moldura", p.moldura);
  const ovoEsp = campoNum(p.ovo?.especie, atualizar, { placeholder: "ex.: 25" });
  const ovoPassos = campoNum(p.ovo?.passos, atualizar, { placeholder: "ex.: 1000" });
  const no = el("div", { class: "eg-premio" }, resumoEl,
    el("div", { class: "eg-grade3" }, campo("Dinheiro (₽)", din), campo("XP de treinador", xp), campo("Pontos de Aventura (PA)", pa)),
    el("div", { class: "eg-linha" }, campo("Item 1", i1.s), campo("Quantidade", i1.q)),
    el("div", { class: "eg-linha" }, campo("Item 2 (opcional)", i2.s), campo("Quantidade", i2.q)),
    el("div", { class: "eg-grade2" }, campo("Título (enfeite)", tit), campo("Moldura (enfeite)", mol)),
    el("div", { class: "eg-grade2" }, campo("Ovo: nº da espécie", ovoEsp), campo("Ovo: passos para chocar", ovoPassos, "Preencha os dois para dar um ovo.")));
  ler = (): Premio => {
    const r: Premio = {};
    if (num(din.value)) r.dinheiro = num(din.value);
    if (num(xp.value)) r.xp_treinador = num(xp.value);
    if (num(pa.value)) r.pa = num(pa.value);
    const itens = [i1, i2].filter((x) => x.s.value && num(x.q.value) > 0).map((x) => ({ item: x.s.value, qtd: num(x.q.value) }));
    if (itens.length) r.itens = itens;
    if (tit.value) r.titulo = tit.value;
    if (mol.value) r.moldura = mol.value;
    if (num(ovoEsp.value) && num(ovoPassos.value)) r.ovo = { especie: num(ovoEsp.value), passos: num(ovoPassos.value) };
    return r;
  };
  resumoEl.textContent = `Prêmio: ${textoPremio(ler())}`;
  return { no, ler, resumo: () => textoPremio(ler()) };
}

/** Cartão recolhível cujo cabeçalho mostra o título e o resumo do prêmio (atualizado ao digitar). */
function cartao(titulo: string, resumoInicial: string): { det: HTMLDetailsElement; resumo: HTMLElement } {
  const resumo = el("span", { class: "eg-sum-prem" }, resumoInicial);
  const det = el("details", { class: "eg-sem" }, el("summary", {}, el("span", { class: "eg-sum-tit" }, titulo), resumo)) as HTMLDetailsElement;
  return { det, resumo };
}

// ---------- Check-in ----------
interface DadosCheckin {
  inicio: string; meta: number; modo: string; hoje: string;
  calendario: { semana: number; dia: number; rotulo: string | null; recompensa: Premio }[];
  semanas: { semana: number; tema: string | null; recompensa: Premio }[];
}

export async function abrirMestreCheckin(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const [{ data, error }, cat] = await Promise.all([supabase.rpc("mestre_checkin_obter"), catalogo()]);
  if (error) return aviso(error.message, 4000, true);
  const d = data as DadosCheckin;
  const msg = msgPainel();
  const inicio = entrada("date", d.inicio);
  const meta = entrada("number", d.meta, { min: "1", max: "7" });
  const modo = el("select", { class: "eg-in" }, el("option", { value: "repetir" }, "Recomeçar na Semana 1 (repete para sempre)"), el("option", { value: "parar" }, "Parar (o check-in acaba)"));
  modo.value = d.modo;
  const leitores: { semana: number; dia?: number; tema?: HTMLInputElement; ler: () => Premio }[] = [];
  const semanas = Array.from({ length: 8 }, (_, i) => i + 1).map((s) => {
    const premio = d.semanas.find((x) => x.semana === s);
    const tema = entrada("text", premio?.tema ?? "", { placeholder: "ex.: Boas-vindas" });
    const topo = cartao(`Semana ${s}`, "");
    const ep = editorPremio(premio?.recompensa, cat, () => { topo.resumo.textContent = `Prêmio semanal: ${ep.resumo()}`; });
    topo.resumo.textContent = `Prêmio semanal: ${ep.resumo()}`;
    leitores.push({ semana: s, tema, ler: ep.ler });
    const dias = Array.from({ length: 7 }, (_, k) => k + 1).map((dia) => {
      const c = d.calendario.find((x) => x.semana === s && x.dia === dia);
      const cd = cartao(`Dia ${dia}`, "");
      const ed = editorPremio(c?.recompensa, cat, () => { cd.resumo.textContent = ed.resumo(); });
      cd.resumo.textContent = ed.resumo();
      leitores.push({ semana: s, dia, ler: ed.ler });
      cd.det.append(ed.no);
      return cd.det;
    });
    topo.det.append(
      campo("Tema da semana (só para o senhor se organizar)", tema),
      el("strong", {}, "Prêmio da semana (ganho quando a meta de dias é cumprida)"), ep.no,
      el("strong", {}, "Prêmio de cada dia (abra o dia para editar)"), el("div", { class: "eg-dias" }, ...dias));
    return { det: topo.det };
  });
  const copiarMarca = el("input", { type: "checkbox" });
  const copiarRot = el("label", { class: "eg-campo" }, el("span", { class: "eg-rot" }, "Ao salvar, copiar a Semana 1 para as Semanas 2 a 8"), copiarMarca,
    el("span", { class: "eg-dica" }, "Marque só se quiser que as 8 semanas fiquem iguais à Semana 1. Desmarque depois de salvar."));
  const salvar = botao("Salvar calendário", async () => {
    salvar.disabled = true;
    const lidos = leitores.map((l) => ({ ...l, p: l.ler() }));
    const premioDe = (semana: number, dia?: number): Premio => {
      const origem = copiarMarca.checked ? 1 : semana;
      return lidos.find((x) => x.semana === origem && x.dia === dia)?.p ?? {};
    };
    const calendario = lidos.filter((l) => l.dia).map((l) => ({ semana: l.semana, dia: l.dia, recompensa: premioDe(l.semana, l.dia) }));
    const sem = lidos.filter((l) => !l.dia).map((l) => ({ semana: l.semana, tema: l.tema?.value ?? "", recompensa: premioDe(l.semana) }));
    const { error: er } = await supabase.rpc("mestre_checkin_salvar", { p: { inicio: inicio.value, meta: Number(meta.value), modo: modo.value, calendario, semanas: sem } });
    salvar.disabled = false;
    if (er) return mensagem(msg, er.message);
    mensagem(msg, "Calendário salvo.", "ok");
    if (copiarMarca.checked) void abrirMestreCheckin(modal, aviso);
  });
  modal.abrir("Mestre · Check-in diário",
    ajuda("Como funciona",
      `Hoje (dia de jogo, que vira às 6h): ${d.hoje}.`,
      "O jogador faz um check-in por dia e ganha o prêmio daquele dia. O calendário tem 8 semanas de 7 dias, e cada dia tem seu prêmio.",
      "Cumprindo a meta de dias da semana, ele ganha também o prêmio semanal. O ciclo começa na data de início (que é o Dia 1 da Semana 1).",
      "Itens só aceitam o que existe no catálogo. Para salvar, use o botão fixo no rodapé."),
    secao("Configuração geral"),
    grade(campo("Data de início (Dia 1 da Semana 1)", inicio),
      campo("Dias de check-in na semana para ganhar o prêmio semanal", meta, "De 1 a 7. Uma sequência com falhas ainda conta se atingir essa meta."),
      campo("Quando terminar a Semana 8", modo)),
    secao("Prêmios por semana", "Toque numa semana para abrir. O cabeçalho já mostra o prêmio salvo."),
    ...semanas.map((x) => x.det),
    copiarRot,
    rodape(msg, salvar));
}

// ---------- Conquistas ----------
interface ConquistaM { id: string; categoria: string; nome: string; descricao: string; metrica: string; meta: number; periodo: string; recompensa: Premio; ordem: number; grupo: string | null; ativa: boolean }
const METRICAS: [string, string][] = [
  ["captura", "Capturar Pokémon"], ["vitoria_selvagem", "Vencer Pokémon selvagem"], ["vitoria_treinador", "Vencer treinador (NPC)"], ["vitoria_lider", "Vencer líder de ginásio"],
  ["duelo", "Fazer duelos"], ["duelo_vitoria", "Vencer duelos"], ["evolucao", "Evoluir Pokémon"], ["missao", "Concluir missões"], ["checkin", "Fazer check-ins"],
  ["cura", "Curar o time"], ["time_dia", "Usar o time completo (6 Pokémon) em batalhas no mesmo dia"], ["duelo_oponentes", "Duelar com jogadores diferentes"],
  ["miniquest", "Concluir desafios da semana"], ["ovo", "Chocar ovos"],
];
const nomeMetrica = (m: string): string => METRICAS.find((x) => x[0] === m)?.[1] ?? m;
const PERIODOS: [string, string][] = [["total", "Total (desde sempre)"], ["dia", "Em um único dia"], ["semana", "Em uma única semana"]];
const nomePeriodo = (p: string): string => PERIODOS.find((x) => x[0] === p)?.[1] ?? p;

export async function abrirMestreConquistas(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const [{ data, error }, cat] = await Promise.all([supabase.rpc("mestre_conquistas_obter"), catalogo()]);
  if (error) return aviso(error.message, 4000, true);
  const lista = (data ?? []) as ConquistaM[];
  const msg = msgPainel();
  const salvarUma = async (c: ConquistaM, ler: () => Premio): Promise<void> => {
    const { error: er } = await supabase.rpc("mestre_conquista_salvar", { p: { ...c, recompensa: ler() } });
    if (er) return mensagem(msg, er.message);
    mensagem(msg, `Salvo: ${c.nome}`, "ok");
  };
  const categorias = [...new Set(lista.map((c) => c.categoria))];
  const blocos = categorias.flatMap((cat1) => [
    secao(cat1),
    ...lista.filter((c) => c.categoria === cat1).map((c) => {
      const nome = entrada("text", c.nome);
      const meta = entrada("number", c.meta, { min: "1" });
      const ativa = el("input", { type: "checkbox" });
      ativa.checked = c.ativa;
      const cd = cartao(`${c.ativa ? "" : "(desligada) "}${c.nome}`, "");
      const ep = editorPremio(c.recompensa, cat, () => { cd.resumo.textContent = ep.resumo(); });
      cd.resumo.textContent = ep.resumo();
      const b = botao("Salvar esta conquista", () => void salvarUma({ ...c, nome: nome.value, meta: num(meta.value) || 1, ativa: ativa.checked }, ep.ler));
      cd.det.append(
        el("p", { class: "eg-dica" }, `${c.descricao} Regra: ${nomeMetrica(c.metrica)} — meta ${c.meta} — ${nomePeriodo(c.periodo)}.`),
        grade(campo("Nome da conquista", nome), campo("Meta (quantidade para concluir)", meta)),
        el("label", { class: "eg-mod" }, ativa, " Conquista ativa (desmarque para esconder e parar)"),
        el("strong", {}, "Prêmio"), ep.no, b);
      return cd.det;
    }),
  ]);
  // nova conquista
  const nId = entrada("text", "", { placeholder: "ex.: cap_200 (sem espaços)" });
  const nNome = entrada("text", "", { placeholder: "ex.: Colecionador" });
  const nDesc = entrada("text", "", { placeholder: "ex.: Capture 200 Pokémon." });
  const nMet = el("select", { class: "eg-in" }, ...METRICAS.map(([m, r]) => el("option", { value: m }, r)));
  const nMeta = entrada("number", "", { min: "1", placeholder: "ex.: 200" });
  const nPer = el("select", { class: "eg-in" }, ...PERIODOS.map(([v, r]) => el("option", { value: v }, r)));
  const nEp = editorPremio({}, cat);
  const criar = botao("Criar conquista", () => void salvarUma({ id: nId.value.trim(), categoria: "Personalizada", nome: nNome.value, descricao: nDesc.value, metrica: nMet.value, meta: num(nMeta.value) || 1, periodo: nPer.value, recompensa: {}, ordem: 500, grupo: null, ativa: true }, nEp.ler).then(() => abrirMestreConquistas(modal, aviso)));
  const nova = el("details", { class: "eg-sem" }, el("summary", {}, el("span", { class: "eg-sum-tit" }, "+ Nova conquista")),
    grade(campo("Código (único, sem espaços)", nId), campo("Nome", nNome), campo("Descrição mostrada ao jogador", nDesc),
      campo("O que conta", nMet), campo("Meta (quantidade)", nMeta), campo("Período", nPer, "Total = soma de sempre; Dia/Semana = precisa acontecer dentro de um único dia/semana.")),
    el("strong", {}, "Prêmio"), nEp.no, criar);
  modal.abrir("Mestre · Conquistas",
    ajuda("Como funciona",
      "Cada conquista tem uma regra (o que conta), uma meta (quantas vezes) e um período (total, num dia ou numa semana).",
      "Aqui o senhor muda o nome, a meta, o prêmio e liga ou desliga cada conquista. A mudança vale para quem ainda não concluiu.",
      "Cada cartão mostra o prêmio atual no cabeçalho. Cada conquista tem seu próprio botão de salvar."),
    ...blocos, secao("Criar uma nova"), nova, rodape(msg));
}

// ---------- Ranking ----------
interface DadosRanking {
  periodo: { id: number; inicio: string; fim: string };
  duracao: number;
  pontos: Record<string, number>; tetos: Record<string, number>; pares: number[];
  premios: { minimo: number; podio: Premio[]; participacao: Premio };
  rivais: { id: string; nome: string; fator: number; ativo: boolean }[];
  jogadores: { id: string; nome: string; pontos: number }[];
}
const ROT_PONTOS: Record<string, string> = {
  lider: "Vencer líder de ginásio", captura: "Capturar um Pokémon", selvagem: "Vencer um Pokémon selvagem", treinador: "Vencer um treinador (NPC)",
  duelo_derrota: "Perder um duelo", duelo_vitoria: "Vencer um duelo",
};
const ROT_TETOS: Record<string, string> = { npc: "Pontos por dia contra NPCs (treinadores e líderes)", selv: "Pontos por dia contra Pokémon selvagens" };

export async function abrirMestreRanking(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const [{ data, error }, cat] = await Promise.all([supabase.rpc("mestre_ranking_obter"), catalogo()]);
  if (error) return aviso(error.message, 4000, true);
  const d = data as DadosRanking;
  const msg = msgPainel();
  const duracao = entrada("number", d.duracao, { min: "1", max: "120" });
  const aplicar = el("input", { type: "checkbox" });
  const minimo = entrada("number", d.premios.minimo ?? 0, { min: "0" });
  const pts = Object.entries(d.pontos).map(([k, v]) => ({ k, i: entrada("number", v, { min: "0" }) }));
  const tetos = Object.entries(d.tetos).map(([k, v]) => ({ k, i: entrada("number", v, { min: "0" }) }));
  const podios = [0, 1, 2].map((i) => editorPremio(d.premios.podio?.[i], cat));
  const part = editorPremio(d.premios.participacao, cat);
  const rivais = d.rivais.map((r) => ({ r, f: entrada("number", r.fator, { step: "0.05", min: "0", max: "2" }) }));
  const salvar = botao("Salvar configuração", async () => {
    const p = {
      duracao: num(duracao.value), aplicar_atual: aplicar.checked,
      pontos: Object.fromEntries(pts.map((x) => [x.k, num(x.i.value)])), tetos: Object.fromEntries(tetos.map((x) => [x.k, num(x.i.value)])),
      premios: { minimo: num(minimo.value), podio: podios.map((x) => x.ler()), participacao: part.ler() },
      rivais: rivais.map((x) => ({ id: x.r.id, fator: Number(x.f.value) || 0 })),
    };
    const { error: er } = await supabase.rpc("mestre_ranking_salvar", { p });
    mensagem(msg, er ? er.message : "Configuração salva.", er ? "erro" : "ok");
  });
  let armado = false;
  const fechar = botao("Encerrar período agora e premiar", async () => {
    if (!armado) { armado = true; fechar.textContent = "Confirmar? Isso paga os prêmios agora"; fechar.classList.add("perigo"); window.setTimeout(() => { armado = false; fechar.textContent = "Encerrar período agora e premiar"; fechar.classList.remove("perigo"); }, 6000); return; }
    const { error: er } = await supabase.rpc("mestre_ranking_fechar");
    if (er) return mensagem(msg, er.message);
    aviso("Período encerrado e prêmios entregues.", 5000);
    void abrirMestreRanking(modal, aviso);
  }, "sec");
  const lin = d.jogadores.map((j) => {
    const delta = entrada("number", "", { placeholder: "± pontos (ex.: 10 ou -5)" });
    return el("div", { class: "ev-item" }, el("span", {}, `${j.nome}: ${j.pontos} pontos`), delta, botao("Ajustar", async () => {
      const { error: er } = await supabase.rpc("mestre_ranking_ajustar", { p_jogador: j.id, p_delta: Math.trunc(Number(delta.value) || 0), p_motivo: "ajuste do Mestre" });
      if (er) return mensagem(msg, er.message);
      void abrirMestreRanking(modal, aviso);
    }, "sec"));
  });
  modal.abrir("Mestre · Ranking",
    ajuda("Como funciona",
      `Período atual: ${d.periodo.inicio} até ${d.periodo.fim} (o último dia não conta).`,
      "O jogador ganha pontos de ranking por eventos (vitórias, capturas, duelos). No fim do período, os 3 primeiros ganham o prêmio do pódio e quem pontuou o mínimo ganha o prêmio de participação.",
      "O teto diário limita quantos pontos por dia podem vir de NPCs ou de Pokémon selvagens, para ninguém subir só repetindo isso.",
      "Mudanças valem para os próximos eventos. Use o botão fixo no rodapé para salvar."),
    secao("Duração do período"),
    grade(campo("Duração (dias)", duracao, "Vale para os próximos períodos."),
      el("label", { class: "eg-mod" }, aplicar, " Aplicar essa duração também ao período que já está em andamento")),
    secao("Pontos de ranking por evento", "Quantos pontos cada ação rende."),
    grade(...pts.map((x) => campo(ROT_PONTOS[x.k] ?? x.k, x.i))),
    secao("Limite de pontos por dia", "Depois de atingir o teto, o resto do dia não soma mais pontos daquele tipo."),
    grade(...tetos.map((x) => campo(ROT_TETOS[x.k] ?? x.k, x.i))),
    secao("Prêmios do período"),
    grade(campo("Pontos mínimos para ganhar qualquer prêmio", minimo, "Abaixo disso o jogador não recebe nem o prêmio de participação.")),
    el("div", { class: "eg-premios" },
      bloco("1º lugar", podios[0].no), bloco("2º lugar", podios[1].no), bloco("3º lugar", podios[2].no),
      bloco("Participação (quem atingiu o mínimo)", part.no)),
    secao("Rivais NPC", "Rivais fictícios aparecem no ranking. O fator multiplica os pontos do líder (1 = igual, 0,5 = metade, 0 = não pontua)."),
    grade(...rivais.map((x) => campo(x.r.nome, x.f))),
    secao("Encerrar período", "Paga os prêmios agora e começa um período novo. Use apenas se quiser antecipar o fim."), fechar,
    secao("Pontuação dos jogadores", "Dê ou tire pontos manualmente (aparece como ajuste do Mestre)."),
    el("div", { class: "eg-campos" }, ...(lin.length ? lin : [el("p", { class: "eg-dica" }, "Ninguém pontuou ainda.")])),
    rodape(msg, salvar));
}

// ---------- Mini-quests ----------
interface MqM { id: string; mapa_id: string; nome: string; dica: string; recompensa: Premio; ativa: boolean; sorteada: boolean }

export async function abrirMestreMiniquests(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const [{ data, error }, cat] = await Promise.all([supabase.rpc("mestre_miniquests_obter"), catalogo()]);
  if (error) return aviso(error.message, 4000, true);
  const d = data as { por_semana: number; lista: MqM[] };
  const msg = msgPainel();
  const porSemana = entrada("number", d.por_semana, { min: "0", max: "100" });
  const cartoes = d.lista.map((q) => {
    const nome = entrada("text", q.nome);
    const dica = entrada("text", q.dica);
    const ativa = el("input", { type: "checkbox" });
    ativa.checked = q.ativa;
    const cd = cartao(`${q.sorteada ? "★ " : ""}${q.mapa_id} · ${q.nome}${q.ativa ? "" : " (desligado)"}`, "");
    const ep = editorPremio(q.recompensa, cat, () => { cd.resumo.textContent = ep.resumo(); });
    cd.resumo.textContent = ep.resumo();
    const b = botao("Salvar este desafio", async () => {
      const { error: er } = await supabase.rpc("mestre_miniquests_salvar", { p: { lista: [{ id: q.id, nome: nome.value, dica: dica.value, ativa: ativa.checked, recompensa: ep.ler() }] } });
      mensagem(msg, er ? er.message : `Salvo: ${nome.value}`, er ? "erro" : "ok");
    });
    cd.det.append(
      grade(campo("Nome do desafio", nome), campo("Dica mostrada ao jogador (onde encontrar)", dica)),
      el("label", { class: "eg-mod" }, ativa, " Desafio ativo (entra no sorteio)"),
      el("strong", {}, "Prêmio"), ep.no, b);
    return cd.det;
  });
  const salvar = botao("Salvar quantidade por semana", async (): Promise<void> => {
    const { error: er } = await supabase.rpc("mestre_miniquests_salvar", { p: { por_semana: num(porSemana.value) } });
    mensagem(msg, er ? er.message : "Salvo (vale a partir do próximo sorteio).", er ? "erro" : "ok");
  });
  const resortear = botao("Sortear de novo a semana", async () => {
    const { error: er } = await supabase.rpc("mestre_miniquests_salvar", { p: { por_semana: num(porSemana.value), resortear: true } });
    if (er) return mensagem(msg, er.message);
    void abrirMestreMiniquests(modal, aviso);
  }, "sec");
  modal.abrir("Mestre · Desafios da semana",
    ajuda("Como funciona",
      "Cada desafio é um treinador desafiante escondido num mapa. Toda semana o jogo sorteia alguns entre os ativos; o jogador recebe a dica e, ao vencê-lo, o prêmio.",
      "A estrela (★) marca os sorteados desta semana. Mudar a quantidade vale a partir do próximo sorteio; \"Sortear de novo\" refaz a semana agora.",
      "Cada desafio tem seu próprio botão de salvar."),
    secao("Quantidade por semana"),
    campo("Quantos desafios sorteados por semana", porSemana, "Os já sorteados continuam até você sortear de novo."),
    el("div", { class: "eg-linha" }, salvar, resortear),
    secao("Lista de desafios", "Toque num desafio para editar. O cabeçalho mostra o prêmio atual."),
    ...cartoes, rodape(msg));
}

// ---------- Módulos e ovos ----------
const MODULOS: [string, string, string][] = [
  ["checkin", "Check-in diário", "Calendário de prêmios diários e semanais."],
  ["conquistas", "Conquistas", "Metas permanentes, diárias e semanais com prêmio."],
  ["ranking", "Ranking e revanche de NPCs", "Pontuação por período, pódio e revanche diária contra NPCs (só pontos de ranking)."],
  ["miniquests", "Desafios da semana", "Desafiantes escondidos sorteados por semana."],
  ["casa", "Casa e ovos", "Casa do jogador, incubadoras e ovos que chocam andando."],
  ["capitulos", "Capítulos (ainda sem efeito no jogo)", "Esqueleto pronto para a história por capítulos. Deixe desligado por enquanto."],
];

export async function abrirMestreEngajamento(modal: Modal, _aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const { data } = await supabase.rpc("modulos_estado");
  const est = (data ?? {}) as Record<string, boolean>;
  const msg = msgPainel();
  const caixas = MODULOS.map(([k, rot, desc]) => {
    const c = el("input", { type: "checkbox" });
    c.checked = k === "capitulos" ? est[k] === true : est[k] !== false;
    return { k, c, no: el("label", { class: "eg-mod eg-mod-bloco" }, c, el("span", {}, el("strong", {}, ` ${rot}`), el("span", { class: "eg-dica" }, desc))) };
  });
  const salvar = botao("Salvar módulos", async () => {
    const { error } = await supabase.rpc("mestre_modulos_salvar", { p: Object.fromEntries(caixas.map((x) => [x.k, x.c.checked])) });
    mensagem(msg, error ? error.message : "Módulos atualizados.", error ? "erro" : "ok");
  });
  const { data: js } = await supabase.from("jogadores").select("id, nome").is("conta", null).order("nome");
  const jog = el("select", { class: "eg-in" }, ...((js ?? []) as { id: string; nome: string }[]).map((j) => el("option", { value: j.id }, j.nome)));
  const esp = el("select", { class: "eg-in" }, ...todasEspecies().slice(0, 151).map((e) => el("option", { value: String(e.id) }, `#${e.id} ${e.nome}`)));
  const passos = entrada("number", 1000, { min: "1" });
  const dar = botao("Dar ovo ao jogador", async () => {
    const { error } = await supabase.rpc("mestre_ovo_dar", { p_jogador: jog.value, p_especie: Number(esp.value), p_passos: num(passos.value) || 1000 });
    mensagem(msg, error ? error.message : "Ovo entregue.", error ? "erro" : "ok");
  }, "sec");
  modal.abrir("Mestre · Engajamento",
    ajuda("Como funciona", "Cada módulo pode ser ligado ou desligado. Desligar esconde e pausa o módulo para todos, sem apagar nenhum dado; ao ligar de novo, tudo volta como estava."),
    secao("Módulos"), el("div", { class: "eg-campos" }, ...caixas.map((x) => x.no)),
    secao("Presentear com um ovo", "Entrega um ovo direto para o jogador escolhido (só espécies da Geração 1 no Arco 1)."),
    grade(campo("Jogador", jog), campo("Espécie", esp), campo("Passos para chocar", passos)), dar,
    rodape(msg, salvar));
}
