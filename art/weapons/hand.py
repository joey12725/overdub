"""
Second preview pass: loads the EXPORTED glbs (what the game gets) and shows them on Moxie.

  blender --background --threads 6 --python art/weapons/hand.py -- --mode hand|lineup|before [--only id,id] [--moxie path.glb]

  hand    art/previews/weapons/<id>/hand.png (game camera: orthographic, yaw 45, pitch 35), hand_close.png
  lineup  art/previews/weapons/lineup.png, lineup_ranged.png
  before  art/previews/weapons/<id>/before_threeq.png + before_hand.png from art/previews/weapons/_before/glb
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import wlib as L  # noqa: E402
import wrender as R  # noqa: E402

WEAPON_DIR = os.path.join(L.ROOT, "assets", "models", "weapons")
PROJ_DIR = os.path.join(L.ROOT, "assets", "models", "projectiles")
PREVIEW_DIR = os.path.join(L.ROOT, "art", "previews", "weapons")
BEFORE_DIR = os.path.join(PREVIEW_DIR, "_before", "glb")
MELEE = ["splice_blade", "stylus_shiv", "amp_sledge", "reel_lash", "speaker_knuckles", "vinyl_glaive"]
RANGED = ["mixtape_rocket", "needle_rail", "bleed_emitter", "bass_drop", "static_spray"]
PROJ = {"mixtape_rocket": "missile", "needle_rail": "pierce", "bleed_emitter": "phase", "bass_drop": "arc", "static_spray": "burst"}

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


MOXIE = arg("--moxie", os.path.join(L.ROOT, "assets", "models", "moxie.glb"))
POSE = (arg("--action"), float(arg("--frac", "0.0")))
SUFFIX = arg("--suffix", "")


def place(root, m):
    root.matrix_world = m @ R.C_B2G
    bpy.context.view_layer.update()


def gauntlet_matrix(h, side):
    """Gauntlet frame on a hand: +Y along the hand bone, +Z = back of the hand (model up at rest)."""
    name = h.bone(R.HAND_R if side == "R" else R.HAND_L)
    head, tail = h.rest_godot(name)
    y = (tail - head).normalized()
    z = Vector((0, 1, 0))
    x = y.cross(z).normalized()
    z = x.cross(y).normalized()
    pos = head + y * 0.075
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2], m[i][3] = x[i], y[i], z[i], pos[i]
    return h.delta(name) @ R.C_G2B @ m


def attach(h, item, glb_dir=WEAPON_DIR):
    root, objs = R.import_glb(os.path.join(glb_dir, item + ".glb"))
    if item in RANGED:
        place(root, h.wrist_matrix())
    elif item == "speaker_knuckles" and any(o.name.startswith("Gauntlet_L") for o in objs):
        place(root, gauntlet_matrix(h, "R"))
        for o in objs:
            if o.name.startswith("Gauntlet_L"):
                # re-seat the left gauntlet on the left hand
                o.parent = None
                o.matrix_world = gauntlet_matrix(h, "L") @ R.C_B2G
        bpy.context.view_layer.update()
    else:
        place(root, h.hand_matrix("R"))
    return root, objs


def hand(item, glb_dir=WEAPON_DIR, out="hand", close=True):
    L.reset()
    h = Holder(item)
    root, objs = attach(h, item, glb_dir)
    R.setup_scene()
    R.toonify(outline=0.005)
    meshes = [o for o in objs if o.type == "MESH"]
    wl, wh = L.bounds(meshes)
    lo = Vector((min(wl.x, -0.5), min(wl.y, 0.0), min(wl.z, -0.4)))
    hi = Vector((max(wh.x, 0.5), max(wh.y, 1.7), max(wh.z, 0.4)))
    c = (lo + hi) / 2
    span = max(2.2, (hi - lo).length * 0.82)
    R.camera(c, span, yaw=45, pitch=35)
    d = os.path.join(PREVIEW_DIR, item)
    R.render(os.path.join(d, out + SUFFIX + ".png"), (1000, 1000))
    if close:
        wl, wh = L.bounds(meshes)
        wc = (wl + wh) / 2
        R.camera(wc, max(0.75, min((wh - wl).length * 1.15, 1.6)), yaw=45, pitch=35)
        R.render(os.path.join(d, out + SUFFIX + "_close.png"), (800, 800))


def Holder(item=None):
    if POSE[0]:
        return R.Holder(MOXIE, POSE[0], POSE[1])
    if item in RANGED:
        return R.Holder(MOXIE, "ranged", 0.4)
    return R.Holder(MOXIE, "stopped", 0.0)


def before(item):
    """The earlier pass, same cameras as build.py's threeq and the hand shot."""
    L.reset()
    root, objs = R.import_glb(os.path.join(BEFORE_DIR, item + ".glb"))
    meshes = [o for o in objs if o.type == "MESH"]
    R.setup_scene()
    lo, hi = L.bounds(meshes)
    span = (hi - lo).length
    R.toonify(outline=max(0.0022, min(0.006, span * 0.006)))
    R.camera((lo + hi) / 2, span * 1.05, up=(0.45, 1, 0), direction=(0.75, 0.25, 0.62))
    R.render(os.path.join(PREVIEW_DIR, item, "before_threeq.png"), (900, 900))
    hand(item, BEFORE_DIR, "before_hand", close=False)


