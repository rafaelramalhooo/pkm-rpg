// Mundo vivo: calcula os "pontos de aparição" (NPCs especiais, desafiantes) e os pontos fixos (Fofoqueiro e Mural)
// de cada mapa externo, garantindo que NENHUM ponto bloqueie o caminho entre portais, chegadas e portas.
// Uso: node scripts/mundo-vivo-pontos.mjs [--sql]   (sem --sql só verifica e imprime o resumo)
// Com --sql grava supabase/migrations/20261117410000_m59b_mundo_vivo_pontos.sql
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { carregarMapas, consulta } from "./mapas/lib.mjs";

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SAIDA = path.join(RAIZ, "supabase", "migrations", "20261117410000_m59b_mundo_vivo_pontos.sql");
const CIDADES = ["pallet", "porto", "argila", "verdelume", "azurana", "quartzo", "ambar", "carmesim", "ametista", "obsidiana"];
const ROTAS = ["rota1", "rota2", "rota3", "rota4", "rota5", "rota6", "rota7a", "rota8", "rota9", "rota10", "caminho_va", "costa1", "costa2"];
const LOCAIS = ["gruta", "cromatica", "vale", "reserva", "plato"];
const PERMITIDO = { rota: "GCF", cidade: "PCEG", local: "GCFE" };
const QTD = { rota: 16, cidade: 8, local: 8 };
const MIN = { rota: 8, cidade: 4, local: 3 };
const NOMES_FOFOCA = ["Zeca", "Dona Neide", "Tonico", "Mirela", "Beto", "Cacá", "Lurdes", "Nando", "Dalva", "Juca"];
const VIZ = [[1, 0], [-1, 0], [0, 1], [0, -1]];

const { mapas } = carregarMapas();
const trein = JSON.parse(fs.readFileSync(path.join(RAIZ, "public", "data", "treinadores.json"), "utf8"));
const cheb = (a, b) => Math.max(Math.abs(a[0] - b[0]), Math.abs(a[1] - b[1]));
const hash = (s) => { let h = 2166136261; for (const c of s) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };

function ancoras(id, m) {
  const a = [];
  for (const p of m.portais ?? []) for (let y = p.y; y < p.y + (p.h ?? 1); y++) for (let x = p.x; x < p.x + (p.w ?? 1); x++) a.push([x, y]);
  for (const [oid, o] of mapas) for (const p of o.portais ?? []) if (p.dest === id) a.push([p.dx, p.dy]);
  for (const p of m.pois ?? []) a.push([p.x, p.y]);
  return a;
}

/** Todas as âncoras continuam conectadas entre si com os tiles `bloq` ocupados? (true = ok) */
function conectado(m, solido, anc, bloq) {
  const bl = new Set(bloq.map(([x, y]) => y * m.w + x));
  const livres = anc.filter(([x, y]) => !solido(x, y) && !bl.has(y * m.w + x));
  if (!livres.length) return true;
  const vis = new Set([livres[0][1] * m.w + livres[0][0]]);
  const fila = [livres[0]];
  while (fila.length) {
    const [x, y] = fila.shift();
    for (const [dx, dy] of VIZ) {
      const nx = x + dx, ny = y + dy, k = ny * m.w + nx;
      if (solido(nx, ny) || vis.has(k) || bl.has(k)) continue;
      vis.add(k); fila.push([nx, ny]);
    }
  }
  return livres.every(([x, y]) => vis.has(y * m.w + x));
}

function direcao(solido, x, y) {
  for (const [d, dx, dy] of [["baixo", 0, 1], ["cima", 0, -1], ["esquerda", -1, 0], ["direita", 1, 0]]) if (!solido(x + dx, y + dy)) return d;
  return "baixo";
}

