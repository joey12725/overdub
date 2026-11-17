"""Moxie's clothes: crop top with dark trim, diagonal chest strap, choker, the oversized dark jacket
with yellow lining worn off the shoulders and bunched at the elbows, loose low-rise olive cargo
pants (pockets, yellow zig-zag, torn knee, rolled cuffs), the belt, and chunky high-top boots.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import mx_skel as S
from mx_body import ARM_PROFILE, arm_point_at, tag, torso_point, torso_section
from mx_geo import (TAU, V, obj_from_bmesh, assign_material_by, basis, catmull, cylinder, extrude_polygon,
                    flat_strip, frames_along, interp_profile, lathe, lerp, loft, look_basis,
                    mirror_copy, resample, ring_points, rounded_box, set_material, slot_index,
                    smoothstep, solidify, subsurf, tube_along, conform)


def solve_angle(z, x_target, front=True, inflate=0.0):
    """Angle on the torso cross-section at height z whose x matches x_target (front or back)."""
    best, best_a = 1e9, 0.0
    lo, hi = (-math.pi, 0.0) if front else (0.0, math.pi)
    for i in range(181):
        a = lo + (hi - lo) * i / 180
        d = abs(torso_point(z, a, inflate).x - x_target)
        if d < best:
            best, best_a = d, a
    return best_a


def body_point(x, z, off, front=True):
    a = solve_angle(z, x, front, off)
    return torso_point(z, a, off)


# --------------------------------------------------------------------------------------------
# top, chest strap, choker
# --------------------------------------------------------------------------------------------

def make_top():
    zs = [1.062, 1.072, 1.084, 1.100, 1.120, 1.140, 1.160, 1.178, 1.192, 1.204, 1.212, 1.218]
    n = 20
    rings = []
    for z in zs:
        ring = []
        for k in range(n):
            a = TAU * k / n - math.pi / 2
            infl = 0.0065 + 0.004 * smoothstep(1.085, 1.12, z) * (1.0 - 0.5 * smoothstep(1.17, 1.21, z))
            infl += 0.010 * math.exp(-((z - 1.128) / 0.04) ** 2) * max(0.0, -math.sin(a))
            p = torso_point(z, a, infl)
            # scoop the neckline a little at the front centre; armholes dip at the sides
            if z == zs[0] and p.y < 0:
                # the hem curves up at the centre front
                p.z += 0.012 * math.exp(-(p.x / 0.055) ** 2)
            if z > 1.19:
                c = math.cos(a)
                p.z -= 0.010 * math.exp(-(p.x / 0.035) ** 2) * (1 if p.y < 0 else 0.3)
                p.z -= 0.012 * (abs(c) ** 4)
            ring.append(p)
        rings.append(ring)
    obj = loft("crop_top", rings, 'top', closed=True)
    trim = slot_index(obj, 'top_trim')
    for poly in obj.data.polygons:
        c = poly.center
        if c.z < 1.082 or c.z > 1.196:
            poly.material_index = trim
    parts = [obj]
    # shoulder straps (dark trim), front scoop edge up over the trapezius to the back
    for s in (1, -1):
        pts = [torso_point(1.200, solve_angle(1.200, s * 0.068, True, 0.006), 0.008),
               V(s * 0.072, -0.030, 1.252), V(s * 0.068, 0.010, 1.286), V(s * 0.068, 0.050, 1.262),
               torso_point(1.205, solve_angle(1.205, s * 0.072, False, 0.006), 0.008)]
        path = resample(catmull(pts, 6), 14)
        strap = flat_strip("top_strap", path, lambda t: 0.017, 0.004,
                           lambda i, p: V(p.x * 0.4, p.y, p.z - 1.17), 'top_trim')
        parts.append(strap)
    # graphic: R01's faint four-point star on the chest, a shade darker than the cream top
    star = []
    for k in range(8):
        a = math.pi / 2 + TAU * k / 8
        r = 0.030 if k % 2 == 0 else 0.009
        star.append((math.cos(a) * r, math.sin(a) * r))
    c = torso_point(1.140, -math.pi / 2 + 0.25, 0.012)
    m = look_basis(c + V(0, -0.010, 0), V(0, -1, 0.15), V(0, 0, 1))
    m = m @ Matrix.Scale(-1, 4, V(1, 0, 0))
    st = extrude_polygon("top_star", star, 0.0015, m, 'top_graphic')
    bm2 = bmesh.new()
    bm2.from_mesh(st.data)
    bmesh.ops.subdivide_edges(bm2, edges=bm2.edges[:], cuts=2, use_grid_fill=False)
    bmesh.ops.triangulate(bm2, faces=bm2.faces[:])
    bm2.to_mesh(st.data)
    bm2.free()
    conform(st, obj, V(0, -1, 0), base=0.0006, thickness=0.0012)
    parts.append(st)
    for p in parts:
        tag(p, "torso")
    return parts


def make_chest_strap():
    """Diagonal dark strap from her left shoulder across the chest to the right hip, buckle on it."""
    pts = [V(0.105, 0.075, 1.170), V(0.112, 0.040, 1.262), V(0.098, -0.010, 1.275)]
    for z, x in ((1.215, 0.072), (1.165, 0.036), (1.115, -0.002), (1.065, -0.040), (1.010, -0.072),
                 (0.955, -0.098), (0.905, -0.118)):
        pts.append(body_point(x, z, 0.016 if z > 1.07 else 0.009))
    path = resample(catmull(pts, 6), 30)
    strap = flat_strip("chest_strap", path, lambda t: 0.024, 0.0045,
                       lambda i, p: V(p.x * 0.6, p.y - 0.012, max(0.0, p.z - 1.235) * 6.0), 'top_trim')
    parts = [strap]
    # buckle at mid-chest
    bp = path[13]
    t = (path[14] - path[12]).normalized()
    nrm = (bp - V(0, 0.01, bp.z)).normalized()
    nrm = (nrm + V(0, -1.2, 0)).normalized()
    m = look_basis(bp + nrm * 0.004, nrm, t)
    frame = rounded_box("buckle_frame", (0.032, 0.030, 0.006), bevel=0.002, material='metal', matrix=m)
    hole = rounded_box("buckle_bar", (0.020, 0.006, 0.008), bevel=0.0015, material='dark',
                       matrix=m @ Matrix.Translation(V(0, 0.004, 0.0)))
    parts += [frame, hole]
    for p in parts:
        tag(p, "torso")
    return parts


def make_choker():
    band = lathe("choker", [(0.0385, -0.008), (0.0405, -0.006), (0.0405, 0.006), (0.0385, 0.008)], n=16,
                 material='top_trim', cap_start=False, cap_end=False)
    band.data.transform(Matrix.Translation(V(0, 0.020, 1.312)) @ Matrix.Scale(1.04, 4, V(0, 1, 0)))
    ringpath = [V(math.cos(a) * 0.009, -0.024, 1.296 + math.sin(a) * 0.009)
                for a in [TAU * k / 16 - math.pi / 2 for k in range(17)]]
    ring = tube_along("choker_ring", ringpath[::2], lambda t: 0.0018, n=4, up=V(0, -1, 0))
    set_material(ring, 'metal')
    ring.data.transform(Matrix.Translation(V(0, -0.0, 0)))
    for p in (band, ring):
        tag(p, "neck")
    return [band, ring]


# --------------------------------------------------------------------------------------------
# jacket
# --------------------------------------------------------------------------------------------

def sleeve_path_params():
    # chain distances along the arm covered by the bunched sleeve
    return [(0.080, 0.050), (0.112, 0.060), (0.145, 0.066), (0.178, 0.069), (0.210, 0.072), (0.240, 0.073),
            (0.268, 0.069), (0.292, 0.064), (0.315, 0.058), (0.335, 0.052)]


def make_sleeve():
    params = sleeve_path_params()
    path = [arm_point_at(d) for d, _ in params]
    fr = frames_along(path, V(0, -1, 0))
    rings = []
    n = 12
    m = len(params)
    for i, (p, (t, nrm, b), (d, r)) in enumerate(zip(path, fr, params)):
        # accordion folds where the sleeve gathers at the elbow: alternate rings swell/pinch
        acc = 1.0 + (0.075 if i % 2 else -0.045) * smoothstep(0.12, 0.20, d) * (1 - smoothstep(0.30, 0.335, d))

        def shape(a, i=i, acc=acc):
            # bunched folds: lobes that shift ring to ring
            return acc * (1.0 + 0.07 * math.sin(4 * a + i * 1.7) + 0.035 * math.sin(7 * a - i * 2.3))
        # sag: the fabric hangs below the arm (world -Z)
        sag = V(0, 0, -0.012 * math.sin(i / (m - 1) * math.pi))
        rings.append(ring_points(p + sag, nrm, b, r, r * 0.95, n, shape))
    obj = loft("sleeve.L", rings, 'jacket', closed=True)
    add_lining = slot_index(obj, 'jacket_lining')
    solidify(obj, 0.006, offset=-1.0, material_offset=add_lining, rim_material_offset=add_lining)
    parts = [obj]
    # ribbed yellow cuff at the forearm end
    d_end, r_end = params[-1]
    c = arm_point_at(d_end + 0.004)
    t = S.FOREARM_DIR
    mm = look_basis(c, t, V(0, 0, 1))
    cuff = lathe("sleeve_cuff", [(r_end - 0.006, -0.012), (r_end + 0.004, -0.010), (r_end + 0.008, 0.0),
                                 (r_end + 0.004, 0.010), (r_end - 0.006, 0.012)], n=16,
                 material='jacket_lining', cap_start=False, cap_end=False)
    cuff.data.transform(mm)
    for v in cuff.data.vertices:
        loc = mm.inverted() @ v.co
        ang = math.atan2(loc.y, loc.x)
        v.co += (v.co - c).normalized() * 0.004 * math.sin(5 * ang)
    parts.append(cuff)
    # chevron graphic on the outer upper sleeve (R01: yellow double chevron), wrapped onto the cloth
    pc = arm_point_at(0.15)
    out = V(1, 0, 0.55).normalized()
    m2 = look_basis(pc + out * 0.08, out, S.ARM_DIR * -1)
    for j in range(2):
        chev = [(-0.022, 0.010), (0.0, -0.008), (0.022, 0.010), (0.022, 0.0), (0.0, -0.019), (-0.022, 0.0)]
        chev = [(x, y + j * 0.021 - 0.010) for x, y in chev]
        ch = extrude_polygon("chevron", chev, 0.003, m2, 'jacket_lining')
        conform(ch, obj, out, thickness=0.0025)
        parts.append(ch)
    for p in parts:
        tag(p, "sleeve.L")
    return parts


JACKET_ZS = [1.170, 1.140, 1.100, 1.055, 1.010, 0.965, 0.925, 0.890]


def jacket_a0(z):
    return interp_profile([(0.89, -0.95), (1.05, -0.75), (1.17, -0.45)], z)


def jacket_point(z, a, top=False):
    """Outer surface of the jacket body: an open arc (a from a0 at her front-left round the back
    to pi - a0 at her front-right)."""
    w = interp_profile([(0.89, 0.218), (0.95, 0.226), (1.05, 0.240), (1.12, 0.250), (1.17, 0.232)], z)
    db = interp_profile([(0.89, 0.125), (1.00, 0.119), (1.12, 0.112), (1.17, 0.098)], z)
    s = math.sin(a)
    # vertical drape folds, deeper toward the hem and across the back
    fold = 1.0 + (0.030 + 0.035 * smoothstep(1.06, 0.89, z)) * math.sin(7 * a + 1.3) \
        + 0.016 * math.sin(13 * a + 0.4) * smoothstep(1.10, 0.95, z)
    x = w * math.cos(a) * fold
    y = 0.022 + (db if s > 0 else 0.080) * s * fold
    zz = z
    if top:
        # the collar line sags in a U between the shoulder blades
        zz -= 0.045 * max(0.0, s) ** 1.5
    # the hem rides up toward the front edges (cropped bomber)
    if z < 0.90:
        zz += 0.020 * (1 - max(0.0, s))
    return V(x, y, zz)


def jacket_ring(z, n, top=False):
    a0 = jacket_a0(z)
    return [jacket_point(z, lerp(a0, math.pi - a0, k / (n - 1)), top) for k in range(n)]


def make_jacket_body():
    zs = JACKET_ZS
    n = 32
    rings = [jacket_ring(z, n, top=(i == 0)) for i, z in enumerate(zs)]
    obj = loft("jacket_body", rings, 'jacket', closed=False)
    lin = slot_index(obj, 'jacket_lining')
    obj.data.flip_normals() if _faces_inward(obj) else None
    shell = obj.data.copy()   # the outer surface, before solidify, for wrapping the back graphic
    solidify(obj, 0.007, offset=-1.0, material_offset=lin, rim_material_offset=lin)
    parts = [obj]
    # bunched hood roll along the top edge: sags at the back, fat and lumpy, lining on its inner face
    top = rings[0]
    cpath = resample(catmull(top, 4), 34)

    def roll(t):
        return (0.020 + 0.016 * math.sin(t * math.pi) ** 1.5) * (1.0 + 0.12 * math.sin(t * 31.0))
    collar = tube_along("jacket_hood", cpath, roll, n=8, up=V(0, 0, 1),
                        ry_fn=lambda t: roll(t) * 1.25 + 0.006 * math.sin(t * math.pi))
    set_material(collar, 'jacket')
    lin2 = slot_index(collar, 'jacket_lining')
    for poly in collar.data.polygons:
        nrm = poly.normal
        rad = V(poly.center.x, poly.center.y - 0.02, 0).normalized()
        if nrm.dot(rad) < -0.2 and nrm.z > -0.3:
            poly.material_index = lin2
    parts.append(collar)
    # ribbed hem band (curves up toward the front edges)
    hem = [p + V(0, 0, 0.004) for p in rings[-1]]
    hpath = resample(catmull(hem, 4), 40)

    def rib(t):
        return 0.009 * (1.0 + 0.10 * math.cos(t * 160.0))
    band = tube_along("jacket_hem", hpath, rib, n=4, up=V(0, 0, 1), ry_fn=lambda t: rib(t) * 1.6)
    set_material(band, 'jacket')
    parts.append(band)
    # front edges turned back: yellow lining facings down both fronts (R01)
    for side in (0, 1):
        pts = []
        for z in zs:
            a0 = jacket_a0(z)
            a = a0 if side == 0 else math.pi - a0
            da = 0.10 if side == 0 else -0.10
            pts.append(jacket_point(z, a + da * 0.5, top=(z == zs[0])))
        path = resample(catmull(pts, 4), 12)

        def up(i, p):
            return V(p.x, p.y - 0.022, 0).normalized()
        face = flat_strip("jacket_facing", path, lambda t: 0.034 - 0.006 * t, 0.004, up, 'jacket_lining')
        for v in face.data.vertices:
            v.co += V(v.co.x, v.co.y - 0.022, 0).normalized() * 0.004
        parts.append(face)
        # zipper pull dangling at the hem of each front
        zp = path[-1] + V(0, -0.006, -0.014)
        parts.append(rounded_box("zip_pull", (0.008, 0.004, 0.022), bevel=0.0015, material='metal',
                                 matrix=Matrix.Translation(zp)))
    # back graphic: a big yellow double chevron (echoing the sleeve patches), wrapped onto the back
    shell_obj = bpy.data.objects.new("jacket_shell_tmp", shell)
    back_c = jacket_point(1.035, math.pi / 2)
    mb = look_basis(back_c + V(0, 0.02, 0), V(0, 1, 0), V(0, 0, 1)) @ Matrix.Scale(-1, 4, V(1, 0, 0))
    for j in range(2):
        chev = [(-0.070, 0.030), (0.0, -0.024), (0.070, 0.030), (0.070, 0.004), (0.0, -0.052), (-0.070, 0.004)]
        chev = [(x, y + j * 0.058 - 0.010) for x, y in chev]
        ob = extrude_polygon("back_chevron", chev, 0.003, mb, 'jacket_lining')
        # subdivide so it bends round the back
        me = ob.data
        bm2 = bmesh.new()
        bm2.from_mesh(me)
        bmesh.ops.subdivide_edges(bm2, edges=bm2.edges[:], cuts=2, use_grid_fill=False)
        bmesh.ops.triangulate(bm2, faces=bm2.faces[:])
        bm2.to_mesh(me)
        bm2.free()
        conform(ob, shell_obj, V(0, 1, 0), base=0.0012, thickness=0.0025)
        parts.append(ob)
    bpy.data.objects.remove(shell_obj)
    bpy.data.meshes.remove(shell)
    for p in parts:
        tag(p, "jacket")
    return parts


def _faces_inward(obj):
    me = obj.data
    score = 0.0
    for poly in me.polygons:
        rad = V(poly.center.x, poly.center.y - 0.02, 0)
        score += poly.normal.dot(rad)
    return score < 0


def build_jacket():
    sl = make_sleeve()
    parts = sl + [mirror_copy(p, p.name + ".R") for p in sl]
    for p in parts[len(sl):]:
        p["wspec"] = "sleeve.R"
    return parts + make_jacket_body()


# --------------------------------------------------------------------------------------------
# pants
# --------------------------------------------------------------------------------------------

PANTS_TOP = [  # (z, half_width, front, back, cy, squareness) pelvis section, waist down to the seat
    (0.895, 0.128, 0.080, 0.080, 0.012, 2.2),
    (0.862, 0.150, 0.092, 0.094, 0.012, 2.2),
    (0.800, 0.180, 0.102, 0.108, 0.012, 2.3),
]
CROTCH_Z = 0.712      # dropped crotch: the seam where the legs part
CROTCH_OPEN = 0.070   # height over which the inner legs separate below the seam
WAIST_Z = 0.895

# Baggy low-rise cargo leg (R01): balloons out from the hip, widest just below the knee, then
# gathers into a thick rolled cuff over the boot top. Rings: (z, r_inner, r_outer, r_front, r_back).
LEG_PROFILE = [
    (0.800, 0.074, 0.092, 0.090, 0.098),
    (0.740, 0.076, 0.098, 0.094, 0.100),
    (0.660, 0.078, 0.104, 0.098, 0.104),
    (0.580, 0.080, 0.110, 0.104, 0.108),
    (0.500, 0.082, 0.118, 0.110, 0.112),
    (0.430, 0.082, 0.124, 0.116, 0.116),
    (0.370, 0.080, 0.122, 0.114, 0.114),
    (0.320, 0.076, 0.112, 0.106, 0.106),
    (0.290, 0.070, 0.098, 0.094, 0.096),
    (0.270, 0.064, 0.086, 0.084, 0.086),
]
CUFF_Z0, CUFF_Z1 = 0.212, 0.282   # rolled cuff (about 7 cm), overlapping the boot top
LEG_N = 18


def leg_centre(z):
    if z >= S.KNEE.z:
        t = (S.HIP_JOINT.z - z) / (S.HIP_JOINT.z - S.KNEE.z)
        c = S.HIP_JOINT.lerp(S.KNEE, t)
    else:
        t = (S.KNEE.z - z) / (S.KNEE.z - S.ANKLE.z)
        c = S.KNEE.lerp(S.ANKLE, t)
    return V(c.x + 0.010, c.y + 0.004, z)


def _ridge(d, w):
    return math.exp(-(d / w) ** 2)


def fold_offset(z, a):
    """Drape folds (radial offset, metres) on the left leg: angle a (0 = outward +x, -pi/2 = front)."""
    c, s = math.cos(a), math.sin(a)
    front = max(0.0, -s)
    back = max(0.0, s)
    outer = max(0.0, c)
    inner = max(0.0, -c)
    off = 0.0
    # knee: stacked horizontal folds on the front, tilting down toward the outside
    for zc, amp in ((0.545, 0.009), (0.470, 0.012), (0.405, 0.010)):
        off += amp * front ** 1.5 * _ridge(z - (zc - 0.03 * c), 0.016)
    # back of the knee: deep creases
    for zc, amp in ((0.500, 0.010), (0.445, 0.008)):
        off -= amp * back ** 2 * _ridge(z - (zc + 0.02 * c), 0.012)
    # gathered fullness above the cuff: wavy bunching all round
    g = _ridge(z - 0.305, 0.030)
    off += 0.008 * g * math.sin(6 * a + 1.1) + 0.004 * g * math.sin(11 * a)
    # diagonal pull folds from the crotch across the inner thigh
    for k in range(2):
        zc = 0.70 - 0.07 * k + 0.05 * (a + math.pi / 2)
        off += 0.007 * inner * _ridge(z - zc, 0.018)
    # long outer seam: a soft vertical ridge down the outside of the thigh
    off += 0.004 * outer ** 6 * smoothstep(0.30, 0.45, z)
    return off


def _section(z):
    prof = [(r[0], r[1:]) for r in reversed(LEG_PROFILE)]
    return interp_profile(prof, z)


def leg_radius(z, a, folds=True):
    ri, ro, rf, rb = _section(z)
    c, s = math.cos(a), math.sin(a)
    rx = ro if c > 0 else ri
    ry = rf if s < 0 else rb
    r = 1.0 / math.sqrt((c / rx) ** 2 + (s / ry) ** 2)
    if folds:
        r += fold_offset(z, a)
    return r


def leg_surface(z, a, off=0.0):
    """Point on the outside of the left pant leg at height z, angle a, pushed off the surface."""
    c = leg_centre(z)
    r = leg_radius(z, a) + off
    return c + V(math.cos(a) * r, math.sin(a) * r, 0)


PANTS_N = 20          # vertices round one leg; index 0 = front centre, PANTS_N // 2 = back centre


def d_params(z):
    """Half-pelvis 'D' section of one leg above the crotch: (half_width, front, back, cy, sq).
    Waist to seat: the pelvis profile; seat to crotch: blends into the top of the baggy leg."""
    if z >= PANTS_TOP[-1][0]:
        return interp_profile([(r[0], r[1:]) for r in reversed(PANTS_TOP)], z)
    c = leg_centre(CROTCH_Z)
    ri, ro, rf, rb = _section(CROTCH_Z)
    at_crotch = (c.x + ro, rf - (c.y - 0.012), rb + (c.y - 0.012), 0.012, 2.0)
    top = PANTS_TOP[-1][1:]
    t = smoothstep(PANTS_TOP[-1][0], CROTCH_Z, z)
    return tuple(lerp(x0, x1, t) for x0, x1 in zip(top, at_crotch))


def d_point(z, k, n=PANTS_N):
    """Point k of the left leg's D section at height z: outer indices run front centre -> outer hip
    -> back centre on a superellipse; inner indices lie on the centre plane x = 0 (shared with the
    right leg, welded later)."""
    hw, fd, bd, cy, sq = d_params(z)
    half = n // 2
    if k <= half:
        a = -math.pi / 2 + TAU * k / n
        c, s = math.cos(a), math.sin(a)
        kk = 2.0 / sq
        ex = abs(c) ** kk
        ey = math.copysign(abs(s) ** kk, s)
        x = hw * ex
        y = cy + (fd if s < 0 else bd) * ey
        # long soft drape folds below the hip, fading out toward the waistband
        if z < 0.84:
            g = smoothstep(0.84, 0.76, z)
            r = 1.0 + g * (0.020 * math.sin(3 * a + 0.6) + 0.010 * math.sin(7 * a)) * min(1.0, ex * 4)
            x *= r
            y = cy + (y - cy) * r
        zz = z
        if z > 0.875:
            # low-rise: the waistband dips at the front centre and rides up over the hip bones
            zz -= 0.026 * (max(0.0, -s) ** 3) - 0.004 * abs(c)
        return V(x, y, zz)
    u = (k - half) / half       # inner line: back centre -> front centre
    zz = z
    if z > 0.875:
        zz -= 0.026 * u ** 3
    return V(0.0, lerp(cy + bd, cy - fd, u), zz)


def pants_point(z, k, n=PANTS_N):
    """Surface point k (see d_point) of the left pant leg at any height."""
    if z >= CROTCH_Z:
        return d_point(z, k, n)
    a = -math.pi / 2 + TAU * k / n
    leg = leg_surface(z, a)
    t = smoothstep(CROTCH_Z, CROTCH_Z - CROTCH_OPEN, z)
    if t >= 1.0:
        return leg
    top = d_point(CROTCH_Z, k, n)
    top.z = z
    return top.lerp(leg, t)


def pants_zs():
    zs = [0.895, 0.880, 0.862, 0.842, 0.818, 0.792, 0.765, 0.738, CROTCH_Z]
    z = CROTCH_Z
    for dz in (0.016, 0.018, 0.020, 0.022):
        z -= dz
        zs.append(z)
    while z > 0.62:
        z -= 0.032
        zs.append(z)
    while z > LEG_PROFILE[-1][0] + 0.02:
        z -= 0.024
        zs.append(z)
    zs.append(LEG_PROFILE[-1][0])
    return zs


def make_pants_half(side):
    """One half of the pants (built on her left; the right half is mirrored by the caller) from the
    waistband through the dropped crotch to the cuff, with a torn hole in the front - the knee on
    her right leg (R01), low on the shin on her left - a dark hole wall, skin showing behind and
    frayed threads."""
    from mx_geo import collection, get_material
    zs = pants_zs()
    n = PANTS_N
    bm = bmesh.new()
    grid = [[bm.verts.new(pants_point(z, k)) for k in range(n)] for z in zs]
    faces = {}
    for i in range(len(zs) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            f = bm.faces.new((grid[i][k], grid[i][k2], grid[i + 1][k2], grid[i + 1][k]))
            faces[(i, k)] = f
    # faces lying on the centre plane above the crotch are inside the garment
    inner = [f for f in bm.faces if all(abs(v.co.x) < 1e-6 for v in f.verts)]
    bmesh.ops.delete(bm, geom=inner, context='FACES_ONLY')
    faces = {key: f for key, f in faces.items() if f.is_valid}
    if side == 'R':
        tz, ta, tw, th = 0.475, -math.pi / 2 - 0.08, 0.090, 0.062
    else:
        tz, ta, tw, th = 0.330, -math.pi / 2 + 0.30, 0.052, 0.036
    rnd = random.Random(5 if side == 'R' else 9)

    def tear_r(theta):
        base = 1.0 / math.sqrt((math.cos(theta) / (tw * 0.5)) ** 2 + (math.sin(theta) / (th * 0.5)) ** 2)
        return base * (1.0 + 0.14 * math.sin(7 * theta + 0.6) + 0.08 * math.sin(13 * theta))

    rad = leg_radius(tz, ta)

    def local(p):
        c = leg_centre(p.z)
        a = math.atan2(p.y - c.y, p.x - c.x)
        da = (a - ta + math.pi) % TAU - math.pi
        return da * rad, p.z - tz

    kill = []
    for (i, k), f in faces.items():
        cen = f.calc_center_median()
        if cen.z > 0.62:
            continue
        u, w = local(cen)
        if math.hypot(u, w) < tear_r(math.atan2(w, u)) * 0.85:
            kill.append(f)
    boundary = {v for f in kill for v in f.verts}
    bmesh.ops.delete(bm, geom=kill, context='FACES_ONLY')
    rim = [v for v in boundary if v.is_valid and v.link_faces]
    for v in rim:
        u, w = local(v.co)
        th_ = math.atan2(w, u)
        r = tear_r(th_)
        v.co = leg_surface(tz + math.sin(th_) * r, ta + math.cos(th_) * r / rad)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    # hole wall: the torn edge turned inward, dark, so the hole reads as a hole and not a sticker
    rim_set = {v for v in rim if v.is_valid}
    edges = [e for e in bm.edges if e.is_boundary and all(v in rim_set for v in e.verts)]
    ext = bmesh.ops.extrude_edge_only(bm, edges=edges)
    for g in ext["geom"]:
        if isinstance(g, bmesh.types.BMVert):
            c = leg_centre(g.co.z)
            d = V(g.co.x - c.x, g.co.y - c.y, 0).normalized()
            g.co -= d * 0.007
    wall = {g for g in ext["geom"] if isinstance(g, bmesh.types.BMFace)}
    for f in bm.faces:
        f.material_index = 1 if f in wall else 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("pants_half")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("pants." + side, me)
    collection().objects.link(obj)
    me.materials.append(get_material('pants'))
    me.materials.append(get_material('dark'))
    me.shade_smooth()
    parts = [obj]
    # skin (knee/shin) showing through, just behind the hole
    rows = []
    for j in range(5):
        w = (j / 4 - 0.5) * th * 1.5
        rows.append([leg_surface(tz + w, ta + (q / 4 - 0.5) * tw * 1.5 / rad, -0.008) for q in range(5)])
    parts.append(loft("tear_skin", rows, 'skin', closed=False))
    # frayed threads hanging into the hole from its upper and lower edges
    for q in range(9):
        th_ = math.pi * (0.12 + 0.76 * q / 8) * (1 if q % 2 == 0 else -1)
        r = tear_r(th_)
        z = tz + math.sin(th_) * r
        a = ta + math.cos(th_) * r / rad
        p0 = leg_surface(z, a, -0.001)
        ln = rnd.uniform(0.009, 0.016)
        drop = V(rnd.uniform(-0.004, 0.004), 0, -ln if z > tz else ln * 0.7)
        p1 = p0 + drop * 0.5 + (leg_surface(z, a, -0.004) - p0)
        p2 = p0 + drop
        thread = tube_along("thread", [p0, p1, p2], lambda t: 0.0020 * (1 - 0.6 * t), n=3, up=V(0, -1, 0),
                            point_end=True)
        set_material(thread, 'pants')
        parts.append(thread)
    return parts


def _front_point(x, z, off):
    """Point on the front of the left pants half at height z whose x is nearest x (off = push out)."""
    best = None
    half = PANTS_N // 2
    for i in range(121):
        kf = (half / 2) * i / 120          # front quarter only
        k0 = int(math.floor(kf))
        p = pants_point(z, k0).lerp(pants_point(z, min(k0 + 1, half)), kf - k0)
        if best is None or abs(p.x - x) < abs(best.x - x):
            best = p
    return best + V(0, -off, 0)


def make_fly():
    """Fly placket: a stitched J-curve from the waistband down to the crotch seam, slightly to her
    left of centre (R01's diagonal fly), standing a little proud of the cloth."""
    ctrl = [(0.030, 0.866), (0.031, 0.830), (0.025, 0.790), (0.012, 0.758), (0.002, 0.738)]
    path = resample(catmull([_front_point(x, z, 0.0) for x, z in ctrl], 6), 16)
    placket = flat_strip("fly_placket", [p + V(0, -0.0015, 0) for p in path], lambda t: 0.011, 0.003,
                         lambda i, p: V(0, -1, 0), 'pants')
    stitch = flat_strip("fly_stitch", [p + V(-0.0035, -0.0032, 0) for p in path], lambda t: 0.0022, 0.0012,
                        lambda i, p: V(0, -1, 0), 'dark')
    return [placket, stitch]


def make_cuff(side):
    """Thick rolled cuff: a stacked fold above a fat roll. On her right leg the roll's edge carries
    R01's yellow band (a face strip of the same mesh, not a separate ring)."""
    c = leg_centre((CUFF_Z0 + CUFF_Z1) * 0.5)
    prof = [(0.058, CUFF_Z1 + 0.004), (0.074, CUFF_Z1), (0.081, CUFF_Z1 - 0.010), (0.083, CUFF_Z1 - 0.024),
            (0.081, CUFF_Z1 - 0.034), (0.077, CUFF_Z1 - 0.038), (0.081, CUFF_Z1 - 0.044),
            (0.085, CUFF_Z1 - 0.054), (0.083, CUFF_Z0 + 0.006), (0.075, CUFF_Z0), (0.060, CUFF_Z0 + 0.002)]
    n = 16
    rings = []
    for r, z in prof:
        ring = []
        for k in range(n):
            a = TAU * k / n - math.pi / 2
            wob = 1.0 + 0.035 * math.sin(5 * a + z * 90) + 0.02 * math.sin(9 * a)
            ring.append(c + V(math.cos(a) * r * wob, math.sin(a) * r * wob * 1.04, z - c.z))
        rings.append(ring)
    cuff = loft("pant_cuff." + side, rings, 'pants', closed=True)
    if side == 'R':
        band = slot_index(cuff, 'pants_graphic')
        for poly in cuff.data.polygons:
            if poly.center.z < CUFF_Z0 + 0.030 and poly.center.z > CUFF_Z0 + 0.004:
                poly.material_index = band
    return cuff


def make_cargo_pocket():
    parts = []
    zc, h = 0.640, 0.110
    a = 0.12
    p = leg_surface(zc, a, 0.002)
    out = V(math.cos(a), math.sin(a), 0)
    m = look_basis(p + out * 0.008, out, V(0, 0, 1))
    pocket = rounded_box("cargo_pocket", (0.078, h, 0.024), bevel=0.008, segments=2, material='pants',
                         matrix=m, smooth=True)
    flap = rounded_box("cargo_flap", (0.084, 0.032, 0.014), bevel=0.004, material='pants',
                       matrix=m @ Matrix.Translation(V(0, h * 0.5 - 0.010, 0.010)), smooth=True)
    snap = cylinder("cargo_snap", 0.0045, 0.006, n=8, material='metal',
                    matrix=m @ Matrix.Translation(V(0, h * 0.5 - 0.016, 0.018)))
    return [pocket, flap, snap]


def mirror_x_pt(p):
    return V(-p.x, p.y, p.z)


def _mitred_band(line, hw):
    """Outline of a constant-width band along a 2D polyline (mitred corners, no self-overlap)."""
    import mathutils
    L = [mathutils.Vector(p) for p in line]
    n = len(L)
    left, right = [], []
    for i in range(n):
        if i == 0:
            d = (L[1] - L[0]).normalized()
            nrm = mathutils.Vector((-d.y, d.x))
            off = nrm * hw
        elif i == n - 1:
            d = (L[-1] - L[-2]).normalized()
            nrm = mathutils.Vector((-d.y, d.x))
            off = nrm * hw
        else:
            d0 = (L[i] - L[i - 1]).normalized()
            d1 = (L[i + 1] - L[i]).normalized()
            n0 = mathutils.Vector((-d0.y, d0.x))
            n1 = mathutils.Vector((-d1.y, d1.x))
            m = (n0 + n1).normalized()
            off = m * (hw / max(0.35, m.dot(n0)))
        left.append(L[i] + off)
        right.append(L[i] - off)
    return [tuple(p) for p in left + right[::-1]]


def make_zigzag():
    """R01's bold yellow zig-zag: three sharp angular legs running diagonally down the front/outer
    side of her right shin into the cuff's yellow band. Laid out in metres on the cloth (arc
    length round the leg, height), then wrapped onto the right leg."""
    R = 0.112
    line = [(-0.055, 0.468), (0.085, 0.428), (-0.030, 0.370), (0.095, 0.322), (0.045, 0.268)]
    pts = [(u / R, z) for u, z in _mitred_band(line, 0.013)]

    def surf(a, z, off):
        return mirror_x_pt(leg_surface(z, -math.pi / 2 + a, off))
    return wrap_decal("zigzag", pts, surf, 0.0022, 'pants_graphic', cuts=5)


def wrap_decal(name, pts2d, surface, thickness, material, cuts=4):
    """Extruded 2D polygon in (angle, z) space wrapped onto a surface(a, z, offset) -> point."""
    bm = bmesh.new()
    bot = [bm.verts.new(V(a, z, 0.0)) for a, z in pts2d]
    top = [bm.verts.new(V(a, z, 1.0)) for a, z in pts2d]
    n = len(pts2d)
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((bot[k], bot[k2], top[k2], top[k]))
    long_edges = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 0.5]
    bmesh.ops.subdivide_edges(bm, edges=long_edges, cuts=cuts)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    for v in bm.verts:
        a, z, w = v.co.x, v.co.y, v.co.z
        v.co = surface(a, z, -0.001 + (thickness + 0.001) * w)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = obj_from_bmesh(name, bm, material, smooth=False)
    return obj


