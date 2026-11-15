import { supabase } from "../supabase";
import { el, mensagem } from "./dom";
import { carregarReferencias, nomeItem, especie } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

export interface Premio {
  dinheiro?: number; xp_treinador?: number; pa?: number;
  itens?: { item: string; qtd: number }[];
  titulo?: string; moldura?: string; ovo?: { especie: number; passos: number };
}

const botao = (texto: string, fn: () => void, classe = ""): HTMLButtonElement => {
  const b = el("button", { type: "button", class: classe }, texto);
  b.addEventListener("click", fn);
  return b;
};

/** "₽ 500 · 40 XP · 2× Poção" */
export function textoPremio(p: Premio | null | undefined): string {
  if (!p) return "—";
  const partes: string[] = [];
  if (p.dinheiro) partes.push(`₽ ${p.dinheiro}`);
  if (p.xp_treinador) partes.push(`${p.xp_treinador} XP de treinador`);
  if (p.pa) partes.push(`${p.pa} PA`);
  for (const i of p.itens ?? []) partes.push(`${i.qtd}× ${nomeItem(i.item)}`);
  if (p.titulo) partes.push(`título "${p.titulo.replace(/_/g, " ")}"`);
  if (p.moldura) partes.push(`moldura ${p.moldura.replace(/_/g, " ")}`);
  if (p.ovo) partes.push(`🥚 ovo de ${especie(p.ovo.especie)?.nome ?? "?"}`);
  return partes.length ? partes.join(" · ") : "—";
}

const barra = (atual: number, meta: number): HTMLElement => {
  const f = el("div", { class: "eg-barra-fill" });
  f.style.width = `${Math.min(100, Math.round((atual / Math.max(meta, 1)) * 100))}%`;
  return el("div", { class: "eg-barra" }, f);
};

const msgPainel = (): HTMLElement => el("p", { class: "msg", role: "status" });

// ---------- Check-in diário ----------
interface EstadoCheckin {
  ativo: boolean; estado?: string; ja_fez_hoje?: boolean; semana?: number; dia?: number; feitos?: number; meta?: number;
  dias?: { dia: number; recompensa: Premio; rotulo?: string | null; feito: boolean }[];
  premio_semana?: { tema: string | null; recompensa: Premio } | null; semana_resgatada?: boolean; proxima_virada?: string; inicio?: string;
}

export async function checkinPendente(): Promise<boolean> {
  const { data } = await supabase.rpc("checkin_estado");
  const e = data as EstadoCheckin | null;
  return !!e && e.ativo && e.estado === "ok" && !e.ja_fez_hoje;
}

export async function abrirCheckin(modal: Modal, aviso: Aviso, aposMudar: () => void): Promise<void> {
  await carregarReferencias();
  const { data, error } = await supabase.rpc("checkin_estado");
  if (error) return aviso(error.message, 4000, true);
  const e = data as EstadoCheckin;
  const msg = msgPainel();
  if (!e.ativo) return modal.abrir("Check-in diário", el("p", { class: "sub" }, "O check-in diário não está ativo no momento."));
  if (e.estado === "aguardando") return modal.abrir("Check-in diário", el("p", { class: "sub" }, `O calendário começa em ${new Date(`${e.inicio}T12:00:00`).toLocaleDateString("pt-BR")}.`));
  if (e.estado === "encerrado") return modal.abrir("Check-in diário", el("p", { class: "sub" }, "O calendário terminou. Aguarde o próximo!"));
  const virada = e.proxima_virada ? new Date(e.proxima_virada).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) : "6h";
  const grade = el("div", { class: "eg-grade" }, ...(e.dias ?? []).map((d) => {
    const hoje = d.dia === e.dia;
    return el("div", { class: `eg-dia${d.feito ? " feito" : ""}${hoje ? " hoje" : ""}` },
      el("strong", {}, `Dia ${d.dia}`), el("small", {}, d.feito ? "✔ recebido" : textoPremio(d.recompensa)));
  }));
  const btn = botao(e.ja_fez_hoje ? `Check-in feito hoje (próximo às ${virada})` : "Fazer check-in de hoje", async () => {
    btn.disabled = true;
    const { data: r, error: er } = await supabase.rpc("fazer_checkin");
    if (er) { btn.disabled = false; return mensagem(msg, er.message); }
    const res = r as { entregue: Premio; premio_semana: Premio | null; feitos: number; meta: number };
    aposMudar();
    aviso(`Check-in feito! Você ganhou: ${textoPremio(res.entregue)}${res.premio_semana ? ` · Prêmio da semana: ${textoPremio(res.premio_semana)}` : ""}`, 9000);
    void abrirCheckin(modal, aviso, aposMudar);
  }, "");
  btn.disabled = !!e.ja_fez_hoje;
  const premioSem = e.premio_semana;
  modal.abrir(`Check-in diário · Semana ${e.semana}`,
    el("p", { class: "sub" }, "Faça o check-in no balcão de qualquer Centro Pokémon. O dia vira às 6h (horário de Brasília)."),
    grade,
    el("p", { class: "sub" }, `Meta da semana: ${e.feitos}/${e.meta} dias${premioSem ? ` · ${premioSem.tema ?? "Prêmio da semana"}: ${textoPremio(premioSem.recompensa)}${e.semana_resgatada ? " (já recebido)" : ""}` : ""}`),
    barra(e.feitos ?? 0, e.meta ?? 5), btn, msg);
}

