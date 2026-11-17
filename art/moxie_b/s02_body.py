"""Stage 2: turn the MakeHuman base into Moxie's stylised body.

- strips helper geometry, keeps the production quad topology of the body
- anime proportions: longer legs, larger head, final scale (bare height 1.565 m + 3.5 cm boot sole)
- rebuilds the head as an anime head on the same topology: tapered jaw, pointed chin, tiny nose,
  softened lips/brow, mouth cavity removed and lip seam closed, large reshaped eye openings (eyelid
  edge loops kept) and the eye pockets replaced by clean recessed eye plates that carry a painted iris.
Outputs _stage/s02_body.blend with objects Body (mesh) and MH_Rig (MakeHuman rig, deformed to match).
Landmarks used by later stages are stored as custom properties on Body; per-vertex int attributes
'eye_ring' (0 = none, 11 = lid edge, 12.. = eyelid loops, -1..-5 = plate rings) and 'eye_side'.
"""
import bpy, bmesh, sys, os, math, json
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
from mathutils import Vector
from mathutils.bvhtree import BVHTree

U.open_stage("s01_base")
base = bpy.data.objects["MH_Base"]
rig = bpy.data.objects["MH_Rig"]
me = base.data

SOLE = 0.035
BARE_H = 1.565
LEG_STRETCH = 1.07
HEAD_SCALE = np.array([1.52, 1.48, 1.40])   # x (width), y (depth), z (height)
LID = 11                                     # BFS ring index of the eyelid edge loop
PLATE_T = [0.93, 0.72, 0.48, 0.24]           # plate rings as a fraction of the lid loop radius


def group_ids(n):
    gi = base.vertex_groups[n].index
    return np.array([v.index for v in me.vertices if any(g.group == gi for g in v.groups)], dtype=int)


def weights_of(names):
    idx = {base.vertex_groups[n].index for n in names if n in base.vertex_groups}
    w = np.zeros(len(me.vertices))
    for v in me.vertices:
        for g in v.groups:
            if g.group in idx:
                w[v.index] += g.weight
    return w


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


co = np.array([v.co[:] for v in me.vertices], dtype=float)
head_bones = [b.name for b in rig.data.bones["head"].children_recursive] + ["head"]
hw = np.clip(weights_of(head_bones), 0, 1)

# ---------------------------------------------------------------- global proportion transforms
zmin = co[group_ids("body")][:, 2].min()
co[:, 2] -= zmin
z_crotch = rig.data.bones["upperleg01.L"].head_local.z - zmin - 0.03
head_pivot = np.array([0.0, 0.005, rig.data.bones["head"].head_local.z - zmin - 0.045])
head_pivot[2] += (LEG_STRETCH - 1) * z_crotch
body_ids = group_ids("body")


def glob(p, w):
    """p (n,3) in grounded MakeHuman metres, w = head weight. Returns stretched/scaled positions."""
    p = p.copy()
    p[:, 2] = p[:, 2] + (LEG_STRETCH - 1) * np.minimum(p[:, 2], z_crotch)
    s = (p - head_pivot) * HEAD_SCALE + head_pivot
    p = p + (s - p) * w[:, None]
    return p


co = glob(co, hw)
k = BARE_H / co[body_ids][:, 2].max()
co = co * k
co[:, 2] += SOLE

# the MakeHuman rig follows (edit bones), so later weight transfer and joint positions stay valid
U.activate(rig)
bpy.ops.object.mode_set(mode='EDIT')
hb = set(head_bones)
for eb in rig.data.edit_bones:
    for attr in ("head", "tail"):
        p = np.array([getattr(eb, attr)[:]], dtype=float)
        p[:, 2] -= zmin
        w = np.array([1.0 if (eb.name in hb and not (eb.name == "head" and attr == "head")) else 0.0])
        q = glob(p, w)[0] * k
        q[2] += SOLE
        setattr(eb, attr, Vector(q))
bpy.ops.object.mode_set(mode='OBJECT')

