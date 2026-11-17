"""
Shared Blender helpers for the OVERDUB decor props and melee weapons.

Everything here builds real meshes through bmesh / curves / modifiers, applies the modifiers, and
leaves plain mesh objects whose origins sit where the asset contract wants them
(docs/GODOT-PORT.md "Asset contract"):

- 1 Blender metre = 1 Godot unit = 1 tile.
- Blender is Z-up; the glTF exporter (export_yup) maps Blender (x, y, z) -> Godot (x, z, -y).
  So a prop's FRONT, which faces +Z in Godot, faces -Y here; Godot +Y (up) is Blender +Z.
- Props: origin on the floor at the footprint centre.
- Weapons: origin at the grip, business end along Godot +Y = Blender +Z.

Colours are flat base colours per material; the material NAME is the styling hook (Godot swaps in
its toon shader and tints by name). Emissive surfaces use a material whose name ends in "_glow".

Run only inside Blender (bpy). Rendering helpers produce Workbench preview stills.
"""
from __future__ import annotations

import math
import os
import random
from typing import Iterable, Sequence

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# ───────────────────────────── palettes ─────────────────────────────
# Role name -> sRGB hex per look. Values follow prototype/src/render/palettes.ts (upper / lower)
# so a model looks right even before Godot re-tints it.

PALETTES: dict[str, dict[str, str]] = {
    "upper": {
        "stone": "#b7906c",
        "stone_light": "#d7b597",
        "stone_dark": "#8a6a52",
        "mortar": "#5d4334",
        "paint_yellow": "#ffc21a",
        "hazard_dark": "#2b2320",
        "metal": "#8e8178",
        "metal_dark": "#5a4c44",
        "trim": "#6b5446",
        "rust": "#d8742a",
        "wood": "#9a6a42",
        "wood_dark": "#6e4a2e",
        "foliage": "#93c22c",
        "foliage_dark": "#5f8f1e",
        "stem": "#4e6a22",
        "rubber": "#2e2a2a",
        "casing": "#e8e0d0",
        "brass": "#c89a3a",
        "canvas": "#e8b030",
        "graffiti": "#ff3fa4",
        "red_paint": "#c8323a",
        "glass": "#bfe9e6",
        "screen_glow": "#4fe6e0",
        "neon_glow": "#ff3d9a",
        "warm_glow": "#ffb45a",
        "rune_glow": "#ffd27a",
        "core_glow": "#ffb347",
        "led_glow": "#7dff9a",
        "tape": "#4a3028",
    },
    "lower": {
        "stone": "#5b5060",
        "stone_light": "#7a6684",
        "stone_dark": "#3e3446",
        "mortar": "#1e1724",
        "paint_yellow": "#ffb020",
        "hazard_dark": "#1a1420",
        "metal": "#5e5066",
        "metal_dark": "#2b2132",
        "trim": "#3a2e44",
        "rust": "#d06a28",
        "wood": "#5a4038",
        "wood_dark": "#3a2a26",
        "foliage": "#568f4c",
        "foliage_dark": "#3a6a40",
        "stem": "#2f4a30",
        "rubber": "#1e1a24",
        "casing": "#6e6278",
        "brass": "#b08a3a",
        "canvas": "#ffb020",
        "graffiti": "#ff3fa4",
        "red_paint": "#a8283a",
        "glass": "#9fe8ff",
        "screen_glow": "#3ff0ff",
        "neon_glow": "#ff2fa0",
        "warm_glow": "#ff8a2a",
        "rune_glow": "#ff3fd0",
        "core_glow": "#ffb347",
        "led_glow": "#3ff0ff",
        "tape": "#3a2420",
    },
}
# The time machine sits in the core depth: same roles, its own chronal amber.
PALETTES["core"] = dict(PALETTES["lower"])
PALETTES["core"].update({
    "metal": "#4c4a66",
    "metal_dark": "#1d1b2c",
    "trim": "#2c2a44",
    "stone": "#47455a",
    "stone_light": "#5e5c80",
    "stone_dark": "#2c2a40",
    "rune_glow": "#ffb347",
    "core_glow": "#ffd27a",
    "screen_glow": "#3ff0ff",
    "neon_glow": "#8a4dff",
})

