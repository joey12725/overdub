"""Rest-pose joint layout for Moxie (Blender coordinates: Z up, she faces -Y, her left is +X).

About 1.6 units tall to the crown with ~6.3 heads, long legs (hip joint at 0.845), slim
athletic build. Arms rest in an A-pose (about 52 degrees below horizontal) which skins the
shoulders better than a T-pose and reads as a natural stance in the rest render.
Everything else (meshes, rig, weights) reads positions from here, so proportions are tuned in
one place.
"""
import math

from mathutils import Vector

from mx_geo import V

HEIGHT = 1.60

# Torso / head column (centre line).
HIPS = V(0, 0.006, 0.845)
SPINE = V(0, 0.012, 0.965)
CHEST = V(0, 0.012, 1.075)
NECK = V(0, 0.020, 1.270)
HEAD = V(0, 0.016, 1.345)
HEAD_TOP = V(0, 0.010, 1.585)
SKULL_C = V(0, 0.010, 1.462)   # centre of the cranium ellipsoid

# Arm (left side; the right is mirrored in X).
SHOULDER_IN = V(0.024, 0.014, 1.248)
SHOULDER_JOINT = V(0.164, 0.020, 1.250)
ARM_DROP = math.radians(54)    # A-pose angle below horizontal
UPPER_ARM_LEN = 0.258
FOREARM_LEN = 0.232
HAND_LEN = 0.085               # wrist -> knuckles (the fingers bone continues)
FINGER_LEN = 0.072


def _arm_dir():
    d = Vector((math.cos(ARM_DROP), -0.06, -math.sin(ARM_DROP)))
    return d.normalized()


ARM_DIR = _arm_dir()
ELBOW = SHOULDER_JOINT + ARM_DIR * UPPER_ARM_LEN
# A hint of elbow flex in the rest pose (forearm angled slightly forward) gives the bend a
# direction and keeps the silhouette relaxed.
FOREARM_DIR = (ARM_DIR + Vector((0.0, -0.10, 0.02))).normalized()
WRIST = ELBOW + FOREARM_DIR * FOREARM_LEN
HAND_DIR = (FOREARM_DIR + Vector((-0.06, -0.02, -0.05))).normalized()
KNUCKLE = WRIST + HAND_DIR * HAND_LEN
FINGER_TIP = KNUCKLE + HAND_DIR * FINGER_LEN

# Leg (left side).
HIP_JOINT = V(0.088, 0.004, 0.845)
KNEE = V(0.098, -0.010, 0.470)
ANKLE = V(0.104, 0.012, 0.112)
BALL = V(0.106, -0.112, 0.036)
TOE_TIP = V(0.107, -0.190, 0.036)
SOLE = 0.046                   # boot sole thickness


# The whole head assembly (head, hair, pigtails, headphones) is modelled at natural size; this
# scales it about the chin/neck pivot. 1.0 = natural size (R01 reads as ~7 heads tall; the eyes get
# their readability from the face texture, not from an enlarged head).
HEAD_SCALE = 1.0
HEAD_PIVOT = V(0, 0.016, 1.335)


def head_xform(p):
    return HEAD_PIVOT + (Vector(p) - HEAD_PIVOT) * HEAD_SCALE


# --------------------------------------------------------------------------------------------
# Proportion stage
# --------------------------------------------------------------------------------------------
# Every part is authored (and skinned) in the coordinates above. Before binding, build.py maps the
# finished meshes and the bones through `warp`, which sets the final figure proportions in one
# place: a piecewise-linear remap of height that lengthens the thighs/knees and the neck, then a
# uniform scale (GLOBAL, measured by the build) that brings the top of the hair back to TARGET_TOP.
# Boots and rolled cuffs (below WARP_KNOTS[1]) keep their shape; rigid parts (hands, belt gear,
# choker) are translated, not stretched (see rigid_shift).
WARP_KNOTS = [  # (authored z, final z before GLOBAL)
    (0.000, 0.000),
    (0.290, 0.290),    # top of the boot cuff: everything below is untouched
    (0.845, 0.915),    # hip joint: legs +7 cm (thighs and knees, inside the baggy pants)
    (1.270, 1.340),    # base of the neck (torso unchanged, shifted)
    (1.335, 1.425),    # chin pivot: neck +2 cm (R01's long neck)
]
TARGET_TOP = 1.667
GLOBAL = 1.0          # set by build.py once the warped model has been measured


def warp_z(z):
    k = WARP_KNOTS
    if z <= k[0][0]:
        return z
    for (z0, w0), (z1, w1) in zip(k, k[1:]):
        if z <= z1:
            return w0 + (z - z0) * (w1 - w0) / (z1 - z0)
    return z + (k[-1][1] - k[-1][0])


def warp(p):
    p = Vector(p)
    return Vector((p.x, p.y, warp_z(p.z))) * GLOBAL


def rigid_shift(anchor_z):
    """Translation (before GLOBAL) that carries a rigid part anchored at anchor_z."""
    return Vector((0.0, 0.0, warp_z(anchor_z) - anchor_z))


# Rigid parts: wspec prefix -> anchor height (authored). Their vertices are translated by the
# warp's displacement at the anchor, then scaled by GLOBAL.
RIGID_ANCHOR = {
    "hand": 1.000,      # hands and wrist devices ride with the arm (torso band)
    "forearm": 1.000,
    "pelvis": 0.870,    # belt, Walkman, pouches, hanging tools ride with the belt
}
RIGID_NAMES = {"choker": 1.312, "choker_ring": 1.312}


def rigid_anchor(name, wspec):
    base = name.split(".")[0]
    if base in RIGID_NAMES:
        return RIGID_NAMES[base]
    w = (wspec or "").split(".")[0]
    return RIGID_ANCHOR.get(w)


def warp_point(p, anchor=None):
    if anchor is None:
        return warp(p)
    return (Vector(p) + rigid_shift(anchor)) * GLOBAL


def mirror(p):
    return V(-p.x, p.y, p.z)


def side(p, s):
    """s = 'L' or 'R'."""
    return p.copy() if s == 'L' else mirror(p)
