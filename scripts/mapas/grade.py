#!/usr/bin/env python3
"""Folha com grade numerada de um TMX (ou de um mapa do jogo) para escolher portas, portais e pontos.
Uso: python3 scripts/mapas/grade.py <arquivo.tmx> <saida.png> [zoom]"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from tmx import carregar_tmx, T
from PIL import Image, ImageDraw
r = carregar_tmx(sys.argv[1]); z = int(sys.argv[3]) if len(sys.argv) > 3 else 2
im = r["base"].copy(); im.alpha_composite(r["cima"]); im = im.convert("RGB").resize((r["w"]*T*z, r["h"]*T*z), Image.NEAREST)
d = ImageDraw.Draw(im, "RGBA"); s = T*z
for i, sol in enumerate(r["solido"]):
    if sol: x, y = i % r["w"], i // r["w"]; d.rectangle((x*s, y*s, x*s+s-1, y*s+s-1), fill=(255, 0, 0, 55))
for x in range(r["w"]+1): d.line((x*s, 0, x*s, r["h"]*s), fill=(255, 255, 255, 40 if x % 5 else 110))
for y in range(r["h"]+1): d.line((0, y*s, r["w"]*s, y*s), fill=(255, 255, 255, 40 if y % 5 else 110))
for x in range(0, r["w"], 5): d.text((x*s+2, 2), str(x), fill=(255, 255, 0))
for y in range(0, r["h"], 5): d.text((2, y*s+2), str(y), fill=(255, 255, 0))
im.save(sys.argv[2]); print(im.size)
