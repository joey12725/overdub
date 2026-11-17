"""Adds the animator-facing control rig (Rigify) to the working file and saves art/moxie_c/moxie.blend.

    blender --background art/moxie_c/moxie_anim.blend --python art/moxie_c/mc_ctrl.py

A Rigify human metarig is fitted to the export skeleton's joints (limbs with one segment so the
deform chain matches the humanoid profile), generated into `MoxieControl` (IK/FK limbs, spine,
fingers), and given one helper bone per export bone (`EXP-<name>`, an exact copy of the export
bone parented to the matching Rigify deform bone). Each export bone carries a Copy Transforms
constraint to its helper, so whatever is animated on the control rig lands on the clean humanoid
skeleton `Rig`, which is the only armature that is exported. The constraints are saved MUTED so the
retargeted library clips on `Rig` play as-is; the text block `moxie_tools.py` inside the .blend
switches them on (`control_rig(True)`) and bakes control-rig animation down (`bake_to_export`).
"""
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

TORSO = [("spine", "Hips"), ("spine.001", "Spine"), ("spine.002", "Chest"), ("spine.003", "UpperChest")]
LIMB = [("shoulder", "Shoulder"), ("upper_arm", "UpperArm"), ("forearm", "LowerArm"), ("hand", "Hand"),
        ("thigh", "UpperLeg"), ("shin", "LowerLeg"), ("foot", "Foot"), ("toe", "Toes")]
FINGER = [("thumb", "Thumb", ("Metacarpal", "Proximal", "Distal")),
          ("f_index", "Index", ("Proximal", "Intermediate", "Distal")),
          ("f_middle", "Middle", ("Proximal", "Intermediate", "Distal")),
          ("f_ring", "Ring", ("Proximal", "Intermediate", "Distal")),
          ("f_pinky", "Little", ("Proximal", "Intermediate", "Distal"))]

TOOLS = '''"""Moxie rig helpers (run this text block once, then call from the Python console).

control_rig(True)   -> the export skeleton `Rig` follows the Rigify rig `MoxieControl`
control_rig(False)  -> `Rig` plays its own actions (the retargeted library clips)
bake_to_export("my_clip", start, end) -> bakes what MoxieControl is doing onto `Rig` as an action
"""
import bpy


def control_rig(on=True):
    rig = bpy.data.objects["Rig"]
    for pb in rig.pose.bones:
        for c in pb.constraints:
            if c.name == "FollowControl":
                c.mute = not on
    ctrl = bpy.data.objects.get("MoxieControl")
    if ctrl:
        ctrl.hide_set(not on)


def bake_to_export(name, start=None, end=None):
    sc = bpy.context.scene
    start = sc.frame_start if start is None else start
    end = sc.frame_end if end is None else end
    rig = bpy.data.objects["Rig"]
    control_rig(True)
    bpy.ops.object.select_all(action='DESELECT')
    rig.hide_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='POSE')
    for pb in rig.pose.bones:
        pb.bone.select = any(c.name == "FollowControl" for c in pb.constraints)
    if rig.animation_data:
        rig.animation_data.action = None
    bpy.ops.nla.bake(frame_start=start, frame_end=end, only_selected=True, visual_keying=True,
                     clear_constraints=False, use_current_action=False, bake_types={'POSE'})
    act = rig.animation_data.action
    act.name = name
    act.use_fake_user = True
    bpy.ops.object.mode_set(mode='OBJECT')
    control_rig(False)
    return act
'''


def fit_metarig(rig):
    import addon_utils
    addon_utils.enable("rigify", default_set=True)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.object.armature_human_metarig_add()
    meta = bpy.context.view_layer.objects.active
    meta.name = "MoxieMetarig"
    src = rig.data.bones

    def H(n):
        return src[n].head_local.copy()

    def T(n):
        return src[n].tail_local.copy()
    bpy.ops.object.mode_set(mode='EDIT')
    eb = meta.data.edit_bones
    # drop the face rig and other parts the export skeleton has no bones for
    def descendants(b):
        out = [b]
        for c in b.children:
            out += descendants(c)
        return out
    kill = []
    for nm in ("face", "breast.L", "breast.R", "pelvis.L", "pelvis.R"):
        if nm in eb:
            kill += descendants(eb[nm])
    for b in kill:
        eb.remove(b)

    def place(mname, head, tail, roll_from=None):
        b = eb[mname]
        b.head = head
        b.tail = tail
        if roll_from is not None:
            b.roll = 0.0
            b.align_roll(roll_from)
    for m, e in TORSO:
        place(m, H(e), T(e))
    neck_h, neck_t = H("Neck"), T("Neck")
    mid = (neck_h + neck_t) / 2
    place("spine.004", neck_h, mid)
    place("spine.005", mid, neck_t)
    place("spine.006", H("Head"), T("Head"))
    for sfx, side in ((".L", "Left"), (".R", "Right")):
        for m, e in LIMB:
            b = eb[m + sfx]
            b.head, b.tail = H(side + e), T(side + e)
        # Rigify wants the elbow/knee to have a slight bend toward the pole
        eb["forearm" + sfx].head = eb["forearm" + sfx].head + Vector((0, 0.012, 0))
        eb["upper_arm" + sfx].tail = eb["forearm" + sfx].head
        eb["shin" + sfx].head = eb["shin" + sfx].head + Vector((0, -0.012, 0))
        eb["thigh" + sfx].tail = eb["shin" + sfx].head
        for b in ("upper_arm", "forearm", "hand"):
            eb[b + sfx].roll = 0.0
            eb[b + sfx].align_roll(Vector((0, 0, 1)))
        for b in ("thigh", "shin"):
            eb[b + sfx].align_roll(Vector((0, -1, 0)))
        sx = 1 if sfx == ".L" else -1
        foot = eb["foot" + sfx]
        heel = eb["heel.02" + sfx]
        heel.head = Vector((sx * 0.060, 0.105, 0.0))
        heel.tail = Vector((sx * 0.140, 0.105, 0.0))
        for m, e, segs in FINGER:
            for i, sg in enumerate(segs):
                b = eb["%s.%02d%s" % (m, i + 1, sfx)]
                b.head, b.tail = H(side + e + sg), T(side + e + sg)
                b.align_roll(Vector((0, 0, 1)))
        hand_h = H(side + "Hand")
        for i, (m, e) in enumerate((("palm.01", "Index"), ("palm.02", "Middle"), ("palm.03", "Ring"),
                                    ("palm.04", "Little"))):
            b = eb[m + sfx]
            k = H(side + e + "Proximal")
            b.head = hand_h + (k - hand_h) * 0.25
            b.tail = k
            b.align_roll(Vector((0, 0, 1)))
    bpy.ops.object.mode_set(mode='POSE')
    for sfx in (".L", ".R"):
        for b in ("upper_arm", "thigh"):
            pb = meta.pose.bones[b + sfx]
            try:
                pb.rigify_parameters.segments = 1
            except Exception as e:
                print("segments:", e)
    bpy.ops.object.mode_set(mode='OBJECT')
    return meta


