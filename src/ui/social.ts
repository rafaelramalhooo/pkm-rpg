// Jogadores: desafios de batalha (1 PA para cada) e trocas de Pokémon e itens. Tudo é validado no servidor.
import { supabase } from "../supabase";
import { el } from "./dom";
import { carregarReferencias, especie, imagemPokemon, nomeItem, nomePokemon, minhaMochila, type PokemonRow } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

export interface Pendencias {
  desafios_recebidos: { id: string; de: string; nome: string }[];
  desafios_enviados: { id: string; para: string; nome: string }[];
  trocas_recebidas: { id: string; de: string; nome: string; oferta: string; pedido: string }[];
  batalha: { id: string } | null;
  historico: { de: string; para: string; estado: string; eu_desafiei: boolean }[];
}
interface Perfil { pokemons: { id: string; especie_id: number; nome: string; nivel: number; brilhante: boolean }[]; itens: { item: string; qtd: number }[] }

export async function carregarPendencias(): Promise<Pendencias | null> {
  const { data, error } = await supabase.rpc("desafio_pendencias");
  return error ? null : ((data as Pendencias | null) ?? null);
}

const TEXTO_RESULTADO: Record<string, string> = { vitoria: "venceu", derrota: "perdeu", fuga: "fugiu", ativa: "luta em andamento", captura: "encerrada" };

export async function abrirSocial(modal: Modal, uid: string, aviso: Aviso, aoMudar: () => void, lutarAgora: () => Promise<void>): Promise<void> {
  await carregarReferencias();
  const [{ data: lista }, pend] = await Promise.all([supabase.rpc("jogadores_lista"), carregarPendencias()]);
  const jogadores = (lista ?? []) as { id: string; nome: string; aparencia: number; mapa_id: string }[];
  const reabrir = (): void => void abrirSocial(modal, uid, aviso, aoMudar, lutarAgora);
  const nos: Node[] = [el("p", { class: "sub" }, "Desafios custam 1 PA para cada jogador e são duelos ao vivo: os dois escolhem o golpe ao mesmo tempo. Trocas são feitas só quando os dois concordam.")];

  if (pend?.batalha) {
    const b = el("button", { type: "button" }, "Lutar agora: seu desafio foi aceito!");
    b.addEventListener("click", () => { modal.fechar(); void lutarAgora(); });
    nos.push(b);
  }
  for (const d of pend?.desafios_recebidos ?? []) {
    const ac = el("button", { type: "button" }, "Aceitar (−1 PA)"); const re = el("button", { type: "button", class: "sec" }, "Recusar");
    ac.addEventListener("click", async () => {
      const { error } = await supabase.rpc("desafio_responder", { p_desafio: d.id, p_aceitar: true });
      if (error) return void aviso(error.message, 4000, true);
      aviso(`Desafio de ${d.nome} aceito! −1 PA. Boa luta!`, 3000);
      aoMudar(); modal.fechar(); void lutarAgora();
    });
    re.addEventListener("click", async () => { await supabase.rpc("desafio_responder", { p_desafio: d.id, p_aceitar: false }); reabrir(); });
    nos.push(el("div", { class: "soc-card" }, el("strong", {}, `${d.nome} desafiou você!`), ac, re));
  }
  for (const t of pend?.trocas_recebidas ?? []) {
    const ac = el("button", { type: "button" }, "Aceitar troca"); const re = el("button", { type: "button", class: "sec" }, "Recusar");
    ac.addEventListener("click", async () => {
      const { error } = await supabase.rpc("troca_responder", { p_troca: t.id, p_aceitar: true });
      if (error) return void aviso(error.message, 5000, true);
      aviso("Troca concluída!", 4000); aoMudar(); reabrir();
    });
    re.addEventListener("click", async () => { await supabase.rpc("troca_responder", { p_troca: t.id, p_aceitar: false }); reabrir(); });
    nos.push(el("div", { class: "soc-card" }, el("strong", {}, `${t.nome} propõe uma troca`), el("p", { class: "sub" }, `Ele oferece: ${t.oferta}`), el("p", { class: "sub" }, `Ele pede: ${t.pedido}`), ac, re));
  }
  for (const e of pend?.desafios_enviados ?? []) {
    const c = el("button", { type: "button", class: "sec" }, "Cancelar");
    c.addEventListener("click", async () => { await supabase.rpc("desafio_cancelar", { p_desafio: e.id }); reabrir(); });
    nos.push(el("div", { class: "soc-card" }, el("span", {}, `Aguardando ${e.nome} aceitar o seu desafio…`), c));
  }
  if (pend?.historico.length) nos.push(el("div", { class: "soc-hist" }, el("small", {}, "Últimas lutas"), ...pend.historico.map((h) => el("p", { class: "sub" }, `${h.de} × ${h.para}: ${h.eu_desafiei ? `${h.de} ${TEXTO_RESULTADO[h.estado] ?? h.estado}` : `${h.de} ${TEXTO_RESULTADO[h.estado] ?? h.estado} contra você`}`))));

  nos.push(el("small", {}, "Jogadores"));
  if (!jogadores.length) nos.push(el("p", { class: "sub" }, "Ainda não há outros jogadores."));
  for (const p of jogadores) {
    const lutar = el("button", { type: "button", class: "sec" }, "Desafiar");
    lutar.addEventListener("click", async () => {
      const { error } = await supabase.rpc("desafio_enviar", { p_alvo: p.id });
      if (error) return void aviso(error.message, 4000, true);
      aviso(`Desafio enviado a ${p.nome}. Ele precisa aceitar (1 PA de cada).`, 4500); reabrir();
    });
    const trocar = el("button", { type: "button", class: "sec" }, "Trocar");
    trocar.addEventListener("click", () => void montarTroca(modal, uid, p, aviso, reabrir));
    nos.push(el("div", { class: "soc-linha" }, el("strong", {}, p.nome), el("div", { class: "soc-bts" }, lutar, trocar)));
  }
  modal.abrir("Jogadores", ...nos);
}

