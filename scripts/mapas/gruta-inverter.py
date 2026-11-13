#!/usr/bin/env python3
"""Gruta Prisma: a colisão estava invertida (andava-se na rocha clara; os corredores escuros eram paredes).
Deriva a colisão da própria arte: corredor = tile com pelo menos 30 pixels da cor escura do piso. Religa as entradas nas
duas bocas de caverna desenhadas e marca o mapa como "escuro" (o jogo mostra só um foco de luz em volta do jogador).
Idempotente. Uso: python3 scripts/mapas/gruta-inverter.py"""
import json, re
from pathlib import Path
from PIL import Image
R = Path(__file__).resolve().parents[2] / "public/assets/mapas"
txt = (R / "gruta.json").read_text()
m = json.loads(txt); w, h = m["w"], m["h"]
px = Image.open(R / "gruta.png").convert("RGB").load()
escuros = {(82, 62, 72), (48, 44, 50), (34, 26, 39)}
novo = "".join("0" if sum(1 for py in range(16) for qx in range(16) if px[x*16+qx, y*16+py] in escuros) >= 30 else "1" for y in range(h) for x in range(w))
txt = txt.replace(m["solido"], novo)
def troca(t, a, b):
    return t if b in t else (t.replace(a, b) if a in t else (_ for _ in ()).throw(SystemExit(f"não achei: {a}")))
txt = troca(txt, '"x":20,"y":39,"w":1,"h":1,"dest":"obsidiana"', '"x":10,"y":15,"w":1,"h":1,"dest":"obsidiana"')
txt = troca(txt, '"x":0,"y":0,"w":1,"h":1,"dest":"cromatica"', '"x":24,"y":1,"w":1,"h":1,"dest":"cromatica"')
txt = troca(txt, '"id":"cristal","tipo":"casa","nome":"Cristal Refratário","x":0,"y":3', '"id":"cristal","tipo":"casa","nome":"Cristal Refratário","x":6,"y":5')
if '"escuro"' not in txt:
    txt = txt.replace('"bioma":', '"escuro":true,"bioma":', 1)
(R / "gruta.json").write_text(txt)
for mapa, a, b in (("obsidiana", '"dest":"gruta","dx":20,"dy":38', '"dest":"gruta","dx":10,"dy":16'), ("cromatica", '"dest":"gruta","dx":0,"dy":1', '"dest":"gruta","dx":24,"dy":2')):
    t = (R / f"{mapa}.json").read_text()
    (R / f"{mapa}.json").write_text(troca(t, a, b))
print("ok")
