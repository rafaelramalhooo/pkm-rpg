import json,sys,shutil,os
REPO=os.path.expanduser('~/mnt/pkm-rpg/public/assets/mapas')
ids=json.load(open(REPO+'/_indice.json'))
M={i:json.load(open(f'saida/{i}.json')) for i in ids}
OLD={i:json.load(open(f'{REPO}/{i}.json')) for i in ids}
def solido(m,x,y): return not(0<=x<m['w'] and 0<=y<m['h']) or m['solido'][y*m['w']+x]=='1'
def frente(R):
    cx=R['x']+R['w']//2; cy=R['y']+R['h']//2; d=R['dir']
    return {'direita':(R['x']-1,cy),'esquerda':(R['x']+R['w'],cy),'cima':(cx,R['y']+R['h']),'baixo':(cx,R['y']-1)}[d]
def livre_perto(m,x,y):
    for r in range(0,6):
        for dy in range(-r,r+1):
            for dx in range(-r,r+1):
                if max(abs(dx),abs(dy))==r and not solido(m,x+dx,y+dy) and not any(p['x']<=x+dx<p['x']+p['w'] and p['y']<=y+dy<p['y']+p['h'] for p in m['portais']): return x+dx,y+dy
    raise SystemExit(f'sem chegada livre {m["id"]} {x},{y}')
mud=0
for i,m in M.items():
    for p in m['portais']:
        d=p['dest']; rev=[q for q in M[d]['portais'] if q['dest']==i]
        if not rev and d=='plato': rev=[q for q in M['plato']['portais'] if q['dest']=='liga_salao1']
        if not rev:
            op={'cima':'baixo','baixo':'cima','esquerda':'direita','direita':'esquerda'}[p['dir']]
            rev=[q for q in M[d]['portais'] if q['dir']==op]
        assert rev,(i,d)
        x,y=frente(rev[0]); 
        if solido(M[d],x,y): x,y=livre_perto(M[d],x,y)
        if (p['dx'],p['dy'])!=(x,y): mud+=1
        p['dx'],p['dy']=x,y
# paridade de chaves com o repositorio atual
for i in ids:
    falta=set(OLD[i])-set(M[i])
    if falta: print('chaves antigas ausentes',i,falta)
for m in M.values():
    g=list(m['grama'])
    for k,ch in enumerate(m['solido']):
        if ch=='1' and g[k]!='0': g[k]='0'
    m['grama']=''.join(g)
print('chegadas alteradas',mud)
if '--aplicar' in sys.argv:
    for i,m in M.items():
        json.dump(m,open(f'{REPO}/{i}.json','w'),ensure_ascii=False,separators=(',',':'))
        shutil.copy(f'saida/{i}.png',f'{REPO}/{i}.png'); shutil.copy(f'saida/{i}-cima.png',f'{REPO}/{i}-cima.png')
    print('aplicado')