def build_pants():
    """One continuous garment: both halves joined and welded on the centre line (front fly line,
    back seam and the crotch seam), so the hips flow into the legs with no separate panel."""
    from mx_geo import join
    left = make_pants_half('L')
    right = []
    for p in make_pants_half('R'):
        q = mirror_copy(p, p.name + ".m")
        bpy.data.objects.remove(p)
        right.append(q)
    body = join([left[0], right[0]], "pants")
    bm = bmesh.new()
    bm.from_mesh(body.data)
    seam = [v for v in bm.verts if abs(v.co.x) < 1e-5]
    bmesh.ops.remove_doubles(bm, verts=seam, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body.data)
    bm.free()
    body.data.shade_smooth()
    tag(body, "pants")
    lextra = left[1:] + [make_cuff('L')] + make_cargo_pocket()
    for p in lextra:
        tag(p, "leg.L")
    cr = make_cuff('R')
    q = mirror_copy(cr, cr.name + ".m")
    bpy.data.objects.remove(cr)
    rextra = right[1:] + [q]
    for p in rextra:
        p["wspec"] = "leg.R"
    zz = make_zigzag()
    zz["wspec"] = "leg.R"
    fly = make_fly()
    for p in fly:
        tag(p, "pants")
    return [body] + lextra + rextra + [zz] + fly


