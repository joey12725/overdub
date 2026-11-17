"""glTF export of Moxie per docs/GODOT-PORT.md: Rig + skinned mesh `Moxie`, every action as a
separately named animation, no cameras/lights, base-colour materials (face_paint carries the
painted face texture), metres, +Y up (she faces +Z in Godot).

The rig is posed in the contract T-pose (mx_contract.t_pose) and exported with
export_rest_position_armature=False: the joint nodes (Godot's bone rests) carry that T-pose while
the inverse bind matrices keep the A-pose the mesh is bound in."""
import os

import bpy


def export(rig, path, rest_pose=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    body = bpy.data.objects["Moxie"]
    for ob in bpy.context.scene.objects:
        ob.select_set(False)
    rig.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    rig.animation_data.action = None
    bpy.context.scene.frame_set(0)
    for pb in rig.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    if rest_pose is not None:
        rest_pose(rig)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_cameras=False,
        export_lights=False,
        export_skins=True,
        export_all_influences=False,
        export_def_bones=False,
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_force_sampling=True,
        export_frame_step=1,
        export_reset_pose_bones=True,
        export_rest_position_armature=False,
        export_anim_single_armature=True,
        export_morph=False,
    )
    print("EXPORTED", path, os.path.getsize(path))
