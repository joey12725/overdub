"""Builds Moxie (candidate C) from scratch.

    blender --background --python art/moxie_c/build.py -- [--parts head,hair,...] [--shots face,turn,...] [--toon]

With no --parts everything is built, rigged, saved to art/moxie_c/moxie.blend and exported.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "candidates", "c")
PREV = os.path.join(ROOT, "art", "previews", "moxie_c")

import bpy  # noqa: E402
import mc_util as U  # noqa: E402
import mc_palette  # noqa: E402


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    d = {"parts": None, "shots": [], "toon": False, "tag": "wip"}
    i = 0
    while i < len(a):
        if a[i] == "--parts":
            d["parts"] = a[i + 1].split(",")
            i += 1
        elif a[i] == "--shots":
            d["shots"] = a[i + 1].split(",")
            i += 1
        elif a[i] == "--toon":
            d["toon"] = True
        elif a[i] == "--tag":
            d["tag"] = a[i + 1]
            i += 1
        i += 1
    return d


def main():
    A = args()
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mc_palette.install(os.path.join(HERE, "tex"))
    parts = A["parts"]
    full = parts is None

    def want(p):
        return full or p in parts

    import mc_assemble
    mc_assemble.build(want, full, OUT, HERE)
    print("BUILD %.1fs tris=%d" % (time.time() - t0, U.tri_count(bpy.data.objects)))
    if full:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "moxie_model.blend"))
    if A["shots"]:
        import mc_shots
        mc_shots.shoot(A["shots"], PREV, A["tag"], toon=A["toon"])
    print("DONE %.1fs" % (time.time() - t0))


main()
