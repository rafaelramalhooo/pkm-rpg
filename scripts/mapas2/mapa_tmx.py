"""Motor novo: o mapa e um arquivo do Tiled (.tmx) feito so de tiles, em camadas.
Camadas: chao, trilha, objetos, cima (desenhada por cima do jogador), colisao (marcador). Objetos: portais e pontos."""
import os, json, shutil
import xml.etree.ElementTree as ET
from PIL import Image
import pecas
from pecas import Mapa, CO, KV, T, TUX
CC = "core_city_and_country.png"
AGUA = pecas.AGUA

class TMapa(Mapa):
    def __init__(self, w, h, semente=1):
        super().__init__(w, h, semente)
        self.cam = {k: {} for k in ('chao', 'trilha', 'agua', 'objetos', 'sobre', 'cima')}
        self._atual = 'chao'
    def poe(self, x, y, ts, c, r, camada="base"):
        super().poe(x, y, ts, c, r, camada)   # mantem registros (flores, pedras, pinheiros)
        if not (0 <= x < self.w and 0 <= y < self.h): return
        if camada != 'base': nome = 'cima'
        else: nome = self._atual
        if ts == AGUA and (c, r) in pecas.AGUA_FILL: nome = 'agua'
        d = self.cam[nome]
        if (x, y) in d and d[(x, y)] != (ts, c, r):
            raise AssertionError(f'dois tiles na camada {nome} em ({x},{y}): {d[(x,y)]} e {(ts,c,r)}')
        d[(x, y)] = (ts, c, r)
    def grama(self):
        self._atual = 'chao'; super().grama(); self._atual = 'objetos'
    def trilha(self, ret):
        self._atual = 'trilha'; super().trilha(ret); self._atual = 'objetos'

def _gids(m):
    ts = []
    for d in m.cam.values():
        for (t, c, r) in d.values():
            if t not in ts: ts.append(t)
    return ts

