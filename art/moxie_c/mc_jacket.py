"""Oversized bomber jacket worn off the shoulders: baggy sleeves pushed up the forearms, a body
that drapes around the back with open front panels, yellow lining, ribbed cuffs / hem / collar."""
import math

import bmesh
import bpy
import numpy as np

from mc_util import (V, Mesh, activate, circle_profile, get_co, hash3, loft, material, norm,
                     set_co, smoothstep, subsurf, to_object)

ARM_Y, ARM_Z = 0.012, 1.300
SLEEVE = [  # x, radius, sag (centre drops below the arm axis): the top lies on the arm, the bulk hangs
    (0.205, 0.070, 0.024), (0.235, 0.079, 0.033), (0.268, 0.081, 0.035), (0.300, 0.077, 0.031),
    (0.332, 0.075, 0.029), (0.362, 0.080, 0.034), (0.390, 0.083, 0.037), (0.414, 0.076, 0.030),
    (0.434, 0.063, 0.018), (0.450, 0.049, 0.006), (0.462, 0.040, 0.001)]
SLEEVE_YS = 0.90             # sleeves are a little narrower front-to-back than they are tall
NS = 16
NC, NR = 32, 8
A0 = math.radians(124)       # the front hangs wide open
BODY_YC = 0.008


def _sleeve_folds(co):
    """Big irregular drape folds: long diagonal ones on the upper arm, a tight stack where the
    sleeve is pushed up the forearm; deepest underneath where the cloth hangs."""
    x = np.abs(co[:, 0])
    side = np.sign(co[:, 0])
    phi = np.arctan2(co[:, 2] - ARM_Z, co[:, 1] - ARM_Y)
    w = smoothstep(0.215, 0.255, x) * smoothstep(0.462, 0.436, x)
    u = np.where(x < 0.335, (x - 0.20) / 0.085, (0.135 / 0.085) + (x - 0.335) / 0.043)
    ph = u * 2 * math.pi + 1.9 * np.sin(phi + 0.8 * side) + 0.9 * np.sin(2 * phi + 1.3)
    amp = 0.0035 + 0.0075 * (0.5 - 0.5 * np.sin(phi))
    d = w * amp * (np.sin(ph) + 0.35 * np.sin(2 * ph + 0.6))
    d += w * 0.0035 * np.sin(phi * 3 + x * 23 + side)
    d += 0.0015 * hash3(co * 2.1, 5.0)
    return d


def _radii(v):
    """Half-width and back depth of the jacket body at height fraction v (0 hem .. 1 collar)."""
    s = math.sin(math.pi * min(1.0, max(0.0, v))) ** 0.8
    return 0.184 + 0.030 * v + 0.012 * s, 0.112 - 0.006 * v + 0.012 * s


def _edges(a):
    """Hem and collar height at azimuth a (0 = back centre). The collar rests on the upper arms
    and dips in a U across the back, as it does when a jacket is shrugged off the shoulders."""
    d = abs(math.degrees(a))
    zb = 0.968 - 0.012 * float(smoothstep(60, 124, d))
    zt = 1.200 + 0.082 * float(smoothstep(12, 82, d)) - 0.085 * float(smoothstep(80, 124, d))
    return zb, zt


def body_pt(a, v):
    zb, zt = _edges(a)
    rx, ry = _radii(v)
    front = abs(a) > math.pi / 2
    return (rx * math.sin(a), BODY_YC + (0.098 if front else ry) * math.cos(a), zb + (zt - zb) * v)


def body_grid():
    return np.array([[body_pt(-A0 + 2 * A0 * c / NC, r / NR) for c in range(NC + 1)]
                     for r in range(NR + 1)])


