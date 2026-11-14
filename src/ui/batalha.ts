// Tela de batalha no estilo do Pokémon Showdown. Quem decide tudo é o servidor (Edge Function "batalha",
// que roda o simulador oficial do Showdown). Aqui só enviamos a intenção do jogador e tocamos o que volta.
import { supabase } from "../supabase";
import { el } from "./dom";
import { dicaGolpe } from "./dica";
import { mostrarEvolucao, resolverPendencias } from "./momentos";
import { painelBusca } from "./pokedex";
import { COR_TIPO, golpePorSlug, iconeBola, imagemPokemon, minhaMochila, NOME_TIPO, nomeItem, urlSprite } from "./dados";

interface MembroSim { orig: number; id?: string; hp: number; maxhp: number; status: string | null; nome: string; nivel: number; especie: string; num: number; ativo: boolean; pp: number[] }
interface PedidoGolpe { n: number; id: string; nome: string; pp: number; maxpp: number; desativado: boolean }
interface PedidoTime { n: number; orig: number; nome: string; ativo: boolean; hp: number; maxhp: number; status: string | null }
interface Pedido { trocar: boolean; golpes: PedidoGolpe[]; preso: boolean; time: PedidoTime[] }
interface Evento { t: string; [k: string]: unknown }
type EstadoFinal = "ativa" | "vitoria" | "derrota" | "fuga" | "captura";
interface Resposta {
  batalha: { id: string; estado: EstadoFinal; tipo: "selvagem" | "treinador" | "duelo"; turno: number };
  espera?: boolean; restante?: number | null; canal?: string; amistoso?: boolean;
  antes: Evento[]; linhas: string[]; depois: Evento[]; pedido: Pedido | null; fim: string | null;
  jogador: MembroSim[]; adversario: MembroSim[]; treinador?: string;
}
export interface ResultadoBatalha { batalha: { id: string; estado: string }; [k: string]: unknown }

const esperar = (ms: number) => new Promise<void>((ok) => window.setTimeout(ok, ms));
const str = (v: unknown) => String(v ?? "");

const STATUS_SIGLA: Record<string, string> = { brn: "QMD", psn: "ENV", tox: "ENV+", par: "PAR", slp: "SONO", frz: "GEL" };
const STATUS_TEXTO: Record<string, string> = {
  brn: "foi queimado!", psn: "foi envenenado!", tox: "foi gravemente envenenado!", par: "está paralisado! Pode ser que não ataque.",
  slp: "caiu no sono!", frz: "foi congelado!",
};
const STAT: Record<string, string> = { atk: "Ataque", def: "Defesa", spa: "Ataque Esp.", spd: "Defesa Esp.", spe: "Velocidade", accuracy: "Precisão", evasion: "Evasão" };
const STAT_CURTO: Record<string, string> = { atk: "Atq", def: "Def", spa: "AtqE", spd: "DefE", spe: "Vel", accuracy: "Prec", evasion: "Eva" };
const CURAVEIS = ["potion", "super-potion", "hyper-potion", "max-potion", "full-restore", "antidote", "burn-heal", "ice-heal", "awakening", "paralyze-heal", "full-heal"];

async function chamar(corpo: Record<string, unknown>): Promise<Resposta> {
  const { data, error } = await supabase.functions.invoke("batalha", { body: corpo });
  if (error) {
    let msg = error.message;
    try {
      const ctx = (error as { context?: Response }).context;
      if (ctx) msg = ((await ctx.json()) as { erro?: string }).erro ?? msg;
    } catch { /* mantém a mensagem genérica */ }
    throw new Error(msg);
  }
  if ((data as { erro?: string })?.erro) throw new Error((data as { erro: string }).erro);
  return data as Resposta;
}

function pctHp(atual: number, max: number): { pct: number; classe: string } {
  const pct = max > 0 ? Math.max(0, Math.min(100, (atual / max) * 100)) : 0;
  return { pct, classe: pct > 50 ? "ok" : pct > 20 ? "medio" : "baixo" };
}

interface Caixa { raiz: HTMLElement; nome: HTMLElement; nivel: HTMLElement; fill: HTMLElement; num: HTMLElement; st: HTMLElement; bufs: HTMLElement }
function caixa(classe: string): Caixa {
  const nome = el("span", { class: "sd-nome" });
  const nivel = el("span", { class: "sd-nivel" });
  const st = el("span", { class: "sd-st" });
  const fill = el("div", { class: "sd-hp-fill ok" });
  const num = el("div", { class: "sd-hp-num" });
  const bufs = el("div", { class: "sd-bufs" });
  const raiz = el("div", { class: `sd-caixa ${classe}` }, el("div", { class: "sd-topo" }, nome, nivel, st), el("div", { class: "sd-hp" }, el("div", { class: "sd-hp-trilho" }, fill), num), bufs);
  raiz.style.visibility = "hidden";
  return { raiz, nome, nivel, fill, num, st, bufs };
}

