"""Containers and loot: crate, barrel, chest (upper and lower looks)."""
from __future__ import annotations

import math

import bmesh
import bpy
from mathutils import Vector

import decor_lib as L
from decor_lib import M


# ───────────────────────────── shared pieces ─────────────────────────────

def paneled_box(size, loc, body="paint_yellow", frame=None, inset=0.055, depth=0.018,
                faces=("x", "y", "top"), bev=0.012, name="paneled"):
    """A box whose chosen faces carry a recessed panel inside a raised frame (crate sides).

    The frame ring takes `frame` (or `body`), the recessed panel takes `body`.
    """
    sx, sy, sz = size
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    pick = []
    for f in bm.faces:
        n = f.normal
        if ("x" in faces and abs(n.x) > 0.9) or ("y" in faces and abs(n.y) > 0.9) or \
                ("top" in faces and n.z > 0.9):
            pick.append(f)
    for f in bm.faces:
        f.material_index = 1
    res = bmesh.ops.inset_individual(bm, faces=pick, thickness=inset, depth=-depth, use_even_offset=True)
    for f in pick:
        f.material_index = 0
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    obj = L._mesh_obj(bm, name, [M(body), M(frame or body)])
    return L.bevel(obj, bev, 1, angle=50)


def star_points(r_out, r_in, n=5, rot=90.0):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot) + i * math.pi / n
        r = r_out if i % 2 == 0 else r_in
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return pts


def star(r, loc, rot=(0, 0, 0), mat="hazard_dark", depth=0.012, name="star"):
    """A raised five-point star stencil (the R03 / R04 crate emblem). Faces -Y by default."""
    return L.prism(star_points(r, r * 0.42), depth, loc=loc, rot=rot, mat=mat, name=name)


def rivets(points, r=0.012, h=0.01, axis="y", sign=-1, mat="metal_dark"):
    out = []
    rot = {"x": (0, 90 * sign, 0), "y": (90 * -sign, 0, 0), "z": (0, 0, 0)}[axis]
    for p in points:
        out.append(L.cyl(r, h, loc=p, rot=rot, mat=mat, n=6, r2=r * 0.6, name="rivet"))
    return out


def handle_loop(cx, cz, y, w=0.16, h=0.07, r=0.014, mat="metal_dark", axis="x"):
    """A U-shaped grab handle standing off a face at `y` (face normal -Y) or at x (normal +-X)."""
    pts = [(-w / 2, 0, -h * 0.2), (-w / 2, -h, 0), (w / 2, -h, 0), (w / 2, 0, -h * 0.2)]
    pts = L.fillet_path(pts, h * 0.45, 3)
    obj = L.tube([tuple(p) for p in pts], r, mat=mat, smooth=False, res=1)
    if axis == "x":
        L.place(obj, (cx, y, cz))
    else:
        sgn = 1 if y > 0 else -1
        L.place(obj, (y, cx, cz), (0, 0, 90 if sgn > 0 else -90))
    return obj


# ───────────────────────────── crate ─────────────────────────────

def _crate_upper_unit(size, loc, rot_z=0.0, emblem=True, name="crate"):
    sx, sy, sz = size
    parts = [paneled_box(size, (0, 0, sz / 2), body="paint_yellow", frame="wood", inset=0.05,
                         depth=0.02, faces=("x", "y", "top"), name=name)]
    # Steel corner guards on the four vertical edges and the top / bottom rims.
    g = 0.075
    for ix in (-1, 1):
        for iy in (-1, 1):
            parts.append(L.box((g, g, sz + 0.012), (ix * (sx / 2 - g / 2 + 0.006), iy * (sy / 2 - g / 2 + 0.006), sz / 2),
                               mat="metal_dark", bev=0.008))
    for z in (0.03, sz - 0.03):
        parts.append(L.box((sx + 0.014, sy + 0.014, 0.05), (0, 0, z), mat="metal_dark", bev=0.008))
    # Handles on the two X sides.
    for sgn in (-1, 1):
        parts.append(handle_loop(0, sz * 0.62, sgn * (sx / 2 + 0.005), w=0.2, h=0.055, axis="side"))
    if emblem:
        parts.append(star(sz * 0.26, (0, -sy / 2 + 0.002, sz * 0.5), mat="hazard_dark"))
    # Stencil bar on the side: two short slats of dark paint.
    parts.append(L.box((0.008, sy * 0.4, 0.035), (sx / 2 - 0.004 + 0.006, 0, sz * 0.3), mat="hazard_dark"))
    # Rivets at the guards.
    pts = []
    for ix in (-1, 1):
        for z in (sz * 0.3, sz * 0.7):
            pts.append((ix * (sx / 2 - g / 2), -sy / 2 - 0.002 + 0.006, z))
    parts += rivets(pts, r=0.013)
    obj = L.join(parts, name)
    L.place(obj, loc, (0, 0, rot_z))
    return obj


