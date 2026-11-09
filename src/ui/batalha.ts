// Tela de batalha (modal). O servidor resolve tudo; aqui só mostramos a lista de eventos que ele devolve.
import { supabase } from "../supabase";
import { el } from "./dom";
import {
  barraHp, COR_TIPO, golpe, imagemPokemon, meuTime, minhaMochila, nomeItem, nomePokemon, type PokemonRow,
} from "./dados";

interface Selvagem {
  especie_id: number; nome: string; nivel: number; hp: number; hp_max: number; tipos: string[];
}
interface BatalhaRow { id: string; estado: "ativa" | "vitoria" | "derrota" | "fuga" | "captura"; selvagem: Selvagem; ativo: string | null; trocar: boolean; turno: number }
interface Evento { t: string; [k: string]: unknown }
export interface ResultadoBatalha { batalha: BatalhaRow; ativo: PokemonRow | null; eventos: Evento[] }

const esperar = (ms: number) => new Promise<void>((ok) => window.setTimeout(ok, ms));
const str = (v: unknown) => String(v ?? "");

function caixaInfo(): { raiz: HTMLElement; nome: HTMLElement; nivel: HTMLElement; fill: HTMLElement; numeros: HTMLElement; exp: HTMLElement } {
  const nome = el("span", { class: "bi-nome" });
  const nivel = el("span", { class: "bi-nivel" });
  const fill = el("div", { class: "hp-fill ok" });
  const numeros = el("div", { class: "bi-hp" });
  const exp = el("div", { class: "exp-fill" });
  const raiz = el(
    "div",
    { class: "bi" },
    el("div", { class: "bi-topo" }, nome, nivel),
    el("div", { class: "hp" }, el("span", { class: "hp-rot" }, "HP"), el("div", { class: "hp-trilho" }, fill)),
    numeros,
    el("div", { class: "exp-trilho" }, exp),
  );
  return { raiz, nome, nivel, fill, numeros, exp };
}

function pintarHp(fill: HTMLElement, atual: number, max: number): void {
  const b = barraHp(atual, max);
  fill.style.width = `${b.pct}%`;
  fill.className = `hp-fill ${b.classe}`;
}

