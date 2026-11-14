import json, os
from collections import deque
from PIL import Image
from pecas import *
from mapa_tmx import TMapa, salvar_tmx, renderizar_tmx, CC
W,H=40,40
m=TMapa(W,H,semente=51)
m.grama()
ruas=[(28,0,5,36),          # avenida leste (Rota 7 ao norte)
      (22,6,15,5),(22,18,15,5),(22,31,15,5),   # ruas leste
      (13,6,5,34),          # avenida oeste (Costa Azul ao sul)
      (3,6,15,5),(3,18,15,5),   # ruas oeste
      (5,22,5,5)]           # entrada da praca
m.trilha(ruas)
m.agua([(18,0,4,40),(22,36,18,4)])   # rio vertical + bacia do cais
P={}; PRED=[]
def pr(nome,x,y,tipo):
    P[nome]=m.predio(x,y,tipo); w,h=PREDIOS[tipo][2:4]; PRED.append((x,y,w,h))
# margem leste
pr('capitania',23,2,'casa_pagode'); pr('armazem',33,2,'predio_cinza')
pr('pescador',23,14,'casa_madeira_a'); pr('mart',33,14,'mart')
pr('aquario',23,27,'casa_grande'); pr('cabana1',33,27,'casa_madeira_b')
# margem oeste
pr('centro',3,2,'centro'); pr('escola',9,2,'casa_grande')
pr('gin_azurana',3,14,'ginasio_cinza'); pr('cabana2',9,14,'casa_madeira_a')
# ponte de tabuas sobre o rio
OC="oceanset_outside.tiles.png"
m._atual='sobre'
for y in (19,20,21):
    for x in range(18,22):
        m.poe(x,y,OC,11+(x%2),43); m.solido(x,y,False)
# cais na bacia
for px in (25,32):
    for y in range(36,39):
        for dx,c in ((0,11),(1,12)): m.poe(px+dx,y,OC,c,43); m.solido(px+dx,y,False)
m._atual='objetos'
# praca cercada com fonte
def cerca_praca(x0,y0,x1,y1,vao):
    def p(x,y,c,r):
        m.poe(x,y,CO,c,r); m.solido(x,y); m.ocupado[y*W+x]=True
    for x in range(x0,x1+1):
        c=21 if x==x0 else 23 if x==x1 else 22
        if x not in vao: p(x,y0,c,31)
        p(x,y1,c,33)
    for y in range(y0+1,y1):
        p(x0,y,21,32); p(x1,y,23,32)
cerca_praca(2,26,12,37,vao=(6,7,8))
m.fonte(6,30,0)
def estatua(x,y):
    for dy in range(3):
        for dx in range(2):
            m.poe(x+dx,y+dy,CC,8+dx,31+dy); m.solido(x+dx,y+dy); m.ocupado[(y+dy)*W+x+dx]=True
estatua(3,32); estatua(10,32)
def livre1(x,y):
    return (0<=x<W and 0<=y<H and not m.sol[y*W+x] and not m.M_agua[y][x] and (x,y) not in m.cam['objetos'] and (x,y) not in m.cam['sobre']
            and (x,y) not in set(P.values()) and not any(a<=x<a+w and b<=y<b+h for (a,b,w,h) in PRED))
def caixa(x,y,c,r,h=2):
    if not all(livre1(x,y+i) and not m.ocupado[(y+i)*W+x] for i in range(h)): return False
    for i in range(h):
        m.poe(x,y+i,CC,c,r+i); m.solido(x,y+i); m.ocupado[(y+i)*W+x]=True
    return True
for y in range(H):
    for x in range(W):
        if m.M_trilha[y][x] or m.M_agua[y][x]:
            for dy in(-1,0,1):
                for dx in(-1,0,1):
                    a,b=x+dx,y+dy
                    if 0<=a<W and 0<=b<H: m.ocupado[b*W+a]=True
for (x,y,w,h) in PRED: m.reservar(x-1,y-1,w+2,h+2)
m.reservar(1,25,13,14)
for x in range(W):
    if x not in (29,30,31): m.solido(x,0); m.ocupado[x]=True
