// Caixa de diálogo estilo RPG: retrato, plaqueta de nome, texto digitado, páginas e "▼" para continuar.
import { el } from "./dom";

const BASE = import.meta.env.BASE_URL;
let aparenciaAtual: number | null = null;
/** Define quem está falando (aparência do NPC) para a próxima caixa de fala. */
export function definirFalante(aparencia: number | null | undefined): void { aparenciaAtual = typeof aparencia === "number" ? aparencia : null; }

/** Divide um texto longo em páginas curtas, quebrando em frases. */
function paginar(texto: string, max = 120): string[] {
  const frases = texto.replace(/^"|"$/g, "").match(/[^.!?…]+[.!?…]*\s*/g) ?? [texto];
  const paginas: string[] = [];
  let atual = "";
  for (const f of frases) {
    if (atual && (atual + f).length > max) { paginas.push(atual.trim()); atual = ""; }
    atual += f;
  }
  if (atual.trim()) paginas.push(atual.trim());
  return paginas.length ? paginas : [texto];
}

/**
 * Caixa de fala. `extras` (botões, avisos) só aparecem depois da última página,
 * como num RPG: o jogador lê, toca para avançar e então escolhe.
 */
export function caixaFala(titulo: string, texto: string, ...extras: Node[]): HTMLElement {
  const paginas = paginar(texto);
  const reduzido = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
  const retrato = el("div", { class: `fala-retrato${aparenciaAtual === null ? " sem" : ""}`, "aria-hidden": "true" });
  if (aparenciaAtual !== null) { retrato.classList.add("tc-emblema"); retrato.style.backgroundImage = `url(${BASE}assets/personagens/p${aparenciaAtual}.png)`; }
  else retrato.textContent = "💬";
  const [classe, ...resto] = titulo.split(" ");
  const nomeTxt = resto.length ? resto.join(" ") : titulo;
  const placa = el("div", { class: "fala-placa" }, el("strong", {}, nomeTxt), resto.length ? el("small", {}, classe) : "");
  const texto$ = el("p", { class: "fala-texto", "aria-live": "polite" });
  const seta = el("span", { class: "fala-seta", "aria-hidden": "true" }, "▼");
  const dica = el("small", { class: "fala-dica" }, "Toque para continuar");
  const corpo = el("div", { class: "fala-corpo", role: "button", tabindex: "0" }, placa, texto$, seta);
  const raiz = el("div", { class: "fala-rpg" }, retrato, corpo);
  const fim = el("div", { class: "fala-extras", hidden: "" }, ...extras);
  const pai = el("div", { class: "fala-wrap" }, raiz, dica, fim);

  let pag = 0, i = 0, timer = 0, digitando = false;
  const ultima = (): boolean => pag >= paginas.length - 1;
  const mostrarFim = (): void => { fim.hidden = false; dica.hidden = true; seta.style.visibility = "hidden"; };
  const terminarPagina = (): void => { window.clearInterval(timer); digitando = false; texto$.textContent = paginas[pag]; seta.style.visibility = ultima() ? "hidden" : "visible"; if (ultima()) mostrarFim(); };
  const digitar = (): void => {
    texto$.textContent = ""; i = 0; seta.style.visibility = "hidden";
    if (reduzido) return terminarPagina();
    digitando = true;
    timer = window.setInterval(() => { i++; texto$.textContent = paginas[pag].slice(0, i); if (i >= paginas[pag].length) terminarPagina(); }, 22);
  };
  const avancar = (): void => {
    if (digitando) return terminarPagina();
    if (!ultima()) { pag++; digitar(); }
  };
  corpo.addEventListener("click", avancar);
  corpo.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); avancar(); } });
  const obs = new MutationObserver(() => { if (!pai.isConnected) { window.clearInterval(timer); obs.disconnect(); } });
  queueMicrotask(() => { obs.observe(document.body, { childList: true, subtree: true }); digitar(); });
  return pai;
}
