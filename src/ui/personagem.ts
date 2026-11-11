import { supabase, type Jogador } from "../supabase";
import { el, montar, mensagem } from "./dom";

const BASE = import.meta.env.BASE_URL as string;
const TOTAL_APARENCIAS = 12;

function marcaPainel(): HTMLElement {
  return el("div", { class: "marca marca-grande" }, el("span", { class: "marca-logo", "aria-hidden": "true" }, el("i", {})), el("span", { class: "marca-nome" }, "PKM RPG"));
}

export function telaPersonagem(aoCriar: (j: Jogador) => void): void {
  let escolhida = 0;
  const nome = el("input", { type: "text", id: "nome", maxlength: "12", autocomplete: "off", required: "" });
  const msg = el("p", { class: "msg", role: "status" });
  const criar = el("button", { type: "submit" }, "Começar a aventura");

  const botoes = Array.from({ length: TOTAL_APARENCIAS }, (_, i) => {
    const b = el("button", { type: "button", class: "aparencia", "aria-label": `Visual ${i + 1}`, title: `Visual ${i + 1}`, "aria-pressed": String(i === 0) });
    b.style.backgroundImage = `url(${BASE}assets/personagens/p${i}.png)`;
    b.addEventListener("click", () => {
      escolhida = i;
      botoes.forEach((x, j) => x.setAttribute("aria-pressed", String(j === i)));
    });
    return b;
  });

  const form = el(
    "form",
    {},
    el("label", { for: "nome" }, "Nome do treinador (2 a 12 letras)"),
    nome,
    el("label", {}, "Aparência"),
    el("div", { class: "aparencias" }, ...botoes),
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
      el("p", { class: "sub" }, "Você começa em Pallet Town."),
      form,
    ),
  ]);
}
