"""Before/after comparison boards for the enemy quality pass (plain Python 3 + Pillow, no Blender).

    python art/enemies/common_before_after.py [type ...]      (default: grunt stalker shielder drone)

For each type it reads the previews kept from before the pass in
art/previews/enemies/<type>/before/ (a copy of the old preview set: <type>_iso.png,
<type>_thumb100.png, <type>_turnaround.png, <type>_sheet_iso.png) and the current previews in
art/previews/enemies/<type>/, and writes art/previews/enemies/<type>/before_after.png:

    row 1  the isometric game view (ortho, yaw 45, pitch 35), with the 100 px thumbnail inset
    row 2  the turnaround before, row 3 the turnaround after
    row 4  the animation reads that matter most in play: the end of the telegraph wind-up, the
           attack's hit frame, the stagger and the death rest pose, before | after
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEWS = os.path.abspath(os.path.join(HERE, "..", "previews", "enemies"))
W = 1640
PAD = 12
BG = (38, 38, 44)
INK = (235, 232, 224)
DIM = (160, 158, 150)
ROWS = ["idle", "move", "telegraph", "attack", "stagger", "death"]
# (action, column in the 8-column contact sheet, caption)
READS = [("telegraph", 7, "telegraph end"), ("attack", 1, "attack hit"), ("stagger", 1, "stagger"),
         ("death", 7, "death rest")]


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # older Pillow
        return ImageFont.load_default()


def sheet_tile(path, action, col):
    im = Image.open(path).convert("RGB")
    tw, th = im.width // 8, im.height // len(ROWS)
    r = ROWS.index(action)
    return im.crop((col * tw + 3, r * th + 3, (col + 1) * tw - 1, (r + 1) * th - 1))


def board(name):
    cur = os.path.join(PREVIEWS, name)
    old = os.path.join(cur, "before")
    half = (W - 3 * PAD) // 2
    f_big, f_small = font(30), font(20)
    rows = []

    # Row 1: iso + thumbnail.
    iso_h = 560
    row = Image.new("RGB", (W, iso_h + 44), BG)
    d = ImageDraw.Draw(row)
    for i, (label, folder) in enumerate((("BEFORE", old), ("AFTER", cur))):
        x0 = PAD + i * (half + PAD)
        d.text((x0, 6), f"{name}  -  {label}", fill=INK, font=f_big)
        iso = Image.open(os.path.join(folder, f"{name}_iso.png")).convert("RGB").resize((iso_h, iso_h), Image.LANCZOS)
        row.paste(iso, (x0, 44))
        th = Image.open(os.path.join(folder, f"{name}_thumb100.png")).convert("RGB")
        row.paste(th, (x0 + iso_h + PAD, 44))
        d.text((x0 + iso_h + PAD, 44 + 106), "100 px", fill=DIM, font=f_small)
        th2 = th.resize((200, 200), Image.NEAREST)
        row.paste(th2, (x0 + iso_h + PAD, 44 + 140))
        d.text((x0 + iso_h + PAD, 44 + 346), "100 px, 2x", fill=DIM, font=f_small)
    rows.append(row)

    # Rows 2-3: turnarounds.
    for label, folder in (("turnaround before", old), ("turnaround after", cur)):
        ta = Image.open(os.path.join(folder, f"{name}_turnaround.png")).convert("RGB")
        tw = W - 2 * PAD
        ta = ta.resize((tw, round(ta.height * tw / ta.width)), Image.LANCZOS)
        row = Image.new("RGB", (W, ta.height + 30), BG)
        ImageDraw.Draw(row).text((PAD, 4), label, fill=DIM, font=f_small)
        row.paste(ta, (PAD, 30))
        rows.append(row)

    # Row 4: animation reads, before | after per read.
    t = (W - PAD * (len(READS) * 2 + 1)) // (len(READS) * 2)
    row = Image.new("RGB", (W, t + 34), BG)
    d = ImageDraw.Draw(row)
    for i, (action, col, caption) in enumerate(READS):
        for j, (label, folder) in enumerate((("before", old), ("after", cur))):
            x0 = PAD + (i * 2 + j) * (t + PAD)
            tile = sheet_tile(os.path.join(folder, f"{name}_sheet_iso.png"), action, col).resize((t, t), Image.LANCZOS)
            row.paste(tile, (x0, 30))
            d.text((x0, 4), f"{caption}: {label}", fill=INK if j else DIM, font=f_small)
    rows.append(row)

    out = Image.new("RGB", (W, sum(r.height for r in rows) + PAD * (len(rows) + 1)), BG)
    y = PAD
    for r in rows:
        out.paste(r, (0, y))
        y += r.height + PAD
    path = os.path.join(cur, "before_after.png")
    out.save(path)
    print(f"[before_after] {path} {out.size}")


def main():
    types = sys.argv[1:] or ["grunt", "stalker", "shielder", "drone"]
    for t in types:
        board(t)


if __name__ == "__main__":
    main()
