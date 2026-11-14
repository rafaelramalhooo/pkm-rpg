#!/usr/bin/env python3
"""Prolonga caminhos de mapas antigos copiando trechos retos REAIS do próprio mapa (com bordas): scripts/mapas/estender.json.
Idempotente: o trecho-modelo nunca fica dentro da área de destino. Uso: python3 scripts/mapas/estender.py [id ...]"""
import json, sys
from pathlib import Path
from PIL import Image
T = 16
raiz = Path(__file__).resolve().parents[2] / "public/assets/mapas"
cfg = json.loads((Path(__file__).parent / "estender.json").read_text())
for mid in (sys.argv[1:] or cfg):
    j = json.loads((raiz / f"{mid}.json").read_text()); w = j["w"]; sol = [c == "1" for c in j["solido"]]
    base = Image.open(raiz / f"{mid}.png").convert("RGBA"); cima = Image.open(raiz / f"{mid}-cima.png").convert("RGBA")
    b0, c0, s0 = base.copy(), cima.copy(), list(sol)
    for e in cfg[mid]:
        mx, my, mw, mh = e["modelo"]; dx, dy = e["para"]; passo = (mw, 0) if e["dir"] == "h" else (0, mh)
        for k in range(e["rep"]):
            for jj in range(mh):
                for ii in range(mw):
                    a, b = mx + ii, my + jj; x, y = dx + ii + passo[0] * k, dy + jj + passo[1] * k
                    if not (0 <= x < w and 0 <= y < j["h"]): continue
                    box = (a * T, b * T, a * T + T, b * T + T)
                    base.paste(b0.crop(box), (x * T, y * T)); cima.paste(c0.crop(box), (x * T, y * T)); sol[y * w + x] = s0[b * w + a]
    base.save(raiz / f"{mid}.png"); cima.save(raiz / f"{mid}-cima.png")
    j["solido"] = "".join("1" if s else "0" for s in sol)
    (raiz / f"{mid}.json").write_text(json.dumps(j, ensure_ascii=False, separators=(",", ":")) + "\n")
    print("estendido:", mid)
