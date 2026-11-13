#!/usr/bin/env python3
"""Piloto de legibilidade: Azurana (lado oeste).
Antes: a clareira de chegada (vinda da Costa Azul) só tinha saída por uma trilha de 1 tile na beira do lago.
Agora: uma trilha de areia sai da chegada, atravessa a mata (árvores 2x2 removidas) e cruza o rio por uma ponte
até a avenida de areia da cidade.
Só usa pixels que já existem no próprio mapa (grama, areia, ponte). Idempotente. Requer Pillow.
Uso: python3 scripts/mapas/piloto-azurana.py [--dry]
"""
import json, sys
from pathlib import Path
from PIL import Image

T = 16
PASTA = Path(__file__).resolve().parents[2] / "public/assets/mapas"
dry = "--dry" in sys.argv

js = json.loads((PASTA / "azurana.json").read_text())
w = js["w"]
sol = list(js["solido"])
base = Image.open(PASTA / "azurana.png").convert("RGBA")
cima = Image.open(PASTA / "azurana-cima.png").convert("RGBA")
orig = base.copy()

def tile(x, y): return orig.crop((x*T, y*T, (x+1)*T, (y+1)*T))
grama = [tile(0, 29), tile(1, 28), tile(2, 30), tile(0, 27)]
areia = tile(12, 34)

def livre(x, y): sol[y*w + x] = "0"

# 1) árvores 2x2 removidas (canto superior esquerdo de cada bloco)
for tx, ty in [(1, 31), (1, 33), (1, 35), (3, 34)]:
    for dx in (0, 1):
        for dy in (0, 1):
            base.paste(grama[(tx+dx+ty+dy) % 4], ((tx+dx)*T, (ty+dy)*T)); livre(tx+dx, ty+dy)
    cima.paste((0, 0, 0, 0), (tx*T, ty*T, (tx+2)*T, (ty+2)*T))

# 2) trilha de areia: da chegada (1,29) até (1,34), depois para leste até a ponte e a avenida
for y in range(29, 35): base.paste(areia, (1*T, y*T))
for x in list(range(1, 5)) + [7, 8]: base.paste(areia, (x*T, 34*T))

# 3) ponte horizontal: miolo da ponte vertical, girado, sem os pixels de água
deck = orig.crop((268, 432, 293, 480)).rotate(90, expand=True)
px = deck.load()
for yy in range(deck.height):
    for xx in range(deck.width):
        r, g, b, a = px[xx, yy]
        if b > r + 50 and b > g + 10: px[xx, yy] = (0, 0, 0, 0)
base.alpha_composite(deck, (72, 34*T - 4))
for x in (5, 6): livre(x, 34)

if dry:
    print("dry-run: nada gravado")
else:
    base.save(PASTA / "azurana.png"); cima.save(PASTA / "azurana-cima.png")
    js["solido"] = "".join(sol)
    txt = (PASTA / "azurana.json").read_text()
    # preserva o formato do arquivo: troca só o valor de "solido"
    import re
    antigo = json.loads(txt)["solido"]
    (PASTA / "azurana.json").write_text(txt.replace(antigo, js["solido"], 1))
    print("Azurana atualizada.")
