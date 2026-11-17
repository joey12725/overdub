"""
Turns the raw image-model output (art/wardrobe/src/) into the shipped wardrobe textures.

    python -I art/wardrobe/textures.py

  assets/textures/wardrobe/pattern_<id>.png   512 px, 8-bit grey, SEAMLESS mask
                                              (white = paint the look's pattern colour)
  assets/textures/wardrobe/decal_<id>.png     512 px RGBA, white graphic, alpha = coverage
  art/previews/wardrobe/tile_<id>.png         the pattern tiled 3x3 (look at these!)
  art/previews/wardrobe/_patterns.png         contact sheet of every 3x3 tiling
  art/previews/wardrobe/_decals.png           contact sheet of the decals

How a pattern is made seamless (the image model draws "tileable-looking" swatches, never exact
ones): a regular pattern has its repeat period measured by autocorrelation and a whole number of
periods is cut out and resampled to 512 px, which is exact; an irregular pattern (camo, static,
dropout) is joined to its own continuation along a minimum-difference path (image quilting)
and re-thresholded, so nothing ghosts and no shape is sliced; a grid of unrelated tiles (mirror) is cut exactly along its grout lines. Each result is scored by comparing the wrap-around seam with ordinary neighbouring rows.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import spec  # noqa: E402

SRC = os.path.join(HERE, "src")
TEX = os.path.join(ROOT, "assets", "textures", "wardrobe")
PREV = os.path.join(ROOT, "art", "previews", "wardrobe")
N = 512

# mode: "periodic" (measure the repeat) or "blend" (cross-fade + threshold).  min_period: ignore
# repeats shorter than this (x, y) px in the source.  hard: cut along grout lines, no cross-fade.  invert: the source
# drew the pattern dark on light.  periods: how many repeats to keep across the tile.
PATTERN_OPTS = {
    "quilt":   {"mode": "periodic", "invert": True, "periods": 2, "min_period": (335, 200)},
    "mesh":    {"mode": "periodic", "periods": 8},
    "grille":  {"mode": "periodic", "periods": 8},
    "dropout": {"mode": "blend", "binary": True},
    "mirror":  {"mode": "periodic", "periods": 4, "hard": True},
    "snaps":   {"mode": "periodic", "periods": 1},
    "canvas":  {"mode": "periodic", "periods": 6},
    "ripstop": {"mode": "periodic", "periods": 8},
    "camo":    {"mode": "blend", "binary": True},
    "static":  {"mode": "blend", "binary": True},
}


def load_grey(path):
    im = Image.open(path).convert("L")
    a = np.asarray(im, dtype=np.float32) / 255.0
    lo, hi = np.percentile(a, 1), np.percentile(a, 99)
    return np.clip((a - lo) / max(hi - lo, 1e-3), 0, 1)


def _corr(a, k, axis):
    L = a.shape[axis]
    x = a.take(range(0, L - k), axis=axis)
    y = a.take(range(k, L), axis=axis)
    return float(np.corrcoef(x.ravel(), y.ravel())[0, 1])


def fundamental(a, axis, lo=6):
    """The smallest shift at which the image matches itself about as well as it ever does: one
    repeat of a regular pattern (None when there is no clear repeat)."""
    L = a.shape[axis]
    b = a - a.mean()
    f = np.fft.rfft(b, axis=axis)
    ac = np.fft.irfft(f * np.conj(f), n=L, axis=axis).mean(axis=1 - axis)
    peaks = [k for k in range(max(6, lo), int(L * 0.6)) if ac[k] > ac[k - 1] and ac[k] >= ac[k + 1]]
    if not peaks:
        return None
    top = max(ac[k] for k in peaks)
    for k in peaks:
        if ac[k] >= 0.8 * top:
            return k
    return None


def best_lag(a, axis, n, p0):
    """The exact pixel length of `n` repeats (p0 = the rough length of one), by overlap correlation."""
    L = a.shape[axis]
    n = max(1, min(n, int((L - 16) / p0)))
    slack = 3 + n
    best, score = None, -1.0
    for k in range(max(6, n * p0 - slack), min(L - 8, n * p0 + slack) + 1):
        s = _corr(a, k, axis)
        if s > score:
            best, score = k, s
    return best, score


def wrap_axis(a, k, axis):
    """Cut `k` pixels along an axis and make the cut wrap exactly: the first few pixels are
    cross-faded from the content that really follows the last pixel (which, k being a whole
    number of repeats, is almost the same picture, so nothing ghosts)."""
    if axis == 0:
        return wrap_axis(a.T, k, 1).T
    L = a.shape[1]
    m = max(2, min(L - k, int(k * 0.08)))
    out = a[:, :k].copy()
    t = (np.arange(m) / m)[None, :]
    t = t * t * (3 - 2 * t)
    out[:, :m] = (1 - t) * a[:, k:k + m] + t * a[:, :m]
    return out


def grout_offset(a, axis, period):
    """Where the darkest line across the pattern falls inside the first repeat (a tile grid's
    grout), so that the cut can run along it."""
    prof = a.mean(axis=1 - axis)[:period]
    return int(np.argmin(ndimage.uniform_filter1d(prof, 3, mode="wrap")))


def make_periodic(a, periods, min_period=(6, 6), hard=False):
    """Cut `periods` repeats across (and as many down as keeps the cut square) and resample.
    hard: a grid of unrelated tiles (disco mirrors) - cut exactly along the grout, no cross-fade."""
    px, py = fundamental(a, 1, min_period[0]), fundamental(a, 0, min_period[1])
    if px is None or py is None:
        return None, "no clear repeat (x %s, y %s)" % (px, py)
    if hard:
        a = a[grout_offset(a, 0, py):, grout_offset(a, 1, px):]
    kx, sx = best_lag(a, 1, periods, px)
    ky, sy = best_lag(a, 0, max(1, int(round(kx / float(py)))), py)
    if kx is None or ky is None or sx < 0.3 or sy < 0.3:
        return None, "no clear repeat (x %s %.2f, y %s %.2f)" % (kx, sx, ky, sy)
    c = a[:ky, :kx] if hard else wrap_axis(wrap_axis(a, kx, 1), ky, 0)
    im = Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8))
    out = im.resize((N, N), Image.LANCZOS)
    note = "periodic: one repeat %d x %d px, cut %d x %d px (self-match %.2f / %.2f)" % (px, py, kx, ky, sx, sy)
    return np.asarray(out, dtype=np.float32) / 255.0, note


def _cut_axis(c, k):
    """Keep c[:, :k]; its first columns are replaced by what really follows the cut, up to a
    minimum-difference path (as in image quilting), so the join runs where the two pictures
    agree instead of slicing through shapes."""
    m = c.shape[1] - k
    A, B = c[:, k:k + m], c[:, :m]
    e = ndimage.gaussian_filter((A - B) ** 2, 1.5) + 1e-4
    H = e.shape[0]
    cost = e.copy()
    for y in range(1, H):
        prev = cost[y - 1]
        best = np.minimum(prev, np.minimum(np.roll(prev, 1), np.roll(prev, -1)))
        best[0] = min(prev[0], prev[1])
        best[-1] = min(prev[-1], prev[-2])
        cost[y] += best
    path = np.zeros(H, dtype=int)
    path[-1] = int(np.argmin(cost[-1]))
    for y in range(H - 2, -1, -1):
        x = path[y + 1]
        lo, hi = max(0, x - 1), min(m, x + 2)
        path[y] = lo + int(np.argmin(cost[y, lo:hi]))
    o = c[:, :k].copy()
    xs = np.arange(m)[None, :]
    w = np.clip((xs - path[:, None]) / 3.0 + 0.5, 0, 1)      # 0 left of the path (A), 1 right (B)
    o[:, :m] = (1 - w) * A + w * B
    return o


def make_blend(a, binary):
    """Irregular patterns: keep 84% of the swatch and join it to itself along minimum-difference
    paths on both axes; then (binary) blur a little and re-threshold to the original coverage."""
    k = int(a.shape[0] * 0.84)
    frac = float((a > 0.5).mean())
    c = _cut_axis(a, k)
    c = _cut_axis(c.T, k).T
    if binary:
        c = ndimage.gaussian_filter(c, 1.5, mode="wrap")
        thr = np.quantile(c, 1.0 - frac)
        c = np.clip((c - thr) * 10.0 + 0.5, 0, 1)
    im = Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8)).resize((N, N), Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0, "blend: min-difference seam cut%s, coverage %.0f%%" % (" + threshold" if binary else "", frac * 100)


def seam_score(t):
    """Wrap-around discontinuity relative to an ordinary neighbouring-pixel step (1.0 = invisible)."""
    def one(a):
        inner = np.abs(np.diff(a, axis=1)).mean()
        wrap = np.abs(a[:, 0] - a[:, -1]).mean()
        return wrap / max(inner, 1e-6)
    return one(t), one(t.T)


def patterns():
    os.makedirs(TEX, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    tiles = []
    for pid in spec.PATTERNS:
        src = os.path.join(SRC, "pattern_%s.png" % pid)
        if not os.path.exists(src):
            print("pattern %-8s MISSING source" % pid)
            continue
        opt = PATTERN_OPTS[pid]
        a = load_grey(src)
        inv = opt.get("invert")
        if inv is None:
            inv = a.mean() > 0.6
        if inv:
            a = 1.0 - a
        out, note = (None, "")
        if opt["mode"] == "periodic":
            out, note = make_periodic(a, opt["periods"], opt.get("min_period", (6, 6)), opt.get("hard", False))
            if out is None:
                print("pattern %-8s %s -> falling back to blend" % (pid, note))
        if out is None:
            out, note = make_blend(a, opt.get("binary", True))
        sx, sy = seam_score(out)
        Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(TEX, "pattern_%s.png" % pid))
        t3 = np.tile(out, (3, 3))
        im3 = Image.fromarray((t3 * 255).astype(np.uint8), "L").resize((768, 768), Image.LANCZOS)
        im3.save(os.path.join(PREV, "tile_%s.png" % pid))
        tiles.append(im3)
        print("pattern %-8s %s | seam x %.2f y %.2f | coverage %.0f%%" % (pid, note, sx, sy, out.mean() * 100))
    if tiles:
        cols = 5
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("L", (cols * 400, rows * 400), 40)
        for i, t in enumerate(tiles):
            sheet.paste(t.resize((392, 392)), ((i % cols) * 400 + 4, (i // cols) * 400 + 4))
        sheet.save(os.path.join(PREV, "_patterns.png"))


def decals():
    outs = []
    for did in spec.DECALS:
        src = os.path.join(SRC, "decal_%s.png" % did)
        if not os.path.exists(src):
            print("decal   %-12s MISSING source" % did)
            continue
        a = load_grey(src)
        if a.mean() > 0.5:
            a = 1.0 - a
        a = np.clip((a - 0.12) / 0.76, 0, 1)
        ys, xs = np.where(a > 0.3)
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        side = int(max(x1 - x0, y1 - y0) * 1.08) + 2
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        canvas = np.zeros((side, side), dtype=np.float32)
        sx0, sy0 = cx - side // 2, cy - side // 2
        for (dst, s0, lim) in ((0, sx0, a.shape[1]), (1, sy0, a.shape[0])):
            pass
        xa, xb = max(sx0, 0), min(sx0 + side, a.shape[1])
        ya, yb = max(sy0, 0), min(sy0 + side, a.shape[0])
        canvas[ya - sy0:yb - sy0, xa - sx0:xb - sx0] = a[ya:yb, xa:xb]
        al = Image.fromarray((canvas * 255).astype(np.uint8), "L").resize((N, N), Image.LANCZOS)
        rgba = Image.merge("RGBA", (Image.new("L", (N, N), 255),) * 3 + (al,))
        rgba.save(os.path.join(TEX, "decal_%s.png" % did))
        outs.append(al)
        print("decal   %-12s ok, coverage %.0f%%" % (did, np.asarray(al).mean() / 2.55))
    if outs:
        sheet = Image.new("L", (len(outs) * 300, 300), 30)
        for i, o in enumerate(outs):
            sheet.paste(o.resize((292, 292)), (i * 300 + 4, 4))
        sheet.save(os.path.join(PREV, "_decals.png"))


if __name__ == "__main__":
    patterns()
    decals()
