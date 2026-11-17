"""Whole-body proportion check against the model sheets (plain Python + PIL/numpy):

    bash art/moxie_c/rs.sh sheet sheet --toon          # renders _wip_sheet0/1_toon.png in the sheet's stance
    python -I art/moxie_c/body_compare.py

Compares silhouette widths at a ladder of heights (front: docs/reference/generated/cut/moxie_front.png,
side: cut/moxie_left.png) with the model rendered at the same scale (835 px per metre, soles on
row 1478), prints the landmark table and writes 50 % overlays to art/previews/moxie_c/.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PREV = os.path.join(ROOT, "art", "previews", "moxie_c")
GEN = os.path.join(ROOT, "docs", "reference", "generated")
sys.path.insert(0, HERE)
import mc_proportion as mp  # noqa: E402

PPM, SOLE = 835.0, 1478


def mask_ref(name):
    im = Image.open(os.path.join(GEN, "cut", name))
    return np.asarray(im.split()[-1]) > 128


def mask_render(path):
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    bg = im[4:30, 4:30].reshape(-1, 3).mean(axis=0)
    return np.abs(im - bg).sum(axis=2) > 40


def width(mask, z):
    y = int(round(SOLE - z * PPM))
    xs = np.nonzero(mask[max(0, y - 2):y + 3].any(axis=0))[0]
    return (xs.max() - xs.min()) / PPM if len(xs) else float("nan")


def main():
    rows = [("pigtails / hair span", 1.50), ("neck", 1.37), ("shoulders + jacket", 1.27), ("waist + sleeves", 1.12),
            ("hips / belt kit", 1.00), ("thighs", 0.80), ("knees", 0.55), ("pants widest", 0.42),
            ("shins above the boots", 0.275), ("boots", 0.10)]
    for view, ref, shot in (("FRONT", "moxie_front.png", "sheet0"), ("SIDE", "moxie_left.png", "sheet1")):
        mr = mask_ref(ref)
        mm = mask_render(os.path.join(PREV, "_wip_%s_toon.png" % shot))
        print("%s silhouette width (m)        sheet   model   ratio" % view)
        for name, z in rows:
            a, b = width(mr, z), width(mm, z)
            print("  %-26s z=%.2f  %.3f   %.3f   %.2f" % (name, z, a, b, b / a))
        top_r = (SOLE - np.nonzero(mr.any(axis=1))[0].min()) / PPM
        top_m = (SOLE - np.nonzero(mm.any(axis=1))[0].min()) / PPM
        print("  top of the hair: sheet %.3f m, model %.3f m" % (top_r, top_m))
        ren = Image.open(os.path.join(PREV, "_wip_%s_toon.png" % shot)).convert("RGB")
        src = Image.open(os.path.join(GEN, ref)).convert("RGB")
        # the sheets are not centred on the canvas: slide the sheet so the necks coincide
        yn = int(round(SOLE - 1.37 * PPM))
        dx = int(round(np.nonzero(mm[yn - 3:yn + 4].any(axis=0))[0].mean() - np.nonzero(mr[yn - 3:yn + 4].any(axis=0))[0].mean()))
        canvas = Image.new("RGB", src.size, src.getpixel((3, 3)))
        canvas.paste(src, (dx, 0))
        Image.blend(ren, canvas, 0.5).save(os.path.join(PREV, "overlay_body_%s.png" % view.lower()))
    print("landmark heights (m)             sheet   model")
    P = mp.warp_point
    for name, ref, pt in (("skull crown", 1.580, (0, 0, 1.600)), ("chin", 1.414, (0, -0.05, 1.386)),
                          ("shoulder line", 1.309, (0.19, 0.01, 1.30)), ("navel", 1.103, (0, -0.07, 0.985)),
                          ("waistband", 1.045, (0.134, 0.016, 0.923)), ("crotch", 0.890, (0, 0.012, 0.770)),
                          ("pants cuff (bottom)", 0.315, (0.11, 0, 0.283)), ("boot top", 0.247, (0.10, 0.02, 0.226))):
        print("  %-22s        %.3f   %.3f" % (name, ref, P(pt)[2]))
    hw = lambda x, z: 2 * P((x, 0.01, z))[0]  # noqa: E731
    print("widths (m)                       sheet   model")
    print("  bare shoulders (tip to tip)    0.293   %.3f" % hw(0.186, 1.30))
    print("  waist                          0.150   %.3f" % hw(0.089, 1.02))
    print("  head height                    0.166   %.3f" % (P((0, 0, 1.600))[2] - P((0, -0.05, 1.386))[2]))
    print("  heads tall (crown to sole)     9.5     %.1f" % (P((0, 0, 1.6))[2] / (P((0, 0, 1.600))[2] - P((0, -0.05, 1.386))[2])))


main()
