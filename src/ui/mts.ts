// MTs (Máquinas Técnicas): infinitas, ensinam um golpe a quem pode aprender (troca 1 dos 4). Tudo validado no servidor.
import { supabase } from "../supabase";
import { el } from "./dom";
import { carregarReferencias, golpe, imagemPokemon, meuTime, nomePokemon, NOME_TIPO, type PokemonRow } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;
interface MT { num: number; golpe_id: number; arco: number; preco: number; liberada: boolean; tenho: boolean }

const rotulo = (m: MT): string => { const g = golpe(m.golpe_id); return `MT${String(m.num).padStart(3, "0")} · ${g.nome}`; };
const CAT: Record<string, string> = { status: "Status", physical: "Físico", special: "Especial" };
const detalhe = (m: MT): string => { const g = golpe(m.golpe_id); return `${NOME_TIPO[g.tipo] ?? g.tipo} · ${CAT[g.categoria] ?? g.categoria} · Poder ${g.poder ?? "—"} · Precisão ${g.precisao ? `${g.precisao}%` : "—"} · PP ${g.pp}`; };
/** Ficha completa do golpe que a MT ensina: tipo, categoria, poder, precisão, PP e efeito. */
const ficha = (m: MT, extra = ""): HTMLElement => {
  const g = golpe(m.golpe_id);
  return el("div", { class: "item-txt mt-ficha" }, el("strong", {}, rotulo(m)), el("small", {}, `${detalhe(m)}${extra}`), el("small", { class: "mt-desc" }, g.descricao ?? "Sem descrição disponível."));
};

async function listar(): Promise<MT[]> {
  const { data } = await supabase.rpc("mt_lista");
  return (Array.isArray(data) ? data : []) as MT[];
}

/** Janela "MTs": as que o jogador tem; escolher uma mostra quem do time pode aprender. */
export async function abrirMTs(modal: Modal, aviso: Aviso, abas: HTMLElement | null, aoMudar: () => void): Promise<void> {
  await carregarReferencias();
  const [mts, time] = await Promise.all([listar(), meuTime((await supabase.auth.getUser()).data.user?.id ?? "")]);
  const minhas = mts.filter((m) => m.tenho);
  const nos: Node[] = [];
  if (abas) nos.push(abas);
  nos.push(el("p", { class: "sub" }, `Você tem ${minhas.length} MT(s). Elas são infinitas: ensinar troca um dos 4 golpes do Pokémon. Compre mais nas lojas grandes.`));
  const lista = el("div", { class: "mt-lista" });
  if (!minhas.length) lista.append(el("p", { class: "sub" }, "Você ainda não tem MTs."));
  for (const m of minhas) {
    const b = el("button", { type: "button", class: "item-cartao mt-item" }, ficha(m));
    b.addEventListener("click", () => void escolherPokemon(modal, m, time, aviso, aoMudar, abas));
    lista.append(b);
  }
  nos.push(lista);
  modal.abrir("MTs", ...nos);
}

async function escolherPokemon(modal: Modal, m: MT, time: PokemonRow[], aviso: Aviso, aoMudar: () => void, abas: HTMLElement | null): Promise<void> {
  const { data } = await supabase.from("mt_compat").select("especie_id").eq("golpe_id", m.golpe_id);
  const pode = new Set(((data ?? []) as { especie_id: number }[]).map((r) => r.especie_id));
  const nos: Node[] = [el("div", { class: "item-cartao mt-topo" }, ficha(m))];
  const voltar = el("button", { type: "button", class: "sec" }, "← Voltar");
  voltar.addEventListener("click", () => void abrirMTs(modal, aviso, abas, aoMudar));
  for (const p of time) {
    const conhece = (p.golpes ?? []).some((g) => g.id === m.golpe_id);
    const ok = pode.has(p.especie_id) && !conhece;
    const b = el("button", { type: "button", class: "item-cartao mt-item" }, imagemPokemon("frente", p.especie_id, "mini"),
      el("div", { class: "item-txt" }, el("strong", {}, nomePokemon(p)), el("small", {}, conhece ? "Já conhece este golpe" : pode.has(p.especie_id) ? `Nv ${p.nivel} · pode aprender` : "Não consegue aprender")));
    b.disabled = !ok;
    if (ok) b.addEventListener("click", () => void escolherGolpe(modal, m, p, aviso, aoMudar, abas));
    nos.push(b);
  }
  nos.push(voltar);
  modal.abrir("Quem vai aprender?", ...nos);
}

