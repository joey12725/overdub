"""Render shots from a saved .blend:
    blender --background <file.blend> --python art/moxie_c/render.py -- --shots turn,face [--pose relaxed] [--toon] [--tag x]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PREV = os.path.join(ROOT, "art", "previews", "moxie_c")

import mc_shots  # noqa: E402

a = sys.argv[sys.argv.index("--") + 1:]
opt = {"shots": [], "pose": None, "toon": False, "tag": "wip"}
i = 0
while i < len(a):
    if a[i] == "--shots":
        opt["shots"] = a[i + 1].split(",")
        i += 1
    elif a[i] == "--pose":
        opt["pose"] = a[i + 1]
        i += 1
    elif a[i] == "--tag":
        opt["tag"] = a[i + 1]
        i += 1
    elif a[i] == "--toon":
        opt["toon"] = True
    i += 1
mc_shots.shoot(opt["shots"], PREV, opt["tag"], toon=opt["toon"], pose=opt["pose"])