// ---------- Conquistas ----------
interface Conquista { id: string; categoria: string; nome: string; descricao: string; meta: number; periodo: string; recompensa: Premio; progresso: number; concluida: boolean; vezes: number }

export async function abrirConquistas(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const { data, error } = await supabase.rpc("conquistas_listar");
  if (error) return aviso(error.message, 4000, true);
  const lista = (data ?? []) as Conquista[];
  if (!lista.length) return modal.abrir("Conquistas", el("p", { class: "sub" }, "As conquistas não estão ativas no momento."));
  const cats = [...new Set(lista.map((c) => c.categoria))];
  const ROT: Record<string, string> = { total: "", dia: " · diária", semana: " · semanal" };
  modal.abrir(`Conquistas · ${lista.filter((c) => c.concluida).length}/${lista.length}`,
    ...cats.flatMap((cat) => [el("h3", { class: "eg-cat" }, cat), ...lista.filter((c) => c.categoria === cat).map((c) =>
      el("div", { class: `eg-conq${c.concluida ? " feita" : ""}` },
        el("div", { class: "eg-conq-topo" }, el("strong", {}, `${c.concluida ? "🏆 " : ""}${c.nome}`), el("small", {}, `${Math.min(c.progresso, c.meta)}/${c.meta}${ROT[c.periodo] ?? ""}`)),
        el("small", {}, c.descricao), barra(c.progresso, c.meta), el("small", { class: "sub" }, `Prêmio: ${textoPremio(c.recompensa)}`)))]));
}

// ---------- Ranking ----------
interface Linha { nome: string; pontos: number; npc: boolean; eu: boolean; titulo?: string | null; moldura?: { cor?: string } | null }

export async function abrirRanking(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const { data, error } = await supabase.rpc("ranking_tabela");
  if (error) return aviso(error.message, 4000, true);
  const r = data as { ativo: boolean; periodo?: { fim: string; dias_restantes: number }; meus_pontos?: number; linhas?: Linha[]; premios?: { minimo?: number; podio?: Premio[]; participacao?: Premio } };
  if (!r.ativo) return modal.abrir("Ranking", el("p", { class: "sub" }, "O ranking não está ativo no momento."));
  const linhas = r.linhas ?? [];
  const tabela = el("div", { class: "eg-rank" }, ...linhas.slice(0, 30).map((l, i) => {
    const nome = el("span", { class: "eg-rank-nome", ...(l.moldura?.cor ? { style: `border-color:${l.moldura.cor}` } : {}) }, `${l.npc ? "🤖 " : ""}${l.nome}`);
    return el("div", { class: `eg-rank-linha${l.eu ? " eu" : ""}${l.npc ? " npc" : ""}${i < 3 ? ` top top${i + 1}` : ""}` },
      el("span", { class: "eg-rank-pos" }, i < 3 ? `${["🥇", "🥈", "🥉"][i]} ${i + 1}º` : `${i + 1}º`), nome, l.titulo ? el("small", {}, l.titulo) : el("small", {}), el("strong", {}, `${l.pontos}`));
  }));
  const pr = r.premios ?? {};
  modal.abrir("Ranking de Treinadores",
    el("p", { class: "sub" }, `Termina em ${r.periodo?.dias_restantes ?? 0} dia(s). Seus pontos: ${r.meus_pontos ?? 0}. Treinadores NPC também disputam: só os jogadores levam prêmio.`),
    el("p", { class: "sub" }, `Prêmios (mínimo de ${pr.minimo ?? 0} pontos): 🥇 ${textoPremio(pr.podio?.[0])} · 🥈 ${textoPremio(pr.podio?.[1])} · 🥉 ${textoPremio(pr.podio?.[2])} · participação: ${textoPremio(pr.participacao)}`),
    linhas.length ? tabela : el("p", { class: "sub" }, "Ninguém pontuou ainda. Vença batalhas para abrir o placar!"),
    el("p", { class: "sub" }, "Pontos vêm de batalhas (selvagens e treinadores com limite diário) e de duelos entre jogadores. Treinadores NPC aceitam uma revanche por dia, valendo só pontos."));
}

