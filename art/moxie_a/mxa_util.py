"""Shared mesh / material / rig utilities for the Moxie-A build (Blender 4.5)."""
import bpy, bmesh, json, math, os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, 'work')
GEN = os.path.join(HERE, 'gen')
BLENDER_FRONT = Vector((0, -1, 0))  # the character faces -Y in Blender (= +Z in Godot)


def srgb(hexstr):
    h = hexstr.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)


# ---------------------------------------------------------------- palette (R01 wins over R02)
PALETTE = {
    'skin': '#B9764F', 'skin_blush': '#C4664C', 'paint_white': '#F3E9D8', 'paint_red': '#C8402F',
    'eye_white': '#F4EFE8', 'eye_shadow': '#C9B9B0', 'iris': '#E8A21C', 'iris_dark': '#9A5A12',
    'iris_light': '#FFD35A', 'pupil': '#2A1608', 'eye_hi': '#FFFFFF', 'lash': '#1E120E',
    'brow': '#2B1A14', 'mouth_in': '#7A2A2A', 'teeth': '#FBF6EC', 'tongue': '#D9706A',
    'hair': '#3B241C', 'hair_hi': '#5A3828', 'hair_tie': '#C8402F',
    'phones': '#F2B81B', 'phones_dark': '#2B2622', 'phones_pad': '#E9E2D2', 'phones_glow': '#FFE27A',
    'top': '#E9E0CF', 'top_trim': '#2A2422', 'strap': '#2A2422', 'buckle': '#B9B4AC',
    'jacket': '#2E2526', 'jacket_lining': '#F0B21C', 'jacket_trim': '#F0B21C', 'jacket_rib': '#1E1819',
    'pants': '#5E5A3A', 'pants_dark': '#4A472E', 'pants_zig': '#F0B21C', 'pants_patch': '#B9764F',
    'belt': '#2A2422', 'pouch': '#3A3530', 'metal': '#9A9690', 'walkman': '#F2B81B',
    'walkman_dark': '#2B2622', 'ribbon': '#C22A4E', 'vial_glow': '#58E6D6', 'screen_glow': '#58E6D6',
    'glove': '#27211F', 'wrist': '#3A3530', 'shoes': '#D9CDBB', 'shoes_dark': '#3A2B2B',
    'shoes_sole': '#CFC3AE', 'laces': '#F2B81B', 'choker': '#221C1B', 'ink': '#1F1412',
}


def mat(name, key=None, glow=False):
    """Flat base-colour material (the game swaps in its toon shader by material name)."""
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    col = srgb(PALETTE[key or (name if name in PALETTE else name.replace('_glow', ''))])
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*col, 1)
    bsdf.inputs['Roughness'].default_value = 0.9
    bsdf.inputs['Metallic'].default_value = 0.0
    if glow or name.endswith('_glow'):
        bsdf.inputs['Emission Color'].default_value = (*col, 1)
        bsdf.inputs['Emission Strength'].default_value = 2.0
    m.diffuse_color = (*col, 1)
    m.use_backface_culling = False
    return m


def mat_slot(obj, m):
    if isinstance(m, str):
        m = mat(m)
    for i, s in enumerate(obj.data.materials):
        if s == m:
            return i
    obj.data.materials.append(m)
    return len(obj.data.materials) - 1


# ---------------------------------------------------------------- Godot humanoid profile
def load_profile():
    with open(os.path.join(GEN, 'godot_humanoid_profile.json')) as f:
        bones = json.load(f)
    by = {b['name']: b for b in bones}

    def gbasis(name):
        b = by[name]
        M = Matrix((b['basis'][0], b['basis'][1], b['basis'][2])).transposed()  # columns x, y, z
        if b['parent']:
            return gbasis(b['parent']) @ M
        return M
    C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot (x, y, z) -> Blender (x, -z, y)
    out = []
    for b in bones:
        out.append({'name': b['name'], 'parent': b['parent'], 'required': b['required'],
                    'group': b['group'], 'basis': C @ gbasis(b['name'])})  # columns = bone axes in Blender space
    return out


