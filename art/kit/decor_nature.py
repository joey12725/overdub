"""Overgrowth and debris: vines, bush, rubble (upper masonry / lower scrap)."""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import decor_lib as L
from decor_lib import M

# Vines are designed against a wall whose top is at this height (the common upper wall,
# prototype layout.ts wallHeightFor); the game may scale the piece in Y to fit a wall.
VINE_WALL_TOP = 1.5


def _curve_points(pts, samples):
    """Evaluate a Catmull-Rom through `pts` at `samples` evenly spaced parameters (for leaf
    placement along a strand that tube() also follows)."""
    P = [Vector(p) for p in pts]
    out = []
    n = len(P) - 1
    for k in range(samples):
        t = k / (samples - 1) * n
        i = min(int(t), n - 1)
        f = t - i
        p0 = P[max(i - 1, 0)]
        p1, p2 = P[i], P[i + 1]
        p3 = P[min(i + 2, n)]
        f2, f3 = f * f, f * f * f
        q = 0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f2 + (-p0 + 3 * p1 - 3 * p2 + p3) * f3)
        tan = 0.5 * ((-p0 + p2) + 2 * (2 * p0 - 5 * p1 + 4 * p2 - p3) * f + 3 * (-p0 + 3 * p1 - 3 * p2 + p3) * f2)
        out.append((q, tan.normalized() if tan.length > 1e-6 else Vector((0, 0, -1))))
    return out


# ───────────────────────────── vines ─────────────────────────────

def vines():
    """Wall-climbing overgrowth. The wall face is the plane y = 0 (Blender), i.e. the piece's
    origin is on the floor at the foot of the wall face; the vines hang in front of it (toward the
    camera, Godot +Z) and a leafy mat spills over the wall top (behind, Godot -Z) at 1.5 units."""
    rng = random.Random(11)
    H = VINE_WALL_TOP
    parts = []
    leaf_specs = []
    # A thick rope vine running along the top edge, gripping the lip.
    rope = [(-0.5, -0.03, H - 0.02), (-0.25, -0.04, H + 0.01), (0.0, -0.035, H - 0.03), (0.22, -0.04, H + 0.0),
            (0.5, -0.03, H - 0.02)]
    parts.append(L.tube(rope, 0.022, mat="stem", res=1, radii=[0.7, 1.0, 1.1, 1.0, 0.7]))
    # Hanging strands.
    strands = []
    for i, x0 in enumerate((-0.38, -0.17, 0.02, 0.2, 0.4)):
        length = rng.uniform(0.7, 1.25) if i != 2 else 1.32
        pts = []
        steps = 6
        for k in range(steps + 1):
            t = k / steps
            z = H - t * length
            sway = math.sin(t * 3.1 + i * 1.7) * 0.07 * t + rng.uniform(-0.015, 0.015)
            bulge = -0.02 - 0.05 * math.sin(t * math.pi) * (0.6 + 0.4 * rng.random())
            pts.append((x0 + sway, bulge, z))
        # curl at the tip
        tip = Vector(pts[-1])
        pts.append((tip.x + 0.04, tip.y - 0.03, tip.z - 0.03))
        radii = [1.0 - 0.6 * k / (len(pts) - 1) for k in range(len(pts))]
        parts.append(L.tube(pts, 0.012, mat="stem", res=1, radii=radii, resolution_u=4))
        strands.append(pts)
    # Leaves along each strand, alternating sides, facing out of the wall (-Y) and drooping.
    for si, pts in enumerate(strands):
        samples = _curve_points(pts, 12)
        for k, (p, tan) in enumerate(samples[1:], start=1):
            side = 1 if k % 2 == 0 else -1
            t = k / len(samples)
            ln = rng.uniform(0.15, 0.2) * (1.0 - 0.3 * t)
            w = ln * rng.uniform(0.75, 0.9)
            u = Vector((side * 0.8, -0.35, -0.55 + rng.uniform(-0.2, 0.2)))
            n = Vector((0, -1, 0.25))
            leaf_specs.append((L.basis(u, n, p + Vector((0, -0.004, 0))), ln, w, rng.randint(0, 1)))
    # A dense mat over the wall top and lip: leaves radiating from the rope, some over the top.
    for k in range(34):
        x = -0.48 + k / 33 * 0.96 + rng.uniform(-0.02, 0.02)
        p = Vector((x, -0.03, H + rng.uniform(-0.03, 0.03)))
        if k % 3 == 0:
            u = Vector((rng.uniform(-0.5, 0.5), 0.6, 0.35))       # back over the wall top
            n = Vector((0, 0.2, 1))
        elif k % 3 == 1:
            u = Vector((rng.uniform(-0.6, 0.6), -0.45, -0.5))     # spilling down the face
            n = Vector((0, -1, 0.3))
        else:
            u = Vector((rng.uniform(-0.4, 0.4), -0.3, 0.6))       # standing up off the lip
            n = Vector((0, -1, 0.1))
        ln = rng.uniform(0.17, 0.23)
        leaf_specs.append((L.basis(u, n, p), ln, ln * 0.8, rng.randint(0, 1)))
    # Creeping runners on the wall top behind the lip.
    for x0, x1 in ((-0.45, -0.1), (0.05, 0.42)):
        pts = [(x0, 0.0, H + 0.005), ((x0 + x1) / 2, 0.14, H + 0.015), (x1, 0.24, H + 0.005)]
        parts.append(L.tube(pts, 0.01, mat="stem", res=1))
        for p, tan in _curve_points(pts, 5)[1:]:
            for side in (-1, 1):
                u = tan.cross(Vector((0, 0, 1))) * side + tan * 0.4
                leaf_specs.append((L.basis(u, Vector((0, 0, 1)), p + Vector((0, 0, 0.004))), 0.11, 0.075,
                                   rng.randint(0, 1)))
    # Two ground shoots at the foot of the wall.
    for x0 in (-0.3, 0.28):
        pts = [(x0, -0.03, 0.0), (x0 + 0.03, -0.06, 0.12), (x0 - 0.02, -0.04, 0.26)]
        parts.append(L.tube(pts, 0.009, mat="stem", res=1))
        for p, tan in _curve_points(pts, 4):
            for side in (-1, 1):
                u = Vector((side * 0.7, -0.4, 0.5))
                leaf_specs.append((L.basis(u, Vector((0, -1, 0.3)), p), 0.1, 0.07, rng.randint(0, 1)))
    parts.append(L.leaves_obj(leaf_specs, ["foliage", "foliage_dark"]))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=50)]


