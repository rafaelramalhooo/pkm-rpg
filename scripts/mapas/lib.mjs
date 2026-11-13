// Utilitários compartilhados pelas ferramentas de mapas (linter e prévia).
// Só leitura: nunca altera os mapas. Sem dependências externas.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";

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

/** Decodifica um PNG RGBA/RGB 8 bits sem entrelaçamento. Retorna { w, h, rgba: Uint8Array } ou null. */
export function lerPng(arquivo) {
  const b = fs.readFileSync(arquivo);
  if (b.toString("ascii", 1, 4) !== "PNG") return null;
  let pos = 8, w = 0, h = 0, tipoCor = 0, prof = 0, inter = 0;
  const dados = [];
  while (pos < b.length) {
    const len = b.readUInt32BE(pos);
    const tipo = b.toString("ascii", pos + 4, pos + 8);
    const corpo = b.subarray(pos + 8, pos + 8 + len);
    if (tipo === "IHDR") { w = corpo.readUInt32BE(0); h = corpo.readUInt32BE(4); prof = corpo[8]; tipoCor = corpo[9]; inter = corpo[12]; }
    else if (tipo === "IDAT") dados.push(corpo);
    else if (tipo === "IEND") break;
    pos += 12 + len;
  }
  if (prof !== 8 || inter !== 0 || (tipoCor !== 6 && tipoCor !== 2)) return null;
  const bpp = tipoCor === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(dados));
  const lin = w * bpp;
  const out = new Uint8Array(w * h * 4);
  let prev = new Uint8Array(lin);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (lin + 1)];
    const cur = new Uint8Array(raw.subarray(y * (lin + 1) + 1, (y + 1) * (lin + 1)));
    for (let i = 0; i < lin; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0, up = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      let v = cur[i];
      if (f === 1) v += a; else if (f === 2) v += up; else if (f === 3) v += (a + up) >> 1;
      else if (f === 4) { const pp = a + up - c, pa = Math.abs(pp - a), pb = Math.abs(pp - up), pc = Math.abs(pp - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c; }
      cur[i] = v & 255;
    }
    for (let x = 0; x < w; x++) { const o = (y * w + x) * 4; out[o] = cur[x * bpp]; out[o + 1] = cur[x * bpp + 1]; out[o + 2] = cur[x * bpp + 2]; out[o + 3] = bpp === 4 ? cur[x * bpp + 3] : 255; }
    prev = cur;
  }
  return { w, h, rgba: out };
}
