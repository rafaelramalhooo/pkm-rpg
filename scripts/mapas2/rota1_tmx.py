import json, os
from collections import deque
from PIL import Image
from pecas import *
from mapa_tmx import TMapa, salvar_tmx, renderizar_tmx
W,H=36,56
m=TMapa(W,H,semente=31)
NAT="core_outdoor_nature.png"
m.grama()
# trilha principal em S: sul (Vila Alvorada) -> norte (Porto Turquesa); 3 tiles de areia
ruas=[(17,44,5,12),(17,41,12,5),(24,27,5,19),(11,27,18,5),(11,14,5,18),(11,14,13,5),(19,0,5,19)]
m.trilha(ruas)
campos=[(12,46,5,7),(29,30,6,8),(4,20,7,9),(24,5,9,9),(9,4,9,8)]
gr=set()
for (x,y,w,h) in campos:
    for yy in range(y,y+h):
        for xx in range(x,x+w): gr.add((xx,yy))
    m.reservar(x,y,w,h)
# lago pequeno, so tiles (moldura de margem 3x3)
LAGO=(26,47,7,5)
m.agua([LAGO]); m.reservar(LAGO[0]-1,LAGO[1]-1,LAGO[2]+2,LAGO[3]+2)
for y in range(H):
    for x in range(W):
        if m.M_trilha[y][x]:
            for dy in(-1,0,1):
                for dx in(-1,0,1):
                    a,b=x+dx,y+dy
                    if 0<=a<W and 0<=b<H: m.ocupado[b*W+a]=True
m.borda_arvores(aberturas=[(20,0,3,2),(18,H-2,3,2)])
for x in range(W):
    if not (20<=x<23): m.solido(x,0); m.ocupado[x]=True
m.enche_arvores((0,3,W,10),passo=2,prob=0.97,margem=0)
m.enche_arvores((0,14,W,42),passo=2,prob=0.97,margem=0)
def toco2(x,y):
    if not m.livre(x,y,2,2): return False
    for dy in range(2):
        for dx in range(2):
            m.poe(x+dx,y+dy,NAT,54+dx,2+dy); m.solido(x+dx,y+dy); m.ocupado[(y+dy)*W+x+dx]=True
    return True
def toco1(x,y):
    if not m.livre(x,y,1,1): return False
    m.poe(x,y,NAT,*m.rng.choice([(53,2),(53,3)])); m.solido(x,y); m.ocupado[y*W+x]=True; return True
def sem_campo(x,y,w,h): return not any((a,b) in gr for b in range(y-1,y+h+1) for a in range(x-1,x+w+1))
deco=set(); cont={'t2':0,'t1':0,'p':0}
def perto(x,y,r=2): return any((a,b) in deco for a in range(x-r,x+r+1) for b in range(y-r,y+r+1))
for _ in range(4000):
    x,y=m.rng.randrange(W),m.rng.randrange(H)
    if perto(x,y): continue
    if cont['t2']<3 and sem_campo(x,y,2,2) and toco2(x,y): cont['t2']+=1; deco.add((x,y))
    elif cont['t1']<5 and sem_campo(x,y,1,1) and toco1(x,y): cont['t1']+=1; deco.add((x,y))
    elif cont['p']<18 and sem_campo(x,y,1,1) and m.pedra(x,y): cont['p']+=1; deco.add((x,y))
FL=[(6,0),(7,0),(4,2),(3,2),(2,41),(2,44)]
for _ in range(14):
    cx,cy=m.rng.randrange(W),m.rng.randrange(H); f=m.rng.choice(FL)
    for dx,dy in((0,0),(1,0),(0,1)):
        x,y=cx+dx,cy+dy
        if 0<=x<W and 0<=y<H and (x,y) not in gr and m.livre(x,y,1,1) and (x,y) not in m.cam['objetos']: m.poe(x,y,CO,*f); m.ocupado[y*W+x]=True
def alcance():
    s=(19,55); seen={s}; q=deque([s])
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
            if (x,y) not in gr and not m.pedra(x,y):
                m.poe(x,y,CO,29,30); m.solido(x,y); m.ocupado[y*W+x]=True
sv=alcance()
bols=[(x,y) for y in range(H) for x in range(W) if not m.sol[y*W+x] and (x,y) not in sv]
assert not bols,('bolsoes',bols[:6])
old=json.load(open(os.path.expanduser('~/mnt/pkm-rpg/public/assets/mapas/rota1.json')))
portais=[]
for p in old['portais']:
    q=dict(p)
    if p['dest']=='pallet': q.update(x=18,y=55,w=3,dx=19,dy=1)
    if p['dest']=='porto': q.update(x=20,y=0,w=3)
    portais.append(q)
sol=''.join('1' if s else '0' for s in m.sol)
grama=''.join('1' if (x,y) in gr else '0' for y in range(H) for x in range(W))
def bio(x,y):
    i=y*W+x
    if m.sol[i]: return 'A' if m.M_agua[y][x] else '#'
    if m.M_trilha[y][x]: return 'E'
    if (x,y) in gr: return 'G'
    for dy in range(-2,3):
        for dx in range(-2,3):
            a,b=x+dx,y+dy
            if 0<=a<W and 0<=b<H and m.sol[b*W+a]: return 'F'
    return 'C'
BIO=''.join(bio(x,y) for y in range(H) for x in range(W))
J=dict(old,solido=sol,grama=grama,bioma=BIO,portais=portais,pois=old.get('pois',[]))
json.dump(J,open('saida/rota1.json','w'),ensure_ascii=False)
GA=os.path.expanduser('~/mnt/pkm-rpg/public/assets/grama-alta.png')
salvar_tmx(m,os.path.abspath('../tmx/rota1.tmx'),portais,J['pois'],None,extras={'grama_alta':(gr,GA)})
b,c,_,_=renderizar_tmx('../tmx/rota1.tmx')
b.save('saida/rota1.png'); c.save('saida/rota1-cima.png')
pv=b.copy(); ga=Image.open(GA).convert('RGBA')
for (x,y) in gr: pv.alpha_composite(ga,(x*16,y*16))
pv.alpha_composite(c); pv.resize((W*24,H*24),Image.NEAREST).save('../rota1_tmx_v1.png')
print('ok',cont)