const pontos = []; const fixos = []; const resumo = [];
let falhou = false;
for (const id of [...CIDADES, ...ROTAS, ...LOCAIS]) {
  const m = mapas.get(id);
  if (!m) { console.error(`Mapa ausente: ${id}`); falhou = true; continue; }
  const tipo = CIDADES.includes(id) ? "cidade" : ROTAS.includes(id) ? "rota" : "local";
  const { solido } = consulta(m);
  const anc = ancoras(id, m);
  const proibidos = [...anc, ...trein.filter((t) => t.mapa_id === id).map((t) => [t.x, t.y])];
  const vizinhosLivres = (x, y) => VIZ.filter(([dx, dy]) => !solido(x + dx, y + dy)).length;
  const bioma = (x, y) => m.bioma?.charAt(y * m.w + x) ?? "#";
  const cand = [];
  for (let y = 1; y < m.h - 1; y++) for (let x = 1; x < m.w - 1; x++) {
    if (solido(x, y) || !PERMITIDO[tipo].includes(bioma(x, y))) continue;
    if (proibidos.some((p) => cheb(p, [x, y]) < 2)) continue;
    if (vizinhosLivres(x, y) < 3) continue;
    cand.push([x, y]);
  }
  cand.sort((a, b) => hash(`${id}:${a}`) - hash(`${id}:${b}`));
  const esc = [];
  for (const c of cand) {
    if (esc.length >= QTD[tipo]) break;
    if (esc.some((e) => cheb(e, c) < 3)) continue;
    if (!conectado(m, solido, anc, [...esc, c])) continue;
    esc.push(c);
  }
  if (esc.length < MIN[tipo]) { console.error(`ERRO ${id}: só ${esc.length} pontos (mínimo ${MIN[tipo]})`); falhou = true; }
  if (!conectado(m, solido, anc, esc)) { console.error(`ERRO ${id}: pontos bloqueiam caminho`); falhou = true; }
  for (const [x, y] of esc) pontos.push({ mapa: id, x, y, dir: direcao(solido, x, y), tipo });
  // Fofoqueiro e Mural: perto do Centro Pokémon de cada cidade
  if (tipo === "cidade") {
    const centro = (m.pois ?? []).find((p) => p.tipo === "centro" || p.acao === "cura");
    if (centro) {
      const perto = [];
      for (let y = centro.y - 5; y <= centro.y + 5; y++) for (let x = centro.x - 5; x <= centro.x + 5; x++) {
        if (x < 1 || y < 1 || x >= m.w - 1 || y >= m.h - 1 || solido(x, y)) continue;
        const d = Math.abs(x - centro.x) + Math.abs(y - centro.y);
        if (d < 2 || d > 6) continue;
        if (proibidos.some((p) => cheb(p, [x, y]) < 2) || esc.some((e) => cheb(e, [x, y]) < 2)) continue;
        if (vizinhosLivres(x, y) < 3) continue;
        perto.push([x, y, d]);
      }
      perto.sort((a, b) => a[2] - b[2] || hash(`${id}:f:${a}`) - hash(`${id}:f:${b}`));
      const fixosCidade = [];
      for (const c of perto) {
        if (fixosCidade.length >= 2) break;
        if (fixosCidade.some((e) => cheb(e, c) < 3)) continue;
        if (!conectado(m, solido, anc, [...esc, ...fixosCidade, c])) continue;
        fixosCidade.push(c);
      }
      if (fixosCidade.length < 2) { console.error(`ERRO ${id}: sem lugar para Fofoqueiro e Mural perto do Centro Pokémon`); falhou = true; }
      fixosCidade.forEach(([x, y], i) => fixos.push({ id: `${i === 0 ? "fofoca" : "mural"}_${id}`, mapa: id, x, y, tipo: i === 0 ? "fofoqueiro" : "mural", dir: direcao(solido, x, y), nome: i === 0 ? NOMES_FOFOCA[hash(id) % NOMES_FOFOCA.length] : "Mural" }));
    } else { console.error(`ERRO ${id}: sem Centro Pokémon`); falhou = true; }
  }
  resumo.push(`${id.padEnd(12)} ${tipo.padEnd(7)} pontos=${String(esc.length).padStart(2)}`);
}
console.log(resumo.join("\n"));
console.log(`Total: ${pontos.length} pontos, ${fixos.length} fixos.`);
if (falhou) { console.error("Verificação FALHOU."); process.exit(1); }
if (process.argv.includes("--sql")) {
  const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
  let sql = "-- m59b: pontos de aparição do Mundo vivo (gerado por scripts/mundo-vivo-pontos.mjs; verificado: nenhum ponto bloqueia caminho).\n";
  sql += "-- Idempotente: pode ser executado de novo.\n";
  sql += "insert into public.mv_pontos (mapa_id, x, y, direcao, tipo_mapa) select v.mapa_id, v.x, v.y, v.direcao, v.tipo_mapa from (values\n";
  sql += pontos.map((p) => `  (${q(p.mapa)}, ${p.x}, ${p.y}, ${q(p.dir)}, ${q(p.tipo)})`).join(",\n");
  sql += "\n) as v(mapa_id, x, y, direcao, tipo_mapa) where exists (select 1 from public.mapas m where m.id = v.mapa_id)\non conflict (mapa_id, x, y) do nothing;\n\n";
  sql += "insert into public.mv_fixos (id, mapa_id, x, y, tipo, direcao, nome, aparencia) select v.id, v.mapa_id, v.x, v.y, v.tipo, v.direcao, v.nome, v.aparencia from (values\n";
  sql += fixos.map((f) => `  (${q(f.id)}, ${q(f.mapa)}, ${f.x}, ${f.y}, ${q(f.tipo)}, ${q(f.dir)}, ${q(f.nome)}, ${f.tipo === "mural" ? 0 : 12 + (hash(f.id) % 37)})`).join(",\n");
  sql += "\n) as v(id, mapa_id, x, y, tipo, direcao, nome, aparencia) where exists (select 1 from public.mapas m where m.id = v.mapa_id)\n";
  sql += "on conflict (id) do update set x = excluded.x, y = excluded.y, direcao = excluded.direcao, nome = excluded.nome;\n";
  fs.writeFileSync(SAIDA, sql);
  console.log(`Gravado ${path.relative(RAIZ, SAIDA)}`);
}
