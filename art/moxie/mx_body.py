"""Moxie's body: torso, neck, arms, hands, lower legs and the head (face topology + UVs).

Parts carry a custom property `wspec` naming how mx_rig weights them (see mx_rig.WEIGHTERS).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import mx_skel as S
from mx_geo import (TAU, V, basis, catmull, frames_along, interp_profile, lerp, loft,
                    mirror_copy, resample, ring_points, set_material, slot_index, smoothstep,
                    subsurf, tube_along, obj_from_bmesh)


def tag(obj, wspec):
    obj["wspec"] = wspec
    return obj


# --------------------------------------------------------------------------------------------
# torso
# --------------------------------------------------------------------------------------------

# (z, half_width, front_depth, back_depth, centre_y, squareness)
TORSO_RINGS = [
    (0.790, 0.128, 0.080, 0.088, 0.012, 2.2),
    (0.845, 0.128, 0.076, 0.086, 0.012, 2.2),
    (0.900, 0.112, 0.068, 0.072, 0.014, 2.2),
    (0.950, 0.098, 0.063, 0.064, 0.016, 2.25),
    (0.995, 0.096, 0.064, 0.063, 0.016, 2.3),
    (1.040, 0.104, 0.068, 0.066, 0.014, 2.3),
    (1.085, 0.114, 0.074, 0.070, 0.012, 2.3),
    (1.130, 0.122, 0.078, 0.071, 0.010, 2.3),
    (1.175, 0.130, 0.074, 0.071, 0.010, 2.4),
    (1.215, 0.140, 0.066, 0.068, 0.013, 2.4),
    (1.243, 0.128, 0.054, 0.060, 0.016, 2.2),
    (1.265, 0.100, 0.046, 0.054, 0.019, 2.0),
    (1.280, 0.066, 0.040, 0.046, 0.021, 2.0),
    (1.292, 0.046, 0.036, 0.040, 0.022, 2.0),
]
TORSO_N = 24


def bust_offset(x, z):
    """Forward push of the bust (two soft lobes) - kept modest; the crop top carries the shape."""
    zf = math.exp(-((z - 1.128) / 0.034) ** 2)
    lobes = math.exp(-((abs(x) - 0.052) / 0.036) ** 2)
    return 0.020 * zf * lobes


def torso_point(z, a, inflate=0.0, ring=None):
    """Surface point of the torso at height z and angle a (a=-pi/2 is straight forward, -Y).

    `inflate` pushes outward along the cross-section (used by clothes hugging the body).
    """
    if ring is None:
        ring = torso_section(z)
    hw, fd, bd, cy, sq = ring
    c, s = math.cos(a), math.sin(a)
    # superellipse: |x|^sq + |y|^sq = 1
    k = 2.0 / sq
    ex = math.copysign(abs(c) ** k, c)
    ey = math.copysign(abs(s) ** k, s)
    x = (hw + inflate) * ex
    y = cy + ((fd if s < 0 else bd) + inflate) * ey
    if s < 0:
        y -= bust_offset(x, z) * (-ey)
    return V(x, y, z)


def torso_section(z):
    prof = [(r[0], r[1:]) for r in TORSO_RINGS]
    return interp_profile(prof, z)


def make_torso():
    rings = []
    for r in TORSO_RINGS:
        z = r[0]
        rings.append([torso_point(z, TAU * k / TORSO_N - math.pi / 2, ring=r[1:]) for k in range(TORSO_N)])
    obj = loft("torso", rings, 'skin', closed=True, cap_start=True)
    # skin that is always covered (under the crop top, inside the pants) is not built
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    hidden = [f for f in bm.faces if f.calc_center_median().z < 0.84]
    bmesh.ops.delete(bm, geom=hidden, context='FACES')
    bm.to_mesh(obj.data)
    bm.free()
    return tag(obj, "torso")


def make_neck():
    rings = []
    for z, rx, ry, cy in ((1.235, 0.040, 0.040, 0.022), (1.285, 0.036, 0.037, 0.022),
                          (1.33, 0.034, 0.036, 0.016), (1.375, 0.034, 0.036, 0.010),
                          (1.405, 0.034, 0.036, 0.010)):
        rings.append(ring_points(V(0, cy, z), V(1, 0, 0), V(0, 1, 0), rx, ry, 14))
    obj = loft("neck", rings, 'skin', closed=True)
    return tag(obj, "neck")


# --------------------------------------------------------------------------------------------
# arms and hands
# --------------------------------------------------------------------------------------------

# (distance along the arm chain from the shoulder joint, radius_front, radius_side)
ARM_PROFILE = [
    (-0.050, 0.039, 0.039),
    (-0.020, 0.044, 0.045),
    (0.000, 0.046, 0.048),
    (0.020, 0.045, 0.047),
    (0.045, 0.041, 0.042),
    (0.075, 0.036, 0.037),
    (0.140, 0.031, 0.031),
    (0.205, 0.029, 0.028),
    (0.235, 0.0275, 0.0265),
    (0.258, 0.027, 0.026),
    (0.280, 0.0285, 0.026),
    (0.300, 0.030, 0.027),
    (0.350, 0.029, 0.025),
    (0.420, 0.025, 0.021),
    (0.475, 0.021, 0.018),
    (0.494, 0.020, 0.017),
]


def arm_point_at(d):
    """Point on the (left) arm axis at chain distance d from the shoulder joint."""
    if d <= S.UPPER_ARM_LEN:
        return S.SHOULDER_JOINT + S.ARM_DIR * d
    return S.ELBOW + S.FOREARM_DIR * min(d - S.UPPER_ARM_LEN, S.FOREARM_LEN + 0.02)


def make_arm():
    path = [arm_point_at(d) for d, _, _ in ARM_PROFILE]
    # the root rings sit inside the torso, tucked down so the deltoid does not poke above it
    path[0] = S.SHOULDER_JOINT + V(-0.050, 0.0, -0.022)
    path[1] = S.SHOULDER_JOINT + V(-0.020, 0.0, -0.010)
    fr = frames_along(path, V(0, -1, 0))
    rings = []
    for p, (t, nrm, b), (d, rf, rs) in zip(path, fr, ARM_PROFILE):
        rings.append(ring_points(p, nrm, b, rf, rs, 14))
    obj = loft("arm.L", rings, 'skin', closed=True, cap_start=True, cap_end=True)
    return tag(obj, "arm.L")


def hand_frame():
    """Left hand local frame: Y along the hand, Z toward the thumb (forward), X dorsal."""
    y = S.HAND_DIR
    z = V(0, -1, 0)
    z = (z - y * z.dot(y)).normalized()
    x = z.cross(y).normalized()  # dorsal (back of the hand)
    return basis(x, y, z, S.WRIST)


def _finger(name, base, length, radius, curl, frame):
    """A finger as a tapered tube curling toward the palm (-X local)."""
    pts = []
    ang = 0.0
    p = Vector(base)
    seg = length / 3
    pts.append(p.copy())
    for i in range(3):
        ang += curl / 3
        p = p + V(-math.sin(ang), math.cos(ang), 0) * seg
        pts.append(p.copy())
    path = resample(catmull(pts, 4), 7)
    world = [frame @ q for q in path]
    up = (frame.to_3x3() @ V(1, 0, 0)).normalized()

    def rad(t):
        return radius * (1.0 - 0.25 * t) if t < 0.92 else radius * 0.55
    return tube_along(name, world, rad, n=5, up=up, ry_fn=lambda t: rad(t) * 0.86)


def make_hand():
    """Left hand with fingerless glove (glove over palm + proximal phalanges, bare fingertips)."""
    fr = hand_frame()
    rings = []
    # palm loft along local Y: (y, half_width (Z), half_thickness (X), x_offset)
    prof = [(-0.018, 0.024, 0.020, 0.000), (0.012, 0.029, 0.016, 0.000),
            (0.060, 0.036, 0.0135, 0.002), (0.092, 0.033, 0.010, 0.000)]
    for y, hw, ht, xo in prof:
        ring = []
        for k in range(8):
            a = TAU * k / 8 + math.pi / 8
            c, s = math.cos(a), math.sin(a)
            # rounded rectangle cross-section (superellipse)
            ex = math.copysign(abs(c) ** 0.7, c)
            ez = math.copysign(abs(s) ** 0.7, s)
            ring.append(fr @ V(xo + ht * ex, y, hw * ez))
        rings.append(ring)
    palm = loft("hand_palm", rings, 'glove', closed=True, cap_start=True, cap_end=True)
    subsurf(palm, 1)
    parts = [palm]
    for i, (z, length, radius) in enumerate(((0.024, 0.066, 0.0090), (0.008, 0.072, 0.0094),
                                            (-0.008, 0.068, 0.0090), (-0.024, 0.056, 0.0080))):
        f = _finger("finger%d" % i, V(0.001, 0.080, z), length, radius, math.radians(28), fr)
        parts.append(f)
    # thumb: from the palm's thumb edge out and forward
    tpts = [V(-0.004, 0.010, 0.026), V(-0.010, 0.032, 0.045), V(-0.014, 0.055, 0.052),
            V(-0.018, 0.072, 0.050)]
    tpath = [fr @ q for q in resample(catmull(tpts, 4), 7)]
    thumb = tube_along("thumb", tpath, lambda t: 0.0115 * (1 - 0.3 * t) if t < 0.92 else 0.006, n=6,
                       up=(fr.to_3x3() @ V(1, 0, 0)))
    parts.append(thumb)
    # fingerless glove: bare skin past the first knuckle
    knuckle_y = 0.080
    inv = fr.inverted()
    for f in parts[1:]:
        f.data.materials.clear()
        f.data.materials.append(bpy.data.materials['glove'])
        skin = slot_index(f, 'skin')
        for poly in f.data.polygons:
            loc = inv @ poly.center
            if f.name.startswith("thumb"):
                bare = loc.y > 0.048
            else:
                bare = loc.y > knuckle_y + 0.030
            if bare:
                poly.material_index = skin
    for p in parts:
        tag(p, "hand.L")
    return parts


def make_lower_leg():
    """Shin/ankle skin (visible through the torn knee and between cuff and boot)."""
    pts = []
    for t in (0.0, 0.25, 0.5, 0.75, 1.0):
        pts.append(S.KNEE.lerp(S.ANKLE, t) if t < 1 else S.ANKLE + V(0, 0, 0.02))
    radii = [0.044, 0.046, 0.038, 0.030, 0.027]
    fr = frames_along(pts, V(0, -1, 0))
    rings = [ring_points(p, n_, b, r, r * 0.95, 10) for p, (t, n_, b), r in zip(pts, fr, radii)]
    obj = loft("shin_skin.L", rings, 'skin', closed=True, cap_start=True, cap_end=True)
    return tag(obj, "leg.L")


# --------------------------------------------------------------------------------------------
# head
# --------------------------------------------------------------------------------------------

HEAD_RX, HEAD_RY, HEAD_RZ = 0.096, 0.099, 0.120
FACE_UV_SCALE = 0.235   # metres covered by the face texture (square), centred on FACE_UV_CENTRE
FACE_UV_CENTRE = (0.0, 1.452)


def head_shape(p):
    """Map a unit-sphere point to the anime head surface (relative to SKULL_C)."""
    x, y, z = p.x, p.y, p.z
    X, Y, Z = x * HEAD_RX, y * HEAD_RY, z * HEAD_RZ
    front = smoothstep(0.15, -0.75, y)       # 1 on the face side
    back = smoothstep(-0.1, 0.6, y)
    # fuller cranium at the back/top
    if z > -0.2:
        Y += 0.006 * back * smoothstep(-0.2, 0.4, z)
        X *= 1.0 + 0.04 * smoothstep(-0.2, 0.5, z)
    # jaw: narrow toward the chin and push the chin forward/down into a soft point
    low = smoothstep(-0.05, -1.0, z)
    X *= 1.0 - 0.50 * (low ** 1.25) * (0.55 + 0.45 * front)
    Y -= 0.012 * low * front
    Z -= 0.004 * low * front
    # the lower back of the skull tucks up into the nape (anime head sits forward on the neck)
    Z += 0.022 * low * back
    Y -= 0.018 * low * back
    # flatten the face plane a little (cheeks forward, eye area flat) for crisp texture reading
    if y < 0:
        Y = Y * (1.0 - 0.10 * front * smoothstep(-0.8, -0.2, z) * smoothstep(0.7, 0.1, z))
    # small nose: soft wedge on the centre line just below the eye line
    nz = (Z + 0.020) / 0.020
    nx = X / 0.010
    if Y < 0:
        Y -= 0.0065 * math.exp(-nx * nx - nz * nz) * front
    # cheekbones
    cz = (Z + 0.012) / 0.03
    Y -= 0.004 * front * math.exp(-cz * cz) * smoothstep(0.02, 0.06, abs(X))
    return V(X, Y, Z)


def make_head():
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=10, use_grid_fill=True)
    for v in bm.verts:
        v.co = head_shape(v.co.normalized()) + S.SKULL_C
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = obj_from_bmesh("head", bm, 'skin')
    face_idx = slot_index(obj, 'face_paint')
    me = obj.data
    uv = me.uv_layers.new(name="UVMap")
    cx, cz = FACE_UV_CENTRE
    for poly in me.polygons:
        c = poly.center
        n = poly.normal
        if n.y < -0.25 and c.z > 1.33 and c.z < 1.56 and abs(c.x) < 0.085:
            poly.material_index = face_idx
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (0.5 + (co.x - cx) / FACE_UV_SCALE, 0.5 + (co.z - cz) / FACE_UV_SCALE)
    return tag(obj, "head")


def cull_under_cap(head, hairline, margin=18.0):
    """Delete scalp faces that lie well inside the hair cap (never visible; saves triangles).
    hairline(az) -> elevation (deg) of the cap edge."""
    bm = bmesh.new()
    bm.from_mesh(head.data)
    kill = []
    for f in bm.faces:
        inside = True
        for v in f.verts:
            d = (v.co - S.SKULL_C).normalized()
            el = math.degrees(math.asin(max(-1.0, min(1.0, d.z))))
            az = math.degrees(math.atan2(d.x, -d.y))
            if el < hairline(az) + margin:
                inside = False
                break
        if inside:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(head.data)
    bm.free()


def build_body():
    parts = [make_torso(), make_neck(), make_head()]
    arm = make_arm()
    parts += [arm, mirror_copy(arm, "arm.R")]
    hand = make_hand()
    parts += hand + [mirror_copy(h, h.name + ".R") for h in hand]
    for p in parts:
        spec = p.get("wspec", "")
        if p.name.endswith(".R") and spec.endswith(".L"):
            p["wspec"] = spec[:-2] + ".R"
    return parts
