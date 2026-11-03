// Extração única de dados de Pokémon (Etapa A: Geração 1, dados atuais).
// Fonte principal: PokéAPI. Conferência: pokemondb.net (respeitando robots.txt e >= 4s entre requisições).
// Tudo que é baixado fica em cache local (data/raw, não versionado). O jogo nunca consulta essas fontes.
//
// Uso: node scripts/extract.js
// Variáveis opcionais: EXTRACT_RANGE=1-151 | SKIP_POKEMONDB=1

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const RAW = path.join(ROOT, 'data', 'raw');
const OUT = path.join(ROOT, 'data');

const UA = 'pkm-rpg-personal/1.0 (projeto de fã privado; respostas guardadas em cache local)';
const POKEAPI = 'https://pokeapi.co/api/v2';
const POKEMONDB = 'https://pokemondb.net';
const DELAY_API_MS = 300;
let delayDbMs = 4000; // robots.txt do pokemondb: no máximo 1 requisição a cada 4 s

const [FROM, TO] = (process.env.EXTRACT_RANGE || '1-151').split('-').map(Number);
const SKIP_DB = process.env.SKIP_POKEMONDB === '1';
const ARCO_MAX_ID = 151; // Arco 1 = Geração 1

// Prioridade para escolher a lista de golpes: jogo mais recente em que o Pokémon aparece.
const VERSION_GROUP_PRIORITY = [
  'legends-za', 'scarlet-violet', 'legends-arceus', 'brilliant-diamond-and-shining-pearl',
  'sword-shield', 'lets-go-pikachu-lets-go-eevee', 'ultra-sun-ultra-moon', 'sun-moon',
  'omega-ruby-alpha-sapphire', 'x-y', 'black-2-white-2', 'black-white',
  'heartgold-soulsilver', 'platinum', 'diamond-pearl', 'firered-leafgreen',
  'emerald', 'ruby-sapphire', 'crystal', 'gold-silver', 'yellow', 'red-blue',
];

const ITEMS_ARCO_1 = [
  'poke-ball', 'great-ball', 'ultra-ball', 'potion', 'super-potion', 'hyper-potion', 'max-potion',
  'full-restore', 'revive', 'max-revive', 'antidote', 'burn-heal', 'ice-heal', 'awakening',
  'paralyze-heal', 'full-heal', 'repel', 'super-repel', 'max-repel', 'escape-rope',
  'fire-stone', 'water-stone', 'thunder-stone', 'leaf-stone', 'moon-stone',
];

const STAT_KEYS = { hp: 'hp', attack: 'attack', defense: 'defense', 'special-attack': 'sp_attack', 'special-defense': 'sp_defense', speed: 'speed' };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const lastAt = {};
async function throttle(host, ms) {
  const wait = (lastAt[host] || 0) + ms - Date.now();
  if (wait > 0) await sleep(wait);
  lastAt[host] = Date.now();
}

async function cached(url, { host, delay, type = 'json', retries = 3 }) {
  const key = createHash('sha1').update(url).digest('hex');
  const dir = path.join(RAW, host);
  const file = path.join(dir, key + (type === 'json' ? '.json' : '.html'));
  try {
    const txt = await readFile(file, 'utf8');
    return type === 'json' ? JSON.parse(txt) : txt;
  } catch { /* sem cache: baixar */ }
  await mkdir(dir, { recursive: true });
  for (let attempt = 1; attempt <= retries; attempt++) {
    await throttle(host, delay);
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: type === 'json' ? 'application/json' : 'text/html,text/plain' } });
      if (res.status === 429 || res.status >= 500) { await sleep(5000 * attempt); continue; }
      if (!res.ok) { const e = new Error(`HTTP ${res.status} em ${url}`); e.noRetry = true; throw e; }
      const txt = await res.text();
      await writeFile(file, txt);
      return type === 'json' ? JSON.parse(txt) : txt;
    } catch (err) {
      if (err.noRetry || attempt === retries) throw err;
      await sleep(2000 * attempt);
    }
  }
  throw new Error(`Falha ao baixar ${url}`);
}

const api = (p) => cached(p.startsWith('http') ? p : POKEAPI + p, { host: 'pokeapi', delay: DELAY_API_MS });
const enText = (arr, key) => arr?.find((e) => e.language?.name === 'en')?.[key] ?? null;
const clean = (obj) => Object.fromEntries(Object.entries(obj).filter(([, v]) => v !== null && v !== false && v !== '' && v !== undefined));

// ---------- robots.txt do pokemondb ----------
let robotsDisallow = [];
async function loadRobots() {
  try {
    const txt = await cached(POKEMONDB + '/robots.txt', { host: 'pokemondb', delay: delayDbMs, type: 'text' });
    let applies = false;
    for (const raw of txt.split(/\r?\n/)) {
      const line = raw.split('#')[0].trim();
      if (!line) continue;
      const [k, ...rest] = line.split(':');
      const v = rest.join(':').trim();
      const key = k.toLowerCase();
      if (key === 'user-agent') applies = v === '*';
      else if (applies && key === 'disallow' && v) robotsDisallow.push(v);
      else if (applies && key === 'crawl-delay') delayDbMs = Math.max(delayDbMs, Number(v) * 1000 || 0);
    }
  } catch (err) {
    console.warn('Aviso: não foi possível ler o robots.txt do pokemondb:', err.message);
  }
}
const dbAllowed = (p) => !robotsDisallow.some((d) => p.startsWith(d));

