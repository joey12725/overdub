"""
Modelling helpers for the OVERDUB wardrobe headgear (Blender 4.5, bmesh only). Self-contained:
nothing outside art/wardrobe is imported. The geometry toolkit follows the conventions of the
melee props (art/weapons) so the two prop families are built the same way.

AUTHORING SPACE = GODOT SPACE, HEAD-BONE RELATIVE. Every coordinate is a Godot coordinate (+Y up,
+Z = Moxie's front, +X = her left) measured from the Head bone's joint (the pivot at the top of the
neck). The glb is exported with export_yup=False so the numbers land in the file unchanged; previews
use cameras whose up vector is +Y.

Units: metres = tiles. Moxie is about 1.6 tall; her head is about 0.25 tall.
"""
from __future__ import annotations

import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

# ───────────────────────────── palette ─────────────────────────────
# Material names are the styling hook in Godot (names ending in _glow are emissive).
PALETTE = {
    "helmet": "#3b3442",          # the item's main colour (look.color in data/gear.json), set per item
    "helmet_trim": "#221e27",     # seams, piping, stitching, straps
    "helmet_dark": "#2c2729",     # dark hardware / rubber (matches headphones_dark)
    "helmet_metal": "#c9cdd6",    # chrome / aluminium
    "helmet_steel": "#7d8394",    # darker machined steel
    "helmet_accent": "#f5b819",   # Moxie's yellow
    "helmet_accent2": "#ff4fa3",  # magenta tape / stickers
    "helmet_paper": "#f2efe6",
    "helmet_copper": "#d98a4a",
    "helmet_lens": "#ffb52e",
    "helmet_glow": "#5ff6ff",     # emissive, set per item
    # preview-only
    "ink": "#0d0b10",
    "mannequin": "#8d8894",
}
_mats: dict = {}


def hexcol(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    # sRGB -> linear
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)


def M(name):
    """Export material: Principled, base colour only (+ emission for *_glow)."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    col = hexcol(PALETTE[name])
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = col
    b.inputs["Roughness"].default_value = 0.8
    b.inputs["Metallic"].default_value = 0.0
    if name.endswith("_glow"):
        b.inputs["Emission Color"].default_value = col
        b.inputs["Emission Strength"].default_value = 2.0
    m.diffuse_color = col
    _mats[name] = m
    return m


def reset(main=None, **overrides):
    """Empty the scene and the material cache; set the per-item colours."""
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.cameras,
                 bpy.data.lights, bpy.data.curves, bpy.data.actions, bpy.data.images):
        for d in list(coll):
            if d.users == 0 or coll in (bpy.data.materials, bpy.data.meshes, bpy.data.armatures, bpy.data.actions):
                try:
                    coll.remove(d)
                except Exception:
                    pass
    _mats.clear()
    if main:
        PALETTE["helmet"] = main
    PALETTE.update(overrides)


# ───────────────────────────── low level ─────────────────────────────

def xmat(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Matrix from location, XYZ euler in degrees, scale."""
    e = Euler([math.radians(a) for a in rot], "XYZ")
    m = Matrix.Translation(Vector(loc)) @ e.to_matrix().to_4x4()
    if scale != (1, 1, 1):
        s = Matrix.Identity(4)
        s[0][0], s[1][1], s[2][2] = scale
        m = m @ s
    return m


AXIS = {  # rotates a shape built along +Z onto the named axis
    "Z": Matrix.Identity(4),
    "Y": Matrix.Rotation(math.radians(-90), 4, "X"),
    "-Y": Matrix.Rotation(math.radians(90), 4, "X"),
    "X": Matrix.Rotation(math.radians(90), 4, "Y"),
    "-X": Matrix.Rotation(math.radians(-90), 4, "Y"),
    "-Z": Matrix.Rotation(math.radians(180), 4, "X"),
}


def _obj(bm, mat, name="part", fix_normals=True):
    if fix_normals:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(M(mat))
    return o


def move(o, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    o.data.transform(xmat(loc, rot, scale))
    if scale[0] * scale[1] * scale[2] < 0:
        o.data.flip_normals()
    return o


def apply(o, m):
    o.data.transform(m)
    if m.determinant() < 0:
        o.data.flip_normals()
    return o


def bevel(o, w=0.004, seg=1, angle=30.0):
    """Bevel every edge sharper than `angle` degrees."""
    if w <= 0:
        return o
    bm = bmesh.new()
    bm.from_mesh(o.data)
    lim = math.radians(angle)
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=w, offset_type="OFFSET", segments=seg, profile=0.5,
                        affect="EDGES", clamp_overlap=True)
    bm.to_mesh(o.data)
    bm.free()
    return o


