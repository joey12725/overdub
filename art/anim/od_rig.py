"""OVERDUB animation rig: the neutral humanoid skeleton and the IK/FK pose solver.

Pure numpy (runs in plain Python and inside Blender). Everything is expressed in GODOT model
space: +Y up, the character faces +Z, her LEFT is +X (so the right, weapon hand is at -X). Units
are metres = tiles. The skeleton uses Godot's SkeletonProfileHumanoid bone names in a clean T-pose.

The solver turns a small, art-directable control pose into a full skeleton pose:

    hips   (dx, dy, dz, yaw, pitch, roll)   offset from rest + absolute orientation, degrees
    chest  (yaw, pitch, roll)               absolute orientation of the upper chest (spine is spread)
    head   (yaw, pitch, roll)               absolute orientation of the head (neck is spread)
    rh/lh  Arm(p, pole, w, e, fist, on)     IK: wrist offset from the shoulder joint in model axes,
                                            elbow pole, optional hand orientation (w = thumb side /
                                            weapon +Y, e = knuckles / weapon +Z = cutting edge),
                                            `on` = grip the right hand's weapon shaft at that offset
    rf/lf  (x, z, lift, yaw, pitch, roll)   IK foot on the floor: pitch > 0 lifts the heel about the
                                            ball, pitch < 0 lifts the toes about the heel
    root   yaw (degrees)                    spins the whole solved pose about the model origin

yaw > 0 turns toward the character's left (+X); pitch > 0 leans forward; roll > 0 leans to her right.

The result of a solve is, per bone, the MODEL-SPACE DELTA ROTATION from the T-pose ("D") plus the
hips position. That representation is skeleton-neutral: a bone's posed global rotation on any
T-posed humanoid is D * (its own global rest), whatever its bone axes are.
"""
import math
import numpy as np

# ───────────────────────────── maths ─────────────────────────────

def v3(x, y, z):
    return np.array([x, y, z], dtype=float)


def norm(a):
    n = np.linalg.norm(a)
    return a / n if n > 1e-9 else a * 0.0


def rx(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=float)


def ry(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=float)


def rz(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=float)


def ypr(yaw, pitch, roll):
    """yaw about +Y (left), pitch about +X (forward), roll about -Z... roll > 0 leans right."""
    return ry(yaw) @ rx(pitch) @ rz(roll)


def frame(x=None, y=None, z=None):
    """Orthonormal right-handed frame (columns x, y, z) from two given axes; the first given axis in
    the order y, z, x is kept exactly, the other is orthogonalised."""
    if y is not None and z is not None:
        y = norm(y); z = norm(z - y * np.dot(z, y)); x = np.cross(y, z)
    elif x is not None and z is not None:
        x = norm(x); z = norm(z - x * np.dot(z, x)); y = np.cross(z, x)
    elif x is not None and y is not None:
        x = norm(x); y = norm(y - x * np.dot(y, x)); z = np.cross(x, y)
    else:
        raise ValueError("frame needs two axes")
    return np.stack([x, y, z], axis=1)


