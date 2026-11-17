"""Step 8 (Blender): animator control rig. Fits a Rigify human metarig to Moxie's joints, generates `MoxieControl`
(IK/FK limbs, spine, head) and ties every humanoid bone of the export skeleton `Rig` to it with a Copy Transforms
constraint stored MUTED (so the retargeted clips on `Rig` keep playing). The text block `moxie_control_rig.py` inside
the .blend switches control on/off and bakes control-rig animation down to `Rig`.
Recipe shared with candidate A (art/moxie_a/s8_control.py); fingers are not rigged on this candidate.
Reads and re-saves art/moxie_e/moxie.blend."""
import bpy, sys, os, json
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import HERE, WORK

HELPER = """\"\"\"Moxie control-rig helpers (run from Blender's text editor).

    control(True)    the Rigify rig `MoxieControl` drives the export skeleton `Rig`
    control(False)   `Rig` plays its own actions again (the retargeted library clips)
    bake("name")     bake the current control-rig animation (scene frame range) onto `Rig` as action `name`;
                     then put it on an NLA track named like the clip and re-run the export at the end of s6_anim.py
\"\"\"
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
    act.use_fake_user = True
    bpy.ops.object.mode_set(mode='OBJECT')
    control(False)
    return act
"""


def act(o, mode='OBJECT'):
    if bpy.context.view_layer.objects.active and bpy.context.view_layer.objects.active.mode != 'OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT'); o.hide_set(False); o.select_set(True); bpy.context.view_layer.objects.active = o
    if mode != 'OBJECT': bpy.ops.object.mode_set(mode=mode)


bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'moxie.blend'))
for o in [o for o in bpy.data.objects if o.name in ('MoxieControl', 'MoxieMetarig') or o.name.startswith('WGT-')]: bpy.data.objects.remove(o)
bpy.ops.preferences.addon_enable(module='rigify')
rig = bpy.data.objects['Rig']
for pb in rig.pose.bones:
    for c in list(pb.constraints): pb.constraints.remove(c)
J = {b.name: b.head_local.copy() for b in rig.data.bones}
bpy.ops.object.armature_human_metarig_add()
meta = bpy.context.object; meta.name = 'MoxieMetarig'
bpy.ops.object.mode_set(mode='EDIT')
eb = meta.data.edit_bones


def kill(name):
    b = eb.get(name)
    if b is None: return
    for c in list(b.children_recursive): eb.remove(c)
    eb.remove(b)


for n in ['face', 'breast.L', 'breast.R'] + [b.name for b in eb if b.name.split('.')[0] in ('palm', 'thumb') or b.name.startswith('f_')]:
    kill(n)


def put(name, head, tail):
    b = eb[name]; b.head = head; b.tail = tail


back = Vector((0, 0.012, 0))
put('spine', J['Hips'], J['Spine']); put('spine.001', J['Spine'], J['Chest']); put('spine.002', J['Chest'], J['UpperChest']); put('spine.003', J['UpperChest'], J['Neck'])
mid = (J['Neck'] + J['Head']) / 2
put('spine.004', J['Neck'], mid); put('spine.005', mid, J['Head']); put('spine.006', J['Head'], J['Head'] + Vector((0, 0, 0.20)))
for s, S in (('L', 'Left'), ('R', 'Right')):
    sx = 1 if s == 'L' else -1
    put('pelvis.' + s, J['Hips'], J['Hips'] + Vector((0.09 * sx, -0.03, 0.07)))
    put('shoulder.' + s, J[S + 'Shoulder'], J[S + 'UpperArm'])
    elbow = J[S + 'LowerArm'] + back
    put('upper_arm.' + s, J[S + 'UpperArm'], elbow); put('forearm.' + s, elbow, J[S + 'Hand'])
    put('hand.' + s, J[S + 'Hand'], J[S + 'Hand'] + Vector((0.08 * sx, 0, 0)))
    knee = J[S + 'LowerLeg'] + Vector((0, -0.012, 0))
    put('thigh.' + s, J[S + 'UpperLeg'], knee); put('shin.' + s, knee, J[S + 'Foot'])
    put('foot.' + s, J[S + 'Foot'], J[S + 'Toes']); put('toe.' + s, J[S + 'Toes'], J[S + 'Toes'] + Vector((0, -0.07, 0)))
    hx = J[S + 'Foot'].x
    put('heel.02.' + s, Vector((hx - 0.035 * sx, J[S + 'Foot'].y + 0.045, 0.0)), Vector((hx + 0.035 * sx, J[S + 'Foot'].y + 0.045, 0.0)))
