"""Stage 7 - retarget off-the-shelf humanoid animation onto Moxie's skeleton.

Source: Quaternius' Universal Animation Library (standard, CC0) - src_dl/ual/*.gltf.
Method: world-space rotation deltas relative to a shared T-pose (the library's `A_TPose` clip vs our
rest pose), hips translation scaled by hip height. One-shots are retimed to exactly 1.0 s; `light`
and `heavy` are time-warped so the wind-up is 0-40 %, the hit 40-60 % and the recovery 60-100 %.
Reads work/s6.blend, saves work/s7.blend with one action per game clip on `Rig`.

    blender --background --python s7_anim.py            # the game clips
    blender --background --python s7_anim.py -- raw A,B # raw source clips as actions src_A, src_B
"""
import bpy, sys, os, math
from mathutils import Matrix, Vector, Quaternion
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_util as U

FPS = 30
UAL = os.path.join(U.HERE, 'src_dl', 'ual', 'AnimationLibrary_Godot_Standard.gltf')

MAP = {'Hips': 'DEF-hips', 'Spine': 'DEF-spine.001', 'Chest': 'DEF-spine.002', 'UpperChest': 'DEF-spine.003',
       'Neck': 'DEF-neck', 'Head': 'DEF-head'}
for s, S in (('L', 'Left'), ('R', 'Right')):
    MAP.update({S + 'Shoulder': 'DEF-shoulder.' + s, S + 'UpperArm': 'DEF-upper_arm.' + s, S + 'LowerArm': 'DEF-forearm.' + s,
                S + 'Hand': 'DEF-hand.' + s, S + 'UpperLeg': 'DEF-thigh.' + s, S + 'LowerLeg': 'DEF-shin.' + s,
                S + 'Foot': 'DEF-foot.' + s, S + 'Toes': 'DEF-toe.' + s,
                S + 'ThumbMetacarpal': 'DEF-thumb.01.' + s, S + 'ThumbProximal': 'DEF-thumb.02.' + s,
                S + 'ThumbDistal': 'DEF-thumb.03.' + s})
    for f, g in (('Index', 'index'), ('Middle', 'middle'), ('Ring', 'ring'), ('Little', 'pinky')):
        for i, seg in ((1, 'Proximal'), (2, 'Intermediate'), (3, 'Distal')):
            MAP[S + f + seg] = 'DEF-f_%s.0%d.%s' % (g, i, s)

# game clip -> (source clip, loop, [source frame range or None], warp)
#   warp for light/heavy: (hit_start, hit_end) as fractions of the used source range
CLIPS = {
    'idle': ('Idle_Loop', True, None, None),
    'run': ('Jog_Fwd_Loop', True, None, None),
    'stopped': ('Sword_Idle', True, None, None),
    'light': ('Punch_Cross', False, None, (0.20, 0.45)),
    'heavy': ('Sword_Attack', False, None, (0.27, 0.50)),
    'dodge': ('Roll', False, None, None),
    'ranged': ('Spell_Simple_Shoot', False, None, None),
    'interact': ('Interact', False, None, None),
    'death': ('Death01', False, None, None),
}


def find_action(name):
    for a in bpy.data.actions:
        if a.name == name or a.name.startswith(name + '_') and a.name.split('_')[-1] in ('Armature', 'Rig'):
            return a
    for a in bpy.data.actions:
        if a.name.split('.')[0] == name:
            return a
    raise KeyError(name)


