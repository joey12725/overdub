"""Key poses for Moxie's nine actions (format: see mx_anim / mx_rig.expand_pose).

Conventions recap (armature axes, she faces -Y, her left is +X):
  thigh/upper_arm ('x', -a) swings forward, (+a) back.  shin/forearm ('bend', +a) flexes.
  foot ('x', +a) points the toes down.  spine/chest/neck/head ('x', +a) leans forward,
  ('z', +a) turns toward her left, ('y', +a) tilts toward her left.
  upper_arm.L ('y', +a) lowers the left arm from the A-pose; upper_arm.R ('y', -a) lowers the right.
  upper_arm.R ('z', +a) swings the right arm forward round the body; upper_arm.L ('z', -a) the left.
  pigtail.S.00n ('z', +a) trails both pigtails back, ('y', +a) droops them.
  jacket.S / jacket.B ('x', +a) swing the jacket hem back.
"""
import math


def merge(*poses):
    out = {}
    for p in poses:
        for k, v in p.items():
            out[k] = list(v) if isinstance(v, list) else v
    return out


def add(pose, extra):
    """Append ops to bones (applied after the existing ones)."""
    out = merge(pose)
    for k, v in extra.items():
        if k == 'hips_loc':
            a = out.get('hips_loc', (0, 0, 0))
            out[k] = tuple(x + y for x, y in zip(a, v))
        else:
            out[k] = out.get(k, []) + list(v)
    return out


def _mirror_ops(ops):
    return [(k, -a) if k in ('y', 'z', 'twist') else (k, a) for k, a in ops]


def mirror(pose):
    """Swap her left and right (for alternating steps)."""
    out = {}
    for k, v in pose.items():
        if k == 'hips_loc':
            out[k] = (-v[0], v[1], v[2])
            continue
        if k.startswith('_'):
            out[k] = v
            continue
        if ".L" in k:
            nk = k.replace(".L", ".R")
        elif ".R" in k:
            nk = k.replace(".R", ".L")
        else:
            nk = k
        out[nk] = v if k.endswith(".S") or ".S." in k else _mirror_ops(v)
        if k.endswith(".S") or ".S." in k:
            out[nk] = list(v)
    return out


def lerp_pose_scalar(a, b, t):
    return a + (b - a) * t


GRIP_R = {
    'fingers.R.001': [('bend', 75)],
    'fingers.R.002': [('bend', 70)],
    'thumb.R': [('bend', 35)],
}
RELAX_HANDS = {
    'fingers.S.001': [('bend', 18)],
    'fingers.S.002': [('bend', 22)],
    'thumb.S': [('bend', 8)],
}
FIST_L = {
    'fingers.L.001': [('bend', 70)],
    'fingers.L.002': [('bend', 75)],
    'thumb.L': [('bend', 30)],
}


def pig(swing, droop=0.0, lag=1.0, out=0.0):
    """Pigtail chain: trail back by `swing`, droop by `droop`, more toward the tips."""
    return {
        'pigtail.S.001': [('z', swing * 0.5), ('y', droop * 0.4 - out)],
        'pigtail.S.002': [('z', swing * 0.7 * lag), ('y', droop * 0.6)],
        'pigtail.S.003': [('z', swing * 0.9 * lag), ('y', droop)],
    }


def jacket(back, side_out=0.0):
    return {
        'jacket.S': [('x', back), ('y', -side_out)],
        'jacket.B': [('x', back * 1.1)],
    }


# --------------------------------------------------------------------------------------------
# stances
# --------------------------------------------------------------------------------------------

ARMS_DOWN = {
    'upper_arm.L': [('y', 26), ('x', -4)],
    'upper_arm.R': [('y', -26), ('x', -4)],
    'forearm.S': [('bend', 14)],
}

