"""Stage 4 - clothing built on the body so it inherits the skin weights: cropped tank top with dark
trim, baggy low-rise cargo pants (folds, gathered cuffs, zig-zag graphic, torn knee), fingerless
gloves, chunky high-top boots. Hidden skin is removed so nothing can poke through.
Reads work/s3.blend, saves work/s4.blend.
"""
import bpy, bmesh, sys, os, math, random
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_util as U
import mxa_cloth as CL
from mxa_build import MB, catmull, resample

U.PALETTE['knee_skin'] = U.PALETTE['skin']


def sstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def lerp_table(tab, x):
    """Piecewise-linear lookup in a table sorted by descending or ascending key."""
    tab = sorted(tab)
    if x <= tab[0][0]:
        return tab[0][1]
    for (a, va), (b, vb) in zip(tab, tab[1:]):
        if x <= b:
            return va + (vb - va) * (x - a) / (b - a)
    return tab[-1][1]


# ------------------------------------------------------------------ top
def top_field(co):
    x = abs(co.x); z = co.z
    front = co.y < 0.0
    hem = z - (1.090 + (0.012 if not front else 0.0) - 0.10 * x * (1 if front else 0))
    zn = (1.212 + 15.0 * x * x) if front else (1.236 + 10.0 * x * x)
    neck = zn - z
    xa = 0.086 if z > 1.205 else 0.086 + (1.205 - z) * 2.2
    arm = xa - x
    return min(hem, neck * 0.7, arm)


def make_top(body, mb):
    top = CL.shell_from(body, 'Top', lambda co: 1.03 < co.z < 1.36 and abs(co.x) < 0.22, 'top')
    CL.displace(top, lambda co, n: co + n * 0.0065)
    bm = bmesh.new(); bm.from_mesh(top.data)
    U.subdivide_faces(bm, list(bm.faces), 1)
    bm.to_mesh(top.data); bm.free()
    CL.cut_object(top, top_field)
    CL.smooth_verts(top, 2, 0.5)
    # chest graphic (dark four-point star, as on R01) cut into the cloth
    def star(co):
        if co.y > -0.02:
            return -1
        dx = abs(co.x - 0.0) / 0.030; dz = abs(co.z - 1.150) / 0.036
        return 1.0 - (dx ** 0.6 + dz ** 0.6) ** (1 / 0.6)
    CL.cut_object(top, star, delete_outside=False, inside_mat='top_trim')
    for loop in CL.border_loops(top):
        CL.trim_loop(mb, top, loop, 0.0055, 'top_trim', sides=6, scale_y=1.5, push=0.001, min_len=0.006)
    CL.delete_faces(body, lambda c: top_field(c) > 0.014 and 1.0 < c.z < 1.4)
    return top


# ------------------------------------------------------------------ pants
HIP = Vector((0.077, 0.0, 0.854)); KNEE = Vector((0.077, 0.007, 0.501)); ANKLE = Vector((0.077, 0.032, 0.086))
PANTS_R = [(0.88, 0.080), (0.80, 0.094), (0.72, 0.106), (0.60, 0.114), (0.50, 0.120), (0.38, 0.128), (0.27, 0.126),
           (0.20, 0.108), (0.155, 0.078), (0.125, 0.066), (0.09, 0.064)]
PANTS_OUT = 0.014   # the cloth hangs a little outward of the leg axis


def leg_axis(z, side):
    if z > KNEE.z:
        t = (HIP.z - z) / (HIP.z - KNEE.z); p = HIP.lerp(KNEE, max(0, t))
    else:
        t = (KNEE.z - z) / (KNEE.z - ANKLE.z); p = KNEE.lerp(ANKLE, min(1.2, t))
    return Vector(((p.x + PANTS_OUT * sstep(0.9, 0.6, z)) * side, p.y, z))


def waist_z(co):
    return 0.925 + 0.20 * co.y


