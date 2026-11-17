"""Structure pieces: wall, wall_top_a, wall_top_b, wall_cut, barrier_low, cliff_skirt, edge_trim.

Placement conventions (Blender axes; Godot = (x, z, -y)):
  * wall / wall_cut: 1 x 1 footprint, from z = -0.2 (the bottom of the floor slab it replaces) to
    z = 1.6 (wall) / 0.45 (wall_cut). Every side face is finished and joints sit exactly on the
    footprint border, so walls tile seamlessly in both directions and around corners.
  * wall_top_a / wall_top_b: caps whose origin is the top of a wall (place at wall top height,
    Godot y = 1.6 on a standard wall). Footprint 1 x 1; growth and cables may hang down the faces.
  * barrier_low: runs along X through the tile centre (rails reach both tile edges, so a row of
    barriers is continuous; a post stands at the centre so crossing runs meet on a post). Rotate
    90 degrees for a run along Z.
  * cliff_skirt: hangs under an exposed tile from z = -0.2 to about -1.5.
  * edge_trim: the band on the tile's front edge (Godot +Z, Blender -Y), rotate per side.
"""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Matrix, Vector

import common as C
import floors as F

PIECES = ('wall', 'wall_top_a', 'wall_top_b', 'wall_cut', 'barrier_low', 'cliff_skirt', 'edge_trim')

WALL_TOP = 1.6
BASE = -0.2
CUT_TOP = 0.45
JOINT = 0.022

# Front face frame: local (u, v, w) = (along face, up, outward) -> world, face plane at y = -0.5.
FACE = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def face_rot(k: int) -> Matrix:
    """Rotation taking the front face (-Y) to face k: 0 front(-Y), 1 right(+X), 2 back(+Y), 3 left(-X)."""
    return Matrix.Rotation(k * math.pi / 2, 4, 'Z')


def place(objs, mtx):
    for o in objs:
        o.matrix_world = mtx @ o.matrix_world
    return objs


def face_cutter_matrix(k: int, plane_y: float) -> Matrix:
    """Map a cutter built in XY (x along the face, y up, z outward) onto face k whose plane is at
    distance |plane_y| from the centre."""
    return face_rot(k) @ Matrix.Translation((0, plane_y, 0)) @ FACE


def block_chips(rng, size, prob, depth=(0.025, 0.06), top_only=False):
    sx, sy, sz = size
    chips = []
    for cx in (-1, 1):
        for cy in (-1, 1):
            for cz in ((1,) if top_only else (-1, 1)):
                if rng.random() < prob:
                    d = rng.uniform(*depth)
                    n = Vector((cx, cy, cz * rng.uniform(0.7, 1.4))).normalized()
                    corner = Vector((cx * sx / 2, cy * sy / 2, cz * sz / 2))
                    chips.append((corner - n * d, n))
    return chips


def stone_mat(m, rng):
    r = rng.random()
    return m('stone_light') if r < 0.22 else m('stone_dark') if r < 0.45 else m('stone')


# ───────────────────────────── masonry ─────────────────────────────

BOND = ([0.5, 0.5], [0.38, 0.62], [0.62, 0.38], [0.3, 0.4, 0.3], [0.45, 0.55])


def masonry(m, rng, z0, z1, courses, name='c', top_light=True, chip=0.3, crack_blocks=2, full_top=True):
    """Coursed masonry over the 1 x 1 footprint between z0 and z1: alternate courses split along X
    then Y (a true bond, so every face shows staggered joints), joints on the footprint border.
    Returns the block objects plus a grout core."""
    parts = [C.box_mm(name + '_core', (-0.5 + 0.03, -0.5 + 0.03, z0), (0.5 - 0.03, 0.5 - 0.03, z1 - 0.03), m('grout'))]
    hs = [rng.uniform(0.85, 1.15) for _ in range(courses)]
    tot = sum(hs)
    zs = [z0]
    for h in hs:
        zs.append(zs[-1] + (z1 - z0) * h / tot)
    blocks = []
    for i in range(courses):
        za, zb = zs[i] + JOINT / 2, zs[i + 1] - JOINT / 2
        if i == courses - 1 and full_top:
            zb = zs[i + 1]
        widths = rng.choice(BOND)
        along_x = (i % 2 == 0)
        a = -0.5
        for j, wd in enumerate(widths):
            b = a + wd
            # Exposed faces sit a random few mm proud/shy: stones read as individual blocks.
            ins = [rng.uniform(0.0, 0.014) for _ in range(4)]
            if along_x:
                lo = (a + JOINT / 2, -0.5 + ins[0], za)
                hi = (b - JOINT / 2, 0.5 - ins[1], zb)
            else:
                lo = (-0.5 + ins[2], a + JOINT / 2, za)
                hi = (0.5 - ins[3], b - JOINT / 2, zb)
            size = [hi[k] - lo[k] for k in range(3)]
            centre = [(hi[k] + lo[k]) / 2 for k in range(3)]
            top = m('stone_light') if (top_light and i == courses - 1) else None
            ob = C.box(f'{name}{i}_{j}', size, centre, stone_mat(m, rng), bevel=0.022,
                       chips=block_chips(rng, size, chip), top_mat=top)
            blocks.append(ob)
            a = b
    # Face cracks: kinked grooves across a couple of blocks.
    for n in range(crack_blocks):
        ob = rng.choice(blocks[:-1] if len(blocks) > 1 else blocks)
        lo, hi = C.bounds([ob])
        k = rng.randrange(4)
        plane = -0.5 + 0.004
        u0 = -0.3 + rng.uniform(-0.1, 0.1)
        cz = (lo.z + hi.z) / 2
        hgt = hi.z - lo.z
        cut = F.crack(f'fc{n}', rng, (u0, cz + hgt * 0.45), (u0 + rng.uniform(0.1, 0.3), cz - hgt * 0.45), m('grout'),
                      width=0.018, depth=0.03, top=0.0, steps=4, amp=0.03)
        cut.matrix_world = face_cutter_matrix(k, plane) @ cut.matrix_world
        C.boolean(ob, [cut])
    return parts + blocks


