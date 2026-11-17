"""Stage 4: hair. Messy dark-brown hair in two high scrappy pigtails with loose strands, built from
swept strand clumps: a scalp cap, flow clumps from the hairline to each tie, messy bangs, side locks,
nape wisps, two pigtail plumes, flyaways and the hair ties.

Authoring scheme: a point on the skull is addressed by a direction from the skull centre,
(azimuth, elevation) in degrees - azimuth 0 = front, 90 = her left, 180 = back; elevation 90 = top.
S(az, el, lift) ray-casts that direction onto the scalp and lifts it off the surface."""
import bpy, bmesh, sys, os, json, math, random
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
import mb_toon as T
import mb_hair as H
from mathutils import Vector
from mathutils.bvhtree import BVHTree

U.open_stage("s03_face")
body = bpy.data.objects["Body"]
L = json.loads(body["landmarks"])
rnd = random.Random(7)

# ---------------------------------------------------------------- skull addressing
bmb = bmesh.new()
bmb.from_mesh(body.data)
bvh = BVHTree.FromBMesh(bmb)
zt = L["z_top"]
R0 = 0.100
HC = Vector((0, -0.012, zt - R0 - 0.004))


def D(az, el):
    a, e = math.radians(az), math.radians(el)
    return Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))


def S(az, el, lift=0.0):
    d = D(az, el)
    hit = bvh.ray_cast(HC, d, 0.5)
    p = hit[0] if hit[0] is not None else HC + d * R0
    return p + d * lift


hair_bm = bmesh.new()
uv = hair_bm.loops.layers.uv.new("UVMap")

# ---------------------------------------------------------------- scalp cap
def hairline_el(az):
    """Elevation of the hairline for an azimuth (degrees)."""
    a = abs(((az + 180) % 360) - 180)
    if a < 55:
        return 33 - 4 * (a / 55) ** 2
    if a < 100:
        return 29 - 31 * ((a - 55) / 45)          # temples down to above the ear
    return -2 - 38 * ((a - 100) / 80) ** 0.9       # round the back to the nape


AZN, ELN = 48, 12
cap = []
for i in range(AZN):
    az = -180 + 360 * i / AZN
    row = []
    e0 = hairline_el(az) - 3
    for j in range(ELN):
        el = e0 + (90 - e0) * j / ELN
        row.append(hair_bm.verts.new(S(az, el, 0.006)))
    cap.append(row)
topv = hair_bm.verts.new(S(0, 90, 0.006))
for i in range(AZN):
    i2 = (i + 1) % AZN
    for j in range(ELN - 1):
        f = hair_bm.faces.new((cap[i][j], cap[i2][j], cap[i2][j + 1], cap[i][j + 1]))
        f.smooth = True
    f = hair_bm.faces.new((cap[i][ELN - 1], cap[i2][ELN - 1], topv))
    f.smooth = True
for f in hair_bm.faces:
    for lp in f.loops:
        lp[uv].uv = (0.5, 0.12)

# ---------------------------------------------------------------- helpers
def path_on_skull(keys, n=None):
    """keys: list of (az, el, lift). Returns (points, normals)."""
    pts = [S(a, e, l) for a, e, l in keys]
    nrm = [D(a, e) for a, e, l in keys]
    return pts, nrm


def clump(keys, width, thick, **kw):
    pts, nrm = path_on_skull(keys)
    H.add_clump(hair_bm, uv, pts, nrm, width, thick, **kw)


TIE_AZ, TIE_EL = 112, 50
tie_pos = {}

