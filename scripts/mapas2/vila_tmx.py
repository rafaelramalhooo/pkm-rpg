import json, os
from collections import deque
from pecas import *
from mapa_tmx import TMapa, salvar_tmx, renderizar_tmx, CC
W,H=40,40
m=TMapa(W,H,semente=21)
m.grama()
# ---- ruas: retangulos de trilha (areia visivel = largura-2) ----
ruas=[(17,0,6,12),      # trilha norte (4 tiles de areia) ate a Rota 1
      (3,11,34,5),      # rua A (3 tiles de areia)
      (3,22,34,5),      # rua B
      (17,11,6,16),     # travessa central ligando A e B
      (28,26,5,5)]      # entrada da praca
m.trilha(ruas)
# ---- predios inteiros; porta voltada para a rua ----
P={}
P['lab']=m.predio(10,7,'lab_branco')
P['casa_flora']=m.predio(24,7,'casa_pagode')
P['cafe']=m.predio(30,7,'casa_madeira_b')
P['casa_jogador']=m.predio(5,18,'casa_pagode')
P['casa_rival']=m.predio(11,18,'casa_pagode')
P['centro']=m.predio(24,18,'centro')
P['mart']=m.predio(30,18,'mart')
PRED=[(10,7,5,4),(24,7,5,4),(30,7,5,4),(5,18,5,4),(11,18,5,4),(24,18,5,4),(30,18,5,4)]
# ---- praca cercada a leste/sul: fonte e duas estatuas ----
def cerca_praca(x0,y0,x1,y1,vao):
    def p(x,y,c,r):
        m.poe(x,y,CO,c,r); m.solido(x,y); m.ocupado[y*W+x]=True
    for x in range(x0,x1+1):
        c=21 if x==x0 else 23 if x==x1 else 22
        if x not in vao: p(x,y0,c,31)
        p(x,y1,c,33)
    for y in range(y0+1,y1):
        p(x0,y,21,32); p(x1,y,23,32)
cerca_praca(24,29,36,36,vao=(29,30,31))
m.fonte(29,31,0)
def estatua(x,y):
    for dy in range(3):
        for dx in range(2):
            m.poe(x+dx,y+dy,CC,8+dx,31+dy); m.solido(x+dx,y+dy); m.ocupado[(y+dy)*W+x+dx]=True
estatua(26,31); estatua(33,31)
# ---- areas livres: anel de grama ao redor de ruas e predios ----
for y in range(H):
    for x in range(W):
        if m.M_trilha[y][x]:
            for dy in(-1,0,1):
                for dx in(-1,0,1):
                    a,b=x+dx,y+dy
                    if 0<=a<W and 0<=b<H: m.ocupado[b*W+a]=True
for (x,y,w,h) in PRED: m.reservar(x-1,y-1,w+2,h+2)
m.reservar(23,28,15,10)
m.borda_arvores(aberturas=[(17,0,6,2)])
m.enche_arvores((0,3,W,8),passo=2,prob=0.9,margem=0)
m.enche_arvores((0,16,W,24),passo=2,prob=0.9,margem=0)
# bosque de pinheiros pequenos a sudoeste
for y in range(29,38,2):
    for x in range(3,17,2):
        if m.rng.random()<0.65: m.pinheiro(x,y)
# flores (so em grama livre, nunca em porta/predio/trilha)
for _ in range(60):
    x,y=m.rng.randrange(3,37),m.rng.randrange(3,37); m.flor(x,y); m.ocupado[y*W+x]=m.ocupado[y*W+x] or (x,y) in m.cam['objetos']
# ---- detalhes: canteiros, pinheiros pequenos, pedras (so em grama livre) ----
alvos_porta={tuple(v) for v in P.values()}
def livre1(x,y):
    return (0<=x<W and 0<=y<H and not m.sol[y*W+x] and not m.M_trilha[y][x] and (x,y) not in m.cam['objetos']
            and (x,y) not in alvos_porta and not any(a<=x<a+w and b<=y<b+h for (a,b,w,h) in PRED))
def canteiro(x,y,p=0.9):
    if livre1(x,y) and m.rng.random()<p:
        c,r=m.rng.choice([(6,0),(7,0),(4,2),(3,2),(2,41),(2,44)]); m.poe(x,y,CO,c,r)
def pin(x,y):
    if 1<=y and y+1<H and livre1(x,y) and livre1(x,y+1):
        m.poe(x,y,CO,24,28); m.poe(x,y+1,CO,24,29); m.poe(x,y,CO,24,28,'cima')
        m.solido(x,y); m.solido(x,y+1); m.ocupado[y*W+x]=m.ocupado[(y+1)*W+x]=True
