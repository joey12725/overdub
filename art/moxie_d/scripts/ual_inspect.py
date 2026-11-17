import bpy, sys
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=sys.argv[-1])
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
print("ARM", arm.name, arm.matrix_world)
for b in arm.data.bones:
    print("BONE", b.name, "<-", b.parent.name if b.parent else None, [round(v, 3) for v in (arm.matrix_world @ b.head_local)], [round(v, 3) for v in (arm.matrix_world @ b.tail_local)])
for a in sorted(bpy.data.actions, key=lambda a: a.name): print("ACT", a.name, a.frame_range[:])
print("FPS", bpy.context.scene.render.fps)