def crate_upper():
    big = _crate_upper_unit((0.64, 0.6, 0.5), (0, 0, 0), name="big")
    small = _crate_upper_unit((0.42, 0.38, 0.3), (0.05, 0.04, 0.5), rot_z=-18, emblem=False, name="small")
    # A cassette lying on top of the small crate: the scavenger's find.
    cas = [L.box((0.16, 0.1, 0.025), (0, 0, 0.0125), mat="graffiti", bev=0.006),
           L.box((0.1, 0.04, 0.006), (0, -0.0, 0.027), mat="hazard_dark")]
    for x in (-0.03, 0.03):
        cas.append(L.cyl(0.012, 0.008, loc=(x, 0, 0.027), mat="casing", n=8))
    cassette = L.join(cas, "cassette")
    L.place(cassette, (0.08, 0.02, 0.8), (0, 0, 25))
    body = L.join([big, small, cassette], "Body")
    return [L.finish(body)]


def crate_lower():
    """Heavy plated case (R04 prop library): dark riveted metal, hazard star, neon seam."""
    sx, sy, sz = 0.7, 0.52, 0.46
    parts = [paneled_box((sx, sy, sz * 0.78), (0, 0, sz * 0.39), body="metal", frame="metal_dark",
                         inset=0.06, depth=0.022, faces=("x", "y"), bev=0.018, name="base")]
    # Overhanging lid slab with chamfered top.
    parts.append(L.box((sx + 0.03, sy + 0.03, sz * 0.24), (0, 0, sz * 0.78 + sz * 0.12), mat="metal_dark",
                       bev=0.03, seg=1, taper=(0.94, 0.92)))
    # Lid detail: two raised ribs and a hazard-striped carry bar across the top.
    for x in (-0.22, 0.22):
        parts.append(L.box((0.06, sy - 0.04, 0.03), (x, 0, sz + 0.012), mat="trim", bev=0.008))
    parts.append(L.hazard_box((0.3, 0.07, 0.035), (0, 0, sz + 0.02), period=0.06, bev=0.006))
    # Glowing seam between lid and base (front + sides).
    parts.append(L.box((sx - 0.02, sy + 0.012, 0.02), (0, 0, sz * 0.78 + 0.004), mat="neon_glow"))
    # Corner bumpers.
    for ix in (-1, 1):
        for iy in (-1, 1):
            parts.append(L.box((0.09, 0.09, sz * 0.74), (ix * (sx / 2 - 0.03), iy * (sy / 2 - 0.03), sz * 0.37),
                               mat="trim", bev=0.02))
    # Hazard star on the front panel and a side stripe block.
    parts.append(star(0.11, (0, -sy / 2 + 0.006, sz * 0.4), mat="paint_yellow"))
    for sgn in (-1, 1):
        parts.append(handle_loop(0, sz * 0.45, sgn * (sx / 2 + 0.03), w=0.22, h=0.06, axis="side"))
    # Latch blocks.
    for x in (-0.2, 0.2):
        parts.append(L.box((0.07, 0.03, 0.09), (x, -sy / 2 - 0.022, sz * 0.76), mat="paint_yellow", bev=0.008))
    pts = [(x, -sy / 2 - 0.015, z) for x in (-0.25, 0.25) for z in (0.08, sz * 0.62)]
    parts += rivets(pts, r=0.014)
    body = L.join(parts, "Body")
    return [L.finish(body)]


# ───────────────────────────── barrel ─────────────────────────────

