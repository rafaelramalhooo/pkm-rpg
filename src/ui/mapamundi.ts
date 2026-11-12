import { supabase } from "../supabase";
import { el } from "./dom";

type No = { id: string; nome: string; x: number; y: number; t: "cidade" | "rota" | "local" };

/** Mapa Mundi de Rafar (layout fixo; as ligações seguem os portais reais). */
const NOS: No[] = [
  { id: "porto", nome: "Porto Turquesa", x: 60, y: 60, t: "cidade" },
  { id: "rota1", nome: "Rota 1", x: 60, y: 76, t: "rota" },
  { id: "pallet", nome: "Vila Alvorada", x: 60, y: 92, t: "cidade" },
  { id: "caminho_va", nome: "Vaga-Lume", x: 42, y: 60, t: "local" },
  { id: "verdelume", nome: "Verdelume", x: 24, y: 60, t: "cidade" },
  { id: "rota2", nome: "Rota 2", x: 48, y: 44, t: "rota" },
  { id: "argila", nome: "Argila", x: 36, y: 28, t: "cidade" },
  { id: "rota3", nome: "Rota 3", x: 18, y: 44, t: "rota" },
  { id: "rota4", nome: "Rota 4", x: 12, y: 76, t: "rota" },
  { id: "carmesim", nome: "Carmesim", x: 28, y: 94, t: "cidade" },
  { id: "rota5", nome: "Rota 5", x: 44, y: 78, t: "rota" },
  { id: "costa1", nome: "Costa Azul", x: 80, y: 62, t: "local" },
  { id: "azurana", nome: "Azurana", x: 98, y: 62, t: "cidade" },
  { id: "costa2", nome: "Costa Rosada", x: 80, y: 80, t: "local" },
  { id: "quartzo", nome: "Quartzo Rosa", x: 98, y: 94, t: "cidade" },
  { id: "rota7a", nome: "Rota 7", x: 108, y: 78, t: "rota" },
  { id: "rota8", nome: "Rota 8", x: 118, y: 96, t: "rota" },
  { id: "reserva", nome: "Reserva", x: 110, y: 108, t: "local" },
  { id: "rota6", nome: "Rota 6", x: 68, y: 44, t: "rota" },
  { id: "ametista", nome: "Ametista", x: 84, y: 30, t: "cidade" },
  { id: "vale", nome: "Vale Cinzento", x: 100, y: 14, t: "local" },
  { id: "rota10", nome: "Rota 10", x: 104, y: 36, t: "rota" },
  { id: "obsidiana", nome: "Obsidiana", x: 120, y: 48, t: "cidade" },
  { id: "rota9", nome: "Rota 9", x: 130, y: 64, t: "rota" },
  { id: "ambar", nome: "Âmbar", x: 130, y: 82, t: "cidade" },
  { id: "gruta", nome: "Gruta", x: 128, y: 28, t: "local" },
  { id: "cromatica", nome: "Cromática", x: 130, y: 12, t: "local" },
  { id: "plato", nome: "Platô (Liga)", x: 114, y: 4, t: "local" },
];
const LIGACOES: [string, string][] = [
  ["porto", "caminho_va"], ["caminho_va", "verdelume"], ["porto", "costa1"], ["costa1", "azurana"], ["porto", "costa2"], ["costa2", "quartzo"],
  ["porto", "rota1"], ["rota1", "pallet"], ["porto", "rota2"], ["rota2", "argila"], ["argila", "rota3"], ["rota3", "verdelume"],
  ["verdelume", "rota4"], ["rota4", "carmesim"], ["carmesim", "rota5"], ["rota5", "porto"], ["porto", "rota6"], ["rota6", "ametista"],
  ["ametista", "vale"], ["ametista", "rota10"], ["rota10", "obsidiana"], ["obsidiana", "gruta"], ["gruta", "cromatica"], ["cromatica", "plato"],
  ["obsidiana", "rota9"], ["rota9", "ambar"], ["ambar", "rota8"], ["rota8", "quartzo"], ["quartzo", "rota7a"], ["rota7a", "azurana"], ["quartzo", "reserva"],
];
const NS = "http://www.w3.org/2000/svg";
const svg = (tag: string, attrs: Record<string, string | number>, ...filhos: (SVGElement | string)[]) => {
  const n = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, String(v));
  for (const f of filhos) n.append(f);
  return n as SVGElement;
};

