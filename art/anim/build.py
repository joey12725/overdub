"""OVERDUB animation rig in Blender: builds the neutral humanoid (Godot SkeletonProfileHumanoid
names, T-pose) with a readable mannequin, exports it, and renders clip frames for review.

  blender --background --threads 8 --python art/anim/build.py -- export
      -> assets/anim/library/mannequin.glb  (armature "Rig" + mesh "Mannequin", no animations)
  blender --background --threads 8 --python art/anim/build.py -- render <outdir> [clip filter]
      -> <outdir>/<clip>/<view>_<nn>.png for every review frame (then run sheets.py)
  blender --background --threads 8 --python art/anim/build.py -- blend
      -> art/anim/baked/anim_rig.blend with every clip baked as an Action (for hand polish)

Clips are solved by od_rig.py / clips.py (the IK/FK control layer) and applied to the armature as
pose-bone matrices; Godot gets them from baked/moxie_clips.json via build_library.gd, not from
the glb, so the library is independent of any exporter's bone axes.
"""
import bpy, bmesh, sys, os, math
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import numpy as np
import od_rig as rig
import clips as clipdefs

C = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], dtype=float)   # Godot (x, y, z) -> Blender (x, -z, y)


def bl(v):
    return Vector((C @ np.asarray(v, dtype=float)).tolist())


def mat3(m):
    return Matrix((C @ m @ C.T).tolist())


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    if b:
        b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        b.inputs["Roughness"].default_value = 0.9
    return m


def hexc(h):
    h = h.lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255.0) ** 2.2 for i in (0, 2, 4))


PALETTE = {
    "body": hexc("#f1ece4"), "armR": hexc("#ff8a3c"), "armL": hexc("#3cb6c8"), "legR": hexc("#8a6a4e"),
    "legL": hexc("#4e6a7a"), "skin": hexc("#f0c9a8"), "hair": hexc("#2b2233"), "phones_glow": hexc("#ffd23f"),
    "ink": hexc("#221a22"), "top": hexc("#f6f1e6"), "pants": hexc("#69713f"), "shoes": hexc("#e9e2d4"),
}


