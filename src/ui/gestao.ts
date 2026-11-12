import { supabase } from "../supabase";
import { el } from "./dom";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
interface Resumo { id: string; nome: string; papel: string; pa: number; dinheiro: number; mapa_id: string; insignias: string[]; campeao: boolean; email: string | null; pokemons: number; maior_nivel: number }
interface Pk { id: string; especie_id: number; apelido: string | null; nivel: number; hp_atual: number; hp_max: number; posicao: number | null; brilhante: boolean }
interface Ficha {
  jogador: { id: string; nome: string; papel: string; pa: number; dinheiro: number; mapa_id: string; x: number; y: number; insignias: string[]; campeao: boolean };
  email: string | null; pokemons: Pk[]; itens: { item: string; qtd: number }[]; treinadores: number; pokedex: number;
}

const campo = (rot: string, entrada: HTMLElement) => el("label", { class: "mg-campo" }, el("span", {}, rot), entrada);
const num = (v: number, min = 0) => el("input", { type: "number", value: String(v), min: String(min) });

/** Gestão do Mestre: todos os usuários, fichas, Pokémon e itens, com edição manual. */
export async function abrirGestao(modal: Modal, aviso: (t: string) => void): Promise<void> {
  const [{ data: lista, error }, { data: esp }, { data: its }, { data: mps }] = await Promise.all([
    supabase.rpc("mestre_jogadores"),
    supabase.from("especies").select("id, nome").order("id").limit(2000),
    supabase.from("itens").select("slug, nome").order("nome").limit(500),
    supabase.from("mapas").select("id, nome").order("nome").limit(100),
  ]);
  if (error) { aviso(error.message); return; }
  const jogadores = (lista ?? []) as Resumo[];
  const especies = (esp ?? []) as { id: number; nome: string }[];
  const nomeEsp = new Map(especies.map((e) => [e.id, e.nome]));
  const itens = (its ?? []) as { slug: string; nome: string }[];
  const mapas = (mps ?? []) as { id: string; nome: string }[];
  const msg = el("p", { class: "msg" }, "");
  const dizer = (t: string, ok = true) => { msg.textContent = t; msg.className = `msg ${ok ? "ok" : "erro"}`; };
  const chamar = async (fn: string, args: Record<string, unknown>) => {
    const { error: e } = await supabase.rpc(fn, args);
    if (e) { dizer(e.message, false); return false; }
    dizer("Salvo.");
    return true;
  };

  const esq = el("div", { class: "mg-lista" });
  const dir = el("div", { class: "mg-ficha" }, el("p", { class: "sub" }, "Escolha um usuário na lista."));
  const busca = el("input", { type: "search", placeholder: "Buscar por nome ou e-mail…" });
  const desenharLista = () => {
    const q = busca.value.trim().toLowerCase();
    esq.replaceChildren(...jogadores.filter((j) => !q || j.nome.toLowerCase().includes(q) || (j.email ?? "").toLowerCase().includes(q)).map((j) => {
      const b = el("button", { type: "button", class: "mg-item" }, el("strong", {}, `${j.papel === "mestre" ? "👑 " : ""}${j.nome}`),
        el("span", {}, `${j.pokemons} Pokémon · maior Nv ${j.maior_nivel} · ${j.insignias.length} insígnias`), el("span", { class: "sub" }, j.email ?? ""));
      b.addEventListener("click", () => void abrirFicha(j.id));
      return b;
    }));
  };
  busca.addEventListener("input", desenharLista);

  async function abrirFicha(id: string): Promise<void> {
    const { data, error: e } = await supabase.rpc("mestre_ficha", { p_id: id });
    if (e || !data) { dizer(e?.message ?? "Ficha indisponível.", false); return; }
    const f = data as Ficha;
    const j = f.jogador;
    const nome = el("input", { type: "text", value: j.nome, maxlength: "24" });
    const pa = num(j.pa), din = num(j.dinheiro);
    const papel = el("select", {}, el("option", { value: "jogador" }, "Jogador"), el("option", { value: "mestre" }, "Mestre")); papel.value = j.papel;
    const ins = el("input", { type: "text", value: j.insignias.join(", "), placeholder: "ex.: Pedra, Cascata" });
    const camp = el("input", { type: "checkbox" }); camp.checked = j.campeao;
    const mapa = el("select", {}, ...mapas.map((m) => el("option", { value: m.id }, `${m.nome} (${m.id})`))); mapa.value = j.mapa_id;
    const mx = num(j.x), my = num(j.y);
    const salvar = el("button", { type: "button" }, "Salvar ficha");
    salvar.addEventListener("click", async () => {
      const campos: Record<string, unknown> = { nome: nome.value, pa: Number(pa.value), dinheiro: Number(din.value), papel: papel.value, campeao: camp.checked,
        insignias: ins.value.split(",").map((x) => x.trim()).filter(Boolean) };
      if (mapa.value !== j.mapa_id || Number(mx.value) !== j.x || Number(my.value) !== j.y) Object.assign(campos, { mapa_id: mapa.value, x: Number(mx.value), y: Number(my.value) });
      if (await chamar("mestre_editar_jogador", { p_id: id, p_campos: campos })) await abrirFicha(id);
    });

    const pk = f.pokemons.map((p) => {
      const ap = el("input", { type: "text", value: p.apelido ?? "", placeholder: nomeEsp.get(p.especie_id) ?? `#${p.especie_id}`, maxlength: "20" });
      const nv = num(p.nivel, 1); nv.max = "1000";
      const br = el("input", { type: "checkbox" }); br.checked = p.brilhante;
      const sv = el("button", { type: "button", class: "sec" }, "Salvar");
      sv.addEventListener("click", async () => { if (await chamar("mestre_editar_pokemon", { p_id: p.id, p_campos: { apelido: ap.value, nivel: Number(nv.value), brilhante: br.checked } })) await abrirFicha(id); });
      const cu = el("button", { type: "button", class: "sec" }, "Curar");
      cu.addEventListener("click", async () => { if (await chamar("mestre_editar_pokemon", { p_id: p.id, p_campos: { curar: true } })) await abrirFicha(id); });
      const rm = el("button", { type: "button", class: "sec" }, "Remover");
      rm.addEventListener("click", async () => { if (!window.confirm(`Remover ${p.apelido ?? nomeEsp.get(p.especie_id)} definitivamente?`)) return; if (await chamar("mestre_remover_pokemon", { p_id: p.id })) await abrirFicha(id); });
      return el("div", { class: "mg-pk" }, el("strong", {}, `${p.posicao ? `#${p.posicao}` : "Caixa"} · ${nomeEsp.get(p.especie_id) ?? p.especie_id} · ${p.hp_atual}/${p.hp_max} HP`),
        el("div", { class: "mg-linha" }, campo("Apelido", ap), campo("Nível", nv), el("label", { class: "mg-chk" }, br, "✨ Brilhante")), el("div", { class: "mg-linha" }, sv, cu, rm));
    });

    const dEsp = el("input", { type: "text", list: "mg-esp", placeholder: "nome ou nº da espécie" });
    const dl = el("datalist", { id: "mg-esp" }, ...especies.map((e) => el("option", { value: e.nome }, `#${e.id}`)));
    const dNv = num(5, 1); dNv.max = "100";
    const dBr = el("input", { type: "checkbox" });
    const dar = el("button", { type: "button", class: "sec" }, "Dar Pokémon");
    dar.addEventListener("click", async () => {
      const t = dEsp.value.trim().toLowerCase();
      const ach = especies.find((e) => e.nome.toLowerCase() === t || String(e.id) === t);
      if (!ach) { dizer("Espécie não encontrada.", false); return; }
      if (await chamar("mestre_dar_pokemon", { p_jogador: id, p_especie: ach.id, p_nivel: Number(dNv.value), p_brilhante: dBr.checked })) await abrirFicha(id);
    });

    const its2 = f.itens.map((i) => {
      const q = num(i.qtd); q.style.width = "80px";
      const s = el("button", { type: "button", class: "sec" }, "Definir");
      s.addEventListener("click", async () => { if (await chamar("mestre_definir_item", { p_jogador: id, p_item: i.item, p_qtd: Number(q.value) })) await abrirFicha(id); });
      return el("div", { class: "mg-linha" }, el("span", { class: "mg-it" }, itens.find((x) => x.slug === i.item)?.nome ?? i.item), q, s);
    });
    const nIt = el("select", {}, ...itens.map((x) => el("option", { value: x.slug }, x.nome)));
    const nQ = num(1); nQ.style.width = "80px";
    const add = el("button", { type: "button", class: "sec" }, "Adicionar item");
    add.addEventListener("click", async () => { if (await chamar("mestre_definir_item", { p_jogador: id, p_item: nIt.value, p_qtd: Number(nQ.value) })) await abrirFicha(id); });

    dir.replaceChildren(
      el("h3", {}, `${j.nome} ${f.email ? `· ${f.email}` : ""}`),
      el("p", { class: "sub" }, `Treinadores vencidos: ${f.treinadores} · Pokédex: ${f.pokedex}/151`),
      el("div", { class: "mg-grade" }, campo("Nome", nome), campo("Papel", papel), campo("PA", pa), campo("Dinheiro (₽)", din), campo("Insígnias", ins),
        el("label", { class: "mg-chk" }, camp, "Campeão da Liga"), campo("Mapa", mapa), campo("X", mx), campo("Y", my)),
      salvar,
      el("label", {}, `Pokémon (${f.pokemons.length})`), ...pk,
      el("div", { class: "mg-linha" }, campo("Dar Pokémon", dEsp), dl, campo("Nível", dNv), el("label", { class: "mg-chk" }, dBr, "✨"), dar),
      el("label", {}, "Mochila"), ...its2, el("div", { class: "mg-linha" }, nIt, nQ, add),
    );
  }

  desenharLista();
  modal.abrir("Gestão do Mestre", el("div", { class: "mg-wrap" }, el("div", { class: "mg-esq" }, busca, esq), dir), msg);
}
