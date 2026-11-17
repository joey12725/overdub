"""Stage 6 - assemble: weld the skin, join everything into two meshes (`Moxie`, and `MoxieFace`
which carries the expression shape keys), stand her on the floor (boot soles at z = 0), clean and
normalise the skin weights (max 4 influences). Reads work/s5.blend, saves work/s6.blend.
"""
import bpy, bmesh, sys, os
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_util as U

LIFT = 0.039   # boot sole + tread


def main():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(U.WORK, 's5.blend'))
    rig = bpy.data.objects['Rig']
    ref = bpy.data.objects.get('BodyRef')
    if ref:
        bpy.data.objects.remove(ref)
    body = bpy.data.objects['Body']
    bm = bmesh.new(); bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bm.to_mesh(body.data); bm.free()
    parts = [bpy.data.objects[n] for n in ('Body', 'Hair', 'Top', 'Pants', 'Gloves', 'OutfitParts', 'Gear', 'Jacket')]
    for o in parts:
        # drop UV layers / colour attributes: flat-colour materials only
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
    mox = U.join(parts, 'Moxie')
    face = bpy.data.objects['Face']; face.name = 'MoxieFace'; face.data.name = 'MoxieFace'
    while face.data.uv_layers:
        face.data.uv_layers.remove(face.data.uv_layers[0])

    # lift so the soles rest on z = 0
    for o in (mox, face):
        for v in o.data.vertices:
            v.co.z += LIFT
        if o.data.shape_keys:
            for kb in o.data.shape_keys.key_blocks:
                for d in kb.data:
                    d.co.z += LIFT
        o.data.update()
    U.active(rig, 'EDIT')
    for eb in rig.data.edit_bones:
        if eb.name != 'Root':
            eb.head.z += LIFT; eb.tail.z += LIFT
    bpy.ops.object.mode_set(mode='OBJECT')

    for o in (mox, face):
        U.active(o)
        # remove groups that are not bones, limit to 4 influences, normalise
        for vg in list(o.vertex_groups):
            if vg.name not in rig.data.bones:
                o.vertex_groups.remove(vg)
        bpy.ops.object.vertex_group_clean(group_select_mode='ALL', limit=0.002)
        bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
        # any vertex left without weights follows the head (face) or hips
        fallback = 'Head' if o is face else 'Hips'
        vg = o.vertex_groups.get(fallback) or o.vertex_groups.new(name=fallback)
        lone = [v.index for v in o.data.vertices if not v.groups]
        if lone:
            vg.add(lone, 1.0, 'REPLACE')
            print('unweighted ->', fallback, len(lone), o.name)
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        md = o.modifiers.new('Armature', 'ARMATURE'); md.object = rig
        o.parent = rig
    # tidy materials: one slot per material name
    for o in (mox, face):
        U.active(o)
        bpy.ops.object.material_slot_remove_unused()
    for im in list(bpy.data.images):
        if im.users == 0:
            bpy.data.images.remove(im)
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    zs = [v.co.z for v in mox.data.vertices]
    tris = sum(len(p.vertices) - 2 for o in (mox, face) for p in o.data.polygons)
    print('S6 OK tris', tris, 'z', min(zs), max(zs), 'mats', len(mox.data.materials), len(face.data.materials),
          'bones', len(rig.data.bones))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(U.WORK, 's6.blend'))


if __name__ == '__main__':
    main()
