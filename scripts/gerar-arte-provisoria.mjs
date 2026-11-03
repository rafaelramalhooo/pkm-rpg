// Gera a ARTE PROVISÓRIA (100% original, desenhada por código) e o mapa de Pallet em formato Tiled.
// Saídas: public/assets/tiles.png, public/assets/personagens.png, public/assets/mapas/pallet.json
// Uso: node scripts/gerar-arte-provisoria.mjs [--preview]   (preview grava em .preview/, não versionado)
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const T = 16;
const SAIDA = "public/assets";

// ---------- PNG mínimo ----------
const tabelaCrc = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = tabelaCrc[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function bloco(tipo, dados) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(dados.length);
  const corpo = Buffer.concat([Buffer.from(tipo, "ascii"), dados]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(corpo));
  return Buffer.concat([len, corpo, crc]);
}
function codificarPng(img) {
  const { w, h, d } = img;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    d.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // profundidade
  ihdr[9] = 6; // RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    bloco("IHDR", ihdr),
    bloco("IDAT", zlib.deflateSync(raw, { level: 9 })),
    bloco("IEND", Buffer.alloc(0)),
  ]);
}

// ---------- Imagem RGBA ----------
class Img {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    this.d = Buffer.alloc(w * h * 4);
  }
  set(x, y, hex, a = 255) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const i = (y * this.w + x) * 4;
    this.d[i] = parseInt(hex.slice(1, 3), 16);
    this.d[i + 1] = parseInt(hex.slice(3, 5), 16);
    this.d[i + 2] = parseInt(hex.slice(5, 7), 16);
    this.d[i + 3] = a;
  }
  alfa(x, y) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return 0;
    return this.d[(y * this.w + x) * 4 + 3];
  }
  rect(x, y, w, h, hex, a = 255) {
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.set(x + i, y + j, hex, a);
  }
}

function ruido(x, y, s) {
  let n = Math.imul(x, 374761393) + Math.imul(y, 668265263) + Math.imul(s, 1442695041);
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}

