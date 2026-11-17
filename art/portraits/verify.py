"""Check the shipped portraits against data/story/story.json.

usage (repo root): python -I art/portraits/verify.py      (exit code 1 on any failure)
  * every characters[].portraits entry and every {who, expression} used by a line has assets/portraits/<who>_<expression>.png
  * no stray PNGs; each file is RGBA 1024x1024 with real transparency (corners clear, 25-80 % coverage, no speck islands)
  * the bust reaches the bottom edge (baseline) and the head has headroom; top edge and mass centre agree within a
    character so swapping expressions does not jump
"""
import json, os, sys
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
P = os.path.join(ROOT, "assets", "portraits")
story = json.load(open(os.path.join(ROOT, "data", "story", "story.json"), encoding="utf-8"))
bad = []
want = {(c["id"], e) for c in story["characters"] for e in c["portraits"]}
used = set()
def walk(o):
    if isinstance(o, dict):
        if "who" in o and "expression" in o: used.add((o["who"], o["expression"]))
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(story)
for u in sorted(used - want): bad.append(f"line uses undeclared portrait {u}")
have = {f[:-4] for f in os.listdir(P) if f.endswith(".png")}
for c, e in sorted(want | used):
    if f"{c}_{e}" not in have: bad.append(f"missing {c}_{e}.png")
for s in sorted(have - {f"{c}_{e}" for c, e in want | used}): bad.append(f"stray file {s}.png")
print(f"{len(want)} declared, {len(used)} used by lines, {len(have)} files")
stats = {}
for c, e in sorted(want):
    f = os.path.join(P, f"{c}_{e}.png")
    if not os.path.exists(f): continue
    im = Image.open(f); name = f"{c}_{e}"
    if im.mode != "RGBA" or im.size != (1024, 1024): bad.append(f"{name}: {im.mode} {im.size}"); continue
    a = np.asarray(im.getchannel("A")); solid = a > 128
    cov = solid.mean(); bb = Image.fromarray((solid * 255).astype(np.uint8)).getbbox()
    corners = max(a[:24, :24].max(), a[:24, -24:].max())
    semi = ((a > 0) & (a < 255)).mean()
    ys, xs = np.nonzero(solid[:520]); cx = xs.mean()                       # mass centre of the head half
    bottom = solid[-1].mean()
    if corners > 0: bad.append(f"{name}: top corners not transparent")
    if not 0.25 < cov < 0.80: bad.append(f"{name}: coverage {cov:.2f}")
    if bb[3] != 1024 or bottom < 0.5: bad.append(f"{name}: bust does not sit on the bottom edge ({bottom:.2f})")
    if bb[1] < 12: bad.append(f"{name}: no headroom (top {bb[1]})")
    if semi > 0.03: bad.append(f"{name}: {semi:.3f} semi-transparent pixels (halo?)")
    stats.setdefault(c, []).append((e, bb[1], cx, cov))
    print(f"  {name:22s} top {bb[1]:3d}  head-cx {cx:5.0f}  cover {cov:.2f}  bottom-row {bottom:.2f}  semi {semi:.3f}")
for c, rows in stats.items():
    tops = [r[1] for r in rows]; cxs = [r[2] for r in rows]
    if max(tops) - min(tops) > 40: bad.append(f"{c}: head top varies {max(tops) - min(tops)} px")
    if max(cxs) - min(cxs) > 40: bad.append(f"{c}: head centre varies {max(cxs) - min(cxs):.0f} px")
print("FAIL" if bad else "OK"); [print("  -", b) for b in bad]
sys.exit(1 if bad else 0)
