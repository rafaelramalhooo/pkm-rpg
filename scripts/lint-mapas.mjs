// Linter dos mapas do jogo (somente leitura).
// Uso: node scripts/lint-mapas.mjs [--so id1,id2] [--md relatorio.md] [--json] [--estrito]
//   ERRO  = problema estrutural (o jogo quebra ou o jogador fica preso); o comando sai com código 1.
//   AVISO = suspeito, merece olhar (com --estrito também sai com código 1).
// As regras espelham o motor em src/game/mundo.ts: a colisão é checada ANTES do portal,
// então um portal em tile sólido simplesmente não funciona.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { T, carregarMapas, consulta, dimensoesPng, lerPng } from "./mapas/lib.mjs";

const ARQ_EXCECOES = path.join(path.dirname(fileURLToPath(import.meta.url)), "mapas", "excecoes.json");
/** Exceções conscientes (ex.: portais de sentido único na Liga). Formato: [{ mapa, codigo, contem?, motivo }]. */
function carregarExcecoes() {
  try { return JSON.parse(fs.readFileSync(ARQ_EXCECOES, "utf8")); } catch { return []; }
}

const VIZ = [[1, 0], [-1, 0], [0, 1], [0, -1]];

/** Componentes conectados de tiles andáveis a partir de sementes. Não atravessa tiles de portal (só entra neles). */
function alcance(m, sementes, ehPortal) {
  const { solido } = consulta(m);
  const visto = new Set();
  const chave = (x, y) => y * m.w + x;
  const comps = [];
  for (const [sx, sy] of sementes) {
    if (solido(sx, sy) || visto.has(chave(sx, sy))) continue;
    const comp = new Set([chave(sx, sy)]);
    visto.add(chave(sx, sy));
    const fila = [[sx, sy]];
    while (fila.length) {
      const [x, y] = fila.shift();
      if (ehPortal(x, y) && !(x === sx && y === sy)) continue; // entrou no portal: não anda "através" dele
      for (const [dx, dy] of VIZ) {
        const nx = x + dx;
        const ny = y + dy;
        if (solido(nx, ny) || visto.has(chave(nx, ny))) continue;
        visto.add(chave(nx, ny));
        comp.add(chave(nx, ny));
        fila.push([nx, ny]);
      }
    }
    comps.push(comp);
  }
  comps.sort((a, b) => b.size - a.size);
  return { comps, visto, chave };
}

