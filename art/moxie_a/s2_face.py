"""Stage 2 - turn the generic VRoid face into Moxie's face and convert every textured face part to
flat-colour geometry (the game replaces all materials with a flat cel shader, so nothing may depend
on a texture): reshape eyes / brows / mouth, bake her default confident grin, cut irises, pupils,
highlights, lashes, brows, teeth and face paint into the mesh as separate flat materials.
Reads work/s1.blend, saves work/s2.blend.
"""
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_util as U

# default expression baked into the Basis (VRoid expression keys stay available on top of it)
GRIN = {'Fcl_MTH_E': 1.0, 'Fcl_MTH_Fun': 0.7, 'Fcl_BRW_Angry': 0.5, 'Fcl_EYE_Angry': 0.25, 'Fcl_HA_Fung1': 1.0}
KEEP_KEYS = {  # exported shape keys (new name -> source)
    'blink': 'Fcl_EYE_Close', 'blink_l': 'Fcl_EYE_Close_L', 'blink_r': 'Fcl_EYE_Close_R',
    'eye_joy': 'Fcl_EYE_Joy', 'eye_wide': 'Fcl_EYE_Surprised', 'brow_angry': 'Fcl_BRW_Angry',
    'brow_sorrow': 'Fcl_BRW_Sorrow', 'brow_up': 'Fcl_BRW_Surprised',
    'mouth_a': 'Fcl_MTH_A', 'mouth_o': 'Fcl_MTH_O', 'mouth_close': 'Fcl_MTH_Close',
    'mouth_angry': 'Fcl_MTH_Angry', 'mouth_joy': 'Fcl_MTH_Joy', 'mouth_sorrow': 'Fcl_MTH_Sorrow',
}

import json
if os.environ.get('MXA_GRIN'):
    GRIN = json.loads(os.environ['MXA_GRIN'])
