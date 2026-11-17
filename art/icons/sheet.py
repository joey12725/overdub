"""Contact sheets for the icon family: every group on a light and a dark background, at a big and a small size.

  python -I art/icons/sheet.py            -> art/icons/sheet_<group>_{light,dark}.png  (+ sheet_small_{light,dark}.png)
  python -I art/icons/sheet.py gear/amp_sledge gear/click_visor   -> art/icons/sheet_pick.png (ad-hoc review sheet)
"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "ui", "icons")
BG = {"light": (236, 229, 214), "dark": (24, 20, 32)}
FG = {"light": (30, 26, 36), "dark": (230, 226, 236)}
GROUPS = [("gear", 160, (64,)), ("abilities", 160, (64, 32)), ("slots", 160, (64, 32)), ("actions", 128, (48, 24)), ("tape", 128, (48, 24))]


def font(n):
    try:
        return ImageFont.truetype("arial.ttf", n)
    except Exception:
        return ImageFont.load_default()


def ids(group):
    d = os.path.join(OUT, group)
    return [f[:-4] for f in sorted(os.listdir(d)) if f.endswith(".png")] if os.path.isdir(d) else []


def sheet(items, big, smalls, bgname, cols):
    """items: list of (label, path)."""
    cw = max(big, 110) + 16
    ch = big + 8 + sum(s + 6 for s in smalls) + 22
    rows = (len(items) + cols - 1) // cols
    im = Image.new("RGB", (cols * cw + 16, rows * ch + 16), BG[bgname])
    d = ImageDraw.Draw(im)
    f = font(11)
    for i, (label, path) in enumerate(items):
        x, y = 16 + (i % cols) * cw, 16 + (i // cols) * ch
        src = Image.open(path).convert("RGBA")
        b = src.resize((big, big), Image.LANCZOS)
        im.paste(b, (x + (cw - 16 - big) // 2, y), b)
        yy = y + big + 6
        xx = x
        for s in smalls:
            t = src.resize((s, s), Image.LANCZOS)
            im.paste(t, (x + (cw - 16 - s) // 2, yy), t)
            yy += s + 6
        d.text((x, yy), label[:20], fill=FG[bgname], font=f)
    return im


def main():
    sel = sys.argv[1:]
    if sel:
        items = [(k.split("/")[-1], os.path.join(OUT, k + ".png")) for k in sel]
        a = sheet(items, 200, (64, 32), "light", min(6, len(items)))
        b = sheet(items, 200, (64, 32), "dark", min(6, len(items)))
        im = Image.new("RGB", (a.width, a.height + b.height))
        im.paste(a, (0, 0)); im.paste(b, (0, a.height))
        im.save(os.path.join(HERE, "sheet_pick.png"))
        return
    for bgname in BG:
        small_items = []
        for g, big, smalls in GROUPS:
            items = [(i, os.path.join(OUT, g, i + ".png")) for i in ids(g)]
            if not items:
                continue
            cols = 8 if g == "gear" else min(10, len(items))
            sheet(items, big, smalls, bgname, cols).save(os.path.join(HERE, "sheet_%s_%s.png" % (g, bgname)))
            small_items += items
        # everything at HUD sizes only: 64 for gear/abilities/slots, 24 for glyphs
        cols = 16
        cell = 76
        rows = (len(small_items) + cols - 1) // cols
        im = Image.new("RGB", (cols * cell + 12, rows * cell + 12), BG[bgname])
        for i, (label, path) in enumerate(small_items):
            s = 24 if (os.sep + "actions" + os.sep in path or os.sep + "tape" + os.sep in path) else 64
            t = Image.open(path).convert("RGBA").resize((s, s), Image.LANCZOS)
            im.paste(t, (12 + (i % cols) * cell + (64 - s) // 2, 12 + (i // cols) * cell + (64 - s) // 2), t)
        im.save(os.path.join(HERE, "sheet_small_%s.png" % bgname))


main()
