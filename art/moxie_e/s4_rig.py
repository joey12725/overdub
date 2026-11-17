"""Step 4 (Blender): skeleton + skin weights + T-pose rest.  work/mesh.blend -> work/rigged.blend

1. joints are placed from model-sheet landmarks (front sheet pixels -> metres; depth = middle of the mesh there)
2. a bind armature in the sheet's A-pose gets bone-heat weights on a watertight voxel proxy, transferred to the mesh;
   the head part is weighted procedurally (Head / Neck / pigtail chains), the jacket hem gets a secondary bone
3. the arms are raised to an exact T-pose, the deformation is applied to the mesh, and the final armature 'Rig' is built
   with Godot SkeletonProfileHumanoid names, hierarchy and reference-pose orientations (see godot_humanoid_profile.json)."""
import bpy, bmesh, sys, os, json, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import *
from mathutils import Vector, Matrix

S = 1.6 / 1400
ZS = float(np.load(os.path.join(WORK, 'mesh.npz'))['zshift'])
bpy.ops.wm.open_mainfile(filepath=os.path.join(WORK, 'mesh.blend'))
ob = bpy.data.objects['Moxie']; me = ob.data
co = np.array([v.co[:] for v in me.vertices])
vmat = np.zeros(len(me.vertices), int)
for p in me.polygons:
    for vi in p.vertices: vmat[vi] = p.material_index


def px(u, v):                       # front-sheet pixel -> (x, z)
    return (u - 576.0) * S, (1480 - v) * S - ZS


def depth(x, z, r=0.035, body_only=True):
    sel = ((co[:, 0] - x) ** 2 + (co[:, 2] - z) ** 2 < r * r)
    if body_only: sel &= vmat == 0
    if not sel.any(): return 0.02
    y = co[sel, 1]
    return float((np.percentile(y, 3) + np.percentile(y, 97)) / 2)


# ---------------------------------------------------------------- joints (her left = +X = picture right)
LM = {  # front sheet pixels
    'Hips': (576, 672), 'Spine': (576, 612), 'Chest': (576, 548), 'UpperChest': (576, 472), 'Neck': (576, 350), 'Head': (576, 303),
    'LeftShoulder': (604, 388), 'LeftUpperArm': (676, 400), 'LeftLowerArm': (783, 527), 'LeftHand': (888, 654), 'LeftHandTip': (950, 760),
    'LeftUpperLeg': (630, 692), 'LeftLowerLeg': (662, 1012), 'LeftFoot': (690, 1338),
}
J = {}
for n, (u, v) in LM.items():
    x, z = px(u, v)
    J[n] = Vector((x, 0, z))
    if n.startswith('Left'):
        J['Right' + n[4:]] = Vector((-x, 0, z))
for n in J:
    limb = any(k in n for k in ('Arm', 'Hand', 'Leg', 'Foot'))
    J[n].y = depth(J[n].x, J[n].z, 0.03 if limb else 0.05)
# spine: one smooth line slightly behind the torso middle; head joint from the neck depth
for n in ('Hips', 'Spine', 'Chest', 'UpperChest'): J[n].y += 0.01
J['Neck'].y = depth(0, J['Neck'].z, 0.03); J['Head'].y = J['Neck'].y - 0.004
for s in ('Left', 'Right'):
    J[s + 'Shoulder'].y = J['UpperChest'].y * 0.5 + J[s + 'UpperArm'].y * 0.5
    J[s + 'UpperLeg'].y = J['Hips'].y
    a = J[s + 'Foot']
    J[s + 'Toes'] = Vector((a.x, a.y - 0.105, 0.035))
    J[s + 'ToesEnd'] = Vector((a.x, a.y - 0.175, 0.035))
J['HeadEnd'] = J['Head'] + Vector((0, 0, 0.17))
# secondary
for s, sg in (('L', 1), ('R', -1)):
    J[f'Pigtail{s}1'] = Vector((sg * 0.098, 0.045, 1.468)); J[f'Pigtail{s}2'] = Vector((sg * 0.165, 0.06, 1.455)); J[f'Pigtail{s}End'] = Vector((sg * 0.235, 0.07, 1.40))
