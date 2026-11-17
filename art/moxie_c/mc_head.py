"""Moxie's head: an SDF-sculpted anime head on a quad cage with edge loops around the eye and
mouth openings, inset eye plates with painted irises, modelled lashes, teeth behind the grin."""
import math

import bmesh
import bpy
import numpy as np

import mc_facedef as fd
import mc_headshape as hs
from mc_util import (V, Mesh, boundary_verts, get_co, laplacian_fast, loft, norm, resample,
                     sd_cone, sd_ellipsoid, sd_sphere, sdf_march, sdf_normal, sdf_project, set_co,
                     smax, smin, smoothstep, subsurf, to_object)

HEAD_C = V(0.0, -0.004, 1.500)     # head-local origin in world space
NECK_CUT_Z = 1.352                 # world z where the head's neck ends (under the choker)
NECK_R = 0.0335


def neck_sdf_world(p):
    return sd_cone(p, V(0, 0.016, 1.27), V(0, -0.002, 1.43), NECK_R + 0.004, NECK_R - 0.001,
                   scale=(1.0, 0.96, 1.0))


def head_sdf(p):
    """Signed distance of the head (head-local coordinates): the traced silhouette shape
    (mc_headshape) plus the features a silhouette cannot give - cheeks, eye sockets, nose, ears."""
    P = hs.P
    d = hs.shape_sdf(p)
    ax = np.abs(p[:, 0])
    q = np.stack([ax, p[:, 1], p[:, 2]], axis=1)
    # soft cheek fullness under the eyes (reads in three-quarter views; stays inside the front outline)
    cheek = sd_ellipsoid(q, P(0.130, 0.262, 0.722), V(0.0250, 0.0270, 0.0215))
    d = smin(d, cheek, 0.016)
    # eye socket: a shallow scoop so the eyes sit in the face, not on it
    sy = float(hs.surface_y(0.172, 0.597))
    sock = sd_ellipsoid(q, V(fd.EYE_C[0], sy - 0.0165, fd.EYE_C[1] + 0.001), V(0.0285, 0.0180, 0.0200))
    d = smax(d, -sock, 0.020)
    # nose: a low bridge and a small upturned tip (barely a bump from the front)
    bridge = sd_cone(p, P(0, 0.112, 0.655), P(0, 0.074, 0.715), 0.0068, 0.0062)
    d = smin(d, bridge, 0.010)
    tip = sd_cone(p, P(0, 0.066, 0.716), P(0, 0.0235, 0.743), 0.0048, 0.0036)
    d = smin(d, tip, 0.0070)
    # ears
    ear = sd_ellipsoid(q, P(0.365, 0.570, 0.655) + V(0.0035, 0, 0), V(0.0065, 0.0110, 0.0235))
    d = smin(d, ear, 0.006)
    neck = neck_sdf_world(p + HEAD_C)
    d = smin(d, neck, 0.014)
    return d


def _cube_sphere(n):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=n - 1, use_grid_fill=True)
    for v in bm.verts:
        x, y, z = v.co
        v.co = (x * math.sqrt(max(0, 1 - y * y / 2 - z * z / 2 + y * y * z * z / 3)),
                y * math.sqrt(max(0, 1 - z * z / 2 - x * x / 2 + z * z * x * x / 3)),
                z * math.sqrt(max(0, 1 - x * x / 2 - y * y / 2 + x * x * y * y / 3)))
    return bm


def _front_y(xz):
    """y of the face surface for frontal (x,z) points (march from in front)."""
    o = np.stack([xz[:, 0], np.full(len(xz), -0.3), xz[:, 1]], axis=1)
    d = np.tile(V(0, 1, 0), (len(xz), 1))
    return sdf_march(head_sdf, o, d, tmax=0.4)[:, 1]


