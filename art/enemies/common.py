"""Shared Blender helpers for the enemy family ("ruin-security machines", see STYLE.md).

Used by grunt.py, stalker.py, shielder.py and drone.py (and free for the other enemy scripts).
Everything here is plain bpy/bmesh so a type script can stay a readable list of parts, bones and
poses:

    parts   - modelling helpers that return mesh objects already placed in armature space
              (box/cyl/lathe/tube/extrude, bevel + subdivision + solidify + mirror modifiers that
              finalize() applies, inset panel seams, hazard bands split as faces, rune grooves).
    rig     - make_rig() builds the armature `Rig`; bind() joins the parts into one skinned mesh:
              automatic (heat) weights first, then a corrective pass that makes every rigid part
              100 % one bone and limits soft parts (cables, bellows) to the bones they may follow.
    anim    - Anim: author actions with rotations given in ARMATURE axes (relative to the parent),
              converted to each bone's local quaternion, with sign continuity and exact frame ranges.
    export  - export_glb() per docs/GODOT-PORT.md (glb, +Y up, actions as separate animations).
    preview - Workbench renders: turnaround, isometric (ortho, yaw 45, pitch 35), thumbnails at game
              size, animation contact sheets; composed into PNGs with numpy.

Blender axes: Z up, the model faces -Y (= +Z in Godot), origin on the floor at the footprint centre.
Rotation convention used by Anim (armature axes, degrees):
    X+  pitches the top of an upright part FORWARD (toward -Y); a hanging leg swings BACK.
    Y+  rolls an upright part toward the model's LEFT (+X).
    Z+  yaws the front toward the model's LEFT (+X).
"""
from __future__ import annotations

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
MODEL_DIR = os.path.join(REPO, "assets", "models", "enemies")
PREVIEW_DIR = os.path.join(REPO, "art", "previews", "enemies")
FPS = 30

# --------------------------------------------------------------------------------------------
# Palette (STYLE.md). Hex sRGB; converted to linear for the glTF base colour factor.
# --------------------------------------------------------------------------------------------
PALETTE = {
    "ceramic": "#c8bba3",
    "ceramic_dark": "#8f8270",
    "metal": "#3a3744",
    "metal_light": "#6a6674",
    "brass": "#c9962f",
    "hazard": "#ffbf1a",
    "hazard_dark": "#1e1c22",
    "cable": "#24222a",
    "tape": "#4a2f1e",
    "speaker": "#2c2a33",
    "screen": "#1b2a2e",
    "blade": "#d9dde4",
    "eye_glow": "#ff6a1a",
    "rune_glow": "#58f0dc",
    "meter_glow": "#ffd04a",
    "charge_glow": "#ff8a3a",
    "shield_glow": "#7ff4ff",
}


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def material(name: str) -> bpy.types.Material:
    """Flat base-colour material by palette name; names ending in _glow are emissive."""
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    srgb = hex_rgb(PALETTE[name])
    lin = tuple(srgb_to_linear(c) for c in srgb)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Metallic"].default_value = 0.0
    if name.endswith("_glow"):
        bsdf.inputs["Emission Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    # Workbench (previews) shows the viewport colour, which is sRGB-ish display colour.
    m.diffuse_color = (*srgb, 1.0)
    return m


# --------------------------------------------------------------------------------------------
# Scene
# --------------------------------------------------------------------------------------------

def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def script_args() -> list[str]:
    argv = sys.argv
    return argv[argv.index("--") + 1:] if "--" in argv else []


def link(obj: bpy.types.Object) -> bpy.types.Object:
    bpy.context.scene.collection.objects.link(obj)
    return obj


def activate(obj: bpy.types.Object, select_only: bool = True) -> None:
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    if select_only:
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


# --------------------------------------------------------------------------------------------
# Parts: every helper returns a linked mesh object with transforms applied (mesh in armature
# space). Custom properties carry skinning intent:
#   obj["bone"]  = bone name for a rigid part (weight 1.0 on that bone)
#   obj["soft"]  = comma-separated bones a soft part may follow (auto weights limited to them)
# Modifiers stay live until finalize() applies them (so the type script can stack mirror / bevel
# / subdivision / solidify as a modeller would).
# --------------------------------------------------------------------------------------------

def _obj_from_bm(name: str, bm: bmesh.types.BMesh, mats: list[str]) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for mn in mats:
        me.materials.append(material(mn))
    obj = bpy.data.objects.new(name, me)
    return link(obj)


def place(obj: bpy.types.Object, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)) -> bpy.types.Object:
    """Bake a transform (rot in degrees, XYZ) into the mesh data."""
    m = Matrix.LocRotScale(Vector(loc), Euler([math.radians(a) for a in rot], "XYZ"),
                           Vector(scale if isinstance(scale, (tuple, list)) else (scale,) * 3))
    obj.data.transform(m)
    obj.data.update()
    return obj


def along(obj: bpy.types.Object, a, b, center: float = 0.5) -> bpy.types.Object:
    """Re-orient a part built along local Z (centred on the origin) so its Z axis runs from a to b,
    centred at the fraction `center` of the way."""
    va, vb = Vector(a), Vector(b)
    q = Vector((0, 0, 1)).rotation_difference((vb - va).normalized())
    obj.data.transform(Matrix.Translation(va.lerp(vb, center)) @ q.to_matrix().to_4x4())
    obj.data.update()
    return obj