# --------------------------------------------------------------------------------------------
# belt
# --------------------------------------------------------------------------------------------

def belt_z(x):
    # slung low and tilted: lower on her right where the Walkman hangs
    return 0.862 - 0.018 * (-x / 0.16)


def make_belt():
    n = 32
    rings = []
    for dz in (-0.018, -0.016, 0.016, 0.018):
        ring = []
        for k in range(n):
            a = TAU * k / n - math.pi / 2
            c, s = math.cos(a), math.sin(a)
            kk = 2.0 / 2.2
            ex = math.copysign(abs(c) ** kk, c)
            ey = math.copysign(abs(s) ** kk, s)
            infl = 0.010 if abs(dz) < 0.017 else 0.006
            x = (0.149 + infl) * ex
            y = 0.012 + ((0.093 if s < 0 else 0.099) + infl) * ey
            ring.append(V(x, y, belt_z(x) + dz))
        rings.append(ring)
    belt = loft("belt", rings, 'belt', closed=True, smooth=True)
    belt.data.set_sharp_from_angle(angle=math.radians(50))
    parts = [belt]
    # buckle (front centre, slightly to her left)
    x0 = 0.018
    p = V(x0, 0.012 - 0.093 - 0.016, belt_z(x0))
    m = look_basis(p, V(0, -1, 0), V(0, 0, 1))
    parts.append(rounded_box("belt_buckle", (0.050, 0.042, 0.010), bevel=0.003, material='metal', matrix=m))
    parts.append(rounded_box("belt_buckle_in", (0.030, 0.022, 0.012), bevel=0.002, material='belt',
                             matrix=m @ Matrix.Translation(V(0, 0, 0.002))))
    parts.append(rounded_box("belt_buckle_tab", (0.014, 0.010, 0.016), bevel=0.002,
                             material='walkman', matrix=m @ Matrix.Translation(V(0.0, 0.0, 0.004))))
    # loops/rivets around the belt
    for ang in (-0.2, 0.6, 1.2, 2.2, 2.9, 3.6):
        a = ang - math.pi / 2
        c, s = math.cos(a), math.sin(a)
        kk = 2.0 / 2.2
        ex = math.copysign(abs(c) ** kk, c)
        ey = math.copysign(abs(s) ** kk, s)
        q = V(0.160 * ex, 0.012 + (0.105 if s > 0 else 0.103) * ey, 0)
        q.z = belt_z(q.x)
        out = V(q.x, q.y - 0.012, 0).normalized()
        parts.append(rounded_box("belt_loop", (0.012, 0.044, 0.006), bevel=0.0, material='belt',
                                 matrix=look_basis(q, out, V(0, 0, 1))))
    for p in parts:
        tag(p, "pelvis")
    return parts


