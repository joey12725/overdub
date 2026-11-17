"""Shared helpers for the Moxie (candidate B) build: paths, quick review renders, mesh utilities."""
import bpy, bmesh, os, sys, math
from mathutils import Vector, Matrix, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
STAGE = os.path.join(HERE, "_stage")
PREV = os.path.join(REPO, "art", "previews", "moxie_b")
WIP = os.path.join(PREV, "wip")
for d in (STAGE, PREV, WIP):
    os.makedirs(d, exist_ok=True)


def args():
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else []


def save_stage(name):
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(STAGE, name + ".blend"), compress=True)


def open_stage(name):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(STAGE, name + ".blend"))


def activate(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifiers(obj):
    activate(obj)
    for m in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except Exception as e:
            print("modifier apply failed", obj.name, m.name, e)
            obj.modifiers.remove(m)


def new_obj(name, me=None, coll=None):
    me = me or bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    (coll or bpy.context.scene.collection).objects.link(o)
    return o


def srgb(hexstr):
    h = hexstr.lstrip('#')
    v = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in v)


def mat(name, color=None, emit=0.0, rough=0.85):
    """Get or create a simple base-colour material. color is an sRGB hex string or a linear tuple."""
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
    if color is None:
        return m
    if isinstance(color, str):
        color = srgb(color)
    b = m.node_tree.nodes.get("Principled BSDF")
    c = tuple(color[:3]) + (1.0,)
    b.inputs["Base Color"].default_value = c
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if emit > 0:
        b.inputs["Emission Color"].default_value = c
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = c
    return m


# ---------------------------------------------------------------- review renders
VIEWS = {  # name: (yaw degrees about Z measured from the front (-Y), pitch)
    "front": (0, 0), "q": (35, 0), "side": (90, 0), "back": (180, 0), "qb": (145, 0),
    "iso": (45, 35), "top": (0, 89), "ql": (-35, 0), "sidel": (-90, 0), "up": (20, -25), "down": (25, 30),
}


def _camera(name="ReviewCam"):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        bpy.context.scene.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    bpy.context.scene.camera = cam
    return cam


def aim(cam, center, yaw, pitch, dist=10.0):
    y, p = math.radians(yaw), math.radians(pitch)
    d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
    cam.location = Vector(center) + d * dist
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()


def setup_workbench(bg=(0.93, 0.93, 0.94)):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'TEXTURE'
    sh.show_cavity = True
    sh.cavity_type = 'BOTH'
    sh.show_object_outline = False
    sh.show_shadows = False
    sc.display.render_aa = '8'
    if sc.world is None:
        sc.world = bpy.data.worlds.new("W")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (*bg, 1)
    sc.view_settings.view_transform = 'Standard'


def render_views(path, views=("front", "q", "side", "back"), center=(0, 0, 0.85), scale=1.9,
                 res=(600, 900), setup=setup_workbench):
    """Render several orthographic views and paste them side by side into one PNG."""
    import numpy as np
    sc = bpy.context.scene
    cam = _camera()
    cam.data.ortho_scale = scale
    cam.data.clip_start, cam.data.clip_end = 0.01, 100
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'PNG'
    if setup:
        setup()
    tiles = []
    for i, v in enumerate(views):
        yaw, pitch = VIEWS[v] if isinstance(v, str) else v
        aim(cam, center, yaw, pitch)
        tmp = path + ".%d.png" % i
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        w, h = img.size
        a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        tiles.append(a)
        bpy.data.images.remove(img)
        os.remove(tmp)
    sheet = np.concatenate(tiles, axis=1)
    out = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=True)
    out.pixels = sheet.ravel()
    out.filepath_raw = path
    out.file_format = 'PNG'
    out.save()
    bpy.data.images.remove(out)
    print("RENDERED", path)


def stitch(paths, out, cols=None, remove=True):
    """Paste PNG tiles (same size) into a grid."""
    import numpy as np
    tiles = []
    for p in paths:
        img = bpy.data.images.load(p)
        w, h = img.size
        tiles.append(np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4))
        bpy.data.images.remove(img)
        if remove:
            os.remove(p)
    cols = cols or len(tiles)
    rows = []
    for r in range(0, len(tiles), cols):
        row = tiles[r:r + cols]
        while len(row) < cols:
            row.append(np.ones_like(tiles[0]))
        rows.append(np.concatenate(row, axis=1))
    sheet = np.concatenate(rows[::-1], axis=0)
    o = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=True)
    o.pixels = sheet.ravel()
    o.filepath_raw = out
    o.file_format = 'PNG'
    o.save()
    bpy.data.images.remove(o)
    print("RENDERED", out)