MOUTH_WIDE = float(os.environ.get('MXA_WIDE', '0.30'))
MOUTH_TALL = float(os.environ.get('MXA_TALL', '1.6'))
OUT = os.environ.get('MXA_OUT', 's2.blend')
EYE_SCALE = 1.24
EYE_TILT = math.radians(7.0)
BROW_THICK = 2.4
EYE_R = 0.052


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def main():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(U.WORK, 's1.blend'))
    face = bpy.data.objects['Face']; body = bpy.data.objects['Body']
    me = face.data
    mats = [m.name for m in me.materials]
    def mi(part):
        return [i for i, n in enumerate(mats) if part in n][0]
    images = {}
    for m in me.materials:
        for n in m.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and n.outputs[0].links:
                images[m.name] = n.image

    # ---- landmarks
    iris_i = mi('EyeIris')
    vs = set()
    for p in me.polygons:
        if p.material_index == iris_i:
            vs.update(p.vertices)
    eyeL = sum((me.vertices[i].co for i in vs if me.vertices[i].co.x > 0), Vector()) / (len(vs) / 2)
    eyeR = Vector((-eyeL.x, eyeL.y, eyeL.z))
    print('eye centre', eyeL[:])

    # ---- spatial warps, applied to the basis and to every shape key alike
    def warp(co):
        x, y, z = co
        for c in (eyeL, eyeR):
            dx = x - c.x; dz = z - c.z
            d = math.hypot(dx, dz * 1.15)
            if d < EYE_R:
                w = smooth(1 - d / EYE_R)
                s = 1 + (EYE_SCALE - 1) * w
                a = EYE_TILT * w * (1 if c.x > 0 else -1)
                ca, sa = math.cos(a), math.sin(a)
                rx = dx * ca - dz * sa; rz = dx * sa + dz * ca
                x = c.x + rx * s * 1.04; z = c.z + rz * s - 0.002 * w
        return Vector((x, y, z))
    kbs = me.shape_keys.key_blocks
    for kb in kbs:
        for d in kb.data:
            d.co = warp(d.co)
    for v in me.vertices:
        v.co = warp(v.co)

    # ---- bake the grin into the basis; every other key keeps its relative offset
    n = len(me.vertices)
    basis = np.zeros(n * 3, np.float32); kbs['Basis'].data.foreach_get('co', basis)
    delta = np.zeros_like(basis)
    for k, w in GRIN.items():
        a = np.zeros(n * 3, np.float32); kbs[k].data.foreach_get('co', a)
        delta += (a - basis) * w
    # widen the grin: stretch the mouth region sideways
    mouth_i = mi('FaceMouth')
    mv = set()
    for p in me.polygons:
        if p.material_index == mouth_i:
            mv.update(p.vertices)
    for kb in kbs:
        a = np.zeros(n * 3, np.float32); kb.data.foreach_get('co', a)
        a += delta
        kb.data.foreach_set('co', a)
    me.vertices.foreach_set('co', basis + delta)
    me.update()
    mc = sum((me.vertices[i].co for i in mv), Vector()) / len(mv)
    lipz = max(me.vertices[i].co.z for i in mv)
    print('mouth centre', mc[:])

    def mouth_warp(co):
        dx = co.x - 0.0; dz = co.z - (mc.z + 0.004)
        d = math.hypot(dx / 0.05, dz / 0.028)
        if d >= 1 or co.y > mc.y + 0.02:
            return co
        w = smooth(1 - d)
        # wider, corners pulled up and to her left (lopsided, cocky)
        x = co.x * (1 + MOUTH_WIDE * w) + 0.0035 * w
        z = (mc.z + 0.002) + (co.z - mc.z - 0.002) * (1 + (MOUTH_TALL - 1) * w)
        z = z + w * (abs(dx) / 0.05) * 0.0075 + (0.0025 * w * (dx / 0.05))
        return Vector((x, co.y, z))
    for kb in kbs:
        for d in kb.data:
            d.co = mouth_warp(d.co)
    for v in me.vertices:
        v.co = mouth_warp(v.co)

    # ---- brows: the VRoid brow is a hairline; stretch the brow patch into a thick, low, angled brow
    brow_i = mi('FaceBrow')
    bv = set()
    for p in me.polygons:
        if p.material_index == brow_i:
            bv.update(p.vertices)
    for side in (1, -1):
        idx = [i for i in bv if me.vertices[i].co.x * side > 0]
        xs_ = np.array([me.vertices[i].co.x for i in idx]); zs_ = np.array([me.vertices[i].co.z for i in idx])
        k1, k0 = np.polyfit(xs_, zs_, 1)
        xm = xs_.mean()
        def bw(co, k1=k1, k0=k0, xm=xm, side=side):
            zl = k1 * co.x + k0
            t = (co.x - xm) * side  # + towards the temple
            return Vector((xm + (co.x - xm) * 1.12, co.y - 0.0008, zl + (co.z - zl) * BROW_THICK - 0.0045 + t * 0.10))
        for kb in kbs:
            for i in idx:
                kb.data[i].co = bw(kb.data[i].co)
        for i in idx:
            me.vertices[i].co = bw(me.vertices[i].co)

    # ---- drop unneeded keys, rename the kept ones
    keep_src = {v: k for k, v in KEEP_KEYS.items()}
    face.active_shape_key_index = 0
    for kb in list(kbs):
        if kb.name == 'Basis':
            continue
        if kb.name in keep_src:
            kb.name = keep_src[kb.name]
        else:
            face.shape_key_remove(kb)

    # ---- geometry conversion
    bm = bmesh.new(); bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active

    def uv_of(v):
        return v.link_loops[0][uvl].uv

    slots = {}
    def slot(name):
        if name not in slots:
            slots[name] = U.mat_slot(face, U.mat(name))
        return slots[name]

    def faces_mat(i):
        return [f for f in bm.faces if f.material_index == i]

    def cut(faces, field, inside_mat=None, delete_outside=False, outside_mat=None):
        ins, outs = U.split_by_field(bm, faces, field)
        if inside_mat is not None:
            for f in ins:
                f.material_index = slot(inside_mat)
        if outside_mat is not None:
            for f in outs:
                f.material_index = slot(outside_mat)
        if delete_outside:
            bmesh.ops.delete(bm, geom=outs, context='FACES')
            outs = []
        return ins, outs

    # irises ------------------------------------------------------------
    im = U.Image2D(images[mats[iris_i]])
    alpha = im.px[..., 3] > 0.5
    ys, xs = np.nonzero(alpha)
    halves = []
    for lo, hi in ((0, im.w // 2), (im.w // 2, im.w)):
        sel = (xs >= lo) & (xs < hi)
        x0, x1, y0, y1 = xs[sel].min(), xs[sel].max(), ys[sel].min(), ys[sel].max()
        halves.append(((x0 + x1) / 2 / im.w, (y0 + y1) / 2 / im.h, (x1 - x0) / 2 / im.w, (y1 - y0) / 2 / im.h))
    print('iris uv ellipses', halves)

    def q_of(v):
        uv = uv_of(v)
        cu, cv, ru, rv = halves[0] if uv.x < 0.5 else halves[1]
        return (uv.x - cu) / ru, (uv.y - cv) / rv

    iris_faces = faces_mat(iris_i)
    U.subdivide_faces(bm, iris_faces, 1)
    iris_faces = faces_mat(iris_i)
    # which way does +u run in world x, and +v in world z?  (so highlights sit on the light side)
    f0 = [f for f in iris_faces if f.calc_center_median().x > 0]
    us = np.array([[uv_of(v).x, uv_of(v).y, v.co.x, v.co.z] for f in f0 for v in f.verts])
    su = 1 if np.corrcoef(us[:, 0], us[:, 2])[0, 1] > 0 else -1
    sv = 1 if np.corrcoef(us[:, 1], us[:, 3])[0, 1] > 0 else -1
    print('iris uv orientation', su, sv)

    def wq(v):  # q in world-ish orientation: +x = Blender +x, +y = up
        qx, qy = q_of(v)
        return qx * su, qy * sv

    def eyef(*names):
        idx = {slot(n) for n in names}
        return [f for f in bm.faces if f.material_index in idx]

    cut(iris_faces, lambda v: 1.0 - math.hypot(*q_of(v)), 'iris', delete_outside=True)
    cut(eyef('iris'), lambda v: math.hypot(*q_of(v)) - 0.84, 'iris_dark')
    cut(eyef('iris'), lambda v: wq(v)[1] - 0.30 + 0.35 * wq(v)[0] ** 2, 'iris_dark')
    cut(eyef('iris'), lambda v: -0.42 - wq(v)[1] + 0.5 * wq(v)[0] ** 2, 'iris_light')
    cut(eyef('iris', 'iris_dark', 'iris_light'), lambda v: 0.40 - math.hypot(wq(v)[0] / 0.85, wq(v)[1]), 'pupil')
    # highlights: a big one on the light side (world -x, up) and a small one opposite, below
    cut(eyef('iris', 'iris_dark', 'iris_light', 'pupil'),
        lambda v: 0.26 - math.hypot(wq(v)[0] + 0.40, (wq(v)[1] - 0.42) * 1.15), 'eye_hi')
    cut(eyef('iris', 'iris_dark', 'iris_light', 'pupil'),
        lambda v: 0.11 - math.hypot(wq(v)[0] - 0.38, wq(v)[1] + 0.45), 'eye_hi')
    bmesh.ops.delete(bm, geom=faces_mat(mi('EyeHighlight')), context='FACES')

    # eye whites --------------------------------------------------------
    ew = faces_mat(mi('EyeWhite'))
    for f in ew:
        f.material_index = slot('eye_white')
    U.subdivide_faces(bm, ew, 1)
    ew = faces_mat(slot('eye_white'))
    def lid_shadow(v):
        c = eyeL if v.co.x > 0 else eyeR
        return (v.co.z - c.z) - 0.0085 + 12.0 * (v.co.x - c.x) ** 2
    cut(ew, lid_shadow, 'eye_shadow')

    # lashes and brows: iso-contours of the (thickened) texture alpha ------
    def alpha_mask(image, grow, blur):
        a = U.Image2D(image).px[..., 3].copy()
        g = a.copy()
        for dy in range(-grow, grow + 1):
            for dx in range(-grow, grow + 1):
                if dx * dx + dy * dy <= grow * grow and (dx or dy):
                    g = np.maximum(g, np.roll(np.roll(a, dy, 0), dx, 1))
        for _ in range(blur):
            g = (g + np.roll(g, 1, 0) + np.roll(g, -1, 0) + np.roll(g, 1, 1) + np.roll(g, -1, 1)) / 5
        return g

    class Arr:
        def __init__(s, a): s.a = a; s.h, s.w = a.shape
        def sample(s, u, v):
            x = min(max(u * s.w - 0.5, 0), s.w - 1.001); y = min(max(v * s.h - 0.5, 0), s.h - 1.001)
            x0 = int(x); y0 = int(y); fx = x - x0; fy = y - y0
            a = s.a
            return float((a[y0, x0] * (1 - fx) + a[y0, x0 + 1] * fx) * (1 - fy) + (a[y0 + 1, x0] * (1 - fx) + a[y0 + 1, x0 + 1] * fx) * fy)

    for part, name, grow, cuts in (('FaceEyeline', 'lash', 5, 2), ('FaceBrow', 'brow', 4, 2)):
        i = mi(part)
        a = Arr(alpha_mask(images[mats[i]], grow, 6))
        fs = faces_mat(i)
        U.subdivide_faces(bm, fs, cuts)
        fs = faces_mat(i)
        cut(fs, lambda v: a.sample(uv_of(v).x, uv_of(v).y) - 0.5, name, delete_outside=True)
        # drop stray specks: keep only islands of a decent size
        fs = set(faces_mat(slot(name)))
        islands = []
        while fs:
            f0 = fs.pop(); isl = [f0]; stack = [f0]
            while stack:
                f = stack.pop()
                for e in f.edges:
                    for g in e.link_faces:
                        if g in fs:
                            fs.discard(g); isl.append(g); stack.append(g)
            islands.append(isl)
        areas = [sum(f.calc_area() for f in isl) for isl in islands]
        for isl, ar in zip(islands, areas):
            if ar < 0.2 * max(areas):
                bmesh.ops.delete(bm, geom=isl, context='FACES')

    # mouth interior: teeth / tongue / dark by texture region ----------------
    for f in faces_mat(mouth_i):
        u = sum((l[uvl].uv.x for l in f.loops)) / len(f.loops)
        v = sum((l[uvl].uv.y for l in f.loops)) / len(f.loops)
        if u < 0.5 and v > 0.5:
            f.material_index = slot('teeth')
        elif u >= 0.5 and v > 0.5 and (u - 0.5) < 0.32 and abs(v - 0.68) < 0.16:
            f.material_index = slot('tongue')
        else:
            f.material_index = slot('mouth_in')

    # skin + face paint ---------------------------------------------------
    skin_i = mi('Face_00_SKIN')
    for f in faces_mat(skin_i):
        f.material_index = slot('skin')

    def seg_field(a, b, r):
        a = Vector(a); b = Vector(b); ab = b - a
        def f(v):
            p = Vector((v.co.x, v.co.z))
            t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
            return r - (p - (a + ab * t)).length
        return f

    def paint(strokes, matname, r):
        cs = [(Vector(a) + Vector(b)) / 2 for a, b in strokes]
        def near(rad):
            out = []
            for f in faces_mat(slot('skin')):
                c = f.calc_center_median()
                if c.y < eyeL.y + 0.03 and any((Vector((c.x, c.z)) - k).length < rad for k in cs):
                    out.append(f)
            return out
        U.subdivide_faces(bm, near(0.016), 2)
        for a, b in strokes:
            cut(near(0.03), seg_field(a, b, r), matname)

    ex, ez = eyeL.x, eyeL.z
    # two cream paint slashes under her right eye (viewer's left), as in R01
    paint([((-ex - 0.020, ez - 0.030), (-ex + 0.002, ez - 0.040)),
           ((-ex - 0.018, ez - 0.040), (-ex + 0.004, ez - 0.050))], 'paint_white', 0.0034)
    # small red scuff marks on the other cheek
    paint([((ex + 0.004, ez - 0.036), (ex + 0.013, ez - 0.031)),
           ((ex + 0.008, ez - 0.043), (ex + 0.017, ez - 0.038))], 'paint_red', 0.0016)

    bm.to_mesh(me); bm.free()

    # ---- materials: drop the textured originals
    used = sorted({p.material_index for p in me.polygons})
    U.active(face)
    bpy.ops.object.material_slot_remove_unused()
    # body: flat skin (scalp cap is handled by the hair stage)
    for i, m in enumerate(body.data.materials):
        if 'Body_00_SKIN' in m.name:
            body.data.materials[i] = U.mat('skin')
    me.update()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(U.WORK, OUT))
    print('S2 OK face tris', sum(len(p.vertices) - 2 for p in me.polygons), [m.name for m in me.materials])


if __name__ == '__main__':
    main()
