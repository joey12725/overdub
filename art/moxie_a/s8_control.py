"""Stage 8 - the animator-friendly control rig. Fits a Rigify human metarig to Moxie's joints,
generates the Rigify rig (IK/FK limbs, spine, fingers) as `MoxieControl`, and ties every bone of the
clean export skeleton `Rig` to the matching Rigify ORG bone with a Child Of constraint (rest poses
differ, so Copy Transforms would not do). The constraints are stored MUTED so the retargeted
library clips on `Rig` keep playing; the text block `moxie_control_rig.py` inside the .blend
switches them on and bakes control-rig animation down to `Rig` for export.
Reads work/s7.blend, saves art/moxie_a/moxie.blend.
"""
import bpy, sys, os
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_util as U

HELPER = '''"""Moxie control-rig helpers (run from Blender's text editor).

    control(True)    the Rigify rig `MoxieControl` drives the export skeleton `Rig`
    control(False)   `Rig` plays its own actions again (the retargeted library clips)
    bake("name")     bake the current control-rig animation (scene frame range) onto `Rig`
                     as action `name`, ready for s9_export.py
"""
import bpy


def control(on=True):
    rig = bpy.data.objects['Rig']
    for pb in rig.pose.bones:
        for c in pb.constraints:
            if c.name == 'MoxieControl':
                c.mute = not on
    bpy.data.objects['MoxieControl'].hide_set(not on)


def bake(name):
    rig = bpy.data.objects['Rig']
    control(True)
    sc = bpy.context.scene
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.nla.bake(frame_start=sc.frame_start, frame_end=sc.frame_end, only_selected=True, visual_keying=True,
                     clear_constraints=False, use_current_action=False, bake_types={'POSE'})
    act = rig.animation_data.action
    act.name = name
    act['source'] = 'authored on MoxieControl'
    act.use_fake_user = True
    bpy.ops.object.mode_set(mode='OBJECT')
    control(False)
    return act
'''


