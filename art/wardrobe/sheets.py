"""
Contact sheets for review (python -I art/wardrobe/sheets.py):
  art/previews/wardrobe/_sheet_a.png, _sheet_b.png   Blender fit renders of the six headgear
                                                     pieces (iso, iso-back, front, side)
  art/previews/wardrobe/_concepts_headgear.png, _concepts_tops.png, _concepts_pants.png,
  _concepts_shoes.png, _concepts_mixes.png           the concept sheets side by side
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import spec  # noqa: E402

PREV = os.path.join(ROOT, "art", "previews", "wardrobe")
CON = os.path.join(ROOT, "docs", "reference", "generated", "wardrobe")


def fit_sheet(ids, name):
    views = ["iso", "isoback", "front", "side"]
    sh = Image.new("RGB", (400 * len(views), 400 * len(ids)), (20, 18, 24))
    for r, i in enumerate(ids):
        for c, v in enumerate(views):
            p = os.path.join(PREV, "%s_%s.png" % (i, v))
            if os.path.exists(p):
                sh.paste(Image.open(p).convert("RGB").resize((400, 400), Image.LANCZOS), (c * 400, r * 400))
    sh.save(os.path.join(PREV, name))


def concept_sheet(ids, cols, cell, name):
    rows = (len(ids) + cols - 1) // cols
    sh = Image.new("RGB", (cols * cell[0], rows * cell[1]), (20, 18, 24))
    for n, i in enumerate(ids):
        p = os.path.join(CON, i + ".png")
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        im.thumbnail(cell, Image.LANCZOS)
        sh.paste(im, ((n % cols) * cell[0] + (cell[0] - im.width) // 2, (n // cols) * cell[1] + (cell[1] - im.height) // 2))
    sh.save(os.path.join(PREV, name))


if __name__ == "__main__":
    hg = list(spec.HEADGEAR)
    fit_sheet(hg[:3], "_sheet_a.png")
    fit_sheet(hg[3:], "_sheet_b.png")
    looks = spec.LOOKS
    concept_sheet(hg, 2, (900, 600), "_concepts_headgear.png")
    concept_sheet([i for i in looks if looks[i]["slot"] == "top"], 4, (480, 480), "_concepts_tops.png")
    concept_sheet([i for i in looks if looks[i]["slot"] == "pants"], 3, (480, 480), "_concepts_pants.png")
    concept_sheet([i for i in looks if looks[i]["slot"] == "shoes"], 3, (480, 480), "_concepts_shoes.png")
    concept_sheet(list(spec.MIXES), 6, (330, 430), "_concepts_mixes.png")
    print("sheets written")