VRM_TO_GODOT = {
    'J_Bip_C_Hips': 'Hips', 'J_Bip_C_Spine': 'Spine', 'J_Bip_C_Chest': 'Chest',
    'J_Bip_C_UpperChest': 'UpperChest', 'J_Bip_C_Neck': 'Neck', 'J_Bip_C_Head': 'Head',
    'J_Adj_L_FaceEye': 'LeftEye', 'J_Adj_R_FaceEye': 'RightEye',
}
for _s, _S in (('L', 'Left'), ('R', 'Right')):
    VRM_TO_GODOT.update({
        f'J_Bip_{_s}_Shoulder': f'{_S}Shoulder', f'J_Bip_{_s}_UpperArm': f'{_S}UpperArm',
        f'J_Bip_{_s}_LowerArm': f'{_S}LowerArm', f'J_Bip_{_s}_Hand': f'{_S}Hand',
        f'J_Bip_{_s}_Thumb1': f'{_S}ThumbMetacarpal', f'J_Bip_{_s}_Thumb2': f'{_S}ThumbProximal',
        f'J_Bip_{_s}_Thumb3': f'{_S}ThumbDistal',
        f'J_Bip_{_s}_UpperLeg': f'{_S}UpperLeg', f'J_Bip_{_s}_LowerLeg': f'{_S}LowerLeg',
        f'J_Bip_{_s}_Foot': f'{_S}Foot', f'J_Bip_{_s}_ToeBase': f'{_S}Toes',
    })
    for _f in ('Index', 'Middle', 'Ring', 'Little'):
        for _i, _seg in ((1, 'Proximal'), (2, 'Intermediate'), (3, 'Distal')):
            VRM_TO_GODOT[f'J_Bip_{_s}_{_f}{_i}'] = f'{_S}{_f}{_seg}'


# ---------------------------------------------------------------- object helpers
def active(obj, mode='OBJECT'):
    cur = bpy.context.view_layer.objects.active
    if cur is not None and cur.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if mode != 'OBJECT':
        bpy.ops.object.mode_set(mode=mode)


def new_obj(name, me=None):
    me = me or bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def join(objs, name):
    active(objs[0])
    for o in objs:
        o.select_set(True)
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


# ---------------------------------------------------------------- mesh cutting
def split_by_field(bm, faces, field, eps=1e-7):
    """Cut `faces` along the zero iso-line of a per-vertex scalar `field` (callable BMVert -> float,
    positive = inside). Faces are triangulated first. Vertex data (weights, shape keys) and loop
    data (UVs) are interpolated by bmesh, and cut vertices are shared between neighbours so the
    surface stays watertight. Returns (inside_faces, outside_faces)."""
    faces = list(dict.fromkeys(f for f in faces if f.is_valid))
    faces = bmesh.ops.triangulate(bm, faces=faces)['faces']
    val = {}

    def fv(v):
        x = val.get(v)
        if x is None:
            x = field(v)
            if abs(x) < eps:
                x = eps
            val[v] = x
        return x
    edges = set()
    for f in faces:
        for e in f.edges:
            edges.add(e)
    cutverts = set()
    for e in list(edges):
        a, b = e.verts
        fa, fb = fv(a), fv(b)
        if (fa > 0) != (fb > 0):
            t = fa / (fa - fb)
            ne, nv = bmesh.utils.edge_split(e, a, t)
            val[nv] = 0.0
            cutverts.add(nv)
    allf = set(f for f in faces if f.is_valid)
    touched = set()
    for v in cutverts:
        for f in v.link_faces:
            touched.add(f)
    for f in list(touched):
        zs = [v for v in f.verts if v in cutverts]
        if len(zs) == 2 and len(f.verts) > 3:
            adj = any((zs[0] in e.verts and zs[1] in e.verts) for e in f.edges)
            if not adj:
                r = bmesh.utils.face_split(f, zs[0], zs[1])
                if r and r[0]:
                    allf.add(r[0])
        allf.add(f)
    inside, outside = [], []
    for f in allf:
        if not f.is_valid:
            continue
        s = 0.0
        for v in f.verts:
            if v not in cutverts:
                s += fv(v)
        (inside if s > 0 else outside).append(f)
    return inside, outside


def subdivide_faces(bm, faces, cuts=1):
    edges = set()
    for f in faces:
        if f.is_valid:
            for e in f.edges:
                edges.add(e)
    bmesh.ops.subdivide_edges(bm, edges=list(edges), cuts=cuts, use_grid_fill=True, smooth=0.0)


class Image2D:
    """Bilinear sampler over an image (numpy), v up as in UV space."""

    def __init__(self, src):
        import numpy as np
        im = bpy.data.images.load(src) if isinstance(src, str) else src
        self.w, self.h = im.size
        self.px = np.array(im.pixels[:], dtype=np.float32).reshape(self.h, self.w, 4)

    def sample(self, u, v, ch=3):
        x = min(max(u * self.w - 0.5, 0), self.w - 1.001)
        y = min(max(v * self.h - 0.5, 0), self.h - 1.001)
        x0 = int(x); y0 = int(y); fx = x - x0; fy = y - y0
        p = self.px
        a = p[y0, x0, ch] * (1 - fx) + p[y0, x0 + 1, ch] * fx
        b = p[y0 + 1, x0, ch] * (1 - fx) + p[y0 + 1, x0 + 1, ch] * fx
        return float(a * (1 - fy) + b * fy)


def faces_of_material(bm, obj, name_part):
    idx = [i for i, m in enumerate(obj.data.materials) if m and name_part in m.name]
    return [f for f in bm.faces if f.material_index in idx]
