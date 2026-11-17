"""
Preview rendering for the weapon props: a cel look close to the game's (two-step toon ramp, ink
outline by inverted hull, emissive *_glow), orthographic cameras with +Y up (authoring space is
Godot space, see wlib.py), and Moxie (or a mannequin) to hold things.
"""
from __future__ import annotations

import math
import os

import bpy
from mathutils import Matrix, Vector

import wlib as L

BG = (0.022, 0.02, 0.028, 1.0)


def _toon_tree(m, glow):
    nt = m.node_tree
    pb = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if pb is None:
        return
    base_in = pb.inputs["Base Color"]
    col = tuple(base_in.default_value)
    src = base_in.links[0].from_socket if base_in.links else None
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    em = nt.nodes.new("ShaderNodeEmission")
    if glow:
        em.inputs["Color"].default_value = col
        em.inputs["Strength"].default_value = 1.6
        if src:
            nt.links.new(src, em.inputs["Color"])
    else:
        dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
        s2r = nt.nodes.new("ShaderNodeShaderToRGB")
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        e = ramp.color_ramp.elements
        e[0].position = 0.0
        e[0].color = (0.50, 0.46, 0.60, 1)
        e[1].position = 0.32
        e[1].color = (1, 1, 1, 1)
        hi = ramp.color_ramp.elements.new(0.93)
        hi.color = (1.12, 1.12, 1.12, 1)
        mix = nt.nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        mix.inputs[1].default_value = col
        if src:
            nt.links.new(src, mix.inputs[1])
        nt.links.new(dif.outputs[0], s2r.inputs[0])
        nt.links.new(s2r.outputs[0], ramp.inputs[0])
        nt.links.new(ramp.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])


def ink_material():
    m = bpy.data.materials.get("ink")
    if m:
        return m
    m = bpy.data.materials.new("ink")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = L.hexcol(L.PALETTE["ink"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = True
    m["toon"] = 1
    return m


def toonify(outline=0.006, objs=None):
    """Switch every material to the preview toon look and add ink hulls."""
    for m in bpy.data.materials:
        if m.get("toon") or not m.use_nodes:
            continue
        _toon_tree(m, m.name.split(".")[0].endswith("_glow"))
        m["toon"] = 1
    ink = ink_material()
    for o in (objs if objs is not None else bpy.data.objects):
        if o.type != "MESH" or o.get("no_ink") or any(md.type == "SOLIDIFY" for md in o.modifiers):
            continue
        if not o.data.materials:
            continue
        o.data.materials.append(ink)
        sd = o.modifiers.new("ink", "SOLIDIFY")
        sd.thickness = outline * float(o.get("ink_scale", 1.0))
        sd.offset = 1.0
        sd.use_flip_normals = True
        sd.use_rim = False
        sd.material_offset = len(o.data.materials) - 1
        sd.use_quality_normals = True


def setup_scene(res=(900, 900)):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    try:
        sc.eevee.taa_render_samples = 16
        sc.eevee.use_shadows = True
    except Exception:
        pass
    w = sc.world or bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = BG
    bg.inputs[1].default_value = 1.0
    if "KeySun" not in bpy.data.objects:
        sun = bpy.data.lights.new("KeySun", "SUN")
        sun.energy = 3.0
        sun.angle = 0.01
        so = bpy.data.objects.new("KeySun", sun)
        sc.collection.objects.link(so)
        # light travelling toward (-0.45, -0.8, -0.5): from upper front right
        d = Vector((0.45, 0.8, 0.55)).normalized()
        so.matrix_world = look_matrix(d * 10, Vector((0, 0, 0)))
    return sc


def look_matrix(pos, target, up=(0, 1, 0)):
    pos = Vector(pos)
    z = (pos - Vector(target)).normalized()
    upv = Vector(up)
    if abs(z.dot(upv)) > 0.999:
        upv = Vector((0, 0, -1))
    x = upv.cross(z).normalized()
    y = z.cross(x)
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2], m[i][3] = x[i], y[i], z[i], pos[i]
    return m


def camera(target, span, yaw=45.0, pitch=35.0, up=(0, 1, 0), direction=None):
    """Orthographic camera. yaw about +Y from +Z toward +X, pitch above the horizon (degrees);
    or an explicit `direction` from the target toward the camera."""
    sc = bpy.context.scene
    cam = bpy.data.objects.get("Cam")
    if cam is None:
        cd = bpy.data.cameras.new("Cam")
        cam = bpy.data.objects.new("Cam", cd)
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = span
    cam.data.clip_start = 0.01
    cam.data.clip_end = 100
    if direction is None:
        y, p = math.radians(yaw), math.radians(pitch)
        direction = Vector((math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)))
    d = Vector(direction).normalized()
    cam.matrix_world = look_matrix(Vector(target) + d * 20, target, up)
    sc.camera = cam
    return cam