def generate(meta):
    bpy.ops.object.select_all(action='DESELECT')
    meta.select_set(True)
    bpy.context.view_layer.objects.active = meta
    bpy.ops.pose.rigify_generate()
    ctrl = meta.data.rigify_target_rig or bpy.context.view_layer.objects.active
    ctrl.name = "MoxieControl"
    return ctrl


def link_export(rig, ctrl):
    """EXP- helper bones on the control rig + Copy Transforms on the export skeleton."""
    pairs = {}
    for m, e in TORSO:
        pairs[e] = "DEF-" + m
    pairs["Neck"] = "DEF-spine.004"
    pairs["Head"] = "DEF-spine.006"
    for sfx, side in ((".L", "Left"), (".R", "Right")):
        for m, e in LIMB:
            pairs[side + e] = "DEF-" + m + sfx
        for m, e, segs in FINGER:
            for i, sg in enumerate(segs):
                pairs[side + e + sg] = "DEF-%s.%02d%s" % (m, i + 1, sfx)
    missing = [d for d in pairs.values() if d not in ctrl.data.bones]
    if missing:
        print("WARNING control rig lacks deform bones:", missing)
    bpy.ops.object.select_all(action='DESELECT')
    ctrl.select_set(True)
    bpy.context.view_layer.objects.active = ctrl
    bpy.ops.object.mode_set(mode='EDIT')
    eb = ctrl.data.edit_bones
    for e, d in pairs.items():
        if d not in eb:
            continue
        src = rig.data.bones[e]
        b = eb.new("EXP-" + e)
        b.head = src.head_local
        b.tail = src.tail_local
        b.matrix = src.matrix_local.copy()
        b.length = src.length
        b.parent = eb[d]
        b.use_deform = False
    bpy.ops.object.mode_set(mode='OBJECT')
    try:
        coll = ctrl.data.collections.new("Export helpers")
        for e in pairs:
            if "EXP-" + e in ctrl.data.bones:
                coll.assign(ctrl.data.bones["EXP-" + e])
        coll.is_visible = False
    except Exception as ex:
        print("collections:", ex)
    n = 0
    for e in pairs:
        if "EXP-" + e not in ctrl.data.bones:
            continue
        c = rig.pose.bones[e].constraints.new('COPY_TRANSFORMS')
        c.name = "FollowControl"
        c.target = ctrl
        c.subtarget = "EXP-" + e
        c.mute = True
        n += 1
    return n


def main():
    rig = bpy.data.objects["Rig"]
    if rig.animation_data:
        rig.animation_data.action = None
    import mc_rig
    mc_rig.reset_pose(rig)
    bpy.context.scene.frame_set(0)
    meta = fit_metarig(rig)
    ctrl = generate(meta)
    n = link_export(rig, ctrl)
    txt = bpy.data.texts.new("moxie_tools.py")
    txt.write(TOOLS)
    txt.use_fake_user = True
    meta.hide_set(True)
    meta.hide_render = True
    ctrl.hide_render = True
    for o in bpy.data.objects:
        if o.name.startswith("WGT") or (o.type == 'MESH' and o.name not in ("Moxie",) and "WGT" in o.name):
            o.hide_render = True
    for coll in bpy.data.collections:
        if coll.name.startswith("WGT"):
            coll.hide_render = True
    # leave the file showing the idle clip on the export skeleton
    import mc_anim
    if "idle" in bpy.data.actions:
        mc_anim._set_action(rig, bpy.data.actions["idle"])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "moxie.blend"))
    print("CTRL DONE: %d export bones follow the control rig; control bones: %d" % (n, len(ctrl.data.bones)))


if __name__ == "__main__":
    main()
