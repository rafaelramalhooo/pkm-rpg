import { supabase, type Direcao, type Jogador } from "../supabase";
import { aoTrocarTela, el, geracaoAtual, mensagem, montar } from "./dom";
import type { Controle, Lugar, Poi } from "../game/mundo";
import { abrirBatalha, type ResultadoBatalha } from "./batalha";
import {
  barraHp, carregarReferencias, COR_TIPO, especie, golpe, imagemPokemon, meuTime, minhaMochila, NOME_TIPO, nomeItem,
  nomePokemon, todasEspecies, type PokemonRow,
} from "./dados";
import { importarDados, importarSprites } from "./mestre";

function botao(texto: string, fn: () => void, classe = "sec"): HTMLButtonElement {
  const b = el("button", { type: "button", class: classe }, texto);
  b.addEventListener("click", fn);
  return b;
}

/** Painel modal reutilizável. */
function criarModal(): { raiz: HTMLElement; abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void; aberto: () => boolean } {
  const titulo = el("h1", {});
  const corpo = el("div", { class: "modal-corpo" });
  const fechar = () => {
    raiz.hidden = true;
  };
  const raiz = el("div", { class: "menu", hidden: "" }, el("div", { class: "painel modal" }, titulo, corpo, botao("Fechar", fechar)));
  raiz.addEventListener("click", (e) => {
    if (e.target === raiz) fechar();
  });
  return {
    raiz,
    abrir: (t, ...nos) => {
      titulo.textContent = t;
      corpo.replaceChildren(...nos);
      raiz.hidden = false;
    },
    fechar,
    aberto: () => !raiz.hidden,
  };
}