def _drum_profile(r=0.24, h=0.68):
    hoop = 0.012
    return [
        (0.0, 0.0), (r - 0.02, 0.0), (r, 0.015), (r, 0.03),
        (r + 0.004, 0.035), (r + 0.004, 0.06), (r, 0.065),
        (r, h * 0.3 - 0.02), (r + hoop, h * 0.3 - 0.01), (r + hoop, h * 0.3 + 0.01), (r, h * 0.3 + 0.02),
        (r, h * 0.7 - 0.02), (r + hoop, h * 0.7 - 0.01), (r + hoop, h * 0.7 + 0.01), (r, h * 0.7 + 0.02),
        (r, h - 0.06), (r + 0.006, h - 0.04), (r + 0.006, h - 0.005), (r - 0.02, h),
        (r - 0.022, h - 0.02), (0.0, h - 0.02),
    ]


def barrel_upper():
    r, h = 0.24, 0.68
    prof = _drum_profile(r, h)
    roles = []
    for i in range(len(prof) - 1):
        z = (prof[i][1] + prof[i + 1][1]) / 2
        rr = (prof[i][0] + prof[i + 1][0]) / 2
        if rr < r - 0.015 and z > h - 0.05:
            roles.append("metal")
        elif rr > r + 0.001 or z < 0.07 or z > h - 0.07:
            roles.append("rust")
        else:
            roles.append("red_paint")
    drum = L.lathe(prof, mat="red_paint", n=24, mats_per_segment=roles, name="drum")
    parts = [drum]
    # Bung caps and a dent: a pressed-in patch on the body.
    parts.append(L.cyl(0.035, 0.03, loc=(0.12, 0.05, h - 0.01), mat="brass", n=8))
    parts.append(L.cyl(0.025, 0.026, loc=(-0.13, -0.04, h - 0.012), mat="brass", n=8))
    # A painted star band: a yellow stencilled star on the front belly.
    parts.append(star(0.085, (0, -r - 0.003, h * 0.5), mat="paint_yellow", depth=0.008))
    # A carry handle welded to the rim and a hand-painted band of yellow.
    hp = L.fillet_path([(-0.07, -0.16, h - 0.03), (-0.07, -0.16, h + 0.05), (0.07, -0.16, h + 0.05),
                        (0.07, -0.16, h - 0.03)], 0.025, 3)
    parts.append(L.tube([tuple(p) for p in hp], 0.011, mat="metal_dark", smooth=False, res=1))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=40)]


def barrel_lower():
    """Sealed canister (R04): dark drum, hazard-banded crown, neon belly band, lid handle."""
    r, h = 0.25, 0.7
    prof = [
        (0.0, 0.0), (r - 0.03, 0.0), (r, 0.03), (r, 0.08), (r + 0.015, 0.09), (r + 0.015, 0.13), (r, 0.14),
        (r, 0.3), (r - 0.012, 0.31), (r - 0.012, 0.39), (r, 0.40),
        (r, h - 0.17), (r + 0.015, h - 0.16), (r + 0.015, h - 0.06), (r, h - 0.05),
        (r - 0.03, h), (0.09, h), (0.09, h + 0.01), (0.0, h + 0.01),
    ]
    drum = L.lathe(prof, mat="metal", n=24, name="drum")
    # Material bands by height: neon recess, hazard crown band (striped by angle), dark rims.
    me = drum.data
    mats = ["metal", "metal_dark", "neon_glow", "paint_yellow", "hazard_dark"]
    me.materials.clear()
    for m in mats:
        me.materials.append(M(m))
    for p in me.polygons:
        c = p.center
        rad = math.hypot(c.x, c.y)
        ang = math.degrees(math.atan2(c.y, c.x)) % 360
        if 0.3 < c.z < 0.4 and rad < r - 0.005:
            p.material_index = 2
        elif h - 0.165 < c.z < h - 0.055 and rad > r + 0.005:
            p.material_index = 3 if int(ang // 30) % 2 == 0 else 4
        elif rad > r + 0.005 or c.z > h - 0.04 or c.z < 0.03:
            p.material_index = 1
        else:
            p.material_index = 0
    parts = [drum]
    # Lid handle and vent valve.
    hp = L.fillet_path([(-0.08, 0, h), (-0.08, 0, h + 0.07), (0.08, 0, h + 0.07), (0.08, 0, h)], 0.03, 3)
    parts.append(L.tube([tuple(p) for p in hp], 0.013, mat="metal_dark", smooth=False, res=1))
    parts.append(L.cyl(0.03, 0.05, loc=(0.15, -0.08, h), mat="paint_yellow", n=8))
    # Pink ring emblem on the front (R04 barrel graffiti face reads as a ring at this size).
    ring = L.torus(0.07, 0.012, loc=(0, -r - 0.004, 0.22), rot=(90, 0, 0), mat="neon_glow", n=20, m=4,
                   square=True)
    parts.append(ring)
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=40)]