def tag(obj: bpy.types.Object, bone: str | None = None, soft: list[str] | None = None) -> bpy.types.Object:
    if bone:
        obj["bone"] = bone
    if soft:
        obj["soft"] = ",".join(soft)
    return obj


def bevel(obj, width=0.01, segments=2, limit_deg=40.0, harden=True, clamp=True):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(limit_deg)
    mod.harden_normals = False
    mod.use_clamp_overlap = clamp
    return obj


def subsurf(obj, levels=1):
    mod = obj.modifiers.new("Subdivision", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    return obj


def solidify(obj, thickness=0.02, offset=-1.0):
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = offset
    mod.use_even_offset = True
    return obj


def mirror_x(obj, merge=True):
    mod = obj.modifiers.new("Mirror", "MIRROR")
    mod.use_axis = (True, False, False)
    mod.use_clip = merge
    mod.use_mirror_merge = merge
    mod.merge_threshold = 1e-4
    return obj


# Family smoothness (quality pass): every round form is built with at least ROUND_MIN segments so
# no silhouette shows facets at preview or game scale. Counts of 8 or fewer are deliberate
# polygons (hex bolts and hubs, the shielder's octagonal pillar) and are left alone.
ROUND_MIN = 24
POLY_MAX = 8


def _round(n: int) -> int:
    return n if n <= POLY_MAX else max(n, ROUND_MIN)


def box(name, size, loc=(0, 0, 0), rot=(0, 0, 0), mat="ceramic", taper=None, cuts=0) -> bpy.types.Object:
    """Axis box of `size` (x, y, z). `taper` = (sx, sy) scales the top face (+Z) for wedges/frusta.
    `cuts` adds that many edge loops around Z (for later bending/insets)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if cuts:
        edges = [e for e in bm.edges if abs((e.verts[0].co - e.verts[1].co).normalized().z) > 0.99]
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=cuts, use_grid_fill=True)
    if taper:
        top = max(v.co.z for v in bm.verts)
        bot = min(v.co.z for v in bm.verts)
        for v in bm.verts:
            t = (v.co.z - bot) / max(1e-9, top - bot)
            v.co.x *= 1 + (taper[0] - 1) * t
            v.co.y *= 1 + (taper[1] - 1) * t
    obj = _obj_from_bm(name, bm, [mat])
    return place(obj, loc, rot)


def cyl(name, r1, r2, depth, loc=(0, 0, 0), rot=(0, 0, 0), verts=16, mat="metal", cap=True) -> bpy.types.Object:
    """Cylinder/cone along local Z, centred; r1 bottom radius, r2 top radius."""
    bm = bmesh.new()
    verts = _round(verts)
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=verts, radius1=r1, radius2=r2, depth=depth)
    obj = _obj_from_bm(name, bm, [mat])
    return place(obj, loc, rot)


def lathe(name, profile, loc=(0, 0, 0), rot=(0, 0, 0), segments=16, mat="ceramic", mats=None) -> bpy.types.Object:
    """Surface of revolution about local Z from a (radius, z) profile listed bottom to top.
    Points with radius 0 close the pole. `mats` optionally gives a material index per profile
    segment (index into a material list `mat` if mat is a list)."""
    bm = bmesh.new()
    segments = _round(segments)
    vs = [bm.verts.new((max(r, 0.0), 0.0, z)) for r, z in profile]
    edges = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    res = bmesh.ops.spin(bm, geom=vs + edges, cent=(0, 0, 0), axis=(0, 0, 1),
                         angle=math.radians(360), steps=segments, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mat_list = mat if isinstance(mat, list) else [mat]
    if mats:
        # Material per profile segment: classify faces by their mean height.
        zs = [z for _, z in profile]
        for f in bm.faces:
            fz = sum(v.co.z for v in f.verts) / len(f.verts)
            seg = 0
            for i in range(len(zs) - 1):
                lo, hi = min(zs[i], zs[i + 1]), max(zs[i], zs[i + 1])
                if lo - 1e-6 <= fz <= hi + 1e-6:
                    seg = i
                    break
            f.material_index = mats[min(seg, len(mats) - 1)]
    obj = _obj_from_bm(name, bm, mat_list)
    return place(obj, loc, rot)


def torus(name, major, minor, loc=(0, 0, 0), rot=(0, 0, 0), seg=24, ring=8, mat="brass") -> bpy.types.Object:
    """Torus around local Z."""
    bm = bmesh.new()
    seg, ring = max(seg, 32), max(ring, 8)
    rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        c, s = math.cos(a), math.sin(a)
        row = []
        for j in range(ring):
            b = 2 * math.pi * j / ring
            r = major + minor * math.cos(b)
            row.append(bm.verts.new((r * c, r * s, minor * math.sin(b))))
        rings.append(row)
    for i in range(seg):
        for j in range(ring):
            a, b = rings[i][j], rings[i][(j + 1) % ring]
            c, d = rings[(i + 1) % seg][(j + 1) % ring], rings[(i + 1) % seg][j]
            bm.faces.new((a, b, c, d))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = _obj_from_bm(name, bm, [mat])
    return place(obj, loc, rot)


def extrude_poly(name, pts, depth, loc=(0, 0, 0), rot=(0, 0, 0), mat="metal", plane="XZ") -> bpy.types.Object:
    """Prism from a 2D outline (counter-clockwise) in `plane`, extruded symmetrically by depth.
    plane XZ: outline in X/Z, thickness along Y (a plate facing front). XY: thickness along Z.
    YZ: outline in Y/Z, thickness along X (a side fin)."""
    bm = bmesh.new()
    if plane == "XZ":
        vs = [bm.verts.new((x, depth / 2, y)) for x, y in pts]
        n = Vector((0, -depth, 0))
    elif plane == "XY":
        vs = [bm.verts.new((x, y, -depth / 2)) for x, y in pts]
        n = Vector((0, 0, depth))
    else:
        vs = [bm.verts.new((depth / 2, x, y)) for x, y in pts]
        n = Vector((-depth, 0, 0))
    face = bm.faces.new(vs)
    res = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=n, verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Triangulate n-gon caps cleanly (beauty fill) so exporters never guess.
    caps = [f for f in bm.faces if len(f.verts) > 4]
    if caps:
        bmesh.ops.triangulate(bm, faces=caps, quad_method="BEAUTY", ngon_method="BEAUTY")
    obj = _obj_from_bm(name, bm, [mat])
    return place(obj, loc, rot)


def tube(name, points, radius, loc=(0, 0, 0), rot=(0, 0, 0), mat="cable", res=6, smooth=True,
         radii=None, segments=2) -> bpy.types.Object:
    """A cable/hose/pipe: a curve through `points` with a round bevel, converted to mesh.
    `smooth` uses a Bezier spline with auto handles; otherwise a poly line. `radii` scales the
    radius per point (tapered tails)."""
    cu = bpy.data.curves.new(name + "_curve", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_mode = "ROUND"
    cu.bevel_depth = radius
    cu.bevel_resolution = max(2, res // 2 - 1)   # >= 12 sides around: cables read round
    cu.use_fill_caps = True
    cu.resolution_u = max(segments * 2, 6)
    if smooth:
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(len(points) - 1)
        for i, p in enumerate(points):
            bp = sp.bezier_points[i]
            bp.co = Vector(p)
            bp.handle_left_type = "AUTO"
            bp.handle_right_type = "AUTO"
            bp.radius = radii[i] if radii else 1.0
    else:
        sp = cu.splines.new("POLY")
        sp.points.add(len(points) - 1)
        for i, p in enumerate(points):
            sp.points[i].co = (*p, 1.0)
            sp.points[i].radius = radii[i] if radii else 1.0
    cobj = bpy.data.objects.new(name + "_c", cu)
    link(cobj)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(cobj.evaluated_get(dg))
    bpy.data.objects.remove(cobj)
    bpy.data.curves.remove(cu)
    me.materials.clear()
    me.materials.append(material(mat))
    obj = link(bpy.data.objects.new(name, me))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    return place(obj, loc, rot)


_CUTTERS: list[bpy.types.Object] = []


def chip(obj, loc, size, rot=(0, 0, 0)) -> bpy.types.Object:
    """Knock a chip out of a ceramic plate: boolean DIFFERENCE with a rotated cutter box (applied
    by finalize/bind; the cutter is deleted afterwards)."""
    cutter = box(obj.name + "_chip", size, loc=loc, rot=rot, mat="ceramic")
    cutter.hide_render = True
    cutter.display_type = "WIRE"
    _CUTTERS.append(cutter)
    mod = obj.modifiers.new("Chip", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    return obj


def cut(obj, cutter: bpy.types.Object) -> bpy.types.Object:
    """Boolean DIFFERENCE with any cutter mesh (e.g. reel windows); cutter removed after bind."""
    cutter.hide_render = True
    cutter.display_type = "WIRE"
    _CUTTERS.append(cutter)
    mod = obj.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    return obj


def remove_cutters() -> None:
    for c in _CUTTERS:
        if c.name in bpy.data.objects:
            bpy.data.objects.remove(c)
    _CUTTERS.clear()


def parent_local(parent_rot_deg, world_delta) -> tuple:
    """Offset to key on a child bone so it moves by `world_delta` (armature axes) while its parent
    chain is rotated by `parent_rot_deg` (accumulated XYZ degrees): R^-1 * delta."""
    r = Euler([math.radians(a) for a in parent_rot_deg], "XYZ").to_matrix()
    return tuple(r.inverted() @ Vector(world_delta))


def set_material_where(obj, mat: str, pred) -> None:
    """Assign `mat` to faces whose centre satisfies pred(Vector) (object space)."""
    me = obj.data
    idx = me.materials.find(mat)
    if idx < 0:
        me.materials.append(material(mat))
        idx = len(me.materials) - 1
    for p in me.polygons:
        if pred(p.center):
            p.material_index = idx


def inset_faces(obj, pred, thickness=0.01, depth=-0.008, mat: str | None = None, individual=True) -> None:
    """Panel seams / sockets: inset the faces whose centre+normal satisfy pred(center, normal) and push
    the inner faces along their normal by `depth` (negative = recessed). Optionally recolour them."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    faces = [f for f in bm.faces if pred(f.calc_center_median(), f.normal)]
    if faces:
        if individual:
            res = bmesh.ops.inset_individual(bm, faces=faces, thickness=thickness, depth=depth, use_even_offset=True)
        else:
            res = bmesh.ops.inset_region(bm, faces=faces, thickness=thickness, depth=depth, use_even_offset=True)
        if mat:
            me = obj.data
            idx = me.materials.find(mat)
            if idx < 0:
                me.materials.append(material(mat))
                idx = len(me.materials) - 1
            for f in faces:
                f.material_index = idx
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def slice_planes(obj, normal, offsets) -> None:
    """Add edge loops by cutting the mesh with planes (normal, distance from origin) — the loop-cut
    step before bending a slab (e.g. curving the shielder's shield)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    n = Vector(normal).normalized()
    for d in offsets:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=n * d, plane_no=n)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def hazard_bands(obj, direction=(1, 0, 1), period=0.06, pred=None) -> None:
    """Split the faces of `obj` (optionally only those whose centre satisfies pred) along parallel
    planes and alternate `hazard` / `hazard_dark` by band: yellow/black diagonal service paint as
    real faces (no texture)."""
    me = obj.data
    for name in ("hazard", "hazard_dark"):
        if me.materials.find(name) < 0:
            me.materials.append(material(name))
    ih, idk = me.materials.find("hazard"), me.materials.find("hazard_dark")
    bm = bmesh.new()
    bm.from_mesh(me)
    d = Vector(direction).normalized()
    proj = [v.co.dot(d) for v in bm.verts]
    lo, hi = min(proj), max(proj)
    k = math.floor(lo / period)
    while k * period < hi:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=d * (k * period), plane_no=d)
        k += 1
    for f in bm.faces:
        c = f.calc_center_median()
        if pred is not None and not pred(c):
            continue
        band = math.floor(c.dot(d) / period)
        f.material_index = ih if band % 2 == 0 else idk
    bm.to_mesh(me)
    bm.free()
    me.update()


def rune_groove(name, strokes, loc=(0, 0, 0), rot=(0, 0, 0), width=0.012, height=0.006,
                mat="rune_glow") -> bpy.types.Object:
    """Angular rune glyph on the local XZ plane (facing -Y): each stroke is a polyline of (x, z)
    points; strokes become thin bars of square-ish section, slightly proud of the surface so the
    ink outline catches them. Place it against a plate with loc/rot."""
    bm = bmesh.new()
    for stroke in strokes:
        for (x0, z0), (x1, z1) in zip(stroke[:-1], stroke[1:]):
            a, b = Vector((x0, 0, z0)), Vector((x1, 0, z1))
            ln = (b - a).length
            if ln < 1e-6:
                continue
            ret = bmesh.ops.create_cube(bm, size=1.0)
            vs = ret["verts"]
            bmesh.ops.scale(bm, vec=Vector((ln + width, height, width)), verts=vs)
            ang = math.atan2(z1 - z0, x1 - x0)
            bmesh.ops.rotate(bm, verts=vs, cent=(0, 0, 0), matrix=Matrix.Rotation(-ang, 3, "Y"))
            bmesh.ops.translate(bm, vec=(a + b) / 2, verts=vs)
    obj = _obj_from_bm(name, bm, [mat])
    return place(obj, loc, rot)


def shade(obj, angle_deg=40.0) -> None:
    """Smooth shading with sharp edges above angle_deg (hard mechanical creases stay crisp)."""
    me = obj.data
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(angle_deg))
    except AttributeError:  # pragma: no cover - older API
        pass


def apply_modifiers(obj) -> None:
    if not obj.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)


def join(objs, name: str) -> bpy.types.Object:
    objs = [o for o in objs if o is not None]
    activate(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


def merge_materials(obj) -> None:
    """Collapse duplicate material slots (same material) left by joins."""
    me = obj.data
    first: dict[str, int] = {}
    remap = []
    for i, m in enumerate(me.materials):
        key = m.name if m else ""
        if key not in first:
            first[key] = len(first)
        remap.append(first[key])
    if len(first) == len(me.materials):
        return
    idx = np.zeros(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", idx)
    idx = np.array(remap, dtype=np.int32)[idx]
    names = [None] * len(first)
    for k, v in first.items():
        names[v] = k
    me.materials.clear()
    for n in names:
        me.materials.append(bpy.data.materials[n])
    me.polygons.foreach_set("material_index", idx)
    me.update()


# --------------------------------------------------------------------------------------------
# Rig
# --------------------------------------------------------------------------------------------

AXLE_X_PREFIX = "reel."   # same convention as common2.AXLE_X_PREFIX


def make_rig(bones: list[tuple], name: str = "Rig") -> bpy.types.Object:
    """bones: (name, head, tail, parent or None[, roll_deg[, deform[, connect]]])."""
    arm_data = bpy.data.armatures.new(name)
    arm = link(bpy.data.objects.new(name, arm_data))
    arm_data.display_type = "STICK"
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    for spec in bones:
        bname, head, tail, parent = spec[:4]
        roll = spec[4] if len(spec) > 4 else 0.0
        deform = spec[5] if len(spec) > 5 else True
        connect = spec[6] if len(spec) > 6 else False
        b = eb.new(bname)
        b.head = Vector(head)
        if bname.startswith(AXLE_X_PREFIX):
            # Game-spun reel: `tail - head` is the AXLE. The bone itself is laid perpendicular to
            # it with its local X along the axle, because actors/enemy_view.gd multiplies its own
            # spin about local X onto "reel.L"/"reel.R" (see STYLE.md and common2.AXLE_X_PREFIX).
            axle = Vector(tail) - Vector(head)
            length = axle.length
            axle.normalize()
            ref = Vector((0, 0, 1)) if abs(axle.z) < 0.9 else Vector((0, -1, 0))
            y = (ref - axle * ref.dot(axle)).normalized()
            b.tail = Vector(head) + y * length
            b.align_roll(axle.cross(y))
        else:
            b.tail = Vector(tail)
            b.roll = math.radians(roll)
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


def _seg_dist(p: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    t = 0.0 if ab.length_squared < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def bind(rig: bpy.types.Object, parts: list[bpy.types.Object], name: str = "Body",
         auto: bool = True, smooth_angle: float = 40.0) -> bpy.types.Object:
    """Apply each part's modifiers, record its skinning intent, join, skin to `rig`.

    1. Automatic (bone heat) weights on the joined mesh.
    2. Corrective pass: rigid parts (obj["bone"]) get exactly weight 1.0 on their bone; soft parts
       (obj["soft"]) keep only the listed bones' weights (normalised, max 4); any soft vertex the
       heat solve missed falls back to inverse-distance weights over its two nearest listed bones.
    """
    tagged = []
    for o in parts:
        apply_modifiers(o)
        shade(o, smooth_angle)
        rigid = o.get("bone")
        soft = o.get("soft")
        if not rigid and not soft:
            raise ValueError(f"part {o.name} has no skinning tag")
        key = "__rigid__" + rigid if rigid else "__soft__" + soft
        vg = o.vertex_groups.new(name=key)
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        tagged.append(o)
    body = join(tagged, name)
    merge_materials(body)
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    deform_bones = [b.name for b in rig.data.bones if b.use_deform]
    marker_groups = [vg for vg in body.vertex_groups if vg.name.startswith("__")]
    if auto:
        activate(body)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        body.modifiers.remove(mod)
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
        mod = next(m for m in body.modifiers if m.type == "ARMATURE")
        mod.name = "Armature"
    for bname in deform_bones:
        if body.vertex_groups.get(bname) is None:
            body.vertex_groups.new(name=bname)
    _corrective_weights(rig, body, marker_groups, deform_bones)
    for vg in [vg for vg in body.vertex_groups if vg.name.startswith("__")]:
        body.vertex_groups.remove(vg)
    remove_cutters()
    return body


def _corrective_weights(rig, body, marker_groups, deform_bones) -> None:
    me = body.data
    gi = {vg.index: vg.name for vg in body.vertex_groups}
    bone_vg = {n: body.vertex_groups[n] for n in deform_bones}
    rest = {b.name: (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local) for b in rig.data.bones}
    for v in me.vertices:
        marker = None
        weights = {}
        for g in v.groups:
            n = gi[g.group]
            if n.startswith("__"):
                marker = n
            elif n in bone_vg and g.weight > 1e-4:
                weights[n] = g.weight
        if marker is None:
            continue
        if marker.startswith("__rigid__"):
            target = {marker[len("__rigid__"):]: 1.0}
        else:
            allowed = marker[len("__soft__"):].split(",")
            target = {k: w for k, w in weights.items() if k in allowed}
            if sum(target.values()) < 1e-3:
                p = body.matrix_world @ v.co
                ds = sorted((_seg_dist(p, *rest[b]), b) for b in allowed)[:2]
                if len(ds) == 1 or ds[0][0] < 1e-6:
                    target = {ds[0][1]: 1.0}
                else:
                    inv = [(1.0 / max(d, 1e-4)) ** 2 for d, _ in ds]
                    target = {ds[i][1]: inv[i] for i in range(len(ds))}
            top = sorted(target.items(), key=lambda kv: -kv[1])[:4]
            s = sum(w for _, w in top)
            target = {k: w / s for k, w in top}
        for n in list(weights):
            bone_vg[n].remove([v.index])
        for n, w in target.items():
            bone_vg[n].add([v.index], w, "REPLACE")


def attach_rigid(rig: bpy.types.Object, obj: bpy.types.Object, bone: str, name: str) -> bpy.types.Object:
    """A separate skinned object (e.g. the shielder's `Shield`) bound 100 % to one bone."""
    apply_modifiers(obj)
    shade(obj)
    merge_materials(obj)
    obj.name = name
    obj.data.name = name
    obj.parent = rig
    vg = obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return obj


def add_uvs(obj) -> None:
    """Smart-project UVs (the contract ships base colours only, but a UV set keeps the meshes ready
    for a grime/detail map without a re-export)."""
    activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")


# --------------------------------------------------------------------------------------------
# Animation
# --------------------------------------------------------------------------------------------

def K(rx=0.0, ry=0.0, rz=0.0, loc=(0.0, 0.0, 0.0), s=1.0, interp="BEZIER"):
    """A bone key: rotation in armature-axis degrees (XYZ), offset in armature axes, uniform or
    per-axis scale (bone axes), and the interpolation of the segment that follows."""
    return {"rot": (rx, ry, rz), "loc": tuple(loc), "s": s, "interp": interp}


class Anim:
    """One action. key(frame, {bone: K(...)}) sets poses; bones never keyed are held at rest
    for the whole range (except names in `skip`, which the game drives)."""

    def __init__(self, rig, name: str, seconds: float, loop: bool, skip=("aim",)):
        self.rig = rig
        self.name = name
        self.end = int(round(seconds * FPS))
        self.loop = loop
        self.skip = set(skip)
        self.keys: dict[str, dict[int, dict]] = {}

    def key(self, frame: int, poses: dict) -> "Anim":
        for b, k in poses.items():
            if b not in self.rig.pose.bones:
                raise KeyError(f"{self.name}: no bone {b}")
            if b in self.skip:
                raise ValueError(f"{self.name}: {b} is game-driven and must not be keyed")
            self.keys.setdefault(b, {})[int(frame)] = k
        return self

    def spin(self, bone: str, axis: str, turns: float, start: int = 0, end: int | None = None,
             step: int = 3, base: dict | None = None, phase_deg: float = 0.0) -> "Anim":
        """Continuous linear rotation about an armature axis (rotors, reels)."""
        end = self.end if end is None else end
        n = max(1, int(math.ceil((end - start) / step)))
        for i in range(n + 1):
            f = start + (end - start) * i / n
            a = phase_deg + 360.0 * turns * i / n
            r = [0.0, 0.0, 0.0]
            r["XYZ".index(axis)] = a
            k = K(*r, interp="LINEAR")
            if base:
                k["loc"] = base.get("loc", k["loc"])
            self.keys.setdefault(bone, {})[int(round(f))] = k
        return self

    def build(self) -> bpy.types.Action:
        rig = self.rig
        act = bpy.data.actions.new(self.name)
        act.use_fake_user = True
        rig.animation_data_create()
        rig.animation_data.action = act
        prefs = bpy.context.preferences.edit
        old_interp = prefs.keyframe_new_interpolation_type
        for pb in rig.pose.bones:
            if pb.name in self.skip:
                continue
            keys = dict(self.keys.get(pb.name, {}))
            if not keys:
                keys = {0: K(), self.end: K()}
            frames = sorted(keys)
            if 0 not in keys:
                # Loops wrap onto their first key; one-shots start from the rest pose, so a wind-up
                # scrubbed from 0 really begins at neutral and builds (a bone first keyed late
                # used to sit in that late pose from frame 0, which made telegraphs start half-posed).
                keys[0] = dict(keys[frames[0]]) if self.loop else K()
            if self.end not in keys:
                keys[self.end] = dict(keys[frames[-1]]) if not self.loop else dict(keys[0])
            if self.loop:
                k0 = dict(keys[0])
                k0["interp"] = keys[self.end].get("interp", "BEZIER")
                keys[self.end] = k0
            rest3 = pb.bone.matrix_local.to_3x3()
            inv = rest3.inverted()
            prev_q = None
            for f in sorted(keys):
                k = keys[f]
                if f < 0 or f > self.end:
                    continue
                rw = Euler([math.radians(a) for a in k["rot"]], "XYZ").to_matrix()
                q = (inv @ rw @ rest3).to_quaternion()
                if prev_q is not None and prev_q.dot(q) < 0:
                    q.negate()
                prev_q = q.copy()
                loc = inv @ Vector(k["loc"])
                s = k["s"]
                scl = Vector(s) if isinstance(s, (tuple, list)) else Vector((s, s, s))
                pb.rotation_quaternion = q
                pb.location = loc
                pb.scale = scl
                prefs.keyframe_new_interpolation_type = k.get("interp", "BEZIER")
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
                pb.keyframe_insert("location", frame=f, group=pb.name)
                pb.keyframe_insert("scale", frame=f, group=pb.name)
        prefs.keyframe_new_interpolation_type = old_interp
        act.use_frame_range = True
        act.frame_start = 0
        act.frame_end = self.end
        act.use_cyclic = self.loop
        for pb in rig.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
            pb.scale = Vector((1, 1, 1))
        return act


def clear_pose(rig) -> None:
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
        pb.scale = Vector((1, 1, 1))
    bpy.context.view_layer.update()


def set_action(rig, act, frame: float) -> None:
    rig.animation_data_create()
    rig.animation_data.action = act
    if hasattr(rig.animation_data, "action_slot") and act.slots:
        rig.animation_data.action_slot = act.slots[0]
    bpy.context.scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))