_LOOK = "upper"


def set_look(look: str) -> None:
    global _LOOK
    if look not in PALETTES:
        raise ValueError(f"unknown look {look}")
    _LOOK = look


def look() -> str:
    return _LOOK


def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_linear(h: str) -> tuple[float, float, float, float]:
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b), 1.0)


def M(role: str) -> bpy.types.Material:
    """The material for a role in the current look (created once per scene)."""
    pal = PALETTES[_LOOK]
    if role not in pal:
        raise KeyError(f"no colour for material role {role!r} in look {_LOOK}")
    m = bpy.data.materials.get(role)
    if m is not None:
        return m
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    col = hex_linear(pal[role])
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    if role.endswith("_glow"):
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 2.5
    m.diffuse_color = col
    return m


# ───────────────────────────── scene ─────────────────────────────

def clear_scene() -> None:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras,
                 bpy.data.lights, bpy.data.images, bpy.data.fonts):
        for d in list(coll):
            coll.remove(d)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


def link(obj: bpy.types.Object) -> bpy.types.Object:
    bpy.context.scene.collection.objects.link(obj)
    return obj


def xform(loc=(0, 0, 0), rot=(0, 0, 0), scale=None) -> Matrix:
    m = Matrix.Translation(Vector(loc)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    if scale is not None:
        s = Matrix.Diagonal((*scale, 1.0)) if isinstance(scale, (tuple, list)) else Matrix.Scale(scale, 4)
        m = m @ s
    return m


def _mesh_obj(bm: bmesh.types.BMesh, name: str, mats: Sequence[bpy.types.Material]) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    return link(bpy.data.objects.new(name, me))


def apply_modifiers(obj: bpy.types.Object) -> bpy.types.Object:
    """Bake the modifier stack (or a curve's bevel) into a plain mesh object."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    if obj.type == "MESH":
        old = obj.data
        obj.modifiers.clear()
        obj.data = me
        if old.users == 0:
            bpy.data.meshes.remove(old)
        return obj
    new = link(bpy.data.objects.new(obj.name + "_m", me))
    new.matrix_world = obj.matrix_world.copy()
    data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if data is not None and data.users == 0 and isinstance(data, bpy.types.Curve):
        bpy.data.curves.remove(data)
    return new


def bevel(obj, width: float, segments: int = 1, angle: float = 40.0, clamp: bool = True):
    if width <= 0:
        return obj
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    mod.use_clamp_overlap = clamp
    mod.miter_outer = "MITER_ARC" if segments > 1 else "MITER_SHARP"
    return apply_modifiers(obj)


def subsurf(obj, levels: int = 1):
    mod = obj.modifiers.new("Subsurf", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    return apply_modifiers(obj)


def solidify(obj, thickness: float, offset: float = 0.0):
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = offset
    mod.use_even_offset = True
    return apply_modifiers(obj)


def mirror_x(obj, merge: float = 0.0005):
    mod = obj.modifiers.new("Mirror", "MIRROR")
    mod.use_axis = (True, False, False)
    mod.use_clip = True
    mod.use_mirror_merge = True
    mod.merge_threshold = merge
    return apply_modifiers(obj)


def transform_obj(obj, m: Matrix):
    obj.data.transform(m)
    obj.data.update()
    return obj


def set_origin(obj, point) -> bpy.types.Object:
    """Move the object's origin to `point` (world space) without moving the geometry."""
    p = Vector(point)
    obj.data.transform(Matrix.Translation(-(p - obj.location)))
    obj.location = p
    return obj


# ───────────────────────────── primitives ─────────────────────────────

def box(size, loc=(0, 0, 0), rot=(0, 0, 0), mat="metal", bev: float = 0.0, seg: int = 1,
        name: str = "box", taper=None) -> bpy.types.Object:
    """Box of `size` centred at `loc`. `taper=(sx, sy)` scales the top face (wedges, plinths)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if taper is not None and v.co.z > 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
    bmesh.ops.transform(bm, matrix=xform(loc, rot), verts=bm.verts)
    obj = _mesh_obj(bm, name, [M(mat)])
    return bevel(obj, bev, seg) if bev else obj


def block(x0, x1, y0, y1, z0, z1, mat="stone", bev=0.0, seg=1, name="block"):
    """Axis-aligned box from extents."""
    return box((x1 - x0, y1 - y0, z1 - z0), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
               mat=mat, bev=bev, seg=seg, name=name)


def cyl(r: float, h: float, loc=(0, 0, 0), rot=(0, 0, 0), mat="metal", n: int = 16, r2=None,
        bev: float = 0.0, seg: int = 1, name: str = "cyl", caps: bool = True) -> bpy.types.Object:
    """Cylinder (or cone with r2) along local Z, centred at `loc`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=n, radius1=r,
                          radius2=r if r2 is None else r2, depth=h)
    bmesh.ops.transform(bm, matrix=xform(loc, rot), verts=bm.verts)
    obj = _mesh_obj(bm, name, [M(mat)])
    return bevel(obj, bev, seg) if bev else obj


