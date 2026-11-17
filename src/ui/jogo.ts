import { supabase, type Direcao, type Jogador } from "../supabase";
import { aoTrocarTela, el, geracaoAtual, mensagem, montar } from "./dom";
import type { Controle, Lugar, Poi, TreinadorMapa } from "../game/mundo";
import { abrirBatalha, type ResultadoBatalha } from "./batalha";
import {
  barraHp, carregarReferencias, chipsTipo, COR_TIPO, especie, golpe, imagemPokemon, meuTime, NOME_TIPO, nomeItem, textoSobre,
  nomePokemon, todasEspecies, type PokemonRow,
} from "./dados";
import { carregarMissao, conversarNpc, conversarPedra, type MissaoEstado } from "./missao";
import { criarDiario } from "./quests";
import { abrirSocial, carregarPendencias } from "./social";
import { resolverPendencias } from "./momentos";
import { fichaEspecie, painelBusca } from "./pokedex";
import { distribuirPendentes } from "./evolucao";
import { abrirMapaMundi } from "./mapamundi";
import { abrirCaixas } from "./caixa";
import { abrirHabilidades, abrirAcoes, acaoPA, textoEventos, exigirClasse } from "./habilidades";
import { aoEstado, consultar, type PingEstado } from "./acesso";
import { abrirMochila as abrirMochilaSS } from "./mochila";
import { abrirMTs, abrirLojaMT } from "./mts";
import { abrirResumo } from "./resumo";
import { caixaFala, definirFalante } from "./fala";
import { iniciarChat } from "./chat";
import { criarAtalhos, type AcaoAtalho } from "./atalhos";
import { blocoInsignias } from "./cartao";
import { abrirOrganizar } from "./organizar";
import { criarReserva } from "./reserva";
import { abrirCreditos } from "./creditos";
import { aparenciasLiberadas, preencherGrade } from "./personagem";
import { abrirResetGolpes } from "./resetgolpes";
import { abrirEventos, iniciarFaixaEventos } from "./eventos";
import { carregarMvMapa, carregarPistas, ehDesafiante, interagirMv, mostrarPistas, mostrarPremiosNovos, observarPokemon } from "./mundovivo";
import { abrirLiga, abrirInscricaoLiga, verificarLiga } from "./liga";
import { abrirCasa, abrirCheckin, abrirConquistas, abrirCosmeticos, abrirMiniquests, abrirRanking, verificarNovidades } from "./engajamento";

function botao(texto: string, fn: () => void, classe = "sec"): HTMLButtonElement {
  const b = el("button", { type: "button", class: classe }, texto);
  b.addEventListener("click", fn);
  return b;
}

