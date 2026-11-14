import { supabase, type Direcao, type Jogador } from "../supabase";
import { aoTrocarTela, el, geracaoAtual, mensagem, montar } from "./dom";
import type { Controle, Lugar, Poi, TreinadorMapa } from "../game/mundo";
import { abrirBatalha, type ResultadoBatalha } from "./batalha";
import {
  barraHp, carregarReferencias, COR_TIPO, especie, golpe, imagemPokemon, meuTime, NOME_TIPO, nomeItem, textoSobre,
  nomePokemon, todasEspecies, type PokemonRow,
} from "./dados";
import { carregarMissao, conversarNpc, type MissaoEstado } from "./missao";
import { abrirSocial, carregarPendencias } from "./social";
import { resolverPendencias } from "./momentos";
import { fichaEspecie, painelBusca } from "./pokedex";
import { distribuirPendentes } from "./evolucao";
import { abrirMapaMundi } from "./mapamundi";
import { abrirCaixas } from "./caixa";
import { abrirHabilidades, abrirAcoes, acaoPA, textoEventos, exigirClasse } from "./habilidades";
import { aoEstado, consultar, type PingEstado } from "./acesso";
import { abrirMochila as abrirMochilaSS } from "./mochila";
import { abrirResumo } from "./resumo";
import { abrirOrganizar } from "./organizar";
import { abrirEventos, iniciarFaixaEventos } from "./eventos";

function botao(texto: string, fn: () => void, classe = "sec"): HTMLButtonElement {
  const b = el("button", { type: "button", class: classe }, texto);
  b.addEventListener("click", fn);
  return b;
}

/** Painel modal reutilizável. */
function criarModal(): { raiz: HTMLElement; abrir: (titulo: string, ...nos: Node[]) => void; acoes: (...nos: Node[]) => void; fechar: () => void; aberto: () => boolean; aoFechar: (fn: (() => void) | null) => void } {
  let ao: (() => void) | null = null;
  const titulo = el("h1", {});
  const corpo = el("div", { class: "modal-corpo" });
  const fechar = () => {
    raiz.hidden = true;
    const f = ao;
    ao = null;
    f?.();
  };
  const x = el("button", { type: "button", class: "modal-x", "aria-label": "Sair do painel" }, "✕");
  x.addEventListener("click", fechar);
  const acoesSlot = el("div", { class: "modal-acoes" });
  const caixaModal = el("div", { class: "painel modal" }, el("div", { class: "modal-topo" }, titulo, acoesSlot, x), corpo, botao("Fechar", fechar));
  const raiz = el("div", { class: "menu", hidden: "" }, caixaModal);
  raiz.addEventListener("click", (e) => {
    if (e.target === raiz) fechar();
  });
  return {
    raiz,
    abrir: (t, ...nos) => {
      titulo.textContent = t;
      acoesSlot.replaceChildren();
      corpo.replaceChildren(...nos);
      caixaModal.classList.toggle("claro", !corpo.querySelector(".mm-caixa, .rs-tela")); // mapa e resumo mantêm o visual escuro próprio
      raiz.hidden = false;
    },
    acoes: (...nos) => { acoesSlot.replaceChildren(...nos); },
    fechar,
    aberto: () => !raiz.hidden,
    aoFechar: (fn) => {
      ao = fn;
    },
  };
}

const ICONES: Record<string, string> = {
  time: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><circle cx="12" cy="12" r="3" fill="currentColor" stroke="none"/>',
  mochila: '<path d="M6 9h12l1 11H5z"/><path d="M9 9V7a3 3 0 0 1 6 0v2"/><path d="M9 14h6"/>',
  pokedex: '<rect x="5" y="3" width="14" height="18" rx="2.5"/><circle cx="12" cy="9" r="2.5"/><path d="M9 16h6"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  mapa: '<path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
  painel: '<rect x="3" y="3" width="8" height="8" rx="2"/><rect x="13" y="3" width="8" height="5" rx="2"/><rect x="13" y="10" width="8" height="11" rx="2"/><rect x="3" y="13" width="8" height="8" rx="2"/>',
  conta: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4-6 8-6s7 2 8 6"/>',
};
/** Ícone vetorial fixo (conteúdo estático do próprio código, nunca texto de usuário). */
function icone(nome: string): HTMLElement {
  const s = el("span", { class: "ico", "aria-hidden": "true" });
  s.innerHTML = `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${ICONES[nome]}</svg>`;
  return s;
}
type ItemMenu = { rotulo: string; fn: () => void; oculto?: boolean };

/** Barra superior com menus suspensos (clique para abrir; fecha ao clicar fora ou escolher). */
function barraNavegacao(grupos: { rotulo: string; itens: () => ItemMenu[] }[], marca: HTMLElement): { raiz: HTMLElement; fecharTudo: () => void } {
  const abertos: HTMLElement[] = [];
  const fecharTudo = () => {
    for (const g of abertos) {
      g.classList.remove("aberto");
      g.querySelector("button")?.setAttribute("aria-expanded", "false");
    }
  };
  const lista = grupos.map((g) => {
    const caixa = el("div", { class: "nav-menu" });
    const gatilho = el("button", { type: "button", class: "nav-gatilho", "aria-haspopup": "true", "aria-expanded": "false" }, g.rotulo, el("span", { class: "nav-seta", "aria-hidden": "true" }, "▾"));
    const painel = el("div", { class: "nav-lista", role: "menu" });
    gatilho.addEventListener("click", (e) => {
      e.stopPropagation();
      const abrir = !caixa.classList.contains("aberto");
      fecharTudo();
      if (!abrir) return;
      painel.replaceChildren(
        ...g.itens().filter((i) => !i.oculto).map((i) => {
          const b = el("button", { type: "button", class: "nav-item", role: "menuitem" }, i.rotulo);
          b.addEventListener("click", () => {
            fecharTudo();
            i.fn();
          });
          return b;
        }),
      );
      caixa.classList.add("aberto");
      gatilho.setAttribute("aria-expanded", "true");
      const r = gatilho.getBoundingClientRect();
      painel.style.top = `${r.bottom + 6}px`;
      painel.style.left = `${Math.max(8, Math.min(r.left, window.innerWidth - 208))}px`;
    });
    caixa.append(gatilho, painel);
    abertos.push(caixa);
    return caixa;
  });
  document.addEventListener("click", fecharTudo);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") fecharTudo();
  });
  return { raiz: el("nav", { class: "nav", "aria-label": "Menu principal" }, marca, el("div", { class: "nav-grupos" }, ...lista)), fecharTudo };
}

