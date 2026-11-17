"""Builds the requested parts in order. Returns {object name: object}."""
import bpy

import mc_util as U


def build(want, full, out_dir, here):
    obs = {}
    if want("head"):
        import mc_head
        obs["Head"] = mc_head.build_head()
        obs["Eyes"] = mc_head.build_eyes()
        obs["Lashes"] = mc_head.build_lashes()
        obs["Teeth"] = mc_head.build_teeth()
    if want("hair"):
        import mc_hair
        obs["Hair"], obs["Pigtails"] = mc_hair.build_hair()
    if want("body"):
        import mc_body
        obs["Body"] = mc_body.build_body()
    if want("hands"):
        import mc_hand
        obs["HandL"] = mc_hand.build_hand_left()
        obs["HandR"] = mc_hand.mirror_object(obs["HandL"], "HandR")
    if want("cloth"):
        import mc_boots
        import mc_cloth
        import mc_jacket
        obs["Pants"], obs["PantsTrim"] = mc_cloth.build_pants()
        obs["Top"], obs["TopTrim"] = mc_cloth.build_top()
        obs["ChestStrap"] = mc_cloth.build_chest_strap()
        obs["Boots"] = mc_boots.build_boots()
        obs["Shins"] = mc_cloth.build_shins()
        obs["Jacket"], obs["JacketTrimSleeve"], obs["JacketTrimBody"] = mc_jacket.build_jacket()
        if "HandL" in obs:
            obs["GloveL"] = mc_cloth.build_gloves(obs["HandL"], "HandL")
            obs["GloveR"] = mc_cloth.build_gloves(obs["HandR"], "HandR")
    if want("gear"):
        import mc_gear
        import mc_kit
        obs["Headphones"] = mc_gear.build_headphones()
        obs["Choker"] = mc_kit.build_choker()
        obs["WristDevices"] = mc_kit.build_wrist_devices()
        obs["BeltKit"] = mc_kit.build_belt_kit()
        obs["Straps"] = mc_kit.build_straps()
        obs["Cable"] = mc_kit.build_cable()
    for k, o in obs.items():
        print("  %-14s %6d tris" % (k, U.tri_count([o])))
    import os
    import mc_proportion
    warp = not os.environ.get("MC_NOWARP")
    if not full and warp:
        mc_proportion.apply_to_objects(list(obs.values()))
    if full:
        import mc_rig
        rig = mc_rig.build_armature()
        body = mc_rig.skin(obs, rig)
        import mc_finish
        mc_finish.consolidate(body, os.path.join(here, "tex"))
        if warp:
            mc_proportion.apply_to_objects([body])
            mc_proportion.apply_to_rig(rig)
        obs = {"Moxie": body, "Rig": rig}
    return obs