// ---------- Tiles (16x16), gids 1..11 ----------
function grama(p) {
  for (let y = 0; y < T; y++)
    for (let x = 0; x < T; x++) {
      const r = ruido(x, y, 1);
      p.set(x, y, r < 0.12 ? "#4a8c34" : r < 0.18 ? "#7cc04c" : "#5aa03c");
    }
}
const TILES = [
  /* 1 grama */ (p) => grama(p),
  /* 2 caminho */ (p) => {
    for (let y = 0; y < T; y++)
      for (let x = 0; x < T; x++) {
        const r = ruido(x, y, 2);
        p.set(x, y, r < 0.1 ? "#c4a874" : r < 0.17 ? "#e8d8b0" : "#d8c090");
      }
  },
  /* 3 árvore */ (p) => {
    grama(p);
    p.rect(7, 11, 2, 4, "#6b4423");
    for (let y = 0; y < 13; y++)
      for (let x = 0; x < T; x++) {
        const e = ((x - 7.5) ** 2) / 36 + ((y - 6.5) ** 2) / 31;
        if (e > 1) continue;
        if (e > 0.78) p.set(x, y, "#1c4a1a");
        else p.set(x, y, x + y < 12 ? "#4c9a3c" : x + y > 17 ? "#245c22" : "#2f7a2c");
      }
  },
  /* 4 água */ (p) => {
    for (let y = 0; y < T; y++)
      for (let x = 0; x < T; x++) {
        const onda = (x + (y >> 1) * 3) % 8 === 0 && y % 4 === 1;
        p.set(x, y, onda ? "#7ab4f0" : ruido(x, y, 4) < 0.08 ? "#356fbc" : "#3f7fd0");
      }
  },
  /* 5 telhado */ (p) => {
    for (let y = 0; y < T; y++)
      for (let x = 0; x < T; x++) {
        let c = "#b5513c";
        if (y % 4 === 0) c = "#c9654e";
        else if (y % 4 === 3) c = "#8a3a2c";
        else if (x % 8 === ((y >> 2) % 2) * 4) c = "#9a4333";
        p.set(x, y, c);
      }
  },
  /* 6 parede */ (p) => parede(p),
  /* 7 janela */ (p) => {
    parede(p);
    p.rect(3, 3, 10, 10, "#6b4a2a");
    p.rect(4, 4, 8, 8, "#6fb0e8");
    p.rect(7, 4, 2, 8, "#6b4a2a");
    p.rect(4, 7, 8, 2, "#6b4a2a");
    p.set(5, 5, "#b8dcf6");
    p.set(6, 5, "#b8dcf6");
  },
  /* 8 porta */ (p) => {
    parede(p);
    p.rect(3, 1, 10, 15, "#5a3418");
    p.rect(4, 2, 8, 6, "#8e5a2c");
    p.rect(4, 9, 8, 6, "#8e5a2c");
    p.set(10, 8, "#f0d848");
  },
  /* 9 cerca */ (p) => {
    grama(p);
    p.rect(0, 5, T, 2, "#a8743c");
    p.rect(0, 10, T, 2, "#a8743c");
    p.rect(0, 7, T, 1, "#7a4e26");
    p.rect(0, 12, T, 1, "#7a4e26");
    p.rect(2, 3, 2, 12, "#8a5a2e");
    p.rect(12, 3, 2, 12, "#8a5a2e");
  },
  /* 10 flores */ (p) => {
    grama(p);
    for (const [fx, fy, cor] of [[3, 4, "#e04848"], [10, 3, "#f0d848"], [6, 10, "#f0d848"], [12, 11, "#e04848"]]) {
      p.rect(fx, fy + 2, 1, 2, "#2f7a2c");
      p.set(fx, fy - 1, cor);
      p.set(fx - 1, fy, cor);
      p.set(fx + 1, fy, cor);
      p.set(fx, fy + 1, cor);
      p.set(fx, fy, "#fff8d0");
    }
  },
  /* 11 marcador de bloqueio (só aparece no editor Tiled; a camada "colisao" fica invisível no jogo) */ (p) => {
    p.rect(0, 0, T, T, "#ff0000", 70);
    for (let i = 0; i < T; i++) {
      p.set(i, 0, "#ff0000", 200);
      p.set(i, T - 1, "#ff0000", 200);
      p.set(0, i, "#ff0000", 200);
      p.set(T - 1, i, "#ff0000", 200);
    }
  },
];
function parede(p) {
  for (let y = 0; y < T; y++)
    for (let x = 0; x < T; x++)
      p.set(x, y, y === 15 ? "#b9a878" : ruido(x, y, 6) < 0.05 ? "#d9cc9c" : "#eadfb8");
}

const tiles = new Img(T * TILES.length, T);
TILES.forEach((fn, i) => fn({ set: (x, y, c, a) => tiles.set(i * T + x, y, c, a), rect: (x, y, w, h, c, a) => tiles.rect(i * T + x, y, w, h, c, a) }));

// ---------- Personagens: 4 aparências x 12 quadros (baixo, esquerda, direita, cima; 3 quadros cada) ----------
const CAMISAS = ["#c04040", "#3f6fd0", "#3f9a4f", "#d8b030"];
const CABELOS = ["#3a2418", "#222222", "#7a4a20", "#a06a28"];
const PELE = "#f0c8a0";
const DIRS = ["baixo", "esquerda", "direita", "cima"];