def seam_moss(m, rng, n, z0, z1, name='sm'):
    """Moss cushions pushed out of joints on the side faces."""
    out = []
    for i in range(n):
        k = rng.randrange(4)
        u = rng.uniform(-0.4, 0.4)
        z = rng.uniform(z0, z1)
        p = face_rot(k) @ Vector((u, -0.5, z))
        nrm = face_rot(k).to_3x3() @ Vector((0, -1, 0))
        out.append(C.moss_pad(f'{name}{i}', rng, p, rng.uniform(0.05, 0.08), 0.03, m('moss'), up=nrm))
    return out


def upper_wall(m, rng):
    parts = masonry(m, rng, BASE, WALL_TOP, 6)
    parts += seam_moss(m, rng, 3, 0.1, 1.2)
    # A creeper down one face (quarter turns put it on different sides along a run).
    path = [(0.505, 0.18, WALL_TOP - 0.02), (0.512, 0.24, 1.2), (0.512, 0.14, 0.8), (0.512, 0.22, 0.45)]
    parts += C.vine('vine', rng, path, (1, 0, 0), m('leaf_dark'), m('grass'))
    parts.append(C.moss_pad('topmoss', rng, (0.22, 0.18, WALL_TOP), 0.13, 0.04, m('moss')))
    parts.append(C.blade_tuft('toptuft', rng, (0.2, 0.2, WALL_TOP + 0.02), m('grass'), height=0.14, blades=6))
    return parts


def upper_wall_cut(m, rng):
    parts = masonry(m, rng, BASE, CUT_TOP - 0.12, 2, name='cc', top_light=False, crack_blocks=1, full_top=False)
    # Clean coping: two long capstones with a crisp bevel and a slightly lighter, sun-bleached top.
    parts.append(C.box_mm('cap0', (-0.5 + 0.005, -0.5 + 0.005, CUT_TOP - 0.12), (0.12 - JOINT / 2, 0.5 - 0.005, CUT_TOP), m('stone_light'),
                          bevel=0.025))
    parts.append(C.box_mm('cap1', (0.12 + JOINT / 2, -0.5 + 0.005, CUT_TOP - 0.12), (0.5 - 0.005, 0.5 - 0.005, CUT_TOP), m('stone_light'),
                          bevel=0.025))
    return parts


def upper_top_a(m, rng):
    """Broken, crenellated cap with overgrowth."""
    parts = []
    # Merlons: two standing blocks of different height, one gap, one broken stump.
    parts.append(C.box_mm('mer0', (-0.5 + 0.01, -0.5 + 0.01, 0.0), (-0.06, 0.5 - 0.01, 0.42), m('stone'), bevel=0.025,
                          chips=block_chips(rng, (0.43, 0.98, 0.42), 0.5, (0.04, 0.09), top_only=True), top_mat=m('stone_light')))
    parts.append(C.box_mm('mer1', (0.22, -0.5 + 0.01, 0.0), (0.5 - 0.01, 0.06, 0.3), m('stone_dark'), bevel=0.025,
                          chips=block_chips(rng, (0.27, 0.55, 0.3), 0.6, (0.04, 0.09), top_only=True), top_mat=m('stone_light')))
    parts.append(C.box_mm('stump', (0.22, 0.1, 0.0), (0.5 - 0.01, 0.5 - 0.01, 0.12), m('stone'), bevel=0.02,
                          chips=block_chips(rng, (0.27, 0.39, 0.12), 0.7, (0.03, 0.06), top_only=True), top_mat=m('stone_light')))
    parts.append(C.rock('broken', rng, (0.2, 0.18, 0.14), (0.08, 0.15, 0.06), m('stone_dark'), flat_bottom=True))
    parts.append(C.rock('rubble', rng, (0.12, 0.1, 0.08), (0.36, 0.3, 0.16), m('stone'), flat_bottom=True))
    # Growth: grass on the ledges, a leafy plant in the gap, moss, and a vine down the front face.
    parts.append(C.moss_pad('moss0', rng, (0.08, -0.2, 0.0), 0.14, 0.05, m('moss')))
    parts.append(C.moss_pad('moss1', rng, (-0.28, 0.1, 0.42), 0.12, 0.04, m('moss')))
    parts.append(C.leaf_clump('plant', rng, (0.08, -0.15, 0.03), 0.26, m('grass'), count=9))
    for i, (x, y, z) in enumerate([(-0.35, -0.25, 0.42), (0.38, -0.3, 0.3), (0.0, 0.3, 0.03), (0.38, 0.3, 0.12)]):
        parts.append(C.blade_tuft(f'tuft{i}', rng, (x, y, z), m('grass') if i % 2 else m('leaf_dark'), height=0.16, blades=7))
    path = [(-0.32, -0.505, 0.4), (-0.3, -0.512, 0.1), (-0.36, -0.512, -0.25), (-0.3, -0.512, -0.6), (-0.34, -0.512, -0.85)]
    parts += C.vine('vine0', rng, path, (0, -1, 0), m('leaf_dark'), m('grass'))
    path = [(0.5 + 0.005, -0.1, 0.28), (0.512, -0.05, -0.1), (0.512, -0.12, -0.45)]
    parts += C.vine('vine1', rng, path, (1, 0, 0), m('leaf_dark'), m('grass'))
    return parts