J['JacketBack'] = Vector((0, depth(0, 1.10, 0.05) + 0.07, 1.12)); J['JacketBackEnd'] = Vector((0, J['JacketBack'].y + 0.01, 1.00))

PARENT = {'Hips': None, 'Spine': 'Hips', 'Chest': 'Spine', 'UpperChest': 'Chest', 'Neck': 'UpperChest', 'Head': 'Neck'}
CHILD = {'Hips': 'Spine', 'Spine': 'Chest', 'Chest': 'UpperChest', 'UpperChest': 'Neck', 'Neck': 'Head', 'Head': 'HeadEnd'}
for s in ('Left', 'Right'):
    PARENT.update({s + 'Shoulder': 'UpperChest', s + 'UpperArm': s + 'Shoulder', s + 'LowerArm': s + 'UpperArm', s + 'Hand': s + 'LowerArm',
                   s + 'UpperLeg': 'Hips', s + 'LowerLeg': s + 'UpperLeg', s + 'Foot': s + 'LowerLeg', s + 'Toes': s + 'Foot'})
    CHILD.update({s + 'Shoulder': s + 'UpperArm', s + 'UpperArm': s + 'LowerArm', s + 'LowerArm': s + 'Hand', s + 'Hand': s + 'HandTip',
                  s + 'UpperLeg': s + 'LowerLeg', s + 'LowerLeg': s + 'Foot', s + 'Foot': s + 'Toes', s + 'Toes': s + 'ToesEnd'})
EXTRA_PARENT = {'PigtailL1': 'Head', 'PigtailL2': 'PigtailL1', 'PigtailR1': 'Head', 'PigtailR2': 'PigtailR1', 'JacketBack': 'UpperChest'}
EXTRA_CHILD = {'PigtailL1': 'PigtailL2', 'PigtailL2': 'PigtailLEnd', 'PigtailR1': 'PigtailR2', 'PigtailR2': 'PigtailREnd', 'JacketBack': 'JacketBackEnd'}
BONES = list(PARENT)


def act(o, mode='OBJECT'):
    if bpy.context.view_layer.objects.active and bpy.context.view_layer.objects.active.mode != 'OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
    if mode != 'OBJECT': bpy.ops.object.mode_set(mode=mode)


# ---------------------------------------------------------------- bind armature (A-pose)
barm = bpy.data.objects.new('Bind', bpy.data.armatures.new('Bind')); bpy.context.scene.collection.objects.link(barm)
act(barm, 'EDIT')
for n in BONES:
    eb = barm.data.edit_bones.new(n); eb.head = J[n]; eb.tail = J[CHILD[n]]
for n in BONES:
    if PARENT[n]: barm.data.edit_bones[n].parent = barm.data.edit_bones[PARENT[n]]
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------- heat weights on a watertight proxy of the body part
act(ob)
bpy.ops.object.duplicate(); proxy = bpy.context.view_layer.objects.active; proxy.name = 'Proxy'
bm = bmesh.new(); bm.from_mesh(proxy.data)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index == 1], context='FACES')
bm.to_mesh(proxy.data); bm.free()
proxy.data.remesh_voxel_size = 0.006; proxy.data.use_remesh_preserve_volume = False
bpy.ops.object.voxel_remesh()
m = proxy.modifiers.new('d', 'DECIMATE'); m.ratio = min(1.0, 70000 / len(proxy.data.polygons)); bpy.ops.object.modifier_apply(modifier='d')
print('proxy tris', len(proxy.data.polygons))
bpy.ops.object.select_all(action='DESELECT'); proxy.select_set(True); barm.select_set(True); bpy.context.view_layer.objects.active = barm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
heat_ok = len(proxy.vertex_groups) > 0 and any(len(v.groups) > 0 for v in proxy.data.vertices)
nw = sum(1 for v in proxy.data.vertices if len(v.groups) > 0)
print('bone heat:', 'ok' if heat_ok else 'FAILED', 'weighted proxy verts %d / %d' % (nw, len(proxy.data.vertices)))
act(ob)
dt = ob.modifiers.new('wt', 'DATA_TRANSFER'); dt.object = proxy; dt.use_vert_data = True; dt.data_types_verts = {'VGROUP_WEIGHTS'}
dt.vert_mapping = 'POLYINTERP_NEAREST'; dt.layers_vgroup_select_src = 'ALL'; dt.layers_vgroup_select_dst = 'NAME'
bpy.ops.object.datalayout_transfer(modifier='wt'); bpy.ops.object.modifier_apply(modifier='wt')
bpy.data.objects.remove(proxy)

