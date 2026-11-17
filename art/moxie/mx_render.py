"""Preview rendering for the Moxie build (Workbench, flat base colours + outline).

Views are described by yaw/pitch around the character: yaw 0 looks at her face (camera on -Y),
yaw 90 shows her left side, 180 her back. The game camera is orthographic, yaw 45, pitch 35.
"""
import math
import os

import bpy
import numpy as np
from mathutils import Vector

from mx_geo import V

BG = (0.86, 0.86, 0.88)


def setup_scene(res=(900, 1200)):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.studio_light = 'Default'
    sh.color_type = 'TEXTURE'
    sh.show_object_outline = True
    sh.object_outline_color = (0.05, 0.04, 0.05)
    sh.show_cavity = True
    sh.cavity_type = 'WORLD'
    sh.cavity_ridge_factor = 0.4
    sh.cavity_valley_factor = 0.8
    sh.show_specular_highlight = False
    sh.background_type = 'VIEWPORT'
    sh.background_color = BG
    sc.display.render_aa = '16'
    sc.view_settings.view_transform = 'Standard'
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cd = bpy.data.cameras.new("PreviewCam")
        cam = bpy.data.objects.new("PreviewCam", cd)
        sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def ensure_floor():
    """Preview-only floor disc at Z=0 (never exported) so contact with the ground is judgeable."""
    if bpy.data.objects.get("PreviewFloor"):
        return
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, radius=0.9, segments=48)
    me = bpy.data.meshes.new("PreviewFloor")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("PreviewFloor", me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("preview_floor")
    mat.diffuse_color = (0.62, 0.62, 0.66, 1.0)
    me.materials.append(mat)


def place_camera(cam, target, yaw, pitch, ortho_scale, dist=6.0):
    y, p = math.radians(yaw), math.radians(pitch)
    d = V(math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p))
    cam.location = Vector(target) + d * dist
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = (Vector(target) - cam.location).to_track_quat('-Z', 'Y')
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = ortho_scale
    cam.data.clip_start = 0.01
    cam.data.clip_end = 50


def render(path, target, yaw, pitch, ortho_scale, res=(600, 900), outline=True):
    sc = bpy.context.scene
    cam = setup_scene(res)
    ensure_floor()
    sc.display.shading.show_object_outline = outline
    place_camera(cam, target, yaw, pitch, ortho_scale)
    sc.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    return path


def load_px(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)


def save_px(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("tmp_save", w, h, alpha=True)
    img.pixels.foreach_set(arr.astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def hstack(paths, out, gap=6):
    arrs = [load_px(p) for p in paths]
    h = max(a.shape[0] for a in arrs)
    cols = []
    for i, a in enumerate(arrs):
        if a.shape[0] < h:
            pad = np.ones((h - a.shape[0], a.shape[1], 4), np.float32)
            a = np.concatenate([pad, a], 0)
        cols.append(a)
        if i < len(arrs) - 1:
            cols.append(np.ones((h, gap, 4), np.float32) * np.array([0.2, 0.2, 0.22, 1], np.float32))
    save_px(np.concatenate(cols, 1), out)
    for p in paths:
        if os.path.exists(p) and os.path.basename(p).startswith("_"):
            os.remove(p)
    return out


def downscale(src, out, height):
    a = load_px(src)
    h, w = a.shape[:2]
    f = h / height
    nh, nw = height, max(1, int(round(w / f)))
    # box filter
    ys = (np.arange(nh + 1) * h / nh).astype(int)
    xs = (np.arange(nw + 1) * w / nw).astype(int)
    res = np.zeros((nh, nw, 4), np.float32)
    for i in range(nh):
        rows = a[ys[i]:max(ys[i + 1], ys[i] + 1)]
        cs = np.add.reduceat(rows, xs[:-1], axis=1) / np.maximum(np.diff(xs), 1)[None, :, None]
        res[i] = cs.mean(0)
    save_px(res, out)
