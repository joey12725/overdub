"""Step 2 (Blender): registered generator meshes -> one clean game mesh with UVs.

  work/body_w.ply  cut at the choker (head removed, capped), floaters removed, decimated to ~44k tris  -> material 'body'
  work/head_w.ply  cut under the choker (bust removed, capped), decimated to ~28k tris                   -> material 'head'
  The neck seam is hidden inside the choker (the head part carries the choker).
Writes work/mesh.blend and work/mesh.npz (arrays for the projection baker, s3_texture.py)."""
import bpy, bmesh, sys, os, json
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import *
from mathutils import Vector

A = json.load(open(os.path.join(WORK, 'align.json')))
BODY_TRIS, HEAD_TRIS = 44000, 28000
Z_BODY_TOP, Z_HEAD_BOTTOM = 1.302, 1.293


def imp(name):
    bpy.ops.wm.ply_import(filepath=os.path.join(WORK, name + '.ply'))
    ob = bpy.context.selected_objects[0]; ob.name = name
    bpy.context.view_layer.objects.active = ob
    return ob


def cut(ob, z, keep_above):
    bm = bmesh.new(); bm.from_mesh(ob.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    r = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_outer=not keep_above, clear_inner=keep_above)
    edges = [e for e in r['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
    bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data); bm.free()


def drop_floaters(ob, min_frac=0.004, protect=None):
    """delete loose islands smaller than min_frac of the biggest island (by vertex count)"""
    bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
    seen = np.zeros(len(bm.verts), bool); islands = []
    for v in bm.verts:
        if seen[v.index]: continue
        stack = [v]; seen[v.index] = True; isl = []
        while stack:
            a = stack.pop(); isl.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if not seen[b.index]: seen[b.index] = True; stack.append(b)
        islands.append(isl)
    big = max(len(i) for i in islands)
    kill = [v for isl in islands if len(isl) < big * min_frac for v in isl]
    print(ob.name, 'islands', len(islands), 'sizes', sorted((len(i) for i in islands), reverse=True)[:8], 'removing verts', len(kill))
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    bm.to_mesh(ob.data); bm.free()


def decimate(ob, tris):
    bpy.context.view_layer.objects.active = ob
    m = ob.modifiers.new('dec', 'DECIMATE'); m.ratio = tris / len(ob.data.polygons); m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier='dec')
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data); bm.free()
    for p in ob.data.polygons: p.use_smooth = True
    print(ob.name, 'tris', len(ob.data.polygons), 'verts', len(ob.data.vertices))


def unwrap(ob):
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.004, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.004, rotate=True)
    bpy.ops.object.mode_set(mode='OBJECT')


reset()
body = imp('body_w'); cut(body, Z_BODY_TOP, keep_above=False); drop_floaters(body); decimate(body, BODY_TRIS)
head = imp('head_w'); cut(head, Z_HEAD_BOTTOM, keep_above=True); drop_floaters(head); decimate(head, HEAD_TRIS)
# floor: put the lowest boot sole exactly on Z=0
zmin = min(v.co.z for v in body.data.vertices)
for ob in (body, head):
    for v in ob.data.vertices: v.co.z -= zmin
print('floor shift', zmin)
for ob, mn in ((body, 'body'), (head, 'head')):
    unwrap(ob)
    mat = bpy.data.materials.new(mn); ob.data.materials.append(mat)
bpy.ops.object.select_all(action='DESELECT'); head.select_set(True); body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active; ob.name = 'Moxie'; ob.data.name = 'Moxie'
me = ob.data
me.calc_loop_triangles()
co = np.array([v.co[:] for v in me.vertices], np.float32)
no = np.array([v.normal[:] for v in me.vertices], np.float32)
tri = np.array([t.vertices[:] for t in me.loop_triangles], np.int32)
tl = np.array([t.loops[:] for t in me.loop_triangles], np.int32)
uv = np.array([d.uv[:] for d in me.uv_layers.active.data], np.float32)
mat = np.array([me.polygons[t.polygon_index].material_index for t in me.loop_triangles], np.int8)
np.savez_compressed(os.path.join(WORK, 'mesh.npz'), co=co, no=no, tri=tri, uv=uv[tl], mat=mat, zshift=zmin)
print('final', len(tri), 'tris; bounds', co.min(0), co.max(0))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, 'mesh.blend'))
paths = []
for i, (yaw, pitch) in enumerate(((0, 5), (45, 35), (90, 5), (180, 5), (-90, 5))):
    cam = ortho_cam(f'c{i}', yaw, pitch, target=(0, 0, 0.8), scale=1.85)
    p = os.path.join(WORK, f'_m_{i}.png'); render(p, cam, res=(500, 640)); paths.append(p)
for i, (yaw, pitch) in enumerate(((0, 0), (35, 10), (90, 0), (180, 0), (-35, 10))):
    cam = ortho_cam(f'h{i}', yaw, pitch, target=(0, 0, 1.44), scale=0.52)
    p = os.path.join(WORK, f'_mh_{i}.png'); render(p, cam, res=(500, 640)); paths.append(p)
contact_sheet(paths, os.path.join(WORK, 'view_mesh.png'), cols=5)
for p in paths: os.remove(p)
