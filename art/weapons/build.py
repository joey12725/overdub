"""
Builds every weapon and projectile glb from scratch and renders stand-alone previews.

  blender --background --threads 6 --python art/weapons/build.py -- [--only id,id] [--no-render] [--no-export]

Outputs
  assets/models/weapons/<item id>.glb         six melee + five wrist-mounted ranged weapons
  assets/models/projectiles/<archetype>.glb   missile, pierce, phase, arc, burst, bolt, shock
  art/weapons/metrics/<id>.json               triangles, bounds, empties (read by sheets.py and the docs)
  art/previews/weapons/<id>/{side,top,threeq,thumb}.png

In-hand and line-up renders are a second pass (hand.py) that loads the exported glbs.
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import wlib as L  # noqa: E402
import wrender as R  # noqa: E402
import melee  # noqa: E402
import ranged  # noqa: E402
import projectiles  # noqa: E402

WEAPON_DIR = os.path.join(L.ROOT, "assets", "models", "weapons")
PROJ_DIR = os.path.join(L.ROOT, "assets", "models", "projectiles")
PREVIEW_DIR = os.path.join(L.ROOT, "art", "previews", "weapons")
METRIC_DIR = os.path.join(HERE, "metrics")

REG = {}
for k, v in melee.MELEE.items():
    REG[k] = ("melee", v[0], v[1], WEAPON_DIR)
for k, v in ranged.RANGED.items():
    REG[k] = ("ranged", v[0], v[1], WEAPON_DIR)
for k, v in projectiles.PROJECTILES.items():
    REG[k] = ("projectile", v[0], v[1], PROJ_DIR)


def r3(v):
    return [round(float(x), 4) for x in v]


def build(item, do_export=True, do_render=True):
    kind, fn, main, out_dir = REG[item]
    L.reset(main=main)
    spec = fn()
    bpy.context.view_layer.update()
    objs = spec["objs"]
    empties = spec.get("empties", [])
    meshes = [o for o in objs if o.type == "MESH"]
    lo, hi = L.bounds(meshes)
    info = {
        "id": item, "kind": kind, "style": spec.get("style", ""), "hands": spec.get("hands", 0),
        "tris": {o.name: L.tris(o) for o in meshes}, "tris_total": sum(L.tris(o) for o in meshes),
        "bounds_min": r3(lo), "bounds_max": r3(hi), "size": r3(hi - lo),
        "empties": {e.name: {"pos": r3(e.matrix_world.translation), "z_axis": r3(e.matrix_world.to_3x3().col[2])} for e in empties},
        "materials": sorted({m.name for o in meshes for m in o.data.materials}),
        "bones": [b.name for o in objs if o.type == "ARMATURE" for b in o.data.bones],
    }
    os.makedirs(METRIC_DIR, exist_ok=True)
    with open(os.path.join(METRIC_DIR, item + ".json"), "w") as f:
        json.dump(info, f, indent=1)
    print("BUILT %-18s tris=%5d size=%s" % (item, info["tris_total"], info["size"]))
    if do_export:
        L.export_glb(os.path.join(out_dir, item + ".glb"), objs + empties)
    if do_render:
        R.setup_scene()
        span = max((hi - lo).length, 0.08)
        R.toonify(outline=max(0.0022, min(0.006, span * 0.006)))
        c = (lo + hi) / 2
        d = os.path.join(PREVIEW_DIR, item)
        if kind == "melee":
            views = {"side": ((1, 0, 0), (0, 0, 1), (1400, 620)), "top": ((0, 0, 1), (-1, 0, 0), (1400, 420)),
                     "threeq": ((0.75, 0.25, 0.62), (0.45, 1, 0), (900, 900))}
        else:
            views = {"side": ((-1, 0, 0), (0, 1, 0), (1200, 700)), "top": ((0, 1, 0), (1, 0, 0), (1200, 700)),
                     "threeq": ((-0.62, 0.5, 0.6), (0, 1, 0), (900, 900))}
        for name, (dr, up, res) in views.items():
            ext = hi - lo
            if name == "threeq":
                sp = span * 1.05
            else:
                # fit the projected box to the frame
                import mathutils
                m = R.look_matrix(Vector(dr), (0, 0, 0), up).to_3x3()
                xs = [abs(sum(m[i][0] * s * ext[i] for i in range(3))) for s in (1,)]
                w = sum(abs(m[i][0]) * ext[i] for i in range(3))
                h = sum(abs(m[i][1]) * ext[i] for i in range(3))
                sp = max(w, h * res[0] / res[1]) * 1.12
            R.camera(c, sp, up=up, direction=dr)
            R.render(os.path.join(d, name + ".png"), res)
        R.camera(c, span * 1.02, up=(0.45, 1, 0) if kind == "melee" else (0, 1, 0),
                 direction=(0.75, 0.25, 0.62) if kind == "melee" else (-0.62, 0.5, 0.6))
        R.render(os.path.join(d, "thumb_384.png"), (384, 384))
    return info


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1].split(",")
    for item in REG:
        if only and item not in only:
            continue
        build(item, "--no-export" not in argv, "--no-render" not in argv)


main()
