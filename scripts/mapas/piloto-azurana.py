#!/usr/bin/env python3
"""Piloto de legibilidade (v2): Azurana, lado oeste.
Problema: a clareira de chegada (vinda da Costa Azul) só tinha saída por uma trilha de 1 tile na beira do lago.
Solução: uma trilha de areia sai da chegada, atravessa a mata (árvores 2x2 removidas) e cruza o rio por uma ponte
até a avenida de areia da cidade. A trilha é montada com PEDAÇOS DA PRÓPRIA AVENIDA (areia + borda clara),
espelhados quando preciso, para ficar no mesmo estilo. Parte sempre do estado original (commit 8de9d2d): idempotente.
Uso: python3 scripts/mapas/piloto-azurana.py [--dry]    (requer Pillow e git)
"""
import io, json, subprocess, sys
from pathlib import Path
from PIL import Image, ImageOps

T = 16
RAIZ = Path(__file__).resolve().parents[2]
PASTA = RAIZ / "public/assets/mapas"
BASE_COMMIT = "8de9d2d"

def original(nome):
    return subprocess.check_output(["git", "show", f"{BASE_COMMIT}:public/assets/mapas/{nome}"], cwd=RAIZ)

js = json.loads(original("azurana.json"))
w = js["w"]
sol = list(js["solido"])
orig = Image.open(io.BytesIO(original("azurana.png"))).convert("RGBA")
base = orig.copy()
cima = Image.open(io.BytesIO(original("azurana-cima.png"))).convert("RGBA")

def tile(x, y, flipv=False):
    t = orig.crop((x*T, y*T, (x+1)*T, (y+1)*T))
    return ImageOps.flip(t) if flipv else t
def put(x, y, t): base.paste(t, (x*T, y*T))
def livre(x, y): sol[y*w + x] = "0"

# 1) mata: árvores 2x2 removidas (+ as cortadas na borda esquerda, coluna 0) -> grama
grama = [tile(0, 29), tile(1, 28), tile(2, 30), tile(0, 27)]
for tx, ty in [(1, 31), (1, 33), (1, 35), (3, 32), (3, 34)]:
    for dx in (0, 1):
        for dy in (0, 1):
            put(tx+dx, ty+dy, grama[(tx+dx+ty+dy) % 4]); livre(tx+dx, ty+dy)
    cima.paste((0, 0, 0, 0), (tx*T, ty*T, (tx+2)*T, (ty+2)*T))
for y in range(31, 37):
    put(0, y, grama[y % 4]); livre(0, y)
cima.paste((0, 0, 0, 0), (0, 31*T, T, 37*T))

# 2) trilha com pedaços da avenida. Peças: horizontal (x=12,y=33..35), vertical (x=8..10,y=37),
#    canto "┌" (centro 9,34) espelhado para "└", ponta de trilha (x=16..18,y=32..33).
CX = 1                                   # coluna da trilha vertical
for dx in (-1, 0, 1):                    # ponta superior: halo em y=28, areia em y=29
    put(CX+dx, 28, tile(17+dx, 32))
    t = tile(9+dx, 37)                   # lados: peça vertical com o topo arredondado da ponta (10 px de cima)
    t.paste(tile(17+dx, 33).crop((0, 0, T, 10)), (0, 0))
    put(CX+dx, 29, t if dx else tile(17, 33))
for y in range(30, 33):                  # trecho vertical
    for dx in (-1, 0, 1): put(CX+dx, y, tile(9+dx, 37))
for dx in (-1, 0, 1):                    # canto └ (espelho vertical do ┌)
    for dy in (-1, 0, 1): put(CX+dx, 34+dy, tile(9+dx, 34-dy, flipv=True))
for x in (2, 3, 4, 8):                   # trecho horizontal até a ponte e depois da ponte
    for dy, sy in ((-1, 33), (0, 34), (1, 35)): put(x, 34+dy, tile(12, sy))
put(7, 34, tile(12, 34))                 # a ponte pousa na areia da margem leste
for dy in (-1, 0, 1): livre(0, 34+dy)

# 3) ponte horizontal: miolo da ponte vertical, girado, sem os pixels de água
deck = orig.crop((268, 432, 293, 480)).rotate(90, expand=True)
px = deck.load()
for yy in range(deck.height):
    for xx in range(deck.width):
        r, g, b, a = px[xx, yy]
        if b > r + 50 and b > g + 10: px[xx, yy] = (0, 0, 0, 0)
base.alpha_composite(deck, (72, 34*T - 4))
for x in (5, 6): livre(x, 34)

if "--dry" in sys.argv:
    print("dry-run: nada gravado")
else:
    base.save(PASTA / "azurana.png"); cima.save(PASTA / "azurana-cima.png")
    txt = original("azurana.json").decode()
    (PASTA / "azurana.json").write_text(txt.replace(js["solido"], "".join(sol), 1))
    print("Azurana atualizada.")
