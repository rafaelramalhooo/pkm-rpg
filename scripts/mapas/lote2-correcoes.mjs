// Lote 2 de correções de legibilidade (idempotente; rode: node scripts/mapas/lote2-correcoes.mjs).
//  1) Paredes invisíveis: tiles sólidos com cara de chão livre (Verdelume e Porto Ferrugem) passam a ser andáveis.
//  2) Ametista: a entrada do ginásio fica na PORTA desenhada (6,19), e não no fim de uma trilha que bate na parede.
import fs from "node:fs";
import path from "node:path";
import { carregarMapas, PASTA_MAPAS } from "./lib.mjs";
import { lintar } from "../lint-mapas.mjs";

const dados = carregarMapas();
const { problemas } = lintar(dados, ["verdelume", "porto", "argila"]);
for (const p of problemas.filter((q) => q.codigo === "PAREDE_INVISIVEL")) {
  const arq = path.join(PASTA_MAPAS, `${p.mapa}.json`);
  const txt = fs.readFileSync(arq, "utf8");
  const m = JSON.parse(txt);
  const s = m.solido.split("");
  for (const [x, y] of p.tiles) s[y * m.w + x] = "0";
  fs.writeFileSync(arq, txt.replace(m.solido, s.join("")));
  console.log(`${p.mapa}: ${p.tiles.length} tiles liberados`);
}

function trocar(id, de, para) {
  const arq = path.join(PASTA_MAPAS, `${id}.json`);
  const txt = fs.readFileSync(arq, "utf8");
  if (txt.includes(para)) return; // já aplicado
  if (!txt.includes(de)) throw new Error(`${id}: trecho não encontrado: ${de}`);
  fs.writeFileSync(arq, txt.replace(de, para));
  console.log(`${id}: portal ajustado`);
}
trocar("ametista", '{"x":9,"y":22,"w":1,"h":1,"dest":"gin_ametista","dx":10,"dy":18,"dir":"cima"}', '{"x":6,"y":19,"w":1,"h":1,"dest":"gin_ametista","dx":10,"dy":18,"dir":"cima"}');
trocar("gin_ametista", '"dest":"ametista","dx":9,"dy":23,"dir":"baixo"', '"dest":"ametista","dx":6,"dy":20,"dir":"baixo"');