def lineup():
    L.reset()
    h = Holder()
    x = 0.75
    objs_all = []
    for item in MELEE:
        root, objs = R.import_glb(os.path.join(WEAPON_DIR, item + ".glb"))
        meshes = [o for o in objs if o.type == "MESH"]
        root.matrix_world = R.C_B2G
        bpy.context.view_layer.update()
        lo, hi = L.bounds(meshes)
        # stand it on the floor, edge toward the camera's right
        turn = Matrix.Rotation(math.radians(90), 4, "Y")
        root.matrix_world = Matrix.Translation((x + (hi.z - lo.z) * 0.5, -lo.y, 0)) @ turn @ Matrix.Translation((0, 0, -(lo.z + hi.z) / 2)) @ R.C_B2G
        bpy.context.view_layer.update()
        x += (hi.z - lo.z) + 0.28
        objs_all += meshes
    R.setup_scene()
    R.toonify(outline=0.005)
    lo, hi = L.bounds(objs_all + h.meshes())
    c = (lo + hi) / 2
    w = hi.x - lo.x
    R.camera(c, w * 1.08, direction=(0.0, 0.18, 1.0))
    R.render(os.path.join(PREVIEW_DIR, "lineup.png"), (2000, int(2000 * (hi.y - lo.y + 0.3) / (w * 1.08))))

    L.reset()
    h = Holder()
    x = 0.7
    objs_all = []
    for item in RANGED:
        root, objs = R.import_glb(os.path.join(WEAPON_DIR, item + ".glb"))
        turn = Matrix.Rotation(math.radians(90), 4, "Y")       # muzzle toward +X (camera right)
        root.matrix_world = Matrix.Translation((x, 1.05, 0)) @ turn @ R.C_B2G
        objs_all += [o for o in objs if o.type == "MESH"]
        proot, pobjs = R.import_glb(os.path.join(PROJ_DIR, PROJ[item] + ".glb"))
        proot.matrix_world = Matrix.Translation((x + 0.12, 0.45, 0)) @ turn @ R.C_B2G
        objs_all += [o for o in pobjs if o.type == "MESH"]
        x += 0.62
    for k, pn in enumerate(("bolt", "shock")):
        proot, pobjs = R.import_glb(os.path.join(PROJ_DIR, pn + ".glb"))
        proot.matrix_world = Matrix.Translation((x + 0.1, 1.05 - k * 0.6, 0)) @ Matrix.Rotation(math.radians(90), 4, "Y") @ R.C_B2G
        objs_all += [o for o in pobjs if o.type == "MESH"]
    bpy.context.view_layer.update()
    R.setup_scene()
    R.toonify(outline=0.004)
    lo, hi = L.bounds(objs_all + h.meshes())
    c = (lo + hi) / 2
    w = hi.x - lo.x
    R.camera(c, w * 1.08, direction=(0.0, 0.3, 1.0))
    R.render(os.path.join(PREVIEW_DIR, "lineup_ranged.png"), (2000, int(2000 * (hi.y - lo.y + 0.35) / (w * 1.08))))


mode = arg("--mode", "hand")
only = arg("--only")
only = only.split(",") if only else None
if mode == "hand":
    for it in MELEE + RANGED:
        if not only or it in only:
            hand(it)
elif mode == "before":
    for it in MELEE:
        if not only or it in only:
            before(it)
elif mode == "lineup":
    lineup()