def upper_top_b(m, rng):
    """Coping course carrying a yellow utility pipe run."""
    parts = []
    parts.append(C.box_mm('cope0', (-0.5 + 0.005, -0.5 + 0.005, 0.0), (-0.1 - JOINT / 2, 0.5 - 0.005, 0.14), m('stone_light'), bevel=0.022,
                          chips=block_chips(rng, (0.39, 0.99, 0.14), 0.4, top_only=True)))
    parts.append(C.box_mm('cope1', (-0.1 + JOINT / 2, -0.5 + 0.005, 0.0), (0.5 - 0.005, 0.5 - 0.005, 0.14), m('stone'), bevel=0.022,
                          chips=block_chips(rng, (0.59, 0.99, 0.14), 0.4, top_only=True), top_mat=m('stone_light')))
    # Pipe saddles and the run (continuous along X so neighbouring caps connect).
    for i, x in enumerate((-0.3, 0.3)):
        parts.append(C.box_mm(f'saddle{i}', (x - 0.05, -0.36, 0.14), (x + 0.05, -0.04, 0.2), m('metal_dark'), bevel=0.01))
        parts.append(C.box_mm(f'strap{i}', (x - 0.03, -0.32, 0.14), (x + 0.03, -0.2, 0.3), m('metal'), bevel=0.008))
    parts.append(C.tube('pipe0', [(-0.5, -0.26, 0.255), (0.5, -0.26, 0.255)], 0.065, m('paint_yellow'), sides=14))
    parts.append(C.tube('pipe1', [(-0.5, -0.1, 0.235), (0.5, -0.1, 0.235)], 0.04, m('rust'), sides=10))
    # Flanged coupling + rust sleeve on the big pipe.
    parts.append(C.cylinder('flange0', 0.085, 0.04, (0.05, -0.26, 0.255), m('paint_yellow'), segments=14, axis='X', bevel=0.008))
    parts.append(C.cylinder('flange1', 0.085, 0.04, (0.1, -0.26, 0.255), m('paint_yellow'), segments=14, axis='X', bevel=0.008))
    parts.append(C.cylinder('rust0', 0.069, 0.12, (-0.4, -0.26, 0.255), m('rust'), segments=14, axis='X'))
    # Junction box with a riser into the wall.
    parts.append(C.box_mm('jbox', (0.18, 0.08, 0.14), (0.4, 0.34, 0.32), m('metal'), bevel=0.02, top_mat=m('paint_yellow')))
    parts.append(C.tube('riser', [(0.29, 0.21, 0.32), (0.29, 0.21, 0.42), (0.29, -0.1, 0.42), (0.29, -0.1, 0.28)], 0.022, m('metal_dark'),
                        sides=8, elbow=0.05))
    parts.append(C.moss_pad('moss', rng, (-0.32, 0.25, 0.14), 0.12, 0.04, m('moss')))
    parts.append(C.blade_tuft('tuft', rng, (-0.3, 0.3, 0.16), m('grass'), height=0.13))
    return parts


def upper_barrier(m, rng):
    parts = []
    # Stone kerb, two blocks, full length so runs are continuous.
    parts.append(C.box_mm('kerb0', (-0.5 + JOINT / 2, -0.18, BASE), (0.08 - JOINT / 2, 0.18, 0.22), m('stone'), bevel=0.025,
                          chips=block_chips(rng, (0.57, 0.36, 0.42), 0.4), top_mat=m('stone_light')))
    parts.append(C.box_mm('kerb1', (0.08 + JOINT / 2, -0.18, BASE), (0.5 - JOINT / 2, 0.18, 0.22), m('stone_dark'), bevel=0.025,
                          chips=block_chips(rng, (0.41, 0.36, 0.42), 0.4), top_mat=m('stone_light')))
    parts += pipe_railing(m, rng, 0.22, rust=True)
    parts.append(C.moss_pad('moss', rng, (-0.3, -0.18, 0.05), 0.07, 0.03, m('moss'), up=(0, -1, 0)))
    parts.append(C.blade_tuft('tuft', rng, (0.08, -0.2, 0.0), m('grass'), height=0.12))
    return parts


