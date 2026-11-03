import { supabase, type Jogador } from "../supabase";
import { el, montar, mensagem } from "./dom";

const APARENCIAS = [
  { nome: "Camisa vermelha", cor: "#c04040" },
  { nome: "Camisa azul", cor: "#3f6fd0" },
  { nome: "Camisa verde", cor: "#3f9a4f" },
  { nome: "Camisa amarela", cor: "#d8b030" },
];

export function telaPersonagem(aoCriar: (j: Jogador) => void): void {
  let escolhida = 0;
  const nome = el("input", { type: "text", id: "nome", maxlength: "12", autocomplete: "off", required: "" });
  const msg = el("p", { class: "msg", role: "status" });
  const criar = el("button", { type: "submit" }, "Começar a aventura");

  const botoes = APARENCIAS.map((a, i) => {
    const b = el("button", { type: "button", "aria-label": a.nome, title: a.nome, "aria-pressed": String(i === 0) });
    b.style.background = a.cor;
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
      { class: "painel" },
      el("h1", {}, "Novo treinador"),
      el("p", { class: "sub" }, "Você começa em Pallet Town."),
      form,
    ),
  ]);
}
