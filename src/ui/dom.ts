// Ajudantes mínimos de DOM. Sempre textContent (nunca innerHTML) para texto vindo de usuários.
type Filho = Node | string;

export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Record<string, string> = {},
  ...filhos: Filho[]
): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  for (const f of filhos) e.append(f);
  return e;
}

let limpeza: (() => void) | null = null;
let geracao = 0;

/** Número da tela atual; muda a cada montar(). Serve para descartar trabalho assíncrono de telas antigas. */
export function geracaoAtual(): number {
  return geracao;
}

/** Registra algo a ser desfeito quando a tela atual for trocada (ex.: encerrar o jogo). */
export function aoTrocarTela(fn: () => void): void {
  limpeza = fn;
}

export function montar(nos: Node[], largo = false): number {
  limpeza?.();
  limpeza = null;
  const app = document.getElementById("app")!;
  app.className = largo ? "largo" : "";
  document.body.classList.toggle("modo-jogo", largo);
  app.replaceChildren(...nos);
  return ++geracao;
}

export function mensagem(alvo: HTMLElement, texto: string, tipo: "erro" | "ok" = "erro"): void {
  alvo.textContent = texto;
  alvo.className = `msg ${tipo}`;
}