async function montarTroca(modal: Modal, uid: string, alvo: { id: string; nome: string }, aviso: Aviso, voltar: () => void): Promise<void> {
  const [{ data: meus }, mochila, { data: perfil }] = await Promise.all([
    supabase.from("pokemons").select("*").eq("dono", uid).order("nivel", { ascending: false }),
    minhaMochila(uid), supabase.rpc("perfil_troca", { p_jogador: alvo.id }),
  ]);
  const meusPk = (meus ?? []) as PokemonRow[];
  const dele = (perfil ?? { pokemons: [], itens: [] }) as Perfil;
  const ofertaPk = new Set<string>(); const pedidoPk = new Set<string>();
  const ofertaIt = new Map<string, number>(); const pedidoIt = new Map<string, number>();

  const chipPk = (id: string, espId: number, nome: string, nivel: number, set: Set<string>): HTMLElement => {
    const b = el("button", { type: "button", class: "troca-pk sec" }, imagemPokemon("frente", espId, "mini"), el("span", {}, `${nome} Nv ${nivel}`));
    b.addEventListener("click", () => { if (set.has(id)) set.delete(id); else set.add(id); b.classList.toggle("sel", set.has(id)); });
    return b;
  };
  const linhaItem = (item: string, max: number, mapa: Map<string, number>): HTMLElement => {
    const n = el("input", { type: "number", min: "0", max: String(max), value: "0", class: "troca-qtd", "aria-label": nomeItem(item) });
    n.addEventListener("input", () => { const v = Math.max(0, Math.min(max, Number(n.value) || 0)); if (v) mapa.set(item, v); else mapa.delete(item); });
    return el("label", { class: "troca-it" }, el("span", {}, `${nomeItem(item)} (${max})`), n);
  };
  const itens = (m: Map<string, number>) => [...m].map(([item, qtd]) => ({ item, qtd }));
  const enviar = el("button", { type: "button" }, `Propor troca a ${alvo.nome}`);
  enviar.addEventListener("click", async () => {
    const { error } = await supabase.rpc("troca_propor", { p_para: alvo.id, p_oferta: { pokemons: [...ofertaPk], itens: itens(ofertaIt) }, p_pedido: { pokemons: [...pedidoPk], itens: itens(pedidoIt) } });
    if (error) return void aviso(error.message, 5000, true);
    aviso(`Proposta enviada a ${alvo.nome}.`, 4000); voltar();
  });
  const cancelar = el("button", { type: "button", class: "sec" }, "Voltar");
  cancelar.addEventListener("click", voltar);
  modal.abrir(`Troca com ${alvo.nome}`,
    el("p", { class: "sub" }, "Toque nos Pokémon para marcar. Itens: digite a quantidade. Só vale se o outro jogador aceitar."),
    el("small", {}, "Você oferece"), el("div", { class: "troca-grade" }, ...meusPk.map((p) => chipPk(p.id, p.especie_id, nomePokemon(p), p.nivel, ofertaPk))),
    el("div", { class: "troca-itens" }, ...mochila.filter((i) => i.qtd > 0 && !/ball$/.test(i.item)).map((i) => linhaItem(i.item, i.qtd, ofertaIt))),
    el("small", {}, `Você pede a ${alvo.nome}`), el("div", { class: "troca-grade" }, ...dele.pokemons.map((p) => chipPk(p.id, p.especie_id, p.nome || especie(p.especie_id).nome, p.nivel, pedidoPk))),
    el("div", { class: "troca-itens" }, ...dele.itens.map((i) => linhaItem(i.item, i.qtd, pedidoIt))),
    enviar, cancelar);
}
