"""Shared helpers for the UI art build scripts (PIL + numpy only)."""
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
RAW = os.path.join(ROOT, 'art', 'ui_art', 'raw')
OUT = os.path.join(ROOT, 'assets', 'ui', 'art')


def load(name):
    return Image.open(os.path.join(RAW, name + '.png')).convert('RGBA')


def clean_alpha(im, lo=14, hi=232):
    """Snap near-transparent to 0 and near-opaque to 255 (the model returns ~250-254 for solid)."""
    a = np.asarray(im).copy()
    al = a[..., 3].astype(np.float32)
    al = np.clip((al - lo) / (hi - lo), 0, 1) * 255
    a[..., 3] = al.round().astype(np.uint8)
    a[a[..., 3] == 0, :3] = 0
    return Image.fromarray(a, 'RGBA')


def drop_specks(im, min_area=400):
    """Remove small disconnected alpha islands (stray halo fragments)."""
    a = np.asarray(im).copy()
    mask = a[..., 3] > 0
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    cur = 0
    # simple two-pass-free flood using a stack on a downsampled grid would be lossy; do a scanline BFS
    from collections import deque
    for y0, x0 in zip(*np.nonzero(mask)):
        if lab[y0, x0]:
            continue
        cur += 1
        q = deque([(y0, x0)])
        lab[y0, x0] = cur
        pts = []
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = cur
                    q.append((yy, xx))
        if len(pts) < min_area:
            ys, xs = zip(*pts)
            a[ys, xs] = 0
    return Image.fromarray(a, 'RGBA')


def trim(im, pad=0):
    bb = im.getchannel('A').point(lambda v: 255 if v > 0 else 0).getbbox()
    im = im.crop(bb)
    if pad:
        c = Image.new('RGBA', (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
        c.paste(im, (pad, pad))
        im = c
    return im


def fit(im, w, h, pad=0):
    """Scale to fit inside (w,h) minus padding, centred on a transparent canvas."""
    s = min((w - 2 * pad) / im.width, (h - 2 * pad) / im.height)
    r = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    c = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    c.paste(r, ((w - r.width) // 2, (h - r.height) // 2))
    return c


def save(im, rel):
    p = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    im.save(p, optimize=True)
    print('wrote', rel, im.size, im.mode)
