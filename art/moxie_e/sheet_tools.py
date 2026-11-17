"""Model-sheet utilities for candidate E.

  python sheet_tools.py cut <in.png> <out_rgba.png>          flat-grey background -> alpha (border flood fill)
  python sheet_tools.py norm                                   cut + normalise all body views, write docs/reference/generated/*
  python sheet_tools.py check                                  print/plot the silhouette agreement between views

Run with the venv python (numpy + scipy + PIL): C:/Users/joeya/.t3/tools/venv-gen/Scripts/python.exe
"""
import sys, os
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GEN = os.path.join(ROOT, 'docs', 'reference', 'generated')
WORK = os.path.join(GEN, 'work')
GREY = (128, 128, 128)


def cutout(im, tol=26, feather=1.0):
    """Remove the flat background by flood-filling from the image border.
    Background colour is estimated from the border pixels; the ink outline stops the fill."""
    rgb = np.asarray(im.convert('RGB')).astype(np.int16)
    h, w, _ = rgb.shape
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    dist = np.abs(rgb - bg).max(axis=2)
    cand = dist < tol
    lab, n = ndi.label(cand)
    ids = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    ids = ids[ids > 0]
    bgmask = np.isin(lab, ids)
    # enclosed background islands (between arm and torso, inside hair loops): any big blob of
    # background colour that is very close to the bg colour
    strict = dist < 10
    lab2, n2 = ndi.label(strict & ~bgmask)
    if n2:
        sizes = ndi.sum(np.ones_like(lab2), lab2, index=np.arange(1, n2 + 1))
        big = np.where(sizes > 150)[0] + 1
        bgmask |= np.isin(lab2, big)
    fg = ~bgmask
    fg = ndi.binary_opening(fg, iterations=1)
    # keep the main component and anything touching near it
    lab3, n3 = ndi.label(fg)
    if n3 > 1:
        sizes = ndi.sum(np.ones_like(lab3), lab3, index=np.arange(1, n3 + 1))
        keep = np.where(sizes > 0.002 * sizes.max())[0] + 1
        fg = np.isin(lab3, keep)
    a = ndi.gaussian_filter(fg.astype(np.float32), feather)
    a = np.clip((a - 0.35) / 0.4, 0, 1)
    out = np.dstack([np.asarray(im.convert('RGB')), (a * 255).astype(np.uint8)])
    return Image.fromarray(out, 'RGBA')


def bbox(rgba, thr=128):
    a = np.asarray(rgba)[:, :, 3] > thr
    ys = np.where(a.any(axis=1))[0]
    xs = np.where(a.any(axis=0))[0]
    return xs[0], ys[0], xs[-1] + 1, ys[-1] + 1


def place(rgba, canvas, height_px, baseline, cx=None, anchor_x=None):
    """Scale so the figure is height_px tall, feet on baseline, anchor_x (source px) at canvas centre."""
    x0, y0, x1, y1 = bbox(rgba)
    s = height_px / (y1 - y0)
    crop = rgba.crop((x0, y0, x1, y1))
    crop = crop.resize((max(1, round((x1 - x0) * s)), height_px), Image.LANCZOS)
    out = Image.new('RGBA', canvas, (0, 0, 0, 0))
    if anchor_x is None:
        anchor_x = (x0 + x1) / 2
    px = round(canvas[0] / 2 - (anchor_x - x0) * s) if cx is None else cx
    out.alpha_composite(crop, (px, baseline - height_px))
    return out


def on_grey(rgba):
    bg = Image.new('RGBA', rgba.size, GREY + (255,))
    bg.alpha_composite(rgba)
    return bg.convert('RGB')


def body_axis_x(rgba):
    """x of the body centre line: centre of the silhouette in the pelvis band (45-55% height)."""
    a = np.asarray(rgba)[:, :, 3] > 128
    x0, y0, x1, y1 = bbox(rgba)
    h = y1 - y0
    band = a[y0 + int(0.02 * h): y0 + int(0.10 * h)]  # head band: symmetric, arms not included
    xs = np.where(band.any(axis=0))[0]
    return (xs[0] + xs[-1]) / 2


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'cut':
        cutout(Image.open(sys.argv[2])).save(sys.argv[3])

