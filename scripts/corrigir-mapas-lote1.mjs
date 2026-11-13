// Correções do lote 1 dos mapas, apontadas pelo linter (node scripts/lint-mapas.mjs).
// Por padrão SÓ SIMULA: mostra o que mudaria. Para gravar de verdade, use --aplicar.
//   node scripts/corrigir-mapas-lote1.mjs                       (simulação de todos os passos)
//   node scripts/corrigir-mapas-lote1.mjs --aplicar             (grava as mudanças)
//   node scripts/corrigir-mapas-lote1.mjs --so azurana-costa1   (só alguns passos; separe por vírgula)
// Passos:
//   azurana-costa1   Abre a saída da clareira de chegada de Azurana (quem vinha da Costa Azul ficava preso).
//   grama-solida     Tira a marca de "grama alta" de tiles sólidos (água/arbustos com grama flutuando por cima).
//   areas-isoladas   Torna sólidas as faixas andáveis que nenhum caminho alcança (nenhum efeito no jogo).
//   viridian         Apaga os 3 arquivos do mapa Viridian, que saiu do jogo na migração m11.
// É idempotente: rodar de novo depois de aplicar não muda mais nada.
import fs from "node:fs";
import path from "node:path";
import { carregarMapas, PASTA_MAPAS } from "./mapas/lib.mjs";
import { lintar } from "./lint-mapas.mjs";

const args = process.argv.slice(2);
const aplicar = args.includes("--aplicar");
const iSo = args.indexOf("--so");
const PASSOS = ["azurana-costa1", "grama-solida", "areas-isoladas", "viridian"];
const escolhidos = iSo >= 0 ? args[iSo + 1].split(",").map((s) => s.trim()) : PASSOS;
for (const e of escolhidos) if (!PASSOS.includes(e)) { console.error(`Passo desconhecido: ${e}. Válidos: ${PASSOS.join(", ")}`); process.exit(2); }

const dados = carregarMapas();
const originais = new Map(); // id -> texto lido do disco (para preservar o formato)
for (const id of dados.mapas.keys()) originais.set(id, fs.readFileSync(path.join(PASTA_MAPAS, `${id}.json`), "utf8"));
const alterados = new Set();
const relato = [];

const trocar = (str, i, c) => str.slice(0, i) + c + str.slice(i + 1);

// ---------- passo 1: saída da clareira de Azurana ----------
if (escolhidos.includes("azurana-costa1")) {
  const m = dados.mapas.get("azurana");
  const p = m?.portais.find((q) => q.dest === "costa1");
  if (!p) relato.push("azurana-costa1: portal para costa1 não encontrado (nada feito).");
  else if (p.x === 0 && p.y === 29 && p.h === 2) relato.push("azurana-costa1: já corrigido.");
  else if (p.x === 0 && p.y === 28 && p.h === 3) {
    // O portal ocupava (0,28)-(0,30). Liberar (0,28) abre a passagem da clareira para o corredor do oeste, que leva à cidade.
    p.y = 29;
    p.h = 2;
    alterados.add("azurana");
    relato.push("azurana-costa1: portal de Azurana para costa1 passou de (0,28) altura 3 para (0,29) altura 2; o tile (0,28) agora é caminho.");
  } else relato.push(`azurana-costa1: portal em formato inesperado (x=${p.x}, y=${p.y}, h=${p.h}); nada feito, confira à mão.`);
}

// ---------- passo 2: grama alta em tile sólido ----------
if (escolhidos.includes("grama-solida")) {
  for (const [id, m] of dados.mapas) {
    let n = 0;
    for (let k = 0; k < m.w * m.h; k++) if (m.grama[k] === "1" && m.solido[k] === "1") { m.grama = trocar(m.grama, k, "0"); n++; }
    if (n) { alterados.add(id); relato.push(`grama-solida: ${id}: ${n} tile(s) deixaram de ser "grama alta".`); }
  }
}

