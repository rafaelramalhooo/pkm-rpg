import { supabase } from "../supabase";
import { el, mensagem } from "./dom";
import { textoPremio, type Premio } from "./engajamento";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

export interface LigaPart { id: string; pos: number; tipo: string; nome: string; classe: string | null; aparencia: number | null; eliminado: boolean; eu: boolean; presente: boolean | null }
export interface LigaPartida { id: string; rodada: number; slot: number; a: string | null; b: string | null; vencedor: string | null; estado: string; motivo: string | null; prazo: string | null; pa: boolean; pb: boolean }
export interface LigaEstado {
  ativa: boolean; agora?: string; na_arena: boolean; inscrito?: boolean; participa?: boolean; eliminado?: boolean;
  resultados: { id: number; colocacao: string; premio: Premio }[];
  minha?: { partida: string; rodada: number; oponente: string; oponente_tipo: string; prazo: string | null; eu_pronto: boolean; op_pronto: boolean; em_batalha: boolean } | null;
  inscritos?: string[];
  edicao: null | {
    id: string; nome: string; estado: string; tamanho: number; rodadas: number; rodada: number; inscricoes_ate: string | null; inicio_em: string | null; prazo_min: number;
    premios: Record<string, Premio>; campeao_nome: string | null; vice_nome: string | null; especiais_n: number;
  };
  chave?: { participantes: LigaPart[]; partidas: LigaPartida[] };
}

const botao = (texto: string, fn: () => void, classe = ""): HTMLButtonElement => {
  const b = el("button", { type: "button", class: classe }, texto);
  b.addEventListener("click", fn);
  return b;
};

export const NOME_RODADA = (r: number, total: number): string => {
  const falta = total - r;
  return falta === 0 ? "Final" : falta === 1 ? "Semifinal" : falta === 2 ? "Quartas de final" : falta === 3 ? "Oitavas de final" : falta === 4 ? "16 avos de final" : "32 avos de final";
};

export const ROTULO_ESTADO: Record<string, string> = {
  inscricoes: "Inscrições abertas", fechada: "Inscrições encerradas", sorteada: "Chave sorteada — aguardando o início", andamento: "Em andamento", finalizada: "Encerrada", cancelada: "Cancelada",
};

export async function carregarLiga(): Promise<LigaEstado | null> {
  const { data, error } = await supabase.rpc("liga_estado");
  if (error || !data) return null;
  return data as LigaEstado;
}

const fmt = (iso: string | null): string => (iso ? new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "—");

/** Chaveamento em colunas por rodada. */
export function desenharChave(est: LigaEstado): HTMLElement {
  const ed = est.edicao;
  const caixa = el("div", { class: "lg-chave" });
  if (!ed || !est.chave || !est.chave.partidas.length) return caixa;
  const nomes = new Map(est.chave.participantes.map((p) => [p.id, p]));
  for (let r = 1; r <= ed.rodadas; r++) {
    const col = el("div", { class: "lg-col" }, el("h4", {}, NOME_RODADA(r, ed.rodadas)));
    for (const m of est.chave.partidas.filter((x) => x.rodada === r)) {
      const lado = (id: string | null): HTMLElement => {
        const p = id ? nomes.get(id) : null;
        const cls = ["lg-lado"];
        if (p?.eu) cls.push("eu");
        if (m.vencedor && id === m.vencedor) cls.push("venc");
        if (m.vencedor && id && id !== m.vencedor) cls.push("perd");
        const rot = p ? `${p.nome}${p.tipo === "jogador" ? " 👤" : ""}` : "a definir";
        return el("div", { class: cls.join(" ") }, rot);
      };
      const status = m.estado === "em_curso" ? "⚔️ lutando" : m.estado === "encerrada" ? (m.motivo === "wo" ? "W.O." : "") : "";
      col.append(el("div", { class: "lg-jogo" }, lado(m.a), lado(m.b), ...(status ? [el("small", {}, status)] : [])));
    }
    caixa.append(col);
  }
  return caixa;
}

function listaPremios(premios: Record<string, Premio>): HTMLElement {
  const linhas: [string, string][] = [["🥇 Campeão", "campeao"], ["🥈 Vice", "vice"], ["🥉 Semifinalistas", "semi"], ["Participação", "participacao"]];
  const ul = el("ul", { class: "lg-premios" });
  for (const [rot, k] of linhas) {
    const t = textoPremio(premios[k]);
    if (t && t !== "—") ul.append(el("li", {}, `${rot}: ${t}`));
  }
  return ul;
}

