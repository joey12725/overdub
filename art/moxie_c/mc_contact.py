"""Animation contact sheets: blender --background moxie_anim.blend --python mc_contact.py -- [clip,...] [--toon]"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
PREV = os.path.abspath(os.path.join(HERE, "..", "previews", "moxie_c"))
import mc_render as R  # noqa: E402
import mc_anim  # noqa: F401,E402  (not run: guarded below)

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
toon = "--toon" in a
names = [x for x in a if not x.startswith("--")]
names = names[0].split(",") if names else [c[0] for c in mc_anim.CLIPS]
rig = bpy.data.objects["Rig"]
R.setup('toon' if toon else 'soft')
if toon:
    R.apply_toon(outline=0.0045)
R.floor(True, r=1.0)
N = 8
os.makedirs(PREV, exist_ok=True)
for nm in names:
    act = bpy.data.actions[nm]
    mc_anim._set_action(rig, act)
    last = act.frame_range[1]
    for i in range(N):
        f = last * i / (N - 1) if not act.get("loop") else last * i / N
        bpy.context.scene.frame_set(int(f), subframe=f - int(f))
        R.render(os.path.join(PREV, "_c_%s_%d.png" % (nm, i)), (0, 0, 0.82), 38, 12, 2.15, (400, 440))
print("CONTACT DONE")