def make_pants(body, mb):
    pants = CL.shell_from(body, 'Pants', lambda co: 0.06 < co.z < 1.0 and abs(co.x) < 0.25, 'pants')

    def inflate(co, n):
        z = co.z; side = 1 if co.x >= 0 else -1
        p_off = co + n * 0.013
        ax = leg_axis(z, side)
        r = Vector((co.x - ax.x, co.y - ax.y))
        rb = r.length
        d = r / max(rb, 1e-6)
        R = lerp_table(PANTS_R, z)
        nr = max(rb + 0.012, R * (1.0 + 0.10 * max(0.0, d.y)))   # a bit fuller at the back
        p_leg = Vector((ax.x + d.x * nr, ax.y + d.y * nr, z))
        if p_leg.x * side < 0.006:
            p_leg.x = 0.006 * side
        t = sstep(0.90, 0.70, z)
        return p_off.lerp(p_leg, t)
    CL.subsurf(pants, 1)       # subdivide first so every vertex lands exactly on the cloth profile
    CL.displace(pants, inflate)
    CL.cut_object(pants, lambda co: min(waist_z(co) - co.z, co.z - 0.100))
    CL.smooth_verts(pants, 2, 0.5)

    def folds(co, n):
        z = co.z; side = 1 if co.x >= 0 else -1
        ax = leg_axis(z, side)
        r = Vector((co.x - ax.x, co.y - ax.y))
        if r.length < 1e-6 or z > 0.90:
            return co
        d = r.normalized(); th = math.atan2(d.y, d.x * side)
        a = 0.0
        k = math.exp(-((z - 0.50) / 0.11) ** 2)
        a += 0.0080 * k * math.sin(34 * z + 2.0 * math.sin(th * 2 + side) + th)
        a += 0.0050 * sstep(0.22, 0.34, z) * sstep(0.88, 0.74, z) * math.sin(14 * z + 2 * th + 1.7 * side)
        a += 0.0025 * sstep(0.9, 0.8, z) * math.sin(3 * th + 18 * z)
        s = sstep(0.40, 0.24, z) * sstep(0.105, 0.14, z)
        a += 0.012 * s * math.sin(52 * z + 1.2 * math.sin(2 * th + side) + 0.5 * th)
        a *= sstep(0.0, 0.02, abs(co.x))      # calm at the inner seam
        return Vector((co.x + d.x * a, co.y + d.y * a, z))
    CL.displace(pants, folds)

    # graphics, cut into the cloth: zig-zag on her right shin, torn knee on her left, small tear right thigh
    def polar(co):
        side = 1 if co.x >= 0 else -1
        ax = leg_axis(co.z, side)
        return side, math.degrees(math.atan2(co.y - ax.y, (co.x - ax.x))), co.z

    zig = [(-78, 0.52), (-128, 0.43), (-80, 0.365), (-128, 0.275), (-84, 0.20)]

    def zig_field(co):
        side, th, z = polar(co)
        if side > 0 or not (0.17 < z < 0.54):
            return -1
        if th > 0:
            th -= 360
        p = Vector((math.radians(th) * 0.12, z))
        best = 9
        for (a0, z0), (a1, z1) in zip(zig, zig[1:]):
            a = Vector((math.radians(a0) * 0.12, z0)); b = Vector((math.radians(a1) * 0.12, z1))
            t = max(0, min(1, (p - a).dot(b - a) / (b - a).length_squared))
            best = min(best, (p - (a + (b - a) * t)).length)
        return 0.024 - best
    bm = bmesh.new(); bm.from_mesh(pants.data)
    near = [f for f in bm.faces if f.calc_center_median().x < -0.01 and 0.15 < f.calc_center_median().z < 0.56
            and f.calc_center_median().y < 0.06]
    U.subdivide_faces(bm, near, 1)
    bm.to_mesh(pants.data); bm.free()
    CL.cut_object(pants, zig_field, delete_outside=False, inside_mat='pants_zig')

    def tear(side_want, th0, z0, ra, rz, seed):
        def f(co):
            side, th, z = polar(co)
            if side != side_want:
                return -1
            du = math.radians(th - th0) * 0.12 / ra; dz = (z - z0) / rz
            ang = math.atan2(dz, du)
            return 1 - math.hypot(du, dz) * (1 + 0.22 * math.sin(7 * ang + seed) + 0.1 * math.sin(13 * ang))
        return f
    CL.cut_object(pants, tear(1, -80, 0.515, 0.040, 0.022, 0.5), delete_outside=False, inside_mat='knee_skin')
    CL.cut_object(pants, tear(-1, -70, 0.66, 0.022, 0.012, 2.0), delete_outside=False, inside_mat='knee_skin')

    for loop in CL.border_loops(pants):
        zc = sum(pants.data.vertices[i].co.z for i in loop) / len(loop)
        if zc > 0.5:
            CL.trim_loop(mb, pants, loop, 0.0085, 'pants_dark', sides=6, scale_y=1.9, push=0.002, min_len=0.012)
        else:
            CL.trim_loop(mb, pants, loop, 0.011, 'pants_dark', sides=6, scale_y=1.5, push=0.004, min_len=0.012)
    CL.delete_faces(body, lambda c: c.z < waist_z(c) - 0.012 and c.z < 1.0)
    return pants


