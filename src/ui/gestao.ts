import { supabase } from "../supabase";
import { el } from "./dom";
import { barraHp, carregarReferencias, chipsTipo, golpe, imagemPokemon, NOME_TIPO } from "./dados";
import { INSIGNIAS, urlInsignia } from "./insignias";

type Modal = { raiz: HTMLElement; abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
interface Resumo { id: string; nome: string; papel: string; pa: number; dinheiro: number; mapa_id: string; insignias: string[]; campeao: boolean; email: string | null; pokemons: number; maior_nivel: number; online?: boolean; visto_ha?: number | null; classe_rpg?: string | null }
interface Pk { exp?: number; natureza?: string; amizade?: number; atk?: number; def?: number; spa?: number; spd?: number; spe?: number; golpes?: { id: number; pp: number }[]; evo_pend?: unknown; id: string; especie_id: number; apelido: string | null; nivel: number; hp_atual: number; hp_max: number; posicao: number | null; brilhante: boolean }
interface Ficha {
  jogador: { id: string; nome: string; papel: string; pa: number; dinheiro: number; mapa_id: string; x: number; y: number; insignias: string[]; campeao: boolean; aparencia?: number };
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
  await carregarReferencias();
  let jogadores = (lista ?? []) as Resumo[];
  const especies = (esp ?? []) as { id: number; nome: string }[];
  const nomeEsp = new Map(especies.map((e) => [e.id, e.nome]));
  const itens = (its ?? []) as { slug: string; nome: string }[];
  const mapas = (mps ?? []) as { id: string; nome: string }[];
  const msg = el("p", { class: "msg" }, "");
  const dizer = (t: string, ok = true) => { msg.textContent = t; msg.className = `msg ${ok ? "ok" : "erro"}`; };

  const esq = el("div", { class: "mg-lista" });
  const dir = el("div", { class: "mg-ficha" }); dir.hidden = true;
  const busca = el("input", { type: "search", placeholder: "Buscar por nome ou e-mail…" });
  const soOnline = el("input", { type: "checkbox" });
  const contador = el("strong", { class: "mg-online-n" }, "");
  const filtro = el("label", { class: "mg-chk" }, soOnline, "só online");
  const tempoVisto = (s: number | null | undefined): string => (s == null ? "nunca entrou" : s < 60 ? `visto há ${s}s` : s < 3600 ? `visto há ${Math.floor(s / 60)} min` : s < 86400 ? `visto há ${Math.floor(s / 3600)} h` : `visto há ${Math.floor(s / 86400)} d`);
  const desenharLista = () => {
    const q = busca.value.trim().toLowerCase();
    const on = jogadores.filter((j) => j.online).length;
    contador.textContent = `🟢 ${on} online agora · ${jogadores.length} contas`;
    esq.replaceChildren(...jogadores
      .filter((j) => (!q || j.nome.toLowerCase().includes(q) || (j.email ?? "").toLowerCase().includes(q)) && (!soOnline.checked || j.online))
      .sort((a, b) => Number(!!b.online) - Number(!!a.online) || a.nome.localeCompare(b.nome))
      .map((j) => {
        const b = el("button", { type: "button", class: "mg-item" },
          el("strong", {}, el("span", { class: `mg-bolinha ${j.online ? "on" : ""}`, title: j.online ? "Online agora" : "Offline" }), `${j.papel === "mestre" ? "👑 " : ""}${j.nome}`),
          el("span", {}, `${j.online ? "online · " : `${tempoVisto(j.visto_ha)} · `}${j.mapa_id} · ${j.classe_rpg ?? "sem classe"}`),
          el("span", {}, `${j.pokemons} Pokémon · maior Nv ${j.maior_nivel} · ${j.insignias.length} insígnias`), el("span", { class: "sub" }, j.email ?? ""));
        b.addEventListener("click", () => void abrirFicha(j.id));
        return b;
      }));
  };
  busca.addEventListener("input", desenharLista);
  soOnline.addEventListener("change", desenharLista);
  // atualização quase em tempo real: a cada 5 s enquanto o painel estiver aberto
  const timerOnline = window.setInterval(async () => {
    if (!esq.isConnected || esq.closest(".menu")?.hasAttribute("hidden")) { window.clearInterval(timerOnline); return; }
    const { data: l } = await supabase.rpc("mestre_jogadores");
    if (Array.isArray(l)) { jogadores = l as Resumo[]; desenharLista(); }
  }, 5000);

  // ----- manutenção e derrubar todos -----
  const manMsg = el("input", { type: "text", maxlength: "200", placeholder: "Motivo para os jogadores (ex.: Manutenção, volto em 10 min)" });
  const manEstado = el("span", { class: "sub" }, "");
  const manLigar = el("button", { type: "button", class: "sec" }, "Ativar manutenção");
  const manDesligar = el("button", { type: "button", class: "sec" }, "Liberar o jogo");
  const derrubar = el("button", { type: "button", class: "sec perigo" }, "Derrubar todos agora");
  const lerManutencao = async () => {
    const { data: a } = await supabase.rpc("estado_acesso");
    const e = a as { manutencao?: boolean; mensagem?: string } | null;
    manEstado.textContent = e?.manutencao ? `🔧 LIGADA: "${e.mensagem}"` : "Jogo liberado para todos.";
    manLigar.textContent = e?.manutencao ? "Atualizar mensagem" : "Ativar manutenção";
    manDesligar.disabled = !e?.manutencao;
    if (e?.manutencao && !manMsg.value) manMsg.value = e.mensagem ?? "";
  };
  manLigar.addEventListener("click", async () => {
    const { error: e } = await supabase.rpc("mestre_manutencao", { p_ativo: true, p_mensagem: manMsg.value });
    if (e) return void dizer(e.message, false);
    dizer("Manutenção ativada: só você consegue jogar. Quem está em batalha termina a luta antes de ver o aviso."); await lerManutencao();
  });
  manDesligar.addEventListener("click", async () => {
    const { error: e } = await supabase.rpc("mestre_manutencao", { p_ativo: false, p_mensagem: "" });
    if (e) return void dizer(e.message, false);
    dizer("Jogo liberado. Os jogadores voltam sozinhos em poucos segundos."); await lerManutencao();
  });
  let armado = false;
  derrubar.addEventListener("click", async () => {
    if (!armado) {
      armado = true; derrubar.textContent = "Confirmar: desconectar todos os jogadores?";
      window.setTimeout(() => { armado = false; derrubar.textContent = "Derrubar todos agora"; }, 5000);
      return;
    }
    armado = false; derrubar.textContent = "Derrubar todos agora";
    const { error: e } = await supabase.rpc("mestre_derrubar_todos");
    if (e) return void dizer(e.message, false);
    dizer("Pronto: todos os jogadores conectados serão desconectados em até 5 segundos (você não).");
  });
  void lerManutencao();
  const painelManut = el("details", { class: "mg-manut" }, el("summary", {}, "🔧 Manutenção e acesso"),
    el("p", { class: "sub" }, "Com a manutenção ligada, só o Mestre consegue entrar e jogar. Quem está em batalha termina a luta. Use “Derrubar todos” para desconectar quem está jogando agora."),
    manEstado, manMsg, el("div", { class: "mg-linha" }, manLigar, manDesligar, derrubar));

  // ---------- popup do jogador (e do Pokémon) ----------
  const BASE = import.meta.env.BASE_URL as string;
  const nomeMapa = (mid: string): string => mapas.find((m) => m.id === mid)?.nome ?? mid;
  let pop: HTMLElement | null = null;
  const fecharPop = (): void => { pop?.remove(); pop = null; };
  new MutationObserver(() => { if (modal.raiz.hidden) fecharPop(); }).observe(modal.raiz, { attributes: true, attributeFilter: ["hidden"] });
  const abrirPop = (...nos: Node[]): void => {
    const x = el("button", { type: "button", class: "mg-pop-x", "aria-label": "Fechar" }, "✕");
    x.addEventListener("click", fecharPop);
    const caixa = el("div", { class: "mg-pop-caixa" }, x, ...nos);
    if (!pop) { pop = el("div", { class: "mg-pop" }); pop.addEventListener("click", (ev) => { if (ev.target === pop) fecharPop(); }); document.body.append(pop); }
    pop.replaceChildren(caixa);
  };

  async function abrirFicha(id: string): Promise<void> {
    const { data, error: e } = await supabase.rpc("mestre_ficha", { p_id: id });
    if (e || !data) { dizer(e?.message ?? "Ficha indisponível.", false); return; }
    const f = data as Ficha;
    const j = f.jogador;
    const msgP = el("p", { class: "msg" });
    const dizP = (t: string, ok = true) => { msgP.textContent = t; msgP.className = `msg ${ok ? "ok" : "erro"}`; };
    const chamarP = async (fn: string, args: Record<string, unknown>): Promise<boolean> => {
      const { error: e2 } = await supabase.rpc(fn, args);
      if (e2) { dizP(e2.message, false); return false; }
      dizP("Salvo.");
      return true;
    };
    const avatar = el("span", { class: "tc-emblema mg-avatar", "aria-hidden": "true" });
    avatar.style.backgroundImage = `url(${BASE}assets/personagens/p${j.aparencia ?? 0}.png)`;
    const cab = el("div", { class: "mg-pop-cab" }, avatar, el("div", { class: "mg-pop-id" },
      el("strong", { class: "dash-nome" }, j.nome),
      el("span", { class: "sub" }, `${f.email ?? "sem e-mail"} · ${j.papel === "mestre" ? "Mestre" : "Jogador"}${j.campeao ? " · 🏆 Campeão da Liga" : ""}`),
      el("span", { class: "sub" }, `${nomeMapa(j.mapa_id)} · ₽ ${j.dinheiro} · PA ${j.pa}`)));
    const tile = (rot: string, val: string | number) => el("div", { class: "dash-tile" }, el("strong", {}, String(val)), el("span", {}, rot));
    const tiles = el("div", { class: "dash-grade mg-tiles" }, tile("Pokémon", f.pokemons.length), tile("Pokédex", `${f.pokedex}/151`), tile("Treinadores vencidos", f.treinadores), tile("Itens na mochila", f.itens.length));

    // insígnias: clique para conceder/retirar (salva na hora)
    const tem = new Set<string>(j.insignias);
    const gradeIns = el("div", { class: "ct-insignias mg-ins" });
    const pintarIns = (): void => {
      gradeIns.replaceChildren(...INSIGNIAS.map((i) => {
        const ok = tem.has(i.slug);
        const b = el("button", { type: "button", class: `ct-ins ${ok ? "ganha" : "falta"}`, title: ok ? `Retirar ${i.nome}` : `Conceder ${i.nome}` },
          el("img", { src: urlInsignia(i.slug), alt: i.nome, class: ok ? "ganha" : "falta", draggable: "false" }), el("span", {}, i.nome), el("small", {}, i.cidade));
        b.addEventListener("click", async () => {
          if (tem.has(i.slug)) tem.delete(i.slug); else tem.add(i.slug);
          pintarIns();
          await chamarP("mestre_editar_jogador", { p_id: id, p_campos: { insignias: [...tem] } });
        });
        return b;
      }));
    };
    pintarIns();

    // dados editáveis
    const nome = el("input", { type: "text", value: j.nome, maxlength: "24" });
    const pa = num(j.pa), din = num(j.dinheiro);
    const papel = el("select", {}, el("option", { value: "jogador" }, "Jogador"), el("option", { value: "mestre" }, "Mestre")); papel.value = j.papel;
    const camp = el("input", { type: "checkbox" }); camp.checked = j.campeao;
    const mapa = el("select", {}, ...mapas.map((m) => el("option", { value: m.id }, `${m.nome} (${m.id})`))); mapa.value = j.mapa_id;
    const mx = num(j.x), my = num(j.y);
    const salvar = el("button", { type: "button" }, "Salvar dados");
    salvar.addEventListener("click", async () => {
      const campos: Record<string, unknown> = { nome: nome.value, pa: Number(pa.value), dinheiro: Number(din.value), papel: papel.value, campeao: camp.checked, insignias: [...tem] };
      if (mapa.value !== j.mapa_id || Number(mx.value) !== j.x || Number(my.value) !== j.y) Object.assign(campos, { mapa_id: mapa.value, x: Number(mx.value), y: Number(my.value) });
      if (await chamarP("mestre_editar_jogador", { p_id: id, p_campos: campos })) { jogadores = ((await supabase.rpc("mestre_jogadores")).data ?? []) as Resumo[]; desenharLista(); await abrirFicha(id); }
    });
    const dados = el("div", { class: "mg-grade" }, campo("Nome", nome), campo("Papel", papel), campo("PA", pa), campo("Dinheiro (₽)", din),
      el("label", { class: "mg-chk" }, camp, "🏆 Campeão da Liga"), campo("Mapa", mapa), campo("X", mx), campo("Y", my));

    // Pokémon: cartões; clicar abre a ficha do Pokémon
    const cartaoPk = (p: Pk): HTMLElement => {
      const hp = barraHp(p.hp_atual, p.hp_max);
      const fill = el("div", { class: `hp-fill ${hp.classe}` }); fill.style.width = `${hp.pct}%`;
      const b = el("button", { type: "button", class: `dash-pk mg-pk-card${p.hp_atual <= 0 ? " caido" : ""}` }, imagemPokemon("frente", p.especie_id, "mini", p.brilhante),
        el("div", { class: "dash-pk-info" }, el("strong", {}, `${p.brilhante ? "✨ " : ""}${p.apelido ?? nomeEsp.get(p.especie_id) ?? `#${p.especie_id}`}`),
          el("span", {}, `Nv ${p.nivel} · ${p.hp_atual}/${p.hp_max} HP`), chipsTipo(p.especie_id), el("div", { class: "hp-trilho" }, fill)));
      b.addEventListener("click", () => abrirPokemon(p));
      return b;
    };
    const time = f.pokemons.filter((p) => p.posicao);
    const caixa = f.pokemons.filter((p) => !p.posicao);

    // mochila e entrega de Pokémon
    const its2 = f.itens.map((i) => {
      const q = num(i.qtd); q.style.width = "80px";
      const s2 = el("button", { type: "button", class: "sec" }, "Definir");
      s2.addEventListener("click", async () => { if (await chamarP("mestre_definir_item", { p_jogador: id, p_item: i.item, p_qtd: Number(q.value) })) await abrirFicha(id); });
      return el("div", { class: "mg-linha" }, el("span", { class: "mg-it" }, itens.find((x) => x.slug === i.item)?.nome ?? i.item), q, s2);
    });
    const nIt = el("select", {}, ...itens.map((x) => el("option", { value: x.slug }, x.nome)));
    const nQ = num(1); nQ.style.width = "80px";
    const add = el("button", { type: "button", class: "sec" }, "Adicionar item");
    add.addEventListener("click", async () => { if (await chamarP("mestre_definir_item", { p_jogador: id, p_item: nIt.value, p_qtd: Number(nQ.value) })) await abrirFicha(id); });
    const dEsp = el("input", { type: "text", list: "mg-esp", placeholder: "nome ou nº da espécie" });
    const dl = el("datalist", { id: "mg-esp" }, ...especies.map((e3) => el("option", { value: e3.nome }, `#${e3.id}`)));
    const dNv = num(5, 1); dNv.max = "100";
    const dBr = el("input", { type: "checkbox" });
    const dar = el("button", { type: "button", class: "sec" }, "Dar Pokémon");
    dar.addEventListener("click", async () => {
      const t = dEsp.value.trim().toLowerCase();
      const ach = especies.find((e3) => e3.nome.toLowerCase() === t || String(e3.id) === t);
      if (!ach) { dizP("Espécie não encontrada.", false); return; }
      if (await chamarP("mestre_dar_pokemon", { p_jogador: id, p_especie: ach.id, p_nivel: Number(dNv.value), p_brilhante: dBr.checked })) await abrirFicha(id);
    });

    function abrirPokemon(p: Pk): void {
      const voltar = el("button", { type: "button", class: "sec mg-pop-voltar" }, `← Voltar a ${j.nome}`);
      voltar.addEventListener("click", () => void abrirFicha(id));
      const ap = el("input", { type: "text", value: p.apelido ?? "", placeholder: nomeEsp.get(p.especie_id) ?? `#${p.especie_id}`, maxlength: "20" });
      const nv = num(p.nivel, 1); nv.max = "1000";
      const br = el("input", { type: "checkbox" }); br.checked = p.brilhante;
      const sv = el("button", { type: "button" }, "Salvar");
      sv.addEventListener("click", async () => { if (await chamarP("mestre_editar_pokemon", { p_id: p.id, p_campos: { apelido: ap.value, nivel: Number(nv.value), brilhante: br.checked } })) await abrirFicha(id); });
      const cu = el("button", { type: "button", class: "sec" }, "Curar");
      cu.addEventListener("click", async () => { if (await chamarP("mestre_editar_pokemon", { p_id: p.id, p_campos: { curar: true } })) await abrirFicha(id); });
      const rm = el("button", { type: "button", class: "perigo" }, "Remover");
      rm.addEventListener("click", async () => { if (!window.confirm(`Remover ${p.apelido ?? nomeEsp.get(p.especie_id)} definitivamente?`)) return; if (await chamarP("mestre_remover_pokemon", { p_id: p.id })) await abrirFicha(id); });
      const st = (r: string, v?: number) => el("div", { class: "mg-st" }, el("b", {}, String(v ?? "—")), el("span", {}, r));
      const gs = (p.golpes ?? []).map((g) => { const gi = golpe(g.id); return el("div", { class: "mg-golpe" }, el("strong", {}, gi.nome), el("small", {}, `${NOME_TIPO[gi.tipo] ?? gi.tipo} · ${gi.categoria === "status" ? "Status" : gi.categoria === "physical" ? "Físico" : "Especial"} · Poder ${gi.poder ?? "—"} · Prec. ${gi.precisao ? `${gi.precisao}%` : "—"} · PP ${g.pp}/${gi.pp}`), el("small", { class: "mg-golpe-desc" }, gi.descricao ?? "")); });
      abrirPop(voltar,
        el("div", { class: "mg-pop-cab" }, imagemPokemon("frente", p.especie_id, "dex-img"), el("div", { class: "mg-pop-id" },
          el("strong", { class: "dash-nome" }, `${p.brilhante ? "✨ " : ""}${p.apelido ?? nomeEsp.get(p.especie_id) ?? `#${p.especie_id}`}`),
          el("span", { class: "sub" }, `${nomeEsp.get(p.especie_id) ?? ""} · Nv ${p.nivel} · ${p.posicao ? `Time #${p.posicao}` : "Caixa"} · ${p.hp_atual}/${p.hp_max} HP`), chipsTipo(p.especie_id),
          el("span", { class: "sub" }, `Natureza ${p.natureza ?? "—"} · XP ${p.exp ?? 0} · Amizade ${p.amizade ?? "—"}${p.evo_pend ? " · ⭐ pontos de evolução pendentes" : ""}`))),
        el("div", { class: "mg-sts" }, st("PV", p.hp_max), st("Ataque", p.atk), st("Defesa", p.def), st("Atq. Esp.", p.spa), st("Def. Esp.", p.spd), st("Veloc.", p.spe)),
        el("label", {}, "Golpes"), el("div", { class: "mg-golpes" }, ...(gs.length ? gs : [el("p", { class: "sub" }, "Sem golpes.")])),
        el("label", {}, "Editar"), el("div", { class: "mg-linha" }, campo("Apelido", ap), campo("Nível", nv), el("label", { class: "mg-chk" }, br, "✨ Brilhante")),
        el("div", { class: "mg-linha" }, sv, cu, rm), msgP);
    }

    abrirPop(cab, tiles,
      el("div", { class: "mg-pop-cols" },
        el("div", {}, el("label", {}, "Dados do personagem"), dados, salvar,
          el("label", {}, `Insígnias (${[...tem].filter((s3) => INSIGNIAS.some((i) => i.slug === s3)).length}/8) — clique para conceder ou retirar`), gradeIns),
        el("div", {}, el("label", {}, `Time ativo (${time.length})`), el("div", { class: "dash-time" }, ...(time.length ? time.map(cartaoPk) : [el("p", { class: "sub" }, "Sem time.")])),
          ...(caixa.length ? [el("label", {}, `Nas caixas (${caixa.length})`), el("div", { class: "dash-time" }, ...caixa.map(cartaoPk))] : []),
          el("label", {}, "Dar Pokémon"), el("div", { class: "mg-linha" }, campo("Espécie", dEsp), dl, campo("Nível", dNv), el("label", { class: "mg-chk" }, dBr, "✨"), dar),
          el("label", {}, "Mochila"), ...its2, el("div", { class: "mg-linha" }, nIt, nQ, add))),
      msgP);
  }

  // ---- reset geral: exige digitar o código aleatório gerado pelo servidor ----
  const resetBotao = el("button", { type: "button", class: "perigo" }, "⚠ Resetar TODOS os jogadores");
  const resetCaixa = el("div", { class: "mg-reset-caixa", hidden: "" });
  resetBotao.addEventListener("click", async () => {
    const { data: cod, error: e } = await supabase.rpc("mestre_reset_codigo");
    if (e || !cod) return void dizer(e?.message ?? "Não foi possível gerar o código.", false);
    const entrada = el("input", { type: "text", maxlength: "6", autocomplete: "off", placeholder: "Digite o código", class: "mg-reset-in" }) as HTMLInputElement;
    const ir = el("button", { type: "button", class: "perigo" }, "Apagar tudo e recomeçar") as HTMLButtonElement;
    const cancelar = el("button", { type: "button", class: "sec" }, "Cancelar");
    ir.disabled = true;
    entrada.addEventListener("input", () => { ir.disabled = entrada.value.trim().toUpperCase() !== String(cod); });
    cancelar.addEventListener("click", () => { resetCaixa.hidden = true; resetCaixa.replaceChildren(); });
    ir.addEventListener("click", async () => {
      ir.disabled = true;
      const { data: n, error: e2 } = await supabase.rpc("mestre_resetar_todos", { p_codigo: entrada.value.trim() });
      if (e2) { dizer(e2.message, false); return; }
      resetCaixa.hidden = true; resetCaixa.replaceChildren();
      dizer(`Reset concluído: ${String(n)} personagem(ns) recomeçaram do zero. A manutenção foi ligada; desligue-a quando quiser reabrir o jogo.`);
      const { data: l } = await supabase.rpc("mestre_jogadores");
      jogadores = (l ?? []) as Resumo[]; desenharLista();
    });
    resetCaixa.replaceChildren(
      el("p", { class: "sub" }, "Isto apaga Pokémon, itens, Pokédex, insígnias, missões e progresso de TODOS os jogadores (menos o Mestre). Ficam só o nome e a aparência de cada personagem, que voltam à cidade inicial. Não dá para desfazer."),
      el("p", {}, "Para confirmar, digite o código: ", el("strong", { class: "mg-reset-cod" }, String(cod))), entrada, el("div", { class: "mg-linha" }, ir, cancelar));
    resetCaixa.hidden = false; entrada.focus();
  });
  const painelReset = el("details", { class: "mg-manut mg-reset" }, el("summary", {}, "⚠ Reiniciar o jogo (zona de perigo)"),
    el("p", { class: "sub" }, "Recomeça todos os jogadores do zero, mantendo só o personagem criado. O Mestre não é afetado."), resetBotao, resetCaixa);

  desenharLista();
  modal.abrir("Gestão do Mestre", painelManut, painelReset, el("div", { class: "mg-wrap mg-solo" }, el("div", { class: "mg-esq" }, el("div", { class: "mg-online" }, contador, filtro), busca, esq), dir), msg);
}