eye_c = {s: co[group_ids("helper-%s-eye" % s)].mean(0) for s in ("l", "r")}
eye_r = np.linalg.norm(co[group_ids("helper-l-eye")] - eye_c["l"], axis=1).max()
for i, v in enumerate(me.vertices):
    v.co = co[i]

# ---------------------------------------------------------------- topology edits
bm = bmesh.new()
bm.from_mesh(me)
keep = set(body_ids.tolist())
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context='VERTS')
bm.verts.ensure_lookup_table()
bm.normal_update()
dl = bm.verts.layers.deform.verify()
L_ring = bm.verts.layers.int.new("eye_ring")
L_side = bm.verts.layers.int.new("eye_side")
L_part = bm.verts.layers.int.new("eye_partner")   # plate vertex -> its lid-loop position index

# 1. mouth: delete the oral cavity (vertices no outside ray reaches) and fill the lip seam
bvh = BVHTree.FromBMesh(bm)
lipg = base.vertex_groups["lips"].index
lipv = [v for v in bm.verts if lipg in v[dl]]
lc = sum((v.co for v in lipv), Vector()) / len(lipv)
dirs = [Vector(d).normalized() for d in [(0, -1, 0), (0.5, -1, 0), (-0.5, -1, 0), (0, -1, 0.5), (0, -1, -0.5), (1, -0.3, 0),
                                         (-1, -0.3, 0), (0, -0.4, -1), (0.7, -0.7, -0.5), (-0.7, -0.7, -0.5)]]
inner = []
for v in bm.verts:
    d = v.co - lc
    if abs(d.x) < 0.05 and abs(d.z) < 0.035 and -0.01 < d.y < 0.09:
        o = v.co + v.normal * 0.0004
        if all(bvh.ray_cast(o, dd, 0.5)[0] is not None for dd in dirs):
            inner.append(v)
bmesh.ops.delete(bm, geom=inner, context='VERTS')
res = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
bmesh.ops.triangulate(bm, faces=res["faces"])
print("mouth cavity verts removed", len(inner))

# 2. eyes: find concentric rings, replace the pocket by a clean plate
bm.verts.ensure_lookup_table()
for si, s in enumerate(("l", "r")):
    c = Vector(eye_c[s])
    near = [v for v in bm.verts if (v.co - c).length < eye_r * 2.2 and Vector((v.co.x - c.x, v.co.z - c.z)).length < eye_r * 1.2]
    seed = max(near, key=lambda v: v.co.y)
    ring = {seed: 0}
    front = {seed}
    kk = 0
    while front and kk < 19:
        kk += 1
        nxt = set()
        for v in front:
            for f in v.link_faces:
                for v2 in f.verts:
                    if v2 not in ring:
                        nxt.add(v2)
        for v in nxt:
            ring[v] = kk
        front = nxt
    for v, r in ring.items():
        if r >= LID:
            v[L_ring] = r
            v[L_side] = si + 1
    lidv = [v for v, r in ring.items() if r == LID]
    bmesh.ops.delete(bm, geom=[v for v, r in ring.items() if r < LID], context='VERTS')
    start = lidv[0]
    loop = [start]
    prev = None
    cur = start
    while True:
        nx = [e.other_vert(cur) for e in cur.link_edges if e.is_boundary and e.other_vert(cur) is not prev]
        nx = [v for v in nx if v[L_ring] == LID]
        if not nx or nx[0] is start:
            break
        prev, cur = cur, nx[0]
        loop.append(cur)
    assert len(loop) == len(lidv), (len(loop), len(lidv))
    m = len(loop)
    for a, v in enumerate(loop):
        v[L_part] = a
    prev_ring = loop
    for j, t in enumerate(PLATE_T):
        new = []
        for a, v in enumerate(loop):
            nv = bm.verts.new(v.co)
            for gk, gv in v[dl].items():
                nv[dl][gk] = gv
            nv[L_ring] = -(j + 1)
            nv[L_side] = si + 1
            nv[L_part] = a
            new.append(nv)
        for a in range(m):
            bm.faces.new((prev_ring[a], prev_ring[(a + 1) % m], new[(a + 1) % m], new[a]))
        prev_ring = new
    cv = bm.verts.new(loop[0].co)
    for gk, gv in loop[0][dl].items():
        cv[dl][gk] = gv
    cv[L_ring] = -(len(PLATE_T) + 1)
    cv[L_side] = si + 1
    for a in range(m):
        bm.faces.new((prev_ring[a], prev_ring[(a + 1) % m], cv))
    bm.verts.ensure_lookup_table()
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
bm.to_mesh(me)

