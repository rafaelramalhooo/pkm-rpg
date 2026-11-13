// Utilitários compartilhados pelas ferramentas de mapas (linter e prévia).
// Só leitura: nunca altera os mapas. Sem dependências externas.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const T = 16; // tamanho do tile em pixels
const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
export const PASTA_MAPAS = path.join(RAIZ, "public", "assets", "mapas");

/** Lê largura e altura de um PNG pelo cabeçalho (IHDR), sem decodificar a imagem. */
export function dimensoesPng(arquivo) {
  const fd = fs.openSync(arquivo, "r");
  try {
    const b = Buffer.alloc(24);
    fs.readSync(fd, b, 0, 24, 0);
    if (b.toString("ascii", 1, 4) !== "PNG") return null;
    return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
  } finally {
    fs.closeSync(fd);
  }
}

/**
 * Carrega o índice e todos os mapas.
 * Retorna { ids, mapas: Map(id -> mapa), orfaos: [ids com .json fora do índice], faltando: [ids do índice sem .json] }.
 * Cada mapa recebe `_arquivo` (nome do arquivo) para checar se o `id` bate.
 */
export function carregarMapas(pasta = PASTA_MAPAS) {
  const ids = JSON.parse(fs.readFileSync(path.join(pasta, "_indice.json"), "utf8"));
  const mapas = new Map();
  const faltando = [];
  for (const id of ids) {
    const arq = path.join(pasta, `${id}.json`);
    if (!fs.existsSync(arq)) {
      faltando.push(id);
      continue;
    }
    const m = JSON.parse(fs.readFileSync(arq, "utf8"));
    m._arquivo = id;
    mapas.set(id, m);
  }
  const orfaos = fs
    .readdirSync(pasta)
    .filter((f) => f.endsWith(".json") && f !== "_indice.json")
    .map((f) => f.slice(0, -5))
    .filter((id) => !ids.includes(id));
  return { ids, mapas, orfaos, faltando, pasta };
}

/** Funções de consulta sobre um mapa (as mesmas regras do motor em src/game/mundo.ts). */
export function consulta(m) {
  const solido = (x, y) => x < 0 || y < 0 || x >= m.w || y >= m.h || m.solido.charAt(y * m.w + x) === "1";
  const grama = (x, y) => m.grama.charAt(y * m.w + x) === "1";
  const retangulo = (p) => {
    const t = [];
    for (let y = p.y; y < p.y + (p.h ?? 1); y++) for (let x = p.x; x < p.x + (p.w ?? 1); x++) t.push([x, y]);
    return t;
  };
  return { solido, grama, retangulo };
}
