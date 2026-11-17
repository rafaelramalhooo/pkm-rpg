// Quests: tela organizada (no Painel do treinador e na tecla J) com missão, busca de Pedra, tarefas do dia e desafios da semana.
import { supabase } from "../supabase";
import { el } from "./dom";
import { carregarReferencias } from "./dados";
import { textoPremio } from "./engajamento";

export interface QuestItem {
  tipo: "missao" | "pedra" | "mv" | "semana"; id: string; titulo: string; passo?: string; npc?: string | null;
  mapa_id?: string | null; mapa?: string | null; progresso?: string; recompensa?: Parameters<typeof textoPremio>[0];
}
type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };

const GRUPOS: { tipo: QuestItem["tipo"]; titulo: string; icone: string; recolher?: boolean }[] = [
  { tipo: "missao", titulo: "Missão principal", icone: "📜" },
  { tipo: "pedra", titulo: "Busca de Pedra", icone: "💎" },
  { tipo: "mv", titulo: "Tarefas do dia", icone: "☀️" },
  { tipo: "semana", titulo: "Desafios da semana", icone: "🎯", recolher: true },
];

export async function abrirQuests(modal: Modal, verNoMapa: (q: QuestItem) => void): Promise<void> {
  await carregarReferencias();
  const { data } = await supabase.rpc("quests_diario");
  const lista = Array.isArray(data) ? (data as QuestItem[]) : [];

  const cartao = (q: QuestItem): HTMLElement => {
    const topo = el("div", { class: "qd-topo" }, el("strong", {}, q.titulo.replace(/^(Desafio|Busca): /, "")));
    if (q.progresso) topo.append(el("span", { class: "qd-prog" }, q.progresso));
    const nos: Node[] = [topo];
    if (q.passo) nos.push(el("p", { class: "qd-passo" }, q.passo));
    const meta: Node[] = [];
    const onde = [q.npc, q.mapa].filter(Boolean).join(" · ");
    if (onde) meta.push(el("span", {}, `📍 ${onde}`));
    if (q.recompensa) meta.push(el("span", {}, `🎁 ${textoPremio(q.recompensa)}`));
    if (meta.length) nos.push(el("div", { class: "qd-meta" }, ...meta));
    if (q.mapa_id) {
      const b = el("button", { type: "button", class: "sec qd-mapa" }, "Ver no mapa");
      b.addEventListener("click", () => verNoMapa(q));
      nos.push(b);
    }
    return el("div", { class: `qd-cartao qd-${q.tipo}` }, ...nos);
  };

  const blocos: Node[] = [];
  for (const g of GRUPOS) {
    const itens = lista.filter((q) => q.tipo === g.tipo);
    if (!itens.length) continue;
    const cab = `${g.icone} ${g.titulo} (${itens.length})`;
    if (g.recolher) {
      blocos.push(el("details", { class: "qd-grupo" }, el("summary", {}, cab), el("div", { class: "qd-lista" }, ...itens.map(cartao))));
    } else {
      blocos.push(el("div", { class: "qd-grupo" }, el("h4", {}, cab), el("div", { class: "qd-lista" }, ...itens.map(cartao))));
    }
  }
  if (!lista.some((q) => q.tipo !== "semana")) blocos.unshift(el("p", { class: "sub" }, "Nenhuma missão ativa agora. Procure NPCs com ❗ nos mapas para começar uma."));
  modal.abrir("Quests", el("div", { class: "qd" }, ...blocos));
}