for sgn in (1, -1):
    # ---- flow clumps: hairline -> tie, lying on the scalp
    taz = sgn * TIE_AZ
    for k in range(15):
        az0 = sgn * (34 + (180 - 34) * k / 14) + rnd.uniform(-3, 3)
        el0 = hairline_el(az0) - 2 + rnd.uniform(-2, 2)
        keys = []
        for q in (0.0, 0.3, 0.62, 0.9, 1.06):
            az = az0 + (taz - az0) * q
            el = el0 + (TIE_EL - el0) * q
            lift = 0.007 + 0.011 * math.sin(math.pi * min(q, 1.0)) + (0.012 if q > 1 else 0)
            keys.append((az, el, lift))
        clump(keys, rnd.uniform(0.048, 0.062), 0.011, segs=8, root=0.75, power=3.2, belly=0.2, vshift=0.0)
    # ---- top clumps: from the parting / crown to the tie
    for k in range(7):
        az0 = sgn * (4 + 26 * (k % 3)) + rnd.uniform(-3, 3)
        el0 = 62 + 9 * (k // 3) + rnd.uniform(-3, 3)
        if k == 6:
            az0, el0 = sgn * 150, 74
        keys = []
        for q in (0.0, 0.35, 0.7, 1.05):
            az = az0 + (taz - az0) * q
            el = el0 + (TIE_EL - el0) * q + 10 * math.sin(math.pi * q) * (1 if abs(az0) < 100 else 0.3)
            keys.append((az, min(el, 88), 0.009 + 0.012 * math.sin(math.pi * min(q, 1))))
        clump(keys, rnd.uniform(0.05, 0.062), 0.012, segs=8, root=0.8, power=3.2, belly=0.2)
    # ---- nape wisps
    for k in range(4):
        az0 = sgn * (125 + 14 * k)
        e0 = hairline_el(az0)
        keys = [(az0, e0 + 22, 0.008), (az0 + sgn * 2, e0 + 6, 0.012), (az0 + sgn * 5, e0 - 9, 0.012), (az0 + sgn * 9, e0 - 20, 0.02)]
        clump(keys, 0.034, 0.009, segs=6, root=0.8, power=2.0)
    # ---- side lock in front of the ear, down to the jaw
    for k, (a0, ln, w) in enumerate(((62, 44, 0.040), (74, 52, 0.042), (50, 30, 0.034))):
        az0 = sgn * a0
        e0 = hairline_el(az0) + 12
        keys = [(az0, e0, 0.008), (az0 - sgn * 3, e0 - ln * 0.35, 0.016), (az0 - sgn * 7, e0 - ln * 0.72, 0.017),
                (az0 - sgn * (16 if k != 1 else 4), e0 - ln, 0.022)]
        clump(keys, w, 0.010, segs=8, root=0.7, power=1.8)

# ---------------------------------------------------------------- bangs (messy, asymmetric)
BANGS = [  # (root az, root el, tip az, tip el, width, tip lift, sideways sweep)
    (-4, 74, -2, -22, 0.056, 0.022, 5),      # centre lock down between the eyes
    (14, 72, 26, -6, 0.060, 0.022, 9),
    (-24, 72, -36, -4, 0.062, 0.024, -11),
    (34, 70, 52, -12, 0.058, 0.024, 10),
    (-44, 68, -60, -14, 0.058, 0.024, -9),
    (54, 64, 70, -20, 0.050, 0.024, 4),
    (-62, 62, -76, -22, 0.050, 0.024, -4),
    (6, 80, 12, 12, 0.050, 0.034, -14),      # shorter upper layer
    (-14, 80, -16, 10, 0.050, 0.034, 13),
    (28, 78, 40, 8, 0.050, 0.034, 12),
    (-36, 78, -48, 10, 0.050, 0.036, -13),
]
for (a0, e0, a1, e1, w, tl, sw) in BANGS:
    keys = []
    for q in (0.0, 0.34, 0.7, 1.0):
        az = a0 + (a1 - a0) * q + sw * (q ** 2.5)
        el = e0 + (e1 - e0) * q
        lift = 0.010 + (tl - 0.004) * math.sin(math.pi * 0.5 * q) ** 1.5 + 0.004 * math.sin(math.pi * q)
        keys.append((az, el, lift))
    clump(keys, w, 0.011, segs=9, root=0.6, power=1.7, belly=0.3)

# ---------------------------------------------------------------- pigtail plumes
def free_clump(p0, d0, length, gravity, width, thick, curl=0.0, curl_start=0.6, side=Vector((1, 0, 0)), wave=0.0, segs=10, nrm=None, power=1.8, root=0.45):
    """A free-hanging lock: integrates a direction that bends under gravity, then flicks (curls) near the tip."""
    pts = [p0.copy()]
    d = d0.normalized()
    p = p0.copy()
    steps = 14
    for i in range(steps):
        t = (i + 0.5) / steps
        d = (d + Vector((0, 0, -1)) * (gravity / steps) * (0.4 + 1.2 * t)).normalized()
        if t > curl_start and curl:
            ax = d.cross(Vector((0, 0, 1)))
            if ax.length < 1e-4:
                ax = side.cross(d)
            ax.normalize()
            from mathutils import Matrix
            d = (Matrix.Rotation(curl / (steps * (1 - curl_start)), 3, ax) @ d).normalized()
        if wave:
            d = (d + side * (wave * math.cos(t * math.pi * 2.2) / steps * 3)).normalized()
        p = p + d * (length / steps)
        if i % 2 == 1:
            pts.append(p.copy())
    n = nrm or (d0.cross(Vector((0, 0, 1))).cross(d0)).normalized()
    H.add_clump(hair_bm, uv, pts, n, width, thick, segs=segs, root=root, power=power, belly=0.3)


for sgn in (1, -1):
    d_tie = D(sgn * TIE_AZ, TIE_EL)
    tie = S(sgn * TIE_AZ, TIE_EL, 0.016)
    tie_pos[sgn] = (tie, d_tie)
    axis = (d_tie + Vector((sgn * 0.95, 0.25, 0.05))).normalized()
    side = Vector((sgn, 0, 0))
    ex = axis.orthogonal().normalized()
    ey = axis.cross(ex).normalized()
    n_cl = 19
    for k in range(n_cl):
        # golden-angle spread inside a cone around the plume axis
        r = math.sqrt((k + 0.5) / n_cl)
        th = k * 2.39996 + rnd.uniform(-0.2, 0.2)
        cone = math.radians(68) * r
        d0 = (axis * math.cos(cone) + (ex * math.cos(th) + ey * math.sin(th)) * math.sin(cone)).normalized()
        length = rnd.uniform(0.16, 0.235) * (1.0 + 0.2 * (1 - r))
        outward = (d0 - axis * d0.dot(axis))
        nrm = outward.normalized() if outward.length > 1e-4 else ex
        free_clump(tie + d0 * 0.004, d0, length * (1.0 + 0.45 * max(-d0.z, 0)), rnd.uniform(2.3, 3.4) * (0.6 + 0.4 * max(d0.z, 0) + 0.4), rnd.uniform(0.060, 0.082), 0.021,
                   curl=rnd.uniform(0.5, 1.3), curl_start=rnd.uniform(0.68, 0.8), side=side,
                   wave=rnd.uniform(-0.25, 0.25), nrm=nrm, segs=11, power=1.6)
    # a few thin stray strands
    for k in range(6):
        th = rnd.uniform(0, 6.28)
        cone = rnd.uniform(0.5, 1.2)
        d0 = (axis * math.cos(cone) + (ex * math.cos(th) + ey * math.sin(th)) * math.sin(cone)).normalized()
        free_clump(tie, d0, rnd.uniform(0.2, 0.27), rnd.uniform(2.0, 3.2), 0.016, 0.007, curl=rnd.uniform(1.0, 2.2), curl_start=0.7, side=side, segs=9)

# flyaways on the crown
for k, (az, el, tilt) in enumerate(((10, 80, 0.5), (-25, 76, -0.6), (40, 70, 0.8), (-60, 68, -0.5), (150, 78, 0.3))):
    p0 = S(az, el, 0.004)
    d0 = (D(az, el) + Vector((tilt, -0.2, 0.2))).normalized()
    free_clump(p0, d0, 0.08, 1.2, 0.013, 0.006, curl=1.2, side=Vector((math.copysign(1, tilt), 0, 0)), segs=7)

bmesh.ops.recalc_face_normals(hair_bm, faces=hair_bm.faces[:])
me = bpy.data.meshes.new("Hair")
hair_bm.to_mesh(me)
hair = U.new_obj("Hair", me)

# ---------------------------------------------------------------- strand gradient texture
os.makedirs(os.path.join(U.HERE, "tex"), exist_ok=True)
W_, H_ = 256, 512
rs = np.random.RandomState(3)
root = np.array(U.srgb("#4a2c20"))
tip = np.array(U.srgb("#8a5636"))
v = np.linspace(0, 1, H_)[:, None]
u = np.linspace(0, 1, W_)[None, :]
g = np.clip((v - 0.15) / 0.85, 0, 1) ** 1.3
streak = np.zeros((1, W_))
for _ in range(26):
    c = rs.uniform(0, 1)
    wdt = rs.uniform(0.004, 0.012)
    streak += rs.uniform(-0.5, 1.0) * np.exp(-((u - c) / wdt) ** 2)
streak = np.clip(streak, -1, 1) * 0.035
fac = np.clip(g + streak * (0.3 + g), 0, 1)
px = root[None, None, :] * (1 - fac[..., None]) + tip[None, None, :] * fac[..., None]
rgba = np.concatenate([px, np.ones((H_, W_, 1))], axis=2).astype(np.float32)
himg = bpy.data.images.new("moxie_hair", W_, H_)
himg.pixels = rgba.ravel()
himg.filepath_raw = os.path.join(U.HERE, "tex", "moxie_hair.png")
himg.file_format = 'PNG'
himg.save()
hm = bpy.data.materials.new("hair")
hm.use_nodes = True
tn = hm.node_tree.nodes.new("ShaderNodeTexImage")
tn.image = himg
hm.node_tree.links.new(tn.outputs["Color"], hm.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
hm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
me.materials.append(hm)

# ---------------------------------------------------------------- hair ties
ties = bmesh.new()
for sgn in (1, -1):
    tie, d_tie = tie_pos[sgn]
    axis = (d_tie + Vector((sgn * 0.75, 0.15, 0.25))).normalized()
    mtx = axis.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    mtx.translation = tie + axis * 0.012
    for off, rad in ((0.0, 0.026), (0.010, 0.023)):
        m2 = mtx.copy()
        m2.translation = tie + axis * (0.010 + off)
        ret = bmesh.ops.create_circle(ties, segments=1, radius=1)  # placeholder to keep API parity
        bmesh.ops.delete(ties, geom=ret["verts"], context='VERTS')
        # torus by hand
        seg, sub = 14, 6
        rings = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            ring = []
            for j in range(sub):
                b = 2 * math.pi * j / sub
                r = rad + 0.0065 * math.cos(b)
                ring.append(ties.verts.new(m2 @ Vector((r * math.cos(a), r * math.sin(a), 0.0065 * math.sin(b)))))
            rings.append(ring)
        for i in range(seg):
            for j in range(sub):
                f = ties.faces.new((rings[i][j], rings[(i + 1) % seg][j], rings[(i + 1) % seg][(j + 1) % sub], rings[i][(j + 1) % sub]))
                f.smooth = True
bmesh.ops.recalc_face_normals(ties, faces=ties.faces[:])
tme = bpy.data.meshes.new("HairTies")
ties.to_mesh(tme)
tobj = U.new_obj("HairTies", tme)
tme.materials.append(U.mat("tie_red", "#c8323c"))
hair["tie_l"] = list(tie_pos[1][0])
hair["tie_r"] = list(tie_pos[-1][0])
hair["tie_axis_l"] = list((tie_pos[1][1] + Vector((0.75, 0.15, 0.25))).normalized())
print("hair tris", sum(len(p.vertices) - 2 for p in me.polygons))
U.save_stage("s04_hair")

bpy.data.objects["MH_Rig"].hide_render = True
T.toonify([body, hair, tobj], outline=0.0022)
zc = L["z_chin"] + L["H"] * 0.55
U.render_views(os.path.join(U.WIP, "s04_head.png"), views=("front", "q", "side", "back", (20, 25)), center=(0, 0, zc),
               scale=0.62, res=(560, 560), setup=T.setup_eevee)
