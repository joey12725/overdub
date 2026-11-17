"""Build Moxie from scratch: model, rig, skin, animate, export assets/models/moxie.glb, previews.

Run (from the repo root):
  blender --background --factory-startup --python art/moxie/build.py -- [options]

Options:
  --export            write assets/models/moxie.glb and assets/models/moxie_face.png
  --previews LIST     comma list of: turnaround, iso, thumb, face, poses, contacts, floor, tpose, all
  --pose ACTION@T     pose the turnaround/iso/face renders at an action time (default idle@0;
                      'rest' for the bind pose)
  --no-rig            model only (fast iteration on shapes)
  --out DIR           preview directory (default art/previews/moxie)
"""
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import importlib  # noqa: E402

import bpy  # noqa: E402

import mx_geo  # noqa: E402
import mx_skel  # noqa: E402
import mx_body  # noqa: E402
import mx_render  # noqa: E402
import mx_face  # noqa: E402
import mx_hair  # noqa: E402
import mx_outfit  # noqa: E402
import mx_gear  # noqa: E402
import mx_rig  # noqa: E402
import mx_anim  # noqa: E402
import mx_check  # noqa: E402

for _m in (mx_geo, mx_skel, mx_body, mx_render, mx_face, mx_hair, mx_outfit, mx_gear, mx_rig, mx_anim, mx_check):
    importlib.reload(_m)

REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
GLB = os.path.join(REPO, "assets", "models", "moxie.glb")
FACE_PNG = os.path.join(REPO, "assets", "models", "moxie_face.png")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"export": False, "previews": [], "rig": True, "pose": None,
            "out": os.path.join(REPO, "art", "previews", "moxie")}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--export":
            opts["export"] = True
        elif a == "--previews":
            i += 1
            opts["previews"] = argv[i].split(",")
        elif a == "--pose":
            i += 1
            opts["pose"] = argv[i]
        elif a == "--no-rig":
            opts["rig"] = False
        elif a == "--out":
            i += 1
            opts["out"] = os.path.abspath(argv[i])
        i += 1
    return opts


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    sc.render.fps = 30
    world = bpy.data.worlds.new("PreviewWorld")
    world.color = tuple(c for c in mx_render.BG)
    sc.world = world


def tri_report(parts):
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in parts)
    agg = collections.Counter()
    for o in parts:
        agg[o.name.split('.')[0].rstrip('0123456789')] += sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("PARTS", len(parts), "TRIS", tris)
    for k, v in agg.most_common(60):
        print("  TRI %-20s %d" % (k, v))
    return tris


def build_model():
    parts = mx_body.build_body()
    parts += mx_hair.build_hair()
    mx_body.cull_under_cap(next(p for p in parts if p.name == "head"), mx_hair.hairline)
    parts += mx_hair.build_headphones()
    parts += mx_outfit.build_outfit()
    parts += mx_gear.build_gear()
    head_region = ("head", "pigtail.L", "pigtail.R", "pigroot.L", "pigroot.R")
    m = (mx_geo.Matrix.Translation(mx_skel.HEAD_PIVOT) @ mx_geo.Matrix.Scale(mx_skel.HEAD_SCALE, 4)
         @ mx_geo.Matrix.Translation(-mx_skel.HEAD_PIVOT))
    for p in parts:
        if p.get("wspec") in head_region:
            p.data.transform(m)
    return parts


def want(pv, name):
    return name in pv or "all" in pv


def set_display_pose(rig, spec):
    if rig is None:
        return
    if spec is None:
        spec = "idle@0"
    if spec == "rest":
        mx_anim.clear_pose(rig)
        return
    name, t = spec.split("@")
    mx_anim.show_action(rig, name, float(t))


def measure_global(parts):
    """GLOBAL scale of the proportion stage: brings the warped top of the model to TARGET_TOP."""
    top = max(mx_skel.warp_z((p.matrix_world @ v.co).z) for p in parts for v in p.data.vertices)
    mx_skel.GLOBAL = mx_skel.TARGET_TOP / top
    print("PROPORTION top %.4f -> GLOBAL %.4f" % (top, mx_skel.GLOBAL))


def apply_proportions(parts):
    for p in parts:
        anchor = mx_skel.rigid_anchor(p.name, p.get("wspec"))
        for v in p.data.vertices:
            v.co = mx_skel.warp_point(v.co, anchor)
        p.data.update()


