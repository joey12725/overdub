"""Stage 1 - import the CC0 VRoid base model, turn it to face -Y (Godot +Z), and replace its
armature with a clean humanoid skeleton named `Rig` whose bone names AND rest orientations match
Godot's SkeletonProfileHumanoid. Saves work/s1.blend.

Run: blender --background --python s1_base.py
"""
import bpy, bmesh, sys, os
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_util as U

SRC = os.path.join(U.HERE, 'src_dl', 'fem_vroid.vrm')


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tmp = os.path.join(U.WORK, 'fem_vroid.glb')
    if not os.path.exists(tmp):
        import shutil
        shutil.copyfile(SRC, tmp)
    bpy.ops.import_scene.gltf(filepath=tmp)
    old = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    body = bpy.data.objects['Body']; face = bpy.data.objects['Face']
    for o in list(bpy.data.objects):
        if o not in (old, body, face):
            bpy.data.objects.remove(o)

    # joints, turned 180 degrees about Z so she faces -Y (VRM 0.x faces +Y in Blender)
    joints = {}
    for b in old.data.bones:
        g = U.VRM_TO_GODOT.get(b.name)
        if g:
            h = old.matrix_world @ b.head_local
            joints[g] = Vector((-h.x, -h.y, h.z))
    for o in (body, face):
        o.parent = None
        me = o.data
        for v in me.vertices:
            v.co = Vector((-v.co.x, -v.co.y, v.co.z))
        if me.shape_keys:
            for kb in me.shape_keys.key_blocks:
                for d in kb.data:
                    d.co = Vector((-d.co.x, -d.co.y, d.co.z))
        me.update()
        # vertex groups -> Godot names; secondary (bust) weights fold into UpperChest
        for vg in list(o.vertex_groups):
            g = U.VRM_TO_GODOT.get(vg.name)
            if g:
                vg.name = g
        fold = [vg for vg in o.vertex_groups if vg.name.startswith('J_Sec')]
        if fold:
            tgt = o.vertex_groups.get('UpperChest') or o.vertex_groups.new(name='UpperChest')
            for v in me.vertices:
                add = 0.0
                for ge in v.groups:
                    if o.vertex_groups[ge.group] in fold:
                        add += ge.weight
                if add > 0:
                    tgt.add([v.index], add, 'ADD')
            for vg in fold:
                o.vertex_groups.remove(vg)
        for vg in list(o.vertex_groups):
            if vg.name in ('Root',) or vg.name.startswith('J_'):
                o.vertex_groups.remove(vg)
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        me.materials  # keep
    bpy.data.objects.remove(old)

    # shape key names live in the glTF primitive extras, which Blender's importer drops
    import json, struct
    with open(tmp, 'rb') as f:
        f.read(12); n, _ = struct.unpack('<II', f.read(8)); j = json.loads(f.read(n))
    names = j['meshes'][0]['primitives'][0]['extras']['targetNames']
    kbs = face.data.shape_keys.key_blocks
    for i, nm in enumerate(names):
        kbs['target_%d' % i].name = nm

    rig = build_rig(joints)
    for o in (body, face):
        o.parent = rig
        md = o.modifiers.new('Armature', 'ARMATURE'); md.object = rig
    # normals: keep the custom split normals that came with the VRM (smooth anime shading)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(U.WORK, 's1.blend'))
    print('S1 OK: bones', len(rig.data.bones), 'body tris', len(body.data.polygons), 'face tris', len(face.data.polygons))


def build_rig(joints):
    prof = U.load_profile()
    arm = bpy.data.armatures.new('Rig')
    rig = bpy.data.objects.new('Rig', arm)
    bpy.context.scene.collection.objects.link(rig)
    U.active(rig, 'EDIT')
    joints = dict(joints)
    joints['Root'] = Vector((0, 0, 0))
    child_main = {'Root': 'Hips', 'Hips': 'Spine', 'Spine': 'Chest', 'Chest': 'UpperChest', 'UpperChest': 'Neck',
                  'Neck': 'Head'}
    for S in ('Left', 'Right'):
        child_main.update({S + 'Shoulder': S + 'UpperArm', S + 'UpperArm': S + 'LowerArm', S + 'LowerArm': S + 'Hand',
                           S + 'Hand': S + 'MiddleProximal', S + 'UpperLeg': S + 'LowerLeg',
                           S + 'LowerLeg': S + 'Foot', S + 'Foot': S + 'Toes',
                           S + 'ThumbMetacarpal': S + 'ThumbProximal', S + 'ThumbProximal': S + 'ThumbDistal'})
        for f in ('Index', 'Middle', 'Ring', 'Little'):
            child_main[S + f + 'Proximal'] = S + f + 'Intermediate'
            child_main[S + f + 'Intermediate'] = S + f + 'Distal'
    lengths = {}
    for p in prof:
        n = p['name']
        if n not in joints:
            continue
        c = child_main.get(n)
        if c and c in joints:
            lengths[n] = max(0.01, (joints[c] - joints[n]).length)
    for p in prof:
        n = p['name']
        if n not in joints:
            continue
        L = lengths.get(n)
        if L is None:
            par = p['parent']
            L = {'Head': 0.16, 'LeftEye': 0.02, 'RightEye': 0.02, 'LeftToes': 0.06, 'RightToes': 0.06}.get(
                n, lengths.get(par, 0.03) * 0.8)
            lengths[n] = L
        if n == 'Root':
            L = 0.25
        eb = arm.edit_bones.new(n)
        B = p['basis']
        eb.head = joints[n]
        eb.tail = joints[n] + B.col[1] * L
        M = B.to_4x4(); M.translation = joints[n]
        eb.matrix = M
        eb.length = L
        if p['parent'] and p['parent'] in arm.edit_bones:
            eb.parent = arm.edit_bones[p['parent']]
        eb.use_connect = False
        eb.use_deform = n != 'Root'
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


if __name__ == '__main__':
    main()
