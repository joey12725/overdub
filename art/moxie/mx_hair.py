"""Moxie's hair and headphones.

Hair (R01/R02: soft, voluminous, messy dark-brown hair): a cap shell over the cranium (a darker
underlayer near its edge gives depth where the locks part), then rounded strands swept along
Catmull-Rom paths. Every strand is a smooth tube with an elliptical section: thick at the root,
bulging through the middle and tapering to a fine point, so the toon shader bands it softly
instead of faceting it.
  - fringe: eight curved, overlapping clumps of uneven length that part over her left eye and
    stop at the brow line, lifted clear of the forehead so they do not shadow the eyes;
  - side locks framing the face in front of the headphone cushions;
  - rounded back and nape clumps whose tips flick outward;
  - crown clumps radiating from the whorl and one soft curl lying across the crown;
  - two high, scrappy pigtails (CHAR-07) on red ties: fourteen strands each that fan out from the
    tie, arc outward and droop, with curled tips, plus thin flyaways.

Headphones: big yellow over-ear cans (CHAR-05) with a band over the crown, sliders, yokes, dark
cushions and a warning-sign triangle badge on each cup (thick dark outline, a fill in material
headphones_glow so the game can tint it per cassette, and a small dark inner mark), the same motif
as the boot patches.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import mx_skel as S
from mx_body import head_shape, tag
from mx_geo import (TAU, V, basis, catmull, cylinder, extrude_polygon, interp_profile, lathe,
                    lerp, loft, look_basis, mirror_copy, resample, ring_points, rounded_box,
                    set_material, slot_index, smoothstep, solidify, subsurf, tube_along)


def head_dir(az, el):
    a, e = math.radians(az), math.radians(el)
    return V(math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))


def head_point(az, el, off=0.0):
    d = head_dir(az, el)
    return S.SKULL_C + head_shape(d) + d * off


def radial_up(_i, p):
    return (p - S.SKULL_C).normalized()


def strand(name, ctrl, width, thick=None, up=radial_up, samples=10, n=7, root=0.70, peak=0.35,
           material='hair'):
    """Rounded, tapered hair strand: `root` x width at the root, full width at `peak`, then a
    smooth taper to a point. width: across the strand; thick: along the `up` direction."""
    thick = thick if thick is not None else width * 0.55
    path = resample(catmull(ctrl, 8), samples)

    def env(t):
        grow = root + (1.0 - root) * math.sin(min(t / peak, 1.0) * math.pi * 0.5)
        fall = 1.0 - smoothstep(peak, 1.0, t)
        return grow * (fall ** 0.45) if t < 1 else 0.0

    obj = tube_along(name, path, lambda t: max(thick * 0.5 * env(t), 1e-4), n=n, up=up,
                     ry_fn=lambda t: max(width * 0.5 * env(t), 1e-4), point_end=True, cap_start=True)
    set_material(obj, material)
    return obj


# --------------------------------------------------------------------------------------------
# cap
# --------------------------------------------------------------------------------------------

def hairline(az):
    """Elevation (deg) of the cap edge around the head (az 0 = front, 180 = back)."""
    a = abs(((az + 180) % 360) - 180)
    return interp_profile([(0, 32), (35, 26), (70, 2), (100, -16), (140, -48), (180, -64)], a)


def make_cap():
    naz, nr = 32, 9
    rings = []
    for i in range(nr):
        u = (i + 1) / nr
        ring = []
        for k in range(naz):
            az = 360 * k / naz
            hl = hairline(az)
            el = 90 - (90 - hl) * u
            a = abs(((az + 180) % 360) - 180)
            back = smoothstep(60, 170, a)
            top = smoothstep(-10, 60, el)
            off = 0.010 + 0.014 * back * top + 0.007 * top
            # soft scalloped edge (no spikes): the edge ring tucks in toward the scalp
            if i == nr - 1:
                off -= 0.004
            ring.append(head_point(az, el, off))
        rings.append(ring)
    obj = loft("hair_cap", rings, 'hair', closed=True, cap_start=True,
               cap_start_point=head_point(0, 90, 0.030))
    # darker underlayer near the edge: shows between the locks and under the fringe (depth)
    dark = slot_index(obj, 'hair_dark')
    for poly in obj.data.polygons:
        d = (poly.center - S.SKULL_C).normalized()
        el = math.degrees(math.asin(max(-1.0, min(1.0, d.z))))
        az = math.degrees(math.atan2(d.x, -d.y))
        if el < hairline(az) + 26:
            poly.material_index = dark
    return obj


# --------------------------------------------------------------------------------------------
# locks
# --------------------------------------------------------------------------------------------

def surface_path(az0, el0, az1, el1, off0, off1, n=5, bulge=0.0):
    pts = []
    for i in range(n):
        t = i / (n - 1)
        pts.append(head_point(lerp(az0, az1, t), lerp(el0, el1, t),
                              lerp(off0, off1, t) + bulge * math.sin(t * math.pi)))
    return pts


BROW_Z = 1.490   # fringe tips stop at the brow line (eyes 1.425-1.466, brows 1.474-1.489)


def make_fringe():
    """Eight curved clumps parting over her left eye (+x): a long sweep from the part across her
    right side, shorter clumps falling to her left; tips curl and lift off the brow."""
    locks = []
    # (az root, el root, az tip, z tip, width, curl direction (+1 = toward her left))
    bangs = [
        (14, 66, -6, BROW_Z + 0.004, 0.058, -1),
        (0, 64, -22, BROW_Z + 0.000, 0.056, -1),
        (-14, 60, -38, BROW_Z + 0.008, 0.052, -1),
        (-28, 56, -52, BROW_Z - 0.012, 0.046, -1),
        (24, 64, 22, BROW_Z + 0.010, 0.050, 1),
        (32, 60, 40, BROW_Z + 0.002, 0.048, 1),
        (42, 54, 52, BROW_Z - 0.014, 0.042, 1),
        (6, 70, 8, BROW_Z + 0.024, 0.044, 1),     # short top layer over the part
    ]
    for i, (a0, e0, a1, ztip, w, curl) in enumerate(bangs):
        # find the elevation whose point on the head reaches ztip at azimuth a1
        el1 = 0.0
        for k in range(120):
            el = -10 + k * 0.5
            if head_point(a1, el).z >= ztip:
                el1 = el
                break
        ctrl = surface_path(a0, e0, lerp(a0, a1, 0.75), lerp(e0, el1, 0.7), 0.020, 0.020, n=4, bulge=0.010)
        tip = head_point(a1, el1, 0.017)   # lifted clear of the brow
        side = V(math.cos(math.radians(a1)), math.sin(math.radians(a1)), 0) * curl
        ctrl += [tip, tip + side * 0.012 + V(0, -0.008, 0.004)]
        locks.append(strand("bang%d" % i, ctrl, w, thick=w * 0.40, samples=9, n=7, root=0.85, peak=0.40))
    # side locks framing the face, in front of the headphone cushions, down to the jaw
    for s in (1, -1):
        for j, (a0, e0, a1, e1, w) in enumerate(((58, 44, 64, -36, 0.034), (70, 34, 78, -24, 0.030))):
            ctrl = surface_path(s * a0, e0, s * a1, e1, 0.018, 0.020, n=5, bulge=0.008)
            ctrl.append(ctrl[-1] + V(-s * 0.012, -0.012, -0.018))
            locks.append(strand("side%d%s" % (j, "L" if s > 0 else "R"), ctrl, w, thick=w * 0.45,
                                samples=9, n=7, root=0.8))
    return locks


def make_back():
    locks = []
    rnd = random.Random(7)
    # rounded back clumps covering the cap's edge, flicking outward at the nape
    for k, az in enumerate(range(96, 268, 19)):
        hl = hairline(az)
        e0 = hl + 34
        e1 = hl - 14 - 8 * rnd.random()
        flare = 0.018 + 0.016 * rnd.random()
        ctrl = surface_path(az, e0, az + rnd.uniform(-6, 6), e1, 0.020, 0.022, n=4, bulge=0.008)
        d = head_dir(az, 0)
        ctrl.append(ctrl[-1] + V(d.x, d.y, 0) * flare + V(0, 0, -0.016))
        locks.append(strand("back%d" % k, ctrl, 0.050, thick=0.022, samples=8, n=6, root=0.85, peak=0.4))
    # nape clumps over the back of the neck
    for k, az in enumerate((158, 180, 202)):
        ctrl = surface_path(az, -26, az + (8 if k != 1 else 0) * (1 if k == 2 else -1), -74, 0.018, 0.014,
                            n=4, bulge=0.006)
        ctrl.append(ctrl[-1] + V(0, 0.012, -0.016))
        locks.append(strand("nape%d" % k, ctrl, 0.052, thick=0.020, samples=8, n=7, root=0.85))
    # crown clumps radiating from the whorl (break the smooth cap at the game camera's angle)
    whorl = 145
    for k, (az, len_el) in enumerate(((whorl - 55, 40), (whorl - 10, 44), (whorl + 40, 40), (whorl + 95, 36))):
        ctrl = [head_point(whorl, 78, 0.024)]
        for t in (0.35, 0.7, 1.0):
            ctrl.append(head_point(lerp(whorl, az, t), lerp(78, len_el, t), 0.024 + 0.006 * math.sin(t * math.pi)))
        locks.append(strand("crown%d" % k, ctrl, 0.048, thick=0.014, samples=8, n=6, root=0.6, peak=0.4))
    # one soft curl lying across the crown (replaces the antenna-like hoop)
    p0 = head_point(20, 72, 0.026)
    ctrl = [p0, head_point(40, 76, 0.026), head_point(62, 72, 0.026), head_point(72, 64, 0.026),
            head_point(62, 58, 0.028)]
    locks.append(strand("crown_curl", ctrl, 0.016, thick=0.009, samples=9, n=6, root=0.8))
    return locks


def pigtail_layout():
    """Tie position and the bone chain of her left pigtail (the right is mirrored); mx_rig builds
    the pigtail bones from it and weights the strands along it."""
    tie = head_point(116, 46, 0.026)
    out = V(1, 0.30, 0).normalized()
    chain = [tie,
             tie + out * 0.050 + V(0, 0.008, 0.040),
             tie + out * 0.108 + V(0, 0.022, 0.032),
             tie + out * 0.150 + V(0, 0.040, -0.030),
             tie + out * 0.162 + V(0, 0.052, -0.120)]
    return tie, chain


def make_pigtail():
    tie, chain = pigtail_layout()
    parts = []
    rnd = random.Random(11)
    # gathered bulb where the hair is pulled up into the tie
    root = head_point(116, 60, 0.012)
    bulb = strand("pig_root", [head_point(116, 30, 0.010), root, tie + V(0.004, 0.003, 0.004),
                               tie + V(0.020, 0.006, 0.016)], 0.070, thick=0.050,
                  up=lambda i, p: V(0, 0, 1), samples=7, n=8, root=0.75, peak=0.45)
    parts.append(bulb)
    out = (chain[2] - chain[0]).normalized()
    v1 = V(0, 0, 1)
    v1 = (v1 - out * v1.dot(out)).normalized()
    v2 = out.cross(v1).normalized()
    n_main = 10
    for i in range(n_main):
        phi = TAU * i / n_main + rnd.uniform(-0.25, 0.25)
        spread = (v1 * math.cos(phi) + v2 * math.sin(phi))
        reach = rnd.uniform(0.78, 1.06)
        fan = rnd.uniform(0.012, 0.022)
        droop = rnd.uniform(-0.02, 0.03)
        curl = rnd.choice((-1, 1)) * rnd.uniform(0.010, 0.022)
        ctrl = [chain[0] + spread * 0.006]
        for j, c in enumerate(chain[1:], start=1):
            f = j / (len(chain) - 1)
            p = chain[0] + (c - chain[0]) * reach + spread * fan * (0.6 + 1.6 * f)
            p.z -= droop * f * f
            ctrl.append(p)
        # curled tip: hooks sideways/back on itself
        tipd = (ctrl[-1] - ctrl[-2]).normalized()
        side = tipd.cross(V(0, 1, 0))
        if side.length < 1e-4:
            side = V(1, 0, 0)
        side.normalize()
        ctrl.append(ctrl[-1] + tipd * 0.016 + side * curl + V(0, 0, 0.006))
        w = rnd.uniform(0.044, 0.056)

        def up(_i, p, axis=chain[2]):
            d = p - axis
            return d if d.length > 1e-4 else V(0, 0, 1)
        parts.append(strand("pig%d" % i, ctrl, w, thick=w * 0.70, up=up, samples=8, n=6, root=0.55,
                            peak=0.45))
    # thin flyaways that break the silhouette
    for i in range(2):
        phi = TAU * (i + 0.25) / 2 + rnd.uniform(-0.3, 0.3)
        spread = (v1 * math.cos(phi) + v2 * math.sin(phi))
        reach = rnd.uniform(0.45, 0.65)
        ctrl = [chain[0] + spread * 0.010]
        for j, c in enumerate(chain[1:4], start=1):
            f = j / 3
            ctrl.append(chain[0] + (c - chain[0]) * reach + spread * (0.026 + 0.030 * f) + V(0, 0, -0.010 * f))
        parts.append(strand("pig_fly%d" % i, ctrl, 0.014, thick=0.008, samples=7, n=5, root=1.0, peak=0.3))
    # hair tie: a red band around the gathered base
    tie_dir = (chain[1] - chain[0]).normalized()
    m = look_basis(tie + tie_dir * 0.004, tie_dir, V(0, 0, 1))
    band = lathe("pig_tie", [(0.020, -0.007), (0.024, -0.005), (0.025, 0.0), (0.024, 0.005), (0.020, 0.007)],
                 n=12, material='strap', cap_start=False, cap_end=False)
    band.data.transform(m)
    parts.append(band)
    return parts


def face_point(x, z, off):
    """Point on the front of the head at (x, z), pushed `off` along the surface normal."""
    best = None
    for i in range(61):
        for j in range(61):
            az = -70 + 140 * i / 60
            el = -40 + 80 * j / 60
            p = head_point(az, el)
            d = (p.x - x) ** 2 + (p.z - z) ** 2
            if p.y < S.SKULL_C.y and (best is None or d < best[0]):
                best = (d, az, el)
    _, az, el = best
    return head_point(az, el, off)


def make_lashes():
    """Small dark lash flicks at the outer eye corners: give the painted eyes a silhouette in
    three-quarter and side views."""
    parts = []
    for s in (1, -1):
        for k, (dx, dz, w) in enumerate(((0.000, 0.000, 0.0095), (0.004, -0.007, 0.0065))):
            p0 = face_point(s * (0.062 + dx), 1.4565 + dz, 0.0008)
            p1 = face_point(s * (0.071 + dx), 1.4615 + dz, 0.0026)
            p2 = face_point(s * (0.078 + dx), 1.4680 + dz, 0.0050)
            lo = strand("lash", [p0, p1, p2], w, thick=0.0024, samples=5, n=4, root=1.0, peak=0.2,
                        material='eye')
            parts.append(lo)
    return parts


def build_hair():
    parts = [make_cap()] + make_fringe() + make_back() + make_lashes()
    for p in parts:
        tag(p, "head")
    pig = make_pigtail()
    for p in pig:
        tag(p, "pigtail.L")
    tag(pig[0], "pigroot.L")
    mirrored = [mirror_copy(p, p.name + ".R") for p in pig]
    for p in mirrored:
        p["wspec"] = p["wspec"][:-2] + ".R"
    return parts + pig + mirrored

# --------------------------------------------------------------------------------------------
# headphones
# --------------------------------------------------------------------------------------------

CUP_C = V(0.118, 0.014, 1.440)   # cup centre (left); axis along +X
CUP_R = 0.047


def make_cup():
    parts = []
    ax = basis(V(0, 1, 0), V(0, 0, 1), V(1, 0, 0), CUP_C)   # local Z -> +X (outward)
    cushion = lathe("cushion", [(0.020, -0.010), (0.038, -0.012), (0.044, -0.002),
                                (0.040, 0.010), (0.022, 0.010)], n=14, material='headphones_dark')
    cushion.data.transform(ax)
    parts.append(cushion)
    shell = lathe("cup_shell", [(0.040, 0.008), (0.046, 0.012), (0.048, 0.022), (0.047, 0.032),
                                (0.043, 0.038), (0.034, 0.041), (0.0005, 0.042)], n=16, material='headphones',
                  cap_start=True, cap_end=False)
    shell.data.transform(ax)
    shell.data.set_sharp_from_angle(angle=math.radians(50))
    parts.append(shell)
    # dark rim ring on the outer face
    rim = lathe("cup_rim", [(0.036, 0.0405), (0.040, 0.0415), (0.040, 0.0445), (0.036, 0.0455),
                            (0.034, 0.0440)], n=14, material='headphones_dark', cap_start=False, cap_end=False)
    rim.data.transform(ax)
    parts.append(rim)
    # triangle graphic (pointing up, R01), raised and bevelled
    tri = []
    for k in range(3):
        a = math.pi / 2 + TAU * k / 3
        tri.append((math.cos(a) * 0.025, math.sin(a) * 0.025))
    # extrude in the cup's outward frame: local X = -Y world (toward the face) so the triangle reads
    # point-up from the side
    m = basis(V(0, -1, 0), V(0, 0, 1), V(1, 0, 0), CUP_C + V(0.0405, 0, -0.002))
    outer = extrude_polygon("cup_tri_border", [(x * 1.50, y * 1.50 - 0.002) for x, y in tri], 0.003, m,
                            'headphones_dark', bevel=0.0)
    parts.append(outer)
    m2 = basis(V(0, -1, 0), V(0, 0, 1), V(1, 0, 0), CUP_C + V(0.0425, 0, -0.002))
    glow = extrude_polygon("cup_tri", tri, 0.003, m2, 'headphones_glow', bevel=0.0)
    parts.append(glow)
    # small dark inner mark (warning-sign styling, as on the boot patches)
    m3 = basis(V(0, -1, 0), V(0, 0, 1), V(1, 0, 0), CUP_C + V(0.0445, 0, -0.006))
    parts.append(extrude_polygon("cup_tri_mark", [(x * 0.36, y * 0.36) for x, y in tri], 0.0025, m3,
                                 'headphones_dark', bevel=0.0))
    # yoke: a fork from the band slider down around the cup
    yoke_pts = [CUP_C + V(0.018, 0, CUP_R + 0.030), CUP_C + V(0.024, -0.030, CUP_R + 0.008),
                CUP_C + V(0.024, -0.050, 0.0)]
    for sgn in (1, -1):
        pts = [V(p.x, CUP_C.y + (p.y - CUP_C.y) * sgn, p.z) for p in yoke_pts]
        y = tube_along("yoke", resample(catmull(pts, 6), 7), lambda t: 0.0045, n=5, up=V(1, 0, 0),
                       ry_fn=lambda t: 0.0065)
        set_material(y, 'headphones')
        parts.append(y)
    pivot = cylinder("pivot", 0.008, 0.012, n=10, material='headphones_dark',
                     matrix=Matrix.Translation(CUP_C + V(0.024, 0, 0)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    for sgn in (1, -1):
        p2 = cylinder("pivot", 0.0075, 0.010, n=8, material='headphones_dark',
                      matrix=Matrix.Translation(CUP_C + V(0.024, sgn * 0.050, 0.0)) @
                      Matrix.Rotation(math.pi / 2, 4, 'Y'))
        parts.append(p2)
    pivot.name = "pivot_unused"
    bpy.data.objects.remove(pivot)
    # slider block where the band meets the yoke
    slider = rounded_box("slider", (0.016, 0.026, 0.040), bevel=0.004, material='headphones_dark',
                         matrix=Matrix.Translation(CUP_C + V(0.016, 0, CUP_R + 0.045)))
    parts.append(slider)
    return parts


def band_path():
    pts = []
    for k in range(17):
        a = math.pi * k / 16  # 0 = left side, pi = right side
        x = math.cos(a) * 0.137
        z = 1.530 + math.sin(a) * 0.098
        x *= 1.0 - 0.08 * math.sin(a) ** 2
        pts.append(V(x, 0.016, z))
    return pts


def make_band():
    path = band_path()
    outer = tube_along("band", path, lambda t: 0.0055, n=8, up=lambda i, p: V(p.x, 0, p.z - 1.47),
                       ry_fn=lambda t: 0.015, cap_start=True, cap_end=True)
    set_material(outer, 'headphones')
    pad_path = [p for p in path[3:14]]
    inner = tube_along("band_pad", [S.SKULL_C + (p - S.SKULL_C) * 0.955 for p in pad_path], lambda t: 0.005, n=8,
                       up=lambda i, p: V(p.x, 0, p.z - 1.47), ry_fn=lambda t: 0.012)
    set_material(inner, 'headphones_dark')
    return [outer, inner]


def build_headphones():
    cup = make_cup()
    parts = make_band() + cup + [mirror_copy(p, p.name + ".R") for p in cup]
    # the right cup's triangle must still point up and read the same: mirroring keeps it
    for p in parts:
        tag(p, "head")
    return parts
