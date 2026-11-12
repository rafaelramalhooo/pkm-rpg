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

const CLASSES: { nome: string; texto: string; estilo: string }[] = [
  { nome: "Treinador", texto: "Focado em batalhas e treino: mais recompensas, resistência e força em combate.", estilo: "Para quem gosta de lutar e evoluir o time rápido. Hoje já funciona: Mestre de Treino (Treinar rende mais XP aos Pokémon)." },
  { nome: "Criador", texto: "Focado em cuidar dos Pokémon: amizade, treino intenso, caixas e (no futuro) ovos.", estilo: "Para quem gosta de cuidar e criar laços. Hoje já funciona: Afeto (mais usos de Cuidar por dia), Alimentador (Cuidar rende XP) e Treino Intenso (+% de XP ao Treinar)." },
  { nome: "Pesquisador", texto: "Focado em explorar o mundo: pesquisas, pesca, descontos e descobertas.", estilo: "Para quem gosta de explorar e descobrir. Hoje já funciona: Olhar Atento (Pesquisar rende mais), Exploração, Rede de Pesca, Economia (lojas mais baratas) e Pokédex Viva." },
];

const PONTOS_ESCADA = "Cada habilidade tem 3 ranks. Aprender o rank 1 custa 1 ponto, o rank 2 custa 2 e o rank 3 custa 3 (6 pontos no total). O bônus soma a cada rank.";

/** Quadro "como funciona" (classes, XP de treinador, pontos e ranks). */
function quadroComoFunciona(): HTMLElement {
  const li = (t: string) => el("li", {}, t);
  return el("details", { class: "hab-ajuda" }, el("summary", {}, "❓ Como funcionam classes, pontos e habilidades"),
    el("p", {}, el("strong", {}, "Classe: "), "define qual árvore de habilidades você desenvolve. É escolhida uma vez só (só o Mestre pode redefinir)."),
    el("p", {}, el("strong", {}, "XP de treinador: "), "é diferente do XP dos Pokémon e sobe seu nível de treinador. Você ganha XP de treinador ao:"),
    el("ul", {}, li("Vencer um treinador pela primeira vez: +40 XP"), li("Registrar uma espécie nova na Pokédex (captura): +30 XP (+5 por rank de Pokédex Viva)"), li("Pesquisar uma espécie (ação de PA): +40 XP (+10 por rank de Olhar Atento)"), li("Explorar: +10 XP · Pescar com sucesso: +10 XP"), li("Concluir etapas de missão (valor varia por missão)")),
    el("p", {}, el("strong", {}, "Pontos de habilidade: "), "você ganha 1 ponto a cada nível de treinador e mais 1 a cada 5 níveis somados dos seus 6 Pokémon mais fortes (ex.: soma 25 = +5 pontos). Subir o time também rende pontos!"),
    el("p", {}, el("strong", {}, "Ranks: "), PONTOS_ESCADA),
    el("p", {}, el("strong", {}, "“Em breve”: "), "habilidades marcadas assim já aparecem, mas o efeito ainda não está ligado no jogo; gaste pontos nelas só se quiser garantir o rank para quando liberarem."),
    el("p", { class: "sub" }, "Nível de treinador: o nível 2 exige 50 XP, o 3 exige 150, o 4 exige 300, e assim por diante (cada nível pede mais que o anterior)."));
}