def sample_source(src, action, frames):
    """Armature-space matrices of every mapped source bone at each (float) frame."""
    src.animation_data_create()
    src.animation_data.action = action
    try:
        if action.slots:
            src.animation_data.action_slot = action.slots[0]
    except Exception:
        pass
    out = []
    sc = bpy.context.scene
    for f in frames:
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        out.append({b: src.pose.bones[b].matrix.copy() for b in set(MAP.values())})
    return out


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    raw = args[1].split(',') if args and args[0] == 'raw' else None
    bpy.ops.wm.open_mainfile(filepath=os.path.join(U.WORK, 's6.blend'))
    sc = bpy.context.scene
    sc.render.fps = FPS
    rig = bpy.data.objects['Rig']
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=UAL)
    new = [o for o in bpy.data.objects if o not in before]
    src = [o for o in new if o.type == 'ARMATURE'][0]
    print('source actions', len(bpy.data.actions), 'src scale', src.scale[:], src.rotation_euler[:])
    src_fps = FPS

    # shared reference: the library's T-pose clip vs our rest pose
    tp = find_action('A_TPose')
    ref = sample_source(src, tp, [tp.frame_range[0]])[0]
    src_hip_h = ref['DEF-hips'].translation.z
    tgt_rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    tgt_hip_h = tgt_rest['Hips'].translation.z
    scale = tgt_hip_h / src_hip_h
    print('hip height src %.3f tgt %.3f scale %.3f' % (src_hip_h, tgt_hip_h, scale))
    order = [b.name for b in rig.data.bones if b.name in MAP]   # parents first
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'

    def retarget(name, src_name, loop, rng, warp):
        act = find_action(src_name)
        f0, f1 = act.frame_range
        if rng:
            f0, f1 = rng
        if loop:
            n = int(round(f1 - f0))
            times = [i / FPS for i in range(n + 1)]
            frames = [f0 + i for i in range(n + 1)]
        else:
            n = FPS  # exactly 1.0 s
            times = [i / FPS for i in range(n + 1)]
            if warp:
                a, b = warp
                def w(t):
                    if t < 0.4:
                        return a * t / 0.4
                    if t < 0.6:
                        return a + (b - a) * (t - 0.4) / 0.2
                    return b + (1 - b) * (t - 0.6) / 0.4
            else:
                w = lambda t: t
            frames = [f0 + (f1 - f0) * w(t) for t in times]
        poses = sample_source(src, act, frames)
        new_act = bpy.data.actions.new(name)
        new_act.use_fake_user = True
        rig.animation_data_create()
        rig.animation_data.action = new_act
        keys = {b: [] for b in order}
        hip_keys = []
        for P in poses:
            world = {}
            for b in order:
                Sb = P[MAP[b]].to_3x3().normalized(); Sr = ref[MAP[b]].to_3x3().normalized()
                Wb = Sb @ Sr.inverted() @ tgt_rest[b].to_3x3()
                world[b] = Wb
                par = rig.data.bones[b].parent
                Rb = tgt_rest[b].to_3x3()
                if par and par.name in world:
                    Wp = world[par.name]; Rp = tgt_rest[par.name].to_3x3()
                    basis = (Wp @ Rp.inverted() @ Rb).inverted() @ Wb
                else:
                    basis = Rb.inverted() @ Wb
                keys[b].append(basis.to_quaternion())
            dp = (P['DEF-hips'].translation - ref['DEF-hips'].translation) * scale
            hip_keys.append(tgt_rest['Hips'].to_3x3().inverted() @ dp)
        if loop:   # make the last key identical to the first
            for b in order:
                keys[b][-1] = keys[b][0].copy()
            hip_keys[-1] = hip_keys[0].copy()
        for b in order:
            prev = None
            for q in keys[b]:
                if prev is not None and prev.dot(q) < 0:
                    q.negate()
                prev = q
            pb = rig.pose.bones[b]
            for i, t in enumerate(times):
                pb.rotation_quaternion = keys[b][i]
                pb.keyframe_insert('rotation_quaternion', frame=t * FPS, group=b)
        pb = rig.pose.bones['Hips']
        for i, t in enumerate(times):
            pb.location = hip_keys[i]
            pb.keyframe_insert('location', frame=t * FPS, group='Hips')
        for fc in (new_act.fcurves if hasattr(new_act, 'fcurves') else []):
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR'
        new_act['loop'] = bool(loop)
        new_act['source'] = 'Quaternius Universal Animation Library (CC0): ' + src_name
        print('clip %-9s <- %-20s frames %d length %.3fs' % (name, src_name, len(times), times[-1]))
        return new_act

    made = []
    if raw:
        for nme in raw:
            made.append(retarget('src_' + nme, nme, True, None, None))
    else:
        for nme, (srcn, loop, rng, warp) in CLIPS.items():
            made.append(retarget(nme, srcn, loop, rng, warp))
    # remove the library objects and its actions
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    for o in new:
        bpy.data.objects.remove(o)
    for a in list(bpy.data.actions):
        if a not in made:
            bpy.data.actions.remove(a)
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(U.WORK, 's7_raw.blend' if raw else 's7.blend'))
    print('S7 OK', [a.name for a in bpy.data.actions])


if __name__ == '__main__':
    main()
