#!/usr/bin/env python3
"""Lote 3 de correções visuais (idempotente; só usa pedaços dos próprios mapas).
 - Quartzo: um fragmento de casa (x=11, y=5..8) cortava a viela de Rota 8; vira grama como a viela.
 - Argila: o "campo escuro" em volta do Centro Pokémon (x=31..37, y=6..15) vira grama normal, mantendo a trilha de areia.
Uso: python3 scripts/mapas/lote3-correcoes.py"""
import json, collections
from pathlib import Path
from PIL import Image
R = Path(__file__).resolve().parents[2] / "public/assets/mapas"
T = 16

def abrir(id):
    txt = (R / f"{id}.json").read_text(); m = json.loads(txt)
    return txt, m, Image.open(R / f"{id}.png").convert("RGBA"), Image.open(R / f"{id}-cima.png").convert("RGBA")
def salvar(id, txt, m, sol, base, cima):
    (R / f"{id}.json").write_text(txt.replace(m["solido"], "".join(sol)))
    base.save(R / f"{id}.png"); cima.save(R / f"{id}-cima.png")
def tile(img, x, y): return img.crop((x*T, y*T, (x+1)*T, (y+1)*T))

# ---- Quartzo
txt, m, base, cima = abrir("quartzo"); w = m["w"]; sol = list(m["solido"])
for y in range(5, 9):
    base.paste(tile(base, 11, 4), (11*T, y*T)); cima.paste((0, 0, 0, 0), (11*T, y*T, 12*T, (y+1)*T)); sol[y*w + 11] = "0"
salvar("quartzo", txt, m, sol, base, cima)

# ---- Argila
txt, m, base, cima = abrir("argila"); w = m["w"]; sol = list(m["solido"]); px = base.load()
def escuro(c): return c[0] < 110 and c[1] < 95 and c[2] < 80 and c[0] >= c[2]
def fracao(x, y): return sum(1 for py in range(T) for q in range(T) if escuro(px[x*T+q, y*T+py])) / (T*T)
grama = [(x, y) for y in range(16, 30) for x in range(0, 40) if sol[y*w+x] == "0" and all(px[x*T+q, y*T+p][:3] in {(64,176,128),(24,160,104),(112,192,160)} for q in range(0,T,5) for p in range(0,T,5))][:4]
assert len(grama) >= 2, "sem tiles de grama de referência"
modelos = [tile(base, x, y) for x, y in grama]
alvo = [(x, y) for y in range(6, 17) for x in range(30, 38) if fracao(x, y) >= 0.25]
for x, y in alvo:
    base.paste(modelos[(x + y) % len(modelos)], (x*T, y*T))
salvar("argila", txt, m, sol, base, cima)
print("quartzo ok; argila:", len(alvo), "tiles trocados")
