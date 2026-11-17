"""Shared helpers for the OVERDUB environment kit (Blender 4.5, bpy + bmesh).

Conventions (docs/GODOT-PORT.md "Asset contract"):
  * 1 Blender metre = 1 Godot unit = 1 tile. Blender is Z-up; the glTF exporter converts to Y-up, so
    Blender (x, y, z) becomes Godot (x, z, -y). Godot +Z (the "front", toward the camera side) is
    Blender -Y. Every builder in the kit works in Blender coordinates with that in mind.
  * A piece's origin is on the floor (Blender z = 0) at its footprint centre. Floor tiles have their
    walkable top at z = 0 and hang below it.
  * Materials carry base colours only. Their names are the styling hook the game uses; emissive
    parts use a material whose name ends in `_glow`.

Geometry is made from real modelling operations: bevelled boxes (bmesh bevel), convex-hull rocks
with limited dissolve, polygon prisms, curve tubes converted to mesh, bisect-plane chips and exact
booleans for grooves (cracks, rune inscriptions). Each part is its own object while a piece is
being built; `join()` merges them into the exported mesh.
"""
from __future__ import annotations

import json
import math
import os
import random
from typing import Iterable, Sequence

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
KIT_DIR = os.path.join(REPO, 'assets', 'models', 'kit')
PREVIEW_DIR = os.path.join(REPO, 'art', 'previews', 'kit')
MANIFEST = os.path.join(KIT_DIR, 'manifest.json')

LOOKS = ('upper', 'lower')
# Which game themes each look serves (docs/GODOT-PORT.md: upper/mid/lower/core). Mid is "mixed"
# (warm stone with more metal) and reads closer to the upper kit; core is the darkest metal.
LOOK_THEMES = {'upper': ['upper', 'mid'], 'lower': ['lower', 'core']}

# ───────────────────────────── palette ─────────────────────────────
# Base colours per look, taken from the reference boards' palette swatches (R03/R04) and the
# prototype's render/palettes.ts so the Godot build keeps the same picture. sRGB hex.
PALETTE = {
    'upper': {
        'stone': 0xC79C7C,        # sunlit masonry
        'stone_light': 0xE2C2A4,  # bleached top faces / coping
        'stone_dark': 0xA47A5E,   # older, darker blocks
        'grout': 0x5D4334,        # mortar and recesses
        'soil': 0x8C6247,         # cliff earth
        'rock': 0xA9825F,         # cliff rocks
        'rock_dark': 0x6E4E3B,
        'metal': 0x8E8178,        # aged neutral metal
        'metal_dark': 0x5A4E48,
        'paint_yellow': 0xFFC21A, # utilities, trim, hazard bands
        'hazard_dark': 0x2B2220,
        'rust': 0xD8742A,
        'moss': 0x7FA82C,
        'grass': 0x9CC92E,
        'leaf_dark': 0x5E8A22,
        'rune_glow': 0xFFD27A,    # warm amber inscriptions in the sunlit ruins
        'neon_pink_glow': 0xFF3D9A,
        'neon_cyan_glow': 0x4FE6E0,
        'accent_glow': 0xFFE7A0,  # mechanism wire accent (tinted by the game per wire)
        'status_glow': 0xFF3048,
        'lens_glow': 0xFF4060,
        'core_glow': 0xFF3D9A,
        'exit_glow': 0x5CFFB0,
        'crack_glow': 0xFFB45A,
        'grate_glow': 0xFFB45A,
        'void': 0x1F1412,         # dark pit under grates / slots
    },
    'lower': {
        'plate': 0x6A5A74,        # inscribed metal (walls)
        'plate_light': 0x84729A,  # floor plating stays mid-value for readability (chapter 18)
        'plate_dark': 0x463A4F,   # heavy structural metal
        'seam': 0x1E1724,         # seams, recesses
        'trim': 0x2E2336,         # frames, girders
        'stone': 0x5B5060,
        'rock': 0x4A3F52,
        'rock_dark': 0x2E2536,
        'metal': 0x7C7086,        # pipes / worn alloy
        'metal_dark': 0x3A3044,
        'paint_yellow': 0xFFB020,
        'hazard_dark': 0x1A1420,
        'rust': 0xD06A28,
        'moss': 0x568F4C,
        'grass': 0x6FA65A,
        'leaf_dark': 0x3E6B3A,
        'rune_glow': 0xFF3FD0,
        'neon_pink_glow': 0xFF2FA0,
        'neon_cyan_glow': 0x3FF0FF,
        'neon_violet_glow': 0xC040FF,
        'accent_glow': 0xFFE7A0,
        'status_glow': 0xFF3048,
        'lens_glow': 0xFF4060,
        'core_glow': 0xFF2FA0,
        'exit_glow': 0x5CFFB0,
        'crack_glow': 0xFF8A2A,
        'grate_glow': 0xFF2FA0,
        'void': 0x0D0912,
    },
}