def _snap_loop(co, loop, outline):
    """Place an ordered boundary loop evenly along a closed outline (n,2), best rotation."""
    k = len(loop)
    pts = resample(outline, k * 8, closed=True)
    cur = co[loop][:, [0, 2]]
    best, bi, brev = 1e9, 0, False
    for rev in (False, True):
        cand = pts[::-1] if rev else pts
        for s in range(0, k * 8):
            sel = cand[(s + np.arange(k) * 8) % (k * 8)]
            e = ((sel - cur) ** 2).sum()
            if e < best:
                best, bi, brev = e, s, rev
    cand = pts[::-1] if brev else pts
    sel = cand[(bi + np.arange(k) * 8) % (k * 8)]
    y = _front_y(sel)
    out = co.copy()
    out[loop, 0] = sel[:, 0]
    out[loop, 1] = y
    out[loop, 2] = sel[:, 1]
    return out


def _ordered_loops(bm):
    """Boundary loops as ordered vertex index lists."""
    bedges = [e for e in bm.edges if e.is_boundary]
    nxt = {}
    for e in bedges:
        a, b = e.verts[0].index, e.verts[1].index
        nxt.setdefault(a, []).append(b)
        nxt.setdefault(b, []).append(a)
    seen, loops = set(), []
    for s in nxt:
        if s in seen:
            continue
        loop = [s]
        seen.add(s)
        prev, cur = None, s
        while True:
            cand = [x for x in nxt[cur] if x != prev and x not in seen]
            if not cand:
                break
            prev, cur = cur, cand[0]
            loop.append(cur)
            seen.add(cur)
        loops.append(loop)
    return loops


def _classify(co, loop):
    c = co[loop].mean(axis=0)
    if c[2] < (NECK_CUT_Z - HEAD_C[2]) + 0.02 and abs(c[0]) < 0.01 and c[1] > -0.03:
        return "neck"
    if abs(c[0]) < 0.004:
        return "mouth"
    return "eyeL" if c[0] > 0 else "eyeR"


