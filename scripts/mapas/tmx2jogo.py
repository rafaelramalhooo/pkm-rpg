#!/usr/bin/env python3
"""Gera os arquivos do jogo (id.png, id-cima.png, id.json) a partir de um mapa Tiled do Tuxemon.
Uso: python3 scripts/mapas/tmx2jogo.py <id> [--dir-tuxemon CAMINHO] [--saida PASTA]
Receita: scripts/mapas/fontes/<id>.meta.json
  tmx        nome do mapa Tuxemon (sem .tmx)
  limpar     [[x,y,w,h]...]  remove decoração (tudo acima da 1ª camada) nessas áreas e libera a colisão
  solidos    [[x,y,w,h]...]  força colisão
  livres     [[x,y,w,h]...]  força passagem
  portais    lista de portais do jogo (x,y,w,h,dest,dx,dy,dir)
  pois       "herdar" (mantém os do json atual) ou lista nova
Campos não citados (bioma, níveis, grama...) são herdados do json atual do mapa. Idempotente."""
import colorsys, json, sys, os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import tmx as TMX
from PIL import Image

RAIZ = Path(__file__).resolve().parents[2]
T = 16

def main():
    args = sys.argv[1:]
    mid = args[0]
    tux = Path(os.environ.get("TUXEMON_DIR", "/tmp/tux/mods/tuxemon")) if "--dir-tuxemon" not in args else Path(args[args.index("--dir-tuxemon") + 1])
    saida = Path(args[args.index("--saida") + 1]) if "--saida" in args else RAIZ / "public/assets/mapas"
    meta = json.loads((Path(__file__).parent / "fontes" / f"{mid}.meta.json").read_text())
    atual = json.loads((saida / f"{mid}.json").read_text()) if (saida / f"{mid}.json").exists() else {}
    r = TMX.carregar_tmx(tux / "maps" / f"{meta['tmx']}.tmx", limpar=meta.get("limpar", []))
    if meta.get("margem"):   # acrescenta faixas laterais (andáveis, com borda de árvores) copiadas de um mapa antigo guardado em fontes/
        mg = meta["margem"]; e, d_ = mg.get("esq", 0), mg.get("dir", 0)
        ant = json.loads((Path(__file__).parent / "fontes" / f"{mg['antigo']}.json").read_text())
        ab = Image.open(Path(__file__).parent / "fontes" / f"{mg['antigo']}.png").convert("RGBA"); ac = Image.open(Path(__file__).parent / "fontes" / f"{mg['antigo']}-cima.png").convert("RGBA")
        W0, H0 = r["w"], r["h"]; W1 = W0 + e + d_; AW = ant["w"]
        nb = Image.new("RGBA", (W1 * T, H0 * T)); nc = Image.new("RGBA", (W1 * T, H0 * T))
        nb.paste(r["base"], (e * T, 0)); nc.paste(r["cima"], (e * T, 0))
        ns = [False] * (W1 * H0); ng = [False] * (W1 * H0)
        for y in range(H0):
            for x in range(W0):
                ns[y * W1 + x + e] = bool(r["solido"][y * W0 + x]); ng[y * W1 + x + e] = bool(r["grama"][y * W0 + x]) if any(r["grama"]) else False
        for ox, ax, n in ((0, 0, e), (e + W0, AW - d_, d_)):
            if n:
                box = (ax * T, 0, (ax + n) * T, H0 * T)
                nb.paste(ab.crop(box), (ox * T, 0)); nc.paste(ac.crop(box), (ox * T, 0))
                for y in range(H0):
                    for x in range(n):
                        ns[y * W1 + ox + x] = ant["solido"][y * AW + ax + x] == "1"; ng[y * W1 + ox + x] = ant["grama"][y * AW + ax + x] == "1"
        r = {"w": W1, "h": H0, "base": nb, "cima": nc, "solido": ns, "grama": ng}
    w, h = r["w"], r["h"]
    sol = list(r["solido"])
    def retangulos(chave, valor):
        for x, y, rw, rh in meta.get(chave, []):
            for ty in range(y, y + rh):
                for tx in range(x, x + rw):
                    if 0 <= tx < w and 0 <= ty < h: sol[ty * w + tx] = valor
    retangulos("solidos", True); retangulos("livres", False); retangulos("solidos_depois", True)
    # remendos de pixels: "colar" copia um trecho (base, cima e sólidos) de outro mapa Tuxemon; "grama" cobre áreas com o tile de grama mais comum
    if meta.get("grama_em"):
        from collections import Counter
        cont = Counter()
        for y in range(h):
            for x in range(w):
                if r["grama"][y * w + x] if any(r["grama"]) else False: cont[r["base"].crop((x*T, y*T, x*T+T, y*T+T)).tobytes()] += 1
        if not cont:
            for y in range(h):
                for x in range(w):
                    if not sol[y * w + x]: cont[r["base"].crop((x*T, y*T, x*T+T, y*T+T)).tobytes()] += 1
        gt = Image.frombytes("RGBA", (T, T), cont.most_common(1)[0][0])
        for x0, y0, rw, rh in meta["grama_em"]:
            for y in range(y0, y0 + rh):
                for x in range(x0, x0 + rw):
                    r["base"].paste(gt, (x * T, y * T)); r["cima"].paste((0, 0, 0, 0), (x * T, y * T, x * T + T, y * T + T)); sol[y * w + x] = False
    for c in meta.get("colar", []):
        if "png" in c:   # trecho de uma imagem antiga guardada em fontes/ (sem colisão: o trecho colado fica andável)
            o = {"base": Image.open(Path(__file__).parent / "fontes" / f"{c['png']}.png").convert("RGBA"), "cima": Image.open(Path(__file__).parent / "fontes" / f"{c['png']}-cima.png").convert("RGBA"), "w": w, "solido": [False] * (w * h)}
        else:
            o = TMX.carregar_tmx(tux / "maps" / f"{c['tmx']}.tmx")
        sx, sy, sw, sh = c["de"]; dx, dy = c["para"]
        if c.get("sem_chao"):   # cola só o desenho (cores do chão do trecho viram transparentes), para não deixar "retângulo" de cor diferente
            for chave in ("base", "cima"):
                rec = o[chave].crop((sx * T, sy * T, (sx + sw) * T, (sy + sh) * T)).convert("RGBA")
                px = rec.load()
                for yy in range(rec.height):
                    for xx in range(rec.width):
                        rr, gg, bb, aa = px[xx, yy]
                        if aa and max(rr, gg, bb) - min(rr, gg, bb) < c.get("sat_max", 45) and rr >= bb and 110 <= rr <= 200: px[xx, yy] = (0, 0, 0, 0)   # tons acinzentados do chão
                r[chave].alpha_composite(rec, (dx * T, dy * T))
            continue
        for j in range(sh):
            for i in range(sw):
                a, b = sx + i, sy + j; x, y = dx + i, dy + j
                if not (0 <= x < w and 0 <= y < h): continue
                box = (a * T, b * T, a * T + T, b * T + T)
                r["base"].paste(o["base"].crop(box), (x * T, y * T)); r["cima"].paste(o["cima"].crop(box), (x * T, y * T))
                if not c.get("sem_sol"): sol[y * w + x] = bool(o["solido"][b * o["w"] + a])
    for e in meta.get("estender", []):   # prolonga um caminho copiando um trecho reto REAL do próprio mapa (com bordas), repetido n vezes
        mx, my, mw, mh = e["modelo"]; dx, dy = e["para"]; n = e.get("rep", 1); passo = (mw, 0) if e.get("dir", "v") == "h" else (0, mh)
        base0 = r["base"].copy(); cima0 = r["cima"].copy(); sol0 = list(sol)
        for k in range(n):
            for j in range(mh):
                for i in range(mw):
                    a, b = mx + i, my + j; x, y = dx + i + passo[0] * k, dy + j + passo[1] * k
                    if not (0 <= x < w and 0 <= y < h): continue
                    box = (a * T, b * T, a * T + T, b * T + T)
                    r["base"].paste(base0.crop(box), (x * T, y * T)); r["cima"].paste(cima0.crop(box), (x * T, y * T)); sol[y * w + x] = sol0[b * w + a]
    # bolsões andáveis que nenhum portal alcança (telhados, cantos cercados) viram sólidos, salvo se tiverem um ponto de interesse
    pois = meta["pois"] if meta.get("pois", "herdar") != "herdar" else atual.get("pois", [])
    visto = set(); fila = []
    for p in meta["portais"]:
        for ty in range(p["y"], p["y"] + p.get("h", 1)):
            for tx in range(p["x"], p["x"] + p.get("w", 1)):
                if 0 <= tx < w and 0 <= ty < h and not sol[ty * w + tx] and (tx, ty) not in visto: visto.add((tx, ty)); fila.append((tx, ty))
    for a, b in fila:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (a + dx, b + dy)
            if 0 <= n[0] < w and 0 <= n[1] < h and not sol[n[1] * w + n[0]] and n not in visto: visto.add(n); fila.append(n)
    sobra = {(x, y) for y in range(h) for x in range(w) if not sol[y * w + x] and (x, y) not in visto}
    poi_em = {(q["x"], q["y"]) for q in pois}
    resto = set(sobra); fechados = 0
    while resto:
        ini = resto.pop(); comp = [ini]
        for a, b in comp:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (a + dx, b + dy)
                if n in resto: resto.discard(n); comp.append(n)
        if len(comp) <= 60 and not any(c in poi_em for c in comp):
            for x, y in comp: sol[y * w + x] = True
            fechados += len(comp)
    grama = r["grama"] if any(r["grama"]) else (list(c == "1" for c in atual["grama"]) if len(atual.get("grama", "")) == w * h else [False] * (w * h))
    for x0, y0, rw, rh in meta.get("grama_marcar", []):   # áreas de mato (encontros selvagens)
        for y in range(y0, y0 + rh):
            for x in range(x0, x0 + rw): grama[y * w + x] = True
    out = dict(atual)
    out.update({"id": mid, "nome": atual.get("nome", meta.get("nome", mid)), "w": w, "h": h,
                "solido": "".join("1" if s else "0" for s in sol), "grama": "".join("1" if g else "0" for g in grama)})
    if len(out.get("bioma", "")) != w * h:
        out["bioma"] = (out.get("bioma", "G") or "G")[0] * (w * h)
    out["portais"] = meta["portais"]
    if meta.get("pois", "herdar") != "herdar": out["pois"] = meta["pois"]
    for t in meta.get("tinta", []):   # identidade de cor da cidade: gira o matiz dos tons quentes (telhados) dentro de áreas escolhidas
        x0, y0, rw, rh = t["rect"]
        for img in (r["base"], r["cima"]):
            px = img.load()
            for yy in range(y0 * T, (y0 + rh) * T):
                for xx in range(x0 * T, (x0 + rw) * T):
                    rr, gg, bb, aa = px[xx, yy]
                    if aa == 0: continue
                    hh, ss, vv = colorsys.rgb_to_hsv(rr / 255, gg / 255, bb / 255)
                    if ss > t.get('smin', 0.2) and vv >= t.get('vmin', 0) and vv <= t.get('vmax', 1) and ((t['faixa'][0] <= hh * 360 <= t['faixa'][1]) if 'faixa' in t else (hh < 50 / 360 or hh > 330 / 360)):
                        nr, ng, nb = colorsys.hsv_to_rgb(((t['matiz'] / 360) if 'matiz' in t else (hh + t['delta'] / 360)) % 1, min(1, ss * t.get('dessat', 1)), min(1, vv * t.get('brilho', 1)))
                        px[xx, yy] = (round(nr * 255), round(ng * 255), round(nb * 255), aa)
    if meta.get("trilha"):   # trilhas de areia: boca de 1 tile em cada portal + caminho de 1 tile até um ponto já existente (A* ao redor de obstáculos)
        tr = meta["trilha"]; AR = tuple(tr.get("areia", (216, 200, 128))); BO = tuple(tr.get("borda", (196, 160, 120))); HA = tuple(tr.get("halo", (112, 192, 160)))
        evitar = tr.get("evitar", []); pintar = set()
        def evita(x, y): return any(a <= x < a + c and b <= y < b + d for a, b, c, d in evitar)
        import heapq
        def rota(ini, fim):
            pq = [(0, 0, ini, None, None)]; dist = {}; pai = {}; cnt = 0
            while pq:
                c0, _, cur, dr, par = heapq.heappop(pq)
                if (cur, dr) in dist: continue
                dist[(cur, dr)] = c0; pai[(cur, dr)] = par
                if cur == fim:
                    out2 = []; k = (cur, dr)
                    while k is not None: out2.append(k[0]); k = pai[k]
                    return out2
                for d2 in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    n = (cur[0] + d2[0], cur[1] + d2[1])
                    if not (0 <= n[0] < w and 0 <= n[1] < h) or sol[n[1] * w + n[0]] or evita(*n) or (n, d2) in dist: continue
                    cnt += 1; heapq.heappush(pq, (c0 + 1 + (0 if dr in (None, d2) else 0.6), cnt, n, d2, (cur, dr)))
            return []
        for lig in tr.get("ligar", []):
            for tx, ty in rota(tuple(lig["de"]), tuple(lig["a"])): pintar.add((tx, ty))
        for p0 in meta["portais"]:
            if p0["dest"] in tr.get("portais", []):
                for ty in range(p0["y"], p0["y"] + p0.get("h", 1)):
                    for tx in range(p0["x"], p0["x"] + p0.get("w", 1)): pintar.add((tx, ty))
        base = r["base"]; px = base.load(); W2, H2 = w * T, h * T
        verde = lambda c: c[1] > c[0] + 30 and c[1] > c[2] + 20
        portal_t = {(tx, ty) for p0 in meta["portais"] if p0["dest"] in tr.get("portais", []) for ty in range(p0["y"], p0["y"] + p0.get("h", 1)) for tx in range(p0["x"], p0["x"] + p0.get("w", 1))}
        def so_grama(t): return sum(1 for yy in range(t[1] * T, t[1] * T + T) for xx in range(t[0] * T, t[0] * T + T) if verde(px[xx, yy][:3])) >= 128   # não pinta por cima de pedra, ponte, prédio ou areia já existente
        pintar = {t for t in pintar if not sol[t[1] * w + t[0]] and not evita(*t) and (t in portal_t or tr.get("qualquer") or so_grama(t))}
        massa = [[False] * H2 for _ in range(W2)]
        for tx, ty in pintar:
            for yy in range(ty * T, ty * T + T):
                for xx in range(tx * T, tx * T + T): massa[xx][yy] = True
        for xx in range(W2):
            for yy in range(H2):
                if massa[xx][yy]: continue
                dmin = 99
                for ddx in range(-4, 5):
                    for ddy in range(-4, 5):
                        a, b = xx + ddx, yy + ddy
                        if 0 <= a < W2 and 0 <= b < H2 and massa[a][b]: dmin = min(dmin, max(abs(ddx), abs(ddy)))
                if dmin <= 4 and verde(px[xx, yy][:3]): px[xx, yy] = (BO if dmin == 1 else HA) + (255,)
        for tx, ty in pintar:
            base.paste(Image.new("RGBA", (T, T), AR + (255,)), (tx * T, ty * T)); r["cima"].paste((0, 0, 0, 0), (tx * T, ty * T, tx * T + T, ty * T + T))
            grama[ty * w + tx] = False
        out["grama"] = "".join("1" if g else "0" for g in grama)
        print("trilha:", len(pintar), "tiles")
    r["base"].save(saida / f"{mid}.png"); r["cima"].save(saida / f"{mid}-cima.png")
    (saida / f"{mid}.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"{mid}: {w}x{h}, {sum(sol)} tiles sólidos ({fechados} de bolsões fechados)")

main()
