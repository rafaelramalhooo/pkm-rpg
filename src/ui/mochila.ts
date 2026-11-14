import { supabase } from "../supabase";
import { el } from "./dom";
import { mostrarEvolucao, processarEventos, resolverPendencias } from "./momentos";
import { textoEventos } from "./habilidades";
import { barraHp, iconeBola, imagemPokemon, infoItem, meuTime, minhaMochila, nomeItem, nomePokemon, carregarReferencias, todasEspecies, type PokemonRow } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

const BOLSOS = [
  { id: "itens", rot: "Itens" }, { id: "bolas", rot: "Poké Bolas" }, { id: "remedios", rot: "Remédios" }, { id: "outros", rot: "Outros" },
] as const;
type Bolso = (typeof BOLSOS)[number]["id"];
const CURA_HP = new Set(["potion", "super-potion", "hyper-potion", "max-potion", "full-restore"]);
const REVIVE = new Set(["revive", "max-revive"]);
/** Por que um Pokémon não pode receber o item agora (null = pode). O servidor confere de novo. */
const motivo = (item: string, p: PokemonRow): string | null => {
  if (CURA_HP.has(item)) return p.hp_atual <= 0 ? "Desmaiado" : p.hp_atual >= p.hp_max ? "HP cheio" : null;
  if (REVIVE.has(item)) return p.hp_atual > 0 ? "Não está desmaiado" : null;
  return null;
};
const bolsoDe = (slug: string, cat: string): Bolso =>
  /ball$/.test(slug) ? "bolas" : /potion|restore|revive|heal|antidote|awakening|ether|elixir/.test(slug) || cat.includes("healing") || cat.includes("status") ? "remedios" : "itens";
const icone = (slug: string): string => (/ball$/.test(slug) ? "" : /stone/.test(slug) ? "💎" : /revive/.test(slug) ? "✨" : /potion|restore/.test(slug) ? "🧪" : /heal|antidote|awakening/.test(slug) ? "💊" : "🎒");

