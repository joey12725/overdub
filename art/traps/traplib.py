"""Shared helpers for the OVERDUB trap models (Blender 4.5). Builds on the environment kit's helpers
(art/kit/common.py, floors.py, structure.py), imported read-only so the traps share its palette,
bevels, hazard stripes, rune grooves and export settings.

Every builder in art/traps works in GODOT coordinates: (x, y, z) = (right, up, forward), 1 unit =
1 tile, the walkable floor at y = 0. A trap that acts in a direction acts along Godot +Z at rest
(the same rule as characters and the kit's laser emitter), so the game yaws a piece by
`RenderCtx.heading_to_yaw(dir)`. The helpers below convert to Blender (x, -z, y).
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT_SRC = os.path.abspath(os.path.join(HERE, '..', 'kit'))
if KIT_SRC not in sys.path:
    sys.path.insert(0, KIT_SRC)

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common as C  # noqa: E402
import floors as F  # noqa: E402
import structure as S  # noqa: E402

PREVIEW_DIR = os.path.join(C.REPO, 'art', 'previews', 'traps')

# Colours the kit palette does not have. Machines never use a cassette colour (TRAPS.md): the
# telegraph is orange-red, sensors are a pale cold white, the magnet is violet.
EXTRA = {
    'upper': {'steel': 0xDAD5CC, 'soot': 0x3A2A24, 'belt': 0x3B3230, 'belt_arrow': 0xFFC21A, 'magnet_body': 0xB8402E},
    'lower': {'steel': 0xCAC5DE, 'soot': 0x140E1A, 'belt': 0x231B2C, 'belt_arrow': 0xFFB020, 'magnet_body': 0xA83A52},
}
GLOWS = {
    'warn_glow': 0xFF6A1E,        # telegraph: emission follows MechSnap.warn, full while live
    'heat_glow': 0xFF8A2A,        # flame throat: lit while burning
    'pilot_glow': 0x4C7CFF,       # flame pilot light
    'flame_glow': 0xFF7A1A,       # helper jet mesh, body
    'flame_core_glow': 0xFFE08A,  # helper jet mesh, hot core at the nozzle
    'pip_glow': 0xF2ECFF,         # dart launcher progress pips
    'muzzle_glow': 0xFFF4D0,      # dart muzzle flash
    'dart_glow': 0xF4EEFF,        # the dart bolt (white-violet: not a turret shot, not a cassette)
    'sensor_glow': 0xCFE4FF,      # sensor lens + cap
    'beam_glow': 0xCFE4FF,        # helper beam mesh
    'relay_glow': 0xFF9A2E,       # relay lamp and progress ticks
    'magnet_glow': 0xB060FF,      # magnet coil
    'magnet_ring_glow': 0xB060FF,  # magnet radius ring
    'run_glow': 0xFFE7A0,         # conveyor "running" edge lines
}


class TrapMats(C.Mats):
    """The kit's material lookup for one look, plus the trap-only colours."""

    def __init__(self, look: str):
        super().__init__(look)
        self.pal = dict(self.pal)
        self.pal.update(EXTRA[look])
        self.pal.update(GLOWS)


def sty(m, look):
    """The handful of material roles that differ between the looks."""
    up = look == 'upper'
    return {
        'up': up,
        'casing': m('paint_yellow') if up else m('plate'),   # painted housings / inscribed plate
        'frame': m('metal_dark') if up else m('trim'),       # frames, jambs, feet
        'dark': m('metal_dark') if up else m('plate_dark'),  # heavy dark metal
        'light': m('metal') if up else m('plate_light'),     # worn bright metal
        'plinth': m('stone') if up else m('trim'),
    }


# ───────────────────────────── Godot-space primitives ─────────────────────────────

def gv(p) -> Vector:
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((p[0], -p[2], p[1]))


def gbox(name, lo, hi, mat, **kw):
    """Bevelled box from Godot-space min / max corners."""
    return C.box_mm(name, (lo[0], -hi[2], lo[1]), (hi[0], -lo[2], hi[1]), mat, **kw)


