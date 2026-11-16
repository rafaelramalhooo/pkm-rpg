// Item segurado: o jogador escolhe 1 item da mochila para o Pokémon levar à batalha. O servidor valida posse e troca.
import { supabase } from "../supabase";
import { el } from "./dom";
import { nomeItem, nomePokemon, type PokemonRow } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void; voltarPara?: (r: (() => void) | null) => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

export async function abrirItemSeguro(modal: Modal, uid: string, p: PokemonRow, aviso: Aviso, aoMudar: () => void, voltar: () => void): Promise<void> {
  const [{ data: inv }, { data: held }, { data: atual }] = await Promise.all([
    supabase.from("inventario").select("item, qtd").eq("jogador", uid).gt("qtd", 0),
    supabase.from("itens").select("slug, nome, efeito").eq("categoria", "held-items").order("nome"),
    supabase.from("pokemons").select("item_seguro").eq("id", p.id).maybeSingle(),
  ]);
  const qtd = new Map(((inv ?? []) as { item: string; qtd: number }[]).map((x) => [x.item, x.qtd]));
  const ef = new Map(((held ?? []) as { slug: string; nome: string; efeito: string }[]).map((x) => [x.slug, x]));
  const segurando = (atual as { item_seguro: string | null } | null)?.item_seguro ?? null;
  const msg = el("p", { class: "msg" });
  const equipar = async (item: string | null): Promise<void> => {
    const { error } = await supabase.rpc("equipar_item", { p_pokemon: p.id, p_item: item });
    if (error) { msg.textContent = error.message; msg.className = "msg erro"; return; }
    aviso(item ? `${nomePokemon(p)} agora segura ${nomeItem(item)}.` : `${nomePokemon(p)} largou o item.`, 3500);
    aoMudar();
    await abrirItemSeguro(modal, uid, p, aviso, aoMudar, voltar);
  };
  const grade = el("div", { class: "grade-loja" });
  const disponiveis = [...ef.values()].filter((x) => (qtd.get(x.slug) ?? 0) > 0);
  for (const x of disponiveis) {
    const b = el("button", { type: "button", class: "item-cartao loja" }, el("div", { class: "item-txt" }, el("strong", {}, `${x.nome} ×${qtd.get(x.slug)}`), el("small", {}, x.efeito)));
    b.addEventListener("click", () => void equipar(x.slug));
    grade.appendChild(b);
  }
  const atualTxt = segurando ? `Segurando: ${ef.get(segurando)?.nome ?? nomeItem(segurando)} — ${ef.get(segurando)?.efeito ?? ""}` : "Não está segurando nada.";
  const largar = el("button", { type: "button", class: "sec" }, "Largar o item (volta para a mochila)");
  if (!segurando) largar.setAttribute("disabled", "");
  largar.addEventListener("click", () => void equipar(null));
  const voltarBtn = el("button", { type: "button", class: "sec" }, "← Voltar");
  voltarBtn.addEventListener("click", voltar);
  modal.abrir(`Item de ${nomePokemon(p)}`, el("p", { class: "sub" }, atualTxt), largar,
    el("p", { class: "sub" }, disponiveis.length ? "Escolha um item da sua mochila (o item atual volta para ela):" : "Você não tem itens seguráveis. Compre nas lojas das cidades maiores (Quartzo, Ametista, Carmesim, Obsidiana)."),
    grade, msg, voltarBtn);
}
