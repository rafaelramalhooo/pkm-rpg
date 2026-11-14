#!/usr/bin/env python3
"""Mapas v2: motor de pecas (tile a tile) sobre os tilesets do Tuxemon (CC-BY-SA 4.0).

O mapa e uma grade de tiles; cada coisa (trilha, arvore, cerca) e montada por REGRAS,
entao nao existe "peca cortada" por construcao. Saida: PNG base, PNG "cima" e grade de solidos.
Uso: from pecas import Mapa
"""
import os, random
from pathlib import Path
from PIL import Image

T = 16
TUX = Path(os.environ.get("TUXEMON_DIR", "/tmp/tux/mods/tuxemon")) / "gfx" / "tilesets"
_cache_ts, _cache_tile = {}, {}


def tile(ts, c, r):
    k = (ts, c, r)
    if k not in _cache_tile:
        if ts not in _cache_ts:
            _cache_ts[ts] = Image.open(TUX / ts).convert("RGBA")
        _cache_tile[k] = _cache_ts[ts].crop((c * T, r * T, c * T + T, r * T + T))
    return _cache_tile[k]


CO = "core_outdoor.png"

# autotile da trilha de areia sobre grama (bloco 0,0 de core_outdoor)
# 3x3 do "blob": colunas 5..7, linhas 3..5. Miolo = (6,4). Cantos internos em (6..7, 6..7).
BLOB = {
    "TL": (5, 3), "T": (6, 3), "TR": (7, 3),
    "L": (5, 4), "C": (6, 4), "R": (7, 4),
    "BL": (5, 5), "B": (6, 5), "BR": (7, 5),
}
INNER = {"SE": (6, 6), "SW": (7, 6), "NE": (6, 7), "NW": (7, 7)}  # onde falta a diagonal

GRAMA_LISA = [(0, 3), (1, 3), (2, 3)]


class Mapa:
    def __init__(self, w, h, semente=1):
        self.w, self.h = w, h
        self.rng = random.Random(semente)
        self.base = Image.new("RGBA", (w * T, h * T), (0, 0, 0, 0))
        self.cima = Image.new("RGBA", (w * T, h * T), (0, 0, 0, 0))
        self.sol = [False] * (w * h)
        self.ocupado = [False] * (w * h)
        self.M_trilha = None

    def poe(self, x, y, ts, c, r, camada="base"):
        img = self.base if camada == "base" else self.cima
        img.alpha_composite(tile(ts, c, r), (x * T, y * T))

    def solido(self, x, y, v=True):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.sol[y * self.w + x] = v

    def grama(self):
        for y in range(self.h):
            for x in range(self.w):
                c, r = (1, 3) if self.rng.random() < 0.8 else self.rng.choice(GRAMA_LISA)
                self.poe(x, y, CO, c, r)

    def trilha(self, retangulos):
        """Retangulos (x,y,w,h) de trilha, cada um com w,h >= 3. Celulas fora do mapa copiam a
        vizinha de dentro (a trilha continua alem da borda)."""
        M = [[False] * self.w for _ in range(self.h)]
        for (x0, y0, ww, hh) in retangulos:
            assert ww >= 3 and hh >= 3, "trilha precisa de pelo menos 3x3"
            for y in range(y0, y0 + hh):
                for x in range(x0, x0 + ww):
                    if 0 <= x < self.w and 0 <= y < self.h:
                        M[y][x] = True

        def m(x, y):
            x = min(max(x, 0), self.w - 1); y = min(max(y, 0), self.h - 1)
            return M[y][x]

        for y in range(self.h):
            for x in range(self.w):
                if not M[y][x]:
                    continue
                n, s, w_, e = m(x, y - 1), m(x, y + 1), m(x - 1, y), m(x + 1, y)
                if n and s and w_ and e:
                    falta = [k for k, (dx, dy) in {"NW": (-1, -1), "NE": (1, -1), "SW": (-1, 1), "SE": (1, 1)}.items() if not m(x + dx, y + dy)]
                    peca = INNER[falta[0]] if falta else BLOB["C"]
                else:
                    v = ("T" if not n else "B" if not s else "") + ("L" if not w_ else "R" if not e else "")
                    peca = BLOB[v or "C"]
                self.poe(x, y, CO, *peca)
        self.M_trilha = M

    ARVORE = (28, 35)

    def arvore(self, x, y, c=None, r=None):
        c = self.ARVORE[0] if c is None else c
        r = self.ARVORE[1] if r is None else r
        if not (0 <= x and x + 1 < self.w and 0 <= y and y + 1 < self.h):
            return False
        for dy in range(2):
            for dx in range(2):
                self.poe(x + dx, y + dy, CO, c + dx, r + dy, "base")
                if dy == 0:
                    self.poe(x + dx, y + dy, CO, c + dx, r + dy, "cima")
                self.solido(x + dx, y + dy)
                self.ocupado[(y + dy) * self.w + x + dx] = True
        return True

    def livre(self, x, y, ww=2, hh=2):
        for yy in range(y, y + hh):
            for xx in range(x, x + ww):
                if not (0 <= xx < self.w and 0 <= yy < self.h) or self.ocupado[yy * self.w + xx]:
                    return False
                if self.M_trilha and self.M_trilha[yy][xx]:
                    return False
        return True

    def borda_arvores(self, aberturas=()):
        """Moldura de arvores 2x2 (espessura 2) em volta do mapa; 'aberturas' = (x,y,w,h) sem arvore."""
        def aberto(x, y):
            return any(ax <= x < ax + aw and ay <= y < ay + ah for (ax, ay, aw, ah) in aberturas)

        def tenta(x, y):
            if self.livre(x, y) and not any(aberto(x + i, y + j) for i in range(2) for j in range(2)):
                self.arvore(x, y)
        for x in range(0, self.w - 1, 2):
            tenta(x, 0); tenta(x, self.h - 2)
        for y in range(2, self.h - 2, 2):
            tenta(0, y); tenta(self.w - 2, y)

    def png(self, caminho, com_cima=True, solidos=False, escala=2):
        im = self.base.copy()
        if com_cima:
            im.alpha_composite(self.cima)
        if solidos:
            from PIL import ImageDraw
            d = ImageDraw.Draw(im)
            for y in range(self.h):
                for x in range(self.w):
                    if self.sol[y * self.w + x]:
                        d.rectangle((x * T, y * T, x * T + T - 1, y * T + T - 1), outline=(255, 0, 0, 255))
        if escala != 1:
            im = im.resize((im.width * escala, im.height * escala), Image.NEAREST)
        Path(caminho).parent.mkdir(parents=True, exist_ok=True)
        im.save(caminho)


