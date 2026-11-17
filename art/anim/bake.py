"""Bake every clip in clips.py to art/anim/baked/moxie_clips.json (the skeleton-neutral source the
Godot library builder reads). Plain Python: `python -I art/anim/bake.py [clip-name-filter]`.

Per clip and frame (60 fps): hips position, each bone's MODEL-SPACE DELTA rotation from the T-pose
(quaternion x, y, z, w), and the right hand's grip: position, weapon direction (+Y of the weapon)
and edge direction (+Z of the weapon), plus the left palm position."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import od_rig as rig
import clips as clipdefs


def bake_all(name_filter=""):
    out = {"version": 1, "fps": 60, "hip_height": rig.HIP_HEIGHT, "bones": rig.NAMES,
           "parents": [rig.PARENT[n] or "" for n in rig.NAMES],
           "rest": [[round(float(x), 5) for x in rig.REST[n]] for n in rig.NAMES],
           "grip_offset_right": rig.GRIP_OFFSET["Right"].tolist(), "grip_offset_left": rig.GRIP_OFFSET["Left"].tolist(),
           "style_of_item": clipdefs.STYLE_OF_ITEM, "two_handed": clipdefs.TWO_HANDED, "clips": []}
    warns = []
    baked = {}
    for c in clipdefs.all_clips():
        if name_filter and name_filter not in c.name:
            continue
        frames, w = c.bake()
        warns += w
        baked[c.name] = (c, frames)
        prev = None
        rot = []
        for s in frames:
            row = []
            for i, n in enumerate(rig.NAMES):
                q = rig.m2q(s.D[n])
                if prev is not None and float(np.dot(prev[i], q)) < 0:
                    q = -q
                row.append(q)
            prev = row
            rot.append([[round(float(x), 5) for x in q] for q in row])
        r3 = lambda a: [round(float(x), 4) for x in a]
        out["clips"].append({
            "name": c.name, "length": c.length, "loop": c.loop, "meta": c.meta,
            "hips": [r3(s.P["Hips"]) for s in frames], "rot": rot,
            "grip": [r3(s.grip) for s in frames], "w": [r3(s.w) for s in frames], "e": [r3(s.e) for s in frames],
            "lgrip": [r3(s.lgrip) for s in frames]})
    return out, warns, baked


if __name__ == "__main__":
    flt = sys.argv[1] if len(sys.argv) > 1 else ""
    data, warns, _ = bake_all(flt)
    seen = {}
    for w in warns:
        k = w.split(" f")[0] + w.split(":")[1]
        seen.setdefault(k, []).append(w)
    for k, v in seen.items():
        print("WARN", v[0], "(+%d frames)" % (len(v) - 1))
    if not flt:
        d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "baked")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "moxie_clips.json"), "w") as f:
            json.dump(data, f, separators=(",", ":"))
        print("wrote", len(data["clips"]), "clips,", os.path.getsize(os.path.join(d, "moxie_clips.json")) // 1024, "KB")