def copy(o, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    c = o.copy()
    c.data = o.data.copy()
    bpy.context.scene.collection.objects.link(c)
    return move(c, loc, rot, scale)


def mirror(o, axis="X"):
    """A mirrored copy across the plane normal to `axis`."""
    s = {"X": (-1, 1, 1), "Y": (1, -1, 1), "Z": (1, 1, -1)}[axis]
    return copy(o, scale=s)


def setmat(o, mat):
    o.data.materials.clear()
    o.data.materials.append(M(mat))
    return o


# ───────────────────────────── primitives ─────────────────────────────

def box(size, loc=(0, 0, 0), rot=(0, 0, 0), mat="helmet_dark", bev=0.0, seg=1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    o = _obj(bm, mat, "box")
    bevel(o, bev, seg)
    return move(o, loc, rot)


def cyl(r, h, loc=(0, 0, 0), axis="Y", mat="helmet_dark", n=16, r2=None, bev=0.0, seg=1, rot=(0, 0, 0)):
    """Cylinder / cone frustum centred on loc, along `axis` (r at the -axis end, r2 at the + end)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=n, radius1=r,
                          radius2=r if r2 is None else r2, depth=h)
    o = _obj(bm, mat, "cyl")
    bevel(o, bev, seg)
    apply(o, AXIS[axis])
    return move(o, loc, rot)


def sphere(r, loc=(0, 0, 0), mat="helmet_dark", n=12, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=n, v_segments=max(6, n // 2), radius=r)
    o = _obj(bm, mat, "sphere")
    return move(o, loc, (0, 0, 0), scale)


def lathe(profile, loc=(0, 0, 0), axis="Y", mat="helmet_dark", n=16, closed=False, rot=(0, 0, 0), arc=360.0):
    """Revolve a profile of (radius, height) points about the axis. Radius 0 makes a pole.
    The profile should describe a closed outline (start and end on the axis, or closed=True)."""
    bm = bmesh.new()
    rings = []
    full = arc >= 359.9
    cnt = n if full else n + 1
    for (r, h) in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0, 0, h))])
        else:
            rings.append([bm.verts.new((r * math.cos(math.radians(arc) * i / n), r * math.sin(math.radians(arc) * i / n), h))
                          for i in range(cnt)])
    pairs = list(zip(rings[:-1], rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for a, b in pairs:
        if len(a) == 1 and len(b) == 1:
            continue
        seg_n = n if full else n
        for i in range(seg_n):
            j = (i + 1) % cnt if full else i + 1
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[i]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    if not full:
        for side in (0, cnt - 1):
            vs = [rg[side] if len(rg) > 1 else rg[0] for rg in rings]
            ded = []
            for v in vs:
                if not ded or ded[-1] is not v:
                    ded.append(v)
            if len(ded) >= 3:
                try:
                    bm.faces.new(ded)
                except ValueError:
                    pass
    o = _obj(bm, mat, "lathe")
    apply(o, AXIS[axis])
    return move(o, loc, rot)


def ring(R, r, loc=(0, 0, 0), axis="Y", mat="helmet_dark", n=20, m=8, rot=(0, 0, 0), flat=None):
    """Torus of major radius R, tube radius r (flat = (radial half-width, axial half-height) makes
    a rectangular-section washer instead)."""
    if flat:
        a, b = flat
        prof = [(R - a, -b), (R + a, -b), (R + a, b), (R - a, b)]
    else:
        prof = [(R + r * math.cos(2 * math.pi * k / m), r * math.sin(2 * math.pi * k / m)) for k in range(m)]
    return lathe(prof, loc, axis, mat, n, closed=True, rot=rot)


def prism(outline, depth, loc=(0, 0, 0), normal="X", mat="helmet_dark", bev=0.0, seg=1, rot=(0, 0, 0)):
    """Extrude a 2D polygon (u, v) by `depth`, centred on its plane.
    normal X: u -> +Z, v -> +Y.   normal Z: u -> +X, v -> +Y.   normal Y: u -> +X, v -> +Z."""
    bm = bmesh.new()
    lo = [bm.verts.new((u, v, -depth / 2)) for (u, v) in outline]
    hi = [bm.verts.new((u, v, depth / 2)) for (u, v) in outline]
    bm.faces.new(lo)
    bm.faces.new(hi)
    k = len(outline)
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    o = _obj(bm, mat, "prism")
    bevel(o, bev, seg)
    if normal == "X":      # (u, v, w) -> (w, v, u)
        apply(o, Matrix(((0, 0, 1, 0), (0, 1, 0, 0), (1, 0, 0, 0), (0, 0, 0, 1))))
    elif normal == "Y":    # (u, v, w) -> (u, w, v)
        apply(o, Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    return move(o, loc, rot)


def loft(sections, mat="helmet_dark", caps=True, closed_loop=False):
    """Skin a list of closed cross-sections (each a list of 3D points, same count)."""
    bm = bmesh.new()
    rs = [[bm.verts.new(p) for p in s] for s in sections]
    k = len(sections[0])
    pairs = list(zip(rs[:-1], rs[1:]))
    if closed_loop:
        pairs.append((rs[-1], rs[0]))
    for a, b in pairs:
        for i in range(k):
            j = (i + 1) % k
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if caps and not closed_loop:
        bm.faces.new(rs[0])
        bm.faces.new(rs[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    return _obj(bm, mat, "loft")


def _frames(pts, up):
    """Parallel-transport frames along a polyline: list of (pos, side, up, tangent)."""
    pts = [Vector(p) for p in pts]
    out = []
    upv = Vector(up).normalized()
    for i, p in enumerate(pts):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
        t.normalize()
        side = t.cross(upv)
        if side.length < 1e-5:
            side = t.cross(Vector((1, 0, 0)))
        side.normalize()
        upv = side.cross(t).normalized()
        out.append((p, side, upv, t))
    return out


def sweep(pts, section, mat="helmet_dark", up=(1, 0, 0), caps=True, scale=None):
    """Sweep a 2D section (list of (a, b): a along `side`, b along `up`) along a polyline.
    scale: optional list of per-point multipliers (taper)."""
    fr = _frames(pts, up)
    secs = []
    for i, (p, side, upv, _t) in enumerate(fr):
        k = scale[i] if scale else 1.0
        secs.append([p + side * (a * k) + upv * (b * k) for (a, b) in section])
    return loft(secs, mat, caps)


def tube(pts, r, mat="helmet_dark", n=8, up=(1, 0, 0), scale=None):
    sec = [(r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n)) for k in range(n)]
    return sweep(pts, sec, mat, up, True, scale)


def ribbon(pts, width, thick, mat="helmet_trim", up=(1, 0, 0), scale=None):
    """Flat strip; `width` runs along the side vector (= tangent x up), thickness along up."""
    w, t = width / 2, thick / 2
    return sweep(pts, [(-w, -t), (w, -t), (w, t), (-w, t)], mat, up, True, scale)


def arc_pts(c, r, a0, a1, n, plane="YZ"):
    """Points on a circular arc (degrees) in a plane. YZ: angle 0 = +Z, 90 = +Y."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        u, v = r * math.cos(a), r * math.sin(a)
        if plane == "YZ":
            out.append((c[0], c[1] + v, c[2] + u))
        elif plane == "XY":
            out.append((c[0] + u, c[1] + v, c[2]))
        else:  # XZ
            out.append((c[0] + u, c[1], c[2] + v))
    return out


def smooth_path(pts, sub=4):
    """Catmull-Rom resample of a polyline."""
    P = [Vector(p) for p in pts]
    P = [P[0]] + P + [P[-1]]
    out = []
    for i in range(1, len(P) - 2):
        for s in range(sub):
            t = s / sub
            a, b, c, d = P[i - 1], P[i], P[i + 1], P[i + 2]
            out.append(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                              + (-a + 3 * b - 3 * c + d) * t * t * t))
    out.append(P[-2])
    return out


def helix(r, y0, y1, turns, axis="Y", steps=10, phase=0.0, r1=None):
    pts = []
    k = max(2, int(turns * steps))
    for i in range(k + 1):
        t = i / k
        a = phase + t * turns * 2 * math.pi
        rr = r + ((r1 - r) * t if r1 is not None else 0)
        u, v, w = rr * math.cos(a), rr * math.sin(a), y0 + (y1 - y0) * t
        pts.append({"Y": (u, w, v), "Z": (u, v, w), "X": (w, u, v)}[axis])
    return pts


def star(R, r, points=5, rot=90.0):
    out = []
    for i in range(points * 2):
        a = math.radians(rot + i * 180.0 / points)
        rr = R if i % 2 == 0 else r
        out.append((rr * math.cos(a), rr * math.sin(a)))
    return out


def bolt_outline(s=1.0):
    """A lightning-bolt polygon about 1 x 2 units, centred."""
    p = [(-0.15, 1.0), (0.5, 1.0), (0.1, 0.2), (0.5, 0.2), (-0.35, -1.0), (-0.05, -0.1), (-0.5, -0.1)]
    return [(x * s, y * s) for x, y in p]


def rounded_rect(w, h, r, n=3):
    out = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def boolean(o, cutters, op="DIFFERENCE"):
    if not isinstance(cutters, (list, tuple)):
        cutters = [cutters]
    c = join(cutters, "cutter", finish=False)
    mod = o.modifiers.new("b", "BOOLEAN")
    mod.operation = op
    mod.object = c
    mod.solver = "EXACT"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    o.modifiers.clear()
    old = o.data
    o.data = me
    bpy.data.meshes.remove(old)
    bpy.data.objects.remove(c, do_unlink=True)
    return o


def hexbolt(r, h, loc, axis="X", mat="helmet_steel"):
    return cyl(r, h, loc, axis, mat, n=6, bev=min(r, h) * 0.18)


def screw(r, loc, axis="X", mat="helmet_steel", h=None):
    h = h or r * 0.6
    return lathe([(0, 0), (r, 0), (r, h * 0.5), (r * 0.6, h), (0, h)], loc, axis, mat, n=8)


def knob(r, h, loc, axis="Y", mat="helmet_dark", cap="helmet_accent", n=12):
    body = lathe([(0, 0), (r * 1.15, 0), (r * 1.15, h * 0.18), (r, h * 0.25), (r * 0.92, h), (0, h)], loc, axis, mat, n)
    off = {"Y": (0, h, 0), "Z": (0, 0, h), "X": (h, 0, 0), "-X": (-h, 0, 0), "-Z": (0, 0, -h), "-Y": (0, -h, 0)}[axis]
    top = cyl(r * 0.55, h * 0.08, (loc[0] + off[0], loc[1] + off[1], loc[2] + off[2]), axis, cap, n=8)
    return [body, top]


def wrap(r, y0, y1, turns, mat="helmet_trim", width=0.02, thick=0.004, axis="Y", core=True, loc=(0, 0, 0), tilt=13.0):
    """Tape-wrapped grip along Y: a core cylinder plus `turns` raised, slightly tilted bands."""
    parts = []
    if core:
        parts.append(cyl(r, abs(y1 - y0), (0, (y0 + y1) / 2, 0), "Y", mat, n=12))
    for k in range(turns):
        y = y0 + (y1 - y0) * (k + 0.5) / turns
        parts.append(ring(r + thick / 2, 0, (0, y, 0), "Y", mat, n=12, flat=(thick / 2 + 0.0015, width / 2), rot=(tilt, 0, tilt * 0.4)))
    for p in parts:
        move(p, loc)
    return parts


def band(r, y, w, mat="helmet_accent2", axis="Y", n=12, t=0.003):
    """A flat tape band around a cylinder of radius r."""
    return ring(r + t / 2, 0, {"Y": (0, y, 0), "Z": (0, 0, y), "X": (y, 0, 0)}[axis], axis, mat, n, flat=(t / 2 + 0.001, w / 2))


# ───────────────────────────── assembly ─────────────────────────────

def flat(parts):
    out = []
    for p in parts:
        if isinstance(p, (list, tuple)):
            out += flat(p)
        elif p is not None:
            out.append(p)
    return out


def join(parts, name, finish=True, sharp=35.0):
    """Merge parts into one mesh object (materials kept by name)."""
    parts = flat(parts)
    bm = bmesh.new()
    mats = []
    for p in parts:
        me = p.data
        remap = []
        for m in me.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        tmp = bmesh.new()
        tmp.from_mesh(me)
        vmap = {}
        for v in tmp.verts:
            vmap[v.index] = bm.verts.new(v.co)
        for f in tmp.faces:
            try:
                nf = bm.faces.new([vmap[v.index] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = remap[f.material_index] if remap else 0
            nf.smooth = True
        tmp.free()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in parts:
        d = p.data
        bpy.data.objects.remove(p, do_unlink=True)
        if d.users == 0:
            bpy.data.meshes.remove(d)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if finish:
        finish_mesh(o, sharp)
    return o


def finish_mesh(o, sharp=35.0):
    """Smooth shading with sharp edges by angle, face-area-weighted normals, triangulated."""
    me = o.data
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(sharp))
    mod = o.modifiers.new("wn", "WEIGHTED_NORMAL")
    mod.keep_sharp = True
    mod.weight = 60
    tri = o.modifiers.new("tri", "TRIANGULATE")
    tri.keep_custom_normals = True
    dg = bpy.context.evaluated_depsgraph_get()
    new = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    new.name = me.name
    o.modifiers.clear()
    o.data = new
    bpy.data.meshes.remove(me)
    return o


def empty(name, loc, rot=(0, 0, 0), parent=None, size=0.03):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = size
    bpy.context.scene.collection.objects.link(e)
    e.matrix_world = xmat(loc, rot)
    if parent is not None:
        e.parent = parent
    return e


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def export_glb(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=False,
        export_apply=False, export_animations=False, export_cameras=False, export_lights=False,
        export_materials="EXPORT", export_normals=True, export_texcoords=False,
        export_tangents=False, export_skins=True, export_extras=False,
        export_vertex_color="NONE", export_def_bones=False, export_rest_position_armature=True,
    )


# ───────────────────────────── wardrobe additions ─────────────────────────────

# The head the gear is fitted to: art/wardrobe/spec.py HEAD (measured on the current Moxie model,
# relative to the Head bone). See docs/WARDROBE.md "Head fit".
import sys as _sys
if HERE not in _sys.path:
    _sys.path.insert(0, HERE)
import spec as _spec  # noqa: E402

HEAD_C = _spec.HEAD["skull_c"]      # skull centre
HEAD_R = _spec.HEAD["skull_r"]      # skull radii (x, y, z)
HAIR = _spec.HEAD["hair"]           # hair thickness over the skull at brow height
HAIR_TOP = _spec.HEAD["hair_top"]   # extra hair thickness toward the crown of the head
CUP_C = _spec.HEAD["cup_c"]         # headphone ear-cup centre (mirror in x)
CUP_R = _spec.HEAD["cup_r"]
BAND_TOP = _spec.HEAD["band_top"]   # top of the headphone band


def head_pt(az, el, grow=0.0):
    """Point on the (skull + grow) ellipsoid. az: degrees about +Y, 0 = front (+Z), +90 = her left
    (+X). el: degrees up from the skull's equator."""
    a, e = math.radians(az), math.radians(el)
    if grow > 0.0:  # gear rides on the hair, which is thicker toward the crown
        grow += HAIR_TOP * max(0.0, math.sin(e)) ** 1.5
    rx, ry, rz = HEAD_R[0] + grow, HEAD_R[1] + grow, HEAD_R[2] + grow
    return Vector((HEAD_C[0] + rx * math.sin(a) * math.cos(e), HEAD_C[1] + ry * math.sin(e),
                   HEAD_C[2] + rz * math.cos(a) * math.cos(e)))


def head_n(az, el):
    """Outward direction of the head surface at (az, el)."""
    p = head_pt(az, el, 0.0) - Vector(HEAD_C)
    n = Vector((p.x / HEAD_R[0] ** 2, p.y / HEAD_R[1] ** 2, p.z / HEAD_R[2] ** 2))
    return n.normalized()


def surf(fn, nu, nv, thick, mat="helmet", name="surf"):
    """A solid shell from a parametric surface fn(u, v) -> point (u, v in 0..1), thickened by
    `thick` along the surface normal."""
    bm = bmesh.new()
    grid = [[bm.verts.new(fn(i / nu, j / nv)) for i in range(nu + 1)] for j in range(nv + 1)]
    for j in range(nv):
        for i in range(nu):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    return _obj(bm, mat, name)


def orient(o, pos, normal, up=(0, 1, 0)):
    """Place a part built with +Z as its outward axis and +Y as its up so that +Z points along
    `normal` at `pos`."""
    z = Vector(normal).normalized()
    x = Vector(up).cross(z)
    if x.length < 1e-5:
        x = Vector((1, 0, 0))
    x.normalize()
    y = z.cross(x).normalized()
    m = Matrix(((x.x, y.x, z.x, pos[0]), (x.y, y.y, z.y, pos[1]), (x.z, y.z, z.z, pos[2]), (0, 0, 0, 1)))
    return apply(o, m)


def orient_all(parts, pos, normal, up=(0, 1, 0)):
    out = flat(parts)
    for p in out:
        orient(p, pos, normal, up)
    return out
