import { el } from "./dom";
import { barraHp, COR_TIPO, especie, golpe, imagemPokemon, NOME_TIPO, nomePokemon, type PokemonRow } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
const NS = "http://www.w3.org/2000/svg";
const sv = (tag: string, at: Record<string, string>, ...filhos: Node[]): SVGElement => {
  const n = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(at)) n.setAttribute(k, v);
  n.append(...filhos);
  return n as SVGElement;
};

/** Gráfico hexagonal de atributos (estilo Pokémon Legends: Arceus). */
export function hexagono(p: PokemonRow): SVGElement {
  const stats: [string, number][] = [
    ["HP", p.hp_max], ["Ataque", p.atk ?? 0], ["Defesa", p.def ?? 0], ["Vel.", p.spe ?? 0], ["Def. Esp.", p.spd ?? 0], ["Atq. Esp.", p.spa ?? 0],
  ];
  const escala = Math.max(60, Math.max(...stats.map((s) => s[1])) * 1.15);
  const cx = 150, cy = 120, R = 78;
  const pt = (i: number, f: number): string => {
    const a = -Math.PI / 2 + (i * Math.PI) / 3;
    return `${(cx + Math.cos(a) * R * f).toFixed(1)},${(cy + Math.sin(a) * R * f).toFixed(1)}`;
  };
  const anel = (f: number) => sv("polygon", { points: stats.map((_, i) => pt(i, f)).join(" "), fill: "none", stroke: "#ffffff40", "stroke-width": "1" });
  const raios = stats.map((_, i) => sv("line", { x1: String(cx), y1: String(cy), x2: pt(i, 1).split(",")[0], y2: pt(i, 1).split(",")[1], stroke: "#ffffff30" }));
  const valores = sv("polygon", { points: stats.map((s, i) => pt(i, Math.min(1, s[1] / escala))).join(" "), fill: "#f5c54299", stroke: "#f5c542", "stroke-width": "2" });
  const rotulos = stats.map(([nome, v], i) => {
    const [x, y] = pt(i, 1.28).split(",");
    const t = sv("text", { x, y, "text-anchor": "middle", fill: "#fff", "font-size": "11", "font-weight": "700" });
    t.append(document.createTextNode(`${nome}`));
    const t2 = sv("text", { x, y: String(Number(y) + 13), "text-anchor": "middle", fill: "#f5c542", "font-size": "12", "font-weight": "800" });
    t2.append(document.createTextNode(String(v)));
    return [t, t2];
  }).flat();
  return sv("svg", { viewBox: "0 0 300 250", class: "hexa", role: "img", "aria-label": "Atributos" }, anel(1), anel(0.66), anel(0.33), ...raios, valores, ...rotulos);
}

/** Tela de resumo do Pokémon (estilo Arceus): retrato, tipos, hexágono de atributos, golpes, experiência. */
export function abrirResumo(modal: Modal, p: PokemonRow, voltar?: () => void): void {
  const e = especie(p.especie_id);
  const hp = barraHp(p.hp_atual, p.hp_max);
  const hpFill = el("div", { class: `hp-fill ${hp.classe}` });
  hpFill.style.width = `${hp.pct}%`;
  const base = p.nivel ** 3, prox = (p.nivel + 1) ** 3;
  const pctExp = Math.max(0, Math.min(100, ((p.exp - base) / (prox - base)) * 100));
  const expFill = el("div", { class: "exp-fill" });
  expFill.style.width = `${pctExp}%`;
  const tipos = e.tipos.map((t) => { const c = el("span", { class: "chip-tipo" }, NOME_TIPO[t] ?? t); c.style.background = COR_TIPO[t] ?? "#888"; return c; });
  const golpes = p.golpes.map((s) => {
    const g = golpe(s.id);
    const b = el("div", { class: "rs-golpe" }, el("b", {}, g.nome), el("span", {}, `PP ${s.pp}/${g.pp}`));
    b.style.setProperty("--cor", COR_TIPO[g.tipo] ?? "#888");
    return b;
  });
  const retrato = el("div", { class: "rs-retrato" }, imagemPokemon("frente", p.especie_id, "grande", p.brilhante));
  retrato.style.setProperty("--cor", COR_TIPO[e.tipos[0]] ?? "#4f8cff");
  const esq = el("div", { class: "rs-esq" }, retrato,
    el("div", { class: "rs-nome" }, el("strong", {}, nomePokemon(p)), el("span", { class: "nivel" }, `Nv ${p.nivel}`)),
    el("div", { class: "tipos" }, ...tipos),
    el("div", { class: "hp" }, el("span", { class: "hp-rot" }, "HP"), el("div", { class: "hp-trilho" }, hpFill), el("span", { class: "hp-num" }, `${p.hp_atual}/${p.hp_max}`)),
    el("div", { class: "rs-exp" }, el("small", {}, `EXP ${p.exp} · faltam ${Math.max(0, prox - p.exp)} para o nível ${p.nivel + 1}`), el("div", { class: "exp-trilho" }, expFill)));
  const dir = el("div", { class: "rs-dir" }, hexagono(p),
    el("small", { class: "rs-info" }, `Natureza: ${p.natureza ?? "—"} · Amizade: ${p.amizade ?? "—"}`),
    el("div", { class: "rs-golpes" }, ...golpes));
  const nos: Node[] = [el("div", { class: "rs-tela" }, esq, dir)];
  if (voltar) { const b = el("button", { type: "button", class: "sec" }, "◀ Voltar"); b.addEventListener("click", voltar); nos.push(b); }
  modal.abrir(`${e.nome} — Resumo`, ...nos);
}