# R01 attitude: weight on her right leg, right hand planted on the hip, left arm loose.
IDLE_BASE = merge(RELAX_HANDS, {
    'hips_loc': (-0.014, 0.0, -0.010),
    'hips': [('y', 5), ('z', -6)],
    'spine': [('y', -6), ('z', 3)],
    'chest': [('y', -3), ('z', 4), ('x', -2)],
    'neck': [('y', 2)],
    'head': [('y', 4), ('z', 5), ('x', -5)],
    'thigh.L': [('y', -9), ('x', -9)],
    'shin.L': [('bend', 13)],
    'foot.L': [('x', -4), ('y', 4)],
    'thigh.R': [('y', -1), ('x', 2)],
    'shin.R': [('bend', 3)],
    'foot.R': [('y', -4)],
    # right hand on the hip: elbow out and back, forearm folded in to the waist
    'upper_arm.R': [('twist', -45), ('y', 6), ('x', 28)],
    'forearm.R': [('bend', 90)],
    'hand.R': [('bend', -25), ('twist', -20)],
    'fingers.R.001': [('bend', 10)],
    'fingers.R.002': [('bend', 10)],
    # left arm loose, a little forward
    'upper_arm.L': [('y', 24), ('x', -6)],
    'forearm.L': [('bend', 18)],
    'hand.L': [('bend', 8)],
    'pigtail.S.001': [('y', 4)],
    'pigtail.S.002': [('y', 6)],
    'pigtail.S.003': [('y', 8)],
})

GUARD = merge(GRIP_R, {
    'hips_loc': (0.0, 0.0, -0.045),
    'hips': [('z', -12)],
    'spine': [('x', 6), ('z', 4)],
    'chest': [('z', 4)],
    'head': [('z', 6), ('x', -4)],
    'thigh.L': [('x', -26), ('y', -6)],
    'shin.L': [('bend', 30)],
    'foot.L': [('x', -4)],
    'thigh.R': [('x', 16), ('y', 6)],
    'shin.R': [('bend', 26)],
    'foot.R': [('x', -14)],
    'upper_arm.L': [('y', 26), ('x', -38)],
    'forearm.L': [('bend', 80)],
    'hand.L': [('bend', 10)],
    'upper_arm.R': [('y', -18), ('x', -28), ('twist', -10)],
    'forearm.R': [('bend', 55)],
    'hand.R': [('bend', -10)],
    'fingers.L.001': [('bend', 40)],
    'fingers.L.002': [('bend', 40)],
    'thumb.L': [('bend', 20)],
    'pigtail.S.001': [('y', 4)],
    'pigtail.S.002': [('y', 8)],
    'pigtail.S.003': [('y', 10)],
})


# --------------------------------------------------------------------------------------------
# idle (2.0 s loop): weight shift, breathing, head bob on the beat (4 bobs), pigtail sway
# --------------------------------------------------------------------------------------------

def idle_keys():
    keys = []
    n = 16
    for i in range(n):
        t = i / n
        ph = t * math.tau
        beat = t * 4 * math.tau          # four nods per loop (120 bpm)
        bob = max(0.0, math.cos(beat)) ** 2
        breath = math.sin(ph)
        sway = math.sin(ph + 0.6)
        extra = {
            'hips_loc': (0.004 * sway, 0.0, -0.004 * bob + 0.002 * breath),
            'hips': [('y', 1.2 * sway)],
            'spine': [('x', -1.2 * breath), ('y', -0.8 * sway)],
            'chest': [('x', -1.5 * breath)],
            'neck': [('x', 2.0 * bob)],
            'head': [('x', 3.5 * bob - 1.0), ('y', 1.5 * sway)],
            'upper_arm.L': [('x', -2.0 * breath), ('y', -1.5 * breath)],
            'forearm.L': [('bend', 3.0 * bob)],
            'thigh.L': [('x', -2.0 * bob)],
            'shin.L': [('bend', 3.0 * bob)],
            'foot.L': [('x', -1.0 * bob)],
            'pigtail.S.001': [('y', 3.0 * bob)],
            'pigtail.S.002': [('y', 4.0 * math.cos(beat - 0.8)), ('z', 3.0 * math.sin(ph))],
            'pigtail.S.003': [('y', 6.0 * math.cos(beat - 1.6)), ('z', 4.0 * math.sin(ph - 0.7))],
            'jacket.S': [('x', 1.5 * breath)],
        }
        keys.append((t, add(IDLE_BASE, extra)))
    keys.append((1.0, keys[0][1]))
    return keys