// ---------- Mini-quests ----------
export async function abrirMiniquests(modal: Modal, aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const { data, error } = await supabase.rpc("miniquests_listar");
  if (error) return aviso(error.message, 4000, true);
  const r = data as { ativo: boolean; lista?: { id: string; mapa: string; nome: string; dica: string; recompensa: Premio; feita: boolean }[] };
  if (!r.ativo) return modal.abrir("Desafios da semana", el("p", { class: "sub" }, "Os desafios não estão ativos no momento."));
  const lista = r.lista ?? [];
  modal.abrir(`Desafios da semana · ${lista.filter((q) => q.feita).length}/${lista.length}`,
    el("p", { class: "sub" }, "Treinadores desafiantes aparecem escondidos pelos mapas e trocam toda segunda-feira. Cada um é bem mais forte que um treinador comum."),
    ...lista.map((q) => el("div", { class: `eg-conq${q.feita ? " feita" : ""}` },
      el("div", { class: "eg-conq-topo" }, el("strong", {}, `${q.feita ? "✔ " : "⚔ "}${q.nome}`), el("small", {}, q.mapa)),
      el("small", {}, q.dica), el("small", { class: "sub" }, `Prêmio: ${textoPremio(q.recompensa)}`))));
}

/** Mapa → quantos desafios abertos há por mapa (para o Mapa Mundi). */
export async function desafiosPorMapa(): Promise<Map<string, number>> {
  const { data } = await supabase.rpc("miniquests_listar");
  const r = data as { ativo: boolean; lista?: { mapa_id: string; feita: boolean }[] } | null;
  const m = new Map<string, number>();
  for (const q of r?.lista ?? []) if (!q.feita) m.set(q.mapa_id, (m.get(q.mapa_id) ?? 0) + 1);
  return m;
}

// ---------- Casa e ovos ----------
interface EstadoCasa {
  ativo: boolean; nivel?: number; nome?: string; incubadoras?: number; aqui?: boolean; dinheiro?: number; passos_hoje?: number; passos_max_dia?: number;
  proximo?: { nivel: number; nome: string; custo: number; incubadoras: number; descricao: string } | null;
  ovos?: { id: string; passos: number; passos_total: number; incubando: boolean; pronto: boolean; origem?: string }[];
}