# --------------------------------------------------------------------------------------------
# boots
# --------------------------------------------------------------------------------------------
# R01's massive high-tops: taupe upper with dark-brown overlays (ankle panel, heel counter, padded
# collar), a rounded broad toe box, a very thick cream lug sole that flares out, yellow laces
# criss-crossing five eyelet rows with two loose loops, and yellow warning-triangle patches on the
# tongue and the outer side.

BOOT_RINGS = [  # (z, centre_y, half_length, half_width)
    (0.046, -0.074, 0.152, 0.070),
    (0.062, -0.074, 0.152, 0.071),
    (0.076, -0.071, 0.148, 0.071),
    (0.090, -0.062, 0.138, 0.068),
    (0.100, -0.052, 0.127, 0.066),
    (0.110, -0.040, 0.112, 0.063),
    (0.122, -0.022, 0.092, 0.060),
    (0.136, -0.008, 0.078, 0.058),
    (0.156, 0.002, 0.071, 0.058),
    (0.180, 0.006, 0.068, 0.058),
    (0.208, 0.009, 0.068, 0.060),
    (0.236, 0.012, 0.070, 0.062),
]
BOOT_N = 22
SOLE_TOP = 0.050


def boot_ring(z, cy, hl, hw, n, off=0.0, cx=0.0, flare=0.0):
    pts = []
    for k in range(n):
        a = TAU * k / n - math.pi / 2   # k=0 points to the toe (-Y)
        c, s = math.cos(a), math.sin(a)
        e = 0.62 if s < 0 else 0.85    # broad, rounded toe box; rounder heel
        ex = math.copysign(abs(c) ** e, c)
        ey = math.copysign(abs(s) ** e, s)
        w = hw * (1.0 - 0.10 * max(0.0, s))
        pts.append(V(cx + (w + off + flare) * ex, cy + (hl + off + flare) * ey, z))
    return pts