# ───────────────────────────── bush ─────────────────────────────

def _blob(seed, r, loc, squash=0.75, mat="foliage_dark"):
    rng = random.Random(seed)
    obj = L.sphere(r, loc=(0, 0, 0), mat=mat, subdiv=2)
    off = Vector((rng.uniform(0, 40), rng.uniform(0, 40), rng.uniform(0, 40)))
    from mathutils import noise
    for v in obj.data.vertices:
        d = v.co.normalized()
        v.co = v.co * (1.0 + 0.22 * noise.noise(d * 2.3 + off))
        v.co.z *= squash
    L.place(obj, loc)
    return obj


def bush():
    """A rounded shrub: lumpy foliage masses wrapped in outward-pointing leaves, a few stems."""
    rng = random.Random(5)
    parts = []
    blobs = [((0.0, 0.0, 0.26), 0.27), ((-0.2, 0.08, 0.18), 0.2), ((0.2, 0.06, 0.2), 0.21),
             ((0.04, -0.17, 0.17), 0.19), ((0.06, 0.2, 0.22), 0.18)]
    for i, (c, r) in enumerate(blobs):
        parts.append(_blob(30 + i, r, c))
    specs = []
    for i, (c, r) in enumerate(blobs):
        cv = Vector(c)
        count = int(26 * (r / 0.22) ** 2)
        for k in range(count):
            # Fibonacci sphere directions, upper hemisphere biased.
            f = (k + 0.5) / count
            zc = 1 - f * 1.35
            if zc < -0.35:
                continue
            ang = k * 2.399963 + i
            rr = math.sqrt(max(0.0, 1 - zc * zc))
            d = Vector((math.cos(ang) * rr, math.sin(ang) * rr, zc))
            p = cv + Vector((d.x * r * 0.92, d.y * r * 0.92, d.z * r * 0.92 * 0.75))
            if p.z < 0.02:
                continue
            # Leaves lie over the mass like shingles: pointing up the surface and a little out,
            # face looking outward, so the clump reads as broad foliage rather than spikes.
            upt = Vector((0, 0, 1)) - d * d.z
            if upt.length < 1e-3:
                upt = Vector((math.cos(ang), math.sin(ang), 0))
            u = (upt.normalized() * 0.75 + d * 0.55).normalized()
            ln = rng.uniform(0.15, 0.2)
            specs.append((L.basis(u, d, p), ln, ln * rng.uniform(0.7, 0.85), rng.randint(0, 2) // 2))
    # Taller sprigs poking out of the top: the silhouette breakers.
    for k in range(7):
        a = k / 7 * 2 * math.pi + 0.3
        base = Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, 0.38))
        tipv = base + Vector((math.cos(a) * 0.14, math.sin(a) * 0.14, rng.uniform(0.16, 0.26)))
        parts.append(L.tube([tuple(base), tuple((base + tipv) / 2 + Vector((0, 0, 0.03))), tuple(tipv)], 0.008,
                            mat="stem", res=1))
        for side in (-1, 1):
            u = Vector((math.cos(a) + side * 0.6 * -math.sin(a), math.sin(a) + side * 0.6 * math.cos(a), 0.7))
            specs.append((L.basis(u, Vector((0, 0, 1)) - u * 0.2, tipv), 0.15, 0.11, 0))
        specs.append((L.basis(Vector((math.cos(a) * 0.4, math.sin(a) * 0.4, 1)), Vector((math.cos(a), math.sin(a), 0)),
                              tipv), 0.14, 0.1, 1))
    # Stems at the base.
    for k in range(5):
        a = k / 5 * 2 * math.pi
        parts.append(L.tube([(0, 0, 0), (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.1),
                             (math.cos(a) * 0.17, math.sin(a) * 0.17, 0.16)], 0.014, mat="stem", res=1))
    parts.append(L.leaves_obj(specs, ["foliage", "foliage_dark"]))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=55)]


