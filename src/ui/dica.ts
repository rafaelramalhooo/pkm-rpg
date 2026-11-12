// Caixinha explicativa de um golpe: aparece ao passar o mouse, ao tocar e segurar (celular) ou ao clicar.
import { golpe, NOME_TIPO, COR_TIPO, type GolpeInfo } from "./dados";

let caixa: HTMLElement | null = null;
let timerEsconder = 0;

function esconder(): void {
  window.clearTimeout(timerEsconder);
  caixa?.remove();
  caixa = null;
}

export function textoCategoria(c: string): string {
  return c === "physical" ? "Físico" : c === "special" ? "Especial" : "Status";
}

function mostrar(alvo: HTMLElement, g: GolpeInfo): void {
  esconder();
  const cor = COR_TIPO[g.tipo] ?? "#888";
  const chip = (t: string): HTMLElement => { const s = document.createElement("span"); s.textContent = t; return s; };
  const cab = document.createElement("div");
  cab.className = "dica-cab";
  const nome = document.createElement("strong");
  nome.textContent = g.nome;
  const tipo = chip(NOME_TIPO[g.tipo] ?? g.tipo);
  tipo.className = "dica-tipo";
  tipo.style.background = cor;
  cab.append(nome, tipo);
  const dados = document.createElement("div");
  dados.className = "dica-dados";
  dados.append(chip(textoCategoria(g.categoria)), chip(g.poder ? `Poder ${g.poder}` : "Sem dano direto"), chip(g.precisao ? `Precisão ${g.precisao}%` : "Não erra"), chip(`PP ${g.pp}`));
  if (g.prioridade) dados.append(chip(`Prioridade ${g.prioridade > 0 ? "+" : ""}${g.prioridade}`));
  const txt = document.createElement("p");
  txt.textContent = g.descricao || (g.poder ? "Causa dano ao alvo." : "Golpe de efeito.");
  caixa = document.createElement("div");
  caixa.className = "dica-golpe";
  caixa.style.borderColor = cor;
  caixa.append(cab, dados, txt);
  document.body.append(caixa);
  const r = alvo.getBoundingClientRect();
  const cw = caixa.offsetWidth, ch = caixa.offsetHeight;
  let x = Math.min(Math.max(8, r.left + r.width / 2 - cw / 2), window.innerWidth - cw - 8);
  let y = r.top - ch - 8;
  if (y < 8) y = Math.min(window.innerHeight - ch - 8, r.bottom + 8);
  caixa.style.left = `${x}px`;
  caixa.style.top = `${Math.max(8, y)}px`;
  x = 0;
  timerEsconder = window.setTimeout(esconder, 6000);
}

document.addEventListener("pointerdown", (e) => { if (caixa && !(e.target as HTMLElement).closest?.(".dica-golpe")) esconder(); }, true);

/** Liga a dica ao elemento. `clicar`: também abre ao clicar (para listas que não têm outra ação). */
export function dicaGolpe(alvo: HTMLElement, obter: () => GolpeInfo | undefined, clicar = false): void {
  let segurou = false;
  let timer = 0;
  const abrir = (): void => { const g = obter(); if (g) mostrar(alvo, g); };
  alvo.addEventListener("pointerenter", (e) => { if (e.pointerType === "mouse") abrir(); });
  alvo.addEventListener("pointerleave", (e) => { if (e.pointerType === "mouse") esconder(); });
  alvo.addEventListener("pointerdown", (e) => {
    if (e.pointerType === "mouse") return;
    segurou = false;
    window.clearTimeout(timer);
    timer = window.setTimeout(() => { segurou = true; abrir(); }, 450);
  });
  for (const ev of ["pointerup", "pointercancel", "pointermove"]) alvo.addEventListener(ev, () => window.clearTimeout(timer));
  alvo.addEventListener("contextmenu", (e) => { e.preventDefault(); abrir(); });
  alvo.addEventListener("click", (e) => {
    if (segurou) { segurou = false; e.stopImmediatePropagation(); e.preventDefault(); return; }
    if (clicar) abrir();
  }, true);
}

export const dicaPorId = (id: number) => (): GolpeInfo => golpe(id);