# --------------------------------------------------------------------------------------------
# Export
# --------------------------------------------------------------------------------------------

def export_glb(rig, meshes, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    clear_pose(rig)
    bpy.context.scene.frame_set(0)
    activate(rig)
    for m in meshes:
        m.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_skins=True,
        export_all_influences=False,
        export_def_bones=False,
        export_morph=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_step=1,
        export_anim_single_armature=True,
        export_reset_pose_bones=True,
        export_rest_position_armature=True,
        export_optimize_animation_size=False,
    )
    strip_animation_channels(path, set(GAME_DRIVEN_BONES))


# Bones the game rotates itself; their channels must not exist in any animation (the exporter's
# forced sampling bakes every bone, which would overwrite the game's rotation every frame).
GAME_DRIVEN_BONES = ("aim",)


def strip_animation_channels(path: str, node_names: set[str]) -> int:
    """Rewrite a .glb removing animation channels (and their samplers) that target `node_names`."""
    import json
    import struct
    with open(path, "rb") as f:
        data = f.read()
    _, version, _ = struct.unpack_from("<III", data, 0)
    off = 12
    chunks = []
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunks.append([ctype, data[off + 8: off + 8 + clen]])
        off += 8 + clen
    js = json.loads(chunks[0][1].decode("utf-8"))
    targets = {i for i, n in enumerate(js.get("nodes", [])) if n.get("name") in node_names}
    removed = 0
    for anim in js.get("animations", []):
        keep = [c for c in anim["channels"] if c["target"].get("node") not in targets]
        removed += len(anim["channels"]) - len(keep)
        used = sorted({c["sampler"] for c in keep})
        remap = {old: new for new, old in enumerate(used)}
        anim["samplers"] = [anim["samplers"][i] for i in used]
        for c in keep:
            c["sampler"] = remap[c["sampler"]]
        anim["channels"] = keep
    if removed == 0:
        return 0
    js_bytes = json.dumps(js, separators=(",", ":")).encode("utf-8")
    js_bytes += b" " * ((4 - len(js_bytes) % 4) % 4)
    chunks[0][1] = js_bytes
    body = b"".join(struct.pack("<II", len(c), t) + c for t, c in chunks)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, version, 12 + len(body)) + body)
    print(f"[export] stripped {removed} animation channels for game-driven bones {sorted(node_names)}")
    return removed


