import { supabase } from "../supabase";
import { el, mensagem } from "./dom";
import { carregarReferencias, todasEspecies } from "./dados";
import { textoPremio, type Premio } from "./engajamento";
import { catalogo, editorPremio } from "./mestre_engaj";
import { desenharChave, NOME_RODADA, ROTULO_ESTADO, type LigaEstado } from "./liga";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

interface NpcEsp { id: string; nome: string; classe: string; aparencia: number; falas: { antes?: string; derrota?: string }; equipe: { especie: number; nivel: number }[] }
interface Obter {
  edicao: null | { id: string; nome: string; estado: string; tamanho: number; rodada: number; rodadas: number; inscricoes_ate: string | null; inicio_em: string | null; prazo_min: number; premios: Record<string, Premio>; especiais: string[] };
  inscritos: { id: string; nome: string; insignias: number; presente: boolean }[];
  chave: { participantes: LigaEstado["chave"] extends infer C ? (C extends { participantes: infer P } ? P : never) : never; partidas: NonNullable<LigaEstado["chave"]>["partidas"] };
  npcs: NpcEsp[];
  ultima: { nome: string; campeao: string | null; vice: string | null } | null;
}

const botao = (texto: string, fn: () => void, classe = ""): HTMLButtonElement => {
  const b = el("button", { type: "button", class: classe }, texto);
  b.addEventListener("click", fn);
  return b;
};
const campo = (rotulo: string, entrada: HTMLElement, dica?: string): HTMLElement =>
  el("label", { class: "eg-campo" }, el("span", { class: "eg-rot" }, rotulo), entrada, ...(dica ? [el("span", { class: "eg-dica" }, dica)] : []));
const entrada = (tipo: string, valor: string | number | undefined, extra: Record<string, string> = {}): HTMLInputElement =>
  el("input", { type: tipo, class: "eg-in", value: valor === undefined ? "" : String(valor), ...extra });

/** ISO (UTC) → valor de <input type="datetime-local"> no fuso do navegador. */
const paraLocal = (iso: string | null): string => {
  if (!iso) return "";
  const d = new Date(iso); const p = (n: number): string => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
};
const deLocal = (v: string): string | null => (v ? new Date(v).toISOString() : null);