_AXIS = {'X': 'X', 'Y': 'Z', 'Z': 'Y'}


def gcyl(name, r, depth, center, mat, axis='Y', **kw):
    """Cylinder / cone along a Godot axis. `radius2` is the +axis end."""
    return C.cylinder(name, r, depth, tuple(gv(center)), mat, axis=_AXIS[axis], **kw)


def grivet(name, center, normal, mat, **kw):
    return C.rivet(name, tuple(gv(center)), tuple(gv(normal)), mat, **kw)


def gprism(name, pts_xz, y0, y1, mat, **kw):
    """Extrude a polygon given in the Godot floor plane (x, z) from y0 to y1."""
    return C.prism(name, [(x, -z) for x, z in pts_xz], y0, y1, mat, **kw)


def gtube(name, pts, radius, mat, **kw):
    return C.tube(name, [tuple(gv(p)) for p in pts], radius, mat, **kw)


def sphere(name, r, center, mat, subdivisions=2, squash=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=r)
    bmesh.ops.scale(bm, vec=Vector((squash[0], squash[2], squash[1])), verts=bm.verts)
    bmesh.ops.translate(bm, vec=gv(center), verts=bm.verts)
    return C.obj_from_bm(name, bm, [mat])


def lathe(name, profile, mat, segs=8, origin=(0, 0, 0), phase=0.0):
    """Surface of revolution about the Godot +Z axis through `origin`; profile = [(z, radius), ...]."""
    bm = bmesh.new()
    rings = []
    for z, r in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new(gv((origin[0], origin[1], origin[2] + z)))])
        else:
            rings.append([bm.verts.new(gv((origin[0] + r * math.cos(phase + i * math.tau / segs),
                                           origin[1] + r * math.sin(phase + i * math.tau / segs), origin[2] + z)))
                          for i in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    for ring in (rings[0], rings[-1]):
        if len(ring) > 1:
            bm.faces.new(ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return C.obj_from_bm(name, bm, [mat])


# ───────────────────────────── frames and hazard language ─────────────────────────────

def gframe(u, w, o) -> Matrix:
    """Matrix placing a decal built in local XY (x = along `u`, z = outward along `w`) at Godot
    point `o`. `u` is the direction the decal's chevrons point, `w` the surface normal."""
    ub, wb = gv(u).normalized(), gv(w).normalized()
    vb = wb.cross(ub)
    ob = gv(o)
    mtx = Matrix.Identity(4)
    for i in range(3):
        mtx[i][0], mtx[i][1], mtx[i][2], mtx[i][3] = ub[i], vb[i], wb[i], ob[i]
    return mtx


def mount(objs, mtx):
    for o in objs:
        o.matrix_world = mtx @ o.matrix_world
    return objs


def _area(poly):
    return abs(sum(poly[i - 1][0] * poly[i][1] - poly[i][0] * poly[i - 1][1] for i in range(len(poly)))) / 2


def chev_strip(name, m, length, width, period=0.125, arm=None, bg='hazard_dark', fg='paint_yellow', thick=0.006):
    """A band of V chevrons pointing along local +X on an optional dark ground: the kit's hazard
    language with a direction. Built flat in XY (z = up out of the surface); place with
    mount(..., gframe(direction, normal, centre)). Chevrons sit on multiples of `period` from the
    strip centre, so strips of whole-tile length tile seamlessly across neighbouring cells."""
    l2, w2 = length / 2, width / 2
    parts = []
    if bg:
        parts.append(C.box_mm(name + '_bg', (-l2, -w2, -0.006), (l2, w2, thick - 0.002), m(bg)))
    t = arm if arm is not None else period * 0.5
    d = min(w2, period * 0.9)
    k = math.floor((-l2 - d - t) / period)
    i = 0
    while k * period < l2:
        u = k * period
        for half, poly in enumerate(([(u, -w2), (u + t, -w2), (u + d + t, 0), (u + d, 0)],
                                     [(u + d, 0), (u + d + t, 0), (u + t, w2), (u, w2)])):
            poly = F.clip_poly(poly, -l2, -9, l2, 9)
            if len(poly) >= 3 and _area(poly) > 1e-6:
                parts.append(C.prism(f'{name}_{i}_{half}', poly, 0.0, thick, m(fg)))
        k += 1
        i += 1
    return parts


def face_stripes(name, m, k, dist, x0, x1, y0, y1, period=0.12, slant=0.06):
    """Diagonal hazard stripes on a vertical face: k = 0 front (+Z), 1 right (+X), 2 back, 3 left;
    `dist` is the face plane's distance from the piece origin; x along the face, y up."""
    hz = F.hazard_stripes(name, x0, x1, y0, y1, 0.003, m, period=period, slant=slant, height=0.008)
    return mount(hz, S.face_rot(k) @ Matrix.Translation((0, -dist, 0)) @ S.FACE)


def floor_border(name, m, e_in, e_out, half, y, period=0.1):
    """Diagonal hazard stripes round the four edges of a tile overlay (no direction: "danger here")."""
    out = []
    for k in range(4):
        hz = F.hazard_stripes(f'{name}{k}', -half, half, -e_out, -e_in, y, m, period=period, slant=0.04, height=0.008)
        out += mount(hz, Matrix.Rotation(k * math.pi / 2, 4, 'Z'))
    return out


def side_runes(target, m, rng, k, dist, cx, cy, n=2, step=0.2):
    """Cut a column of rune glyphs (floored with rune_glow) into face k of `target`."""
    glyphs = []
    for g in range(n):
        for s_, pl in enumerate(F.glyph_strokes(rng, 0.07, 0.13)):
            r = F.ribbon(f'g{k}{g}{s_}', [(cx + q[0], cy + g * step + q[1]) for q in pl], 0.02, -0.014, 0.05, m('rune_glow'))
            if r is not None:
                glyphs.append(r)
    cut = C.join(glyphs, f'rc{k}')
    cut.matrix_world = S.face_cutter_matrix(k, -dist)
    return C.boolean(target, [cut])


def top_runes(target, m, rng, top, centres, w=0.07, h=0.13):
    """Cut rune glyphs into the top face (Godot y = top) of `target` at the (x, z) centres."""
    glyphs = []
    for g, (cx, cz) in enumerate(centres):
        for s_, pl in enumerate(F.glyph_strokes(rng, w, h)):
            r = F.ribbon(f'tg{g}{s_}', [(cx + q[0], -cz + q[1]) for q in pl], 0.02, top - 0.014, top + 0.05, m('rune_glow'))
            if r is not None:
                glyphs.append(r)
    return C.boolean(target, [C.join(glyphs, 'trc')])


# ───────────────────────────── parts ─────────────────────────────

def as_part(parts, name, origin=(0, 0, 0), uv=True):
    """Join `parts` into the exported object `name` with its origin (pivot) at Godot `origin`."""
    ob = C.join(parts, name)
    bpy.context.view_layer.update()
    if ob.matrix_world != Matrix.Identity(4):
        ob.data.transform(ob.matrix_world)
        ob.matrix_world = Matrix.Identity(4)
    C.finish(ob, uv=uv)
    o = gv(origin)
    if o.length > 0:
        ob.data.transform(Matrix.Translation(-o))
        ob.location = o
    ob.name = name
    ob.data.name = name
    return ob


def travel_uv(ob, x0, x1):
    """UVs for a scrolling surface, in the object's local frame: U runs 0..1 across the belt from
    -X to +X, V follows the travel axis. Blender V = 0.5 - z_godot, which the glTF exporter flips
    to V = z + 0.5 in the file / in Godot: 0 at the upstream edge, 1 at the downstream edge."""
    me = ob.data
    layer = me.uv_layers.get('UVMap') or me.uv_layers.new(name='UVMap')
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            layer.data[li].uv = ((co.x - x0) / (x1 - x0), 0.5 + co.y)
