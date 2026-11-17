"""
Assembles review sheets from the renders (plain PIL, no Blender):
  python -I art/weapons/sheets.py
Writes, under art/previews/weapons/:
  <id>/thumb.png          96 px thumbnail (downsampled from thumb_384.png)
  <id>/sheet.png          concept | three-quarter | in hand (game camera) | thumbnails, side + top below
  <id>/before_after.png   earlier pass vs this one (melee only)
  thumbs.png              every thumbnail at native 96 px
  before_after.png        all six melee before/after rows
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PREV = os.path.join(ROOT, "art", "previews", "weapons")
CONCEPT = os.path.join(ROOT, "docs", "reference", "generated", "weapons")
MELEE = ["splice_blade", "stylus_shiv", "amp_sledge", "reel_lash", "speaker_knuckles", "vinyl_glaive"]
RANGED = ["mixtape_rocket", "needle_rail", "bleed_emitter", "bass_drop", "static_spray"]
PROJ = ["missile", "pierce", "phase", "arc", "burst", "bolt", "shock"]
BG = (24, 22, 30)
try:
    FONT = ImageFont.truetype("arialbd.ttf", 22)
    SMALL = ImageFont.truetype("arial.ttf", 16)
except Exception:
    FONT = SMALL = ImageFont.load_default()


def op(path):
    try:
        return Image.open(path).convert("RGB")
    except Exception:
        return None


def fit(im, w, h):
    if im is None:
        return Image.new("RGB", (w, h), BG)
    im = im.copy()
    im.thumbnail((w, h), Image.LANCZOS)
    out = Image.new("RGB", (w, h), BG)
    out.paste(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def label(im, text, xy=(10, 8), font=None):
    d = ImageDraw.Draw(im)
    d.text(xy, text, fill=(255, 210, 63), font=font or SMALL)
    return im


def thumbs():
    for it in MELEE + RANGED + PROJ:
        im = op(os.path.join(PREV, it, "thumb_384.png"))
        if im:
            im.resize((96, 96), Image.LANCZOS).save(os.path.join(PREV, it, "thumb.png"))
    items = MELEE + RANGED + PROJ
    sheet = Image.new("RGB", (len(items) * 104 + 8, 96 + 40), BG)
    for i, it in enumerate(items):
        t = op(os.path.join(PREV, it, "thumb.png"))
        if t:
            sheet.paste(t, (8 + i * 104, 8))
        ImageDraw.Draw(sheet).text((8 + i * 104, 110), it[:13], fill=(200, 200, 210))
    sheet.save(os.path.join(PREV, "thumbs.png"))


def sheet(it):
    d = os.path.join(PREV, it)
    H = 560
    cols = [(op(os.path.join(CONCEPT, it + ".png")), 840, "concept (image model)"),
            (op(os.path.join(d, "threeq.png")), 560, "model"),
            (op(os.path.join(d, "hand.png")), 560, "in hand, game camera (ortho, yaw 45, pitch 35)"),
            (op(os.path.join(d, "hand_close.png")), 560, "in hand, close")]
    W = sum(c[1] for c in cols)
    side = op(os.path.join(d, "side.png"))
    top = op(os.path.join(d, "top.png"))
    out = Image.new("RGB", (W, H + 420 + 44), BG)
    x = 0
    for im, w, text in cols:
        out.paste(label(fit(im, w, H), text), (x, 44))
        x += w
    out.paste(label(fit(side, W // 2, 420), "side"), (0, H + 44))
    out.paste(label(fit(top, W // 2 - 220, 420), "top / edge-on"), (W // 2, H + 44))
    t = op(os.path.join(d, "thumb.png"))
    if t:
        out.paste(t, (W - 200, H + 44 + 40))
        out.paste(t.resize((48, 48), Image.LANCZOS), (W - 90, H + 44 + 64))
        label(out, "96 px / 48 px", (W - 200, H + 44 + 150))
    label(out, it, (12, 8), FONT)
    out.save(os.path.join(d, "sheet.png"))


def before_after():
    rows = []
    for it in MELEE:
        d = os.path.join(PREV, it)
        cells = [("before", "before_threeq.png"), ("after", "threeq.png"), ("before, in hand", "before_hand.png"), ("after, in hand", "hand.png")]
        row = Image.new("RGB", (4 * 480, 480), BG)
        for i, (text, f) in enumerate(cells):
            row.paste(label(fit(op(os.path.join(d, f)), 480, 480), "%s - %s" % (it, text)), (i * 480, 0))
        row.save(os.path.join(d, "before_after.png"))
        rows.append(row)
    out = Image.new("RGB", (4 * 480, 480 * len(rows)), BG)
    for i, r in enumerate(rows):
        out.paste(r, (0, i * 480))
    out.save(os.path.join(PREV, "before_after.png"))


thumbs()
for it in MELEE + RANGED:
    sheet(it)
before_after()
print("sheets written to", PREV)
