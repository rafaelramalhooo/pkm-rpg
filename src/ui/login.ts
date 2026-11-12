import { supabase } from "../supabase";
import { el, montar, mensagem } from "./dom";

function marcaPainel(): HTMLElement {
  return el("img", { class: "logo-rafar", src: `${import.meta.env.BASE_URL}assets/logo-rafar.png`, alt: "Rafar: Um novo começo" });
}

const URL_VOLTA = (): string => `${window.location.origin}${import.meta.env.BASE_URL}`;

type Modo = "entrar" | "criar" | "esqueci";

export function telaLogin(modo: Modo = "entrar"): void {
  const email = el("input", { type: "email", id: "email", autocomplete: "username", required: "" });
  const senha = el("input", { type: "password", id: "senha", autocomplete: modo === "criar" ? "new-password" : "current-password", minlength: modo === "criar" ? "8" : "1" });
  if (modo !== "esqueci") senha.setAttribute("required", "");
  const msg = el("p", { class: "msg", role: "status" });
  const envio = el("button", { type: "submit" }, modo === "entrar" ? "Entrar" : modo === "criar" ? "Criar conta" : "Enviar link de recuperação");
  const troca = (rotulo: string, para: Modo): HTMLElement => {
    const b = el("button", { type: "button", class: "link" }, rotulo);
    b.addEventListener("click", () => telaLogin(para));
    return b;
  };

  const campos: Node[] = [el("label", { for: "email" }, "E-mail"), email];
  if (modo !== "esqueci") campos.push(el("label", { for: "senha" }, modo === "criar" ? "Senha (mínimo 8 caracteres)" : "Senha"), senha);
  const form = el("form", {}, ...campos, envio, msg);

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    envio.disabled = true;
    if (modo === "entrar") {
      mensagem(msg, "Entrando...", "ok");
      const { error } = await supabase.auth.signInWithPassword({ email: email.value.trim(), password: senha.value });
      if (error) { envio.disabled = false; mensagem(msg, "E-mail ou senha incorretos."); }
      // Em caso de sucesso, o roteador em main.ts troca a tela.
    } else if (modo === "criar") {
      mensagem(msg, "Criando sua conta...", "ok");
      const { data, error } = await supabase.auth.signUp({ email: email.value.trim(), password: senha.value, options: { emailRedirectTo: URL_VOLTA() } });
      if (error) { envio.disabled = false; mensagem(msg, error.message.includes("registered") ? "Este e-mail já tem conta. Use Entrar ou Esqueci a senha." : `Não foi possível criar a conta: ${error.message}`); return; }
      if (!data.session) { envio.disabled = false; mensagem(msg, "Conta criada! Confirme pelo link enviado ao seu e-mail e depois entre.", "ok"); }
      // com sessão (sem confirmação por e-mail), o roteador abre a criação do personagem
    } else {
      mensagem(msg, "Enviando...", "ok");
      const { error } = await supabase.auth.resetPasswordForEmail(email.value.trim(), { redirectTo: URL_VOLTA() });
      envio.disabled = false;
      if (error) mensagem(msg, `Não foi possível enviar: ${error.message}`);
      else mensagem(msg, "Se o e-mail estiver cadastrado, você receberá um link para criar uma nova senha.", "ok");
    }
  });

  const rodape = el("div", { class: "login-links" },
    ...(modo === "entrar" ? [troca("Criar conta", "criar"), troca("Esqueci a senha", "esqueci")] : [troca("← Voltar para Entrar", "entrar")]));
  montar([
    el("div", { class: "painel painel-hub" }, marcaPainel(),
      el("h1", {}, modo === "entrar" ? "Entrar na aventura" : modo === "criar" ? "Criar conta" : "Recuperar senha"),
      form, rodape),
  ]);
}

/** Depois de abrir o link de recuperação: o jogador define a nova senha. */
export function telaNovaSenha(aoConcluir: () => void): void {
  const nova = el("input", { type: "password", id: "nova", autocomplete: "new-password", minlength: "8", required: "" });
  const msg = el("p", { class: "msg", role: "status" });
  const envio = el("button", { type: "submit" }, "Salvar nova senha");
  const form = el("form", {}, el("label", { for: "nova" }, "Nova senha (mínimo 8 caracteres)"), nova, envio, msg);
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    envio.disabled = true;
    const { error } = await supabase.auth.updateUser({ password: nova.value });
    if (error) { envio.disabled = false; return void mensagem(msg, `Não foi possível trocar: ${error.message}`); }
    mensagem(msg, "Senha alterada! Entrando...", "ok");
    window.setTimeout(aoConcluir, 700);
  });
  montar([el("div", { class: "painel painel-hub" }, marcaPainel(), el("h1", {}, "Nova senha"), el("p", { class: "sub" }, "Escolha uma senha nova para a sua conta."), form)]);
}
