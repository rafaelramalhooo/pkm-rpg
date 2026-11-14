import json, os
from PIL import Image
import numpy as np
from pecas import *
from mapa_tmx import TMapa, salvar_tmx, renderizar_tmx
from comp import comps
REPO=os.path.expanduser('~/mnt/pkm-rpg/public/assets/mapas')
IW='core_indoor_walls.png'; IF='core_indoor_floors.png'; INT='Interiors_16x16.png'; CAV='Cave_Tiles_by_George_.png'; CAM='Cave_Tiles_by_ArMM1998_(Tuxemon_Style).png'
_C={}
def _comp(sheet):
    if sheet not in _C:
        r,_=comps(str(TUX/sheet),2)
        im=np.array(Image.open(TUX/sheet).convert('RGBA'))[:,:,3]>0
        _C[sheet]=(r,im)
    return _C[sheet]
_A={}
def _alpha(sheet):
    if sheet not in _A:
        a=np.array(Image.open(TUX/sheet).convert('RGBA'))[:,:,3]; _A[sheet]=a
    return _A[sheet]
def acha(sheet,c,r):
    """componente do sheet mais proximo do centro do tile (c,r); devolve retangulo de tiles (c0,r0,w,h)"""
    rs,_=_comp(sheet); cx,cy=c*16+8,r*16+8; best=None
    for (x0,y0,x1,y1) in rs:
        d=max(x0-cx,0,cx-x1)**2+max(y0-cy,0,cy-y1)**2
        if best is None or d<best[0]: best=(d,(x0,y0,x1,y1))
    x0,y0,x1,y1=best[1]
    return (x0//16,y0//16,(x1-1)//16-x0//16+1,(y1-1)//16-y0//16+1)
class IMapa(TMapa):
    def __init__(self,w,h,seed=1):
        super().__init__(w,h,seed); self.livres=set()
    def bloco(self,x,y,ts,c,r,w,h,solido=True,camada='objetos',topo_cima=0):
        """copia o retangulo w*h de tiles do sheet (c,r) para (x,y). topo_cima = linhas de cima que ficam na camada 'cima'"""
        for j in range(h):
            for i in range(w):
                if x+i>=self.w or y+j>=self.h: continue
                self._atual='objetos'
                cam='cima' if j<topo_cima else 'base'
                if cam=='base' and (x+i,y+j) in self.cam['objetos']: continue
                self.poe(x+i,y+j,ts,c+i,r+j,cam)
                if solido and j>=topo_cima: self.solido(x+i,y+j)
    def item(self,x,y,c,r,w,h,ts=INT,solido=True,cobre=False):
        """coloca o bloco (c,r,w,h) do sheet em (x,y). Solido so onde ha pixels opacos (>=20% do tile)."""
        im=_alpha(ts)
        for j in range(h):
            for i in range(w):
                xx,yy=x+i,y+j
                if not(0<=xx<self.w and 0<=yy<self.h): continue
                sub=im[(r+j)*16:(r+j)*16+16,(c+i)*16:(c+i)*16+16]
                if not sub.any(): continue
                if (xx,yy) in self.cam['sobre']: raise AssertionError(f'celula ocupada {(xx,yy)} por item {(c,r,w,h)}')
                self._atual='sobre'; self.poe(xx,yy,ts,c+i,r+j)
                self._atual='objetos'
                if solido and (sub>200).sum()>=51: self.solido(xx,yy)
        return (w,h)
def carpete(m,x,y,w,h,c,r,ts=IF):
    for j in range(h):
        for i in range(w):
            ci=0 if i==0 else 2 if i==w-1 else 1
            rj=0 if j==0 else 2 if j==h-1 else 1
            m._atual='trilha'; m.poe(x+i,y+j,ts,c+ci,r+rj)
def sala(m,tema,piso,sala_y0=5):
    """piso em toda a sala; parede de fundo (5 linhas); laterais e teto escuros"""
    W,H=m.w,m.h; c0,r0=tema
    m._atual='chao'
    for y in range(H):
        for x in range(W): m.poe(x,y,IF,*piso)
    m._atual='objetos'
    for x in range(W):
        for k,(c,r) in enumerate([(3,0),(3,1),(1,2),(1,3),(1,5)]):
            m.poe(x,sala_y0-5+k,IW,c0+c,r0+r); m.solido(x,sala_y0-5+k)
    for y in range(sala_y0,H):
        for x in (0,W-1):
            m.poe(x,y,IW,c0+3,r0+1); m.solido(x,y)
def fechar(m,mid,portais,pois,spawn,extra=None):
    W,H=m.w,m.h
    old=json.load(open(f'{REPO}/{mid}.json')) if os.path.exists(f'{REPO}/{mid}.json') else {}
    sol=''.join('1' if m.sol[y*W+x] else '0' for y in range(H) for x in range(W))
    BIO=''.join('#' if m.sol[y*W+x] else 'E' for y in range(H) for x in range(W))
    J=dict(old,solido=sol,grama='0'*(W*H),bioma=BIO,portais=portais,pois=pois)
    if extra: J.update(extra)
    json.dump(J,open(f'saida/{mid}.json','w'),ensure_ascii=False)
    salvar_tmx(m,os.path.abspath(f'../tmx/{mid}.tmx'),portais,pois)
    b,cc,_,_=renderizar_tmx(f'../tmx/{mid}.tmx')
    b.save(f'saida/{mid}.png'); cc.save(f'saida/{mid}-cima.png')
    im=b.copy(); im.alpha_composite(cc); im.resize((W*28,H*28),Image.NEAREST).save(f'../{mid}_tmx_v1.png')

def porta_topo(m,x0=9,x1=11,wc=(0,0)):
    """vao escuro na parede de fundo (acesso ao proximo salao): linhas 2..4 escuras, linha 4 caminhavel"""
    c0,r0=wc
    for x in range(x0,x1+1):
        for y in (2,3,4):
            for nome in ('objetos','sobre'): m.cam[nome].pop((x,y),None)
            m._atual='objetos'; m.poe(x,y,IW,c0+3,r0+1)
            m.solido(x,y,y!=4)
