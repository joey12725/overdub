"""Floor tiles: floor_solid, floor_cracked, floor_grate, floor_overgrown, floor_rune.

Each tile is 1 x 1 with its walkable top at z = 0 and its body hanging to z = -0.2 (TILE_THICK in
the game is 0.24; the extra few centimetres are covered by the cliff skirt and walls). Slabs/plates
are inset by half a joint from the tile border, so neighbouring tiles always meet on a full-width
joint: any tile tiles against any other on all four sides. Layouts are deliberately asymmetric so
the game's quarter-turn rotations give visibly different variants.

UPPER: sun-bleached masonry slabs with chipped corners, cracks cut as grooves, moss in seams.
LOWER: riveted metal plates with recessed panels, etched glow runes, glowing grates.
"""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Matrix, Vector

import common as C

T = 0.2          # tile body thickness below the walkable top
GAP = 0.026      # joint width between slabs (and, split in two, at the tile border)
FLOOR_PIECES = ('floor_solid', 'floor_cracked', 'floor_grate', 'floor_overgrown', 'floor_rune')


# ───────────────────────────── shared tile parts ─────────────────────────────

def bed(m, name='bed', top=-0.045):
    """The grout / sub-floor that shows at the bottom of every joint."""
    return C.box_mm(name, (-0.5 + GAP / 2, -0.5 + GAP / 2, -T), (0.5 - GAP / 2, 0.5 - GAP / 2, top), m, bevel=0.0)


def corner_chips(rng: random.Random, size, prob: float, depth=(0.03, 0.07)):
    """Planes that knock the top corners off a box of `size` (box-local, centred)."""
    sx, sy, sz = size
    chips = []
    for cx in (-1, 1):
        for cy in (-1, 1):
            if rng.random() < prob:
                d = rng.uniform(*depth)
                n = Vector((cx, cy, rng.uniform(0.9, 1.6))).normalized()
                corner = Vector((cx * sx / 2, cy * sy / 2, sz / 2))
                chips.append((corner - n * d, n))
    return chips


def slab(name, rect, mat, rng, top=0.0, bottom=-T, chip=0.35, bevel=0.02, jitter=0.01, top_mat=None, rot=0.0):
    """A masonry slab / metal plate over rect = (x0, y0, x1, y1) in tile space (-0.5..0.5)."""
    x0, y0, x1, y1 = rect
    x0 += GAP / 2
    y0 += GAP / 2
    x1 -= GAP / 2
    y1 -= GAP / 2
    t = top - rng.uniform(0.0, jitter)
    size = (x1 - x0, y1 - y0, t - bottom)
    centre = ((x0 + x1) / 2, (y0 + y1) / 2, (t + bottom) / 2)
    ob = C.box(name, size, centre, mat, bevel=bevel, chips=corner_chips(rng, size, chip), top_mat=top_mat)
    if rot:
        ob.rotation_euler.z = rot
    return ob


def ribbon(name, pts, width, z0, z1, mat):
    """A groove cutter: one box per polyline segment (overlapping at joints), joined."""
    parts = []
    for i in range(len(pts) - 1):
        a, b = Vector((*pts[i][:2], 0)), Vector((*pts[i + 1][:2], 0))
        d = b - a
        L = d.length
        if L < 1e-5:
            continue
        ang = math.atan2(d.y, d.x)
        mid = (a + b) / 2
        parts.append(C.box(f'{name}_{i}', (L + width, width, z1 - z0), (mid.x, mid.y, (z0 + z1) / 2), mat, rot_z=ang))
    return C.join(parts, name) if parts else None


def zigzag(rng, a, b, steps=5, amp=0.035):
    """A crack path from a to b with sideways kinks."""
    a, b = Vector(a), Vector(b)
    d = b - a
    n = Vector((-d.y, d.x)).normalized()
    pts = [a]
    for i in range(1, steps):
        t = i / steps
        pts.append(a + d * t + n * rng.uniform(-amp, amp))
    pts.append(b)
    return pts


