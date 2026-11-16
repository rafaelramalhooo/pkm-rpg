import { supabase } from "../supabase";
import { el } from "./dom";

export interface AcaoAtalho { id: string; rotulo: string; grupo: string; fn: () => void; oculto?: boolean }

/** Barra com 10 atalhos (teclas 1–9 e 0), salva por conta. F1 mostra/oculta. */
export function criarAtalhos(
  jogadorId: string,
  acoes: () => AcaoAtalho[],
  escolher: (titulo: string, atual: string | null) => Promise<string | null | undefined>,
): { raiz: HTMLElement; executar: (n: number) => boolean; alternar: () => void } {
  const CHAVE = "pkm_atalhos_vis";
  let lista: (string | null)[] = Array.from({ length: 10 }, () => null);
  let visivel = true;
  try { const v = localStorage.getItem(CHAVE); visivel = v === null ? window.innerWidth > 700 : v === "1"; } catch { /* sem storage */ }
  let editando = false;
  const raiz = el("div", { class: "atalhos" });
  const slots = el("div", { class: "atalhos-slots" });
  const toggle = el("button", { type: "button", class: "atalhos-toggle", title: "Atalhos (F1)", "aria-label": "Mostrar ou ocultar atalhos" }, "⚡");
  const editar = el("button", { type: "button", class: "atalhos-edit", title: "Editar atalhos", "aria-label": "Editar atalhos" }, "✎");
  raiz.append(toggle, slots, editar);

  const achar = (id: string | null): AcaoAtalho | undefined => (id ? acoes().find((a) => a.id === id) : undefined);
  const salvar = (): void => { void supabase.rpc("atalhos_salvar", { p_atalhos: lista }); };
  const desenhar = (): void => {
    raiz.classList.toggle("oculta", !visivel);
    raiz.classList.toggle("editando", editando);
    slots.replaceChildren(...lista.map((id, i) => {
      const a = achar(id);
      const num = String((i + 1) % 10);
      const b = el("button", { type: "button", class: `atalho-slot${a ? " cheio" : ""}`, title: a ? `${a.rotulo} (tecla ${num})` : `Espaço ${num}: clique para escolher` }, el("i", {}, num), el("span", {}, a ? a.rotulo : "+"));
      b.addEventListener("click", async () => {
        if (a && !editando) { if (!a.oculto) a.fn(); return; }
        const r = await escolher(`Atalho da tecla ${num}`, id);
        if (r === undefined) return;
        lista[i] = r;
        salvar();
        desenhar();
      });
      return b;
    }));
  };
  const alternar = (): void => {
    visivel = !visivel;
    try { localStorage.setItem(CHAVE, visivel ? "1" : "0"); } catch { /* sem storage */ }
    desenhar();
  };
  toggle.addEventListener("click", alternar);
  editar.addEventListener("click", () => { editando = !editando; desenhar(); });
  desenhar();
  void supabase.from("jogadores").select("atalhos").eq("id", jogadorId).maybeSingle().then(({ data }) => {
    const a = (data as { atalhos?: unknown } | null)?.atalhos;
    if (Array.isArray(a)) { lista = Array.from({ length: 10 }, (_, i) => (typeof a[i] === "string" ? (a[i] as string) : null)); desenhar(); }
  });
  return {
    raiz,
    alternar,
    executar: (n: number): boolean => {
      const a = achar(lista[n]);
      if (!a || a.oculto) return false;
      a.fn();
      return true;
    },
  };
}
