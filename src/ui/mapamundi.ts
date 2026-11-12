import { supabase } from "../supabase";
import { el } from "./dom";

type No = { id: string; nome: string; x: number; y: number; t: "cidade" | "rota" | "local" };

/** Mapa Mundi de Rafar (layout fixo, posições conforme a ilustração do mundo, em pixels da imagem 1024×1536; as ligações seguem os portais reais). */
const NOS: No[] = [
  { id: "porto", nome: "Porto Turquesa", x: 516, y: 785, t: "cidade" },
  { id: "rota1", nome: "Rota 1", x: 520, y: 1030, t: "rota" },
  { id: "pallet", nome: "Vila Alvorada", x: 521, y: 1261, t: "cidade" },
  { id: "caminho_va", nome: "Vaga-Lume", x: 385, y: 715, t: "local" },
  { id: "verdelume", nome: "Verdelume", x: 240, y: 632, t: "cidade" },
  { id: "rota2", nome: "Rota 2", x: 345, y: 810, t: "rota" },
  { id: "argila", nome: "Argila", x: 190, y: 806, t: "cidade" },
  { id: "rota3", nome: "Rota 3", x: 205, y: 720, t: "rota" },
  { id: "rota4", nome: "Rota 4", x: 255, y: 545, t: "rota" },
  { id: "carmesim", nome: "Carmesim", x: 270, y: 462, t: "cidade" },
  { id: "rota5", nome: "Rota 5", x: 410, y: 590, t: "rota" },
  { id: "costa1", nome: "Costa Azul", x: 690, y: 800, t: "local" },
  { id: "azurana", nome: "Azurana", x: 856, y: 839, t: "cidade" },
  { id: "costa2", nome: "Costa Rosada", x: 585, y: 705, t: "local" },
  { id: "quartzo", nome: "Quartzo Rosa", x: 664, y: 632, t: "cidade" },
  { id: "rota7a", nome: "Rota 7", x: 790, y: 740, t: "rota" },
  { id: "rota8", nome: "Rota 8", x: 730, y: 480, t: "rota" },
  { id: "reserva", nome: "Reserva", x: 867, y: 570, t: "local" },
  { id: "rota6", nome: "Rota 6", x: 455, y: 470, t: "rota" },
  { id: "ametista", nome: "Ametista", x: 394, y: 354, t: "cidade" },
  { id: "vale", nome: "Vale Cinzento", x: 470, y: 290, t: "local" },
  { id: "rota10", nome: "Rota 10", x: 505, y: 340, t: "rota" },
  { id: "obsidiana", nome: "Obsidiana", x: 617, y: 302, t: "cidade" },
  { id: "rota9", nome: "Rota 9", x: 705, y: 345, t: "rota" },
  { id: "ambar", nome: "Âmbar", x: 772, y: 364, t: "cidade" },
  { id: "gruta", nome: "Gruta", x: 697, y: 205, t: "local" },
  { id: "cromatica", nome: "Cromática", x: 625, y: 165, t: "local" },
  { id: "plato", nome: "Platô (Liga)", x: 548, y: 112, t: "local" },
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
  missao: { mapa_id: string; mapa_nome: string; nome: string; objetivo: string } | null = null,
): Promise<void> {
  const { data, error } = await supabase.rpc("mapa_mundi");
  if (error || !data) { aviso(error?.message ?? "Não foi possível abrir o Mapa Mundi."); return; }
  const info = data as { atual: string; mestre: boolean; insignias: number };
    const SX = 0.4, SY = 0.4;
  const porId = new Map(NOS.map((n) => [n.id, { ...n, x: n.x * SX, y: n.y * SY }]));
  let escolhido: string | null = null;

  const mapa = svg("svg", { viewBox: "0 0 410 615", class: "mm-svg", role: "img", "aria-label": "Mapa Mundi de Rafar" });
  // fundo: ilustração do mundo de Rafar (as posições dos lugares seguem os pixels da imagem 1024×1536, escala 0,4)
  mapa.append(svg("image", { href: `${import.meta.env.BASE_URL}assets/mapamundi.jpg`, x: 0, y: 0, width: 409.6, height: 614.4, preserveAspectRatio: "none", class: "mm-fundo" }));
  for (const [a, b] of LIGACOES) {
    const A = porId.get(a)!, B = porId.get(b)!;
    mapa.append(svg("line", { x1: A.x, y1: A.y, x2: B.x, y2: B.y, class: "mm-via-sombra" }));
  }
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
    if (n.id === "pallet" || n.id === "plato") {
      const R1 = 10.5, R2 = 4.6; const pts: string[] = [];
      for (let k = 0; k < 10; k++) { const ang = -Math.PI / 2 + (k * Math.PI) / 5; const rr = k % 2 ? R2 : R1; pts.push(`${(n.x + rr * Math.cos(ang)).toFixed(1)},${(n.y + rr * Math.sin(ang)).toFixed(1)}`); }
      g.append(svg("polygon", { points: pts.join(" "), class: `mm-estrela ${n.id === "pallet" ? "inicio" : "liga"}` }));
    }
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
    el("span", { class: "mm-leg atual" }, "Você"), el("span", { class: "mm-leg livre" }, "Destino"), el("span", { class: "mm-leg cid" }, "Cidade"), el("span", { class: "mm-leg est inicio" }, "★ Início"), el("span", { class: "mm-leg est liga" }, "★ Liga"));
  nodos.get(info.atual)?.classList.add("atual");
  if (missao) {
    const alvo = porId.get(missao.mapa_id);
    if (alvo) {
      const pino = svg("g", { class: "mm-missao", transform: `translate(${alvo.x} ${alvo.y - 12})` },
        svg("circle", { r: 7.5, class: "mm-missao-aura" }), svg("circle", { r: 5.4, class: "mm-missao-ponto" }), svg("text", { y: 3, "text-anchor": "middle", class: "mm-missao-txt" }, "!"));
      mapa.append(pino);
    }
  }
  const aqui = porId.get(info.atual);
  if (aqui) rotulo.textContent = `Você está em ${aqui.nome}. Toque em um lugar para viajar.`;
  // ---- zoom e arrastar (botões, roda do mouse, arrastar e pinça no celular) ----
  const W0 = 410, H0 = 615, ZMAX = 4;
  let z = 1, cx = W0 / 2, cy = H0 / 2;
  const aplicar = () => {
    const w = W0 / z, h = H0 / z;
    cx = Math.min(W0 - w / 2, Math.max(w / 2, cx)); cy = Math.min(H0 - h / 2, Math.max(h / 2, cy));
    mapa.setAttribute("viewBox", `${cx - w / 2} ${cy - h / 2} ${w} ${h}`);
    mapa.style.touchAction = z > 1 ? "none" : "pan-y";
    mapa.classList.toggle("mm-ampliado", z > 1);
    pct.textContent = `${Math.round(z * 100)}%`;
  };
  const noPonto = (clientX: number, clientY: number) => {
    const r = mapa.getBoundingClientRect(); const w = W0 / z, h = H0 / z;
    const esc = Math.min(r.width / w, r.height / h); // preserveAspectRatio "meet"
    const ox = r.left + (r.width - w * esc) / 2, oy = r.top + (r.height - h * esc) / 2;
    return { x: cx - w / 2 + (clientX - ox) / esc, y: cy - h / 2 + (clientY - oy) / esc, esc };
  };
  const zoomar = (novo: number, clientX?: number, clientY?: number) => {
    novo = Math.min(ZMAX, Math.max(1, novo));
    const r = mapa.getBoundingClientRect();
    const px = clientX ?? r.left + r.width / 2, py = clientY ?? r.top + r.height / 2;
    const antes = noPonto(px, py);
    z = novo;
    const depois = noPonto(px, py);
    cx += antes.x - depois.x; cy += antes.y - depois.y;
    aplicar();
  };
  const pct = el("span", { class: "mm-zoom-pct" }, "100%");
  const bt = (t: string, titulo: string, f: () => void) => { const b = el("button", { type: "button", class: "mm-zbtn", title: titulo, "aria-label": titulo }, t) as HTMLButtonElement; b.addEventListener("click", f); return b; };
  const controles = el("div", { class: "mm-zoom" }, bt("+", "Aproximar", () => zoomar(z * 1.5)), pct, bt("−", "Afastar", () => zoomar(z / 1.5)), bt("⟲", "Voltar ao tamanho inicial", () => { z = 1; cx = W0 / 2; cy = H0 / 2; aplicar(); }));
  mapa.addEventListener("wheel", (e) => { e.preventDefault(); zoomar(z * (e.deltaY < 0 ? 1.2 : 1 / 1.2), e.clientX, e.clientY); }, { passive: false });
  const dedos = new Map<number, { x: number; y: number }>();
  let moveu = false, distAntes = 0;
  mapa.addEventListener("pointerdown", (e) => { dedos.set(e.pointerId, { x: e.clientX, y: e.clientY }); moveu = false; distAntes = 0; });
  mapa.addEventListener("pointermove", (e) => {
    const d = dedos.get(e.pointerId); if (!d) return;
    if (dedos.size === 2) {
      dedos.set(e.pointerId, { x: e.clientX, y: e.clientY });
      const [a, b] = [...dedos.values()];
      const dist = Math.hypot(a.x - b.x, a.y - b.y);
      if (distAntes) zoomar(z * (dist / distAntes), (a.x + b.x) / 2, (a.y + b.y) / 2);
      distAntes = dist; moveu = true; return;
    }
    if (z <= 1) return;
    const dx = e.clientX - d.x, dy = e.clientY - d.y;
    if (!moveu && Math.hypot(dx, dy) < 5) return;
    moveu = true;
    const esc = noPonto(0, 0).esc;
    cx -= dx / esc; cy -= dy / esc;
    dedos.set(e.pointerId, { x: e.clientX, y: e.clientY });
    aplicar();
  });
  const soltar = (e: PointerEvent) => { dedos.delete(e.pointerId); distAntes = 0; };
  mapa.addEventListener("pointerup", soltar); mapa.addEventListener("pointercancel", soltar); mapa.addEventListener("pointerleave", soltar);
  // depois de arrastar/pinçar, o clique não escolhe destino sem querer
  mapa.addEventListener("click", (e) => { if (moveu) { e.stopPropagation(); e.preventDefault(); moveu = false; } }, true);
  const caixa = el("div", { class: "mm-caixa" }, mapa as unknown as Node, controles);
  aplicar();
  modal.abrir("Mapa Mundi", ...(missao ? [el("div", { class: "mm-missao-info" }, el("strong", {}, `Missão: ${missao.nome}`), el("span", {}, `${missao.objetivo} (${missao.mapa_nome})`))] : []), el("div", { class: "mm-topo" }, rotulo, ir), caixa, legenda);
}