def pipe_railing(m, rng, base_z, rust=False):
    """Yellow pipe railing: a centre post with a foot flange, top rail at 0.55 and a mid rail, both
    spanning the full tile so neighbours connect."""
    parts = []
    top = 0.55
    parts.append(C.cylinder('foot', 0.06, 0.03, (0, 0, base_z + 0.015), m('metal_dark'), segments=12, bevel=0.006))
    parts.append(C.tube('post', [(0, 0, base_z), (0, 0, top)], 0.032, m('paint_yellow'), sides=10))
    parts.append(C.cylinder('cap', 0.042, 0.04, (0, 0, top), m('paint_yellow'), segments=12, bevel=0.01))
    parts.append(C.tube('rail_top', [(-0.5, 0, top), (0.5, 0, top)], 0.028, m('paint_yellow'), sides=10))
    parts.append(C.tube('rail_mid', [(-0.5, 0, base_z + (top - base_z) * 0.5), (0.5, 0, base_z + (top - base_z) * 0.5)], 0.022,
                        m('paint_yellow'), sides=10))
    parts.append(C.cylinder('clamp', 0.04, 0.05, (0, 0, base_z + (top - base_z) * 0.5), m('metal_dark'), segments=10))
    if rust:
        parts.append(C.cylinder('rust0', 0.031, 0.1, (-0.32, 0, top), m('rust'), segments=10, axis='X'))
        parts.append(C.cylinder('rust1', 0.025, 0.07, (0.36, 0, base_z + (top - base_z) * 0.5), m('rust'), segments=10, axis='X'))
    return parts


def upper_cliff(m, rng):
    parts = []
    # A course of big foundation stones flush with the tile border.
    parts += masonry(m, rng, -0.55, BASE, 1, name='fd', top_light=False, crack_blocks=1, full_top=True)
    # Earth core tapering down and chunky rocks bulging out of it.
    core = C.prism('earth', [(-0.42, -0.42), (0.42, -0.42), (0.42, 0.42), (-0.42, 0.42)], -1.15, -0.55, m('soil'), bevel=0.03)
    parts.append(core)
    parts.append(C.prism('earth2', [(-0.28, -0.3), (0.3, -0.26), (0.25, 0.3), (-0.3, 0.24)], -1.5, -1.12, m('soil'), bevel=0.03))
    for i, (x, y, z, s) in enumerate([(-0.25, -0.28, -0.75, 0.42), (0.26, -0.24, -0.8, 0.38), (0.24, 0.26, -0.72, 0.4),
                                       (-0.26, 0.24, -0.78, 0.4), (0.0, -0.05, -1.25, 0.46), (0.05, 0.12, -1.45, 0.3)]):
        parts.append(C.rock(f'rock{i}', rng, (s, s * rng.uniform(0.85, 1.1), s * 0.8), (x, y, z),
                            m('rock') if i % 3 else m('rock_dark'), jitter=0.3))
    # Roots dangling below the foundation.
    for i in range(3):
        x, y = rng.uniform(-0.35, 0.35), rng.choice((-0.43, 0.43))
        path = [(x, y, -0.56), (x + rng.uniform(-0.05, 0.05), y * 1.03, -0.8), (x + rng.uniform(-0.08, 0.08), y * 1.01, -1.05)]
        parts.append(C.tube(f'root{i}', path, 0.014, m('leaf_dark'), sides=6, elbow=0.08))
    parts.append(C.blade_tuft('hang', rng, (-0.2, -0.47, -0.56), m('grass'), height=0.14, up=(0, -0.3, -1)))
    return parts


def upper_edge_trim(m, rng):
    return edge_band(m, rng, m('metal'), rust=True)


def edge_band(m, rng, metal, rust=False, neon=False):
    """Angle-iron lip on the tile's front edge with a hazard band on its outer face (geometry
    stripes), bolted on. Built along X with its outer face at y = -0.5 - 0.03."""
    parts = []
    t = 0.028
    top = 0.012
    bottom = -0.34
    # Top flange lies on the floor edge; vertical flange hangs over the slab side.
    parts.append(C.box_mm('flange_top', (-0.5, -0.5 - t, -0.012), (0.5, -0.5 + 0.075, top), metal, bevel=0.006))
    parts.append(C.box_mm('flange_side', (-0.5, -0.5 - t, bottom), (0.5, -0.5 + 0.002, top), metal, bevel=0.008))
    # Hazard stripes on the outer face: built flat then stood up on the face.
    stripes = F.hazard_stripes('hz', -0.5, 0.5, bottom + 0.04, top - 0.05, 0.003, m, period=0.2, slant=0.12, height=0.006)
    mtx = Matrix.Translation((0, -0.5 - t, 0)) @ FACE
    for s in stripes:
        s.matrix_world = mtx @ s.matrix_world
    parts += stripes
    for i, x in enumerate((-0.25, 0.25)):
        parts.append(C.rivet(f'bolt{i}', (x, -0.5 - t - 0.006, top - 0.025), (0, -1, 0), m('metal_dark'), radius=0.016, height=0.01))
        parts.append(C.rivet(f'boltb{i}', (x, -0.5 - t - 0.006, bottom + 0.02), (0, -1, 0), m('metal_dark'), radius=0.016, height=0.01))
    if rust:
        parts.append(C.box_mm('rust0', (0.12, -0.5 - t - 0.008, bottom - 0.002), (0.27, -0.5 - t + 0.004, bottom + 0.06), m('rust'), bevel=0.004))
        parts.append(C.box_mm('rust1', (-0.44, -0.5 - t - 0.008, top - 0.03), (-0.36, -0.5 + 0.06, top + 0.002), m('rust'), bevel=0.004))
    if neon:
        parts.append(C.box_mm('neon_ch', (-0.5, -0.5 - t - 0.01, bottom - 0.05), (0.5, -0.5 + 0.0, bottom), m('trim'), bevel=0.006))
        parts.append(C.box_mm('neon', (-0.5, -0.5 - t - 0.016, bottom - 0.035), (0.5, -0.5 - t + 0.006, bottom - 0.015), m('neon_pink_glow')))
    return parts