/** Janela obrigatória: enquanto o jogador não tiver classe, nada mais funciona. Não pode ser fechada. */
export async function exigirClasse(aviso: Aviso, aoEscolher: () => void): Promise<void> {
  if (document.querySelector(".classe-obrig")) return;
  const { data: cat } = await supabase.from("habilidades_catalogo").select("id, classe, nome, descricao, ativo").order("classe").order("ordem");
  const habs = (cat ?? []) as Pick<Hab, "id" | "classe" | "nome" | "descricao" | "ativo">[];
  const raiz = el("div", { class: "classe-obrig", role: "alertdialog", "aria-modal": "true", "aria-label": "Escolha sua classe" });
  const bloquear = (e: KeyboardEvent) => { e.stopPropagation(); };
  window.addEventListener("keydown", bloquear, true);
  const fechar = () => { window.removeEventListener("keydown", bloquear, true); raiz.remove(); };

  const lista = () => {
    raiz.replaceChildren(el("div", { class: "painel classe-caixa" },
      el("h1", {}, "Escolha a sua classe"),
      el("p", { class: "sub" }, "Antes de aventurar-se por Rafar, escolha como você quer evoluir. A classe define as habilidades que você desenvolve e a escolha é definitiva (só o Mestre pode redefinir)."),
      el("div", { class: "hab-classes" }, ...CLASSES.map((c) => {
        const ativas = habs.filter((h) => h.classe === c.nome && h.ativo);
        const b = el("button", { type: "button", class: "hab-classe" }, el("strong", {}, c.nome), el("span", {}, c.texto), el("span", { class: "classe-estilo" }, c.estilo),
          el("small", {}, `Habilidades já ativas (${ativas.length} de 10): ${ativas.map((h) => h.nome).join(", ")}`));
        b.addEventListener("click", () => confirmar(c.nome));
        return b;
      }))));
  };
  const confirmar = (nome: string) => {
    const c = CLASSES.find((x) => x.nome === nome)!;
    const ok = el("button", { type: "button" }, `Sim, quero ser ${nome}`);
    const volta = el("button", { type: "button", class: "sec" }, "Voltar");
    volta.addEventListener("click", lista);
    ok.addEventListener("click", async () => {
      ok.disabled = true;
      const { error } = await supabase.rpc("escolher_classe", { p_classe: nome });
      if (error) { ok.disabled = false; aviso(error.message, 4000, true); return; }
      fechar();
      aviso(`Você agora é ${nome}! Abra Treinador → Habilidades para usar seus pontos.`, 6000);
      aoEscolher();
    });
    raiz.replaceChildren(el("div", { class: "painel classe-caixa" }, el("h1", {}, `Confirmar: ${nome}`), el("p", {}, c.texto), el("p", { class: "classe-estilo" }, c.estilo),
      el("p", { class: "sub" }, "Atenção: não dá para trocar de classe depois. Só o Mestre consegue redefinir."), el("div", { class: "mg-linha" }, ok, volta)));
  };
  lista();
  document.body.append(raiz);
}

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
    modal.fechar();
    void exigirClasse(aviso, () => { aoMudar(); });
    return;
  }

  const livres = e.pontos_total - e.pontos_gastos;
  const pct = e.xp_prox ? Math.round(((e.xp - e.xp_atual_nivel) / (e.xp_prox - e.xp_atual_nivel)) * 100) : 100;
  const barra = el("div", { class: "hab-xp" }, el("div", { class: "hab-xp-fill" }));
  (barra.firstElementChild as HTMLElement).style.width = `${pct}%`;
  const cab = el("div", { class: "hab-cab" },
    el("div", {}, el("strong", {}, `${e.classe} · Nível ${e.nivel}`), el("span", { class: "sub" }, e.xp_prox ? ` XP ${e.xp}/${e.xp_prox}` : ` XP ${e.xp} (nível máximo)`)),
    barra,
    el("div", { class: "hab-pontos" }, `Pontos de habilidade: ${livres}`, el("small", {}, ` (${e.pontos_total} ganhos no total, ${e.pontos_gastos} já gastos)`)));

  const nomes = new Map(habs.map((h) => [h.id, h.nome]));
  const cabecalho = el("div", {}, cab, quadroComoFunciona());
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
    const card = el("div", { class: `hab-card${h.ativo ? "" : " breve"}` }, el("div", { class: "hab-topo" }, el("strong", {}, h.nome), bolas), el("span", { class: h.ativo ? "hab-selo ativa" : "hab-selo" }, h.ativo ? "✔ Ativa no jogo" : "⏳ Em breve (efeito ainda não ligado)"), el("p", {}, h.descricao.replace(/ \(em breve\)\.?$/, ".")));
    const un = UNIDADE[h.id];
    if (un) card.append(el("div", { class: "hab-total" }, el("span", {}, `Agora: ${rank ? "+" + fmt(h.bonus * rank) : "—"}${rank ? un : ""}`), el("span", {}, `Rank 1: +${fmt(h.bonus)} · Rank 2: +${fmt(h.bonus * 2)} · Rank 3: +${fmt(h.bonus * 3)}${un}`)));
    if (req) card.append(req);
    card.append(b);
    return card;
  });
  modal.abrir("Habilidades do treinador", cabecalho, el("div", { class: "hab-grade" }, ...cartoes));
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

  const info = (titulo: string, ...linhas: string[]) => el("p", { class: "acao-info" }, el("strong", {}, `${titulo} `), linhas.join(" "));
  const paAjuda = el("details", { class: "hab-ajuda", open: "" }, el("summary", {}, "❓ O que é PA e para que servem as ações"),
    el("p", {}, el("strong", {}, "PA (Pontos de Aventura): "), "é a sua energia do dia. Você começa com 30 e o Mestre repõe os PA. Andar e viajar NÃO gastam PA."),
    el("p", {}, el("strong", {}, "Onde se gasta: "), "1 PA para buscar um Pokémon selvagem na prévia de encontro e 1 PA para cada ação abaixo. Em eventos de “buscas grátis”, a busca não gasta PA."),
    info("Treinar:", "escolha um Pokémon do time. Ele ganha 25 de XP-base (+8 por rank de Mestre de Treino e +10% por rank de Treino Intenso), multiplicado por eventos de XP. Pode subir de nível, evoluir e aprender golpes."),
    info("Cuidar:", "+1 de amizade no Pokémon (máx. 255), até 3 vezes por dia por Pokémon (+1 por rank de Afeto). Com Alimentador, também rende XP. A amizade será usada em evoluções por amizade (em breve)."),
    info("Pesquisar:", "estude uma espécie que você já viu (1 vez por espécie): +40 XP de treinador e ₽150 (+10 XP e +₽25 por rank de Olhar Atento). A cada 10 espécies pesquisadas, bônus de ₽500."),
    info("Explorar:", "vasculhe o ponto onde você está (1 vez por dia em cada ponto do mapa): 60% de chance de ₽100–400 e 40% de um item (Poção ou Poké Bola); +25% de recompensa por rank de Exploração; +10 XP de treinador."),
    info("Pescar:", "só em costas e rios. 15% de chance de pescar um item (Poção, Poké Bola ou Great Ball), +10% por rank de Rede de Pesca; +10 XP de treinador ao pescar."),
    info("Barganhar:", "40% de chance de conseguir 10% de desconto na sua próxima compra em loja (o desconto é usado na compra seguinte)."));

  modal.abrir("Ações (gastam 1 PA)",
    paAjuda,
    msg,
    lista("Treinar (+25 XP)", "acao_treinar", (d) => eventosTxt(d) || "Treino concluído!"),
    lista("Cuidar (+1 amizade, até 3 vezes por dia por Pokémon)", "acao_cuidar", (d) => `Você cuidou do Pokémon! Amizade ${d.amizade}. ${eventosTxt(d)}`),
    pesq,
    el("div", { class: "acao-linha" },
      simples("Explorar aqui", "acao_explorar", (d) => (d.tipo === "dinheiro" ? `Você achou ₽${d.valor}!` : `Você achou ${d.qtd}× ${nomeItem(String(d.item))}!`)),
      simples("Pescar", "acao_pescar", (d) => (d.tipo === "nada" ? "Nada mordeu a isca..." : d.tipo === "dinheiro" ? `Você pescou ₽${d.valor}!` : `Você pescou ${d.qtd}× ${nomeItem(String(d.item))}!`)),
      simples("Barganhar", "acao_barganhar", (d) => (d.ok ? "Barganha bem-sucedida! 10% de desconto na próxima compra." : "O lojista não cedeu desta vez."))));
}
