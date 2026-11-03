import { supabase, type Direcao, type Jogador } from "../supabase";
import { aoTrocarTela, el, geracaoAtual, mensagem, montar } from "./dom";
import type { Entrada } from "../game/mundo";

const SETAS: { dir: Direcao; rotulo: string; area: string }[] = [
  { dir: "cima", rotulo: "▲", area: "cima" },
  { dir: "esquerda", rotulo: "◀", area: "esq" },
  { dir: "direita", rotulo: "▶", area: "dir" },
  { dir: "baixo", rotulo: "▼", area: "baixo" },
];

function ligarSeta(botao: HTMLButtonElement, dir: Direcao, entrada: Entrada): void {
  botao.addEventListener("pointerdown", (ev) => {
    ev.preventDefault();
    botao.setPointerCapture(ev.pointerId);
    entrada.dir = dir;
  });
  const soltar = () => {
    if (entrada.dir === dir) entrada.dir = null;
  };
  botao.addEventListener("pointerup", soltar);
  botao.addEventListener("pointercancel", soltar);
  botao.addEventListener("contextmenu", (ev) => ev.preventDefault());
}

function criarMenu(j: Jogador, fechar: () => void): HTMLElement {
  const msg = el("p", { class: "msg", role: "status" });
  const novaSenha = el("input", { type: "password", id: "nova", autocomplete: "new-password", minlength: "8" });
  const trocar = el("button", { type: "submit", class: "sec" }, "Trocar senha");
  const sair = el("button", { type: "button" }, "Sair");
  const voltar = el("button", { type: "button", class: "sec" }, "Voltar ao jogo");
  sair.addEventListener("click", () => void supabase.auth.signOut());
  voltar.addEventListener("click", fechar);

  const form = el("form", {}, el("label", { for: "nova" }, "Nova senha (mín. 8 caracteres)"), novaSenha, trocar, msg);
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
  titulo.textContent = j.nome;
  return el(
    "div",
    { class: "menu", hidden: "" },
    el("div", { class: "painel" }, titulo, el("p", { class: "sub" }, j.papel === "mestre" ? "Mestre" : "Treinador"), form, voltar, sair),
  );
}

export async function telaJogo(j: Jogador): Promise<void> {
  const entrada: Entrada = { dir: null };

  const tela = el("div", { class: "tela-jogo" });
  const dica = el("p", { class: "dica" }, "Setas ou WASD para andar");
  const botaoMenu = el("button", { type: "button", class: "sec botao-menu" }, "Menu");
  const menu = criarMenu(j, () => {
    menu.hidden = true;
  });
  botaoMenu.addEventListener("click", () => {
    entrada.dir = null;
    menu.hidden = !menu.hidden;
  });

  const direcional = el("div", { class: "dpad" });
  for (const s of SETAS) {
    const b = el("button", { type: "button", class: "seta", "data-area": s.area, "aria-label": s.dir }, s.rotulo);
    ligarSeta(b, s.dir, entrada);
    direcional.append(b);
  }
  const controles = el("div", { class: "controles" }, direcional);

  const nome = el("span", { class: "nome-jogador" });
  nome.textContent = j.nome;
  const barra = el("div", { class: "barra" }, botaoMenu, nome);
  const minha = montar([el("div", { class: "jogo" }, el("div", { class: "cartucho" }, barra, tela), dica, controles, menu)], true);

  const { iniciarMundo } = await import("../game/mundo");
  if (minha !== geracaoAtual()) return; // a tela mudou enquanto o jogo carregava
  const controlesVisiveis = () => getComputedStyle(controles).display !== "none";
  const encerrar = iniciarMundo(tela, j, entrada, controlesVisiveis);
  aoTrocarTela(encerrar);
}