/** Painel modal reutilizável. */
function criarModal(): { raiz: HTMLElement; voltarPara: (reabrir: (() => void) | null) => void; abrir: (titulo: string, ...nos: Node[]) => void; acoes: (...nos: Node[]) => void; fechar: () => void; aberto: () => boolean; aoFechar: (fn: (() => void) | null) => void } {
  let ao: (() => void) | null = null;
  const titulo = el("h1", {});
  const corpo = el("div", { class: "modal-corpo" });
  const retorno: (() => void)[] = [];
  const voltar = el("button", { type: "button", class: "modal-voltar", hidden: "" }, "← Voltar");
  voltar.addEventListener("click", () => { const r = retorno.pop(); voltar.hidden = retorno.length === 0; r?.(); });
  const fechar = () => {
    retorno.length = 0; voltar.hidden = true;
    raiz.hidden = true;
    const f = ao;
    ao = null;
    f?.();
  };
  const x = el("button", { type: "button", class: "modal-x", "aria-label": "Sair do painel" }, "✕");
  x.addEventListener("click", fechar);
  const acoesSlot = el("div", { class: "modal-acoes" });
  const caixaModal = el("div", { class: "painel modal" }, el("div", { class: "modal-topo" }, voltar, titulo, acoesSlot, x), corpo, botao("Fechar", fechar));
  const raiz = el("div", { class: "menu", hidden: "" }, caixaModal);
  raiz.addEventListener("click", (e) => {
    if (e.target === raiz) fechar();
  });
  return {
    raiz,
    voltarPara: (r) => { if (r) retorno.push(r); else retorno.length = 0; voltar.hidden = retorno.length === 0; },
    abrir: (t, ...nos) => {
      voltar.hidden = retorno.length === 0;
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

export async function telaJogo(inicial: Jogador): Promise<void> {
  let j: Jogador = { ...inicial };
  let controle: Controle | null = null;
  let lugar: Lugar | null = null;
  let emBatalha = false;
  let paMax = 30;
  let missaoAtual: MissaoEstado | null = null;
  const hudMissao = el("button", { type: "button", class: "hud-missao", hidden: "", "aria-label": "Missão ativa" });
  const diario = criarDiario((q) => {
    void abrirMapaMundi(modal, (m) => controle?.viajar(m) ?? Promise.resolve(false), mostrarAviso, q.mapa_id ? { mapa_id: q.mapa_id, mapa_nome: q.mapa ?? "", nome: q.titulo, objetivo: q.passo ?? "" } : undefined);
  });
  const atualizarMissao = async (): Promise<void> => {
    try { missaoAtual = await carregarMissao(); } catch { missaoAtual = null; }
    void diario.atualizar();
    void controle?.atualizarMarcas();
    hudMissao.hidden = true; // substituído pelo Diário de Quests
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
  const reserva = criarReserva(modal, mostrarAviso, () => { void recarregarJogador(); atualizarHud(); });

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
    const safari = j.mapa_id === "reserva" && o.bioma !== "agua";
    const buscar = el("button", { type: "button", class: "oferta-buscar" }, safari ? "Observar (Safári)" : "Buscar (1 PA)");
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
  cartaoTreinador.setAttribute("role", "button"); cartaoTreinador.setAttribute("tabindex", "0"); cartaoTreinador.title = "Abrir o menu";
  cartaoTreinador.addEventListener("click", () => abrirMenuAvatar());
  cartaoTreinador.addEventListener("keydown", (ev) => { if (ev.key === "Enter") abrirMenuAvatar(); });
  tela.append(aviso, hudMissao, diario.raiz, reserva.faixa, acoes, cartaoOferta, dpad);

  // ---------- painéis ----------
  const msgPainel = (): HTMLElement => el("p", { class: "msg", role: "status" });

  function abas(ativa: "time" | "mochila" | "pokedex" | "mts"): HTMLElement {
    const mk = (id: "time" | "mochila" | "pokedex" | "mts", rot: string, fn: () => Promise<void>) => {
      const b = el("button", { type: "button", class: `aba${id === ativa ? " ativa" : ""}`, "aria-pressed": String(id === ativa) }, id === "mts" ? el("span", { class: "ico-emoji" }, "💿") : icone(id), el("span", {}, rot));
      b.addEventListener("click", () => void fn());
      return b;
    };
    return el("div", { class: "abas" }, mk("time", "Time", abrirTime), mk("mochila", "Mochila", abrirMochila), mk("mts", "MTs", abrirMTsJanela), mk("pokedex", "Pokédex", abrirPokedex));
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
      const pt = el("button", { type: "button", class: "cartao-pontos" }, `⭐ Distribuir ${p.evo_pend.pool} pontos de atributo`);
      pt.addEventListener("click", (ev) => { ev.stopPropagation(); void distribuirPendentes().then(() => abrirTime()); });
      c.querySelector(".cartao-info")?.append(pt);
    }
    c.querySelector(".cartao-info")?.append(el("div", { class: "cartao-acoes" },
      btn("Resumo", () => abrirResumo(modal, p, () => void abrirTime(), "resumo", { uid: j.id, aviso: mostrarAviso, aoMudar: () => void controle?.atualizarSeguidor() })),
      btn("Treinar · 2 PA", () => void acaoPA("acao_treinar", { p_pokemon: p.id }, j.id, mostrarAviso, refrescar, (d) => `${nomePokemon(p)} treinou! ${textoEventos((d.eventos ?? []) as Parameters<typeof textoEventos>[0])}`)),
      btn("Cuidar · 1 PA", () => void acaoPA("acao_cuidar", { p_pokemon: p.id }, j.id, mostrarAviso, refrescar, (d) => `Você cuidou de ${nomePokemon(p)}! Amizade ${d.amizade}. ${textoEventos((d.eventos ?? []) as Parameters<typeof textoEventos>[0])}`))));
    return c;
  }

  async function abrirMochila(): Promise<void> {
    await abrirMochilaSS(modal, j.id, j.dinheiro ?? 0, mostrarAviso, atualizarHud, abas("mochila"));
  }

  async function abrirMTsJanela(): Promise<void> {
    await abrirMTs(modal, mostrarAviso, abas("mts"), () => { atualizarHud(); void recarregarJogador(); });
  }

  /** Lendários e pseudo-lendários da Geração 1: só aparecem na Pokédex depois de vistos e nunca têm local. */
  const DEX_RAROS = new Set([144, 145, 146, 150, 151, 147, 148, 149]);
  async function abrirPokedex(): Promise<void> {
    const { data } = await supabase.from("pokedex").select("especie_id, capturado").eq("jogador", j.id);
    const vistos = new Map<number, boolean>();
    for (const r of (data ?? []) as { especie_id: number; capturado: boolean }[]) vistos.set(r.especie_id, r.capturado);
    const cap = [...vistos.values()].filter(Boolean).length;
    const celulas = todasEspecies().map((e) => {
      const v = vistos.get(e.id);
      const raro = DEX_RAROS.has(e.id);
      const c = el("button", { type: "button", class: `dex ${v === undefined ? "novo" : v ? "cap" : "visto"}`, title: "Ver detalhes" });
      c.addEventListener("click", () => void abrirFichaDex(e.id));
      c.append(el("span", { class: "dex-n" }, String(e.id).padStart(3, "0")));
      if (v !== undefined || !raro) c.append(imagemPokemon("frente", e.id, "dex-img"));
      else c.append(el("div", { class: "dex-img vazio" }, "?"));
      c.append(el("span", { class: "dex-nome" }, v === undefined && raro ? "???" : e.nome));
      if (v) c.append(el("span", { class: "dex-sel", title: "Capturado" }, "", el("i", { class: "dex-ball" })));
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
    const [time, painel, insBloco] = await Promise.all([meuTime(j.id), supabase.rpc("meu_painel"), blocoInsignias(j.id)]);
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
        el("div", { class: "dash-pk-info" }, el("strong", {}, nomePokemon(p)), el("span", {}, `Nv ${p.nivel} · ${p.hp_atual}/${p.hp_max} HP`), chipsTipo(p.especie_id), el("div", { class: "hp-trilho" }, fill)));
    });
    const secao = (tit: string, itens: [string, () => void][]) => el("div", { class: "dash-sec" }, el("label", {}, tit), el("div", { class: "dash-menu" }, ...itens.map(([r, f]) => botao(r, () => { modal.voltarPara(() => void abrirDashboard()); f(); }, "sec"))));
    const recarregar = () => { atualizarHud(); void recarregarJogador(); };
    const menus = el("div", { class: "dash-menus" },
      secao("Progresso", [["🏅 Conquistas", () => void abrirConquistas(modal, mostrarAviso)], ["📊 Ranking", () => void abrirRanking(modal, mostrarAviso)], ["🎯 Desafios da semana", () => void abrirMiniquests(modal, mostrarAviso)], ["📅 Check-in diário", () => void abrirCheckin(modal, mostrarAviso, recarregar)], ["🎖 Títulos e molduras", () => void abrirCosmeticos(modal, mostrarAviso)]]),
      secao("Treinador", [["Habilidades", () => void abrirHabilidades(modal, mostrarAviso, atualizarHud)], ["Ações (PA)", () => void abrirAcoes(modal, j.id, mostrarAviso, () => void recarregarJogador())], ["Organizar time / Seguidor", () => void abrirOrganizar(modal, j.id, mostrarAviso, () => void controle?.atualizarSeguidor())], ["🏠 Minha casa e ovos", () => void abrirCasa(modal, mostrarAviso, recarregar)]]),
      secao("Social e conta", [["Jogadores (desafios e trocas)", () => void abrirSocial(modal, j.id, mostrarAviso, recarregar, lutarDesafio)], ["Meus personagens / Reiniciar", () => void abrirPersonagens()], ["📜 Créditos", () => void abrirCreditos(modal)]]));
    modal.abrir("Painel do treinador", el("div", { class: "dash-wide" },
      el("div", { class: "dash-esq" }, cab, grade, insBloco),
      el("div", { class: "dash-dir" }, el("label", {}, "Time ativo"),
        linhas.length ? el("div", { class: "dash-time" }, ...linhas) : el("p", { class: "sub" }, "Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório."), menus)));
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
      const gradeA = el("div", { class: "aparencias" });
      void aparenciasLiberadas().then((lista) => preencherGrade(gradeA, lista, (n) => { aparencia = n; }));
      const criar = botao("Criar 2º personagem e jogar com ele", async () => {
        const { error } = await supabase.rpc("criar_novo_personagem", { p_nome: nome.value, p_aparencia: aparencia });
        if (error) return void mensagem(msg, error.message);
        location.reload();
      }, "");
      nos.push(el("label", {}, "Criar segundo personagem"), nome, gradeA, criar);
    }

    const zerar = confirmar(botao("Apagar todos os meus personagens", () => undefined, "sec"), "Apagar todos os meus personagens", "Confirmar: apagar TUDO e criar do zero?", async () => {
      const { error } = await supabase.rpc("apagar_todos_meus_personagens");
      if (error) return void mensagem(msg, error.message);
      location.reload();
    });
    nos.push(el("label", {}, "Começar do zero"), el("p", { class: "sub" }, "Apaga TUDO: seus personagens (o atual e o reserva), nome, visual, classe, time, mochila, Pokédex, dinheiro e progresso. Você volta à criação de personagem e escolhe tudo de novo. Não dá para desfazer."), zerar, msg);
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
        mensagem(msg, `${p.nome} foi apagado por completo e criará o personagem de novo ao entrar.`, "ok");
        if (p.id === j.id) window.setTimeout(() => location.reload(), 900);
      });
      return b;
    });
    modal.abrir("Resetar jogador", el("p", { class: "sub" }, "Apaga TUDO do jogador: nome, visual, classe, time, mochila, Pokédex, missões e progresso. Só o login fica; ao entrar, ele escolhe nome, visual e classe de novo."), ...linhas, msg);
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
    await supabase.rpc("pa_garantir");   // recarga diária das 6h (a agenda do servidor faz o mesmo; isto cobre quem já está online)
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
    void verificarNovidades(mostrarAviso);
    if (estado === "derrota") mostrarAviso("Seus Pokémon precisam descansar: cure-os no Centro Pokémon ou em casa.", 6000);
  }

  /** Fala do treinador, desafio no servidor e batalha. Devolve true se o jogador o venceu. */
  async function aoTreinador(t: TreinadorMapa): Promise<boolean> {
    if (emBatalha) return false;
    const aceitou = await new Promise<boolean>((ok) => {
      const lutar = botao(ehDesafiante(t.id) ? `Aceitar o desafio! (−${custoDesafiante} PA)` : "Aceitar o desafio!", () => { modal.aoFechar(null); modal.fechar(); ok(true); }, "");
      definirFalante(t.aparencia);
      modal.abrir(`${t.classe} ${t.nome}`, caixaFala(`${t.classe} ${t.nome}`, t.falas.antes ?? "Vamos lutar!", lutar));
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
  const tempoSocial = window.setInterval(() => void verificarSocial(), 6000);
  const tempoMissao = window.setInterval(() => { if (!document.hidden) { void atualizarMissao(); void verificarNovidades(mostrarAviso); void recarregarJogador(); void verificarMundoVivo(); } }, 30000);
  const vigiarLiga = (): void => {
    if (document.hidden) return;
    void verificarLiga(mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }).then((e) => {
      if (e?.minha?.em_batalha && e.na_arena && !emBatalha) void lutarDesafio();
    });
  };
  const tempoLiga = window.setInterval(vigiarLiga, 15000);
  window.setTimeout(vigiarLiga, 5000);
  window.setTimeout(() => void recarregarJogador(), 1500);
  window.setTimeout(() => void verificarNovidades(mostrarAviso), 3000);

  let turnoMv = -1;
  async function verificarMundoVivo(): Promise<void> {
    try {
      const { data } = await supabase.rpc("mv_garantir");
      const d = data as { ativo?: boolean; turno?: number } | null;
      if (d?.ativo && typeof d.turno === "number" && d.turno !== turnoMv) {
        if (turnoMv !== -1) mostrarAviso("O mundo mudou: novos rostos pelos caminhos... e algo raro foi avistado.", 5500);
        turnoMv = d.turno;
        if (turnoMv === -1) return;
      }
      if (d?.ativo) void mostrarPremiosNovos(mostrarAviso);
    } catch { /* sem mundo vivo */ }
  }
  window.setTimeout(() => void verificarMundoVivo(), 4000);
  let custoDesafiante = 2;
  async function listarTreinadores(mapaId: string): Promise<TreinadorMapa[]> {
    const mv = await carregarMvMapa(mapaId); // gera o turno/dia se preciso e limpa os desafiantes antigos antes de listar
    custoDesafiante = mv.desafiante_pa ?? 2;
    const [{ data: ts }, { data: vs }, { data: rev }, { data: mqs }] = await Promise.all([
      supabase.from("treinadores").select("id, x, y, direcao, visao, nome, classe, aparencia, falas").eq("mapa_id", mapaId).not("id", "like", "lgn_%"),
      supabase.from("treinadores_vencidos").select("treinador").eq("jogador", j.id),
      supabase.rpc("revanche_disponivel"),
      supabase.rpc("miniquests_mapa", { p_mapa: mapaId }),
    ]);
    const emRevanche = new Set((Array.isArray(rev) ? rev : []) as string[]);
    const venceu = new Set((vs ?? []).map((v: { treinador: string }) => v.treinador));
    const { data: ms } = await supabase.from("npcs_missao").select("id, x, y, direcao, nome, classe, aparencia").eq("mapa_id", mapaId);
    const npcs = ((ms ?? []) as Omit<TreinadorMapa, "vencido" | "visao" | "falas" | "missao">[]).map((n) => ({ ...n, visao: 0, falas: {}, vencido: false, missao: true }));
    const { data: pds } = await supabase.from("pedra_etapas").select("id, x, y, direcao, nome, classe, aparencia").eq("mapa_id", mapaId);
    const pedras = ((pds ?? []) as Omit<TreinadorMapa, "vencido" | "visao" | "falas" | "missao">[]).map((n) => ({ ...n, visao: 0, falas: {}, vencido: false, missao: true }));
    const prof: TreinadorMapa[] = mapaId === "lab"
      ? [{ id: "prof-carvalho", x: 6, y: 6, direcao: "baixo", nome: "Carvalho", classe: "Prof.", aparencia: 13, visao: 0, falas: {}, vencido: false, missao: true } as unknown as TreinadorMapa]
      : [];
    const normais = ((ts ?? []) as Omit<TreinadorMapa, "vencido">[]).filter((t) => !t.id.startsWith("mq_"))
      .map((t) => (ehDesafiante(t.id) ? { ...t, visao: 0, vencido: venceu.has(t.id) } : emRevanche.has(t.id) ? { ...t, visao: 0, vencido: false } : { ...t, vencido: venceu.has(t.id) }));
    const vivos: TreinadorMapa[] = mv.ativo ? [
      ...(mv.npcs ?? []).map((n) => ({ id: n.id, x: n.x, y: n.y, direcao: n.direcao, nome: n.nome, classe: n.classe, aparencia: n.aparencia, visao: 0, falas: {}, vencido: false, missao: true } as TreinadorMapa)),
      ...(mv.fixos ?? []).map((f) => ({ id: f.id, x: f.x, y: f.y, direcao: f.direcao, nome: f.tipo === "mural" ? "" : f.nome, classe: f.tipo === "mural" ? "Mural" : "Fofoqueiro", aparencia: f.aparencia, visao: 0, falas: {}, vencido: false, missao: true, tipo: f.tipo } as TreinadorMapa)),
      ...(mv.pokemon ?? []).filter((p) => !p.tentou).map((p) => ({ id: "mvpk", x: p.x, y: p.y, direcao: p.direcao, nome: "raro", classe: "Algo", aparencia: 12, visao: 0, falas: {}, vencido: false, missao: true, tipo: "pokemon" } as TreinadorMapa)),
    ] : [];
    const desafiantes = ((Array.isArray(mqs) ? mqs : []) as Omit<TreinadorMapa, "vencido">[]).map((t) => ({ ...t, vencido: false }));
    return [...normais, ...desafiantes, ...npcs, ...pedras, ...prof, ...vivos];
  }

  let pescaGratis = false;
  window.addEventListener("pkm-pesca", async () => {
    if (emBatalha) return;
    modal.fechar();
    const { data } = await supabase.rpc("gerar_oferta");
    if (!data) return;
    mostrarOferta(data as Oferta);
    pescaGratis = true;
    await procurar();
  });
  async function procurar(): Promise<void> {
    if (emBatalha || !oferta) return;
    if (j.mapa_id === "reserva" && oferta.bioma !== "agua") { limparOferta(); await reserva.observar(); return; }
    cartaoOferta.querySelectorAll("button").forEach((b) => ((b as HTMLButtonElement).disabled = true));
    const gratis = pescaGratis; pescaGratis = false;
    const { data, error } = await supabase.rpc("procurar_pokemon");
    limparOferta();
    if (error || !data) return void mostrarAviso(error?.message ?? "Nada por aqui.", 3200, true);
    mostrarAviso(gratis ? "Fisgou um Pokémon! A luta já estava paga." : `Pokémon à vista! −1 PA (restam ${Math.max(0, j.pa - 1)})`, 3000);
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
      if (p.tipo === "centro") nos.push(botao("🏆 Liga Pokémon (inscrição)", () => void abrirInscricaoLiga(modal, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }), "sec"));
      if (p.tipo === "centro") nos.push(botao("📅 Check-in diário", () => void abrirCheckin(modal, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }), "sec"));
      if (p.tipo === "casa_jogador") nos.push(botao("🏠 Minha casa e ovos", () => void abrirCasa(modal, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }), "sec"));
      if (p.tipo === "centro") nos.push(botao("Acessar as Caixas", () => void abrirCaixas(modal, j.id, mostrarAviso, atualizarHud), "sec"));
      if (p.tipo === "centro" && j.mapa_id !== "pallet" && j.mapa_id !== "porto") nos.push(botao("🔄 Resetar golpes (₽ 1.000)", () => { modal.voltarPara(() => void abrirPoi(p)); void abrirResetGolpes(modal, j.id, j.dinheiro ?? 0, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }); }, "sec"));
    } else if (p.acao === "reserva") {
      await reserva.abrir();
      return;
    } else if (p.acao === "dica" || p.acao === "quadro") {
      const lista = p.acao === "dica" ? p.dicas : p.textos;
      if (lista?.length) nos.push(el("p", { class: "sub" }, `“${lista[Math.floor(Math.random() * lista.length)]}”`));
    } else if (p.acao === "loja") {
      await carregarReferencias();
      const saldo = el("p", { class: "sub" }, `Seu dinheiro: ₽ ${j.dinheiro ?? 0}`);
      nos.push(saldo);
      if (p.tipo === "loja") nos.push(botao("💿 Ver MTs à venda", () => void abrirLojaMT(modal, p.id, j.dinheiro ?? 0, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }), "sec"));
      const gradeLoja = el("div", { class: "grade-loja" });
      for (const it of p.estoque ?? []) {
        const btns = el("div", { class: "item-btns" });
        for (const q of [1, 5]) btns.appendChild(botao(`Comprar ×${q}`, () => void comprar(p, it.item, q, msg, saldo), "sec"));
        gradeLoja.appendChild(el("div", { class: "item-cartao loja" }, el("div", { class: "item-txt" }, el("strong", {}, nomeItem(it.item)), el("small", {}, `₽ ${it.preco}`)), btns));
      }
      nos.push(gradeLoja);
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

  let atalhos: ReturnType<typeof criarAtalhos> | null = null;
  const aoTecla = (e: KeyboardEvent) => {
    if (e.key === "F1") { e.preventDefault(); atalhos?.alternar(); return; }
    if ((e.ctrlKey || e.metaKey) && ["+", "=", "-", "_", "0"].includes(e.key)) {
      e.preventDefault();
      controle?.zoom(e.key === "0" ? 0 : e.key === "-" || e.key === "_" ? -1 : 1);
      return;
    }
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
    if ((e.key === "j" || e.key === "J") && !e.ctrlKey && !e.metaKey && !e.altKey) { if (!emBatalha) { diario.alternar(); e.preventDefault(); } return; }
    if ((e.key === "m" || e.key === "M") && !e.ctrlKey && !e.metaKey && !e.altKey) {
      if (modal.aberto() && modal.raiz.querySelector(".mm-fundo")) { modal.fechar(); e.preventDefault(); }
      else if (!emBatalha && !modal.aberto() && !document.querySelector(".classe-obrig, .manut-tela")) { abrirMundi(); e.preventDefault(); }
      return;
    }
    if (emBatalha || modal.aberto()) return;
    if (/^[0-9]$/.test(e.key) && !e.ctrlKey && !e.metaKey && !e.altKey) { if (atalhos?.executar((Number(e.key) + 9) % 10)) e.preventDefault(); return; }
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
  const chatUi = iniciarChat(modal, j.id, j.nome, mostrarAviso, tela, j.papel === "mestre");
  const chat = el("input", { type: "text", maxlength: "120", placeholder: "Dizer algo (todos veem)...", autocomplete: "off", "aria-label": "Chat" });
  const formChat = el("form", { class: "chat" }, chat);
  formChat.addEventListener("submit", (ev) => {
    ev.preventDefault();
    controle?.dizer(chat.value);
    if (chat.value.trim()) void chatUi.enviarGlobal(chat.value);
    chat.value = "";
    chat.blur();
  });
  const botoes = el("div", { class: "grupo" }, chatUi.botao, botao("🗺", () => { if (!emBatalha) abrirMundi(); }, "sec botao-menu botao-mapa"), botao("−", () => controle?.zoom(-1), "sec botao-menu botao-zoom"), botao("+", () => controle?.zoom(1), "sec botao-menu botao-zoom"));

  const abrirMundi = (): void => void atualizarMissao().then(() => abrirMapaMundi(modal, (m) => controle?.viajar(m) ?? Promise.resolve(false), mostrarAviso, missaoAtual?.estado === "ativa" && missaoAtual.mapa_id ? { mapa_id: missaoAtual.mapa_id, mapa_nome: missaoAtual.mapa_nome ?? "", nome: missaoAtual.nome, objetivo: missaoAtual.objetivo ?? "" } : null));
  const grupos: { rotulo: string; itens: () => ItemMenu[] }[] = [
      {
        rotulo: "Jogar",
        itens: () => [
          { rotulo: "Mapa Mundi (tecla M)", fn: abrirMundi, oculto: emBatalha },
          { rotulo: "Check-in diário", fn: () => void abrirCheckin(modal, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }) },
          { rotulo: "🏆 Liga Pokémon", fn: () => void abrirLiga(modal, mostrarAviso, () => void lutarDesafio(), () => { atualizarHud(); void recarregarJogador(); }) },
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
          { rotulo: "Chat (global e privado)", fn: () => chatUi.abrir() },
          { rotulo: "Amigos", fn: () => chatUi.abrirAmigos() },
          { rotulo: "Jogadores (desafios e trocas)", fn: () => void abrirSocial(modal, j.id, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }, lutarDesafio) },
          { rotulo: "Caixas", fn: () => void abrirCaixas(modal, j.id, mostrarAviso, atualizarHud) },
          { rotulo: "Conquistas", fn: () => void abrirConquistas(modal, mostrarAviso) },
          { rotulo: "Ranking de Treinadores", fn: () => void abrirRanking(modal, mostrarAviso) },
          { rotulo: "Desafios da semana", fn: () => void abrirMiniquests(modal, mostrarAviso) },
          { rotulo: "Minha casa e ovos", fn: () => void abrirCasa(modal, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }) },
          { rotulo: "Títulos e molduras", fn: () => void abrirCosmeticos(modal, mostrarAviso) },
          { rotulo: "Organizar time / Seguidor", fn: () => void abrirOrganizar(modal, j.id, mostrarAviso, () => void controle?.atualizarSeguidor()) },
        ],
      },
      { rotulo: "Minha conta", itens: () => [{ rotulo: "Meus personagens / Reiniciar", fn: () => void abrirPersonagens() }, { rotulo: "Trocar senha", fn: abrirMenu }, { rotulo: "Sair", fn: () => void supabase.auth.signOut() }] },
      ...(j.papel === "mestre"
        ? [{ rotulo: "Mestre", itens: () => [
            { rotulo: "Gestão de jogadores", fn: () => void import("./gestao").then((m) => m.abrirGestao(modal, mostrarAviso)) },
            { rotulo: "Eventos", fn: () => void abrirEventos(modal, mostrarAviso) },
            { rotulo: "Engajamento (módulos, ovos)", fn: () => void import("./mestre_engaj").then((m) => m.abrirMestreEngajamento(modal, mostrarAviso)) },
            { rotulo: "Check-in (calendário)", fn: () => void import("./mestre_engaj").then((m) => m.abrirMestreCheckin(modal, mostrarAviso)) },
            { rotulo: "Conquistas (editar)", fn: () => void import("./mestre_engaj").then((m) => m.abrirMestreConquistas(modal, mostrarAviso)) },
            { rotulo: "Ranking (configurar)", fn: () => void import("./mestre_engaj").then((m) => m.abrirMestreRanking(modal, mostrarAviso)) },
            { rotulo: "Desafios da semana (editar)", fn: () => void import("./mestre_engaj").then((m) => m.abrirMestreMiniquests(modal, mostrarAviso)) },
            { rotulo: "Mundo vivo (NPCs, desafiantes)", fn: () => void import("./mestre_mundo").then((m) => m.abrirMestreMundo(modal, mostrarAviso)) },
            { rotulo: "🏆 Liga Pokémon (torneio)", fn: () => void import("./mestre_liga").then((m) => m.abrirMestreLiga(modal, mostrarAviso)) },
            { rotulo: "Missões dos jogadores", fn: () => void abrirMissoesMestre() },
            { rotulo: "Ferramentas (importar, repor PA)", fn: abrirMenu },
          ] }]
        : []),
  ];
  const rodape = el("div", { class: "barra rodape" }, formChat, botoes);
  const dica = el("p", { class: "dica" }, "Setas/WASD andam · E interage · M abre o Mapa Mundi · B busca o Pokémon da prévia · Ctrl + / Ctrl − ajustam o zoom");

  const faixaEventos = iniciarFaixaEventos(modal);
  tela.append(faixaEventos);
  const rapidos: AcaoAtalho[] = [
    { id: "Time", rotulo: "Time", grupo: "Treinador", fn: () => void abrirTime() },
    { id: "Mochila", rotulo: "Mochila", grupo: "Treinador", fn: () => void abrirMochila() },
    { id: "Pokédex", rotulo: "Pokédex", grupo: "Treinador", fn: () => void abrirPokedex() },
    { id: "MTs", rotulo: "MTs", grupo: "Treinador", fn: () => void abrirMTsJanela() },
  ];
  const todasAcoes = (): AcaoAtalho[] => [
    ...rapidos,
    ...grupos.flatMap((g) => g.itens().map((i) => ({ id: i.rotulo, rotulo: i.rotulo, grupo: g.rotulo, fn: i.fn, oculto: i.oculto }))),
  ];
  const secoesMenu = (lista: AcaoAtalho[], aoEscolher: (a: AcaoAtalho) => void): HTMLElement[] => {
    const porGrupo = new Map<string, AcaoAtalho[]>();
    for (const a of lista) porGrupo.set(a.grupo, [...(porGrupo.get(a.grupo) ?? []), a]);
    return [...porGrupo.entries()].map(([g, as]) => el("section", { class: "menu-sec" }, el("h2", {}, g), el("div", { class: "menu-grade" }, ...as.map((a) => botao(a.rotulo, () => aoEscolher(a), "menu-item")))));
  };
  /** Itens que vivem dentro do Painel do Treinador (continuam disponíveis como atalho). */
  const NO_PAINEL = new Set(["Habilidades", "Ações (PA)", "Jogadores (desafios e trocas)", "Conquistas", "Ranking de Treinadores", "Desafios da semana", "Minha casa e ovos", "Títulos e molduras", "Organizar time / Seguidor", "Check-in diário", "Onde estou", "Meus personagens / Reiniciar"]);
  function abrirMenuAvatar(): void {
    if (emBatalha) return;
    modal.abrir(j.nome, ...secoesMenu(todasAcoes().filter((a) => !a.oculto && !NO_PAINEL.has(a.id)), (a) => { modal.aoFechar(null); if (a.grupo === "Jogar") { modal.fechar(); a.fn(); } else { modal.voltarPara(abrirMenuAvatar); a.fn(); } }));
  }
  const escolherAtalho = (titulo: string, atual: string | null): Promise<string | null | undefined> => new Promise((resolve) => {
    modal.aoFechar(() => resolve(undefined));
    const nos: Node[] = secoesMenu(todasAcoes().filter((a) => a.grupo !== "Minha conta"), (a) => { resolve(a.id); modal.aoFechar(null); modal.fechar(); });
    if (atual) nos.unshift(botao("Remover este atalho", () => { resolve(null); modal.aoFechar(null); modal.fechar(); }, "sec"));
    modal.abrir(titulo, ...nos);
  });
  atalhos = criarAtalhos(j.id, todasAcoes, escolherAtalho);
  tela.append(el("div", { class: "hud-topo" }, cartaoTreinador, atalhos.raiz));
  void dica;
  const minha = montar([el("div", { class: "jogo" }, el("div", { class: "cartucho" }, tela, rodape), modal.raiz)], true);

  const { iniciarMundo } = await import("../game/mundo");
  if (minha !== geracaoAtual()) return;
  let iniciado: Controle;
  try {
    iniciado = await iniciarMundo(tela, j, {
      aoLugar: (l) => {
        lugar = l;
        j = { ...j, mapa_id: l.mapa_id, x: l.x, y: l.y };
        reserva.aoMapa(l.mapa_id);
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
      marcas: async () => { const { data } = await supabase.rpc("quests_marcas"); return (data ?? {}) as Record<string, string>; },
      pistas: carregarPistas,
      aoTreinador,
      aoClicarJogador: (id) => chatUi.abrirCartao(id),
      aoNpcMissao: async (t) => { definirFalante(t.aparencia); if (t.id === "prof-carvalho") { await abrirPoi({ id: "prof", tipo: "lab", x: 6, y: 7 } as unknown as Poi); return; } if (t.id === "mvpk") { await observarPokemon(modal, mostrarAviso, async (r) => { await carregarReferencias(); await lutar(r as ResultadoBatalha); }); atualizarHud(); void recarregarJogador(); return; } if (t.tipo === "fofoqueiro" || t.tipo === "mural") { await mostrarPistas(modal, t.tipo, t.tipo === "mural" ? "Mural de avisos" : "Fofoqueiro"); return; } if (t.id.startsWith("mv_")) { await interagirMv(modal, t.id, `${t.classe} ${t.nome}`, mostrarAviso, () => { void atualizarMissao(); atualizarHud(); void recarregarJogador(); }); return; } if (t.id.startsWith("pd_")) { await conversarPedra(modal, t.id, `${t.classe} ${t.nome}`, mostrarAviso, () => { atualizarHud(); void recarregarJogador(); }); return; } await conversarNpc(modal, t.id, `${t.classe} ${t.nome}`, mostrarAviso, () => { void atualizarMissao(); atualizarHud(); void recarregarJogador(); }); },
    });
  } catch (e) {
    mostrarAviso(e instanceof Error ? e.message : "Não foi possível abrir o jogo.");
    return;
  }
  if (minha !== geracaoAtual()) {
    iniciado.encerrar();
    chatUi.encerrar();
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
    window.clearInterval(tempoLiga);
    window.removeEventListener("keydown", aoTecla);
    chatUi.encerrar();
    iniciado.encerrar();
  });

  // configuração, referências e batalha pendente
  void (async () => {
    const [{ data: cfg }, temRef] = await Promise.all([supabase.from("config").select("valor").eq("chave", "pa_por_dia").maybeSingle(), carregarReferencias()]);
    paMax = Number(cfg?.valor ?? 30) || 30;
    atualizarHud();
    void atualizarMissao();
    void resolverPendencias();
    void supabase.from("pokemons").select("id", { count: "exact", head: true }).eq("dono", j.id).not("evo_pend", "is", null).then(({ count }) => { if (count) mostrarAviso("Você tem pontos de atributo para distribuir: abra o Time (ou a Caixa Principal) e toque no ⭐ do Pokémon.", 8000); });
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
