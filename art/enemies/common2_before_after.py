"""Before/after comparison boards for the turret / brute / boss quality pass (system Python + PIL).

    python art/enemies/common2_before_after.py [type ...]        (default: turret brute boss)

Reads the preview set kept from before the pass in art/previews/enemies/<type>/before/ (a copy of
the old iso.png, thumb_160.png, turnaround.png and anim/<action>_NN.png stills) and the current
set in art/previews/enemies/<type>/, and writes art/previews/enemies/<type>/before_after.png:

    row 1   game camera (ortho, yaw 45, pitch 35.3): before | after, each with its thumbnail at
            1x (160 px, and 100 px where it exists)
    row 2-3 turnaround before, turnaround after
    row 4+  the animation reads that matter in play, before above after, 8 frames each:
            telegraph (scrubbed 0..1 by the game), attack, death
"""
from __future__ import annotations

import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEWS = os.path.abspath(os.path.join(HERE, "..", "previews", "enemies"))
BG = (28, 27, 33)
FG = (235, 230, 220)
BEFORE = (232, 150, 90)
AFTER = (120, 220, 150)
PAD = 10
W = 2000
ACTIONS = ["telegraph", "attack", "death"]


def font(size: int):
    for name in ("arialbd.ttf", "arial.ttf", "segoeui.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def fit(im: Image.Image, w: int | None = None, h: int | None = None) -> Image.Image:
    k = (w / im.width) if w else (h / im.height)
    return im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)


def tag(im: Image.Image, text: str, colour) -> Image.Image:
    out = Image.new("RGB", (im.width, im.height + 26), BG)
    out.paste(im, (0, 26))
    ImageDraw.Draw(out).text((4, 3), text, fill=colour, font=font(17))
    return out


def game_view(d: str) -> Image.Image | None:
    iso = os.path.join(d, "iso.png")
    if not os.path.exists(iso):
        return None
    a = fit(Image.open(iso).convert("RGB"), h=620)
    thumbs = [Image.open(p).convert("RGB") for p in (os.path.join(d, "thumb_160.png"), os.path.join(d, "thumb_100.png"))
              if os.path.exists(p)]
    out = Image.new("RGB", (a.width + PAD + 160, a.height), BG)
    out.paste(a, (0, 0))
    y = 0
    for t in thumbs:
        out.paste(t, (a.width + PAD, y))
        y += t.height + PAD
    return out


def anim_row(d: str, action: str, frame_w: int) -> Image.Image | None:
    fs = sorted(glob.glob(os.path.join(d, "anim", f"{action}_[0-9][0-9].png")))
    if not fs:
        return None
    ims = [fit(Image.open(f).convert("RGB"), w=frame_w) for f in fs]
    out = Image.new("RGB", (sum(i.width for i in ims) + 4 * (len(ims) - 1), ims[0].height), BG)
    x = 0
    for im in ims:
        out.paste(im, (x, 0))
        x += im.width + 4
    return out


def board(t: str) -> str | None:
    cur = os.path.join(PREVIEWS, t)
    old = os.path.join(cur, "before")
    if not os.path.isdir(old):
        print(f"{t}: no before/ folder, skipped")
        return None
    rows: list[Image.Image] = []
    a, b = game_view(old), game_view(cur)
    if a and b:
        r = Image.new("RGB", (W, a.height + 26), BG)
        r.paste(tag(a, "BEFORE - game camera, thumbnails at 1x", BEFORE), (0, 0))
        r.paste(tag(b, "AFTER - game camera, thumbnails at 1x", AFTER), (W // 2, 0))
        rows.append(r)
    for d, label, col in ((old, "BEFORE - turnaround", BEFORE), (cur, "AFTER - turnaround", AFTER)):
        p = os.path.join(d, "turnaround.png")
        if os.path.exists(p):
            rows.append(tag(fit(Image.open(p).convert("RGB"), w=W), label, col))
    fw = (W - 4 * 7) // 8
    for act in ACTIONS:
        for d, label, col in ((old, f"BEFORE - {act} (8 frames, t = 0..1)", BEFORE), (cur, f"AFTER - {act}", AFTER)):
            r = anim_row(d, act, fw)
            if r:
                rows.append(tag(r, label, col))
    title_h = 44
    out = Image.new("RGB", (W + 2 * PAD, title_h + sum(r.height + PAD for r in rows) + PAD), BG)
    ImageDraw.Draw(out).text((PAD, 8), f"{t} - quality pass, before / after", fill=FG, font=font(26))
    y = title_h
    for r in rows:
        out.paste(r, (PAD, y))
        y += r.height + PAD
    path = os.path.join(cur, "before_after.png")
    out.save(path)
    print("wrote", path)
    return path


def main() -> None:
    for t in sys.argv[1:] or ["turret", "brute", "boss"]:
        board(t)


if __name__ == "__main__":
    main()