for g in list(base.vertex_groups):
    if g.name.startswith(("helper-", "joint-")) or g.name in ("HelperGeometry", "JointCubes"):
        base.vertex_groups.remove(g)
base.name = "Body"
me.name = "Body"
while base.modifiers:
    base.modifiers.remove(base.modifiers[0])
if me.shape_keys:
    base.shape_key_clear()

# ---------------------------------------------------------------- numpy state on the new topology
n = len(me.vertices)
co = np.array([v.co[:] for v in me.vertices], dtype=float)
hw = np.clip(weights_of(head_bones), 0, 1)
ringa = np.array([d.value for d in me.attributes["eye_ring"].data], dtype=int)
sidea = np.array([d.value for d in me.attributes["eye_side"].data], dtype=int)
parta = np.array([d.value for d in me.attributes["eye_partner"].data], dtype=int)
plate = ringa < 0
bm.verts.index_update()
bm.verts.ensure_lookup_table()
edges_all = np.array([[e.verts[0].index, e.verts[1].index] for e in bm.edges], dtype=int)
# the smoothing graph ignores the plates, so the lids relax as an open boundary
edges = edges_all[~(plate[edges_all[:, 0]] | plate[edges_all[:, 1]])]
deg = np.zeros(n)
np.add.at(deg, edges[:, 0], 1)
np.add.at(deg, edges[:, 1], 1)


def smooth(co, mask, iters=10, lam=0.5, axes=(0, 1, 2)):
    for _ in range(iters):
        acc = np.zeros_like(co)
        np.add.at(acc, edges[:, 0], co[edges[:, 1]])
        np.add.at(acc, edges[:, 1], co[edges[:, 0]])
        avg = acc / np.maximum(deg, 1)[:, None]
        d = (avg - co) * (lam * mask)[:, None]
        for a in axes:
            co[:, a] += d[:, a]
    return co


# ---------------------------------------------------------------- head landmarks
front_mid = [i for i in range(n) if hw[i] > 0.95 and abs(co[i][0]) < 0.004 and co[i][1] < eye_c["l"][1] + 0.03 and not plate[i]]
z_top = co[hw > 0.9][:, 2].max()
lipi = base.vertex_groups["lips"].index
lips = [v.index for v in me.vertices if any(g.group == lipi for g in v.groups)]
z_mouth = co[lips][:, 2].mean()
nose_tip = min(front_mid, key=lambda i: co[i][1])
z_nose = co[nose_tip][2]
below = [i for i in front_mid if co[i][2] < z_mouth - 0.01]
chin = min(below, key=lambda i: co[i][1])
z_chin = min(co[i][2] for i in below if co[i][1] < co[chin][1] + 0.012)
z_eye = eye_c["l"][2]
H = z_top - z_chin
print("landmarks: top %.3f eye %.3f nose %.3f mouth %.3f chin %.3f  H %.3f eye x %.3f" % (z_top, z_eye, z_nose, z_mouth, z_chin, H, eye_c["l"][0]))

