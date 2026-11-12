import { supabase } from "../supabase";
import { el } from "./dom";
import { barraHp, imagemPokemon, infoItem, meuTime, minhaMochila, nomeItem, nomePokemon, carregarReferencias, type PokemonRow } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

const BOLSOS = [
  { id: "itens", rot: "Itens" }, { id: "bolas", rot: "Poké Bolas" }, { id: "remedios", rot: "Remédios" }, { id: "outros", rot: "Outros" },
] as const;
type Bolso = (typeof BOLSOS)[number]["id"];
const USAVEIS = new Set(["potion", "super-potion", "hyper-potion", "max-potion", "full-restore", "revive", "max-revive"]);
const bolsoDe = (slug: string, cat: string): Bolso =>
  /ball$/.test(slug) ? "bolas" : /potion|restore|revive|heal|antidote|awakening|ether|elixir/.test(slug) || cat.includes("healing") || cat.includes("status") ? "remedios" : "itens";
const icone = (slug: string): string => (/ball$/.test(slug) ? "◓" : /revive/.test(slug) ? "✨" : /potion|restore/.test(slug) ? "🧪" : /heal|antidote|awakening/.test(slug) ? "💊" : "🎒");

/** Minhas Coisas — mochila no estilo Sword & Shield: time à esquerda, bolsos e itens à direita, descrição embaixo. */
export async function abrirMochila(modal: Modal, uid: string, dinheiro: number, aviso: Aviso, aoMudar: () => void, abas: HTMLElement, bolsoInicial: Bolso = "itens"): Promise<void> {
  await carregarReferencias();
  const [time, itens] = await Promise.all([meuTime(uid), minhaMochila(uid)]);
  let bolso: Bolso = bolsoInicial;
  let sel: string | null = null;
  let usando: string | null = null;

  const lista = el("div", { class: "ss-itens" });
  const desc = el("div", { class: "ss-desc" }, "Escolha um item.");
  const tabs = el("div", { class: "ss-bolsos" });
  const partes = el("div", { class: "ss-time" });

  const redesenhar = (): void => {
    tabs.replaceChildren(...BOLSOS.map((b) => {
      const n = itens.filter((i) => bolsoDe(i.item, infoItem(i.item).categoria) === b.id).length;
      const bt = el("button", { type: "button", class: `ss-bolso${b.id === bolso ? " ativo" : ""}` }, `${b.rot}`, el("small", {}, String(n)));
      bt.addEventListener("click", () => { bolso = b.id; sel = null; usando = null; redesenhar(); });
      return bt;
    }));
    const doBolso = itens.filter((i) => i.qtd > 0 && bolsoDe(i.item, infoItem(i.item).categoria) === bolso);
    lista.replaceChildren(...(doBolso.length ? doBolso.map((i) => {
      const l = el("button", { type: "button", class: `ss-item${sel === i.item ? " sel" : ""}` }, el("span", { class: "ss-ico" }, icone(i.item)), el("span", { class: "ss-nome" }, nomeItem(i.item)), el("span", { class: "ss-qtd" }, `× ${i.qtd}`));
      l.addEventListener("click", () => { sel = i.item; usando = null; redesenhar(); });
      return l;
    }) : [el("p", { class: "sub" }, "Nada neste bolso.")]));
    const inf = sel ? infoItem(sel) : null;
    desc.replaceChildren(el("p", {}, sel ? inf?.efeito || "Sem descrição." : "Escolha um item."));
    if (sel && USAVEIS.has(sel)) {
      const b = el("button", { type: "button", class: "ss-usar" }, usando ? "Escolha o Pokémon ▶" : "Usar");
      b.addEventListener("click", () => { usando = sel; redesenhar(); });
      desc.append(b);
    }
    partes.replaceChildren(...time.map((p: PokemonRow) => {
      const hp = barraHp(p.hp_atual, p.hp_max);
      const fill = el("i", { class: hp.classe });
      fill.style.width = `${hp.pct}%`;
      const c = el("button", { type: "button", class: `ss-pk${p.hp_atual <= 0 ? " caido" : ""}${usando ? " alvo" : ""}` },
        imagemPokemon("frente", p.especie_id, "mini", p.brilhante),
        el("div", { class: "ss-pk-info" }, el("strong", {}, `${nomePokemon(p)}`), el("small", {}, `Nv ${p.nivel}`), el("div", { class: "ss-hp" }, fill), el("small", {}, `${p.hp_atual}/${p.hp_max}`)));
      c.addEventListener("click", async () => {
        if (!usando) return;
        const { error } = await supabase.rpc("usar_item_fora", { p_item: usando, p_pokemon: p.id });
        if (error) return void aviso(error.message, 4000, true);
        aviso(`${nomeItem(usando)} usado em ${nomePokemon(p)}.`);
        aoMudar();
        void abrirMochila(modal, uid, dinheiro, aviso, aoMudar, abas, bolso);
      });
      return c;
    }), ...Array.from({ length: Math.max(0, 6 - time.length) }, () => el("div", { class: "ss-pk vazio" }, "—")));
  };
  redesenhar();

  modal.abrir("Minhas Coisas", abas,
    el("div", { class: "ss-topo" }, el("span", {}, "Mochila"), el("strong", { class: "ss-din" }, `₽ ${dinheiro}`)),
    el("div", { class: "ss-tela" }, partes, el("div", { class: "ss-dir" }, tabs, lista)),
    desc);
}
