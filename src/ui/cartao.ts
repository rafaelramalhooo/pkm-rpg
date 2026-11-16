// Cartão do Treinador: nome, visual, insígnias (cinza até conquistar), capturas e vitórias.
import { supabase } from "../supabase";
import { el } from "./dom";
import { INSIGNIAS, urlInsignia } from "./insignias";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };

export async function abrirCartaoTreinador(modal: Modal, uid: string): Promise<void> {
  const [{ data: jg }, { count: capt }, { count: vit }, { count: pk }] = await Promise.all([
    supabase.from("jogadores").select("nome, aparencia, insignias, campeao, dinheiro").eq("id", uid).single(),
    supabase.from("pokedex").select("especie_id", { count: "exact", head: true }).eq("jogador", uid).eq("capturado", true),
    supabase.from("treinadores_vencidos").select("treinador", { count: "exact", head: true }).eq("jogador", uid),
    supabase.from("pokemons").select("id", { count: "exact", head: true }).eq("dono", uid),
  ]);
  const j = (jg ?? { nome: "Treinador", aparencia: 0, insignias: [], campeao: false, dinheiro: 0 }) as { nome: string; aparencia: number; insignias: string[] | null; campeao: boolean; dinheiro: number };
  const tem = new Set(j.insignias ?? []);
  const avatar = el("div", { class: "ct-avatar" });
  avatar.style.backgroundImage = `url(${import.meta.env.BASE_URL}assets/personagens/p${j.aparencia ?? 0}.png)`;
  const cab = el("div", { class: "ct-cab" }, avatar, el("div", { class: "ct-id" },
    el("strong", {}, j.nome), el("small", {}, j.campeao ? "🏆 Campeão da Liga" : "Treinador de Rafar"),
    el("small", {}, `₽ ${j.dinheiro ?? 0}`)));
  const stats = el("div", { class: "ct-stats" },
    el("div", {}, el("b", {}, String(capt ?? 0)), el("span", {}, "Pokémon capturados")),
    el("div", {}, el("b", {}, String(pk ?? 0)), el("span", {}, "Pokémon com você")),
    el("div", {}, el("b", {}, String(vit ?? 0)), el("span", {}, "Treinadores vencidos")));
  const grade = el("div", { class: "ct-insignias" }, ...INSIGNIAS.map((i) => {
    const ok = tem.has(i.slug);
    const img = el("img", { src: urlInsignia(i.slug), alt: i.nome, class: ok ? "ganha" : "falta", draggable: "false" });
    return el("div", { class: `ct-ins ${ok ? "ganha" : "falta"}`, title: ok ? `Insígnia ${i.nome} — Ginásio de ${i.cidade}` : `Ginásio de ${i.cidade}` }, img, el("span", {}, i.nome), el("small", {}, i.cidade));
  }));
  modal.abrir("Cartão do Treinador", cab, stats, el("h3", { class: "ct-tit" }, `Insígnias (${[...tem].filter((s) => INSIGNIAS.some((i) => i.slug === s)).length}/8)`), grade);
}