for b in eb: b.select = b.select_head = b.select_tail = False
for n in [b.name for b in eb if b.name.split('.')[0] in ('upper_arm', 'forearm', 'hand')]: eb[n].select = True
bpy.ops.armature.calculate_roll(type='GLOBAL_POS_Z')
for b in eb: b.select = False
for n in [b.name for b in eb if b.name.split('.')[0] in ('thigh', 'shin', 'foot', 'toe')]: eb[n].select = True
bpy.ops.armature.calculate_roll(type='GLOBAL_NEG_Y')
bpy.ops.object.mode_set(mode='OBJECT')
for pb in meta.pose.bones:
    try:
        if pb.rigify_type.startswith('limbs.'): pb.rigify_parameters.rotation_axis = 'x'
    except Exception: pass
meta.data.rigify_rig_basename = 'MoxieControl'
bpy.context.view_layer.objects.active = meta
bpy.ops.pose.rigify_generate()
ctrl = [o for o in bpy.data.objects if o.type == 'ARMATURE' and o not in (rig, meta)][0]
ctrl.name = 'MoxieControl'; ctrl.show_in_front = True
print('generated', ctrl.name, len(ctrl.data.bones), 'bones')
m = {'Hips': 'spine', 'Spine': 'spine.001', 'Chest': 'spine.002', 'UpperChest': 'spine.003', 'Neck': 'spine.004', 'Head': 'spine.006'}
for s, S in (('L', 'Left'), ('R', 'Right')):
    m.update({S + 'Shoulder': 'shoulder.' + s, S + 'UpperArm': 'upper_arm.' + s, S + 'LowerArm': 'forearm.' + s, S + 'Hand': 'hand.' + s,
              S + 'UpperLeg': 'thigh.' + s, S + 'LowerLeg': 'shin.' + s, S + 'Foot': 'foot.' + s, S + 'Toes': 'toe.' + s})
# helper bones in the control rig reproduce each export bone's rest matrix exactly, parented to the Rigify ORG bone;
# the export bone copies the helper's world transform (constraint stored muted)
rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}; lens = {b.name: b.length for b in rig.data.bones}
act(ctrl, 'EDIT')
missing = []
for bone, org in m.items():
    tgt = 'ORG-' + org
    if tgt not in ctrl.data.edit_bones: missing.append(tgt); continue
    hb = ctrl.data.edit_bones.new('MX-' + bone)
    hb.head = rest[bone].translation; hb.tail = rest[bone].translation + rest[bone].to_3x3().col[1] * lens[bone]
    hb.matrix = rest[bone]; hb.length = lens[bone]; hb.parent = ctrl.data.edit_bones[tgt]; hb.use_deform = False
bpy.ops.object.mode_set(mode='OBJECT')
try:
    coll = ctrl.data.collections.new('MX export helpers')
    for bone in m:
        if 'MX-' + bone in ctrl.data.bones: coll.assign(ctrl.data.bones['MX-' + bone])
    coll.is_visible = False
except Exception as e: print('collection', e)
n = 0
for bone in m:
    if 'MX-' + bone not in ctrl.data.bones: continue
    c = rig.pose.bones[bone].constraints.new('COPY_TRANSFORMS'); c.name = 'MoxieControl'; c.target = ctrl; c.subtarget = 'MX-' + bone; c.mute = True; n += 1
print('constraints', n, 'missing', missing)
# sanity: with the control rig at rest and the constraints on, the export skeleton must not move
for pb in rig.pose.bones:
    for c in pb.constraints: c.mute = False
bpy.context.view_layer.update()
err = max((rig.pose.bones[b].matrix.translation - rest[b].translation).length for b in m)
print('control rig at rest moves the export bones by at most %.5f m' % err)
for pb in rig.pose.bones:
    for c in pb.constraints: c.mute = True
if 'moxie_control_rig.py' in bpy.data.texts: bpy.data.texts.remove(bpy.data.texts['moxie_control_rig.py'])
t = bpy.data.texts.new('moxie_control_rig.py'); t.write(HELPER)
meta.hide_set(True); meta.hide_render = True; ctrl.hide_render = True; ctrl.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'moxie.blend'))
print('S8 OK')
