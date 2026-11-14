"""Verificador automatico de mapas. Uso: python3 verificar.py [builder.py ...]
Roda o construtor, confere as regras e gera painel de zooms em ../verificacao/<id>/. Saida: ERRO (reprova) / AVISO."""
import sys, os, json, runpy
from collections import deque
from PIL import Image, ImageDraw
BUILDERS={'porto_tmx.py':'porto','rota1_tmx.py':'rota1','vila_tmx.py':'vila_alvorada','vila_alvorada.py':'vila_alvorada','rota1.py':'rota1','porto_turquesa.py':'porto','azurana.py':'azurana','azurana_tmx.py':'azurana','argila_tmx.py':'argila','verdelume_tmx.py':'verdelume','ambar_tmx.py':'ambar','carmesim_tmx.py':'carmesim','ametista_tmx.py':'ametista','quartzo_tmx.py':'quartzo','obsidiana_tmx.py':'obsidiana','vale_tmx.py':'vale','reserva_tmx.py':'reserva','cromatica_tmx.py':'cromatica','plato_tmx.py':'plato','rota2_tmx.py':'rota2','rota3_tmx.py':'rota3','rota4_tmx.py':'rota4','rota5_tmx.py':'rota5','rota6_tmx.py':'rota6','rota7a_tmx.py':'rota7a','rota8_tmx.py':'rota8','rota9_tmx.py':'rota9','rota10_tmx.py':'rota10','caminho_va_tmx.py':'caminho_va','costa1_tmx.py':'costa1','costa2_tmx.py':'costa2'}
REPO=os.path.expanduser('~/mnt/pkm-rpg/public/assets/mapas')
T=16
def vizinhos(x,y):
    return ((x+1,y),(x-1,y),(x,y+1),(x,y-1))
