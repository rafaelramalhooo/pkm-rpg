import { supabase } from "../supabase";
import { el, mensagem } from "./dom";
import { carregarReferencias, todasEspecies } from "./dados";
import type { Premio } from "./engajamento";

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

async function catalogo(): Promise<Catalogo> {
  const { data } = await supabase.rpc("mestre_catalogo_premios");
  return (data ?? { itens: [], cosmeticos: [] }) as Catalogo;
}

function campoNum(rotulo: string, valor: number | undefined, ao: () => void): HTMLInputElement {
  const i = el("input", { type: "number", min: "0", class: "eg-in", placeholder: rotulo, title: rotulo, value: valor ? String(valor) : "" });
  i.addEventListener("input", ao);
  return i;
}

/** Editor de um prêmio (dinheiro, XP, PA, até 2 itens, título, moldura, ovo). Devolve o elemento e um leitor do valor atual. */
export function editorPremio(inicial: Premio | null | undefined, cat: Catalogo, ao?: () => void): { no: HTMLElement; ler: () => Premio } {
  const p = inicial ?? {};
  const noop = ao ?? ((): void => undefined);
  const din = campoNum("₽", p.dinheiro, noop);
  const xp = campoNum("XP treinador", p.xp_treinador, noop);
  const pa = campoNum("PA", p.pa, noop);
  const itemSel = (atual?: { item: string; qtd: number }): { s: HTMLSelectElement; q: HTMLInputElement } => {
    const s = el("select", { class: "eg-in" }, el("option", { value: "" }, "— item —"), ...cat.itens.map((i) => el("option", { value: i.slug }, i.nome)));
    s.value = atual?.item ?? "";
    s.addEventListener("change", noop);
    return { s, q: campoNum("qtd", atual?.qtd, noop) };
  };
  const i1 = itemSel(p.itens?.[0]);
  const i2 = itemSel(p.itens?.[1]);
  const cosSel = (tipo: string, atual?: string): HTMLSelectElement => {
    const s = el("select", { class: "eg-in" }, el("option", { value: "" }, `— ${tipo} —`), ...cat.cosmeticos.filter((c) => c.tipo === tipo).map((c) => el("option", { value: c.id }, c.nome)));
    s.value = atual ?? "";
    s.addEventListener("change", noop);
    return s;
  };
  const tit = cosSel("titulo", p.titulo);
  const mol = cosSel("moldura", p.moldura);
  const ovoEsp = campoNum("ovo: nº da espécie", p.ovo?.especie, noop);
  const ovoPassos = campoNum("ovo: passos", p.ovo?.passos, noop);
  const no = el("div", { class: "eg-premio" }, din, xp, pa, i1.s, i1.q, i2.s, i2.q, tit, mol, ovoEsp, ovoPassos);
  const ler = (): Premio => {
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
  return { no, ler };
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
  const inicio = el("input", { type: "date", class: "eg-in", value: d.inicio });
  const meta = el("input", { type: "number", min: "1", max: "7", class: "eg-in", value: String(d.meta) });
  const modo = el("select", { class: "eg-in" }, el("option", { value: "repetir" }, "Repetir o ciclo de 8 semanas"), el("option", { value: "parar" }, "Parar ao fim das 8 semanas"));
  modo.value = d.modo;
  const leitores: { semana: number; dia?: number; tema?: HTMLInputElement; rotulo?: HTMLInputElement; ler: () => Premio }[] = [];
  const semanas = Array.from({ length: 8 }, (_, i) => i + 1).map((s) => {
    const premio = d.semanas.find((x) => x.semana === s);
    const tema = el("input", { class: "eg-in", placeholder: "Tema da semana", value: premio?.tema ?? "" });
    const ep = editorPremio(premio?.recompensa, cat);
    leitores.push({ semana: s, tema, ler: ep.ler });
    const dias = Array.from({ length: 7 }, (_, k) => k + 1).map((dia) => {
      const c = d.calendario.find((x) => x.semana === s && x.dia === dia);
      const ed = editorPremio(c?.recompensa, cat);
      leitores.push({ semana: s, dia, ler: ed.ler });
      return el("div", { class: "eg-dia-ed" }, el("strong", {}, `Dia ${dia}`), ed.no);
    });
    const det = el("details", { class: "eg-sem" }, el("summary", {}, `Semana ${s}`), el("div", {}, el("strong", {}, "Prêmio da semana (meta cumprida)"), tema, ep.no), ...dias);
    return det;
  });
  const salvar = botao("Salvar calendário", async () => {
    salvar.disabled = true;
    const calendario = leitores.filter((l) => l.dia).map((l) => ({ semana: l.semana, dia: l.dia, recompensa: l.ler() }));
    const sem = leitores.filter((l) => !l.dia).map((l) => ({ semana: l.semana, tema: l.tema?.value ?? "", recompensa: l.ler() }));
    const { error: er } = await supabase.rpc("mestre_checkin_salvar", { p: { inicio: inicio.value, meta: Number(meta.value), modo: modo.value, calendario, semanas: sem } });
    salvar.disabled = false;
    if (er) return mensagem(msg, er.message);
    mensagem(msg, "Calendário salvo.", "ok");
  });
  modal.abrir("Mestre · Check-in diário",
    el("p", { class: "sub" }, `Hoje (dia de jogo): ${d.hoje}. O dia 1 do ciclo é a data de início abaixo. Itens só aceitam o que existe no catálogo.`),
    el("label", {}, "Data de início (dia 1)", inicio), el("label", {}, "Dias por semana para o prêmio semanal", meta), el("label", {}, "Ao fim das 8 semanas", modo),
    ...semanas, salvar, msg);
}

// ---------- Conquistas ----------
interface ConquistaM { id: string; categoria: string; nome: string; descricao: string; metrica: string; meta: number; periodo: string; recompensa: Premio; ordem: number; grupo: string | null; ativa: boolean }
const METRICAS = ["captura", "vitoria_selvagem", "vitoria_treinador", "vitoria_lider", "duelo", "duelo_vitoria", "evolucao", "missao", "checkin", "cura", "time_dia", "duelo_oponentes", "miniquest", "ovo"];

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
  const cartoes = lista.map((c) => {
    const nome = el("input", { class: "eg-in", value: c.nome });
    const meta = el("input", { type: "number", min: "1", class: "eg-in", value: String(c.meta) });
    const ativa = el("input", { type: "checkbox" });
    ativa.checked = c.ativa;
    const ep = editorPremio(c.recompensa, cat);
    const b = botao("Salvar", () => void salvarUma({ ...c, nome: nome.value, meta: num(meta.value) || 1, ativa: ativa.checked }, ep.ler));
    return el("details", { class: "eg-sem" }, el("summary", {}, `${c.ativa ? "" : "(off) "}${c.nome} · ${c.metrica} ≥ ${c.meta} (${c.periodo})`), nome, meta, el("label", {}, ativa, " ativa"), ep.no, b);
  });
  // nova conquista
  const nId = el("input", { class: "eg-in", placeholder: "id (ex.: cap_200)" });
  const nNome = el("input", { class: "eg-in", placeholder: "Nome" });
  const nDesc = el("input", { class: "eg-in", placeholder: "Descrição" });
  const nMet = el("select", { class: "eg-in" }, ...METRICAS.map((m) => el("option", { value: m }, m)));
  const nMeta = el("input", { type: "number", min: "1", class: "eg-in", placeholder: "meta" });
  const nPer = el("select", { class: "eg-in" }, el("option", { value: "total" }, "total"), el("option", { value: "dia" }, "dia"), el("option", { value: "semana" }, "semana"));
  const nEp = editorPremio({}, cat);
  const criar = botao("Criar conquista", () => void salvarUma({ id: nId.value.trim(), categoria: "Personalizada", nome: nNome.value, descricao: nDesc.value, metrica: nMet.value, meta: num(nMeta.value) || 1, periodo: nPer.value, recompensa: {}, ordem: 500, grupo: null, ativa: true }, nEp.ler).then(() => abrirMestreConquistas(modal, aviso)));
  modal.abrir("Mestre · Conquistas", el("p", { class: "sub" }, "Edite metas e prêmios. Mudanças valem para quem ainda não concluiu."), ...cartoes,
    el("details", { class: "eg-sem" }, el("summary", {}, "+ Nova conquista"), nId, nNome, nDesc, nMet, nMeta, nPer, nEp.no, criar), msg);
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

export async function abrirMestreRanking(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const [{ data, error }, cat] = await Promise.all([supabase.rpc("mestre_ranking_obter"), catalogo()]);
  if (error) return aviso(error.message, 4000, true);
  const d = data as DadosRanking;
  const msg = msgPainel();
  const duracao = el("input", { type: "number", min: "1", max: "120", class: "eg-in", value: String(d.duracao) });
  const aplicar = el("input", { type: "checkbox" });
  const minimo = el("input", { type: "number", min: "0", class: "eg-in", value: String(d.premios.minimo ?? 0) });
  const pts = Object.entries(d.pontos).map(([k, v]) => ({ k, i: el("input", { type: "number", min: "0", class: "eg-in", value: String(v) }) }));
  const tetos = Object.entries(d.tetos).map(([k, v]) => ({ k, i: el("input", { type: "number", min: "0", class: "eg-in", value: String(v) }) }));
  const podios = [0, 1, 2].map((i) => editorPremio(d.premios.podio?.[i], cat));
  const part = editorPremio(d.premios.participacao, cat);
  const rivais = d.rivais.map((r) => ({ r, f: el("input", { type: "number", step: "0.05", min: "0", max: "2", class: "eg-in", value: String(r.fator) }) }));
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
    const delta = el("input", { type: "number", class: "eg-in", placeholder: "±pontos" });
    return el("div", { class: "ev-item" }, el("span", {}, `${j.nome}: ${j.pontos}`), delta, botao("Ajustar", async () => {
      const { error: er } = await supabase.rpc("mestre_ranking_ajustar", { p_jogador: j.id, p_delta: Math.trunc(Number(delta.value) || 0), p_motivo: "ajuste do Mestre" });
      if (er) return mensagem(msg, er.message);
      void abrirMestreRanking(modal, aviso);
    }, "sec"));
  });
  const grupo = (t: string, itens: { k: string; i: HTMLInputElement }[]): HTMLElement => el("div", {}, el("strong", {}, t), ...itens.map((x) => el("label", {}, x.k, x.i)));
  modal.abrir("Mestre · Ranking",
    el("p", { class: "sub" }, `Período atual: ${d.periodo.inicio} → ${d.periodo.fim} (exclusivo).`),
    el("label", {}, "Duração (dias)", duracao), el("label", {}, aplicar, " aplicar a duração ao período atual"),
    grupo("Pontos por evento", pts), grupo("Teto diário por grupo (npc, selv)", tetos),
    el("label", {}, "Pontos mínimos para ganhar prêmio", minimo),
    el("strong", {}, "🥇 1º lugar"), podios[0].no, el("strong", {}, "🥈 2º lugar"), podios[1].no, el("strong", {}, "🥉 3º lugar"), podios[2].no, el("strong", {}, "Participação"), part.no,
    el("strong", {}, "Rivais NPC (fator × pontos do líder)"), ...rivais.map((x) => el("label", {}, x.r.nome, x.f)),
    salvar, fechar, el("h3", { class: "eg-cat" }, "Pontuação dos jogadores"), ...(lin.length ? lin : [el("p", { class: "sub" }, "Ninguém pontuou ainda.")]), msg);
}