# ---------------------------------------------------------------- weights as a matrix, clean up
ALL = BONES + list(EXTRA_PARENT)
idx = {n: i for i, n in enumerate(ALL)}
W = np.zeros((len(co), len(ALL)))
gi = {g.index: idx[g.name] for g in ob.vertex_groups if g.name in idx}
for v in me.vertices:
    for g in v.groups:
        if g.group in gi: W[v.index, gi[g.group]] = g.weight
body = vmat == 0; head = vmat == 1
# verts the heat left empty: nearest bone segment
empty = body & (W.sum(1) < 1e-4)
if empty.any():
    P = co[empty]; best = np.full(len(P), 1e9); bi = np.zeros(len(P), int)
    for n in BONES:
        a, b = np.array(J[n]), np.array(J[CHILD[n]]); ab = b - a
        t = np.clip(((P - a) @ ab) / (ab @ ab), 0, 1); d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
        upd = d < best; best[upd] = d[upd]; bi[upd] = idx[n]
    W[np.where(empty)[0], bi] = 1.0
    print('verts without heat weights (nearest-bone fallback):', int(empty.sum()))
# smooth the body weights over the mesh (3 passes)
edges = np.array([e.vertices[:] for e in me.edges])
for it in range(3):
    acc = np.zeros_like(W); cnt = np.zeros(len(co))
    np.add.at(acc, edges[:, 0], W[edges[:, 1]]); np.add.at(acc, edges[:, 1], W[edges[:, 0]])
    np.add.at(cnt, edges[:, 0], 1); np.add.at(cnt, edges[:, 1], 1)
    Wn = 0.5 * W + 0.5 * acc / np.maximum(cnt, 1)[:, None]
    W[body] = Wn[body]
# no hand / arm influence on the trunk gear and vice versa is left to the heat solve; the head part is procedural:
W[head] = 0
z = co[:, 2]; ax = np.abs(co[:, 0]); y = co[:, 1]


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)


neck_w = 1 - sstep(1.300, 1.345, z)
cup = (ax < 0.132) & (z < 1.43) & (y < 0.085)
pig_t = np.where(cup, 0.0, sstep(0.092, 0.125, ax) * sstep(1.30, 1.36, z))          # 0 on the skull, 1 on the pigtail
tip = sstep(0.13, 0.20, ax)
for sname, sg in (('L', 1), ('R', -1)):
    side = head & (co[:, 0] * sg > 0)
    W[side, idx[f'Pigtail{sname}1']] = (pig_t * (1 - tip))[side]
    W[side, idx[f'Pigtail{sname}2']] = (pig_t * tip)[side]
W[head, idx['Neck']] = (neck_w * (1 - pig_t))[head]
W[head, idx['Head']] = ((1 - neck_w) * (1 - pig_t))[head]
# jacket hem at the back: secondary bone takes part of the weight
jb = body & (y > J['JacketBack'].y - 0.05) & (ax < 0.24)
f = (sstep(1.14, 1.06, z) * sstep(0.95, 1.00, z) * sstep(J['JacketBack'].y - 0.05, J['JacketBack'].y - 0.01, y) * (1 - sstep(0.17, 0.24, ax)) * 0.6)
f = np.where(jb, f, 0.0)
W *= (1 - f)[:, None]; W[:, idx['JacketBack']] = f * (W.sum(1) > 0) + f * (W.sum(1) <= 0)
# max 4 influences, normalise
order = np.argsort(-W, axis=1)[:, 4:]
np.put_along_axis(W, order, 0.0, axis=1)
W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
for g in list(ob.vertex_groups): ob.vertex_groups.remove(g)
for n in ALL:
    g = ob.vertex_groups.new(name=n); k = idx[n]
    nz = np.where(W[:, k] > 1e-4)[0]
    for vi in nz: g.add([int(vi)], float(W[vi, k]), 'REPLACE')