VIEWS = {  # name -> work file
    'front': 'front_a3', 'back': 'back_a1', 'left': 'left_a2', 'right': 'right_a1',
    'threequarter': 'q34_a1',
}
H = 1400; CANVAS = (1152, 1536); BASE = 1480


def norm():
    os.makedirs(os.path.join(GEN, 'cut'), exist_ok=True)
    for name, src in VIEWS.items():
        im = Image.open(os.path.join(WORK, src + '.png')).convert('RGB')
        if name == 'left':  # the chevrons belong to the right sleeve only: paint them out
            a = np.asarray(im).copy()
            box = a[370:432, 515:595]
            m = box.min(axis=2) > 150
            m = ndi.binary_dilation(m, iterations=2)
            box[m] = (52, 40, 42)
            im = Image.fromarray(a)
        c = cutout(im)
        ax = body_axis_x(c) if name in ('front', 'back') else None
        p = place(c, CANVAS, H, BASE, anchor_x=ax)
        p.save(os.path.join(GEN, 'cut', f'moxie_{name}.png'))
        on_grey(p).save(os.path.join(GEN, f'moxie_{name}.png'))
        print(name, bbox(p))
    # T-pose: same figure height in pixels on a wider canvas
    c = cutout(Image.open(os.path.join(WORK, 'tpose_a1.png')))
    p = place(c, (2304, 1536), H, BASE, anchor_x=body_axis_x(c))
    p.save(os.path.join(GEN, 'cut', 'moxie_tpose_front.png'))
    on_grey(p).save(os.path.join(GEN, 'moxie_tpose_front.png'))


def check():
    """Row-by-row comparison of the silhouettes: front vs mirrored back (should match almost exactly),
    left vs mirrored right, and the vertical landmark rows across all views."""
    def mask(n):
        return np.asarray(Image.open(os.path.join(GEN, 'cut', f'moxie_{n}.png')))[:, :, 3] > 128
    f, b, l, r = mask('front'), mask('back'), mask('left'), mask('right')
    iou = lambda a, c: (a & c).sum() / (a | c).sum()
    print('IoU front vs mirrored back : %.3f' % iou(f, b[:, ::-1]))
    print('IoU left  vs mirrored right: %.3f' % iou(l, r[:, ::-1]))
    # landmark rows: first row from the top where the silhouette gets wider than X etc. are fragile;
    # use the row-width profiles' correlation instead
    for a, c, n in ((f, b, 'front/back'), (l, r, 'left/right')):
        wa, wc = a.sum(axis=1).astype(float), c.sum(axis=1).astype(float)
        print('row-width profile correlation %s: %.4f' % (n, np.corrcoef(wa, wc)[0, 1]))
    # overlay image
    def tint(m, col):
        o = np.zeros(m.shape + (3,), np.uint8); o[m] = col; return o
    ov1 = np.clip(tint(f, (255, 60, 0)).astype(int) + tint(b[:, ::-1], (0, 160, 255)), 0, 255).astype(np.uint8)
    ov2 = np.clip(tint(l, (255, 60, 0)).astype(int) + tint(r[:, ::-1], (0, 160, 255)), 0, 255).astype(np.uint8)
    q = mask('threequarter')
    ov3 = np.clip(tint(f, (255, 60, 0)).astype(int) + tint(q, (0, 160, 255)), 0, 255).astype(np.uint8)
    sheet = Image.fromarray(np.hstack([ov1, ov2, ov3])).resize((CANVAS[0] * 3 // 2, CANVAS[1] // 2))
    d = ImageDraw.Draw(sheet)
    d.text((10, 10), 'front (orange) vs mirrored back (blue); white = agree', fill='white')
    d.text((CANVAS[0] // 2 + 10, 10), 'left vs mirrored right', fill='white')
    d.text((CANVAS[0] + 10, 10), 'front vs three-quarter (height check)', fill='white')
    sheet.save(os.path.join(GEN, 'consistency_overlay.png'))


if __name__ == '__main__':
    if cmd == 'norm': norm()
    if cmd == 'check': check()