def lathe(profile: Sequence[tuple[float, float]], loc=(0, 0, 0), rot=(0, 0, 0), mat="metal",
          n: int = 20, name: str = "lathe", mats_per_segment: Sequence[str] | None = None) -> bpy.types.Object:
    """Revolve a (radius, z) profile about local Z. Points with radius 0 close the ends.

    `mats_per_segment`, if given, has one role per profile segment (len(profile) - 1): each
    revolved band takes that material (barrel rims, reel flanges...).
    """
    bm = bmesh.new()
    verts = [bm.verts.new((max(r, 0.0), 0.0, z)) for r, z in profile]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    for i, e in enumerate(edges):
        e.index = i
    res = bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 0, 1),
                         angle=2 * math.pi, steps=n, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mats = [mat]
    if mats_per_segment:
        roles = list(dict.fromkeys(mats_per_segment))
        mats = roles
        zs = [z for _, z in profile]
        rs = [r for r, _ in profile]
        for f in bm.faces:
            c = f.calc_center_median()
            rc = math.hypot(c.x, c.y)
            # nearest profile segment by (r, z) distance to its midpoint
            best, bd = 0, 1e9
            for i in range(len(profile) - 1):
                mr, mz = (rs[i] + rs[i + 1]) / 2, (zs[i] + zs[i + 1]) / 2
                d = (mr - rc) ** 2 + (mz - c.z) ** 2
                if d < bd:
                    best, bd = i, d
            f.material_index = roles.index(mats_per_segment[best])
    bmesh.ops.transform(bm, matrix=xform(loc, rot), verts=bm.verts)
    return _mesh_obj(bm, name, [M(m) for m in mats])


