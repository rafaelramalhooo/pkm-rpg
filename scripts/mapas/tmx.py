#!/usr/bin/env python3
"""Leitor de mapas Tiled (.tmx) do Tuxemon (CC-BY-SA 4.0, ver docs/CREDITOS-TUXEMON.md).
Renderiza as camadas (base e "Above Player"), calcula a colisão e a grama a partir dos objetos do mapa.
Uso como biblioteca: from tmx import carregar_tmx ; r = carregar_tmx(caminho_tmx)"""
import base64, zlib, struct, xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image, ImageDraw

T = 16
FH, FV, FD = 0x80000000, 0x40000000, 0x20000000

class Tileset:
    def __init__(self, firstgid, r, pasta: Path):
        self.first = firstgid
        self.cols = int(r.get("columns")); self.count = int(r.get("tilecount"))
        self.margin = int(r.get("margin", 0)); self.spacing = int(r.get("spacing", 0))
        self.img = Image.open(pasta / r.find("image").get("source")).convert("RGBA")
        # tiles que bloqueiam: água ("surfable") e saltos de barranco ("hop")
        self.bloqueia = {int(t.get("id")) for t in r.findall("tile")
                         if any(p.get("name") in ("surfable", "hop") for p in t.findall("properties/property"))}
        self._cache = {}
    def tile(self, local):
        if local not in self._cache:
            c, l = local % self.cols, local // self.cols
            x = self.margin + c * (T + self.spacing); y = self.margin + l * (T + self.spacing)
            self._cache[local] = self.img.crop((x, y, x + T, y + T))
        return self._cache[local]

def _camada(el, w, h):
    d = el.find("data")
    raw = d.text.strip()
    if d.get("encoding") == "base64":
        b = base64.b64decode(raw)
        if d.get("compression") == "zlib": b = zlib.decompress(b)
        return list(struct.unpack(f"<{w*h}I", b))
    return [int(v) for v in raw.replace("\n", "").split(",") if v != ""]

def _poligono_para_grade(pts, sol, w, h):
    im = Image.new("1", (w * T, h * T), 0)
    ImageDraw.Draw(im).polygon(pts, fill=1)
    px = im.load()
    for ty in range(h):
        for tx in range(w):
            n = sum(1 for y in range(ty * T, ty * T + T, 4) for x in range(tx * T, tx * T + T, 4) if px[x, y])
            if n >= 6: sol[ty * w + tx] = True

def carregar_tmx(caminho, limpar=()):
    caminho = Path(caminho)
    raiz = ET.parse(caminho).getroot()
    w, h = int(raiz.get("width")), int(raiz.get("height"))
    tilesets = []
    for ts in raiz.findall("tileset"):
        if ts.get("source"):
            tsx = (caminho.parent / ts.get("source")).resolve()
            tilesets.append(Tileset(int(ts.get("firstgid")), ET.parse(tsx).getroot(), tsx.parent))
        else:
            tilesets.append(Tileset(int(ts.get("firstgid")), ts, caminho.parent.resolve()))
    tilesets.sort(key=lambda t: -t.first)
    def tile_de(gid):
        g = gid & 0x1FFFFFFF
        for t in tilesets:
            if g >= t.first:
                im = t.tile(g - t.first)
                if gid & FD: im = im.transpose(Image.TRANSPOSE)
                if gid & FH: im = im.transpose(Image.FLIP_LEFT_RIGHT)
                if gid & FV: im = im.transpose(Image.FLIP_TOP_BOTTOM)
                return im
        return None
    def bloqueia(gid):
        g = gid & 0x1FFFFFFF
        for t in tilesets:
            if g >= t.first: return (g - t.first) in t.bloqueia
        return False
    base = Image.new("RGBA", (w * T, h * T), (0, 0, 0, 0)); cima = base.copy()
    agua = [False] * (w * h)
    vazio = set()   # tiles "limpos": só a 1ª camada (chão) permanece
    for x0, y0, rw, rh in limpar:
        for ty in range(y0, y0 + rh):
            for tx in range(x0, x0 + rw): vazio.add(ty * w + tx)
    for n_camada, el in enumerate(raiz.findall("layer")):
        gids = _camada(el, w, h)
        if n_camada > 0 or "above" in el.get("name", "").lower():
            gids = [0 if i in vazio else g for i, g in enumerate(gids)]
        acima = "above" in el.get("name", "").lower()
        alvo = cima if acima else base
        for i, gid in enumerate(gids):
            if gid & 0x1FFFFFFF:
                t = tile_de(gid)
                if t: alvo.alpha_composite(t, ((i % w) * T, (i // w) * T))
                if not acima: agua[i] = bloqueia(gid)   # uma camada de cima (ponte, chão) sobre a água libera o tile
    sol = list(agua)
    grama = [False] * (w * h); eventos = []
    for og in raiz.findall("objectgroup"):
        for o in og.findall("object"):
            x, y = float(o.get("x", 0)), float(o.get("y", 0)); ow, oh = float(o.get("width", 0)), float(o.get("height", 0))
            tipo = o.get("type", ""); nome = o.get("name", "")
            props = {p.get("name"): p.get("value") for p in o.findall("properties/property")}
            if tipo == "collision":
                poly = o.find("polygon")
                if poly is not None:
                    pts = [(x + float(a), y + float(b)) for a, b in (p.split(",") for p in poly.get("points").split())]
                    _poligono_para_grade(pts, sol, w, h)
                else:
                    for ty in range(int(y // T), int(-(-(y + oh) // T))):
                        for tx in range(int(x // T), int(-(-(x + ow) // T))):
                            if 0 <= tx < w and 0 <= ty < h: sol[ty * w + tx] = True
            elif tipo == "event":
                eventos.append({"nome": nome, "x": x, "y": y, "w": ow, "h": oh, "props": props})
                if any(str(v).startswith("random_encounter") for v in props.values()):
                    for ty in range(int(y // T), int(-(-(y + oh) // T))):
                        for tx in range(int(x // T), int(-(-(x + ow) // T))):
                            if 0 <= tx < w and 0 <= ty < h: grama[ty * w + tx] = True
    for i in vazio: sol[i] = agua[i]   # áreas limpas voltam a ser só chão
    return {"w": w, "h": h, "base": base, "cima": cima, "solido": sol, "grama": grama, "eventos": eventos, "props": {p.get("name"): p.get("value") for p in raiz.findall("properties/property")}}

if __name__ == "__main__":
    import sys
    r = carregar_tmx(sys.argv[1])
    out = r["base"].copy(); out.alpha_composite(r["cima"])
    d = ImageDraw.Draw(out, "RGBA")
    for i, s in enumerate(r["solido"]):
        if s: d.rectangle(((i % r["w"]) * T, (i // r["w"]) * T, (i % r["w"]) * T + 15, (i // r["w"]) * T + 15), outline=(255, 0, 0, 90))
    out.save(sys.argv[2]); print(r["w"], r["h"], sum(r["solido"]), sum(r["grama"]))