def m2q(m):
    """3x3 rotation -> quaternion (x, y, z, w)."""
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = ((m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s)
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = (0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s)
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = ((m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s)
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = ((m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s)
    q = np.array(q, dtype=float)
    return q / np.linalg.norm(q)


def q2m(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]], dtype=float)


def qslerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0:
        b = -b; d = -d
    if d > 0.9995:
        q = a + (b - a) * t
        return q / np.linalg.norm(q)
    th = math.acos(min(1.0, d))
    return (math.sin((1 - t) * th) * a + math.sin(t * th) * b) / math.sin(th)


def mslerp(a, b, t):
    return q2m(qslerp(m2q(a), m2q(b), t))


def dir_slerp(a, b, t):
    """Interpolate an offset vector along an arc: direction slerps, length lerps."""
    la, lb = np.linalg.norm(a), np.linalg.norm(b)
    if la < 1e-6 or lb < 1e-6:
        return a + (b - a) * t
    ua, ub = a / la, b / lb
    d = float(np.clip(np.dot(ua, ub), -1, 1))
    th = math.acos(d)
    if th < 1e-4 or th > math.pi - 1e-3:
        return a + (b - a) * t
    u = (math.sin((1 - t) * th) * ua + math.sin(t * th) * ub) / math.sin(th)
    return u * (la + (lb - la) * t)


def twist_about(m, axis):
    """Signed twist angle (degrees) of rotation m about `axis` (swing-twist decomposition)."""
    q = m2q(m)
    p = np.dot(q[:3], axis)
    return math.degrees(2 * math.atan2(p, q[3]))


def rot_axis(axis, deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    x, y, z = norm(axis)
    return np.array([
        [c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
        [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
        [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]], dtype=float)


# ───────────────────────────── skeleton (T-pose, Godot model space) ─────────────────────────────
# 1.6 units tall, anime proportions (long legs, short torso, big head).

BONES = []  # (name, parent, joint position)


def _b(name, parent, x, y, z):
    BONES.append((name, parent, v3(x, y, z)))


_b("Hips", None, 0, 0.84, 0)
_b("Spine", "Hips", 0, 0.92, 0)
_b("Chest", "Spine", 0, 1.01, 0)
_b("UpperChest", "Chest", 0, 1.11, 0)
_b("Neck", "UpperChest", 0, 1.26, 0)
_b("Head", "Neck", 0, 1.32, 0)
for _s, _sg in (("Left", 1.0), ("Right", -1.0)):
    _b(_s + "Shoulder", "UpperChest", 0.025 * _sg, 1.215, 0)
    _b(_s + "UpperArm", _s + "Shoulder", 0.135 * _sg, 1.215, 0)
    _b(_s + "LowerArm", _s + "UpperArm", 0.375 * _sg, 1.215, 0)
    _b(_s + "Hand", _s + "LowerArm", 0.595 * _sg, 1.215, 0)
    _b(_s + "ThumbMetacarpal", _s + "Hand", 0.615 * _sg, 1.205, 0.025)
    _b(_s + "ThumbProximal", _s + "ThumbMetacarpal", 0.640 * _sg, 1.200, 0.050)
    _b(_s + "ThumbDistal", _s + "ThumbProximal", 0.665 * _sg, 1.198, 0.066)
    for _f, _fz, _fx in (("Index", 0.026, 0.0), ("Middle", 0.008, 0.004), ("Ring", -0.010, 0.0), ("Little", -0.027, -0.008)):
        _b(_s + _f + "Proximal", _s + "Hand", (0.672 + _fx) * _sg, 1.215, _fz)
        _b(_s + _f + "Intermediate", _s + _f + "Proximal", (0.704 + _fx) * _sg, 1.215, _fz)
        _b(_s + _f + "Distal", _s + _f + "Intermediate", (0.726 + _fx) * _sg, 1.215, _fz)
    _b(_s + "UpperLeg", "Hips", 0.082 * _sg, 0.80, 0)
    _b(_s + "LowerLeg", _s + "UpperLeg", 0.082 * _sg, 0.435, 0)
    _b(_s + "Foot", _s + "LowerLeg", 0.082 * _sg, 0.075, 0)
    _b(_s + "Toes", _s + "Foot", 0.082 * _sg, 0.018, 0.115)

NAMES = [b[0] for b in BONES]
PARENT = {b[0]: b[1] for b in BONES}
REST = {b[0]: b[2] for b in BONES}
# Tail (for building the Blender bone and the mannequin): the first child joint, else an extension.
TAIL = {}
for _n in NAMES:
    kids = [b[0] for b in BONES if b[1] == _n]
    pref = {"Hips": "Spine", "UpperChest": "Neck", "LeftHand": "LeftMiddleProximal", "RightHand": "RightMiddleProximal"}
    if _n in pref:
        TAIL[_n] = REST[pref[_n]].copy()
    elif kids:
        TAIL[_n] = REST[kids[0]].copy()
    elif _n == "Head":
        TAIL[_n] = REST[_n] + v3(0, 0.26, 0)
    elif _n.endswith("Toes"):
        TAIL[_n] = REST[_n] + v3(0, 0, 0.06)
    else:
        TAIL[_n] = REST[_n] + norm(REST[_n] - REST[PARENT[_n]]) * 0.022

HIP_HEIGHT = REST["Hips"][1]
ANKLE_H = REST["LeftFoot"][1]
BALL_Z = 0.115          # ankle -> ball of the foot, along the foot
HEEL_Z = -0.045
L_UPPER_ARM = 0.24
L_LOWER_ARM = 0.22
L_THIGH = REST["LeftUpperLeg"][1] - REST["LeftLowerLeg"][1]
L_SHIN = REST["LeftLowerLeg"][1] - REST["LeftFoot"][1]
# Palm centre (where a grip sits) relative to the wrist, in T-pose model axes.
GRIP_OFFSET = {"Right": v3(-0.082, -0.022, 0.006), "Left": v3(0.082, -0.022, 0.006)}
# Rest "grip frame" of each hand in model axes (columns = weapon X, Y, Z): the weapon's +Y leaves
# the fist on the thumb side (forward in the T-pose, palms down), its +Z (cutting edge / striking
# face) points the way the knuckles do (outward along the arm).
GRIP_REST = {
    "Right": np.stack([v3(0, -1, 0), v3(0, 0, 1), v3(-1, 0, 0)], axis=1),
    "Left": np.stack([v3(0, 1, 0), v3(0, 0, 1), v3(1, 0, 0)], axis=1),
}
SIDE_SIGN = {"Left": 1.0, "Right": -1.0}

# ───────────────────────────── control pose ─────────────────────────────


class Arm:
    """One arm's controls. p: wrist offset from the shoulder joint (model axes). pole: where the
    elbow points. w / e: hand orientation (None = the hand follows the forearm). fist: 0 open .. 1
    closed. on: (left hand) hold the right hand's weapon shaft `on` metres from its grip."""
    __slots__ = ("p", "pole", "w", "e", "fist", "on", "cf")

    def __init__(self, p, pole=(0, -1, -0.4), w=None, e=None, fist=0.5, on=None, cf=False):
        # cf: p, pole, w and e are given in the CHEST frame (they turn with the upper chest), which
        # is how two-handed swings are authored: the hands stay in front of the chest, the torso swings.
        self.cf = cf
        self.p = np.array(p, dtype=float)
        self.pole = np.array(pole, dtype=float)
        self.w = None if w is None else norm(np.array(w, dtype=float))
        self.e = None if e is None else norm(np.array(e, dtype=float))
        self.fist = float(fist)
        self.on = on


def pose(base=None, **kw):
    """A control pose: a dict copied from `base` with overrides."""
    p = dict(base) if base else {
        "hips": (0, 0, 0, 0, 0, 0), "chest": (0, 0, 0), "head": (0, 0, 0),
        "rh": Arm((-0.03, -0.44, 0.03)), "lh": Arm((0.03, -0.44, 0.03)),
        "rf": (-0.09, 0.0, 0, -8, 0, 0), "lf": (0.09, 0.0, 0, 8, 0, 0), "root": 0.0,
    }
    for k, val in kw.items():
        if k not in p:
            raise KeyError(k)
        p[k] = val
    return p


class Solved:
    """Result of a solve: D (bone -> 3x3 model-space delta from the T-pose), P (bone -> joint
    position), the right hand's grip (position, weapon dir, edge dir) and warnings."""

    def __init__(self):
        self.D = {}
        self.P = {}
        self.grip = v3(0, 0, 0)
        self.w = v3(0, 1, 0)
        self.e = v3(0, 0, 1)
        self.lgrip = v3(0, 0, 0)
        self.warn = []


def _two_bone(S, T, l1, l2, pole):
    """Mid joint position for a two-bone chain from S to T; returns (mid, clamped target, stretch)."""
    d = T - S
    dist = np.linalg.norm(d)
    stretch = dist / (l1 + l2)
    lo, hi = abs(l1 - l2) + 1e-3, (l1 + l2) * 0.999
    cd = min(max(dist, lo), hi)
    u = d / dist if dist > 1e-6 else v3(0, -1, 0)
    T2 = S + u * cd
    a = (l1 * l1 - l2 * l2 + cd * cd) / (2 * cd)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    perp = pole - u * np.dot(pole, u)
    if np.linalg.norm(perp) < 1e-5:
        perp = v3(0, 0, 1) - u * u[2]
    perp = norm(perp)
    return S + u * a + perp * h, T2, stretch, perp


def solve(ps, hand_override=None):
    """Solve a control pose. hand_override: {"Right": D, "Left": D} forces the hands' orientation
    (used when blending between keys so the hand slerps instead of re-deriving)."""
    out = Solved()
    D, P = out.D, out.P
    hx, hy, hz, hyaw, hpitch, hroll = ps["hips"]
    D["Hips"] = ypr(hyaw, hpitch, hroll)
    P["Hips"] = REST["Hips"] + v3(hx, hy, hz)
    Duc = ypr(*ps["chest"])
    D["UpperChest"] = Duc
    D["Spine"] = mslerp(D["Hips"], Duc, 0.3)
    D["Chest"] = mslerp(D["Hips"], Duc, 0.66)
    D["Head"] = ypr(*ps["head"])
    D["Neck"] = mslerp(Duc, D["Head"], 0.45)
    for n in ("Spine", "Chest", "UpperChest", "Neck", "Head"):
        P[n] = P[PARENT[n]] + D[PARENT[n]] @ (REST[n] - REST[PARENT[n]])

    def solve_arm(side, arm, target_abs=None):
        sg = SIDE_SIGN[side]
        sh, ua, la, hd = side + "Shoulder", side + "UpperArm", side + "LowerArm", side + "Hand"
        P[sh] = P["UpperChest"] + Duc @ (REST[sh] - REST["UpperChest"])
        # Clavicle: follows the reach a little (shrug / protraction).
        F = Duc if arm.cf else np.eye(3)
        arm_p, arm_pole = F @ arm.p, F @ norm(arm.pole)
        arm_w = None if arm.w is None else F @ arm.w
        arm_e = None if arm.e is None else F @ arm.e
        want = target_abs - (P[sh] + Duc @ (REST[ua] - REST[sh])) if target_abs is not None else arm_p
        local = norm(Duc.T @ want)
        restdir = v3(sg, 0, 0)
        ax = np.cross(restdir, local)
        ang = math.degrees(math.atan2(np.linalg.norm(ax), np.dot(restdir, local)))
        # Only the upward / forward part of the reach moves the clavicle.
        lift = max(0.0, local[1]) * 0.30 + max(0.0, local[2]) * 0.22 + max(0.0, -local[0] * sg) * 0.15
        D[sh] = Duc @ (rot_axis(ax, min(ang, 60.0) * lift) if np.linalg.norm(ax) > 1e-6 else np.eye(3))
        P[ua] = P[sh] + D[sh] @ (REST[ua] - REST[sh])
        S = P[ua]
        T = target_abs if target_abs is not None else S + arm_p
        E, T, stretch, perp = _two_bone(S, T, L_UPPER_ARM, L_LOWER_ARM, arm_pole)
        if stretch > 1.02:
            out.warn.append("%s arm over-reach x%.2f" % (side, stretch))
        u = norm(E - S)
        f = norm(T - E)
        b = f - u * np.dot(f, u)
        b = norm(b) if np.linalg.norm(b) > 1e-4 else -perp
        # Rest frame of an arm bone: x = along the bone, z = the way the forearm folds (+Z), y = hinge.
        R0 = frame(x=v3(sg, 0, 0), z=v3(0, 0, 1))
        Mu = frame(x=u, z=b)
        D[ua] = Mu @ R0.T
        hinge = Mu[:, 1]
        Ml = frame(x=f, y=hinge)
        Dl = Ml @ R0.T
        # Hand orientation.
        if hand_override is not None and side in hand_override:
            Dh = hand_override[side]
        elif arm_w is not None:
            e = arm_e if arm_e is not None else f
            if abs(np.dot(norm(e), arm_w)) > 0.98:
                e = Ml[:, 2]
            Dh = frame(y=arm_w, z=e) @ GRIP_REST[side].T
        else:
            Dh = Dl
        # Forearm pronation: carry part of the hand's twist about the forearm.
        tw = twist_about(Dl.T @ Dh, v3(sg, 0, 0))
        tw = max(-150.0, min(150.0, tw))
        Dl = Dl @ rot_axis(v3(sg, 0, 0), tw * 0.6)
        D[la] = Dl
        D[hd] = Dh
        P[la] = E
        P[hd] = T
        # Fingers.
        c = arm.fist
        for fname in ("Index", "Middle", "Ring", "Little"):
            cum = 0.0
            for seg, deg in (("Proximal", 72.0), ("Intermediate", 88.0), ("Distal", 55.0)):
                cum += deg * c
                D[side + fname + seg] = Dh @ rz(-sg * cum)
        D[side + "ThumbMetacarpal"] = Dh @ ry(-sg * 25.0 * c) @ rz(-sg * 20.0 * c)
        D[side + "ThumbProximal"] = Dh @ ry(-sg * 45.0 * c) @ rz(-sg * 40.0 * c)
        D[side + "ThumbDistal"] = Dh @ ry(-sg * 70.0 * c) @ rz(-sg * 60.0 * c)
        return Dh, T

    rh, lh = ps["rh"], ps["lh"]
    Dh, T = solve_arm("Right", rh)
    out.grip = T + Dh @ GRIP_OFFSET["Right"]
    G = Dh @ GRIP_REST["Right"]
    out.w, out.e = G[:, 1].copy(), G[:, 2].copy()
    if lh.on is not None:
        # Left hand grips the right hand's weapon shaft: same thumb direction, wrapped from the other side.
        if hand_override is not None and "Left" in hand_override:
            Dl_hand = hand_override["Left"]
        else:
            Fl = Duc if lh.cf else np.eye(3)
            wl = Fl @ lh.w if lh.w is not None else out.w
            el = Fl @ lh.e if lh.e is not None else -out.e
            Dl_hand = frame(y=wl, z=el) @ GRIP_REST["Left"].T
        palm = out.grip + out.w * lh.on
        wrist = palm - Dl_hand @ GRIP_OFFSET["Left"]
        ho = dict(hand_override) if hand_override else {}
        ho["Left"] = Dl_hand
        saved = hand_override
        hand_override = ho
        DhL, TL = solve_arm("Left", lh, target_abs=wrist)
        hand_override = saved
    else:
        DhL, TL = solve_arm("Left", lh)
    out.lgrip = TL + DhL @ GRIP_OFFSET["Left"]

    for side, key in (("Left", "lf"), ("Right", "rf")):
        sg = SIDE_SIGN[side]
        fx, fz, lift, fyaw, fpitch, froll = ps[key]
        ul, ll, ft, toe = side + "UpperLeg", side + "LowerLeg", side + "Foot", side + "Toes"
        P[ul] = P["Hips"] + D["Hips"] @ (REST[ul] - REST["Hips"])
        Ry = ry(fyaw)
        base = v3(fx, lift, fz)
        if fpitch >= 0:
            ball = base + Ry @ v3(0, 0, BALL_Z)
            ankle = ball + Ry @ rx(fpitch) @ v3(0, ANKLE_H, -BALL_Z)
        else:
            heel = base + Ry @ v3(0, 0, HEEL_Z)
            ankle = heel + Ry @ rx(fpitch) @ v3(0, ANKLE_H, -HEEL_Z)
        Dfoot = Ry @ rx(fpitch) @ rz(froll)
        fwd_foot = Ry @ v3(0, 0, 1)
        fwd_hips = D["Hips"] @ v3(0, 0, 1)
        pole = norm(fwd_foot * 0.65 + fwd_hips * 0.35 + v3(sg * 0.12, 0, 0))
        K, ankle2, stretch, perp = _two_bone(P[ul], ankle, L_THIGH, L_SHIN, pole)
        if stretch > 1.01:
            out.warn.append("%s leg over-reach x%.2f" % (side, stretch))
        ythigh = norm(P[ul] - K)
        Mt = frame(y=ythigh, z=perp)
        D[ul] = Mt
        Ms = frame(x=Mt[:, 0], y=norm(K - ankle2))
        D[ll] = Ms
        D[ft] = Dfoot
        # Toes stay flat on the floor while the heel lifts (when the foot is near the ground).
        flat = 1.0 if lift < 0.03 else max(0.0, 1.0 - (lift - 0.03) / 0.08)
        D[toe] = Ry @ rx(fpitch * (1.0 - flat) if fpitch > 0 else fpitch) @ rz(froll)
        P[ll] = K
        P[ft] = ankle2
        P[toe] = ankle2 + Dfoot @ (REST[toe] - REST[ft])

    # Finger / thumb joint positions (FK).
    for n in NAMES:
        if n not in P:
            P[n] = P[PARENT[n]] + D[PARENT[n]] @ (REST[n] - REST[PARENT[n]])

    root = ps.get("root", 0.0)
    if abs(root) > 1e-9:
        R = ry(root)
        for n in NAMES:
            D[n] = R @ D[n]
            P[n] = R @ P[n]
        out.grip = R @ out.grip; out.w = R @ out.w; out.e = R @ out.e; out.lgrip = R @ out.lgrip
    return out


# ───────────────────────────── key interpolation ─────────────────────────────

def ease(kind, t):
    if kind == "lin":
        return t
    if kind == "in":
        return t * t
    if kind == "out":
        return 1 - (1 - t) * (1 - t)
    if kind == "io":
        return t * t * (3 - 2 * t)
    if kind == "snap":      # hangs, then whips
        return t * t * t
    if kind == "snap5":
        return t ** 5
    if kind == "out3":      # arrives fast, settles
        return 1 - (1 - t) ** 3
    if kind == "out5":
        return 1 - (1 - t) ** 5
    if kind == "hold":
        return 0.0 if t < 1.0 else 1.0
    if kind == "back":      # overshoots ~10 % then settles
        s = 1.70158
        u = t - 1
        return 1 + u * u * ((s + 1) * u + s)
    raise ValueError(kind)


def _lerp_tuple(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def blend(pa, sa, pb, sb, t):
    """Control pose between keys a and b (with their solves, for the hand orientations)."""
    ps = {}
    for k in ("hips", "chest", "head", "rf", "lf"):
        ps[k] = _lerp_tuple(pa[k], pb[k], t)
    ps["root"] = pa.get("root", 0.0) + (pb.get("root", 0.0) - pa.get("root", 0.0)) * t
    over = {}
    for k, side in (("rh", "Right"), ("lh", "Left")):
        a, b = pa[k], pb[k]
        Ra, Rb = ry(-pa.get("root", 0.0)), ry(-pb.get("root", 0.0))
        if a.cf and b.cf:
            arm = Arm(dir_slerp(a.p, b.p, t), norm(a.pole) + (norm(b.pole) - norm(a.pole)) * t, fist=a.fist + (b.fist - a.fist) * t, cf=True)
        else:
            Fa = Ra @ sa.D["UpperChest"] if a.cf else np.eye(3)
            Fb = Rb @ sb.D["UpperChest"] if b.cf else np.eye(3)
            pole = Fa @ norm(a.pole) + (Fb @ norm(b.pole) - Fa @ norm(a.pole)) * t
            arm = Arm(dir_slerp(Fa @ a.p, Fb @ b.p, t), pole, fist=a.fist + (b.fist - a.fist) * t)
        if a.on is not None and b.on is not None:
            arm.on = a.on + (b.on - a.on) * t
        elif a.on is not None or b.on is not None:
            # Taking the hand on / off the shaft: blend the wrist position between the two solves.
            arm.on = None
            arm.cf = False
            pa_abs = sa.P[side + "Hand"] - sa.P[side + "UpperArm"]
            pb_abs = sb.P[side + "Hand"] - sb.P[side + "UpperArm"]
            arm.p = dir_slerp(Ra @ pa_abs, Rb @ pb_abs, t)
        ps[k] = arm
        Ha = ry(-pa.get("root", 0.0)) @ sa.D[side + "Hand"]
        Hb = ry(-pb.get("root", 0.0)) @ sb.D[side + "Hand"]
        over[side] = mslerp(Ha, Hb, t)
    return solve(ps, hand_override=over)


class Clip:
    """A clip: name, length (s), loop flag and either keys [(t, pose, ease)] with t in 0..1, or a
    function fn(t) -> control pose. `meta` carries tags for the game (style, fire fraction ...)."""

    def __init__(self, name, length=1.0, loop=False, keys=None, fn=None, meta=None, fps=60):
        self.name, self.length, self.loop, self.keys, self.fn = name, length, loop, keys, fn
        self.meta = meta or {}
        self.fps = fps
        self._solved = None

    def frame_count(self):
        return int(round(self.length * self.fps)) + 1

    def sample(self, t):
        """Solved pose at normalised time t (0..1)."""
        if self.fn is not None:
            return solve(self.fn(t))
        keys = self.keys
        if self._solved is None:
            self._solved = [solve(k[1]) for k in keys]
        if t <= keys[0][0]:
            return self._solved[0]
        for i in range(1, len(keys)):
            if t <= keys[i][0] + 1e-9:
                t0, t1 = keys[i - 1][0], keys[i][0]
                a = 1.0 if t1 - t0 < 1e-9 else (t - t0) / (t1 - t0)
                a = ease(keys[i][2], min(1.0, max(0.0, a)))
                if a <= 0.0:
                    return self._solved[i - 1]
                if a >= 1.0 and keys[i][2] != "back":
                    return self._solved[i]
                return blend(keys[i - 1][1], self._solved[i - 1], keys[i][1], self._solved[i], a)
        return self._solved[-1]

    def bake(self):
        """Every frame: list of Solved, plus collected warnings."""
        n = self.frame_count()
        frames, warns = [], []
        for i in range(n):
            s = self.sample(i / (n - 1))
            frames.append(s)
            for w in s.warn:
                warns.append("%s f%d: %s" % (self.name, i, w))
        return frames, warns