/** Minhas Coisas: só os itens, em tela retangular com rolagem. Time e Pokémon ficam em outra aba. Usar um item abre a escolha do Pokémon. */
export async function abrirMochila(modal: Modal, uid: string, dinheiro: number, aviso: Aviso, aoMudar: () => void, abas: HTMLElement, bolsoInicial: Bolso = "itens"): Promise<void> {
  await carregarReferencias();
  const [time, itens] = await Promise.all([meuTime(uid), minhaMochila(uid)]);
  let bolso: Bolso = bolsoInicial;
  let sel: string | null = null;
  let usando = false;

  const lista = el("div", { class: "mc-itens" });
  const desc = el("div", { class: "mc-desc" });
  const tabs = el("div", { class: "mc-bolsos" });

  const erro = el("p", { class: "msg erro mc-erro", role: "alert" });
  erro.hidden = true;
  const escolherPokemon = (item: string): void => {
    const linhas = time.map((p: PokemonRow) => {
      const hp = barraHp(p.hp_atual, p.hp_max);
      const fill = el("i", { class: hp.classe });
      fill.style.width = `${hp.pct}%`;
      const c = el("button", { type: "button", class: `mc-pk${p.hp_atual <= 0 ? " caido" : ""}` },
        imagemPokemon("frente", p.especie_id, "mini", p.brilhante),
        el("div", { class: "mc-pk-info" }, el("strong", {}, nomePokemon(p)), el("small", {}, `Nv ${p.nivel} · ${p.hp_atual}/${p.hp_max} PV`), el("div", { class: "ss-hp" }, fill)));
      const porque = motivo(item, p);
      if (porque) { c.classList.add("indisp"); c.append(el("small", { class: "mc-motivo" }, porque)); }
      c.addEventListener("click", async () => {
        if (porque) { erro.textContent = `${nomePokemon(p)}: ${porque}.`; erro.hidden = false; return; }
        c.disabled = true;
        const { data: rs, error } = await supabase.rpc("usar_item_fora", { p_item: item, p_pokemon: p.id });
        if (error) { c.disabled = false; erro.textContent = error.message; erro.hidden = false; return void aviso(error.message, 4000, true); }
        const r = (rs ?? {}) as { evolucao?: { nome: string; para: string }; eventos?: { t: string }[]; curou?: number; rare?: boolean };
        aoMudar();
        if (r.evolucao) {
          const para = todasEspecies().find((e) => e.nome === r.evolucao!.para);
          if (para) await mostrarEvolucao(p.especie_id, para.id, r.evolucao.nome, r.evolucao.para);
        } else if (r.rare) {
          aviso(`${nomePokemon(p)}: ${textoEventos((r.eventos ?? []) as Parameters<typeof textoEventos>[0]) || "subiu de nível!"}`, 5000);
          await processarEventos(r.eventos as Parameters<typeof processarEventos>[0]);
          await resolverPendencias();
        } else aviso(`${nomeItem(item)} usado em ${nomePokemon(p)}${r.curou ? ` (+${r.curou} PV)` : ""}.`, 3200);
        void abrirMochila(modal, uid, dinheiro, aviso, aoMudar, abas, bolso);
      });
      return c;
    });
    const voltar = el("button", { type: "button", class: "sec" }, "← Voltar aos itens");
    voltar.addEventListener("click", () => { usando = false; redesenhar(); });
    erro.hidden = true;
    lista.replaceChildren(el("p", { class: "sub" }, `Usar ${nomeItem(item)} em qual Pokémon?`), erro, el("div", { class: "mc-pks" }, ...(linhas.length ? linhas : [el("p", { class: "sub" }, "Você ainda não tem Pokémon no time.")])), voltar);
  };

  const redesenhar = (): void => {
    tabs.replaceChildren(...BOLSOS.map((b) => {
      const n = itens.filter((i) => i.qtd > 0 && bolsoDe(i.item, infoItem(i.item).categoria) === b.id).length;
      const bt = el("button", { type: "button", class: `ss-bolso${b.id === bolso ? " ativo" : ""}` }, `${b.rot}`, el("small", {}, String(n)));
      bt.addEventListener("click", () => { bolso = b.id; sel = null; usando = false; redesenhar(); });
      return bt;
    }));
    const doBolso = itens.filter((i) => i.qtd > 0 && bolsoDe(i.item, infoItem(i.item).categoria) === bolso);
    if (usando && sel) escolherPokemon(sel);
    else lista.replaceChildren(...(doBolso.length ? doBolso.map((i) => {
      const l = el("button", { type: "button", class: `ss-item${sel === i.item ? " sel" : ""}` }, el("span", { class: "ss-ico" }, /ball$/.test(i.item) ? iconeBola(i.item) : icone(i.item)), el("span", { class: "ss-nome" }, nomeItem(i.item)), el("span", { class: "ss-qtd" }, `× ${i.qtd}`));
      l.addEventListener("click", () => { sel = i.item; usando = false; redesenhar(); });
      return l;
    }) : [el("p", { class: "sub" }, "Nada neste bolso.")]));
    const inf = sel ? infoItem(sel) : null;
    desc.replaceChildren(el("p", {}, sel ? inf?.efeito || "Sem descrição." : "Escolha um item para ver a descrição."));
    if (sel && !/ball$/.test(sel) && !usando) {
      const b = el("button", { type: "button", class: "ss-usar" }, `Usar ${nomeItem(sel)}`);
      b.addEventListener("click", () => { usando = true; redesenhar(); });
      desc.append(b);
    }
  };
  redesenhar();

  modal.abrir("Minhas Coisas", abas,
    el("div", { class: "ss-topo" }, el("span", {}, "Mochila"), el("strong", { class: "ss-din" }, `₽ ${dinheiro}`)),
    tabs, lista, desc);
}