# --------------------------------------------------------------------------------------------
# Previews (Workbench, flat base colours + ink outline)
# --------------------------------------------------------------------------------------------

VIEWS = {
    # name: (yaw_deg, pitch_deg) of the camera around the model; yaw 0 = in front (at -Y),
    # positive yaw moves the camera toward the model's right (-X).
    "front": (0.0, 0.0),
    "side": (90.0, 0.0),
    "back": (180.0, 0.0),
    "threeq": (40.0, 12.0),
    "iso": (45.0, 35.0),
    "iso_back": (225.0, 35.0),
}


def setup_render(res_x: int, res_y: int, bg="#5d6670", transparent=False) -> None:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = res_x
    sc.render.resolution_y = res_y
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.display_settings.display_device = "sRGB"
    sc.view_settings.view_transform = "Standard"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.object_outline_color = (0.05, 0.04, 0.06)
    sh.show_cavity = True
    sh.cavity_type = "WORLD"
    sh.show_shadows = False
    sh.show_specular_highlight = False
    sc.display.render_aa = "8"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    c = hex_rgb(bg)
    sc.world.color = tuple(srgb_to_linear(x) for x in c)


def camera(name="PreviewCam") -> bpy.types.Object:
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = link(bpy.data.objects.new(name, bpy.data.cameras.new(name)))
    cam.data.type = "ORTHO"
    cam.data.clip_start = 0.01
    cam.data.clip_end = 100.0
    bpy.context.scene.camera = cam
    return cam