def crack(name, rng, a, b, mat, width=0.022, depth=0.035, top=0.0, steps=5, amp=0.035, branch=True):
    """Crack cutter: a kinked groove, optionally with one short branch."""
    pts = zigzag(rng, a, b, steps, amp)
    cutters = [ribbon(name, pts, width, top - depth, top + 0.05, mat)]
    if branch and len(pts) > 3:
        k = rng.randint(1, len(pts) - 2)
        p = pts[k]
        d = (Vector(b) - Vector(a)).normalized()
        n = Vector((-d.y, d.x)) * rng.choice((-1, 1))
        q = p + (n * 0.8 + d * 0.5).normalized() * rng.uniform(0.09, 0.15)
        cutters.append(ribbon(name + '_br', zigzag(rng, p, q, 2, 0.015), width * 0.75, top - depth * 0.8, top + 0.05, mat))
    return C.join(cutters, name)


def annulus(name, r_in, r_out, z0, z1, mat, segs=28, center=(0, 0)):
    bm = bmesh.new()
    rings = []
    for z in (z0, z1):
        for r in (r_in, r_out):
            rings.append([bm.verts.new((center[0] + math.cos(i / segs * math.tau) * r,
                                        center[1] + math.sin(i / segs * math.tau) * r, z)) for i in range(segs)])
    bi, bo, ti, to = rings
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((bo[i], bo[j], to[j], to[i]))      # outer wall
        bm.faces.new((ti[i], ti[j], bi[j], bi[i]))      # inner wall
        bm.faces.new((to[i], to[j], ti[j], ti[i]))      # top
        bm.faces.new((bi[i], bi[j], bo[j], bo[i]))      # bottom
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return C.obj_from_bm(name, bm, [mat])


def star_strokes(r, points=5, rot=math.pi / 2):
    """A pentagram as one closed polyline (the boards' recurring star motif)."""
    vs = [(math.cos(rot + i * math.tau / points) * r, math.sin(rot + i * math.tau / points) * r) for i in range(points)]
    order = [vs[(i * 2) % points] for i in range(points + 1)]
    return [order]


def glyph_strokes(rng, w, h, n=3):
    """An angular rune glyph inside a w x h box centred at 0: a spine plus 2-3 strokes snapped to
    a 2 x 3 lattice, so glyphs read as one engineered alphabet rather than random scratches."""
    xs = (-w / 2, 0.0, w / 2)
    ys = (-h / 2, -h / 6, h / 6, h / 2)
    strokes = [[(0.0, ys[0]), (0.0, ys[3])]] if rng.random() < 0.6 else [[(xs[0], ys[0]), (xs[0], ys[3])]]
    for _ in range(n):
        kind = rng.randrange(4)
        y = rng.choice(ys)
        y2 = rng.choice(ys)
        if kind == 0:
            strokes.append([(xs[0], y), (xs[2], y)])
        elif kind == 1:
            strokes.append([(xs[0], y), (0.0, y2), (xs[2], y)])
        elif kind == 2:
            strokes.append([(xs[2], ys[0]), (xs[2], y)])
        else:
            strokes.append([(xs[0], y), (xs[2], y2)])
    return strokes


def rivets_rect(name, rect, z, m, inset=0.045, r=0.018, every=None):
    """Rivets at the corners (and optionally along the edges) of a plate rect, sitting on z."""
    x0, y0, x1, y1 = rect
    pts = [(x0 + inset, y0 + inset), (x1 - inset, y0 + inset), (x0 + inset, y1 - inset), (x1 - inset, y1 - inset)]
    if every:
        for x0e, y0e, x1e, y1e in (((x0, y0 + inset, x1, y0 + inset)), ((x0, y1 - inset, x1, y1 - inset))):
            L = x1e - x0e
            n = int(L / every)
            for i in range(1, n):
                pts.append((x0e + L * i / n, y0e))
    return [C.rivet(f'{name}_{i}', (p[0], p[1], z), (0, 0, 1), m, radius=r, height=r * 0.6) for i, p in enumerate(pts)]


