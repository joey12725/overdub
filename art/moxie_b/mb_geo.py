"""Small hard-surface / sweep toolkit on top of bmesh, used for gear and garment trims."""
import bpy, bmesh, math
from mathutils import Vector, Matrix
import mb_util as U


class Builder:
    """Accumulates geometry in one bmesh with named material slots; finish() makes the object."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.bone = self.bm.faces.layers.int.new("rigid_bone")   # index into self.bones (rigid skinning hint)
        self.bones = [""]
        self.cur_bone = 0

    def set_bone(self, name):
        if name not in self.bones:
            self.bones.append(name)
        self.cur_bone = self.bones.index(name)

    def mat(self, name, color=None, emit=0.0):
        m = U.mat(name, color, emit=emit)
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _tag(self, faces, mi, smooth=True):
        for f in faces:
            f.material_index = mi
            f.smooth = smooth
            f[self.bone] = self.cur_bone

    # ---- sweeps
    def tube(self, pts, radius, mi, sides=8, closed=False, caps=True, flat=1.0, up=None, smooth=True, twist0=0.0):
        """Sweep a circle (optionally flattened along `up`) along pts. radius: float or f(t)."""
        n = len(pts)
        rings = []
        prev_n = None
        for i, p in enumerate(pts):
            if closed:
                tan = (pts[(i + 1) % n] - pts[(i - 1) % n]).normalized()
            else:
                tan = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            if up is not None:
                ref = up[i] if isinstance(up, (list, tuple)) else up
            elif prev_n is not None:
                ref = prev_n
            else:
                ref = tan.orthogonal()
            nn = ref - tan * ref.dot(tan)
            if nn.length < 1e-6:
                nn = tan.orthogonal()
            nn.normalize()
            prev_n = nn
            b = tan.cross(nn).normalized()
            t = i / (n - 1) if n > 1 else 0
            r = radius(t) if callable(radius) else radius
            ring = []
            for j in range(sides):
                a = 2 * math.pi * j / sides + twist0
                ring.append(self.bm.verts.new(p + b * (math.cos(a) * r) + nn * (math.sin(a) * r * flat)))
            rings.append(ring)
        faces = []
        m = n if closed else n - 1
        for i in range(m):
            r0, r1 = rings[i], rings[(i + 1) % n]
            for j in range(sides):
                j2 = (j + 1) % sides
                faces.append(self.bm.faces.new((r0[j], r0[j2], r1[j2], r1[j])))
        if caps and not closed:
            faces.append(self.bm.faces.new(rings[0][::-1]))
            faces.append(self.bm.faces.new(rings[-1]))
        self._tag(faces, mi, smooth)
        return rings

    def ribbon(self, pts, normals, width, thick, mi, closed=False, mi_in=None):
        """Flat strap: rectangular section, `normals` point away from the body."""
        n = len(pts)
        rings = []
        for i, p in enumerate(pts):
            if closed:
                tan = (pts[(i + 1) % n] - pts[(i - 1) % n]).normalized()
            else:
                tan = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            nn = normals[i] if isinstance(normals, (list, tuple)) else normals
            nn = (nn - tan * nn.dot(tan)).normalized()
            b = tan.cross(nn).normalized()
            w = width(i / max(n - 1, 1)) if callable(width) else width
            rings.append([self.bm.verts.new(p + b * (w / 2) + nn * thick), self.bm.verts.new(p - b * (w / 2) + nn * thick),
                          self.bm.verts.new(p - b * (w / 2)), self.bm.verts.new(p + b * (w / 2))])
        m = n if closed else n - 1
        for i in range(m):
            r0, r1 = rings[i], rings[(i + 1) % n]
            for j in range(4):
                j2 = (j + 1) % 4
                f = self.bm.faces.new((r0[j], r0[j2], r1[j2], r1[j]))
                self._tag([f], mi_in if (mi_in is not None and j == 2) else mi, smooth=False)
        if not closed:
            self._tag([self.bm.faces.new(rings[0][::-1]), self.bm.faces.new(rings[-1])], mi, smooth=False)
        return rings

    # ---- primitives (matrix places a unit shape)
    def box(self, mtx, size, mi, bevel=0.004, segs=2):
        ret = bmesh.ops.create_cube(self.bm, size=1.0)
        vs = ret["verts"]
        for v in vs:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        faces = list({f for v in vs for f in v.link_faces})
        if bevel > 0:
            edges = list({e for v in vs for e in v.link_edges})
            r = bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=segs, affect='EDGES', profile=0.5)
            faces = list({f for f in r["faces"]} | {f for v in r["verts"] for f in v.link_faces})
            vs = list({v for f in faces for v in f.verts})
        for v in vs:
            v.co = mtx @ v.co
        self._tag(faces, mi, smooth=False)
        return faces

    def cyl(self, mtx, r, h, mi, sides=16, bevel=0.0, r2=None, smooth=True):
        """Cylinder along local Z, centred. r2 = top radius (cone) if given."""
        r2 = r if r2 is None else r2
        prof = []
        if bevel > 0:
            prof = [(r - bevel, -h / 2), (r, -h / 2 + bevel), (r2, h / 2 - bevel), (r2 - bevel, h / 2)]
        else:
            prof = [(r, -h / 2), (r2, h / 2)]
        rings = []
        for (rr, z) in prof:
            rings.append([self.bm.verts.new(mtx @ Vector((rr * math.cos(2 * math.pi * j / sides), rr * math.sin(2 * math.pi * j / sides), z))) for j in range(sides)])
        faces = []
        for i in range(len(rings) - 1):
            for j in range(sides):
                j2 = (j + 1) % sides
                faces.append(self.bm.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j])))
        self._tag(faces, mi, smooth)
        capf = [self.bm.faces.new(rings[0][::-1]), self.bm.faces.new(rings[-1])]
        self._tag(capf, mi, smooth=False)
        return faces + capf

    def torus(self, mtx, R, r, mi, seg=24, sub=8, flat=1.0, arc=1.0):
        rings = []
        n = seg if arc >= 1.0 else seg + 1
        for i in range(n):
            a = 2 * math.pi * arc * i / seg
            rings.append([self.bm.verts.new(mtx @ Vector(((R + r * math.cos(2 * math.pi * j / sub)) * math.cos(a),
                                                          (R + r * math.cos(2 * math.pi * j / sub)) * math.sin(a),
                                                          r * flat * math.sin(2 * math.pi * j / sub)))) for j in range(sub)])
        faces = []
        m = seg
        for i in range(m):
            r0, r1 = rings[i], rings[(i + 1) % n]
            for j in range(sub):
                j2 = (j + 1) % sub
                faces.append(self.bm.faces.new((r0[j], r0[j2], r1[j2], r1[j])))
        if arc < 1.0:
            faces += [self.bm.faces.new(rings[0][::-1]), self.bm.faces.new(rings[-1])]
        self._tag(faces, mi)
        return faces

    def poly(self, pts, mi, thick=0.0, normal=None):
        """Flat polygon decal (optionally extruded by `thick` along its normal)."""
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        faces = [f]
        if thick:
            f.normal_update()
            nn = normal or f.normal
            r = bmesh.ops.extrude_face_region(self.bm, geom=[f])
            nv = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
            for v in nv:
                v.co += nn * thick
            faces = list({ff for v in nv + vs for ff in v.link_faces})
        self._tag(faces, mi, smooth=False)
        return faces

    def finish(self, recalc=True):
        if recalc:
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        o = U.new_obj(self.name, me)
        o["rigid_bones"] = self.bones
        return o


def place(origin, z_axis, x_hint=Vector((1, 0, 0))):
    """Matrix with local Z along z_axis and local X as close to x_hint as possible."""
    z = Vector(z_axis).normalized()
    x = Vector(x_hint) - z * Vector(x_hint).dot(z)
    if x.length < 1e-6:
        x = z.orthogonal()
    x.normalize()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


def smooth_path(pts, n):
    from mb_hair import catmull
    return catmull([Vector(p) for p in pts], n)
