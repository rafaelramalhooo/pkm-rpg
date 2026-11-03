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

export function montar(...nos: Node[]): void {
  const app = document.getElementById("app")!;
  app.replaceChildren(...nos);
}

export function mensagem(alvo: HTMLElement, texto: string, tipo: "erro" | "ok" = "erro"): void {
  alvo.textContent = texto;
  alvo.className = `msg ${tipo}`;
}
