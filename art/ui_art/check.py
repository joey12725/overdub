"""Alpha/dimension report + preview on dark / checker backgrounds.
   python -I art/ui_art/check.py <png> [...]   -> writes art/ui_art/raw/_prev_<name>.png"""
import sys, os
from PIL import Image
import numpy as np
for p in sys.argv[1:]:
    im = Image.open(p)
    print(os.path.basename(p), im.size, im.mode, end=' ')
    if im.mode != 'RGBA':
        print('NO ALPHA'); continue
    a = np.asarray(im)[..., 3]
    ys, xs = np.nonzero(a > 8)
    bbox = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1) if len(xs) else None
    print('alpha0=%.1f%% alpha255=%.1f%% partial=%.1f%% bbox=%s corners=%s' % (
        (a == 0).mean() * 100, (a == 255).mean() * 100, ((a > 0) & (a < 255)).mean() * 100, bbox,
        [int(a[0, 0]), int(a[0, -1]), int(a[-1, 0]), int(a[-1, -1])]))
    w, h = im.size
    out = Image.new('RGB', (w * 2, h), (27, 23, 20))
    out.paste(im, (0, 0), im)
    mag = Image.new('RGB', (w, h), (255, 0, 255))
    mag.paste(im, (0, 0), im)
    out.paste(mag, (w, 0))
    out.thumbnail((1600, 1600))
    out.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'raw', '_prev_' + os.path.basename(p)))