def render(path, res=None):
    sc = bpy.context.scene
    if res:
        sc.render.resolution_x, sc.render.resolution_y = res
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def frame(objs, pad=1.12):
    lo, hi = L.bounds(objs)
    c = (lo + hi) / 2
    span = max((hi - lo).length, 0.05) * pad
    return c, span


# ───────────────────────────── Moxie ─────────────────────────────
C_G2B = Matrix.Rotation(math.radians(90), 4, "X")     # Godot coords -> Blender import coords
C_B2G = Matrix.Rotation(math.radians(-90), 4, "X")

HAND_R = ("RightHand", "hand.R")
FOREARM_L = ("LeftLowerArm", "forearm.L")
HAND_L = ("LeftHand", "hand.L")
GRIP_ALONG = 0.068      # palm centre, metres along the hand bone from the wrist (for a 1.6 Moxie)


class Holder:
    """An imported Moxie (rotated into Godot space) that weapons can be attached to."""

    def __init__(self, glb, action=None, frac=0.0):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=glb)
        self.objs = [o for o in bpy.data.objects if o not in before]
        self.root = bpy.data.objects.new("MoxieRoot", None)
        bpy.context.scene.collection.objects.link(self.root)
        for o in self.objs:
            if o.parent is None:
                o.parent = self.root
        self.root.matrix_world = C_B2G
        self.arm = next(o for o in self.objs if o.type == "ARMATURE")
        self.pose(action, frac)

    def pose(self, action=None, frac=0.0):
        arm = self.arm
        if action:
            act = next((a for a in bpy.data.actions if a.name.split(".")[0] == action or a.name == action), None)
            if act is not None:
                if arm.animation_data is None:
                    arm.animation_data_create()
                arm.animation_data.action = act
                try:
                    if act.slots:
                        arm.animation_data.action_slot = act.slots[0]
                except Exception:
                    pass
                f0, f1 = act.frame_range
                bpy.context.scene.frame_set(int(round(f0 + (f1 - f0) * frac)))
        bpy.context.view_layer.update()

    def bone(self, names):
        for n in names:
            if n in self.arm.pose.bones:
                return n
        return None

    def delta(self, name):
        pb = self.arm.pose.bones[name]
        return self.arm.matrix_world @ pb.matrix @ self.arm.data.bones[name].matrix_local.inverted()

    def rest_godot(self, name):
        """(head, tail) of a bone at rest in Godot model space."""
        b = self.arm.data.bones[name]
        return C_B2G @ b.head_local, C_B2G @ b.tail_local

    def hand_matrix(self, side="R"):
        """World matrix for a melee weapon, mirroring actors/self_view.gd: at the rest pose the
        weapon's +Y points along model +Z (forward) and its +Z along model -Y."""
        name = self.bone(HAND_R if side == "R" else HAND_L)
        head, tail = self.rest_godot(name)
        grip = self.bone(("grip." + side,))
        if grip:
            pos = self.rest_godot(grip)[0]
        else:
            pos = head + (tail - head).normalized() * GRIP_ALONG
        model_b = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        if side == "L":
            model_b = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        rest_g = Matrix.Translation(pos) @ model_b
        return self.delta(name) @ C_G2B @ rest_g

    def wrist_matrix(self, along=0.62, radius=0.034):
        """World matrix for a wrist weapon: origin on top of the left forearm, +Z toward the hand,
        +Y away from the arm (model up at rest)."""
        name = self.bone(FOREARM_L)
        head, tail = self.rest_godot(name)
        z = (tail - head).normalized()
        y = Vector((0, 1, 0))
        x = y.cross(z).normalized()
        y = z.cross(x).normalized()
        pos = head + (tail - head) * along + y * radius
        m = Matrix.Identity(4)
        for i in range(3):
            m[i][0], m[i][1], m[i][2], m[i][3] = x[i], y[i], z[i], pos[i]
        return self.delta(name) @ C_G2B @ m

    def meshes(self):
        return [o for o in self.objs if o.type == "MESH"]


def import_glb(path):
    """Import a weapon glb written by wlib (Godot-space numbers); returns its objects in Godot space."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new("W_" + os.path.basename(path), None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        if o.parent is None:
            o.parent = root
    root.matrix_world = C_B2G
    bpy.context.view_layer.update()
    return root, objs
