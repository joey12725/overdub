"""Numerical head check (plain Python + PIL/numpy), run after the `hc` shots have been rendered:

    bash art/moxie_c/run.sh --parts head --shots hc --toon
    python -I art/moxie_c/ref_compare.py [tag]

Traces the model renders exactly like the sheet (ref_measure.py), prints sheet vs model for the
silhouette at a ladder of heights and for the facial landmarks, and writes 50 % overlays to
art/previews/moxie_c/_wip_overlay_front.png / _side.png (sheet scaled so the head heights agree,
crowns and centre lines aligned).
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PREV = os.path.abspath(os.path.join(HERE, "..", "previews", "moxie_c"))
sys.path.insert(0, HERE)
import mc_facedef as fd  # noqa: E402
import mc_headshape as hs  # noqa: E402

PPM = 3000.0                         # render pixels per metre
CEN = (0.0, -0.015, 1.493)           # render target (world)
HEAD_C = (0.0, -0.004, 1.500)
RES = 900
SUF = "_toon"


def fgmask(path):
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    bg = im[4:30, 4:30].reshape(-1, 3).mean(axis=0)
    return np.abs(im - bg).sum(axis=2) > 40


def ext(mask, y):
    xs = np.nonzero(mask[y])[0]
    return (float(xs.min()), float(xs.max())) if len(xs) else (np.nan, np.nan)


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "wip"
    raw = json.load(open(os.path.join(HERE, "ref", "head_profile_raw.json")))
    rw, rf, rb = (np.array(raw[k]) for k in ("front_raw", "side_front_raw", "side_back_raw"))
    Hpx = hs.H * PPM
    crown_y = RES / 2 - (HEAD_C[2] + hs.ZTOP - CEN[2]) * PPM
    cx = RES / 2
    nose_x = RES / 2 + ((HEAD_C[1] + hs.Y0) - CEN[1]) * PPM      # side view: +y (back) is to the right
    mf = fgmask(os.path.join(PREV, "_%s_hc0%s.png" % (tag, SUF)))
    ms = fgmask(os.path.join(PREV, "_%s_hc1%s.png" % (tag, SUF)))
    crown_seen = int(np.nonzero(mf.any(axis=1))[0].min())
    print("crown row: expected %.1f, traced %d" % (crown_y, crown_seen))
    print("   t    | half-width sheet model  d%%H | front  sheet model  d%%H | back  sheet model  d%%H")
    errs = []
    for t in np.arange(0.05, 0.96, 0.05):
        y = int(round(crown_y + t * Hpx))
        a, b = ext(mf, y)
        w = 0.5 * (b - a) / Hpx
        c, d = ext(ms, y)
        f, bk = (c - nose_x) / Hpx, (d - nose_x) / Hpx
        i = int(round(t * (len(rw) - 1)))
        errs.append((w - rw[i], f - rf[i], bk - rb[i]))
        print("  %.2f  |   %.3f  %.3f  %+5.1f      |  %.3f  %.3f  %+5.1f    |  %.3f  %.3f  %+5.1f"
              % (t, rw[i], w, 100 * (w - rw[i]), rf[i], f, 100 * (f - rf[i]), rb[i], bk, 100 * (bk - rb[i])))
    e = np.abs(np.array(errs))
    print("max |error| in %% of head height: width %.1f  front %.1f  back %.1f   (rows under t=0.80 in the"
          " back column are neck in the sheet)" % tuple(100 * e.max(axis=0)))
    wmax_s, wmax_m = rw[: int(0.5 * len(rw))].max(), np.nanmax([0.5 * (ext(mf, y)[1] - ext(mf, y)[0]) / Hpx
                                                               for y in range(int(crown_y) + 5, int(crown_y + 0.5 * Hpx))])
    print("landmarks (head heights)            sheet   model")
    print("  cranium width / head height       %.3f   %.3f" % (2 * wmax_s, 2 * wmax_m))
    print("  eye line below crown              0.597   %.3f" % ((hs.ZTOP - fd.EYE_C[1]) / hs.H))
    print("  eye centre from centre line       0.172   %.3f" % (fd.EYE_C[0] / hs.H))
    xs = [p[0] for p in fd.EYE_PTS_MM]
    zs = [p[1] for p in fd.EYE_PTS_MM]
    print("  eye opening width                 0.171   %.3f" % ((max(xs) - min(xs)) * 0.001 * fd.EYE_K / hs.H))
    print("  eye opening height                0.098   %.3f" % ((max(zs) - min(zs)) * 0.001 * fd.EYE_K / hs.H))
    print("  mouth line below crown            0.846   %.3f" % ((hs.ZTOP - fd.MOUTH_C[1]) / hs.H))
    ym = int(round(crown_y + 0.846 * Hpx))
    a, b = ext(mf, ym)
    print("  jaw width at the mouth line       %.3f   %.3f" % (2 * rw[int(round(0.846 * (len(rw) - 1)))], (b - a) / Hpx))
    print("  nose tip below crown              0.735   %.3f" % ((hs.ZTOP - fd.NOSE_TIP_Z) / hs.H))
    # ---- overlays
    src = Image.open(os.path.join(HERE, "ref", "head_bald_front_side.png")).convert("RGB")
    px = raw["px"]
    k = Hpx / px["H"]
    half = src.width // 2
    for name, shot, box_x0, ax_src, ax_dst in (("front", "hc0", 0, px["cx"], cx),
                                               ("side", "hc1", half, px["side_x0"] - half, nose_x)):
        part = src.crop((box_x0, 0, box_x0 + half, src.height))
        part = part.resize((round(part.width * k), round(part.height * k)), Image.LANCZOS)
        ren = Image.open(os.path.join(PREV, "_%s_%s%s.png" % (tag, shot, SUF))).convert("RGB")
        canvas = Image.new("RGB", ren.size, (128, 128, 128))
        crown_src = px["crown"] if name == "front" else px["side_crown"]
        canvas.paste(part, (round(ax_dst - ax_src * k), round(crown_y - crown_src * k)))
        Image.blend(ren, canvas, 0.5).save(os.path.join(PREV, "_%s_overlay_%s.png" % (tag, name)))
    print("overlays written")


main()
