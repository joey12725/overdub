"""Stage 5: garments fitted over the body.

  Top     - crop tank derived from the body's own torso faces (inherits its skin weights), dark piping
  Strap   - diagonal chest strap with buckle, ray-fitted round the torso
  Pants   - loose low-rise cargo pants: the body's hip/leg topology pushed out to a baggy silhouette,
            subdivided, with fold stacks at ankle/knee, a dropped crotch, torn knee/shin, rolled cuffs,
            waistband, cargo pockets; UVs for the painted olive/zig-zag texture
  Jacket  - oversized bomber worn off the shoulders: bunched sleeves from the arm topology, a body
            panel with yellow lining and turned-out lapels, a fat collar roll round the upper arms
  Gloves  - fingerless gloves as a material region of the hands (cannot poke through)
Finally the skin that the garments hide is deleted.
"""
import bpy, bmesh, sys, os, json, math, random
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
import mb_toon as T
import mb_geo as G
from mathutils import Vector
from mathutils.bvhtree import BVHTree

U.open_stage("s04_hair")
body = bpy.data.objects["Body"]
rig = bpy.data.objects["MH_Rig"]
bme = body.data
L = json.loads(body["landmarks"])
rnd = random.Random(11)


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def J(name, tail=False):
    b = rig.data.bones[name]
    return Vector(b.tail_local if tail else b.head_local)


def weights(obj, names):
    idx = {obj.vertex_groups[n].index for n in names if n in obj.vertex_groups}
    w = np.zeros(len(obj.data.vertices))
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group in idx:
                w[v.index] += g.weight
    return w