# --------------------------------------------------------------------------------------------
# run (0.6 s loop, two steps): forward lean, pumping arms, high knees, trailing pigtails
# --------------------------------------------------------------------------------------------

RUN_COMMON = merge({
    'spine': [('x', 12)],
    'chest': [('x', 8)],
    'neck': [('x', -4)],
    'head': [('x', -6)],
    'hips': [('x', 14)],
    'fingers.S.001': [('bend', 60)],
    'fingers.S.002': [('bend', 60)],
    'thumb.S': [('bend', 25)],
})

RUN_CONTACT = merge(RUN_COMMON, {   # left foot strikes in front
    'hips_loc': (0.0, 0.0, -0.050),
    'hips': [('x', 14), ('z', -10)],
    'chest': [('x', 8), ('z', 16)],
    'thigh.L': [('x', -52)],
    'shin.L': [('bend', 18)],
    'foot.L': [('x', -10)],
    'thigh.R': [('x', 32)],
    'shin.R': [('bend', 75)],
    'foot.R': [('x', 25)],
    'upper_arm.R': [('y', -34), ('x', -72)],
    'forearm.R': [('bend', 100)],
    'upper_arm.L': [('y', 34), ('x', 58)],
    'forearm.L': [('bend', 70)],
}, pig(28, 4), jacket(18, 6))

RUN_PASS = merge(RUN_COMMON, {      # left leg pushing off under the body, right knee driving up
    'hips_loc': (0.0, 0.0, 0.018),
    'hips': [('x', 14), ('z', -2)],
    'chest': [('x', 8), ('z', 3)],
    'thigh.L': [('x', 18)],
    'shin.L': [('bend', 30)],
    'foot.L': [('x', 30)],
    'thigh.R': [('x', -62)],
    'shin.R': [('bend', 105)],
    'foot.R': [('x', 15)],
    'upper_arm.R': [('y', -34), ('x', -8)],
    'forearm.R': [('bend', 90)],
    'upper_arm.L': [('y', 34), ('x', 8)],
    'forearm.L': [('bend', 90)],
}, pig(40, -8), jacket(26, 10), {'_lift': 0.035})


RUN_DOWN = merge(RUN_COMMON, {      # weight sinks onto the bent left leg, right heel folds high
    'hips': [('x', 14), ('z', -6)],
    'chest': [('x', 8), ('z', 9)],
    'thigh.L': [('x', -12)],
    'shin.L': [('bend', 48)],
    'foot.L': [('x', -22)],
    'thigh.R': [('x', 10)],
    'shin.R': [('bend', 118)],
    'foot.R': [('x', 30)],
    'upper_arm.R': [('y', -34), ('x', -45)],
    'forearm.R': [('bend', 100)],
    'upper_arm.L': [('y', 34), ('x', 38)],
    'forearm.L': [('bend', 78)],
}, pig(34, 8), jacket(22, 8))


def run_keys():
    return [(0.0, RUN_CONTACT), (0.125, RUN_DOWN), (0.25, RUN_PASS), (0.5, mirror(RUN_CONTACT)),
            (0.625, mirror(RUN_DOWN)), (0.75, mirror(RUN_PASS)), (1.0, RUN_CONTACT)]


# --------------------------------------------------------------------------------------------
# stopped (1.0 s loop): a held "paused tape" freeze-frame, mid-gesture, with a tiny tape-wobble
# --------------------------------------------------------------------------------------------

STOPPED_BASE = merge(RELAX_HANDS, {
    'hips_loc': (0.0, 0.0, -0.030),
    'hips': [('z', -8)],
    'spine': [('x', 4), ('z', 3)],
    'chest': [('z', 5)],
    'head': [('z', 10), ('x', -3), ('y', -4)],
    'thigh.L': [('x', -22), ('y', -5)],
    'shin.L': [('bend', 22)],
    'thigh.R': [('x', 12), ('y', 5)],
    'shin.R': [('bend', 18)],
    'foot.R': [('x', -10)],
    'upper_arm.L': [('y', 20), ('x', -25)],
    'forearm.L': [('bend', 60)],
    'upper_arm.R': [('y', -22), ('x', 12)],
    'forearm.R': [('bend', 25)],
}, pig(12, 2), jacket(6))


