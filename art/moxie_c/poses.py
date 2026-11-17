"""Test / presentation poses (see mc_rig.set_pose for the convention)."""


def arms(down=72, fwd=8, elbow=18):
    return {
        "LeftUpperArm": [("z", -fwd), ("y", down)], "RightUpperArm": [("z", fwd), ("y", -down)],
        "LeftLowerArm": [("z", -elbow)], "RightLowerArm": [("z", elbow)],
        "LeftShoulder": [("y", 6)], "RightShoulder": [("y", -6)],
    }


RELAXED = dict(arms(), **{
    "LeftHand": [("z", -8)], "RightHand": [("z", 8)],
    "LeftUpperLeg": [("y", -3)], "RightUpperLeg": [("y", 3)],
})
for side, sg in (("Left", 1), ("Right", -1)):
    for f in ("Index", "Middle", "Ring", "Little"):
        for i, seg in enumerate(("Proximal", "Intermediate", "Distal")):
            RELAXED[side + f + seg] = [("y", sg * (14 + 6 * i))]

TESTS = {
    "tpose": {},
    "relaxed": RELAXED,
    # the stance of the model sheet (docs/reference/generated/moxie_front.png): arms ~38 deg below
    # horizontal, feet apart - used by the proportion overlay
    "sheet": {"LeftUpperArm": [("y", 42)], "RightUpperArm": [("y", -42)],
              "LeftLowerArm": [("y", 6)], "RightLowerArm": [("y", -6)],
              "LeftUpperLeg": [("y", -2.5)], "RightUpperLeg": [("y", 2.5)],
              "LeftFoot": [("y", 2.5)], "RightFoot": [("y", -2.5)]},
    "crouch": {
        "Hips": [("loc", (0, 0.06, -0.40))],
        "LeftUpperLeg": [("x", -105), ("y", -16)], "RightUpperLeg": [("x", -105), ("y", 16)],
        "LeftLowerLeg": [("x", 130)], "RightLowerLeg": [("x", 130)],
        "LeftFoot": [("x", -25)], "RightFoot": [("x", -25)],
        "Spine": [("x", -16)], "Chest": [("x", -10)],
        "LeftUpperArm": [("z", -30), ("y", 55)], "RightUpperArm": [("z", 30), ("y", -55)],
        "LeftLowerArm": [("z", -60)], "RightLowerArm": [("z", 60)],
    },
    "arms_up": {
        "LeftShoulder": [("y", -18)], "RightShoulder": [("y", 18)],
        "LeftUpperArm": [("y", -72)], "RightUpperArm": [("y", 72)],
        "LeftLowerArm": [("y", -15)], "RightLowerArm": [("y", 15)],
    },
    "arms_fwd": {
        "LeftUpperArm": [("z", -85)], "RightUpperArm": [("z", 85)],
        "LeftLowerArm": [("z", -25)], "RightLowerArm": [("z", 25)],
    },
    "stride": dict(arms(60, 10, 40), **{
        "Hips": [("loc", (0, 0, -0.045))],
        "LeftUpperLeg": [("x", -48)], "RightUpperLeg": [("x", 38)],
        "LeftLowerLeg": [("x", 35)], "RightLowerLeg": [("x", 55)],
        "LeftFoot": [("x", 10)], "RightFoot": [("x", 30)], "RightToes": [("x", -35)],
        "LeftUpperArm": [("y", 70), ("x", 40)], "RightUpperArm": [("y", -70), ("x", -40)],
    }),
    "twist": dict(arms(), **{
        "Spine": [("z", 18)], "Chest": [("z", 18)], "UpperChest": [("z", 16)],
        "Neck": [("z", 20)], "Head": [("z", 35), ("x", 8)],
    }),
    "head_turn": dict(arms(), **{"Neck": [("z", -25)], "Head": [("z", -45), ("x", -12)]}),
    "fist": {
        "LeftUpperArm": [("z", -50), ("y", 10)], "LeftLowerArm": [("z", -85)],
        "RightUpperArm": [("z", 50), ("y", -10)], "RightLowerArm": [("z", 85)],
    },
}
for side, sg in (("Left", 1), ("Right", -1)):
    for f in ("Index", "Middle", "Ring", "Little"):
        for seg, a in (("Proximal", 80), ("Intermediate", 95), ("Distal", 60)):
            TESTS["fist"][side + f + seg] = [("y", sg * a)]
    TESTS["fist"][side + "ThumbMetacarpal"] = [("y", sg * 25), ("z", sg * 10)]
    TESTS["fist"][side + "ThumbProximal"] = [("z", sg * 35), ("y", sg * 25)]
    TESTS["fist"][side + "ThumbDistal"] = [("z", sg * 50)]
