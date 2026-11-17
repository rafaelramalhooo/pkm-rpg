// Diário de Quests: quadro minimizável com todas as quests do jogador (missão, busca de Pedra, tarefas do dia e desafios da semana).
import { supabase } from "../supabase";
import { el } from "./dom";
import { carregarReferencias } from "./dados";
import { textoPremio } from "./engajamento";

export interface QuestItem {
  tipo: "missao" | "pedra" | "mv" | "semana"; id: string; titulo: string; passo?: string; npc?: string | null;
  mapa_id?: string | null; mapa?: string | null; progresso?: string; recompensa?: Parameters<typeof textoPremio>[0];
}

export interface Diario { raiz: HTMLElement; atualizar: () => Promise<void>; alternar: () => void }

const CHAVE = "pkm_diario_aberto";

export function criarDiario(verNoMapa: (q: QuestItem) => void): Diario {
  let aberto = false;
  try { const v = localStorage.getItem(CHAVE); aberto = v === null ? window.innerWidth > 700 : v === "1"; } catch { /* sem storage */ }
  let lista: QuestItem[] = [];
  let semanaAberta = false;
  const raiz = el("div", { class: "diario" });
  const topo = el("button", { type: "button", class: "diario-topo", title: "Quests (tecla J)", "aria-label": "Abrir ou minimizar o diário de quests" });
  const corpo = el("div", { class: "diario-corpo" });
  raiz.append(topo, corpo);

  const cartao = (q: QuestItem): HTMLElement => {
    const nos: Node[] = [el("strong", {}, q.titulo)];
    if (q.passo) nos.push(el("span", { class: "dq-passo" }, q.passo));
    const onde = [q.npc, q.mapa].filter(Boolean).join(" · ");
    if (onde) nos.push(el("small", { class: "dq-onde" }, `📍 ${onde}`));
    if (q.progresso) nos.push(el("small", { class: "dq-prog" }, `Progresso: ${q.progresso}`));
    if (q.recompensa) nos.push(el("small", { class: "dq-rec" }, `Prêmio: ${textoPremio(q.recompensa)}`));
    if (q.mapa_id) {
      const b = el("button", { type: "button", class: "dq-mapa" }, "📍 Ver no mapa");
      b.addEventListener("click", () => verNoMapa(q));
      nos.push(b);
    }
    return el("div", { class: `dq dq-${q.tipo}` }, ...nos);
  };

  const desenhar = (): void => {
    raiz.classList.toggle("minimizado", !aberto);
    const principais = lista.filter((q) => q.tipo !== "semana");
    const semana = lista.filter((q) => q.tipo === "semana");
    topo.replaceChildren(el("span", {}, `📜 Quests${principais.length ? ` (${principais.length})` : ""}`), el("i", {}, aberto ? "▾  J" : "▸  J"));
    const nos: Node[] = [];
    if (!principais.length) nos.push(el("p", { class: "sub" }, "Nenhuma quest ativa. Procure NPCs com ❗ nos mapas para começar uma."));
    nos.push(...principais.map(cartao));
    if (semana.length) {
      const cab = el("button", { type: "button", class: "dq-semana-cab" }, `${semanaAberta ? "▾" : "▸"} Desafios da semana (${semana.length})`);
      cab.addEventListener("click", () => { semanaAberta = !semanaAberta; desenhar(); });
      nos.push(cab);
      if (semanaAberta) nos.push(...semana.map(cartao));
    }
    corpo.replaceChildren(...nos);
  };

  const alternar = (): void => {
    aberto = !aberto;
    try { localStorage.setItem(CHAVE, aberto ? "1" : "0"); } catch { /* sem storage */ }
    desenhar();
  };
  topo.addEventListener("click", alternar);

  const atualizar = async (): Promise<void> => {
    try {
      await carregarReferencias();
      const { data } = await supabase.rpc("quests_diario");
      lista = Array.isArray(data) ? (data as QuestItem[]) : [];
    } catch { /* mantém a lista anterior */ }
    desenhar();
  };
  desenhar();
  return { raiz, atualizar, alternar };
}