def stopped_keys():
    jit = {'hips_loc': (0.0015, 0.0, 0.0), 'head': [('z', 0.8)], 'pigtail.S.003': [('z', 1.5)]}
    return [(0.0, STOPPED_BASE), (0.48, STOPPED_BASE), (0.52, add(STOPPED_BASE, jit)),
            (0.56, STOPPED_BASE), (1.0, STOPPED_BASE)]


# --------------------------------------------------------------------------------------------
# light (1.0 s): fast one-handed forehand slash
# --------------------------------------------------------------------------------------------

def light_keys():
    """Forehand slash with a committed wind-up (R02 action strip): the right arm pulls back
    across the body with the shoulders counter-rotated ~30 degrees (0.12-0.40), snaps to a
    full-extension strike with the torso twisted through and the lead foot stepping in (0.40-0.47),
    holds the extension for two frames with a small bounce, sweeps through and recovers."""
    wind = merge(GUARD, {
        'hips_loc': (0.0, 0.020, -0.030),
        'hips': [('z', 8)],
        'spine': [('z', 12), ('x', 2)],
        'chest': [('z', 18)],
        'neck': [('z', -10)],
        'head': [('z', -16), ('x', -2)],
        'thigh.L': [('x', -12), ('y', -6)],
        'shin.L': [('bend', 22)],
        'foot.L': [('x', -6)],
        'thigh.R': [('x', 18), ('y', 6)],
        'shin.R': [('bend', 30)],
        'foot.R': [('x', -16)],
        'upper_arm.R': [('y', 46), ('z', 128), ('x', -6)],
        'forearm.R': [('bend', 115)],
        'hand.R': [('bend', 20)],
        'upper_arm.L': [('y', 22), ('x', 24)],
        'forearm.L': [('bend', 60)],
    }) | pig(12, 6, out=-6) | jacket(6, 6)
    anticip = merge(wind, {'chest': [('z', 24)], 'spine': [('z', 15), ('x', 3)],
                           'upper_arm.R': [('y', 50), ('z', 134), ('x', -8)], 'forearm.R': [('bend', 122)]})
    strike = merge(GUARD, {
        'hips_loc': (0.0, -0.060, -0.055),
        'hips': [('z', -16)],
        'spine': [('z', -12), ('x', 8)],
        'chest': [('z', -22)],
        'neck': [('z', 10)],
        'head': [('z', 22), ('x', -4)],
        'thigh.L': [('x', -42), ('y', -6)],
        'shin.L': [('bend', 38)],
        'foot.L': [('x', -4)],
        'thigh.R': [('x', 26), ('y', 6)],
        'shin.R': [('bend', 22)],
        'foot.R': [('x', -24)],
        'upper_arm.R': [('y', 52), ('z', 58), ('x', 2)],
        'forearm.R': [('bend', 0)],
        'hand.R': [('bend', -8)],
        'upper_arm.L': [('y', 30), ('x', 38)],
        'forearm.L': [('bend', 30)],
    }) | pig(-30, 4, out=12) | jacket(-14, 12)
    hold = add(strike, {'hips_loc': (0.0, -0.004, -0.014), 'spine': [('x', 2)]})
    through = merge(strike, {
        'hips_loc': (0.0, -0.062, -0.040),
        'hips': [('z', -24)],
        'chest': [('z', -30)],
        'spine': [('z', -16), ('x', 8)],
        'upper_arm.R': [('y', 46), ('z', 22)],
        'forearm.R': [('bend', 12)],
    }) | pig(-40, 8, out=14) | jacket(-18, 14)
    settle = merge(GUARD, {
        'hips_loc': (0.0, -0.030, -0.040),
        'hips': [('z', -10)],
        'chest': [('z', -8)],
        'thigh.L': [('x', -34), ('y', -6)],
        'shin.L': [('bend', 34)],
        'upper_arm.R': [('y', 10), ('x', -30), ('z', 30)],
        'forearm.R': [('bend', 50)],
    }) | pig(-10, 10) | jacket(-4)
    return [(0.0, GUARD), (0.14, wind), (0.36, anticip), (0.40, anticip), (0.45, strike), (0.517, hold),
            (0.60, through), (0.76, settle), (1.0, GUARD)]


