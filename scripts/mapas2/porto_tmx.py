import json, os
from collections import deque
from PIL import Image
from pecas import *
from mapa_tmx import TMapa, salvar_tmx, renderizar_tmx, CC
W,H=50,40
m=TMapa(W,H,semente=41)
m.grama()
ruas=[(7,0,5,20),(35,0,5,20),     # trilhas das Rotas 5 e 6 (norte)
      (0,7,12,5),                  # Rota 2 (oeste)
      (11,8,24,7),                 # praca-feira
      (21,0,5,40),                 # avenida norte-sul (Rota 1 ao sul)
      (0,19,50,5),                 # avenida leste-oeste
      (40,13,10,5),                # Costa Azul (leste)
      (0,29,23,5),(23,29,27,5)]    # rua do cais (Caminho da Floresta a oeste, Costa Rosada a leste)
m.trilha(ruas)
m.agua([(26,34,24,6)])             # baia a sudeste
P={}; PRED=[]
def pr(nome,x,y,tipo):
    P[nome]=m.predio(x,y,tipo); w,h=PREDIOS[tipo][2:4]; PRED.append((x,y,w,h))
pr('centro',13,4,'centro'); pr('loja',28,4,'mart')
pr('casa_marta',13,15,'casa_pagode'); pr('casa_nilo',28,15,'casa_pagode'); pr('casa_gil',1,15,'casa_madeira_a')
pr('casa_helio',2,25,'casa_madeira_a'); pr('casa_rubi',7,25,'casa_pagode'); pr('casa_vera',13,25,'casa_madeira_a')
pr('armazem_a',27,25,'casa_escura'); pr('armazem_b',34,25,'predio_cinza')
# barracas da feira (5x5, toldo por cima do jogador nas 3 linhas de cima)
def barraca(x,y):
    for dy in range(5):
        for dx in range(5):
            m.poe(x+dx,y+dy,CC,18+dx,22+dy)
            if dy<3: m.poe(x+dx,y+dy,CC,18+dx,22+dy,'cima')
            m.solido(x+dx,y+dy); m.ocupado[(y+dy)*W+x+dx]=True
barraca(13,9); barraca(28,9)
P['feira']=(15,14)
# cais: duas passarelas de tabuas sobre a agua
OC="oceanset_outside.tiles.png"
m._atual='sobre'
for px in (34,40):
    for y in range(34,39):
        for dx,c in ((0,11),(1,12)): m.poe(px+dx,y,OC,c,43); m.solido(px+dx,y,False)
m._atual='objetos'
def livre1(x,y):
    return (0<=x<W and 0<=y<H and not m.sol[y*W+x] and not m.M_agua[y][x] and (x,y) not in m.cam['objetos'] and (x,y) not in m.cam['sobre']
            and (x,y) not in set(P.values()) and not any(a<=x<a+w and b<=y<b+h for (a,b,w,h) in PRED))
def caixa(x,y,c,r,h=2):
    if not all(livre1(x,y+i) and not m.ocupado[(y+i)*W+x] for i in range(h)): return False
    for i in range(h):
        m.poe(x,y+i,CC,c,r+i); m.solido(x,y+i); m.ocupado[(y+i)*W+x]=True
    return True
for (x,y,c,r) in [(18,12,26,20),(19,12,27,20),(34,12,28,20),(35,12,29,20),   # caixas de frutas junto as barracas
                  (40,26,30,0),(41,26,31,0),(43,27,33,0),(44,27,34,0),(42,27,30,0)]:
    caixa(x,y,c,r,2)
for (x,y) in [(40,28),(45,28),(38,27)]:
    if livre1(x,y) and not m.ocupado[y*W+x]: m.poe(x,y,CC,32,0); m.solido(x,y); m.ocupado[y*W+x]=True
# aneis livres e reservas
for y in range(H):
    for x in range(W):
        if m.M_trilha[y][x] or m.M_agua[y][x]:
            for dy in(-1,0,1):
                for dx in(-1,0,1):
                    a,b=x+dx,y+dy
                    if 0<=a<W and 0<=b<H: m.ocupado[b*W+a]=True
for (x,y,w,h) in PRED: m.reservar(x-1,y-1,w+2,h+2)
m.reservar(40,24,10,5)
for x in range(W):
    if x not in (8,9,10,36,37,38): m.solido(x,0); m.ocupado[x]=True
