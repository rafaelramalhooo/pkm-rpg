import { supabase } from "../supabase";
import { el } from "./dom";
import { processarEventos } from "./momentos";
import { carregarReferencias, especie, imagemPokemon, nomeItem, nomePokemon, type PokemonRow } from "./dados";

/** Texto dos eventos de experiência devolvidos pelo servidor (nível, evolução, golpes). */
export function textoEventos(ev: { t: string; valor?: number; nivel?: number; nome?: string; golpe?: string; para?: string; esqueceu?: string }[]): string {
  return ev.map((x) => (x.t === "exp" ? `+${x.valor} XP` : x.t === "nivel" ? `${x.nome} subiu para o nível ${x.nivel}!` : x.t === "evolucao" ? `${x.nome} evoluiu para ${x.para}!` : x.t === "aprendeu" ? (x.esqueceu ? `${x.nome} esqueceu ${x.esqueceu} e aprendeu ${x.golpe}!` : `${x.nome} aprendeu ${x.golpe}!`) : "")).filter(Boolean).join(" · ");
}

/** Executa uma ação que gasta PA e mostra claramente quanto foi gasto e quanto resta. */
export async function acaoPA(rpc: string, args: Record<string, unknown>, uid: string, aviso: Aviso, aoMudar: () => void, texto: (d: Record<string, unknown>) => string): Promise<boolean> {
  const { data, error } = await supabase.rpc(rpc, args);
  if (error) { aviso(error.message, 4000, true); return false; }
  const { data: j } = await supabase.from("jogadores").select("pa").eq("id", uid).maybeSingle();
  const pa = j ? ` · −1 PA (restam ${(j as { pa: number }).pa})` : " · −1 PA";
  aviso(`${texto((data ?? {}) as Record<string, unknown>)}${pa}`, 5000);
  aoMudar();
  await processarEventos((data as { eventos?: { t: string }[] } | null)?.eventos);
  return true;
}

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

interface Hab { id: string; classe: string; ordem: number; nome: string; descricao: string; bonus: number; req: { id: string; rank: number }[]; ativo: boolean }
interface Estado {
  classe: string | null; nivel: number; xp: number; xp_atual_nivel: number; xp_prox: number | null;
  pontos_total: number; pontos_gastos: number; habilidades: Record<string, number>; pesquisadas: number;
}

const CLASSES: { nome: string; texto: string }[] = [
  { nome: "Treinador", texto: "Focado em batalhas e treino: mais recompensas, resistência e força em combate." },
  { nome: "Criador", texto: "Focado em cuidar dos Pokémon: amizade, treino intenso, caixas e (no futuro) ovos." },
  { nome: "Pesquisador", texto: "Focado em explorar o mundo: pesquisas, pesca, descontos e descobertas." },
];


/** Unidade do bônus de cada habilidade (o bônus é somado a cada rank; o máximo é no rank 3). */
const UNIDADE: Record<string, string> = {
  instinto: "% de dano", recompensa: "% de dinheiro", mestre_treino: " XP por treino", resistencia: " PA máx.", foco: "% de precisão", cura_rapida: "% de HP",
  lideranca: " de amizade", provocacao: " PA máx.", veterano: "% de XP", campeao: "% nos atributos", afeto: " uso(s) extra/dia", mao_amiga: "% de cura",
  olho_brilhante: "% de brilhante", ovos: "", alimentador: " XP por cuidado", laco: "% de XP", espaco: " espaços de caixa", treino_intenso: "% de XP no treino",
  banco_dados: "", criador_mestre: "", olhar_atento: " XP de treinador (e +₽25 por rank)", exploracao: "% de recompensa", rede_pesca: "% de chance", captura: "% de captura",
  mochila: " por item", mapa_mental: "", economia: "% de desconto", pokedex_viva: " XP por espécie nova", intuicao: " PA máx.", cientista: "",
};
const fmt = (n: number): string => (Number.isInteger(n) ? String(n) : n.toFixed(1).replace(".", ","));

