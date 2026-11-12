// Motor de batalha do RPG: envolve o simulador oficial do Pokémon Showdown (@pkmn/sim). Roda só no servidor (Edge Function).
import { Battle, Dex } from "./sim.js";

const IVS = ["hp", "atk", "def", "spa", "spd", "spe"];
const cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : "Hardy");
const dex9 = Dex.forGen(9);
const POR_NUM = {};
for (const s of dex9.species.all()) if (!s.forme && s.num > 0 && s.num <= 1025) POR_NUM[s.num] = s.name;
export const nomeEspecie = (num) => POR_NUM[num];

function conjunto(m, i) {
  const ivs = {};
  for (const k of IVS) ivs[k] = m.ivs?.[k] ?? 31;
  return {
    name: m.apelido || m.nome, species: m.especie, level: m.nivel, nature: cap(m.natureza),
    ability: "No Ability", item: "", moves: m.golpes.map((g) => g.slug).slice(0, 4), gender: "",
    happiness: 100 + i, // guarda a posição original do Pokémon (a ordem do time muda ao trocar)
    evs: { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }, ivs,
  };
}

function ajustar(lado, time, jogador) {
  lado.pokemon.forEach((p) => {
    const m = time[p.set.happiness - 100];
    if (!m) return;
    p.hp = Math.max(1, Math.min(m.hp, p.maxhp));
    (m.golpes ?? []).slice(0, 4).forEach((g, k) => { if (p.moveSlots[k] && g.pp != null) p.moveSlots[k].pp = Math.min(g.pp, p.moveSlots[k].maxpp); });
    if (!jogador) return;
    // golpe "Splash" escondido: serve para o jogador gastar o turno (bolas e itens)
    p.moveSlots.push({ move: "Splash", id: "splash", pp: 64, maxpp: 64, target: "self", disabled: false, disabledSource: "", used: false });
    p.baseMoveSlots = p.moveSlots.slice();
  });
}

/** time: membros do jogador (só os vivos); inimigos: membros adversários. Membro: {especie, nome, apelido, nivel, natureza, ivs, golpes:[{slug,pp}], hp} */
export function criar({ time, inimigos, seed }) {
  const b = new Battle({ formatid: "gen9customgame@@@!teampreview", seed });
  b.setPlayer("p1", { name: "Jogador", team: time.map(conjunto) });
  ajustar(b.sides[0], time, true);
  b.setPlayer("p2", { name: "Adversário", team: inimigos.map(conjunto) });
  ajustar(b.sides[1], inimigos, false);
  return resultado(b, 0);
}

function visivel(linhas, lado = 0) {
  const out = [];
  for (let i = 0; i < linhas.length; i++) {
    const l = linhas[i];
    if (l.startsWith("|split|")) {
      out.push(l.slice(7) === `p${lado + 1}` ? linhas[i + 1] : linhas[i + 2]);
      i += 2;
      continue;
    }
    out.push(l);
  }
  // quem vê pelo lado 2 enxerga a si mesmo como "p1" (o cliente sempre desenha o próprio time como p1)
  const persp = lado === 1 ? (l) => (l ?? "").replace(/\bp([12])([ab]?)(?=:)/g, (_m, n, ab) => `p${3 - Number(n)}${ab}`) : (l) => l;
  return out.map(persp).filter((l) => l && l !== "|" && !l.startsWith("|t:|") && !/^\|move\|p1a: [^|]*\|Splash\|/.test(l) && !/^\|(upkeep|teamsize|gen|tier|clearpoke|poke|teampreview|rule|raw|gametype|player)\b/.test(l) && !/^\|-nothing/.test(l));
}

