"""Hard-surface gear: headphones (the signature piece), choker, Walkman, belt kit, wrist devices."""
import math

import bmesh
import bpy
import numpy as np

from mc_head import HEAD_C
from mc_util import (V, Mesh, circle_profile, cylinder, get_co, loft, norm, rbox, rot_axis, set_co,
                     shade_auto, sweep, to_object, torus, catmull, resample)


def basis(axis, up=V(0, 0, 1)):
    a = norm(np.asarray(axis, dtype=np.float64))
    u = np.cross(up, a)
    if np.linalg.norm(u) < 1e-6:
        u = V(1, 0, 0)
    u = norm(u)
    w = np.cross(a, u)
    return a, u, w


def lathe(mesh, c, axis, prof, mat, n=24, cap_end=True, cap_start=False):
    """Revolve a (radius, height-along-axis) profile around axis through c."""
    a, u, w = basis(axis)
    rings = []
    for (r, s) in prof:
        ring = []
        for k in range(n):
            t = 2 * math.pi * k / n
            ring.append(c + a * s + (math.cos(t) * u + math.sin(t) * w) * max(r, 1e-5))
        rings.append(ring)
    return loft(np.array(rings), mat, mesh, cap0=cap_start, cap1=cap_end)


def prism(mesh, c, axis, pts2, h, mat, up=V(0, 0, 1)):
    """Extrude a 2D polygon (in the plane perpendicular to axis; x->u, y->w) by h along axis."""
    a, u, w = basis(axis, up)
    pts2 = np.asarray(pts2)
    base = np.array([c + u * x + w * y for x, y in pts2])
    rings = np.array([base, base + a * h])
    return loft(rings, mat, mesh, cap0=True, cap1=True)


def finish(mesh, name, angle=35, offset=None):
    ob = to_object(name, mesh, smooth=True)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    if offset is not None:
        set_co(ob, get_co(ob) + offset)
    shade_auto(ob, angle)
    return ob


# --------------------------------------------------------------------------- headphones

CUP_C = V(0.0865, 0.017, -0.038)          # left cup centre (head-local)
CUP_AXIS = norm(V(1.0, 0.03, 0.10))
BAND_C = V(0.0, 0.016, -0.006)
BAND_R = 0.1235
CUP_SCALE = 1.20
CUP_DEPTH = 1.55


def build_headphones():
    m = Mesh()
    for s in (1, -1):
        mir = V(s, 1, 1)
        c = CUP_C * mir
        ax = CUP_AXIS * mir
        n_before = len(m.v)
        # cushion
        torus(c + ax * 0.004, ax, 0.034, 0.0115, "hp_cushion", m, n=20, m=6)
        # shell
        lathe(m, c, ax, [(0.030, 0.006), (0.0440, 0.008), (0.0470, 0.012), (0.0470, 0.025),
                         (0.0445, 0.0305), (0.0400, 0.0335), (0.0360, 0.0345)], "hp_yellow",
              cap_end=False)
        lathe(m, c, ax, [(0.0360, 0.0345), (0.0345, 0.0330), (0.0300, 0.0330)], "hp_dark",
              cap_end=False)
        lathe(m, c, ax, [(0.0300, 0.0330), (0.0290, 0.0352), (0.0240, 0.0362), (0.0, 0.0362)],
              "hp_yellow", cap_end=True)
        # triangle graphic: a dark outlined triangle standing proud of the face plate
        a, u, w = basis(ax)
        ro, ri = 0.0205, 0.0120
        outer = [(math.sin(t) * ro, math.cos(t) * ro - 0.002) for t in
                 (0, 2 * math.pi / 3, 4 * math.pi / 3)]
        inner = [(math.sin(t) * ri, math.cos(t) * ri - 0.002) for t in
                 (0, 2 * math.pi / 3, 4 * math.pi / 3)]
        base = c + ax * 0.0358
        vs, fs = [], []
        for h in (0.0, 0.0016):
            for (x, y) in outer + inner:
                vs.append(base + ax * h + u * x * s + w * y)
        for i in range(3):
            j = (i + 1) % 3
            fs.append((6 + i, 6 + j, 9 + j, 9 + i))          # top
            fs.append((i, j, 6 + j, 6 + i))                  # outer wall
            fs.append((3 + j, 3 + i, 9 + i, 9 + j))          # inner wall
        m.add(np.array(vs), fs, "hp_dark")
        # yoke: half ring around the cup + slider up to the band
        torus(c + ax * 0.018, ax, 0.0500, 0.0042, "metal_dark", m, n=18, m=6,
              arc=(math.radians(-8), math.radians(188)))
        for sg in (1, -1):
            pv = c + ax * 0.018 + u * 0.050 * sg
            cylinder(pv - u * sg * 0.006, pv + u * sg * 0.004, 0.0062, "metal", m, n=12, bevel=0.001)
        for arr in m.v[n_before:]:            # the cups are drawn big: scale the whole cup about its centre
            rel = arr - c
            along = (rel @ ax)[:, None] * ax
            arr[:] = c + (rel - along) * CUP_SCALE + along * CUP_DEPTH
        top = c + ax * 0.018 * CUP_DEPTH + w * 0.050 * CUP_SCALE
        band_ang = math.radians(62)
        bend = BAND_C + V(math.sin(band_ang) * BAND_R * s, 0, math.cos(band_ang) * BAND_R)
        rbox((top + bend) / 2 + V(0, 0, 0.002), (0.0050, 0.0105, np.linalg.norm(bend - top) / 2 + 0.008),
             0.002, "metal_dark", m,
             R=_align_z(bend - top))
    # band: yellow outer shell, dark padded inner strip
    def band(r0, half_w, half_t, a_max, mat, n=30):
        rings = []
        prof = circle_profile(10, half_w, half_t, power=4.0)
        for b in np.linspace(-a_max, a_max, n):
            rad = V(math.sin(b), 0, math.cos(b))
            p = BAND_C + rad * r0
            rings.append([p + V(0, 1, 0) * x + rad * y for x, y in prof])
        loft(np.array(rings), mat, m, cap0=True, cap1=True)
    band(BAND_R, 0.0150, 0.0050, math.radians(64), "hp_yellow")
    band(BAND_R - 0.0062, 0.0125, 0.0040, math.radians(40), "hp_cushion")
    return finish(m, "Headphones", 40, HEAD_C)


def _align_z(d):
    """Rotation matrix taking +Z to direction d."""
    d = norm(np.asarray(d, dtype=np.float64))
    z = V(0, 0, 1)
    v = np.cross(z, d)
    s = np.linalg.norm(v)
    if s < 1e-8:
        return np.eye(3)
    return rot_axis(v / s, math.atan2(s, float(z @ d)))
