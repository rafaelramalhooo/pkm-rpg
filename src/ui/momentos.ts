// Momentos de destaque do jogo: animação de evolução e escolha (bloqueante) de golpe novo.
import { distribuirPendentes } from "./evolucao";
import { supabase } from "../supabase";
import { el } from "./dom";
import { dicaGolpe, dicaPorId } from "./dica";
import { COR_TIPO, carregarReferencias, especie, golpe, imagemPokemon, NOME_TIPO, type GolpeSlot } from "./dados";

type Evento = { t: string; [k: string]: unknown };
const esperar = (ms: number) => new Promise<void>((ok) => window.setTimeout(ok, ms));
const str = (v: unknown) => String(v ?? "");

function camada(classe: string, ...nos: Node[]): HTMLElement {
  const c = el("div", { class: `momento ${classe}`, role: "dialog", "aria-modal": "true" }, ...nos);
  document.body.append(c);
  return c;
}

/** Janela de evolução com animação: o Pokémon pisca em silhueta, brilha e revela a nova forma. */
export async function mostrarEvolucao(deId: number, paraId: number, nome: string, paraNome: string): Promise<void> {
  await carregarReferencias();
  const curto = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const antigo = imagemPokemon("frente", deId, "evo-sprite");
  const novo = imagemPokemon("frente", paraId, "evo-sprite evo-novo");
  const texto = el("p", { class: "evo-texto" }, `O quê? ${nome} está evoluindo...`);
  const brilho = el("div", { class: "evo-brilho" });
  const palco = el("div", { class: "evo-palco" }, el("div", { class: "evo-aura" }), antigo, novo, brilho,
    ...Array.from({ length: 14 }, (_, i) => { const s = el("i", { class: "evo-estrela" }); s.style.setProperty("--a", `${(360 / 14) * i}deg`); s.style.setProperty("--d", `${0.05 * i}s`); return s; }));
  const ok = el("button", { type: "button", class: "evo-ok" }, "Continuar");
  ok.hidden = true;
  const dica = el("small", { class: "evo-dica" }, "Sua evolução está acontecendo!");
  const c = camada("evo", el("div", { class: "evo-cartao" }, el("div", { class: "evo-faixa" }, "EVOLUÇÃO"), palco, texto, dica, ok));
  novo.style.opacity = "0";
  await esperar(curto ? 500 : 1300);
  // alterna silhueta branca do antigo e do novo, cada vez mais rápido
  if (!curto) {
    let intervalo = 420;
    for (let i = 0; i < 9; i++) {
      const mostraNovo = i % 2 === 1;
      antigo.style.opacity = mostraNovo ? "0" : "1"; novo.style.opacity = mostraNovo ? "1" : "0";
      antigo.classList.toggle("silhueta", true); novo.classList.toggle("silhueta", true);
      await esperar(intervalo);
      intervalo = Math.max(90, intervalo * 0.72);
    }
  }
  palco.classList.add("explode");
  await esperar(curto ? 200 : 650);
  antigo.style.display = "none";
  novo.classList.remove("silhueta"); novo.style.opacity = "1"; novo.classList.add("revela");
  c.classList.add("fim");
  texto.textContent = `Parabéns! ${nome} evoluiu para ${paraNome}!`;
  dica.textContent = `${especie(paraId).nome} é a nova forma do seu Pokémon.`;
  ok.hidden = false; ok.focus();
  await new Promise<void>((fim) => ok.addEventListener("click", () => fim()));
  c.classList.add("sai");
  await esperar(220);
  c.remove();
  void distribuirPendentes();
}

export interface GolpePendente { id: string; pokemon: string; nome: string; especie_id: number; golpe_id: number; golpe: string; golpes: GolpeSlot[] }

function cartaGolpe(id: number, extra = "", pp?: number): HTMLElement {
  const g = golpe(id);
  const b = el("button", { type: "button", class: `mg-golpe ${extra}` },
    el("span", { class: "mg-nome" }, g.nome),
    el("span", { class: "mg-meta" }, el("b", {}, NOME_TIPO[g.tipo] ?? g.tipo), ` · ${g.categoria === "physical" ? "Físico" : g.categoria === "special" ? "Especial" : "Status"}`),
    el("span", { class: "mg-meta" }, `${g.poder ? `Poder ${g.poder}` : "Sem dano"} · PP ${pp ?? g.pp}`));
  b.style.setProperty("--cor", COR_TIPO[g.tipo] ?? "#888");
  dicaGolpe(b, dicaPorId(id));
  return b;
}