/** Abre a batalha. Resolve quando o jogador fecha (com o estado final). */
export interface OpcoesBatalha { fundo?: string; nome?: string; aparencia?: number; brilhantes?: Set<number> }
export function abrirBatalha(inicial: ResultadoBatalha, _meuId: string, opcoes: OpcoesBatalha = {}): Promise<EstadoFinal> {
  const fundoCena = opcoes.fundo ?? "campo";
  return new Promise((resolver) => {
    let ocupado = true;
    let ultima: Resposta | null = null;
    let estado: EstadoFinal = "ativa";
    let tipoBatalha: "selvagem" | "treinador" | "duelo" = "selvagem";
    let nomeTreinador = "";
    let amistosoDuelo = false;
    let canalRt: ReturnType<typeof supabase.channel> | null = null;
    const fecharCanal = (): void => { if (canalRt) { void supabase.removeChannel(canalRt); canalRt = null; } };

    const fundo = el("div", { class: "sd-fundo" });
    fundo.style.backgroundImage = `url(${import.meta.env.BASE_URL}assets/batalha/${fundoCena}.jpg)`;
    const campoAdv = el("div", { class: "sd-campo adv" });
    const campoJog = el("div", { class: "sd-campo jog" });
    const cxAdv = caixa("adv");
    const cxJog = caixa("jog");
    const msg = el("div", { class: "sd-msg", role: "status", "aria-live": "polite" });
    const turnoEl = el("div", { class: "sd-selo" }, "Turno 1");
    const palco = el("div", { class: "sd-palco" }, fundo, campoAdv, campoJog, cxAdv.raiz, cxJog.raiz, turnoEl, msg);
    // faixas laterais, como no Showdown: nome do treinador, avatar e as bolas do time
    const avatar = el("div", { class: "sd-avatar" });
    if (opcoes.aparencia !== undefined) avatar.style.backgroundImage = `url(${import.meta.env.BASE_URL}assets/personagens/p${opcoes.aparencia}.png)`;
    const bolasJog = el("div", { class: "sd-bolas" });
    const nomeAdvEl = el("div", { class: "sd-tnome" }, "Selvagem");
    const bolasAdv = el("div", { class: "sd-bolas" });
    const ladoJog = el("div", { class: "sd-lado jog" }, el("div", { class: "sd-tnome" }, opcoes.nome ?? "Você"), avatar, bolasJog);
    const ladoAdv = el("div", { class: "sd-lado adv" }, nomeAdvEl, bolasAdv);
    const cena = el("div", { class: "sd-cena" }, ladoJog, palco, ladoAdv);
    const controles = el("div", { class: "sd-controles" });
    const log = el("div", { class: "sd-log" });
    // painéis fixos nas laterais da tela de combate: histórico (esquerda) e Pokédex (direita)
    const painelHist = el("aside", { class: "sd-lat esq", "aria-label": "Histórico da batalha" });
    const painelDex = el("aside", { class: "sd-lat dir", "aria-label": "Pokédex" });
    const raiz = el("div", { class: "batalha sd" }, el("div", { class: "sd-moldura" }, painelHist, el("div", { class: "sd-centro" }, cena, controles), painelDex));
    document.body.append(raiz);
    const alerta = el("div", { class: "sd-alerta", role: "alert", hidden: "" });
    raiz.append(alerta);
    // histórico e Pokédex ficam sempre à vista; atualizam sozinhos conforme a batalha anda
    const cabecalhoAux = (titulo: string): HTMLElement => el("div", { class: "sd-hist-topo" }, el("strong", {}, titulo));
    function pintarHistorico(): void {
      const cartaoAtivo = (l: "jog" | "adv"): HTMLElement => {
        const a = ativos[l];
        if (!a.nome) return el("div", { class: "sd-hist-cartao" }, el("strong", {}, l === "jog" ? "Você" : "Adversário"), el("p", { class: "sub" }, "—"));
        const pc = pctHp(a.hp, a.max);
        const mods = Object.entries(a.bufs).filter(([, v]) => v !== 0).map(([k, v]) => `${STAT_CURTO[k] ?? k} ${v > 0 ? "+" : ""}${v}`);
        const cond = [a.status ? (STATUS_SIGLA[a.status] ?? a.status) : "", ...volateis[l]].filter(Boolean);
        return el("div", { class: "sd-hist-cartao" },
          el("strong", {}, `${l === "jog" ? "Seu" : "Inimigo"}: ${a.nome} Lv${a.nivel}`),
          el("p", {}, `PV: ${l === "jog" ? `${a.hp}/${a.max}` : `${Math.round(pc.pct)}%`}`),
          el("p", {}, `Modificadores: ${mods.length ? mods.join(", ") : "nenhum"}`),
          el("p", {}, `Condições: ${cond.length ? cond.join(", ") : "nenhuma"}`),
          el("p", {}, `No lado: ${ladoCond[l].size ? [...ladoCond[l]].join(", ") : "nada"}`));
      };
      const lista = (m: Map<string, number>): HTMLElement => el("ul", {}, ...(m.size ? [...m.entries()].map(([n, v]) => el("li", {}, `${n} × ${v}`)) : [el("li", { class: "sub" }, "ainda nenhum")]));
      const campoTxt = [clima.atual ? `Clima: ${clima.atual}` : "", terreno.atual ? `Terreno: ${terreno.atual}` : "", ...terreno.extras].filter(Boolean);
      const linha = (r: Registro): HTMLElement => el("div", { class: `sd-hist-lin ${r.classe}` }, r.texto);
      const linhaTempo = el("div", { class: "sd-hist-tempo" }, ...(historico.length ? historico.map(linha) : [el("p", { class: "sub" }, "Nada aconteceu ainda.")]));
      const antes = painelHist.querySelector<HTMLElement>(".sd-hist-tempo");
      const noFim = !antes || antes.scrollTop + antes.clientHeight >= antes.scrollHeight - 12;
      const rolagem = painelHist.querySelector<HTMLElement>(".sd-hist-corpo")?.scrollTop ?? 0;
      painelHist.replaceChildren(el("div", { class: "sd-hist-topo" }, el("strong", {}, "📜 Histórico da batalha")),
        el("div", { class: "sd-hist-corpo" },
          el("h4", {}, "Em campo agora"), el("div", { class: "sd-hist-duo" }, cartaoAtivo("jog"), cartaoAtivo("adv")),
          el("h4", {}, "Campo"), el("p", {}, campoTxt.length ? campoTxt.join(" · ") : "Sem clima ou terreno ativo."),
          el("h4", {}, "Golpes já usados"), el("div", { class: "sd-hist-duo" }, el("div", {}, el("strong", {}, "Seus"), lista(usados.jog)), el("div", {}, el("strong", {}, "Inimigo"), lista(usados.adv))),
          el("h4", {}, "O que aconteceu"), linhaTempo));
      const corpo = painelHist.querySelector<HTMLElement>(".sd-hist-corpo");
      if (corpo) corpo.scrollTop = rolagem;
      if (noFim) linhaTempo.scrollTop = linhaTempo.scrollHeight;
    }
    let dexAlvo = 0;   // 0 = acompanha o inimigo em campo
    let dexChave = "";
    async function pintarPokedex(forcar = false): Promise<void> {
      const alvo = dexAlvo || ativos.adv.num || ativos.jog.num;
      const chave = `${alvo}|${ativos.adv.num}|${ativos.jog.num}`;
      if (!forcar && chave === dexChave) return;
      dexChave = chave;
      const mk = (rot: string, n: number, auto: boolean): HTMLButtonElement => {
        const b = botao(rot, () => { dexAlvo = auto ? 0 : n; void pintarPokedex(true); }, "sec");
        b.disabled = !n; if ((auto && !dexAlvo) || (!auto && dexAlvo === n)) b.classList.add("ativa");
        return b;
      };
      const abas = el("div", { class: "sd-hist-abas" }, mk("Inimigo", ativos.adv.num, true), mk("Meu Pokémon", ativos.jog.num, false));
      const ficha = await painelBusca(alvo || undefined, { locais: false });
      if (chave !== dexChave) return;
      painelDex.replaceChildren(cabecalhoAux("📖 Pokédex"), el("div", { class: "sd-hist-corpo" }, abas, ficha));
    }
    let chaveHist = "";
    const chaveAtual = (): string => JSON.stringify([historico.length, ativos.jog.hp, ativos.adv.hp, ativos.jog.status, ativos.adv.status, ativos.jog.bufs, ativos.adv.bufs, [...usados.jog.values()], [...usados.adv.values()], clima.atual, terreno.atual, [...volateis.jog], [...volateis.adv], [...ladoCond.jog], [...ladoCond.adv], terreno.extras]);
    const timerLat = window.setInterval(() => {
      if (!raiz.isConnected) { window.clearInterval(timerLat); return; }
      try {
        const k = chaveAtual();
        if (k !== chaveHist) { chaveHist = k; pintarHistorico(); }
        void pintarPokedex();
      } catch { /* painéis ainda sem dados */ }
    }, 350);
    setTimeout(() => { try { pintarHistorico(); void pintarPokedex(true); } catch { /* sem dados ainda */ } }, 0);
    let tAlerta = 0;
    const alertar = (texto: string) => { alerta.textContent = texto; alerta.hidden = false; window.clearTimeout(tAlerta); tAlerta = window.setTimeout(() => { alerta.hidden = true; }, 5000); };
    // sprites em tamanho natural (como no Showdown), reduzidos só quando o palco encolhe
    cena.addEventListener("load", (ev) => {
      const t = ev.target;
      if (t instanceof HTMLImageElement && t.closest(".sd-campo")) t.style.setProperty("--nw", String(t.naturalWidth));
    }, true);
    msg.textContent = "Carregando a batalha...";
    // alinha cada Pokémon à sua caixa de HP: o topo do sprite encosta na base da caixa e os pés ficam acima da mensagem
    const alinhar = () => {
      const H = palco.clientHeight, W = palco.clientWidth;
      if (!H || !W) return;
      const k = Math.min(1, W / 438);
      cena.style.setProperty("--k", String(k));
      const lados: Array<[HTMLElement, HTMLElement, number, number]> = [
        [campoAdv, cxAdv.raiz, 0.56 * H, 0.42],
        [campoJog, cxJog.raiz, Math.max(H * 0.5, msg.offsetTop - 6), 0.42],
      ];
      for (const [campo, caixaEl, pes, larg] of lados) {
        const img = campo.querySelector("img");
        if (!(img instanceof HTMLImageElement) || !img.naturalWidth) continue;
        const nw = img.naturalWidth, nh = img.naturalHeight;
        const bh = caixaEl.offsetHeight || 36;
        const s = Math.max(0.5, Math.min(1.75 * k, (pes - bh - 6) / nh, (larg * W) / nw));
        img.style.width = `${Math.round(nw * s)}px`;
        campo.style.top = `${Math.round(pes)}px`;
        caixaEl.style.top = `${Math.max(2, Math.round(pes - nh * s - bh))}px`;
      }
    };
    new ResizeObserver(alinhar).observe(palco);
    cena.addEventListener("load", (ev) => { if (ev.target instanceof HTMLImageElement && ev.target.closest(".sd-campo")) requestAnimationFrame(alinhar); }, true);
    new MutationObserver(() => requestAnimationFrame(alinhar)).observe(msg, { childList: true, characterData: true, subtree: true });
    new MutationObserver(() => requestAnimationFrame(alinhar)).observe(cxAdv.raiz, { attributes: true, attributeFilter: ["style"] });

    let imgAdv: HTMLElement | null = null;
    let imgJog: HTMLElement | null = null;
    let bola: HTMLElement | null = null;
    const novoAtivo = () => ({ nome: "", nivel: 0, hp: 0, max: 1, status: null as string | null, num: 0, bufs: {} as Record<string, number> });
    const ativos = { jog: novoAtivo(), adv: novoAtivo() };
    const lado = (l: string) => (l === "p1" ? "jog" : "adv") as "jog" | "adv";

    // ---------- histórico da batalha (golpes, o que aconteceu, efeitos ativos) ----------
    interface Registro { turno: number; texto: string; classe: string }
    const historico: Registro[] = [];
    let turnoAtual = 1;
    const usados = { jog: new Map<string, number>(), adv: new Map<string, number>() };
    const clima = { atual: "" };
    const terreno = { atual: "", extras: new Set<string>() };
    const ladoCond = { jog: new Set<string>(), adv: new Set<string>() };
    const volateis = { jog: new Set<string>(), adv: new Set<string>() };
    const T: Record<string, string> = {
      raindance: "Chuva", sunnyday: "Sol forte", sandstorm: "Tempestade de areia", hail: "Granizo", snow: "Neve", snowscape: "Neve", desolateland: "Terra desolada", primordialsea: "Mar primordial", deltastream: "Corrente delta",
      electricterrain: "Terreno Elétrico", grassyterrain: "Terreno de Grama", mistyterrain: "Terreno Enevoado", psychicterrain: "Terreno Psíquico", trickroom: "Espaço Mágico (Trick Room)", gravity: "Gravidade", magicroom: "Sala Mágica", wonderroom: "Sala Maravilhosa",
      stealthrock: "Pedras Pontiagudas", spikes: "Espinhos", toxicspikes: "Espinhos Venenosos", stickyweb: "Teia Pegajosa", reflect: "Reflexo", lightscreen: "Tela de Luz", auroraveil: "Véu de Aurora", safeguard: "Safeguard", mist: "Névoa", tailwind: "Vento Favorável",
      confusion: "Confuso", leechseed: "Semente Parasita", substitute: "Substituto", taunt: "Provocado", encore: "Encore", disable: "Desabilitado", attract: "Apaixonado", infatuation: "Apaixonado", curse: "Maldição", nightmare: "Pesadelo", perishsong: "Canção da Morte", yawn: "Sonolento", focusenergy: "Foco de Energia", protect: "Protegido", flinch: "Recuou", partiallytrapped: "Preso", bind: "Preso", wrap: "Preso", firespin: "Preso (Redemoinho de Fogo)", whirlpool: "Preso (Redemoinho)", sandtomb: "Preso (Tumba de Areia)", ingrain: "Enraizado", aquaring: "Anel de Água", charge: "Carregado", minimize: "Minimizado", bide: "Revidando", rage: "Fúria", mustrecharge: "Recarregando", twoturnmove: "Preparando golpe", lockedmove: "Golpe em sequência",
    };
    const idv = (v: string) => (v ?? "").replace(/^move: |^ability: |^item: /, "").toLowerCase().replace(/[^a-z0-9]/g, "");
    const tr = (v: string) => T[idv(v)] ?? (v ?? "").replace(/^move: /, "");
    function registrar(texto: string, classe = ""): void {
      if (!texto) return;
      historico.push({ turno: turnoAtual, texto, classe });
      if (historico.length > 600) historico.shift();
    }

    // ---------- desenho ----------
    function pintar(l: "jog" | "adv"): void {
      const a = ativos[l];
      const c = l === "jog" ? cxJog : cxAdv;
      c.raiz.style.visibility = a.nome ? "visible" : "hidden";
      c.nome.textContent = a.nome;
      c.nivel.textContent = a.nivel ? `Lv${a.nivel}` : "";
      c.st.textContent = a.status ? (STATUS_SIGLA[a.status] ?? a.status.toUpperCase()) : "";
      c.st.className = `sd-st ${a.status ?? ""}`;
      const b = pctHp(a.hp, a.max);
      c.fill.style.width = `${b.pct}%`;
      c.fill.className = `sd-hp-fill ${b.classe}`;
      c.num.textContent = l === "jog" ? `${a.hp}/${a.max}` : `${Math.round(b.pct)}%`;
      c.bufs.replaceChildren(...Object.entries(a.bufs).filter(([, v]) => v !== 0).map(([k, v]) => el("span", { class: `sd-buf ${v > 0 ? "up" : "down"}` }, `${STAT_CURTO[k] ?? k} ${v > 0 ? "+" : ""}${v}`)));
    }
    const selvBrilha = Boolean((inicial.batalha as { selvagem?: { brilhante?: boolean } }).selvagem?.brilhante);
    function trocarSprite(l: "jog" | "adv", num: number): void {
      const antigo = l === "jog" ? imgJog : imgAdv;
      antigo?.remove();
      const nova = imagemPokemon(l === "jog" ? "costas" : "frente", num, l === "jog" ? "sd-spr jog" : "sd-spr adv", l === "jog" ? Boolean(opcoes.brilhantes?.has(num)) : tipoBatalha === "selvagem" && selvBrilha);
      nova.animate([{ opacity: 0, transform: "translateY(10px) scale(.7)" }, { opacity: 1, transform: "none" }], { duration: 380, easing: "ease-out" });
      (l === "jog" ? campoJog : campoAdv).append(nova);
      if (l === "jog") imgJog = nova; else imgAdv = nova;
    }
    const sprite = (l: "jog" | "adv") => (l === "jog" ? imgJog : imgAdv);
    function mexer(alvo: HTMLElement | null, quadros: Keyframe[], ms = 320): void {
      alvo?.animate(quadros, { duration: ms, easing: "ease-out" });
    }

    function dizer(texto: string, ms = 850, classe = ""): Promise<void> {
      // caixa de texto sobre o palco: mostra as últimas linhas, a mais antiga vai esmaecendo
      registrar(texto, classe);
      if (!msg.firstElementChild || msg.firstChild?.nodeType === 3) msg.textContent = "";
      msg.append(el("div", { class: `sd-linha ${classe}` }, texto));
      while (msg.children.length > 3) msg.firstElementChild?.remove();
      return esperar(ms);
    }
    const nomeAdv = (n: string) => (tipoBatalha === "selvagem" ? `${n} selvagem` : tipoBatalha === "duelo" ? `${n} de ${nomeTreinador || "oponente"}` : `${n} inimigo`);
    const quem = (l: "jog" | "adv", n: string) => (l === "jog" ? n : nomeAdv(n));

    // ---------- captura ----------
    const centro = (n: Element) => {
      const r = n.getBoundingClientRect();
      const c = cena.getBoundingClientRect();
      return { x: r.left - c.left + r.width / 2, y: r.top - c.top + r.height / 2 };
    };
    let bolaAtual = "poke-ball";
    async function lancarBola(): Promise<void> {
      bola?.remove();
      const b = el("div", { class: `pokebola b-${bolaAtual}` }, el("i", {}));
      cena.append(b);
      bola = b;
      const de = centro(campoJog);
      const para = centro(campoAdv);
      const solo = { x: para.x, y: para.y + cena.clientHeight * 0.12 };
      b.style.left = `${de.x}px`;
      b.style.top = `${de.y}px`;
      await b.animate(
        [
          { transform: "translate(-50%,-50%) rotate(0deg)", left: `${de.x}px`, top: `${de.y}px` },
          { transform: "translate(-50%,-50%) rotate(540deg)", left: `${(de.x + para.x) / 2}px`, top: `${Math.min(de.y, para.y) - 60}px`, offset: 0.5 },
          { transform: "translate(-50%,-50%) rotate(1080deg)", left: `${para.x}px`, top: `${para.y}px` },
        ],
        { duration: 650, easing: "ease-in", fill: "forwards" },
      ).finished;
      imgAdv?.animate([{ filter: "brightness(1)", transform: "scale(1)", opacity: 1 }, { filter: "brightness(6)", transform: "scale(.2)", opacity: 0 }], { duration: 450, fill: "forwards" });
      b.classList.add("aberta");
      await esperar(450);
      b.classList.remove("aberta");
      await b.animate(
        [{ left: `${para.x}px`, top: `${para.y}px` }, { left: `${solo.x}px`, top: `${solo.y}px`, offset: 0.7 }, { left: `${solo.x}px`, top: `${solo.y - 14}px`, offset: 0.85 }, { left: `${solo.x}px`, top: `${solo.y}px` }],
        { duration: 600, fill: "forwards" },
      ).finished;
      b.style.left = `${solo.x}px`;
      b.style.top = `${solo.y}px`;
      await esperar(250);
    }
    async function balancar(): Promise<void> {
      if (!bola) return;
      await bola.animate(
        [{ transform: "translate(-50%,-50%) rotate(0deg)" }, { transform: "translate(-50%,-50%) rotate(-28deg)" }, { transform: "translate(-50%,-50%) rotate(26deg)" }, { transform: "translate(-50%,-50%) rotate(0deg)" }],
        { duration: 700, easing: "ease-in-out" },
      ).finished;
      await esperar(300);
    }
    async function brilharBola(): Promise<void> {
      if (!bola) return;
      bola.classList.add("capturada");
      for (let i = 0; i < 8; i++) {
        const e = el("span", { class: "estrela" }, "✦");
        const a = (i / 8) * Math.PI * 2;
        e.style.left = bola.style.left;
        e.style.top = bola.style.top;
        cena.append(e);
        e.animate(
          [{ transform: "translate(-50%,-50%) scale(.4)", opacity: 1 }, { transform: `translate(calc(-50% + ${Math.cos(a) * 46}px), calc(-50% + ${Math.sin(a) * 46}px)) scale(1.2)`, opacity: 0 }],
          { duration: 900, easing: "ease-out", fill: "forwards" },
        ).finished.then(() => e.remove(), () => e.remove());
      }
      await esperar(700);
    }
    async function abrirBola(): Promise<void> {
      if (bola) {
        bola.classList.add("aberta");
        await esperar(250);
        bola.remove();
        bola = null;
      }
      imgAdv?.animate([{ filter: "brightness(6)", transform: "scale(.2)", opacity: 0 }, { filter: "brightness(1)", transform: "scale(1)", opacity: 1 }], { duration: 500, fill: "forwards" });
      await esperar(500);
    }

    function laterais(r: Resposta): void {
      amistosoDuelo = !!r.amistoso;
      turnoEl.textContent = `${tipoBatalha === "duelo" ? (amistosoDuelo ? "Amistoso · " : "Duelo · ") : ""}Turno ${r.batalha.turno}`;
      const bola = (m: MembroSim | null) => el("i", { class: `mini-bola${m ? (m.hp > 0 ? "" : " caida") : " vazia"}` });
      bolasJog.replaceChildren(...Array.from({ length: 6 }, (_, i) => bola(r.jogador[i] ?? null)));
      const n = Math.max(1, r.adversario.length);
      bolasAdv.replaceChildren(...Array.from({ length: tipoBatalha !== "selvagem" ? 6 : n }, (_, i) => bola(r.adversario[i] ?? null)));
      nomeAdvEl.textContent = tipoBatalha === "treinador" ? (nomeTreinador || "Treinador") : tipoBatalha === "duelo" ? (nomeTreinador || "Oponente") : "Selvagem";
    }

    // ---------- eventos do servidor (fora do protocolo do Showdown) ----------
    async function tocarEvento(e: Evento): Promise<void> {
      switch (e.t) {
        case "bola": {
          bolaAtual = str(e.bola);
          await dizer(`Você lançou a ${nomeItem(str(e.bola))}!`, 400);
          await lancarBola();
          const n = Number(e.balancos);
          for (let i = 0; i < n; i++) {
            await balancar();
            msg.textContent = ".".repeat(i + 1);
          }
          if (e.capturado) await brilharBola();
          else {
            await abrirBola();
            await dizer(`${str(e.nome)} escapou da bola!`, 900);
          }
          break;
        }
        case "capturado": await dizer(`Capturou ${str(e.nome)}! ${e.time ? "Ele entrou no seu time." : "Foi enviado para o box."}`, 1500, "forte"); break;
        case "item": await dizer(`Você usou ${nomeItem(str(e.item))} em ${str(e.nome)}${Number(e.curou) ? ` (+${str(e.curou)} PV)` : ""}.`, 900); break;
        case "fuga": await dizer(e.ok ? "Você fugiu em segurança!" : "Não conseguiu fugir!", 900); break;
        case "dinheiro": await dizer(`Você ganhou ₽ ${str(e.valor)} de ${str(e.nome)}!`, 1200, "forte"); break;
        case "fala": await dizer(`${str(e.nome)}: "${str(e.texto)}"`, 1800); break;
        case "exp": await dizer(Number(e.valor) > 0 ? `${str(e.nome)} ganhou ${str(e.valor)} pontos de experiência!` : `${str(e.nome)} já atingiu o limite de nível. Conquiste mais insígnias para ir além!`, 1000); break;
        case "nivel": await dizer(`${str(e.nome)} subiu para o nível ${str(e.nivel)}!`, 1100, "forte"); break;
        case "insignia": await dizer(`Você conquistou a Insígnia ${str(e.nome).replace(/^./, (c) => c.toUpperCase())} de ${str(e.lider)}!`, 2200, "forte"); break;
        case "campeao": await dizer(`${str(e.nome)} foi derrotada! Você é o novo Campeão de Rafar!`, 2600, "forte"); break;
        case "aprendeu": await dizer(e.esqueceu ? `${str(e.nome)} esqueceu ${str(e.esqueceu)} e aprendeu ${str(e.golpe)}!` : `${str(e.nome)} aprendeu ${str(e.golpe)}!`, 1500, "forte"); break;
        case "evolucao": await dizer(`O quê? ${str(e.nome)} está evoluindo...`, 900, "forte"); await mostrarEvolucao(Number(e.de_id ?? e.especie_id), Number(e.especie_id), str(e.nome), str(e.para)); break;
        case "aprender": await dizer(`${str(e.nome)} quer aprender ${str(e.golpe)}!`, 900, "forte"); await resolverPendencias(); break;
        default: break;
      }
    }

    // ---------- protocolo do Showdown → animações e texto em português ----------
    function achar(r: Resposta, l: "jog" | "adv", especie: string, nivel: number): MembroSim | undefined {
      const lista = l === "jog" ? r.jogador : r.adversario;
      return lista.find((m) => m.especie === especie && m.nivel === nivel) ?? lista.find((m) => m.especie === especie);
    }
    function lerHp(txt: string): { hp: number; max: number | null; st: string | null } {
      const p = txt.split(" ");
      if (p[1] === "fnt" || p[0] === "0") return { hp: 0, max: null, st: null };
      const [a, b] = p[0].split("/");
      return { hp: Number(a), max: b ? Number(b) : null, st: p[1] ?? null };
    }
    const ident = (s: string) => ({ l: lado(s.slice(0, 2)), nome: s.slice(4) });

    async function linha(r: Resposta, raw: string): Promise<void> {
      const p = raw.split("|").slice(1);
      const cmd = p[0];
      switch (cmd) {
        case "switch": case "drag": {
          const { l, nome } = ident(p[1]);
          // detalhes do Showdown: "Espécie, L50, M" — o nível some quando é 100 e o sexo pode vir sozinho
          const [esp, ...resto] = p[2].split(", ");
          const lv = resto.find((x) => /^L\d+$/.test(x));
          const nivel = lv ? Number(lv.slice(1)) : 100;
          const m = achar(r, l, esp, nivel);
          const h = lerHp(p[3]);
          volateis[l].clear();
          ativos[l] = { nome, nivel, hp: h.hp, max: h.max ?? m?.maxhp ?? Math.max(1, h.hp), status: h.st, num: m?.num ?? 0, bufs: {} };
          if (l === "adv" && ativos.adv.max > 0 && tipoBatalha === "selvagem") ativos.adv.max = 100, ativos.adv.hp = Math.round((h.hp / (h.max ?? 1)) * 100) || 100;
          trocarSprite(l, ativos[l].num);
          pintar(l);
          if (l === "jog") await dizer(`Vai, ${nome}!`, 800);
          else await dizer(tipoBatalha === "selvagem" ? `Um ${nome} selvagem apareceu!` : `${nomeTreinador || "O treinador"} enviou ${nome}!`, 1000);
          break;
        }
        case "move": {
          const { l, nome } = ident(p[1]);
          const g = golpePorSlug(p[2].toLowerCase().replace(/[^a-z0-9]/g, ""));
          mexer(sprite(l), [{ transform: "none" }, { transform: `translate(${l === "jog" ? "40px,-20px" : "-40px,20px"}) scale(1.06)` }, { transform: "none" }], 360);
          usados[l].set(p[2], (usados[l].get(p[2]) ?? 0) + 1);
          await dizer(`${quem(l, nome)} usou ${p[2]}!`, 800, g ? `tipo-${g.tipo}` : "");
          break;
        }
        case "-damage": case "-heal": {
          const { l, nome } = ident(p[1]);
          const h = lerHp(p[2]);
          const a = ativos[l];
          const max = tipoBatalha === "selvagem" && l === "adv" ? 100 : (h.max ?? a.max);
          const novo = tipoBatalha === "selvagem" && l === "adv" ? (h.max ? Math.round((h.hp / h.max) * 100) : 0) : h.hp;
          a.max = max;
          a.hp = novo;
          a.status = h.st ?? (h.hp === 0 ? null : a.status);
          if (cmd === "-damage") mexer(sprite(l), [{ transform: "none", filter: "none" }, { transform: "translateX(-8px)", filter: "brightness(2.2)" }, { transform: "translateX(8px)" }, { transform: "none", filter: "none" }], 380);
          pintar(l);
          const de = p.find((x) => x?.startsWith("[from]"));
          if (de?.includes("brn")) await dizer(`${quem(l, nome)} se machucou com a queimadura!`, 800);
          else if (de?.includes("psn")) await dizer(`${quem(l, nome)} sofreu com o veneno!`, 800);
          else if (de?.includes("Recoil")) await dizer(`${quem(l, nome)} sofreu o dano do recuo!`, 800);
          else if (cmd === "-heal") await dizer(`${quem(l, nome)} recuperou PV!`, 700);
          else await esperar(620);
          break;
        }
        case "faint": {
          const { l, nome } = ident(p[1]);
          sprite(l)?.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "translateY(40px)" }], { duration: 600, fill: "forwards" });
          await dizer(`${quem(l, nome)} desmaiou!`, 1000, "forte");
          ativos[l].nome = ativos[l].nome; // mantém a caixa até o próximo entrar
          break;
        }
        case "-supereffective": await dizer("Foi super efetivo!", 750, "bom"); break;
        case "-resisted": await dizer("Não foi muito efetivo...", 750); break;
        case "-immune": await dizer(`Não afeta ${quem(ident(p[1]).l, ident(p[1]).nome)}...`, 800); break;
        case "-crit": await dizer("Um golpe crítico!", 700, "bom"); break;
        case "-miss": await dizer(`O ataque de ${quem(ident(p[1]).l, ident(p[1]).nome)} errou!`, 800); break;
        case "-fail": await dizer("Mas falhou!", 700); break;
        case "-hitcount": await dizer(`Acertou ${p[2]} vez(es)!`, 700); break;
        case "-status": {
          const { l, nome } = ident(p[1]);
          ativos[l].status = p[2];
          pintar(l);
          await dizer(`${quem(l, nome)} ${STATUS_TEXTO[p[2]] ?? "foi afetado!"}`, 900);
          break;
        }
        case "-curestatus": {
          const { l, nome } = ident(p[1]);
          ativos[l].status = null;
          pintar(l);
          await dizer(`${quem(l, nome)} se recuperou!`, 800);
          break;
        }
        case "-boost": case "-unboost": {
          const { l, nome } = ident(p[1]);
          const n = Number(p[3]);
          const a = ativos[l];
          a.bufs[p[2]] = Math.max(-6, Math.min(6, (a.bufs[p[2]] ?? 0) + (cmd === "-boost" ? n : -n)));
          pintar(l);
          await dizer(`${STAT[p[2]] ?? p[2]} de ${quem(l, nome)} ${cmd === "-boost" ? (n > 1 ? "aumentou muito" : "aumentou") : n > 1 ? "diminuiu muito" : "diminuiu"}!`, 800);
          break;
        }
        case "cant": {
          const { l, nome } = ident(p[1]);
          const motivo = p[2] === "slp" ? "está dormindo" : p[2] === "par" ? "está paralisado e não consegue se mover" : p[2] === "frz" ? "está congelado" : p[2] === "flinch" ? "se encolheu de medo" : "não consegue se mover";
          await dizer(`${quem(l, nome)} ${motivo}!`, 850);
          break;
        }
        case "turn": turnoAtual = Number(p[1]) || turnoAtual; log.append(el("div", { class: "sd-turno" }, `Turno ${p[1]}`)); registrar(`— Turno ${p[1]} —`, "turno"); break;
        case "-weather": {
          const w = p[1];
          if (w === "none") { if (clima.atual) registrar("O clima voltou ao normal.", ""); clima.atual = ""; }
          else if (!p.some((x) => x?.startsWith("[upkeep]"))) { clima.atual = tr(w); await dizer(`Clima: ${clima.atual}!`, 800); }
          break;
        }
        case "-fieldstart": { const n = tr(p[1]); if (/terreno|terrain/i.test(n)) terreno.atual = n; else terreno.extras.add(n); await dizer(`${n} entrou em campo!`, 800); break; }
        case "-fieldend": { const n = tr(p[1]); if (terreno.atual === n) terreno.atual = ""; terreno.extras.delete(n); registrar(`${n} terminou.`); break; }
        case "-sidestart": { const l = lado(p[1].slice(0, 2)); const n = tr(p[2]); ladoCond[l].add(n); await dizer(`${n} no lado ${l === "jog" ? "do seu time" : "inimigo"}!`, 800); break; }
        case "-sideend": { const l = lado(p[1].slice(0, 2)); const n = tr(p[2]); ladoCond[l].delete(n); registrar(`${n} acabou no lado ${l === "jog" ? "do seu time" : "inimigo"}.`); break; }
        case "-start": { const { l, nome } = ident(p[1]); const n = tr(p[2]); volateis[l].add(n); await dizer(`${quem(l, nome)}: ${n}.`, 700); break; }
        case "-end": { const { l, nome } = ident(p[1]); const n = tr(p[2]); volateis[l].delete(n); registrar(`${quem(l, nome)}: ${n} acabou.`); break; }
        case "-heal-info": break;
        default: break;
      }
    }

    // ---------- controles ----------
    function botao(texto: string, fn: () => void, classe = ""): HTMLButtonElement {
      const x = el("button", { type: "button", class: classe }, texto);
      x.addEventListener("click", fn);
      return x;
    }

    function botaoDesistir(): HTMLButtonElement {
      let armado = false;
      const b = botao("Desistir do duelo", () => {
        if (!armado) {
          armado = true;
          b.textContent = "Confirmar: desistir?";
          window.setTimeout(() => { armado = false; b.textContent = "Desistir do duelo"; }, 4000);
          return;
        }
        void agir({ acao: "fugir" });
      }, "sec perigo");
      return b;
    }

    function iconeTime(t: PedidoTime, r: Resposta, aoClicar: () => void, desabilitar: boolean): HTMLButtonElement {
      const m = r.jogador.find((x) => x.orig === t.orig);
      const hp = pctHp(t.hp, t.maxhp);
      const x = el("button", { type: "button", class: `sd-membro${t.ativo ? " em-campo" : ""}${t.hp <= 0 ? " caido" : ""}` });
      x.append(
        imagemPokemon("frente", m?.num ?? 0, "mini"),
        el("span", { class: "m-nome" }, `${t.nome} Lv${m?.nivel ?? ""}`),
        el("span", { class: "m-barra" }, (() => { const f = el("i", { class: hp.classe }); f.style.width = `${hp.pct}%`; return f; })()),
        el("span", { class: "m-hp" }, `${t.hp}/${t.maxhp}${t.status ? ` · ${STATUS_SIGLA[t.status] ?? t.status}` : ""}`),
      );
      x.disabled = desabilitar || t.hp <= 0;
      x.addEventListener("click", aoClicar);
      return x;
    }

    function mostrarControles(r: Resposta): void {
      ultima = r;
      const ped = r.pedido;
      if (!ped) {
        if (r.espera && tipoBatalha === "duelo") {
          msg.textContent = r.restante ? `Aguardando ${nomeTreinador || "o oponente"}... (${r.restante}s)` : `Aguardando ${nomeTreinador || "o oponente"}...`;
          controles.replaceChildren(el("div", { class: "sd-sub" }, "Sua escolha foi enviada."), botaoDesistir());
        }
        return;
      }
      const nomeAtivo = ativos.jog.nome;
      if (ped.trocar) {
        msg.textContent = "Escolha o próximo Pokémon!";
        controles.replaceChildren(
          el("div", { class: "sd-sub" }, "Quem entra agora?"),
          el("div", { class: "sd-time" }, ...ped.time.map((t) => iconeTime(t, r, () => void agir({ acao: "trocar", n: t.n }), t.ativo))),
        );
        return;
      }
      msg.textContent = `O que ${nomeAtivo} vai fazer?`;
      const golpes = ped.golpes.map((g) => {
        const info = golpePorSlug(g.id);
        const tipo = info?.tipo ?? "normal";
        const x = el("button", { type: "button", class: "sd-golpe" });
        x.style.setProperty("--cor", COR_TIPO[tipo] ?? "#888");
        x.append(
          el("span", { class: "g-nome" }, g.nome),
          el("span", { class: "g-meta" }, el("b", {}, NOME_TIPO[tipo] ?? tipo), ` · ${info?.categoria === "physical" ? "Físico" : info?.categoria === "special" ? "Especial" : "Status"}${info?.poder ? ` · Pod ${info.poder}` : ""}`),
          el("span", { class: "g-pp" }, `PP ${g.pp}/${g.maxpp}`),
        );
        x.disabled = g.desativado || g.pp <= 0;
        dicaGolpe(x, () => info);
        x.addEventListener("click", () => void agir({ acao: "golpe", n: g.n }));
        return x;
      });
      const extras = el("div", { class: "sd-extras" });
      if (tipoBatalha === "duelo") {
        extras.append(botaoDesistir());
      } else {
        extras.append(botao("Mochila", () => void menuMochila(r), "sec"), botao("Fugir", () => void agir({ acao: "fugir" }), "sec perigo"));
        if (tipoBatalha === "treinador") (extras.lastElementChild as HTMLButtonElement).disabled = true;
      }
      controles.replaceChildren(
        el("div", { class: "sd-sub" }, "Golpes"),
        el("div", { class: "sd-golpes" }, ...golpes),
        el("div", { class: "sd-sub" }, "Trocar Pokémon"),
        el("div", { class: "sd-time" }, ...ped.time.map((t) => iconeTime(t, r, () => void agir({ acao: "trocar", n: t.n }), t.ativo || !!ped.preso))),
        extras,
      );
    }

    async function menuMochila(r: Resposta): Promise<void> {
      const todos = await minhaMochila(_meuId);
      const bolas = tipoBatalha === "selvagem" ? todos.filter((i) => /ball$/.test(i.item)) : [];
      const cura = todos.filter((i) => CURAVEIS.includes(i.item));
      msg.textContent = "Mochila";
      const lista: HTMLElement[] = [
        ...bolas.map((i) => { const b = botao(`${nomeItem(i.item)} ×${i.qtd}`, () => void agir({ acao: "bola", item: i.item }), "sd-item"); b.prepend(iconeBola(i.item)); return b; }),
        ...cura.map((i) => botao(`${nomeItem(i.item)} ×${i.qtd}`, () => escolherAlvo(r, i.item), "sd-item")),
      ];
      controles.replaceChildren(
        el("div", { class: "sd-sub" }, "Itens de batalha"),
        lista.length ? el("div", { class: "sd-itens" }, ...lista) : el("p", { class: "sub" }, "Nada que possa ser usado agora."),
        botao("Voltar", () => mostrarControles(r), "sec"),
      );
    }
    function escolherAlvo(r: Resposta, item: string): void {
      msg.textContent = `Usar ${nomeItem(item)} em quem?`;
      controles.replaceChildren(
        el("div", { class: "sd-sub" }, "Escolha o Pokémon"),
        el("div", { class: "sd-time" }, ...(r.pedido?.time ?? []).map((t) => iconeTime(t, r, () => void agir({ acao: "item", item, n: t.n }), false))),
        botao("Voltar", () => void menuMochila(r), "sec"),
      );
    }

    async function tocarResposta(r: Resposta): Promise<void> {
      tipoBatalha = r.batalha.tipo;
      if (r.treinador) nomeTreinador = r.treinador;
      laterais(r);
      for (const e of r.antes) await tocarEvento(e);
      for (const l of r.linhas) await linha(r, l);
      for (const e of r.depois) await tocarEvento(e);
      // garante que a caixa reflita o estado final (por segurança)
      const j = r.jogador.find((m) => m.ativo);
      if (j && ativos.jog.nome && !r.fim) { ativos.jog.hp = j.hp; ativos.jog.max = j.maxhp; ativos.jog.status = j.status; pintar("jog"); }
    }

    async function agir(corpo: Record<string, unknown>): Promise<void> {
      if (ocupado) return;
      ocupado = true;
      controles.replaceChildren();
      try {
        const r = await chamar(corpo);
        await tocarResposta(r);
        estado = r.batalha.estado;
        if (r.fim || estado !== "ativa") return void encerrar(r.fim ?? estado);
        ocupado = false;
        mostrarControles(r);
      } catch (e) {
        msg.textContent = (e as Error).message;
        alertar((e as Error).message);
        await esperar(1300);
        ocupado = false;
        if (ultima) mostrarControles(ultima);
      }
    }

    function encerrar(fim: string): void {
      window.clearInterval(timerSonda);
      fecharCanal();
      const textos: Record<string, string> = {
        vitoria: tipoBatalha === "treinador" ? "Você venceu o treinador!" : tipoBatalha === "duelo" ? `Você venceu o duelo contra ${nomeTreinador || "o oponente"}!` : "Vitória!",
        derrota: tipoBatalha === "duelo" ? (amistosoDuelo ? `Você perdeu o duelo para ${nomeTreinador || "o oponente"}. Foi só um amistoso: seus Pokémon não sofreram nada!` : `Você perdeu o duelo para ${nomeTreinador || "o oponente"}. Cure seus Pokémon no Centro Pokémon ou em casa.`) : "Todos os seus Pokémon desmaiaram... Cure-os no Centro Pokémon ou em casa.",
        fuga: "Você escapou.", captura: "Captura concluída!",
      };
      void dizer(textos[fim] ?? "Fim da batalha.", 0, "forte");
      const ok = botao("Continuar", () => { raiz.remove(); resolver((fim === "derrota" ? "derrota" : fim) as EstadoFinal); }, "sd-continuar");
      controles.replaceChildren(ok);
      ok.focus();
    }

    // duelo ao vivo: consulta o servidor de tempos em tempos (mostra a jogada do oponente e avisa que estamos presentes)
    let sondando = false;
    async function sondar(): Promise<void> {
      if (tipoBatalha !== "duelo" || ocupado || sondando || estado !== "ativa") return;
      sondando = true;
      try {
        const r = await chamar({ acao: "estado" });
        if (ocupado) return;
        if (r.linhas.length || r.fim || r.batalha.estado !== "ativa") {
          ocupado = true;
          controles.replaceChildren();
          await tocarResposta(r);
          estado = r.batalha.estado;
          if (r.fim || estado !== "ativa") return void encerrar(r.fim ?? estado);
          ocupado = false;
          mostrarControles(r);
        } else if (!!r.pedido !== !!ultima?.pedido || r.pedido?.trocar !== ultima?.pedido?.trocar) mostrarControles(r);
        else if (!r.pedido && r.espera) mostrarControles(r);
      } catch (e) {
        const m = (e as Error).message;
        if (/terminou|não está em batalha/i.test(m)) { estado = "derrota"; ocupado = true; encerrar("derrota"); }
      } finally { sondando = false; }
    }
    const timerSonda = window.setInterval(() => void sondar(), 2500);
    // Realtime: o servidor avisa na hora que algo mudou (a consulta acima fica como reserva)
    const inscrever = (nome?: string): void => {
      if (!nome || canalRt) return;
      canalRt = supabase.channel(nome).on("broadcast", { event: "ping" }, () => void sondar()).subscribe();
    };

    // início
    void (async () => {
      try {
        const r = await chamar({ acao: "estado" });
        tipoBatalha = r.batalha.tipo;
        if (tipoBatalha === "duelo") inscrever(r.canal);
        // baixa os sprites antes de abrir a cena, para não aparecerem aos pedaços
        await Promise.race([
          Promise.all([...r.jogador.filter((x) => x.ativo).map((x) => urlSprite("costas", x.num)), ...r.adversario.filter((x) => x.ativo).map((x) => urlSprite("frente", x.num))]),
          esperar(2500),
        ]);
        if (r.treinador) nomeTreinador = r.treinador;
        laterais(r);
        if (r.linhas.length === 0) {
          // batalha retomada: desenha direto o estado atual
          for (const l of ["jog", "adv"] as const) {
            const m = (l === "jog" ? r.jogador : r.adversario).find((x) => x.ativo);
            if (!m) continue;
            const selv = l === "adv" && tipoBatalha === "selvagem";
            ativos[l] = { nome: m.nome, nivel: m.nivel, hp: selv ? Math.round((m.hp / m.maxhp) * 100) : m.hp, max: selv ? 100 : m.maxhp, status: m.status, num: m.num, bufs: {} };
            trocarSprite(l, m.num);
            pintar(l);
          }
          await dizer("Você voltou para a batalha!", 700);
        } else await tocarResposta(r);
        estado = r.batalha.estado;
        ocupado = false;
        if (r.fim || estado !== "ativa") return void encerrar(r.fim ?? estado);
        mostrarControles(r);
      } catch (e) {
        msg.textContent = (e as Error).message;
        window.clearInterval(timerSonda);
        fecharCanal();
        const ok = botao("Fechar", () => { raiz.remove(); resolver("ativa"); });
        controles.replaceChildren(ok);
      }
    })();
    void inicial;
  });
}