# --------------------------------------------------------------------------------------------
# heavy (1.0 s): big two-handed overhead slam with a deep wind-up and a long recovery
# --------------------------------------------------------------------------------------------

def heavy_keys():
    two_hand = merge(GRIP_R, FIST_L)
    gather = add(GUARD, {
        'hips_loc': (0.0, 0.0, -0.050),
        'spine': [('x', 12)],
        'upper_arm.R': [('y', -20), ('x', 25)],
        'forearm.R': [('bend', 20)],
        'upper_arm.L': [('x', 55)],
        'forearm.L': [('bend', -40)],
        'thigh.L': [('x', -8)],
        'shin.L': [('bend', 14)],
        'thigh.R': [('x', -4)],
        'shin.R': [('bend', 14)],
    }) | pig(10, 12) | two_hand
    lift = merge(GUARD, two_hand, {
        'hips_loc': (0.0, 0.020, -0.070),
        'hips': [('z', -8), ('x', -4)],
        'spine': [('x', -16)],
        'chest': [('x', -12)],
        'neck': [('x', -6)],
        'head': [('x', -6)],
        'thigh.L': [('x', -40), ('y', -8)],
        'shin.L': [('bend', 50)],
        'foot.L': [('x', 0)],
        'thigh.R': [('x', 14), ('y', 8)],
        'shin.R': [('bend', 48)],
        'foot.R': [('x', -24)],
        'upper_arm.L': [('y', 8), ('x', -138), ('z', 24)],
        'forearm.L': [('bend', 75)],
        'upper_arm.R': [('y', -8), ('x', -142), ('z', -24)],
        'forearm.R': [('bend', 65)],
        'hand.R': [('bend', -20)],
    }) | pig(-20, -18) | jacket(-10, 8)
    peak = add(lift, {'hips_loc': (0.0, 0.006, -0.012), 'spine': [('x', -4)], 'upper_arm.S': [('x', 6)]})
    slam = merge(GUARD, two_hand, {
        'hips_loc': (0.0, -0.060, -0.150),
        'hips': [('x', 14), ('z', -6)],
        'spine': [('x', 26)],
        'chest': [('x', 16)],
        'neck': [('x', -10)],
        'head': [('x', -16)],
        'thigh.L': [('x', -78), ('y', -8)],
        'shin.L': [('bend', 88)],
        'foot.L': [('x', -12)],
        'thigh.R': [('x', 28), ('y', 8)],
        'shin.R': [('bend', 42)],
        'foot.R': [('x', -30)],
        'upper_arm.L': [('y', 30), ('x', -62), ('z', -14)],
        'forearm.L': [('bend', 14)],
        'upper_arm.R': [('y', -30), ('x', -66), ('z', 10)],
        'forearm.R': [('bend', 14)],
        'hand.R': [('bend', 10)],
    }) | pig(55, 14, out=12) | jacket(35, 16)
    impact = add(slam, {'hips_loc': (0.0, -0.004, -0.018), 'spine': [('x', 5)], 'upper_arm.S': [('x', 6)]}) \
        | pig(-15, 30) | jacket(-8, 6)
    hold = add(slam, {'hips_loc': (0.0, 0.0, -0.010), 'spine': [('x', 2)]}) | pig(8, 18) | jacket(4, 4)
    rise = add(GUARD, {'hips_loc': (0.0, -0.015, -0.035), 'spine': [('x', 10)],
                       'upper_arm.R': [('x', -10)], 'forearm.R': [('bend', -15)]}) | pig(5, 10)
    return [(0.0, GUARD), (0.12, gather), (0.32, lift), (0.40, peak), (0.47, slam), (0.53, impact),
            (0.70, hold), (0.86, rise), (1.0, GUARD)]


# --------------------------------------------------------------------------------------------
# dodge (1.0 s): low dash into a forward shoulder roll, back up to guard
# --------------------------------------------------------------------------------------------