function escurecer(hex) {
  const f = (i) => Math.round(parseInt(hex.slice(i, i + 2), 16) * 0.72).toString(16).padStart(2, "0");
  return `#${f(1)}${f(3)}${f(5)}`;
}
function personagem(img, ox, oy, dir, quadro, camisa, cabelo) {
  const s = (x, y, c) => img.set(ox + x, oy + y, c);
  const r = (x, y, w, h, c) => img.rect(ox + x, oy + y, w, h, c);
  // cabeça
  r(5, 2, 6, 5, PELE);
  if (dir === "baixo") {
    r(5, 2, 6, 2, cabelo); s(5, 4, cabelo); s(10, 4, cabelo);
    s(6, 5, "#202020"); s(9, 5, "#202020");
  } else if (dir === "cima") {
    r(5, 2, 6, 5, cabelo);
  } else if (dir === "esquerda") {
    r(5, 2, 6, 2, cabelo); r(8, 4, 3, 2, cabelo); s(6, 5, "#202020");
  } else {
    r(5, 2, 6, 2, cabelo); r(5, 4, 3, 2, cabelo); s(9, 5, "#202020");
  }
  // corpo e braços
  r(5, 7, 6, 5, camisa);
  if (dir === "baixo" || dir === "cima") {
    r(4, 7, 1, 4, camisa); r(11, 7, 1, 4, camisa); s(4, 11, PELE); s(11, 11, PELE);
  } else {
    r(7, 7, 2, 4, escurecer(camisa)); r(7, 11, 2, 1, PELE);
  }
  // pernas
  const calca = "#2c3a78";
  const altE = quadro === 1 ? 2 : 3;
  const altD = quadro === 2 ? 2 : 3;
  r(5, 12, 3, altE, calca); r(8, 12, 3, altD, calca);
  r(5, 12 + altE - 1, 3, 1, "#303030"); r(8, 12 + altD - 1, 3, 1, "#303030");
  // contorno
  const marca = [];
  for (let y = 0; y < T; y++)
    for (let x = 0; x < T; x++) {
      if (img.alfa(ox + x, oy + y)) continue;
      if (img.alfa(ox + x - 1, oy + y) || img.alfa(ox + x + 1, oy + y) || img.alfa(ox + x, oy + y - 1) || img.alfa(ox + x, oy + y + 1)) marca.push([x, y]);
    }
  for (const [x, y] of marca) s(x, y, "#1a1a1a");
}
const chars = new Img(T * 12, T * 4);
for (let a = 0; a < 4; a++)
  DIRS.forEach((dir, di) => {
    for (let q = 0; q < 3; q++) personagem(chars, (di * 3 + q) * T, a * T, dir, q, CAMISAS[a], CABELOS[a]);
  });

// ---------- Mapa de Pallet Town (24x20) ----------
const W = 24, H = 20;
const G = { grama: 1, caminho: 2, arvore: 3, agua: 4, telhado: 5, parede: 6, janela: 7, porta: 8, cerca: 9, flor: 10, bloqueio: 11 };
const grade = (v) => Array.from({ length: H }, () => Array(W).fill(v));
const chao = grade(G.grama);
const decor = grade(0);
for (let x = 0; x < W; x++) decor[0][x] = G.arvore;
for (let y = 0; y < H; y++) decor[y][0] = decor[y][W - 1] = G.arvore;
for (let y = 0; y <= 6; y++) for (const x of [11, 12]) { chao[y][x] = G.caminho; decor[y][x] = 0; }
for (let x = 5; x <= 19; x++) chao[6][x] = G.caminho;
for (let y = 17; y < H; y++) for (let x = 0; x < W; x++) { chao[y][x] = G.agua; decor[y][x] = 0; }
const casa = (x0, linhaPorta) => {
  for (let x = x0; x < x0 + 4; x++) { decor[2][x] = G.telhado; decor[3][x] = G.telhado; decor[4][x] = G.parede; }
  linhaPorta.forEach((g, i) => (decor[5][x0 + i] = g));
};
casa(3, [G.parede, G.janela, G.porta, G.parede]);
casa(16, [G.parede, G.porta, G.janela, G.parede]);
for (let x = 8; x <= 15; x++) { decor[9][x] = G.telhado; decor[10][x] = G.telhado; decor[11][x] = G.parede; }
[G.parede, G.janela, G.parede, G.porta, G.porta, G.parede, G.janela, G.parede].forEach((g, i) => (decor[12][8 + i] = g));
for (let y = 13; y <= 15; y++) for (const x of [11, 12]) chao[y][x] = G.caminho;
const flores = (y0, y1, x0, x1) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) decor[y][x] = G.flor; };
flores(8, 9, 2, 3); flores(8, 9, 20, 21); flores(14, 15, 3, 5); flores(14, 15, 18, 20);
for (let x = 1; x <= 9; x++) decor[16][x] = G.cerca;
for (let x = 14; x <= 22; x++) decor[16][x] = G.cerca;