def coords(obj):
    a = np.zeros(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def set_coords(obj, co):
    obj.data.vertices.foreach_set("co", np.asarray(co, dtype=np.float64).ravel())
    obj.data.update()


def normals(obj):
    a = np.zeros(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("normal", a)
    return a.reshape(-1, 3)


def derive(name, mask, subdiv=0):
    """New object from the body faces whose vertices are all in `mask`; keeps the skin weights."""
    bm = bmesh.new()
    bm.from_mesh(bme)
    bm.verts.ensure_lookup_table()
    kill = [f for f in bm.faces if not all(mask[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = U.new_obj(name, me)
    for g in body.vertex_groups:
        o.vertex_groups.new(name=g.name)
    for a in ("eye_ring", "eye_side", "eye_partner"):
        if a in me.attributes:
            me.attributes.remove(me.attributes[a])
    if subdiv:
        m = o.modifiers.new("sub", 'SUBSURF')
        m.levels = subdiv
        U.apply_modifiers(o)
    return o


def boundary_loops(bm):
    seen = set()
    loops = []
    for e in bm.edges:
        if not e.is_boundary or e in seen:
            continue
        loop = [e.verts[0]]
        used = {e.verts[0]}
        seen.add(e)
        cur = e.verts[1]
        prev_e = e
        while cur is not loop[0] and cur not in used:
            loop.append(cur)
            used.add(cur)
            nxt = [x for x in cur.link_edges if x.is_boundary and x is not prev_e and x not in seen]
            if not nxt:
                break
            prev_e = nxt[0]
            seen.add(prev_e)
            cur = prev_e.other_vert(cur)
        loops.append(loop)
    return loops


def relax_loops(obj, iters=6):
    """Smooth the garment's boundary loops (removes the stair-stepping of a face-selected edge)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    loops = boundary_loops(bm)
    for loop in loops:
        n = len(loop)
        for _ in range(iters):
            new = [(loop[(i - 1) % n].co + loop[i].co * 2 + loop[(i + 1) % n].co) / 4 for i in range(n)]
            for v, p in zip(loop, new):
                v.co = p
    out = [[v.co.copy() for v in loop] for loop in loops]
    bm.to_mesh(obj.data)
    bm.free()
    return out


def piping(name, loops, radius, mat_name, color, flat=1.0, sides=6):
    b = G.Builder(name)
    mi = b.mat(mat_name, color)
    for loop in loops:
        if len(loop) >= 6:
            b.tube(loop, radius, mi, sides=sides, closed=True, flat=flat)
    return b.finish()


def poly_project(p, pts):
    """Closest point on polyline pts to p -> (arc fraction, point, segment index)."""
    best = None
    total = sum((pts[i + 1] - pts[i]).length for i in range(len(pts) - 1))
    acc = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        q = a + ab * t
        d = (p - q).length
        if best is None or d < best[0]:
            best = (d, (acc + ab.length * t) / total, q, i)
        acc += ab.length
    return best[1], best[2], best[3]


def interp(table, x):
    xs = [t[0] for t in table]
    ys = [t[1] for t in table]
    return float(np.interp(x, xs, ys))


_keep = []


def bvh_of(o):
    bm_ = bmesh.new()
    bm_.from_mesh(o.data)
    _keep.append(bm_)
    return BVHTree.FromBMesh(bm_)


co_b = coords(body)
n_b = normals(body)
W = lambda *names: weights(body, names)
w_arm = {s: W("upperarm01." + s, "upperarm02." + s, "lowerarm01." + s, "lowerarm02." + s) for s in "LR"}
w_sh = {s: W("shoulder01." + s, "clavicle." + s) for s in "LR"}
w_hand = {s: weights(body, [g.name for g in body.vertex_groups if g.name.endswith("." + s) and g.name.startswith(("wrist", "finger", "metacarpal"))]) for s in "LR"}
w_leg = W(*[g.name for g in body.vertex_groups if g.name.startswith(("upperleg", "lowerleg"))])
w_foot = W(*[g.name for g in body.vertex_groups if g.name.startswith(("foot", "toe"))])
w_head = W(*([b.name for b in rig.data.bones["head"].children_recursive] + ["head", "neck01", "neck02", "neck03"]))
arm_any = w_arm["L"] + w_arm["R"] + w_hand["L"] + w_hand["R"]
x, y, z = co_b[:, 0], co_b[:, 1], co_b[:, 2]
Y_MID = -0.03

mats = {}
objs = {}

# =================================================================== TOP
front = y < Y_MID
ax = np.abs(x)
body_bvh = bvh_of(body)


def torso_cast(az, zz, y0=-0.028, rmax=0.125):
    """Radius of the torso wall at azimuth az (0 = front, +90deg = her left), cast from the spine outwards."""
    d = Vector((math.sin(az), -math.cos(az), 0))
    o = Vector((0, y0, zz))
    h = body_bvh.ray_cast(o, d, 0.4)
    r = (h[0] - o).length if h[0] is not None else rmax
    return min(r, rmax), d, o


Z_HEM = 1.085
tb = G.Builder("Top")
t_main = tb.mat("top_main", "#efe7d6")
t_trim = tb.mat("top_trim", "#2b2530")
NA_, NZ_ = 56, 8
rad = np.zeros((NA_, NZ_ + 1))
zz_ = np.zeros((NA_, NZ_ + 1))
for a in range(NA_):
    az = 2 * math.pi * a / NA_
    side_ = abs(math.sin(az)) ** 2.2
    z_top = 1.198 - 0.068 * side_ + (0.004 if math.cos(az) < 0 else -0.010 * math.exp(-(math.sin(az) / 0.25) ** 2))
    for k in range(NZ_ + 1):
        zz = Z_HEM + (z_top - Z_HEM) * k / NZ_
        rad[a, k] = torso_cast(az, zz)[0]
        zz_[a, k] = zz
# bridge the bust: the cloth spans hollows instead of following them
for _ in range(6):
    avg = (np.roll(rad, 1, 0) + np.roll(rad, -1, 0)) / 2
    rad = np.maximum(rad, avg)
    avg2 = rad.copy()
    avg2[:, 1:-1] = (rad[:, :-2] + rad[:, 2:]) / 2
    rad = np.maximum(rad, avg2 * 0.995)
tv = []
for a in range(NA_):
    az = 2 * math.pi * a / NA_
    d = Vector((math.sin(az), -math.cos(az), 0))
    tv.append([tb.bm.verts.new(Vector((0, -0.028, zz_[a, k])) + d * (rad[a, k] + 0.0055 + 0.0015 * math.sin(9 * az + 3 * k))) for k in range(NZ_ + 1)])
for a in range(NA_):
    a2 = (a + 1) % NA_
    for k in range(NZ_):
        tb._tag([tb.bm.faces.new((tv[a][k], tv[a2][k], tv[a2][k + 1], tv[a][k + 1]))], t_main)
tb.tube([tv[a][0].co + Vector((0, 0, 0.004)) for a in range(NA_)], 0.0050, t_trim, sides=5, closed=True, flat=1.6, up=Vector((0, 0, 1)))
tb.tube([tv[a][NZ_].co.copy() for a in range(NA_)], 0.0045, t_trim, sides=5, closed=True)
# shoulder straps: fitted over the shoulder from the front edge to the back edge
for sgn in (1, -1):
    pts_, nr_ = [], []
    for q in range(15):
        ang = math.radians(-4 + 188 * q / 14)
        xx = sgn * (0.066 - 0.012 * math.sin(math.radians(188 * q / 14)))
        o = Vector((xx, -0.022, 1.165))
        d = Vector((0, -math.cos(ang), math.sin(ang)))
        h = body_bvh.ray_cast(o, d, 0.3)
        if h[0] is None:
            continue
        pts_.append(h[0] + d * 0.0045)
        nr_.append(d)
    tb.ribbon(pts_, nr_, 0.021, 0.003, t_main)
    for e in (-1, 1):
        tb.tube([p + (nr_[i].cross(pts_[min(i + 1, len(pts_) - 1)] - pts_[max(i - 1, 0)]).normalized()) * (e * 0.0105) + nr_[i] * 0.0015 for i, p in enumerate(pts_)],
                0.0032, t_trim, sides=4, caps=True)
top = tb.finish()
objs["Top"] = top
top_bvh = bvh_of(top)

# chest graphic: a dark split-triangle emblem laid on the top
gb = G.Builder("TopGraphic")
gmi = gb.mat("top_graphic", "#3a3138")


def on_top(px_, pz_):
    h = top_bvh.ray_cast(Vector((px_, -0.5, pz_)), Vector((0, 1, 0)), 1.0)
    return (h[0] + h[1] * 0.0012) if h[0] else Vector((px_, -0.1, pz_))


gc = (0.052, 1.122)
for tri in ([(-0.030, 0.020), (0.0, -0.030), (-0.004, 0.022)], [(0.004, 0.022), (0.006, -0.026), (0.034, 0.024)], [(-0.008, -0.034), (0.010, -0.034), (0.001, -0.046)]):
    # subdivide each triangle so it follows the chest
    a, b_, c = [Vector((gc[0] + p[0], 0, gc[1] + p[1])) for p in tri]
    n = 4
    grid = {}
    for i in range(n + 1):
        for j in range(n + 1 - i):
            p = a + (b_ - a) * (i / n) + (c - a) * (j / n)
            grid[(i, j)] = gb.bm.verts.new(on_top(p.x, p.z))
    fs = []
    for i in range(n):
        for j in range(n - i):
            fs.append(gb.bm.faces.new((grid[(i, j)], grid[(i + 1, j)], grid[(i, j + 1)])))
            if i + j < n - 1:
                fs.append(gb.bm.faces.new((grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)])))
    gb._tag(fs, gmi)
objs["TopGraphic"] = gb.finish()

# =================================================================== CHEST STRAP
def torso_r(az, zz, y0=-0.025):
    d = Vector((math.sin(az), math.cos(az), 0))      # az 0 = back (+y), +90deg = her left
    o = Vector((0, y0, zz))
    best = 0.0
    for bv in (body_bvh,):
        h = bv.ray_cast(o, d, 0.3)
        if h[0] is not None:
            best = max(best, (h[0] - o).length)
    return best, d, o


sb = G.Builder("ChestStrap")
smi = sb.mat("strap_dark", "#28232b")
metal = sb.mat("metal", "#9c9a95")
yel = sb.mat("gear_yellow", "#f2b61f")
pts, nrm = [], []
NA = 56
for i in range(NA):
    az = 2 * math.pi * i / NA
    zz = 1.14
    for _ in range(4):
        r, d, o = torso_r(az, zz)
        xx = r * math.sin(az)
        zz = 1.145 + 1.22 * xx
        zz = min(zz, 1.262)
    r, d, o = torso_r(az, zz)
    r = min(r, 0.15)
    pts.append(o + d * (r + 0.011))
    nrm.append(d)
for _ in range(6):
    pts = [(pts[(i - 1) % NA] + pts[i] * 2 + pts[(i + 1) % NA]) / 4 for i in range(NA)]
sb.ribbon(pts, nrm, 0.026, 0.0045, smi, closed=True)
# buckle at the front centre and a slider higher up
fi = min(range(NA), key=lambda i: abs(pts[i].x + 0.012) + (100 if pts[i].y > Y_MID else 0))
for k, (off, sz, mi_) in enumerate(((0, (0.034, 0.030, 0.008), metal), (0, (0.020, 0.018, 0.011), yel), (5, (0.032, 0.014, 0.008), metal))):
    i = (fi + off) % NA
    tan = (pts[(i + 1) % NA] - pts[(i - 1) % NA]).normalized()
    m = G.place(pts[i] + nrm[i] * 0.005, nrm[i], tan)
    sb.box(m, (sz[1], sz[0], sz[2]), mi_, bevel=0.002)
objs["ChestStrap"] = sb.finish()

# =================================================================== PANTS
HIP, KNEE, ANK = J("upperleg01.L"), J("lowerleg01.L"), J("foot.L")
Z_WAIST_F, Z_WAIST_B, Z_CUFF = 0.925, 0.948, 0.185
waist = np.where(front, Z_WAIST_F, Z_WAIST_B) - 0.02 * sstep(0.05, 0.12, ax) * 0
pants_mask = (z < waist) & (z > Z_CUFF - 0.02) & (w_foot < 0.4) & (arm_any < 0.1)
pants = derive("Pants", pants_mask, subdiv=1)
co = coords(pants)
nn = normals(pants)
R_TAB = [(0.16, 0.060), (0.185, 0.064), (0.215, 0.100), (0.27, 0.124), (0.36, 0.120), (0.47, 0.108), (0.56, 0.108), (0.68, 0.112), (0.78, 0.108), (0.86, 0.100)]
TEARS = [  # (side, z, theta centre, half height, half width in theta)  theta: -pi/2 = front, 0 = outside
    (1, 0.505, -1.45, 0.030, 0.55),
    (-1, 0.335, -1.0, 0.028, 0.50),
]
new = co.copy()
uvs = np.zeros((len(co), 2))
tear_w = np.zeros(len(co))
for i, p in enumerate(co):
    side = 1.0 if p[0] >= 0 else -1.0
    P = Vector((abs(p[0]), p[1], p[2]))
    hip_ext = HIP + (HIP - KNEE).normalized() * 0.3
    s_, q, seg = poly_project(P, [hip_ext, HIP, KNEE, ANK, ANK + (ANK - KNEE).normalized() * 0.2])
    rad = P - q
    rl = rad.length
    dr = rad / rl if rl > 1e-6 else Vector((1, 0, 0))
    th = math.atan2(dr.y, dr.x)
    zz = p[2]
    R = interp(R_TAB, zz)
    # folds: ankle stack, knee creases, long thigh drape
    f = 0.0
    f += 0.11 * float(sstep(0.40, 0.30, zz) * sstep(0.19, 0.225, zz)) * math.sin(2 * math.pi * (zz - 0.2) / 0.042 + 0.9 * math.sin(th * 2 + side))
    f += 0.07 * math.exp(-((zz - 0.50) / 0.07) ** 2) * math.sin(2 * math.pi * zz / 0.036 + 1.6 * th) * (0.55 + 0.45 * math.sin(th))
    f += 0.045 * float(sstep(0.52, 0.62, zz) * sstep(0.84, 0.74, zz)) * math.sin(3 * th + 15 * zz + side)
    f += 0.03 * float(sstep(0.30, 0.40, zz) * sstep(0.50, 0.42, zz)) * math.sin(2 * th - 22 * zz)
    # the knee / shin presses against the cloth where it is torn
    tw = 0.0
    for (ts, tz, tth, hh, hw_) in TEARS:
        if ts == side:
            dth = abs(math.atan2(math.sin(th - tth), math.cos(th - tth)))
            tw = max(tw, float(sstep(hh * 3.2, hh * 1.0, abs(zz - tz)) * sstep(hw_ * 2.4, hw_ * 1.0, dth)))
    tear_w[i] = tw
    Rf = R * (1 + f)
    Rf = Rf * (1 - tw) + (rl + 0.006) * tw
    p_leg = q + dr * max(Rf, rl + 0.008)
    p_hip = P + Vector((abs(nn[i][0]) if p[0] * nn[i][0] >= 0 else -abs(nn[i][0]), nn[i][1], nn[i][2])) * 0.012
    wl = float(sstep(0.875, 0.775, zz))
    pn = p_hip.lerp(p_leg, wl)
    # dropped crotch
    pn.z -= 0.040 * math.exp(-(P.x / 0.07) ** 2) * float(sstep(0.92, 0.84, zz) * sstep(0.66, 0.80, zz))
    if abs(p[0]) < 1e-5:
        pn.x = 0.0
    else:
        pn.x = max(pn.x, 0.0008)
    new[i] = (pn.x * side, pn.y, pn.z)
    uvs[i] = (((th + math.pi) / (2 * math.pi)) * 0.5 + (0.0 if side > 0 else 0.5), (zz - 0.15) / 0.80)
set_coords(pants, new)

# tears: delete the faces in the middle of each tear zone
bm = bmesh.new()
bm.from_mesh(pants.data)
bm.verts.ensure_lookup_table()
uvl = bm.loops.layers.uv.verify()
kill = []
for f in bm.faces:
    if min(tear_w[v.index] for v in f.verts) > 0.985 and rnd.random() < 0.93:
        kill.append(f)
    fx = f.calc_center_median().x
    for lp in f.loops:
        u_, v_ = uvs[lp.vert.index]
        if abs(lp.vert.co.x) < 1e-5:          # midline vertices take the side of their face
            u_ = (0.0 if fx > 0 else 0.5) + (u_ % 0.5)
        lp[uvl].uv = (u_, v_)
# fix the theta wrap inside faces that straddle the inner seam
for f in bm.faces:
    us = [lp[uvl].uv.x for lp in f.loops]
    base = 0.0 if us[0] < 0.5 else 0.5
    loc = [u - base for u in us]
    if max(loc) - min(loc) > 0.25:
        for lp in f.loops:
            if lp[uvl].uv.x - base < 0.25:
                lp[uvl].uv.x += 0.5
                lp[uvl].uv.x = min(lp[uvl].uv.x, base + 0.5)
bmesh.ops.delete(bm, geom=kill, context='FACES')
bm.to_mesh(pants.data)
bm.free()
loops = relax_loops(pants, iters=9)
pants_tex = os.path.join(U.HERE, "tex", "moxie_pants.png")
pm = bpy.data.materials.new("pants_main")
pm.use_nodes = True
if os.path.exists(pants_tex):
    tn = pm.node_tree.nodes.new("ShaderNodeTexImage")
    tn.image = bpy.data.images.load(pants_tex)
    pm.node_tree.links.new(tn.outputs["Color"], pm.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
else:
    pm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*U.srgb("#5e5a33"), 1)
pants.data.materials.append(pm)
objs["Pants"] = pants

# cuffs (rolled), waistband and frayed tear edges from the boundary loops
pb = G.Builder("PantsTrim")
cuff_mi = pb.mat("pants_cuff", "#7d7748")
band_mi = pb.mat("pants_band", "#4c4829")
fray_mi = pb.mat("pants_fray", "#8c8656")
for loop in loops:
    zc_ = sum(p.z for p in loop) / len(loop)
    if zc_ < 0.25 and len(loop) > 20:
        pb.tube([p + Vector((0, 0, 0.012)) for p in loop[::2]], 0.017, cuff_mi, sides=6, closed=True, flat=1.5, up=Vector((0, 0, 1)))
    elif zc_ > 0.85:
        pb.tube([p + Vector((0, 0, -0.014)) for p in loop[::2]], 0.008, band_mi, sides=5, closed=True, flat=2.8, up=Vector((0, 0, 1)))
    elif len(loop) >= 6:
        pb.tube(loop, 0.0032, fray_mi, sides=5, closed=True)
objs["PantsTrim"] = pb.finish()

# cargo pockets on the outer thighs, back pockets, fly
pants_bvh = bvh_of(pants)
kb = G.Builder("PantsPockets")
pk_mi = kb.mat("pants_pocket", "#57532f")
pk_dk = kb.mat("pants_band", "#4c4829")
btn = kb.mat("metal", "#9c9a95")
for side in (1, -1):
    for (zz, th, w_, h_, d_) in ((0.60, 0.15, 0.105, 0.125, 0.030),):
        _, q, _ = poly_project(Vector((0.1, 0, zz)), [HIP, KNEE, ANK])
        d = Vector((math.cos(th), math.sin(th), 0))
        o = Vector((q.x + d.x * 0.4, q.y + d.y * 0.4, zz))
        o.x *= side
        dd = Vector((-d.x * side, -d.y, 0))
        h = pants_bvh.ray_cast(o, dd, 1.0)
        if h[0] is None:
            continue
        nrm_ = -dd
        m = G.place(h[0] + nrm_ * (d_ * 0.35), nrm_, Vector((0, 0, 1)))
        kb.box(m, (h_, w_, d_), pk_mi, bevel=0.008, segs=2)
        m2 = G.place(h[0] + nrm_ * (d_ * 0.82) + Vector((0, 0, h_ * 0.30)), nrm_, Vector((0, 0, 1)))
        kb.box(m2, (h_ * 0.42, w_ * 1.06, 0.012), pk_dk, bevel=0.004)
        m3 = G.place(h[0] + nrm_ * (d_ * 0.82 + 0.007) + Vector((0, 0, h_ * 0.16)), nrm_, Vector((0, 0, 1)))
        kb.cyl(m3, 0.007, 0.006, btn, sides=10)
objs["PantsPockets"] = kb.finish()

# =================================================================== JACKET
jk = {}
SH, EL, WR = J("upperarm01.L"), J("lowerarm01.L"), J("wrist.L")
ARM = [SH, EL, WR]
S_TOP, S_CUFF = 0.19, 0.64
SLEEVE_R = [(0.17, 0.098), (0.21, 0.094), (0.27, 0.084), (0.38, 0.080), (0.50, 0.078), (0.58, 0.072), (0.62, 0.056), (0.66, 0.050)]
sleeve_objs = []
for sgn, s in ((1, "L"), (-1, "R")):
    sfrac = np.zeros(len(co_b))
    for i in np.where((w_arm[s] + w_sh[s] > 0.3) & (x * sgn > 0.08))[0]:
        sfrac[i] = poly_project(Vector((abs(co_b[i][0]), co_b[i][1], co_b[i][2])), ARM)[0]
    mask = (w_arm[s] + w_sh[s] > 0.45) & (sfrac > S_TOP) & (sfrac < S_CUFF) & (x * sgn > 0.08)
    sl = derive("Sleeve" + s, mask, subdiv=1)
    co = coords(sl)
    lin = np.zeros(len(co), dtype=bool)
    for i, p in enumerate(co):
        P = Vector((abs(p[0]), p[1], p[2]))
        s_, q, seg = poly_project(P, ARM)
        rad = P - q
        rl = max(rad.length, 1e-6)
        dr = rad / rl
        axis_dir = (ARM[seg + 1] - ARM[seg]).normalized()
        ref = Vector((0, -1, 0)) - axis_dir * Vector((0, -1, 0)).dot(axis_dir)
        ref.normalize()
        th = math.atan2(dr.dot(axis_dir.cross(ref)), dr.dot(ref))
        R = interp(SLEEVE_R, s_)
        f = 0.13 * float(sstep(0.27, 0.34, s_) * sstep(0.63, 0.57, s_)) * math.sin(2 * math.pi * s_ / 0.075 + 1.3 * math.sin(th + sgn))
        f += 0.05 * math.sin(3 * th + 20 * s_)
        pn = q + dr * max(R * (1 + f), rl + 0.006)
        # gravity sag: bunched sleeve hangs below the arm
        pn.z -= 0.018 * float(sstep(0.22, 0.4, s_))
        co[i] = (pn.x * sgn, pn.y, pn.z)
        lin[i] = s_ < 0.265
    set_coords(sl, co)
    sl.data.materials.append(U.mat("jacket_main", "#2a242a"))
    sl.data.materials.append(U.mat("jacket_lining", "#f0b21c"))
    for p in sl.data.polygons:
        p.material_index = 0
    loops = relax_loops(sl, iters=3)
    sb_ = G.Builder("SleeveTrim" + s)
    rib = sb_.mat("jacket_rib", "#3b3440")
    lining = sb_.mat("jacket_lining", "#f0b21c")
    for loop in loops:
        c = sum(loop, Vector()) / len(loop)
        if poly_project(Vector((abs(c.x), c.y, c.z)), ARM)[0] > 0.5:
            sb_.tube(loop[::2], 0.012, rib, sides=6, closed=True, flat=1.0)
            jk["cuff_" + s] = c
        else:
            sb_.tube(loop[::2], 0.013, lining, sides=6, closed=True)
            jk["rim_" + s] = c
    objs["Sleeve" + s] = sl
    objs["SleeveTrim" + s] = sb_.finish()


def arm_pt(sfr):
    tot = (EL - SH).length + (WR - EL).length
    d = sfr * tot
    if d <= (EL - SH).length:
        return SH + (EL - SH).normalized() * d
    return EL + (WR - EL).normalized() * (d - (EL - SH).length)


# ---- body panel: an open tube round the torso, yellow inside, turned-out lapels, ribbed hem
jb = G.Builder("JacketBody")
j_out = jb.mat("jacket_main", "#2a242a")
j_lin = jb.mat("jacket_lining", "#f0b21c")
j_rib = jb.mat("jacket_rib", "#3b3440")
NS, NH = 52, 12
PHI_MAX = math.radians(124)
Z_HEMJ = 0.955
grid_o, grid_i = [], []
for a in range(NS + 1):
    phi = -PHI_MAX + 2 * PHI_MAX * a / NS
    ap = abs(math.degrees(phi))
    z_top = 1.085 + 0.070 * float(sstep(15, 80, ap)) - 0.012 * float(sstep(95, 124, ap))
    edge = float(sstep(PHI_MAX - math.radians(24), PHI_MAX, abs(phi)))
    col_o, col_i = [], []
    for b_ in range(NH + 1):
        h = b_ / NH
        zz = z_top + (Z_HEMJ - z_top) * h
        r, d, o = torso_r(phi, zz, y0=-0.03)
        r = min(max(r, 0.07), 0.17)
        rr = r + 0.040 + 0.030 * h + 0.022 * math.sin(math.pi * min(h * 1.1, 1.0))
        rr += 0.010 * math.sin(6 * phi + 1.0) * (0.3 + h) + 0.006 * math.sin(11 * phi + 3 * h)
        rr += 0.030 * edge * (0.4 + 0.6 * h)                     # front edges swing open
        if h > 0.86:
            rr -= 0.014 * (h - 0.86) / 0.14                     # ribbed hem pulls in
        zz2 = zz - 0.012 * math.sin(4 * phi) * h
        p = o + d * rr
        p.z = zz2
        col_o.append(jb.bm.verts.new(p))
        col_i.append(jb.bm.verts.new(o + d * (rr - 0.008) + Vector((0, 0, zz2 - zz))))
    grid_o.append(col_o)
    grid_i.append(col_i)
for a in range(NS):
    lap = min(a, NS - 1 - a)
    for b_ in range(NH):
        h = b_ / NH
        lapel = lap < 4
        mi = j_rib if b_ >= NH - 2 else (j_lin if lapel else j_out)
        f = jb.bm.faces.new((grid_o[a][b_], grid_o[a + 1][b_], grid_o[a + 1][b_ + 1], grid_o[a][b_ + 1]))
        jb._tag([f], mi)
        f = jb.bm.faces.new((grid_i[a][b_ + 1], grid_i[a + 1][b_ + 1], grid_i[a + 1][b_], grid_i[a][b_]))
        jb._tag([f], j_lin)
    jb._tag([jb.bm.faces.new((grid_o[a][0], grid_i[a][0], grid_i[a + 1][0], grid_o[a + 1][0])),
             jb.bm.faces.new((grid_o[a][NH], grid_o[a + 1][NH], grid_i[a + 1][NH], grid_i[a][NH]))], j_rib)
for a in (0, NS):
    for b_ in range(NH):
        jb._tag([jb.bm.faces.new((grid_o[a][b_], grid_o[a][b_ + 1], grid_i[a][b_ + 1], grid_i[a][b_]))], j_lin)
objs["JacketBody"] = jb.finish()

# ---- collar roll: sags across the back and wraps round the outside of both upper arms
cb = G.Builder("JacketCollar")
c_out = cb.mat("jacket_main", "#2a242a")
c_lin = cb.mat("jacket_lining", "#f0b21c")
ap_ = arm_pt(0.215)
half = [Vector((0.150, -0.125, 1.108)), Vector((ap_.x - 0.012, ap_.y - 0.088, ap_.z - 0.012)),
        Vector((ap_.x + 0.058, ap_.y - 0.040, ap_.z + 0.058)), Vector((ap_.x + 0.062, ap_.y + 0.045, ap_.z + 0.060)),
        Vector((ap_.x - 0.02, ap_.y + 0.095, ap_.z + 0.005)), Vector((0.085, 0.112, 1.135)), Vector((0.0, 0.118, 1.105))]
path = half + [Vector((-p.x, p.y, p.z)) for p in half[-2::-1]]
sm = G.smooth_path(path, 56)
ups = []
for p in sm:
    c_ = Vector((0, -0.02, p.z))
    ups.append((p - c_).normalized())
cb.tube(sm, lambda t: 0.034 * (0.55 + 0.45 * math.sin(math.pi * t) ** 0.5), c_out, sides=8, flat=0.62, up=ups)
sm2 = [p - u * 0.012 + Vector((0, 0, 0.022)) for p, u in zip(sm, ups)]
cb.tube(sm2, lambda t: 0.017 * (0.5 + 0.5 * math.sin(math.pi * t) ** 0.5), c_lin, sides=6, flat=0.7, up=ups)
objs["JacketCollar"] = cb.finish()

# =================================================================== GLOVES (material region on the hands)
bm = bmesh.new()
bm.from_mesh(bme)
bm.verts.ensure_lookup_table()
gl = U.mat("glove", "#27222b")
bme.materials.append(gl)
gi = len(bme.materials) - 1
glove_v = np.zeros(len(co_b), dtype=bool)
for sgn, s in ((1, "L"), (-1, "R")):
    tipw = weights(body, [g.name for g in body.vertex_groups if g.name.endswith("." + s) and g.name.startswith("finger") and (g.name[8] in "23")])
    # thumb: finger1-2/1-3 are its outer phalanges
    wr = Vector((J("wrist.L").x * sgn, J("wrist.L").y, J("wrist.L").z))
    fore_dir = (Vector((EL.x * sgn, EL.y, EL.z)) - wr).normalized()
    for i in range(len(co_b)):
        if x[i] * sgn < 0.25:
            continue
        up_arm = (Vector(co_b[i]) - wr).dot(fore_dir)
        if (w_hand[s][i] > 0.5 and tipw[i] < 0.30) or (w_hand[s][i] + w_arm[s][i] > 0.5 and -0.02 < up_arm < 0.035 and w_hand[s][i] > 0.05):
            glove_v[i] = True
for f in bm.faces:
    if all(glove_v[v.index] for v in f.verts):
        f.material_index = gi
for v in bm.verts:
    if glove_v[v.index]:
        v.co += v.normal * 0.0016
    elif 1.092 < v.co.z < 1.185 and arm_any[v.index] < 0.3 and abs(v.co.x) < 0.12:
        v.co -= v.normal * 0.006          # tuck the skin under the top

# =================================================================== hide skin under the garments
kill = []
tear_z = [(t[0], t[1]) for t in TEARS]
for f in bm.faces:
    c = f.calc_center_median()
    vi = [v.index for v in f.verts]
    under_pants = (c.z < 0.895) and (c.z > 0.24) and all(arm_any[i] < 0.1 for i in vi)
    if under_pants:
        near_tear = any(((c.x > 0) == (ts > 0)) and abs(c.z - tz) < 0.09 for ts, tz in tear_z)
        if not near_tear:
            kill.append(f)
            continue
    if c.z < 0.105 and all(w_foot[i] + w_leg[i] > 0.5 for i in vi):
        kill.append(f)          # feet live inside the boots
bmesh.ops.delete(bm, geom=kill, context='FACES')
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
bm.to_mesh(bme)
bm.free()

body["jacket"] = json.dumps({k: list(v) for k, v in jk.items()})
print("tris:", {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == 'MESH'})
U.save_stage("s05_outfit")

if "--norender" not in sys.argv:
    rig.hide_render = True
    T.toonify([o for o in bpy.data.objects if o.type == 'MESH'], outline=0.0028)
    U.render_views(os.path.join(U.WIP, "s05_full.png"), views=("front", "q", "side", "back"), center=(0, 0, 0.84), scale=1.85,
                   res=(560, 1000), setup=T.setup_eevee)