/** Abre a batalha. Resolve quando o jogador fecha (com o estado final). */
export function abrirBatalha(inicial: ResultadoBatalha, meuId: string): Promise<BatalhaRow["estado"]> {
  return new Promise((resolver) => {
    let b = inicial.batalha;
    let ativo = inicial.ativo;
    let ocupado = true;
    let time: PokemonRow[] = [];

    const fundo = el("div", { class: "bt-fundo" });
    const campoInimigo = el("div", { class: "bt-inimigo" });
    const campoMeu = el("div", { class: "bt-meu" });
    const infoI = caixaInfo();
    const infoM = caixaInfo();
    infoI.raiz.classList.add("bi-inimigo");
    infoM.raiz.classList.add("bi-meu");
    infoI.exp.parentElement!.hidden = true;
    const cena = el("div", { class: "bt-cena" }, fundo, campoInimigo, campoMeu, infoI.raiz, infoM.raiz);
    const msg = el("div", { class: "bt-msg", role: "status", "aria-live": "polite" });
    const menu = el("div", { class: "bt-menu" });
    const painel = el("div", { class: "bt-painel" }, msg, menu);
    const raiz = el("div", { class: "batalha" }, el("div", { class: "bt-moldura" }, cena, painel));
    document.body.append(raiz);

    let imgI: HTMLElement | null = null;
    let imgM: HTMLElement | null = null;
    let idMeu = -1;
    const mostrarInimigo = () => {
      imgI?.remove();
      imgI = imagemPokemon("frente", b.selvagem.especie_id, "spr-inimigo");
      campoInimigo.append(imgI);
    };
    const mostrarMeu = () => {
      if (!ativo) return;
      if (idMeu === ativo.especie_id && imgM) return;
      idMeu = ativo.especie_id;
      imgM?.remove();
      imgM = imagemPokemon("costas", ativo.especie_id, "spr-meu");
      campoMeu.append(imgM);
    };

    let hpI = b.selvagem.hp;
    let hpM = ativo?.hp_atual ?? 0;
    const desenhar = () => {
      infoI.nome.textContent = b.selvagem.nome;
      infoI.nivel.textContent = `Lv${b.selvagem.nivel}`;
      pintarHp(infoI.fill, hpI, b.selvagem.hp_max);
      infoI.numeros.textContent = "";
      if (ativo) {
        infoM.nome.textContent = nomePokemon(ativo);
        infoM.nivel.textContent = `Lv${ativo.nivel}`;
        pintarHp(infoM.fill, hpM, ativo.hp_max);
        infoM.numeros.textContent = `${hpM}/${ativo.hp_max}`;
        const base = ativo.nivel ** 3;
        const prox = (ativo.nivel + 1) ** 3;
        infoM.exp.style.width = `${Math.max(0, Math.min(100, ((ativo.exp - base) / (prox - base)) * 100))}%`;
        mostrarMeu();
      }
    };

    const dizer = async (texto: string, ms = 900) => {
      msg.textContent = texto;
      await esperar(ms);
    };
    const tremer = (alvo: HTMLElement | null, classe: string) => {
      if (!alvo) return;
      alvo.classList.remove(classe);
      void alvo.offsetWidth;
      alvo.classList.add(classe);
    };

    // ---------- animação de captura ----------
    let bola: HTMLElement | null = null;
    const centro = (n: Element) => {
      const r = n.getBoundingClientRect();
      const c = cena.getBoundingClientRect();
      return { x: r.left - c.left + r.width / 2, y: r.top - c.top + r.height / 2 };
    };
    async function lancarBola(): Promise<void> {
      bola?.remove();
      const b = el("div", { class: "pokebola" }, el("i", {}));
      cena.append(b);
      bola = b;
      const de = centro(campoMeu);
      const para = centro(campoInimigo);
      const solo = { x: para.x, y: para.y + cena.clientHeight * 0.12 };
      b.style.left = `${de.x}px`;
      b.style.top = `${de.y}px`;
      const voo = b.animate(
        [
          { transform: "translate(-50%,-50%) rotate(0deg)", left: `${de.x}px`, top: `${de.y}px` },
          { transform: "translate(-50%,-50%) rotate(540deg)", left: `${(de.x + para.x) / 2}px`, top: `${Math.min(de.y, para.y) - 60}px`, offset: 0.5 },
          { transform: "translate(-50%,-50%) rotate(1080deg)", left: `${para.x}px`, top: `${para.y}px` },
        ],
        { duration: 650, easing: "ease-in", fill: "forwards" },
      );
      await voo.finished;
      // o Pokémon vira luz e entra na bola
      imgI?.animate([{ filter: "brightness(1)", transform: "scale(1)", opacity: 1 }, { filter: "brightness(6)", transform: "scale(.2)", opacity: 0 }], { duration: 450, fill: "forwards" });
      b.classList.add("aberta");
      await esperar(450);
      b.classList.remove("aberta");
      const cai = b.animate(
        [{ left: `${para.x}px`, top: `${para.y}px` }, { left: `${solo.x}px`, top: `${solo.y}px`, offset: 0.7 }, { left: `${solo.x}px`, top: `${solo.y - 14}px`, offset: 0.85 }, { left: `${solo.x}px`, top: `${solo.y}px` }],
        { duration: 600, fill: "forwards" },
      );
      await cai.finished;
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
      imgI?.animate([{ filter: "brightness(6)", transform: "scale(.2)", opacity: 0 }, { filter: "brightness(1)", transform: "scale(1)", opacity: 1 }], { duration: 500, fill: "forwards" });
      await esperar(500);
    }

    async function tocar(eventos: Evento[], novoAtivo: PokemonRow | null = null): Promise<void> {
      for (const e of eventos) {
        switch (e.t) {
          case "apareceu": await dizer(`Um ${str(e.nome)} selvagem (Lv${str(e.nivel)}) apareceu!`, 1100); break;
          case "retomada": await dizer("Você voltou para a batalha!", 700); break;
          case "usou": {
            tremer(e.quem === "jogador" ? imgM : imgI, e.quem === "jogador" ? "ataca-meu" : "ataca-inimigo");
            await dizer(e.quem === "jogador" ? `${str(e.nome)} usou ${str(e.golpe)}!` : `${str(e.nome)} selvagem usou ${str(e.golpe)}!`, 800);
            break;
          }
          case "errou": await dizer("O ataque errou!", 800); break;
          case "dano": {
            const alvoMeu = e.alvo === "jogador";
            tremer(alvoMeu ? imgM : imgI, "atingido");
            if (alvoMeu) hpM = Number(e.hp); else hpI = Number(e.hp);
            desenhar();
            await esperar(650);
            const ef = Number(e.efic);
            if (e.crit) await dizer("Acerto crítico!", 700);
            if (ef === 0) await dizer("Não teve efeito...", 800);
            else if (ef > 1) await dizer("Foi super efetivo!", 800);
            else if (ef < 1) await dizer("Não foi muito efetivo...", 800);
            break;
          }
          case "desmaiou": {
            const meu = e.alvo === "jogador";
            (meu ? imgM : imgI)?.classList.add("desmaiado");
            await dizer(meu ? `${str(e.nome)} desmaiou!` : `${str(e.nome)} selvagem desmaiou!`, 1000);
            break;
          }
          case "exp": await dizer(`${str(e.nome)} ganhou ${str(e.valor)} pontos de experiência!`, 1000); break;
          case "nivel": await dizer(`${str(e.nome)} subiu para o nível ${str(e.nivel)}!`, 1100); break;
          case "aprendeu": await dizer(`${str(e.nome)} aprendeu ${str(e.golpe)}!`, 1100); break;
          case "troca":
            imgM?.remove(); imgM = null; idMeu = -1;
            if (novoAtivo) { ativo = novoAtivo; hpM = novoAtivo.hp_atual; desenhar(); }
            await dizer(`Vai, ${str(e.nome)}!`, 800); break;
          case "bola": {
            await dizer(`Você lançou a ${nomeItem(str(e.bola))}! (chance de ${str(e.chance)}%)`, 500);
            await lancarBola();
            break;
          }
          case "balanco": {
            const n = Number(e.n);
            for (let i = 0; i < n; i++) {
              await balancar();
              msg.textContent = ".".repeat(i + 1) + "  ";
            }
            await esperar(350);
            break;
          }
          case "capturado":
            await brilharBola();
            await dizer(`Capturou ${str(e.nome)}! ${e.time ? "Ele entrou no seu time." : "Foi enviado para o box."}`, 1500);
            break;
          case "escapou":
            await abrirBola();
            await dizer(`${str(e.nome)} escapou da bola!`, 900);
            break;
          case "fuga": await dizer("Você fugiu em segurança!", 900); break;
          default: break;
        }
      }
    }

    async function sincronizar(r: ResultadoBatalha): Promise<void> {
      b = r.batalha;
      if (r.ativo) ativo = r.ativo;
      hpI = b.selvagem.hp;
      hpM = ativo?.hp_atual ?? 0;
      desenhar();
    }

    async function agir(fn: () => Promise<{ data: unknown; error: { message: string } | null }>): Promise<void> {
      if (ocupado) return;
      ocupado = true;
      menu.replaceChildren();
      const { data, error } = await fn();
      if (error || !data) {
        msg.textContent = error?.message ?? "Algo deu errado.";
        await esperar(1200);
        ocupado = false;
        return void menuPrincipal();
      }
      const r = data as ResultadoBatalha;
      await tocar(r.eventos, r.ativo);
      await sincronizar(r);
      time = await meuTime(meuId);
      if (b.estado !== "ativa") return void encerrar();
      ocupado = false;
      if (b.trocar) return void menuTime(true);
      menuPrincipal();
    }

    function encerrar(): void {
      const fim: Record<string, string> = {
        vitoria: "Vitória!", derrota: "Todos os seus Pokémon desmaiaram... Cure-os no Centro Pokémon ou em casa.",
        fuga: "Você escapou.", captura: "Captura concluída!",
      };
      msg.textContent = fim[b.estado] ?? "Fim da batalha.";
      const ok = el("button", { type: "button" }, "Continuar");
      ok.addEventListener("click", () => {
        raiz.remove();
        resolver(b.estado);
      });
      menu.replaceChildren(ok);
      ok.focus();
    }

    function botao(texto: string, fn: () => void, classe = ""): HTMLButtonElement {
      const x = el("button", { type: "button", class: classe }, texto);
      x.addEventListener("click", fn);
      return x;
    }

    function menuPrincipal(): void {
      msg.textContent = ativo ? `O que ${nomePokemon(ativo)} vai fazer?` : "";
      menu.replaceChildren(
        botao("Lutar", menuGolpes),
        botao("Mochila", () => void menuMochila()),
        botao("Pokémon", () => menuTime(false)),
        botao("Fugir", () => void agir(() => supabase.rpc("batalha_fugir", { p_batalha: b.id }) as never)),
      );
    }

    function menuGolpes(): void {
      if (!ativo) return;
      const lista = ativo.golpes.map((s, i) => {
        const g = golpe(s.id);
        const x = el("button", { type: "button", class: "golpe" });
        x.style.borderColor = COR_TIPO[g.tipo] ?? "#888";
        x.style.setProperty("--cor", COR_TIPO[g.tipo] ?? "#888");
        x.append(el("span", { class: "g-nome" }, g.nome), el("span", { class: "g-pp" }, `PP ${s.pp}/${g.pp}`));
        x.disabled = s.pp <= 0;
        x.addEventListener("click", () => void agir(() => supabase.rpc("batalha_atacar", { p_batalha: b.id, p_slot: i }) as never));
        return x;
      });
      menu.replaceChildren(...lista, botao("Voltar", menuPrincipal, "sec"));
    }

    async function menuMochila(): Promise<void> {
      const itens = (await minhaMochila(meuId)).filter((i) => /ball$/.test(i.item));
      if (itens.length === 0) {
        msg.textContent = "Você não tem Poké Bolas.";
        menu.replaceChildren(botao("Voltar", menuPrincipal, "sec"));
        return;
      }
      msg.textContent = "Qual bola você quer lançar?";
      const bolas = itens.map((i) =>
        botao(`${nomeItem(i.item)} x${i.qtd}`, () => void agir(() => supabase.rpc("batalha_capturar", { p_batalha: b.id, p_bola: i.item }) as never)),
      );
      menu.replaceChildren(...bolas, botao("Voltar", menuPrincipal, "sec"));
    }

    function menuTime(forcado: boolean): void {
      msg.textContent = forcado ? "Escolha o próximo Pokémon." : "Trocar de Pokémon:";
      const lista = time.map((p) => {
        const hp = barraHp(p.hp_atual, p.hp_max);
        const x = el("button", { type: "button", class: "membro" });
        x.append(
          imagemPokemon("frente", p.especie_id, "mini"),
          el("span", { class: "m-nome" }, `${nomePokemon(p)} Lv${p.nivel}`),
          el("span", { class: "m-hp" }, `${p.hp_atual}/${p.hp_max}`),
        );
        x.style.setProperty("--hp", `${hp.pct}%`);
        x.disabled = p.hp_atual <= 0 || (p.id === ativo?.id && !forcado);
        x.addEventListener("click", () => void agir(() => supabase.rpc("batalha_trocar", { p_batalha: b.id, p_pokemon: p.id }) as never));
        return x;
      });
      menu.replaceChildren(...lista, ...(forcado ? [] : [botao("Voltar", menuPrincipal, "sec")]));
    }

    // início
    void (async () => {
      time = await meuTime(meuId);
      mostrarInimigo();
      hpI = b.selvagem.hp;
      hpM = ativo?.hp_atual ?? 0;
      desenhar();
      await tocar(inicial.eventos);
      ocupado = false;
      if (b.estado !== "ativa") return void encerrar();
      menuPrincipal();
    })();

  });
}