def build_head(n=14):
    bm = _cube_sphere(n)
    dirs = norm(np.array([v.co[:] for v in bm.verts]))
    centre = V(0, 0.004, -0.022)
    co = sdf_march(head_sdf, centre + dirs * 0.40, -dirs, tmax=0.40)
    for v, p in zip(bm.verts, co):
        v.co = p
    cut = NECK_CUT_Z - HEAD_C[2]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.co.z < cut for v in f.verts)],
                     context='FACES')
    me = bpy.data.meshes.new("Head")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Head", me)
    bpy.context.scene.collection.objects.link(ob)

    def relax(iters, k=0.5, pin=None):
        co = get_co(ob)
        b = boundary_verts(ob.data)
        mask = ~b if pin is None else ~(b | pin)
        for _ in range(iters):
            new = laplacian_fast(co, ob.data, mask=mask, k=k)
            new[mask] = sdf_project(head_sdf, new[mask], iters=3)
            co = new
        # neck boundary: keep on the cut plane, round
        co[:, 0] = np.where(np.abs(co[:, 0]) < 1e-5, 0.0, co[:, 0])
        set_co(ob, co)

    def flatten_neck():
        co = get_co(ob)
        bm2 = bmesh.new()
        bm2.from_mesh(ob.data)
        for loop in _ordered_loops(bm2):
            if _classify(co, loop) == "neck":
                p = co[loop]
                p[:, 2] = cut
                c = V(0, (neck_centre_y(NECK_CUT_Z)) - HEAD_C[1], cut)
                a = np.arctan2(p[:, 1] - c[1], p[:, 0] - c[0])
                # even angular spacing preserving order
                order = np.argsort(a)
                aa = np.linspace(-math.pi, math.pi, len(loop), endpoint=False) + math.pi / len(loop)
                tgt = np.empty_like(p)
                for rank, idx in enumerate(order):
                    tgt[idx] = c + V(math.cos(aa[rank]), math.sin(aa[rank]), 0) * 0.05
                tgt = sdf_project_plane(tgt, cut)
                co[loop] = tgt
        bm2.free()
        set_co(ob, co)

    flatten_neck()
    relax(25)

    # ---- eye and mouth openings with a concentric loop
    outlines = {"eyeL": fd.eye_outline(1), "eyeR": fd.eye_outline(-1), "mouth": fd.mouth_outline()}
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    for key in ("eyeL", "eyeR", "mouth"):
        poly = outlines[key] if key != "mouth" else fd.mouth_outline(scale=1.25)
        sel = []
        if key == "mouth":
            mz = fd.MOUTH_C[1]
            cand = [(f, f.calc_center_median()) for f in bm.faces]
            cand = [(f, c) for f, c in cand if c.y < -0.03 and abs(c.x) < 0.0255
                    and abs(c.z - mz) < 0.012]
            z0 = min(cand, key=lambda fc: abs(fc[1].z - mz + 0.001))[1].z
            sel = [f for f, c in cand if abs(c.z - z0) < 0.003]
        else:
            for f in bm.faces:
                c = f.calc_center_median()
                if c.y < -0.03 and fd.point_in_poly((c.x, c.z), poly):
                    sel.append(f)
        print('HOLE', key, len(sel))
        res = bmesh.ops.inset_region(bm, faces=sel, thickness=0.0035, use_even_offset=True,
                                     use_boundary=True)
        bmesh.ops.delete(bm, geom=sel, context='FACES')
    bm.to_mesh(ob.data)
    bm.free()

    def snap_holes(relax_ring=True):
        co = get_co(ob)
        bm2 = bmesh.new()
        bm2.from_mesh(ob.data)
        pin = np.zeros(len(co), dtype=bool)
        for loop in _ordered_loops(bm2):
            kind = _classify(co, loop)
            print('LOOP', kind, len(loop), co[loop].mean(axis=0).round(3))
            if kind == "neck":
                continue
            co = _snap_loop(co, loop, outlines[kind])
            pin[loop] = True
        bm2.free()
        set_co(ob, co)
        return pin

    snap_holes()
    relax(18, k=0.45)
    subsurf(ob, 1)
    flatten_neck()
    snap_holes()
    co = get_co(ob)
    b = boundary_verts(ob.data)
    co[~b] = sdf_project(head_sdf, co[~b], iters=6)
    set_co(ob, co)
    relax(3, k=0.3)

    # ---- UVs (frontal projection for the painted face) and rims
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    co = get_co(ob)
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            uvl.data[li].uv = fd.face_uv(co[vi, 0], co[vi, 2])
    from mc_util import material
    me.materials.append(material("skin_face"))
    me.materials.append(material("skin"))
    me.materials.append(material("mouth_in"))
    # back / side of the head uses the plain skin material (no texture stretch)
    for poly in me.polygons:
        c = co[list(poly.vertices)].mean(axis=0)
        nrm = poly.normal
        poly.material_index = 0 if (nrm.y < -0.25 and c[1] < 0.0) else 1

    # rims: extrude the eye and mouth borders inward for lid / lip thickness
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for loop in _ordered_loops(bm):
        kind = _classify(co, loop)
        if kind == "neck":
            continue
        bm.verts.ensure_lookup_table()
        vs = [bm.verts[i] for i in loop]
        cen = np.mean([v.co[:] for v in vs], axis=0)
        depth = 0.0045 if kind != "mouth" else 0.0022
        shrink = 0.94 if kind != "mouth" else 0.97
        new = []
        for v in vs:
            p = np.array(v.co[:])
            q = cen + (p - cen) * shrink
            q[1] = p[1] + depth
            new.append(bm.verts.new(q))
        k = len(vs)
        for i in range(k):
            a, b2 = vs[i], vs[(i + 1) % k]
            c2, d2 = new[(i + 1) % k], new[i]
            try:
                f = bm.faces.new((a, b2, c2, d2))
            except ValueError:
                continue
            f.smooth = True
            f.material_index = 2 if kind == "mouth" else 0
            for lp in f.loops:
                lp[uv].uv = fd.face_uv(lp.vert.co.x, lp.vert.co.z)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    # head-local -> world
    set_co(ob, get_co(ob) + HEAD_C)
    return ob


