"""Shared Blender helpers for the turret, brute and boss enemy builds (art/enemies/{turret,brute,boss}.py).

Run inside Blender 4.5 (bpy). Everything here builds real meshes through bmesh / modifiers / curves,
rigs them with an armature "Rig", skins them (rigid weights for mechanical parts, automatic or
blended weights for soft parts), keys named actions and exports a glb per docs/GODOT-PORT.md.
It also renders Workbench preview stills for review (art/previews/enemies/<type>/).

Conventions (see art/enemies/STYLE.md):
  * 1 Blender metre = 1 tile. Origin on the floor at the footprint centre.
  * Models face -Y in Blender, which the glTF exporter turns into +Z in Godot.
  * Materials are named by role; emissive ones end in "_glow".
"""
from __future__ import annotations

import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

FPS = 30
REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ISO_YAW = 45.0
ISO_PITCH = math.degrees(math.atan(1 / math.sqrt(2)))  # 35.26 deg, the game's camera pitch
# Tape-reel bones ("reel.L"/"reel.R") have their axle along the bone's LOCAL X: the game
# (actors/enemy_view.gd) adds its own spin to these bones as a rotation about local X
# (Vector3.RIGHT), matching the stand-in rigs. Animator.spin() spins them about X too.
AXLE_X_PREFIX = "reel."

# ───────────────────────────── palette (STYLE.md) ─────────────────────────────

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
    "eye_glow": "#ff6a1a",
    "rune_glow": "#58f0dc",
    "meter_glow": "#ffd04a",
    "charge_glow": "#ff8a3a",
    "core_glow": "#ff5a2a",
    "screen_glow": "#8ff6ff",
}


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))  # type: ignore


def material(name: str) -> bpy.types.Material:
    """Get or create the named material with its flat base colour (and emission for *_glow)."""
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    rgb = hex_rgb(PALETTE[name])
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.75
    bsdf.inputs["Metallic"].default_value = 0.0
    if name.endswith("_glow"):
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    m.diffuse_color = (*rgb, 1.0)
    m.roughness = 0.75
    return m


# ───────────────────────────── scene / args ─────────────────────────────


