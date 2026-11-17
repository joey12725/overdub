"""Contact sheets of the retargeted clips on the final model (toon + outline).
Usage: blender -b --python render_anim.py -- [clip ...]   -> art/previews/moxie_b/contact_<clip>.png"""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
import mb_toon as T

U.open_stage("s08_anim")
rig = bpy.data.objects["Rig"]
rig.hide_render = True
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
T.toonify(meshes, outline=0.0028)
clips = U.args() or ["idle", "run", "stopped", "light", "heavy", "dodge", "ranged", "interact", "death"]
N = 7
for c in clips:
    act = bpy.data.actions[c]
    rig.animation_data_create()
    rig.animation_data.action = act
    try:
        if rig.animation_data.action_slot is None:
            rig.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    a, b = act.frame_range
    tiles = []
    for i in range(N):
        f = a + (b - a) * i / (N - 1) if c != "stopped" else a
        bpy.context.scene.frame_set(int(round(f)))
        p = os.path.join(U.WIP, "c_%s_%d.png" % (c, i))
        U.render_views(p, views=((40, 12),), center=(0, -0.05, 0.8), scale=2.3, res=(400, 560), setup=T.setup_eevee)
        tiles.append(p)
        if c == "stopped" and i == 1:
            break
    U.stitch(tiles, os.path.join(U.PREV, "contact_%s.png" % c))
