// Edge Function "batalha": árbitro de todas as batalhas. Usa o simulador oficial do Pokémon Showdown (engine.js).
// O navegador só envia a intenção do jogador; regras, dano, captura, itens e experiência são decididos aqui.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { criar, passo, ler, usarItem, itemDeBatalha, nomeEspecie, dadosBasicos } from "https://rafaelramalhooo.github.io/pkm-rpg/sim/engine.js";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (corpo: unknown, status = 200) => new Response(JSON.stringify(corpo), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

const BOLAS: Record<string, number> = { "poke-ball": 1, "great-ball": 1.5, "ultra-ball": 2, "master-ball": 255 };
const sorteio = (n: number) => Math.floor(Math.random() * n);

// deno-lint-ignore no-explicit-any
type Any = any;

async function montar(b: Any, uid: string) {
  const { data: pks } = await admin.from("pokemons").select("*").eq("dono", uid).not("posicao", "is", null).gt("hp_atual", 0).order("posicao");
  if (!pks?.length) throw new Error("Você não tem Pokémon aptos a lutar.");
  const lista = [...pks].sort((x: Any, y: Any) => (x.id === b.ativo ? -1 : y.id === b.ativo ? 1 : x.posicao - y.posicao));
  const adv: Any[] = b.tipo === "treinador" ? b.adversarios : [b.selvagem];
  let nomeTreinador: string | undefined;
  if (b.tipo === "treinador" && b.treinador) {
    const { data: t } = await admin.from("treinadores").select("nome,classe").eq("id", b.treinador).single();
    if (t) nomeTreinador = `${t.classe} ${t.nome}`;
  }
  const ids = new Set<number>();
  lista.forEach((p: Any) => p.golpes.forEach((g: Any) => ids.add(g.id)));
  adv.forEach((a: Any) => a.golpes.forEach((g: Any) => ids.add(g.id)));
  const { data: gs } = await admin.from("golpes").select("id,slug,nome").in("id", [...ids]);
  const slug = new Map((gs ?? []).map((g: Any) => [g.id, g.slug]));
  const { data: es } = await admin.from("especies").select("id,nome").in("id", [...new Set([...lista.map((p: Any) => p.especie_id), ...adv.map((a: Any) => a.especie_id)])]);
  const nome = new Map((es ?? []).map((e: Any) => [e.id, e.nome]));
  const ivs = (p: Any) => ({ hp: p.iv_hp, atk: p.iv_atk, def: p.iv_def, spa: p.iv_spa, spd: p.iv_spd, spe: p.iv_spe });
  const time = lista.map((p: Any) => ({
    especie: nomeEspecie(p.especie_id), nome: nome.get(p.especie_id), apelido: p.apelido, nivel: p.nivel, natureza: p.natureza,
    ivs: ivs(p), hp: p.hp_atual, golpes: p.golpes.map((g: Any) => ({ slug: slug.get(g.id), pp: g.pp })),
  }));
  const inimigos = adv.map((a: Any) => ({
    especie: nomeEspecie(a.especie_id), nome: a.nome, nivel: a.nivel, natureza: a.natureza ?? "hardy",
    ivs: a.ivs ?? { hp: sorteio(32), atk: sorteio(32), def: sorteio(32), spa: sorteio(32), spd: sorteio(32), spe: sorteio(32) },
    hp: 9999, golpes: a.golpes.map((g: Any) => ({ slug: slug.get(g.id), pp: g.pp })),
  }));
  const seed = [sorteio(65536), sorteio(65536), sorteio(65536), sorteio(65536)];
  const r = criar({ time, inimigos, seed });
  const meta = {
    time: lista.map((p: Any) => p.id), participantes: [lista[0].id], fuga: 0, ativo: lista[0].id, treinador: nomeTreinador,
    inimigos: adv.map((a: Any) => ({ exp_base: a.exp_base, nivel: a.nivel, especie_id: a.especie_id, golpes: a.golpes, caiu: false })),
  };
  return { r, meta };
}

