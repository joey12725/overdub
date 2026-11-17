"""Set pieces: arch (ruined masonry / plated gate) and rune_panel (inscribed wall slab)."""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Vector

import decor_lib as L
from decor_lib import M
from decor_nature import broken_block


def voussoir(a0, a1, r_in, r_out, depth, centre, mat="stone", bev=0.025, gap=0.012):
    """One wedge stone of an arch: an annular sector in the XZ plane (angles in radians from +X),
    extruded along Y, with a small mortar gap trimmed off each side."""
    ga = gap / r_in
    a0, a1 = a0 + ga / 2, a1 - ga / 2
    pts = []
    n = 3
    for k in range(n + 1):
        a = a0 + (a1 - a0) * k / n
        pts.append((math.cos(a) * r_out, math.sin(a) * r_out))
    for k in range(n, -1, -1):
        a = a0 + (a1 - a0) * k / n
        pts.append((math.cos(a) * r_in, math.sin(a) * r_in))
    obj = L.prism(pts, depth, loc=centre, mat=mat, bev=bev, seg=1)
    return obj


def arch_upper():
    """A ruined masonry arch about 2 units tall (R03 modules / tile set): coursed pillars on
    plinths, a ring of wedge stones whose right shoulder has fallen (two stones lie at its foot),
    moss and vines hanging from the crown, a pink tag-star on one pillar block."""
    rng = random.Random(4)
    parts = []
    D = 0.44
    span = 1.0                       # clear opening
    pw = 0.34                        # pillar width
    px = span / 2 + pw / 2
    spring = 1.2                     # springing line height
    # Plinths.
    for sx in (-1, 1):
        parts.append(L.box((pw + 0.1, D + 0.08, 0.14), (sx * px, 0, 0.07), mat="stone_dark", bev=0.025))
    # Coursed pillar blocks with jitter; alternate heights.
    for sx in (-1, 1):
        z = 0.14
        k = 0
        while z < spring - 0.01:
            h = min(0.26 if k % 2 == 0 else 0.22, spring - z)
            jx = rng.uniform(-0.015, 0.015)
            jr = rng.uniform(-2.5, 2.5)
            mat = "stone" if (k + (sx > 0)) % 3 else "stone_light"
            parts.append(L.box((pw - 0.012 + rng.uniform(-0.01, 0.02), D - rng.uniform(0, 0.03), h - 0.012),
                               (sx * px + jx, rng.uniform(-0.01, 0.01), z + h / 2), rot=(0, 0, jr), mat=mat,
                               bev=0.025))
            z += h
            k += 1
        # Impost block at the springing line.
        parts.append(L.box((pw + 0.06, D + 0.04, 0.1), (sx * px, 0, spring + 0.05), mat="stone_light", bev=0.02))
    # Arch ring: 9 voussoirs from the left springing to the right; stone 6 has fallen out.
    r_in, r_out = span / 2, span / 2 + pw
    n = 9
    centre = (0, 0, spring + 0.1)
    for i in range(n):
        a0 = math.pi - math.pi * i / n
        a1 = math.pi - math.pi * (i + 1) / n
        if i == 6:
            continue
        mat = "stone_light" if i == 4 else ("stone" if i % 2 else "stone_dark")
        v = voussoir(a1, a0, r_in, r_out, D - 0.02 if i != 4 else D + 0.04, centre, mat=mat)
        parts.append(v)
    # Fallen stones at the right foot.
    parts.append(broken_block(51, (0.32, 0.36, 0.22), (0.62, -0.42, 0.0), rot_z=24, mat="stone"))
    parts.append(broken_block(52, (0.26, 0.3, 0.2), (0.86, -0.18, 0.0), rot_z=-40, mat="stone_dark", tilt=(0, 12)))
    parts.append(L.rock(53, 0.14, (0.42, -0.5, 0), rot_z=40, mat="stone_dark"))
    # Graffiti star block: a pink stencil star on the left pillar front.
    from decor_containers import star
    parts.append(star(0.1, (-px, -D / 2 - 0.002, 0.62), mat="graffiti", depth=0.012))
    # Overgrowth: a mat of leaves on the crown and a few strands hanging from the left side.
    specs = []
    crown = Vector(centre)
    for k in range(40):
        a = math.pi * (0.25 + 0.6 * rng.random())
        p = crown + Vector((math.cos(a) * (r_out + 0.01), rng.uniform(-D / 2, D / 2), math.sin(a) * (r_out + 0.01)))
        u = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.3))
        n_ = Vector((math.cos(a), 0, math.sin(a)))
        ln = rng.uniform(0.14, 0.2)
        specs.append((L.basis(u, n_, p), ln, ln * 0.8, rng.randint(0, 1)))
    for sx0, ln_ in ((-0.68, 0.9), (-0.5, 0.6), (-0.2, 0.45)):
        x0 = sx0
        top = crown.z + math.sqrt(max(0.0, r_out ** 2 - x0 ** 2)) - 0.03 if abs(x0) < r_out else spring + 0.1
        pts = [(x0, -D / 2 - 0.02, top), (x0 + 0.03, -D / 2 - 0.05, top - ln_ * 0.5), (x0 - 0.02, -D / 2 - 0.04, top - ln_)]
        parts.append(L.tube(pts, 0.012, mat="stem", res=1))
        for k in range(8):
            t = (k + 0.5) / 8
            p = Vector(pts[0]).lerp(Vector(pts[2]), t) + Vector((0.02 * math.sin(k), -0.01, 0))
            side = 1 if k % 2 else -1
            specs.append((L.basis(Vector((side * 0.8, -0.3, -0.5)), Vector((0, -1, 0.3)), p), 0.15, 0.12,
                          rng.randint(0, 1)))
    # Weeds at the foot of each pillar.
    for sx in (-1, 1):
        base = Vector((sx * (px - 0.18), -D / 2 - 0.05, 0.0))
        for k in range(7):
            a = k / 7 * math.pi * 2
            specs.append((L.basis(Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 1)), Vector((math.cos(a), math.sin(a), 0.3)),
                                  base), rng.uniform(0.14, 0.2), 0.08, k % 2))
    parts.append(L.leaves_obj(specs, ["foliage", "foliage_dark"]))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=30)]


