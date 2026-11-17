"""tile.py <out.png> <cols> <in1.png> ...   (PIL contact sheet; optional --bg r,g,b and --h N to resize rows)"""
import sys
from PIL import Image
args = sys.argv[1:]; bg = (40, 40, 44); H = None
if '--bg' in args: i = args.index('--bg'); bg = tuple(int(x) for x in args[i + 1].split(',')); del args[i:i + 2]
if '--h' in args: i = args.index('--h'); H = int(args[i + 1]); del args[i:i + 2]
out, cols, paths = args[0], int(args[1]), args[2:]
ims = [Image.open(p).convert('RGBA') for p in paths]
if H: ims = [im.resize((round(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
w = max(i.width for i in ims); h = max(i.height for i in ims); rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (cols * w, rows * h), bg)
for k, im in enumerate(ims):
    r, c = divmod(k, cols); tile = Image.new('RGBA', (w, h), bg + (255,)); tile.alpha_composite(im, ((w - im.width) // 2, (h - im.height) // 2)); sheet.paste(tile.convert('RGB'), (c * w, r * h))
sheet.save(out); print('wrote', out, sheet.size)