def inset_panel(ob, inset=0.05, depth=0.012, mat_index=None):
    """Recess the top face of a plate object: bmesh inset + push down (a pressed panel)."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    top = max((f for f in bm.faces if f.normal.z > 0.99), key=lambda f: f.calc_area())
    res = bmesh.ops.inset_region(bm, faces=[top], thickness=inset, depth=0.0, use_even_offset=True)
    bmesh.ops.translate(bm, vec=Vector((0, 0, -depth)), verts=list(top.verts))
    inner = bmesh.ops.inset_region(bm, faces=[top], thickness=0.006, depth=0.0)
    if mat_index is not None:
        top.material_index = mat_index
    bm.to_mesh(me)
    bm.free()
    return ob


# ───────────────────────────── UPPER (masonry) ─────────────────────────────

# Slab layouts per tile in tile space. Running-bond and irregular so rotation reads as a new tile.
UP_LAYOUT_SOLID = [(-0.5, -0.5, 0.1, -0.05), (0.1, -0.5, 0.5, -0.05), (-0.5, -0.05, -0.15, 0.5),
                   (-0.15, -0.05, 0.5, 0.22), (-0.15, 0.22, 0.5, 0.5)]
UP_LAYOUT_CRACK = [(-0.5, -0.5, -0.05, 0.0), (-0.05, -0.5, 0.5, -0.12), (-0.05, -0.12, 0.5, 0.5),
                   (-0.5, 0.0, -0.05, 0.5)]


def stone_mat(m, rng):
    r = rng.random()
    return m('stone_light') if r < 0.3 else m('stone_dark') if r < 0.5 else m('stone')


def upper_solid(m, rng):
    parts = [bed(m('grout'))]
    for i, rect in enumerate(UP_LAYOUT_SOLID):
        parts.append(slab(f's{i}', rect, stone_mat(m, rng), rng, chip=0.45))
    # One small moss cushion in a joint keeps the "sun-bleached ruin" feel without noise.
    parts.append(C.moss_pad('moss', rng, (-0.15, -0.05, -0.012), 0.06, 0.035, m('moss')))
    return parts


def upper_cracked(m, rng):
    parts = [bed(m('grout'))]
    rects = list(UP_LAYOUT_CRACK)
    # Slab 2 is shattered into three shards around a point, each sunk and tilted a little.
    shattered = rects.pop(2)
    for i, rect in enumerate(rects):
        s = slab(f's{i}', rect, stone_mat(m, rng), rng, chip=0.5)
        if i in (0, 1):
            x0, y0, x1, y1 = rect
            a = (x0 + 0.06, rng.uniform(y0 + 0.05, y1 - 0.05))
            b = (x1 - 0.06, rng.uniform(y0 + 0.05, y1 - 0.05))
            C.boolean(s, [crack(f'c{i}', rng, a, b, m('grout'))])
        parts.append(s)
    parts += shards(m, rng, shattered, m('stone'), count=3)
    # Grit in the broken corner.
    for k in range(3):
        parts.append(C.rock(f'grit{k}', rng, (0.05, 0.04, 0.03), (0.27 + rng.uniform(-0.12, 0.12), 0.2 + rng.uniform(-0.15, 0.15), -0.03),
                            m('stone_dark')))
    parts.append(C.blade_tuft('tuft', rng, (0.2, 0.06, -0.03), m('grass'), height=0.1, blades=6))
    return parts


def shards(m, rng, rect, mat, count=3, sink=(0.01, 0.04), top=0.0):
    """Break a slab rect into `count` wedge shards meeting at an interior point; each is the slab box
    clipped by two half-planes, pulled apart by the joint width, sunk and tilted."""
    x0, y0, x1, y1 = rect
    x0 += GAP / 2
    y0 += GAP / 2
    x1 -= GAP / 2
    y1 -= GAP / 2
    cx = rng.uniform(x0 + (x1 - x0) * 0.35, x0 + (x1 - x0) * 0.65)
    cy = rng.uniform(y0 + (y1 - y0) * 0.35, y0 + (y1 - y0) * 0.65)
    base = rng.uniform(0, math.tau)
    angs = sorted((base + i * math.tau / count + rng.uniform(-0.4, 0.4)) for i in range(count))
    out = []
    size = (x1 - x0, y1 - y0, top + T)
    centre = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (top - T) / 2))
    for i in range(count):
        a0 = angs[i]
        a1 = angs[(i + 1) % count] + (math.tau if i == count - 1 else 0)
        bm = C.bm_box(size)
        C._bevel_all(bm, 0.018)
        p = Vector((cx, cy, 0)) - centre
        for a, sgn in ((a0, -1), (a1, 1)):
            # Normal points away from the wedge interior; offset by half a joint.
            n = Vector((-math.sin(a), math.cos(a), 0)) * sgn
            C.bm_chip(bm, p + n * (GAP / 2), n)
        for co, no in corner_chips(rng, size, 0.4):
            C.bm_chip(bm, co, no)
        mid = (a0 + a1) / 2
        tilt_axis = Vector((-math.sin(mid), math.cos(mid), 0))
        drop = rng.uniform(*sink)
        mtx = Matrix.Translation(centre + Vector((0, 0, -drop))) @ Matrix.Rotation(rng.uniform(0.02, 0.06), 4, tilt_axis)
        bmesh.ops.transform(bm, matrix=mtx, verts=bm.verts)
        # Sunk shards must not poke out of the tile's underside (it sits on the cliff skirt / walls).
        C.bm_chip(bm, (0, 0, -T), (0, 0, -1))
        out.append(C.obj_from_bm(f'shard{i}', bm, [mat]))
    return out


def upper_grate(m, rng):
    parts = []
    inner = 0.33
    # Four border stones in a pinwheel so the frame is asymmetric under rotation.
    rects = [(-0.5, -0.5, 0.5 - 0.17, -inner), (0.5 - 0.17, -0.5, 0.5, 0.5 - 0.0), (-0.5, inner, 0.5 - 0.17, 0.5),
             (-0.5, -inner, -inner, inner)]
    for i, r in enumerate(rects):
        parts.append(slab(f'b{i}', r, stone_mat(m, rng), rng, chip=0.4))
    # Pit under the grate: dark void with a lip.
    parts.append(C.box_mm('pit', (-inner, -inner, -T), (0.33, inner, -0.17), m('void')))
    # Grate: rusty metal frame + bars.
    fx0, fx1 = -inner + 0.005, 0.33 - 0.005
    fw = 0.035
    frame = [
        C.box_mm('f0', (fx0, fx0, -0.05), (fx1, fx0 + fw, -0.004), m('metal_dark'), bevel=0.008),
        C.box_mm('f1', (fx0, fx1 - fw, -0.05), (fx1, fx1, -0.004), m('metal_dark'), bevel=0.008),
        C.box_mm('f2', (fx0, fx0, -0.05), (fx0 + fw, fx1, -0.004), m('metal_dark'), bevel=0.008),
        C.box_mm('f3', (fx1 - fw, fx0, -0.05), (fx1, fx1, -0.004), m('metal_dark'), bevel=0.008),
    ]
    parts += frame
    n = 5
    span = fx1 - fx0 - 2 * fw
    for i in range(1, n):
        t = fx0 + fw + span * i / n
        parts.append(C.box_mm(f'bx{i}', (t - 0.012, fx0 + fw - 0.002, -0.045), (t + 0.012, fx1 - fw + 0.002, -0.012), m('metal'), bevel=0.004))
        parts.append(C.box_mm(f'by{i}', (fx0 + fw - 0.002, t - 0.012, -0.04), (fx1 - fw + 0.002, t + 0.012, -0.016), m('metal'), bevel=0.004))
    # Rust bloom on one frame corner.
    parts.append(C.box_mm('rust', (fx0 - 0.002, fx0 - 0.002, -0.03), (fx0 + 0.09, fx0 + fw + 0.002, -0.003), m('rust'), bevel=0.006))
    parts.append(C.blade_tuft('tuft', rng, (-0.42, 0.42, -0.02), m('grass'), height=0.09, blades=5))
    return parts


def upper_overgrown(m, rng):
    parts = [bed(m('soil'), top=-0.05)]
    rects = [(-0.5, -0.5, 0.15, 0.0), (0.15, -0.5, 0.5, 0.08), (-0.5, 0.0, -0.08, 0.5)]
    for i, r in enumerate(rects):
        s = slab(f's{i}', r, stone_mat(m, rng), rng, chip=0.6, jitter=0.02)
        parts.append(s)
    # The fourth slab is gone: a soil bed with grass and a leafy plant.
    parts.append(C.box_mm('soil', (-0.08 + GAP / 2, 0.08 + GAP / 2 - 0.08, -T), (0.5 - GAP / 2, 0.5 - GAP / 2, -0.04), m('soil'), bevel=0.02))
    parts.append(slab('half', (0.18, 0.08, 0.5, 0.3), m('stone_dark'), rng, top=-0.02, chip=0.8))
    parts.append(C.leaf_clump('plant', rng, (0.16, 0.24, -0.04), 0.19, m('grass'), count=8))
    for k, (x, y) in enumerate([(-0.02, 0.36), (0.34, 0.36), (0.06, 0.12), (-0.08, 0.02), (0.15, -0.02)]):
        parts.append(C.blade_tuft(f't{k}', rng, (x, y, -0.04), m('grass') if k % 2 else m('leaf_dark'), height=rng.uniform(0.1, 0.17), blades=7))
    # Moss creeping over the remaining slabs' edges.
    parts.append(C.moss_pad('m0', rng, (-0.1, -0.02, -0.006), 0.12, 0.035, m('moss')))
    parts.append(C.moss_pad('m1', rng, (0.17, -0.3, -0.006), 0.08, 0.03, m('moss')))
    parts.append(C.moss_pad('m2', rng, (-0.33, 0.2, -0.006), 0.07, 0.03, m('moss')))
    return parts


def upper_rune(m, rng):
    parts = [bed(m('grout'))]
    # Central inscribed slab with a border of narrow stones.
    border = [(-0.5, -0.5, 0.32, -0.32), (0.32, -0.5, 0.5, 0.32), (-0.32, 0.32, 0.5, 0.5), (-0.5, -0.32, -0.32, 0.5)]
    for i, r in enumerate(border):
        parts.append(slab(f'b{i}', r, stone_mat(m, rng), rng, chip=0.35))
    centre = slab('centre', (-0.32, -0.32, 0.32, 0.32), m('stone_light'), rng, chip=0.0, jitter=0.0)
    cut = rune_circle(m, 0.25, 0.0)
    C.boolean(centre, [cut])
    parts.append(centre)
    return parts


def rune_circle(m, r, top, ticks=True):
    """Ring + star + tick marks as one glow-floored groove cutter."""
    depth = 0.014
    cutters = [annulus('ring', r - 0.028, r, top - depth, top + 0.05, m('rune_glow'), segs=32)]
    for k, pl in enumerate(star_strokes(r * 0.72)):
        cutters.append(ribbon(f'star{k}', pl, 0.026, top - depth, top + 0.05, m('rune_glow')))
    if ticks:
        for i in range(8):
            a = i * math.tau / 8 + math.pi / 8
            p0 = (math.cos(a) * (r + 0.02), math.sin(a) * (r + 0.02))
            p1 = (math.cos(a) * (r + 0.05), math.sin(a) * (r + 0.05))
            cutters.append(ribbon(f'tick{i}', [p0, p1], 0.02, top - depth, top + 0.05, m('rune_glow')))
    return C.join(cutters, 'rune_cut')


# ───────────────────────────── LOWER (metal) ─────────────────────────────

def plate(name, rect, m, rng, mat=None, recess=True, rivet=True, jitter=0.0):
    x0, y0, x1, y1 = rect
    ob = slab(name, rect, mat or m('plate_light'), rng, chip=0.0, bevel=0.016, jitter=jitter)
    parts = [ob]
    if recess:
        C.apply_modifiers(ob)
        ob.data.materials.append(m('plate'))
        inset_panel(ob, inset=0.055, depth=0.012, mat_index=len(ob.data.materials) - 1)
    if rivet:
        parts += rivets_rect(name + '_r', (x0 + GAP / 2, y0 + GAP / 2, x1 - GAP / 2, y1 - GAP / 2), 0.0, m('metal'), inset=0.03, r=0.016)
    return parts


def hazard_stripes(name, x0, x1, y0, y1, z, m, period=0.1, slant=0.05, height=0.006):
    """Diagonal yellow / dark stripes inlaid in a rect (flush paint bands as thin prisms)."""
    parts = [C.box_mm(name + '_bg', (x0, y0, z - height), (x1, y1, z), m('hazard_dark'))]
    x = x0 - (y1 - y0)
    i = 0
    while x < x1:
        pts = [(x, y0), (x + period / 2, y0), (x + period / 2 + slant * (y1 - y0) / 0.1, y1), (x + slant * (y1 - y0) / 0.1, y1)]
        # Clip the parallelogram to the rect.
        poly = clip_poly(pts, x0, y0, x1, y1)
        if len(poly) >= 3:
            parts.append(C.prism(f'{name}_{i}', poly, z - height, z + 0.0015, m('paint_yellow')))
        x += period
        i += 1
    return parts


def clip_poly(pts, x0, y0, x1, y1):
    def clip(poly, inside, inter):
        out = []
        for i in range(len(poly)):
            a, b = poly[i - 1], poly[i]
            ia, ib = inside(a), inside(b)
            if ib:
                if not ia:
                    out.append(inter(a, b))
                out.append(b)
            elif ia:
                out.append(inter(a, b))
        return out

    def ix(xc):
        return lambda a, b: (xc, a[1] + (b[1] - a[1]) * (xc - a[0]) / (b[0] - a[0]))

    poly = list(pts)
    poly = clip(poly, lambda p: p[0] >= x0, ix(x0))
    if poly:
        poly = clip(poly, lambda p: p[0] <= x1, ix(x1))
    return poly


def lower_solid(m, rng):
    parts = [bed(m('seam'))]
    parts += plate('p0', (-0.5, -0.5, 0.15, 0.5), m, rng)
    parts += plate('p1', (0.15, -0.5, 0.5, 0.05), m, rng, recess=False)
    parts += plate('p2', (0.15, 0.05, 0.5, 0.5), m, rng, recess=False, mat=m('plate'))
    # A hazard-painted corner on the small plate gives the tile a readable orientation.
    parts += hazard_stripes('hz', 0.15 + GAP / 2 + 0.02, 0.5 - GAP / 2 - 0.02, -0.5 + GAP / 2 + 0.05, -0.5 + GAP / 2 + 0.16, 0.0005, m)
    # A floor vent slot on the dark plate.
    parts.append(C.box_mm('vent', (0.22, 0.2, -0.03), (0.43, 0.36, 0.001), m('seam'), bevel=0.006))
    for i in range(4):
        y = 0.215 + i * 0.04
        parts.append(C.box_mm(f'slat{i}', (0.23, y, -0.012), (0.42, y + 0.016, -0.002), m('metal'), bevel=0.003))
    return parts


def lower_cracked(m, rng):
    parts = [bed(m('seam'))]
    # Left plate: fractured, crack grooves glowing faintly from the machinery beneath.
    p0 = plate('p0', (-0.5, -0.5, 0.1, 0.5), m, rng, recess=False)
    C.boolean(p0[0], [crack('c0', rng, (-0.42, -0.3), (0.05, 0.12), m('crack_glow'), width=0.02, depth=0.04, amp=0.04),
                      crack('c1', rng, (-0.3, 0.42), (-0.12, -0.05), m('crack_glow'), width=0.018, depth=0.04, branch=False)])
    parts += p0
    # Right-front plate buckled up at one corner.
    pl = plate('p1', (0.1, -0.5, 0.5, 0.0), m, rng, recess=True)
    for o in pl:
        o.rotation_euler = (0.06, -0.05, 0.0)
        o.location = (0.0, 0.0, 0.012)
    parts += pl
    parts += plate('p2', (0.1, 0.0, 0.5, 0.5), m, rng, recess=False, mat=m('plate'))
    # Torn rivet holes and a dent.
    parts.append(C.box_mm('dent', (0.2, 0.15, -0.02), (0.38, 0.3, 0.001), m('plate_dark'), bevel=0.01))
    return parts


def lower_grate(m, rng):
    parts = []
    # Glow well under the grate (the boards' magenta-lit grates).
    parts.append(C.box_mm('well', (-0.5 + GAP / 2, -0.5 + GAP / 2, -T), (0.5 - GAP / 2, 0.5 - GAP / 2, -0.17), m('seam')))
    parts.append(C.box_mm('glow', (-0.3, -0.3, -0.17), (0.3, 0.3, -0.155), m('grate_glow')))
    # Riveted frame, wider on one side with a hazard strip (orientation cue).
    fr = 0.09
    e = 0.5 - GAP / 2
    frames = [(-e, -e, e, -e + fr + 0.06), (-e, e - fr, e, e), (-e, -e, -e + fr, e), (e - fr, -e, e, e)]
    for i, (x0, y0, x1, y1) in enumerate(frames):
        f = C.box_mm(f'fr{i}', (x0, y0, -T), (x1, y1, 0.0), m('plate'), bevel=0.014)
        parts.append(f)
    parts += hazard_stripes('hz', -e + fr, e - fr, -e + 0.02, -e + fr + 0.04, 0.0005, m, period=0.09)
    for i, (x, y) in enumerate([(-e + 0.045, -e + 0.045), (e - 0.045, -e + 0.045), (-e + 0.045, e - 0.045), (e - 0.045, e - 0.045)]):
        parts.append(C.rivet(f'rv{i}', (x, y, 0.0), (0, 0, 1), m('metal'), radius=0.018, height=0.01))
    # Bars: a square lattice of flat bars.
    lo, hi = -e + fr, e - fr
    n = 6
    for i in range(1, n):
        t = lo + (hi - lo) * i / n
        parts.append(C.box_mm(f'bx{i}', (t - 0.013, lo - 0.005, -0.06), (t + 0.013, hi + 0.005, -0.006), m('trim'), bevel=0.004))
        parts.append(C.box_mm(f'by{i}', (lo - 0.005, t - 0.013, -0.05), (hi + 0.005, t + 0.013, -0.012), m('trim'), bevel=0.004))
    return parts


def lower_overgrown(m, rng):
    parts = [bed(m('seam'))]
    parts += plate('p0', (-0.5, -0.5, 0.0, 0.5), m, rng, recess=True)
    parts += plate('p1', (0.0, -0.5, 0.5, -0.1), m, rng, recess=False, mat=m('plate'))
    # Missing plate: rubble and soil with growth pushing up from below the deck.
    parts.append(C.box_mm('soil', (0.0 + GAP / 2, -0.1 + GAP / 2, -T), (0.5 - GAP / 2, 0.5 - GAP / 2, -0.06), m('rock_dark'), bevel=0.02))
    for k in range(4):
        parts.append(C.rock(f'rb{k}', rng, (0.09, 0.08, 0.05), (0.12 + rng.uniform(0, 0.25), 0.05 + rng.uniform(0, 0.3), -0.05), m('stone')))
    parts.append(C.leaf_clump('plant', rng, (0.28, 0.22, -0.06), 0.18, m('grass'), count=7))
    for k, (x, y) in enumerate([(0.1, 0.4), (0.42, 0.0), (0.05, -0.05), (-0.02, 0.3)]):
        parts.append(C.blade_tuft(f't{k}', rng, (x, y, -0.05), m('grass') if k % 2 else m('leaf_dark'), height=0.13, blades=6))
    parts.append(C.moss_pad('m0', rng, (-0.02, 0.1, -0.004), 0.1, 0.03, m('moss')))
    return parts


def lower_rune(m, rng):
    parts = [bed(m('seam'))]
    e = 0.5 - GAP / 2
    ob = C.box_mm('plate', (-e, -e, -T), (e, e, 0.0), m('plate_light'), bevel=0.016)
    C.apply_modifiers(ob)
    cut = rune_circle(m, 0.3, 0.0)
    glyphs = []
    for i, (x, y) in enumerate([(-0.4, -0.4), (0.4, 0.4)]):
        for k, pl in enumerate(glyph_strokes(rng, 0.06, 0.09)):
            pts = [(x + p[0], y + p[1]) for p in pl]
            glyphs.append(ribbon(f'g{i}_{k}', pts, 0.016, -0.012, 0.05, m('rune_glow')))
    C.boolean(ob, [cut] + glyphs)
    parts.append(ob)
    parts += rivets_rect('rv', (-e, -e, e, e), 0.0, m('metal'), inset=0.04, r=0.016)
    return parts


BUILDERS = {
    'upper': {'floor_solid': upper_solid, 'floor_cracked': upper_cracked, 'floor_grate': upper_grate,
              'floor_overgrown': upper_overgrown, 'floor_rune': upper_rune},
    'lower': {'floor_solid': lower_solid, 'floor_cracked': lower_cracked, 'floor_grate': lower_grate,
              'floor_overgrown': lower_overgrown, 'floor_rune': lower_rune},
}


def build(piece: str, look: str) -> list:
    """Build one floor piece; returns the exported objects (a single joined mesh)."""
    m = C.Mats(look)
    rng = random.Random(f'{piece}:{look}')
    parts = BUILDERS[look][piece](m, rng)
    ob = C.join(parts, piece)
    C.finish(ob)
    return [ob]
