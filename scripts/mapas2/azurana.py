#!/usr/bin/env python3
"""Azurana v2 (rascunho 1). Saida em scripts/mapas2/saida/ -- NAO toca public/."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from pecas import Mapa, T

W = H = 40
m = Mapa(W, H, semente=7)
m.grama()
# --- trilhas (blob autotile; larguras >= 3) ---
m.trilha([
    (31, 0, 3, 35),      # espinha leste: da saida norte (rota7a) ate a avenida sul
    (3, 12, 3, 23),      # espinha oeste (fecha o circuito)
    (3, 12, 31, 3),      # avenida 1
    (3, 22, 31, 3),      # avenida 2
    (3, 32, 31, 3),      # avenida 3
    (8, 32, 5, 8),       # saida sul (costa1)
])
# --- predios: (nome, x, y, poi_id) ---
lista = [
    ("centro", 7, 8, "centro"), ("mart", 13, 8, "mart"), ("casa_madeira_b", 19, 8, "capitania"),
    ("lab_branco", 7, 18, "escola"), ("ginasio_cinza", 15, 17, "GINASIO"), ("predio_cinza", 21, 17, "aquario"),
    ("casa_escura", 7, 27, "armazem"), ("casa_madeira_a", 14, 27, "pescador"),
    ("casa_grande", 19, 27, "cabana1"), ("casa_pagode", 25, 27, "cabana2"),
]
portas = {}
for nome, x, y, pid in lista:
    portas[pid] = m.predio(x, y, nome)
# --- decoracao ---
m.borda_arvores(aberturas=[(31, 0, 3, 2), (8, 38, 5, 2)])
# canteiros de flores ao lado de cada porta
for pid, (px, py) in portas.items():
    for dx in (-2, 2):
        for dy in (0, -1):
            m.flor(px + dx, py + dy)
m.enche_arvores((25, 4, 6, 8), passo=3, prob=0.8)
m.enche_arvores((12, 16, 3, 5), passo=3, prob=0.9)
m.enche_arvores((26, 15, 5, 6), passo=3, prob=0.7)
m.enche_arvores((26, 17, 5, 6), passo=3, prob=0.6)
m.enche_arvores((35, 3, 3, 32), passo=3, prob=0.5)
m.enche_arvores((14, 36, 17, 2), passo=3, prob=0.5)
for _ in range(60):
    m.flor(m.rng.randrange(2, W - 2), m.rng.randrange(2, H - 2))

saida = os.path.join(os.path.dirname(__file__), "saida")
m.base.save(f"{saida}/azurana.png"); m.cima.save(f"{saida}/azurana-cima.png")
# --- json no formato do jogo (portais e pois reaproveitados do mapa atual) ---
ant = json.load(open(os.path.expanduser("~/mnt/pkm-rpg/public/assets/mapas/azurana.json")))
pois = []
for p in ant["pois"]:
    x, y = portas[p["id"]]
    pois.append({**p, "x": x, "y": y})
gx, gy = portas["GINASIO"]
portais = [{**q, "x": gx, "y": gy} if q["dest"] == "gin_azurana" else q for q in ant["portais"]]
j = {**ant, "w": W, "h": H, "solido": "".join("1" if s else "0" for s in m.sol), "grama": "0" * (W * H), "portais": portais, "pois": pois}
json.dump(j, open(f"{saida}/azurana.json", "w"), ensure_ascii=False, separators=(",", ":"))
# --- preview ---
from PIL import ImageDraw
im = m.base.copy(); im.alpha_composite(m.cima)
d = ImageDraw.Draw(im)
for p in pois: d.rectangle((p["x"]*T, p["y"]*T, p["x"]*T+T-1, p["y"]*T+T-1), outline=(255, 255, 0, 255), width=2)
for q in portais: d.rectangle((q["x"]*T, q["y"]*T, (q["x"]+q.get("w",1))*T-1, (q["y"]+q.get("h",1))*T-1), outline=(0, 160, 255, 255), width=2)
im = im.resize((im.width*2, im.height*2), 0); im.save(os.path.expanduser("~/mnt/referencias/v2_azurana_r1.png"))
print("ok", len(pois), "pois")