# ───────────────────────────── rubble ─────────────────────────────

def broken_block(seed, size, loc, rot_z=0.0, mat="stone", bev=0.02, tilt=(0, 0)):
    """A dressed masonry block with one or two corners sheared off (bisect + fill), chamfered."""
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2] + size[2] / 2))
    for _ in range(rng.randint(1, 2)):
        corner = Vector((rng.choice((-1, 1)) * size[0] / 2, rng.choice((-1, 1)) * size[1] / 2, size[2]))
        nrm = Vector((corner.x, corner.y, corner.z * 0.8)).normalized()
        nrm += Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 0))
        nrm.normalize()
        co = corner - nrm * min(size) * rng.uniform(0.35, 0.55)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=nrm, clear_outer=True)
        edges = [e for e in bm.edges if e.is_boundary]
        if edges:
            bmesh.ops.edgeloop_fill(bm, edges=edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=L.xform(loc, (tilt[0], tilt[1], rot_z)), verts=bm.verts)
    obj = L._mesh_obj(bm, "block", [M(mat)])
    return L.bevel(obj, bev, 1, angle=30)


def rubble_upper():
    """Collapsed masonry (R03): two dressed blocks, broken stone chunks, grit and a weed tuft."""
    rng = random.Random(21)
    parts = [
        broken_block(1, (0.42, 0.3, 0.26), (-0.12, 0.08, 0.0), rot_z=12, mat="stone"),
        broken_block(2, (0.32, 0.26, 0.2), (0.2, -0.12, 0.0), rot_z=-28, mat="stone_light", tilt=(0, 8)),
        broken_block(3, (0.26, 0.2, 0.16), (-0.06, 0.06, 0.26), rot_z=40, mat="stone_light", tilt=(10, -6)),
    ]
    for i, (x, y, s) in enumerate(((0.3, 0.22, 0.18), (-0.34, -0.2, 0.16), (0.02, -0.3, 0.12), (-0.38, 0.25, 0.12),
                                   (0.36, -0.3, 0.1))):
        parts.append(L.rock(100 + i, s, (x, y, 0), rot_z=rng.uniform(0, 360), mat="stone_dark" if i % 2 else "stone"))
    for i in range(9):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.2, 0.45)
        parts.append(L.rock(200 + i, rng.uniform(0.045, 0.075), (math.cos(a) * d, math.sin(a) * d, 0),
                            rot_z=rng.uniform(0, 360), mat="stone_dark", detail=0))
    # A weed tuft growing out of the pile's seam.
    specs = []
    base = Vector((0.12, 0.12, 0.02))
    for k in range(9):
        a = k / 9 * 2 * math.pi
        u = Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, 1.0))
        specs.append((L.basis(u, Vector((math.cos(a), math.sin(a), 0.2)), base), rng.uniform(0.13, 0.2), 0.06,
                      k % 2))
    parts.append(L.leaves_obj(specs, ["foliage", "foliage_dark"]))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=30)]