/** Tela do Treinador: classe, nível, pontos e árvore de habilidades (compra validada no servidor). */
export async function abrirHabilidades(modal: Modal, aviso: Aviso, aoMudar: () => void): Promise<void> {
  const [{ data: est, error }, { data: cat }] = await Promise.all([
    supabase.rpc("estado_treino"),
    supabase.from("habilidades_catalogo").select("*").order("classe").order("ordem"),
  ]);
  if (error) { aviso(error.message, 4000, true); return; }
  const e = est as Estado;
  const habs = (cat ?? []) as Hab[];

  if (!e.classe) {
    const cartas = CLASSES.map((c) => {
      const b = el("button", { type: "button", class: "hab-classe" }, el("strong", {}, c.nome), el("span", {}, c.texto));
      b.addEventListener("click", async () => {
        const { error: er } = await supabase.rpc("escolher_classe", { p_classe: c.nome });
        if (er) return void aviso(er.message, 4000, true);
        aviso(`Você agora é ${c.nome}!`);
        void abrirHabilidades(modal, aviso, aoMudar);
      });
      return b;
    });
    modal.abrir("Escolha sua classe", el("p", { class: "sub" }, "A classe define quais habilidades você pode desenvolver. Esta escolha é permanente."), el("div", { class: "hab-classes" }, ...cartas));
    return;
  }

  const livres = e.pontos_total - e.pontos_gastos;
  const pct = e.xp_prox ? Math.round(((e.xp - e.xp_atual_nivel) / (e.xp_prox - e.xp_atual_nivel)) * 100) : 100;
  const barra = el("div", { class: "hab-xp" }, el("div", { class: "hab-xp-fill" }));
  (barra.firstElementChild as HTMLElement).style.width = `${pct}%`;
  const cab = el("div", { class: "hab-cab" },
    el("div", {}, el("strong", {}, `${e.classe} · Nível ${e.nivel}`), el("span", { class: "sub" }, e.xp_prox ? ` XP ${e.xp}/${e.xp_prox}` : ` XP ${e.xp} (nível máximo)`)),
    barra,
    el("div", { class: "hab-pontos" }, `Pontos de habilidade: ${livres}`, el("small", {}, ` (${e.pontos_total} ganhos: 1 por nível de treinador + 1 a cada 5 níveis somados do time)`)));

  const nomes = new Map(habs.map((h) => [h.id, h.nome]));
  const cartoes = habs.filter((h) => h.classe === e.classe).map((h) => {
    const rank = e.habilidades[h.id] ?? 0;
    const faltam = h.req.filter((r) => (e.habilidades[r.id] ?? 0) < r.rank);
    const custo = rank + 1;
    const bolas = el("span", { class: "hab-ranks" }, ...[1, 2, 3].map((n) => el("i", { class: n <= rank ? "on" : "" })));
    const b = el("button", { type: "button", class: "sec hab-comprar" }, rank >= 3 ? "Máximo" : `Aprender (${custo} pt)`);
    b.disabled = rank >= 3 || faltam.length > 0 || livres < custo;
    b.addEventListener("click", async () => {
      const { error: er } = await supabase.rpc("comprar_habilidade", { p_hab: h.id });
      if (er) return void aviso(er.message, 4000, true);
      aoMudar();
      void abrirHabilidades(modal, aviso, aoMudar);
    });
    const req = faltam.length ? el("small", { class: "hab-req" }, `Requer: ${faltam.map((r) => `${nomes.get(r.id)} rank ${r.rank}`).join(", ")}`) : null;
    const card = el("div", { class: `hab-card${h.ativo ? "" : " breve"}` }, el("div", { class: "hab-topo" }, el("strong", {}, h.nome), bolas), el("p", {}, h.descricao));
    const un = UNIDADE[h.id];
    if (un) card.append(el("div", { class: "hab-total" }, el("span", {}, `Agora: ${rank ? "+" + fmt(h.bonus * rank) : "—"}${rank ? un : ""}`), el("span", {}, `Máximo (rank 3): +${fmt(h.bonus * 3)}${un}`)));
    if (req) card.append(req);
    card.append(b);
    return card;
  });
  modal.abrir("Habilidades do treinador", cab, el("div", { class: "hab-grade" }, ...cartoes));
}

