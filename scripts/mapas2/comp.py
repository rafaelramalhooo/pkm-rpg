from PIL import Image
import numpy as np
from collections import deque
def comps(path,gap=1):
    im=Image.open(path).convert('RGBA'); a=np.array(im)[:,:,3]>0
    H,W=a.shape; seen=np.zeros_like(a); res=[]
    for y in range(H):
        for x in range(W):
            if a[y,x] and not seen[y,x]:
                q=deque([(y,x)]); seen[y,x]=True; x0=x1=x; y0=y1=y
                while q:
                    cy,cx=q.popleft(); x0=min(x0,cx);x1=max(x1,cx);y0=min(y0,cy);y1=max(y1,cy)
                    for dy in range(-gap,gap+1):
                        for dx in range(-gap,gap+1):
                            ny,nx=cy+dy,cx+dx
                            if 0<=ny<H and 0<=nx<W and a[ny,nx] and not seen[ny,nx]: seen[ny,nx]=True; q.append((ny,nx))
                res.append((x0,y0,x1+1,y1+1))
    return res,im.size
if __name__=='__main__':
    import sys,glob,os
    T='/tmp/tux/mods/pacote/gfx/tilesets/'
    for f in sorted(os.listdir(T)):
        if not f.lower().endswith('.png'): continue
        try:
            im=Image.open(T+f)
            if im.size[0]*im.size[1]>400000: continue
            r,s=comps(T+f)
            al=sum(1 for q in r if all(v%16==0 for v in q))
            print(f,s,len(r),'alinhados',al)
        except Exception as e: print(f,e)
