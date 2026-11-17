"""
Compose decor / weapon preview renders into review sheets (plain Python 3 + Pillow; run outside
Blender after art/kit/build_decor.py or art/weapons/build_weapons.py has rendered the cells).

  python art/kit/decor_sheet.py strip <dir> [<dir> ...]   one row per piece: front/side/back/3-4/iso/thumb
  python art/kit/decor_sheet.py decor                     art/previews/decor/sheet_upper.png, sheet_lower.png
  python art/kit/decor_sheet.py weapons                   art/previews/weapons/sheet.png
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DECOR = os.path.join(ROOT, "art", "previews", "decor")
WEAPONS = os.path.join(ROOT, "art", "previews", "weapons")
VIEWS = ["front", "side", "back", "threequarter", "iso", "thumb_iso"]

UPPER = ["vines", "bush", "rubble__upper", "crate__upper", "barrel__upper", "chest__upper", "pipe__upper",
         "console__upper", "generator__upper", "vent__upper", "lamp__upper", "arch__upper", "neon", "cable",
         "wave_screen", "rune_panel"]
LOWER = ["vines", "bush", "rubble__lower", "crate__lower", "barrel__lower", "chest__lower", "pipe__lower",
         "console__lower", "generator__lower", "vent__lower", "lamp__lower", "arch__lower", "neon", "cable",
         "wave_screen", "rune_panel", "time_machine"]


def font(size):
    for name in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def strip(dirs, out):
    cell = 280
    rows = []
    for d in dirs:
        ims = []
        for v in VIEWS:
            p = os.path.join(d, f"{v}.png")
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGB")
            if v == "thumb_iso":
                canvas = Image.new("RGB", (cell, cell), (58, 54, 52))
                canvas.paste(im, ((cell - im.width) // 2, (cell - im.height) // 2))
                im = canvas
            else:
                im = im.resize((cell, cell), Image.LANCZOS)
            ims.append(im)
        rows.append((os.path.basename(d.rstrip("/\\")), ims))
    W = cell * len(VIEWS)
    H = (cell + 26) * len(rows)
    sheet = Image.new("RGB", (W, H), (30, 28, 30))
    dr = ImageDraw.Draw(sheet)
    f = font(16)
    for r, (name, ims) in enumerate(rows):
        y = r * (cell + 26)
        dr.text((6, y + 4), name, fill=(240, 230, 210), font=f)
        for c, im in enumerate(ims):
            sheet.paste(im, (c * cell, y + 26))
    sheet.save(out)
    print("wrote", out)


def grid(names, base, out, title, cols=6, cell_name="sheet_cell.png", cell=300):
    cells = []
    for n in names:
        p = os.path.join(base, n, cell_name)
        if os.path.exists(p):
            cells.append((n, Image.open(p).convert("RGB")))
        else:
            print("missing", p)
    rows = (len(cells) + cols - 1) // cols
    head = 54
    sheet = Image.new("RGB", (cols * cell, head + rows * (cell + 28)), (24, 22, 26))
    dr = ImageDraw.Draw(sheet)
    dr.text((12, 12), title, fill=(255, 210, 90), font=font(26))
    f = font(17)
    for i, (n, im) in enumerate(cells):
        r, c = divmod(i, cols)
        x, y = c * cell, head + r * (cell + 28)
        sheet.paste(im.resize((cell, cell), Image.LANCZOS), (x, y))
        dr.text((x + 8, y + cell + 4), n, fill=(235, 225, 205), font=f)
    sheet.save(out)
    print("wrote", out)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "decor"
    if cmd == "strip":
        dirs = sys.argv[2:]
        out = os.path.join(os.path.dirname(dirs[0].rstrip("/\\")), "strip_" + "_".join(
            os.path.basename(d.rstrip("/\\")) for d in dirs)[:80] + ".png")
        strip(dirs, out)
    elif cmd == "decor":
        grid(UPPER, DECOR, os.path.join(DECOR, "sheet_upper.png"),
             "OVERDUB decor - upper look (fixed scale, 1x1 tile under each)")
        grid(LOWER, DECOR, os.path.join(DECOR, "sheet_lower.png"),
             "OVERDUB decor - lower look (fixed scale, 1x1 tile under each; time machine at 0.6x)")
    elif cmd == "weapons":
        names = ["splice_blade", "stylus_shiv", "amp_sledge", "reel_lash", "speaker_knuckles", "vinyl_glaive"]
        grid(names, WEAPONS, os.path.join(WEAPONS, "sheet.png"),
             "OVERDUB melee weapons - with a 1.6-unit player silhouette", cols=3, cell=420)
        strip([os.path.join(WEAPONS, n) for n in names], os.path.join(WEAPONS, "views.png"))


if __name__ == "__main__":
    main()
