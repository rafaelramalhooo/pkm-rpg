from interior import *
mid='lab'; W,H=13,18
m=IMapa(W,H,5)
sala(m,(0,14),(9,2))
carpete(m,3,7,7,7,26,6)
m.item(1,2,10,46,2,3)
m.item(3,2,12,46,2,3)
m.item(8,2,10,49,4,3)
m.item(5,9,0,10,4,3)
m.item(1,8,8,19,2,2)
m.item(10,8,5,14,2,2)
m.item(1,14,10,28,2,2)
m.item(10,14,13,28,2,2)
fechar(m,mid,[dict(x=5,y=17,w=3,h=1,dest='pallet',dx=22,dy=11,dir='baixo')],[dict(id='prof',tipo='lab',x=6,y=7)],{'x':6,'y':14})