def prism(points2d: Sequence[tuple[float, float]], depth: float, loc=(0, 0, 0), rot=(0, 0, 0),
          mat="metal", bev: float = 0.0, seg: int = 1, name: str = "prism") -> bpy.types.Object:
    """Extrude a 2D polygon (in local XZ, counter-clockwise seen from -Y) by `depth` along Y,
    centred on Y = 0. Used for blades, brackets and flat cut-outs."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, -depth / 2, z)) for x, z in points2d]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, depth, 0), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=xform(loc, rot), verts=bm.verts)
    obj = _mesh_obj(bm, name, [M(mat)])
    return bevel(obj, bev, seg) if bev else obj


def torus(R: float, r: float, loc=(0, 0, 0), rot=(0, 0, 0), mat="metal", n: int = 32, m: int = 8,
          name: str = "torus", arc: float = 360.0, square: bool = False) -> bpy.types.Object:
    """Torus about local Z. `arc` < 360 gives an open section (elbows); `square` a box section."""
    bm = bmesh.new()
    ring = []
    if square:
        sec = [(R - r, -r), (R + r, -r), (R + r, r), (R - r, r)]
    else:
        sec = [(R + r * math.cos(2 * math.pi * k / m), r * math.sin(2 * math.pi * k / m)) for k in range(m)]
    verts = [bm.verts.new((x, 0, z)) for x, z in sec]
    edges = [bm.edges.new((verts[i], verts[(i + 1) % len(verts)])) for i in range(len(verts))]
    full = arc >= 359.999
    if not full:
        bm.faces.new(verts)
    res = bmesh.ops.spin(bm, geom=verts + edges + ([] if full else list(bm.faces)), cent=(0, 0, 0),
                         axis=(0, 0, 1), angle=math.radians(arc), steps=max(2, int(n * arc / 360)),
                         use_duplicate=False)
    if full:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=xform(loc, rot), verts=bm.verts)
    return _mesh_obj(bm, name, [M(mat)])


def sphere(r: float, loc=(0, 0, 0), rot=(0, 0, 0), mat="metal", subdiv: int = 2, scale=None,
           name: str = "sphere", uv=False, segs=16, rings=8) -> bpy.types.Object:
    bm = bmesh.new()
    if uv:
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    else:
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    bmesh.ops.transform(bm, matrix=xform(loc, rot, scale), verts=bm.verts)
    return _mesh_obj(bm, name, [M(mat)])


def fillet_path(points: Sequence[Sequence[float]], radius: float, segs: int = 5) -> list[Vector]:
    """Round each interior corner of a polyline with a circular arc of `radius` (pipe elbows)."""
    pts = [Vector(p) for p in points]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        d1 = (a - b).normalized()
        d2 = (c - b).normalized()
        ang = d1.angle(d2)
        if ang > math.pi - 1e-3:
            out.append(b)
            continue
        t = radius / math.tan(ang / 2)
        t = min(t, (a - b).length * 0.49, (c - b).length * 0.49)
        p1 = b + d1 * t
        p2 = b + d2 * t
        bis = (d1 + d2).normalized()
        rr = t * math.tan(ang / 2)
        centre = b + bis * math.sqrt(t * t + rr * rr)
        v1 = p1 - centre
        v2 = p2 - centre
        for k in range(segs + 1):
            f = k / segs
            # slerp between v1 and v2 around centre
            q = v1.lerp(v2, f)
            q = q.normalized() * rr
            out.append(centre + q)
    out.append(pts[-1])
    return out


def tube(points: Sequence[Sequence[float]], radius: float, mat="rubber", res: int = 2,
         smooth: bool = True, caps: bool = True, name: str = "tube", resolution_u: int = 6,
         radii: Sequence[float] | None = None, twist: str = "MINIMUM") -> bpy.types.Object:
    """A curve swept with a round bevel, converted to a mesh. smooth=True uses an auto-handle
    Bezier through the points (cables, vines, tape); smooth=False a poly line (pipes after
    fillet_path). `radii` gives per-point radius factors (tapering vines)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_mode = "ROUND"
    cu.bevel_depth = radius
    cu.bevel_resolution = res
    cu.use_fill_caps = caps
    cu.resolution_u = resolution_u
    cu.twist_mode = twist
    if smooth:
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(len(points) - 1)
        for i, p in enumerate(points):
            bp = sp.bezier_points[i]
            bp.co = Vector(p)
            bp.handle_left_type = "AUTO"
            bp.handle_right_type = "AUTO"
            if radii is not None:
                bp.radius = radii[i]
    else:
        sp = cu.splines.new("POLY")
        sp.points.add(len(points) - 1)
        for i, p in enumerate(points):
            sp.points[i].co = (*p, 1.0)
            if radii is not None:
                sp.points[i].radius = radii[i]
    cu.materials.append(M(mat))
    obj = link(bpy.data.objects.new(name, cu))
    return apply_modifiers(obj)