const BLOQUEIA_DECOR = new Set([G.arvore, G.telhado, G.parede, G.janela, G.porta, G.cerca]);
const colisao = grade(0);
for (let y = 0; y < H; y++)
  for (let x = 0; x < W; x++) if (BLOQUEIA_DECOR.has(decor[y][x]) || chao[y][x] === G.agua) colisao[y][x] = G.bloqueio;

const camada = (id, name, g, visible = true) => ({
  id, name, type: "tilelayer", x: 0, y: 0, width: W, height: H, opacity: 1, visible, data: g.flat(),
});
const mapa = {
  compressionlevel: -1, type: "map", version: "1.10", tiledversion: "1.10.2",
  orientation: "orthogonal", renderorder: "right-down", infinite: false,
  width: W, height: H, tilewidth: T, tileheight: T, nextlayerid: 6, nextobjectid: 3,
  layers: [
    camada(1, "chao", chao),
    camada(2, "decoracao", decor),
    camada(3, "colisao", colisao, false),
    {
      id: 4, name: "saidas", type: "objectgroup", x: 0, y: 0, opacity: 1, visible: true, draworder: "topdown",
      objects: [{
        id: 1, name: "norte", type: "saida", x: 11 * T, y: 0, width: 2 * T, height: T, rotation: 0, visible: true,
        properties: [
          { name: "destino", type: "string", value: "rota1" },
          { name: "mensagem", type: "string", value: "Rota 1: em construção" },
        ],
      }],
    },
    {
      id: 5, name: "locais", type: "objectgroup", x: 0, y: 0, opacity: 1, visible: true, draworder: "topdown",
      objects: [{ id: 2, name: "spawn", type: "spawn", x: 11 * T, y: 8 * T, width: T, height: T, rotation: 0, visible: true }],
    },
  ],
  tilesets: [{
    firstgid: 1, name: "tiles", image: "../tiles.png", imagewidth: T * TILES.length, imageheight: T,
    tilewidth: T, tileheight: T, tilecount: TILES.length, columns: TILES.length, margin: 0, spacing: 0,
  }],
};

// ---------- Gravação ----------
fs.mkdirSync(path.join(SAIDA, "mapas"), { recursive: true });
fs.writeFileSync(path.join(SAIDA, "tiles.png"), codificarPng(tiles));
fs.writeFileSync(path.join(SAIDA, "personagens.png"), codificarPng(chars));
fs.writeFileSync(path.join(SAIDA, "mapas", "pallet.json"), JSON.stringify(mapa) + "\n");
console.log("Arte e mapa gerados em", SAIDA);

if (process.argv.includes("--preview")) {
  const Z = 3;
  const pre = new Img(W * T * Z, H * T * Z + 8 + 4 * T * 2 * 2);
  const copiar = (origem, sx, sy, dx, dy, z) => {
    for (let y = 0; y < T; y++) for (let x = 0; x < T; x++) {
      const i = ((sy + y) * origem.w + sx + x) * 4;
      if (!origem.d[i + 3]) continue;
      const c = "#" + [0, 1, 2].map((k) => origem.d[i + k].toString(16).padStart(2, "0")).join("");
      pre.rect(dx + x * z, dy + y * z, z, z, c, origem.d[i + 3]);
    }
  };
  for (const g of [chao, decor])
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (g[y][x]) copiar(tiles, (g[y][x] - 1) * T, 0, x * T * Z, y * T * Z, Z);
  for (let q = 0; q < 12; q++) for (let a = 0; a < 4; a++) copiar(chars, q * T, a * T, q * T * 2, H * T * Z + 8 + a * T * 2, 2);
  fs.mkdirSync(".preview", { recursive: true });
  fs.writeFileSync(".preview/pallet-preview.png", codificarPng(pre));
  console.log("Prévia em .preview/pallet-preview.png");
}