/** Abre o Mapa Mundi dentro do modal. `viajar` devolve true se a viagem foi feita. */
export async function abrirMapaMundi(
  modal: { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void },
  viajar: (mapa: string) => Promise<boolean>,
  aviso: (t: string) => void,
): Promise<void> {
  const { data, error } = await supabase.rpc("mapa_mundi");
  if (error || !data) { aviso(error?.message ?? "Não foi possível abrir o Mapa Mundi."); return; }
  const info = data as { atual: string; mestre: boolean; insignias: number };
    const SX = 2.5, SY = 1.8;
  const porId = new Map(NOS.map((n) => [n.id, { ...n, x: n.x * SX, y: n.y * SY }]));
  let escolhido: string | null = null;

  const mapa = svg("svg", { viewBox: "-16 -14 376 232", class: "mm-svg", role: "img", "aria-label": "Mapa Mundi de Rafar" });
  for (const [a, b] of LIGACOES) {
    const A = porId.get(a)!, B = porId.get(b)!;
    mapa.append(svg("line", { x1: A.x, y1: A.y, x2: B.x, y2: B.y, class: "mm-via aberta" }));
  }
  const rotulo = el("div", { class: "mm-info" }, "Toque em um lugar para escolher o destino.");
  const ir = el("button", { type: "button", disabled: "" }, "Viajar") as HTMLButtonElement;
  const nodos = new Map<string, SVGElement>();
  const pintar = () => {
    for (const [id, g] of nodos) {
      g.classList.toggle("sel", id === escolhido);
    }
  };
  for (const n of porId.values()) {
    const ok = true;
    const r = n.t === "cidade" ? 5.5 : n.t === "local" ? 4.6 : 3.4;
    const g = svg("g", { class: `mm-no ${n.t}${ok ? " livre" : " trancado"}${n.id === info.atual ? " atual" : ""}`, tabindex: "0", role: "button", "aria-label": n.nome });
    g.append(svg("circle", { cx: n.x, cy: n.y, r: r + 2.4, class: "mm-hit" }), svg("circle", { cx: n.x, cy: n.y, r, class: "mm-ponto" }));
    g.append(svg("text", { x: n.x, y: n.t === "cidade" || n.id === "reserva" ? n.y + r + 8 : n.y - r - 2.5, "text-anchor": "middle", class: n.t === "rota" ? "mm-nome pequeno" : "mm-nome" }, n.t === "rota" ? n.nome.replace("Rota ", "R") : n.nome));
    const escolher = () => {
      escolhido = n.id;
      pintar();
      if (n.id === info.atual) { rotulo.textContent = `Você está em ${n.nome}.`; ir.disabled = true; }
      else if (n.id === "plato" && !info.mestre && info.insignias < 8) { rotulo.textContent = `${n.nome}: só abre com 8 insígnias (você tem ${info.insignias}).`; ir.disabled = true; }
      else { rotulo.textContent = `Destino: ${n.nome}`; ir.disabled = false; ir.removeAttribute("disabled"); ir.textContent = `Viajar para ${n.nome}`; }
    };
    g.addEventListener("click", escolher);
    g.addEventListener("keydown", (e) => { if ((e as KeyboardEvent).key === "Enter" || (e as KeyboardEvent).key === " ") { e.preventDefault(); escolher(); } });
    nodos.set(n.id, g);
    mapa.append(g);
  }
  ir.addEventListener("click", async () => {
    if (!escolhido) return;
    ir.disabled = true;
    const alvo = escolhido;
    modal.fechar();
    await viajar(alvo);
  });
  const legenda = el("div", { class: "mm-legenda" },
    el("span", { class: "mm-leg atual" }, "Você"), el("span", { class: "mm-leg livre" }, "Destino"), el("span", { class: "mm-leg cid" }, "Cidade"));
  nodos.get(info.atual)?.classList.add("atual");
  const aqui = porId.get(info.atual);
  if (aqui) rotulo.textContent = `Você está em ${aqui.nome}. Toque em um lugar para viajar.`;
  modal.abrir("Mapa Mundi", el("div", { class: "mm-topo" }, rotulo, ir), el("div", { class: "mm-caixa" }, mapa as unknown as Node), legenda);
}
