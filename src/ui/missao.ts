// Missões: estado para o HUD/Mapa Mundi e diálogo com os NPCs de missão (tudo validado no servidor).
import { supabase } from "../supabase";
import { el } from "./dom";
import { carregarReferencias, nomeItem } from "./dados";
import { textoEventos } from "./habilidades";
import { processarEventos } from "./momentos";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void; aoFechar: (fn: (() => void) | null) => void };

export interface MissaoEstado {
  id: string; nome: string; estado: "ativa" | "concluida"; feitas: number; total: number;
  objetivo?: string; npc?: string; mapa_id?: string; mapa_nome?: string;
}

export async function carregarMissao(): Promise<MissaoEstado | null> {
  const { data } = await supabase.rpc("missao_estado");
  return (data as MissaoEstado | null) ?? null;
}

interface Resp {
  tipo: "oferta" | "fala" | "pendente" | "avanca"; nome: string; texto: string; missao?: string; descricao?: string; concluida?: boolean;
  recompensa?: { dinheiro?: number; xp_treinador?: number; xp_pokemon?: number; itens?: { item: string; qtd: number }[] } | null;
  eventos?: { t: string; [k: string]: unknown }[];
}

/** Conversa com um NPC de missão. Resolve quando o jogador fecha a janela. */
export async function conversarNpc(modal: Modal, npcId: string, titulo: string, aviso: (t: string, ms?: number, erro?: boolean) => void, aoMudar: () => void): Promise<void> {
  await carregarReferencias();
  const { data, error } = await supabase.rpc("npc_interagir", { p_npc: npcId });
  if (error || !data) return void aviso(error?.message ?? "Não foi possível conversar agora.", 4000, true);
  const r = data as Resp;
  await new Promise<void>((fim) => {
    const fechar = (): void => { modal.aoFechar(null); modal.fechar(); fim(); };
    const nos: Node[] = [el("p", { class: "fala-npc" }, `"${r.texto}"`)];
    if (r.tipo === "oferta") {
      nos.unshift(el("p", { class: "sub" }, `Missão: ${r.missao}`));
      nos.push(el("p", { class: "sub" }, r.descricao ?? ""));
      const ok = el("button", { type: "button" }, "Aceitar a missão");
      ok.addEventListener("click", async () => {
        ok.disabled = true;
        const { error: er } = await supabase.rpc("missao_aceitar", { p_npc: npcId });
        if (er) { ok.disabled = false; return void aviso(er.message, 4000, true); }
        aviso("Missão aceita! Veja o destino no Mapa Mundi e no canto da tela.", 5000);
        aoMudar();
        fechar();
      });
      nos.push(ok, (() => { const b = el("button", { type: "button", class: "sec" }, "Agora não"); b.addEventListener("click", fechar); return b; })());
    } else {
      if (r.tipo === "avanca" && r.concluida && r.recompensa) {
        const rc = r.recompensa;
        const itens = [rc.dinheiro ? `₽ ${rc.dinheiro}` : "", rc.xp_treinador ? `+${rc.xp_treinador} XP de treinador` : "", rc.xp_pokemon ? `+${rc.xp_pokemon} XP para cada Pokémon do time` : "",
          ...(rc.itens ?? []).map((i) => `${i.qtd}× ${nomeItem(i.item)}`)].filter(Boolean);
        nos.push(el("p", { class: "sub" }, `Missão concluída: ${r.missao}!`), el("div", { class: "rec-lista" }, ...itens.map((t) => el("span", {}, t))));
        const ev = textoEventos((r.eventos ?? []) as Parameters<typeof textoEventos>[0]);
        if (ev) nos.push(el("p", { class: "sub" }, ev));
      } else if (r.tipo === "avanca") nos.push(el("p", { class: "sub" }, "Objetivo concluído! Veja o próximo no canto da tela."));
      const b = el("button", { type: "button" }, "Ok");
      b.addEventListener("click", fechar);
      nos.push(b);
    }
    modal.abrir(titulo, ...nos);
    modal.aoFechar(() => fim());
  });
  if (r.tipo === "avanca") { aoMudar(); await processarEventos(r.eventos); }
}
