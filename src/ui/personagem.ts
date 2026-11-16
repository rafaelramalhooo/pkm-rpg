import { supabase, type Jogador } from "../supabase";
import { el, montar, mensagem } from "./dom";

const BASE = import.meta.env.BASE_URL as string;
const TOTAL_SPRITES = 49;
const APARENCIAS_PADRAO = Array.from({ length: 12 }, (_, i) => i);

/** Aparências que o servidor libera para jogadores (config.aparencias_jogador); sem a lista, só as 12 originais. */
export async function aparenciasLiberadas(): Promise<number[]> {
  try {
    const { data } = await supabase.from("config").select("valor").eq("chave", "aparencias_jogador").maybeSingle();
    const v = (data as { valor?: unknown } | null)?.valor;
    if (Array.isArray(v)) {
      const lista = v.map(Number).filter((n) => Number.isInteger(n) && n >= 0 && n < TOTAL_SPRITES);
      if (lista.length) return lista;
    }
  } catch { /* usa a lista padrão */ }
  return APARENCIAS_PADRAO;
}

/** Preenche a grade de botões de aparência; chama aoEscolher com o número escolhido (a 1ª da lista já vem marcada). */
export function preencherGrade(grade: HTMLElement, lista: number[], aoEscolher: (n: number) => void): void {
  grade.classList.add("aparencias-rolavel");
  const botoes = lista.map((n, k) => {
    const b = el("button", { type: "button", class: "aparencia", "aria-label": `Visual ${k + 1}`, title: `Visual ${k + 1}`, "aria-pressed": String(k === 0) });
    b.style.backgroundImage = `url(${BASE}assets/personagens/p${n}.png)`;
    b.addEventListener("click", () => {
      aoEscolher(n);
      botoes.forEach((x, j) => x.setAttribute("aria-pressed", String(j === k)));
    });
    return b;
  });
  grade.replaceChildren(...botoes);
  if (lista.length) aoEscolher(lista[0]);
}

function marcaPainel(): HTMLElement {
  return el("img", { class: "logo-rafar", src: `${BASE}assets/logo-rafar.png`, alt: "Rafar: Um novo começo" });
}

export function telaPersonagem(aoCriar: (j: Jogador) => void): void {
  let escolhida = 0;
  const nome = el("input", { type: "text", id: "nome", maxlength: "12", autocomplete: "off", required: "" });
  const msg = el("p", { class: "msg", role: "status" });
  const criar = el("button", { type: "submit" }, "Começar a aventura");

  const grade = el("div", { class: "aparencias" });
  void aparenciasLiberadas().then((lista) => preencherGrade(grade, lista, (n) => { escolhida = n; }));

  const form = el(
    "form",
    {},
    el("label", { for: "nome" }, "Nome do treinador (2 a 12 letras)"),
    nome,
    el("label", {}, "Aparência"),
    grade,
    criar,
    msg,
  );

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    criar.disabled = true;
    mensagem(msg, "Criando personagem...", "ok");
    const { data, error } = await supabase.rpc("criar_personagem", {
      p_nome: nome.value,
      p_aparencia: escolhida,
    });
    if (error || !data) {
      criar.disabled = false;
      mensagem(msg, error?.message ?? "Não foi possível criar o personagem.");
      return;
    }
    aoCriar(data as Jogador);
  });

  montar([
    el(
      "div",
      { class: "painel painel-hub" },
      marcaPainel(),
      el("h1", {}, "Novo treinador"),
      el("p", { class: "sub" }, "Você começa dentro do Laboratório do Professor Carvalho."),
      form,
    ),
  ]);
}