async function ensinar(modal: Modal, m: MT, p: PokemonRow, slot: number | null, aviso: Aviso, aoMudar: () => void, abas: HTMLElement | null): Promise<void> {
  const { data, error } = await supabase.rpc("mt_ensinar", { p_pokemon: p.id, p_num: m.num, p_slot: slot });
  if (error) return void aviso(error.message, 4500, true);
  const r = data as { golpe: string; esqueceu: string | null };
  aviso(`${nomePokemon(p)} aprendeu ${r.golpe}${r.esqueceu ? ` e esqueceu ${r.esqueceu}` : ""}!`, 5000);
  aoMudar();
  await abrirMTs(modal, aviso, abas, aoMudar);
}

async function escolherGolpe(modal: Modal, m: MT, p: PokemonRow, aviso: Aviso, aoMudar: () => void, abas: HTMLElement | null): Promise<void> {
  if ((p.golpes ?? []).length < 4) return void (await ensinar(modal, m, p, null, aviso, aoMudar, abas));
  const nos: Node[] = [el("p", { class: "sub" }, `${nomePokemon(p)} já sabe 4 golpes. Qual esquecer para aprender ${golpe(m.golpe_id).nome}?`)];
  (p.golpes ?? []).forEach((g, i) => {
    const gi = golpe(g.id);
    const b = el("button", { type: "button", class: "item-cartao mt-item" }, el("div", { class: "item-txt" }, el("strong", {}, gi.nome), el("small", {}, `${NOME_TIPO[gi.tipo] ?? gi.tipo} · ${CAT[gi.categoria] ?? gi.categoria} · Poder ${gi.poder ?? "—"} · PP ${gi.pp}`)));
    b.addEventListener("click", () => void ensinar(modal, m, p, i, aviso, aoMudar, abas));
    nos.push(b);
  });
  const cancelar = el("button", { type: "button", class: "sec" }, "Cancelar");
  cancelar.addEventListener("click", () => void abrirMTs(modal, aviso, abas, aoMudar));
  nos.push(cancelar);
  modal.abrir("Esquecer qual golpe?", ...nos);
}

/** Loja grande: compra de MTs liberadas no arco atual. */
export async function abrirLojaMT(modal: Modal, poi: string, dinheiro: number, aviso: Aviso, aoMudar: () => void): Promise<void> {
  await carregarReferencias();
  const mts = (await listar()).filter((m) => m.liberada && !m.tenho);
  const saldo = el("p", { class: "sub" }, `Seu dinheiro: ₽ ${dinheiro}`);
  const nos: Node[] = [saldo, el("p", { class: "sub" }, "MTs são infinitas: compre uma vez e ensine a quantos Pokémon puderem aprender.")];
  if (!mts.length) nos.push(el("p", { class: "sub" }, "Não há MTs novas à venda agora."));
  for (const m of mts) {
    const linha = el("div", { class: "item-cartao loja mt-loja" }, ficha(m, ` · ₽ ${m.preco}`));
    const b = el("button", { type: "button", class: "sec" }, "Comprar");
    b.addEventListener("click", async () => {
      b.disabled = true;
      const { data, error } = await supabase.rpc("mt_comprar", { p_poi: poi, p_num: m.num });
      if (error) { b.disabled = false; return void aviso(error.message, 4500, true); }
      const r = data as { dinheiro: number };
      saldo.textContent = `Seu dinheiro: ₽ ${r.dinheiro}`;
      linha.remove();
      aviso(`Você comprou ${rotulo(m)}!`, 3500);
      aoMudar();
    });
    linha.append(b);
    nos.push(linha);
  }
  const grade = el("div", { class: "grade-loja" });
  const fixos = nos.slice(0, 2); const itens = nos.slice(2);
  grade.append(...itens);
  modal.abrir("MTs à venda", ...fixos, grade);
}