const timeDe = (r: Any, meta: Any) => r.jogador.map((p: Any) => ({ id: meta.time[p.orig], hp: p.hp, pp: p.pp }));

async function gastarItem(uid: string, item: string) {
  const { error } = await admin.rpc("sim_gastar_item", { p_jogador: uid, p_item: item });
  if (error) throw new Error(error.message);
}

function formatar(b: Any, meta: Any, r: Any, antes: Any[], depois: Any[]) {
  return {
    batalha: { id: b.id, estado: b.estado, tipo: b.tipo, turno: b.turno },
    antes, linhas: r.linhas, depois, pedido: r.pedido, fim: r.fim,
    treinador: meta.treinador,
    jogador: r.jogador.map((p: Any) => ({ ...p, id: meta.time[p.orig] })),
    adversario: r.adversario,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: u } = await admin.auth.getUser(token);
    const uid = u?.user?.id;
    if (!uid) return resp({ erro: "Faça login primeiro." }, 401);
    const { acao, n, item } = await req.json();

    const { data: b } = await admin.from("batalhas").select("*").eq("jogador", uid).eq("estado", "ativa").maybeSingle();
    if (!b) return resp({ erro: "Você não está em batalha." }, 409);

    let estado: Any = b.sim, meta: Any = b.meta, logLen: number = b.log_len;
    const antes: Any[] = [];

    if (!estado) {
      const m = await montar(b, uid);
      estado = m.r.estado; meta = m.meta; logLen = m.r.logLen;
      const { error } = await admin.rpc("sim_gravar", { p_batalha: b.id, p_turno: b.turno, p_sim: estado, p_meta: meta, p_log_len: logLen, p_time: timeDe(m.r, meta), p_fim: null });
      if (error) throw new Error(error.message);
      b.turno += 1;
      if (!acao || acao === "estado") return resp(formatar(b, meta, m.r, [], []));
    } else if (!acao || acao === "estado") {
      return resp(formatar(b, meta, ler(estado, logLen), [], []));
    }

    const atual = ler(estado, logLen);
    const pedido = atual.pedido;
    if (!pedido) throw new Error("Aguarde.");
    let tipoPasso: Any;
    let antesFn: Any;
    let gastou: string | null = null;

    if (acao === "golpe") {
      if (pedido.trocar) throw new Error("Escolha o próximo Pokémon.");
      const g = pedido.golpes.find((x: Any) => x.n === n);
      if (!g || g.desativado || g.pp <= 0) throw new Error("Golpe indisponível.");
      tipoPasso = { tipo: "golpe", n };
    } else if (acao === "trocar") {
      const t = pedido.time.find((x: Any) => x.n === n);
      if (!t || t.hp <= 0 || (t.ativo && !pedido.trocar)) throw new Error("Troca inválida.");
      if (pedido.preso && !pedido.trocar) throw new Error("Seu Pokémon está preso e não pode sair!");
      tipoPasso = { tipo: "trocar", n };
    } else if (acao === "bola") {
      if (pedido.trocar) throw new Error("Escolha o próximo Pokémon.");
      if (b.tipo !== "selvagem") throw new Error("Não dá para capturar Pokémon de treinadores.");
      const mult = BOLAS[item];
      if (!mult) throw new Error("Bola desconhecida.");
      const d = dadosBasicos(estado);
      await gastarItem(uid, item);
      const sel = meta.inimigos[0];
      const { data: esp } = await admin.from("especies").select("taxa_captura").eq("id", sel.especie_id).single();
      const bonus = d.status === "slp" || d.status === "frz" ? 2 : d.status ? 1.5 : 1;
      const a = Math.max(1, Math.floor(((3 * d.maxhp - 2 * d.hp) * (esp?.taxa_captura ?? 45) * mult * bonus) / (3 * d.maxhp)));
      const bb = a >= 255 ? 65536 : 1048560 / Math.sqrt(Math.sqrt(16711680 / a));
      let balancos = 0;
      for (let i = 0; i < 4; i++) { if (bb >= 65536 || sorteio(65536) < bb) balancos++; else break; }
      const ok = balancos >= 4;
      antes.push({ t: "bola", bola: item, balancos: ok ? 3 : balancos, capturado: ok, nome: d.nomeA });
      if (ok) {
        const { data: cap, error } = await admin.rpc("sim_capturar", {
          p_batalha: b.id, p_turno: b.turno, p_sim: estado, p_meta: meta, p_log_len: logLen, p_time: timeDe(atual, meta),
          p_especie: sel.especie_id, p_nivel: sel.nivel, p_golpes: sel.golpes.map((g: Any) => ({ id: g.id, pp: g.pp })),
        });
        if (error) throw new Error(error.message);
        b.estado = "captura";
        return resp(formatar(b, meta, { ...atual, fim: "captura", pedido: null, linhas: [] }, antes, [{ t: "capturado", nome: cap.nome, time: cap.time }]));
      }
      tipoPasso = { tipo: "passar" };
    } else if (acao === "item") {
      if (pedido.trocar) throw new Error("Escolha o próximo Pokémon.");
      if (!itemDeBatalha(item)) throw new Error("Esse item não pode ser usado em batalha.");
      if (!pedido.time.find((x: Any) => x.n === n)) throw new Error("Alvo inválido.");
      tipoPasso = { tipo: "passar" };
      gastou = item;
      antesFn = (bt: Any) => usarItem(bt, item, n);
      passo({ estado, logLen, acao: tipoPasso, antes: antesFn }); // ensaio: lança erro se não surtir efeito
      await gastarItem(uid, item);
    } else if (acao === "fugir") {
      if (pedido.trocar) throw new Error("Escolha o próximo Pokémon.");
      if (b.tipo !== "selvagem") throw new Error("Não dá para fugir de um treinador!");
      const d = dadosBasicos(estado);
      meta.fuga = (meta.fuga ?? 0) + 1;
      const f = Math.floor((d.velJ * 128) / Math.max(1, d.velA)) + 30 * meta.fuga;
      if (f > 255 || sorteio(256) < f) {
        const { error } = await admin.rpc("sim_gravar", { p_batalha: b.id, p_turno: b.turno, p_sim: estado, p_meta: meta, p_log_len: logLen, p_time: timeDe(atual, meta), p_fim: "fuga" });
        if (error) throw new Error(error.message);
        b.estado = "fuga";
        return resp(formatar(b, meta, { ...atual, fim: "fuga", pedido: null, linhas: [] }, [{ t: "fuga", ok: true }], []));
      }
      antes.push({ t: "fuga", ok: false });
      tipoPasso = { tipo: "passar" };
    } else throw new Error("Ação desconhecida.");

    const r = passo({ estado, logLen, acao: tipoPasso, antes: antesFn });
    if (r.retorno) antes.push({ t: "item", item: gastou, nome: r.retorno.nome, curou: r.retorno.curou });

    const ia = r.jogador.findIndex((p: Any) => p.ativo);
    if (ia >= 0) {
      const id = meta.time[r.jogador[ia].orig];
      if (id && !meta.participantes.includes(id)) meta.participantes.push(id);
      meta.ativo = id;
    }
    meta.exp_pendente = meta.exp_pendente ?? [];
    r.adversario.forEach((p: Any) => {
      const m = meta.inimigos[p.orig];
      if (p.hp <= 0 && m && !m.caiu) { m.caiu = true; meta.exp_pendente.push({ exp_base: m.exp_base, nivel: m.nivel }); }
    });
    const { data: ev, error } = await admin.rpc("sim_gravar", {
      p_batalha: b.id, p_turno: b.turno, p_sim: r.estado, p_meta: meta, p_log_len: r.logLen, p_time: timeDe(r, meta),
      p_fim: r.fim, p_exp: r.fim === "vitoria" ? meta.exp_pendente : [],
    });
    if (error) throw new Error(error.message);
    b.estado = r.fim ?? "ativa";
    b.turno += 1;
    return resp(formatar(b, meta, r, antes, ev ?? []));
  } catch (e) {
    return resp({ erro: (e as Error).message }, 400);
  }
});
