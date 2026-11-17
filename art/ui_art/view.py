"""Thumbnail montage for eyeballing: python -I art/ui_art/view.py <out.png> <cols> <cellw> <cellh> <png>..."""
import sys
from PIL import Image
out, cols, cw, ch = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
names = sys.argv[5:]
rows = (len(names) + cols - 1) // cols
im = Image.new('RGB', (cols * cw, rows * ch), (40, 34, 30))
for i, n in enumerate(names):
    t = Image.open(n).convert('RGBA'); t.thumbnail((cw - 8, ch - 8))
    im.paste(t, ((i % cols) * cw + 4, (i // cols) * ch + 4), t)
im.save(out)