def pedra(x,y):
    if livre1(x,y): m.pedra(x,y)
for (x,y,w,h) in PRED:                          # canteiros nas laterais de cada casa
    for yy in (y+h-2,y+h-1):
        canteiro(x-1,yy); canteiro(x+w,yy)
    for xx in range(x,x+w): canteiro(xx,y-1,0.45)
for (x,y) in [(4,16),(7,16),(10,16),(13,16),(26,16),(29,16),(32,16),(35,16)]: pin(x,y)
for (x,y) in [(4,3),(8,2),(12,4),(14,5),(34,4),(36,6),(26,3),(31,3),(36,15),(3,15),(36,27),(3,27),(2,27)]: pedra(x,y)
for x in range(3,17):                           # faixa de flores entre a rua B e o bosque
    canteiro(x,27,0.5); canteiro(x,28,0.35)
for (x,y) in [(25,30),(35,30),(25,35),(35,35),(26,35),(34,35),(28,35),(32,35),(25,31),(35,31),(25,34),(35,34),(30,35),(30,36-1)]:
    canteiro(x,y,1.0)
for (x,y) in [(19,28),(20,28),(21,28),(23,27),(22,28),(18,27),(37,28),(37,29)]: canteiro(x,y,0.8)
# ---- alcance: nenhum tile andavel pode ficar isolado ----
def alcance():
    s=(19,1); seen={s}; q=deque([s])
    while q:
        x,y=q.popleft()
        for dx,dy in((1,0),(-1,0),(0,1),(0,-1)):
            a,b=x+dx,y+dy
            if 0<=a<W and 0<=b<H and not m.sol[b*W+a] and (a,b) not in seen: seen.add((a,b)); q.append((a,b))
    return seen
for _ in range(10):
    sv=alcance(); mud=False
    for y in range(H):
        for x in range(W):
            if not m.sol[y*W+x] and (x,y) not in sv and m.livre(x,y):
                if m.arvore(x,y): mud=True
    if not mud: break
sv=alcance()
for y in range(H):
    for x in range(W):
        if not m.sol[y*W+x] and (x,y) not in sv:
            if (x,y) in m.cam['objetos']: del m.cam['objetos'][(x,y)]
            if not m.pedra(x,y):
                m.poe(x,y,CO,29,30); m.solido(x,y); m.ocupado[y*W+x]=True
sv=alcance()
bols=[(x,y) for y in range(H) for x in range(W) if not m.sol[y*W+x] and (x,y) not in sv]
assert not bols,('bolsoes inalcancaveis',bols[:5])
# ---- dados do jogo (pontos e portais), vindos do jogo atual ----
old=json.load(open(os.path.expanduser('~/mnt/pkm-rpg/public/assets/mapas/pallet.json')))
pois=[]
for p in old['pois']:
    q=dict(p)
    if p['id'] in P: q['x'],q['y']=P[p['id']]
    pois.append(q)
lx,ly=P['lab']
portais=[dict(old['portais'][0],x=18,y=0,w=4,h=1),dict(old['portais'][1],x=lx,y=ly)]
spawn=dict(old.get('spawn',{}),x=19,y=6)
sol=''.join('1' if s else '0' for s in m.sol)
def bio(x,y):
    i=y*W+x
    if m.sol[i]: return '#'
    if m.M_trilha[y][x]: return 'E'
    for dy in range(-2,3):
        for dx in range(-2,3):
            a,b=x+dx,y+dy
            if 0<=a<W and 0<=b<H and m.sol[b*W+a]: return 'F'
    return 'C'
BIO=''.join(bio(x,y) for y in range(H) for x in range(W))
J=dict(old,solido=sol,grama='0'*(W*H),bioma=BIO,portais=portais,pois=pois,spawn=spawn)
os.makedirs('saida',exist_ok=True)
json.dump(J,open('saida/vila_alvorada.json','w'),ensure_ascii=False)
salvar_tmx(m,os.path.abspath('../tmx/vila_alvorada.tmx'),portais,pois,spawn)
b,c,_,_=renderizar_tmx('../tmx/vila_alvorada.tmx')
b.save('saida/vila_alvorada.png'); c.save('saida/vila_alvorada-cima.png')
from PIL import Image
im=b.copy(); im.alpha_composite(c); im.resize((W*32,H*32),Image.NEAREST).save('../vila_tmx_v1.png')
print('ok',P)
