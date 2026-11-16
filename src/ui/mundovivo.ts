// Mundo vivo: NPCs do turno, Pokémon do dia, pistas (Fofoqueiro/Mural) e prêmios. Tudo é validado no servidor.
import { supabase } from "../supabase";
import { el } from "./dom";
import { caixaFala } from "./fala";
import { carregarReferencias, nomeItem } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void; aoFechar: (fn: (() => void) | null) => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

export interface MvNpc { id: string; x: number; y: number; direcao: "cima" | "baixo" | "esquerda" | "direita"; nome: string; classe: string; aparencia: number; arquetipo: string }
export interface MvFixo { id: string; x: number; y: number; direcao: "cima" | "baixo" | "esquerda" | "direita"; nome: string; aparencia: number; tipo: "fofoqueiro" | "mural" }
export interface MvPokemon { especie_id: number; x: number; y: number; direcao: "cima" | "baixo" | "esquerda" | "direita"; tentou: boolean }
export interface MvMapa { ativo: boolean; turno?: number; periodo?: string; desafiante_pa?: number; npcs?: MvNpc[]; fixos?: MvFixo[]; pokemon?: MvPokemon[] }
export interface Pistas { fofoca: string[]; mural: string[]; turno?: number }

export const ehDesafiante = (id: string): boolean => /^d[cver]_/.test(id);

export async function carregarMvMapa(mapaId: string): Promise<MvMapa> {
  try {
    const { data, error } = await supabase.rpc("mv_mapa", { p_mapa: mapaId });
    if (error || !data) return { ativo: false };
    return data as MvMapa;
  } catch { return { ativo: false }; }
}

export async function carregarPistas(): Promise<Pistas> {
  try {
    const { data } = await supabase.rpc("mv_pistas");
    const d = (data ?? {}) as Partial<Pistas>;
    return { fofoca: d.fofoca ?? [], mural: d.mural ?? [], turno: d.turno };
  } catch { return { fofoca: [], mural: [] }; }
}

const botao = (texto: string, fn: () => void, classe = ""): HTMLButtonElement => {
  const b = el("button", { type: "button", class: classe }, texto);
  b.addEventListener("click", fn);
  return b;
};

/** Fofoqueiro e Mural: além do balão automático, ao conversar mostra tudo de uma vez. */
export async function mostrarPistas(modal: Modal, tipo: "fofoqueiro" | "mural", titulo: string): Promise<void> {
  const p = await carregarPistas();
  const lista = tipo === "mural" ? p.mural : p.fofoca;
  await new Promise<void>((fim) => {
    const fechar = (): void => { modal.aoFechar(null); modal.fechar(); fim(); };
    modal.abrir(titulo,
      el("div", { class: "rec-lista" }, ...(lista.length ? lista : ["Nada de novo por aqui."]).map((t) => el("p", { class: "fala-npc" }, t))),
      botao("Ok", fechar));
    modal.aoFechar(() => fim());
  });
}

/** Pokémon do dia: observa de perto (1 PA, uma tentativa por aparição) e entra na batalha. */
export async function observarPokemon(modal: Modal, aviso: Aviso, lutar: (r: never) => Promise<void>): Promise<void> {
  const ok = await new Promise<boolean>((resolve) => {
    const fechar = (v: boolean): void => { modal.aoFechar(null); modal.fechar(); resolve(v); };
    modal.abrir("Algo raro nas moitas",
      el("p", { class: "fala-npc" }, "Há um Pokémon raro aqui. Ele só fica neste turno, e você tem uma única tentativa. Chance maior de ser brilhante!"),
      botao("Aproximar (−1 PA)", () => fechar(true)),
      botao("Agora não", () => fechar(false), "sec"));
    modal.aoFechar(() => resolve(false));
  });
  if (!ok) return;
  const { data, error } = await supabase.rpc("mv_pokemon_buscar");
  if (error || !data) return void aviso(error?.message ?? "Não foi possível agora.", 4000, true);
  await lutar(data as never);
}

interface Opcao { id: string; rotulo: string; custo_pa?: number; detalhe?: string }
interface RespInteragir { npc?: string; texto?: string; mensagem?: string; opcoes?: Opcao[]; premio?: Record<string, unknown>; fim?: boolean }

export function textoPremio(p: Record<string, unknown> | null | undefined): string {
  if (!p) return "";
  const out: string[] = [];
  if (typeof p.dinheiro === "number" && p.dinheiro) out.push(`₽ ${p.dinheiro}`);
  if (typeof p.xp_treinador === "number" && p.xp_treinador) out.push(`+${p.xp_treinador} XP de treinador`);
  if (typeof p.pa === "number" && p.pa) out.push(`+${p.pa} PA`);
  if (typeof p.mt === "string") out.push(`${p.mt}`);
  for (const i of (Array.isArray(p.itens) ? p.itens : []) as { item: string; qtd: number }[]) out.push(`${i.qtd}× ${nomeItem(i.item)}`);
  const ov = p.ovo as { especie?: number } | undefined;
  if (ov) out.push("1 ovo de Pokémon");
  return out.join(" · ");
}

/** NPC especial do turno (serviço, missão, troca): o servidor devolve o menu e executa a opção escolhida. */
export async function interagirMv(modal: Modal, npcId: string, titulo: string, aviso: Aviso, aoMudar: () => void): Promise<void> {
  await carregarReferencias();
  let acao: string | null = null;
  let arg: string | null = null;
  for (let volta = 0; volta < 12; volta++) {
    const { data, error } = await supabase.rpc("mv_interagir", { p_npc: npcId, p_acao: acao, p_arg: arg });
    if (error || !data) return void aviso(error?.message ?? "Não foi possível conversar agora.", 4000, true);
    const r = data as RespInteragir;
    if (acao) aoMudar();
    const escolha = await new Promise<{ id: string } | null>((resolve) => {
      const fechar = (v: { id: string } | null): void => { modal.aoFechar(null); modal.fechar(); resolve(v); };
      const nos: Node[] = [];
      if (r.mensagem) nos.push(el("p", { class: "sub" }, r.mensagem));
      const extras: Node[] = [];
      const pr = textoPremio(r.premio);
      if (pr) extras.push(el("div", { class: "rec-lista" }, ...pr.split(" · ").map((t) => el("span", {}, t))));
      for (const o of r.opcoes ?? []) {
        const b = botao(`${o.rotulo}${o.custo_pa ? ` (−${o.custo_pa} PA)` : ""}`, () => fechar({ id: o.id }));
        extras.push(b);
        if (o.detalhe) extras.push(el("p", { class: "sub" }, o.detalhe));
      }
      extras.push(botao(r.opcoes?.length ? "Sair" : "Ok", () => fechar(null), "sec"));
      modal.abrir(titulo, ...nos, r.texto ? caixaFala(titulo, r.texto, ...extras) : el("div", {}, ...extras));
      modal.aoFechar(() => resolve(null));
    });
    if (!escolha) return;
    acao = escolha.id;
    arg = null;
  }
}

/** Prêmios que chegaram por vitórias em desafiantes/NPCs (itens, MTs): avisa o jogador uma vez. */
export async function mostrarPremiosNovos(aviso: Aviso): Promise<void> {
  try {
    const { data } = await supabase.rpc("mv_premios_novos");
    for (const p of (Array.isArray(data) ? data : []) as { titulo: string; payload: Record<string, unknown> }[]) {
      await carregarReferencias();
      const t = textoPremio(p.payload);
      if (t) aviso(`${p.titulo}: ${t}`, 6500);
    }
  } catch { /* sem prêmios novos */ }
}
