"""Proportion pass: the parts are modelled and weighted in a comfortable 'build space' (7.3 heads,
broad torso) and this smooth warp then takes mesh AND skeleton to the proportions measured from
the model sheet docs/reference/generated/moxie_front.png (see README: body landmarks table):

  * everything above the hip line is scaled 0.80 (narrow shoulders and waist, short torso, slim arms)
  * the head is scaled a little further (0.775) and lifted, which lengthens the neck
  * the legs are stretched to make up the height (crotch at 0.89 m instead of 0.77 m)
  * the boots are enlarged 9 % in height and 15 % in width (chunky, as drawn)

Skin weights are functions of build-space positions and travel with the vertices, so the pass can
run after skinning. It is a pure function of position: warp(P) for (n,3) arrays.
"""
import numpy as np

S_UP = 0.80                      # upper body scale
S_HEAD = 0.775                   # head scale
Z_HIP = 0.80                     # build-space hip line (top of the leg tubes)
Z_HIP_NEW = 0.925
PIV_Y = 0.012
BOOT_TOP = 0.226                 # build-space top of the boots
BOOT_SZ = 1.09
BOOT_SX = 1.15
FOOT_X = 0.100
HEAD_PIV = np.array([0.0, 0.004, 1.386])     # build-space chin level on the neck axis
HEAD_LIFT = 0.024
NECK_BLEND = (1.335, 1.380)


def _ss(a, b, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _ztable():
    """Monotone, smooth height map z -> z' below the hip line, built by integrating a vertical scale:
    boots BOOT_SZ, legs k (solved so the hip line lands on Z_HIP_NEW), upper body S_UP."""
    z = np.linspace(0.0, 2.2, 4401)

    def build(k):
        s = BOOT_SZ + (k - BOOT_SZ) * _ss(BOOT_TOP - 0.01, BOOT_TOP + 0.05, z)
        s = s + (S_UP - s) * _ss(Z_HIP - 0.06, Z_HIP + 0.04, z)
        g = np.concatenate([[0.0], np.cumsum(0.5 * (s[1:] + s[:-1]) * np.diff(z))])
        return g
    lo, hi = 0.8, 2.0
    for _ in range(50):
        k = 0.5 * (lo + hi)
        g = build(k)
        if np.interp(Z_HIP, z, g) < Z_HIP_NEW:
            lo = k
        else:
            hi = k
    return z, build(0.5 * (lo + hi))


_Z, _G = _ztable()


def warp(P):
    P = np.asarray(P, dtype=np.float64).reshape(-1, 3)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    zn = np.interp(z, _Z, _G)
    # horizontal scale: 1 on the lower leg, S_UP from just above the hip line upward
    k = 1.0 + (S_UP - 1.0) * _ss(0.55, Z_HIP + 0.04, z)
    xn = x * k
    yn = PIV_Y + (y - PIV_Y) * k
    # boots: wider about each foot's own centre line
    b = 1.0 + (BOOT_SX - 1.0) * _ss(BOOT_TOP + 0.045, BOOT_TOP - 0.005, z)
    cx = np.sign(x) * FOOT_X
    xn = np.where(z < BOOT_TOP + 0.05, cx + (xn - cx) * b, xn)
    out = np.stack([xn, yn, zn], axis=1)
    # head: scaled about the chin-level neck point and lifted; blended in across the neck
    piv_new = np.array([0.0, PIV_Y + (HEAD_PIV[1] - PIV_Y) * S_UP, float(np.interp(HEAD_PIV[2], _Z, _G)) + HEAD_LIFT])
    head = piv_new + (P - HEAD_PIV) * S_HEAD
    w = _ss(NECK_BLEND[0], NECK_BLEND[1], z)[:, None]
    return out * (1 - w) + head * w


def warp_point(p):
    return warp(np.asarray(p, dtype=np.float64)[None, :])[0]


def apply_to_objects(obs):
    """Warp mesh objects in place."""
    import bpy  # noqa: F401
    for ob in obs:
        if ob.type != 'MESH':
            continue
        n = len(ob.data.vertices)
        co = np.empty(n * 3)
        ob.data.vertices.foreach_get("co", co)
        ob.data.vertices.foreach_set("co", warp(co.reshape(-1, 3)).reshape(-1))
        ob.data.update()


def apply_to_rig(rig):
    """Warp every bone's head and tail (rolls are re-aligned to the same reference directions)."""
    import bpy
    from mathutils import Vector
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    zaxes = {b.name: b.z_axis.copy() for b in eb}
    pts = {b.name: (np.array(b.head[:]), np.array(b.tail[:])) for b in eb}
    for b in eb:
        b.use_connect = False
    for b in eb:
        h, t = pts[b.name]
        b.head = Vector(warp_point(h))
        b.tail = Vector(warp_point(t))
    for b in eb:
        b.align_roll(zaxes[b.name])
        if b.parent and (b.head - b.parent.tail).length < 1e-5:
            b.use_connect = True
    bpy.ops.object.mode_set(mode='OBJECT')


if __name__ == "__main__":
    for name, p in (("crown", (0, 0, 1.600)), ("chin", (0, -0.05, 1.386)), ("shoulder joint", (0.128, 0.01, 1.30)),
                    ("shoulder tip", (0.19, 0.01, 1.30)), ("wrist", (0.60, 0.01, 1.30)), ("navel", (0, -0.07, 0.985)),
                    ("waistband", (0.134, 0.016, 0.915)), ("crotch", (0, 0.012, 0.770)), ("knee", (0.094, 0.004, 0.48)),
                    ("cuff", (0.11, 0.0, 0.29)), ("boot top", (0.10, 0.02, 0.226)), ("boot side", (0.158, 0.0, 0.02))):
        print("%-15s %s -> %s" % (name, p, np.round(warp_point(p), 3)))
