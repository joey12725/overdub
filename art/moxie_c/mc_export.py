"""glTF export: blender --background art/moxie_c/moxie_anim.blend --python art/moxie_c/mc_export.py

Writes assets/models/candidates/c/moxie.glb: armature `Rig` (clean humanoid deform skeleton, rest =
T-pose, identity object transform) + one skinned mesh `Moxie`, every contract clip as a glTF
animation, textures embedded, +Y up, metres (she faces +Z in Godot)."""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "models", "candidates", "c", "moxie.glb"))


def main():
    import mc_rig
    rig = bpy.data.objects["Rig"]
    body = bpy.data.objects["Moxie"]
    for ob in list(bpy.data.objects):
        if ob not in (rig, body):
            bpy.data.objects.remove(ob, do_unlink=True)
    assert all(abs(v) < 1e-9 for v in rig.location) and all(abs(v - 1) < 1e-9 for v in rig.scale)
    assert all(abs(v) < 1e-9 for v in rig.rotation_euler)
    if rig.animation_data:
        rig.animation_data.action = None
    mc_rig.reset_pose(rig)
    bpy.context.scene.frame_set(0)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format='GLB', use_selection=True, export_yup=True, export_apply=False,
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_materials='EXPORT', export_image_format='AUTO',
        export_cameras=False, export_lights=False, export_skins=True, export_all_influences=False,
        export_def_bones=False, export_rest_position_armature=True,
        export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
        export_frame_range=False, export_anim_slide_to_zero=True, export_optimize_animation_size=False,
        export_optimize_animation_keep_anim_armature=True, export_nla_strips=True,
        export_morph=False, export_extras=False)
    print("EXPORTED", OUT, os.path.getsize(OUT))


main()
