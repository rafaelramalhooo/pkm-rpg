// Pokédex: busca por nome, onde cada Pokémon aparece (e a chance), fraquezas e resistências. Também usada dentro da batalha.
import { supabase } from "../supabase";
import { el } from "./dom";
import { COR_TIPO, NOME_TIPO, carregarReferencias, especie, imagemPokemon, textoSobre, todasEspecies } from "./dados";

interface Encontro { mapa_id: string; bioma: string; especie_id: number; peso: number; nivel_min: number; nivel_max: number }
let encontros: Encontro[] | null = null;
let nomesMapa: Map<string, string> | null = null;
let eficacia: { atacante: string; defensor: string; mult: number }[] | null = null;

const NOME_BIOMA: Record<string, string> = { grama: "Grama alta", campo: "Campo", agua: "Água", floresta: "Floresta", estrada: "Estrada" };

async function carregar(): Promise<void> {
  await carregarReferencias();
  if (!encontros) {
    const [e, m, f] = await Promise.all([
      supabase.from("encontros").select("mapa_id, bioma, especie_id, peso, nivel_min, nivel_max").limit(3000),
      supabase.from("mapas").select("id, nome").limit(200),
      supabase.from("eficacia").select("atacante, defensor, mult").limit(500),
    ]);
    encontros = (e.data ?? []) as Encontro[];
    nomesMapa = new Map(((m.data ?? []) as { id: string; nome: string }[]).map((x) => [x.id, x.nome]));
    eficacia = (f.data ?? []) as { atacante: string; defensor: string; mult: number }[];
  }
}

/** Onde o Pokémon aparece e a chance (peso dele ÷ soma dos pesos do mesmo bioma do mapa). */
export function locaisDe(id: number): { mapa: string; bioma: string; chance: number; nv: string }[] {
  const lista = encontros ?? [];
  const soma = new Map<string, number>();
  for (const x of lista) soma.set(`${x.mapa_id}|${x.bioma}`, (soma.get(`${x.mapa_id}|${x.bioma}`) ?? 0) + x.peso);
  return lista.filter((x) => x.especie_id === id)
    .map((x) => ({ mapa: nomesMapa?.get(x.mapa_id) ?? x.mapa_id, bioma: x.bioma, chance: (x.peso / (soma.get(`${x.mapa_id}|${x.bioma}`) || 1)) * 100, nv: x.nivel_min === x.nivel_max ? `Nv ${x.nivel_min}` : `Nv ${x.nivel_min}-${x.nivel_max}` }))
    .sort((a, b) => b.chance - a.chance);
}

/** Multiplicador de dano de cada tipo atacante contra o(s) tipo(s) do Pokémon. */
export function fraquezasDe(tipos: string[]): Record<string, number> {
  const r: Record<string, number> = {};
  for (const atk of Object.keys(NOME_TIPO)) {
    let m = 1;
    for (const d of tipos) {
      const linha = (eficacia ?? []).find((x) => x.atacante === atk && x.defensor === d);
      if (linha) m *= Number(linha.mult);
    }
    r[atk] = m;
  }
  return r;
}

const selo = (t: string, extra = ""): HTMLElement => {
  const s = el("span", { class: "dx-tipo" }, extra ? `${NOME_TIPO[t] ?? t} ${extra}` : (NOME_TIPO[t] ?? t));
  s.style.background = COR_TIPO[t] ?? "#777"; s.style.color = textoSobre(COR_TIPO[t] ?? "#777"); s.style.textShadow = "none";
  return s;
};

