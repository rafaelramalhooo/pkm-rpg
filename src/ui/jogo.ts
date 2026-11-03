import { supabase, type Jogador } from "../supabase";
import { el, montar, mensagem } from "./dom";

// Placeholder do M1a: o mapa e o movimento chegam no M1b.
export function telaJogo(j: Jogador): void {
  const msg = el("p", { class: "msg", role: "status" });
  const novaSenha = el("input", { type: "password", id: "nova", autocomplete: "new-password", minlength: "8" });

  const trocar = el("button", { type: "submit", class: "sec" }, "Trocar senha");
  const sair = el("button", { type: "button" }, "Sair");
  sair.addEventListener("click", () => void supabase.auth.signOut());

  const form = el(
    "form",
    {},
    el("label", { for: "nova" }, "Nova senha (mín. 8 caracteres)"),
    novaSenha,
    trocar,
    sair,
    msg,
  );
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    if (novaSenha.value.length < 8) {
      mensagem(msg, "A senha precisa ter ao menos 8 caracteres.");
      return;
    }
    const { error } = await supabase.auth.updateUser({ password: novaSenha.value });
    if (error) mensagem(msg, "Não foi possível trocar a senha.");
    else {
      novaSenha.value = "";
      mensagem(msg, "Senha trocada.", "ok");
    }
  });

  const titulo = el("h1", {});
  titulo.textContent = `Olá, ${j.nome}!`;
  montar(
    el(
      "div",
      { class: "painel" },
      titulo,
      el("p", { class: "sub" }, "Pallet Town ainda está em construção. O mapa chega na próxima etapa."),
      form,
    ),
  );
}