/** Executa todas as verificações. Retorna { problemas: [{mapa,gravidade,codigo,msg,tiles?}], resumo }. */
export function lintar({ ids, mapas, orfaos, faltando, pasta }, filtro = null) {
  const problemas = [];
  const add = (mapa, gravidade, codigo, msg, tiles) => problemas.push({ mapa, gravidade, codigo, msg, ...(tiles?.length ? { tiles } : {}) });

  for (const id of faltando) add(id, "ERRO", "INDICE_SEM_ARQUIVO", `Listado em _indice.json, mas ${id}.json não existe.`);
  for (const id of orfaos) add(id, "AVISO", "ARQUIVO_FORA_DO_INDICE", `${id}.json existe, mas não está em _indice.json (o Mestre não importa esse mapa).`);

  // Sementes de entrada por mapa: spawn + chegadas de portais de outros mapas.
  const chegadas = new Map(); // id -> [{x,y,de}]
  for (const [id, m] of mapas) for (const p of m.portais ?? []) {
    if (!chegadas.has(p.dest)) chegadas.set(p.dest, []);
    chegadas.get(p.dest).push({ x: p.dx, y: p.dy, de: id });
  }

  for (const [id, m] of mapas) {
    if (filtro && !filtro.includes(id)) continue;
    const { solido, grama, retangulo } = consulta(m);
    const n = m.w * m.h;

    // ---- estrutura e arquivos
    if (m.id !== m._arquivo) add(id, "ERRO", "ID_DIFERENTE", `O campo id do JSON é "${m.id}", mas o arquivo é ${id}.json.`);
    for (const campo of ["solido", "grama", "bioma"]) {
      if (typeof m[campo] !== "string" || m[campo].length !== n) add(id, "ERRO", "TAMANHO", `"${campo}" tem ${m[campo]?.length ?? "nenhum"} caracteres; esperado ${n} (${m.w}x${m.h}).`);
    }
    if (n <= 0 || m.solido?.length !== n) continue; // sem grade válida, o resto não faz sentido
    for (const [sufixo, rotulo] of [["", "imagem base"], ["-cima", "camada superior"]]) {
      const arq = path.join(pasta, `${id}${sufixo}.png`);
      if (!fs.existsSync(arq)) { add(id, "ERRO", "PNG_AUSENTE", `Falta ${id}${sufixo}.png (${rotulo}).`); continue; }
      const d = dimensoesPng(arq);
      if (!d || d.w !== m.w * T || d.h !== m.h * T) add(id, "ERRO", "PNG_TAMANHO", `${id}${sufixo}.png tem ${d ? `${d.w}x${d.h}` : "formato inválido"}; esperado ${m.w * T}x${m.h * T}.`);
    }

    // ---- portais
    const tilesPortal = new Set();
    for (const p of m.portais ?? []) for (const [x, y] of retangulo(p)) tilesPortal.add(y * m.w + x);
    const ehPortal = (x, y) => tilesPortal.has(y * m.w + x);
    (m.portais ?? []).forEach((p, i) => {
      const nome = `portal #${i + 1} → ${p.dest}`;
      const tiles = retangulo(p);
      const fora = tiles.filter(([x, y]) => x < 0 || y < 0 || x >= m.w || y >= m.h);
      if (fora.length) { add(id, "ERRO", "PORTAL_FORA", `${nome}: ${fora.length} tile(s) fora do mapa.`, tiles.filter((t) => !fora.includes(t))); return; }
      const sol = tiles.filter(([x, y]) => solido(x, y));
      if (sol.length === tiles.length) add(id, "ERRO", "PORTAL_SOLIDO", `${nome}: todos os tiles são sólidos; o motor bloqueia o passo antes do portal, então ele nunca dispara.`, sol);
      else if (sol.length) add(id, "AVISO", "PORTAL_PARCIAL_SOLIDO", `${nome}: ${sol.length} de ${tiles.length} tiles são sólidos (o portal funciona só nos demais).`, sol);
      const destino = mapas.get(p.dest);
      if (!destino) { add(id, "ERRO", "PORTAL_DESTINO", `${nome}: o mapa de destino não existe.`, tiles); return; }
      const dentro = Number.isInteger(p.dx) && Number.isInteger(p.dy) && p.dx >= 0 && p.dy >= 0 && p.dx < destino.w && p.dy < destino.h;
      if (!dentro) add(id, "ERRO", "CHEGADA_FORA", `${nome}: chegada (${p.dx},${p.dy}) fora do mapa de destino (${destino.w}x${destino.h}).`, tiles);
      else if (consulta(destino).solido(p.dx, p.dy)) add(id, "ERRO", "CHEGADA_SOLIDA", `${nome}: chegada (${p.dx},${p.dy}) cai num tile sólido de ${p.dest}; o jogador nasce preso.`, tiles);
      if (!(destino.portais ?? []).some((q) => q.dest === id)) add(id, "AVISO", "SEM_RETORNO", `${nome}: ${p.dest} não tem nenhum portal de volta para ${id} (ok se for sentido único de propósito).`, tiles);
    });

    // ---- pontos de interesse
    const vistos = new Set();
    for (const p of m.pois ?? []) {
      if (vistos.has(p.id)) add(id, "ERRO", "POI_ID_DUPLICADO", `Dois pontos de interesse com o id "${p.id}".`, [[p.x, p.y]]);
      vistos.add(p.id);
      if (p.x < 0 || p.y < 0 || p.x >= m.w || p.y >= m.h) add(id, "ERRO", "POI_FORA", `"${p.id}" está fora do mapa (${p.x},${p.y}).`);
      else if (solido(p.x, p.y)) add(id, "ERRO", "POI_SOLIDO", `"${p.id}" (${p.nome}) está num tile sólido (${p.x},${p.y}); o jogador não consegue pisar nele.`, [[p.x, p.y]]);
    }

    // ---- spawn
    if (m.spawn) {
      if (solido(m.spawn.x, m.spawn.y)) add(id, "ERRO", "SPAWN_SOLIDO", `O spawn (${m.spawn.x},${m.spawn.y}) está num tile sólido ou fora do mapa.`, [[m.spawn.x, m.spawn.y]]);
    }

    // ---- alcançabilidade (4 direções, como o jogador anda)
    const sementes = [];
    if (m.spawn) sementes.push([m.spawn.x, m.spawn.y]);
    for (const c of chegadas.get(id) ?? []) sementes.push([c.x, c.y]);
    if (!sementes.length) { add(id, "ERRO", "SEM_ENTRADA", "Nenhum portal leva a este mapa e ele não tem spawn: ninguém consegue chegar aqui."); continue; }
    const { comps, visto, chave } = alcance(m, sementes, ehPortal);
    const principal = comps[0] ?? new Set();
    for (const c of chegadas.get(id) ?? []) {
      if (!solido(c.x, c.y) && !principal.has(chave(c.x, c.y)))
        add(id, "ERRO", "CHEGADA_DESCONECTADA", `Quem chega de ${c.de} em (${c.x},${c.y}) fica numa área de ${comps.find((s) => s.has(chave(c.x, c.y)))?.size ?? "?"} tiles, separada do resto do mapa.`, [[c.x, c.y]]);
    }
    if (m.spawn && !solido(m.spawn.x, m.spawn.y) && !principal.has(chave(m.spawn.x, m.spawn.y)))
      add(id, "ERRO", "SPAWN_DESCONECTADO", `O spawn (${m.spawn.x},${m.spawn.y}) fica numa área separada do resto do mapa.`, [[m.spawn.x, m.spawn.y]]);
    for (const p of m.pois ?? []) {
      if (!solido(p.x, p.y) && !principal.has(chave(p.x, p.y))) add(id, "ERRO", "POI_INALCANCAVEL", `"${p.id}" (${p.nome}) em (${p.x},${p.y}) não é alcançável a pé a partir das entradas.`, [[p.x, p.y]]);
    }
    (m.portais ?? []).forEach((p, i) => {
      const tiles = retangulo(p).filter(([x, y]) => !solido(x, y));
      if (tiles.length && !tiles.some(([x, y]) => principal.has(chave(x, y))))
        add(id, "ERRO", "PORTAL_INALCANCAVEL", `portal #${i + 1} → ${p.dest} em (${p.x},${p.y}) não é alcançável a pé a partir das entradas.`, tiles);
    });


    // ---- legibilidade (o caminho precisa ser óbvio para quem joga, não só correto no código)
    // Chegada: o jogador deve nascer numa área livre de pelo menos 3x3 tiles.
    for (const c of chegadas.get(id) ?? []) {
      let ok = false;
      for (let oy = -2; oy <= 0 && !ok; oy++) for (let ox = -2; ox <= 0 && !ok; ox++) {
        let livre = true;
        for (let j = 0; j < 3 && livre; j++) for (let i = 0; i < 3; i++) if (solido(c.x + ox + i, c.y + oy + j)) { livre = false; break; }
        if (livre) ok = true;
      }
      if (!ok && !m.interior) add(id, "AVISO", "CHEGADA_APERTADA", `Quem chega de ${c.de} em (${c.x},${c.y}) fica num corredor apertado (sem área livre de 3x3).`, [[c.x, c.y]]);
    }
    // Desvio: caminho a pé muito mais longo que a linha reta até um portal = jogador acha que está preso.
    const distDe = (sx, sy) => {
      const d = new Map([[chave(sx, sy), 0]]);
      const fila = [[sx, sy]];
      for (let i = 0; i < fila.length; i++) {
        const [x, y] = fila[i];
        for (const [dx, dy] of VIZ) {
          const nx = x + dx, ny = y + dy, k = chave(nx, ny);
          if (solido(nx, ny) || d.has(k)) continue;
          d.set(k, d.get(chave(x, y)) + 1);
          if (!ehPortal(nx, ny)) fila.push([nx, ny]);
        }
      }
      return d;
    };
    for (const c of chegadas.get(id) ?? []) {
      if (solido(c.x, c.y)) continue;
      const d = distDe(c.x, c.y);
      (m.portais ?? []).forEach((p) => {
        let melhor = null;
        for (const [x, y] of retangulo(p)) { const v = d.get(chave(x, y)); if (v !== undefined && (melhor === null || v < melhor)) melhor = v; }
        const reta = Math.abs(p.x - c.x) + Math.abs(p.y - c.y);
        if (melhor !== null && reta >= 8 && melhor > reta * 1.8 + 6)
          add(id, "AVISO", "DESVIO_EXCESSIVO", `De ${c.de} (${c.x},${c.y}) até o portal → ${p.dest} são ${melhor} passos para ${reta} de distância em linha reta (caminho muito tortuoso).`, [[c.x, c.y]]);
      });
    }
    // Parede invisível: bloco 3x3 sólido cujo chão parece igual ao chão andável (nenhuma árvore/água/prédio desenhado).
    if (!m.interior) {
      const pngB = lerPng(path.join(pasta, `${id}.png`));
      const pngC = lerPng(path.join(pasta, `${id}-cima.png`));
      if (pngB && pngB.w === m.w * T) {
        const sig = (x, y) => { let s = ""; for (let py = 0; py < T; py++) for (let px = 0; px < T; px++) { const o = ((y * T + py) * pngB.w + x * T + px) * 4; s += pngB.rgba[o] + "," + pngB.rgba[o + 1] + "," + pngB.rgba[o + 2] + ";"; } return s; };
        const cont = new Map();
        for (let y = 0; y < m.h; y++) for (let x = 0; x < m.w; x++) if (!solido(x, y)) { const k = sig(x, y); cont.set(k, (cont.get(k) ?? 0) + 1); }
        const paleta = new Set();
        [...cont.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).forEach(([k]) => k.split(";").forEach((c) => c && paleta.add(c)));
        const simples = (x, y) => {
          let ok = 0;
          for (let py = 0; py < T; py++) for (let px = 0; px < T; px++) {
            const o = ((y * T + py) * pngB.w + x * T + px) * 4;
            if (pngC && pngC.rgba[o + 3] > 0) continue;
            if (paleta.has(pngB.rgba[o] + "," + pngB.rgba[o + 1] + "," + pngB.rgba[o + 2])) ok++;
          }
          return ok >= T * T * 0.97;
        };
        const marca = new Set();
        for (let y = 0; y + 2 < m.h; y++) for (let x = 0; x + 2 < m.w; x++) {
          let tudo = true;
          for (let j = 0; j < 3 && tudo; j++) for (let i = 0; i < 3; i++) if (!solido(x + i, y + j) || !simples(x + i, y + j)) { tudo = false; break; }
          if (tudo) for (let j = 0; j < 3; j++) for (let i = 0; i < 3; i++) marca.add(chave(x + i, y + j));
        }
        // só conta se o jogador consegue chegar encostado no bloco (senão é um bosque fechado, que não engana ninguém)
        const encosta = [...marca].some((k) => VIZ.some(([dx, dy]) => { const nx = (k % m.w) + dx, ny = Math.floor(k / m.w) + dy; return !solido(nx, ny) && principal.has(chave(nx, ny)); }));
        if (marca.size >= 9 && encosta) add(id, "AVISO", "PAREDE_INVISIVEL", `${marca.size} tiles sólidos com cara de chão livre (o jogador esbarra sem ver o que bloqueia). Desenhe árvores/pedras/água ali ou libere a passagem.`, [...marca].map((k) => [k % m.w, Math.floor(k / m.w)]));
      }
    }

    // ---- áreas andáveis isoladas (sem nenhuma entrada): jardim fechado, cercado sem porta...
    const resto = new Set();
    for (let y = 0; y < m.h; y++) for (let x = 0; x < m.w; x++) if (!solido(x, y) && !visto.has(chave(x, y))) resto.add(chave(x, y));
    while (resto.size) {
      const [ini] = resto;
      resto.delete(ini);
      const comp = [ini];
      for (let i = 0; i < comp.length; i++) {
        const x = comp[i] % m.w;
        const y = Math.floor(comp[i] / m.w);
        for (const [dx, dy] of VIZ) {
          const k = chave(x + dx, y + dy);
          if (x + dx >= 0 && x + dx < m.w && resto.has(k)) { resto.delete(k); comp.push(k); }
        }
      }
      if (comp.length >= 4) add(id, "AVISO", "AREA_ISOLADA", `Área andável de ${comp.length} tiles que nenhum caminho alcança (jardim fechado? cerca sem abertura?).`, comp.map((k) => [k % m.w, Math.floor(k / m.w)]));
    }

    // ---- grama em tile sólido
    const gs = [];
    for (let y = 0; y < m.h; y++) for (let x = 0; x < m.w; x++) if (grama(x, y) && solido(x, y)) gs.push([x, y]);
    if (gs.length) add(id, "AVISO", "GRAMA_SOLIDA", `${gs.length} tile(s) marcados como grama alta, mas sólidos (a grama nunca será pisada).`, gs);
  }

  const ordem = { ERRO: 0, AVISO: 1 };
  problemas.sort((a, b) => ordem[a.gravidade] - ordem[b.gravidade] || a.mapa.localeCompare(b.mapa) || a.codigo.localeCompare(b.codigo));
  const excecoes = carregarExcecoes();
  const ignorado = (p) => excecoes.some((e) => e.mapa === p.mapa && e.codigo === p.codigo && (!e.contem || p.msg.includes(e.contem)));
  const validos = problemas.filter((p) => !ignorado(p));
  const resumo = {
    mapas: filtro ? filtro.length : mapas.size,
    erros: validos.filter((p) => p.gravidade === "ERRO").length,
    avisos: validos.filter((p) => p.gravidade === "AVISO").length,
    ignorados: problemas.length - validos.length,
  };
  return { problemas: validos, resumo };
}

