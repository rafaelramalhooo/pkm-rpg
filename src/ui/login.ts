import { supabase } from "../supabase";
import { el, montar, mensagem } from "./dom";

function marcaPainel(): HTMLElement {
  return el("img", { class: "logo-rafar", src: `${import.meta.env.BASE_URL}assets/logo-rafar.png`, alt: "Rafar: Um novo começo" });
}

export function telaLogin(): void {
  const email = el("input", { type: "email", id: "email", autocomplete: "username", required: "" });
  const senha = el("input", { type: "password", id: "senha", autocomplete: "current-password", required: "" });
  const msg = el("p", { class: "msg", role: "status" });
  const entrar = el("button", { type: "submit" }, "Entrar");

  const form = el(
    "form",
    {},
    el("label", { for: "email" }, "E-mail"),
    email,
    el("label", { for: "senha" }, "Senha"),
    senha,
    entrar,
    msg,
  );

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    entrar.disabled = true;
    mensagem(msg, "Entrando...", "ok");
    const { error } = await supabase.auth.signInWithPassword({
      email: email.value.trim(),
      password: senha.value,
    });
    if (error) {
      entrar.disabled = false;
      mensagem(msg, "E-mail ou senha incorretos.");
    }
    // Em caso de sucesso, o roteador em main.ts troca a tela.
  });

  montar([
    el(
      "div",
      { class: "painel painel-hub" },
      marcaPainel(),
      el("h1", {}, "Entrar na aventura"),
      el("p", { class: "sub" }, "Acesso só por convite do Mestre."),
      form,
    ),
  ]);
}