def verificar(arq):
    g=runpy.run_path(arq,run_name='__main__'); m=g['m']; W,H=m.w,m.h
    mid=BUILDERS.get(arq,arq[:-3]); J=json.load(open(f'saida/{mid}.json'))
    sol=lambda x,y: m.sol[y*W+x]
    err=[];av=[]
    E=lambda t:err.append(t); A=lambda t:av.append(t)
    dentro=lambda x,y:0<=x<W and 0<=y<H
    # 1) sobreposicao e arvore cortada
    ocup={}
    for r in m.reg:
        k,x,y,w,h=r[:5]
        for yy in range(y,y+h):
            for xx in range(x,x+w):
                if not dentro(xx,yy): E(f'{k} em ({x},{y}) sai do mapa'); continue
                if k in('arvore','predio') and not(k=='predio' and False):
                    pass
                if (xx,yy) in ocup and ocup[(xx,yy)][0]!=k+'?':
                    E(f'{k} em ({x},{y}) sobrepoe {ocup[(xx,yy)][0]} em ({xx},{yy})')
                ocup[(xx,yy)]=(k,x,y)
                if k in('arvore','pinheiro','pedra') and not sol(xx,yy): E(f'{k} em ({x},{y}) com tile nao solido: arvore cortada')
    # 2) portas
    portas=[]
    for r in m.reg:
        if r[0]=='predio':
            _,x,y,w,h,pd,nome=r; dx,dy=x+pd,y+h-1; portas.append((dx,dy,nome))
            if sol(dx,dy): E(f'porta de {nome} em ({dx},{dy}) esta solida')
            fx,fy=dx,dy+1
            if not dentro(fx,fy) or sol(fx,fy): E(f'frente da porta de {nome} ({fx},{fy}) bloqueada')
            elif J['bioma'][fy*W+fx] not in 'E': A(f'frente da porta de {nome} ({fx},{fy}) nao e trilha')
    alvos=[(p['x'],p['y'],p.get('id',p.get('dest'))) for p in J['pois']+J['portais']]
    pset={(a,b) for a,b,_ in portas}
    for x,y,i in alvos:
        pt=[p for p in J['portais'] if p.get('id',p.get('dest'))==i]
        if i in [p['dest'] for p in J['portais']] and not [q for q in J['pois'] if q['id']==i]:
            continue
        q0=[q for q in J['pois'] if q['id']==i]
        if q0 and q0[0].get('tipo') not in ('casa','loja','centro','ginasio','lab','predio'): continue
        if (x,y) not in pset and i not in getattr(m,'poix_ids',()): E(f'POI "{i}" em ({x},{y}) nao esta numa porta de predio')
    # portal com 'lab' dentro de predio conta como porta
    for p in J['portais']:
        if p['y'] in(0,H-1) or p['x'] in(0,W-1): continue
        if (p['x'],p['y']) not in pset: E(f'portal {p["dest"]} em ({p["x"]},{p["y"]}) nao esta numa porta')
    for a,b,nome in portas:
        if not any((q['x'],q['y'])==(a,b) for q in J['pois']+J['portais']): A(f'porta de {nome} em ({a},{b}) sem POI/portal (predio so decorativo)')
    pr=[r for r in m.reg if r[0]=='predio']
    for i,a in enumerate(pr):
        for b in pr[i+1:]:
            if a[2]<b[2]+b[4] and b[2]<a[2]+a[4] and (a[1]+a[3]==b[1] or b[1]+b[3]==a[1]): A(f'predios {a[6]} ({a[1]},{a[2]}) e {b[6]} ({b[1]},{b[2]}) colados lado a lado (parecem um bloco so)')
    # 3) enfeite em cima de porta/POI/portal/predio
    marc={(a,b) for a,b,_ in alvos}|pset
    for (x,y) in m.flores:
        if (x,y) in marc: E(f'flor em cima de porta/POI em ({x},{y})')
        if (x,y) in ocup and ocup[(x,y)][0]=='predio': E(f'flor dentro de predio em ({x},{y})')
    # 4) alcance
    ini=None
    for p in J['portais']:
        for yy in range(p['y'],p['y']+p['h']):
            for xx in range(p['x'],p['x']+p['w']):
                if ini is None and not sol(xx,yy): ini=(xx,yy)
    seen={ini}; q=deque([ini])
    while q:
        x,y=q.popleft()
        for a,b in vizinhos(x,y):
            if dentro(a,b) and not sol(a,b) and (a,b) not in seen: seen.add((a,b)); q.append((a,b))
    bolsoes=sum(1 for y in range(H) for x in range(W) if not sol(x,y) and (x,y) not in seen)
    if bolsoes: E(f'{bolsoes} tiles andaveis inalcancaveis')
    for x,y,i in alvos:
        if (x,y) not in seen: E(f'"{i}" ({x},{y}) inalcancavel')
    for p in J['portais']:
        ok=any((xx,yy) in seen for yy in range(p['y'],p['y']+p['h']) for xx in range(p['x'],p['x']+p['w']))
        if not ok: E(f'portal {p["dest"]} inalcancavel')
    # 4b) trilha sem destino
    T_=m.M_trilha; vis=set(); ancor=set()
    for a,b,_ in portas: ancor.add((a,b+1))
    for p in J['portais']:
        for yy in range(p['y'],p['y']+p['h']):
            for xx in range(p['x'],p['x']+p['w']): ancor.add((xx,yy))
    for y in range(H):
        for x in range(W):
            if T_ and T_[y][x] and (x,y) not in vis:
                comp=[];q=deque([(x,y)]);vis.add((x,y))
                while q:
                    c=q.popleft();comp.append(c)
                    for a,b in vizinhos(*c):
                        if dentro(a,b) and T_[b][a] and (a,b) not in vis: vis.add((a,b));q.append((a,b))
                borda=any(cx in(0,W-1) or cy in(0,H-1) for cx,cy in comp)
                if not(borda or any(c in ancor for c in comp)): E(f'trilha sem destino perto de {comp[0]} ({len(comp)} tiles)')
    # ramos cegos: celula de trilha longe (>9, Chebyshev) de qualquer ancora/borda
    pts=list(ancor)+[(x,y) for y in range(H) for x in range(W) if T_ and T_[y][x] and (x in(0,W-1) or y in(0,H-1))]
    if T_:
        for y in range(H):
            for x in range(W):
                if T_[y][x] and not any(max(abs(x-a),abs(y-b))<=9 for a,b in pts):
                    A(f'ramo de trilha longe de qualquer porta/saida em ({x},{y})'); break
            else: continue
            break
    # 5) agua
    ag=[[J['bioma'][y*W+x]=='A' for x in range(W)] for y in range(H)]
    vis=set()
    for y in range(H):
        for x in range(W):
            if ag[y][x] and (x,y) not in vis:
                comp=[];q=deque([(x,y)]);vis.add((x,y))
                while q:
                    c=q.popleft();comp.append(c)
                    for a,b in vizinhos(*c):
                        if dentro(a,b) and ag[b][a] and (a,b) not in vis: vis.add((a,b));q.append((a,b))
                if len(comp)<6: A(f'agua minuscula ({len(comp)} tiles) em {comp[0]}')
    for y in range(H):
        for x in range(W):
            if ag[y][x] and not sol(x,y): E(f'agua andavel em ({x},{y})')
    # 6) solido sem dono (baked)
    dono=sum(1 for y in range(H) for x in range(W) if sol(x,y) and (x,y) not in ocup and not ag[y][x])
    if dono: A(f'{dono} tiles solidos sem objeto registrado (fonte, cerca ou moldura de arvore)')
    # 7) vazio grande
    cheio=[[sol(x,y) or (T_ and T_[y][x]) or ag[y][x] or (x,y) in ocup for x in range(W)] for y in range(H)]
    for y in range(0,H-9):
        for x in range(0,W-9):
            if not any(cheio[yy][xx] for yy in range(y,y+10) for xx in range(x,x+10)):
                A(f'vazio grande 10x10 sem nada em ({x},{y})'); break
        else: continue
        break
    # 8) chegada em outros mapas
    for p in J['portais']:
        for base in ('saida',REPO):
            f=f"{base}/{p['dest']}.json"
            if os.path.exists(f):
                D=json.load(open(f)); ax,ay=p['dx'],p['dy']
                if not(0<=ax<D['w'] and 0<=ay<D['h']) or D['solido'][ay*D['w']+ax]=='1': A(f'chegada de {p["dest"]} em ({ax},{ay}) fora ou solida no mapa de destino')
                break
    # painel de zooms
    os.makedirs(f'../verificacao/{mid}',exist_ok=True)
    im=m.base.copy(); im.alpha_composite(m.cima); 
    def crop(cx,cy,r=4,esc=5):
        x0,y0=max(0,cx-r),max(0,cy-r); x1,y1=min(W,cx+r+1),min(H,cy+r+1)
        c=im.crop((x0*T,y0*T,x1*T,y1*T)).resize(((x1-x0)*T*esc,(y1-y0)*T*esc),Image.NEAREST)
        d=ImageDraw.Draw(c); px,py=(cx-x0)*T*esc,(cy-y0)*T*esc
        d.rectangle([px,py,px+T*esc,py+T*esc],outline=(255,215,0),width=3); return c
    lst=[(a,b) for a,b,_ in portas]+[(p['x'],p['y']) for p in J['portais'] if (p['x'],p['y']) not in pset]
    cs=[crop(a,b) for a,b in lst]
    if cs:
        cw=max(c.width for c in cs);ch=max(c.height for c in cs);col=4;rows=(len(cs)+col-1)//col
        S=Image.new('RGB',(cw*col,ch*rows),(40,40,40))
        for i,c in enumerate(cs): S.paste(c,((i%col)*cw,(i//col)*ch))
        S.save(f'../verificacao/{mid}/zoom_portas.png')
    im.resize((W*32,H*32),Image.NEAREST).save(f'../verificacao/{mid}/mapa.png')
    return mid,err,av
if __name__=='__main__':
    alvo=sys.argv[1:] or list(BUILDERS)
    for a in alvo:
        mid,err,av=verificar(a)
        print(f'== {mid}: {"REPROVADO" if err else "APROVADO"} ({len(err)} erros, {len(av)} avisos)')
        for e in err: print('  ERRO ',e)
        for e in av: print('  aviso',e)
