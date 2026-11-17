"""Stage 1: parametric human from MPFB2 (MakeHuman, CC0 output) with anime-leaning proportions,
plus the MakeHuman 'default' rig and its weights (used later as the source for skin weights)."""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U

bpy.ops.wm.read_factory_settings(use_empty=True)
import addon_utils
addon_utils.enable("bl_ext.user_default.mpfb")
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

macro = {"gender": 0.0, "age": 0.5, "muscle": 0.62, "weight": 0.36, "proportions": 0.9, "height": 0.5,
         "cupsize": 0.36, "firmness": 0.8, "race": {"asian": 0.45, "caucasian": 0.25, "african": 0.30}}
base = HumanService.create_human(mask_helpers=False, detailed_helpers=True, extra_vertex_groups=True,
                                 feet_on_ground=True, scale=0.1, macro_detail_dict=macro)

DETAIL = {
    # head: larger, softer, tapering to a pointed chin
    "head-scale-horiz-incr": 0.55, "head-scale-vert-incr": 0.35, "head-scale-depth-incr": 0.5,
    "head-invertedtriangular": 0.55, "head-oval": 0.3, "head-age-decr": 0.6, "head-fat-decr": 0.2,
    "chin-triangle": 0.6, "chin-width-decr": 0.5, "chin-bones-decr": 0.6, "chin-prominent-decr": 0.3,
    "chin-height-decr": 0.3,
    "nose-scale-horiz-decr": 0.9, "nose-scale-vert-decr": 0.6, "nose-scale-depth-decr": 0.7,
    "nose-flaring-decr": 0.8, "nose-point-up": 0.5, "nose-volume-decr": 0.8, "nose-nostrils-width-decr": 0.8,
    "nose-hump-decr": 0.5, "nose-width1-decr": 0.7, "nose-width2-decr": 0.7, "nose-width3-decr": 0.7,
    "mouth-scale-horiz-decr": 0.3, "mouth-lowerlip-volume-decr": 0.6, "mouth-philtrum-volume-decr": 0.8,
    "mouth-cupidsbow-decr": 0.8, "mouth-laugh-lines-out": 0.5,
    "l-eye-scale-incr": 0.8, "r-eye-scale-incr": 0.8, "l-eye-bag-decr": 1.0, "r-eye-bag-decr": 1.0,
    "l-eye-trans-down": 0.3, "r-eye-trans-down": 0.3,
    "l-cheek-bones-decr": 0.4, "r-cheek-bones-decr": 0.4, "l-cheek-volume-incr": 0.25, "r-cheek-volume-incr": 0.25,
    "forehead-scale-vert-incr": 0.2, "forehead-temple-incr": 0.3,
    "neck-scale-horiz-decr": 0.55, "neck-scale-depth-decr": 0.55, "neck-scale-vert-incr": 0.2,
    # body: long legs, short torso, slim waist, athletic
    "upperlegs-height-incr": 0.55, "lowerlegs-height-incr": 0.6,
    "measure-waist-circ-decr": 0.5, "measure-hips-circ-incr": 0.15, "torso-vshape-incr": 0.15,
    "stomach-tone-incr": 0.6, "measure-shoulder-dist-decr": 0.2,
    "l-hand-scale-incr": 0.45, "r-hand-scale-incr": 0.45,
    "l-hand-fingers-diameter-incr": 0.25, "r-hand-fingers-diameter-incr": 0.25,
    "l-upperarm-shoulder-muscle-incr": 0.2, "r-upperarm-shoulder-muscle-incr": 0.2,
    "measure-upperarm-length-incr": 0.15, "measure-lowerarm-length-incr": 0.15,
}
stack = [{"target": k, "value": v} for k, v in DETAIL.items()]
TargetService.bulk_load_targets(base, stack)
TargetService.bake_targets(base)

rig = HumanService.add_builtin_rig(base, "default", import_weights=True)
base.name = "MH_Base"
rig.name = "MH_Rig"
print("BASE verts", len(base.data.vertices), "dims", tuple(base.dimensions), "rig bones", len(rig.data.bones))
U.save_stage("s01_base")

# quick review (helpers masked)
m = base.modifiers.new("mask", 'MASK')
m.vertex_group = "body"
rig.hide_render = True
zmax = base.dimensions.z
U.render_views(os.path.join(U.WIP, "s01_body.png"), center=(0, 0, zmax / 2), scale=zmax * 1.08)
U.render_views(os.path.join(U.WIP, "s01_head.png"), views=("front", "q", "side"),
               center=(0, 0, zmax - 0.13), scale=0.42, res=(700, 700))
