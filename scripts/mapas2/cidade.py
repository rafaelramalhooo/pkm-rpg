import json, os
from collections import deque
from PIL import Image, ImageDraw
from pecas import *
from mapa_tmx import TMapa, salvar_tmx, renderizar_tmx, CC
REPO=os.path.expanduser('~/mnt/pkm-rpg/public/assets/mapas')
CRIS=[(26,33),(27,33)]
def gerar(c):
    W,H=c['W'],c['H']; mid=c['id']
    m=TMapa(W,H,semente=c['seed']); m.pal=c.get('pal',(0,0)); m.poix_ids=set(c.get('poix',{}))
    NAT='core_outdoor_nature.png'
    if c.get('arv'): m.ARV=[(NAT,a,b) for a,b in c['arv']]
    if c.get('rochas'): m.ROCHAS=[(NAT,a,b) for a,b in c['rochas']]
    if False:
        ts,vs=c['chao']; m._atual='chao'
        for y in range(H):
            for x in range(W):
                cc,r=vs[0] if m.rng.random()<0.8 else m.rng.choice(vs)
                m.poe(x,y,ts,cc,r,'base')
        m._atual='objetos'
    else: m.grama()
    m.trilha(c['ruas'])
    m.M_agua=[[False]*W for _ in range(H)]
    if c.get('aguas'): m.agua(c['aguas'])
    P={}; PRED=[]
    for nome,x,y,tipo in c.get('predios',[]):
        P[nome]=m.predio(x,y,tipo); w,h=PREDIOS[tipo][2:4]; PRED.append((x,y,w,h))
    def cerca(x0,y0,x1,y1,vao):
        def p(x,y,cc,r): m.poe(x,y,CO,cc,r); m.solido(x,y); m.ocupado[y*W+x]=True
        for x in range(x0,x1+1):
            cc=21 if x==x0 else 23 if x==x1 else 22
            if x not in vao: p(x,y0,cc,31)
            p(x,y1,cc,33)
        for y in range(y0+1,y1):
            p(x0,y,21,32); p(x1,y,23,32)
    def estatua(x,y):
        for dy in range(3):
            for dx in range(2):
                m.poe(x+dx,y+dy,CC,8+dx,31+dy); m.solido(x+dx,y+dy); m.ocupado[(y+dy)*W+x+dx]=True
    for (x0,y0,x1,y1,vao,fx,fy,est) in c.get('pracas',[]):
        cerca(x0,y0,x1,y1,vao); m.fonte(fx,fy,0)
        for (ex,ey) in est: estatua(ex,ey)
    for (ex,ey) in c.get('estatuas',[]): estatua(ex,ey); m.reservar(ex-1,ey-1,4,5)
    for (fx,fy) in c.get('fontes',[]): m.fonte(fx,fy,0); m.reservar(fx-1,fy-1,5,5)
    def livre1(x,y):
        return (0<=x<W and 0<=y<H and not m.sol[y*W+x] and not m.M_agua[y][x] and (x,y) not in m.cam['objetos'] and (x,y) not in m.cam['sobre']
                and (x,y) not in set(P.values()) and not any(a<=x<a+w and b<=y<b+h for (a,b,w,h) in PRED))
    for y in range(H):
        for x in range(W):
            if m.M_trilha[y][x] or (m.M_agua and m.M_agua[y][x]):
                for dy in(-1,0,1):
                    for dx in(-1,0,1):
                        a,b=x+dx,y+dy
                        if 0<=a<W and 0<=b<H: m.ocupado[b*W+a]=True
    for (x,y,w,h) in PRED: m.reservar(x-1,y-1,w+2,h+2)
    for r in c.get('reservas',[]): m.reservar(*r)
    gr=set()
    for (fx,fy,fw,fh) in c.get('campos',[]):
        for yy in range(fy-1,fy+fh+1):
            for xx in range(fx-1,fx+fw+1):
                if 0<=xx<W and 0<=yy<H: assert not m.M_trilha[yy][xx],('campo encosta na trilha',(fx,fy,fw,fh))
        for yy in range(fy,fy+fh):
            for xx in range(fx,fx+fw):
                assert (xx,yy) not in gr,('campos sobrepostos',(fx,fy,fw,fh)); gr.add((xx,yy))
        m.reservar(fx-1,fy-1,fw+2,fh+2)
    NATT='core_outdoor_nature.png'
    for (k,ox,oy) in c.get('objs',[]):
        if k=='toco1':
            assert m.livre(ox,oy,1,1),('obj',k,ox,oy); m.poe(ox,oy,NATT,*m.rng.choice([(53,2),(53,3)])); m.solido(ox,oy)
        elif k=='toco2':
            assert m.livre(ox,oy,2,2),('obj',k,ox,oy)
            for dy in range(2):
                for dx in range(2): m.poe(ox+dx,oy+dy,NATT,54+dx,2+dy); m.solido(ox+dx,oy+dy)
        elif k=='placa':
            assert m.livre(ox,oy,1,1),('obj',k,ox,oy); m.poe(ox,oy,KV,6,4); m.solido(ox,oy)
        elif k=='pedra':
            assert m.pedra(ox,oy),('obj',k,ox,oy)
        m.reservar(ox-1,oy-1,4,4)
    pt=c['portais']
    for (lx,ly,lw,lh) in c.get('lavas',[]):
        m.reservar(lx-2,ly-2,lw+4,lh+4)
        for yy in range(ly,ly+lh):
            for xx in range(lx,lx+lw):
                m.poe(xx,yy,CO,12 if m.rng.random()<0.7 else 11,35); m.solido(xx,yy); m.ocupado[yy*W+xx]=True
    topo={x for d,(x,y,w,h) in pt.items() if y==0 and not d.startswith('gin') for x in range(x,x+w)}
    for x in range(W):
        if x not in topo: m.solido(x,0); m.ocupado[x]=True
    ab=[]
    for d,(x,y,w,h) in pt.items():
        if d.startswith('gin'): continue
        ab.append((x-1 if y in(0,H-1) else x,y-1 if x in(0,W-1) else y,w+(2 if y in(0,H-1) else 0),h+(2 if x in(0,W-1) else 0)))
    ab=[(max(0,a),max(0,b),w,h) for a,b,w,h in ab]
    m.borda_arvores(aberturas=ab+[(x,y,w,2) if y==0 else (x,y-1,w,2) if y==H-1 else (x,y,2,h) for d,(x,y,w,h) in []])
    sm=c['seam']
    for z in [(0,3,W,sm-3),(0,sm,W,H-sm)]: m.enche_arvores(z,passo=2,prob=c.get('dens',0.9),margem=0)
    fp=c.get('flores',0.5)
    if c.get('crist_tiles'): CRIS[:]=c['crist_tiles']
    def canteiro(x,y,p=0.9):
        if livre1(x,y) and not m.ocupado[y*W+x] and m.rng.random()<p:
            cc,r=m.rng.choice(m.FLP()); m.poe(x,y,CO,cc,r); m.ocupado[y*W+x]=True
    for (x,y,w,h) in PRED:
        for yy in (y+h-2,y+h-1): canteiro(x-1,yy); canteiro(x+w,yy)
        for xx in range(x,x+w): canteiro(xx,y-1,0.4)
    for _ in range(c.get('pedras',10)*30):
        if sum(1 for r in m.reg if r[0]=='pedra')>=c.get('pedras',10): break
        x,y=m.rng.randrange(1,W-1),m.rng.randrange(2,H-1)
        if livre1(x,y) and not m.ocupado[y*W+x]: m.pedra(x,y)
    def pin(x,y):
        if 1<=y and y+1<H and livre1(x,y) and livre1(x,y+1) and not m.M_trilha[y][x] and not m.M_trilha[y+1][x]:
            m.poe(x,y,CO,24,28); m.poe(x,y+1,CO,24,29); m.poe(x,y,CO,24,28,'cima')
            m.solido(x,y); m.solido(x,y+1); m.ocupado[y*W+x]=m.ocupado[(y+1)*W+x]=True
    for _ in range(600):
        x,y=m.rng.randrange(1,W-1),m.rng.randrange(3,H-3)
        if sum(1 for r in m.reg if r[0]=='pinheiro')>=c.get('pinos',12): break
        if not m.M_trilha[y][x] and not any(abs(x-r[1])<3 and abs(y-r[2])<3 for r in m.reg if r[0]=='pinheiro'): pin(x,y)
    for _ in range(900):
        x,y=m.rng.randrange(W),m.rng.randrange(3,H-1)
        if livre1(x,y) and not m.M_trilha[y][x] and not m.ocupado[y*W+x] and m.rng.random()<fp:
            cc,r=m.rng.choice(m.FLP()); m.poe(x,y,CO,cc,r); m.ocupado[y*W+x]=True
    for _ in range(c.get('cristais',0)*40):
        if sum(1 for q in m.cam['objetos'].values() if q[0]==CO and (q[1],q[2]) in CRIS)>=c.get('cristais',0): break
        x,y=m.rng.randrange(1,W-1),m.rng.randrange(3,H-2)
        if livre1(x,y) and not m.ocupado[y*W+x] and not m.M_trilha[y][x]:
            cc,r=m.rng.choice(CRIS); m.poe(x,y,CO,cc,r); m.solido(x,y); m.ocupado[y*W+x]=True
    # ponto de partida da busca
    d0=[v for k,v in pt.items() if not k.startswith('gin')][0]
    sx,sy=d0[0]+d0[2]//2,d0[1]+d0[3]//2
    sx=min(max(sx,1),W-2) if d0[1] in(0,H-1) else sx
    if d0[1]==0: sy=1
    elif d0[1]==H-1: sy=H-2
    if d0[0]==0: sx=1
    elif d0[0]==W-1: sx=W-2
    def alcance():
        s=(sx,sy); seen={s}; q=deque([s])
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
            if not m.sol[y*W+x] and (x,y) not in sv and (x,y) not in gr:
                if (x,y) in m.cam['objetos']: del m.cam['objetos'][(x,y)]
                if not m.pedra(x,y):
                    m.poe(x,y,*m.ROCHAS[0] if hasattr(m,'ROCHAS') else (CO,29,30)); m.solido(x,y); m.ocupado[y*W+x]=True
    sv=alcance()
    bols=[(x,y) for y in range(H) for x in range(W) if not m.sol[y*W+x] and (x,y) not in sv]
    assert not bols,('bolsoes',bols[:6])
    old=json.load(open(f'{REPO}/{mid}.json'))
    portais=[]
    for p in old['portais']:
        q=dict(p)
        if p['dest'].startswith('gin'):
            q.update(x=P['gin'][0],y=P['gin'][1],w=1,h=1)
        else: q.update(zip(('x','y','w','h'),pt[p['dest']]))
        portais.append(q)
    pois=[]
    for p in old['pois']:
        q=dict(p)
        px=P.get(p['id']) or c.get('poix',{}).get(p['id'])
        assert px,('poi sem local',p['id'])
        q['x'],q['y']=px
        pois.append(q)
    sol=''.join('1' if m.sol[y*W+x] else '0' for y in range(H) for x in range(W))
    def bio(x,y):
        if sol[y*W+x]=='1': return 'A' if m.M_agua and m.M_agua[y][x] else '#'
        if m.M_trilha[y][x]: return 'E'
        if (x,y) in gr: return 'G'
        return 'C'
    BIO=''.join(bio(x,y) for y in range(H) for x in range(W))
    J=dict(old,solido=sol,grama=''.join('1' if (x,y) in gr else '0' for y in range(H) for x in range(W)),bioma=BIO,portais=portais,pois=pois)
    json.dump(J,open(f'saida/{mid}.json','w'),ensure_ascii=False)
    GA=os.path.expanduser('~/mnt/pkm-rpg/public/assets/grama-alta.png')
    salvar_tmx(m,os.path.abspath(f'../tmx/{mid}.tmx'),portais,pois,None,extras={'grama_alta':(gr,GA)} if gr else None)
    b,cc,_,_=renderizar_tmx(f'../tmx/{mid}.tmx')
    b.save(f'saida/{mid}.png'); cc.save(f'saida/{mid}-cima.png')
    im=b.copy()
    if gr:
        ga=Image.open(GA).convert('RGBA')
        for (x,y) in gr: im.alpha_composite(ga,(x*16,y*16))
    im.alpha_composite(cc); im.resize((W*28,H*28),Image.NEAREST).save(f'../{mid}_tmx_v1.png')
    return m
