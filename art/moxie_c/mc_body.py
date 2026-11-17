"""Torso + arms: one quad cage (rings up the torso, arm tubes bridged into side openings with
loops at the shoulder and elbow), shaped by projecting onto a sculpted signed-distance body."""
import math

import bmesh
import bpy
import numpy as np

from mc_head import NECK_CUT_Z, neck_sdf_world
from mc_util import (V, Mesh, boundary_verts, get_co, laplacian_fast, sd_cone, sd_ellipsoid,
                     sd_sphere, sdf_project, set_co, smax, smin, subsurf, to_object)

SHOULDER = V(0.128, 0.010, 1.300)
ELBOW = V(0.375, 0.016, 1.300)
WRIST = V(0.600, 0.010, 1.300)
HIP_CUT_Z = 0.880


def body_sdf(p):
    ax = np.abs(p[:, 0])
    q = np.stack([ax, p[:, 1], p[:, 2]], axis=1)
    rib = sd_ellipsoid(p, V(0, 0.010, 1.185), V(0.112, 0.080, 0.150))
    waist = sd_cone(p, V(0, 0.012, 1.120), V(0, 0.010, 0.960), 0.090, 0.092, scale=(1.0, 0.76, 1.0))
    d = smin(rib, waist, 0.05)
    pelvis = sd_ellipsoid(p, V(0, 0.016, 0.880), V(0.136, 0.096, 0.105))
    d = smin(d, pelvis, 0.06)
    glute = sd_ellipsoid(q, V(0.060, 0.060, 0.870), V(0.062, 0.055, 0.070))
    d = smin(d, glute, 0.03)
    bust = sd_ellipsoid(q, V(0.052, -0.058, 1.190), V(0.047, 0.040, 0.044))
    d = smin(d, bust, 0.028)
    # shoulder girdle: clavicle line, trapezius, deltoid
    clav = sd_cone(q, V(0.0, 0.010, 1.292), V(0.118, 0.010, 1.300), 0.046, 0.040,
                   scale=(1.0, 0.85, 1.0))
    d = smin(d, clav, 0.035)
    trap = sd_cone(q, V(0.026, 0.022, 1.345), V(0.110, 0.014, 1.312), 0.020, 0.022)
    d = smin(d, trap, 0.030)
    delt = sd_ellipsoid(q, V(0.146, 0.010, 1.298), V(0.046, 0.043, 0.044))
    d = smin(d, delt, 0.025)
    upper = sd_cone(q, V(0.150, 0.010, 1.298), ELBOW, 0.0380, 0.0300)
    d = smin(d, upper, 0.02)
    fore = sd_cone(q, ELBOW + V(0.01, 0, 0), WRIST + V(0.02, 0, 0), 0.0320, 0.0215,
                   scale=(1.0, 1.0, 0.92))
    d = smin(d, fore, 0.012)
    neck = neck_sdf_world(p)
    d = smin(d, neck, 0.022)
    # collar-bone hollow and navel
    hollow = sd_ellipsoid(q, V(0.045, -0.062, 1.315), V(0.040, 0.018, 0.012))
    d = smax(d, -hollow, 0.02)
    navel = sd_ellipsoid(p, V(0, -0.074, 0.985), V(0.0050, 0.012, 0.0085))
    d = smax(d, -navel, 0.008)
    # soft centre line down the abdomen
    line = sd_cone(p, V(0, -0.085, 1.09), V(0, -0.085, 1.00), 0.006, 0.006)
    d = smax(d, -line, 0.016)
    return d


# torso rings: z, rx, ry (initial guesses; the SDF gives the real shape)
RINGS = [(0.880, 0.135, 0.098), (0.902, 0.131, 0.094), (0.925, 0.124, 0.090), (0.965, 0.104, 0.078),
         (1.005, 0.090, 0.070), (1.045, 0.088, 0.069), (1.085, 0.094, 0.073), (1.125, 0.103, 0.079),
         (1.165, 0.110, 0.086), (1.205, 0.114, 0.088), (1.248, 0.122, 0.078), (1.298, 0.150, 0.060),
         (1.340, 0.120, 0.050), (1.336, 0.066, 0.046), (1.343, 0.040, 0.040), (NECK_CUT_Z, 0.034, 0.034)]
ARM_A = 10                      # ring index of the armpit ring (bottom of the arm opening)
N = 24
ARM_X = [0.190, 0.232, 0.275, 0.318, 0.352, 0.375, 0.398, 0.440, 0.490, 0.540, 0.582, 0.612]