# ---------- prédios (Kelvin Shadewing, CC-BY-SA) ----------
KV = "Outdoor_Tiles_-_City_and_Country_-_by_Kelvin_Shadewing.png"
# nome: (col, linha, largura, altura, coluna_da_porta_relativa)  -- porta sempre na ultima linha
PREDIOS = {
    "centro": (0, 5, 5, 4, 2), "mart": (5, 5, 5, 4, 2), "casa_escura": (10, 5, 6, 4, 4),
    "casa_madeira_a": (0, 9, 4, 4, 2), "casa_pagode": (4, 9, 5, 4, 3), "casa_madeira_b": (9, 9, 5, 4, 3),
    "lab_branco": (0, 13, 5, 4, 2), "ginasio_cinza": (5, 13, 5, 4, 2), "casa_grande": (10, 13, 5, 4, 3),
    "predio_cinza": (0, 17, 5, 4, 2),
}
FLORES = [(6, 0), (7, 0), (4, 2), (3, 2)]


def _predio(self, x, y, nome):
    c, r, ww, hh, pd = PREDIOS[nome]
    assert 0 <= x and x + ww <= self.w and 0 <= y and y + hh <= self.h, f"{nome} fora do mapa"
    for dy in range(hh):
        for dx in range(ww):
            assert not self.ocupado[(y + dy) * self.w + x + dx], f"{nome} sobrepoe algo em {(x+dx, y+dy)}"
            self.poe(x + dx, y + dy, KV, c + dx, r + dy)
            self.ocupado[(y + dy) * self.w + x + dx] = True
            self.solido(x + dx, y + dy, not (dy == hh - 1 and dx == pd))
    return (x + pd, y + hh - 1)  # tile da porta (caminhavel)


def _flor(self, x, y):
    if self.livre(x, y, 1, 1):
        c, r = self.rng.choice(FLORES)
        self.poe(x, y, CO, c, r)


def _reservar(self, x, y, ww, hh):
    for yy in range(y, y + hh):
        for xx in range(x, x + ww):
            if 0 <= xx < self.w and 0 <= yy < self.h:
                self.ocupado[yy * self.w + xx] = True


def _enche_arvores(self, area, passo=3, prob=0.55, margem=1):
    """Arvores 2x2 espalhadas numa area (x,y,w,h), longe de trilha e predios (margem em tiles)."""
    ax, ay, aw, ah = area
    for y in range(ay, ay + ah - 1, 2):
        for x in range(ax, ax + aw - 1, passo):
            if self.rng.random() > prob:
                continue
            if self.livre(x - margem, y - margem, 2 + 2 * margem, 2 + 2 * margem) or self.livre(x, y):
                if self._sem_vizinho(x, y, margem):
                    self.arvore(x, y)


def _sem_vizinho(self, x, y, margem):
    for yy in range(y - margem, y + 2 + margem):
        for xx in range(x - margem, x + 2 + margem):
            if 0 <= xx < self.w and 0 <= yy < self.h:
                if self.ocupado[yy * self.w + xx]:
                    return False
                if self.M_trilha and self.M_trilha[yy][xx]:
                    return False
    return True


Mapa.predio = _predio
Mapa.flor = _flor
Mapa.reservar = _reservar
Mapa.enche_arvores = _enche_arvores
Mapa._sem_vizinho = _sem_vizinho