def main():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(U.WORK, 's7.blend'))
    bpy.ops.preferences.addon_enable(module='rigify')
    rig = bpy.data.objects['Rig']
    J = {b.name: b.head_local.copy() for b in rig.data.bones}
    T = {b.name: b.tail_local.copy() for b in rig.data.bones}
    bpy.ops.object.armature_human_metarig_add()
    meta = bpy.context.object
    meta.name = 'MoxieMetarig'
    bpy.ops.object.mode_set(mode='EDIT')
    eb = meta.data.edit_bones
    # no face rig, no breast bones: the face is driven by shape keys
    def kill(name):
        b = eb.get(name)
        if b is None:
            return
        for c in list(b.children_recursive):
            eb.remove(c)
        eb.remove(b)
    for n in ('face', 'breast.L', 'breast.R'):
        kill(n)

    def put(name, head, tail):
        b = eb[name]
        b.head = head; b.tail = tail

    back = Vector((0, 0.012, 0))
    put('spine', J['Hips'], J['Spine'])
    put('spine.001', J['Spine'], J['Chest'])
    put('spine.002', J['Chest'], J['UpperChest'])
    put('spine.003', J['UpperChest'], J['Neck'])
    mid = (J['Neck'] + J['Head']) / 2
    put('spine.004', J['Neck'], mid)
    put('spine.005', mid, J['Head'])
    put('spine.006', J['Head'], J['Head'] + Vector((0, 0, 0.20)))
    for s, S in (('L', 'Left'), ('R', 'Right')):
        sx = 1 if s == 'L' else -1
        put('pelvis.' + s, J['Hips'], J['Hips'] + Vector((0.09 * sx, -0.03, 0.07)))
        put('shoulder.' + s, J[S + 'Shoulder'], J[S + 'UpperArm'])
        elbow = J[S + 'LowerArm'] + back          # a hint of bend so IK knows which way to fold
        put('upper_arm.' + s, J[S + 'UpperArm'], elbow)
        put('forearm.' + s, elbow, J[S + 'Hand'])
        put('hand.' + s, J[S + 'Hand'], J[S + 'Hand'].lerp(J[S + 'MiddleProximal'], 0.75))
        for f, g, palm in (('Index', 'index', '01'), ('Middle', 'middle', '02'), ('Ring', 'ring', '03'), ('Little', 'pinky', '04')):
            p1, p2, p3 = J[S + f + 'Proximal'], J[S + f + 'Intermediate'], J[S + f + 'Distal']
            put('palm.%s.%s' % (palm, s), J[S + 'Hand'].lerp(p1, 0.25), p1)
            put('f_%s.01.%s' % (g, s), p1, p2)
            put('f_%s.02.%s' % (g, s), p2, p3)
            put('f_%s.03.%s' % (g, s), p3, p3 + (p3 - p2) * 0.9)
        t1, t2, t3 = J[S + 'ThumbMetacarpal'], J[S + 'ThumbProximal'], J[S + 'ThumbDistal']
        put('thumb.01.' + s, t1, t2); put('thumb.02.' + s, t2, t3); put('thumb.03.' + s, t3, t3 + (t3 - t2) * 0.9)
        knee = J[S + 'LowerLeg'] + Vector((0, -0.012, 0))
        put('thigh.' + s, J[S + 'UpperLeg'], knee)
        put('shin.' + s, knee, J[S + 'Foot'])
        put('foot.' + s, J[S + 'Foot'], J[S + 'Toes'])
        put('toe.' + s, J[S + 'Toes'], J[S + 'Toes'] + Vector((0, -0.07, 0)))
        hx = J[S + 'Foot'].x
        put('heel.02.' + s, Vector((hx - 0.035 * sx, J[S + 'Foot'].y + 0.045, 0.0)), Vector((hx + 0.035 * sx, J[S + 'Foot'].y + 0.045, 0.0)))
    # rolls: limbs bend about their local X
    for b in eb:
        b.select = b.select_head = b.select_tail = False
    for n in [b.name for b in eb if b.name.split('.')[0] in ('upper_arm', 'forearm', 'hand')]:
        eb[n].select = True
    bpy.ops.armature.calculate_roll(type='GLOBAL_POS_Z')
    for b in eb:
        b.select = False
    for n in [b.name for b in eb if b.name.split('.')[0] in ('thigh', 'shin', 'foot', 'toe')]:
        eb[n].select = True
    bpy.ops.armature.calculate_roll(type='GLOBAL_NEG_Y')
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in meta.pose.bones:
        try:
            if pb.rigify_type.startswith('limbs.'):
                pb.rigify_parameters.rotation_axis = 'x'
        except Exception:
            pass
    meta.data.rigify_rig_basename = 'MoxieControl'
    bpy.context.view_layer.objects.active = meta
    bpy.ops.pose.rigify_generate()
    ctrl = [o for o in bpy.data.objects if o.type == 'ARMATURE' and o not in (rig, meta)][0]
    ctrl.name = 'MoxieControl'
    ctrl.show_in_front = True
    print('generated', ctrl.name, len(ctrl.data.bones), 'bones')

    # ---- tie the export skeleton to the control rig
    m = {'Hips': 'spine', 'Spine': 'spine.001', 'Chest': 'spine.002', 'UpperChest': 'spine.003', 'Neck': 'spine.004',
         'Head': 'spine.006'}
    for s, S in (('L', 'Left'), ('R', 'Right')):
        m.update({S + 'Shoulder': 'shoulder.' + s, S + 'UpperArm': 'upper_arm.' + s, S + 'LowerArm': 'forearm.' + s,
                  S + 'Hand': 'hand.' + s, S + 'UpperLeg': 'thigh.' + s, S + 'LowerLeg': 'shin.' + s,
                  S + 'Foot': 'foot.' + s, S + 'Toes': 'toe.' + s,
                  S + 'ThumbMetacarpal': 'thumb.01.' + s, S + 'ThumbProximal': 'thumb.02.' + s, S + 'ThumbDistal': 'thumb.03.' + s})
        for f, g in (('Index', 'index'), ('Middle', 'middle'), ('Ring', 'ring'), ('Little', 'pinky')):
            for i, seg in ((1, 'Proximal'), (2, 'Intermediate'), (3, 'Distal')):
                m[S + f + seg] = 'f_%s.0%d.%s' % (g, i, s)
    # helper bones in the control rig that reproduce each export bone's rest matrix exactly, parented
    # to the Rigify ORG bone; the export bone then simply copies the helper's world transform.
    rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    lens = {b.name: b.length for b in rig.data.bones}
    U.active(ctrl, 'EDIT')
    missing = []
    for bone, org in m.items():
        tgt = 'ORG-' + org
        if tgt not in ctrl.data.edit_bones:
            missing.append(tgt); continue
        hb = ctrl.data.edit_bones.new('MX-' + bone)
        hb.head = rest[bone].translation
        hb.tail = rest[bone].translation + rest[bone].to_3x3().col[1] * lens[bone]
        hb.matrix = rest[bone]
        hb.length = lens[bone]
        hb.parent = ctrl.data.edit_bones[tgt]
        hb.use_deform = False
    bpy.ops.object.mode_set(mode='OBJECT')
    try:
        coll = ctrl.data.collections.new('MX export helpers')
        for bone in m:
            if 'MX-' + bone in ctrl.data.bones:
                coll.assign(ctrl.data.bones['MX-' + bone])
        coll.is_visible = False
    except Exception as e:
        print('collection', e)
    for bone in m:
        if 'MX-' + bone not in ctrl.data.bones:
            continue
        c = rig.pose.bones[bone].constraints.new('COPY_TRANSFORMS')
        c.name = 'MoxieControl'
        c.target = ctrl; c.subtarget = 'MX-' + bone
        c.mute = True
    print('constraints', len(m) - len(missing), 'missing', missing)
    t = bpy.data.texts.new('moxie_control_rig.py'); t.write(HELPER)
    meta.hide_set(True); meta.hide_render = True
    ctrl.hide_render = True
    out = os.path.join(U.HERE, 'moxie.blend')
    bpy.ops.file.pack_all() if False else None
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print('S8 OK', out)


if __name__ == '__main__':
    main()