# ------------------------------------------------------------------ gloves
def make_gloves(body, mb):
    names = [g.name for g in body.vertex_groups]
    dom = {}
    for v in body.data.vertices:
        if v.groups:
            g = max(v.groups, key=lambda g: g.weight)
            dom[v.index] = names[g.group]
    idx = {}
    for i, v in enumerate(body.data.vertices):
        idx[(round(v.co.x, 6), round(v.co.y, 6), round(v.co.z, 6))] = i

    def keep(co):
        if abs(co.x) < 0.505:
            return False
        d = dom.get(idx.get((round(co.x, 6), round(co.y, 6), round(co.z, 6)), -1), '')
        if 'Distal' in d or 'Intermediate' in d:
            return False
        if 'ThumbProximal' in d and abs(co.x) > 0.592:
            return False
        return True
    gl = CL.shell_from(body, 'Gloves', keep, 'glove')
    CL.displace(gl, lambda co, n: co + n * 0.0032)
    CL.cut_object(gl, lambda co: min(abs(co.x) - 0.512, 0.6315 - abs(co.x)))
    for loop in CL.border_loops(gl):
        CL.trim_loop(mb, gl, loop, 0.0028, 'glove', sides=5, push=0.0005, min_len=0.004)
    # knuckle plate
    return gl


# ------------------------------------------------------------------ boots
SOLE = 0.036