def arch_lower():
    """A plated gate frame (R04 modules): two heavy riveted pillars with recessed neon strips and
    hazard-banded feet, a chamfered lintel carrying an inscription plate, corner brackets."""
    from decor_containers import paneled_box, rivets
    parts = []
    D = 0.46
    span = 1.0
    pw = 0.34
    px = span / 2 + pw / 2
    H = 2.0
    lint_h = 0.38
    for sx in (-1, 1):
        x = sx * px
        parts.append(paneled_box((pw, D, H - lint_h), (x, 0, (H - lint_h) / 2), body="metal", frame="metal_dark",
                                 inset=0.05, depth=0.02, faces=("x", "y"), bev=0.02, name="pillar"))
        parts.append(L.hazard_box((pw + 0.06, D + 0.06, 0.2), (x, 0, 0.1), period=0.1, bev=0.012))
        # Neon strip down the inner-front edge of the pillar and a row of glowing slots.
        parts.append(L.box((0.04, 0.03, H - lint_h - 0.5), (x - sx * (pw / 2 - 0.06), -D / 2 - 0.006, (H - lint_h) / 2 + 0.1),
                           mat="neon_glow"))
        for k in range(4):
            parts.append(L.box((0.1, 0.02, 0.04), (x + sx * 0.04, -D / 2 - 0.008, 0.45 + k * 0.22), mat="warm_glow"))
        parts += rivets([(x + dx, -D / 2 - 0.004, z) for dx in (-0.12, 0.12) for z in (0.3, H - lint_h - 0.1)], r=0.015)
        # Brackets bracing the lintel.
        parts.append(L.prism([(0.0, 0.0), (0.0, 0.16), (-0.16, 0.16)], D - 0.06,
                             loc=(sx * (span / 2), 0, H - lint_h - 0.16), rot=(0, 0, 0) if sx > 0 else (0, 0, 180),
                             mat="metal_dark", bev=0.01))
    # Lintel.
    parts.append(L.box((span + 2 * pw + 0.12, D + 0.06, lint_h), (0, 0, H - lint_h / 2), mat="metal_dark", bev=0.04,
                       seg=1, taper=(0.97, 0.92)))
    parts.append(L.box((span + 0.2, 0.02, lint_h - 0.14), (0, -D / 2 - 0.03, H - lint_h / 2), mat="metal", bev=0.006))
    # Inscription on the lintel plate: glyph strokes in rune glow.
    rng = random.Random(8)
    x = -0.5
    while x < 0.5:
        ln = rng.choice((0.12, 0.16, 0.08))
        ang = rng.choice((0, 0, 45, -45, 90))
        parts.append(L.box((0.016, 0.012, ln), (x, -D / 2 - 0.042, H - lint_h / 2 + rng.uniform(-0.03, 0.03)),
                           rot=(0, ang, 0), mat="rune_glow"))
        x += rng.uniform(0.05, 0.09)
    # Top cornice and an orange warning lamp at the centre.
    parts.append(L.box((span + 2 * pw + 0.2, D + 0.12, 0.06), (0, 0, H + 0.03), mat="metal", bev=0.015))
    parts.append(L.cyl(0.06, 0.08, loc=(0, -0.05, H + 0.1), mat="warm_glow", n=12))
    parts.append(L.cyl(0.075, 0.03, loc=(0, -0.05, H + 0.06), mat="paint_yellow", n=12))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=35)]


