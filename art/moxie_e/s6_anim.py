"""Step 6 (Blender): retarget Quaternius' Universal Animation Library (CC0) onto the rig, bake the nine game clips,
render contact sheets, save art/moxie_e/moxie.blend and export assets/models/candidates/e/moxie.glb.

Retarget (rest-pose independent): per frame the source bone's WORLD rotation delta from its rest is applied to the
target bone's rest; limb bones are first aligned so the target limb points where the source limb points. Hip motion is
scaled by the leg-length ratio. One-shots are time-normalised to exactly 1.0 s (30 fps, keys 0..30); for light/heavy the
hit (peak right-hand speed) is warped to 40-60 %."""
import bpy, sys, os, math, json
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import *
from mathutils import Vector, Matrix, Quaternion

FPS = 30
bpy.ops.wm.open_mainfile(filepath=os.path.join(WORK, 'rigged.blend'))
sc = bpy.context.scene; sc.render.fps = FPS
setup_materials()
rig = bpy.data.objects['Rig']; mesh = bpy.data.objects['Moxie']
bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, 'dl', 'ual', 'UAL1_Standard.glb'))
src = [o for o in bpy.data.objects if o.type == 'ARMATURE' and o != rig][0]
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o != mesh: bpy.data.objects.remove(o)

MAP = {'pelvis': 'Hips', 'spine_01': 'Spine', 'spine_02': 'Chest', 'spine_03': 'UpperChest', 'neck_01': 'Neck', 'Head': 'Head'}
for s, S_ in (('l', 'Left'), ('r', 'Right')):
    MAP.update({f'clavicle_{s}': S_ + 'Shoulder', f'upperarm_{s}': S_ + 'UpperArm', f'lowerarm_{s}': S_ + 'LowerArm', f'hand_{s}': S_ + 'Hand',
                f'thigh_{s}': S_ + 'UpperLeg', f'calf_{s}': S_ + 'LowerLeg', f'foot_{s}': S_ + 'Foot', f'ball_{s}': S_ + 'Toes'})
INV = {v: k for k, v in MAP.items()}
ALIGN = {}                                             # target bone -> child whose direction is matched to the source
for S_ in ('Left', 'Right'):
    ALIGN.update({S_ + 'UpperArm': S_ + 'LowerArm', S_ + 'LowerArm': S_ + 'Hand', S_ + 'UpperLeg': S_ + 'LowerLeg', S_ + 'LowerLeg': S_ + 'Foot'})
order = [b.name for b in rig.data.bones if b.name in INV]                  # parent-first
Rt = {b.name: b.matrix_local.to_quaternion() for b in rig.data.bones}
Ht = {b.name: b.head_local.copy() for b in rig.data.bones}
Rs = {b.name: (src.matrix_world @ b.matrix_local).to_quaternion() for b in src.data.bones}
Hs = {b.name: (src.matrix_world @ b.matrix_local).translation.copy() for b in src.data.bones}
A = {}
for b in order:
    if b in ALIGN:
        dt = (Ht[ALIGN[b]] - Ht[b]).normalized(); ds = (Hs[INV[ALIGN[b]]] - Hs[INV[b]]).normalized()
        A[b] = dt.rotation_difference(ds)
    else:
        A[b] = Quaternion()
leg_t = (Ht['LeftUpperLeg'] - Ht['LeftLowerLeg']).length + (Ht['LeftLowerLeg'] - Ht['LeftFoot']).length
leg_s = (Hs['thigh_l'] - Hs['calf_l']).length + (Hs['calf_l'] - Hs['foot_l']).length
HIP_SCALE = leg_t / leg_s
# keep the feet on the floor: with the limbs aligned to the source, the hip height that puts the ankles where the
# source ankles are (scaled) is  rest_hip_z + (source hip offset) * scale - (rest stance correction)
stance_drop = (Ht['LeftUpperLeg'].z - Ht['LeftFoot'].z) - leg_t        # < 0: her rest legs are splayed, straight legs reach lower
print('hip scale %.3f, stance correction %.4f m' % (HIP_SCALE, stance_drop))