function pedido(b, ld = 0) {
  const r = b.sides[ld].activeRequest;
  if (!r || r.wait) return null;
  const ativo = r.active?.[0];
  const lado = b.sides[ld].pokemon;
  return {
    trocar: !!r.forceSwitch,
    golpes: ativo ? ativo.moves.filter((m) => m.id !== "splash").map((m, i) => ({ n: i + 1, id: m.id, nome: m.move, pp: m.pp, maxpp: m.maxpp, desativado: !!m.disabled })) : [],
    preso: !!(ativo && (ativo.trapped || ativo.maybeTrapped)),
    time: lado.map((p, i) => ({ n: i + 1, orig: p.set.happiness - 100, nome: p.name, ativo: p.isActive, hp: p.hp, maxhp: p.maxhp, status: p.status || null })),
  };
}

function resultado(b, desde, ld = 0) {
  const fim = b.ended ? (b.winner === b.sides[ld].name ? "vitoria" : "derrota") : null;
  const dados = (lado) => lado.pokemon.map((p) => ({
    orig: p.set.happiness - 100, hp: p.hp, maxhp: p.maxhp, status: p.status || null,
    pp: p.moveSlots.filter((s) => s.id !== "splash").map((s) => s.pp),
    nome: p.name, nivel: p.level, especie: p.species.name, num: p.species.num, ativo: p.isActive,
  }));
  return {
    estado: b.toJSON(), linhas: visivel(b.log.slice(desde), ld), logLen: b.log.length, pedido: fim ? null : pedido(b, ld), fim,
    jogador: dados(b.sides[ld]), adversario: dados(b.sides[1 - ld]),
  };
}

function escolhaIA(b) {
  const r = b.sides[1].activeRequest;
  if (!r || r.wait) return null;
  if (r.forceSwitch) {
    const i = r.side.pokemon.findIndex((p) => !p.active && !p.condition.endsWith(" fnt"));
    return `switch ${i + 1}`;
  }
  const mv = r.active[0].moves.map((m, i) => ({ m, i })).filter((x) => !x.m.disabled && x.m.pp > 0);
  if (!mv.length) return "move 1";
  return `move ${mv[b.random(mv.length)].i + 1}`;
}

const CURAS = { potion: 20, "super-potion": 50, "hyper-potion": 200, "max-potion": 9999, "full-restore": 9999 };
const STATUS = { antidote: ["psn", "tox"], "burn-heal": ["brn"], "ice-heal": ["frz"], awakening: ["slp"], "paralyze-heal": ["par"], "full-heal": ["psn", "tox", "brn", "frz", "slp", "par"], "full-restore": ["psn", "tox", "brn", "frz", "slp", "par"] };
export const itemDeBatalha = (slug) => slug in CURAS || slug in STATUS;

/** aplica um item num Pokémon do jogador (n = posição atual no time, 1..). Lança erro se não surtir efeito. */
export function usarItem(b, slug, n) {
  const p = b.sides[0].pokemon[n - 1];
  if (!p || p.hp <= 0) throw new Error("Esse Pokémon não pode receber o item agora.");
  let fez = false;
  const cura = CURAS[slug];
  if (cura && p.hp < p.maxhp) { const antes = p.hp; p.hp = Math.min(p.maxhp, p.hp + cura); fez = p.hp - antes; }
  const st = STATUS[slug];
  if (st && p.status && st.includes(p.status)) { p.clearStatus(); fez = fez || true; }
  if (!fez) throw new Error("Não surtiria efeito.");
  return { nome: p.name, curou: typeof fez === "number" ? fez : 0 };
}

/** velocidade e PV dos dois lados, para fuga e captura */
export function dadosBasicos(estado) {
  const b = Battle.fromJSON(JSON.parse(JSON.stringify(estado)));
  const j = b.sides[0].pokemon[0], a = b.sides[1].pokemon[0];
  return { velJ: j.storedStats.spe, velA: a.storedStats.spe, hp: a.hp, maxhp: a.maxhp, status: a.status || null, nomeA: a.name };
}