/** Ficha de uma espécie: tipos, fraquezas/resistências e (opcional) onde aparece. */
export async function fichaEspecie(id: number, opcoes: { locais?: boolean; nota?: HTMLElement | string } = {}): Promise<HTMLElement> {
  await carregar();
  const e = especie(id);
  const f = fraquezasDe(e.tipos);
  const grupo = (rotulo: string, cond: (m: number) => boolean, fmt: (m: number) => string, classe: string): HTMLElement | null => {
    const itens = Object.entries(f).filter(([, m]) => cond(m)).sort((a, b) => b[1] - a[1]);
    if (!itens.length) return null;
    return el("div", { class: `dx-grupo ${classe}` }, el("strong", {}, rotulo), el("div", { class: "dx-tipos" }, ...itens.map(([t, m]) => selo(t, fmt(m)))));
  };
  const caixa = el("div", { class: "dx-ficha" },
    el("div", { class: "dx-topo" }, imagemPokemon("frente", id, "dx-sprite"),
      el("div", {}, el("h3", {}, `#${String(id).padStart(3, "0")} ${e.nome}`), el("div", { class: "dx-tipos" }, ...e.tipos.map((t) => selo(t))))));
  if (opcoes.nota) caixa.append(typeof opcoes.nota === "string" ? el("p", { class: "sub" }, opcoes.nota) : opcoes.nota);
  const gs = [
    grupo("Fraco contra", (m) => m > 1, (m) => `×${m}`, "fraco"),
    grupo("Resiste a", (m) => m > 0 && m < 1, (m) => `×${m === 0.5 ? "½" : m === 0.25 ? "¼" : m}`, "resiste"),
    grupo("Imune a", (m) => m === 0, () => "×0", "imune"),
  ].filter(Boolean) as HTMLElement[];
  caixa.append(...gs);
  if (opcoes.locais !== false) {
    const ls = locaisDe(id);
    caixa.append(el("div", { class: "dx-grupo" }, el("strong", {}, "Onde aparece"),
      ls.length
        ? el("ul", { class: "dx-locais" }, ...ls.map((l) => el("li", {}, el("span", {}, `${l.mapa} · ${NOME_BIOMA[l.bioma] ?? l.bioma}`), el("span", { class: "dx-pct" }, `${l.chance < 1 ? l.chance.toFixed(1) : Math.round(l.chance)}%`), el("small", {}, l.nv))))
        : el("p", { class: "sub" }, "Não aparece na natureza por aqui (pode vir de presentes, trocas, evolução ou eventos).")));
    caixa.append(el("p", { class: "sub dx-nota" }, "A chance vale entre os Pokémon que aparecem naquele bioma do mapa; eventos do Mestre podem alterar."));
  }
  return caixa;
}

/** Caixa de busca por nome ou número com a ficha logo abaixo. */
export async function painelBusca(inicial?: number, opcoes: { locais?: boolean } = {}): Promise<HTMLElement> {
  await carregar();
  const entrada = el("input", { type: "search", placeholder: "Digite o nome ou o número de um Pokémon...", class: "dx-busca", autocomplete: "off" }) as HTMLInputElement;
  const sugestoes = el("div", { class: "dx-sug" });
  const ficha = el("div", { class: "dx-resultado" });
  const mostrar = async (id: number): Promise<void> => {
    entrada.value = especie(id).nome;
    sugestoes.replaceChildren();
    ficha.replaceChildren(await fichaEspecie(id, opcoes));
  };
  const filtrar = (): void => {
    const q = entrada.value.trim().toLowerCase();
    if (!q) { sugestoes.replaceChildren(); return; }
    const achados = todasEspecies().filter((e) => e.nome.toLowerCase().includes(q) || String(e.id) === q.replace(/^#/, "").replace(/^0+/, "")).slice(0, 8);
    sugestoes.replaceChildren(...achados.map((e) => {
      const b = el("button", { type: "button", class: "dx-item" }, `#${String(e.id).padStart(3, "0")} ${e.nome}`);
      b.addEventListener("click", () => void mostrar(e.id));
      return b;
    }));
    if (achados.length === 1 && achados[0].nome.toLowerCase() === q) void mostrar(achados[0].id);
  };
  entrada.addEventListener("input", filtrar);
  entrada.addEventListener("keydown", (ev) => { if (ev.key === "Enter") { const p = sugestoes.firstElementChild as HTMLButtonElement | null; p?.click(); } });
  const raiz = el("div", { class: "dx-painel" }, entrada, sugestoes, ficha);
  if (inicial) await mostrar(inicial);
  return raiz;
}
