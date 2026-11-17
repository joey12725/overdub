import bpy, bmesh, sys, os, json, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
from mathutils import Vector
from mathutils.bvhtree import BVHTree
U.open_stage("s04_hair")
b = bpy.data.objects["Body"]; rig = bpy.data.objects["MH_Rig"]
for n in ["root", "spine05", "spine04", "spine03", "spine02", "spine01", "neck01", "head", "clavicle.L", "shoulder01.L", "upperarm01.L", "upperarm02.L", "lowerarm01.L", "lowerarm02.L", "wrist.L",
          "pelvis.L", "upperleg01.L", "upperleg02.L", "lowerleg01.L", "lowerleg02.L", "foot.L", "toe1-1.L", "toe3-1.L", "finger2-1.L", "finger2-2.L", "finger2-3.L", "finger1-1.L", "metacarpal2.L", "breast.L"]:
    bn = rig.data.bones[n]
    print("%-14s head %s tail %s" % (n, tuple(round(c, 3) for c in bn.head_local), tuple(round(c, 3) for c in bn.tail_local)))
bm = bmesh.new(); bm.from_mesh(b.data); bvh = BVHTree.FromBMesh(bm)
for z in (0.10, 0.2, 0.5, 0.8, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3):
    out = []
    for az in (0, 90, 180):
        d = Vector((math.sin(math.radians(az)), -math.cos(math.radians(az)), 0))
        o = Vector((0, 0, z))
        # outermost hit: cast from far away inward
        h = bvh.ray_cast(o + d * 1.0, -d, 1.0)
        out.append(round((h[0] - o).length, 3) if h[0] else None)
    print("z %.2f torso/outer radius front %s left %s back %s" % (z, out[0], out[1], out[2]))
co = np.array([v.co[:] for v in b.data.vertices])
print("bbox", co.min(0).round(3), co.max(0).round(3))
print("tris", sum(len(p.vertices) - 2 for p in b.data.polygons))