// ---------- conferência com pokemondb (não fatal) ----------
function parseDbStats(html) {
  const re = /<th>\s*(HP|Attack|Defense|Sp\. Atk|Sp\. Def|Speed)\s*<\/th>\s*<td[^>]*>\s*(\d+)\s*<\/td>/g;
  const map = { HP: 'hp', Attack: 'attack', Defense: 'defense', 'Sp. Atk': 'sp_attack', 'Sp. Def': 'sp_defense', Speed: 'speed' };
  const out = {};
  let m;
  while ((m = re.exec(html)) && Object.keys(out).length < 6) {
    if (!(map[m[1]] in out)) out[map[m[1]]] = Number(m[2]);
  }
  return out;
}

// ---------- evoluções ----------
function findNode(node, name) {
  if (node.species.name === name) return node;
  for (const next of node.evolves_to) { const f = findNode(next, name); if (f) return f; }
  return null;
}
const evoDetail = (d) => clean({
  trigger: d.trigger?.name, min_level: d.min_level, item: d.item?.name, held_item: d.held_item?.name,
  known_move: d.known_move?.name, min_happiness: d.min_happiness, time_of_day: d.time_of_day,
  location: d.location?.name, needs_overworld_rain: d.needs_overworld_rain, gender: d.gender,
  relative_physical_stats: d.relative_physical_stats, trade_species: d.trade_species?.name,
});

// ---------- learnset ----------
function buildLearnset(pokemon) {
  const byGroup = {};
  for (const mv of pokemon.moves) {
    for (const d of mv.version_group_details) {
      (byGroup[d.version_group.name] ??= []).push({ move: mv.move.name, method: d.move_learn_method.name, level: d.level_learned_at });
    }
  }
  const chosen = VERSION_GROUP_PRIORITY.find((g) => byGroup[g]?.some((e) => e.method === 'level-up'))
    ?? VERSION_GROUP_PRIORITY.find((g) => byGroup[g]);
  if (!chosen) return { version_group: null, level_up: [], machine: [], other: [] };
  const entries = byGroup[chosen];
  return {
    version_group: chosen,
    level_up: entries.filter((e) => e.method === 'level-up').sort((a, b) => a.level - b.level || a.move.localeCompare(b.move)).map(({ move, level }) => ({ move, level })),
    machine: [...new Set(entries.filter((e) => e.method === 'machine').map((e) => e.move))].sort(),
    other: entries.filter((e) => !['level-up', 'machine'].includes(e.method)).map(({ move, method }) => ({ move, method })),
  };
}