export async function telaJogo(inicial: Jogador): Promise<void> {
  let j: Jogador = { ...inicial };
  let controle: Controle | null = null;
  let lugar: Lugar | null = null;
  let emBatalha = false;
  let paMax = 30;
  let missaoAtual: MissaoEstado | null = null;
  const hudMissao = el("button", { type: "button", class: "hud-missao", hidden: "", "aria-label": "Missão ativa" });
  const atualizarMissao = async (): Promise<void> => {
    try { missaoAtual = await carregarMissao(); } catch { missaoAtual = null; }
    const m = missaoAtual;
    if (!m || m.estado !== "ativa") { hudMissao.hidden = true; return; }
    hudMissao.replaceChildren(el("strong", {}, `Missão: ${m.nome}`), el("span", {}, m.objetivo ?? ""), el("em", {}, `${m.feitas}/${m.total} concluídas`));
    hudMissao.hidden = false;
  };
  hudMissao.addEventListener("click", () => void abrirMapaMundi(modal, (m) => controle?.viajar(m) ?? Promise.resolve(false), mostrarAviso, missaoAtual?.estado === "ativa" && missaoAtual.mapa_id ? { mapa_id: missaoAtual.mapa_id, mapa_nome: missaoAtual.mapa_nome ?? "", nome: missaoAtual.nome, objetivo: missaoAtual.objetivo ?? "" } : null));

  const tela = el("div", { class: "tela-jogo" });
  const aviso = el("div", { class: "aviso", role: "status", hidden: "" });
  let temporizador: number | undefined;
  const mostrarAviso = (texto: string, ms = 3200, erro = false) => {
    aviso.textContent = texto;
    aviso.classList.toggle("erro", erro);
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
  const nomeTreinador = el("strong", { class: "tc-nome" });
  const emblema = el("span", { class: "tc-emblema", "aria-hidden": "true" });
  const BASE = import.meta.env.BASE_URL as string;
  const atualizarHud = () => {
    pa.textContent = `PA ${j.pa}/${paMax}`;
    pa.classList.toggle("zerado", j.pa === 0);
    dinheiro.textContent = `₽ ${j.dinheiro ?? 0}`;
    onde.textContent = lugar ? lugar.nome_mapa : "";
    nomeTreinador.textContent = j.nome;
    emblema.style.backgroundImage = `url(${BASE}assets/personagens/p${j.aparencia ?? 0}.png)`;
  };
  atualizarHud();

  const modal = criarModal();

  // ---------- botões de ação sobre o mapa ----------
  const btnInteragir = el("button", { type: "button", class: "acao", hidden: "" }, "Interagir");
  const acoes = el("div", { class: "acoes" }, btnInteragir);

  // ---------- prévia de encontro (canto inferior esquerdo) ----------
  interface Oferta { especie_id: number; nome: string; nivel: number; bioma: string }
  const NOME_BIOMA: Record<string, string> = { grama: "Grama alta", estrada: "Estrada", floresta: "Floresta", agua: "Água", campo: "Campo" };
  let oferta: Oferta | null = null;
  const cartaoOferta = el("div", { class: "oferta", hidden: "", role: "status" });
  let tempoOferta: number | undefined;
  const limparOferta = () => {
    window.clearTimeout(tempoOferta);
    oferta = null;
    cartaoOferta.hidden = true;
    cartaoOferta.replaceChildren();
  };
  const mostrarOferta = (o: Oferta) => {
    oferta = o;
    const buscar = el("button", { type: "button", class: "oferta-buscar" }, "Buscar (1 PA)");
    buscar.addEventListener("click", () => void procurar());
    const ignorar = el("button", { type: "button", class: "oferta-ignorar" }, "Ignorar");
    ignorar.addEventListener("click", limparOferta);
    cartaoOferta.replaceChildren(
      imagemPokemon("frente", o.especie_id, "mini"),
      el("div", { class: "oferta-info" },
        el("span", { class: "oferta-bioma" }, NOME_BIOMA[o.bioma] ?? o.bioma),
        el("strong", {}, `${o.nome} · Nv ${o.nivel}`),
        el("div", { class: "oferta-btns" }, buscar, ignorar)),
    );
    cartaoOferta.hidden = false;
  };
  /** Chamado quando o jogador para de andar: pede ao servidor a prévia do bioma daquele tile. */
  function agendarOferta(l: Lugar): void {
    limparOferta();
    if (l.poi || emBatalha) return;
    tempoOferta = window.setTimeout(async () => {
      if (emBatalha || modal.aberto() || !lugar || lugar.x !== l.x || lugar.y !== l.y || lugar.mapa_id !== l.mapa_id) return;
      const { data } = await supabase.rpc("gerar_oferta");
      if (!data || emBatalha || !lugar || lugar.x !== l.x || lugar.y !== l.y || lugar.mapa_id !== l.mapa_id) return;
      mostrarOferta(data as Oferta);
    }, 180);
  }

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
  const cartaoTreinador = el("div", { class: "cartao-treinador" }, emblema, el("div", { class: "tc-info" }, nomeTreinador, onde, el("div", { class: "tc-chips" }, dinheiro, pa)));
  tela.append(aviso, cartaoTreinador, hudMissao, acoes, cartaoOferta, dpad);

  // ---------- painéis ----------
  const msgPainel = (): HTMLElement => el("p", { class: "msg", role: "status" });

  function abas(ativa: "time" | "mochila" | "pokedex"): HTMLElement {
    const mk = (id: "time" | "mochila" | "pokedex", rot: string, fn: () => Promise<void>) => {
      const b = el("button", { type: "button", class: `aba${id === ativa ? " ativa" : ""}`, "aria-pressed": String(id === ativa) }, icone(id), el("span", {}, rot));
      b.addEventListener("click", () => void fn());
      return b;
    };
    return el("div", { class: "abas" }, mk("time", "Time", abrirTime), mk("mochila", "Mochila", abrirMochila), mk("pokedex", "Pokédex", abrirPokedex));
  }

  async function abrirTime(): Promise<void> {
    const time = await meuTime(j.id);
    if (time.length === 0) {
      modal.abrir("Seu time", abas("time"), el("p", { class: "sub" }, "Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório."));
      return;
    }
    const vazios = Array.from({ length: Math.max(0, 6 - time.length) }, () => el("div", { class: "cartao-vazio", "aria-label": "Espaço livre" }, el("span", {}, "+")));
    modal.abrir("Seu time", abas("time"), el("div", { class: "grade-time" }, ...time.map(cartaoPokemon), ...vazios), botao("Ver Caixas (consulta)", () => void abrirCaixas(modal, j.id, mostrarAviso, atualizarHud), "sec"));
  }

  function cartaoPokemon(p: PokemonRow): HTMLElement {
    const e = especie(p.especie_id);
    const hp = barraHp(p.hp_atual, p.hp_max);
    const golpes = p.golpes.map((s) => {
      const g = golpe(s.id);
      const c = el("span", { class: "chip-golpe" }, el("b", {}, g.nome), el("i", {}, `${s.pp}/${g.pp}`));
      c.style.setProperty("--cor", COR_TIPO[g.tipo] ?? "#888");
      return c;
    });
    const tipos = e.tipos.map((t) => {
      const c = el("span", { class: "chip-tipo" }, NOME_TIPO[t] ?? t);
      c.style.background = COR_TIPO[t] ?? "#888"; c.style.color = textoSobre(COR_TIPO[t] ?? "#888");
      return c;
    });
    const fill = el("div", { class: `hp-fill ${hp.classe}` });
    fill.style.width = `${hp.pct}%`;
    const base = p.nivel ** 3;
    const prox = (p.nivel + 1) ** 3;
    const expFill = el("div", { class: "exp-fill" });
    expFill.style.width = `${Math.max(0, Math.min(100, ((p.exp - base) / (prox - base)) * 100))}%`;
    const c = el(
      "div",
      { class: `cartao-pk${p.hp_atual <= 0 ? " caido" : ""}` },
      el("div", { class: "cartao-img" }, imagemPokemon("frente", p.especie_id, "grande", p.brilhante)),
      el(
        "div",
        { class: "cartao-info" },
        el("div", { class: "cartao-topo" }, el("strong", {}, nomePokemon(p)), el("span", { class: "nivel" }, `Lv${p.nivel}`)),
        el("div", { class: "tipos" }, ...tipos),
        el("div", { class: "hp" }, el("span", { class: "hp-rot" }, "HP"), el("div", { class: "hp-trilho" }, fill), el("span", { class: "hp-num" }, `${p.hp_atual}/${p.hp_max}`)),
        el("div", { class: "exp-trilho" }, expFill),
        el("div", { class: "golpes-lista" }, ...golpes),
      ),
    );
    c.style.setProperty("--cor", COR_TIPO[e.tipos[0]] ?? "#4f8cff");
    const refrescar = () => { void recarregarJogador(); void abrirTime(); };
    const btn = (rot: string, fn: () => void) => { const b = el("button", { type: "button", class: "sec cartao-acao" }, rot); b.addEventListener("click", (ev) => { ev.stopPropagation(); fn(); }); return b; };
    if (p.evo_pend) {
      const pt = el("button", { type: "button", class: "cartao-pontos" }, `⭐ Distribuir ${p.evo_pend.pool} pontos da evolução`);
      pt.addEventListener("click", (ev) => { ev.stopPropagation(); void distribuirPendentes().then(() => abrirTime()); });
      c.querySelector(".cartao-info")?.append(pt);
    }
    c.querySelector(".cartao-info")?.append(el("div", { class: "cartao-acoes" },
      btn("Resumo", () => abrirResumo(modal, p, () => void abrirTime())),
      btn("Treinar · 1 PA", () => void acaoPA("acao_treinar", { p_pokemon: p.id }, j.id, mostrarAviso, refrescar, (d) => `${nomePokemon(p)} treinou! ${textoEventos((d.eventos ?? []) as Parameters<typeof textoEventos>[0])}`)),
      btn("Cuidar · 1 PA", () => void acaoPA("acao_cuidar", { p_pokemon: p.id }, j.id, mostrarAviso, refrescar, (d) => `Você cuidou de ${nomePokemon(p)}! Amizade ${d.amizade}. ${textoEventos((d.eventos ?? []) as Parameters<typeof textoEventos>[0])}`))));
    return c;
  }

  async function abrirMochila(): Promise<void> {
    await abrirMochilaSS(modal, j.id, j.dinheiro ?? 0, mostrarAviso, atualizarHud, abas("mochila"));
  }

  async function abrirPokedex(): Promise<void> {
    const { data } = await supabase.from("pokedex").select("especie_id, capturado").eq("jogador", j.id);
    const vistos = new Map<number, boolean>();
    for (const r of (data ?? []) as { especie_id: number; capturado: boolean }[]) vistos.set(r.especie_id, r.capturado);
    const cap = [...vistos.values()].filter(Boolean).length;
    const celulas = todasEspecies().map((e) => {
      const v = vistos.get(e.id);
      const c = el("button", { type: "button", class: `dex ${v === undefined ? "novo" : v ? "cap" : "visto"}`, title: "Ver detalhes" });
      c.addEventListener("click", () => void abrirFichaDex(e.id));
      c.append(el("span", { class: "dex-n" }, String(e.id).padStart(3, "0")));
      if (v !== undefined) c.append(imagemPokemon("frente", e.id, `dex-img${v ? "" : " silhueta"}`));
      else c.append(el("div", { class: "dex-img vazio" }, "?"));
      c.append(el("span", { class: "dex-nome" }, v === undefined ? "???" : e.nome));
      if (v) c.append(el("span", { class: "dex-sel", title: "Capturado" }, "●"));
      return c;
    });
    const total = todasEspecies().length || 151;
    const prog = el("div", { class: "dex-prog" });
    prog.style.setProperty("--p", `${(cap / total) * 100}%`);
    modal.abrir(
      "Pokédex", abas("pokedex"),
      el("p", { class: "sub" }, `Vistos: ${vistos.size}   Capturados: ${cap}   de ${total} (Geração 1)`),
      prog,
      el("div", { class: "dex-busca-caixa" }, el("strong", {}, "🔎 Onde encontrar um Pokémon?"), await painelBusca()),
      el("div", { class: "dex-grade" }, ...celulas),
    );
  }

  /** Ficha de uma espécie (tipos, fraquezas, onde aparece e %). Com "Banco de Dados", mostra os atributos dos seus Pokémon dessa espécie. */
  async function abrirFichaDex(id: number): Promise<void> {
    const nota = el("div", {});
    const { data: tr } = await supabase.rpc("estado_treino");
    const rankBanco = Number(((tr as { habilidades?: Record<string, number> } | null)?.habilidades ?? {}).banco_dados ?? 0);
    if (rankBanco > 0) {
      const { data: meus } = await supabase.from("pokemons").select("nivel, natureza, atk, def, spa, spd, spe, hp_max, apelido").eq("dono", j.id).eq("especie_id", id);
      const lista = (meus ?? []) as { nivel: number; natureza: string; atk: number; def: number; spa: number; spd: number; spe: number; hp_max: number; apelido: string | null }[];
      if (lista.length) nota.append(el("div", { class: "dx-grupo" }, el("strong", {}, "📊 Seus Pokémon desta espécie (Banco de Dados)"),
        ...lista.map((p) => el("p", { class: "sub" }, `${p.apelido ?? "Sem apelido"} · Nv ${p.nivel} · ${p.natureza} · PV ${p.hp_max} · Atq ${p.atk} · Def ${p.def} · AtqE ${p.spa} · DefE ${p.spd} · Vel ${p.spe}`))));
    }
    const voltar = el("button", { type: "button", class: "sec" }, "← Voltar à Pokédex");
    voltar.addEventListener("click", () => void abrirPokedex());
    modal.abrir("Pokédex", abas("pokedex"), voltar, await fichaEspecie(id, { nota }));
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
        botao("Importar dados do jogo", () => void rodar(async () => (await import("./mestre")).importarDados(pr))()),
        botao("Importar sprites (PokeAPI)", () => void rodar(async () => (await import("./mestre")).importarSprites(pr))()),
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
        botao("Gestão do Mestre (jogadores e fichas)", () => void import("./gestao").then((m) => m.abrirGestao(modal, mostrarAviso))),
        botao("Eventos (XP em dobro, brilhantes...)", () => void abrirEventos(modal, mostrarAviso), ""),
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


  // ---------- Dashboard ----------
  async function abrirDashboard(): Promise<void> {
    await carregarReferencias();
    const [time, painel] = await Promise.all([meuTime(j.id), supabase.rpc("meu_painel")]);
    const st = (painel.data ?? {}) as { pokemons?: number; pokedex?: number; treinadores?: number; itens?: number; maior_nivel?: number };
    const tile = (rot: string, val: string | number) => el("div", { class: "dash-tile" }, el("strong", {}, String(val)), el("span", {}, rot));
    const avatar = el("span", { class: "tc-emblema dash-avatar", "aria-hidden": "true" });
    avatar.style.backgroundImage = `url(${BASE}assets/personagens/p${j.aparencia ?? 0}.png)`;
    const cab = el("div", { class: "dash-cab" }, avatar,
      el("div", {}, el("strong", { class: "dash-nome" }, j.nome), el("span", { class: "sub" }, `${lugar?.nome_mapa ?? ""} · ₽ ${j.dinheiro ?? 0} · PA ${j.pa}/${paMax}`)));
    const grade = el("div", { class: "dash-grade" },
      tile("Pokémon capturados", st.pokemons ?? 0), tile("Pokédex", `${st.pokedex ?? 0}/151`), tile("Treinadores vencidos", st.treinadores ?? 0),
      tile("Itens na mochila", st.itens ?? 0), tile("Maior nível", st.maior_nivel ?? 0));
    const linhas = time.map((p) => {
      const hp = barraHp(p.hp_atual, p.hp_max);
      const fill = el("div", { class: `hp-fill ${hp.classe}` });
      fill.style.width = `${hp.pct}%`;
      return el("div", { class: `dash-pk${p.hp_atual <= 0 ? " caido" : ""}` }, imagemPokemon("frente", p.especie_id, "mini", p.brilhante),
        el("div", { class: "dash-pk-info" }, el("strong", {}, nomePokemon(p)), el("span", {}, `Nv ${p.nivel} · ${p.hp_atual}/${p.hp_max} HP`), el("div", { class: "hp-trilho" }, fill)));
    });
    const atalhos = [
      botao("Habilidades", () => void abrirHabilidades(modal, mostrarAviso, atualizarHud), "modal-atalho"), botao("Ações (PA)", () => void abrirAcoes(modal, j.id, mostrarAviso, () => void recarregarJogador()), "modal-atalho"), botao("Organizar time", () => void abrirOrganizar(modal, j.id, mostrarAviso, () => void controle?.atualizarSeguidor()), "modal-atalho"), botao("Personagens", () => void abrirPersonagens(), "modal-atalho")];
    modal.abrir("Painel do treinador", el("div", { class: "dash-wide" },
      el("div", { class: "dash-esq" }, cab, grade),
      el("div", { class: "dash-dir" }, el("label", {}, "Time ativo"),
        linhas.length ? el("div", { class: "dash-time" }, ...linhas) : el("p", { class: "sub" }, "Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório."))));
    modal.acoes(...atalhos);
  }

  // ---------- Personagens (até 2) e reinício ----------
  async function abrirPersonagens(): Promise<void> {
    const { data } = await supabase.rpc("meus_personagens");
    const lista = (data ?? []) as { id: string; nome: string; aparencia: number; ativo: boolean; dinheiro: number; pokemons: number; pokedex: number }[];
    const msg = msgPainel();
    const confirmar = (b: HTMLButtonElement, rot: string, aviso: string, fn: () => Promise<void>) => {
      let armado = false;
      b.addEventListener("click", async () => {
        if (!armado) {
          armado = true;
          b.textContent = aviso;
          b.classList.add("perigo");
          window.setTimeout(() => { armado = false; b.classList.remove("perigo"); b.textContent = rot; }, 5000);
          return;
        }
        await fn();
      });
      return b;
    };
    const cartoes = lista.map((p) => {
      const av = el("span", { class: "tc-emblema dash-avatar", "aria-hidden": "true" });
      av.style.backgroundImage = `url(${BASE}assets/personagens/p${p.aparencia}.png)`;
      const acoesP: Node[] = [];
      if (!p.ativo) {
        acoesP.push(botao("Jogar com ele", async () => {
          const { error } = await supabase.rpc("trocar_personagem", { p_id: p.id });
          if (error) return void mensagem(msg, error.message);
          location.reload();
        }, ""));
        acoesP.push(confirmar(botao("Excluir", () => undefined, "sec"), "Excluir", "Confirmar: apagar tudo dele?", async () => {
          const { error } = await supabase.rpc("excluir_personagem_reserva", { p_id: p.id });
          if (error) return void mensagem(msg, error.message);
          void abrirPersonagens();
        }));
      }
      return el("div", { class: `dash-pk${p.ativo ? " ativo" : ""}` }, av,
        el("div", { class: "dash-pk-info" }, el("strong", {}, `${p.nome}${p.ativo ? " (jogando agora)" : ""}`),
          el("span", {}, `${p.pokemons} Pokémon · Pokédex ${p.pokedex}/151 · ₽ ${p.dinheiro}`), el("div", { class: "dash-btns" }, ...acoesP)));
    });
    const nos: Node[] = [el("p", { class: "sub" }, "Cada personagem tem seu próprio time, mochila, Pokédex, dinheiro e PA. Você pode ter até 2."), ...cartoes];

    if (lista.length < 2) {
      let aparencia = 0;
      const nome = el("input", { type: "text", maxlength: "12", autocomplete: "off", placeholder: "Nome do 2º personagem" });
      const botoesA = Array.from({ length: 12 }, (_, i) => {
        const b = el("button", { type: "button", class: "aparencia", "aria-label": `Visual ${i + 1}`, "aria-pressed": String(i === 0) });
        b.style.backgroundImage = `url(${BASE}assets/personagens/p${i}.png)`;
        b.addEventListener("click", () => { aparencia = i; botoesA.forEach((x, k) => x.setAttribute("aria-pressed", String(k === i))); });
        return b;
      });
      const criar = botao("Criar 2º personagem e jogar com ele", async () => {
        const { error } = await supabase.rpc("criar_novo_personagem", { p_nome: nome.value, p_aparencia: aparencia });
        if (error) return void mensagem(msg, error.message);
        location.reload();
      }, "");
      nos.push(el("label", {}, "Criar segundo personagem"), nome, el("div", { class: "aparencias" }, ...botoesA), criar);
    }

    const reiniciar = confirmar(botao("Reiniciar o jogo deste personagem", () => undefined, "sec"), "Reiniciar o jogo deste personagem", "Confirmar: apagar time, mochila e Pokédex?", async () => {
      const { error } = await supabase.rpc("reiniciar_meu_jogo");
      if (error) return void mensagem(msg, error.message);
      location.reload();
    });
    const zerar = confirmar(botao("Apagar todos os meus personagens", () => undefined, "sec"), "Apagar todos os meus personagens", "Confirmar: apagar TUDO e criar do zero?", async () => {
      const { error } = await supabase.rpc("apagar_todos_meus_personagens");
      if (error) return void mensagem(msg, error.message);
      location.reload();
    });
    nos.push(el("label", {}, "Recomeçar"), el("p", { class: "sub" }, "Apaga time, mochila, Pokédex e vitórias do personagem atual e volta ao Laboratório. O nome e o visual ficam."), reiniciar,
      el("label", {}, "Começar do zero"), el("p", { class: "sub" }, "Apaga TODOS os seus personagens (o atual e o reserva), com time, mochila, Pokédex e dinheiro, e leva você à criação de um novo personagem. Não dá para desfazer."), zerar, msg);
    modal.abrir("Meus personagens", ...nos);
  }

  function abrirInfoLugar(): void {
    if (!lugar) return void mostrarAviso("Ainda carregando o mapa...");
    const nos: Node[] = [el("p", { class: "sub" }, lugar.poi ? lugar.poi.descricao : `Você está em ${lugar.nome_mapa}.`)];
    if (lugar.poi) nos.push(botao("Interagir", () => void abrirPoi(lugar!.poi!), ""));
    modal.abrir(lugar.nome_mapa, ...nos);
  }

  function abrirAjuda(): void {
    modal.abrir(
      "Como jogar",
      el("p", { class: "sub" }, "Setas ou WASD para andar (no celular, use os botões na tela). E, Espaço ou Enter interagem com o que está no seu tile ou ao seu lado; B busca o Pokémon da prévia."),
      el("p", { class: "sub" }, "Ande e pare: às vezes um Pokémon do bioma (grama, estrada, floresta, água...) aparece no canto inferior esquerdo. Buscá-lo custa 1 Ponto de Aventura (PA); ignorar é grátis. Seus PA se renovam com o tempo."),
      el("p", { class: "sub" }, "O Mapa Mundi abre pelo botão 🗺 ao lado do zoom ou pela tecla M. Fale com o Professor Carvalho no laboratório para receber seu primeiro Pokémon. Treinadores só desafiam quando você chega ao lado deles e fala (botão Interagir ou E)."),
    );
  }

  async function abrirReset(): Promise<void> {
    const { data } = await supabase.from("jogadores").select("id, nome, papel").is("conta", null).order("nome");
    const msg = msgPainel();
    const caixaMissao = el("input", { type: "checkbox", id: "reset-missao", checked: "" }) as HTMLInputElement;
    caixaMissao.checked = true;
    const optMissao = el("label", { class: "sub", for: "reset-missao", style: "display:flex;gap:8px;align-items:center;cursor:pointer" }, caixaMissao, "Limpar também a missão (história volta ao início)");
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
        const { error } = await supabase.rpc("resetar_jogador", { p_jogador: p.id, p_limpar_missao: caixaMissao.checked });
        if (error) return void mensagem(msg, error.message);
        mensagem(msg, `${p.nome} voltou ao começo.`, "ok");
        if (p.id === j.id) window.setTimeout(() => location.reload(), 900);
      });
      return b;
    });
    modal.abrir("Resetar jogador", el("p", { class: "sub" }, "Volta para o Laboratório, apaga time, mochila, Pokédex e batalha; devolve PA e dinheiro. O login e o personagem ficam."), optMissao, ...linhas, msg);
  }

  // ---------- missões: desistir (jogador) e remover (Mestre) ----------
  function abrirDesistirMissao(): void {
    const msg = msgPainel();
    let armado = false;
    const b = botao("Desistir da missão", async () => {
      if (!armado) {
        armado = true;
        b.textContent = "Confirmar: desistir da missão?";
        b.classList.add("perigo");
        window.setTimeout(() => { armado = false; b.classList.remove("perigo"); b.textContent = "Desistir da missão"; }, 5000);
        return;
      }
      const { error } = await supabase.rpc("missao_desistir");
      if (error) return void mensagem(msg, error.message);
      mensagem(msg, "Você desistiu da missão. Para recomeçar, fale de novo com quem a deu.", "ok");
      await atualizarMissao();
    }, "");
    modal.abrir("Desistir da missão", el("p", { class: "sub" }, `Missão atual: ${missaoAtual?.nome ?? "—"}. Ao desistir, o progresso é apagado e a missão volta ao começo. Itens já entregues e Pokémon já entregues não voltam.`), b, msg);
  }

  async function abrirMissoesMestre(): Promise<void> {
    const msg = msgPainel();
    const { data, error } = await supabase.rpc("mestre_missoes_jogadores");
    if (error) return void mostrarAviso(error.message, 4000, true);
    const lista = (data ?? []) as { jogador: string; nome: string; missao: string; missao_nome: string; estado: string; etapa: number; total: number }[];
    const linhas = lista.map((m) => {
      let armado = false;
      const b = botao("Remover", async () => {
        if (!armado) {
          armado = true;
          b.textContent = "Confirmar?";
          b.classList.add("perigo");
          window.setTimeout(() => { armado = false; b.classList.remove("perigo"); b.textContent = "Remover"; }, 5000);
          return;
        }
        const { error: e } = await supabase.rpc("mestre_remover_missao", { p_jogador: m.jogador, p_missao: m.missao });
        if (e) return void mensagem(msg, e.message);
        mensagem(msg, `Missão removida de ${m.nome}.`, "ok");
        void abrirMissoesMestre();
      }, "sec");
      const situacao = m.estado === "concluida" ? "concluída" : `etapa ${m.etapa} de ${m.total}`;
      return el("div", { class: "ev-item" }, el("span", {}, `${m.nome} — ${m.missao_nome} (${situacao})`), b);
    });
    modal.abrir("Missões dos jogadores", el("p", { class: "sub" }, "Remover apaga o progresso do jogador nessa missão (ativa ou concluída) e ele pode aceitá-la de novo."),
      lista.length ? el("div", { class: "ev-lista" }, ...linhas) : el("p", { class: "sub" }, "Nenhum jogador tem missões."), msg);
  }

  // ---------- ações do jogo ----------
  async function recarregarJogador(): Promise<void> {
    const novo = await controle?.recarregarJogador();
    if (novo) {
      j = { ...j, ...novo };
      atualizarHud();
    }
  }

  const FUNDOS: Record<string, string> = { pallet: "campo", lab: "cidade", rota1: "mato", costa1: "agua", costa2: "agua", gruta: "caverna", cromatica: "caverna", vale: "floresta", caminho_va: "floresta", reserva: "campo", plato: "ginasio" };
  const fundoDoMapa = (id: string | null | undefined): string => {
    const m = id ?? "";
    if (FUNDOS[m]) return FUNDOS[m];
    if (m.startsWith("gin_") || m.startsWith("liga_")) return "ginasio";
    if (m.startsWith("rota")) return "mato";
    return ["porto", "argila", "verdelume", "azurana", "quartzo", "ambar", "carmesim", "ametista", "obsidiana"].includes(m) ? "cidade" : "campo";
  };

  // aquece a função de batalha (o motor é pesado): a 1ª batalha da sessão não precisa esperar o carregamento
  const aquecer = (): void => { void supabase.functions.invoke("batalha", { body: { acao: "aquecer" } }).catch(() => undefined); };
  aquecer();
  window.setInterval(() => { if (!document.hidden) aquecer(); }, 4 * 60 * 1000);

  async function lutar(res: ResultadoBatalha): Promise<void> {
    emBatalha = true;
    limparOferta();
    modal.fechar();
    controle?.bloquear(true);
    await carregarReferencias();
    const brilhantes = new Set((await meuTime(j.id)).filter((p) => p.brilhante).map((p) => p.especie_id));
    const estado = await abrirBatalha(res, j.id, { fundo: fundoDoMapa(j.mapa_id), nome: j.nome, aparencia: j.aparencia, brilhantes });
    emBatalha = false;
    controle?.bloquear(false);
    await recarregarJogador();
    void atualizarMissao();
    await resolverPendencias();
    void distribuirPendentes();
    if (estado === "derrota") mostrarAviso("Seus Pokémon precisam descansar: cure-os no Centro Pokémon ou em casa.", 6000);
  }

  /** Fala do treinador, desafio no servidor e batalha. Devolve true se o jogador o venceu. */
  async function aoTreinador(t: TreinadorMapa): Promise<boolean> {
    if (emBatalha) return false;
    const aceitou = await new Promise<boolean>((ok) => {
      const lutar = botao("Aceitar o desafio!", () => { modal.aoFechar(null); modal.fechar(); ok(true); }, "");
      modal.abrir(`${t.classe} ${t.nome}`, el("p", { class: "fala" }, `"${t.falas.antes ?? "Vamos lutar!"}"`), lutar);
      modal.aoFechar(() => ok(false));
      lutar.focus();
    });
    if (!aceitou) return false;
    const { data, error } = await supabase.rpc("desafiar_treinador", { p_treinador: t.id });
    if (error || !data) {
      mostrarAviso(error?.message ?? "Não foi possível começar o desafio.", 5000);
      return false;
    }
    await carregarReferencias();
    await lutar(data as ResultadoBatalha);
    const { data: v } = await supabase.from("treinadores_vencidos").select("treinador").eq("treinador", t.id).maybeSingle();
    return !!v;
  }

  /** Seu desafio foi aceito: a batalha já está pronta no servidor. */
  async function lutarDesafio(): Promise<void> {
    if (emBatalha) return;
    const { data, error } = await supabase.rpc("procurar_pokemon");
    if (error || !data) return void mostrarAviso(error?.message ?? "Nenhuma luta pronta.", 4000, true);
    await lutar(data as ResultadoBatalha);
  }

  // popup para o desafiado aceitar ou recusar na hora
  let popupAberto = false;
  function popupDesafio(d: { id: string; nome: string; amistoso?: boolean }): void {
    if (popupAberto || emBatalha) return;
    popupAberto = true;
    const fundo = el("div", { class: "soc-popup", role: "alertdialog" });
    const fechar = (): void => { fundo.remove(); popupAberto = false; };
    const aceitar = botao("Aceitar (−1 PA)", async () => {
      aceitar.disabled = true;
      const { error } = await supabase.rpc("desafio_responder", { p_desafio: d.id, p_aceitar: true });
      if (error) { aceitar.disabled = false; return void mostrarAviso(error.message, 5000, true); }
      fechar();
      modal.fechar();
      atualizarHud();
      void recarregarJogador();
      void lutarDesafio();
    }, "");
    const recusar = botao("Recusar", async () => { await supabase.rpc("desafio_responder", { p_desafio: d.id, p_aceitar: false }); fechar(); }, "sec");
    const depois = botao("Decidir depois", fechar, "sec");
    fundo.append(el("div", { class: "soc-popup-caixa" },
      el("h2", {}, `${d.nome} desafiou você!`),
      el("p", { class: "soc-tag" }, d.amistoso ? "Duelo amistoso" : "Duelo valendo"),
      el("p", { class: "sub" }, d.amistoso
        ? "Todos começam com HP e PP cheios e nada muda nos seus Pokémon. Não dá XP."
        : "HP e PP são os reais: quem perder fica com os Pokémon feridos. O vencedor ganha XP pelos Pokémon derrotados."),
      el("p", { class: "sub" }, "Custa 1 PA para cada um. A luta é ao vivo: os dois escolhem ao mesmo tempo."),
      el("div", { class: "soc-popup-bts" }, aceitar, recusar, depois)));
    document.body.append(fundo);
  }

  // avisos de desafios e trocas recebidos
  const vistos = new Set<string>();
  const verificarSocial = async (): Promise<void> => {
    if (document.hidden || emBatalha) return;
    const p = await carregarPendencias();
    if (!p) return;
    for (const d of p.desafios_recebidos) if (!vistos.has(d.id)) { vistos.add(d.id); popupDesafio(d); }
    for (const t of p.trocas_recebidas) if (!vistos.has(t.id)) { vistos.add(t.id); mostrarAviso(`${t.nome} propôs uma troca! Abra Treinador › Jogadores.`, 7000); }
    if (p.batalha && !emBatalha && !vistos.has(p.batalha.id)) {
      vistos.add(p.batalha.id);
      mostrarAviso("Seu desafio foi aceito! Entrando no duelo...", 3000);
      window.setTimeout(() => void lutarDesafio(), 1200);
    }
  };
  const tempoSocial = window.setInterval(() => void verificarSocial(), 4000);
  const tempoMissao = window.setInterval(() => { if (!document.hidden) void atualizarMissao(); }, 30000);

  async function listarTreinadores(mapaId: string): Promise<TreinadorMapa[]> {
    const [{ data: ts }, { data: vs }] = await Promise.all([
      supabase.from("treinadores").select("id, x, y, direcao, visao, nome, classe, aparencia, falas").eq("mapa_id", mapaId),
      supabase.from("treinadores_vencidos").select("treinador").eq("jogador", j.id),
    ]);
    const venceu = new Set((vs ?? []).map((v: { treinador: string }) => v.treinador));
    const { data: ms } = await supabase.from("npcs_missao").select("id, x, y, direcao, nome, classe, aparencia").eq("mapa_id", mapaId);
    const npcs = ((ms ?? []) as Omit<TreinadorMapa, "vencido" | "visao" | "falas" | "missao">[]).map((n) => ({ ...n, visao: 0, falas: {}, vencido: false, missao: true }));
    return [...((ts ?? []) as Omit<TreinadorMapa, "vencido">[]).map((t) => ({ ...t, vencido: venceu.has(t.id) })), ...npcs];
  }

  async function procurar(): Promise<void> {
    if (emBatalha || !oferta) return;
    cartaoOferta.querySelectorAll("button").forEach((b) => ((b as HTMLButtonElement).disabled = true));
    const { data, error } = await supabase.rpc("procurar_pokemon");
    limparOferta();
    if (error || !data) return void mostrarAviso(error?.message ?? "Nada por aqui.", 3200, true);
    mostrarAviso(`Pokémon à vista! −1 PA (restam ${Math.max(0, j.pa - 1)})`, 3000);
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

  async function comprar(p: Poi, item: string, qtd: number, msg: HTMLElement, saldo: HTMLElement): Promise<void> {
    const { data, error } = await supabase.rpc("comprar_item", { p_poi: p.id, p_item: item, p_qtd: qtd });
    if (error) return void mensagem(msg, error.message);
    const r = data as { dinheiro: number };
    j = { ...j, dinheiro: r.dinheiro };
    saldo.textContent = `Seu dinheiro: ₽ ${r.dinheiro}`;
    atualizarHud();
    mensagem(msg, `Comprou ${qtd}× ${nomeItem(item)}.`, "ok");
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
      nos.push(botao("Acessar as Caixas", () => void abrirCaixas(modal, j.id, mostrarAviso, atualizarHud), "sec"));
    } else if (p.tipo === "centro" || p.tipo === "casa_jogador" || p.acao === "cura") {
      nos.push(botao("Curar meu time", () => void curar(msg), ""));
      if (p.tipo === "centro") nos.push(botao("Acessar as Caixas", () => void abrirCaixas(modal, j.id, mostrarAviso, atualizarHud), "sec"));
    } else if (p.acao === "dica" || p.acao === "quadro") {
      const lista = p.acao === "dica" ? p.dicas : p.textos;
      if (lista?.length) nos.push(el("p", { class: "sub" }, `“${lista[Math.floor(Math.random() * lista.length)]}”`));
    } else if (p.acao === "loja") {
      await carregarReferencias();
      const saldo = el("p", { class: "sub" }, `Seu dinheiro: ₽ ${j.dinheiro ?? 0}`);
      nos.push(saldo);
      for (const it of p.estoque ?? []) {
        const linha = el("div", { class: "item-cartao" }, el("div", { class: "item-txt" }, el("strong", {}, nomeItem(it.item)), el("small", {}, `₽ ${it.preco}`)));
        for (const q of [1, 5]) {
          linha.appendChild(botao(`Comprar ×${q}`, () => void comprar(p, it.item, q, msg, saldo), "sec"));
        }
        nos.push(linha);
      }
    } else if (p.acao === "presente") {
      nos.push(botao("Aceitar o presente", async () => {
        const { data, error } = await supabase.rpc("usar_poi", { p_poi: p.id });
        if (error) return void mensagem(msg, error.message);
        const r = data as { texto?: string };
        mensagem(msg, r.texto ?? "Você recebeu um presente!", "ok");
      }, ""));
    } else if (p.acao === "troca") {
      await carregarReferencias();
      const time = (await meuTime(j.id)).filter((x) => x.especie_id === p.quer);
      if (!time.length) nos.push(el("p", { class: "sub" }, `Você precisa ter um ${especie(p.quer ?? 0).nome} para trocar por um ${especie(p.da ?? 0).nome}.`));
      for (const x of time) {
        nos.push(botao(`Trocar ${especie(x.especie_id).nome} (nv ${x.nivel}) por ${especie(p.da ?? 0).nome}`, async () => {
          const { data, error } = await supabase.rpc("usar_poi", { p_poi: p.id, p_pokemon: x.id });
          if (error) return void mensagem(msg, error.message);
          const r = data as { recebeu?: string };
          mensagem(msg, `Troca feita! Você recebeu ${r.recebeu ?? "um novo Pokémon"}.`, "ok");
        }, ""));
      }
    } else if (p.acao === "liga") {
      nos.push(el("p", { class: "sub" }, `Insígnias: ${(j as { insignias?: string[] }).insignias?.length ?? 0} de 8.`));
    }
    nos.push(msg);
    modal.abrir(p.nome, ...nos);
  }

  /** Falar com o treinador ao lado ou usar o ponto de interesse do tile. Devolve true se havia algo para interagir. */
  function interagir(): boolean {
    if (!lugar) return false;
    if (lugar.npc) {
      void controle?.conversar(lugar.npc.id);
      return true;
    }
    if (lugar.poi) {
      void abrirPoi(lugar.poi);
      return true;
    }
    return false;
  }
  btnInteragir.addEventListener("click", () => {
    interagir();
  });

  const aoTecla = (e: KeyboardEvent) => {
    if ((e.ctrlKey || e.metaKey) && ["+", "=", "-", "_", "0"].includes(e.key)) {
      e.preventDefault();
      controle?.zoom(e.key === "0" ? 0 : e.key === "-" || e.key === "_" ? -1 : 1);
      return;
    }
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
    if ((e.key === "m" || e.key === "M") && !e.ctrlKey && !e.metaKey && !e.altKey) {
      if (modal.aberto() && modal.raiz.querySelector(".mm-fundo")) { modal.fechar(); e.preventDefault(); }
      else if (!emBatalha && !modal.aberto() && !document.querySelector(".classe-obrig, .manut-tela")) { abrirMundi(); e.preventDefault(); }
      return;
    }
    if (emBatalha || modal.aberto()) return;
    if (e.key === "e" || e.key === "E" || e.key === " " || e.key === "Enter") {
      if (!interagir() && oferta) void procurar();
      e.preventDefault();
    }
    if ((e.key === "b" || e.key === "B") && oferta) {
      void procurar();
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
  const botoes = el("div", { class: "grupo" }, botao("🗺", () => { if (!emBatalha) abrirMundi(); }, "sec botao-menu botao-mapa"), botao("−", () => controle?.zoom(-1), "sec botao-menu botao-zoom"), botao("+", () => controle?.zoom(1), "sec botao-menu botao-zoom"));

  const marca = el("img", { class: "marca-img", src: `${import.meta.env.BASE_URL}assets/logo-rafar.png`, alt: "Rafar" });
  const abrirMundi = (): void => void atualizarMissao().then(() => abrirMapaMundi(modal, (m) => controle?.viajar(m) ?? Promise.resolve(false), mostrarAviso, missaoAtual?.estado === "ativa" && missaoAtual.mapa_id ? { mapa_id: missaoAtual.mapa_id, mapa_nome: missaoAtual.mapa_nome ?? "", nome: missaoAtual.nome, objetivo: missaoAtual.objetivo ?? "" } : null));
  const { raiz: nav } = barraNavegacao(
    [
      {
        rotulo: "Jogar",
        itens: () => [
          { rotulo: "Mapa Mundi (tecla M)", fn: abrirMundi, oculto: emBatalha },
          { rotulo: "Buscar Pokémon (1 PA)", fn: () => void procurar(), oculto: !oferta },
          { rotulo: "Interagir", fn: () => { interagir(); }, oculto: !(lugar?.poi || lugar?.npc) },
          { rotulo: "Desistir da missão", fn: abrirDesistirMissao, oculto: missaoAtual?.estado !== "ativa" },
          { rotulo: "Onde estou", fn: () => abrirInfoLugar() },
          { rotulo: "Estou preso (destravar)", fn: () => void controle?.destravar() },
          { rotulo: "Como jogar", fn: () => abrirAjuda() },
        ],
      },
      {
        rotulo: "Treinador",
        itens: () => [
          { rotulo: "Painel do treinador", fn: () => void abrirDashboard() },
          { rotulo: "Habilidades", fn: () => void abrirHabilidades(modal, mostrarAviso, atualizarHud) },
          { rotulo: "Ações (PA)", fn: () => void abrirAcoes(modal, j.id, mostrarAviso, () => void recarregarJogador()) },
          { rotulo: "Jogadores (desafios e trocas)", fn: () => void abrirSocial(modal, j.id, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }, lutarDesafio) },
          { rotulo: "Caixas", fn: () => void abrirCaixas(modal, j.id, mostrarAviso, atualizarHud) },
          { rotulo: "Organizar time / Seguidor", fn: () => void abrirOrganizar(modal, j.id, mostrarAviso, () => void controle?.atualizarSeguidor()) },
        ],
      },
      { rotulo: "Minha conta", itens: () => [{ rotulo: "Meus personagens / Reiniciar", fn: () => void abrirPersonagens() }, { rotulo: "Trocar senha", fn: abrirMenu }, { rotulo: "Sair", fn: () => void supabase.auth.signOut() }] },
      ...(j.papel === "mestre"
        ? [{ rotulo: "Mestre", itens: () => [
            { rotulo: "Gestão de jogadores", fn: () => void import("./gestao").then((m) => m.abrirGestao(modal, mostrarAviso)) },
            { rotulo: "Eventos", fn: () => void abrirEventos(modal, mostrarAviso) },
            { rotulo: "Missões dos jogadores", fn: () => void abrirMissoesMestre() },
            { rotulo: "Ferramentas (importar, repor PA)", fn: abrirMenu },
          ] }]
        : []),
    ],
    marca,
  );
  const rodape = el("div", { class: "barra rodape" }, formChat, botoes);
  const dica = el("p", { class: "dica" }, "Setas/WASD andam · E interage · M abre o Mapa Mundi · B busca o Pokémon da prévia · Ctrl + / Ctrl − ajustam o zoom");

  const faixaEventos = iniciarFaixaEventos(modal);
  tela.append(faixaEventos);
  const atalho = (nome: string, rotulo: string, fn: () => void) => {
    const b = el("button", { type: "button", class: "nav-atalho", "aria-label": rotulo, title: rotulo }, icone(nome), el("span", { class: "nav-atalho-rot" }, rotulo));
    b.addEventListener("click", (e) => { e.stopPropagation(); fn(); });
    return b;
  };
  nav.querySelector(".nav-grupos")?.prepend(
    atalho("painel", "Painel", () => void abrirDashboard()),
    atalho("time", "Time", () => void abrirTime()),
    atalho("mochila", "Mochila", () => void abrirMochila()),
    atalho("pokedex", "Pokédex", () => void abrirPokedex()),
  );
  void dica;
  const minha = montar([el("div", { class: "jogo" }, nav, el("div", { class: "cartucho" }, tela, rodape), modal.raiz)], true);

  const { iniciarMundo } = await import("../game/mundo");
  if (minha !== geracaoAtual()) return;
  let iniciado: Controle;
  try {
    iniciado = await iniciarMundo(tela, j, {
      aoLugar: (l) => {
        lugar = l;
        j = { ...j, mapa_id: l.mapa_id, x: l.x, y: l.y };
        btnInteragir.hidden = !(l.poi || l.npc);
        btnInteragir.textContent = l.npc ? `Falar com ${l.npc.nome}` : "Interagir";
        agendarOferta(l);
        atualizarHud();
      },
      aoPasso: () => limparOferta(),
      aoJogador: (novo) => {
        j = { ...j, ...novo };
        atualizarHud();
      },
      aviso: mostrarAviso,
      treinadores: listarTreinadores,
      aoTreinador,
      aoNpcMissao: async (t) => { await conversarNpc(modal, t.id, `${t.classe} ${t.nome}`, mostrarAviso, () => { void atualizarMissao(); atualizarHud(); void recarregarJogador(); }); },
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
  const checarClasse = (d: Pick<PingEstado, "personagem" | "classe" | "mestre">): void => { if (d.personagem && !d.classe && !d.mestre) void exigirClasse(mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }); };
  void consultar().then((d) => { if (d) checarClasse(d); });
  const sairDoPing = aoEstado(checarClasse);
  aoTrocarTela(() => {
    sairDoPing();
    window.clearInterval(tempoSocial);
    window.clearInterval(tempoMissao);
    window.removeEventListener("keydown", aoTecla);
    iniciado.encerrar();
  });

  // configuração, referências e batalha pendente
  void (async () => {
    const [{ data: cfg }, temRef] = await Promise.all([supabase.from("config").select("valor").eq("chave", "pa_por_dia").maybeSingle(), carregarReferencias()]);
    paMax = Number(cfg?.valor ?? 30) || 30;
    atualizarHud();
    void atualizarMissao();
    void resolverPendencias();
    void distribuirPendentes();
    void verificarSocial();
    if (!temRef) {
      mostrarAviso(j.papel === "mestre" ? "Mestre: abra Menu e clique em \"Importar dados do jogo\" e depois \"Importar sprites\"." : "O mundo ainda está sendo preparado. Tente de novo em instantes.", 8000);
      return;
    }
    if ((await meuTime(j.id)).length === 0) mostrarAviso("Fale com o Professor Carvalho: chegue ao lado dele e use Interagir (ou a tecla E) para escolher seu primeiro Pokémon.", 9000);
    const { data: ativa } = await supabase.from("batalhas").select("id").eq("estado", "ativa").maybeSingle();
    if (ativa) {
      const { data } = await supabase.rpc("procurar_pokemon");
      if (data) await lutar(data as ResultadoBatalha);
    }
  })();
}