export async function abrirMestreLiga(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const [{ data, error }, cat] = await Promise.all([supabase.rpc("mestre_liga_obter"), catalogo()]);
  if (error) return aviso(error.message, 4000, true);
  const d = data as Obter;
  const ed = d.edicao;
  const msg = el("p", { class: "msg", role: "status" });
  const recarregar = (): void => void abrirMestreLiga(modal, aviso);
  const corpo = el("div", { class: "eg lg" });
  const chamar = async (fn: string, args: Record<string, unknown> = {}, ok = ""): Promise<boolean> => {
    const { error: er } = await supabase.rpc(fn, args);
    if (er) { mensagem(msg, er.message); return false; }
    if (ok) aviso(ok, 3500);
    recarregar();
    return true;
  };

  corpo.append(el("div", { class: "eg-ajuda" }, el("strong", {}, "Como funciona a Liga"),
    el("p", {}, "1) Crie a edição e abra as inscrições (os jogadores recebem um aviso). 2) Os jogadores com 8 insígnias se inscrevem num Centro Pokémon. 3) Feche as inscrições e sorteie a chave: as vagas que sobram são preenchidas com NPCs especiais (os seus) e depois NPCs aleatórios. 4) No dia, inicie cada rodada; os jogadores lutam na arena (Platô Prisma). 5) A Liga termina sozinha na final e entrega prêmios e títulos."),
    el("p", {}, "Luta entre jogadores: duelo amistoso ao vivo (sem PA, HP/PP cheios). Contra NPC: luta normal sem XP nem dinheiro. NPC contra NPC é resolvido pelo servidor. Quem não aparecer no prazo perde por W.O.")));

  // ---------- NPCs especiais ----------
  const bNpcs = el("div", { class: "eg-bloco" }, el("strong", { class: "eg-bloco-tit" }, "NPCs especiais (times montados por você)"));
  const abrirNpc = (n: NpcEsp | null): void => {
    const nome = entrada("text", n?.nome ?? "", { maxlength: "30" });
    const classe = entrada("text", n?.classe ?? "Campeão", { maxlength: "30" });
    const aparencia = entrada("number", n?.aparencia ?? 12, { min: "0", max: "99" });
    const antes = entrada("text", n?.falas?.antes ?? "", { maxlength: "160" });
    const derrota = entrada("text", n?.falas?.derrota ?? "", { maxlength: "160" });
    const linhas = el("div", {});
    const lista = todasEspecies().filter((e) => e.id <= 151);
    const addLinha = (esp?: number, niv?: number): void => {
      const sel = el("select", { class: "eg-in" });
      for (const e of lista) sel.append(el("option", { value: String(e.id) }, `#${e.id} ${e.nome}`));
      if (esp) sel.value = String(esp);
      const nv = entrada("number", niv ?? 50, { min: "1", max: "1000" });
      const linha = el("div", { class: "eg-campos" }, sel, nv, botao("✕", () => linha.remove(), "sec"));
      linha.dataset.l = "1";
      linhas.append(linha);
    };
    (n?.equipe?.length ? n.equipe : [{ especie: 1, nivel: 50 }]).forEach((x) => addLinha(x.especie, x.nivel));
    const m2 = el("p", { class: "msg", role: "status" });
    const salvar = botao("Salvar NPC", async () => {
      const equipe = [...linhas.querySelectorAll("[data-l]")].map((l) => ({ especie: Number((l.querySelector("select") as HTMLSelectElement).value), nivel: Number((l.querySelector("input") as HTMLInputElement).value) }));
      const { error: er } = await supabase.rpc("mestre_liga_npc_salvar", { p: { id: n?.id ?? null, nome: nome.value, classe: classe.value, aparencia: Number(aparencia.value), falas: { antes: antes.value, derrota: derrota.value }, equipe } });
      if (er) return mensagem(m2, er.message);
      recarregar();
    });
    modal.abrir(n ? `NPC: ${n.nome}` : "Novo NPC especial", el("div", { class: "eg" },
      campo("Nome", nome), campo("Classe (ex.: Campeão, Elite)", classe), campo("Aparência (número do sprite)", aparencia),
      campo("Fala antes da luta", antes), campo("Fala ao perder", derrota),
      el("h3", { class: "eg-cat" }, "Time (até 6 Pokémon da Geração 1)"), linhas,
      botao("+ Pokémon", () => { if (linhas.children.length < 6) addLinha(); }, "sec"), m2, salvar,
      botao("← Voltar à Liga", recarregar, "sec")));
  };
  for (const n of d.npcs) {
    bNpcs.append(el("div", { class: "eg-linha" }, el("span", {}, `${n.nome} — ${n.classe} (${n.equipe.map((e) => `#${e.especie} nv${e.nivel}`).join(", ")})`),
      botao("Editar", () => abrirNpc(n), "sec"),
      botao("Remover", async () => { if (window.confirm(`Remover "${n.nome}"?`)) await chamar("mestre_liga_npc_remover", { p_id: n.id }); }, "sec")));
  }
  bNpcs.append(botao("+ Novo NPC especial", () => abrirNpc(null), "sec"));

  // ---------- configuração da edição ----------
  const premioSeq: [string, string][] = [["campeao", "🥇 Campeão"], ["vice", "🥈 Vice-campeão"], ["semi", "🥉 Semifinalistas (cada)"], ["participacao", "Participação (quem não ficou no pódio)"]];
  const eds = Object.fromEntries(premioSeq.map(([k]) => [k, editorPremio(ed?.premios?.[k] ?? (k === "campeao" ? { dinheiro: 10000, titulo: "campeao_liga" } : k === "vice" ? { dinheiro: 4000, titulo: "vice_liga" } : k === "semi" ? { dinheiro: 1500 } : {}), cat)]));
  const nome = entrada("text", ed?.nome ?? "Liga Pokémon", { maxlength: "40" });
  const tam = el("select", { class: "eg-in" });
  for (const t of [8, 16, 32, 64]) tam.append(el("option", { value: String(t) }, `${t} participantes`));
  tam.value = String(ed?.tamanho ?? 32);
  const ate = entrada("datetime-local", paraLocal(ed?.inscricoes_ate ?? null));
  const ini = entrada("datetime-local", paraLocal(ed?.inicio_em ?? null));
  const prazo = entrada("number", ed?.prazo_min ?? 10, { min: "1", max: "120" });
  const sel = new Set(ed?.especiais ?? []);
  const espBox = el("div", { class: "eg-campos" });
  for (const n of d.npcs) {
    const c = el("input", { type: "checkbox" }) as HTMLInputElement; c.checked = sel.has(n.id);
    c.addEventListener("change", () => { if (c.checked) sel.add(n.id); else sel.delete(n.id); });
    espBox.append(el("label", { class: "eg-mod" }, c, ` ${n.nome}`));
  }
  if (!d.npcs.length) espBox.append(el("p", { class: "sub" }, "Crie NPCs especiais abaixo para escolhê-los aqui."));
  const payload = (): Record<string, unknown> => ({
    nome: nome.value, tamanho: Number(tam.value), inscricoes_ate: deLocal(ate.value) ?? "", inicio_em: deLocal(ini.value) ?? "", prazo_min: Number(prazo.value),
    especiais: [...sel], premios: Object.fromEntries(premioSeq.map(([k]) => [k, eds[k].ler()])),
  });
  const cfg = el("div", { class: "eg-bloco" }, el("strong", { class: "eg-bloco-tit" }, ed ? "Configuração da edição" : "Criar a Liga"),
    campo("Nome da edição", nome), campo("Tamanho da chave", tam, "Jogadores + NPCs especiais + NPCs aleatórios = este número."),
    campo("Inscrições até (opcional)", ate), campo("Dia e hora do início (aviso para os jogadores)", ini),
    campo("Prazo por rodada (minutos)", prazo, "Quem não se apresentar a tempo perde por W.O."),
    el("h3", { class: "eg-cat" }, "NPCs especiais nesta edição"), espBox,
    el("h3", { class: "eg-cat" }, "Prêmios (dinheiro, XP, itens, título na ficha…)"),
    ...premioSeq.flatMap(([k, rot]) => [el("strong", {}, rot), eds[k].no]));

  if (!ed) {
    cfg.append(botao("Criar Liga e abrir inscrições", async () => { await chamar("mestre_liga_criar", { p: payload() }, "Liga criada. Inscrições abertas!"); }));
    corpo.append(cfg);
    if (d.ultima) corpo.append(el("p", { class: "sub" }, `Última edição: ${d.ultima.nome} — campeão ${d.ultima.campeao ?? "—"}, vice ${d.ultima.vice ?? "—"}.`));
    corpo.append(bNpcs, msg);
    return modal.abrir("🏆 Liga Pokémon (Mestre)", corpo);
  }

  corpo.append(el("p", {}, `${ed.nome} — ${ROTULO_ESTADO[ed.estado] ?? ed.estado}${ed.estado === "andamento" ? ` · ${NOME_RODADA(ed.rodada, ed.rodadas)}` : ""}`));
  const acoes = el("div", { class: "eg-rodape-bt" });
  if (ed.estado === "inscricoes") acoes.append(botao("Encerrar inscrições", () => void chamar("mestre_liga_inscricoes", { p_abrir: false }), "sec"));
  if (ed.estado === "fechada") acoes.append(botao("Reabrir inscrições", () => void chamar("mestre_liga_inscricoes", { p_abrir: true }), "sec"));
  if (ed.estado === "inscricoes" || ed.estado === "fechada" || ed.estado === "sorteada")
    acoes.append(botao(ed.estado === "sorteada" ? "Sortear de novo" : "Sortear a chave", async () => {
      const { data: r, error: er } = await supabase.rpc("mestre_liga_sortear");
      if (er) return mensagem(msg, er.message);
      const x = r as { jogadores: number; especiais: number; aleatorios: number };
      aviso(`Chave sorteada: ${x.jogadores} jogador(es), ${x.especiais} NPC(s) especial(is), ${x.aleatorios} aleatório(s).`, 5000);
      recarregar();
    }));
  if (ed.estado === "sorteada" || ed.estado === "andamento") {
    const feitas = ed.estado === "andamento" && !d.chave.partidas.some((p) => p.rodada === ed.rodada && p.estado !== "encerrada");
    if (ed.estado === "sorteada" || (feitas && ed.rodada < ed.rodadas))
      acoes.append(botao(`▶ Iniciar ${NOME_RODADA(ed.rodada + 1, ed.rodadas)}`, () => void chamar("mestre_liga_iniciar_rodada", {}, "Rodada iniciada!")));
  }
  acoes.append(botao("Cancelar a Liga", async () => { if (window.confirm("Cancelar esta Liga? Nada é premiado.")) await chamar("mestre_liga_cancelar", {}, "Liga cancelada."); }, "sec"));
  corpo.append(acoes);

  if (ed.estado === "inscricoes" || ed.estado === "fechada") {
    const lista = el("div", { class: "eg-bloco" }, el("strong", { class: "eg-bloco-tit" }, `Inscritos (${d.inscritos.length})`));
    for (const i of d.inscritos) lista.append(el("div", { class: "eg-linha" }, el("span", {}, `${i.nome} — ${i.insignias} insígnias`), botao("Remover", () => void chamar("mestre_liga_remover_inscrito", { p_jogador: i.id }), "sec")));
    if (!d.inscritos.length) lista.append(el("p", { class: "sub" }, "Ninguém inscrito ainda."));
    corpo.append(lista);
  }

  if (d.chave.partidas.length) {
    const fake = { ativa: true, na_arena: false, resultados: [], edicao: { ...ed, campeao_nome: null, vice_nome: null, especiais_n: 0 }, chave: d.chave } as unknown as LigaEstado;
    const chave = el("div", { class: "eg-bloco" }, el("strong", { class: "eg-bloco-tit" }, "Chaveamento"), desenharChave(fake));
    const nomes = new Map(d.chave.participantes.map((p) => [p.id, p]));
    const abertas = d.chave.partidas.filter((p) => p.estado === "em_curso");
    if (abertas.length) {
      chave.append(el("h3", { class: "eg-cat" }, "Partidas em curso (decidir à mão, se necessário)"));
      for (const p of abertas) {
        const a = p.a ? nomes.get(p.a) : null, b = p.b ? nomes.get(p.b) : null;
        chave.append(el("div", { class: "eg-linha" }, el("span", {}, `${a?.nome ?? "?"} × ${b?.nome ?? "?"}  ${a?.presente === false ? "(" + a.nome + " fora da arena)" : ""}`),
          botao(`${a?.nome ?? "A"} vence`, () => void chamar("mestre_liga_vencedor", { p_partida: p.id, p_participante: p.a }), "sec"),
          botao(`${b?.nome ?? "B"} vence`, () => void chamar("mestre_liga_vencedor", { p_partida: p.id, p_participante: p.b }), "sec")));
      }
    }
    corpo.append(chave);
  }

  const salvarCfg = botao("Salvar configuração", async () => {
    const { error: er } = await supabase.rpc("mestre_liga_atualizar", { p: payload() });
    if (er) return mensagem(msg, er.message);
    mensagem(msg, `Configuração salva. Prêmio do campeão: ${textoPremio(eds.campeao.ler())}.`, "ok");
  });
  cfg.append(salvarCfg);
  corpo.append(cfg, bNpcs, msg);
  modal.abrir("🏆 Liga Pokémon (Mestre)", corpo);
}
