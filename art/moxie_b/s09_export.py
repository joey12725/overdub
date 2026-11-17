"""Stage 9: export assets/models/candidates/b/moxie.glb.
One skinned mesh 'Moxie' + armature 'Rig' (identity transform, T-pose rest), textures embedded,
the nine retargeted clips as glTF animations. -Y forward in Blender becomes +Z forward in Godot."""
import bpy, sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
from mathutils import Matrix

U.open_stage("s08_anim")
rig = bpy.data.objects["Rig"]
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in list(bpy.data.objects):
    if o.type not in ('MESH', 'ARMATURE'):
        bpy.data.objects.remove(o)
for o in meshes:
    for a in list(o.data.attributes):
        if a.name in ("eye_ring", "eye_side", "eye_partner", "rigid_bone"):
            o.data.attributes.remove(a)
body = bpy.data.objects["Body"]
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "Moxie"
body.data.name = "Moxie"
# drop unused material slots and empty vertex groups
bpy.ops.object.material_slot_remove_unused()
used = set()
for v in body.data.vertices:
    for g in v.groups:
        if g.weight > 0:
            used.add(g.group)
for g in [g for g in body.vertex_groups if g.index not in used]:
    body.vertex_groups.remove(g)
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
mats = [m.name for m in body.data.materials]
print("TRIS", tris, "MATERIALS", len(mats), mats)

# clips -> NLA tracks (one glTF animation per track)
ad = rig.animation_data or rig.animation_data_create()
ad.action = None
order = ["idle", "run", "stopped", "light", "heavy", "dodge", "ranged", "interact", "death"]
for name in order:
    act = bpy.data.actions[name]
    tr = ad.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(act.frame_range[0]), act)
    st.name = name
bpy.context.scene.frame_start = 0
bpy.context.scene.frame_end = 80
bpy.context.scene.render.fps = 30
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)

out_dir = os.path.join(U.REPO, "assets", "models", "candidates", "b")
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, "moxie.glb")
bpy.ops.export_scene.gltf(
    filepath=out, export_format='GLB', use_selection=False, export_yup=True, export_apply=False,
    export_skins=True, export_all_influences=False, export_morph=False, export_cameras=False, export_lights=False,
    export_animations=True, export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_frame_range=False,
    export_optimize_animation_size=False, export_anim_single_armature=True, export_reset_pose_bones=True,
    export_image_format='AUTO', export_materials='EXPORT', export_extras=False, export_def_bones=False,
    export_rest_position_armature=True)
print("EXPORTED", out, os.path.getsize(out))
with open(os.path.join(U.STAGE, "export_report.json"), "w") as fh:
    json.dump({"triangles": tris, "materials": mats, "bones": [b.name for b in rig.data.bones]}, fh, indent=1)
U.save_stage("s09_export")