BG = {'upper': 0x221917, 'lower': 0x0D0912}


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h: int) -> tuple[float, float, float]:
    return tuple(srgb_to_linear(((h >> s) & 255) / 255.0) for s in (16, 8, 0))  # type: ignore


class Mats:
    """Material lookup for one look. `m('stone')` returns (and creates once) the named material."""

    def __init__(self, look: str):
        self.look = look
        self.pal = PALETTE[look]

    def __call__(self, name: str) -> bpy.types.Material:
        mat = bpy.data.materials.get(name)
        if mat is not None:
            return mat
        if name not in self.pal:
            raise KeyError(f'no colour for material {name!r} in look {self.look!r}')
        rgb = hex_rgb(self.pal[name])
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value = (*rgb, 1.0)
        bsdf.inputs['Roughness'].default_value = 0.85
        bsdf.inputs['Metallic'].default_value = 0.0
        mat.diffuse_color = (*rgb, 1.0)  # Workbench preview colour
        return mat


# ───────────────────────────── scene ─────────────────────────────

def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0


def link(ob: bpy.types.Object, coll: bpy.types.Collection | None = None) -> bpy.types.Object:
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


def obj_from_bm(name: str, bm: bmesh.types.BMesh, mats: Sequence[bpy.types.Material]) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    return link(bpy.data.objects.new(name, me))


def delete(objs: Iterable[bpy.types.Object]) -> None:
    for ob in list(objs):
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if data is not None and getattr(data, 'users', 1) == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Curve):
                bpy.data.curves.remove(data)


# ───────────────────────────── bmesh primitives ─────────────────────────────

def _bevel_all(bm: bmesh.types.BMesh, width: float, segments: int = 1, edges=None) -> None:
    if width <= 0:
        return
    geom = list(edges) if edges is not None else list(bm.edges)
    bmesh.ops.bevel(bm, geom=geom, offset=width, offset_type='OFFSET', segments=segments,
                    profile=0.5, affect='EDGES', clamp_overlap=True)