m.borda_arvores(aberturas=[(7,0,5,2),(35,0,5,2),(0,7,2,5),(0,29,2,5),(48,13,2,5),(48,29,2,5),(21,38,5,2)])
m.enche_arvores((0,3,W,10),passo=2,prob=0.9,margem=0)
m.enche_arvores((0,16,W,24),passo=2,prob=0.9,margem=0)
# canteiros e pedras
def canteiro(x,y,p=0.9):
    if livre1(x,y) and not m.ocupado[y*W+x] and m.rng.random()<p:
        c,r=m.rng.choice([(6,0),(7,0),(4,2),(3,2),(2,41),(2,44)]); m.poe(x,y,CO,c,r); m.ocupado[y*W+x]=True
for (x,y,w,h) in PRED:
    for yy in (y+h-2,y+h-1): canteiro(x-1,yy); canteiro(x+w,yy)
    for xx in range(x,x+w): canteiro(xx,y-1,0.4)
for (x,y) in [(3,3),(5,5),(1,12),(44,5),(46,9),(43,21),(5,36),(12,36),(18,35),(46,26),(15,22),(31,24)]:
    if livre1(x,y) and not m.ocupado[y*W+x]: m.pedra(x,y)
# ---- detalhes de vida (so peças ja usadas) ----
def pin(x,y):
    if 1<=y and y+1<H and livre1(x,y) and livre1(x,y+1) and not m.M_trilha[y][x] and not m.M_trilha[y+1][x]:
        m.poe(x,y,CO,24,28); m.poe(x,y+1,CO,24,29); m.poe(x,y,CO,24,28,'cima')
        m.solido(x,y); m.solido(x,y+1); m.ocupado[y*W+x]=m.ocupado[(y+1)*W+x]=True
for _ in range(400):
    x,y=m.rng.randrange(1,W-1),m.rng.randrange(3,H-3)
    if sum(1 for r in m.reg if r[0]=='pinheiro')>=16: break
    if not m.M_trilha[y][x] and not any(abs(x-r[1])<3 and abs(y-r[2])<3 for r in m.reg if r[0]=='pinheiro'): pin(x,y)
for _ in range(900):
    x,y=m.rng.randrange(W),m.rng.randrange(3,H-1)
    if livre1(x,y) and not m.M_trilha[y][x] and not m.ocupado[y*W+x] and m.rng.random()<0.5:
        c,r=m.rng.choice([(6,0),(7,0),(4,2),(3,2),(2,41),(2,44)]); m.poe(x,y,CO,c,r); m.ocupado[y*W+x]=True
for (x,y,c,r) in [(31,32,33,0),(38,32,34,0),(44,32,30,0),(45,32,31,0),(46,32,33,0),(28,32,30,0),(29,32,31,0)]:
    caixa(x,y,c,r,2)
for (x,y) in [(33,31),(37,31),(43,31)]:
    if livre1(x,y) and not m.ocupado[y*W+x]: m.poe(x,y,CC,32,0); m.solido(x,y); m.ocupado[y*W+x]=True
def alcance():
    s=(23,39); seen={s}; q=deque([s])
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
old=json.load(open(os.path.expanduser('~/mnt/pkm-rpg/public/assets/mapas/porto.json')))
nova={'rota2':(0,8,1,3),'caminho_va':(0,30,1,3),'rota5':(8,0,3,1),'rota6':(36,0,3,1),'costa1':(49,14,1,3),'costa2':(49,30,1,3),'rota1':(22,39,3,1)}
portais=[]
for p in old['portais']:
    q=dict(p); q.update(zip(('x','y','w','h'),nova[p['dest']]))
    if p['dest']=='rota1': q['dx']=21
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
json.dump(J,open('saida/porto.json','w'),ensure_ascii=False)
salvar_tmx(m,os.path.abspath('../tmx/porto_turquesa.tmx'),portais,pois)
b,c,_,_=renderizar_tmx('../tmx/porto_turquesa.tmx')
b.save('saida/porto.png'); c.save('saida/porto-cima.png')
im=b.copy(); im.alpha_composite(c); im.resize((W*28,H*28),Image.NEAREST).save('../porto_tmx_v1.png')
print('ok',P)
