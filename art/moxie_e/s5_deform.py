"""Step 5 (Blender): T-pose sheet and skin-weight test poses of work/rigged.blend -> art/previews/moxie_e/_parts/*.png"""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import *
bpy.ops.wm.open_mainfile(filepath=os.path.join(WORK, 'rigged.blend'))
setup_materials(); flat_tex_shading()
rig = bpy.data.objects['Rig']; rig.hide_render = True
bpy.context.scene.render.film_transparent = True
P = os.path.join(PREV, '_parts'); os.makedirs(P, exist_ok=True)
X, Y, Z = 'X', 'Y', 'Z'
for i, (yaw, pitch) in enumerate(((0, 0), (180, 0), (90, 0), (40, 25))):
    render(os.path.join(P, f'tpose_{i}.png'), ortho_cam(f't{i}', yaw, pitch, target=(0, 0, 0.8), scale=1.75), res=(900, 1000) if i < 2 else (560, 1000), transparent=True)
rig.data.display_type = 'STICK'


def crouch():
    move(rig, 'Hips', (0, 0.02, -0.36)); rot(rig, 'Hips', X, -18)
    for s in ('Left', 'Right'):
        rot(rig, s + 'UpperLeg', X, -92); rot(rig, s + 'LowerLeg', X, 128); rot(rig, s + 'Foot', X, -18)
        rot(rig, s + 'UpperArm', Y, 55 if s == 'Left' else -55); rot(rig, s + 'UpperArm', X, -25)
    rot(rig, 'Spine', X, -14); rot(rig, 'Neck', X, 16)


def overhead():
    for s, sg in (('Left', 1), ('Right', -1)):
        rot(rig, s + 'Shoulder', Y, -22 * sg); rot(rig, s + 'UpperArm', Y, -58 * sg); rot(rig, s + 'LowerArm', Y, -20 * sg)


def stride():
    rot(rig, 'LeftUpperLeg', X, -48); rot(rig, 'LeftLowerLeg', X, 22)
    rot(rig, 'RightUpperLeg', X, 38); rot(rig, 'RightLowerLeg', X, 30)
    rot(rig, 'LeftUpperArm', Y, 70); rot(rig, 'LeftUpperArm', X, 40); rot(rig, 'RightUpperArm', Y, -70); rot(rig, 'RightUpperArm', X, -40)
    rot(rig, 'RightLowerArm', X, -50); rot(rig, 'LeftLowerArm', X, -30)


def twist():
    for b in ('Spine', 'Chest', 'UpperChest'): rot(rig, b, Z, 20)
    for s, sg in (('Left', 1), ('Right', -1)): rot(rig, s + 'UpperArm', Y, 62 * sg)


def headturn():
    rot(rig, 'Neck', Z, 22); rot(rig, 'Head', Z, 42); rot(rig, 'Head', X, -12)
    for s, sg in (('Left', 1), ('Right', -1)): rot(rig, s + 'UpperArm', Y, 66 * sg)
    rot(rig, 'LeftLowerArm', Z, -70); rot(rig, 'PigtailL1', Y, -25); rot(rig, 'PigtailR1', Y, 25)


for k, (name, fn, views) in enumerate((('crouch', crouch, ((35, 12), (90, 5))), ('overhead', overhead, ((20, 8), (160, 8))), ('stride', stride, ((60, 10), (-60, 10))),
                                        ('twist', twist, ((20, 12), (200, 12))), ('headturn', headturn, ((20, 8),)))):
    reset_pose(rig); fn()
    for j, (yaw, pitch) in enumerate(views):
        tgt = (0, 0, 1.25) if name == 'headturn' else (0, 0, 0.85)
        sc = 0.95 if name == 'headturn' else 2.0
        render(os.path.join(P, f'deform_{k}{name}_{j}.png'), ortho_cam(f'd{k}{j}', yaw, pitch, target=tgt, scale=sc), res=(620, 760), transparent=True)