def set_action(obj, act):
    ad = obj.animation_data or obj.animation_data_create()
    ad.action = act
    if act is not None and hasattr(ad, 'action_slot') and len(getattr(act, 'slots', [])):
        try: ad.action_slot = act.slots[0]
        except Exception: pass


def sample(act, f):
    """source pose at (fractional) frame f -> {src bone: (world quat, world pos)}"""
    set_action(src, act)
    fi = math.floor(f); sc.frame_set(int(fi), subframe=float(f - fi))
    out = {}
    for sb in MAP:
        m = src.matrix_world @ src.pose.bones[sb].matrix
        out[sb] = (m.to_quaternion(), m.translation.copy())
    m = src.matrix_world @ src.pose.bones['root'].matrix
    out['root'] = (m.to_quaternion(), m.translation.copy())
    return out


def hit_window(act, bone='hand_r'):
    a, b = act.frame_range
    fs = np.arange(a, b + 0.01, 0.5)
    pos = np.array([sample(act, f)[bone][1] - sample(act, f)['pelvis'][1] * 0 for f in fs])
    sp = np.linalg.norm(np.diff(pos, axis=0), axis=1)
    sp = np.convolve(sp, np.ones(3) / 3, mode='same')
    k = int(np.argmax(sp)); lo = k; hi = k
    while lo > 0 and sp[lo - 1] > 0.45 * sp[k]: lo -= 1
    while hi < len(sp) - 1 and sp[hi + 1] > 0.45 * sp[k]: hi += 1
    return float(fs[lo]), float(fs[hi + 1])


CLIPS = [  # name, source action, loop, options
    ('idle', 'Idle_Loop', True, {}), ('run', 'Jog_Fwd_Loop', True, {}), ('stopped', 'Sword_Idle', True, {}),
    ('light', 'Sword_Attack', False, {'hit': True}), ('heavy', 'Punch_Cross', False, {'hit': True}),
    ('dodge', 'Roll', False, {'inplace': True}), ('ranged', 'Pistol_Shoot', False, {}), ('interact', 'Interact', False, {}), ('death', 'Death01', False, {}),
]
report = {}
baked = {}
for name, sname, loop, opt in CLIPS:
    act = bpy.data.actions[sname]
    a, b = act.frame_range
    src_fps = float(FPS)      # the glTF importer converts clip seconds to frames at the scene rate
    if loop:
        n = max(2, int(round((b - a) / src_fps * FPS)))
        times = [a + (b - a) * k / n for k in range(n + 1)]
    else:
        n = FPS
        if opt.get('hit'):
            h0, h1 = hit_window(act)
            def warp(u, a=a, b=b, h0=h0, h1=h1):
                if u < 0.4: return a + (h0 - a) * u / 0.4
                if u < 0.6: return h0 + (h1 - h0) * (u - 0.4) / 0.2
                return h1 + (b - h1) * (u - 0.6) / 0.4
            times = [warp(k / n) for k in range(n + 1)]
            report[name] = {'source': sname, 'hit_frames': [h0, h1], 'source_range': [a, b]}
        else:
            times = [a + (b - a) * k / n for k in range(n + 1)]
    frames = []
    p0 = None
    for f in times:
        P = sample(act, f)
        pel = P['pelvis'][1] - P['root'][1] * 0
        frames.append(P)
    # horizontal drift (root motion baked into the pelvis) -> in place
    pel = np.array([P['pelvis'][1][:] for P in frames]); rest = np.array(Hs['pelvis'][:])
    off = pel - rest
    if opt.get('inplace') or loop:
        k = np.linspace(0, 1, len(off))[:, None]
        drift = off[0, :2] * (1 - k) + off[-1, :2] * k
        if loop: drift = np.repeat(off[:, :2].mean(0)[None], len(off), 0) * 0 + (off[0, :2] * (1 - k) + off[-1, :2] * k)
        off[:, :2] -= drift
    new = bpy.data.actions.new(name)
    set_action(rig, new)
    prev = {}
    for k, P in enumerate(frames):
        Qw = {}
        for bname in order:
            qs = P[INV[bname]][0]
            D = qs @ Rs[INV[bname]].inverted()
            Qw[bname] = D @ A[bname] @ Rt[bname]
            par = rig.data.bones[bname].parent
            if par is None: basis = Rt[bname].inverted() @ Qw[bname]
            else: basis = (Qw[par.name] @ (Rt[par.name].inverted() @ Rt[bname])).inverted() @ Qw[bname]
            if bname in prev and prev[bname].dot(basis) < 0: basis = -basis
            prev[bname] = basis
            pb = rig.pose.bones[bname]; pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = basis
            pb.keyframe_insert('rotation_quaternion', frame=k)
        w = Vector(off[k]) * HIP_SCALE
        w.z += stance_drop
        pb = rig.pose.bones['Hips']; pb.location = Rt['Hips'].inverted() @ w
        pb.keyframe_insert('location', frame=k)
    for fc in (new.fcurves if hasattr(new, 'fcurves') and len(new.fcurves) else []):
        for kp in fc.keyframe_points: kp.interpolation = 'LINEAR'
    new.use_fake_user = True
    baked[name] = (new, n, loop)
    report.setdefault(name, {'source': sname, 'source_range': [a, b]}).update({'frames': n, 'seconds': n / FPS, 'loop': loop})
    print('baked %-9s from %-14s %3d frames (%.3f s)%s' % (name, sname, n, n / FPS, ' loop' if loop else ''))