TUCK = {
    'spine': [('x', 38)],
    'chest': [('x', 22)],
    'neck': [('x', 20)],
    'head': [('x', 25)],
    'thigh.S': [('x', -118), ('y', -4)],
    'shin.S': [('bend', 140)],
    'foot.S': [('x', 20)],
    'upper_arm.L': [('y', 30), ('x', -65), ('z', -15)],
    'upper_arm.R': [('y', -30), ('x', -65), ('z', 15)],
    'forearm.S': [('bend', 110)],
    'fingers.S.001': [('bend', 60)],
    'fingers.S.002': [('bend', 60)],
}


def dodge_keys():
    crouch = merge(GUARD, {
        'hips_loc': (0.0, -0.030, -0.200),
        'hips': [('x', 25)],
        'spine': [('x', 28)],
        'chest': [('x', 10)],
        'head': [('x', -20)],
        'thigh.L': [('x', -85), ('y', -6)],
        'shin.L': [('bend', 100)],
        'foot.L': [('x', -12)],
        'thigh.R': [('x', -30), ('y', 6)],
        'shin.R': [('bend', 95)],
        'foot.R': [('x', 25)],
        'upper_arm.L': [('y', 28), ('x', 45)],
        'forearm.L': [('bend', 20)],
        'upper_arm.R': [('y', -28), ('x', 45)],
        'forearm.R': [('bend', 20)],
    }) | pig(45, 0) | jacket(40, 12)
    dive = merge({
        'hips_loc': (0.0, -0.060, -0.380),
        'hips': [('x', 70)],
        'spine': [('x', 28)],
        'chest': [('x', 14)],
        'head': [('x', 15)],
        'thigh.S': [('x', -40)],
        'shin.S': [('bend', 50)],
        'foot.S': [('x', 30)],
        'upper_arm.L': [('y', 30), ('x', -95)],
        'upper_arm.R': [('y', -30), ('x', -95)],
        'forearm.S': [('bend', 40)],
    }, pig(70, 0), jacket(60, 20), GRIP_R, {'_lift': 0.06})
    keys = [(0.0, GUARD), (0.12, crouch), (0.22, dive)]
    for t, ang, z in ((0.32, 150, -0.36), (0.42, 225, -0.38), (0.52, 300, -0.46), (0.60, 360, -0.42)):
        p = merge(TUCK, GRIP_R, {'hips_loc': (0.0, 0.0, z), 'hips': [('x', ang)]}, pig(60 - (t - 0.3) * 80, 10),
                  jacket(50, 10))
        keys.append((t, p))
    up = merge(GUARD, {
        'hips_loc': (0.0, 0.020, -0.280),
        'hips': [('x', 15)],
        'spine': [('x', 30)],
        'chest': [('x', 10)],
        'head': [('x', -20)],
        'thigh.L': [('x', -100), ('y', -8)],
        'shin.L': [('bend', 120)],
        'foot.L': [('x', -20)],
        'thigh.R': [('x', -40), ('y', 8)],
        'shin.R': [('bend', 120)],
        'foot.R': [('x', 40)],
        'upper_arm.L': [('y', 30), ('x', -30), ('y', -30)],
        'forearm.L': [('bend', 30)],
    }) | pig(-30, 20, out=10) | jacket(-20, 14)
    rise = add(GUARD, {'hips_loc': (0.0, 0.0, -0.050), 'spine': [('x', 10)]}) | pig(-12, 14) | jacket(-6, 4)
    keys += [(0.72, up), (0.86, rise), (1.0, GUARD)]
    return keys


# --------------------------------------------------------------------------------------------
# ranged (1.0 s): aim the left wrist device, fire with recoil, lower
# --------------------------------------------------------------------------------------------

