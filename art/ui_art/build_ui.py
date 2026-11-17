"""Build the interface pieces in assets/ui/art/ui/** from the raw model output in art/ui_art/raw/.
   python -I art/ui_art/build_ui.py            (writes PNGs + assets/ui/art/ui/slices.json)

Every nine-slice piece goes through norm9(): the corner cells keep the hand-inked drawing, the edge
bands are replaced by their median cross-section (so stretching or tiling them is exact), the seam is
cross-faded over a few pixels, and the middle is collapsed to MID pixels to keep textures small."""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from lib import load, clean_alpha, drop_specks, trim, fit, save, RAW, OUT

MID = 16          # stretchable middle kept in every nine-slice texture
SLICES = {}       # file -> {size, margins l/t/r/b, note}
TAPES = {'red': (255, 77, 109), 'yellow': (255, 210, 63), 'blue': (62, 197, 255), 'green': (125, 255, 107)}
PINK = (255, 79, 163)


def prep(name, specks=400):
    return trim(drop_specks(clean_alpha(load(name)), specks))


def scale(im, s):
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)


def premul(im):
    a = np.asarray(im).astype(np.float32)
    a[..., :3] *= a[..., 3:4] / 255.0
    return a


def unpremul(a):
    a = a.copy()
    al = np.maximum(a[..., 3:4], 1e-3)
    a[..., :3] = np.where(a[..., 3:4] > 0, a[..., :3] * 255.0 / al, 0)
    return Image.fromarray(np.clip(a.round(), 0, 255).astype(np.uint8), 'RGBA')


def norm9(im, l, t, r, b, blend=6, horiz=True, vert=True, mid=MID):
    """Regularise + collapse a nine-slice source. Margins in pixels of `im`. vert=False -> 3-slice."""
    a = premul(im)
    h, w = a.shape[:2]
    o = a.copy()
    if not vert:
        t, b = h, 0          # the whole height behaves as the "top band"
    if not horiz:
        l, r = w, 0
    colp = np.median(a[:, l:w - r], axis=1) if horiz else None       # (h,4) cross-section of top/bottom bands
    rowp = np.median(a[t:h - b, :], axis=0) if vert else None        # (w,4) cross-section of left/right bands
    if horiz:
        o[:, l:w - r] = colp[:, None, :]
    if vert:
        o[t:h - b, :] = rowp[None, :, :]
    if horiz and vert:
        o[t:h - b, l:w - r] = np.median(a[t:h - b, l:w - r].reshape(-1, 4), axis=0)
    # seam cross-fades inside the corner cells
    if horiz:
        for k in range(blend):
            wgt = (k + 1) / (blend + 1)
            for x in (l - blend + k, w - r + blend - 1 - k):
                if 0 <= x < w:
                    rows = np.r_[0:min(t, h), max(h - b, 0):h] if vert else np.arange(h)
                    o[rows, x] = o[rows, x] * (1 - wgt) + colp[rows] * wgt
    if vert:
        for k in range(blend):
            wgt = (k + 1) / (blend + 1)
            for y in (t - blend + k, h - b + blend - 1 - k):
                if 0 <= y < h:
                    cols = np.r_[0:l, w - r:w] if horiz else np.arange(w)
                    o[y, cols] = o[y, cols] * (1 - wgt) + rowp[cols] * wgt
    # collapse the middle
    if horiz:
        o = np.concatenate([o[:, :l], o[:, l:l + mid] if w - r - l >= mid else o[:, l:w - r], o[:, w - r:]], axis=1)
    if vert:
        o = np.concatenate([o[:t], o[t:t + mid] if h - b - t >= mid else o[t:h - b], o[h - b:]], axis=0)
    return unpremul(o)


def out9(im, rel, l, t, r, b, note, **kw):
    res = norm9(im, l, t, r, b, **kw)
    vert = kw.get('vert', True)
    save(res, rel)
    SLICES[rel] = {'size': [res.width, res.height], 'left': l, 'top': t if vert else 0, 'right': r,
                   'bottom': b if vert else 0, 'note': note}
    return res