export async function abrirCasa(modal: Modal, aviso: Aviso, aposMudar: () => void): Promise<void> {
  const { data, error } = await supabase.rpc("casa_estado");
  if (error) return aviso(error.message, 4000, true);
  const c = data as EstadoCasa;
  if (!c.ativo) return modal.abrir("Minha casa", el("p", { class: "sub" }, "A casa não está ativa no momento."));
  const msg = msgPainel();
  const recarregar = (): void => void abrirCasa(modal, aviso, aposMudar);
  const ovos = (c.ovos ?? []).map((o) => {
    const acoes: HTMLElement[] = [];
    if (o.pronto) acoes.push(botao("Chocar!", async () => {
      const { data: r, error: er } = await supabase.rpc("ovo_chocar", { p_ovo: o.id });
      if (er) return mensagem(msg, er.message);
      const x = r as { nome: string; time: boolean };
      aviso(`🐣 Nasceu um ${x.nome}! ${x.time ? "Ele entrou no seu time." : "Ele foi para as caixas."}`, 8000);
      aposMudar();
      recarregar();
    }));
    else acoes.push(botao(o.incubando ? "Tirar da incubadora" : "Colocar na incubadora", async () => {
      const { error: er } = await supabase.rpc("ovo_incubar", { p_ovo: o.id, p_ligar: !o.incubando });
      if (er) return mensagem(msg, er.message);
      recarregar();
    }, "sec"));
    return el("div", { class: "eg-conq" }, el("div", { class: "eg-conq-topo" }, el("strong", {}, `🥚 Ovo misterioso${o.origem ? ` (${o.origem})` : ""}`), el("small", {}, `${o.passos}/${o.passos_total} passos${o.incubando ? " · incubando" : ""}`)), barra(o.passos, o.passos_total), ...acoes);
  });
  const reformar = c.proximo
    ? botao(`Reformar para "${c.proximo.nome}" (₽ ${c.proximo.custo})`, async () => {
      const { error: er } = await supabase.rpc("casa_melhorar");
      if (er) return mensagem(msg, er.message);
      aposMudar();
      recarregar();
    }, "sec")
    : el("p", { class: "sub" }, "Sua casa está no nível máximo.");
  if (c.proximo && !c.aqui) (reformar as HTMLButtonElement).title = "Só dá para reformar estando na sua casa";
  modal.abrir(`Minha casa · ${c.nome}`,
    el("p", { class: "sub" }, `Incubadoras: ${c.incubadoras}. Ovos chocam enquanto você anda (até ${c.passos_max_dia} passos por dia; hoje: ${c.passos_hoje}).`),
    ...(ovos.length ? ovos : [el("p", { class: "sub" }, "Você não tem ovos. Eles vêm de prêmios e do Mestre.")]),
    c.proximo ? el("p", { class: "sub" }, `${c.proximo.descricao} Reformar exige estar na sua casa.`) : el("span", {}), reformar, msg);
}

// ---------- Títulos e molduras ----------
export async function abrirCosmeticos(modal: Modal, aviso: Aviso): Promise<void> {
  const { data, error } = await supabase.rpc("cosmeticos_meus");
  if (error) return aviso(error.message, 4000, true);
  const c = data as { titulo: string | null; moldura: string | null; itens: { id: string; tipo: string; nome: string }[] };
  const msg = msgPainel();
  const bloco = (tipo: "titulo" | "moldura", rotulo: string, ativo: string | null): HTMLElement => {
    const meus = c.itens.filter((i) => i.tipo === tipo);
    return el("div", {}, el("h3", { class: "eg-cat" }, rotulo),
      ...(meus.length ? [botao("Nenhum", async () => { await supabase.rpc("cosmetico_equipar", { p_tipo: tipo, p_id: null }); void abrirCosmeticos(modal, aviso); }, ativo ? "sec" : ""),
        ...meus.map((i) => botao(i.nome, async () => {
          const { error: er } = await supabase.rpc("cosmetico_equipar", { p_tipo: tipo, p_id: i.id });
          if (er) return mensagem(msg, er.message);
          void abrirCosmeticos(modal, aviso);
        }, ativo === i.id ? "" : "sec"))] : [el("p", { class: "sub" }, "Você ainda não ganhou nenhum.")]));
  };
  modal.abrir("Títulos e molduras", bloco("titulo", "Título", c.titulo), bloco("moldura", "Moldura do nome", c.moldura), msg);
}

// ---------- Novidades (conquistas novas e prêmios do ranking) ----------
export async function verificarNovidades(aviso: Aviso): Promise<void> {
  await carregarReferencias();
  const [{ data: cq }, { data: rk }] = await Promise.all([supabase.rpc("conquistas_novas"), supabase.rpc("ranking_meus_premios")]);
  for (const c of (cq ?? []) as { nome: string; recompensa: Premio }[]) aviso(`🏆 Conquista: ${c.nome}! Prêmio: ${textoPremio(c.recompensa)}`, 9000);
  for (const p of (rk ?? []) as { posicao: number | null; pontos: number; premio: Premio }[]) {
    aviso(p.posicao ? `🏅 Ranking encerrado: você ficou em ${p.posicao}º lugar! Prêmio: ${textoPremio(p.premio)}` : `Ranking encerrado: obrigado por participar! Prêmio: ${textoPremio(p.premio)}`, 12000);
  }
}