def ranged_keys():
    """Aim the left wrist device at shoulder height along the eye line, lean into the shot, fire
    at 0.30 with a sharp two-frame recoil (elbow kicks up, shoulder jerks back, head flinches),
    recover with an overshoot, hold the aim, lower."""
    aim = merge(GRIP_R, {
        'hips_loc': (0.0, -0.010, -0.045),
        'hips': [('z', -16)],
        'spine': [('z', -8), ('x', 5)],
        'chest': [('z', -10), ('x', 3)],
        'neck': [('z', 12)],
        'head': [('z', 18), ('x', -2)],
        'thigh.L': [('x', -28), ('y', -8)],
        'shin.L': [('bend', 26)],
        'thigh.R': [('x', 16), ('y', 10)],
        'shin.R': [('bend', 24)],
        'foot.R': [('x', -12)],
        # left arm straight out at the target at shoulder height, palm down so the screen faces up
        'upper_arm.L': [('twist', 90), ('y', -54), ('z', -78)],
        'forearm.L': [('bend', 0)],
        'hand.L': [('bend', -14)],
        'fingers.L.001': [('bend', 8)],
        'fingers.L.002': [('bend', 4)],
        # right hand (weapon) held low and back, clear of the face
        'upper_arm.R': [('y', -22), ('x', -20), ('twist', -10)],
        'forearm.R': [('bend', 60)],
    }) | pig(8, 6) | jacket(4, 4)
    charge = add(aim, {'forearm.L': [('bend', 2)], 'hand.L': [('bend', -6)], 'spine': [('x', 2)]})
    recoil = add(aim, {
        'hips_loc': (0.0, 0.030, 0.004),
        'spine': [('x', -7)],
        'chest': [('x', -6), ('z', 10)],
        'neck': [('x', -4)],
        'head': [('x', -10), ('y', -4)],
        'upper_arm.L': [('y', -13)],
        'forearm.L': [('bend', 26)],
        'hand.L': [('bend', -28)],
    }) | pig(-24, 0, out=8) | jacket(-12, 8)
    overshoot = add(aim, {'hips_loc': (0.0, -0.008, -0.004), 'spine': [('x', 3)], 'chest': [('z', -3)],
                          'upper_arm.L': [('y', 5)], 'forearm.L': [('bend', 4)], 'head': [('x', 3)]})
    return [(0.0, GUARD), (0.16, aim), (0.27, charge), (0.30, charge), (0.367, recoil), (0.46, overshoot),
            (0.56, aim), (0.72, aim), (1.0, GUARD)]


# --------------------------------------------------------------------------------------------
# interact (1.0 s): reach out with the left hand and press
# --------------------------------------------------------------------------------------------

def interact_keys():
    base = IDLE_BASE
    reach = add(base, {
        'hips_loc': (0.0, -0.020, -0.020),
        'hips': [('x', 6)],
        'spine': [('x', 12)],
        'chest': [('x', 6), ('z', -8)],
        'head': [('x', 18), ('z', 6)],
        'upper_arm.L': [('twist', 45), ('x', -72), ('z', -10)],
        'forearm.L': [('bend', 10)],
        'hand.L': [('bend', -25)],
        'fingers.L.001': [('bend', -18)],
        'fingers.L.002': [('bend', -20)],
        'thigh.L': [('x', -16)],
        'shin.L': [('bend', 14)],
    }) | pig(-10, 10)
    press = add(reach, {'hips_loc': (0.0, -0.012, -0.006), 'spine': [('x', 4)], 'upper_arm.L': [('x', -6)],
                        'hand.L': [('bend', -12)], 'head': [('x', 4)]})
    release = add(reach, {'hand.L': [('bend', 8)], 'forearm.L': [('bend', 10)]})
    look = add(base, {'head': [('x', 8), ('z', 8)], 'upper_arm.L': [('x', -12)], 'forearm.L': [('bend', 30)]})
    return [(0.0, base), (0.30, reach), (0.40, press), (0.50, press), (0.58, release), (0.80, look), (1.0, base)]


# --------------------------------------------------------------------------------------------
# death (1.0 s): hit, stagger, knees buckle, fall back and settle
# --------------------------------------------------------------------------------------------