def build_jacket():
    m = Mesh()
    for side in (1, -1):
        rings = []
        for (x, r, sag) in SLEEVE:
            ring = []
            for k in range(NS):
                a = 2 * math.pi * k / NS
                ring.append((side * x, ARM_Y + math.cos(a) * r * SLEEVE_YS, ARM_Z - sag + math.sin(a) * r))
            rings.append(ring)
        loft(np.array(rings), "jacket_dark", m)
    grid = body_grid()
    loft(grid, "jacket_dark", m, closed=False)
    ob = to_object("Jacket", m)
    g = ob.vertex_groups.new(name="tag_sleeve")
    g.add(list(range(2 * len(SLEEVE) * NS)), 1.0, 'REPLACE')
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    subsurf(ob, 1)
    co = get_co(ob)
    ob.data.update()
    nrm = np.array([v.normal[:] for v in ob.data.vertices])
    is_sleeve = np.zeros(len(co), dtype=bool)
    for v in ob.data.vertices:
        for ge in v.groups:
            if ge.weight > 0.5:
                is_sleeve[v.index] = True
    # orient normals outward (away from the arm axis / the body axis) per island
    ax = np.stack([np.zeros(len(co)), co[:, 1] - ARM_Y, co[:, 2] - ARM_Z + 0.015], axis=1)
    bx = np.stack([co[:, 0], co[:, 1] - BODY_YC, np.zeros(len(co))], axis=1)
    outward = np.where(is_sleeve[:, None], ax, bx)
    sgn_s = np.sign((nrm[is_sleeve] * outward[is_sleeve]).sum())
    sgn_b = np.sign((nrm[~is_sleeve] * outward[~is_sleeve]).sum())
    d = np.zeros(len(co))
    d[is_sleeve] = _sleeve_folds(co[is_sleeve]) * sgn_s
    b = ~is_sleeve
    a = np.arctan2(co[b, 0], co[b, 1] - BODY_YC)
    z = co[b, 2]
    fold = 0.0065 * np.sin(a * 5 + (z - 1.1) * 14 + 1.2 * np.sin(a * 2)) * smoothstep(1.27, 1.16, z)
    fold += 0.0050 * np.sin((z - 0.96) / 0.055 * 2 * math.pi + 1.5 * np.sin(a * 3)) * smoothstep(1.07, 0.99, z)
    fold += 0.0018 * hash3(co[b] * 2.0, 9.0)
    d[b] = fold * sgn_b
    set_co(ob, co + nrm * d[:, None])
    # flip faces if an island points inward, so the lining ends up inside
    if sgn_s < 0 or sgn_b < 0:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        for f in bm.faces:
            sleeve = all(is_sleeve[v.index] for v in f.verts)
            if (sleeve and sgn_s < 0) or (not sleeve and sgn_b < 0):
                f.normal_flip()
        bm.to_mesh(ob.data)
        bm.free()
    ob.data.materials.append(material("jacket_lining"))
    activate(ob)
    md = ob.modifiers.new("solid", 'SOLIDIFY')
    md.thickness = 0.0065
    md.offset = -1.0
    md.use_even_offset = True
    md.material_offset = 1
    md.material_offset_rim = 0
    bpy.ops.object.modifier_apply(modifier=md.name)

    # ---- ribbing: cuffs, sleeve-opening roll, hem, collar roll, plackets, sleeve chevrons
    t = Mesh()
    sx = [s[0] for s in SLEEVE]
    for side in (1, -1):
        rings = []
        xs = np.linspace(0.458, 0.500, 9)
        for i, x in enumerate(xs):
            rib = 0.0016 * (1 if i % 2 else -1)
            r = 0.0390 - 0.004 * (i / 8) + rib
            rings.append([(side * x, ARM_Y + math.cos(2 * math.pi * k / 16) * r,
                           ARM_Z + math.sin(2 * math.pi * k / 16) * r) for k in range(16)])
        loft(np.array(rings), "jacket_rib", t)
        x, r, sag = SLEEVE[0]
        prof = circle_profile(8, 0.012, 0.0045, power=5.0)
        rr = []
        for k in range(20):
            a = 2 * math.pi * k / 20
            p = V(side * (x + 0.006), ARM_Y + math.cos(a) * (r + 0.004) * SLEEVE_YS, ARM_Z - sag + math.sin(a) * (r + 0.004))
            out = V(0, math.cos(a), math.sin(a))
            rr.append([p + V(side, 0, 0) * px + out * py for px, py in prof])
        rr.append(rr[0])
        loft(np.array(rr), "jacket_lining", t)
        for dx in (0.0, 0.026):
            x0 = 0.262 + dx
            pts = []
            for (u, v) in ((-0.020, 0.030), (0.0, 0.006), (0.020, 0.030), (0.020, 0.018), (0.0, -0.006),
                           (-0.020, 0.018)):
                rad = float(np.interp(x0 + v, sx, [s[1] for s in SLEEVE])) + 0.0105
                sagv = float(np.interp(x0 + v, sx, [s[2] for s in SLEEVE]))
                ang = math.pi / 2 + u / rad
                pts.append((side * (x0 + v), ARM_Y + math.cos(ang) * rad * SLEEVE_YS,
                            ARM_Z - sagv + math.sin(ang) * rad))
            t.add(np.array(pts), [(0, 1, 4, 5), (1, 2, 3, 4), (5, 4, 1, 0), (4, 3, 2, 1)], "jacket_patch")

    tb = Mesh()

    def edge_tube(row, rad_z, rad_o, mat, ribs=False, drop=0.0, out=0.0, power=2.6):
        pts = grid[row]
        rr = []
        prof = circle_profile(8, rad_z, rad_o, power=power)
        for i in range(len(pts)):
            p = pts[i].copy()
            o_ = norm(V(p[0], (p[1] - BODY_YC) * 2.4, 0))
            p = p + o_ * out - V(0, 0, drop)
            out_ = o_
            sc = 1.0 + (0.10 * (1 if i % 2 else -1) if ribs else 0.0)
            rr.append([p + V(0, 0, 1) * px + out_ * py * sc for px, py in prof])
        loft(np.array(rr), mat, tb, cap0=True, cap1=True)
    edge_tube(0, 0.020, 0.0085, "jacket_rib", ribs=True)
    edge_tube(NR, 0.030, 0.0075, "jacket_lining", drop=0.020, out=0.009, power=4.0)
    for c in (0, NC):
        col = grid[:, c]
        rr = []
        prof = circle_profile(8, 0.022, 0.0032, power=6.0)
        sg = 1.0 if c == 0 else -1.0
        for i in range(len(col)):
            p = col[i]
            out = norm(V(p[0], (p[1] - BODY_YC) * 2.4, 0))
            tang = norm(V(-out[1], out[0], 0))
            q = p + out * 0.0050 + tang * sg * 0.019
            rr.append([q + tang * px + out * py for px, py in prof])
        loft(np.array(rr), "jacket_lining", tb, cap0=True, cap1=True)
    # back emblem: the headphone triangle, as a raised yellow outline on the back panel
    def back_pt(x, z, lift):
        zb, zt = _edges(0.0)
        rx, ry = _radii((z - zb) / (zt - zb))
        return (x, BODY_YC + ry * math.sqrt(max(0.0, 1 - (x / rx) ** 2)) + lift, z)
    cz, ro, ri = 1.082, 0.058, 0.038
    outer, inner = [], []
    for k in range(3):
        a0 = math.radians(90 + 120 * k)
        a1 = math.radians(90 + 120 * (k + 1))
        for sgi in range(6):
            f = sgi / 6
            for lst, rad in ((outer, ro), (inner, ri)):
                x = rad * (math.cos(a0) * (1 - f) + math.cos(a1) * f)
                z = cz + rad * (math.sin(a0) * (1 - f) + math.sin(a1) * f)
                lst.append((x, z))
    n = len(outer)
    vs = [back_pt(x, z, 0.0125) for x, z in outer] + [back_pt(x, z, 0.0125) for x, z in inner]
    fs = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    tb.add(np.array(vs), fs + [f[::-1] for f in fs], "jacket_lining")
    out = [ob]
    for name, mesh in (("JacketTrimSleeve", t), ("JacketTrimBody", tb)):
        ob2 = to_object(name, mesh)
        bm = bmesh.new()
        bm.from_mesh(ob2.data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(ob2.data)
        bm.free()
        out.append(ob2)
    return out