def bm_box(size: Sequence[float], center: Sequence[float] = (0, 0, 0)) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def bm_chip(bm: bmesh.types.BMesh, co: Sequence[float], no: Sequence[float]) -> None:
    """Slice off everything on the +no side of the plane through co and cap the hole flat."""
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=Vector(co), plane_no=Vector(no).normalized(),
                                 clear_outer=True, clear_inner=False)
    cut = [e for e in res['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
    boundary = [e for e in cut if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)


def box(name: str, size: Sequence[float], center: Sequence[float], mat: bpy.types.Material,
        bevel: float = 0.0, segments: int = 1, chips: Sequence[tuple] = (), rot_z: float = 0.0,
        top_mat: bpy.types.Material | None = None) -> bpy.types.Object:
    """A bevelled box. `chips` are (point, normal) planes in the box's local frame (centred at 0)
    that knock off corners/edges, giving chipped masonry. `top_mat` paints the upward faces."""
    bm = bm_box(size)
    _bevel_all(bm, min(bevel, 0.45 * min(size)), segments)
    for co, no in chips:
        bm_chip(bm, co, no)
    if top_mat is not None:
        for f in bm.faces:
            f.material_index = 1 if f.normal.z > 0.7 else 0
    if rot_z:
        bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(rot_z, 3, 'Z'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return obj_from_bm(name, bm, [mat] + ([top_mat] if top_mat is not None else []))


def box_mm(name: str, lo: Sequence[float], hi: Sequence[float], mat, **kw) -> bpy.types.Object:
    """Box from min/max corners."""
    size = [hi[i] - lo[i] for i in range(3)]
    center = [(hi[i] + lo[i]) / 2 for i in range(3)]
    return box(name, size, center, mat, **kw)


def prism(name: str, pts: Sequence[Sequence[float]], z0: float, z1: float, mat,
          bevel: float = 0.0, segments: int = 1, matrix: Matrix | None = None,
          top_mat=None) -> bpy.types.Object:
    """Extrude a 2D polygon (counter-clockwise, XY) from z0 to z1, bevel, then transform."""
    bm = bmesh.new()
    verts = [bm.verts.new((p[0], p[1], z0)) for p in pts]
    face = bm.faces.new(verts)
    if face.normal.z > 0:
        face.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    top = [v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, z1 - z0)), verts=top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _bevel_all(bm, bevel, segments)
    if top_mat is not None:
        for f in bm.faces:
            f.material_index = 1 if f.normal.z > 0.7 else 0
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return obj_from_bm(name, bm, [mat] + ([top_mat] if top_mat is not None else []))


def cylinder(name: str, radius: float, depth: float, center: Sequence[float], mat, segments: int = 12,
             axis: str = 'Z', bevel: float = 0.0, radius2: float | None = None,
             cap_mat=None) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    if bevel > 0:
        rim = [e for e in bm.edges if not all(len(f.verts) == 4 for f in e.link_faces)]
        _bevel_all(bm, bevel, 1, rim)
    if cap_mat is not None:
        for f in bm.faces:
            f.material_index = 1 if abs(f.normal.z) > 0.9 else 0
    if axis == 'X':
        bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'), verts=bm.verts)
    elif axis == 'Y':
        bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, 'X'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return obj_from_bm(name, bm, [mat] + ([cap_mat] if cap_mat is not None else []))


def rock(name: str, rng: random.Random, size: Sequence[float], center: Sequence[float], mat,
         jitter: float = 0.22, bevel: float = 0.0, flat_bottom: bool = False, rot_z: float | None = None,
         top_mat=None) -> bpy.types.Object:
    """Chunky faceted rock: convex hull of a jittered, corner-chamfered box, coplanar facets merged."""
    sx, sy, sz = size
    pts = []
    for ix in (-1, 1):
        for iy in (-1, 1):
            for iz in (-1, 1):
                # Three points per corner, pulled in along each axis: a chamfered, irregular corner.
                base = Vector((ix * sx / 2, iy * sy / 2, iz * sz / 2))
                for ax in range(3):
                    p = base.copy()
                    p[ax] *= 1 - rng.uniform(0.15, 0.45)
                    for k in range(3):
                        p[k] += rng.uniform(-jitter, jitter) * size[k] * 0.35
                    pts.append(p)
    if flat_bottom:
        for p in pts:
            p.z = max(p.z, -sz / 2)
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in pts]
    bmesh.ops.convex_hull(bm, input=verts, use_existing_faces=False)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(7), verts=bm.verts, edges=bm.edges)
    if flat_bottom:
        bm_chip(bm, (0, 0, -sz / 2 + 0.002), (0, 0, -1))
    if bevel > 0:
        _bevel_all(bm, bevel, 1)
    if top_mat is not None:
        for f in bm.faces:
            f.material_index = 1 if f.normal.z > 0.75 else 0
    bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(rng.uniform(0, math.tau) if rot_z is None else rot_z, 3, 'Z'),
                     verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return obj_from_bm(name, bm, [mat] + ([top_mat] if top_mat is not None else []))


def fillet(points: Sequence[Sequence[float]], radius: float, steps: int = 4) -> list[Vector]:
    """Round the interior corners of a polyline with circular arcs (pipe elbows)."""
    pts = [Vector(p) for p in points]
    if radius <= 0 or len(pts) < 3:
        return pts
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        d1 = (a - b)
        d2 = (c - b)
        l1, l2 = d1.length, d2.length
        if l1 < 1e-6 or l2 < 1e-6:
            continue
        d1.normalize()
        d2.normalize()
        ang = d1.angle(d2)
        if ang > math.pi - 1e-3:
            out.append(b)
            continue
        t = min(radius / math.tan(ang / 2), l1 * 0.49, l2 * 0.49)
        p1 = b + d1 * t
        p2 = b + d2 * t
        # Quadratic Bezier through the corner approximates the arc closely enough for pipes.
        for s in range(steps + 1):
            u = s / steps
            out.append(p1 * (1 - u) ** 2 + b * 2 * u * (1 - u) + p2 * u * u)
    out.append(pts[-1])
    return out


