from cidade import *
m=gerar(dict(id='verdelume',W=40,H=40,seed=62,
 ruas=[(13,0,5,40),(3,8,34,5),(3,19,37,5),(3,31,34,5)],
 predios=[('gin',3,4,'ginasio_cinza'),('biblioteca',20,4,'casa_grande'),('centro',30,4,'centro'),
          ('estufa1',3,15,'casa_madeira_a'),('estufa2',8,15,'casa_madeira_a'),('estufa3',20,15,'casa_madeira_a'),('mart',25,15,'mart'),('celeiro',32,15,'casa_pagode'),
          ('casa_lis',3,27,'casa_pagode'),('casa_bento',20,27,'casa_madeira_b')],
 fontes=[(33,28)],
 portais={'gin_verdelume':(0,0,1,1),'caminho_va':(39,20,1,3),'rota3':(14,39,3,1),'rota4':(14,0,3,1)},
 pedras=8,pinos=8,flores=0.35,dens=0.97,seam=20,arv=[(44,1),(46,1),(44,5),(46,5),(48,1)]))
