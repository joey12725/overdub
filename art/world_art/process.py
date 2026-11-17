"""OVERDUB world art: raw image-model output -> game textures + contact sheets.
Run:  python -I art/world_art/process.py
Reads art/world_art/raw/*.png, verifies alpha, trims, pads to a consistent canvas per family and writes
assets/textures/{graffiti,decals,backdrops,tape}/**, then builds art/world_art/contact/*.png on a
warm-stone and a dark-metal ground. Deterministic; safe to re-run."""
import json, math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
RAW = os.path.join(HERE, "raw")
TEX = os.path.join(ROOT, "assets", "textures")
CONTACT = os.path.join(HERE, "contact")
STONE, METAL = (196, 160, 128), (52, 40, 62)
report = []


def out(*parts):
    p = os.path.join(TEX, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def raw(name):
    p = os.path.join(RAW, name + ".png")
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


def clean(im, floor=10):
    """Kill near-zero alpha haze so the trim box is honest."""
    a = np.array(im)
    a[..., 3][a[..., 3] < floor] = 0
    return Image.fromarray(a)


def bleed(im):
    """Fill the RGB of fully transparent pixels with the nearest paint colour (iterative dilation), so
    filtering and mipmaps never pull a dark or white fringe in from invisible pixels."""
    a = np.array(im).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3]
    known = al > 0
    if not known.any():
        return im
    acc = rgb * known[..., None]
    w = known.astype(np.float32)
    for _ in range(24):
        if w.min() > 0:
            break
        s = np.zeros_like(acc); n = np.zeros_like(w)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            s += np.roll(acc, (dy, dx), (0, 1)); n += np.roll(w, (dy, dx), (0, 1))
        grow = (w == 0) & (n > 0)
        acc[grow] = s[grow] / n[grow][:, None]
        w[grow] = 1
    mean = (rgb * al[..., None]).sum((0, 1)) / max(al.sum(), 1)
    acc[w == 0] = mean
    a[..., :3] = np.where(known[..., None], rgb, acc)
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def fit(im, canvas, margin, stretch_w=False):
    """Trim to the alpha box, scale to fit canvas minus margin, centre. Returns (image, coverage)."""
    im = clean(im)
    box = im.getchannel("A").getbbox()
    if box is None:
        raise ValueError("empty alpha")
    touching = box[0] <= 1 or box[1] <= 1 or box[2] >= im.width - 1 or box[3] >= im.height - 1
    im = im.crop(box)
    cw, ch = canvas
    mw = 0 if stretch_w else margin
    s = min((cw - 2 * mw) / im.width, (ch - 2 * margin) / im.height)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    c = Image.new("RGBA", canvas, (0, 0, 0, 0))
    c.alpha_composite(im, ((cw - im.width) // 2, (ch - im.height) // 2))
    return bleed(c), touching


def check(path, im, touching=False, kind="rgba"):
    a = np.array(im.getchannel("A")) if im.mode == "RGBA" else None
    row = {"file": os.path.relpath(path, ROOT).replace("\\", "/"), "size": im.size}
    if a is not None:
        row["alpha_min"], row["alpha_max"] = int(a.min()), int(a.max())
        row["coverage"] = round(float((a > 0).mean()), 3)
        row["corners_clear"] = bool(a[0, 0] == 0 and a[0, -1] == 0 and a[-1, 0] == 0 and a[-1, -1] == 0)
        row["raw_touched_edge"] = bool(touching)
        ok = a.min() == 0 and a.max() > 200 and (row["corners_clear"] or kind == "strip")
        row["ok"] = bool(ok)
    else:
        row["ok"] = True
    report.append(row)


def export(name, dest, canvas, margin, stretch_w=False, kind="rgba"):
    im = raw(name)
    if im is None:
        print("MISSING raw", name); return None
    res, touching = fit(im, canvas, margin, stretch_w)
    res.save(dest, optimize=True)
    check(dest, res, touching, kind)
    return res


# ───────────────────────────── graffiti ─────────────────────────────
def graffiti():
    for f in sorted(os.listdir(RAW)):
        if f.startswith("graffiti__") and f.endswith(".png"):
            n = f[len("graffiti__"):-4]
            export("graffiti__" + n, out("graffiti", n + ".png"), (768, 768), 24)


# ───────────────────────────── decals ─────────────────────────────
SQUARE = ["lane_arrow", "lane_arrow_turn", "worn_paint_yellow", "do_not_stand", "keep_clear", "moss_a", "leaves",
          "crack_a", "crack_b", "scorch_a"]
WIDE = ["hazard_chevrons", "moss_b", "scorch_b", "exit"]
BAND = ["hazard_stripe", "worn_line"]          # run edge to edge horizontally


def quads(name, names):
    im = raw(name)
    if im is None:
        print("MISSING raw", name); return
    im = clean(im)
    w, h = im.size
    for i, n in enumerate(names):
        q = im.crop(((i % 2) * w // 2, (i // 2) * h // 2, (i % 2 + 1) * w // 2, (i // 2 + 1) * h // 2))
        res, touching = fit(q, (512, 512), 20)
        p = out("decals", n + ".png"); res.save(p, optimize=True); check(p, res, touching)


def decals():
    for n in SQUARE:
        export("decal__" + n, out("decals", n + ".png"), (512, 512), 16)
    for n in WIDE:
        export("decal__" + n, out("decals", n + ".png"), (1024, 512), 16)
    for n in BAND:
        export("decal__" + n, out("decals", n + ".png"), (1024, 256), 8, stretch_w=True, kind="strip")
    quads("decal__bay_numbers", ["bay_01", "bay_02", "bay_03", "bay_04"])
    quads("decal__bay_letters", ["bay_a", "bay_b", "bay_c", "bay_d"])
    runes()


# ───────────────────────────── rune glyphs ─────────────────────────────
CELL = 128


def segment(mask, n_cols=8, n_rows=5):
    """Split a white-on-black glyph sheet into rows then columns using empty gutters."""
    def runs(profile, want):
        on = profile > 0
        spans, start = [], None
        for i, v in enumerate(on):
            if v and start is None: start = i
            if not v and start is not None: spans.append([start, i]); start = None
        if start is not None: spans.append([start, len(on)])
        # merge the closest spans until we have the wanted count (glyphs made of separate strokes)
        while len(spans) > want:
            gaps = [spans[i + 1][0] - spans[i][1] for i in range(len(spans) - 1)]
            i = int(np.argmin(gaps)); spans[i][1] = spans[i + 1][1]; del spans[i + 1]
        return spans
    cells = []
    for y0, y1 in runs(mask.sum(1), n_rows):
        for x0, x1 in runs(mask[y0:y1].sum(0), n_cols):
            sub = mask[y0:y1, x0:x1]
            ys, xs = np.where(sub > 0)
            cells.append((x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1))
    return cells


def runes():
    src = raw("decal__rune_glyphs_src")
    if src is None:
        print("MISSING raw rune sheet"); return
    lum = np.array(src.convert("L")).astype(np.float32)
    alpha = np.clip((lum - 40) / (215 - 40), 0, 1)
    mask = (alpha > 0.35).astype(np.uint8)
    cells = segment(mask)
    glyphs = []
    for (x0, y0, x1, y1) in cells:
        g = Image.fromarray((alpha[y0:y1, x0:x1] * 255).astype(np.uint8))
        s = min((CELL - 24) / g.width, (CELL - 24) / g.height)
        g = g.resize((max(1, round(g.width * s)), max(1, round(g.height * s))), Image.LANCZOS)
        c = Image.new("L", (CELL, CELL), 0)
        c.paste(g, ((CELL - g.width) // 2, (CELL - g.height) // 2))
        glyphs.append(c)
    print("rune glyphs segmented:", len(glyphs))

    # forty DISTINCT glyphs: where the model drew two near-twins, turn the later one (180, then 90, 270)
    # until it no longer matches any other glyph or its mirror image.
    def iou(a, b):
        a, b = np.array(a) > 128, np.array(b) > 128
        return max((a & c).sum() / max((a | c).sum(), 1) for c in (b, b[:, ::-1]))
    for j in range(len(glyphs)):
        for turn in (0, 180, 90, 270):
            cand = glyphs[j].rotate(turn) if turn else glyphs[j]
            if all(iou(glyphs[i], cand) < 0.72 for i in range(len(glyphs)) if i != j):
                if turn:
                    print("  rune %d turned %d degrees to separate it from a twin" % (j, turn))
                glyphs[j] = cand
                break
    worst = max(iou(glyphs[i], glyphs[j]) for i in range(len(glyphs)) for j in range(i + 1, len(glyphs)))
    print("  most similar pair of glyphs: overlap %.2f (1.00 = identical)" % worst)

    def white(a):
        im = Image.new("RGBA", a.size, (255, 255, 255, 0)); im.putalpha(a); return im

    atlas = Image.new("L", (8 * CELL, 5 * CELL), 0)
    for i, g in enumerate(glyphs[:40]):
        atlas.paste(g, ((i % 8) * CELL, (i // 8) * CELL))
    p = out("decals", "runes", "rune_glyphs_atlas.png"); white(atlas).save(p, optimize=True); check(p, white(atlas))
    for i, g in enumerate(glyphs[:40]):
        white(g).save(out("decals", "runes", "glyphs", "rune_%02d.png" % i), optimize=True)
    with open(out("decals", "runes", "rune_glyphs_atlas.json"), "w") as f:
        json.dump({"cell": CELL, "columns": 8, "rows": 5, "count": min(40, len(glyphs)),
                   "note": "glyph i is at column i % 8, row i // 8; white on transparent, tint with modulate"}, f, indent=1)

    rng = random.Random(1986)

    def strip(count, vertical):
        ids = rng.sample(range(len(glyphs[:40])), count)
        size = (CELL, CELL * count) if vertical else (CELL * count, CELL)
        s = Image.new("L", size, 0)
        for k, i in enumerate(ids):
            s.paste(glyphs[i], (0, k * CELL) if vertical else (k * CELL, 0))
        d = ImageDraw.Draw(s)                      # thin carved rails either side of the text
        if vertical:
            d.rectangle((4, 6, 7, size[1] - 7), fill=200); d.rectangle((CELL - 8, 6, CELL - 5, size[1] - 7), fill=200)
        else:
            d.rectangle((6, 4, size[0] - 7, 7), fill=200); d.rectangle((6, CELL - 8, size[0] - 7, CELL - 5), fill=200)
        return white(s)

    for k in range(3):
        p = out("decals", "runes", "rune_strip_h_%02d.png" % (k + 1)); im = strip(8, False); im.save(p, optimize=True); check(p, im, kind="strip")
    for k in range(2):
        p = out("decals", "runes", "rune_strip_v_%02d.png" % (k + 1)); im = strip(8, True); im.save(p, optimize=True); check(p, im, kind="strip")

    # rune ring: sixteen glyphs facing outward around a circle, for floor seals / the exit pad / the core
    R = 512
    ring = Image.new("L", (R, R), 0)
    ids = rng.sample(range(len(glyphs[:40])), 16)
    for k, i in enumerate(ids):
        ang = 360.0 * k / 16
        g = glyphs[i].resize((72, 72), Image.LANCZOS)
        layer = Image.new("L", (R, R), 0)
        layer.paste(g, (R // 2 - 36, 30))
        layer = layer.rotate(-ang, resample=Image.BICUBIC, center=(R / 2, R / 2))
        ring = Image.fromarray(np.maximum(np.array(ring), np.array(layer)))
    d = ImageDraw.Draw(ring)
    for rad, wd in ((248, 4), (146, 4), (136, 2)):
        d.ellipse((R / 2 - rad, R / 2 - rad, R / 2 + rad, R / 2 + rad), outline=220, width=wd)
    p = out("decals", "runes", "rune_ring.png"); white(ring).save(p, optimize=True); check(p, white(ring))


# ───────────────────────────── backdrops / tape ─────────────────────────────
def backdrops():
    for n in ("upper", "mid", "lower", "core"):
        im = raw("backdrop__" + n)
        if im is None:
            print("MISSING raw backdrop", n); continue
        im = im.convert("RGB")
        if im.size != (1536, 1024):
            im = im.resize((1536, 1024), Image.LANCZOS)
        p = out("backdrops", "%s.png" % n); im.save(p, optimize=True); check(p, im)
        a = np.array(im.convert("L")).astype(np.float32)
        c = a[256:768, 384:1152]
        print("backdrop %-5s luma mean %.0f  std(all) %.1f  std(centre) %.1f" % (n, a.mean(), a.std(), c.std()))


def tape():
    for l in "abcd":
        im = raw("jcard__" + l)
        if im is not None:
            im = im.convert("RGB")
            if im.size != (1024, 1536):
                im = im.resize((1024, 1536), Image.LANCZOS)
            p = out("tape", "jcard_%s.png" % l); im.save(p, optimize=True); check(p, im)
        else:
            print("MISSING raw jcard", l)
        export("label__" + l, out("tape", "label_%s.png" % l), (1024, 640), 16)
    for f in sorted(os.listdir(RAW)):
        if f.startswith("sticker__") and f.endswith(".png"):
            n = f[len("sticker__"):-4]
            export("sticker__" + n, out("tape", "stickers", n + ".png"), (1024, 512), 20)


# ───────────────────────────── contact sheets ─────────────────────────────
def font(sz):
    for p in ("C:/Windows/Fonts/consola.ttf", "C:/Windows/Fonts/arial.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def sheet(title, paths, bg, cols, cell, dest, tint=None):
    os.makedirs(CONTACT, exist_ok=True)
    rows = math.ceil(len(paths) / cols)
    cw, chh = cell
    lab = 22
    W, H = cols * cw, rows * (chh + lab) + 34
    sh = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(sh)
    ink = (30, 22, 26) if sum(bg) > 380 else (235, 225, 240)
    d.text((8, 8), title, fill=ink, font=font(18))
    for i, p in enumerate(paths):
        im = Image.open(p).convert("RGBA")
        if tint:
            a = im.getchannel("A"); im = Image.new("RGBA", im.size, tint + (0,)); im.putalpha(a)
        im.thumbnail((cw - 12, chh - 8), Image.LANCZOS)
        x, y = (i % cols) * cw, 34 + (i // cols) * (chh + lab)
        sh.alpha_composite(im, (x + (cw - im.width) // 2, y + (chh - im.height) // 2))
        d.text((x + 6, y + chh + 2), os.path.splitext(os.path.basename(p))[0], fill=ink, font=font(14))
    sh.convert("RGB").save(dest, optimize=True)


def ls(*parts, ext=".png"):
    d = os.path.join(TEX, *parts)
    return [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(ext)] if os.path.isdir(d) else []


def pages(title, paths, cols, cell, per, stem, tint_metal=None, tint_stone=None):
    for k in range(0, len(paths), per):
        chunk = paths[k:k + per]
        n = k // per + 1
        sheet("%s  (%d)  on warm stone" % (title, n), chunk, STONE, cols, cell, os.path.join(CONTACT, "%s_%d_stone.png" % (stem, n)), tint_stone)
        sheet("%s  (%d)  on dark metal" % (title, n), chunk, METAL, cols, cell, os.path.join(CONTACT, "%s_%d_metal.png" % (stem, n)), tint_metal)


def contacts():
    pages("graffiti", ls("graffiti"), 4, (384, 384), 12, "graffiti")
    pages("decals", ls("decals"), 4, (384, 300), 12, "decals")
    pages("rune strips + ring (white, shown tinted)", ls("decals", "runes"), 2, (768, 300), 8, "runes",
          tint_metal=(120, 240, 255), tint_stone=(70, 40, 90))
    pages("tape stickers + labels", ls("tape", "stickers") + ls("tape", "label_") + [p for p in ls("tape") if "label_" in p],
          3, (512, 300), 15, "tape")
    jc = [p for p in ls("tape") if "jcard_" in p]
    if jc:
        sheet("J-cards A-D", jc, (30, 24, 34), 4, (384, 560), os.path.join(CONTACT, "jcards.png"))
    bd = ls("backdrops")
    if bd:
        sheet("backdrops", bd, (20, 16, 24), 2, (768, 512), os.path.join(CONTACT, "backdrops.png"))
        # the real test: a kit diorama floating in front of each plate
        for theme, dio in (("upper", "diorama__upper.png"), ("mid", "diorama__upper.png"), ("lower", "diorama__lower.png"), ("core", "diorama__lower.png")):
            bp = os.path.join(TEX, "backdrops", "%s.png" % theme)
            dp = os.path.join(ROOT, "art", "previews", "kit", dio)
            if not (os.path.exists(bp) and os.path.exists(dp)):
                continue
            b = Image.open(bp).convert("RGBA")
            dm = Image.open(dp).convert("RGB")
            a = np.array(dm).astype(np.int32)
            key = a[4, 4]
            dist = np.abs(a - key).sum(2)
            al = Image.fromarray(np.where(dist > 14, 255, 0).astype(np.uint8)).filter(ImageFilter.MedianFilter(3))
            dm = dm.convert("RGBA"); dm.putalpha(al)
            dm.thumbnail((1150, 860), Image.LANCZOS)
            b.alpha_composite(dm, ((b.width - dm.width) // 2, (b.height - dm.height) // 2 + 20))
            b.convert("RGB").save(os.path.join(CONTACT, "backdrop_test_%s.png" % theme), optimize=True)


if __name__ == "__main__":
    graffiti(); decals(); backdrops(); tape(); contacts()
    bad = [r for r in report if not r["ok"] or r.get("raw_touched_edge")]
    with open(os.path.join(HERE, "alpha_report.json"), "w") as f:
        json.dump(report, f, indent=1)
    print("exported", len(report), "textures;", len(bad), "flagged")
    for r in bad:
        print("  FLAG", r)