def bent_plate(size, bend, loc, rot, mat="metal", seg=6):
    """A riveted metal plate bent along its length (subdivided strip, curved, solidified)."""
    sx, sy, t = size
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=seg, y_segments=1, size=0.5)
    for v in bm.verts:
        x = v.co.x * sx
        y = v.co.y * sy
        z = bend * (x / (sx / 2)) ** 2
        v.co = Vector((x, y, z))
    bmesh.ops.transform(bm, matrix=L.xform(loc, rot), verts=bm.verts)
    obj = L._mesh_obj(bm, "plate", [M(mat)])
    obj = L.solidify(obj, t, 0.0)
    return L.bevel(obj, t * 0.3, 1, angle=50)


def rubble_lower():
    """Wrecked plating (R04): a bent inscribed panel leaning on a dark boulder, a snapped pipe on
    the floor with a live neon stub, scattered plate scraps, bolts and grit."""
    rng = random.Random(33)
    parts = []
    parts.append(L.rock(301, 0.36, (0.16, 0.14, 0), rot_z=30, mat="stone"))
    parts.append(L.rock(302, 0.2, (-0.3, 0.26, 0), rot_z=75, mat="stone_dark"))
    # The panel fragment, built flat with its inscription, then leaned against the boulder.
    plate = [bent_plate((0.5, 0.34, 0.035), 0.05, (0, 0, 0), (0, 0, 0), mat="metal")]
    plate.append(L.box((0.34, 0.2, 0.012), (0.0, 0.0, 0.03), mat="metal_dark"))
    for x, a, ln in ((-0.12, 90, 0.14), (-0.08, 30, 0.08), (-0.02, 90, 0.14), (0.03, -35, 0.09),
                     (0.08, 90, 0.14), (0.12, 0, 0.07)):
        plate.append(L.box((0.016, ln, 0.01), (x, 0.0, 0.038), rot=(0, 0, a - 90 if a != 90 else 0),
                           mat="rune_glow"))
    panel = L.join(plate, "panel")
    L.place(panel, (-0.04, -0.02, 0.17), (0, -32, 20))
    parts.append(L.rest_on_floor(panel))
    # Snapped pipe lying on the floor; yellow coupling; glowing conduit poking from the break.
    pr = 0.065
    pipe = L.cyl(pr, 0.42, loc=(0, 0, 0), rot=(0, 90, 0), mat="metal_dark", n=12)
    coup = L.cyl(pr + 0.015, 0.05, loc=(0.12, 0, 0), rot=(0, 90, 0), mat="paint_yellow", n=12)
    stub = L.cyl(0.03, 0.1, loc=(-0.24, 0, 0), rot=(0, 90, 0), mat="neon_glow", n=8)
    jag = L.cyl(pr * 0.98, 0.03, loc=(-0.21, 0, 0), rot=(0, 90, 0), mat="metal", n=12, r2=pr * 0.6)
    p = L.join([pipe, coup, stub, jag], "pipe")
    L.place(p, (0.02, -0.3, pr + 0.015), (0, 0, 200))
    parts.append(L.rest_on_floor(p))
    # Plate scraps, bolts and grit.
    for i in range(9):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.25, 0.46)
        x, y = math.cos(a) * d, math.sin(a) * d
        if i % 3 == 0:
            parts.append(L.box((0.09, 0.06, 0.014), (x, y, 0.007), rot=(0, 0, rng.uniform(0, 180)), mat="metal",
                               bev=0.004))
        elif i % 3 == 1:
            parts.append(L.rock(400 + i, rng.uniform(0.05, 0.08), (x, y, 0), rot_z=rng.uniform(0, 360),
                                mat="stone_dark", detail=0))
        else:
            parts.append(L.cyl(0.022, 0.018, loc=(x, y, 0.009), mat="paint_yellow", n=6))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=30)]