# ---------------------------------------------------------------- face restyle
face_front = sstep(0.0, -0.035, co[:, 1] - (eye_c["l"][1] + 0.045)) * hw   # 1 on the face, 0 behind the ears
x, y, z = co[:, 0], co[:, 1], co[:, 2]
nose_m = sstep(0.028, 0.012, np.abs(x)) * sstep(z_mouth + 0.004, z_mouth + 0.014, z) * sstep(z_eye + 0.035, z_eye + 0.01, z) * face_front
lip_m = sstep(0.045, 0.025, np.abs(x)) * sstep(z_mouth - 0.03, z_mouth - 0.012, z) * sstep(z_mouth + 0.02, z_mouth + 0.008, z) * face_front
co0 = co.copy()
co = smooth(co, np.clip(nose_m, 0, 1), iters=60, lam=0.6)
tip_m = np.exp(-(x ** 2 + (z - z_nose) ** 2) / (2 * 0.007 ** 2)) * face_front
co[:, 1] += (co0[:, 1] - co[:, 1]) * tip_m * 0.45          # keep a small upturned nose tip
co = smooth(co, np.clip(lip_m, 0, 1) * 0.95, iters=45, lam=0.5)
co = smooth(co, face_front * 0.5, iters=4, lam=0.5)

x, y, z = co[:, 0], co[:, 1], co[:, 2]
u = (z - z_chin) / H
jaw = hw * sstep(0.03, -0.05, y - eye_c["l"][1] - 0.06)
taper = 1.0 - 0.14 * sstep(0.42, 0.0, u) * jaw - 0.05 * sstep(0.16, -0.02, u) * jaw
co[:, 0] = x * taper
cheek = np.exp(-((u - 0.36) / 0.13) ** 2) * face_front * sstep(0.02, 0.06, np.abs(x))
co[:, 0] += np.sign(x) * cheek * 0.004
muzzle = sstep(0.05, 0.0, np.abs(x)) * sstep(0.40, 0.2, u) * sstep(-0.05, 0.1, u) * face_front
co[:, 1] += muzzle * 0.006
chin_m = np.exp(-(x ** 2) / (2 * 0.03 ** 2)) * sstep(0.12, 0.0, u) * hw
co[:, 2] += chin_m * 0.004

# ---------------------------------------------------------------- anime eyes
EYE_X = 0.0545          # centre distance from the midline
EYE_Z = z_eye - 0.010
EYE_W = 0.0282          # half width
EYE_HU = 0.0225         # height above centre
EYE_HL = 0.0135         # height below centre
TILT = math.radians(7)  # outer corner raised
RECESS = 0.0040


import mb_eye


def outline(theta):
    return mb_eye.outline(theta, EYE_W, EYE_HU, EYE_HL, TILT)


for si, (s, sign) in enumerate((("l", 1.0), ("r", -1.0))):
    ids_lid = np.where((ringa == LID) & (sidea == si + 1))[0]
    c_old = co[ids_lid].mean(0)
    c_new = np.array([sign * EYE_X, 0.0, EYE_Z])

    # parametrise the lid loop by vertex order: outer corner -> upper lid -> inner corner -> lower lid
    order = sorted(ids_lid, key=lambda i: parta[i])
    lat = np.array([(co[i][0] - c_old[0]) * sign for i in order])
    m = len(order)
    io, ii = int(np.argmax(lat)), int(np.argmin(lat))
    step = 1
    probe = order[(io + 2) % m]
    if co[probe][2] < c_old[2]:
        step = -1                                  # make the walk from the outer corner go over the top
    n_up = ((ii - io) * step) % m
    n_lo = m - n_up
    theta = {}
    for q in range(m):
        i = order[(io + step * q) % m]
        theta[i] = math.pi * q / n_up if q <= n_up else -math.pi * (m - q) / n_lo
    disp = []
    for i in ids_lid:
        oa, ob = outline(theta[i])
        disp.append(np.array([c_new[0] + sign * oa, co[i][1], c_new[2] + ob]) - co[i])
    disp = np.array(disp)
    old_lid = co[ids_lid].copy()

    def near_disp(p):
        d = np.linalg.norm((old_lid - p)[:, [0, 2]], axis=1)
        j = np.argsort(d)[:3]
        w = 1.0 / (d[j] + 1e-5)
        return (disp[j] * w[:, None]).sum(0) / w.sum()

    newco = {}
    for i in range(n):
        if plate[i] or hw[i] < 0.5 or co[i][0] * sign < 0.004:
            continue
        if ringa[i] == LID and sidea[i] == si + 1:
            continue
        d = np.linalg.norm((old_lid - co[i])[:, [0, 2]], axis=1).min()
        dy = abs(co[i][1] - c_old[1])
        wgt = float(sstep(0.036, 0.002, d) * sstep(0.05, 0.02, dy))
        if wgt > 0:
            newco[i] = co[i] + near_disp(co[i]) * wgt
    for i, p in newco.items():
        co[i] = p
    co[ids_lid] += disp

