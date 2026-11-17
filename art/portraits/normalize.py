"""Normalise raw generated busts into game-ready 1024x1024 portraits.

usage (repo root):  python -I art/portraits/normalize.py            # all characters in cast.json
                    python -I art/portraits/normalize.py moxie      # one character

For each character in art/portraits/cast.json:
  * the anchor raw image defines the frame: uniform scale + offset that puts the top of the anchor's
    silhouette at HEADROOM px, the bottom of the raw image on the canvas bottom, and the chosen
    head-centre column on the canvas centre line;
  * every other expression is first registered to the anchor (translation + small scale search on the
    alpha masks, FFT correlation) so the head does not jump when expressions are swapped, then the
    same frame is applied;
  * optional horizontal mirror (characters that must face screen-left), alpha clean-up (kill stray
    specks, snap near-0/near-255), and a report of the residual offsets.
Outputs assets/portraits/<id>_<expression>.png (RGBA, 1024x1024).
"""
import json, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "assets", "portraits")
CANVAS = 1024

def load(p):
    return Image.open(p).convert("RGBA")

def mask_small(im, size):
    a = im.getchannel("A").resize(size, Image.BILINEAR)
    return (np.asarray(a, dtype=np.float32) / 255.0 > 0.5).astype(np.float32)

def register(anchor, im, q=4):
    """Return (scale, dx, dy) mapping im onto anchor (im scaled by `scale`, then shifted)."""
    aw, ah = anchor.size
    A = mask_small(anchor, (aw // q, ah // q))
    H, W = A.shape
    PH, PW = H * 2, W * 2
    FA = np.fft.rfft2(A, (PH, PW))
    best = (-1, 1.0, 0, 0)
    for s in np.arange(0.92, 1.081, 0.01):
        w, h = int(round(im.width * s / q)), int(round(im.height * s / q))
        if w > PW or h > PH: continue
        B = mask_small(im, (w, h))
        FB = np.fft.rfft2(B, (PH, PW))
        c = np.fft.irfft2(FA * np.conj(FB), (PH, PW))
        i = int(np.argmax(c)); y, x = divmod(i, PW)
        if y > PH // 2: y -= PH
        if x > PW // 2: x -= PW
        inter = c.flat[i]; iou = inter / (A.sum() + B.sum() - inter)
        if iou > best[0]: best = (iou, float(s), x * q, y * q)
    return best

def clean_alpha(im):
    a = np.asarray(im.getchannel("A")).copy()
    a[a < 10] = 0; a[a > 245] = 255
    # drop specks: connected components are overkill; remove isolated pixels with a 5x5 majority test
    solid = (a > 0).astype(np.uint8)
    pad = np.pad(solid, 2)
    n = sum(pad[2 + dy: 2 + dy + solid.shape[0], 2 + dx: 2 + dx + solid.shape[1]] for dy in range(-2, 3) for dx in range(-2, 3))
    a[n <= 3] = 0
    rgb = np.asarray(im.convert("RGB")).copy(); rgb[a == 0] = 0
    return Image.fromarray(np.dstack([rgb, a]), "RGBA")

def place(im, scale, ox, oy):
    w, h = int(round(im.width * scale)), int(round(im.height * scale))
    r = im.resize((w, h), Image.LANCZOS)
    c = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    c.alpha_composite(r, (int(round(ox)), int(round(oy)))) if 0 <= ox and 0 <= oy else c.paste(r, (int(round(ox)), int(round(oy))))
    return c

def run(cid, spec):
    raw = lambda n: os.path.join(HERE, "raw", n)
    anchor = load(raw(spec["anchor"]))
    bb = anchor.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    headroom = spec.get("headroom", 64)
    # frame: by default the anchor's top goes to `headroom` and the raw bottom to the canvas bottom
    scale = spec.get("scale") or (CANVAS - headroom) / (anchor.height - bb[1])
    cx = spec.get("center_x", (bb[0] + bb[2]) / 2)          # raw-pixel column to put on the canvas centre
    ox = CANVAS / 2 - cx * scale
    oy = CANVAS - anchor.height * scale + spec.get("drop", 0)
    if spec.get("scale") and "headroom" in spec:              # explicit scale: pin the top, let the bottom crop
        oy = headroom - bb[1] * scale
        assert oy + anchor.height * scale >= CANVAS, "scale too small: bust would not reach the bottom edge"
    print(f"{cid}: anchor {anchor.size} bbox {bb} scale {scale:.3f} ox {ox:.0f} oy {oy:.0f}")
    for expr, name in spec["expressions"].items():
        im = load(raw(name))
        if name == spec["anchor"] or spec.get("register", True) is False:
            iou, s, dx, dy = 1.0, 1.0, 0, 0
        else:
            iou, s, dx, dy = register(anchor, im)
            # the edits come back pixel-aligned almost every time; ignore sub-grid jitter so the bust
            # never lifts off the bottom edge, and only correct genuine drifts
            if abs(s - 1.0) < 0.015 and abs(dx) <= 8 and abs(dy) <= 8: s, dx, dy = 1.0, 0, 0
        out = place(im, scale * s, ox + dx * scale, oy + dy * scale)
        if spec.get("mirror"): out = out.transpose(Image.FLIP_LEFT_RIGHT)
        out = clean_alpha(out)
        path = os.path.join(OUT, f"{cid}_{expr}.png")
        out.save(path, optimize=True)
        ob = out.getchannel("A").getbbox()
        print(f"  {expr:11s} <- {name:28s} reg iou {iou:.3f} s {s:.2f} d ({dx:+d},{dy:+d})  bbox {ob}")

if __name__ == "__main__":
    cast = json.load(open(os.path.join(HERE, "cast.json"), encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    for cid, spec in cast.items():
        if len(sys.argv) > 1 and cid not in sys.argv[1:]: continue
        run(cid, spec)
