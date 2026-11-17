"""Stage 3 - Moxie's hair, modelled as flowing tapered strand clumps: hair pulled back over the
skull into two high scrappy pigtails, messy bangs, side locks, loose wisps, red hair ties.
Adds the pigtail secondary-motion bones. Reads work/s2.blend, saves work/s3.blend.
"""
import bpy, bmesh, sys, os, math, random
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_util as U
import mxa_build as MBm
from mxa_build import MB, catmull, resample

C = Vector((0, 0.03, 1.47))                      # head centre used for the polar hair coordinates
SECTION = [(-1, 0), (-0.62, 0.6), (0, 1.0), (0.62, 0.6), (1, 0), (0, -0.28)]
PIG_AZ, PIG_EL = 122, 50                         # pigtail root on the skull (degrees)
PIG_LEN = 0.24
HEAD = {'Head': 1.0}


def D(az, el):
    a = math.radians(az); e = math.radians(el)
    return Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))


def main():
    random.seed(7)
    bpy.ops.wm.open_mainfile(filepath=os.path.join(U.WORK, 's2.blend'))
    face = bpy.data.objects['Face']; body = bpy.data.objects['Body']; rig = bpy.data.objects['Rig']

    # ---- scalp cap: cut the painted hairline into the mesh, flat hair colour
    capi = [i for i, m in enumerate(body.data.materials) if 'Hair' in m.name][0]
    img = [n.image for n in body.data.materials[capi].node_tree.nodes if n.type == 'TEX_IMAGE' and n.outputs[0].links][0]
    im = U.Image2D(img)
    bm = bmesh.new(); bm.from_mesh(body.data)
    uvl = bm.loops.layers.uv.active
    fs = [f for f in bm.faces if f.material_index == capi]
    U.subdivide_faces(bm, fs, 1)
    fs = [f for f in bm.faces if f.material_index == capi]
    ins, outs = U.split_by_field(bm, fs, lambda v: im.sample(v.link_loops[0][uvl].uv.x, v.link_loops[0][uvl].uv.y) - 0.5)
    bmesh.ops.delete(bm, geom=outs, context='FACES')
    bm.to_mesh(body.data); bm.free()
    body.data.materials[capi] = U.mat('hair')

    # ---- head surface for ray-cast placement
    tris = []; verts = []
    for ob in (face, body):
        base = len(verts)
        me = ob.data
        ok = [v.co.z > 1.30 for v in me.vertices]
        verts += [v.co.copy() for v in me.vertices]
        me.calc_loop_triangles()
        for t in me.loop_triangles:
            if all(ok[i] for i in t.vertices):
                tris.append(tuple(base + i for i in t.vertices))
    bvh = BVHTree.FromPolygons(verts, tris)

    def surf(az, el, off=0.0):
        d = D(az, el)
        hit = bvh.ray_cast(C + d * 0.6, -d, 0.58)
        if hit[0] is None:
            p = C + Vector((d.x * 0.097, d.y * 0.108, d.z * 0.115))
        else:
            p = hit[0]
        return p + d * off

    mb = MB()

    def clump(ctrl, w, thick=0.35, m='hair', weights=HEAD, n=10, centre=C, profile='blade', wfn=None, up=None):
        pts = resample(catmull(ctrl, 48), n)

        def width(t):
            if profile == 'blade':      # tucked root, full by 25%, long taper to a point
                f = (t / 0.22) ** 0.7 if t < 0.22 else max(0.03, 1 - ((t - 0.22) / 0.78) ** 1.8)
            elif profile == 'pulled':   # hairline -> tie: swells then narrows, never to a point
                f = (0.35 + 0.65 * math.sin(math.pi * min(1, t / 0.5) / 2)) * (1 - 0.55 * max(0, t - 0.5) / 0.5)
            else:                       # spike: widest at the root
                f = max(0.03, (1 - t) ** 0.8) * (0.6 + 0.4 * min(1, t / 0.1))
            return (w / 2 * f, w * thick * (0.55 + 0.45 * f) * (f ** 0.5))
        upf = up or (lambda i, p: p - centre)
        mb.strip(pts, SECTION, m, wfn or weights, up=upf, width=width)

    def polar_path(a0, e0, a1, e1, off0, offm, off1, k=5):
        """Great-arc path on the head between two polar positions, lifted by a sine bump."""
        d0, d1 = D(a0, e0), D(a1, e1)
        q = d0.rotation_difference(d1)
        out = []
        for i in range(k + 1):
            t = i / k
            d = Quaternion().slerp(q, t) @ d0
            el = math.degrees(math.asin(max(-1, min(1, d.z)))); az = math.degrees(math.atan2(d.x, -d.y))
            off = off0 + (off1 - off0) * t + offm * math.sin(math.pi * t)
            out.append(surf(az, el, off))
        return out

    for side in (1, -1):
        s = side
        pa = PIG_AZ * s
        # ---- hair pulled over the skull into the tie
        starts = [(3, 44), (20, 42), (40, 38), (60, 31), (78, 22), (92, 10), (104, -2), (124, -14), (144, -24),
                  (162, -31), (177, -35),
                  (4, 60), (5, 78), (176, 84), (176, 66), (176, 46), (177, 22), (178, -6)]
        for i, (a, e) in enumerate(starts):
            a = a + random.uniform(-3, 3); e = e + random.uniform(-2, 2)
            path = polar_path(a * s, e, pa, PIG_EL, 0.004, 0.012, 0.016)
            clump(path, random.uniform(0.050, 0.064), 0.22, profile='pulled', n=7,
                  m='hair_hi' if i in (3, 13) else 'hair')
        # ---- side lock in front of the ear
        clump([surf(74 * s, 44, 0.006), surf(80 * s, 22, 0.02), surf(80 * s, -4, 0.022), surf(74 * s, -30, 0.02),
               surf(66 * s, -50, 0.03) + Vector((0.01 * s, -0.004, 0))], 0.034, 0.4, n=12)
        clump([surf(88 * s, 36, 0.006), surf(92 * s, 12, 0.022), surf(88 * s, -14, 0.03), surf(84 * s, -34, 0.036)],
              0.026, 0.4, n=10)

    # ---- bangs: (root az, tip az, tip el, width, lift) - asymmetric and messy on purpose
    bangs = [(-4, 4, -13, 0.036, 0.030), (-12, -12, 8, 0.030, 0.034), (-22, -25, 2, 0.044, 0.030),
             (-38, -50, -8, 0.044, 0.028), (-54, -68, -30, 0.040, 0.024), (-30, -36, 14, 0.028, 0.036),
             (12, 18, 6, 0.044, 0.032), (26, 38, 0, 0.046, 0.030), (44, 58, -14, 0.042, 0.026),
             (58, 72, -34, 0.036, 0.024), (20, 27, 16, 0.028, 0.038), (4, 9, 14, 0.026, 0.040)]
    for i, (a0, a1, e1, w, lift) in enumerate(bangs):
        e0 = random.uniform(66, 76)
        am = a0 * 0.4 + a1 * 0.6
        path = [surf(a0 * 0.8, e0 + 8, 0.004), surf(a0, e0 - 8, 0.016), surf(am, 36, lift), surf(a1, (36 + e1) / 2, lift * 0.9),
                surf(a1 + (4 if a1 > 0 else -4), e1, 0.020), surf(a1 + (9 if a1 > 0 else -9), e1 - 7, 0.034)]
        clump(path, w, 0.42, n=10, m='hair_hi' if i in (5,) else 'hair')

    # ---- loose wisps on the crown
    for k in range(9):
        a = random.uniform(-150, 150); e = random.uniform(58, 84)
        p0 = surf(a, e, 0.002)
        d = (D(a, e) + Vector((random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), 0.5))).normalized()
        L = random.uniform(0.05, 0.085)
        bend = Vector((random.uniform(-1, 1), random.uniform(-1, 1), -0.3)) * 0.02
        clump([p0, p0 + d * L * 0.4, p0 + d * L * 0.75 + bend * 0.5, p0 + d * L + bend], random.uniform(0.012, 0.018), 0.5,
              profile='spike', n=6)

    # ---- pigtails
    for side, S in ((1, 'L'), (-1, 'R')):
        base = surf(PIG_AZ * side, PIG_EL, 0.010)
        A = Vector((0.80 * side, 0.30, 0.52)).normalized()
        # bone chain (droops a little along its length)
        bp = [base]
        d = A.copy()
        for i in range(3):
            bp.append(bp[-1] + d * (PIG_LEN / 3))
            d = (d + Vector((0.12 * side, 0.05, -0.42))).normalized()
        names = ['Pigtail%s%d' % (S, i + 1) for i in range(3)]
        for i, nme in enumerate(names):
            MBm.add_bone(rig, nme, bp[i], bp[i + 1], 'Head' if i == 0 else names[i - 1])

        def wfn(t, p, base=base, names=names):
            tt = max(0.0, min(1.0, (p - base).length / PIG_LEN))
            return MBm.chain_weights(tt, names, root='Head', root_blend=0.10)

        def axis_point(p, base=base, bp=bp):
            # nearest point on the bone polyline
            best = None
            for a, b in zip(bp, bp[1:]):
                ab = b - a
                t = max(0, min(1, (p - a).dot(ab) / ab.length_squared))
                q = a + ab * t
                if best is None or (p - q).length < (p - best).length:
                    best = q
            return best
        K = 15
        for k in range(K):
            # spread the clump directions in a cone around the axis
            ang = 2 * math.pi * k / K + random.uniform(-0.2, 0.2)
            cone = random.uniform(0.3, 0.95) if k else 0.0
            ortho1 = A.cross(Vector((0, 0, 1))).normalized(); ortho2 = A.cross(ortho1)
            radial = ortho1 * math.cos(ang) + ortho2 * math.sin(ang)
            d = (A + radial * cone).normalized()
            L = random.uniform(0.17, 0.27) * (1.0 if radial.z < 0.3 else 0.8)
            steps = 7
            p = base - A * 0.012 + radial * 0.006
            ctrl = [p.copy()]
            for i in range(steps):
                t = (i + 1) / steps
                g = 0.62 * t ** 1.2
                flick = 0.0 if t < 0.70 else 0.75 * (t - 0.70) / 0.30
                d = (d + Vector((0, 0, -1)) * g + (radial * 0.8 + Vector((side * 0.5, 0, 0.9))) * flick
                     + Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))) * 0.07).normalized()
                p = p + d * (L / steps)
                ctrl.append(p.copy())
            clump(ctrl, random.uniform(0.050, 0.076), 0.46, n=11, wfn=wfn,
                  up=lambda i, p, ap=axis_point, r=radial: (p - ap(p)) + r * 0.02,
                  m='hair_hi' if k % 6 == 3 else 'hair')
        # thin flyaways
        for k in range(6):
            d = (A + Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.6, 1))) * 0.7).normalized()
            L = random.uniform(0.10, 0.18)
            p0 = base + A * 0.02
            bend = Vector((random.uniform(-1, 1), random.uniform(-1, 1), -1.0)) * L * 0.25
            clump([p0, p0 + d * L * 0.4, p0 + d * L * 0.75 + bend * 0.4, p0 + d * L + bend], random.uniform(0.012, 0.018),
                  0.5, profile='spike', n=7, wfn=wfn)
        # hair tie: a chunky red band around the root
        o1 = A.cross(Vector((0, 0, 1))).normalized(); o2 = A.cross(o1)
        circ = [base + A * 0.012 + (o1 * math.cos(2 * math.pi * i / 14) + o2 * math.sin(2 * math.pi * i / 14)) * 0.027
                for i in range(15)]
        rings = mb.tube(circ[:-1], 0.0085, 'hair_tie', HEAD, sides=6, up=lambda i, p, b=base: p - b, cap0=False, cap1=False)
        mb.loft([rings[-1], rings[0]], 'hair_tie')

    hair = mb.build('Hair')
    hair.parent = rig
    md = hair.modifiers.new('Armature', 'ARMATURE'); md.object = rig
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(U.WORK, 's3.blend'))
    print('S3 OK hair tris', sum(len(p.vertices) - 2 for p in hair.data.polygons))


if __name__ == '__main__':
    main()