def ribbon(points: Sequence[Sequence[float]], width: float, thickness: float, mat="rubber",
           name: str = "ribbon", resolution_u: int = 8, normal_tilt: float = 0.0) -> bpy.types.Object:
    """A flat strap (tape) along a smooth path: a curve with a rectangular extrusion profile."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.extrude = width / 2
    cu.bevel_depth = thickness / 2
    cu.bevel_resolution = 0
    cu.resolution_u = resolution_u
    cu.use_fill_caps = True
    cu.twist_mode = "Z_UP"
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for i, p in enumerate(points):
        bp = sp.bezier_points[i]
        bp.co = Vector(p)
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
        bp.tilt = normal_tilt
    cu.materials.append(M(mat))
    obj = link(bpy.data.objects.new(name, cu))
    return apply_modifiers(obj)


def rock(seed: int, size: float, loc=(0, 0, 0), rot_z: float = 0.0, mat="stone", squash=0.7,
         name: str = "rock", detail: int = 1) -> bpy.types.Object:
    """A faceted rubble chunk: a displaced, then planar-decimated icosphere sitting on Z=0."""
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1 + detail, radius=size / 2)
    off = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))
    sx, sy = rng.uniform(0.85, 1.25), rng.uniform(0.75, 1.1)
    for v in bm.verts:
        n = noise.noise(v.co * (3.2 / size) + off)
        v.co *= 1.0 + 0.32 * n
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= squash
    # flat underside
    minz = min(v.co.z for v in bm.verts)
    cut = minz + size * 0.12
    for v in bm.verts:
        if v.co.z < cut:
            v.co.z = cut
    for v in bm.verts:
        v.co.z -= cut
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=size * 0.01)
    bmesh.ops.transform(bm, matrix=xform(loc, (0, 0, rot_z)), verts=bm.verts)
    obj = _mesh_obj(bm, name, [M(mat)])
    mod = obj.modifiers.new("Dec", "DECIMATE")
    mod.decimate_type = "DISSOLVE"
    mod.angle_limit = math.radians(14)
    obj = apply_modifiers(obj)
    return obj


def leaf_bmesh(bm: bmesh.types.BMesh, m: Matrix, length: float, width: float, fold: float = 0.35,
               thick: float = 0.01, mat_index: int = 0, detailed: bool = False) -> None:
    """Append a closed, folded leaf to `bm`, transformed by `m`.

    Leaf space: length along +Y from the stem at the origin, width along X, face normal +Z (the
    two halves fold up along the midrib by `fold` * width). It is a thin closed solid (a
    hand-built solidify), so it renders from both sides and takes an outline.
    """
    Ln, W = length, width
    if detailed:
        top = [(0, 0), (W * 0.5, 0.35 * Ln), (W * 0.34, 0.72 * Ln), (0, Ln), (-W * 0.34, 0.72 * Ln),
               (-W * 0.5, 0.35 * Ln)]
    else:
        top = [(0, 0), (W * 0.5, 0.42 * Ln), (0, Ln), (-W * 0.5, 0.42 * Ln)]
    lift = W * fold * 0.5
    up = [bm.verts.new(m @ Vector((x, y, (lift if abs(x) > 1e-6 else 0.0) + thick / 2))) for x, y in top]
    dn = [bm.verts.new(m @ Vector((x, y, (lift if abs(x) > 1e-6 else 0.0) - thick / 2))) for x, y in top]
    n = len(top)
    # top surface as a fan of triangles around the midrib, folded
    faces = []
    if detailed:
        tris = [(0, 1, 2), (0, 2, 3), (0, 3, 4), (0, 4, 5)]
    else:
        tris = [(0, 1, 2), (0, 2, 3)]
    for a, b, c in tris:
        faces.append(bm.faces.new((up[a], up[b], up[c])))
        faces.append(bm.faces.new((dn[c], dn[b], dn[a])))
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((up[j], up[i], dn[i], dn[j])))
    for f in faces:
        f.material_index = mat_index


def basis(u: Vector, n: Vector, origin) -> Matrix:
    """Matrix whose local +Y is `u` and local +Z is `n` (orthogonalised), at `origin`."""
    y = Vector(u).normalized()
    z = Vector(n) - y * Vector(n).dot(y)
    if z.length < 1e-6:
        z = y.orthogonal()
    z.normalize()
    x = y.cross(z)
    m = Matrix((
        (x.x, y.x, z.x, origin[0]),
        (x.y, y.y, z.y, origin[1]),
        (x.z, y.z, z.z, origin[2]),
        (0, 0, 0, 1),
    ))
    return m


def leaf(length: float, width: float, mat="foliage", fold: float = 0.35, name: str = "leaf") -> bpy.types.Object:
    """A single pointed leaf along +Y (see leaf_bmesh)."""
    bm = bmesh.new()
    leaf_bmesh(bm, Matrix.Identity(4), length, width, fold, detailed=True)
    return _mesh_obj(bm, name, [M(mat)])


def leaves_obj(specs, mats: Sequence[str], name: str = "leaves") -> bpy.types.Object:
    """Many leaves in one object. `specs` is a list of (matrix, length, width, mat_index)."""
    bm = bmesh.new()
    for m, ln, w, mi in specs:
        leaf_bmesh(bm, m, ln, w, mat_index=mi)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_obj(bm, name, [M(x) for x in mats])


def rest_on_floor(obj, floor: float = 0.0):
    """Lift a loose part so its lowest point sits on the floor (never sinks below Y = 0)."""
    lo = min((v.co.z for v in obj.data.vertices), default=floor)
    if lo < floor:
        obj.data.transform(Matrix.Translation((0, 0, floor - lo)))
    return obj


def place(obj, loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
    """Bake a transform into the mesh data (object stays at the origin)."""
    return transform_obj(obj, xform(loc, rot, scale))


def join(objs: Iterable[bpy.types.Object], name: str) -> bpy.types.Object:
    objs = [o for o in objs if o is not None]
    if not objs:
        raise ValueError("nothing to join")
    for o in objs:
        if o.type != "MESH":
            raise TypeError(f"{o.name} is not a mesh")
        # bake object transform into data
        if o.matrix_world != Matrix.Identity(4):
            o.data.transform(o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
    base = objs[0]
    if len(objs) > 1:
        with bpy.context.temp_override(active_object=base, selected_editable_objects=objs,
                                       selected_objects=objs):
            bpy.ops.object.join()
    base.name = name
    base.data.name = name
    _dedupe_material_slots(base)
    return base


def _dedupe_material_slots(obj):
    me = obj.data
    names = [m.name if m else None for m in me.materials]
    uniq = list(dict.fromkeys(names))
    if len(uniq) == len(names):
        return
    remap = [uniq.index(n) for n in names]
    for p in me.polygons:
        p.material_index = remap[p.material_index]
    mats = [bpy.data.materials.get(n) for n in uniq]
    me.materials.clear()
    for m in mats:
        me.materials.append(m)


def finish(obj, smooth_angle: float = 32.0, weld: float = 0.0) -> bpy.types.Object:
    """Final clean-up: optional weld, smooth shading split at hard edges (`smooth_angle`)."""
    me = obj.data
    if weld > 0:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
        bm.to_mesh(me)
        bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(smooth_angle))
    me.validate(clean_customdata=False)
    me.update()
    return obj


def flat(obj):
    for p in obj.data.polygons:
        p.use_smooth = False
    return obj


def tri_count(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def bounds(objs) -> tuple[Vector, Vector]:
    bpy.context.view_layer.update()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


# ───────────────────────────── export ─────────────────────────────

def export_glb(path: str, objs: Sequence[bpy.types.Object]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Only surfaces the game draws on keep texture coordinates; modelling ops (bevel, curves,
    # booleans) leave stray UV layers on everything else.
    for o in objs:
        if o.type == "MESH" and o.name != "Screen":
            while o.data.uv_layers:
                o.data.uv_layers.remove(o.data.uv_layers[0])
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_materials="EXPORT",
        export_normals=True,
        export_tangents=False,
        export_extras=False,
        export_image_format="NONE",
    )


# ───────────────────────────── preview rendering ─────────────────────────────

VIEWS = {
    # name: (yaw degrees from front (-Y) toward +X, pitch degrees above horizon)
    "front": (0.0, 0.0),
    "side": (90.0, 0.0),
    "back": (180.0, 0.0),
    "threequarter": (40.0, 18.0),
    # The game camera: orthographic, yaw 45, pitch 35, seeing the Godot +Z (Blender -Y) and +X faces.
    "iso": (45.0, 35.0),
}


def _setup_render(width: int, height: int, bg="#3a3634"):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = width
    sc.render.resolution_y = height
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.display_settings.display_device = "sRGB"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.object_outline_color = (0.02, 0.015, 0.02)
    sh.show_cavity = True
    sh.cavity_type = "WORLD"
    sh.cavity_ridge_factor = 0.6
    sh.cavity_valley_factor = 1.0
    sh.show_specular_highlight = False
    sc.display.render_aa = "8"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    sc.world.color = hex_linear(bg)[:3]


def _camera():
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cd = bpy.data.cameras.new("PreviewCam")
        cam = link(bpy.data.objects.new("PreviewCam", cd))
    bpy.context.scene.camera = cam
    return cam


def view_dir(yaw: float, pitch: float) -> Vector:
    """Unit vector from the target toward the camera."""
    y, p = math.radians(yaw), math.radians(pitch)
    return Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))


def render_view(path: str, objs, yaw: float, pitch: float, width=640, height=640, margin=1.12,
                bg="#3a3634", ortho_scale: float | None = None, centre=None) -> None:
    _setup_render(width, height, bg)
    cam = _camera()
    cam.data.type = "ORTHO"
    d = view_dir(yaw, pitch)
    rotq = d.to_track_quat("Z", "Y")
    right = rotq @ Vector((1, 0, 0))
    up = rotq @ Vector((0, 1, 0))
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        mw = o.matrix_world
        pts += [mw @ v.co for v in o.data.vertices]
    if not pts:
        return
    xs = [p.dot(right) for p in pts]
    ys = [p.dot(up) for p in pts]
    zs = [p.dot(d) for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    ext_x, ext_y = max(xs) - min(xs), max(ys) - min(ys)
    aspect = width / height
    if ortho_scale is None:
        # Blender's ortho_scale spans the larger render dimension.
        if aspect >= 1:
            ortho_scale = max(ext_x, ext_y * aspect) * margin
        else:
            ortho_scale = max(ext_y, ext_x / aspect) * margin
    if centre is not None:
        c = Vector(centre)
        cx, cy = c.dot(right), c.dot(up)
    cam.data.ortho_scale = ortho_scale
    dist = max(zs) + 20.0
    cam.location = right * cx + up * cy + d * dist
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = rotq
    cam.data.clip_start = 0.1
    cam.data.clip_end = dist + 60.0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_standard_views(out_dir: str, objs, size: int = 560, thumb_h: int = 160) -> None:
    for name, (yaw, pitch) in VIEWS.items():
        render_view(os.path.join(out_dir, f"{name}.png"), objs, yaw, pitch, size, size)
    # In-game-sized check: 160 px tall at the isometric angle.
    render_view(os.path.join(out_dir, "thumb_iso.png"), objs, *VIEWS["iso"], width=thumb_h, height=thumb_h,
                margin=1.05)


def label(text: str, loc, size=0.18, rot=(0, 0, 0), mat="hazard_dark") -> bpy.types.Object:
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    cu.materials.append(M(mat))
    obj = link(bpy.data.objects.new("label", cu))
    obj.location = loc
    obj.rotation_euler = [math.radians(a) for a in rot]
    return obj


# ───────────────────────────── utility-prop helpers ─────────────────────────────

def hazard_box(size, loc=(0, 0, 0), rot=(0, 0, 0), period: float = 0.12,
               mats=("paint_yellow", "hazard_dark"), bev: float = 0.0, name: str = "hazard",
               direction=(1.0, 0.0, 1.0)) -> bpy.types.Object:
    """A box painted with diagonal hazard stripes as real geometry: the box is cut by parallel
    planes (normal `direction`) every half period and the bands alternate materials."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    nrm = Vector(direction).normalized()
    proj = [v.co.dot(nrm) for v in bm.verts]
    half = period / 2
    k0 = math.floor(min(proj) / half) + 1
    k1 = math.ceil(max(proj) / half)
    for k in range(k0, k1):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=nrm * (k * half),
                               plane_no=nrm)
    for f in bm.faces:
        c = f.calc_center_median()
        f.material_index = int(math.floor(c.dot(nrm) / half)) % 2
    bmesh.ops.transform(bm, matrix=xform(loc, rot), verts=bm.verts)
    obj = _mesh_obj(bm, name, [M(mats[0]), M(mats[1])])
    return bevel(obj, bev, 1) if bev else obj