def tube(name: str, points: Sequence[Sequence[float]], radius: float, mat, sides: int = 10,
         elbow: float = 0.0, caps: bool = True) -> bpy.types.Object:
    """A pipe/cable along a polyline: a bevelled curve, converted to a mesh."""
    pts = fillet(points, elbow) if elbow > 0 else [Vector(p) for p in points]
    cu = bpy.data.curves.new(name + '_curve', 'CURVE')
    cu.dimensions = '3D'
    cu.twist_mode = 'MINIMUM'
    sp = cu.splines.new('POLY')
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (p.x, p.y, p.z, 1.0)
    cu.bevel_mode = 'ROUND'
    cu.bevel_depth = radius
    cu.bevel_resolution = max(0, (sides - 4) // 2)
    cu.use_fill_caps = caps
    cob = link(bpy.data.objects.new(name + '_curve', cu))
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(cob.evaluated_get(dg))
    me.name = name
    delete([cob])
    me.materials.clear()
    me.materials.append(mat)
    for poly in me.polygons:
        poly.material_index = 0
    ob = link(bpy.data.objects.new(name, me))
    # Merge the duplicate seam vertices the curve tessellation leaves, so the tube is one shell.
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    return ob


def rivet(name: str, center: Sequence[float], normal: Sequence[float], mat, radius: float = 0.022,
          height: float = 0.014, segments: int = 6) -> bpy.types.Object:
    """A low domed rivet head sitting on a surface with the given outward normal."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius * 0.55, depth=height)
    bmesh.ops.translate(bm, vec=Vector((0, 0, height / 2)), verts=bm.verts)
    n = Vector(normal).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix()
    bmesh.ops.rotate(bm, cent=Vector(), matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return obj_from_bm(name, bm, [mat])


def blade_tuft(name: str, rng: random.Random, center: Sequence[float], mat, height: float = 0.16,
               blades: int = 7, spread: float = 0.05, width: float = 0.022, up: Sequence[float] = (0, 0, 1)) -> bpy.types.Object:
    """A grass tuft: tapered three-sided blades leaning outward, each bent in two segments."""
    bm = bmesh.new()
    for i in range(blades):
        a = (i / blades) * math.tau + rng.uniform(-0.4, 0.4)
        h = height * rng.uniform(0.6, 1.15)
        lean = rng.uniform(0.25, 0.75)
        ox, oy = math.cos(a) * spread * rng.uniform(0.2, 1.0), math.sin(a) * spread * rng.uniform(0.2, 1.0)
        dx, dy = math.cos(a), math.sin(a)
        w = width * rng.uniform(0.8, 1.2)
        # Base triangle.
        base = []
        for k in range(3):
            t = a + k * math.tau / 3
            base.append(bm.verts.new((ox + math.cos(t) * w, oy + math.sin(t) * w, 0)))
        mid_c = Vector((ox + dx * h * lean * 0.35, oy + dy * h * lean * 0.35, h * 0.55))
        mid = []
        for k in range(3):
            t = a + k * math.tau / 3
            mid.append(bm.verts.new(mid_c + Vector((math.cos(t) * w * 0.55, math.sin(t) * w * 0.55, 0))))
        tip = bm.verts.new((ox + dx * h * lean, oy + dy * h * lean, h))
        for k in range(3):
            k2 = (k + 1) % 3
            bm.faces.new((base[k], base[k2], mid[k2], mid[k]))
            bm.faces.new((mid[k], mid[k2], tip))
        bm.faces.new(list(reversed(base)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    u = Vector(up).normalized()
    if (u - Vector((0, 0, 1))).length > 1e-4:
        bmesh.ops.rotate(bm, cent=Vector(), matrix=Vector((0, 0, 1)).rotation_difference(u).to_matrix(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return obj_from_bm(name, bm, [mat])


def moss_pad(name: str, rng: random.Random, center: Sequence[float], radius: float, height: float, mat,
             up: Sequence[float] = (0, 0, 1), lumps: int = 3) -> bpy.types.Object:
    """A low lumpy moss cushion: a few overlapping flattened faceted domes merged with a hull."""
    bm = bmesh.new()
    pts = []
    for i in range(lumps):
        a = rng.uniform(0, math.tau)
        d = radius * rng.uniform(0.0, 0.55)
        cx, cy = math.cos(a) * d, math.sin(a) * d
        r = radius * rng.uniform(0.45, 0.7)
        hh = height * rng.uniform(0.7, 1.0)
        for k in range(7):
            t = k * math.tau / 7 + rng.uniform(-0.2, 0.2)
            pts.append(Vector((cx + math.cos(t) * r, cy + math.sin(t) * r, 0)))
            pts.append(Vector((cx + math.cos(t) * r * 0.55, cy + math.sin(t) * r * 0.55, hh * 0.8)))
        pts.append(Vector((cx, cy, hh)))
    verts = [bm.verts.new(p) for p in pts]
    bmesh.ops.convex_hull(bm, input=verts)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(4), verts=bm.verts, edges=bm.edges)
    u = Vector(up).normalized()
    if (u - Vector((0, 0, 1))).length > 1e-4:
        bmesh.ops.rotate(bm, cent=Vector(), matrix=Vector((0, 0, 1)).rotation_difference(u).to_matrix(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return obj_from_bm(name, bm, [mat])


def leaf(bm: bmesh.types.BMesh, base: Vector, direction: Vector, normal: Vector, length: float, width: float,
         thick: float = 0.008) -> None:
    """Append a closed, slightly folded leaf (diamond with a raised midrib) to bm."""
    d = direction.normalized()
    n = normal.normalized()
    side = d.cross(n).normalized()
    tip = base + d * length
    mid = base + d * length * 0.42
    l = mid + side * width / 2 - n * width * 0.12
    r = mid - side * width / 2 - n * width * 0.12
    top = mid + n * thick
    bot = mid - n * thick
    vb, vt, vl, vr, vu, vd = (bm.verts.new(p) for p in (base, tip, l, r, top, bot))
    for f in ((vb, vl, vu), (vl, vt, vu), (vt, vr, vu), (vr, vb, vu),
              (vb, vd, vl), (vl, vd, vt), (vt, vd, vr), (vr, vd, vb)):
        bm.faces.new(f)


def vine(name: str, rng: random.Random, path: Sequence[Sequence[float]], normal: Sequence[float],
         stem_mat, leaf_mat, leaf_every: float = 0.09, leaf_len: float = 0.11) -> list[bpy.types.Object]:
    """A creeping vine: a thin stem tube along `path` lying on a surface (outward `normal`), with
    alternating leaves fanned out over the surface."""
    stem = tube(name + '_stem', path, 0.012, stem_mat, sides=6, elbow=0.05)
    pts = [Vector(p) for p in path]
    bm = bmesh.new()
    n = Vector(normal).normalized()
    acc = 0.0
    side = 1
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        seg = (b - a)
        L = seg.length
        if L < 1e-6:
            continue
        d = seg / L
        t = leaf_every * 0.5 - acc
        while t < L:
            p = a + d * t
            lat = d.cross(n).normalized() * side
            ang = rng.uniform(0.6, 1.1)
            ldir = (d * math.cos(ang) + lat * math.sin(ang)).normalized()
            ldir = (ldir + n * 0.25).normalized()
            leaf(bm, p + n * 0.006, ldir, n, leaf_len * rng.uniform(0.75, 1.2), leaf_len * 0.6)
            side = -side
            t += leaf_every * rng.uniform(0.8, 1.2)
        acc = (acc + L) % leaf_every
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    leaves = obj_from_bm(name + '_leaves', bm, [leaf_mat])
    return [stem, leaves]


def leaf_clump(name: str, rng: random.Random, center: Sequence[float], radius: float, mat,
               count: int = 9, up: Sequence[float] = (0, 0, 1)) -> bpy.types.Object:
    """A bushy clump of leaves radiating from a point (plant growing out of a seam)."""
    bm = bmesh.new()
    u = Vector(up).normalized()
    c = Vector(center)
    ref = Vector((1, 0, 0)) if abs(u.x) < 0.9 else Vector((0, 1, 0))
    t1 = u.cross(ref).normalized()
    t2 = u.cross(t1).normalized()
    for i in range(count):
        a = i / count * math.tau + rng.uniform(-0.3, 0.3)
        elev = rng.uniform(0.25, 1.0)
        d = (t1 * math.cos(a) + t2 * math.sin(a)) * math.cos(elev) + u * math.sin(elev)
        n = (u - d * d.dot(u)).normalized() if abs(d.dot(u)) < 0.99 else t1
        leaf(bm, c + d * radius * 0.1, d, n, radius * rng.uniform(0.7, 1.1), radius * 0.55, 0.01)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, [mat])


# ───────────────────────────── booleans, joining ─────────────────────────────

def boolean(target: bpy.types.Object, cutters: Sequence[bpy.types.Object], op: str = 'DIFFERENCE',
            keep: bool = False) -> bpy.types.Object:
    """Exact boolean of target with the cutters (joined first). Faces created by a cutter take the
    cutter's material (groove floors of cracks / runes keep e.g. `rune_glow`)."""
    cutters = [c for c in cutters if c is not None]
    if not cutters:
        return target
    cutter = join(cutters, target.name + '_cutter') if len(cutters) > 1 else cutters[0]
    for m in cutter.data.materials:
        if m.name not in [x.name for x in target.data.materials]:
            target.data.materials.append(m)
    mod = target.modifiers.new('bool', 'BOOLEAN')
    mod.operation = op
    mod.solver = 'EXACT'
    mod.object = cutter
    mod.use_self = True
    mod.material_mode = 'TRANSFER'
    cutter.hide_render = True
    apply_modifiers(target)
    if not keep:
        delete([cutter])
    return target


def apply_modifiers(ob: bpy.types.Object) -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)