# ───────────────────────────── metal (lower) ─────────────────────────────

def plate_face(ob, inset=0.04, depth=0.01, normal=(0, -1, 0), mat_index=None):
    """Recess the largest face pointing along `normal` (pressed panel)."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    n = Vector(normal)
    cands = [f for f in bm.faces if f.normal.dot(n) > 0.99]
    if not cands:
        bm.free()
        return ob
    face = max(cands, key=lambda f: f.calc_area())
    bmesh.ops.inset_region(bm, faces=[face], thickness=inset, depth=0.0, use_even_offset=True)
    bmesh.ops.translate(bm, vec=-n * depth, verts=list(face.verts))
    if mat_index is not None:
        face.material_index = mat_index
    bm.to_mesh(me)
    bm.free()
    return ob


def metal_face(m, rng, k, z0, z1, variant, name):
    """One side of a plated wall block, built on the front face and rotated to side k."""
    parts = []
    R = face_rot(k)
    y_out = -0.5
    # Plinth band.
    plinth_top = min(z1, 0.28)
    pl = C.box_mm(f'{name}_plinth', (-0.41, y_out, z0 + 0.0), (0.41, y_out + 0.07, plinth_top), m('trim'), bevel=0.016)
    parts.append(pl)
    for i in range(4):
        x = -0.3 + i * 0.2
        parts.append(C.rivet(f'{name}_pr{i}', (x, y_out, plinth_top - 0.05), (0, -1, 0), m('metal'), radius=0.02, height=0.012))
    if variant == 'neon' and z1 > 0.6:
        parts.append(C.box_mm(f'{name}_slot', (-0.3, y_out - 0.004, 0.1), (0.3, y_out + 0.02, 0.2), m('seam'), bevel=0.008))
        parts.append(C.box_mm(f'{name}_neon', (-0.27, y_out + 0.002, 0.125), (0.27, y_out + 0.03, 0.175), m('neon_pink_glow')))
    if variant == 'hazard':
        hz = F.hazard_stripes(f'{name}_hz', -0.38, 0.38, 0.0, plinth_top - 0.1, 0.003, m, period=0.12, slant=0.08, height=0.006)
        mtx = Matrix.Translation((0, y_out - 0.0005, 0)) @ FACE
        for s in hz:
            s.matrix_world = mtx @ s.matrix_world
        parts += hz
    if z1 - plinth_top > 0.3:
        # Main panels: two plates split asymmetrically, riveted top and bottom. The wide plate
        # carries the face's feature (rune column, or etched circuit traces); the narrow one is a
        # pressed panel. A vertical neon channel runs in the split on 'neon' faces.
        split = rng.choice((-0.12, 0.12))
        zt = z1 - 0.13
        wide = 0 if split > 0 else 1
        for j, (a, b) in enumerate(((-0.41, split), (split, 0.41))):
            p = C.box_mm(f'{name}_pn{j}', (a + 0.012, y_out + 0.012, plinth_top + 0.02), (b - 0.012, y_out + 0.07, zt), m('plate'), bevel=0.014)
            C.apply_modifiers(p)
            face_y = y_out + 0.012
            if j != wide:
                p.data.materials.append(m('plate_dark'))
                plate_face(p, inset=0.04, depth=0.012, mat_index=1)
            elif variant == 'rune':
                # Tall rune column: three large glyphs, grooves floored with rune_glow.
                glyphs = []
                cx = (a + b) / 2
                for g in range(3):
                    gy = plinth_top + 0.2 + g * 0.34
                    if gy + 0.14 > zt - 0.04:
                        break
                    for s, pl_ in enumerate(F.glyph_strokes(rng, 0.17, 0.25)):
                        pts = [(cx + q[0], gy + q[1]) for q in pl_]
                        glyphs.append(F.ribbon(f'{name}_g{g}_{s}', pts, 0.032, -0.018, 0.05, m('rune_glow')))
                cut = C.join(glyphs, f'{name}_runes')
                cut.matrix_world = Matrix.Translation((0, face_y, 0)) @ FACE
                C.boolean(p, [cut])
            else:
                # Etched circuit traces: angular grooves (dark) running off the plate's edges.
                traces = []
                for t in range(3):
                    x = a + (b - a) * (0.25 + 0.25 * t)
                    zA = plinth_top + 0.06
                    zB = plinth_top + rng.uniform(0.25, 0.55)
                    dx = rng.choice((-1, 1)) * 0.08
                    pts = [(x, zA), (x, zB), (x + dx, zB + 0.08), (x + dx, min(zt - 0.08, zB + 0.4))]
                    traces.append(F.ribbon(f'{name}_t{t}', pts, 0.018, -0.01, 0.05, m('seam')))
                    end = pts[-1]
                    traces.append(C.box(f'{name}_te{t}', (0.04, 0.04, 0.06), (end[0], end[1], 0.0), m('seam')))
                cut = C.join(traces, f'{name}_traces')
                cut.matrix_world = Matrix.Translation((0, face_y, 0)) @ FACE
                C.boolean(p, [cut])
            parts.append(p)
        if variant == 'neon':
            parts.append(C.box_mm(f'{name}_vch', (split - 0.035, y_out + 0.0, plinth_top + 0.08), (split + 0.035, y_out + 0.04, zt - 0.06), m('seam'), bevel=0.01))
            parts.append(C.box_mm(f'{name}_vneon', (split - 0.016, y_out - 0.006, plinth_top + 0.11), (split + 0.016, y_out + 0.03, zt - 0.09),
                                  m('neon_pink_glow'), bevel=0.008))
            for zz in (plinth_top + 0.05, zt - 0.035):
                for xx in (a + 0.05, b - 0.05):
                    parts.append(C.rivet(f'{name}_r{j}{zz:.2f}{xx:.2f}', (xx, y_out + 0.012, zz), (0, -1, 0), m('metal'), radius=0.017, height=0.01))
        if variant == 'vent':
            parts.append(C.box_mm(f'{name}_vent', (-0.32, y_out + 0.004, zt - 0.36), (-0.02, y_out + 0.02, zt - 0.1), m('seam'), bevel=0.01))
            for s in range(4):
                zz = zt - 0.33 + s * 0.06
                parts.append(C.box_mm(f'{name}_sl{s}', (-0.3, y_out + 0.0, zz), (-0.04, y_out + 0.016, zz + 0.025), m('metal'), bevel=0.004))
    for o in parts:
        o.matrix_world = R @ o.matrix_world
    return parts


def lower_block(m, rng, z0, z1, variants, name='w', lid=True):
    parts = [C.box_mm(name + '_core', (-0.44, -0.44, z0), (0.44, 0.44, z1 - 0.02), m('plate_dark'))]
    # Corner posts: heavy L-section columns.
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        parts.append(C.box_mm(f'{name}_post{i}', (sx * 0.5 if sx < 0 else 0.5 - 0.1, sy * 0.5 if sy < 0 else 0.5 - 0.1, z0),
                              (-0.5 + 0.1 if sx < 0 else 0.5, -0.5 + 0.1 if sy < 0 else 0.5, z1), m('trim'), bevel=0.018))
    for k, v in enumerate(variants):
        parts += metal_face(m, rng, k, z0, z1, v, f'{name}_f{k}')
    if lid:
        lidob = C.box_mm(name + '_lid', (-0.41, -0.41, z1 - 0.07), (0.41, 0.41, z1), m('plate'), bevel=0.014)
        C.apply_modifiers(lidob)
        lidob.data.materials.append(m('plate_dark'))
        plate_face(lidob, inset=0.06, depth=0.012, normal=(0, 0, 1), mat_index=1)
        parts.append(lidob)
        # Top band: bevelled rim around the lid.
        for i, (lo, hi) in enumerate((((-0.4, -0.5, z1 - 0.12), (0.4, -0.41, z1)), ((-0.4, 0.41, z1 - 0.12), (0.4, 0.5, z1)),
                                      ((-0.5, -0.4, z1 - 0.12), (-0.41, 0.4, z1)), ((0.41, -0.4, z1 - 0.12), (0.5, 0.4, z1)))):
            parts.append(C.box_mm(f'{name}_rim{i}', lo, hi, m('trim'), bevel=0.014))
    return parts


def lower_wall(m, rng):
    return lower_block(m, rng, BASE, WALL_TOP, ['neon', 'rune', 'hazard', 'vent'])


def lower_wall_cut(m, rng):
    parts = lower_block(m, rng, BASE, CUT_TOP, ['plain', 'plain', 'plain', 'plain'], lid=False)
    # Clean cap: a plate with a yellow hazard rim so the cut reads as deliberate.
    cap = C.box_mm('cap', (-0.5, -0.5, CUT_TOP - 0.08), (0.5, 0.5, CUT_TOP), m('plate_light'), bevel=0.018)
    C.apply_modifiers(cap)
    cap.data.materials.append(m('plate'))
    plate_face(cap, inset=0.1, depth=0.008, normal=(0, 0, 1), mat_index=1)
    parts.append(cap)
    for i in range(4):
        hz = F.hazard_stripes(f'hz{i}', -0.4, 0.4, -0.5 + 0.03, -0.5 + 0.07, CUT_TOP + 0.0005, m, period=0.1, slant=0.04)
        for s in hz:
            s.matrix_world = face_rot(i) @ s.matrix_world
        parts += hz
    return parts


def lower_top_a(m, rng):
    """Crenellated armour cap with a torn plate and cables slung over the face."""
    parts = []
    parts.append(C.box_mm('band', (-0.5, -0.5, 0.0), (0.5, 0.5, 0.1), m('trim'), bevel=0.016))
    for i, (x0, x1, h) in enumerate(((-0.46, -0.1, 0.36), (0.12, 0.46, 0.28))):
        b = C.box_mm(f'mer{i}', (x0, -0.46, 0.1), (x1, 0.46, 0.1 + h), m('plate'), bevel=0.02,
                     chips=[((0, -0.46 + 0.0, h / 2 - 0.0), Vector((0, -1, 1.2)).normalized())] if i == 0 else (),
                     top_mat=m('plate_light'))
        b.location = (0, 0, 0)
        parts.append(b)
        for zz in (0.17, 0.1 + h - 0.06):
            for xx in (x0 + 0.05, x1 - 0.05):
                parts.append(C.rivet(f'mr{i}{zz:.2f}{xx:.2f}', (xx, -0.46, zz), (0, -1, 0), m('metal'), radius=0.018, height=0.01))
    # Rune slit in the tall merlon.
    cut = C.join([F.ribbon('rs', [(-0.28, 0.2), (-0.28, 0.38)], 0.03, -0.02, 0.05, m('rune_glow')),
                  F.ribbon('rs2', [(-0.34, 0.3), (-0.22, 0.3)], 0.024, -0.02, 0.05, m('rune_glow'))], 'runes')
    cut.matrix_world = Matrix.Translation((0, -0.46, 0)) @ FACE
    mer0 = [p for p in parts if p.name == 'mer0'][0]
    C.boolean(mer0, [cut])
    # Torn plate bent outward between the merlons.
    torn = C.prism('torn', [(-0.08, 0.0), (0.1, 0.0), (0.08, 0.16), (-0.02, 0.22), (-0.07, 0.12)], -0.012, 0.012, m('plate'),
                   matrix=Matrix.Translation((0.01, -0.44, 0.1)) @ Matrix.Rotation(-0.5, 4, 'X') @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    parts.append(torn)
    # Cables slung over the front face.
    for i, (x0, x1, sag) in enumerate(((-0.42, 0.1, 0.35), (-0.2, 0.45, 0.5))):
        pts = []
        for s in range(9):
            t = s / 8
            x = x0 + (x1 - x0) * t
            z = 0.06 - sag * 4 * t * (1 - t)
            pts.append((x, -0.53 - 0.01 * i, z))
        parts.append(C.tube(f'cable{i}', pts, 0.02, m('seam') if i else m('metal_dark'), sides=8))
    parts.append(C.moss_pad('moss', rng, (0.0, 0.2, 0.1), 0.1, 0.03, m('moss')))
    return parts


def lower_top_b(m, rng):
    """Pipe and conduit run with a caged neon tube along the front edge."""
    parts = []
    parts.append(C.box_mm('band', (-0.5, -0.5, 0.0), (0.5, 0.5, 0.08), m('trim'), bevel=0.016))
    for i, x in enumerate((-0.28, 0.28)):
        parts.append(C.box_mm(f'saddle{i}', (x - 0.05, -0.45, 0.08), (x + 0.05, 0.4, 0.14), m('metal_dark'), bevel=0.012))
    parts.append(C.tube('pipe0', [(-0.5, 0.12, 0.22), (0.5, 0.12, 0.22)], 0.08, m('metal'), sides=14))
    parts.append(C.tube('pipe1', [(-0.5, 0.33, 0.19), (0.5, 0.33, 0.19)], 0.05, m('plate'), sides=12))
    for i, x in enumerate((-0.05, 0.4)):
        parts.append(C.cylinder(f'band{i}', 0.092, 0.05, (x, 0.12, 0.22), m('paint_yellow'), segments=14, axis='X', bevel=0.008))
    # Neon tube in a cage on the front edge.
    parts.append(C.box_mm('ch', (-0.5, -0.5, 0.08), (0.5, -0.3, 0.12), m('seam'), bevel=0.01))
    parts.append(C.tube('neon', [(-0.5, -0.4, 0.17), (0.5, -0.4, 0.17)], 0.03, m('neon_cyan_glow'), sides=10))
    for i, x in enumerate((-0.42, -0.14, 0.14, 0.42)):
        parts.append(C.tube(f'cage{i}', [(x, -0.47, 0.1), (x, -0.47, 0.22), (x, -0.33, 0.22), (x, -0.33, 0.1)], 0.01, m('metal_dark'),
                            sides=6, elbow=0.02))
    # A junction box with a conduit dropping down the back.
    parts.append(C.box_mm('jbox', (-0.2, -0.22, 0.08), (0.02, 0.0, 0.28), m('plate_dark'), bevel=0.018, top_mat=m('paint_yellow')))
    parts.append(C.box_mm('jlamp', (-0.15, -0.226, 0.18), (-0.03, -0.215, 0.22), m('neon_pink_glow')))
    return parts


def lower_barrier(m, rng):
    parts = []
    parts.append(C.box_mm('kerb', (-0.5, -0.17, BASE), (0.5, 0.17, 0.2), m('plate'), bevel=0.02, top_mat=m('plate_light')))
    for side in (-1, 1):
        hz = F.hazard_stripes(f'hz{side}', -0.48, 0.48, 0.02, 0.17, 0.003, m, period=0.16, slant=0.1, height=0.006)
        mtx = Matrix.Rotation(0 if side < 0 else math.pi, 4, 'Z') @ Matrix.Translation((0, -0.17, 0)) @ FACE
        for s in hz:
            s.matrix_world = mtx @ s.matrix_world
        parts += hz
        for i, x in enumerate((-0.35, 0.35)):
            parts.append(C.rivet(f'kr{side}{i}', (x, side * 0.17, -0.06), (0, side, 0), m('metal'), radius=0.018, height=0.01))
    parts += pipe_railing(m, rng, 0.2)
    return parts


def lower_cliff(m, rng):
    parts = []
    # Heavy riveted band flush with the tile border.
    parts.append(C.box_mm('band', (-0.5, -0.5, -0.52), (0.5, 0.5, BASE), m('plate_dark'), bevel=0.02))
    for k in range(4):
        sub = []
        sub.append(C.box_mm(f'bp{k}', (-0.42, -0.512, -0.48), (0.42, -0.49, -0.24), m('plate'), bevel=0.01))
        for i in range(5):
            sub.append(C.rivet(f'br{k}{i}', (-0.36 + i * 0.18, -0.512, -0.27), (0, -1, 0), m('metal'), radius=0.018, height=0.01))
        for o in sub:
            o.matrix_world = face_rot(k) @ o.matrix_world
        parts += sub
    # Substructure: stepped machinery blocks and girders tapering into the dark.
    parts.append(C.box_mm('sub0', (-0.4, -0.4, -0.95), (0.4, 0.4, -0.52), m('trim'), bevel=0.03))
    parts.append(C.box_mm('sub1', (-0.28, -0.3, -1.35), (0.3, 0.26, -0.95), m('plate_dark'), bevel=0.03))
    parts.append(C.box_mm('sub2', (-0.15, -0.12, -1.55), (0.14, 0.16, -1.35), m('trim'), bevel=0.025))
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        parts.append(C.box_mm(f'gird{i}', (sx * 0.4 - 0.05, sy * 0.4 - 0.05, -1.0), (sx * 0.4 + 0.05, sy * 0.4 + 0.05, -0.52), m('plate'), bevel=0.012))
    # Vertical pipes and a hanging conduit.
    parts.append(C.tube('pipe0', [(-0.3, -0.43, -0.52), (-0.3, -0.43, -1.05), (-0.18, -0.33, -1.25)], 0.045, m('metal'), sides=10, elbow=0.1))
    parts.append(C.tube('pipe1', [(0.43, 0.15, -0.52), (0.43, 0.15, -1.15)], 0.035, m('rust'), sides=10))
    parts.append(C.tube('cable', [(0.1, -0.41, -0.55), (0.14, -0.43, -0.85), (0.08, -0.4, -1.1), (0.12, -0.42, -1.3)], 0.016, m('seam'),
                        sides=6, elbow=0.1))
    # Underside light slit (warm orange source of the lower board).
    parts.append(C.box_mm('lamp', (-0.2, -0.315, -1.2), (0.2, -0.3, -1.12), m('neon_violet_glow')))
    parts.append(C.box_mm('vent', (0.05, -0.405, -0.85), (0.3, -0.39, -0.62), m('seam'), bevel=0.008))
    return parts


def lower_edge_trim(m, rng):
    return edge_band(m, rng, m('plate_dark'), neon=True)


BUILDERS = {
    'upper': {'wall': upper_wall, 'wall_top_a': upper_top_a, 'wall_top_b': upper_top_b, 'wall_cut': upper_wall_cut,
              'barrier_low': upper_barrier, 'cliff_skirt': upper_cliff, 'edge_trim': upper_edge_trim},
    'lower': {'wall': lower_wall, 'wall_top_a': lower_top_a, 'wall_top_b': lower_top_b, 'wall_cut': lower_wall_cut,
              'barrier_low': lower_barrier, 'cliff_skirt': lower_cliff, 'edge_trim': lower_edge_trim},
}

PLACEMENT = {
    'wall': 'tile; z -0.2..1.6, all four faces finished; quarter turns give variants',
    'wall_top_a': 'cap; origin at the wall top (place at y = wall height)',
    'wall_top_b': 'cap; origin at the wall top (place at y = wall height)',
    'wall_cut': 'tile; z -0.2..0.45, clean capped top for camera-side cutaways',
    'barrier_low': 'runs along X through the tile centre; rotate 90 deg for a Z run; centre post',
    'cliff_skirt': 'under an exposed tile, from y = -0.2 down',
    'edge_trim': 'front edge (+Z) of the tile; rotate per exposed side',
}


def manifest_extra(piece, look):
    return {'placement': PLACEMENT[piece]}


def build(piece: str, look: str) -> list:
    m = C.Mats(look)
    rng = random.Random(f'{piece}:{look}')
    parts = BUILDERS[look][piece](m, rng)
    ob = C.join(parts, piece)
    C.finish(ob)
    return [ob]
