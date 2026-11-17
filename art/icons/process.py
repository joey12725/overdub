"""Turn raw generated stickers (art/icons/raw/<group>/<id>.png) into final icons (assets/ui/icons/<group>/<id>.png).

  python -I art/icons/process.py [group/id ...]        (no args = every raw that has no _suffix)
  python -I art/icons/process.py --pick gear/foo=_v2    (use raw/gear/foo_v2.png as the source for gear/foo)

What it does, per icon:
  1. Rebuilds the cut-out instead of trusting the model's alpha (which is ragged): flood from the transparent
     outside through the model's own white border; whatever is not reached is the inked object ("core").
  2. Drops specks, then re-draws a uniform white sticker border of BORDER final pixels around the core.
  3. Scales so the longest side of the sticker fills 512 - 2*PAD, centres it on a 512x512 transparent canvas.
  4. Prints QA flags: EDGE (object touched the raw frame = probably cropped), PARTS (number of separate pieces).
"""
import sys, os, json, re
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
RAW = os.path.join(HERE, "raw")
OUT = os.path.join(ROOT, "assets", "ui", "icons")
SIZE, PAD, BORDER = 512, 24, 8
PICKS = os.path.join(HERE, "picks.json")


def cutout(im):
    a = np.asarray(im.convert("RGBA")).astype(np.int32)
    rgb, al = a[..., :3], a[..., 3]
    seed = al < 128
    near_white = (al >= 128) & (rgb.min(-1) > 236) & ((rgb.max(-1) - rgb.min(-1)) < 16)
    passable = seed | near_white
    # require the passage to be a few px wide so a hairline gap in the ink outline does not leak the flood inside
    er = ndi.binary_erosion(passable, iterations=2, border_value=1)
    lab, n = ndi.label(er)
    hit = np.unique(lab[seed & er])
    outside_er = np.isin(lab, hit[hit > 0])
    outside = (ndi.binary_dilation(outside_er, iterations=3) & passable) | seed
    core = ~outside
    core = ndi.binary_opening(core, iterations=2)
    lab, n = ndi.label(core)
    if n == 0:
        raise ValueError("empty")
    areas = ndi.sum(core, lab, range(1, n + 1))
    keep = [i + 1 for i, ar in enumerate(areas) if ar >= max(500, 0.004 * areas.max())]
    core = np.isin(lab, keep)
    # fill pin-holes (alpha noise); real holes (big) stay open
    holes = ndi.binary_fill_holes(core) & ~core
    lab, n = ndi.label(holes)
    if n:
        areas = ndi.sum(holes, lab, range(1, n + 1))
        core |= np.isin(lab, [i + 1 for i, ar in enumerate(areas) if ar < 1500])
    # composite over white so filled pixels are never black-transparent
    al3 = (al[..., None] / 255.0)
    a = a.copy()
    a[..., :3] = (rgb * al3 + 255 * (1 - al3)).astype(np.int32)
    return a, core, len(keep)


def process(src, dst):
    im = Image.open(src)
    a, core, parts = cutout(im)
    H, W = core.shape
    ys, xs = np.where(core)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    edge = y0 <= 1 or x0 <= 1 or y1 >= H - 1 or x1 >= W - 1
    s = (SIZE - 2 * PAD - 2 * BORDER) / max(y1 - y0, x1 - x0)
    bw = BORDER / s
    m = int(bw + 4)
    core_p = np.pad(core, m)
    rgb_p = np.pad(a[..., :3], ((m, m), (m, m), (0, 0)), constant_values=255)
    dist = ndi.distance_transform_edt(~core_p)
    alpha = np.clip(bw - dist + 0.5, 0, 1)
    out = np.where(core_p[..., None], rgb_p, 255).astype(np.uint8)
    rgba = np.dstack([out, (alpha * 255).astype(np.uint8)])
    Y0, Y1, X0, X1 = y0 + m - int(bw) - 1, y1 + m + int(bw) + 1, x0 + m - int(bw) - 1, x1 + m + int(bw) + 1
    crop = Image.fromarray(rgba, "RGBA").crop((X0, Y0, X1, Y1))
    tw, th = max(1, round(crop.width * s)), max(1, round(crop.height * s))
    k = min((SIZE - 2 * PAD) / tw, (SIZE - 2 * PAD) / th, 1.0)
    tw, th = round(tw * k), round(th * k)
    # premultiplied resize so no dark/white fringe
    arr = np.asarray(crop).astype(np.float32) / 255
    pm = np.dstack([arr[..., :3] * arr[..., 3:], arr[..., 3]])
    chans = [Image.fromarray((pm[..., i] * 255).astype(np.uint8)).resize((tw, th), Image.LANCZOS) for i in range(4)]
    r = np.dstack([np.asarray(c).astype(np.float32) for c in chans])
    al = r[..., 3:4]
    rgbu = np.where(al > 0, r[..., :3] * 255 / np.maximum(al, 1), 255)
    small = Image.fromarray(np.dstack([np.clip(rgbu, 0, 255), al]).astype(np.uint8), "RGBA")
    canvas = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    canvas.paste(small, ((SIZE - tw) // 2, (SIZE - th) // 2))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    canvas.save(dst, optimize=True)
    return edge, parts


def main():
    args = sys.argv[1:]
    picks = json.load(open(PICKS)) if os.path.exists(PICKS) else {}
    sel = []
    while args:
        x = args.pop(0)
        if x == "--pick":
            k, v = args.pop(0).split("=")
            picks[k] = v
            sel.append(k)
        else:
            sel.append(x)
    json.dump(picks, open(PICKS, "w"), indent=1, sort_keys=True)
    if not sel:
        for g in ("gear", "abilities", "slots"):
            d = os.path.join(RAW, g)
            if os.path.isdir(d):
                sel += [g + "/" + f[:-4] for f in sorted(os.listdir(d)) if f.endswith(".png") and not re.search(r"_v\d+\.png$", f)]
    for k in sel:
        src = os.path.join(RAW, k + picks.get(k, "") + ".png")
        try:
            edge, parts = process(src, os.path.join(OUT, k + ".png"))
            print("%-28s %s parts=%d%s" % (k, picks.get(k, "raw"), parts, "  EDGE!" if edge else ""))
        except Exception as e:
            print("%-28s FAILED %r" % (k, e))


main()