def main():
    opts = parse_args()
    reset_scene()
    parts = build_model()
    tri_report(parts)
    measure_global(parts)
    rig = None
    if opts["rig"]:
        rig = mx_rig.build_armature()
        mx_rig.skin_parts(parts)       # weights are computed in the authored coordinates
    apply_proportions(parts)
    floating = mx_check.floating_parts(parts)
    print("FLOATING", ", ".join(floating) if floating else "none")
    if floating and opts["export"]:
        raise SystemExit("refusing to export: floating parts " + ", ".join(floating))
    mx_face.hook_material(mx_face.make_image(FACE_PNG if opts["export"] else None))
    if opts["rig"]:
        body = mx_geo.join(parts, "Moxie")
        mx_rig.bind(body, rig)
        mx_anim.build_actions(rig, body)
    out = opts["out"]
    os.makedirs(out, exist_ok=True)
    pv = opts["previews"]
    if rig is not None and want(pv, "floor"):
        mx_anim.floor_report(rig, body)
    set_display_pose(rig, opts["pose"])
    if want(pv, "turnaround"):
        views = [("front", 0), ("threeq", 35), ("side", 90), ("back", 180)]
        paths = [mx_render.render(os.path.join(out, "_%s.png" % n), (0, 0, 0.82), yaw, 4, 1.85, res=(560, 1000))
                 for n, yaw in views]
        mx_render.hstack(paths, os.path.join(out, "turnaround.png"))
    if want(pv, "face"):
        fp = []
        for i, (yaw, pitch) in enumerate(((0, 0), (35, 5), (90, 0))):
            fp.append(mx_render.render(os.path.join(out, "_face%d.png" % i), (0, 0, 1.47), yaw, pitch, 0.42,
                                       res=(700, 700)))
        mx_render.hstack(fp, os.path.join(out, "face.png"))
    if want(pv, "iso"):
        # game camera: orthographic, yaw 45, pitch 35
        mx_render.render(os.path.join(out, "iso_game.png"), (0, 0, 0.78), 45, 35, 2.0, res=(800, 900))
    if want(pv, "thumb"):
        big = mx_render.render(os.path.join(out, "_thumb_big.png"), (0, 0, 0.78), 45, 35, 2.0, res=(800, 900))
        # in game she is ~160 px tall: the 2.0-unit frame holds her ~1.6 units -> 200 px frame
        mx_render.downscale(big, os.path.join(out, "thumb.png"), 200)
        os.remove(big)
    if want(pv, "poses") and rig is not None:
        paths = []
        for name, pose in mx_anim.TEST_POSES.items():
            mx_anim.clear_pose(rig)
            mx_rig.apply_pose(rig, pose)
            for yaw in (25, 100):
                paths.append(mx_render.render(os.path.join(out, "_pose_%s_%d.png" % (name, yaw)), (0, 0, 0.75),
                                              yaw, 6, 2.0, res=(420, 640)))
        mx_render.hstack(paths, os.path.join(out, "test_poses.png"))
        set_display_pose(rig, opts["pose"])
    if want(pv, "contacts") and rig is not None:
        for name in mx_anim.ACTION_ORDER:
            paths = []
            n = 8
            for i in range(n):
                t = i / n if name in mx_anim.LOOPS else i / (n - 1)
                mx_anim.show_action(rig, name, t)
                yaw = mx_anim.CONTACT_YAW.get(name, 30)
                paths.append(mx_render.render(os.path.join(out, "_c_%s_%d.png" % (name, i)), (0, 0, 0.72), yaw, 8,
                                              2.05, res=(330, 520)))
            mx_render.hstack(paths, os.path.join(out, "contact_%s.png" % name), gap=3)
        set_display_pose(rig, opts["pose"])
    if rig is not None and (opts["export"] or want(pv, "tpose")):
        import mx_contract
        importlib.reload(mx_contract)
        mx_anim.clear_pose(rig)
        mx_contract.apply_contract(rig, body)
        if want(pv, "tpose"):
            mx_contract.t_pose(rig)
            paths = [mx_render.render(os.path.join(out, "_t_%d.png" % yaw), (0, 0, 0.82), yaw, 4, 1.95,
                                      res=(700, 1000)) for yaw in (0, 90)]
            mx_render.hstack(paths, os.path.join(out, "tpose.png"))
    if opts["export"]:
        import mx_export
        importlib.reload(mx_export)
        mx_export.export(rig, GLB, rest_pose=mx_contract.t_pose)


main()