def script_args() -> dict:
    """Parse `-- --out x.glb --previews dir --no-anim-previews` style arguments."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out: dict = {"out": None, "previews": None, "anim": True, "quick": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--out":
            out["out"] = argv[i + 1]
            i += 1
        elif a == "--previews":
            out["previews"] = argv[i + 1]
            i += 1
        elif a == "--no-anim-previews":
            out["anim"] = False
        elif a == "--quick":
            out["quick"] = True
        i += 1
    return out


def reset_scene() -> bpy.types.Scene:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    sc.frame_start = 0
    sc.frame_end = 60
    return sc


def link(ob: bpy.types.Object) -> bpy.types.Object:
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ───────────────────────────── mesh primitives ─────────────────────────────


def _slot(me: bpy.types.Mesh, name: str) -> int:
    for i, m in enumerate(me.materials):
        if m is not None and m.name == name:
            return i
    me.materials.append(material(name))
    return len(me.materials) - 1


def mat_index(ob: bpy.types.Object, name: str) -> int:
    return _slot(ob.data, name)


def smooth_by_angle(bm: bmesh.types.BMesh, angle_deg: float = 40.0) -> None:
    """Smooth shading with sharp edges above `angle_deg` (exported as split normals)."""
    lim = math.radians(angle_deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if not e.is_manifold:
            e.smooth = False
            continue
        try:
            e.smooth = e.calc_face_angle() <= lim
        except ValueError:
            e.smooth = False


def bm_to_object(name: str, bm: bmesh.types.BMesh, mats: list[str], smooth: float | None = 40.0) -> bpy.types.Object:
    """Finish a bmesh into a linked object. Face material_index values index into `mats`."""
    if smooth is not None:
        smooth_by_angle(bm, smooth)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(material(m))
    ob = bpy.data.objects.new(name, me)
    return link(ob)


def box(name: str, size, mat: str, loc=(0, 0, 0), rot=(0, 0, 0), bevel: float = 0.0, seg: int = 1,
        taper=(1.0, 1.0), smooth: float = 40.0) -> bpy.types.Object:
    """Chamfered box; `taper` scales the top face in X/Y (plinths, wedges)."""
    sx, sy, sz = size
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
        if v.co.z > 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, offset_type="OFFSET", segments=seg,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    ob = bm_to_object(name, bm, [mat], smooth)
    return xf(ob, loc, rot)


def lathe(name: str, prof, mat: str | list[str], segs: int = 24, loc=(0, 0, 0), rot=(0, 0, 0),
          angle0: float = 0.0, cap: bool = True, smooth: float = 40.0, band_mats: list[int] | None = None,
          twist: float = 0.0) -> bpy.types.Object:
    """Surface of revolution about local Z. `prof` is [(r, z), ...] traced counter-clockwise in the
    (r, z) half-plane so normals face out. Points with r == 0 become poles. `band_mats[i]` picks the
    material (index into the `mat` list) of the band between profile points i and i+1. `twist`
    rotates each successive ring by that many degrees (diagonal quads, used for hazard bands)."""
    mats = [mat] if isinstance(mat, str) else list(mat)
    bm = bmesh.new()
    rings = []
    for i, (r, z) in enumerate(prof):
        if r < 1e-7:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            a0 = math.radians(angle0 + twist * i)
            rings.append([bm.verts.new((r * math.cos(a0 + 2 * math.pi * j / segs),
                                        r * math.sin(a0 + 2 * math.pi * j / segs), z)) for j in range(segs)])
    for i in range(len(rings) - 1):
        A, B = rings[i], rings[i + 1]
        mi = band_mats[i] if band_mats else 0
        for j in range(segs):
            q = [A[j % len(A)], A[(j + 1) % len(A)], B[(j + 1) % len(B)], B[j % len(B)]]
            vs = []
            for v in q:
                if v not in vs:
                    vs.append(v)
            if len(vs) >= 3:
                f = bm.faces.new(vs)
                f.material_index = mi
    if cap:
        if len(rings[0]) > 1:
            f = bm.faces.new(list(reversed(rings[0])))
            f.material_index = band_mats[0] if band_mats else 0
        if len(rings[-1]) > 1:
            f = bm.faces.new(rings[-1])
            f.material_index = band_mats[-1] if band_mats else 0
    ob = bm_to_object(name, bm, mats, smooth)
    return xf(ob, loc, rot)


def cyl(name: str, r: float, h: float, mat: str, segs: int = 16, loc=(0, 0, 0), rot=(0, 0, 0),
        bevel: float = 0.0, r_top: float | None = None, angle0: float = 0.0, z0: float | None = None) -> bpy.types.Object:
    """Cylinder along local Z from z0 (default -h/2) to z0+h, optionally tapered and chamfered."""
    rt = r if r_top is None else r_top
    a = -h / 2 if z0 is None else z0
    b = a + h
    if bevel > 0:
        prof = [(0, a), (r - bevel, a), (r, a + bevel), (rt, b - bevel), (rt - bevel, b), (0, b)]
    else:
        prof = [(0, a), (r, a), (rt, b), (0, b)]
    return lathe(name, prof, mat, segs, loc, rot, angle0=angle0, cap=False)


def torus(name: str, R: float, r: float, mat: str, segs: int = 32, rsegs: int = 8, loc=(0, 0, 0), rot=(0, 0, 0)) -> bpy.types.Object:
    prof = [(R + r * math.cos(2 * math.pi * k / rsegs - math.pi / 2), r * math.sin(2 * math.pi * k / rsegs - math.pi / 2))
            for k in range(rsegs + 1)]
    ob = lathe(name, prof, mat, segs, loc, rot, cap=False)
    _weld(ob)
    return ob


def ring(name: str, r_out: float, r_in: float, h: float, mat: str, segs: int = 32, loc=(0, 0, 0), rot=(0, 0, 0),
         bevel: float = 0.0) -> bpy.types.Object:
    """Flat washer / flange: closed annulus of height h centred on z = 0."""
    b = min(bevel, h / 3, (r_out - r_in) / 3)
    a, t = -h / 2, h / 2
    prof = [(r_in, a), (r_out - b, a), (r_out, a + b), (r_out, t - b), (r_out - b, t), (r_in, t), (r_in, a)]
    ob = lathe(name, prof, mat, segs, loc, rot, cap=False)
    _weld(ob)
    return ob


def prism(name: str, poly, depth: float, mat: str, loc=(0, 0, 0), rot=(0, 0, 0), bevel: float = 0.0,
          smooth: float = 40.0) -> bpy.types.Object:
    """Polygon [(x, z), ...] (counter-clockwise seen from -Y, i.e. from the front) extruded along +Y
    by `depth`, centred on y = 0. Good for plates, blades and brackets."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in poly]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in poly]
    n = len(poly)
    bm.faces.new(front)  # CCW seen from -Y => normal -Y
    bm.faces.new(list(reversed(back)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([front[j], front[i], back[i], back[j]])
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, offset_type="OFFSET", segments=1,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    ob = bm_to_object(name, bm, [mat], smooth)
    return xf(ob, loc, rot)


def tube(name: str, pts, r: float, mat: str, sides: int = 8, res: int = 6, loc=(0, 0, 0), rot=(0, 0, 0),
         taper: float | None = None) -> bpy.types.Object:
    """Cable / hose / pipe: a Bezier curve through `pts` with a round bevel, converted to a mesh."""
    cu = bpy.data.curves.new(name + "_curve", "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = res
    cu.bevel_mode = "ROUND"
    cu.bevel_depth = r
    cu.bevel_resolution = max(0, (sides - 4) // 2)
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for bp, p in zip(sp.bezier_points, pts):
        bp.co = Vector(p)
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    if taper is not None:
        sp.bezier_points[-1].radius = taper
    cob = link(bpy.data.objects.new(name + "_c", cu))
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(cob.evaluated_get(dg))
    bpy.data.objects.remove(cob)
    bpy.data.curves.remove(cu)
    me.name = name
    me.materials.clear()
    me.materials.append(material(mat))
    for p in me.polygons:
        p.material_index = 0
    ob = link(bpy.data.objects.new(name, me))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    smooth_by_angle(bm, 50)
    bm.to_mesh(me)
    bm.free()
    return xf(ob, loc, rot)


def hazard_band(name: str, r: float, z0: float, z1: float, stripes: int = 8, loc=(0, 0, 0), rot=(0, 0, 0),
                r_top: float | None = None, slant: float = 1, angle0: float = 0.0, rows: int = 4, sub: int = 2,
                polygon: int = 0) -> bpy.types.Object:
    """Cylindrical band of diagonal yellow/black hazard stripes as real geometry. The band is a
    stack of `rows` rings, each turned a little further, with `sub` quad columns per stripe, so the
    stripes are clean helices on a round band (no long twisted quads that triangulate into shards).
    `slant` = stripe widths the pattern advances from bottom to top. `polygon` = n makes the band
    hug an n-sided faceted body (corners at angle0 + k*360/n, radius r at the corners)."""
    segs = stripes * 2 * sub
    rt = r if r_top is None else r_top
    step = 360.0 / segs

    def rad(base: float, ang_deg: float) -> float:
        if not polygon:
            return base
        sector = 360.0 / polygon
        d = ((ang_deg - angle0) % sector) - sector / 2
        return base * math.cos(math.radians(sector / 2)) / math.cos(math.radians(d))

    bm = bmesh.new()
    rings = []
    for k in range(rows + 1):
        t = k / rows
        z = z0 + (z1 - z0) * t
        rr = r + (rt - r) * t
        ring_v = []
        for j in range(segs):
            ang = angle0 + step * (j + slant * sub * t)
            q = rad(rr, ang)
            ring_v.append(bm.verts.new((q * math.cos(math.radians(ang)), q * math.sin(math.radians(ang)), z)))
        rings.append(ring_v)
    for k in range(rows):
        lo, hi = rings[k], rings[k + 1]
        for j in range(segs):
            f = bm.faces.new([lo[j], lo[(j + 1) % segs], hi[(j + 1) % segs], hi[j]])
            f.material_index = (j // sub) % 2
    ob = bm_to_object(name, bm, ["hazard", "hazard_dark"], 60)
    return xf(ob, loc, rot)


def ray_hit(target: bpy.types.Object, origin, direction, reach: float = 10.0) -> Vector:
    """First point where the ray from `origin` along `direction` meets `target` (baked first).
    Used to seat parts on subdivided shells whose surface is not where the control cage was."""
    from mathutils.bvhtree import BVHTree
    bake(target)
    bm = bmesh.new()
    bm.from_mesh(target.data)
    hit = BVHTree.FromBMesh(bm).ray_cast(Vector(origin), Vector(direction).normalized(), reach)
    bm.free()
    if hit[0] is None:
        raise RuntimeError(f"ray_hit: ray misses {target.name}")
    return hit[0]


def project_onto(ob: bpy.types.Object, target: bpy.types.Object, origin, normal, reach: float = 1.0,
                 lift: float = 0.0) -> bpy.types.Object:
    """Drape a flat decal part (rune glyphs, plates built on the plane through `origin` with
    `normal`) onto the curved surface of `target`: every vertex keeps its height above the plane
    but the plane point under it is moved to where a ray along -normal hits the target. Both
    objects are baked first. Vertices whose ray misses stay where they are. `lift` raises the
    part off the surface (a strip spanning a convex curve would otherwise dip under it)."""
    from mathutils.bvhtree import BVHTree
    bake(ob)
    bake(target)
    o, n = Vector(origin), Vector(normal).normalized()
    bm = bmesh.new()
    bm.from_mesh(target.data)
    tree = BVHTree.FromBMesh(bm)
    for v in ob.data.vertices:
        h = (v.co - o).dot(n)
        base = v.co - n * h
        hit = tree.ray_cast(base + n * reach, -n, reach * 2)
        if hit[0] is not None:
            v.co = hit[0] + n * (h + lift)
    bm.free()
    return ob


def hazard_panel(name: str, size, period: float, loc=(0, 0, 0), rot=(0, 0, 0), bevel: float = 0.0,
                 angle: float = 45.0, frame: float = 0.0) -> bpy.types.Object:
    """Flat plate (x wide, y thick, z tall) whose faces are cut by parallel diagonal planes into
    alternating hazard / hazard_dark stripes. `frame` > 0 leaves a dark border of that width."""
    sx, sy, sz = size
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, offset_type="OFFSET", segments=1,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    n = Vector((math.cos(math.radians(angle)), 0, math.sin(math.radians(angle))))
    ext = (abs(n.x) * sx + abs(n.z) * sz) / 2 + period
    k = -int(ext / period) - 1
    while k * period <= ext:
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=n * (k * period), plane_no=n)
        k += 1
    for f in bm.faces:
        c = f.calc_center_median()
        band = math.floor(c.dot(n) / period + 1e-4)
        inside = frame <= 0 or (abs(c.x) < sx / 2 - frame and abs(c.z) < sz / 2 - frame)
        f.material_index = 0 if (band % 2 == 0 and inside) else 1
    ob = bm_to_object(name, bm, ["hazard", "hazard_dark"], 30)
    return xf(ob, loc, rot)


def glyphs(name: str, strokes, origin, u_axis, v_axis, width: float = 0.012, depth: float = 0.008,
           mat: str = "rune_glow") -> bpy.types.Object:
    """Rune inlay: thin raised strips along 2D polylines laid on a plane (origin, u, v). The strip
    sits half sunk in the surface so it reads as an inlaid glowing groove."""
    o, u, v = Vector(origin), Vector(u_axis).normalized(), Vector(v_axis).normalized()
    nrm = u.cross(v).normalized()
    bm = bmesh.new()
    for line in strokes:
        for a, b in zip(line[:-1], line[1:]):
            pa = o + u * a[0] + v * a[1]
            pb = o + u * b[0] + v * b[1]
            d = (pb - pa)
            ln = d.length
            if ln < 1e-6:
                continue
            d.normalize()
            side = d.cross(nrm).normalized() * (width / 2)
            ext = d * (width / 2)
            corners = []
            for s, e in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                base = (pa - ext) if e < 0 else (pb + ext)
                corners.append(base + side * s)
            lo = [bm.verts.new(c - nrm * (depth / 2)) for c in corners]
            hi = [bm.verts.new(c + nrm * (depth / 2)) for c in corners]
            bm.faces.new(lo[::-1])
            bm.faces.new(hi)
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new([lo[i], lo[j], hi[j], hi[i]])
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm_to_object(name, bm, [mat], 30)


def _weld(ob: bpy.types.Object, dist: float = 1e-5) -> None:
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=dist)
    bm.to_mesh(ob.data)
    bm.free()


def xf(ob: bpy.types.Object, loc=(0, 0, 0), rot=(0, 0, 0), scale=None) -> bpy.types.Object:
    """Set the object transform (rotation in degrees, XYZ Euler). Baked into the mesh at finalize."""
    ob.location = Vector(loc)
    ob.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    if scale is not None:
        ob.scale = Vector(scale)
    return ob


def bake(ob: bpy.types.Object) -> bpy.types.Object:
    """Bake the object transform into its mesh."""
    bpy.context.view_layer.update()
    mw = ob.matrix_world.copy()
    ob.parent = None
    ob.data.transform(mw)
    if mw.determinant() < 0:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.to_mesh(ob.data)
        bm.free()
    ob.matrix_world = Matrix.Identity(4)
    return ob


def place(ob: bpy.types.Object, loc=(0, 0, 0), rot=(0, 0, 0)) -> bpy.types.Object:
    """Bake the current transform, then apply another (rotation degrees XYZ, then translation)."""
    bake(ob)
    m = Matrix.Translation(Vector(loc)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    ob.data.transform(m)
    return ob


def apply_modifiers(ob: bpy.types.Object) -> bpy.types.Object:
    """Apply the modifier stack (mirror / subsurf / solidify / bevel) into the mesh."""
    if not ob.modifiers:
        return ob
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    me.name = old.name
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def mod_mirror(ob, axis_x=True, merge=0.001, bisect=True):
    m = ob.modifiers.new("Mirror", "MIRROR")
    m.use_axis = (axis_x, False, False)
    m.use_clip = True
    m.use_mirror_merge = True
    m.merge_threshold = merge
    m.use_bisect_axis = (bisect, False, False)
    return ob


def mod_subsurf(ob, levels=2):
    m = ob.modifiers.new("Subsurf", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    return ob


def mod_solidify(ob, thickness=0.04, offset=-1.0):
    m = ob.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = thickness
    m.offset = offset
    m.use_even_offset = True
    return ob


def mod_bevel(ob, width=0.01, segments=1, angle=40):
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    return ob


def crease_edges(ob: bpy.types.Object, pred, value: float = 1.0) -> None:
    """Set subdivision crease on edges whose two endpoint coordinates satisfy pred(a, b)."""
    me = ob.data
    attr = me.attributes.get("crease_edge") or me.attributes.new("crease_edge", "FLOAT", "EDGE")
    for e in me.edges:
        a = me.vertices[e.vertices[0]].co
        b = me.vertices[e.vertices[1]].co
        if pred(a, b):
            attr.data[e.index].value = value


def resmooth(ob: bpy.types.Object, angle: float = 40.0) -> bpy.types.Object:
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    smooth_by_angle(bm, angle)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def mirrored(ob: bpy.types.Object, name: str) -> bpy.types.Object:
    """A copy mirrored across X = 0 (transform baked, normals kept outward)."""
    bake(ob)
    me = ob.data.copy()
    me.name = name
    me.transform(Matrix.Scale(-1, 4, Vector((1, 0, 0))))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    cp = link(bpy.data.objects.new(name, me))
    return cp


def recolor(ob: bpy.types.Object, mat: str, pred) -> int:
    """Assign `mat` to faces whose (centre, normal) satisfy pred. Works in the object's mesh space
    after `bake`. Returns the number of faces changed."""
    bake(ob)
    idx = mat_index(ob, mat)
    n = 0
    for p in ob.data.polygons:
        if pred(Vector(p.center), Vector(p.normal)):
            p.material_index = idx
            n += 1
    return n


def inset_faces(ob: bpy.types.Object, pred, thickness: float, depth: float, mat: str | None = None,
                individual: bool = True) -> int:
    """Inset the faces selected by pred(centre, normal) and push the inner faces by `depth` along
    the normal (negative = carve in). The inner faces optionally get `mat` (glow inlays, sockets)."""
    bake(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    faces = [f for f in bm.faces if pred(f.calc_center_median(), f.normal)]
    if not faces:
        bm.free()
        return 0
    if individual:
        bmesh.ops.inset_individual(bm, faces=faces, thickness=thickness, depth=depth, use_even_offset=True)
    else:
        bmesh.ops.inset_region(bm, faces=faces, thickness=thickness, depth=depth, use_even_offset=True)
    idx = mat_index(ob, mat) if mat else None
    if idx is not None:
        for f in faces:
            f.material_index = idx
    smooth_by_angle(bm, 40)
    bm.to_mesh(ob.data)
    bm.free()
    return len(faces)


def bolts(name: str, points, normal, r: float = 0.018, h: float = 0.016, mat: str = "brass") -> bpy.types.Object:
    """Hex bolt heads at points, axis along `normal` (one vector for all, or one per point)."""
    parts = []
    for i, p in enumerate(points):
        n = Vector(normal[i] if isinstance(normal[0], (tuple, list, Vector)) else normal).normalized()
        b = cyl(f"{name}_{i}", r, h, mat, segs=6, z0=0.0, bevel=h * 0.3)
        q = Vector((0, 0, 1)).rotation_difference(n)
        b.rotation_mode = "QUATERNION"
        b.rotation_quaternion = q
        b.location = Vector(p)
        bake(b)
        parts.append(b)
    return join_raw(name, parts)


def join_raw(name: str, parts) -> bpy.types.Object:
    """Join objects into one (transforms baked; materials and vertex groups merged by name)."""
    parts = [p for p in parts if p is not None]
    for p in parts:
        bake(p)
    if len(parts) == 1:
        parts[0].name = name
        return parts[0]
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


# ───────────────────────────── armature ─────────────────────────────


class RigBuilder:
    """Creates the armature object "Rig" (data "Rig") at the origin."""

    def __init__(self) -> None:
        arm = bpy.data.armatures.new("Rig")
        arm.display_type = "OCTAHEDRAL"
        self.ob = link(bpy.data.objects.new("Rig", arm))
        self.ob.show_in_front = True
        bpy.context.view_layer.objects.active = self.ob
        bpy.ops.object.mode_set(mode="EDIT")
        self.arm = arm
        self.spin_bones: set[str] = set()

    def bone(self, name: str, head, tail, parent: str | None = None, roll: float = 0.0, deform: bool = True,
             connect: bool = False, spin: bool = False) -> None:
        """For an axle bone (name starting with AXLE_X_PREFIX) `tail - head` gives the axle; the bone
        is then built so its LOCAL X is that axle (see AXLE_X_PREFIX) and its Y points 'up-ish'."""
        eb = self.arm.edit_bones.new(name)
        eb.head = Vector(head)
        if name.startswith(AXLE_X_PREFIX):
            axle = (Vector(tail) - Vector(head))
            length = axle.length
            axle.normalize()
            ref = Vector((0, 0, 1)) if abs(axle.z) < 0.9 else Vector((0, -1, 0))
            y = (ref - axle * ref.dot(axle)).normalized()
            eb.tail = Vector(head) + y * length
            eb.align_roll(axle.cross(y))  # local Z = X x Y with X = axle  =>  Y x Z = axle
        else:
            eb.tail = Vector(tail)
            eb.roll = math.radians(roll)
        eb.use_deform = deform
        if parent:
            eb.parent = self.arm.edit_bones[parent]
            eb.use_connect = connect
        if spin:
            self.spin_bones.add(name)

    def finish(self) -> bpy.types.Object:
        bpy.ops.object.mode_set(mode="OBJECT")
        for pb in self.ob.pose.bones:
            pb.rotation_mode = "XYZ" if pb.name in self.spin_bones else "QUATERNION"
        return self.ob


def scale_model(rig: bpy.types.Object, objs, k: float) -> None:
    """Uniformly scale the finished rig and its skinned meshes about the origin, applying the
    scale into bone rest positions and vertex data (no object scale left for the exporter)."""
    bpy.ops.object.select_all(action="DESELECT")
    rig.scale = (k, k, k)
    bpy.context.view_layer.update()
    for ob in [rig, *objs]:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.context.view_layer.update()


def bone_segment(rig: bpy.types.Object, name: str) -> tuple[Vector, Vector]:
    b = rig.data.bones[name]
    return rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local


def _seg_dist(p: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    t = 0.0 if ab.length_squared < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


class Skin:
    """Collects parts per skinning rule, then joins them into one skinned mesh object."""

    def __init__(self, rig: bpy.types.Object) -> None:
        self.rig = rig
        self.parts: list[tuple[bpy.types.Object, str, object]] = []

    def rigid(self, ob: bpy.types.Object, bone: str) -> bpy.types.Object:
        self.parts.append((ob, "rigid", bone))
        return ob

    def blend(self, ob: bpy.types.Object, bones: list[str], falloff: float = 4.0) -> bpy.types.Object:
        """Smooth weights from distance to each listed bone segment (soft parts: bellows, tape)."""
        self.parts.append((ob, "blend", (bones, falloff)))
        return ob

    def auto(self, ob: bpy.types.Object, bones: list[str]) -> bpy.types.Object:
        """Blender's automatic (bone heat) weights, then corrected to the listed bones only."""
        self.parts.append((ob, "auto", bones))
        return ob

    def build(self, name: str) -> bpy.types.Object:
        objs = []
        for ob, kind, arg in self.parts:
            apply_modifiers(ob)
            bake(ob)
            for vg in list(ob.vertex_groups):
                ob.vertex_groups.remove(vg)
            if kind == "rigid":
                vg = ob.vertex_groups.new(name=arg)
                vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
            elif kind == "blend":
                bones, falloff = arg
                self._distance_weights(ob, bones, falloff)
            else:
                self._auto_weights(ob, arg)
            objs.append(ob)
        ob = join_raw(name, objs)
        ob.parent = self.rig
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = self.rig
        return ob

    def _distance_weights(self, ob, bones, falloff, only_missing=False) -> None:
        segs = [(b, *bone_segment(self.rig, b)) for b in bones]
        groups = {b: (ob.vertex_groups.get(b) or ob.vertex_groups.new(name=b)) for b in bones}
        for v in ob.data.vertices:
            if only_missing and any(g.weight > 1e-4 for g in v.groups):
                continue
            ws = []
            for b, a, t in segs:
                d = max(_seg_dist(v.co, a, t), 1e-3)
                ws.append((b, 1.0 / d ** falloff))
            tot = sum(w for _, w in ws)
            for b, w in ws:
                w /= tot
                if w > 0.005:
                    groups[b].add([v.index], w, "REPLACE")

    def _auto_weights(self, ob, bones) -> None:
        rig = self.rig
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        try:
            bpy.ops.object.parent_set(type="ARMATURE_AUTO")
        except RuntimeError as e:  # bone heat can fail on odd geometry; distance weights cover it
            print("auto weights failed:", e)
        # Unparent but keep the weights; drop the modifier the operator added.
        ob.parent = None
        for m in list(ob.modifiers):
            ob.modifiers.remove(m)
        ob.matrix_world = Matrix.Identity(4)
        # Corrective pass: keep only the allowed bones, renormalise, fill any vertex heat missed.
        allowed = set(bones)
        for vg in list(ob.vertex_groups):
            if vg.name not in allowed:
                ob.vertex_groups.remove(vg)
        for b in bones:
            if ob.vertex_groups.get(b) is None:
                ob.vertex_groups.new(name=b)
        idx = {vg.index: vg for vg in ob.vertex_groups}
        for v in ob.data.vertices:
            tot = sum(g.weight for g in v.groups)
            if tot > 1e-4:
                for g in v.groups:
                    idx[g.group].add([v.index], g.weight / tot, "REPLACE")
        self._distance_weights(ob, bones, 4.0, only_missing=True)


# ───────────────────────────── animation ─────────────────────────────


class Animator:
    """Pose-based keying. Rotations are given in degrees about ARMATURE axes (X right, Y back,
    Z up; models face -Y) around the bone head; locations in armature axes; scale uniform or xyz.
    Every key writes the full pose of every bone not excluded, so each action fully owns its
    bones (no channel leaks between Godot animations)."""

    def __init__(self, rig: bpy.types.Object, never_key: tuple[str, ...] = ()) -> None:
        self.rig = rig
        self.never = set(never_key)
        self.rest = {b.name: b.matrix_local.to_3x3() for b in rig.data.bones}
        self.actions: list[bpy.types.Action] = []
        self.act = None
        self.spinning: set[str] = set()
        self.last_q: dict[str, Quaternion] = {}
        if rig.animation_data is None:
            rig.animation_data_create()

    def begin(self, name: str, length_s: float, loop: bool = False) -> None:
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        self.rig.animation_data.action = act
        if hasattr(self.rig.animation_data, "action_slot") and act.slots:
            self.rig.animation_data.action_slot = act.slots[0]
        self.act = act
        self.frames = int(round(length_s * FPS))
        self.loop = loop
        self.spinning = set()
        self.last_q = {}
        self.overlay = None
        for pb in self.rig.pose.bones:
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.rotation_euler = (0, 0, 0)

    def _q(self, bone: str, rot) -> Quaternion:
        R = self.rest[bone]
        qw = Euler([math.radians(a) for a in rot], "XYZ").to_quaternion()
        ql = (R.inverted() @ qw.to_matrix() @ R).to_quaternion()
        prev = self.last_q.get(bone)
        if prev is not None and prev.dot(ql) < 0:
            ql.negate()
        self.last_q[bone] = ql
        return ql

    def pose(self, frame: float, pose: dict, interp: str = "BEZIER", easing: str = "AUTO") -> None:
        """Key every bone at `frame`. pose = {bone: dict(r=(x,y,z) deg, l=(x,y,z), s=k or (x,y,z))}.
        If `self.overlay` is set (per action), overlay(frame) is merged on top (e.g. the eye bone)."""
        if self.overlay is not None:
            pose = {**pose, **self.overlay(frame)}
        for pb in self.rig.pose.bones:
            n = pb.name
            if n in self.never or n in self.spinning:
                continue
            p = pose.get(n, {})
            R = self.rest[n]
            pb.location = R.inverted() @ Vector(p.get("l", (0, 0, 0)))
            s = p.get("s", 1.0)
            pb.scale = (s, s, s) if isinstance(s, (int, float)) else s
            if pb.rotation_mode == "QUATERNION":
                pb.rotation_quaternion = self._q(n, p.get("r", (0, 0, 0)))
                pb.keyframe_insert("rotation_quaternion", frame=frame, group=n)
            else:
                pb.rotation_euler = Euler([math.radians(a) for a in p.get("e", (0, 0, 0))], "XYZ")
                pb.keyframe_insert("rotation_euler", frame=frame, group=n)
            pb.keyframe_insert("location", frame=frame, group=n)
            pb.keyframe_insert("scale", frame=frame, group=n)
        self._set_interp(frame, interp, easing, skip=self.spinning)

    def spin(self, bone: str, turns_deg: float, start: float = 0, end: float | None = None, axis: int | None = None,
             curve=None) -> None:
        """Rotate a spin bone about its own axis linearly, or by curve(t)->deg. The default axis is
        local Y, or local X for axle bones (AXLE_X_PREFIX)."""
        if axis is None:
            axis = 0 if bone.startswith(AXLE_X_PREFIX) else 1
        pb = self.rig.pose.bones[bone]
        assert pb.rotation_mode == "XYZ", bone
        self.spinning.add(bone)
        end = self.frames if end is None else end
        steps = max(2, int(end - start))
        for i in range(steps + 1):
            t = i / steps
            f = start + (end - start) * t
            ang = curve(t) if curve else turns_deg * t
            e = [0.0, 0.0, 0.0]
            e[axis] = math.radians(ang)
            pb.rotation_euler = e
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)
            pb.keyframe_insert("rotation_euler", frame=f, group=bone)
            pb.keyframe_insert("location", frame=f, group=bone)
            pb.keyframe_insert("scale", frame=f, group=bone)
        for fc in self._fcurves():
            if fc.data_path.startswith(f'pose.bones["{bone}"]'):
                for k in fc.keyframe_points:
                    k.interpolation = "LINEAR"

    def _fcurves(self):
        act = self.act
        if hasattr(act, "fcurves") and len(getattr(act, "layers", [])) == 0:
            return list(act.fcurves)
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out.extend(cb.fcurves)
        return out

    def _set_interp(self, frame, interp, easing, skip=()):
        for fc in self._fcurves():
            if any(fc.data_path.startswith(f'pose.bones["{b}"]') for b in skip):
                continue
            for k in fc.keyframe_points:
                if abs(k.co.x - frame) < 1e-3:
                    k.interpolation = interp
                    k.easing = easing

    def ground(self, objs, bone: str = "hips", exact: bool = True) -> None:
        """Foot planting without IK. Call just before end(): on every frame of the current action
        measure the lowest point of the skinned meshes and shift `bone` (the body's root joint)
        vertically so that point sits exactly on the floor (exact) or is at least not under it.
        The body height then follows from the leg pose, so feet neither sink nor float."""
        import numpy as np
        pb = self.rig.pose.bones[bone]
        Rinv = self.rest[bone].inverted()
        sc = bpy.context.scene
        out = []
        for f in range(self.frames + 1):
            sc.frame_set(f)
            dg = bpy.context.evaluated_depsgraph_get()
            zmin = 1e9
            for ob in objs:
                ev = ob.evaluated_get(dg)
                me = ev.to_mesh()
                co = np.empty(len(me.vertices) * 3, dtype=np.float32)
                me.vertices.foreach_get("co", co)
                zmin = min(zmin, float(co[2::3].min()) + ob.matrix_world.translation.z)
                ev.to_mesh_clear()
            d = -zmin if (exact or zmin < 0) else 0.0
            out.append((f, pb.location.copy(), d))
        for f, base, d in out:
            pb.location = base + Rinv @ Vector((0, 0, d))
            pb.keyframe_insert("location", frame=f, group=bone)
        sc.frame_set(0)

    def end(self) -> bpy.types.Action:
        act = self.act
        if self.overlay is not None:
            # Overlay bones (eye flicker, charge swell) get a scale key on every frame so their
            # curves keep their sharp shape between the sparser pose keys.
            for f in range(self.frames + 1):
                for bone, p in self.overlay(f).items():
                    pb = self.rig.pose.bones[bone]
                    s = p.get("s", 1.0)
                    pb.scale = (s, s, s) if isinstance(s, (int, float)) else s
                    pb.keyframe_insert("scale", frame=f, group=bone)
        act.use_frame_range = True
        act.frame_start = 0
        act.frame_end = self.frames
        act.use_cyclic = self.loop
        for fc in self._fcurves():
            for k in fc.keyframe_points:
                if k.interpolation == "BEZIER":
                    k.handle_left_type = "AUTO_CLAMPED"
                    k.handle_right_type = "AUTO_CLAMPED"
            fc.update()
        self.actions.append(act)
        track = self.rig.animation_data.nla_tracks.new()
        track.name = act.name
        track.strips.new(act.name, 0, act)
        track.mute = True
        self.rig.animation_data.action = None
        return act


def piecewise(table) -> callable:
    """Linear interpolation through [(frame, value), ...]; clamps outside."""
    pts = sorted(table)

    def f(x: float) -> float:
        if x <= pts[0][0]:
            return pts[0][1]
        for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
            if x <= x1:
                return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        return pts[-1][1]
    return f


# STYLE.md: the eye lens sits on its own `eye` bone. It swells while telegraphing, flickers in
# `stagger` and powers down (shrinks to ~0) in `death`, so state reads without material animation.
EYE_TELEGRAPH = piecewise([(0, 1.0), (30, 1.3)])
EYE_ATTACK = piecewise([(0, 1.3), (3, 1.45), (12, 1.0), (30, 1.0)])
EYE_STAGGER = piecewise([(0, 1.0), (2, 0.3), (5, 1.25), (8, 0.35), (12, 1.15), (16, 0.5), (21, 1.1), (25, 0.85), (30, 1.0)])
EYE_DEATH = piecewise([(0, 1.0), (4, 1.4), (10, 0.7), (16, 0.25), (22, 0.02), (30, 0.02)])


def eye_overlay(curve, bone: str = "eye"):
    return lambda f: {bone: {"s": curve(f)}}


def ease_out(t: float) -> float:
    return 1 - (1 - t) ** 3


def ease_in(t: float) -> float:
    return t ** 3


def ease_io(t: float) -> float:
    return 3 * t * t - 2 * t * t * t


# ───────────────────────────── export ─────────────────────────────


def export_glb(path: str) -> None:
    path = os.path.abspath(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc = bpy.context.scene
    rig = bpy.data.objects.get("Rig")
    if rig and rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones if rig else []:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)
    sc.frame_set(0)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_skins=True,
        export_morph=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_range=False,
        export_anim_slide_to_zero=False,
        export_def_bones=False,
        export_optimize_animation_size=False,
        export_optimize_animation_keep_anim_armature=False,
        export_reset_pose_bones=True,
        export_extras=False,
    )
    print("exported", path)


def uv_unwrap(ob: bpy.types.Object) -> None:
    """Smart-project UVs (no texture is used by the enemies, but the toon shader may sample UVs)."""
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")


# ───────────────────────────── previews ─────────────────────────────


class Previewer:
    """Workbench preview renders: flat material colours, studio light, object outlines, a 1-tile
    checker floor for scale. Never exported (create it after export_glb)."""

    def __init__(self, out_dir: str, floor_tiles: int = 4) -> None:
        self.dir = os.path.abspath(out_dir)
        os.makedirs(self.dir, exist_ok=True)
        sc = bpy.context.scene
        self.sc = sc
        sc.render.engine = "BLENDER_WORKBENCH"
        sh = sc.display.shading
        sh.light = "STUDIO"
        sh.color_type = "MATERIAL"
        sh.show_object_outline = True
        sh.object_outline_color = (0.02, 0.02, 0.03)
        sh.show_cavity = True
        sh.cavity_type = "BOTH"
        sh.cavity_ridge_factor = 0.6
        sh.cavity_valley_factor = 0.8
        sh.show_shadows = False
        sh.show_specular_highlight = False
        sc.display.render_aa = "8"
        sc.render.film_transparent = False
        sc.view_settings.view_transform = "Standard"
        w = bpy.data.worlds.new("preview_world")
        w.color = (0.11, 0.105, 0.13)
        sc.world = w
        cam_data = bpy.data.cameras.new("preview_cam")
        cam_data.type = "ORTHO"
        cam_data.clip_start = 0.1
        cam_data.clip_end = 200
        self.cam = link(bpy.data.objects.new("preview_cam", cam_data))
        sc.camera = self.cam
        self.floor = self._floor(floor_tiles)

    def _floor(self, n: int) -> bpy.types.Object:
        bm = bmesh.new()
        for i in range(-n, n):
            for j in range(-n, n):
                vs = [bm.verts.new((i + a, j + b, -0.002)) for a, b in ((0, 0), (1, 0), (1, 1), (0, 1))]
                f = bm.faces.new(vs)
                f.material_index = (i + j) % 2
        me = bpy.data.meshes.new("preview_floor")
        bm.to_mesh(me)
        bm.free()
        for nm, col in (("preview_floor_a", (0.30, 0.29, 0.33)), ("preview_floor_b", (0.24, 0.23, 0.27))):
            m = bpy.data.materials.get(nm) or bpy.data.materials.new(nm)
            m.diffuse_color = (*col, 1)
            me.materials.append(m)
        return link(bpy.data.objects.new("preview_floor", me))

    def frame_bounds(self, objs, extra=0.0) -> tuple[Vector, Vector]:
        bpy.context.view_layer.update()
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        dg = bpy.context.evaluated_depsgraph_get()
        for ob in objs:
            ev = ob.evaluated_get(dg)
            me = ev.to_mesh()
            for v in me.vertices:
                p = ob.matrix_world @ v.co
                lo = Vector(map(min, lo, p))
                hi = Vector(map(max, hi, p))
            ev.to_mesh_clear()
        pad = Vector((extra, extra, extra))
        return lo - pad, hi + pad

    def shoot(self, name: str, yaw: float, pitch: float, lo: Vector, hi: Vector, res=(800, 800),
              margin: float = 1.08, show_floor: bool = True) -> str:
        sc = self.sc
        sc.render.resolution_x, sc.render.resolution_y = res
        sc.render.resolution_percentage = 100
        y, p = math.radians(yaw), math.radians(pitch)
        d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
        rot = (-d).to_track_quat("-Z", "Y")
        right = rot @ Vector((1, 0, 0))
        up = rot @ Vector((0, 1, 0))
        corners = [Vector((x, yy, z)) for x in (lo.x, hi.x) for yy in (lo.y, hi.y) for z in (lo.z, hi.z)]
        us = [c.dot(right) for c in corners]
        vs = [c.dot(up) for c in corners]
        w, h = (max(us) - min(us)) * margin, (max(vs) - min(vs)) * margin
        cu, cv = (max(us) + min(us)) / 2, (max(vs) + min(vs)) / 2
        centre = (lo + hi) / 2
        cd = centre.dot(d)
        target = right * cu + up * cv + d * cd
        rx, ry = res
        self.cam.data.ortho_scale = max(w, h * rx / ry) if rx >= ry else max(w * ry / rx, h)
        self.cam.location = target + d * 50
        self.cam.rotation_mode = "QUATERNION"
        self.cam.rotation_quaternion = rot
        self.floor.hide_render = not show_floor
        path = os.path.join(self.dir, name + ".png")
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        return path

    def turnaround(self, objs, prefix: str = "turn", res=(700, 900)) -> list[str]:
        lo, hi = self.frame_bounds(objs)
        lo.z = 0.0
        out = []
        for nm, yaw, pitch in (("front", 0, 4), ("left", 90, 4), ("back", 180, 4), ("right", -90, 4),
                               ("threequarter", -35, 15)):
            out.append(self.shoot(f"{prefix}_{nm}", yaw, pitch, lo, hi, res))
        return out

    def iso(self, objs, name: str = "iso", res=(900, 900), lo=None, hi=None) -> str:
        if lo is None:
            lo, hi = self.frame_bounds(objs)
            lo.z = 0.0
        return self.shoot(name, ISO_YAW, ISO_PITCH, lo, hi, res)

    def thumbnail(self, objs, name: str = "thumb_160", px_per_unit: float | None = None) -> str:
        """160 px and 100 px isometric renders, framed to the model (the in-game read check)."""
        lo, hi = self.frame_bounds(objs)
        lo.z = 0.0
        self.shoot("thumb_100", ISO_YAW, ISO_PITCH, lo, hi, (100, 100), margin=1.04)
        return self.shoot(name, ISO_YAW, ISO_PITCH, lo, hi, (160, 160), margin=1.04)

    def action_frames(self, rig, objs, actions, frames_per: int = 8, res=(360, 360), lo=None, hi=None,
                      yaw: float = ISO_YAW, pitch: float = ISO_PITCH, sub: str = "anim") -> dict:
        """Render `frames_per` evenly spaced frames of each action into <dir>/<sub>/<action>_NN.png."""
        sc = self.sc
        out: dict = {}
        base = self.dir
        self.dir = os.path.join(base, sub)
        os.makedirs(self.dir, exist_ok=True)
        try:
            for act in actions:
                rig.animation_data.action = act
                if hasattr(rig.animation_data, "action_slot") and act.slots:
                    rig.animation_data.action_slot = act.slots[0]
                f0, f1 = act.frame_range
                n = frames_per
                files = []
                for i in range(n):
                    f = f0 + (f1 - f0) * i / (n - 1)
                    sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
                    files.append(self.shoot(f"{act.name}_{i:02d}", yaw, pitch, lo, hi, res))
                out[act.name] = files
        finally:
            self.dir = base
            rig.animation_data.action = None
            sc.frame_set(0)
        return out


def run_sheets(type_name: str, previews_dir: str) -> None:
    """Compose the PNG sheets (turnaround, animation contact sheets) with the system Python + PIL."""
    import subprocess
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "common2_sheets.py")
    py = os.environ.get("OD_PYTHON", "python")
    try:
        subprocess.run([py, script, type_name, previews_dir], check=True)
    except Exception as e:  # sheets are a review aid; the model build must not depend on them
        print("sheet composition failed:", e)


def floor_report(rig: bpy.types.Object, objs, actions, step: int = 2, tol: float = 0.012, frames=None) -> list[str]:
    """Play every action and report the lowest point the skinned meshes reach (armature space, so
    Z = height above the floor), with the bones whose parts are below the floor on the worst frame
    and on the final frame. Anything below -tol means a part sinks through the floor in that
    action. `frames` = {action: [frame, ...]} adds a per-bone listing for those frames.
    Returns the list of problems (also printed)."""
    sc = bpy.context.scene
    problems = []

    def sample(f):
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        per: dict = {}
        for ob in objs:
            names = {g.index: g.name for g in ob.vertex_groups}
            ev = ob.evaluated_get(dg)
            me = ev.to_mesh()
            for v in me.vertices:
                z = (ob.matrix_world @ v.co).z
                g = max(v.groups, key=lambda x: x.weight, default=None)
                nm = names.get(g.group, "?") if g else "?"
                if z < per.get(nm, 1e9):
                    per[nm] = z
            ev.to_mesh_clear()
        return per

    def low(per):
        return ", ".join(f"{n} {z:+.2f}" for n, z in sorted(per.items(), key=lambda kv: kv[1]) if z < -tol)

    for act in actions:
        rig.animation_data.action = act
        if hasattr(rig.animation_data, "action_slot") and act.slots:
            rig.animation_data.action_slot = act.slots[0]
        f0, f1 = (int(v) for v in act.frame_range)
        worst, worst_f, worst_per, per = 1e9, f0, {}, {}
        for f in list(range(f0, f1, step)) + [f1]:
            per = sample(f)
            zmin = min(per.values())
            if zmin < worst:
                worst, worst_f, worst_per = zmin, f, per
        end_min = min(per.values())
        note = "" if worst >= -tol else f"  <-- below the floor: {low(worst_per)}"
        print(f"floor check {act.name:<10} lowest z {worst:+.3f} at frame {worst_f}, final frame {end_min:+.3f}{note}")
        if end_min < -tol and worst_f != f1:
            print(f"            final frame below the floor: {low(per)}")
        for f in (frames or {}).get(act.name, []):
            per = sample(f)
            print(f"            frame {f}: " + ", ".join(f"{n} {z:+.2f}" for n, z in sorted(per.items(), key=lambda kv: kv[1])[:10]))
        if worst < -tol:
            problems.append(f"{act.name}: {worst:+.3f} at frame {worst_f}")
    rig.animation_data.action = None
    sc.frame_set(0)
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()
    return problems


def mesh_stats(objs) -> tuple[int, Vector, Vector]:
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    tris = 0
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in objs:
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        for v in me.vertices:
            p = ob.matrix_world @ v.co
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
        ev.to_mesh_clear()
    return tris, lo, hi
