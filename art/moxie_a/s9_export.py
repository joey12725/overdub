"""Stage 9 - export assets/models/candidates/a/moxie.glb from art/moxie_a/moxie.blend (or a given
.blend): the clean deform skeleton `Rig`, the two skinned meshes, flat-colour materials, shape keys
and one glTF animation per game clip. The Rigify control rig and its constraints stay in the .blend.

    blender --background moxie.blend --python s9_export.py [-- out.glb]
"""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_util as U

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
out = args[0] if args else os.path.normpath(os.path.join(U.HERE, '..', '..', 'assets', 'models', 'candidates', 'a', 'moxie.glb'))
os.makedirs(os.path.dirname(out), exist_ok=True)

rig = bpy.data.objects['Rig']
keep = {rig, bpy.data.objects['Moxie'], bpy.data.objects['MoxieFace']}
for o in list(bpy.data.objects):          # the control rig, widgets, cameras... never ship
    if o not in keep:
        bpy.data.objects.remove(o)
for pb in rig.pose.bones:                  # the export skeleton must stand alone
    for c in list(pb.constraints):
        pb.constraints.remove(c)
    pb.matrix_basis.identity()
assert tuple(rig.location) == (0, 0, 0) and tuple(rig.scale) == (1, 1, 1) and tuple(rig.rotation_euler) == (0, 0, 0)
if rig.animation_data:
    rig.animation_data.action = None
    for t in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(t)
# one NLA track per clip: the exporter writes each track as its own glTF animation
rig.animation_data_create()
clips = sorted(a.name for a in bpy.data.actions if not a.name.startswith(('src_', 'rig_', 'WGT')) and a.get('source'))
for name in clips:
    act = bpy.data.actions[name]
    tr = rig.animation_data.nla_tracks.new(); tr.name = name
    st = tr.strips.new(name, int(act.frame_range[0]), act)
    st.name = name
    tr.mute = False
for o in bpy.data.objects:
    o.select_set(o in keep)
bpy.context.view_layer.objects.active = rig
bpy.context.scene.render.fps = 30
bpy.ops.export_scene.gltf(
    filepath=out, export_format='GLB', use_selection=True, export_yup=True,
    export_apply=False, export_skins=True, export_all_influences=False, export_def_bones=False,
    export_morph=True, export_morph_normal=False, export_normals=True, export_tangents=False,
    export_texcoords=False, export_materials='EXPORT', export_image_format='NONE',
    export_cameras=False, export_lights=False, export_extras=False,
    export_animations=True, export_animation_mode='NLA_TRACKS', export_force_sampling=True,
    export_frame_range=False, export_anim_slide_to_zero=True, export_optimize_animation_size=False,
    export_optimize_animation_keep_anim_armature=True, export_reset_pose_bones=True,
    export_rest_position_armature=True, export_bake_animation=False)
tris = sum(len(p.vertices) - 2 for o in keep if o.type == 'MESH' for p in o.data.polygons)
print('EXPORT OK', out, 'tris', tris, 'clips', clips, 'size', os.path.getsize(out))
