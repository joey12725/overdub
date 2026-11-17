"""Family line-up: the exported enemy .glb files side by side at true scale next to a 1.6-unit
scale bar (Moxie's height; a banded measuring staff, deliberately not a figure), front and
isometric. Re-importing the shipped files also proves they round-trip.

    blender --background --python art/enemies/common_lineup.py -- [type ...]
    (default: grunt stalker shielder drone; the other enemy types are added if their .glb exists
     and are named on the command line)

Writes art/previews/enemies/lineup_family_front.png, lineup_family_iso.png and
lineup_family_iso_small.png (the iso at roughly in-game pixel size: ~60 px per tile). The
"family_" prefix keeps these apart from common2_lineup.py's lineup_front/lineup_iso.png
(turret/brute/boss).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

import common as C  # noqa: E402


PLAYER_HEIGHT = 1.6


def scale_bar(x: float):
    """A neutral surveyor's staff, PLAYER_HEIGHT tall, banded every 0.2 units, on a small foot.
    It replaces the old humanoid stand-in, which was mistaken for a character: this is plainly a
    measuring stick. Returns (mesh parts, label objects)."""
    parts = []
    n = int(round(PLAYER_HEIGHT / 0.2))
    for i in range(n):
        seg = C.box(f"bar{i}", (0.05, 0.05, 0.2), loc=(0, 0, 0.1 + 0.2 * i),
                    mat="ceramic" if i % 2 == 0 else "metal")
        parts.append(seg)
    parts.append(C.box("bar_foot", (0.22, 0.22, 0.02), loc=(0, 0, 0.01), mat="metal"))
    parts.append(C.box("bar_top", (0.3, 0.05, 0.02), loc=(0, 0, PLAYER_HEIGHT - 0.01), mat="metal"))
    for p in parts:
        C.place(p, loc=(x, 0, 0))
    labels = []
    for text, z, size in ((f"{PLAYER_HEIGHT:g}", PLAYER_HEIGHT - 0.14, 0.13), ("player", PLAYER_HEIGHT - 0.27, 0.075),
                          ("height", PLAYER_HEIGHT - 0.36, 0.075), ("0", 0.03, 0.09)):
        cu = bpy.data.curves.new("label", "FONT")
        cu.body = text
        cu.size = size
        cu.align_x = "LEFT"
        cu.materials.append(C.material("ceramic"))
        ob = C.link(bpy.data.objects.new("label", cu))
        ob.location = (x + 0.19, 0, z)
        ob.rotation_euler = (1.5707963, 0, 0)      # upright, facing the front camera
        labels.append(ob)
    return parts, labels


def main():
    args = [a for a in C.script_args() if not a.startswith("--")]
    types = args or ["grunt", "stalker", "shielder", "drone"]
    C.reset_scene()
    objs, labels = scale_bar(0.0)
    groups = [list(objs) + labels]  # top-level objects per model, in order (scale bar first)
    x = 1.0
    for t in types:
        path = os.path.join(C.MODEL_DIR, f"{t}.glb")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
        top = [o for o in new if o.parent is None and o.type != "MESH"]
        for o in top:
            o.location.x += x
        for o in new:
            if o.type == "ARMATURE":
                if o.animation_data:
                    o.animation_data.action = None
                for pb in o.pose.bones:  # back to the rest pose (the importer leaves an action's pose)
                    pb.location = (0, 0, 0)
                    pb.rotation_quaternion = (1, 0, 0, 0)
                    pb.rotation_euler = (0, 0, 0)
                    pb.scale = (1, 1, 1)
        bpy.context.view_layer.update()
        groups.append(top)
        # The importer adds bone display shapes (unparented "Icosphere" meshes): not part of the model.
        for o in new:
            if o.type == "MESH" and o.parent is None:
                o.hide_render = True
        objs += [o for o in new if o.type == "MESH" and o.parent is not None]
        print(f"[lineup] {t}: {len(new)} objects ({', '.join(sorted(o.name for o in new))})")
        x += 1.0
    # Floor strip (front view only) so floor contact reads.
    bpy.ops.mesh.primitive_plane_add(size=1)
    floor = bpy.context.object
    floor.scale = (x + 0.6, 1.4, 1)
    floor.location = ((x - 1.0) / 2, 0, -0.001)
    floor.data.materials.append(C.material("screen"))
    out = C.PREVIEW_DIR
    os.makedirs(out, exist_ok=True)
    cam = C.camera()
    C.setup_render(1800, 700)
    C.frame_camera(cam, objs, 0.0, 0.0, margin=1.08)
    C.render_to(os.path.join(out, "lineup_family_front.png"))
    # Iso: re-space the models along the camera's screen-right axis so none overlaps.
    from mathutils import Vector
    right = Vector((0.7071, -0.7071, 0.0))
    for i, g in enumerate(groups):
        for o in g:
            o.location.x -= float(i)
            o.location += right * (i * 1.05)
    floor.hide_render = True
    bpy.context.view_layer.update()
    C.setup_render(1800, 900)
    C.frame_camera(cam, objs, 45.0, 35.0, margin=1.08)
    for lb in labels:   # billboard the labels to the isometric camera, offset along screen-right
        lb.rotation_euler = cam.rotation_euler
        lb.location = lb.location - Vector((0.19, 0, 0)) + right * 0.19
    C.render_to(os.path.join(out, "lineup_family_iso.png"))
    # Small copy: the 1.6-unit scale bar comes out about 100 px tall, close to in-game size.
    C.setup_render(520, 220)
    C.frame_camera(cam, objs, 45.0, 35.0, margin=1.08)
    C.render_to(os.path.join(out, "lineup_family_iso_small.png"))
    print(f"[lineup] wrote lineup_family_front.png, lineup_family_iso.png, lineup_family_iso_small.png in {out}")


if __name__ == "__main__":
    main()