def col_suggest(im, tol=6.0):
    """Print where the left/right caps end (first/last column that matches the median cross-section)."""
    a = premul(im)
    med = np.median(a[:, a.shape[1] // 3: 2 * a.shape[1] // 3], axis=1)
    d = np.abs(a - med[:, None, :]).mean(axis=(0, 2))
    ok = np.nonzero(d < tol)[0]
    medr = np.median(a[a.shape[0] // 3: 2 * a.shape[0] // 3], axis=0)
    dr = np.abs(a - medr[None, :, :]).mean(axis=(1, 2))
    okr = np.nonzero(dr < tol)[0]
    return 'cap L=%d R=%d  T=%d B=%d' % (ok.min(), a.shape[1] - 1 - ok.max(), okr.min(), a.shape[0] - 1 - okr.max())


# ───────────────────────── panel / dialogue / toast / tooltip ─────────────────────────
def panels():
    p = scale(prep('ui_panel'), 0.30)
    print('panel', p.size, col_suggest(p))
    out9(p, 'ui/panel.png', 32, 32, 32, 32, 'dark inked panel, off-white sticker edge')

    d = scale(prep('ui_dialogue'), 0.36)
    da = np.asarray(d)
    yel = (da[..., 0] > 200) & (da[..., 1] > 140) & (da[..., 2] < 140) & (da[..., 3] > 200)
    ys, xs = np.nonzero(yel)
    print('dialogue', d.size, col_suggest(d), 'tab yellow bbox', xs.min(), ys.min(), xs.max(), ys.max())
    return p, d, int(xs.max()) + 22, int(ys.max()) + 22


def dialogue(d, l, t, r, b):
    out9(d, 'ui/dialogue_box.png', l, t, r, b, 'dialogue box; yellow speaker tab lives in the top-left cell')


def toast_tooltip():
    t = scale(prep('ui_toast'), 0.25)
    print('toast', t.size, col_suggest(t))
    tt = scale(prep('ui_tooltip'), 0.24)
    print('tooltip', tt.size, col_suggest(tt))
    return t, tt


# ───────────────────────── button states ─────────────────────────
def shift(arr, dx, dy):
    """Shift an array so that out[y, x] = arr[y - dy, x - dx] (content moves by +dx,+dy), zero-filled."""
    o = np.zeros_like(arr)
    h, w = arr.shape[:2]
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    o[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx] = arr[ys0:ys1, xs0:xs1]
    return o


def over(top, bottom):
    return Image.alpha_composite(bottom, top)


def recolour_face(arr, fn):
    """Apply fn(rgb float array)->rgb to the non-ink part of an RGBA array, weighted by brightness."""
    rgb = arr[..., :3].astype(np.float32)
    wgt = np.clip((rgb.max(axis=-1, keepdims=True) - 60) / 120.0, 0, 1)
    new = fn(rgb)
    o = arr.copy()
    o[..., :3] = np.clip(rgb * (1 - wgt) + new * wgt, 0, 255).round().astype(np.uint8)
    return o


def buttons():
    raw = prep('ui_button')
    a = np.asarray(raw)
    yel = (a[..., 0] > 200) & (a[..., 1] > 140) & (a[..., 2] < 140) & (a[..., 3] > 200)
    ys, xs = np.nonzero(yel)
    tk = int(xs.min())                                   # outline thickness (left side has no shadow)
    dx = int(raw.width - 1 - xs.max() - tk)
    dy = int(raw.height - 1 - ys.max() - int(ys.min()))  # top outline thickness = ys.min()
    print('button raw', raw.size, 'outline', tk, ys.min(), 'shadow offset', dx, dy)
    al = a[..., 3]
    body_a = np.minimum(al, shift(al, -dx, -dy))        # U ∩ (U − d): the button without its shadow slab
    body = a.copy(); body[..., 3] = body_a
    body[body_a == 0, :3] = 0

    def slab(col, alpha=1.0):
        s = np.zeros_like(a)
        s[..., :3] = col
        s[..., 3] = (al * alpha).astype(np.uint8)
        return Image.fromarray(s, 'RGBA')

    def img(x):
        return Image.fromarray(x, 'RGBA')

    lum = lambda rgb: (rgb * np.array([0.3, 0.59, 0.11], np.float32)).sum(-1, keepdims=True)
    normal = over(img(body), slab((0, 0, 0)))
    hover = over(img(recolour_face(body, lambda c: c + (255 - c) * 0.45)), slab(PINK))
    pressed = img(shift(recolour_face(body, lambda c: c * 0.86), dx, dy))
    dis_body = recolour_face(body, lambda c: lum(c) * 0.55 + np.array([40, 37, 32], np.float32))
    disabled = over(img(dis_body), slab((0, 0, 0), 0.45))
    s = 0.2
    states = {'normal': normal, 'hover': hover, 'pressed': pressed, 'disabled': disabled}
    states = {k: scale(v, s) for k, v in states.items()}
    print('button', states['normal'].size, col_suggest(states['normal']))
    tab = scale(img(body).crop((0, 0, raw.width - dx, raw.height - dy)), 0.13)
    print('name tab', tab.size)
    out9(tab, 'ui/name_tab.png', 22, 20, 22, 24, 'yellow speaker-name tab / tag (button face without the shadow slab)')
    return states


# ───────────────────────── progress bar ─────────────────────────
def bars():
    im = drop_specks(clean_alpha(load('ui_bar')))
    al = np.asarray(im)[..., 3]
    rows = np.nonzero(al.max(axis=1) > 0)[0]
    gap = np.nonzero(np.diff(rows) > 20)[0][0]
    track = trim(im.crop((0, rows[0], im.width, rows[gap] + 1)))
    fill = trim(im.crop((0, rows[gap + 1], im.width, rows[-1] + 1)))
    s = 36.0 / track.height
    track = scale(track, s)
    ta = np.asarray(track)
    mid = ta[:, track.width // 2]
    bw = 0
    while bw < track.height and mid[bw, 0] > 170 and mid[bw, 2] > 120:
        bw += 1
    bw = max(1, bw - 1)                                   # let the ink lines overlap by a pixel
    f = fill.resize((track.width - 2 * bw, track.height - 2 * bw), Image.LANCZOS)
    fc = Image.new('RGBA', track.size, (0, 0, 0, 0))
    fc.paste(f, (bw, bw))
    cap = track.height // 2 + 10
    print('bar', track.size, 'sticker border', bw, col_suggest(track))
    out9(track, 'ui/progress_track.png', cap, 0, cap, 0, 'slim progress bar, empty track (3-slice, fixed height)', vert=False)
    out9(fc, 'ui/progress_fill.png', cap, 0, cap, 0, 'slim progress bar, white fill to tint; same canvas as the track', vert=False)


# ───────────────────────── cassette ─────────────────────────
def cassette():
    im = trim(drop_specks(clean_alpha(load('ui_cassette'))))
    a = np.asarray(im).astype(np.float32)
    gd = a[..., 1] - np.maximum(a[..., 0], a[..., 2])
    key = np.clip((gd - 30) / 110.0, 0, 1)                # 1 = pure chroma green
    a[..., 3] *= (1 - key)
    a[..., 1] = np.minimum(a[..., 1], np.maximum(a[..., 0], a[..., 2]))   # despill
    a[a[..., 3] < 4] = 0
    ys, xs = np.nonzero(key > 0.9)
    win = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    shell = Image.fromarray(a.round().astype(np.uint8), 'RGBA')
    s = 640.0 / shell.width
    small = scale(shell, s)
    save(small, 'ui/cassette_shell.png')
    w = [round(v * s) for v in win]
    info = {'size': list(small.size), 'window_rect': [w[0], w[1], w[2] - w[0], w[3] - w[1]],
            'hub_centres': [[round(w[0] + (w[2] - w[0]) * 0.24), (w[1] + w[3]) // 2],
                            [round(w[0] + (w[2] - w[0]) * 0.76), (w[1] + w[3]) // 2]]}
    # blank label -> tape-colour tints
    sa = np.asarray(small).astype(np.float32)
    cream = np.clip((sa[..., :3].min(axis=-1) - 150) / 50.0, 0, 1) * (sa[..., 0] - sa[..., 2] < 80)
    solid = cream > 0.9                                   # label = the big cream block (screws are cream too)
    lx = np.nonzero(solid.mean(axis=0) > 0.25)[0]; ly = np.nonzero(solid.mean(axis=1) > 0.25)[0]
    info['label_rect'] = [int(lx.min()), int(ly.min()), int(lx.max() - lx.min() + 1), int(ly.max() - ly.min() + 1)]
    inside = np.zeros_like(cream)
    inside[ly.min() - 3:ly.max() + 4, lx.min() - 3:lx.max() + 4] = 1
    cream = cream * inside
    for name, col in TAPES.items():
        tint = (np.array(col, np.float32) * 0.8 + 255 * 0.2) / 255.0
        o = sa.copy()
        o[..., :3] = sa[..., :3] * (1 - cream[..., None]) + sa[..., :3] * tint * cream[..., None]
        save(Image.fromarray(o.round().astype(np.uint8), 'RGBA'), 'ui/cassette_shell_%s.png' % name)
    SLICES['ui/cassette_shell.png'] = dict(info, note='not sliced; draw hubs behind it')

    hub = trim(drop_specks(clean_alpha(load('ui_hub'))))
    ha = np.asarray(hub)
    ys, xs = np.nonzero(ha[..., 3] > 128)
    cx, cy = xs.mean(), ys.mean()
    rad = max(cx - xs.min(), xs.max() - cx, cy - ys.min(), ys.max() - cy) + 2
    print('hub raw', hub.size, 'centre', round(cx, 1), round(cy, 1), 'radius', round(rad, 1),
          'bbox w/h', xs.max() - xs.min() + 1, ys.max() - ys.min() + 1)
    # the model drew it ~2% taller than wide: crop to the ink bbox and resize to a true circle
    reel = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    reel.paste(hub.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)).resize((252, 252), Image.LANCZOS), (2, 2))
    save(reel, 'ui/cassette_reel.png')
    # radial luminance profile -> radius of the cream hub ring (incl. its ink outline)
    ra = np.asarray(reel).astype(np.float32)
    yy, xx = np.mgrid[0:256, 0:256]
    rr = np.hypot(xx - 127.5, yy - 127.5)
    lum = ra[..., :3].mean(axis=-1)
    prof = np.array([lum[(rr >= r) & (rr < r + 1)].mean() for r in range(127)])
    r_cream = max(r for r in range(127) if prof[r] > 170)
    r_core = next(r for r in range(r_cream + 1, 127) if prof[r] > 45 and prof[r - 1] <= 45) if any(
        prof[r] <= 45 for r in range(r_cream, 127)) else r_cream + 6
    print('hub cream radius', r_cream, 'core radius', r_core)
    n = 2 * (r_core + 2)
    core = reel.crop((128 - n // 2, 128 - n // 2, 128 + n // 2, 128 + n // 2))
    ca = np.asarray(core).copy()
    yy, xx = np.mgrid[0:n, 0:n]
    rc = np.hypot(xx - (n - 1) / 2, yy - (n - 1) / 2)
    ca[..., 3] = (ca[..., 3] * np.clip(r_core + 0.5 - rc, 0, 1)).astype(np.uint8)
    save(Image.fromarray(ca, 'RGBA'), 'ui/cassette_hub.png')
    SLICES['ui/cassette_reel.png'] = {'size': [256, 256], 'pivot': [128, 128], 'hub_radius': int(r_core),
                                      'note': 'full tape pack + hub, rotate about the centre; sixfold symmetric'}
    SLICES['ui/cassette_hub.png'] = {'size': [n, n], 'pivot': [n // 2, n // 2],
                                     'note': 'hub only (same pixel scale as cassette_reel.png)'}


# ───────────────────────── master ruler strip ─────────────────────────
def ruler():
    im = Image.open(os.path.join(RAW, 'ui_ruler.png')).convert('RGB')
    a = np.asarray(im).astype(np.float32)
    notbg = np.abs(a - 128).mean(axis=2).mean(axis=1) > 25
    ys = np.nonzero(notbg)[0]
    y0, y1 = ys.min(), ys.max() + 1
    strip = a[y0:y1]
    h = strip.shape[0]
    lum = strip.mean(axis=2)

    def runs(mask):
        xs = np.nonzero(mask)[0]
        if not len(xs):
            return []
        cuts = np.nonzero(np.diff(xs) > 3)[0]
        st = np.r_[xs[0], xs[cuts + 1]]; en = np.r_[xs[cuts], xs[-1]]
        return [(s + e) / 2.0 for s, e in zip(st, en)]

    allt = runs((lum[int(h * .72):int(h * .82)] < 90).mean(axis=0) > 0.5)
    tall = runs((lum[int(h * .30):int(h * .42)] < 90).mean(axis=0) > 0.5)
    sp = float(np.median(np.diff(allt)))
    print('ruler strip rows', y0, y1, 'ticks', [round(t) for t in allt], 'tall', [round(t) for t in tall], 'spacing', sp)
    BW, BH = 128, 96
    prof = np.median(strip, axis=1)                       # (h,3) tick-free cross-section
    start = next(t for t in tall if t - sp / 2 >= 0 and t + 3.5 * sp <= im.width)
    cells = []
    for k in range(4):
        c = min(allt, key=lambda t: abs(t - (start + k * sp)))
        x0 = int(round(c - sp / 2)); x1 = x0 + int(round(sp))
        cell = strip[:, x0:x1].copy()
        wd = cell.shape[1]
        # keep the drawing only near the tick, fade to the clean cross-section toward the cell borders
        xr = np.abs(np.arange(wd) - wd / 2.0)
        wgt = np.clip((wd * 0.30 - xr) / (wd * 0.10), 0, 1)[None, :, None]
        cell = cell * wgt + prof[:, None, :] * (1 - wgt)
        cells.append(Image.fromarray(cell.round().astype(np.uint8), 'RGB').resize((BW, BH), Image.LANCZOS))
    tile = Image.new('RGB', (4 * BW, BH))
    for k, c in enumerate(cells):
        tile.paste(c, (k * BW, 0))
    save(tile.convert('RGBA'), 'ui/ruler_strip.png')
    # dark variant: cream -> charcoal, ink -> cream, keep the yellow stripe
    t = np.asarray(tile).astype(np.float32)
    lumt = t.mean(axis=2, keepdims=True) / 255.0
    yellow = np.clip(((t[..., 0:1] - t[..., 2:3]) - 90) / 60.0, 0, 1)
    dark = np.array([27, 23, 20], np.float32) * lumt + np.array([244, 236, 216], np.float32) * (1 - lumt)
    dark = dark * (1 - yellow) + t * yellow
    save(Image.fromarray(dark.round().astype(np.uint8), 'RGB').convert('RGBA'), 'ui/ruler_strip_dark.png')
    for n in ('ui/ruler_strip.png', 'ui/ruler_strip_dark.png'):
        SLICES[n] = {'size': [4 * BW, BH], 'tile': 'repeat-x', 'beat_px': BW, 'tick_x': [64, 192, 320, 448],
                     'note': 'one bar (4 beats) per tile; tall tick = downbeat at x=64, beats every 128 px'}


if __name__ == '__main__':
    only = sys.argv[1:]
    def want(k): return not only or k in only
    if want('panels'):
        p, d, dl, dt = panels()
        dialogue(d, dl, dt, 36, 36)
        t, tt = toast_tooltip()
        out9(t, 'ui/toast.png', 84, 0, 32, 0, 'toast (3-slice, fixed height); hazard-striped yellow cap is the left cell', vert=False)
        out9(tt, 'ui/tooltip.png', 56, 30, 34, 44, 'paper tooltip, pink sticker shadow; tail lives in the bottom-left cell')
    if want('buttons'):
        for k, v in buttons().items():
            out9(v, 'ui/button_%s.png' % k, 34, 30, 36, 40, 'button, %s state (all four share canvas + margins)' % k)
    if want('bars'):
        bars()
    if want('cassette'):
        cassette()
    if want('ruler'):
        ruler()
    p = os.path.join(OUT, 'ui', 'slices.json')
    old = json.load(open(p)) if os.path.exists(p) else {}
    old.update(SLICES)
    json.dump(old, open(p, 'w'), indent=1, sort_keys=True, default=int)
    print('wrote ui/slices.json', len(old), 'entries')
