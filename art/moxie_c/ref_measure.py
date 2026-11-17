"""Trace the head model sheet numerically (plain Python + PIL/numpy):

    python -I art/moxie_c/ref_measure.py

Reads ref/head_bald_front_side.png (front view left, left profile right, same scale) and writes
ref/head_profile.json: silhouette curves normalised by head height H (crown -> chin) sampled at
t = 0 (crown) .. 1 (chin), plus the facial landmarks used by mc_facedef / mc_head.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "ref", "head_bald_front_side.png")


def load():
    im = np.asarray(Image.open(SRC).convert("RGB")).astype(np.int32)
    bg = im[5:40, 5:40].reshape(-1, 3).mean(axis=0)
    fg = np.abs(im - bg).sum(axis=2) > 45
    return im, fg


def runs(mask_row):
    xs = np.nonzero(mask_row)[0]
    return (xs.min(), xs.max()) if len(xs) else None


def main():
    im, fg = load()
    Hh, Ww = fg.shape
    half = Ww // 2
    dark = im.sum(axis=2) < 150
    out = {}
    # ---------------- front view
    f = fg[:, :half]
    rows = np.nonzero(f.any(axis=1))[0]
    crown = int(rows.min())
    ext = [runs(f[y]) for y in range(Hh)]
    cx = np.mean([0.5 * (ext[y][0] + ext[y][1]) for y in range(crown + 20, crown + 120)])
    # chin: the lowest dark (ink) pixel on the centre line above the choker; choker = wide dark band
    col = dark[:, int(round(cx)) - 2:int(round(cx)) + 3].any(axis=1)
    ys = np.nonzero(col)[0]
    chin = int(ys[ys > crown + 380][0])            # first ink row under the mouth = chin line
    H = chin - crown
    wl = np.array([cx - ext[y][0] for y in range(crown, chin + 1)], dtype=float)
    wr = np.array([ext[y][1] - cx for y in range(crown, chin + 1)], dtype=float)
    w = 0.5 * (wl + wr)
    t = np.arange(len(w)) / H
    out["px"] = {"crown": crown, "chin": chin, "cx": float(cx), "H": int(H)}
    out["front_raw"] = (w / H).round(4).tolist()
    # ---------------- side view (profile faces left)
    s = fg[:, half:]
    rows = np.nonzero(s.any(axis=1))[0]
    s_crown = int(rows.min())
    exts = [runs(s[y]) for y in range(Hh)]
    front = np.array([exts[y][0] for y in range(s_crown, s_crown + H + 1)], dtype=float)
    back = np.array([exts[y][1] for y in range(s_crown, s_crown + H + 1)], dtype=float)
    x_face = front.min()                              # nose tip
    out["px"]["side_crown"] = s_crown
    out["px"]["side_x0"] = float(x_face + half)
    out["side_front_raw"] = ((front - x_face) / H).round(4).tolist()
    out["side_back_raw"] = ((back - x_face) / H).round(4).tolist()
    json.dump(out, open(os.path.join(HERE, "ref", "head_profile_raw.json"), "w"))
    print("front crown", crown, "chin", chin, "cx", round(cx, 1), "H", H, "side crown", s_crown)
    for k in range(0, len(w), max(1, len(w) // 40)):
        print("t=%.3f  w=%.3f  f=%.3f b=%.3f" % (t[k], w[k] / H, (front[k] - x_face) / H, (back[k] - x_face) / H))
    # debug crops
    Image.open(SRC).crop((0, crown - 20, half, chin + 60)).save(os.path.join(HERE, "ref", "_dbg_front.png"))
    Image.open(SRC).crop((half, s_crown - 20, Ww, s_crown + H + 60)).save(os.path.join(HERE, "ref", "_dbg_side.png"))


main()
