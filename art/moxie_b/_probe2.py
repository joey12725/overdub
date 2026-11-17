import bpy, sys, os, json, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
U.open_stage("s02_body")
b = bpy.data.objects["Body"]; me = b.data
ring = np.array([d.value for d in me.attributes["eye_ring"].data]); side = np.array([d.value for d in me.attributes["eye_side"].data])
part = np.array([d.value for d in me.attributes["eye_partner"].data])
co = np.array([v.co[:] for v in me.vertices])
L = json.loads(b["landmarks"])
c = np.array([L["eye_x"], 0, L["z_eye"]])
for r in (11, 12, 13, 14, 16, -1):
    ids = np.where((ring == r) & (side == 1))[0]
    d = co[ids] - c
    a = np.degrees(np.arctan2(d[:, 2], d[:, 0])); rad = np.hypot(d[:, 0], d[:, 2])
    o = np.argsort(a)
    print("ring", r, len(ids))
    print("  ang", a[o].round(0).tolist())
    print("  rad", (rad[o] * 1000).round(1).tolist())
    print("  y", (co[ids][o][:, 1] * 1000).round(1).tolist())
