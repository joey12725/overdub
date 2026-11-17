"""Compose review frames rendered by build.py into contact sheets.

  python -I art/anim/sheets.py <framedir> <outdir> [clip filter]

Per clip: <outdir>/<clip>.png = one row per view (labelled with the clip fraction), plus a last row
of the game-camera frames at IN-GAME SIZE (about 80 px tall), which is how the clip is really seen."""
import os, sys
from PIL import Image, ImageDraw

MELEE_T = [0.0, 0.10, 0.20, 0.30, 0.36, 0.40, 0.44, 0.50, 0.60, 0.75, 0.90, 1.0]


def sheet(clipdir, out, name):
    files = sorted(os.listdir(clipdir))
    views = sorted({f.split("_")[0] for f in files})
    rows = []
    for v in views:
        fr = [Image.open(os.path.join(clipdir, f)).convert("RGB") for f in files if f.startswith(v + "_")]
        rows.append((v, fr))
    n = len(rows[0][1])
    w, h = rows[0][1][0].size
    small_h = 84
    small_w = int(w * small_h / h)
    W = n * w
    H = len(rows) * h + small_h + 18
    im = Image.new("RGB", (W, H), (30, 28, 34))
    d = ImageDraw.Draw(im)
    for r, (v, fr) in enumerate(rows):
        for i, f in enumerate(fr):
            im.paste(f, (i * w, r * h))
            if n == len(MELEE_T) and ("light" in name or "heavy" in name):
                t = MELEE_T[i]
                col = (255, 80, 60) if 0.399 <= t <= 0.601 else (240, 240, 240)
                d.text((i * w + 4, r * h + 3), "%.2f" % t, fill=col)
            else:
                d.text((i * w + 4, r * h + 3), "%d/%d" % (i, n - 1), fill=(240, 240, 240))
    iso = [fr for v, fr in rows if v == "iso"]
    if iso:
        for i, f in enumerate(iso[0]):
            im.paste(f.resize((small_w, small_h), Image.LANCZOS), (i * (small_w + 6) + 4, len(rows) * h + 14))
    d.text((4, len(rows) * h + 1), name + "  (bottom row: in-game size)", fill=(255, 210, 63))
    im.save(out)


def overview(src, dst, names, view, tag, cell=150):
    """Several clips on one page, one row each (for quick review)."""
    rows = []
    for name in names:
        d = os.path.join(src, name)
        fr = [Image.open(os.path.join(d, f)).convert("RGB").resize((cell, cell), Image.LANCZOS)
              for f in sorted(os.listdir(d)) if f.startswith(view + "_")]
        rows.append((name, fr))
    W = max(len(fr) for _, fr in rows) * cell
    im = Image.new("RGB", (W, len(rows) * cell), (30, 28, 34))
    dr = ImageDraw.Draw(im)
    for r, (name, fr) in enumerate(rows):
        for i, f in enumerate(fr):
            im.paste(f, (i * cell, r * cell))
            if len(fr) == len(MELEE_T) and ("light" in name or "heavy" in name) and 0.399 <= MELEE_T[i] <= 0.601:
                dr.rectangle((i * cell, r * cell, (i + 1) * cell - 1, r * cell + 3), fill=(255, 80, 60))
        dr.text((4, r * cell + 5), name, fill=(255, 210, 63))
    im.save(os.path.join(dst, "overview_%s_%s.png" % (view, tag)))


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    flt = sys.argv[3] if len(sys.argv) > 3 else ""
    os.makedirs(dst, exist_ok=True)
    for name in sorted(os.listdir(src)):
        if flt and flt not in name:
            continue
        sheet(os.path.join(src, name), os.path.join(dst, name + ".png"), name)
        print("sheet", name)
    names = [n for n in sorted(os.listdir(src)) if not flt or flt in n]
    for view in ("iso", "side"):
        for k in range(0, len(names), 4):
            overview(src, dst, names[k:k + 4], view, "%02d" % (k // 4))