async function main() {
  const started = Date.now();
  const report = { range: [FROM, TO], pokemon: 0, moves: 0, divergences: [], failures: [], version_groups: {} };
  await mkdir(OUT, { recursive: true });
  if (!SKIP_DB) await loadRobots();

  const pokemonOut = [];
  const learnsets = {};
  const encountersOut = {};
  const moveNames = new Set();
  const chainCache = new Map();

  for (let id = FROM; id <= TO; id++) {
    try {
      const [p, s] = await Promise.all([api(`/pokemon/${id}`), api(`/pokemon-species/${id}`)]);
      const chain = chainCache.get(s.evolution_chain.url) ?? (await api(s.evolution_chain.url));
      chainCache.set(s.evolution_chain.url, chain);
      const node = findNode(chain.chain, s.name);

      const stats = {};
      for (const st of p.stats) stats[STAT_KEYS[st.stat.name]] = st.base_stat;

      pokemonOut.push({
        id, name: p.name, display_name: enText(s.names, 'name') ?? p.name,
        types: [...p.types].sort((a, b) => a.slot - b.slot).map((t) => t.type.name),
        base_stats: stats,
        abilities: p.abilities.map((a) => ({ name: a.ability.name, hidden: a.is_hidden })),
        height_dm: p.height, weight_hg: p.weight,
        capture_rate: s.capture_rate, base_experience: p.base_experience,
        growth_rate: s.growth_rate.name, gender_rate: s.gender_rate, base_happiness: s.base_happiness,
        egg_groups: s.egg_groups.map((g) => g.name),
        is_legendary: s.is_legendary, is_mythical: s.is_mythical,
        evolves_from: s.evolves_from_species?.name ?? null,
        evolves_to: (node?.evolves_to ?? []).map((n) => ({ species: n.species.name, details: n.evolution_details.map(evoDetail) })),
        arco_liberacao: id <= ARCO_MAX_ID ? 1 : null,
      });

      const ls = buildLearnset(p);
      learnsets[p.name] = ls;
      report.version_groups[ls.version_group] = (report.version_groups[ls.version_group] ?? 0) + 1;
      for (const e of [...ls.level_up, ...ls.other]) moveNames.add(e.move);
      for (const m of ls.machine) moveNames.add(m);

      const enc = await api(`/pokemon/${id}/encounters`);
      encountersOut[p.name] = enc.flatMap((a) => a.version_details
        .filter((v) => ['red', 'blue', 'yellow'].includes(v.version.name))
        .flatMap((v) => v.encounter_details.map((d) => ({
          area: a.location_area.name, version: v.version.name, method: d.method.name,
          min_level: d.min_level, max_level: d.max_level, chance: d.chance,
        }))));

      if (!SKIP_DB && dbAllowed(`/pokedex/${p.name}`)) {
        try {
          const html = await cached(`${POKEMONDB}/pokedex/${p.name}`, { host: 'pokemondb', delay: delayDbMs, type: 'text' });
          const dbStats = parseDbStats(html);
          const diffs = Object.entries(stats).filter(([k, v]) => dbStats[k] !== undefined && dbStats[k] !== v).map(([k, v]) => ({ stat: k, pokeapi: v, pokemondb: dbStats[k] }));
          if (Object.keys(dbStats).length < 6) report.failures.push({ id, name: p.name, source: 'pokemondb', error: 'atributos não reconhecidos na página' });
          if (diffs.length) report.divergences.push({ id, name: p.name, diffs });
        } catch (err) {
          report.failures.push({ id, name: p.name, source: 'pokemondb', error: err.message });
        }
      }
      report.pokemon++;
      if (id % 10 === 0 || id === TO) console.log(`Pokémon ${id}/${TO}`);
    } catch (err) {
      report.failures.push({ id, source: 'pokeapi', error: err.message });
      console.warn(`Falha no Pokémon ${id}: ${err.message}`);
    }
  }

  // Golpes usados nas listas
  const movesOut = [];
  for (const name of [...moveNames].sort()) {
    try {
      const m = await api(`/move/${name}`);
      const chance = m.effect_chance;
      const short = enText(m.effect_entries, 'short_effect');
      movesOut.push({
        id: m.id, name: m.name, type: m.type.name, category: m.damage_class.name,
        power: m.power, accuracy: m.accuracy, pp: m.pp, priority: m.priority, target: m.target.name,
        effect_chance: chance, ailment: m.meta?.ailment?.name ?? null,
        short_effect: short ? short.replace(/\$effect_chance/g, String(chance ?? '')) : null,
        arco_liberacao: 1,
      });
    } catch (err) { report.failures.push({ move: name, source: 'pokeapi', error: err.message }); }
  }
  report.moves = movesOut.length;

  // Tipos (matriz de eficácia)
  const typeList = (await api('/type?limit=100')).results.map((t) => t.name).filter((n) => !['unknown', 'shadow', 'stellar'].includes(n));
  const typeInfos = [];
  for (const n of typeList) typeInfos.push(await api(`/type/${n}`));
  const chart = {};
  for (const t of typeInfos) {
    chart[t.name] = Object.fromEntries(typeList.map((d) => [d, 1]));
    for (const x of t.damage_relations.double_damage_to) if (x.name in chart[t.name]) chart[t.name][x.name] = 2;
    for (const x of t.damage_relations.half_damage_to) if (x.name in chart[t.name]) chart[t.name][x.name] = 0.5;
    for (const x of t.damage_relations.no_damage_to) if (x.name in chart[t.name]) chart[t.name][x.name] = 0;
  }

  // Naturezas
  const natures = [];
  for (const n of (await api('/nature?limit=100')).results) {
    const d = await api(n.url);
    natures.push({ name: d.name, increased: d.increased_stat?.name ?? null, decreased: d.decreased_stat?.name ?? null });
  }

  // Itens do Arco 1
  const items = [];
  for (const name of ITEMS_ARCO_1) {
    try {
      const i = await api(`/item/${name}`);
      items.push({ id: i.id, name: i.name, cost: i.cost, category: i.category.name, short_effect: enText(i.effect_entries, 'short_effect'), arco_liberacao: 1 });
    } catch (err) { report.failures.push({ item: name, source: 'pokeapi', error: err.message }); }
  }

  const write = (f, data) => writeFile(path.join(OUT, f), JSON.stringify(data, null, 2) + '\n');
  await write('pokemon.json', pokemonOut);
  await write('moves.json', movesOut);
  await write('learnsets.json', learnsets);
  await write('types.json', chart);
  await write('natures.json', natures);
  await write('items.json', items);
  await write('encounters.json', encountersOut);
  report.duration_min = Math.round((Date.now() - started) / 600) / 100;
  report.generated_at = new Date().toISOString();
  report.sources = ['pokeapi.co', SKIP_DB ? null : 'pokemondb.net (conferência)'].filter(Boolean);
  await write('extraction-report.json', report);

  console.log(`Concluído: ${report.pokemon} Pokémon, ${report.moves} golpes, ${report.divergences.length} divergências, ${report.failures.length} falhas.`);
  if (report.failures.some((f) => f.source === 'pokeapi')) process.exitCode = 1;
}

main().catch((err) => { console.error(err); process.exit(1); });