print('weights written; max influences 4; unweighted verts', int((W.sum(1) < 0.5).sum()))

# ---------------------------------------------------------------- A-pose -> T-pose
md = ob.modifiers.new('Armature', 'ARMATURE'); md.object = barm
act(barm, 'POSE')


def aim(bone, child_pos_fn, target):
    pb = barm.pose.bones[bone]
    head_ = pb.matrix.translation.copy()
    d = (child_pos_fn() - head_).normalized()
    q = d.rotation_difference(Vector(target))
    pb.matrix = Matrix.Translation(head_) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head_) @ pb.matrix
    bpy.context.view_layer.update()
    return math.degrees(q.angle)


for s, sg in (('Left', 1), ('Right', -1)):
    t = (sg, 0, 0)
    a1 = aim(s + 'UpperArm', lambda: barm.pose.bones[s + 'LowerArm'].matrix.translation, t)
    a2 = aim(s + 'LowerArm', lambda: barm.pose.bones[s + 'Hand'].matrix.translation, t)
    a3 = aim(s + 'Hand', lambda: barm.pose.bones[s + 'Hand'].tail, t)
    print(s, 'arm raised by %.1f / %.1f / %.1f deg' % (a1, a2, a3))
posed = {n: barm.pose.bones[n].matrix.translation.copy() for n in BONES}
for s, sg in (('Left', 1), ('Right', -1)):
    posed[s + 'HandTip'] = barm.pose.bones[s + 'Hand'].tail.copy()
bpy.ops.object.mode_set(mode='OBJECT')
act(ob); bpy.ops.object.modifier_apply(modifier='Armature')
bpy.data.objects.remove(barm)
for n in J:
    if n not in posed: posed[n] = J[n]

# ---------------------------------------------------------------- final armature with the Godot profile's rest orientations
prof = json.load(open(os.path.join(HERE, 'godot_humanoid_profile.json')))
by = {b['name']: b for b in prof}


def gbasis(name):
    b = by[name]; M = Matrix(b['basis']).transposed()
    return gbasis(b['parent']) @ M if b['parent'] else M


C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))                 # Godot (x, y, z) -> Blender (x, -z, y)
rig = bpy.data.objects.new('Rig', bpy.data.armatures.new('Rig')); bpy.context.scene.collection.objects.link(rig)
act(rig, 'EDIT')
for n in BONES:
    B = C @ gbasis(n)
    L = max(0.02, (posed[CHILD[n]] - posed[n]).length)
    eb = rig.data.edit_bones.new(n); eb.head = posed[n]; eb.tail = posed[n] + B.col[1] * L
    M = B.to_4x4(); M.translation = posed[n]; eb.matrix = M; eb.length = L
for n in EXTRA_PARENT:
    eb = rig.data.edit_bones.new(n); eb.head = posed[n]; eb.tail = posed[EXTRA_CHILD[n]]; eb.roll = 0
for n in BONES + list(EXTRA_PARENT):
    p = PARENT.get(n) or EXTRA_PARENT.get(n)
    if p: rig.data.edit_bones[n].parent = rig.data.edit_bones[p]; rig.data.edit_bones[n].use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')
for b in rig.data.bones: b.use_deform = True
ob.parent = rig
md = ob.modifiers.new('Armature', 'ARMATURE'); md.object = rig
rig.show_in_front = True
json.dump({n: list(v) for n, v in posed.items()}, open(os.path.join(WORK, 'joints.json'), 'w'), indent=1)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, 'rigged.blend'))
co2 = np.array([v.co[:] for v in ob.data.vertices])
print('T-pose bounds', co2.min(0).round(3), co2.max(0).round(3), 'bones', len(rig.data.bones))