/** Menu de ações que gastam PA: Treinar, Cuidar, Pesquisar, Explorar, Pescar, Barganhar. */
export async function abrirAcoes(modal: Modal, uid: string, aviso: Aviso, aoMudar: () => void): Promise<void> {
  await carregarReferencias();
  const msg = el("div", { class: "hab-msg" });
  const rodar = async (rpc: string, args: Record<string, unknown>, texto: (d: Record<string, unknown>) => string) => {
    await acaoPA(rpc, args, uid, (t, ms, er) => { msg.textContent = t; aviso(t, ms, er); }, aoMudar, texto);
  };
  const eventosTxt = (d: Record<string, unknown>): string => textoEventos((d.eventos ?? []) as Parameters<typeof textoEventos>[0]);

  const { data: pks } = await supabase.from("pokemons").select("*").eq("dono", uid).not("posicao", "is", null).order("posicao");
  const time = (pks ?? []) as PokemonRow[];
  const lista = (rotulo: string, rpc: string, fim: (d: Record<string, unknown>) => string) =>
    el("div", { class: "acao-bloco" }, el("label", {}, rotulo),
      el("div", { class: "acao-pks" }, ...time.map((p) => {
        const b = el("button", { type: "button", class: "sec acao-pk" }, imagemPokemon("frente", p.especie_id, "mini", p.brilhante), el("span", {}, `${nomePokemon(p)} Nv ${p.nivel}`));
        b.addEventListener("click", () => void rodar(rpc, { p_pokemon: p.id }, fim));
        return b;
      })));

  const simples = (rotulo: string, rpc: string, fim: (d: Record<string, unknown>) => string) => {
    const b = el("button", { type: "button", class: "sec" }, rotulo);
    b.addEventListener("click", () => void rodar(rpc, {}, fim));
    return b;
  };

  const { data: dex } = await supabase.from("pokedex").select("especie_id, pesquisado").eq("jogador", uid).eq("pesquisado", false).order("especie_id");
  const pesq = el("div", { class: "acao-bloco" }, el("label", {}, "Pesquisar espécie vista (1 PA, uma vez por espécie)"),
    el("div", { class: "acao-pks" }, ...((dex ?? []) as { especie_id: number }[]).slice(0, 60).map((r) => {
      const b = el("button", { type: "button", class: "sec acao-pk" }, imagemPokemon("frente", r.especie_id, "mini"), el("span", {}, especie(r.especie_id).nome));
      b.addEventListener("click", () => void rodar("acao_pesquisar", { p_especie: r.especie_id }, (d) => `Pesquisa concluída! +${d.xp} XP de treinador e ₽${d.dinheiro}${d.bonus ? " (bônus de 10 espécies!)" : ""}.`));
      return b;
    })));

  modal.abrir("Ações (gastam 1 PA)",
    el("p", { class: "sub" }, "Cada ação custa 1 PA. Treinar e Cuidar valem para o seu time; Explorar só uma vez por dia em cada ponto do mapa."),
    msg,
    lista("Treinar (+25 XP)", "acao_treinar", (d) => eventosTxt(d) || "Treino concluído!"),
    lista("Cuidar (+1 amizade, até 3 vezes por dia por Pokémon)", "acao_cuidar", (d) => `Você cuidou do Pokémon! Amizade ${d.amizade}. ${eventosTxt(d)}`),
    pesq,
    el("div", { class: "acao-linha" },
      simples("Explorar aqui", "acao_explorar", (d) => (d.tipo === "dinheiro" ? `Você achou ₽${d.valor}!` : `Você achou ${d.qtd}× ${nomeItem(String(d.item))}!`)),
      simples("Pescar", "acao_pescar", (d) => (d.tipo === "nada" ? "Nada mordeu a isca..." : d.tipo === "dinheiro" ? `Você pescou ₽${d.valor}!` : `Você pescou ${d.qtd}× ${nomeItem(String(d.item))}!`)),
      simples("Barganhar", "acao_barganhar", (d) => (d.ok ? "Barganha bem-sucedida! 10% de desconto na próxima compra." : "O lojista não cedeu desta vez."))));
}
