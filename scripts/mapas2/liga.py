from gin import *
LIGA={
 'liga_salao1':('Gelo',(0,14),(11,2),(32,15),['tub_vazia','esp1','tub_vazia'],['tub_vazia','esp3','tub_vazia'],'liga_salao2',True),
 'liga_salao2':('Combate',(0,0),(13,2),(26,3),['banco','saco_r','esteira','saco_v'],['banco2','saco_v','esteira','saco_r'],'liga_salao3',True),
 'liga_salao3':('Sombras',(14,7),(8,15),(32,9),['cav1','saco_a','cav2','saco_a'],['cav3','saco_a','cav1','saco_a'],'liga_salao4',True),
 'liga_salao4':('Ceus',(14,14),(12,2),(26,9),['planta','bola_a','planta','bola_a'],['planta','bola_a','planta','bola_a'],'liga_campeao',True),
 'liga_campeao':('Campeao',(14,0),(14,2),(32,12),['cand','mapa','cand','mapa'],['cand','mapa','cand','mapa'],None,False),
}
if __name__=='__main__':
    for k,(n,pa,pi,tap,L,R,prox,sobe) in LIGA.items():
        m=gin(k,pa,pi,tap,L,R,[])
        port=[dict(x=9,y=19,w=3,h=1,dest='plato',dx=19,dy=16,dir='baixo')]
        if prox:
            porta_topo(m,wc=pa); port.append(dict(x=9,y=4,w=3,h=1,dest=prox,dx=10,dy=18,dir='cima'))
        fechar(m,k,port,[],{'x':10,'y':18}); print(k,'ok')
    from PIL import Image
    nomes=list(LIGA); fs=[Image.open(f'../{k}_tmx_v1.png') for k in nomes]
    w,h=fs[0].size; S=Image.new('RGB',(w*3//2,h*2//2),(30,30,30))
    for i,f in enumerate(fs): S.paste(f.resize((w//2,h//2),Image.NEAREST),((i%3)*w//2,(i//3)*h//2))
    S.save('../ligas.png')