/** acao: {tipo:'golpe', n} | {tipo:'trocar', n} | {tipo:'passar'}; antes(b) pode alterar a simulação (itens). Troca (n) começa em 1. */
export function passo({ estado, logLen, acao, antes }) {
  const b = Battle.fromJSON(JSON.parse(JSON.stringify(estado)));
  const retorno = antes ? antes(b) : undefined;
  let escolhaJ;
  if (acao.tipo === "golpe") escolhaJ = `move ${acao.n}`;
  else if (acao.tipo === "trocar") escolhaJ = `switch ${acao.n}`;
  else escolhaJ = `move ${b.sides[0].pokemon[0].moveSlots.length}`; // Splash
  const jReq = b.sides[0].activeRequest, iaReq = b.sides[1].activeRequest;
  const aVez1 = !!jReq && !jReq.wait, aVez2 = !!iaReq && !iaReq.wait;
  if (aVez1 && !b.choose("p1", escolhaJ)) throw new Error("Escolha inválida.");
  if (aVez2) b.choose("p2", escolhaIA(b));
  // o adversário caiu e precisa trocar enquanto o jogador só espera: resolve sozinho
  for (let i = 0; i < 6 && !b.ended; i++) {
    const j = b.sides[0].activeRequest, a = b.sides[1].activeRequest;
    if ((j && !j.wait) || !a || a.wait) break;
    b.choose("p2", escolhaIA(b));
  }
  const r = resultado(b, logLen);
  r.retorno = retorno;
  return r;
}

/** devolve o estado atual (pedido, times) sem avançar a simulação */
export function ler(estado, desde = 0, ld = 0) {
  return resultado(Battle.fromJSON(JSON.parse(JSON.stringify(estado))), desde, ld);
}

// ===== duelo entre dois jogadores (os dois lados são humanos; times com HP e PP cheios) =====
/** time1/time2: membros {especie, nome, apelido, nivel, natureza, ivs, hp?, golpes:[{slug, pp?}]} (sem hp/pp = cheio) */
export function criarDuelo({ time1, time2, seed }) {
  const b = new Battle({ formatid: "gen9customgame@@@!teampreview", seed });
  b.setPlayer("p1", { name: "Jogador", team: time1.map(conjunto) });
  ajustar(b.sides[0], time1.map((m) => ({ ...m, hp: m.hp ?? 9999 })), false);
  b.setPlayer("p2", { name: "Adversário", team: time2.map(conjunto) });
  ajustar(b.sides[1], time2.map((m) => ({ ...m, hp: m.hp ?? 9999 })), false);
  return { estado: b.toJSON(), logLen: b.log.length, v: [resultado(b, 0, 0), resultado(b, 0, 1)] };
}

/** quais lados ainda precisam escolher neste momento (0 e/ou 1) */
export function ladosPendentes(estado) {
  const b = Battle.fromJSON(JSON.parse(JSON.stringify(estado)));
  return [0, 1].filter((i) => { const r = b.sides[i].activeRequest; return !!r && !r.wait; });
}

/** testa uma escolha ("move 2", "switch 3") sem alterar nada guardado */
export function escolhaValida(estado, ld, escolha) {
  const b = Battle.fromJSON(JSON.parse(JSON.stringify(estado)));
  const r = b.sides[ld].activeRequest;
  if (!r || r.wait) return false;
  return !!b.choose(`p${ld + 1}`, escolha);
}

/** aplica as escolhas ({0:"move 1", 1:"switch 2"}); lados sem pedido são ignorados. "default" = escolha automática. */
export function passoDuelo({ estado, logLen, escolhas }) {
  const b = Battle.fromJSON(JSON.parse(JSON.stringify(estado)));
  for (const i of [0, 1]) {
    const e = escolhas[i];
    const r = b.sides[i].activeRequest;
    if (!e || !r || r.wait) continue;
    if (!b.choose(`p${i + 1}`, e)) throw new Error("Escolha inválida.");
  }
  return { estado: b.toJSON(), logLen: b.log.length, v: [resultado(b, logLen, 0), resultado(b, logLen, 1)] };
}

/** visão de um lado sem avançar a simulação */
export const verDuelo = (estado, desde, ld) => resultado(Battle.fromJSON(JSON.parse(JSON.stringify(estado))), desde, ld);