# ───────────────────────────── rune panel ─────────────────────────────

# Glyph alphabet on a 3 x 4 anchor grid (columns 0..2, rows 0..3, row 0 at the bottom). Each glyph
# is a list of strokes between anchors; the shapes echo the R04 close-ups (angular, spine-based).
GLYPHS = [
    [((1, 0), (1, 3)), ((1, 3), (0, 2)), ((1, 3), (2, 2)), ((0, 1), (2, 1))],          # arrow spine
    [((0, 0), (0, 3)), ((0, 3), (2, 2)), ((2, 2), (0, 1)), ((0, 1), (2, 0))],          # R-like
    [((0, 0), (1, 3)), ((1, 3), (2, 0)), ((0, 0), (2, 0)), ((1, 0), (1, 1))],          # delta
    [((0, 3), (2, 3)), ((1, 3), (1, 0)), ((0, 1), (1, 2)), ((2, 1), (1, 2))],          # tau with wings
    [((0, 0), (0, 3)), ((2, 0), (2, 3)), ((0, 2), (2, 1))],                           # N-like
    [((0, 3), (2, 3)), ((2, 3), (0, 0)), ((0, 0), (2, 0)), ((1, 1), (2, 1))],          # Z hook
]


def glyph_strokes(idx, origin, cell, width, depth, y, mat="rune_glow"):
    out = []
    ox, oz = origin
    for (c0, r0), (c1, r1) in GLYPHS[idx % len(GLYPHS)]:
        p0 = Vector((ox + c0 * cell, oz + r0 * cell))
        p1 = Vector((ox + c1 * cell, oz + r1 * cell))
        d = p1 - p0
        ln = d.length + width
        ang = math.degrees(math.atan2(d.y, d.x))
        mid = (p0 + p1) / 2
        out.append(L.box((ln, depth, width), (mid.x, y, mid.y), rot=(0, -ang, 0), mat=mat))
    return out


def rune_panel():
    """An inscribed slab (R04 modules / close-ups): plinth, bevelled slab with a sunk field in
    which three glyphs and a ring are inlaid as glowing strokes, a capping stone, side clamps."""
    parts = []
    W, H, D = 0.72, 1.46, 0.22
    parts.append(L.box((W + 0.12, D + 0.12, 0.12), (0, 0, 0.06), mat="metal_dark", bev=0.025))
    slab = L.box((W, D, H), (0, 0, 0.12 + H / 2), mat="metal", bev=0.03, seg=1)
    # Sink a field into the front face.
    bm = bmesh.new()
    bm.from_mesh(slab.data)
    front = [f for f in bm.faces if f.normal.y < -0.9 and f.calc_area() > 0.5]
    if front:
        bmesh.ops.inset_individual(bm, faces=front, thickness=0.07, depth=-0.03)
    bm.to_mesh(slab.data)
    bm.free()
    slab.data.materials.append(M("metal_dark"))
    for p in slab.data.polygons:
        if p.normal.y < -0.9 and abs(p.center.y + D / 2 - 0.03) < 0.005:
            p.material_index = 1
    parts.append(slab)
    yf = -D / 2 + 0.03            # sunk field plane
    # Ring glyph at the top, three glyphs below.
    parts.append(L.torus(0.13, 0.018, loc=(0, yf - 0.006, 0.12 + H - 0.26), rot=(90, 0, 0), mat="rune_glow", n=28, m=4,
                         square=True))
    parts.append(L.box((0.03, 0.012, 0.26), (0, yf - 0.006, 0.12 + H - 0.26), mat="rune_glow"))
    cell = 0.1
    for k, idx in enumerate((2, 1, 4)):
        oz = 0.12 + H - 0.62 - k * 0.36
        parts += glyph_strokes(idx, (-cell, oz), cell, 0.03, 0.012, yf - 0.006)
    # Border line just inside the field.
    for sx in (-1, 1):
        parts.append(L.box((0.016, 0.012, H - 0.3), (sx * (W / 2 - 0.1), yf - 0.006, 0.12 + H / 2), mat="rune_glow"))
    # Capstone and side clamps.
    parts.append(L.box((W + 0.1, D + 0.08, 0.1), (0, 0, 0.12 + H + 0.05), mat="metal_dark", bev=0.025,
                       taper=(0.9, 0.85)))
    for sx in (-1, 1):
        for z in (0.4, 1.2):
            parts.append(L.box((0.05, D + 0.04, 0.09), (sx * (W / 2 + 0.01), 0, z), mat="paint_yellow", bev=0.01))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=35)]