/** Janela principal da Liga (chave, minha partida, inscritos). */
export async function abrirLiga(modal: Modal, aviso: Aviso, entrarLuta: () => void, aposMudar: () => void): Promise<void> {
  const est0 = await carregarLiga();
  if (!est0) return aviso("Não consegui abrir a Liga agora.", 4000, true);
  const est: LigaEstado = est0;
  const ed = est.edicao;
  const msg = el("p", { class: "msg", role: "status" });
  const corpo = el("div", { class: "lg" });
  if (!ed) {
    corpo.append(el("p", { class: "sub" }, "Não há Liga Pokémon marcada. Fique de olho nos comunicados do Mestre."));
    return modal.abrir("🏆 Liga Pokémon", corpo);
  }
  corpo.append(el("h2", {}, ed.nome), el("p", { class: "sub" }, ROTULO_ESTADO[ed.estado] ?? ed.estado));
  if (ed.inicio_em) corpo.append(el("p", { class: "sub" }, `Início previsto: ${fmt(ed.inicio_em)}`));
  if (ed.estado === "inscricoes") {
    if (ed.inscricoes_ate) corpo.append(el("p", { class: "sub" }, `Inscrições até ${fmt(ed.inscricoes_ate)} — no balcão de um Centro Pokémon, com as 8 insígnias.`));
    corpo.append(el("p", { class: "sub" }, `Vagas: ${ed.tamanho} (jogadores + NPCs). Inscritos: ${est.inscritos?.length ?? 0}.`));
  }
  if (est.minha && ed.estado === "andamento") {
    const m = est.minha;
    const caixa = el("div", { class: "lg-minha" }, el("strong", {}, `Sua partida — ${NOME_RODADA(m.rodada, ed.rodadas)}`), el("p", {}, `Adversário: ${m.oponente}${m.oponente_tipo === "jogador" ? " (jogador)" : ""}`));
    if (m.prazo) caixa.append(el("p", { class: "sub" }, `Apresente-se até ${fmt(m.prazo)}; quem não aparecer perde por W.O.`));
    if (!est.na_arena) caixa.append(el("p", { class: "msg erro" }, "Vá até a arena da Liga (Platô Prisma) para lutar."));
    else {
      const rot = m.em_batalha ? "Voltar à luta" : m.eu_pronto && m.oponente_tipo === "jogador" ? "Aguardando o adversário…" : "Estou pronto — lutar!";
      const bt = botao(rot, async () => {
        bt.disabled = true;
        const { data, error } = await supabase.rpc("liga_pronto");
        if (error) { bt.disabled = false; return mensagem(msg, error.message); }
        const r = data as { batalha?: boolean; espera?: boolean };
        if (r.batalha) { modal.fechar(); aposMudar(); entrarLuta(); } else { mensagem(msg, "Pronto! Assim que o adversário também confirmar, a luta começa.", "ok"); bt.textContent = "Aguardando o adversário…"; }
      });
      if (m.eu_pronto && !m.em_batalha && m.oponente_tipo === "jogador") bt.disabled = false;
      caixa.append(bt);
    }
    corpo.append(caixa);
  } else if (est.participa && est.eliminado && ed.estado === "andamento") corpo.append(el("p", { class: "sub" }, "Você foi eliminado. Acompanhe o resto do torneio pela chave!"));
  else if (est.inscrito && ed.estado !== "andamento" && ed.estado !== "finalizada") corpo.append(el("p", { class: "msg ok" }, "✅ Você está inscrito."));
  if (ed.estado === "finalizada") corpo.append(el("p", {}, `🏆 Campeão: ${ed.campeao_nome ?? "—"} · Vice: ${ed.vice_nome ?? "—"}`));
  corpo.append(el("h3", {}, "Prêmios"), listaPremios(ed.premios));
  if (est.chave && est.chave.partidas.length) corpo.append(el("h3", {}, "Chaveamento"), desenharChave(est));
  else if (est.inscritos?.length) corpo.append(el("h3", {}, "Inscritos"), el("p", { class: "sub" }, est.inscritos.join(", ")));
  corpo.append(msg);
  modal.abrir("🏆 Liga Pokémon", corpo);
  // atualiza sozinha enquanto a janela estiver aberta
  const t = window.setInterval(() => { if (!corpo.isConnected) return void window.clearInterval(t); void atualizarSilencioso(); }, 5000);
  let travado = false;
  async function atualizarSilencioso(): Promise<void> {
    if (travado) return;
    const e2 = await carregarLiga();
    if (!e2 || !corpo.isConnected) return;
    if (e2.minha?.em_batalha && e2.na_arena) { travado = true; window.clearInterval(t); modal.fechar(); aposMudar(); entrarLuta(); return; }
    const mudou = JSON.stringify([e2.edicao?.estado, e2.edicao?.rodada, e2.minha, e2.chave?.partidas.map((p) => p.vencedor)]) !== JSON.stringify([ed!.estado, ed!.rodada, est.minha, est.chave?.partidas.map((p) => p.vencedor)]);
    if (mudou) { window.clearInterval(t); void abrirLiga(modal, aviso, entrarLuta, aposMudar); }
  }
}

