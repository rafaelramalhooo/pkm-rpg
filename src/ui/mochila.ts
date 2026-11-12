import { supabase } from "../supabase";
import { el } from "./dom";
import { mostrarEvolucao } from "./momentos";
import { barraHp, iconeBola, imagemPokemon, infoItem, meuTime, minhaMochila, nomeItem, nomePokemon, carregarReferencias, todasEspecies, type PokemonRow } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

const BOLSOS = [
  { id: "itens", rot: "Itens" }, { id: "bolas", rot: "Poké Bolas" }, { id: "remedios", rot: "Remédios" }, { id: "outros", rot: "Outros" },
] as const;
type Bolso = (typeof BOLSOS)[number]["id"];
const USAVEIS = new Set(["fire-stone", "water-stone", "thunder-stone", "leaf-stone", "moon-stone", "potion", "super-potion", "hyper-potion", "max-potion", "full-restore", "revive", "max-revive"]);
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

  const escolherPokemon = (item: string): void => {
    const linhas = time.map((p: PokemonRow) => {
      const hp = barraHp(p.hp_atual, p.hp_max);
      const fill = el("i", { class: hp.classe });
      fill.style.width = `${hp.pct}%`;
      const c = el("button", { type: "button", class: `mc-pk${p.hp_atual <= 0 ? " caido" : ""}` },
        imagemPokemon("frente", p.especie_id, "mini", p.brilhante),
        el("div", { class: "mc-pk-info" }, el("strong", {}, nomePokemon(p)), el("small", {}, `Nv ${p.nivel} · ${p.hp_atual}/${p.hp_max} PV`), el("div", { class: "ss-hp" }, fill)));
      c.addEventListener("click", async () => {
        const { data: rs, error } = await supabase.rpc("usar_item_fora", { p_item: item, p_pokemon: p.id });
        if (error) return void aviso(error.message, 4000, true);
        const evo = (rs as { evolucao?: { nome: string; para: string } } | null)?.evolucao;
        aoMudar();
        if (evo) {
          const para = todasEspecies().find((e) => e.nome === evo.para);
          if (para) await mostrarEvolucao(p.especie_id, para.id, evo.nome, evo.para);
        } else aviso(`${nomeItem(item)} usado em ${nomePokemon(p)}.`, 3200);
        void abrirMochila(modal, uid, dinheiro, aviso, aoMudar, abas, bolso);
      });
      return c;
    });
    const voltar = el("button", { type: "button", class: "sec" }, "← Voltar aos itens");
    voltar.addEventListener("click", () => { usando = false; redesenhar(); });
    lista.replaceChildren(el("p", { class: "sub" }, `Usar ${nomeItem(item)} em qual Pokémon?`), el("div", { class: "mc-pks" }, ...(linhas.length ? linhas : [el("p", { class: "sub" }, "Você ainda não tem Pokémon no time.")])), voltar);
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
    if (sel && USAVEIS.has(sel) && !usando) {
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
