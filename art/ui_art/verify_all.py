"""Final gate: dimensions, mode, alpha sanity and slice margins for everything in assets/ui/art.
   python -I art/ui_art/verify_all.py   (exit 1 on any failure)"""
import sys, os, json, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from lib import OUT
sl = json.load(open(os.path.join(OUT, 'ui', 'slices.json')))
bad = 0
def fail(rel, msg):
    global bad; bad += 1; print('FAIL', rel, msg)
EXPECT = {'keyart/title_1536x1024.png': (1536, 1024), 'keyart/title_1024x1536.png': (1024, 1536), 'keyart/title_1600x900.png': (1600, 900)}
for p in sorted(glob.glob(os.path.join(OUT, '**', '*.png'), recursive=True)):
    rel = os.path.relpath(p, OUT).replace(os.sep, '/')
    im = Image.open(p); im.load()
    opaque = rel.startswith(('keyart/', 'cards/'))
    if rel in EXPECT and im.size != EXPECT[rel]: fail(rel, 'size %s' % (im.size,))
    if rel.startswith('cards/') and im.size != (1536, 1024): fail(rel, 'size %s' % (im.size,))
    if opaque:
        if im.mode != 'RGB': fail(rel, 'mode ' + im.mode)
        print('ok  %-44s %4dx%-4d RGB opaque' % (rel, *im.size)); continue
    if im.mode != 'RGBA': fail(rel, 'mode ' + im.mode); continue
    a = np.asarray(im); al = a[..., 3]
    t0, t255 = (al == 0).mean() * 100, (al == 255).mean() * 100
    part = 100 - t0 - t255
    tile = rel.startswith('ui/ruler')
    if tile:
        if t255 < 99.9: fail(rel, 'tile not opaque')
        # seamless check: left and right edge columns must match
        d = np.abs(a[:, 0, :3].astype(int) - a[:, -1, :3].astype(int)).mean()
        if d > 6: fail(rel, 'tile seam diff %.1f' % d)
    else:
        if t255 < 0.5: fail(rel, 'almost no solid pixels (alpha255 %.1f%%)' % t255)
        if al[0, 0] or al[0, -1] or al[-1, 0] or al[-1, -1]: fail(rel, 'canvas corner not transparent')
        if part > 20: fail(rel, 'too much partial alpha %.1f%%' % part)
    m = sl.get(rel)
    extra = ''
    if m and 'left' in m:
        if list(im.size) != m['size']: fail(rel, 'slices.json size mismatch')
        if m['left'] + m['right'] >= im.width or (m['top'] + m['bottom'] >= im.height and m['top'] + m['bottom'] > 0): fail(rel, 'margins exceed texture')
        l, t, r, b = m['left'], m['top'], m['right'], m['bottom']
        mid = a[:, l:im.width - r].astype(int)
        if np.abs(mid - mid[:, :1]).max() > 0: fail(rel, 'horizontal middle band is not constant')
        if t + b:
            midv = a[t:im.height - b].astype(int)
            if np.abs(midv - midv[:1]).max() > 0: fail(rel, 'vertical middle band is not constant')
        extra = ' slice l%d t%d r%d b%d' % (l, t, r, b)
    print('ok  %-44s %4dx%-4d RGBA a0=%4.1f%% a255=%4.1f%% partial=%4.1f%%%s' % (rel, *im.size, t0, t255, part, extra))
print('FAILURES:', bad); sys.exit(1 if bad else 0)
