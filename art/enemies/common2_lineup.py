"""Line-up of exported enemies at true relative scale beside a neutral 1.6-unit scale bar.

    blender --background --python art/enemies/common2_lineup.py -- [--family] [type ...]
    (default types: turret brute boss; any exported assets/models/enemies/<type>.glb works)

Imports the shipped .glb files (so it also proves they round-trip through a glTF importer), lines
them up left to right after the scale bar on a 1-tile checker floor and renders a front
orthographic view and the game's isometric view at a fixed scale (px per unit), then adds a caption
with the order and heights: art/previews/enemies/lineup_front.png, lineup_iso.png.

`--family` lines up all seven enemy types and writes lineup_family_front.png,
lineup_family_iso.png and lineup_family_iso_small.png (about in-game pixel size) instead.

The scale bar is deliberately NOT a figure: a plain striped post, 1.6 units tall (the player's
height) with a tick every 0.5 unit and a 1-tile foot. An earlier version used a grey humanoid
stand-in for the player, which was mistaken for one of the characters.
"""
from __future__ import annotations

import os
import subprocess
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common2 as C  # noqa: E402

PX_PER_UNIT = 110
FAMILY = ["grunt", "stalker", "shielder", "drone", "turret", "brute", "boss"]
BAR_H = 1.6


def scale_bar() -> bpy.types.Object:
    """A neutral measuring post: 1.6 tall, alternating light/dark 0.1 bands, wider ticks at each
    0.5, a cap at 1.6 and a flat 1 x 0.2 foot (one tile wide). No head, limbs or face."""
    light = bpy.data.materials.new("scale_light")
    light.diffuse_color = (0.86, 0.86, 0.88, 1)
    dark = bpy.data.materials.new("scale_dark")
    dark.diffuse_color = (0.16, 0.16, 0.19, 1)
    parts = []
    n = int(round(BAR_H / 0.1))
    for i in range(n):
        seg = C.box(f"bar{i}", (0.07, 0.07, 0.1), "metal", loc=(0, 0, 0.05 + 0.1 * i))
        seg.data.materials.clear()
        seg.data.materials.append(light if i % 2 == 0 else dark)
        parts.append(seg)
    for z in (0.5, 1.0, 1.5, BAR_H):
        w = 0.34 if z == BAR_H else 0.2
        t = C.box(f"tick{z}", (w, 0.075, 0.025), "metal", loc=(0, 0, z - (0.0125 if z == BAR_H else 0.0)))
        t.data.materials.clear()
        t.data.materials.append(dark if z != BAR_H else light)
        parts.append(t)
    foot = C.box("bar_foot", (1.0, 0.2, 0.03), "metal", loc=(0, 0, 0.015))
    foot.data.materials.clear()
    foot.data.materials.append(dark)
    parts.append(foot)
    return C.join_raw("scale_bar", parts)


