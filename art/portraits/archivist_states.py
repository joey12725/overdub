"""Derive the Archivist 'playback' and 'still' states from the idle anchor, procedurally.

usage (repo root): python -I art/portraits/archivist_states.py
The image model would not change the machine state from the anchor (two attempts; the first is kept in raw/rejected/), so the
states are painted over the anchor here. That also keeps every pixel of the housing identical, so swapping states
changes only the reels, the sensor, the rune light and the halo screens.
  playback: reels smeared into a backwards spin + speed arcs, every halo screen lit in a cassette colour with a tiny
            pigtailed silhouette, sensor white-hot with a star flare, rune light brighter.
  still:    motion lines removed, sensor down to an ember, rune light dimmed, one screen lit showing a cassette.
"""
import os, math
import numpy as np
import scipy.ndimage as nd
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__)); RAW = os.path.join(HERE, "raw")
REELS = [(520, 540), (792, 538)]; RR = 127          # reel centres / radius in the anchor
SENSOR = (654, 652)
LINES = [(396, 380, 480, 440), (850, 386, 934, 446)]  # idle motion-line boxes
TAKES = [(255, 77, 122), (245, 197, 24), (77, 184, 255), (95, 211, 95)]   # red-pink, yellow, sky blue, green
INK = (24, 16, 34)
SS = 3

def screens(a):
    r, g, b, al = (a[..., i].astype(int) for i in range(4))
    lab, n = nd.label((r < 22) & (g < 22) & (b < 22) & (al > 250))
    out = []
    for i, sl in enumerate(nd.find_objects(lab)):
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        m = lab[sl] == i + 1
        if 80 < w < 110 and 50 < h < 75 and m.sum() > 5000: out.append((sl[1].start, sl[0].start, w, h))
    cx = a.shape[1] / 2
    out.sort(key=lambda s: math.atan2(s[0] + s[2] / 2 - cx, -(s[1] + s[3] / 2 - 520)))   # round the ring
    return out

def teal(a, gain, toward=None, k=0.0):
    f = a[..., :3].astype(np.float32); r, g, b = f[..., 0], f[..., 1], f[..., 2]
    m = np.clip((np.minimum(g, b) - r - 25) / 60.0, 0, 1)[..., None]
    t = f * gain
    if toward is not None: t = t * (1 - k) + np.array(toward, np.float32) * k
    a[..., :3] = np.clip(f * (1 - m) + t * m, 0, 255).astype(np.uint8)

def overlay(base, draw_fn):
    W, H = base.size
    lay = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0)); draw_fn(ImageDraw.Draw(lay), SS)
    lay = lay.resize((W, H), Image.LANCZOS)
    al = np.asarray(lay.getchannel("A")).astype(np.float32) * (np.asarray(base.getchannel("A")) > 0)
    lay.putalpha(Image.fromarray(al.astype(np.uint8)))
    out = base.copy(); out.alpha_composite(lay); return out

def girl(d, x, y, w, h, s, col):
    """tiny standing pigtailed silhouette centred in a screen"""
    cx, cy = (x + w / 2) * s, (y + h / 2) * s; u = h * s / 60.0
    P = lambda dx, dy: (cx + dx * u, cy + dy * u)
    d.ellipse([*P(-8, -24), *P(8, -8)], fill=col)                                   # head
    d.polygon([P(-7, -20), P(-21, -27), P(-17, -10)], fill=col)                     # pigtails
    d.polygon([P(7, -20), P(21, -27), P(17, -10)], fill=col)
    d.polygon([P(-7, -8), P(7, -8), P(11, 10), P(-11, 10)], fill=col)               # jacket
    d.polygon([P(-9, 10), P(-1, 10), P(-3, 25), P(-11, 25)], fill=col)              # legs
    d.polygon([P(1, 10), P(9, 10), P(11, 25), P(3, 25)], fill=col)

def cassette(d, x, y, w, h, s, col):
    cx, cy = (x + w / 2) * s, (y + h / 2) * s; u = h * s / 60.0
    d.rounded_rectangle([cx - 30 * u, cy - 19 * u, cx + 30 * u, cy + 19 * u], 5 * u, outline=col, width=int(5 * u))
    d.rounded_rectangle([cx - 20 * u, cy - 9 * u, cx + 20 * u, cy + 5 * u], 7 * u, outline=col, width=int(3.5 * u))
    for sx in (-11, 11): d.ellipse([cx + (sx - 4) * u, cy - 6 * u, cx + (sx + 4) * u, cy + 2 * u], fill=col)

def spin(im, arc=75, steps=26):
    """smear each reel backwards around its hub"""
    out = im.copy()
    for (cx, cy) in REELS:
        box = (cx - RR - 4, cy - RR - 4, cx + RR + 4, cy + RR + 4)
        t = im.crop(box).convert("RGB")
        tile = np.asarray(t).astype(np.float32); acc = np.zeros_like(tile); wsum = 0
        for i in range(steps):
            wgt = 1.0 - 0.7 * i / steps
            acc += wgt * np.asarray(t.rotate(arc * i / (steps - 1), Image.BICUBIC), dtype=np.float32); wsum += wgt
        acc /= wsum
        yy, xx = np.mgrid[0:tile.shape[0], 0:tile.shape[1]]; rad = np.hypot(xx - RR - 4, yy - RR - 4)
        m = np.clip((RR - 3 - rad) / 3.0, 0, 1)[..., None]
        res = Image.fromarray(np.clip(tile * (1 - m) + acc * m, 0, 255).astype(np.uint8)).convert("RGBA")
        res.putalpha(im.crop(box).getchannel("A")); out.paste(res, box[:2])
    return out