class Builder:
    """Collects rigid parts (each fully weighted to one bone) into one mesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.groups = []   # (verts, bone)
        self.mats = []
        self.mat_index = {}

    def _mat(self, name):
        if name not in self.mat_index:
            self.mat_index[name] = len(self.mats)
            self.mats.append(name)
        return self.mat_index[name]

    def _commit(self, geom, bone, mat, xf):
        verts = [g for g in geom if isinstance(g, bmesh.types.BMVert)]
        bmesh.ops.transform(self.bm, matrix=xf, verts=verts)
        mi = self._mat(mat)
        for v in verts:
            for f in v.link_faces:
                f.material_index = mi
                f.smooth = True
        self.groups.append((verts, bone))

    def capsule(self, bone, a, b, r0, r1, mat, squash=(1, 1)):
        """Tapered capsule from point a to b (Godot coords)."""
        a, b = bl(a), bl(b)
        d = b - a
        ln = d.length
        rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
        sc = Matrix.Diagonal((squash[0], squash[1], 1, 1))
        g = bmesh.ops.create_cone(self.bm, cap_ends=False, segments=14, radius1=r0, radius2=r1, depth=ln)
        self._commit(g["verts"], bone, mat, Matrix.Translation((a + b) / 2) @ rot @ sc)
        for p, r in ((a, r0), (b, r1)):
            g = bmesh.ops.create_uvsphere(self.bm, u_segments=14, v_segments=8, radius=r)
            self._commit(g["verts"], bone, mat, Matrix.Translation(p) @ rot @ sc)

    def ball(self, bone, c, r, mat, scale=(1, 1, 1)):
        g = bmesh.ops.create_uvsphere(self.bm, u_segments=16, v_segments=10, radius=r)
        s = C @ np.diag(scale) @ C.T
        sc = Matrix.Diagonal((abs(s[0, 0]) or 1, abs(s[1, 1]) or 1, abs(s[2, 2]) or 1, 1))
        # scale is given in Godot axes (x, y, z) -> Blender (x, z, y)
        sc = Matrix.Diagonal((scale[0], scale[2], scale[1], 1))
        self._commit(g["verts"], bone, mat, Matrix.Translation(bl(c)) @ sc)

    def box(self, bone, c, size, mat, rot_y=0.0):
        g = bmesh.ops.create_cube(self.bm, size=1.0)
        sc = Matrix.Diagonal((size[0], size[2], size[1], 1))
        r = Matrix.Rotation(math.radians(rot_y), 4, "Z")
        self._commit(g["verts"], bone, mat, Matrix.Translation(bl(c)) @ r @ sc)
        for v in g["verts"]:
            for f in v.link_faces:
                f.smooth = False

    def finish(self, name, arm_obj):
        me = bpy.data.meshes.new(name)
        self.bm.verts.index_update()
        index_of = {}
        for verts, bone in self.groups:
            for v in verts:
                index_of[v.index] = bone
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        for mname in self.mats:
            me.materials.append(new_mat(mname, PALETTE[mname]))
        vg = {}
        for idx, bone in index_of.items():
            if bone not in vg:
                vg[bone] = ob.vertex_groups.new(name=bone)
            vg[bone].add([idx], 1.0, "REPLACE")
        ob.parent = arm_obj
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm_obj
        return ob


def build_rig():
    arm = bpy.data.armatures.new("Rig")
    ob = bpy.data.objects.new("Rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, pos in rig.BONES:
        eb = arm.edit_bones.new(name)
        eb.head = bl(pos)
        eb.tail = bl(rig.TAIL[name])
        # A consistent roll: bone Z toward the character's front (limbs) / back (spine).
        eb.align_roll(Vector((0, -1, 0)))
        if parent:
            eb.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"

    R = rig.REST
    b = Builder()
    # Torso.
    b.ball("Hips", R["Hips"] + rig.v3(0, -0.035, 0), 0.115, "pants", (1.05, 0.72, 0.80))
    b.ball("Spine", (R["Spine"] + R["Chest"]) / 2, 0.092, "skin", (0.95, 0.75, 0.74))
    b.ball("Chest", (R["Chest"] + R["UpperChest"]) / 2 + rig.v3(0, 0.01, 0.005), 0.108, "top", (1.02, 0.78, 0.80))
    b.ball("UpperChest", R["UpperChest"] + rig.v3(0, 0.055, 0.0), 0.112, "top", (1.18, 0.66, 0.76))
    b.capsule("Neck", R["Neck"] - rig.v3(0, 0.02, 0), R["Head"], 0.036, 0.034, "skin")
    # Head: big anime head, face marker, yellow headphones, messy pigtails.
    hc = R["Head"] + rig.v3(0, 0.125, 0.012)
    b.ball("Head", hc, 0.132, "skin", (0.95, 1.0, 0.98))
    b.ball("Head", hc + rig.v3(0, 0.03, -0.022), 0.142, "hair", (0.98, 0.95, 0.95))
    b.box("Head", hc + rig.v3(0, -0.012, 0.118), (0.15, 0.04, 0.03), "ink")           # eye band = "front"
    b.box("Head", hc + rig.v3(0, 0.118, 0.0), (0.285, 0.03, 0.05), "phones_glow")     # headband
    for sg in (1, -1):
        b.ball("Head", hc + rig.v3(0.135 * sg, -0.005, 0.0), 0.058, "phones_glow", (0.55, 1.0, 1.0))
        b.capsule("Head", hc + rig.v3(0.11 * sg, 0.07, -0.07), hc + rig.v3(0.21 * sg, -0.10, -0.15), 0.055, 0.018, "hair")
    # Arms and legs.
    for side, sg, am, lm in (("Left", 1, "armL", "legL"), ("Right", -1, "armR", "legR")):
        b.capsule(side + "Shoulder", R[side + "Shoulder"] + rig.v3(0.03 * sg, 0, 0), R[side + "UpperArm"], 0.045, 0.048, "top")
        b.capsule(side + "UpperArm", R[side + "UpperArm"], R[side + "LowerArm"], 0.044, 0.036, am)
        b.capsule(side + "LowerArm", R[side + "LowerArm"], R[side + "Hand"], 0.036, 0.028, am)
        b.box(side + "Hand", R[side + "Hand"] + rig.v3(0.045 * sg, -0.004, 0.0), (0.085, 0.032, 0.078), "skin")
        b.box(side + "MiddleProximal", R[side + "Hand"] + rig.v3(0.113 * sg, -0.004, -0.002), (0.062, 0.026, 0.074), "skin")
        b.box(side + "ThumbProximal", R[side + "Hand"] + rig.v3(0.045 * sg, -0.008, 0.052), (0.03, 0.024, 0.045), "skin")
        b.capsule(side + "UpperLeg", R[side + "UpperLeg"], R[side + "LowerLeg"], 0.070, 0.050, "pants")
        b.capsule(side + "LowerLeg", R[side + "LowerLeg"], R[side + "Foot"] + rig.v3(0, 0.02, 0), 0.052, 0.040, lm)
        b.box(side + "Foot", R[side + "Foot"] + rig.v3(0, -0.028, 0.03), (0.092, 0.092, 0.17), "shoes")
        b.box(side + "Toes", R[side + "Toes"] + rig.v3(0, 0.012, 0.045), (0.09, 0.062, 0.10), "shoes")
    mesh = b.finish("Mannequin", ob)
    return ob, mesh


def apply_pose(arm_obj, s):
    """Write a solved pose (od_rig.Solved) onto the armature as matrix_basis per bone."""
    arm = arm_obj.data
    glob = {}
    for n in rig.NAMES:
        restm = arm.bones[n].matrix_local
        m = mat3(s.D[n]).to_4x4() @ restm.to_3x3().to_4x4()
        m.translation = bl(s.P[n])
        glob[n] = m
    for n in rig.NAMES:
        bone = arm.bones[n]
        p = rig.PARENT[n]
        if p:
            rest_local = arm.bones[p].matrix_local.inverted() @ bone.matrix_local
            basis = rest_local.inverted() @ glob[p].inverted() @ glob[n]
        else:
            basis = bone.matrix_local.inverted() @ glob[n]
        arm_obj.pose.bones[n].matrix_basis = basis


# ───────────────────────────── weapons (for review renders) ─────────────────────────────

def import_weapon(item):
    path = os.path.join(REPO, "assets", "models", "weapons", item + ".glb")
    if not os.path.exists(path):
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new("W_" + item, None)
    bpy.context.scene.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    return root


def place_weapon(root, grip, w, e, worn=False, mirror=False):
    """Weapon root so its glTF +Y lies along w and +Z along e (worn: gauntlet convention)."""
    w, e = rig.norm(np.asarray(w)), np.asarray(e)
    if worn:
        xg = np.cross(w, e)
        G = rig.frame(y=e, z=(xg if mirror else -xg))
    else:
        G = rig.frame(y=w, z=e)
    m = mat3(G).to_4x4()
    if mirror:
        m = m @ Matrix.Diagonal((-1, 1, 1, 1))
    m.translation = bl(grip)
    root.matrix_world = m


def set_visible(root, vis):
    for o in [root] + list(root.children_recursive):
        o.hide_render = not vis


# ───────────────────────────── rendering ─────────────────────────────

VIEWS = {"iso": (-45.0, 35.0), "side": (-90.0, 4.0), "back": (135.0, 35.0)}


def setup_render(res=(230, 230)):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.object_outline_color = (0.08, 0.05, 0.08)
    sh.show_shadows = False
    sh.show_cavity = True
    sc.display.render_aa = "5"
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.color = (0.55, 0.56, 0.60)
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    cam.ortho_scale = 2.3
    co = bpy.data.objects.new("Cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    # Floor grid: one-tile squares so reach and travel can be judged.
    bm = bmesh.new()
    for i in range(-3, 4):
        for j in range(-3, 4):
            if (i + j) % 2 == 0:
                g = bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
                bmesh.ops.translate(bm, verts=g["verts"], vec=(i, j, -0.002))
    me = bpy.data.meshes.new("Floor")
    bm.to_mesh(me); bm.free()
    fl = bpy.data.objects.new("Floor", me)
    me.materials.append(new_mat("floor", (0.42, 0.43, 0.47)))
    sc.collection.objects.link(fl)
    return co


def aim_camera(co, view, centre=(0, 0.72, 0.2)):
    az, el = VIEWS[view]
    a, e = math.radians(az), math.radians(el)
    d = np.array([math.sin(a) * math.cos(e), math.sin(e), math.cos(a) * math.cos(e)])
    pos = np.asarray(centre) + d * 12.0
    co.location = bl(pos)
    look = bl(centre) - co.location
    co.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()


def review_times(c):
    if c.meta.get("melee"):
        return [0.0, 0.10, 0.20, 0.30, 0.36, 0.40, 0.44, 0.50, 0.60, 0.75, 0.90, 1.0]
    if c.loop:
        return [i / 10.0 for i in range(10)]
    return [i / 11.0 for i in range(12)]


def render_clips(outdir, flt, views=("iso", "side")):
    arm_obj, mesh = build_rig()
    cam = setup_render()
    weapons = {item: import_weapon(item) for item in clipdefs.STYLE_OF_ITEM}
    left_g = import_weapon("speaker_knuckles")
    for c in clipdefs.all_clips():
        if flt and not any(f in c.name for f in flt.split(",")):
            continue
        style = c.meta.get("style", "blade")
        item = clipdefs.ITEM_OF_STYLE[style]
        for it, root in weapons.items():
            if root:
                set_visible(root, it == item)
        if left_g:
            set_visible(left_g, style == "gauntlet")
        d = os.path.join(outdir, c.name)
        os.makedirs(d, exist_ok=True)
        for i, t in enumerate(review_times(c)):
            s = c.sample(t)
            apply_pose(arm_obj, s)
            root = weapons.get(item)
            if root:
                place_weapon(root, s.grip, s.w, s.e, worn=(style == "gauntlet"))
            if left_g and style == "gauntlet":
                GL = s.D["LeftHand"] @ rig.GRIP_REST["Left"]
                place_weapon(left_g, s.lgrip, GL[:, 1], GL[:, 2], worn=True, mirror=True)
            for view in views:
                aim_camera(cam, view)
                bpy.context.scene.render.filepath = os.path.join(d, "%s_%02d.png" % (view, i))
                bpy.ops.render.render(write_still=True)
        print("rendered", c.name, flush=True)


def export_glb():
    arm_obj, mesh = build_rig()
    out = os.path.join(REPO, "assets", "anim", "library", "mannequin.glb")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=False, export_yup=True,
                              export_apply=False, export_skins=True, export_cameras=False, export_lights=False)
    print("exported", out)


def save_blend():
    arm_obj, mesh = build_rig()
    arm_obj.animation_data_create()
    for c in clipdefs.all_clips():
        act = bpy.data.actions.new(c.name)
        act.use_fake_user = True
        arm_obj.animation_data.action = act
        frames, _ = c.bake()
        for i, s in enumerate(frames):
            apply_pose(arm_obj, s)
            for n in rig.NAMES:
                pb = arm_obj.pose.bones[n]
                pb.keyframe_insert("rotation_quaternion", frame=i)
                if n == "Hips":
                    pb.keyframe_insert("location", frame=i)
        print("baked", c.name, flush=True)
    out = os.path.join(HERE, "baked", "anim_rig.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("saved", out)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    cmd = argv[0] if argv else "export"
    reset_scene()
    if cmd == "export":
        export_glb()
    elif cmd == "render":
        render_clips(argv[1], argv[2] if len(argv) > 2 else "", tuple(argv[3].split(",")) if len(argv) > 3 else ("iso", "side"))
    elif cmd == "blend":
        save_blend()