/** Balcão de inscrição no Centro Pokémon. */
export async function abrirInscricaoLiga(modal: Modal, aviso: Aviso, aposMudar: () => void): Promise<void> {
  const est = await carregarLiga();
  const ed = est?.edicao;
  const msg = el("p", { class: "msg", role: "status" });
  const corpo = el("div", { class: "lg" });
  if (!est || !ed || !est.ativa) {
    corpo.append(el("p", { class: "sub" }, "Atendente: \"No momento não há inscrições para a Liga Pokémon. Fique atento aos comunicados!\""));
    return modal.abrir("🏆 Inscrição na Liga", corpo);
  }
  corpo.append(el("h2", {}, ed.nome), el("p", { class: "sub" }, ROTULO_ESTADO[ed.estado] ?? ed.estado));
  if (ed.inscricoes_ate) corpo.append(el("p", { class: "sub" }, `Inscrições até ${fmt(ed.inscricoes_ate)}.`));
  if (ed.inicio_em) corpo.append(el("p", { class: "sub" }, `Início previsto: ${fmt(ed.inicio_em)} — vá até a arena (Platô Prisma) nesse dia.`));
  corpo.append(el("p", {}, "Requisitos: as 8 insígnias e pelo menos um Pokémon no time. Sem custo, sem gastar PA. Os confrontos usam as regras normais; seus Pokémon são curados entre as rodadas."));
  corpo.append(el("h3", {}, "Prêmios"), listaPremios(ed.premios));
  if (est.inscrito) {
    corpo.append(el("p", { class: "msg ok" }, "✅ Você está inscrito."));
    if (ed.estado === "inscricoes" || ed.estado === "fechada") corpo.append(botao("Cancelar minha inscrição", async () => {
      const { error } = await supabase.rpc("liga_desinscrever");
      if (error) return mensagem(msg, error.message);
      aposMudar(); void abrirInscricaoLiga(modal, aviso, aposMudar);
    }, "sec"));
  } else if (ed.estado === "inscricoes") {
    corpo.append(botao("Inscrever-me na Liga", async () => {
      const { error } = await supabase.rpc("liga_inscrever");
      if (error) return mensagem(msg, error.message);
      aposMudar(); void abrirInscricaoLiga(modal, aviso, aposMudar);
    }));
  }
  corpo.append(el("p", { class: "sub" }, `Inscritos até agora: ${est.inscritos?.length ?? 0}`), msg);
  modal.abrir("🏆 Inscrição na Liga", corpo);
}

// ---------- avisos automáticos ----------
let ultimo = "";
/** Compara com a última leitura e avisa (toasts). Devolve o estado atual para o chamador decidir se entra na luta. */
export async function verificarLiga(aviso: Aviso, aposMudar: () => void): Promise<LigaEstado | null> {
  const est = await carregarLiga();
  if (!est) return null;
  const ed = est.edicao;
  if (est.resultados.length) {
    for (const r of est.resultados) {
      const t = textoPremio(r.premio);
      aviso(`🏆 Liga Pokémon: você ficou como ${r.colocacao}!${t && t !== "—" ? ` Prêmio: ${t}.` : ""}`, 9000);
    }
    void supabase.rpc("liga_resultados_vistos");
    aposMudar();
  }
  if (est.ativa && ed) {
    const chave = `${ed.id}|${ed.estado}|${ed.rodada}|${est.minha?.partida ?? ""}`;
    if (chave !== ultimo) {
      if (ultimo) {
        if (ed.estado === "inscricoes" && !ultimo.includes("|inscricoes|")) aviso(`📣 ${ed.nome}: inscrições abertas! Procure um Centro Pokémon com as 8 insígnias.`, 9000);
        else if (ed.estado === "andamento" && est.minha) aviso(`⚔️ Liga: sua partida (${NOME_RODADA(est.minha.rodada, ed.rodadas)}) contra ${est.minha.oponente} está pronta! Vá à arena.`, 10000);
        else if (ed.estado === "sorteada" && est.participa) aviso("🏆 A chave da Liga foi sorteada! Veja seus confrontos em Menu › Liga Pokémon.", 8000);
      } else if (ed.estado === "inscricoes") aviso(`📣 ${ed.nome}: inscrições abertas! Procure um Centro Pokémon com as 8 insígnias.`, 9000);
      ultimo = chave;
    }
  }
  return est;
}