def playback(anchor):
    a = np.asarray(anchor).copy(); teal(a, 1.25, (150, 255, 240), 0.25)
    im = spin(Image.fromarray(a, "RGBA")); sc = screens(np.asarray(anchor))
    def draw(d, s):
        for i, (x, y, w, h) in enumerate(sc):
            col = TAKES[i % 4]
            d.rounded_rectangle([(x + 2) * s, (y + 2) * s, (x + w - 2) * s, (y + h - 2) * s], 5 * s, fill=col + (255,))
            girl(d, x, y, w, h, s, INK + (255,))
        for (cx, cy), sgn in zip(REELS, (-1, 1)):                                   # speed arcs outside each reel
            for (r0, a0, a1, wd) in [(RR + 13, 200, 262, 7), (RR + 27, 212, 250, 5), (RR + 13, 112, 168, 7), (RR + 27, 124, 158, 5)]:
                if sgn > 0: a0, a1 = 180 - a1, 180 - a0
                bb = [(cx - r0) * s, (cy - r0) * s, (cx + r0) * s, (cy + r0) * s]
                d.arc(bb, a0, a1, fill=INK + (255,), width=(wd + 5) * s); d.arc(bb, a0 + 1, a1 - 1, fill=(214, 200, 226, 255), width=wd * s)
            for r0 in (40, 66, 92, 114):                                            # spin streaks on the reel face
                bb = [(cx - r0) * s, (cy - r0) * s, (cx + r0) * s, (cy + r0) * s]
                for a0 in (15, 135, 255): d.arc(bb, a0 + r0 * 0.3, a0 + 62 + r0 * 0.3, fill=(232, 222, 240, 150), width=3 * s)
        x, y = SENSOR                                                              # white-hot sensor, four-point flare
        for L, wd, col in ((58, 9, INK + (255,)), (52, 5, (255, 170, 60, 255))):
            d.polygon([((x - L) * s, y * s), (x * s, (y - wd) * s), ((x + L) * s, y * s), (x * s, (y + wd) * s)], fill=col)
            d.polygon([(x * s, (y - L) * s), ((x - wd) * s, y * s), (x * s, (y + L) * s), ((x + wd) * s, y * s)], fill=col)
        d.ellipse([(x - 21) * s, (y - 21) * s, (x + 21) * s, (y + 21) * s], fill=(255, 150, 40, 255))
        d.ellipse([(x - 14) * s, (y - 14) * s, (x + 14) * s, (y + 14) * s], fill=(255, 246, 214, 255))
    return overlay(im, draw)

def still(anchor):
    a = np.asarray(anchor).copy()
    rgb = a[..., :3].astype(np.float32)
    for (x0, y0, x1, y1) in LINES:                                                  # inpaint the idle motion lines
        t = rgb[y0:y1, x0:x1]; lum = t.mean(axis=2)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        off = np.minimum.reduce([np.hypot(xx - cx, yy - cy) for cx, cy in REELS]) > RR + 5      # never touch the reel itself
        bright = nd.binary_dilation((lum > 95) & off, iterations=3) & off
        w = (~bright).astype(np.float32)
        num = np.dstack([nd.gaussian_filter(t[..., c] * w, 7) for c in range(3)]); den = nd.gaussian_filter(w, 7)[..., None] + 1e-3
        t[bright] = (num / den)[bright]
    a[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    teal(a, 0.42, (58, 78, 84), 0.45)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]; rad = np.hypot(xx - SENSOR[0], yy - SENSOR[1])
    f = a[..., :3].astype(np.float32); m = np.clip((27 - rad) / 3.0, 0, 1)[..., None]
    ember = f * np.array([0.42, 0.16, 0.14], np.float32)
    a[..., :3] = np.clip(f * (1 - m) + ember * m, 0, 255).astype(np.uint8)
    im = Image.fromarray(a, "RGBA"); sc = screens(np.asarray(anchor)); top = min(sc, key=lambda s: s[1])
    def draw(d, s):
        x, y, w, h = top
        d.rounded_rectangle([(x + 2) * s, (y + 2) * s, (x + w - 2) * s, (y + h - 2) * s], 5 * s, fill=(238, 230, 204, 255))
        cassette(d, x, y, w, h, s, INK + (255,))
        ex, ey = SENSOR; d.ellipse([(ex - 6) * s, (ey - 6) * s, (ex + 6) * s, (ey + 6) * s], fill=(214, 74, 36, 255))
    return overlay(im, draw)

if __name__ == "__main__":
    anchor = Image.open(os.path.join(RAW, "archivist_idle_a.png")).convert("RGBA")
    print("screens:", len(screens(np.asarray(anchor))))
    playback(anchor).save(os.path.join(RAW, "archivist_playback.png"))
    still(anchor).save(os.path.join(RAW, "archivist_still.png"))