m.borda_arvores(aberturas=[(28,0,5,2),(13,38,5,2)])
m.enche_arvores((22,11,16,7),passo=2,prob=0.9,margem=0)
m.enche_arvores((22,23,16,8),passo=2,prob=0.9,margem=0)
m.enche_arvores((0,11,18,3),passo=2,prob=0.9,margem=0)
FL=[(6,0),(7,0),(4,2),(3,2),(2,41),(2,44)]
def canteiro(x,y,p=0.9):
    if livre1(x,y) and not m.ocupado[y*W+x] and m.rng.random()<p:
        c,r=m.rng.choice(FL); m.poe(x,y,CO,c,r); m.ocupado[y*W+x]=True
for (x,y,w,h) in PRED:
    for yy in (y+h-2,y+h-1): canteiro(x-1,yy); canteiro(x+w,yy)
    for xx in range(x,x+w): canteiro(xx,y-1,0.4)
for (x,y) in [(3,10),(15,24),(16,30),(14,36),(37,25),(36,23),(1,23),(38,12),(25,12),(37,37)]:
    if livre1(x,y) and not m.ocupado[y*W+x]: m.pedra(x,y)
def pin(x,y):
    if 1<=y and y+1<H and livre1(x,y) and livre1(x,y+1) and not m.M_trilha[y][x] and not m.M_trilha[y+1][x]:
        m.poe(x,y,CO,24,28); m.poe(x,y+1,CO,24,29); m.poe(x,y,CO,24,28,'cima')
        m.solido(x,y); m.solido(x,y+1); m.ocupado[y*W+x]=m.ocupado[(y+1)*W+x]=True
for _ in range(500):
    x,y=m.rng.randrange(1,W-1),m.rng.randrange(3,H-3)
    if sum(1 for r in m.reg if r[0]=='pinheiro')>=14: break
    if not m.M_trilha[y][x] and not any(abs(x-r[1])<3 and abs(y-r[2])<3 for r in m.reg if r[0]=='pinheiro'): pin(x,y)
for _ in range(900):
    x,y=m.rng.randrange(W),m.rng.randrange(3,H-1)
    if livre1(x,y) and not m.M_trilha[y][x] and not m.ocupado[y*W+x] and m.rng.random()<0.5:
        c,r=m.rng.choice(FL); m.poe(x,y,CO,c,r); m.ocupado[y*W+x]=True
# caixas e barris junto ao cais e ao armazem
for (x,y,c,r) in [(28,32,30,0),(29,32,31,0),(36,32,33,0),(37,32,34,0),(38,24,30,0),(37,24,31,0)]:
    pass
def alcance():
    s=(15,38); seen={s}; q=deque([s])
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
assert not bols,('bolsoes',bols[:6])
old=json.load(open(os.path.expanduser('~/mnt/pkm-rpg/public/assets/mapas/azurana.json')))
portais=[]
gx,gy=P['gin_azurana']
for p in old['portais']:
    q=dict(p)
    if p['dest']=='gin_azurana': q.update(x=gx,y=gy)
    elif p['dest']=='rota7a': q.update(x=29,y=0,w=3,h=1)
    elif p['dest']=='costa1': q.update(x=14,y=39,w=3,h=1)
    portais.append(q)
pois=[]
for p in old['pois']:
    q=dict(p)
    if p['id'] in P: q['x'],q['y']=P[p['id']]
    pois.append(q)
sol=''.join('1' if m.sol[y*W+x] else '0' for y in range(H) for x in range(W))
def bio(x,y):
    if sol[y*W+x]=='1': return 'A' if m.M_agua[y][x] else '#'
    if m.M_trilha[y][x]: return 'E'
    return 'C'
BIO=''.join(bio(x,y) for y in range(H) for x in range(W))
J=dict(old,solido=sol,grama='0'*(W*H),bioma=BIO,portais=portais,pois=pois)
json.dump(J,open('saida/azurana.json','w'),ensure_ascii=False)
salvar_tmx(m,os.path.abspath('../tmx/azurana.tmx'),portais,pois)
b,c,_,_=renderizar_tmx('../tmx/azurana.tmx')
b.save('saida/azurana.png'); c.save('saida/azurana-cima.png')
im=b.copy(); im.alpha_composite(c); im.resize((W*28,H*28),Image.NEAREST).save('../azurana_tmx_v1.png')
print('ok',P)