def join(objs: Sequence[bpy.types.Object], name: str) -> bpy.types.Object:
    """Join mesh objects into the first (materials merged by name), rename it."""
    objs = [o for o in objs if o is not None]
    bpy.context.view_layer.update()
    for o in objs:
        if o.modifiers:
            apply_modifiers(o)
    if len(objs) == 1:
        objs[0].name = name
        objs[0].data.name = name
        return objs[0]
    # Join without operators: rebuild through bmesh, remapping material indices by name.
    mats: list[bpy.types.Material] = []
    bm = bmesh.new()
    for o in objs:
        me = o.data
        remap = []
        for m in me.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        tmp = me.copy()
        tmp.transform(o.matrix_world)
        for p in tmp.polygons:
            p.material_index = remap[p.material_index] if remap else 0
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    delete(objs)
    out = obj_from_bm(name, bm, mats)
    return out


def finish(ob: bpy.types.Object, sharp_angle: float = 38.0, uv: bool = True) -> bpy.types.Object:
    """Final clean-up of an exported mesh: merge coincident verts, consistent normals, smooth
    shading split at hard edges (flat facets on chamfers read crisply under toon steps), box UVs."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if uv:
        _box_uv(bm)
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(sharp_angle))
    return ob


def _box_uv(bm: bmesh.types.BMesh) -> None:
    """World-space box projection: UVs continue across neighbouring tiles, so any detail texture the
    game applies (noise, grime) tiles seamlessly over the kit."""
    layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for lp in f.loops:
            co = lp.vert.co
            if ax == 0:
                lp[layer].uv = (co.y * (1 if n.x > 0 else -1), co.z)
            elif ax == 1:
                lp[layer].uv = (co.x * (-1 if n.y > 0 else 1), co.z)
            else:
                lp[layer].uv = (co.x, co.y)


# ───────────────────────────── export ─────────────────────────────

def export_glb(objs: Sequence[bpy.types.Object], path: str, animations: bool = False) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.frame_set(0)  # node rest transforms = the first key of each action
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_animations=animations,
        export_animation_mode='ACTIONS',
        export_force_sampling=True,
        export_extras=False,
    )


def bounds(objs: Sequence[bpy.types.Object]) -> tuple[Vector, Vector]:
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != 'MESH':
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def godot_aabb(objs: Sequence[bpy.types.Object]) -> dict:
    """AABB in Godot axes (x, y, z) = Blender (x, z, -y)."""
    lo, hi = bounds(objs)
    gmin = [lo.x, lo.z, -hi.y]
    gmax = [hi.x, hi.z, -lo.y]
    r = lambda v: [round(x, 3) for x in v]
    return {'min': r(gmin), 'max': r(gmax), 'size': r([gmax[i] - gmin[i] for i in range(3)])}


def update_manifest(entries: dict) -> None:
    """Merge our entries into the shared manifest (another engineer owns the decor keys)."""
    os.makedirs(KIT_DIR, exist_ok=True)
    data = {'pieces': {}}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, 'r', encoding='utf-8') as f:
            data = json.load(f)
    data.setdefault('pieces', {})
    for k, v in entries.items():
        data['pieces'][k] = v
    data['pieces'] = {k: data['pieces'][k] for k in sorted(data['pieces'])}
    tmp = MANIFEST + '.tmp'
    with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    os.replace(tmp, MANIFEST)


# ───────────────────────────── preview rendering ─────────────────────────────

# Blender camera rotations (degrees) per view. Godot +Z (front) is Blender -Y.
VIEWS = {
    'iso': (90 - 35, 0, 45),      # the game camera: yaw 45, pitch 35, from Godot +X/+Z
    'front': (90, 0, 0),
    'side': (90, 0, 90),
    'back': (90, 0, 180),
    'three_quarter': (72, 0, 28),
    'top': (0, 0, 0),
}


def setup_render(look: str, width: int, height: int, flat: bool = False) -> None:
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'Standard'
    sh = scene.display.shading
    sh.light = 'FLAT' if flat else 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_object_outline = True
    sh.object_outline_color = hex_rgb(0x140C0A)
    sh.show_cavity = not flat
    sh.cavity_type = 'BOTH'
    sh.cavity_ridge_factor = 0.6
    sh.cavity_valley_factor = 1.0
    sh.curvature_ridge_factor = 0.6
    sh.curvature_valley_factor = 0.8
    sh.show_shadows = False
    scene.display.render_aa = '8'
    if scene.world is None:
        scene.world = bpy.data.worlds.new('World')
    scene.world.color = hex_rgb(BG[look])


def render_view(objs: Sequence[bpy.types.Object], path: str, view: str = 'iso', margin: float = 1.12,
                rot: Sequence[float] | None = None) -> None:
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.get('preview_cam') or bpy.data.cameras.new('preview_cam')
    cam_data.type = 'ORTHO'
    cam = bpy.data.objects.get('preview_cam') or link(bpy.data.objects.new('preview_cam', cam_data))
    r = rot or VIEWS[view]
    cam.rotation_euler = tuple(math.radians(a) for a in r)
    bpy.context.view_layer.update()
    lo, hi = bounds(objs)
    centre = (lo + hi) / 2
    rinv = cam.rotation_euler.to_matrix().inverted()
    # Frame on the projected vertices (not the AABB corners), so wide iso layouts fill the frame.
    xs, ys = [], []
    for o in objs:
        if o.type != 'MESH':
            continue
        mw = rinv @ o.matrix_world.to_3x3()
        off = rinv @ (o.matrix_world.translation - centre)
        for v in o.data.vertices:
            p = mw @ v.co + off
            xs.append(p.x)
            ys.append(p.y)
    if not xs:
        xs, ys = [0.0, 1.0], [0.0, 1.0]
    w = max(xs) - min(xs)
    h = max(ys) - min(ys)
    cx = (max(xs) + min(xs)) / 2
    cy = (max(ys) + min(ys)) / 2
    aspect = scene.render.resolution_x / scene.render.resolution_y
    cam_data.ortho_scale = max(w, h * aspect) * margin
    cam_data.clip_start = 0.01
    cam_data.clip_end = 200
    rm = cam.rotation_euler.to_matrix()
    cam.location = centre + rm @ Vector((cx, cy, 50))
    scene.camera = cam
    scene.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)


def label(text: str, loc: Sequence[float], size: float = 0.16, mat=None, rot=(math.radians(55), 0, math.radians(45))):
    cu = bpy.data.curves.new('label_' + text, 'FONT')
    cu.body = text
    cu.size = size
    cu.align_x = 'CENTER'
    ob = link(bpy.data.objects.new('label_' + text, cu))
    ob.location = loc
    ob.rotation_euler = rot
    if mat is not None:
        cu.materials.append(mat)
    return ob