function coordenadas(tiles) {
  if (!tiles?.length) return "";
  const t = tiles.slice(0, 4).map(([x, y]) => `(${x},${y})`).join(" ");
  return tiles.length > 4 ? ` [${t} … +${tiles.length - 4}]` : ` [${t}]`;
}

export function relatorioMarkdown({ problemas, resumo }) {
  const L = [];
  L.push("# Relatório dos mapas", "", `Mapas verificados: **${resumo.mapas}** · Erros: **${resumo.erros}** · Avisos: **${resumo.avisos}**${resumo.ignorados ? ` · Ignorados (exceções conscientes): ${resumo.ignorados}` : ""}`, "");
  if (!problemas.length) { L.push("Nenhum problema encontrado.", ""); return L.join("\n"); }
  for (const g of ["ERRO", "AVISO"]) {
    const lista = problemas.filter((p) => p.gravidade === g);
    if (!lista.length) continue;
    L.push(`## ${g === "ERRO" ? "Erros (estruturais)" : "Avisos (a revisar)"} — ${lista.length}`, "");
    let atual = "";
    for (const p of lista) {
      if (p.mapa !== atual) { atual = p.mapa; L.push(`### ${atual}`); }
      L.push(`- \`${p.codigo}\` ${p.msg}${coordenadas(p.tiles)}`);
    }
    L.push("");
  }
  return L.join("\n");
}

