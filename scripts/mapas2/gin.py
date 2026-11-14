from interior import *
import sys
IT={'banco':(2,97,2,3),'banco2':(4,97,2,3),'esteira':(3,105,2,3),'saco_v':(6,84,1,3),'saco_g':(6,87,1,3),'saco_a':(6,90,1,3),'saco_r':(6,93,1,3),
 'bola_a':(7,84,2,2),'bola_v':(7,86,2,2),'bola_r':(7,88,2,2),'bonsai':(7,98,1,2),'bonsai2':(8,98,1,2),'bonsai3':(7,100,1,2),'bonsai4':(8,100,1,2),
 'planta':(10,28,2,2),'palmeira':(13,28,2,2),'vaso1':(10,98,1,2),'vaso2':(11,98,1,2),'vaso3':(12,98,1,2),
 'cav1':(10,84,2,3),'cav2':(12,84,2,3),'cav3':(14,84,2,3),'est1':(10,46,2,3),'est2':(12,46,2,3),'est3':(14,46,2,3),'comp3':(10,49,4,3),'comp1':(14,49,2,3),
 'tub_pato':(10,116,2,4),'tub_azul':(12,116,2,4),'tub_vazia':(14,116,2,4),'pia_agua':(6,114,2,3),'esp1':(2,110,2,3),'esp2':(4,110,2,3),'esp3':(6,110,2,3),
 'cand':(4,31,2,2),'lampada':(0,30,2,3),'mapa':(12,32,2,2),'globo':(13,34,1,2),'globo2':(14,34,1,2),'barra':(0,96,2,1),'halt':(2,102,2,2),
 'tapete_r':(0,87,3,3),'tapete_c':(0,84,3,3),'tapete_a':(0,90,3,3),'mesa':(0,10,4,3),'pcs':(10,49,4,3)}

def gin(mid,parede,piso,tap,L,R,topo=()):
    m=IMapa(20,20,sum(map(ord,mid)))
    sala(m,parede,piso)
    carpete(m,6,6,8,4,*tap)
    carpete(m,8,10,4,9,*tap)
    ys=[6,10,14] if len(L)==3 else [6,9,12,15]
    for i,n in enumerate(L):
        c,r,w,h=IT[n]; m.item(2,ys[i],c,r,w,h)
    for i,n in enumerate(R):
        c,r,w,h=IT[n]; m.item(18-w,ys[i],c,r,w,h)
    for n,x in zip(topo,(3,15)):
        c,r,w,h=IT[n]; m.item(x,2,c,r,w,h)
    return m
CFG={
 'argila':((0,0),(13,2),(26,3),['banco','saco_r','esteira','saco_v'],['banco2','saco_v','esteira','saco_r'],['mapa','mapa']),
 'verdelume':((21,0),(11,2),(26,6),['palmeira','planta','palmeira','planta'],['planta','palmeira','planta','palmeira'],['globo','globo2']),
 'azurana':((0,14),(12,2),(26,9),['tub_azul','pia_agua','tub_vazia'],['tub_pato','pia_agua','tub_azul'],[]),
 'ambar':((7,0),(9,2),(32,12),['comp3','lampada','comp3','lampada'],['comp3','lampada','comp3','lampada'],[]),
 'carmesim':((14,0),(14,2),(32,6),['cand','bola_r','cand','bola_r'],['cand','bola_r','cand','bola_r'],[]),
 'ametista':((0,14),(15,2),(32,9),['esp1','cav1','esp2','cav3'],['esp3','cav2','esp1','cav1'],[]),
 'quartzo':((7,0),(10,2),(38,6),['bonsai2','vaso2','bonsai4','vaso3'],['bonsai4','vaso1','bonsai2','vaso2'],['est3','est2']),
 'obsidiana':((14,7),(8,15),(26,12),['cav1','saco_a','cav2','saco_a'],['cav3','saco_a','cav1','saco_a'],[]),
}
def arr(cidade):
    J=json.load(open(f'saida/{cidade}.json'))
    for p in J['portais']:
        if p['dest']=='gin_'+cidade: return p['x'],p['y']+1
    raise SystemExit('sem portal gin em '+cidade)
if __name__=='__main__':
    for k,(pa,pi,tap,L,R,topo) in CFG.items():
        m=gin(k,pa,pi,tap,L,R,topo)
        dx,dy=arr(k)
        fechar(m,'gin_'+k,[dict(x=9,y=19,w=3,h=1,dest=k,dx=dx,dy=dy,dir='baixo')],[],{'x':10,'y':18})
        print(k,'ok',dx,dy)
    from PIL import Image
    nomes=list(CFG); fs=[Image.open(f'../gin_{k}_tmx_v1.png') for k in nomes]
    w,h=fs[0].size; S=Image.new('RGB',(w*4//2,h*2//2),(30,30,30))
    for i,f in enumerate(fs): S.paste(f.resize((w//2,h//2),Image.NEAREST),((i%4)*w//2,(i//4)*h//2))
    S.save('../gins.png')