def boot_profile(z):
    prof = [(r[0], r[1:]) for r in BOOT_RINGS]
    return interp_profile(prof, z)


def boot_surface(z, a, off=0.0):
    """Point on the boot upper (left foot) at height z and angle a (a=-pi/2 is the toe)."""
    cy, hl, hw = boot_profile(z)
    c, s = math.cos(a), math.sin(a)
    e = 0.62 if s < 0 else 0.85
    ex = math.copysign(abs(c) ** e, c)
    ey = math.copysign(abs(s) ** e, s)
    w = hw * (1.0 - 0.10 * max(0.0, s))
    return V(S.ANKLE.x + (w + off) * ex, cy + (hl + off) * ey, z)


def make_boot():
    cx = S.ANKLE.x
    n = BOOT_N
    rings = [boot_ring(z, cy, hl, hw, n, 0.0, cx) for z, cy, hl, hw in BOOT_RINGS]
    upper = loft("boot_upper.L", rings, 'shoes', closed=True)
    dark = slot_index(upper, 'shoes_dark')
    for poly in upper.data.polygons:
        c = poly.center
        rel = c - V(cx, 0, c.z)
        ang = math.atan2(rel.y, rel.x)          # -pi/2 = toe
        # R01 two-tone: light toe box and vamp, dark-brown quarter panel and heel counter
        quarter = c.y > -0.040 + 0.25 * (c.z - 0.10) and abs(ang + math.pi / 2) > 0.45
        if quarter:
            poly.material_index = dark
    parts = [upper]
    # padded, rolled collar round the top of the shaft
    top_z, cy, hl, hw = BOOT_RINGS[-1]
    cpath = [V(p.x, p.y, top_z + 0.004) for p in boot_ring(top_z, cy, hl, hw, 16, 0.002, cx)]
    cpath.append(cpath[0])
    collar = tube_along("boot_collar", cpath, lambda t: 0.011, n=5, up=V(0, 0, 1), ry_fn=lambda t: 0.014,
                        cap_start=False, cap_end=False)
    set_material(collar, 'shoes_dark')
    parts.append(collar)
    # massive cream lug sole: flared, two grooves, a jagged dark tread
    srings = []
    for z, off, lug in ((0.000, 0.004, 1), (0.006, 0.010, 1), (0.012, 0.012, 0), (0.016, 0.008, 0),
                        (0.020, 0.012, 0), (0.032, 0.012, 0), (0.036, 0.007, 0), (0.040, 0.010, 0),
                        (0.050, 0.004, 0)):
        ring = boot_ring(z, -0.074, 0.152, 0.070, 24, off, cx)
        if lug:
            for k, p in enumerate(ring):
                d = V(p.x - cx, p.y + 0.074, 0)
                if d.length > 1e-6:
                    ring[k] = p + d.normalized() * (0.004 if k % 2 == 0 else -0.001)
        srings.append(ring)
    sole = loft("boot_sole.L", srings, 'shoes_sole', closed=True, cap_start=True, cap_end=True)
    sole.data.set_sharp_from_angle(angle=math.radians(40))
    d2 = slot_index(sole, 'shoes_dark')
    for poly in sole.data.polygons:
        if poly.center.z < 0.009:
            poly.material_index = d2
    parts.append(sole)
    # raised tongue rising above the collar, with a yellow warning-triangle patch
    fy = lambda z: boot_surface(z, -math.pi / 2).y
    tpath = [V(cx, fy(0.112) + 0.002, 0.112), V(cx, fy(0.150) - 0.002, 0.150), V(cx, fy(0.200) - 0.004, 0.200),
             V(cx, fy(0.236) - 0.012, 0.252)]
    tongue = flat_strip("boot_tongue", resample(catmull(tpath, 4), 8), lambda t: 0.048 - 0.004 * t, 0.007,
                        lambda i, p: V(0, -1, 0.25), 'shoes')
    parts.append(tongue)
    tri = [(0.0, 0.017), (-0.016, -0.011), (0.016, -0.011)]
    tp = V(cx, fy(0.236) - 0.018, 0.236)
    mt = look_basis(tp, V(0, -1, 0.35), V(0, 0, 1))
    mt = mt @ Matrix.Scale(-1, 4, V(1, 0, 0))
    parts.append(extrude_polygon("tongue_badge", tri, 0.003, mt, 'shoes_lace'))
    parts.append(extrude_polygon("tongue_badge_in", [(x * 0.42, y * 0.42 - 0.001) for x, y in tri], 0.0045, mt,
                                 'shoes_dark'))
    # laces: five eyelet rows, crossed tube strands bowing slightly off the tongue
    rows = (0.108, 0.136, 0.164, 0.192, 0.218)
    def eyelet(z, sgn):
        a = -math.pi / 2 + sgn * 0.42
        return boot_surface(z, a, 0.003)
    for i in range(len(rows) - 1):
        for sgn in (1, -1):
            a = eyelet(rows[i], sgn)
            b = eyelet(rows[i + 1], -sgn)
            mid = (a + b) * 0.5 + V(0, -0.007, 0)
            lace = tube_along("lace", resample(catmull([a, mid, b], 4), 4), lambda t: 0.0034, n=4,
                              up=V(0, -1, 0))
            set_material(lace, 'shoes_lace')
            parts.append(lace)
    # two loose loops and two dangling ends at the top
    top = eyelet(rows[-1], 0) + V(0, -0.006, 0.004)
    for sx in (-1, 1):
        loop = [top, top + V(sx * 0.022, -0.016, 0.014), top + V(sx * 0.038, -0.012, -0.004),
                top + V(sx * 0.016, -0.008, -0.008), top]
        lo = tube_along("lace_loop", resample(catmull(loop, 5), 7), lambda t: 0.0034, n=4, up=V(0, -1, 0))
        set_material(lo, 'shoes_lace')
        end = [top, top + V(sx * 0.010, -0.012, -0.026), top + V(sx * 0.020, -0.016, -0.056)]
        en = tube_along("lace_end", resample(catmull(end, 5), 5), lambda t: 0.0032, n=4, up=V(0, -1, 0))
        set_material(en, 'shoes_lace')
        parts += [lo, en]
    # yellow triangle patch with a dark inner mark on the outer side
    sp = boot_surface(0.150, 0.15, 0.001)
    ms = look_basis(sp, V(1, 0.15, 0).normalized(), V(0, 0, 1))
    parts.append(extrude_polygon("boot_badge", [(x * 1.1, y * 1.1) for x, y in tri], 0.003, ms, 'shoes_lace'))
    parts.append(extrude_polygon("boot_badge_in", [(x * 0.42, y * 0.42 - 0.001) for x, y in tri], 0.0045, ms,
                                 'shoes_dark'))
    for p in parts:
        tag(p, "foot.L")
    return parts


def build_boots():
    b = make_boot()
    r = [mirror_copy(p, p.name + ".R") for p in b]
    for p in r:
        p["wspec"] = "foot.R"
    return b + r


def build_outfit():
    return (make_top() + make_chest_strap() + make_choker() + build_jacket() + build_pants()
            + make_belt() + build_boots())