def view_dir(yaw: float, pitch: float) -> Vector:
    """Unit vector from the target toward the camera."""
    y, p = math.radians(yaw), math.radians(pitch)
    return Vector((-math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))


def world_points(objs) -> list[Vector]:
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        if o.type != "MESH" or o.hide_render:
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        co = np.zeros(len(me.vertices) * 3, dtype=np.float32)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        if len(co) > 4000:
            co = co[:: max(1, len(co) // 4000)]
        pts.extend(mw @ Vector(c) for c in co)
        ev.to_mesh_clear()
    return pts


def frame_camera(cam, objs, yaw, pitch, margin=1.12, fixed=None) -> tuple:
    """Aim an ortho camera along (yaw, pitch) and fit `objs` (or the `fixed` (center, scale))."""
    d = view_dir(yaw, pitch)
    rot = d.to_track_quat("Z", "Y")
    cam.rotation_euler = rot.to_euler()
    right = rot @ Vector((1, 0, 0))
    up = rot @ Vector((0, 1, 0))
    sc = bpy.context.scene
    aspect = sc.render.resolution_x / sc.render.resolution_y
    if fixed is None:
        pts = world_points(objs)
        xs = [p.dot(right) for p in pts]
        ys = [p.dot(up) for p in pts]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        scale = max(w, h * aspect) * margin
        center = right * cx + up * cy
        fixed = (center, scale)
    center, scale = fixed
    cam.data.ortho_scale = scale
    cam.location = center + d * 20.0
    return fixed


def render_to(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def load_png(path: str) -> np.ndarray:
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(h, w, 4)


def save_png(arr: np.ndarray, path: str) -> None:
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def grid(tiles: list[list[np.ndarray]], gap: int = 4, bg=(0.15, 0.15, 0.17, 1.0)) -> np.ndarray:
    """Compose rows of equally sized tiles (Blender images are bottom-up: row 0 drawn on top)."""
    th, tw = tiles[0][0].shape[:2]
    rows = len(tiles)
    cols = max(len(r) for r in tiles)
    H = rows * th + (rows + 1) * gap
    W = cols * tw + (cols + 1) * gap
    out = np.empty((H, W, 4), dtype=np.float32)
    out[:] = bg
    for r, row in enumerate(tiles):
        y0 = H - (r + 1) * (th + gap)
        for c, t in enumerate(row):
            x0 = gap + c * (tw + gap)
            out[y0:y0 + th, x0:x0 + tw] = t
    return out


def render_previews(name: str, rig, meshes, actions: dict, out_dir: str | None = None,
                    stills=True, sheets=True) -> list[str]:
    """Write the standard preview set for one enemy into art/previews/enemies/<name>/."""
    out_dir = out_dir or os.path.join(PREVIEW_DIR, name)
    os.makedirs(out_dir, exist_ok=True)
    tmp = os.path.join(out_dir, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    written = []
    cam = camera()
    clear_pose(rig)
    if stills:
        setup_render(640, 640)
        tiles = []
        for v in ("front", "side", "back", "threeq", "iso"):
            frame_camera(cam, meshes, *VIEWS[v])
            p = os.path.join(out_dir, f"{name}_{v}.png")
            render_to(p)
            written.append(p)
            tiles.append(load_png(p))
        tp = os.path.join(out_dir, f"{name}_turnaround.png")
        save_png(grid([tiles]), tp)
        written.append(tp)
        # Game-size reads: the model as tall as it is on screen (~100 px; and 160 px).
        for px in (100, 160):
            setup_render(px, px, bg="#3b3546")
            frame_camera(cam, meshes, *VIEWS["iso"], margin=1.04)
            p = os.path.join(out_dir, f"{name}_thumb{px}.png")
            render_to(p)
            written.append(p)
        setup_render(640, 640)
        frame_camera(cam, meshes, *VIEWS["iso_back"])
        p = os.path.join(out_dir, f"{name}_iso_back.png")
        render_to(p)
        written.append(p)
    if sheets and actions:
        for view in ("iso", "side"):
            setup_render(300, 300)
            # One framing for the whole sheet so motion reads against a fixed frame.
            fixed = None
            pts = []
            for act in actions.values():
                for f in (0, act.frame_range[1] * 0.5, act.frame_range[1]):
                    set_action(rig, act, f)
                    pts.extend(world_points(meshes))
            clear_pose(rig)
            d = view_dir(*VIEWS[view])
            rot = d.to_track_quat("Z", "Y")
            right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
            xs = [p.dot(right) for p in pts]
            ys = [p.dot(up) for p in pts]
            center = right * (min(xs) + max(xs)) / 2 + up * (min(ys) + max(ys)) / 2
            fixed = (center, max(max(xs) - min(xs), max(ys) - min(ys)) * 1.08)
            rows = []
            for aname, act in actions.items():
                end = act.frame_range[1]
                n = 8
                row = []
                for i in range(n):
                    f = end * i / (n - 1) if not act.use_cyclic else end * i / n
                    set_action(rig, act, f)
                    frame_camera(cam, meshes, *VIEWS[view], fixed=fixed)
                    p = os.path.join(tmp, f"{aname}_{i}.png")
                    render_to(p)
                    row.append(load_png(p))
                rows.append(row)
            sp = os.path.join(out_dir, f"{name}_sheet_{view}.png")
            save_png(grid(rows), sp)
            written.append(sp)
        # Telegraph read: the wind-up at the scrub positions the game shows (0..1), then the
        # first frames of the attack, large enough to judge the pose and the hit frame.
        if "telegraph" in actions and "attack" in actions:
            setup_render(400, 400)
            strips = [(actions["telegraph"], [0, 6, 12, 18, 24, 30]), (actions["attack"], [0, 2, 4, 6, 12, 22])]
            pts = []
            for act, frames in strips:
                for f in frames:
                    set_action(rig, act, f)
                    pts.extend(world_points(meshes))
            d = view_dir(*VIEWS["iso"])
            rot = d.to_track_quat("Z", "Y")
            right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
            xs = [p.dot(right) for p in pts]
            ys = [p.dot(up) for p in pts]
            center = right * (min(xs) + max(xs)) / 2 + up * (min(ys) + max(ys)) / 2
            fixed = (center, max(max(xs) - min(xs), max(ys) - min(ys)) * 1.06)
            rows = []
            for act, frames in strips:
                row = []
                for i, f in enumerate(frames):
                    set_action(rig, act, f)
                    frame_camera(cam, meshes, *VIEWS["iso"], fixed=fixed)
                    p = os.path.join(tmp, f"tg_{act.name}_{i}.png")
                    render_to(p)
                    row.append(load_png(p))
                rows.append(row)
            sp = os.path.join(out_dir, f"{name}_telegraph.png")
            save_png(grid(rows), sp)
            written.append(sp)
        clear_pose(rig)
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)
    return written


def run(name: str, build_fn) -> None:
    """Standard entry point for a type script.
    Args after `--`: [--no-export] [--no-stills] [--no-sheets] [--out <glb path>]."""
    args = script_args()
    reset_scene()
    rig, meshes, actions = build_fn()
    for m in meshes:
        add_uvs(m)
    if "--no-export" not in args:
        out = os.path.join(MODEL_DIR, f"{name}.glb")
        if "--out" in args:
            out = os.path.abspath(args[args.index("--out") + 1])
        export_glb(rig, meshes, out)
        print(f"[{name}] exported {out}")
    if "--no-stills" not in args or "--no-sheets" not in args:
        files = render_previews(name, rig, meshes, actions,
                                stills="--no-stills" not in args, sheets="--no-sheets" not in args)
        print(f"[{name}] previews: {len(files)} files in {os.path.join(PREVIEW_DIR, name)}")
    tris = sum(sum(len(p.vertices) - 2 for p in m.data.polygons) for m in meshes)
    print(f"[{name}] triangles: {tris}")