# ───────────────────────────── chest ─────────────────────────────

def _tray(sx, sy, sz, wall, mat_out, mat_in):
    """A hollow box (outer shell + inner cavity), open at the top."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz + sz / 2))
    top = [f for f in bm.faces if f.normal.z > 0.9][0]
    for f in bm.faces:
        f.material_index = 0
    r = bmesh.ops.inset_individual(bm, faces=[top], thickness=wall, depth=0.0)
    ext = bmesh.ops.extrude_face_region(bm, geom=[top])
    nv = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, -(sz - wall)), verts=nv)
    nf = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMFace)]
    bm.faces.remove(top) if top.is_valid else None
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        c = f.calc_center_median()
        inner = abs(c.x) < sx / 2 - wall * 0.5 and abs(c.y) < sy / 2 - wall * 0.5 and c.z > wall * 0.5
        f.material_index = 1 if inner else 0
    obj = L._mesh_obj(bm, "tray", [M(mat_out), M(mat_in)])
    return obj


def chest_upper():
    """Scavenger loot chest (R03): wooden body with yellow steel bands, barrel lid, brass lock.
    The lid is the separate object "Lid", its origin on the hinge line so the game opens it by
    rotating about local X (negative = open, toward the back)."""
    sx, sy, sz = 0.66, 0.44, 0.3
    tray = _tray(sx, sy, sz, 0.035, "wood", "wood_dark")
    tray = L.bevel(tray, 0.008, 1, angle=60)
    parts = [tray]
    # Plank grooves: thin dark strips across front and back.
    for z in (sz * 0.36, sz * 0.7):
        for sgn in (-1, 1):
            parts.append(L.box((sx - 0.02, 0.006, 0.012), (0, sgn * (sy / 2 + 0.001), z), mat="wood_dark"))
    # Steel bands wrapping the body.
    for x in (-0.23, 0.23):
        parts.append(L.box((0.06, sy + 0.02, sz + 0.004), (x, 0, sz / 2 - 0.0), mat="paint_yellow", bev=0.006))
    # Base skid.
    parts.append(L.box((sx + 0.03, sy + 0.03, 0.04), (0, 0, 0.02), mat="metal_dark", bev=0.008))
    # Lock plate (front) and side handles.
    parts.append(L.box((0.1, 0.02, 0.11), (0, -sy / 2 - 0.012, sz - 0.05), mat="brass", bev=0.008))
    parts.append(L.cyl(0.012, 0.02, loc=(0, -sy / 2 - 0.024, sz - 0.06), rot=(90, 0, 0), mat="hazard_dark", n=6))
    for sgn in (-1, 1):
        parts.append(handle_loop(0, sz * 0.62, sgn * (sx / 2 + 0.006), w=0.16, h=0.05, axis="side"))
    # The loot glows inside: a stack of cassettes on a pad of warm light.
    parts.append(L.box((sx - 0.1, sy - 0.1, 0.02), (0, 0, 0.06), mat="warm_glow"))
    for i, (x, rz) in enumerate(((-0.12, 8), (0.02, -6), (0.15, 14))):
        parts.append(L.box((0.13, 0.085, 0.022), (x, 0.0, 0.085 + i * 0.012), rot=(0, 0, rz),
                           mat="graffiti" if i != 1 else "paint_yellow", bev=0.004))
    body = L.finish(L.join(parts, "Body"))

    # Lid: half-barrel with bands and the lock hasp. Hinge along the top back edge.
    lid_parts = []
    lr = sy / 2
    shell = L.cyl(lr, sx, loc=(0, 0, sz), rot=(0, 90, 0), mat="wood", n=20)
    # Cut to a half cylinder: drop the vertices below the hinge plane.
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, sz),
                           plane_no=(0, 0, 1), clear_inner=True)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bm.to_mesh(shell.data)
    bm.free()
    for p in shell.data.polygons:
        p.material_index = 0
    lid_parts.append(shell)
    # Flatten the lid a little so it reads as a chest lid, not a tube.
    shell.data.transform(L.xform((0, 0, sz)) @ L.xform(scale=(1.0, 1.0, 0.62)) @ L.xform((0, 0, -sz)))
    for x in (-0.23, 0.23):
        band = L.cyl(lr + 0.008, 0.062, loc=(x, 0, sz), rot=(0, 90, 0), mat="paint_yellow", n=20)
        bm = bmesh.new()
        bm.from_mesh(band.data)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, sz + 0.001),
                               plane_no=(0, 0, 1), clear_inner=True)
        bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
        bm.to_mesh(band.data)
        bm.free()
        band.data.transform(L.xform((0, 0, sz)) @ L.xform(scale=(1.0, 1.0, 0.62)) @ L.xform((0, 0, -sz)))
        lid_parts.append(band)
    lid_parts.append(L.box((0.08, 0.025, 0.07), (0, -sy / 2 - 0.006, sz + 0.02), mat="brass", bev=0.006))
    lid_parts.append(L.box((sx + 0.01, 0.03, 0.02), (0, sy / 2 - 0.01, sz + 0.01), mat="metal_dark"))
    lid = L.finish(L.join(lid_parts, "Lid"), smooth_angle=40)
    L.set_origin(lid, (0, sy / 2, sz))
    return [body, lid]


def chest_lower():
    """Sealed relic case (R04): angular plated metal, rune-lit seam, hazard corners. "Lid" hinges
    at the top back edge like the upper chest."""
    sx, sy, sz = 0.7, 0.46, 0.3
    tray = _tray(sx, sy, sz, 0.04, "metal", "metal_dark")
    tray = L.bevel(tray, 0.012, 1, angle=60)
    parts = [tray]
    parts.append(L.box((sx + 0.04, sy + 0.04, 0.05), (0, 0, 0.025), mat="metal_dark", bev=0.012))
    for ix in (-1, 1):
        for iy in (-1, 1):
            parts.append(L.box((0.07, 0.07, sz + 0.01), (ix * (sx / 2 - 0.02), iy * (sy / 2 - 0.02), sz / 2),
                               mat="paint_yellow", bev=0.012))
    # Inscription strip on the front: short glowing rune strokes in a recess.
    parts.append(L.box((0.4, 0.012, 0.1), (0, -sy / 2 - 0.002, sz * 0.45), mat="metal_dark"))
    strokes = [(-0.15, 0.0, 0.07, 90), (-0.11, 0.0, 0.05, 30), (-0.05, 0.0, 0.07, 90), (-0.02, 0.0, 0.05, -40),
               (0.04, 0.0, 0.07, 90), (0.08, 0.0, 0.06, 0), (0.13, 0.0, 0.07, 90), (0.16, 0.0, 0.05, 45)]
    for x, _, ln, a in strokes:
        parts.append(L.box((ln, 0.008, 0.012), (x, -sy / 2 - 0.009, sz * 0.45), rot=(0, a, 0), mat="rune_glow"))
    parts.append(L.box((sx - 0.12, sy - 0.12, 0.02), (0, 0, 0.07), mat="rune_glow"))
    parts.append(L.box((0.2, 0.12, 0.06), (0, 0, 0.11), rot=(0, 0, 12), mat="core_glow", bev=0.01))
    body = L.finish(L.join(parts, "Body"))

    lid_parts = [L.box((sx + 0.02, sy + 0.02, 0.1), (0, 0, sz + 0.05), mat="metal", bev=0.03, taper=(0.86, 0.8))]
    lid_parts.append(L.box((sx * 0.5, sy * 0.4, 0.025), (0, 0, sz + 0.105), mat="metal_dark", bev=0.008))
    lid_parts.append(star(0.07, (0, 0, sz + 0.12), rot=(90, 0, 0), mat="paint_yellow", depth=0.012))
    lid_parts.append(L.box((0.1, 0.03, 0.06), (0, -sy / 2 - 0.012, sz + 0.03), mat="paint_yellow", bev=0.008))
    lid_parts.append(L.box((sx + 0.024, sy + 0.024, 0.016), (0, 0, sz + 0.008), mat="neon_glow"))
    lid = L.finish(L.join(lid_parts, "Lid"))
    L.set_origin(lid, (0, sy / 2, sz))
    return [body, lid]