// ---------- Mini-quests ----------
interface MqM { id: string; mapa_id: string; nome: string; dica: string; recompensa: Premio; ativa: boolean; sorteada: boolean }

export async function abrirMestreMiniquests(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const [{ data, error }, cat] = await Promise.all([supabase.rpc("mestre_miniquests_obter"), catalogo()]);
  if (error) return aviso(error.message, 4000, true);
  const d = data as { por_semana: number; lista: MqM[] };
  const msg = msgPainel();
  const porSemana = el("input", { type: "number", min: "0", max: "100", class: "eg-in", value: String(d.por_semana) });
  const cartoes = d.lista.map((q) => {
    const nome = el("input", { class: "eg-in", value: q.nome });
    const dica = el("input", { class: "eg-in", value: q.dica });
    const ativa = el("input", { type: "checkbox" });
    ativa.checked = q.ativa;
    const ep = editorPremio(q.recompensa, cat);
    const b = botao("Salvar", async () => {
      const { error: er } = await supabase.rpc("mestre_miniquests_salvar", { p: { lista: [{ id: q.id, nome: nome.value, dica: dica.value, ativa: ativa.checked, recompensa: ep.ler() }] } });
      mensagem(msg, er ? er.message : `Salvo: ${nome.value}`, er ? "erro" : "ok");
    });
    return el("details", { class: "eg-sem" }, el("summary", {}, `${q.sorteada ? "★ " : ""}${q.mapa_id} · ${q.nome}${q.ativa ? "" : " (off)"}`), nome, dica, el("label", {}, ativa, " ativa"), ep.no, b);
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
  modal.abrir("Mestre · Desafios da semana", el("p", { class: "sub" }, "★ = sorteado esta semana. Cada desafiante é um NPC escondido no mapa indicado."),
    el("label", {}, "Desafios sorteados por semana", porSemana), salvar, resortear, ...cartoes, msg);
}

// ---------- Módulos e ovos ----------
const MODULOS: [string, string][] = [["checkin", "Check-in diário"], ["conquistas", "Conquistas"], ["ranking", "Ranking e revanche de NPCs"], ["miniquests", "Desafios da semana"], ["casa", "Casa e ovos"], ["capitulos", "Capítulos (ainda sem efeito no jogo)"]];

export async function abrirMestreEngajamento(modal: Modal, _aviso: Aviso): Promise<void> {
  const { data } = await supabase.rpc("modulos_estado");
  const est = (data ?? {}) as Record<string, boolean>;
  const msg = msgPainel();
  const caixas = MODULOS.map(([k, rot]) => {
    const c = el("input", { type: "checkbox" });
    c.checked = k === "capitulos" ? est[k] === true : est[k] !== false;
    return { k, c, no: el("label", { class: "eg-mod" }, c, ` ${rot}`) };
  });
  const salvar = botao("Salvar módulos", async () => {
    const { error } = await supabase.rpc("mestre_modulos_salvar", { p: Object.fromEntries(caixas.map((x) => [x.k, x.c.checked])) });
    mensagem(msg, error ? error.message : "Módulos atualizados.", error ? "erro" : "ok");
  });
  const { data: js } = await supabase.from("jogadores").select("id, nome").is("conta", null).order("nome");
  const jog = el("select", { class: "eg-in" }, ...((js ?? []) as { id: string; nome: string }[]).map((j) => el("option", { value: j.id }, j.nome)));
  const esp = el("select", { class: "eg-in" }, ...todasEspecies().slice(0, 151).map((e) => el("option", { value: String(e.id) }, `#${e.id} ${e.nome}`)));
  const passos = el("input", { type: "number", min: "1", class: "eg-in", value: "1000" });
  const dar = botao("Dar ovo ao jogador", async () => {
    const { error } = await supabase.rpc("mestre_ovo_dar", { p_jogador: jog.value, p_especie: Number(esp.value), p_passos: num(passos.value) || 1000 });
    mensagem(msg, error ? error.message : "Ovo entregue.", error ? "erro" : "ok");
  }, "sec");
  modal.abrir("Mestre · Engajamento",
    el("p", { class: "sub" }, "Desligue um módulo para escondê-lo e pará-lo sem mexer em código. Capítulos vêm desligados."),
    ...caixas.map((x) => x.no), salvar,
    el("h3", { class: "eg-cat" }, "Presentear com um ovo"), jog, esp, el("label", {}, "Passos para chocar", passos), dar, msg);
}
