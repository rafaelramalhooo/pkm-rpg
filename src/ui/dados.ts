// Dados de referência (espécies, golpes, itens) e sprites (bucket privado) usados pela interface.
import { supabase } from "../supabase";

export interface Especie { id: number; nome: string; tipos: string[] }
export interface GolpeInfo { id: number; slug?: string; nome: string; tipo: string; categoria: string; poder: number | null; pp: number }
export interface GolpeSlot { id: number; pp: number }
export interface PokemonRow {
  id: string;
  especie_id: number;
  apelido: string | null;
  nivel: number;
  exp: number;
  hp_max: number;
  hp_atual: number;
  golpes: GolpeSlot[];
  posicao: number | null;
  brilhante?: boolean;
}

const especies = new Map<number, Especie>();
const golpes = new Map<number, GolpeInfo>();
const golpesSlug = new Map<string, GolpeInfo>();
const itens = new Map<string, string>();
const itensInfo = new Map<string, { efeito: string; categoria: string }>();
let carregado = false;

export async function carregarReferencias(forcar = false): Promise<boolean> {
  if (carregado && !forcar) return especies.size > 0;
  const [e, g, i] = await Promise.all([
    supabase.from("especies").select("id, nome, tipos").order("id").limit(2000),
    supabase.from("golpes").select("id, slug, nome, tipo, categoria, poder, pp").limit(2000),
    supabase.from("itens").select("slug, nome, efeito, categoria").limit(500),
  ]);
  especies.clear();
  golpes.clear();
  golpesSlug.clear();
  itens.clear();
  itensInfo.clear();
  for (const x of (e.data ?? []) as Especie[]) especies.set(x.id, x);
  for (const x of (g.data ?? []) as GolpeInfo[]) { golpes.set(x.id, x); if (x.slug) golpesSlug.set(x.slug.replace(/-/g, ""), x); }
  for (const x of (i.data ?? []) as { slug: string; nome: string; efeito: string | null; categoria: string | null }[]) {
    itens.set(x.slug, x.nome);
    itensInfo.set(x.slug, { efeito: x.efeito ?? "", categoria: x.categoria ?? "" });
  }
  carregado = true;
  return especies.size > 0;
}

export const especie = (id: number): Especie => especies.get(id) ?? { id, nome: `#${id}`, tipos: [] };
export const golpe = (id: number): GolpeInfo => golpes.get(id) ?? { id, nome: `Golpe ${id}`, tipo: "normal", categoria: "physical", poder: null, pp: 10 };
export const infoItem = (slug: string): { efeito: string; categoria: string } => itensInfo.get(slug) ?? { efeito: "", categoria: "" };
export const golpePorSlug = (slug: string): GolpeInfo | undefined => golpesSlug.get(slug);
export const nomeItem = (slug: string): string => (itens.get(slug) ?? slug).replace(/^Poke /, "Poké ");
export const nomePokemon = (p: PokemonRow): string => (p.apelido ?? especie(p.especie_id).nome) + (p.brilhante ? " ✨" : "");
export const totalEspecies = (): number => especies.size;
export const todasEspecies = (): Especie[] => [...especies.values()];

export const COR_TIPO: Record<string, string> = {
  normal: "#a8a878", fire: "#f08030", water: "#6890f0", electric: "#f8d030", grass: "#78c850", ice: "#98d8d8",
  fighting: "#c03028", poison: "#a040a0", ground: "#e0c068", flying: "#a890f0", psychic: "#f85888", bug: "#a8b820",
  rock: "#b8a038", ghost: "#705898", dragon: "#7038f8", dark: "#705848", steel: "#b8b8d0", fairy: "#ee99ac",
};
export const NOME_TIPO: Record<string, string> = {
  normal: "Normal", fire: "Fogo", water: "Água", electric: "Elétrico", grass: "Planta", ice: "Gelo", fighting: "Lutador",
  poison: "Veneno", ground: "Terra", flying: "Voador", psychic: "Psíquico", bug: "Inseto", rock: "Pedra", ghost: "Fantasma",
  dragon: "Dragão", dark: "Sombrio", steel: "Aço", fairy: "Fada",
};

// ---------- sprites (bucket privado: só com sessão, via URL assinada temporária) ----------

const urls = new Map<string, Promise<string | null>>();
export type LadoSprite = "frente" | "costas";

export function urlSprite(lado: LadoSprite, id: number): Promise<string | null> {
  const caminho = `${lado}/${id}.gif`;
  let p = urls.get(caminho);
  if (!p) {
    p = supabase.storage
      .from("sprites")
      .createSignedUrl(caminho, 3600)
      .then(({ data, error }) => (error || !data ? null : data.signedUrl))
      .catch(() => null);
    urls.set(caminho, p);
    window.setTimeout(() => urls.delete(caminho), 50 * 60 * 1000);
  }
  return p;
}

/** Cria um <img> que se preenche sozinho (ou mostra o nome se o sprite ainda não foi importado). */
export function imagemPokemon(lado: LadoSprite, id: number, classe = "", brilhante = false): HTMLElement {
  const caixa = document.createElement("div");
  caixa.className = `pk-img ${classe}${brilhante ? " brilhante" : ""}`;
  void urlSprite(lado, id).then((u) => {
    if (!u) {
      caixa.textContent = especie(id).nome;
      caixa.classList.add("sem-sprite");
      return;
    }
    const img = document.createElement("img");
    img.alt = especie(id).nome;
    img.decoding = "async";
    img.addEventListener("error", () => {
      img.remove();
      caixa.textContent = especie(id).nome;
      caixa.classList.add("sem-sprite");
    });
    img.src = u;
    caixa.append(img);
  });
  return caixa;
}

// ---------- dados do jogador ----------

export async function meuTime(uid: string): Promise<PokemonRow[]> {
  const { data } = await supabase
    .from("pokemons")
    .select("*")
    .eq("dono", uid)
    .not("posicao", "is", null)
    .order("posicao");
  return (data ?? []) as PokemonRow[];
}

export async function minhaMochila(uid: string): Promise<{ item: string; qtd: number }[]> {
  const { data } = await supabase.from("inventario").select("item, qtd").eq("jogador", uid).gt("qtd", 0).order("item");
  return (data ?? []) as { item: string; qtd: number }[];
}

export function barraHp(atual: number, max: number): { pct: number; classe: string } {
  const pct = max > 0 ? Math.max(0, Math.min(100, (atual / max) * 100)) : 0;
  return { pct, classe: pct > 50 ? "ok" : pct > 20 ? "medio" : "baixo" };
}