def build_body():
    verts = []
    for (z, rx, ry) in RINGS:
        for k in range(N):
            t = 2 * math.pi * k / N
            verts.append((math.sin(t) * rx, 0.012 - math.cos(t) * ry, z))
    verts = np.array(verts)
    faces = []
    R = len(RINGS)

    def vid(r, k):
        return r * N + (k % N)
    holes = {}
    for side, c0 in ((1, 4), (-1, 16)):
        holes[side] = c0
    for r in range(R - 1):
        for k in range(N):
            skip = False
            for side, c0 in holes.items():
                if r in (ARM_A, ARM_A + 1) and c0 <= k < c0 + 4:
                    skip = True
            if not skip:
                faces.append((vid(r, k), vid(r, k + 1), vid(r + 1, k + 1), vid(r + 1, k)))
    extra = []
    tags = np.zeros(len(verts), dtype=int)
    for side, c0 in holes.items():
        # ordered boundary loop: bottom front->back, back mid, top back->front, front mid
        if side > 0:
            bottom = [vid(ARM_A, c0 + i) for i in range(5)]
            top = [vid(ARM_A + 2, c0 + 4 - i) for i in range(5)]
            backm, frontm = vid(ARM_A + 1, c0 + 4), vid(ARM_A + 1, c0)
        else:
            bottom = [vid(ARM_A, c0 + 4 - i) for i in range(5)]
            top = [vid(ARM_A + 2, c0 + i) for i in range(5)]
            backm, frontm = vid(ARM_A + 1, c0), vid(ARM_A + 1, c0 + 4)
        loop = bottom + [backm] + top + [frontm]
        ang = [math.radians(a) for a in (-60, -30, 0, 30, 60, 90, 120, 150, 180, 210, 240, 270)]
        for vi, a in zip(loop, ang):
            verts[vi] = (side * 0.158, SHOULDER[1] + math.sin(a) * 0.048, SHOULDER[2] - math.cos(a) * 0.048)
            tags[vi] = 1
        # delete interior verts later (they are unused: no faces reference them)
        prev = loop
        for x in ARM_X:
            t = (x - 0.19) / (0.612 - 0.19)
            rad = 0.040 + (0.024 - 0.040) * t
            ring = []
            for a in ang:
                ring.append(len(verts) + len(extra))
                extra.append((side * x, SHOULDER[1] + math.sin(a) * rad, SHOULDER[2] - math.cos(a) * rad))
            for i in range(12):
                a0, a1 = prev[i], prev[(i + 1) % 12]
                b0, b1 = ring[i], ring[(i + 1) % 12]
                faces.append((a0, a1, b1, b0) if side > 0 else (a0, b0, b1, a1))
            prev = ring
    verts = np.vstack([verts, np.array(extra)])
    m = Mesh()
    m.add(verts, faces, "skin")
    ob = to_object("Body", m)
    # drop unreferenced verts, fix normals
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()

    def settle(iters, k):
        co = get_co(ob)
        b = boundary_verts(ob.data)
        for _ in range(iters):
            new = laplacian_fast(co, ob.data, mask=~b, k=k)
            # only relax the torso/shoulder; arms keep their ring spacing
            w = np.clip((0.26 - np.abs(co[:, 0])) / 0.06, 0, 1)[:, None]
            new = co + (new - co) * w
            new[~b] = sdf_project(body_sdf, new[~b], iters=4)
            co = new
        co[b] = _project_fixed_axis(co[b])
        set_co(ob, co)

    co = get_co(ob)
    co = sdf_project(body_sdf, co, iters=10)
    set_co(ob, co)
    settle(6, 0.35)
    subsurf(ob, 1)
    co = get_co(ob)
    co = sdf_project(body_sdf, co, iters=6)
    set_co(ob, co)
    settle(1, 0.2)
    return ob


def _project_fixed_axis(p):
    """Boundary rings: neck (stay at NECK_CUT_Z), hips (stay at HIP z), wrists (stay at x)."""
    p = p.copy()
    neck = p[:, 2] > 1.33
    hips = p[:, 2] < 0.9
    wrist = np.abs(p[:, 0]) > 0.5
    for sel, fixed, val in ((neck, 2, NECK_CUT_Z), (hips, 2, HIP_CUT_Z), (wrist, 0, None)):
        if not sel.any():
            continue
        q = p[sel]
        if val is None:
            target = np.sign(q[:, 0]) * 0.612
        else:
            target = np.full(len(q), val)
        for _ in range(10):
            q[:, fixed] = target
            e = 4e-4
            f0 = body_sdf(q)
            g = np.zeros_like(q)
            for ax in range(3):
                if ax == fixed:
                    continue
                d = np.zeros(3)
                d[ax] = e
                g[:, ax] = (body_sdf(q + d) - body_sdf(q - d)) / (2 * e)
            gg = np.maximum((g * g).sum(axis=1), 1e-10)
            q = q - (f0 / gg)[:, None] * g
        q[:, fixed] = target
        p[sel] = q
    return p