def neck_centre_y(z):
    t = (z - 1.27) / (1.43 - 1.27)
    return 0.016 + (-0.002 - 0.016) * t


def sdf_project_plane(p, zc):
    """Project points onto the head surface while staying in the plane z = zc."""
    p = p.copy()
    for _ in range(12):
        q = p.copy()
        e = 4e-4
        f0 = head_sdf(q)
        gx = (head_sdf(q + V(e, 0, 0)) - head_sdf(q - V(e, 0, 0))) / (2 * e)
        gy = (head_sdf(q + V(0, e, 0)) - head_sdf(q - V(0, e, 0))) / (2 * e)
        gg = np.maximum(gx * gx + gy * gy, 1e-9)
        p[:, 0] -= f0 * gx / gg
        p[:, 1] -= f0 * gy / gg
        p[:, 2] = zc
    return p


# --------------------------------------------------------------------------- eyes, lashes, teeth

def _surface_pts(xz, lift=0.0):
    y = _front_y(xz)
    p = np.stack([xz[:, 0], y, xz[:, 1]], axis=1)
    if lift:
        p = p - sdf_normal(head_sdf, p) * (-lift)
    return p


def build_eyes():
    """Inset eye plates (slightly concave) with the painted iris texture."""
    m = Mesh()
    for side, u0 in ((1, 0.0), (-1, 0.5)):
        ex, ez = fd.EYE_C[0] * side, fd.EYE_C[1]
        out = fd.eye_outline(side, n=28, scale=1.22)
        cen = np.array([ex, ez])
        rings = []
        K = 4
        for j in range(K + 1):
            s = j / K
            rings.append(cen + (out - cen) * s)
        rings = np.array(rings)               # (K+1, 40, 2)
        flat = rings.reshape(-1, 2)
        ysurf = _front_y(out).mean()
        r = np.linalg.norm((flat - cen) / np.array([0.024, 0.016]), axis=1)
        y = ysurf + 0.0052 + 0.0022 * (1 - np.clip(r, 0, 1.3) ** 2) - 0.004 * np.abs(flat[:, 0] - ex) * 0.0
        # follow the head curvature sideways so the plate never pokes through the temple
        y = y + 0.9 * np.maximum(np.abs(flat[:, 0]) - abs(ex), 0) * 0.35
        verts = np.stack([flat[:, 0], y, flat[:, 1]], axis=1)
        uvs = np.stack([u0 + 0.5 * ((flat[:, 0] - ex) / fd.EYE_SPAN + 0.5),
                        (flat[:, 1] - ez) / fd.EYE_SPAN + 0.5], axis=1)
        n = 28
        faces = []
        for j in range(1, K):
            for i in range(n):
                a, b = j * n + i, j * n + (i + 1) % n
                c, d = (j + 1) * n + (i + 1) % n, (j + 1) * n + i
                faces.append((a, d, c, b))
        for i in range(n):       # centre fan (ring 0 collapses to the centre: use ring 1)
            faces.append((0, n + i, n + (i + 1) % n))
        m.add(verts, faces, "eye", uvs)
    ob = to_object("Eyes", m)
    co = get_co(ob) + HEAD_C
    set_co(ob, co)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    # make sure the plates face the viewer (-Y)
    for f in bm.faces:
        if f.normal.y > 0:
            f.normal_flip()
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def build_lashes():
    """Upper lashes with an outer wing, a few spikes, as solid geometry sitting on the lid."""
    m = Mesh()
    for side in (1, -1):
        lid = fd.upper_lid(36)
        n = len(lid)
        t = np.linspace(0, 1, n)
        tang = np.gradient(lid, axis=0)
        tang /= np.linalg.norm(tang, axis=1, keepdims=True)
        nrm = np.stack([-tang[:, 1], tang[:, 0]], axis=1)       # up / outward
        th = 0.001 * np.interp(t, [0, 0.15, 0.5, 0.8, 1.0], [0.5, 2.0, 3.6, 4.4, 4.0])
        lower = lid - nrm * 0.0009
        upper = lid + nrm * th[:, None]
        # wing: continue past the outer corner, sweeping up and out to a point
        wing_dir = norm(tang[-1] + V(0.25, 0.75)[:2])
        wl = np.array([lower[-1] + wing_dir * 0.0040 + V(0.0012, -0.0004)[:2],
                       lower[-1] + wing_dir * 0.0110 + V(0.0012, 0.0008)[:2]])
        wu = np.array([upper[-1] + wing_dir * 0.0045, lower[-1] + wing_dir * 0.0112 + V(0.0, 0.0012)[:2]])
        lower = np.vstack([lower, wl])
        upper = np.vstack([upper, wu])
        if side < 0:
            lower = lower * np.array([-1, 1])
            upper = upper * np.array([-1, 1])
        k = len(lower)
        pf_l, pf_u = _surface_pts(lower), _surface_pts(upper)
        front = np.array([0, -0.0013, 0])
        back = np.array([0, 0.0016, 0])
        rings = np.stack([np.stack([pf_l[i] + back, pf_l[i] + front * 0.8, pf_u[i] + front,
                                    pf_u[i] + back]) for i in range(k)])
        loft(rings, "lash", m, cap0=True, cap1=True, flip=(side > 0))
        # spikes on the outer upper edge
        for a, ln in ((0.70, 0.0042), (0.84, 0.0052), (0.95, 0.0046)):
            i = int(a * (n - 1))
            base = lid[i] + nrm[i] * th[i] * 0.6
            d = norm(nrm[i] * 0.8 + tang[i] * 0.75)
            w = tang[i] * 0.0014
            tri2 = np.array([base - w, base + w, base + d * (th[i] * 0.4 + ln)])
            if side < 0:
                tri2 = tri2 * np.array([-1, 1])
            p3 = _surface_pts(tri2)
            p3[2, 1] -= 0.0006
            rr = np.stack([np.stack([p + back, p + front]) for p in p3])
            fs = [(0, 2, 4), (1, 5, 3), (0, 1, 3, 2), (2, 3, 5, 4), (4, 5, 1, 0)]
            m.add(rr.reshape(-1, 3), fs, "lash")
    ob = to_object("Lashes", m, smooth=False)
    set_co(ob, get_co(ob) + HEAD_C)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def build_teeth():
    """Teeth plate behind the grin."""
    out = fd.mouth_outline(n=36, scale=1.3)
    cen = np.array(fd.MOUTH_C)
    m = Mesh()
    K = 3
    rings = np.array([cen + (out - cen) * (j / K) for j in range(K + 1)])
    flat = rings.reshape(-1, 2)
    ys = _front_y(fd.mouth_outline(n=36))
    y0 = ys.mean() + 0.0028
    y = y0 + 6.0 * flat[:, 0] ** 2
    verts = np.stack([flat[:, 0], y, flat[:, 1]], axis=1)
    n = 36
    faces = []
    for j in range(1, K):
        for i in range(n):
            a, b = j * n + i, j * n + (i + 1) % n
            c, d = (j + 1) * n + (i + 1) % n, (j + 1) * n + i
            faces.append((a, d, c, b))
    for i in range(n):
        faces.append((0, n + i, n + (i + 1) % n))
    m.add(verts, faces, "teeth")
    ob = to_object("Teeth", m)
    set_co(ob, get_co(ob) + HEAD_C)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    for f in bm.faces:
        if f.normal.y > 0:
            f.normal_flip()
    bm.to_mesh(ob.data)
    bm.free()
    return ob