// ---------- linha de comando ----------
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  const valor = (nome) => { const i = args.indexOf(nome); return i >= 0 ? args[i + 1] : null; };
  const filtro = valor("--so")?.split(",").map((s) => s.trim()).filter(Boolean) ?? null;
  const dados = carregarMapas();
  if (filtro) for (const f of filtro) if (!dados.mapas.has(f)) { console.error(`Mapa desconhecido: ${f}`); process.exit(2); }
  const r = lintar(dados, filtro);
  if (args.includes("--json")) console.log(JSON.stringify(r, null, 2));
  else {
    let atual = "";
    for (const p of r.problemas) {
      if (p.mapa !== atual) { atual = p.mapa; console.log(`\n${atual}`); }
      console.log(`  ${p.gravidade === "ERRO" ? "✖ ERRO " : "▲ AVISO"} ${p.codigo.padEnd(22)} ${p.msg}${coordenadas(p.tiles)}`);
    }
    console.log(`\n${r.resumo.mapas} mapas verificados · ${r.resumo.erros} erro(s) · ${r.resumo.avisos} aviso(s)${r.resumo.ignorados ? ` · ${r.resumo.ignorados} ignorado(s) por scripts/mapas/excecoes.json` : ""}`);
  }
  const md = valor("--md");
  if (md) { fs.mkdirSync(path.dirname(path.resolve(md)), { recursive: true }); fs.writeFileSync(md, relatorioMarkdown(r)); console.log(`Relatório gravado em ${md}`); }
  process.exit(r.resumo.erros > 0 || (args.includes("--estrito") && r.resumo.avisos > 0) ? 1 : 0);
}
