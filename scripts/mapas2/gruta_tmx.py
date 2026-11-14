from interior import *
import random
from collections import deque
mid='gruta'; W,H=40,40
m=IMapa(W,H,77)
rng=random.Random(77)
# --- planta da caverna: corredores e salas (True = chao)
F=[[False]*W for _ in range(H)]
def sala_(x,y,w,h):
    for yy in range(y,y+h):
        for xx in range(x,x+w): F[yy][xx]=True
def corr(x0,y0,x1,y1,l=3):
    # corredor em L com largura l
    for xx in range(min(x0,x1),max(x0,x1)+l): 
        for k in range(l): F[y0+k][xx]=True
    for yy in range(min(y0,y1),max(y0,y1)+l):
        for k in range(l): F[yy][x1+k]=True
# entrada embaixo (10,38) ; saida em cima (24,1)
sala_(8,33,7,6)             # antecamara de entrada
corr(10,34,12,26)           # sobe
sala_(8,20,12,7)            # salao 1
corr(18,22,26,16)           # leste
sala_(22,10,12,8)           # salao cristais
corr(30,12,30,5)            # sobe a direita
sala_(20,2,13,5)            # salao de saida
corr(24,4,24,2,3)
sala_(3,8,8,8)              # bolsao oeste (cristais)
corr(8,11,10,20)
sala_(26,26,10,8)           # bolsao sudeste
corr(12,29,26,29)
corr(32,16,32,26)
# bordas: 1 tile de rocha sempre
for y in range(H):
    for x in range(W):
        if x in(0,W-1) or y in(0,H-1): F[y][x]=False
# garante que linha 0 e 1 abrem a saida e 38/39 a entrada
for x in (23,24,25):
    for y in (1,2): F[y][x]=True
for x in (9,10,11): F[38][x]=True
# tiles
def F_(x,y): return 0<=x<W and 0<=y<H and F[y][x]
m._atual='chao'
for y in range(H):
    for x in range(W):
        if F[y][x]:
            m.poe(x,y,CAM,0,0 if rng.random()<0.85 else rng.choice([1,2]))
        else:
            m.poe(x,y,CAV,2,1); m.solido(x,y)          # vazio escuro
m._atual='objetos'
for y in range(H):
    for x in range(W):
        if F[y][x]: continue
        if F_(x,y+1): t=(1+x%3,3)
        elif F_(x-1,y): t=(0,1+y%2)
        elif F_(x+1,y): t=(4,1+y%2)
        elif F_(x,y-1): t=(0,1+x%2) if False else (4,1)
        else: continue
        m.poe(x,y,CAV,*t)
# cristais, cogumelos e pedras (so junto das paredes das salas, sem fechar corredores)
CR=[(9,9),(10,9),(11,9),(12,9)]; CG=[(5,9),(6,9),(7,9),(8,9)]; PD=[(0,9),(1,9),(2,9)]
def encosta(x,y): return F_(x,y) and any(not F_(x+a,y+b) for a,b in((1,0),(-1,0),(0,1),(0,-1)))
cands=[(x,y) for y in range(3,H-3) for x in range(2,W-2) if encosta(x,y) and not (x in(9,10,11) and y>35) and not (x in (23,24,25) and y<5)]
rng.shuffle(cands)
usados=[]
def ok(x,y): return all(abs(x-a)+abs(y-b)>=3 for a,b in usados)
def alcance(ini):
    seen={ini}; q=deque([ini])
    while q:
        x,y=q.popleft()
        for dx,dy in((1,0),(-1,0),(0,1),(0,-1)):
            a,b=x+dx,y+dy
            if 0<=a<W and 0<=b<H and not m.sol[b*W+a] and (a,b) not in seen: seen.add((a,b)); q.append((a,b))
    return seen
n_c=n_g=n_p=0
for (x,y) in cands:
    if not ok(x,y): continue
    if n_c<40: k=CR[n_c%4]; n_c+=1; sol=True
    elif n_g<18: k=CG[n_g%4]; n_g+=1; sol=False
    elif n_p<12: k=PD[n_p%3]; n_p+=1; sol=True
    else: break
    m.poe(x,y,CAV,*k); 
    if sol: m.solido(x,y)
    usados.append((x,y))
sv=alcance((10,37))
assert (24,2) in sv and (10,38) in sv, 'caminho principal bloqueado'
pos=[(x,y) for y in range(H) for x in range(W) if F[y][x] and not m.sol[y*W+x] and (x,y) not in sv]
print('inalcancaveis',len(pos))
for (x,y) in pos:
    m.cam['objetos'].pop((x,y),None); m.poe(x,y,CAV,0,9); m.solido(x,y)
print('ok')
J=dict(escuro=True)
portais=[dict(x=9,y=38,w=3,h=1,dest='obsidiana',dx=29,dy=1,dir='baixo'),dict(x=23,y=1,w=3,h=1,dest='cromatica',dx=19,dy=38,dir='cima')]
fechar(m,mid,portais,[dict(id='cristal',tipo='casa',x=6,y=11)],None,J)
