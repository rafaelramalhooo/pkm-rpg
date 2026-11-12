// Aviso de nova versão: consulta version.json (gerado a cada publicação) e oferece recarregar o jogo.
declare const __BUILD__: string;
const BASE = import.meta.env.BASE_URL as string;
const A_CADA_MS = 90_000;

let faixa: HTMLElement | null = null;

async function conferir(): Promise<void> {
  if (faixa) return;
  try {
    const r = await fetch(`${BASE}version.json?t=${Date.now()}`, { cache: "no-store" });
    if (!r.ok) return;
    const { build } = (await r.json()) as { build?: string };
    if (build && build !== __BUILD__) mostrar();
  } catch { /* sem rede: tenta de novo mais tarde */ }
}

function mostrar(): void {
  faixa = document.createElement("div");
  faixa.className = "nova-versao";
  faixa.setAttribute("role", "status");
  const txt = document.createElement("span");
  txt.textContent = "Nova versão do jogo disponível!";
  const b = document.createElement("button");
  b.type = "button";
  b.textContent = "Atualizar agora";
  b.addEventListener("click", () => location.reload());
  const x = document.createElement("button");
  x.type = "button";
  x.className = "nv-fechar";
  x.setAttribute("aria-label", "Depois");
  x.textContent = "Depois";
  x.addEventListener("click", () => { faixa?.remove(); window.setTimeout(() => { faixa = null; }, 10 * 60_000); });
  faixa.append(txt, b, x);
  document.body.append(faixa);
}

export function vigiarVersao(): void {
  if (!/^\d+$/.test(__BUILD__)) return;
  window.setTimeout(() => void conferir(), 20_000);
  window.setInterval(() => void conferir(), A_CADA_MS);
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") void conferir(); });
}