def make_boots(ref, ws, mb):
    fv = [v.co for v in ref.data.vertices if v.co.z < 0.06 and v.co.x > 0]
    y_toe = min(v.y for v in fv); y_heel = max(v.y for v in fv)
    xc = (min(v.x for v in fv) + max(v.x for v in fv)) / 2
    print('foot', y_toe, y_heel, xc)
    y_toe -= 0.020; y_heel += 0.016
    L = y_heel - y_toe
    for side, S in ((1, 'Left'), (-1, 'Right')):
        FOOT = {S + 'Foot': 1.0}; TOES = {S + 'Toes': 1.0}
        toe_y = -0.078

        def wfoot(y):
            k = sstep(toe_y + 0.02, toe_y - 0.02, y)
            return {S + 'Foot': 1 - k, S + 'Toes': k} if 0 < k < 1 else (TOES if k >= 1 else FOOT)

        def halfw(t):   # t: 0 heel .. 1 toe
            return lerp_table([(0, 0.030), (0.06, 0.043), (0.3, 0.047), (0.62, 0.056), (0.82, 0.055), (0.94, 0.043), (1.0, 0.024)], t)
        # --- sole: outline rings
        n = 14
        outline = []
        for i in range(n + 1):
            t = i / n
            outline.append((halfw(t), y_heel - L * t))
        def sole_ring(z, grow):
            pts = []
            for w, y in outline:
                pts.append(Vector((xc * side + (w + grow), y, z)))
            for w, y in reversed(outline[1:-1]):
                pts.append(Vector((xc * side - (w + grow), y, z)))
            # stretch the ends a little so the outline stays rounded
            pts[0].y += grow; pts[n].y -= grow
            return [mb.vert(p, wfoot(p.y)) for p in pts]
        zs = [(-SOLE, 0.000), (-SOLE + 0.004, 0.006), (-0.014, 0.008), (-0.010, 0.004), (0.0, 0.004), (0.004, 0.0)]
        rings = [sole_ring(z, g) for z, g in zs]
        mb.loft(rings[:3], 'shoes_sole', cap0=True)
        mb.loft(rings[2:4], 'shoes_dark')
        mb.loft(rings[3:], 'shoes_sole', cap1=True)
        # tread blocks
        for i in range(6):
            y = y_heel - L * (0.1 + 0.16 * i)
            mb.box(Vector((xc * side, y, -SOLE - 0.003)), Vector((halfw(0.1 + 0.16 * i) * 0.9, 0, 0)), Vector((0, 0.011, 0)),
                   Vector((0, 0, 0.004)), 'shoes_dark', wfoot(y), bevel=0.002)
        # --- upper: D-shaped sections from heel to toe
        m = 16
        up_rings = []
        mats = []
        for i in range(m + 1):
            t = i / m
            y = y_heel - 0.004 - (L - 0.010) * t
            w = halfw(t) * 0.97
            h = lerp_table([(0, 0.060), (0.08, 0.090), (0.3, 0.092), (0.5, 0.075), (0.66, 0.056), (0.85, 0.050), (0.95, 0.040), (1.0, 0.016)], t)
            sec = []
            for k in range(9):
                a = math.pi * k / 8
                sec.append(Vector((xc * side + math.cos(a) * w * side, y, 0.002 + math.sin(a) ** 0.8 * h)))
            up_rings.append([mb.vert(p, wfoot(p.y)) for p in sec])
        for i in range(m):
            t = (i + 0.5) / m
            mat = 'shoes_dark' if (t > 0.74 or t < 0.14) else 'shoes'
            mb.loft(up_rings[i:i + 2], mat, closed=False, flip=(side > 0))
        mb.face(up_rings[0] if side < 0 else up_rings[0][::-1], 'shoes_dark')
        mb.face(up_rings[-1][::-1] if side < 0 else up_rings[-1], 'shoes_dark')
        # --- shaft around the ankle
        ank = Vector((ANKLE.x * side, ANKLE.y, ANKLE.z))
        path = [Vector((ank.x, ank.y + 0.004, 0.035)), Vector((ank.x, ank.y + 0.002, 0.10)), Vector((ank.x, ank.y - 0.002, 0.17)),
                Vector((ank.x, ank.y - 0.004, 0.225))]
        path = resample(catmull(path, 20), 7)

        def wsh(t, p):
            w = ws.at(Vector((ank.x, ank.y, max(p.z, 0.05))), only=[S + 'Foot', S + 'LowerLeg'])
            return w or FOOT
        rr = mb.tube(path, lambda t: 0.052 + 0.004 * math.sin(math.pi * t) + 0.004 * t, 'shoes', wsh, sides=14,
                     up=Vector((0, -1, 0)), scale_y=1.22, cap0=False, cap1=True)
        # padded collar
        top = path[-1]
        circ = [top + Vector((math.cos(2 * math.pi * i / 14) * 0.056, math.sin(2 * math.pi * i / 14) * 0.068, 0)) for i in range(14)]
        rc = mb.tube(circ, 0.012, 'shoes_dark', wsh(1, top), sides=6, up=Vector((0, 0, 1)), cap0=False, cap1=False)
        mb.loft([rc[-1], rc[0]], 'shoes_dark')
        # tongue + laces up the front
        front = [Vector((ank.x, y_heel - L * 0.62, 0.060)), Vector((ank.x, ank.y - 0.058, 0.085)), Vector((ank.x, ank.y - 0.066, 0.13)),
                 Vector((ank.x, ank.y - 0.070, 0.19)), Vector((ank.x, ank.y - 0.076, 0.245))]
        fp = resample(catmull(front, 24), 8)
        mb.strip(fp, [(-1, 0), (-0.7, 0.8), (0, 1), (0.7, 0.8), (1, 0), (0, -0.6)], 'shoes', lambda t, p: wsh(t, p),
                 up=Vector((0, -1, 0.3)), width=lambda t: (0.026 + 0.004 * t, 0.012))
        for i in range(1, 6):
            c = fp[i] + Vector((0, -0.011, 0.002))
            a = c + Vector((0.027, 0.012, -0.007)); b = c + Vector((-0.027, 0.012, 0.007))
            a2 = c + Vector((0.027, 0.012, 0.007)); b2 = c + Vector((-0.027, 0.012, -0.007))
            mb.tube([a, c + Vector((0, -0.003, 0)), b], 0.0036, 'laces', wsh(i / 8, c), sides=5)
            mb.tube([a2, c + Vector((0, -0.004, 0)), b2], 0.0036, 'laces', wsh(i / 8, c), sides=5)
            for e in (a, b):
                mb.disc(e + Vector((0, 0.002, 0)), Vector((1, 0, 0)), Vector((0, 0, 1)), 0.0058, 'metal', wsh(i / 8, c), sides=8,
                        depth=Vector((0, -0.004, 0)))
        # bow
        c = fp[5] + Vector((0, -0.014, 0.010))
        for sx in (-1, 1):
            loop = [c, c + Vector((sx * 0.030, -0.006, 0.012)), c + Vector((sx * 0.040, -0.004, -0.004)), c + Vector((sx * 0.012, -0.002, -0.004)), c]
            mb.tube(resample(catmull(loop, 20), 8), 0.0034, 'laces', wsh(1, c), sides=5)
            tail = [c, c + Vector((sx * 0.016, -0.008, -0.024)), c + Vector((sx * 0.028, -0.004, -0.050))]
            mb.tube(resample(catmull(tail, 12), 5), 0.0032, 'laces', wsh(1, c), sides=5)
        # triangle tag on the outer side (R01) and a heel pull tab
        o = Vector((ank.x + side * 0.060, ank.y + 0.004, 0.165))
        tri = [o + Vector((0, 0, 0.022)), o + Vector((0, -0.020, -0.012)), o + Vector((0, 0.020, -0.012))]
        ia = [mb.vert(p, wsh(1, o)) for p in tri]
        mb.face(ia if side > 0 else ia[::-1], 'laces')
        mb.box(Vector((ank.x, ank.y + 0.072, 0.215)), Vector((0.009, 0, 0)), Vector((0, 0.004, 0)), Vector((0, 0, 0.028)),
               'laces', wsh(1, o), bevel=0.002)


def main():
    random.seed(11)
    bpy.ops.wm.open_mainfile(filepath=os.path.join(U.WORK, 's3.blend'))
    body = bpy.data.objects['Body']; rig = bpy.data.objects['Rig']
    # weights reference: the untouched body
    ref = body.copy(); ref.data = body.data.copy(); ref.name = 'BodyRef'
    bpy.context.scene.collection.objects.link(ref)
    ws = CL.WeightSampler(ref)
    mb = MB()
    top = make_top(body, mb)
    pants = make_pants(body, mb)
    gloves = make_gloves(body, mb)
    make_boots(ref, ws, mb)
    extra = mb.build('OutfitParts')
    for ob in (top, pants, gloves, extra):
        ob.parent = rig
        for m in list(ob.modifiers):
            ob.modifiers.remove(m)
        md = ob.modifiers.new('Armature', 'ARMATURE'); md.object = rig
    ref.hide_render = True; ref.hide_viewport = True
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(U.WORK, 's4.blend'))
    for ob in (body, top, pants, gloves, extra):
        print('S4', ob.name, sum(len(p.vertices) - 2 for p in ob.data.polygons))
    print('S4 OK')


if __name__ == '__main__':
    main()