/** O Pokémon já sabe 4 golpes: o jogador escolhe qual esquecer ou desiste. Não dá para fechar sem decidir. */
export async function escolherGolpe(p: GolpePendente): Promise<void> {
  await carregarReferencias();
  await new Promise<void>((fim) => {
    let sel: number | null = null;
    const atuais = p.golpes.map((s) => {
      const b = cartaGolpe(s.id, "atual", s.pp);
      b.addEventListener("click", () => { sel = s.id; atualizar(); });
      return { id: s.id, b };
    });
    const esquecer = el("button", { type: "button", class: "mg-ok" }, "Escolha o golpe a esquecer");
    esquecer.disabled = true;
    const negar = el("button", { type: "button", class: "mg-nao sec" }, `Não aprender ${p.golpe}`);
    let confirmaNegar = false;
    const msg = el("p", { class: "msg", role: "status" });
    const atualizar = (): void => {
      for (const a of atuais) a.b.classList.toggle("sel", a.id === sel);
      esquecer.disabled = sel === null;
      esquecer.textContent = sel === null ? "Escolha o golpe a esquecer" : `Esquecer ${golpe(sel).nome} e aprender ${p.golpe}`;
    };
    const resolver = async (esq: number | null): Promise<void> => {
      esquecer.disabled = true; negar.disabled = true;
      const { error } = await supabase.rpc("resolver_golpe", { p_pendente: p.id, p_esquecer: esq });
      if (error) { msg.textContent = error.message; msg.className = "msg erro"; esquecer.disabled = sel === null; negar.disabled = false; return; }
      c.classList.add("sai");
      await esperar(200);
      c.remove();
      fim();
    };
    esquecer.addEventListener("click", () => { if (sel !== null) void resolver(sel); });
    negar.addEventListener("click", () => {
      if (!confirmaNegar) { confirmaNegar = true; negar.textContent = `Confirmar: ${p.nome} não aprende ${p.golpe}`; window.setTimeout(() => { confirmaNegar = false; negar.textContent = `Não aprender ${p.golpe}`; }, 4000); return; }
      void resolver(null);
    });
    const c = camada("mg", el("div", { class: "mg-cartao" },
      el("div", { class: "mg-faixa" }, "NOVO GOLPE"),
      el("h2", {}, `${p.nome} quer aprender ${p.golpe}!`),
      el("p", { class: "sub" }, `${p.nome} já conhece 4 golpes. Escolha qual esquecer, ou desista de aprender ${p.golpe}.`),
      el("div", { class: "mg-novo" }, el("small", {}, "Golpe novo"), cartaGolpe(p.golpe_id, "novo")),
      el("small", {}, "Golpes atuais (toque para esquecer)"),
      el("div", { class: "mg-grade" }, ...atuais.map((a) => a.b)),
      msg, esquecer, negar));
  });
}

/** Resolve escolhas de golpe que ficaram pendentes (por exemplo, se o jogador fechou a página no meio). */
export async function resolverPendencias(): Promise<void> {
  for (let i = 0; i < 20; i++) {
    const { data } = await supabase.rpc("golpes_pendentes_lista");
    const lista = (data ?? []) as GolpePendente[];
    if (!lista.length) return;
    await escolherGolpe(lista[0]);
  }
}

/** Mostra os momentos dos eventos devolvidos pelo servidor, na ordem: evoluções e escolhas de golpe. */
export async function processarEventos(ev: Evento[] | undefined | null): Promise<void> {
  for (const e of ev ?? []) {
    if (e.t === "evolucao") await mostrarEvolucao(Number(e.de_id ?? e.especie_id), Number(e.especie_id), str(e.nome), str(e.para));
  }
  if ((ev ?? []).some((e) => e.t === "aprender")) await resolverPendencias();
}