def import_type(t: str) -> list[bpy.types.Object]:
    path = os.path.join(C.REPO, "assets", "models", "enemies", f"{t}.glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.animation_data:
            o.animation_data.action = None
            for tr in o.animation_data.nla_tracks:
                tr.mute = True
        if o.type == "ARMATURE":
            for pb in o.pose.bones:
                pb.location = (0, 0, 0)
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.rotation_euler = (0, 0, 0)
                pb.scale = (1, 1, 1)
    # The importer adds bone display shapes (unparented helper meshes): not part of the model.
    for o in new:
        if o.type == "MESH" and o.parent is None and not o.modifiers:
            o.hide_render = True
            o.hide_viewport = True
    bpy.context.scene.frame_set(0)
    return [o for o in new if o.parent is None and not o.hide_render]


def group_meshes(roots) -> list[bpy.types.Object]:
    out = []
    for o in bpy.data.objects:
        if o.type != "MESH" or o.hide_render:
            continue
        p = o
        while p is not None:
            if p in roots:
                out.append(o)
                break
            p = p.parent
    return out


def tight_box(pv: C.Previewer, meshes, res, pad_px: int = 28) -> str:
    """Pixel box "x0,y0,x1,y1" of the given meshes in the image the previewer just rendered (the
    camera frames the axis-aligned bounds, which is far too loose for a diagonal line-up)."""
    cam = pv.cam
    rot = cam.rotation_quaternion
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    ppu = res[0] / cam.data.ortho_scale
    cu, cv = cam.location.dot(right), cam.location.dot(up)
    us, vs = [], []
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in meshes:
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        for v in me.vertices:
            p = ob.matrix_world @ v.co
            us.append(p.dot(right))
            vs.append(p.dot(up))
        ev.to_mesh_clear()
    x0 = max(0, int(res[0] / 2 + (min(us) - cu) * ppu) - pad_px)
    x1 = min(res[0], int(res[0] / 2 + (max(us) - cu) * ppu) + pad_px)
    y0 = max(0, int(res[1] / 2 - (max(vs) - cv) * ppu) - pad_px)
    y1 = min(res[1], int(res[1] / 2 - (min(vs) - cv) * ppu) + pad_px)
    return f"{x0},{y0},{x1},{y1}"


def caption_images(caption: str, paths: list[str]) -> None:
    """paths: "file" or "file|x0,y0,x1,y1" (crop box applied before the caption strip is added)."""
    py = os.environ.get("OD_PYTHON", "python")
    code = ("import sys\nfrom PIL import Image, ImageDraw, ImageFont\n"
            "cap=sys.argv[1]\n"
            "for a in sys.argv[2:]:\n"
            "    p,_,box=a.partition('|')\n"
            "    im=Image.open(p).convert('RGB')\n"
            "    if box: im=im.crop(tuple(int(v) for v in box.split(',')))\n"
            "    out=Image.new('RGB',(im.width,im.height+34),(28,27,33)); out.paste(im,(0,34))\n"
            "    d=ImageDraw.Draw(out)\n"
            "    try: f=ImageFont.truetype('arialbd.ttf',18)\n"
            "    except OSError: f=ImageFont.load_default()\n"
            "    while f.size>9 and d.textlength(cap,font=f)>im.width-16: f=ImageFont.truetype('arialbd.ttf',f.size-1)\n"
            "    d.text((8,7),cap,fill=(235,230,220),font=f); out.save(p)\n")
    try:
        subprocess.run([py, "-c", code, caption, *paths], check=True)
    except Exception as e:
        print("caption failed:", e)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    family = "--family" in argv
    types = [a for a in argv if not a.startswith("--")] or (FAMILY if family else ["turret", "brute", "boss"])
    prefix = "lineup_family" if family else "lineup"
    C.reset_scene()
    groups = [("scale bar", [scale_bar()])]
    for t in types:
        groups.append((t, import_type(t)))
    bpy.context.view_layer.update()
    # Measure each group once, at the origin.
    info = []
    for name, roots in groups:
        meshes = group_meshes(roots)
        _, lo, hi = C.mesh_stats(meshes)
        info.append((name, roots, lo.copy(), hi.copy()))
    caption = "left to right: scale bar (1.6 = player height, ticks every 0.5), " + ", ".join(
        f"{n} ({hi.z - lo.z:.2f} tall)" for n, _, lo, hi in info[1:])
    out_dir = os.path.join(C.REPO, "art", "previews", "enemies")

    def layout(axis: Vector, gap: float) -> float:
        """Place the groups one after another along `axis` (a horizontal unit vector)."""
        x = 0.0
        for name, roots, lo, hi in info:
            # Half-extent of the footprint along the axis (conservative: bounding-box radius).
            ext = max(abs(lo.x), abs(hi.x), abs(lo.y), abs(hi.y)) if axis.y != 0 else None
            a, b = (-ext, ext) if ext is not None else (lo.x, hi.x)
            for r in roots:
                r.location = axis * (x - a)
            x += (b - a) + gap
        bpy.context.view_layer.update()
        return x - gap

    def all_meshes():
        return [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render and o.name != "preview_floor"]

    # Front view: along X.
    total = layout(Vector((1, 0, 0)), 0.45)
    pv = C.Previewer(out_dir, floor_tiles=int(total) + 3)
    pv.floor.location.x = float(int(total / 2))
    _, lo, hi = C.mesh_stats(all_meshes())
    lo.z = 0.0
    w_px = int((hi.x - lo.x + 0.6) * PX_PER_UNIT)
    h_px = int((hi.z + 0.4) * PX_PER_UNIT)
    front = pv.shoot(f"{prefix}_front", 0, 0, lo, hi, (w_px, h_px), margin=1.05)
    # Game view: along the camera's screen-right axis so nothing hides behind its neighbour.
    right = Vector((0.7071068, 0.7071068, 0.0))
    total = layout(right, 0.25)
    pv.floor.location = right * float(int(total / 2))
    _, lo, hi = C.mesh_stats(all_meshes())
    lo.z = 0.0
    # The camera frames the (loose) axis-aligned bounds of the diagonal row; render big enough for
    # PX_PER_UNIT after the crop to the models.
    span = (hi.x - lo.x + hi.y - lo.y) * 0.7071068 * 1.04
    res = (int(span * PX_PER_UNIT), int(span * PX_PER_UNIT * 0.6))
    iso = pv.shoot(f"{prefix}_iso", C.ISO_YAW, C.ISO_PITCH, lo, hi, res, margin=1.04)
    outs = [front, iso + "|" + tight_box(pv, all_meshes(), res)]
    if family:
        res_s = (int(res[0] * 0.5), int(res[1] * 0.5))  # about 55 px per tile: in-game size
        small = pv.shoot(f"{prefix}_iso_small", C.ISO_YAW, C.ISO_PITCH, lo, hi, res_s, margin=1.04)
        outs.append(small + "|" + tight_box(pv, all_meshes(), res_s, 14))
    print(caption)
    caption_images(caption, outs)


if __name__ == "__main__":
    main()
