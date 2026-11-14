#!/usr/bin/env python3
"""Remove as copas de árvore cortadas na última linha dos mapas (o tronco ficaria fora do mapa): troca por grama do próprio mapa.
Referência = bloco 2x2 de árvore no canto (0,0). Uso: python3 scripts/mapas/bordas.py id [id ...]"""
import json, sys
from collections import Counter
from pathlib import Path
from PIL import Image
T = 16
raiz = Path(__file__).resolve().parents[2] / "public/assets/mapas"
def sim(a, b):
    pa, pb = a.load(), b.load(); return sum(pa[x, y] == pb[x, y] for x in range(T) for y in range(T)) / (T * T)
for mid in sys.argv[1:]:
    j = json.loads((raiz / f"{mid}.json").read_text()); w, h = j["w"], j["h"]; sol = [c == "1" for c in j["solido"]]
    base = Image.open(raiz / f"{mid}.png").convert("RGBA"); cima = Image.open(raiz / f"{mid}-cima.png").convert("RGBA")
    comp = Image.alpha_composite(base, cima)
    tile = lambda im, x, y: im.crop((x * T, y * T, x * T + T, y * T + T))
    refs = [tile(comp, 0, 0), tile(comp, 1, 0)]
    cont = Counter(tile(base, x, y).tobytes() for y in range(h) for x in range(w) if not sol[y * w + x])
    grama = Image.frombytes("RGBA", (T, T), cont.most_common(1)[0][0]); n = 0
    for x in range(w):
        if any(sim(tile(comp, x, h - 1), r) >= 0.8 for r in refs):
            base.paste(grama, (x * T, (h - 1) * T)); cima.paste((0, 0, 0, 0), (x * T, (h - 1) * T, x * T + T, h * T)); sol[(h - 1) * w + x] = False; n += 1
    base.save(raiz / f"{mid}.png"); cima.save(raiz / f"{mid}-cima.png")
    j["solido"] = "".join("1" if s else "0" for s in sol)
    (raiz / f"{mid}.json").write_text(json.dumps(j, ensure_ascii=False, separators=(",", ":")) + "\n"); print(mid, n, "copas removidas")