def death_keys():
    """Hit, stagger, the knees drop to the floor, a backward topple pivoting on the pinned knees,
    then the shoulders land and the body settles. The body only ever goes down: every key is
    grounded (no lift) and the whole clip is floor-locked in mx_anim."""
    hit = merge(RELAX_HANDS, {
        'hips_loc': (0.0, 0.040, -0.010),
        'hips': [('x', -8)],
        'spine': [('x', -16)],
        'chest': [('x', -14)],
        'neck': [('x', -10)],
        'head': [('x', -22), ('y', 8)],
        'upper_arm.L': [('y', -25), ('x', 15)],
        'forearm.L': [('bend', 30)],
        'upper_arm.R': [('y', 20), ('x', 20)],
        'forearm.R': [('bend', 40)],
        'thigh.L': [('x', -12)],
        'shin.L': [('bend', 8)],
        'thigh.R': [('x', 8)],
    }) | pig(-35, -10, out=10) | jacket(-20, 14)
    stagger = merge(RELAX_HANDS, {
        'hips_loc': (0.0, 0.020, -0.080),
        'hips': [('x', 10), ('y', 6)],
        'spine': [('x', 18), ('y', -6)],
        'chest': [('x', 8)],
        'head': [('x', 25), ('y', -10)],
        'upper_arm.L': [('y', 15), ('x', -10)],
        'forearm.L': [('bend', 20)],
        'upper_arm.R': [('y', -10), ('x', 15)],
        'forearm.R': [('bend', 25)],
        'thigh.L': [('x', -35)],
        'shin.L': [('bend', 50)],
        'foot.L': [('x', -10)],
        'thigh.R': [('x', 5)],
        'shin.R': [('bend', 35)],
        'foot.R': [('x', -20)],
    }) | pig(25, 12) | jacket(14, 4)
    kneel = merge(RELAX_HANDS, {
        'hips_loc': (0.0, 0.050, -0.360),
        'hips': [('x', -6)],
        'spine': [('x', 10)],
        'chest': [('x', 6)],
        'head': [('x', 30), ('y', -12)],
        'thigh.S': [('x', -58)],
        'shin.S': [('bend', 140)],
        'foot.S': [('x', 40)],
        'upper_arm.L': [('y', 24), ('x', -10)],
        'forearm.L': [('bend', 20)],
        'upper_arm.R': [('y', -24), ('x', -15)],
        'forearm.R': [('bend', 25)],
    }) | pig(30, 20) | jacket(20, 6)
    # backward topple: the pelvis tips back while the thighs counter-rotate so the knees stay put
    topple = merge(RELAX_HANDS, {
        'hips_loc': (0.0, 0.080, -0.420),
        'hips': [('x', -42)],
        'spine': [('x', -12)],
        'chest': [('x', -6)],
        'neck': [('x', 6)],
        'head': [('x', 18), ('z', 10)],
        'thigh.S': [('x', -22)],
        'shin.S': [('bend', 138)],
        'foot.S': [('x', 40)],
        'upper_arm.L': [('y', -34), ('x', -20)],
        'forearm.L': [('bend', 30)],
        'upper_arm.R': [('y', 34), ('x', -26)],
        'forearm.R': [('bend', 36)],
    }) | pig(-20, -10, out=10) | jacket(-30, 20)
    down = merge(RELAX_HANDS, {
        'hips_loc': (0.0, 0.120, -0.640),
        'hips': [('x', -84), ('y', 4)],
        'spine': [('x', -6)],
        'chest': [('x', 0)],
        'neck': [('x', 4)],
        'head': [('z', 35), ('x', 10)],
        'thigh.L': [('x', -44)],
        'shin.L': [('bend', 96)],
        'foot.L': [('x', 10)],
        'thigh.R': [('x', -8), ('y', 12)],
        'shin.R': [('bend', 22)],
        'foot.R': [('x', 30)],
        'upper_arm.L': [('y', -40), ('x', 12)],
        'forearm.L': [('bend', 12)],
        'upper_arm.R': [('y', 20), ('x', 8)],
        'forearm.R': [('bend', 30)],
    }) | pig(0, 40) | jacket(-10, 30)
    settle = add(down, {'spine': [('x', 3)], 'head': [('x', 6)], 'upper_arm.L': [('y', -4)]})
    return [(0.0, IDLE_BASE), (0.10, hit), (0.24, stagger), (0.42, kneel), (0.60, topple), (0.76, down),
            (0.86, settle), (1.0, down)]



ACTIONS = {
    "idle": idle_keys(),
    "run": run_keys(),
    "stopped": stopped_keys(),
    "light": light_keys(),
    "heavy": heavy_keys(),
    "dodge": dodge_keys(),
    "ranged": ranged_keys(),
    "interact": interact_keys(),
    "death": death_keys(),
}
