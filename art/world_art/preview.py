"""Composite RGBA images side by side on warm-stone and dark-metal swatches for eyeballing.
usage: python -I art/world_art/preview.py out.png a.png b.png ..."""
import sys
from PIL import Image
STONE=(196,160,128); METAL=(52,40,62)
def tile(p, cell=384):
    im=Image.open(p).convert('RGBA'); im.thumbnail((cell-16,cell-16))
    out=Image.new('RGB',(cell*2,cell))
    for i,c in enumerate((STONE,METAL)):
        bg=Image.new('RGBA',(cell,cell),c+(255,))
        bg.alpha_composite(im,((cell-im.width)//2,(cell-im.height)//2))
        out.paste(bg.convert('RGB'),(i*cell,0))
    return out
if __name__=='__main__':
    ts=[tile(p) for p in sys.argv[2:]]
    sh=Image.new('RGB',(ts[0].width,sum(t.height for t in ts)))
    y=0
    for t in ts: sh.paste(t,(0,y)); y+=t.height
    sh.save(sys.argv[1])