# relax the area around the eyes: the lid edge keeps its outline (x, z) but its depth floats, which
# fills in the realistic orbital hollow and leaves a clean anime eye socket
xz_dist = np.hypot(np.abs(co[:, 0]) - EYE_X, co[:, 2] - EYE_Z)
around = sstep(0.06, 0.03, xz_dist) * face_front * (~plate)
is_lid = (ringa == LID)
m_free = around * (~is_lid)
for _ in range(10):
    co = smooth(co, m_free, iters=3, lam=0.5)
    co = smooth(co, around * is_lid, iters=3, lam=0.5, axes=(1,))

# eye plates
eye_new_c = {}
for si, (s, sign) in enumerate((("l", 1.0), ("r", -1.0))):
    ids_lid = np.where((ringa == LID) & (sidea == si + 1))[0]
    by_part = {int(parta[i]): i for i in ids_lid}
    c = co[ids_lid].mean(0)
    plate_y = co[ids_lid][:, 1].max() + RECESS
    for j, t in enumerate(PLATE_T):
        for i in np.where((ringa == -(j + 1)) & (sidea == si + 1))[0]:
            p = c + (co[by_part[int(parta[i])]] - c) * t
            p[1] = plate_y + 0.0012 * (1 - t * t)
            co[i] = p
    ci = np.where((ringa == -(len(PLATE_T) + 1)) & (sidea == si + 1))[0]
    co[ci] = [c[0], plate_y + 0.0012, c[2]]
    eye_new_c[s] = [float(c[0]), float(plate_y), float(c[2])]

for i, v in enumerate(me.vertices):
    v.co = co[i]
bm.free()

for s, si in (("l", 1), ("r", 2)):
    g = base.vertex_groups.new(name="eye_plate_" + s)
    g.add([int(i) for i in np.where((ringa < 0) & (sidea == si))[0]], 1.0, 'REPLACE')
    g = base.vertex_groups.new(name="eye_lid_" + s)
    g.add([int(i) for i in np.where((ringa == LID) & (sidea == si))[0]], 1.0, 'REPLACE')
base["landmarks"] = json.dumps(dict(
    z_top=float(z_top), z_eye=float(EYE_Z), z_nose=float(co[nose_tip][2]), y_nose=float(co[nose_tip][1]),
    z_mouth=float(co[lips][:, 2].mean()), y_mouth=float(co[lips][:, 1].min()),
    z_chin=float(co[np.array(below)][:, 2].min()),
    eye_x=EYE_X, eye_w=EYE_W, eye_hu=EYE_HU, eye_hl=EYE_HL, tilt=TILT,
    eye_c_l=eye_new_c["l"], eye_c_r=eye_new_c["r"],
    head_pivot=[float(a) for a in (head_pivot * k + np.array([0, 0, SOLE]))], H=float(H), sole=SOLE))
for p in me.polygons:
    p.use_smooth = True
me.update()
with open(os.path.join(U.STAGE, "landmarks.json"), "w") as fh:
    fh.write(base["landmarks"])
U.save_stage("s02_body")

if "--norender" not in sys.argv:
    rig.hide_render = True
    U.render_views(os.path.join(U.WIP, "s02_body.png"), center=(0, 0, 0.82), scale=1.75, res=(520, 900))
    hc = (0, 0, z_chin + H * 0.5)
    U.render_views(os.path.join(U.WIP, "s02_eye.png"), views=("front", "q", "side"), center=(EYE_X, -0.05, EYE_Z), scale=0.09, res=(700, 700))
    U.render_views(os.path.join(U.WIP, "s02_head.png"), views=("front", "q", "side", "up"), center=hc, scale=H * 1.45, res=(700, 700))
