#!/usr/bin/env python3
"""Gera os arquivos do jogo (id.png, id-cima.png, id.json) a partir de um mapa Tiled do Tuxemon.
Uso: python3 scripts/mapas/tmx2jogo.py <id> [--dir-tuxemon CAMINHO] [--saida PASTA]
Receita: scripts/mapas/fontes/<id>.meta.json
  tmx        nome do mapa Tuxemon (sem .tmx)
  limpar     [[x,y,w,h]...]  remove decoração (tudo acima da 1ª camada) nessas áreas e libera a colisão
  solidos    [[x,y,w,h]...]  força colisão
  livres     [[x,y,w,h]...]  força passagem
  portais    lista de portais do jogo (x,y,w,h,dest,dx,dy,dir)
  pois       "herdar" (mantém os do json atual) ou lista nova
Campos não citados (bioma, níveis, grama...) são herdados do json atual do mapa. Idempotente."""
import colorsys, json, sys, os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import tmx as TMX
from PIL import Image

RAIZ = Path(__file__).resolve().parents[2]
T = 16

def main():
    args = sys.argv[1:]
    mid = args[0]
    tux = Path(os.environ.get("TUXEMON_DIR", "/tmp/tux/mods/tuxemon")) if "--dir-tuxemon" not in args else Path(args[args.index("--dir-tuxemon") + 1])
    saida = Path(args[args.index("--saida") + 1]) if "--saida" in args else RAIZ / "public/assets/mapas"
    meta = json.loads((Path(__file__).parent / "fontes" / f"{mid}.meta.json").read_text())
    atual = json.loads((saida / f"{mid}.json").read_text()) if (saida / f"{mid}.json").exists() else {}
    r = TMX.carregar_tmx(tux / "maps" / f"{meta['tmx']}.tmx", limpar=meta.get("limpar", []))
    w, h = r["w"], r["h"]
    sol = list(r["solido"])
    def retangulos(chave, valor):
        for x, y, rw, rh in meta.get(chave, []):
            for ty in range(y, y + rh):
                for tx in range(x, x + rw):
                    if 0 <= tx < w and 0 <= ty < h: sol[ty * w + tx] = valor
    retangulos("solidos", True); retangulos("livres", False)
    # bolsões andáveis que nenhum portal alcança (telhados, cantos cercados) viram sólidos, salvo se tiverem um ponto de interesse
    pois = meta["pois"] if meta.get("pois", "herdar") != "herdar" else atual.get("pois", [])
    visto = set(); fila = []
    for p in meta["portais"]:
        for ty in range(p["y"], p["y"] + p.get("h", 1)):
            for tx in range(p["x"], p["x"] + p.get("w", 1)):
                if 0 <= tx < w and 0 <= ty < h and not sol[ty * w + tx] and (tx, ty) not in visto: visto.add((tx, ty)); fila.append((tx, ty))
    for a, b in fila:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (a + dx, b + dy)
            if 0 <= n[0] < w and 0 <= n[1] < h and not sol[n[1] * w + n[0]] and n not in visto: visto.add(n); fila.append(n)
    sobra = {(x, y) for y in range(h) for x in range(w) if not sol[y * w + x] and (x, y) not in visto}
    poi_em = {(q["x"], q["y"]) for q in pois}
    resto = set(sobra); fechados = 0
    while resto:
        ini = resto.pop(); comp = [ini]
        for a, b in comp:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (a + dx, b + dy)
                if n in resto: resto.discard(n); comp.append(n)
        if len(comp) <= 60 and not any(c in poi_em for c in comp):
            for x, y in comp: sol[y * w + x] = True
            fechados += len(comp)
    grama = r["grama"] if any(r["grama"]) else (list(c == "1" for c in atual["grama"]) if len(atual.get("grama", "")) == w * h else [False] * (w * h))
    out = dict(atual)
    out.update({"id": mid, "nome": atual.get("nome", meta.get("nome", mid)), "w": w, "h": h,
                "solido": "".join("1" if s else "0" for s in sol), "grama": "".join("1" if g else "0" for g in grama)})
    if len(out.get("bioma", "")) != w * h:
        out["bioma"] = (out.get("bioma", "G") or "G")[0] * (w * h)
    out["portais"] = meta["portais"]
    if meta.get("pois", "herdar") != "herdar": out["pois"] = meta["pois"]
    for t in meta.get("tinta", []):   # identidade de cor da cidade: gira o matiz dos tons quentes (telhados) dentro de áreas escolhidas
        x0, y0, rw, rh = t["rect"]
        for img in (r["base"], r["cima"]):
            px = img.load()
            for yy in range(y0 * T, (y0 + rh) * T):
                for xx in range(x0 * T, (x0 + rw) * T):
                    rr, gg, bb, aa = px[xx, yy]
                    if aa == 0: continue
                    hh, ss, vv = colorsys.rgb_to_hsv(rr / 255, gg / 255, bb / 255)
                    if ss > 0.2 and (hh < 50 / 360 or hh > 330 / 360):
                        nr, ng, nb = colorsys.hsv_to_rgb((hh + t["delta"] / 360) % 1, ss, vv)
                        px[xx, yy] = (round(nr * 255), round(ng * 255), round(nb * 255), aa)
    r["base"].save(saida / f"{mid}.png"); r["cima"].save(saida / f"{mid}-cima.png")
    (saida / f"{mid}.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"{mid}: {w}x{h}, {sum(sol)} tiles sólidos ({fechados} de bolsões fechados)")

main()