def screen_quad(name: str, w: float, h: float, loc=(0, 0, 0), rot=(0, 0, 0), mat="screen_glow",
                cols: int = 1, rows: int = 1) -> bpy.types.Object:
    """A flat screen facing -Y (Godot +Z) with clean 0-1 UVs: u left->right and v bottom->top as
    seen from the front (glTF/Godot: UV (0,0) is the top-left corner). The game draws on it."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    grid = [[bm.verts.new((-w / 2 + w * i / cols, 0.0, -h / 2 + h * j / rows)) for j in range(rows + 1)]
            for i in range(cols + 1)]
    for i in range(cols):
        for j in range(rows):
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
            for loop in f.loops:
                co = loop.vert.co
                loop[uvl].uv = ((co.x + w / 2) / w, (co.z + h / 2) / h)
    bmesh.ops.transform(bm, matrix=xform(loc, rot), verts=bm.verts)
    obj = _mesh_obj(bm, name, [M(mat)])
    return set_origin(obj, loc)


def fan_blades(r: float, n: int = 5, hub: float = 0.05, pitch: float = 28.0, thick: float = 0.012,
               mat="metal", hub_mat="metal_dark", name: str = "Fan", chord: float | None = None) -> bpy.types.Object:
    """A fan rotor about local Y (blades in the XZ plane), centred on the origin."""
    parts = [cyl(hub, thick * 3.2, rot=(90, 0, 0), mat=hub_mat, n=12)]
    chord = chord or r * 0.55
    for k in range(n):
        a = 360.0 * k / n
        blade = prism([(hub * 0.6, -chord * 0.35), (r * 0.98, -chord * 0.5), (r, chord * 0.2),
                       (hub * 0.6, chord * 0.3)], thick, mat=mat, name="blade")
        transform_obj(blade, xform((0, 0, 0), (0, a, 0)) @ xform((0, 0, 0), (pitch, 0, 0)))
        parts.append(blade)
    return join(parts, name)


def bolt_ring(n: int, R: float, y: float, r: float = 0.012, mat="metal_dark", centre=(0, 0)) -> list:
    """Bolt heads around a circle in the XZ plane at depth y, facing -Y."""
    out = []
    for k in range(n):
        a = 2 * math.pi * k / n
        out.append(cyl(r, 0.012, loc=(centre[0] + math.cos(a) * R, y, centre[1] + math.sin(a) * R),
                       rot=(90, 0, 0), mat=mat, n=6))
    return out
