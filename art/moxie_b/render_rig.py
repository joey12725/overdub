"""Review renders of the rigged model: tpose.png and deform_tests.png (toon + outline).
Usage: blender -b --python render_rig.py -- [stage name, default s07_rig]"""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
import mb_toon as T
import mb_pose as P
from mathutils import Vector, Matrix

a = U.args()
U.open_stage(a[0] if a else "s07_rig")
rig = bpy.data.objects["Rig"]
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in bpy.data.objects:
    if o.type == 'ARMATURE':
        o.hide_render = True
T.toonify(meshes, outline=0.0028)
pb = rig.pose.bones

U.render_views(os.path.join(U.PREV, "tpose.png"), views=("front", "side", "back", (45, 35)), center=(0, 0, 0.86), scale=1.95,
               res=(900, 1000), setup=T.setup_eevee)


def relaxed_arms(down=1.0):
    for side, sx in P.SIDES:
        P.aim(pb[side + "UpperArm"], (sx * 0.38, 0.05, -1 * down))
        P.aim(pb[side + "LowerArm"], (sx * 0.22, -0.25, -1 * down))


def keep_feet(foot_m):
    for side, sx in P.SIDES:
        m = foot_m[side].copy()
        P._update()
        m.translation = pb[side + "Foot"].head
        pb[side + "Foot"].matrix = m
        P._update()


def pose_crouch():
    fm = {s: pb[s + "Foot"].matrix.copy() for s in ("Left", "Right")}
    h = pb["Hips"]
    m = h.matrix.copy()
    m.translation = m.translation + Vector((0, 0.06, -0.30))
    h.matrix = m
    P.turn(pb["Spine"], (1, 0, 0), -28)
    for side, sx in P.SIDES:
        P.aim(pb[side + "UpperLeg"], (sx * 0.42, -0.80, -0.22))
        P.aim(pb[side + "LowerLeg"], (sx * 0.02, 0.50, -1))
        P.aim(pb[side + "UpperArm"], (sx * 0.3, -0.8, -0.5))
        P.aim(pb[side + "LowerArm"], (-sx * 0.3, -0.6, 0.1))
    keep_feet(fm)


def pose_overhead():
    for side, sx in P.SIDES:
        P.aim(pb[side + "Shoulder"], (sx, 0, 0.6))
        P.aim(pb[side + "UpperArm"], (sx * 0.35, 0, 1))
        P.aim(pb[side + "LowerArm"], (sx * 0.05, -0.1, 1))


def pose_forward():
    for side, sx in P.SIDES:
        P.aim(pb[side + "UpperArm"], (sx * 0.12, -1, 0))
        P.aim(pb[side + "LowerArm"], (0, -1, 0.05))


def pose_stride():
    fm = {s: pb[s + "Foot"].matrix.copy() for s in ("Left", "Right")}
    P.aim(pb["LeftUpperLeg"], (0.08, -0.70, -0.75))
    P.aim(pb["LeftLowerLeg"], (0.05, -0.10, -1))
    P.aim(pb["RightUpperLeg"], (-0.08, 0.45, -0.9))
    P.aim(pb["RightLowerLeg"], (-0.05, 0.85, -0.55))
    P.aim(pb["LeftUpperArm"], (0.25, 0.6, -0.8))
    P.aim(pb["LeftLowerArm"], (0.15, 0.2, -1))
    P.aim(pb["RightUpperArm"], (-0.25, -0.6, -0.75))
    P.aim(pb["RightLowerArm"], (-0.05, -1, 0.2))
    m = fm["Left"].copy()
    P._update()
    m.translation = pb["LeftFoot"].head
    pb["LeftFoot"].matrix = m
    P._update()


def pose_twist():
    relaxed_arms()
    for b in ("Spine", "Chest", "UpperChest"):
        P.turn(pb[b], (0, 0, 1), 20)


def pose_head():
    relaxed_arms()
    P.turn(pb["Neck"], (0, 0, 1), 20)
    P.turn(pb["Head"], (0, 0, 1), 40)
    P.turn(pb["Head"], (1, 0, 0), 12)


def pose_fist():
    for side, sx in P.SIDES:
        P.aim(pb[side + "UpperArm"], (sx * 0.5, -0.3, -0.8))
        P.aim(pb[side + "LowerArm"], (-sx * 0.2, -0.8, 0.6))
        P.curl_fingers(rig, side, 1.0)


POSES = [("crouch", pose_crouch, (35, 8), (0, 0, 0.72)), ("overhead", pose_overhead, (25, 5), (0, 0, 0.95)),
         ("forward", pose_forward, (50, 10), (0, -0.1, 0.86)), ("stride", pose_stride, (60, 8), (0, 0, 0.86)),
         ("twist", pose_twist, (20, 8), (0, 0, 0.86)), ("head", pose_head, (20, 8), (0, 0, 0.86)), ("fist", pose_fist, (30, 8), (0, 0, 0.86))]
only = a[1:] if len(a) > 1 else None
tiles = []
for name, fn, view, center in POSES:
    if only and name not in only:
        continue
    P.reset(rig)
    fn()
    P._update()
    for k, (v, c, sc) in enumerate(((view, center, 2.0), ((view[0] + 150, view[1]), center, 2.0))):
        path = os.path.join(U.WIP, "deform_%s_%d.png" % (name, k))
        U.render_views(path, views=(v,), center=c, scale=sc, res=(520, 760), setup=T.setup_eevee)
        tiles.append(path)
    if name == "fist":
        path = os.path.join(U.WIP, "deform_fist_close.png")
        P._update()
        hc = rig.pose.bones["LeftHand"].tail
        U.render_views(path, views=((40, 10),), center=tuple(hc), scale=0.36, res=(520, 760), setup=T.setup_eevee)
        tiles.append(path)
out = os.path.join(U.PREV, "deform_tests.png") if not only else os.path.join(U.WIP, "deform_part.png")
U.stitch(tiles, out, cols=8 if not only else None)
