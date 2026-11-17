"""Render the comparison plates into art/accessibility/plates/.

    python -I art/accessibility/make_plates.py

plate_themes_<set>.png   the four cassette marks on every theme floor and on the HUD panel, one
                         row per vision (normal, protanopia, deuteranopia, tritanopia). Each
                         theme cell also carries that theme's neon / hazard / danger chips, so a
                         cassette colour that reads as a hazard is visible at a glance. Left half
                         of a cell: keylined shape rings with letters. Bottom strip: bare dots
                         with no keyline, shape or letter (the worst case: sparks, trails).
plate_swatches.png       current vs proposed vs high-contrast swatches next to the reserved
                         colours, per vision.
plate_identity.png       the non-colour identity: shape, ring, pattern and letter, in colour and
                         with all colour removed.
The simulation is applied to the finished picture (Machado 2009, severity 1.0), so floors, neon and
marks are all transformed together.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import cvd
import refs

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = refs.ROOT
TEX = os.path.join(ROOT, "assets", "textures", "patterns")
OUT = os.path.join(HERE, "plates")
SHAPES = ["circle", "triangle", "square", "plus"]
PATTERNS = ["stripes", "dots", "chevrons", "grid"]
LET = ["a", "b", "c", "d"]
INK = "#14110f"
PAPER = "#f3ead8"

CW, CH = 360, 250  # one cell


def font(size, bold=True):
    for name in (("arialbd.ttf" if bold else "arial.ttf"), "segoeuib.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def rgb8(h):
    return tuple(int(round(x * 255)) for x in cvd.hex_to_rgb(h))


def mask(name, px):
    im = Image.open(os.path.join(TEX, name)).convert("RGBA").getchannel("A")
    return im.resize((px, px), Image.LANCZOS)


def tile(name, w, h, scale=1.0):
    t = Image.open(os.path.join(TEX, name)).convert("L")
    if scale != 1.0:
        s = max(8, int(round(t.width * scale)))
        t = t.resize((s, s), Image.LANCZOS)
    out = Image.new("L", (w, h))
    for y in range(0, h, t.height):
        for x in range(0, w, t.width):
            out.paste(t, (x, y))
    return out


def stamp(img, m, xy, color, grow=0):
    """Paste solid `color` through mask `m` (optionally dilated by `grow` px) centred at xy."""
    if grow > 0:
        pad = grow + 2
        big = Image.new("L", (m.width + pad * 2, m.height + pad * 2), 0)
        big.paste(m, (pad, pad))
        big = big.filter(ImageFilter.MaxFilter(grow * 2 + 1)).filter(ImageFilter.GaussianBlur(0.6))
        m = big
    img.paste(Image.new("RGB", m.size, rgb8(color)), (int(xy[0] - m.width / 2), int(xy[1] - m.height / 2)), m)


def text_c(d, xy, s, f, fill):
    b = d.textbbox((0, 0), s, font=f)
    d.text((xy[0] - (b[0] + b[2]) / 2, xy[1] - (b[1] + b[3]) / 2), s, font=f, fill=fill)


def best_text(c):
    return INK if float(cvd.contrast(cvd.hex_to_rgb(c), cvd.hex_to_rgb(INK))) >= float(cvd.contrast(cvd.hex_to_rgb(c), cvd.hex_to_rgb(PAPER))) else PAPER


def theme_cell(pal, colors, double_keyline):
    im = Image.new("RGB", (CW, CH), rgb8(pal["floor_color"]))
    d = ImageDraw.Draw(im)
    # Floor: checker of floor / floor_alt slabs with grout lines.
    s = 45
    for gy in range(0, CH, s):
        for gx in range(0, CW, s):
            if ((gx // s) + (gy // s)) % 2:
                d.rectangle([gx, gy, gx + s, gy + s], fill=rgb8(pal["floor_alt"]))
            d.rectangle([gx, gy, gx + s, gy + s], outline=rgb8(pal["grout"]))
    # Back wall with the theme's emissive accents and the danger colours that share the frame.
    d.rectangle([0, 0, CW, 46], fill=rgb8(pal["wall"]))
    d.rectangle([0, 0, CW, 9], fill=rgb8(pal["wall_top"]))
    chips = [pal["neon_a"], pal["neon_b"], pal["neon_c"], pal["graffiti"], pal["foliage"], pal["hazard"],
             refs.RESERVED["moxie_yellow"], refs.RESERVED["enemy_eye"], refs.RESERVED["laser"], refs.RESERVED["shield_teal"]]
    labels = ["nA", "nB", "nC", "graf", "fol", "haz", "mox", "eye", "laser", "shld"]
    cw = CW / len(chips)
    f8 = font(10)
    for i, c in enumerate(chips):
        d.rectangle([i * cw + 3, 14, (i + 1) * cw - 3, 40], fill=rgb8(c), outline=rgb8(pal["ink"]))
        text_c(d, (i * cw + cw / 2, 27), labels[i], f8, rgb8(best_text(c)))
    # Keylined shape rings with letters (how a floor ring should be drawn).
    fl = font(30)
    for i, c in enumerate(colors):
        cx = 48 + i * 88
        cy = 112
        ring = mask("shape_%s_%s_ring.png" % (LET[i], SHAPES[i]), 78)
        if double_keyline:
            stamp(im, ring, (cx, cy), INK, grow=5)
            stamp(im, ring, (cx, cy), PAPER, grow=2)
        else:
            stamp(im, ring, (cx, cy), INK, grow=3)
        stamp(im, ring, (cx, cy), c)
        # Letter badge next to the ring (ink disc, coloured letter), like the in-world badge.
        d.ellipse([cx + 16, cy + 20, cx + 46, cy + 50], fill=rgb8(INK))
        text_c(d, (cx + 31, cy + 34), "ABCD"[i], font(20), rgb8(c))
    # Worst case: bare dots (spark cores, trail bits) with no keyline, shape or letter.
    for i, c in enumerate(colors):
        cx = 48 + i * 88
        d.ellipse([cx - 13, 196, cx + 13, 222], fill=rgb8(c))
        for k in range(1, 4):
            r = 6 - k
            d.ellipse([cx - 13 - k * 14 - r, 209 - r, cx - 13 - k * 14 + r, 209 + r], fill=rgb8(c))
    return im


def hud_cell(colors, patterns_on):
    im = Image.new("RGB", (CW, CH), rgb8(refs.HUD["panel"]))
    d = ImageDraw.Draw(im)
    f = font(22)
    for i, c in enumerate(colors):
        y = 20 + i * 56
        # Lane on the ruler track.
        d.rectangle([64, y, CW - 14, y + 40], fill=rgb8(refs.HUD["track"]))
        seg = Image.new("RGB", (190, 32), rgb8(c))
        if patterns_on:
            t = tile("pattern_%s_%s.png" % (LET[i], PATTERNS[i]), 190, 32, 0.5)
            ink = Image.new("RGB", (190, 32), rgb8(best_text(c)))
            seg = Image.composite(Image.blend(seg, ink, 0.55), seg, t)
        im.paste(seg, (68, y + 4))
        # Lane-end shape and letter chip.
        sm = mask("shape_%s_%s.png" % (LET[i], SHAPES[i]), 30)
        stamp(im, sm, (284, y + 20), c)
        d.rounded_rectangle([12, y + 2, 52, y + 38], 6, fill=rgb8(c), outline=rgb8(INK), width=2)
        text_c(d, (32, y + 19), "ABCD"[i], f, rgb8(best_text(c)))
        d.text((306, y + 9), "1.0x", font=font(16), fill=rgb8(c))
    return im


def simulate_img(im, vision):
    a = np.asarray(im, dtype=np.float64) / 255.0
    return Image.fromarray(np.clip(np.round(cvd.simulate(a, vision) * 255), 0, 255).astype(np.uint8), "RGB")


def plate_themes(name, colors, double_keyline=False):
    pal = refs.theme_palettes()
    cols = refs.THEMES + ["hud"]
    left, top = 130, 64
    W, H = left + len(cols) * (CW + 8), top + 4 * (CH + 8)
    plate = Image.new("RGB", (W, H), (24, 22, 26))
    d = ImageDraw.Draw(plate)
    d.text((12, 10), "%s   %s" % (name, "  ".join("%s %s" % ("ABCD"[i], c) for i, c in enumerate(colors))), font=font(22), fill=(240, 236, 226))
    row = Image.new("RGB", (len(cols) * (CW + 8), CH))
    for i, t in enumerate(cols):
        cell = hud_cell(colors, True) if t == "hud" else theme_cell(pal[t], colors, double_keyline)
        row.paste(cell, (i * (CW + 8), 0))
        d.text((left + i * (CW + 8) + 4, 42), t.upper(), font=font(15), fill=(200, 196, 188))
    for r, v in enumerate(cvd.VISIONS):
        plate.paste(simulate_img(row, v), (left, top + r * (CH + 8)))
        d.text((10, top + r * (CH + 8) + CH / 2 - 8), v, font=font(15), fill=(240, 236, 226))
    plate.save(os.path.join(OUT, "plate_themes_%s.png" % name))


def plate_swatches(sets):
    reserved = ["laser", "enemy_fx", "enemy_eye", "hazard_upper", "moxie_yellow", "shield_teal", "state_desync", "ghost_grey"]
    sw, sh = 86, 54
    left, top = 150, 40
    W = left + 4 * sw + 30 + len(reserved) * sw + 16
    block = 4 * (sh + 6) + 46
    plate = Image.new("RGB", (W, top + len(sets) * block), (24, 22, 26))
    d = ImageDraw.Draw(plate)
    f = font(13)
    for k, r in enumerate(reserved):
        d.text((left + 4 * sw + 30 + k * sw + 3, 14), r.replace("_", " "), font=font(11), fill=(200, 196, 188))
    for si, (name, colors) in enumerate(sets.items()):
        y0 = top + si * block
        d.text((10, y0 + 2), name, font=font(18), fill=(240, 236, 226))
        strip = Image.new("RGB", (W - left, sh), (24, 22, 26))
        sd = ImageDraw.Draw(strip)
        for i, c in enumerate(colors):
            sd.rectangle([i * sw, 0, (i + 1) * sw - 4, sh], fill=rgb8(c))
            text_c(sd, (i * sw + sw / 2 - 2, sh / 2), "ABCD"[i] + " " + c, f, rgb8(best_text(c)))
        for k, r in enumerate(reserved):
            x = 4 * sw + 30 + k * sw
            sd.rectangle([x, 0, x + sw - 4, sh], fill=rgb8(refs.RESERVED[r]))
        for vi, v in enumerate(cvd.VISIONS):
            y = y0 + 28 + vi * (sh + 6)
            plate.paste(simulate_img(strip, v), (left, y))
            d.text((14, y + sh / 2 - 8), v, font=f, fill=(200, 196, 188))
    plate.save(os.path.join(OUT, "plate_swatches.png"))


def plate_identity(colors):
    cw, pad = 250, 16
    W, H = pad + 4 * (cw + pad), 560
    im = Image.new("RGB", (W, H), rgb8(refs.HUD["panel"]))
    d = ImageDraw.Draw(im)
    for i, c in enumerate(colors):
        x = pad + i * (cw + pad)
        d.text((x, 10), "%s  %s / %s" % ("ABCD"[i], SHAPES[i], PATTERNS[i]), font=font(18), fill=rgb8(PAPER))
        for row, col in enumerate((c, "#d9d9d9")):
            y = 44 + row * 256
            stamp(im, mask("shape_%s_%s.png" % (LET[i], SHAPES[i]), 72), (x + 40, y + 40), col)
            stamp(im, mask("shape_%s_%s_ring.png" % (LET[i], SHAPES[i]), 72), (x + 124, y + 40), col)
            d.rounded_rectangle([x + 172, y + 6, x + 240, y + 74], 8, fill=rgb8(col), outline=rgb8(INK), width=2)
            text_c(d, (x + 206, y + 38), "ABCD"[i], font(46), rgb8(INK))
            # 2x2 tiles of the pattern over the colour, with the tile boundary NOT drawn: no seam shows.
            base = Image.new("RGB", (cw, 150), rgb8(col))
            t = tile("pattern_%s_%s.png" % (LET[i], PATTERNS[i]), cw, 150, 0.75)
            ink = Image.new("RGB", (cw, 150), rgb8(INK))
            im.paste(Image.composite(Image.blend(base, ink, 0.6), base, t), (x, y + 88))
    d.text((pad, H - 22), "Top: cassette colour. Bottom: colour removed. Shape, pattern and letter still name the cassette.", font=font(13), fill=rgb8(PAPER))
    im.save(os.path.join(OUT, "plate_identity.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    sets = {"current": refs.CURRENT}
    sets.update(json.load(open(os.path.join(HERE, "sets.json"))))
    for name, colors in sets.items():
        if name == "coral_variant":
            continue
        plate_themes(name, colors, double_keyline=(name == "high_contrast"))
    plate_swatches(sets)
    plate_identity(sets["proposed"])
    print("plates written to", OUT)


if __name__ == "__main__":
    main()
