import { supabase, type Jogador } from "../supabase";
import { aoTrocarTela, el, geracaoAtual, mensagem, montar } from "./dom";
import type { Controle, Ganchos, Poi } from "../game/mundo";

function criarMenu(j: Jogador, fechar: () => void, aoReporPA: () => void): HTMLElement {
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

  const filhos: Node[] = [];
  const titulo = el("h1", {});
  titulo.textContent = j.nome;
  filhos.push(titulo, el("p", { class: "sub" }, j.papel === "mestre" ? "Mestre" : "Treinador"));

  if (j.papel === "mestre") {
    const msgPA = el("p", { class: "msg", role: "status" });
    const repor = (todos: boolean) => async () => {
      const { data, error } = await supabase.rpc("repor_pa", { p_todos: todos });
      if (error) mensagem(msgPA, error.message);
      else {
        mensagem(msgPA, `PA repostos (${String(data)} jogador${data === 1 ? "" : "es"}).`, "ok");
        aoReporPA();
      }
    };
    const meus = el("button", { type: "button", class: "sec" }, "Repor meus PA");
    const todos = el("button", { type: "button", class: "sec" }, "Repor PA de todos");
    meus.addEventListener("click", () => void repor(false)());
    todos.addEventListener("click", () => void repor(true)());
    filhos.push(el("label", {}, "Mestre"), meus, todos, msgPA);
  }

  filhos.push(form, voltar, sair);
  return el("div", { class: "menu", hidden: "" }, el("div", { class: "painel" }, ...filhos));
}

function criarPainelPoi(): { painel: HTMLElement; abrir: (p: Poi) => void } {
  const titulo = el("h1", {});
  const texto = el("p", { class: "sub" });
  const fechar = el("button", { type: "button", class: "sec" }, "Fechar");
  const painel = el("div", { class: "menu", hidden: "" }, el("div", { class: "painel" }, titulo, texto, fechar));
  fechar.addEventListener("click", () => {
    painel.hidden = true;
  });
  return {
    painel,
    abrir: (p) => {
      titulo.textContent = p.nome;
      texto.textContent = p.descricao;
      painel.hidden = false;
    },
  };
}

export async function telaJogo(j: Jogador): Promise<void> {
  let controle: Controle | null = null;

  const tela = el("div", { class: "tela-jogo" });
  const aviso = el("div", { class: "aviso", role: "status", hidden: "" });
  tela.append(aviso);
  let temporizador: number | undefined;
  const mostrarAviso = (texto: string) => {
    aviso.textContent = texto;
    aviso.hidden = false;
    window.clearTimeout(temporizador);
    temporizador = window.setTimeout(() => {
      aviso.hidden = true;
    }, 2800);
  };

  const dica = el("p", { class: "dica" }, "Arraste o mapa. Toque num hexágono vizinho para andar; o número é o custo em PA.");
  const botaoMenu = el("button", { type: "button", class: "sec botao-menu" }, "Menu");
  const menos = el("button", { type: "button", class: "sec botao-menu", "aria-label": "Diminuir zoom" }, "−");
  const mais = el("button", { type: "button", class: "sec botao-menu", "aria-label": "Aumentar zoom" }, "+");
  const alvo = el("button", { type: "button", class: "sec botao-menu", "aria-label": "Centralizar em mim" }, "⌖");
  menos.addEventListener("click", () => controle?.zoom(0.8));
  mais.addEventListener("click", () => controle?.zoom(1.25));
  alvo.addEventListener("click", () => controle?.centralizar());

  const pa = el("span", { class: "pa" });
  pa.textContent = `PA ${j.pa}`;
  const nome = el("span", { class: "nome-jogador" });
  nome.textContent = j.nome;

  const menu = criarMenu(
    j,
    () => {
      menu.hidden = true;
    },
    () => void controle?.atualizarPA(),
  );
  botaoMenu.addEventListener("click", () => {
    menu.hidden = !menu.hidden;
  });
  const poi = criarPainelPoi();

  const esquerda = el("div", { class: "grupo" }, botaoMenu, menos, mais, alvo);
  const direita = el("div", { class: "grupo" }, pa, nome);
  const barra = el("div", { class: "barra" }, esquerda, direita);
  const minha = montar([el("div", { class: "jogo" }, el("div", { class: "cartucho" }, barra, tela), dica, menu, poi.painel)], true);

  const ganchos: Ganchos = {
    aoPA: (valor, max) => {
      pa.textContent = `PA ${valor}/${max}`;
      pa.classList.toggle("zerado", valor === 0);
    },
    aoPoi: poi.abrir,
    aviso: mostrarAviso,
  };

  const { iniciarMundo } = await import("../game/mundo");
  if (minha !== geracaoAtual()) return; // a tela mudou enquanto o jogo carregava
  let iniciado: Controle;
  try {
    iniciado = await iniciarMundo(tela, j, ganchos);
  } catch (e) {
    mostrarAviso(e instanceof Error ? e.message : "Não foi possível abrir o jogo.");
    return;
  }
  if (minha !== geracaoAtual()) {
    iniciado.encerrar();
    return;
  }
  controle = iniciado;
  aoTrocarTela(iniciado.encerrar);
}