// ---------- passo 3: faixas andáveis que ninguém alcança ----------
if (escolhidos.includes("areas-isoladas")) {
  const { problemas } = lintar(dados);
  for (const pr of problemas.filter((x) => x.codigo === "AREA_ISOLADA")) {
    const m = dados.mapas.get(pr.mapa);
    for (const [x, y] of pr.tiles) {
      const k = y * m.w + x;
      m.solido = trocar(m.solido, k, "1");
      m.grama = trocar(m.grama, k, "0");
    }
    alterados.add(pr.mapa);
    const ys = pr.tiles.map((t) => t[1]);
    relato.push(`areas-isoladas: ${pr.mapa}: ${pr.tiles.length} tiles inalcançáveis (linhas ${Math.min(...ys)}–${Math.max(...ys)}) tornados sólidos.`);
  }
}

// ---------- gravação preservando o formato de cada arquivo ----------
const ascii = (s) => s.replace(/[\u0080-￿]/g, (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"));
// Serializador no estilo json.dumps do Python (", " e ": ", com ou sem escape de não-ASCII).
function dumpsPython(valor, escapar) {
  const esc = (s) => (escapar ? ascii(JSON.stringify(s)) : JSON.stringify(s));
  const rec = (v) => {
    if (Array.isArray(v)) return "[" + v.map(rec).join(", ") + "]";
    if (v && typeof v === "object") return "{" + Object.entries(v).map(([k, x]) => `${esc(k)}: ${rec(x)}`).join(", ") + "}";
    return typeof v === "string" ? esc(v) : JSON.stringify(v);
  };
  return rec(valor);
}
function escolherSerializador(id) {
  const orig = originais.get(id);
  const base = JSON.parse(orig);
  const tentativas = [
    (o) => JSON.stringify(o),
    (o) => ascii(JSON.stringify(o)),
    (o) => dumpsPython(o, false),
    (o) => dumpsPython(o, true),
  ];
  return tentativas.find((f) => f(base) === orig) ?? null;
}

const limpar = (m) => { const o = { ...m }; delete o._arquivo; return o; };
let gravados = 0;
for (const id of alterados) {
  const f = escolherSerializador(id);
  if (!f) { relato.push(`ATENÇÃO: ${id}.json tem um formato que não consegui reproduzir byte a byte; não gravei este arquivo.`); continue; }
  if (aplicar) fs.writeFileSync(path.join(PASTA_MAPAS, `${id}.json`), f(limpar(dados.mapas.get(id))));
  gravados++;
}

// ---------- passo 4: Viridian ----------
if (escolhidos.includes("viridian")) {
  const arquivos = ["viridian.json", "viridian.png", "viridian-cima.png"].map((a) => path.join(PASTA_MAPAS, a)).filter((a) => fs.existsSync(a));
  if (!arquivos.length) relato.push("viridian: já removido.");
  else {
    if (aplicar) for (const a of arquivos) fs.rmSync(a);
    relato.push(`viridian: ${aplicar ? "apagados" : "seriam apagados"} ${arquivos.map((a) => path.basename(a)).join(", ")}.`);
  }
}

console.log(aplicar ? "== APLICADO ==" : "== SIMULAÇÃO (nada foi gravado; use --aplicar para gravar) ==");
for (const l of relato) console.log("• " + l);
console.log(`\nArquivos de mapa ${aplicar ? "gravados" : "que seriam gravados"}: ${gravados}${gravados ? " (" + [...alterados].join(", ") + ")" : ""}`);

if (aplicar) {
  console.log("\nVerificação com o linter:");
  const r = lintar(carregarMapas());
  for (const p of r.problemas) console.log(`  ${p.gravidade} ${p.mapa} ${p.codigo} ${p.msg}`);
  console.log(`  ${r.resumo.erros} erro(s), ${r.resumo.avisos} aviso(s)${r.resumo.ignorados ? `, ${r.resumo.ignorados} ignorado(s) por exceção` : ""}`);
  process.exit(r.resumo.erros ? 1 : 0);
}