json.dump(report, open(os.path.join(WORK, 'anim_report.json'), 'w'), indent=1)
bpy.data.objects.remove(src)

# ---------------------------------------------------------------- contact sheets (flat texture colours, game camera)
flat_tex_shading(); sc.render.film_transparent = True
rig.hide_render = True
P_ = os.path.join(PREV, '_parts'); os.makedirs(P_, exist_ok=True)
cam = ortho_cam('iso', -45, 35, target=(0, 0, 0.8), scale=2.3)
STRIP = 6
for name, (act, n, loop) in baked.items():
    set_action(rig, act)
    for i in range(STRIP):
        f = n * i / (STRIP if loop else STRIP - 1)
        sc.frame_set(int(round(f)))
        render(os.path.join(P_, f'anim_{name}_{i}.png'), cam, res=(380, 480), transparent=True)

# ---------------------------------------------------------------- NLA tracks, save, export
ad = rig.animation_data; ad.action = None
for pb in rig.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
for name, (act, n, loop) in baked.items():
    tr = ad.nla_tracks.new(); tr.name = name
    st = tr.strips.new(name, 0, act); st.name = name
    tr.mute = True
sc.frame_set(0); sc.frame_start = 0; sc.frame_end = 30
rig.hide_render = False
bpy.ops.file.make_paths_relative() if False else None
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'moxie.blend'))
OUT = os.path.join(ROOT, 'assets', 'models', 'candidates', 'e', 'moxie.glb')
bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True); mesh.select_set(True); bpy.context.view_layer.objects.active = rig
for tr in ad.nla_tracks: tr.mute = False
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True, export_apply=False,
                          export_animations=True, export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_optimize_animation_size=False,
                          export_anim_slide_to_zero=True, export_skins=True, export_def_bones=False, export_rest_position_armature=True,
                          export_materials='EXPORT', export_image_format='AUTO', export_normals=True, export_tangents=False, export_morph=False,
                          export_cameras=False, export_lights=False, export_extras=False)
print('exported', OUT, os.path.getsize(OUT))
