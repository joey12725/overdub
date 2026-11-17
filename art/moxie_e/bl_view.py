"""Clay check of raw generator outputs: blender -b --python bl_view.py -- <out.png> <a.glb> [b.glb ...]
Each mesh is normalised to 1.6 m tall, feet on the floor, and shown from front / 3-4 / side / back (+ a head close-up row)."""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import *
from mathutils import Matrix
argv = sys.argv[sys.argv.index('--') + 1:]
out, glbs = os.path.abspath(argv[0]), [a if a.startswith("--") else os.path.abspath(a) for a in argv[1:]]
flags = [a for a in glbs if a.startswith('--')]; glbs = [a for a in glbs if not a.startswith('--')]
head = '--head' in flags; full = '--full' in flags
paths = []
for gi, g in enumerate(glbs):
    reset()
    bpy.ops.import_scene.gltf(filepath=g)
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs: o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1: bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM'); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    import numpy as np
    co = np.array([v.co[:] for v in ob.data.vertices])
    mn, mx = co.min(0), co.max(0)
    s = 1.6 / (mx[2] - mn[2])
    ob.data.transform(Matrix.Translation((-(mn[0] + mx[0]) / 2 * s, -(mn[1] + mx[1]) / 2 * s, -mn[2] * s)) @ Matrix.Scale(s, 4))
    print(os.path.basename(g), 'tris', len(ob.data.polygons), 'size', (mx - mn) * s)
    bpy.ops.object.shade_smooth()
    views = ((0, 5), (45, 35), (90, 5), (180, 5), (-90, 5))
    for i, (yaw, pitch) in enumerate(views):
        cam = ortho_cam(f'c{i}', yaw, pitch, target=(0, 0, 0.8), scale=1.85)
        if full: cam.data.ortho_scale = 2.3
        p = os.path.join(WORK, f'_v_{gi}_{i}.png'); render(p, cam, res=(500, 640)); paths.append(p)
    if head:
        for i, (yaw, pitch) in enumerate(views):
            cam = ortho_cam(f'h{i}', yaw, pitch if yaw != 45 else 15, target=(0, 0, 1.40), scale=0.62)
            p = os.path.join(WORK, f'_vh_{gi}_{i}.png'); render(p, cam, res=(500, 640)); paths.append(p)
contact_sheet(paths, out, cols=5)
for p in paths: os.remove(p)