export async function telaJogo(inicial: Jogador): Promise<void> {
  let j: Jogador = { ...inicial };
  let controle: Controle | null = null;
  let lugar: Lugar | null = null;
  let emBatalha = false;
  let poiAberto = "";
  let paMax = 30;

  const tela = el("div", { class: "tela-jogo" });
  const aviso = el("div", { class: "aviso", role: "status", hidden: "" });
  let temporizador: number | undefined;
  const mostrarAviso = (texto: string, ms = 3200) => {
    aviso.textContent = texto;
    aviso.hidden = false;
    window.clearTimeout(temporizador);
    temporizador = window.setTimeout(() => {
      aviso.hidden = true;
    }, ms);
  };

  // ---------- HUD ----------
  const pa = el("span", { class: "pa" });
  const dinheiro = el("span", { class: "dinheiro" });
  const onde = el("span", { class: "onde" });
  const atualizarHud = () => {
    pa.textContent = `PA ${j.pa}/${paMax}`;
    pa.classList.toggle("zerado", j.pa === 0);
    dinheiro.textContent = `₽ ${j.dinheiro ?? 0}`;
    onde.textContent = lugar ? lugar.nome_mapa : "";
  };
  atualizarHud();

  const modal = criarModal();

  // ---------- botões de ação sobre o mapa ----------
  const btnProcurar = el("button", { type: "button", class: "acao", hidden: "" }, "Procurar Pokémon (1 PA)");
  const btnInteragir = el("button", { type: "button", class: "acao", hidden: "" }, "Interagir");
  const acoes = el("div", { class: "acoes" }, btnProcurar, btnInteragir);

  const dpad = el("div", { class: "dpad", "aria-label": "Controles" });
  const dir = (d: Direcao, rot: string) => {
    const b = el("button", { type: "button", class: `d-${d}`, "aria-label": d }, rot);
    const soltar = () => controle?.segurar(null);
    b.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      controle?.segurar(d);
    });
    for (const ev of ["pointerup", "pointerleave", "pointercancel"]) b.addEventListener(ev, soltar);
    b.addEventListener("contextmenu", (e) => e.preventDefault());
    return b;
  };
  dpad.append(dir("cima", "▲"), dir("esquerda", "◀"), dir("direita", "▶"), dir("baixo", "▼"));
  tela.append(aviso, acoes, dpad);

  // ---------- painéis ----------
  const msgPainel = (): HTMLElement => el("p", { class: "msg", role: "status" });

  async function abrirTime(): Promise<void> {
    const time = await meuTime(j.id);
    if (time.length === 0) {
      modal.abrir("Seu time", el("p", { class: "sub" }, "Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório, em Pallet Town."));
      return;
    }
    modal.abrir("Seu time", ...time.map(cartaoPokemon));
  }

  function cartaoPokemon(p: PokemonRow): HTMLElement {
    const e = especie(p.especie_id);
    const hp = barraHp(p.hp_atual, p.hp_max);
    const golpes = p.golpes.map((s) => {
      const g = golpe(s.id);
      const c = el("span", { class: "chip-golpe" }, `${g.nome} ${s.pp}/${g.pp}`);
      c.style.background = COR_TIPO[g.tipo] ?? "#888";
      return c;
    });
    const tipos = e.tipos.map((t) => {
      const c = el("span", { class: "chip-tipo" }, NOME_TIPO[t] ?? t);
      c.style.background = COR_TIPO[t] ?? "#888";
      return c;
    });
    const fill = el("div", { class: `hp-fill ${hp.classe}` });
    fill.style.width = `${hp.pct}%`;
    return el(
      "div",
      { class: "cartao-pk" },
      imagemPokemon("frente", p.especie_id, "mini"),
      el(
        "div",
        { class: "cartao-info" },
        el("div", { class: "cartao-topo" }, el("strong", {}, nomePokemon(p)), el("span", {}, `Lv${p.nivel}`)),
        el("div", { class: "tipos" }, ...tipos),
        el("div", { class: "hp" }, el("span", { class: "hp-rot" }, "HP"), el("div", { class: "hp-trilho" }, fill), el("span", { class: "hp-num" }, `${p.hp_atual}/${p.hp_max}`)),
        el("div", { class: "golpes-lista" }, ...golpes),
      ),
    );
  }

  async function abrirMochila(): Promise<void> {
    const itens = await minhaMochila(j.id);
    const lista = itens.length
      ? itens.map((i) => el("div", { class: "linha" }, el("span", {}, nomeItem(i.item)), el("span", {}, `x${i.qtd}`)))
      : [el("p", { class: "sub" }, "Mochila vazia.")];
    modal.abrir("Mochila", el("div", { class: "linha" }, el("span", {}, "Dinheiro"), el("strong", {}, `₽ ${j.dinheiro ?? 0}`)), ...lista);
  }

  async function abrirPokedex(): Promise<void> {
    const { data } = await supabase.from("pokedex").select("especie_id, capturado").eq("jogador", j.id);
    const vistos = new Map<number, boolean>();
    for (const r of (data ?? []) as { especie_id: number; capturado: boolean }[]) vistos.set(r.especie_id, r.capturado);
    const celulas = todasEspecies().map((e) => {
      const v = vistos.get(e.id);
      const c = el("div", { class: `dex ${v === undefined ? "novo" : v ? "cap" : "visto"}` }, `${String(e.id).padStart(3, "0")} ${v === undefined ? "???" : e.nome}`);
      if (v) c.prepend("● ");
      return c;
    });
    const cap = [...vistos.values()].filter(Boolean).length;
    modal.abrir("Pokédex", el("p", { class: "sub" }, `Vistos: ${vistos.size}   Capturados: ${cap}   de 151 (Geração 1)`), el("div", { class: "dex-grade" }, ...celulas));
  }

  function abrirMenu(): void {
    const msg = msgPainel();
    const nos: Node[] = [el("p", { class: "sub" }, j.papel === "mestre" ? "Mestre" : "Treinador"), msg];

    if (j.papel === "mestre") {
      const pr = (t: string) => mensagem(msg, t, "ok");
      const rodar = (fn: () => Promise<void>) => async () => {
        try {
          await fn();
          await carregarReferencias(true);
          await recarregarJogador();
        } catch (e) {
          mensagem(msg, e instanceof Error ? e.message : "Erro.");
        }
      };
      nos.push(
        el("label", {}, "Ferramentas do Mestre"),
        botao("Importar dados do jogo", () => void rodar(() => importarDados(pr))()),
        botao("Importar sprites (PokeAPI)", () => void rodar(() => importarSprites(pr))()),
        botao("Repor meus PA", () => void rodar(async () => {
          const { error } = await supabase.rpc("repor_pa", { p_todos: false });
          if (error) throw new Error(error.message);
          pr("PA repostos.");
        })()),
        botao("Repor PA de todos", () => void rodar(async () => {
          const { data, error } = await supabase.rpc("repor_pa", { p_todos: true });
          if (error) throw new Error(error.message);
          pr(`PA repostos (${String(data)} jogadores).`);
        })()),
        botao("Resetar jogador...", () => void abrirReset(), ""),
        botao("+10 Poké Bolas para mim", () => void rodar(async () => {
          const { error } = await supabase.rpc("dar_item", { p_jogador: j.id, p_item: "poke-ball", p_qtd: 10 });
          if (error) throw new Error(error.message);
          pr("Poké Bolas entregues.");
        })()),
      );
    }

    const novaSenha = el("input", { type: "password", id: "nova", autocomplete: "new-password", minlength: "8" });
    const form = el("form", {}, el("label", { for: "nova" }, "Nova senha (mín. 8 caracteres)"), novaSenha, el("button", { type: "submit", class: "sec" }, "Trocar senha"));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      if (novaSenha.value.length < 8) return void mensagem(msg, "A senha precisa ter ao menos 8 caracteres.");
      const { error } = await supabase.auth.updateUser({ password: novaSenha.value });
      if (error) mensagem(msg, "Não foi possível trocar a senha.");
      else {
        novaSenha.value = "";
        mensagem(msg, "Senha trocada.", "ok");
      }
    });
    nos.push(form, botao("Sair", () => void supabase.auth.signOut(), ""));
    modal.abrir(j.nome, ...nos);
  }

  async function abrirReset(): Promise<void> {
    const { data } = await supabase.from("jogadores").select("id, nome, papel").order("nome");
    const msg = msgPainel();
    const linhas = ((data ?? []) as { id: string; nome: string; papel: string }[]).map((p) => {
      const b = el("button", { type: "button", class: "sec" }, `${p.nome}${p.papel === "mestre" ? " (Mestre)" : ""}`);
      let armado = false;
      b.addEventListener("click", async () => {
        if (!armado) {
          armado = true;
          b.textContent = `Confirmar: apagar tudo de ${p.nome}?`;
          b.classList.add("perigo");
          window.setTimeout(() => {
            armado = false;
            b.classList.remove("perigo");
            b.textContent = `${p.nome}${p.papel === "mestre" ? " (Mestre)" : ""}`;
          }, 5000);
          return;
        }
        const { error } = await supabase.rpc("resetar_jogador", { p_jogador: p.id });
        if (error) return void mensagem(msg, error.message);
        mensagem(msg, `${p.nome} voltou ao começo.`, "ok");
        if (p.id === j.id) window.setTimeout(() => location.reload(), 900);
      });
      return b;
    });
    modal.abrir("Resetar jogador", el("p", { class: "sub" }, "Volta para Pallet Town, apaga time, mochila, Pokédex e batalha; devolve PA e dinheiro. O login e o personagem ficam."), ...linhas, msg);
  }

  // ---------- ações do jogo ----------
  async function recarregarJogador(): Promise<void> {
    const novo = await controle?.recarregarJogador();
    if (novo) {
      j = { ...j, ...novo };
      atualizarHud();
    }
  }

  async function lutar(res: ResultadoBatalha): Promise<void> {
    emBatalha = true;
    modal.fechar();
    controle?.bloquear(true);
    await carregarReferencias();
    const estado = await abrirBatalha(res, j.id);
    emBatalha = false;
    controle?.bloquear(false);
    await recarregarJogador();
    if (estado === "derrota") mostrarAviso("Seus Pokémon precisam descansar: cure-os no Centro Pokémon (Viridian) ou em casa (Pallet).", 6000);
  }

  async function procurar(): Promise<void> {
    if (emBatalha) return;
    btnProcurar.disabled = true;
    const { data, error } = await supabase.rpc("procurar_pokemon");
    btnProcurar.disabled = false;
    if (error || !data) return void mostrarAviso(error?.message ?? "Nada por aqui.");
    await lutar(data as ResultadoBatalha);
  }

  async function escolherInicial(id: number, msg: HTMLElement): Promise<void> {
    mensagem(msg, "Entregando...", "ok");
    const { error } = await supabase.rpc("escolher_inicial", { p_especie: id });
    if (error) return void mensagem(msg, error.message);
    modal.fechar();
    mostrarAviso(`O Professor Carvalho entregou ${especie(id).nome} e 10 Poké Bolas. Boa sorte!`, 5000);
  }

  async function curar(msg: HTMLElement): Promise<void> {
    const { data, error } = await supabase.rpc("curar_time");
    if (error) return void mensagem(msg, error.message);
    mensagem(msg, `${String(data)} Pokémon curados!`, "ok");
  }

  async function abrirPoi(p: Poi): Promise<void> {
    const msg = msgPainel();
    const nos: Node[] = [el("p", { class: "sub" }, p.descricao)];
    if (p.tipo === "lab") {
      const time = await meuTime(j.id);
      if (time.length === 0) {
        await carregarReferencias();
        nos.splice(0, 1, el("p", { class: "sub" }, "Professor Carvalho: \"Escolha seu primeiro Pokémon!\""));
        nos.push(el("div", { class: "iniciais" }, ...[1, 4, 7].map((id) => {
          const b = el("button", { type: "button", class: "inicial" }, imagemPokemon("frente", id, "mini"), el("span", {}, especie(id).nome));
          b.addEventListener("click", () => void escolherInicial(id, msg));
          return b;
        })));
      } else nos.push(el("p", { class: "sub" }, "Professor Carvalho: \"Cuide bem do seu parceiro!\""));
    } else if (p.tipo === "centro" || p.tipo === "casa_jogador") {
      nos.push(botao("Curar meu time", () => void curar(msg), ""));
    }
    nos.push(msg);
    modal.abrir(p.nome, ...nos);
  }

  btnProcurar.addEventListener("click", () => void procurar());
  btnInteragir.addEventListener("click", () => {
    const p = lugar?.poi;
    if (p) void abrirPoi(p);
  });

  const aoTecla = (e: KeyboardEvent) => {
    if ((e.ctrlKey || e.metaKey) && ["+", "=", "-", "_", "0"].includes(e.key)) {
      e.preventDefault();
      controle?.zoom(e.key === "0" ? 0 : e.key === "-" || e.key === "_" ? -1 : 1);
      return;
    }
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
    if (emBatalha || modal.aberto()) return;
    if (e.key === "e" || e.key === "E" || e.key === " " || e.key === "Enter") {
      if (lugar?.naGrama) void procurar();
      else if (lugar?.poi) void abrirPoi(lugar.poi);
      e.preventDefault();
    }
  };
  window.addEventListener("keydown", aoTecla);

  // ---------- barra inferior ----------
  const chat = el("input", { type: "text", maxlength: "60", placeholder: "Dizer algo...", autocomplete: "off", "aria-label": "Chat" });
  const formChat = el("form", { class: "chat" }, chat);
  formChat.addEventListener("submit", (ev) => {
    ev.preventDefault();
    controle?.dizer(chat.value);
    chat.value = "";
    chat.blur();
  });
  const botoes = el(
    "div",
    { class: "grupo" },
    botao("−", () => controle?.zoom(-1), "sec botao-menu botao-zoom"),
    botao("+", () => controle?.zoom(1), "sec botao-menu botao-zoom"),
    botao("Time", () => void abrirTime(), "sec botao-menu"),
    botao("Mochila", () => void abrirMochila(), "sec botao-menu"),
    botao("Pokédex", () => void abrirPokedex(), "sec botao-menu"),
    botao("Menu", abrirMenu, "sec botao-menu"),
  );
  const topo = el("div", { class: "barra" }, el("div", { class: "grupo" }, el("span", { class: "nome-jogador" }, j.nome), onde), el("div", { class: "grupo" }, dinheiro, pa));
  const rodape = el("div", { class: "barra rodape" }, formChat, botoes);
  const dica = el("p", { class: "dica" }, "Setas/WASD andam · E interage · Ctrl + / Ctrl − ajustam o zoom · entre na grama alta e procure Pokémon");

  const minha = montar([el("div", { class: "jogo" }, el("div", { class: "cartucho" }, topo, tela, rodape), dica, modal.raiz)], true);

  const { iniciarMundo } = await import("../game/mundo");
  if (minha !== geracaoAtual()) return;
  let iniciado: Controle;
  try {
    iniciado = await iniciarMundo(tela, j, {
      aoLugar: (l) => {
        lugar = l;
        j = { ...j, mapa_id: l.mapa_id, x: l.x, y: l.y };
        btnProcurar.hidden = !l.naGrama;
        btnInteragir.hidden = !l.poi;
        atualizarHud();
        const chave = l.poi ? `${l.mapa_id}:${l.x},${l.y}` : "";
        if (chave && chave !== poiAberto && !emBatalha && !modal.aberto()) void abrirPoi(l.poi!);
        poiAberto = chave;
      },
      aoJogador: (novo) => {
        j = { ...j, ...novo };
        atualizarHud();
      },
      aviso: mostrarAviso,
    });
  } catch (e) {
    mostrarAviso(e instanceof Error ? e.message : "Não foi possível abrir o jogo.");
    return;
  }
  if (minha !== geracaoAtual()) {
    iniciado.encerrar();
    window.removeEventListener("keydown", aoTecla);
    return;
  }
  controle = iniciado;
  aoTrocarTela(() => {
    window.removeEventListener("keydown", aoTecla);
    iniciado.encerrar();
  });

  // configuração, referências e batalha pendente
  void (async () => {
    const [{ data: cfg }, temRef] = await Promise.all([supabase.from("config").select("valor").eq("chave", "pa_por_dia").maybeSingle(), carregarReferencias()]);
    paMax = Number(cfg?.valor ?? 30) || 30;
    atualizarHud();
    if (!temRef) {
      mostrarAviso(j.papel === "mestre" ? "Mestre: abra Menu e clique em \"Importar dados do jogo\" e depois \"Importar sprites\"." : "O Mestre ainda está preparando o mundo.", 8000);
      return;
    }
    const { data: ativa } = await supabase.from("batalhas").select("id").eq("estado", "ativa").maybeSingle();
    if (ativa) {
      const { data } = await supabase.rpc("procurar_pokemon");
      if (data) await lutar(data as ResultadoBatalha);
    }
  })();
}