def salvar_tmx(m, caminho, portais, pois, spawn=None, extras=None):
    pasta = os.path.dirname(caminho); os.makedirs(pasta + '/tilesets', exist_ok=True)
    nomes = _gids(m); info = {}; gid = 1
    mapa = ET.Element('map', version='1.10', orientation='orthogonal', renderorder='right-down',
                      width=str(m.w), height=str(m.h), tilewidth='16', tileheight='16', infinite='0', nextlayerid='20', nextobjectid='500')
    for t in nomes:
        im = Image.open(TUX / t); cols, rows = im.width // T, im.height // T
        shutil.copy(TUX / t, pasta + '/tilesets/' + t)
        info[t] = (gid, cols)
        e = ET.SubElement(mapa, 'tileset', firstgid=str(gid), name=os.path.splitext(t)[0], tilewidth='16', tileheight='16', tilecount=str(cols * rows), columns=str(cols))
        ET.SubElement(e, 'image', source='tilesets/' + t, width=str(im.width), height=str(im.height))
        gid += cols * rows
    # marcador de colisao
    mk = Image.new('RGBA', (16, 16), (255, 0, 0, 110)); mk.save(pasta + '/tilesets/colisao.png')
    e = ET.SubElement(mapa, 'tileset', firstgid=str(gid), name='colisao', tilewidth='16', tileheight='16', tilecount='1', columns='1')
    ET.SubElement(e, 'image', source='tilesets/colisao.png', width='16', height='16'); gcol = gid
    ext={}
    for nome,(cells,png) in (extras or {}).items():
        shutil.copy(png, pasta + '/tilesets/' + nome + '.png')
        e = ET.SubElement(mapa, 'tileset', firstgid=str(gid+1), name=nome, tilewidth='16', tileheight='16', tilecount='1', columns='1')
        ET.SubElement(e, 'image', source='tilesets/' + nome + '.png', width='16', height='16'); ext[nome]=(gid+1,cells); gid+=1
    lid = 1
    def camada(nome, f, visivel=True):
        nonlocal lid
        l = ET.SubElement(mapa, 'layer', id=str(lid), name=nome, width=str(m.w), height=str(m.h))
        if not visivel: l.set('visible', '0')
        lid += 1
        dt = ET.SubElement(l, 'data', encoding='csv')
        linhas = []
        for y in range(m.h): linhas.append(','.join(str(f(x, y)) for x in range(m.w)))
        dt.text = '\n' + ',\n'.join(linhas) + '\n'
    for nome in ('chao', 'trilha', 'agua', 'objetos', 'sobre', 'cima'):
        d = m.cam[nome]
        def f(x, y, d=d):
            v = d.get((x, y))
            return 0 if v is None else info[v[0]][0] + v[2] * info[v[0]][1] + v[1]
        camada(nome, f)
    for nome,(g0,cells) in ext.items():
        camada(nome, lambda x,y,g0=g0,cells=cells: g0 if (x,y) in cells else 0)
    camada('colisao', lambda x, y: gcol if m.sol[y * m.w + x] else 0, visivel=False)
    oid = 1
    og = ET.SubElement(mapa, 'objectgroup', id=str(lid), name='portais'); lid += 1
    for p in portais:
        o = ET.SubElement(og, 'object', id=str(oid), name=p['dest'], x=str(p['x'] * 16), y=str(p['y'] * 16), width=str(p['w'] * 16), height=str(p['h'] * 16)); oid += 1
        pr = ET.SubElement(o, 'properties')
        for k in ('dest', 'dx', 'dy', 'dir'):
            ET.SubElement(pr, 'property', name=k, value=str(p[k]), **({'type': 'int'} if k in ('dx', 'dy') else {}))
    og = ET.SubElement(mapa, 'objectgroup', id=str(lid), name='pontos'); lid += 1
    for p in pois:
        o = ET.SubElement(og, 'object', id=str(oid), name=p['id'], x=str(p['x'] * 16), y=str(p['y'] * 16), width='16', height='16'); oid += 1
        pr = ET.SubElement(o, 'properties')
        ET.SubElement(pr, 'property', name='dados', value=json.dumps(p, ensure_ascii=False))
    if spawn:
        pr = ET.SubElement(mapa, 'properties'); ET.SubElement(pr, 'property', name='spawn', value=json.dumps(spawn))
    ET.indent(mapa); ET.ElementTree(mapa).write(caminho, encoding='utf-8', xml_declaration=True)

def renderizar_tmx(caminho, ocultar=('colisao','grama_alta')):
    """Le o .tmx (so tiles) e compoe base e cima. Independente do construtor."""
    pasta = os.path.dirname(caminho); raiz = ET.parse(caminho).getroot()
    W, H = int(raiz.get('width')), int(raiz.get('height'))
    ts = []
    for e in raiz.findall('tileset'):
        im = Image.open(pasta + '/' + e.find('image').get('source')).convert('RGBA')
        ts.append((int(e.get('firstgid')), int(e.get('columns')), im, e.get('name')))
    ts.sort(key=lambda t: -t[0])
    base = Image.new('RGBA', (W * 16, H * 16), (0, 0, 0, 0)); cima = Image.new('RGBA', (W * 16, H * 16), (0, 0, 0, 0))
    for l in raiz.findall('layer'):
        nome = l.get('name')
        if nome in ocultar: continue
        alvo = cima if nome == 'cima' else base
        vals = [int(v) for v in l.find('data').text.replace('\n', '').split(',') if v.strip() != '']
        for i, g in enumerate(vals):
            if g == 0: continue
            for (fg, cols, im, _) in ts:
                if g >= fg:
                    k = g - fg; c, r = k % cols, k // cols
                    alvo.alpha_composite(im.crop((c * 16, r * 16, c * 16 + 16, r * 16 + 16)), ((i % W) * 16, (i // W) * 16)); break
    return base, cima, W, H
