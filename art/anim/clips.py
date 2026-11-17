"""OVERDUB — every Moxie clip, hand-keyed on the control rig in od_rig.py.

Model space: +Y up, she faces +Z, her left is +X (the weapon hand is at -X).
Melee clips are exactly 1.0 s, time-normalised: wind-up 0..0.40, hit window 0.40..0.60, recovery
0.60..1.0. The game scrubs each third by the weapon's real windup / active / recover ticks
(data/gear.json), so key times below are chosen against those real durations (noted per clip as
w/a/r local ticks at 60 Hz): one clip-fraction of 0.40 is `windup` ticks long, and so on.

Principles applied to every attack:
  - the anticipation pose is reached EARLY in the wind-up (ease out) and then hangs, so even a
    two-tick wind-up shows one clean "about to" frame; the strike itself is a `snap` (t^3 / t^5);
  - hips lead, chest follows, the arm and the weapon arrive last (drag), then overshoot;
  - the contact pose sits exactly at 0.40 with the weapon ON the target line, weight already forward;
  - the free arm counter-swings; the head stays on the target while the torso winds;
  - recovery holds the follow-through for a beat before returning (the "pose you can read").
"""
from od_rig import Arm, pose, Clip
import math


def R(p, w=None, e=None, pole=(-0.45, -0.8, -0.4), fist=1.0, cf=False):
    return Arm(p, pole=pole, w=w, e=e, fist=fist, cf=cf)


def L(p, w=None, e=None, pole=(0.45, -0.8, -0.4), fist=0.6, on=None, cf=False):
    return Arm(p, pole=pole, w=w, e=e, fist=fist, on=on, cf=cf)


def P(base, **kw):
    return pose(base, **kw)


# ───────────────────────────── base stances ─────────────────────────────

# Combat-ready guard: left foot forward, torso bladed to the right, weapon up in front.
GUARD = pose(
    hips=(0, -0.07, 0, -22, 4, 0), chest=(-30, 10, 0), head=(0, 4, 0),
    rh=R((-0.05, -0.27, 0.22), w=(0.25, 0.78, 0.57)),
    lh=L((0.03, -0.23, 0.26), fist=0.75),
    lf=(0.12, 0.17, 0, 8, 0, 0), rf=(-0.15, -0.15, 0, -40, 0, 0))

FL = (0.12, 0.17, 0, 8, 0, 0)
FR = (-0.15, -0.15, 0, -40, 0, 0)


def _pulse(x, sharp=3.0):
    """1 on every integer x, falling off between (a beat accent)."""
    return (0.5 + 0.5 * math.cos(2 * math.pi * x)) ** sharp


# ───────────────────────────── locomotion ─────────────────────────────

def idle_fn(t):
    """2.0 s = four beats at 120 bpm: hip popped over the right leg, nodding and tapping the left
    toe to the beat, one slow weight sway and one breath across the loop."""
    b = _pulse(t * 4.0)                  # accent on each beat
    off = _pulse(t * 4.0 + 0.5, 2.0)     # between the beats
    sway = math.sin(2 * math.pi * t)
    sway2 = math.sin(2 * math.pi * t + 0.9)
    breath = math.sin(2 * math.pi * t - 0.6)
    return pose(
        hips=(-0.035 + 0.016 * sway, -0.025 - 0.026 * b, 0.0, -10 + 3 * sway, 2, -7 + 1.5 * sway),
        chest=(-14 + 5 * sway2, 3 + 1.5 * breath + 2.0 * b, 4 - 1.5 * sway),
        head=(-4 + 8 * sway2, 1 + 12 * b, -4 * sway),
        rh=R((-0.07, -0.425 + 0.006 * breath - 0.006 * b, 0.05), w=(-0.2, -0.5, 0.84), pole=(-0.5, -0.5, -0.7)),
        lh=L((0.135, -0.315 + 0.006 * breath, 0.03), pole=(0.9, -0.1, -0.45), fist=0.8),
        rf=(-0.075, -0.02, 0, -16, 0, 0),
        lf=(0.15, 0.09, 0, 26, -17 * off, 0))


def run_fn(t):
    """0.6 s, two steps. Big anime stride: 24 degrees of forward lean, arms pumping, the blade
    trailing behind, a real flight phase. Left foot strikes at t = 0."""
    def foot(u, sg):
        u = u % 1.0
        if u < 0.36:                      # stance: the foot travels back under the body
            s = u / 0.36
            z = 0.30 - 0.60 * s
            lift = 0.0
            pitch = -18 + 30 * min(1.0, s * 3.0) + 46 * max(0.0, (s - 0.55) / 0.45) ** 1.5
        else:                             # swing: heel kicks up behind, knee drives through
            s = (u - 0.36) / 0.64
            e = s * s * (3 - 2 * s)
            z = -0.30 + 0.60 * e
            lift = 0.30 * math.sin(math.pi * min(1.0, s * 1.25)) ** 0.8 * (1 - 0.35 * s) + 0.02 * math.sin(math.pi * s)
            pitch = 58 * (1 - s) ** 0.6 * (1 if s < 0.8 else (1 - s) / 0.2) - 18 * max(0.0, (s - 0.7) / 0.3)
        return (0.07 * sg, z, max(0.0, lift), 4 * sg, pitch, 0)
    ph = 2 * math.pi * t
    lfoot = foot(t, 1.0)
    rfoot = foot(t + 0.5, -1.0)
    # Arms oppose legs: the right arm is forward while the left leg is forward (t ~ 0).
    a = math.cos(ph)
    bob = math.cos(2 * ph - 0.9)
    rp = (-0.06 + 0.07 * max(0, a), -0.20 + 0.08 * a, 0.06 + 0.25 * a)
    lp = (0.06 - 0.07 * max(0, -a), -0.20 - 0.08 * a, 0.06 - 0.25 * a)
    return pose(
        hips=(0, -0.085 + 0.035 * bob, 0.0, -9 * a, 14, 3 * math.sin(ph)),
        chest=(13 * a, 24, -3 * math.sin(ph)),
        head=(0, 8, 0),
        rh=R(rp, w=(-0.25, 0.62 - 0.15 * a, -0.74), pole=(-0.35, -0.3, -0.9)),
        lh=L(lp, pole=(0.35, -0.3, -0.9), fist=0.9),
        lf=lfoot, rf=rfoot)


STOPPED = pose(
    hips=(0, -0.03, 0, 0, 3, 0), chest=(0, 12, 0), head=(0, 26, 0),
    rh=R((-0.07, -0.43, 0.02), w=(-0.1, -0.86, 0.5), pole=(-0.6, -0.4, -0.7)),
    lh=L((0.07, -0.44, 0.02), pole=(0.6, -0.4, -0.7), fist=0.35),
    rf=(-0.10, 0.0, 0, -12, 0, 0), lf=(0.10, 0.0, 0, 12, 0, 0))


def countin_fn(t):
    """1.0 s = two beats: bouncing on the toes in guard, rolling the shoulders."""
    b = _pulse(t * 2.0, 2.0)
    sw = math.sin(2 * math.pi * t)
    g = GUARD
    return P(g,
             hips=(0, -0.05 - 0.05 * b, 0, -22 + 3 * sw, 4, 0),
             chest=(-30 + 7 * sw, 10 + 3 * b, 2 * sw), head=(0, 3 + 6 * b, 0),
             rh=R((-0.05, -0.27 - 0.02 * b, 0.22), w=(0.25 + 0.1 * sw, 0.78, 0.57)),
             lh=L((0.03, -0.23 + 0.03 * b, 0.26), fist=0.9),
             lf=(0.12, 0.17, 0, 8, 14 * (1 - b), 0), rf=(-0.15, -0.15, 0, -40, 18 * (1 - b), 0))


# ───────────────────────────── melee ─────────────────────────────

def blade_light():
    # splice_blade 6/4/10: a flat right-to-left slash. Anticipation by tick 2, strike on ticks 4-6.
    A = P(GUARD, hips=(-0.02, -0.10, -0.05, -38, 6, 0), chest=(-74, 8, 6), head=(-8, 6, 0),
          rh=R((-0.27, 0.03, -0.15), w=(-0.55, 0.45, -0.7), e=(0.6, 0, 0.8), pole=(-0.6, -0.6, -0.5)),
          lh=L((0.10, -0.12, 0.33)), rf=(-0.15, -0.15, 0, -50, 0, 0))
    C = P(GUARD, hips=(0.02, -0.12, 0.10, 12, 8, 0), chest=(8, 14, -4), head=(0, 8, 0),
          rh=R((-0.16, -0.16, 0.38), w=(0.35, -0.05, 0.93), e=(1, 0, 0)),
          lh=L((0.16, -0.20, -0.05)), lf=(0.13, 0.30, 0, 5, 0, 0), rf=(-0.15, -0.16, 0, -45, 25, 0))
    T = P(C, hips=(0.03, -0.13, 0.12, 28, 8, 0), chest=(42, 14, -6),
          rh=R((0.06, -0.20, 0.36), w=(0.80, -0.15, 0.55), e=(0.5, 0, -0.85)), lh=L((0.14, -0.22, -0.18)))
    F = P(C, hips=(0.03, -0.12, 0.12, 36, 8, 0), chest=(68, 12, -8), head=(10, 8, 0),
          rh=R((0.30, -0.20, 0.14), w=(0.75, -0.25, -0.6), e=(-0.6, 0, -0.8)), lh=L((0.12, -0.22, -0.27)))
    F2 = P(F, hips=(0.03, -0.11, 0.11, 32, 8, 0), chest=(58, 12, -6))
    return [(0, GUARD, "lin"), (0.18, A, "out3"), (0.40, C, "snap"), (0.47, T, "lin"), (0.57, F, "out3"),
            (0.72, F2, "io"), (1.0, GUARD, "io")]


def blade_heavy():
    # splice_blade 16/5/20: overhead diagonal cleave with a step-in; ends low and committed.
    D0 = P(GUARD, hips=(0, -0.13, -0.02, -28, 8, 0), chest=(-40, 16, 0),
           rh=R((-0.12, -0.22, 0.14), w=(0.1, 0.9, 0.42)))
    W = P(GUARD, hips=(-0.03, -0.04, -0.08, -45, -4, 0), chest=(-80, -12, 8), head=(-5, 0, 0),
          rh=R((-0.12, 0.36, -0.16), w=(-0.3, 0.3, -0.9), e=(0, 1, 0), pole=(-0.9, -0.1, -0.4)),
          lh=L((0.14, 0.02, 0.36), fist=0.2), lf=(0.12, 0.22, 0.07, 8, -12, 0), rf=(-0.16, -0.18, 0, -55, 0, 0))
    W2 = P(W, hips=(-0.03, -0.02, -0.09, -48, -6, 0), chest=(-84, -16, 8),
           rh=R((-0.13, 0.385, -0.17), w=(-0.3, 0.15, -0.94), e=(0, 1, 0), pole=(-0.9, -0.1, -0.4)))
    C = P(GUARD, hips=(0.02, -0.20, 0.20, 15, 14, 0), chest=(15, 32, -6), head=(0, 14, 0),
          rh=R((-0.10, -0.10, 0.42), w=(0.25, -0.35, 0.9), e=(0.3, -0.9, -0.3)),
          lh=L((0.20, -0.10, -0.18)), lf=(0.13, 0.44, 0, 5, 0, 0), rf=(-0.16, -0.20, 0, -50, 35, 0))
    T = P(C, hips=(0.03, -0.26, 0.22, 28, 18, 0), chest=(40, 40, -8),
          rh=R((0.10, -0.34, 0.26), w=(0.55, -0.75, 0.35), e=(0.5, -0.3, -0.8)), lh=L((0.16, -0.06, -0.26)))
    F = P(C, hips=(0.03, -0.28, 0.22, 35, 20, 0), chest=(58, 44, -10), head=(8, 16, 0),
          rh=R((0.22, -0.36, 0.10), w=(0.6, -0.6, -0.5), e=(-0.5, -0.4, -0.75)), lh=L((0.10, -0.03, -0.31), fist=0.3))
    F2 = P(F, hips=(0.03, -0.24, 0.20, 32, 18, 0), chest=(52, 38, -8))
    return [(0, GUARD, "lin"), (0.12, D0, "out"), (0.29, W, "out3"), (0.345, W2, "out"), (0.40, C, "snap"),
            (0.48, T, "lin"), (0.58, F, "out3"), (0.76, F2, "io"), (1.0, GUARD, "io")]


def shiv_light():
    # stylus_shiv 3/3/6: a lunging jab straight down the facing line and straight back.
    A = P(GUARD, hips=(-0.01, -0.10, -0.03, -30, 6, 0), chest=(-50, 10, 0),
          rh=R((-0.10, -0.20, -0.10), w=(0.0, 0.3, 0.95), e=(0, -0.95, 0.3), pole=(-0.3, -0.5, -0.8)),
          lh=L((0.08, -0.16, 0.32)))
    C = P(GUARD, hips=(0.02, -0.14, 0.16, 20, 10, 0), chest=(38, 18, -4), head=(0, 8, 0),
          rh=R((0.04, -0.10, 0.43), w=(0.05, 0.12, 0.99), e=(0, -1, 0.1)),
          lh=L((0.14, -0.20, -0.14)), lf=(0.12, 0.34, 0, 5, 0, 0), rf=(-0.15, -0.14, 0, -45, 30, 0))
    C2 = P(C, hips=(0.02, -0.15, 0.18, 24, 11, 0), chest=(44, 19, -4),
           rh=R((0.05, -0.11, 0.44), w=(0.08, 0.05, 0.99), e=(0, -1, 0.1)))
    B = P(GUARD, hips=(0.01, -0.10, 0.08, -8, 6, 0), chest=(-14, 10, 0),
          rh=R((-0.08, -0.22, 0.08), w=(0.1, 0.5, 0.86), e=(0, -0.9, 0.4)), lh=L((0.06, -0.2, 0.2)),
          lf=(0.12, 0.26, 0, 6, 0, 0), rf=(-0.15, -0.14, 0, -42, 10, 0))
    return [(0, GUARD, "lin"), (0.17, A, "out3"), (0.40, C, "snap"), (0.52, C2, "out3"), (0.74, B, "out"),
            (1.0, GUARD, "io")]


def shiv_heavy():
    # stylus_shiv 9/4/12: a backhand rip, left to right, off a deep lunge (the opposite line to the
    # blade's slash, so the two never read alike).
    A = P(GUARD, hips=(0.0, -0.14, -0.04, 22, 8, 0), chest=(56, 16, -6), head=(-6, 8, 0),
          rh=R((0.27, -0.04, 0.16), w=(0.8, 0.3, -0.5), e=(-0.4, 0, -0.9), pole=(-0.2, -0.9, -0.3)),
          lh=L((0.05, -0.30, 0.10)))
    C = P(GUARD, hips=(0.0, -0.20, 0.18, -5, 10, 0), chest=(-12, 16, 4), head=(0, 8, 0),
          rh=R((-0.12, -0.10, 0.42), w=(-0.25, 0.05, 0.97), e=(-1, 0, 0)),
          lh=L((0.20, -0.12, 0.10)), lf=(0.12, 0.40, 0, 5, 0, 0), rf=(-0.15, -0.16, 0, -45, 30, 0))
    T = P(C, hips=(0.0, -0.21, 0.19, -15, 10, 0), chest=(-46, 16, 5),
          rh=R((-0.36, -0.10, 0.18), w=(-0.9, 0.05, 0.42), e=(-0.4, 0, -0.9)), lh=L((0.18, -0.16, 0.20)))
    F = P(C, hips=(0.0, -0.20, 0.18, -26, 10, 0), chest=(-72, 14, 6), head=(-8, 8, 0),
          rh=R((-0.40, -0.02, -0.10), w=(-0.85, 0.15, -0.5), e=(0.5, 0, -0.85), pole=(-0.3, -0.9, -0.3)),
          lh=L((0.14, -0.18, 0.28)))
    F2 = P(F, hips=(0.0, -0.17, 0.15, -24, 9, 0), chest=(-62, 13, 5))
    return [(0, GUARD, "lin"), (0.24, A, "out3"), (0.40, C, "snap"), (0.49, T, "lin"), (0.59, F, "out3"),
            (0.76, F2, "io"), (1.0, GUARD, "io")]


SLEDGE_ON = -0.12


def blunt_light():
    # amp_sledge 12/5/18: two-handed side swing. The head lags the hips, then drags her round.
    def hands(p, w, e=None):
        return dict(rh=R(p, w=w, e=e, cf=True, pole=(-0.6, -0.7, -0.3)), lh=L((0, 0, 0), on=SLEDGE_ON, cf=True, pole=(0.6, -0.7, -0.3), fist=1.0))
    W = P(GUARD, hips=(-0.03, -0.12, -0.06, -40, 6, 0), chest=(-80, 12, 8), head=(-10, 6, 0),
          rf=(-0.16, -0.16, 0, -55, 0, 0), **hands((0.12, -0.25, 0.25), (-0.85, 0.3, -0.42), (0.4, 0, -0.9)))
    DR = P(W, hips=(0.0, -0.14, 0.02, -5, 8, 0), chest=(-52, 14, 4), head=(-4, 6, 0),
           **hands((0.12, -0.26, 0.26), (-0.92, 0.2, -0.32), (0.3, 0, -0.95)))
    C = P(GUARD, hips=(0.02, -0.15, 0.10, 20, 10, 0), chest=(6, 16, -4), head=(0, 8, 0),
          lf=(0.13, 0.30, 0, 5, 0, 0), rf=(-0.16, -0.16, 0, -45, 28, 0),
          **hands((0.12, -0.24, 0.30), (0.12, -0.12, 0.98), (1, 0, -0.1)))
    T = P(C, hips=(0.04, -0.15, 0.11, 38, 10, 0), chest=(52, 16, -8),
          **hands((0.12, -0.24, 0.30), (0.62, -0.10, 0.78), (0.8, 0, -0.6)))
    F = P(C, hips=(0.06, -0.13, 0.10, 52, 8, -3), chest=(88, 12, -10), head=(20, 8, 0),
          rf=(-0.14, -0.10, 0, -5, 45, 0), **hands((0.12, -0.22, 0.28), (0.92, 0.22, 0.30), (0.3, 0, -0.95)))
    F2 = P(F, hips=(0.05, -0.12, 0.08, 44, 8, -2), chest=(70, 14, -6), head=(12, 8, 0),
           **hands((0.12, -0.27, 0.27), (0.8, -0.25, 0.55), (0.5, 0, -0.85)))
    return [(0, GUARD, "lin"), (0.20, W, "out3"), (0.32, DR, "in"), (0.40, C, "snap"), (0.49, T, "lin"),
            (0.60, F, "out3"), (0.80, F2, "io"), (1.0, GUARD, "io")]


def blunt_heavy():
    # amp_sledge 28/6/32: the overhead smash. Dip, hoist, hang on the toes, then everything comes down.
    def hands(p, w, e=None):
        return dict(rh=R(p, w=w, e=e, cf=True, pole=(-0.8, -0.5, -0.3)), lh=L((0, 0, 0), on=SLEDGE_ON, cf=True, pole=(0.8, -0.5, -0.3), fist=1.0))
    DIP = P(GUARD, hips=(0, -0.17, 0.0, -8, 14, 0), chest=(-10, 28, 0), head=(0, 10, 0),
            **hands((0.12, -0.30, 0.24), (0.1, -0.12, 0.99), (0, -1, -0.12)))
    UP = P(GUARD, hips=(0, 0.0, -0.05, 0, -6, 0), chest=(-6, -16, 0), head=(0, -4, 0),
           lf=(0.13, 0.17, 0, 8, 22, 0), rf=(-0.15, -0.13, 0, -30, 26, 0),
           **hands((0.11, 0.27, 0.06), (0.0, 0.45, -0.89), (0, 0.9, 0.45)))
    HANG = P(UP, hips=(0, 0.02, -0.07, 0, -10, 0), chest=(-4, -26, 0), head=(0, -6, 0),
             lf=(0.13, 0.19, 0.02, 8, 30, 0), rf=(-0.15, -0.13, 0, -30, 34, 0),
             **hands((0.11, 0.28, 0.03), (0.0, 0.05, -1.0), (0, 1, 0.05)))
    C = P(GUARD, hips=(0, -0.30, 0.12, 0, 22, 0), chest=(0, 56, 0), head=(0, 26, 0),
          lf=(0.15, 0.32, 0, 8, 0, 0), rf=(-0.16, -0.10, 0, -30, 22, 0),
          **hands((0.12, -0.06, 0.42), (0.0, 0.16, 0.985), (0, -1, 0.16)))
    SQ = P(C, hips=(0, -0.37, 0.13, 0, 26, 0), chest=(0, 62, 0), head=(0, 30, 0),
           **hands((0.12, -0.08, 0.42), (0.0, 0.20, 0.98), (0, -1, 0.2)))
    HOLD = P(C, hips=(0, -0.31, 0.12, 0, 22, 0), chest=(0, 54, 0), head=(0, 22, 0),
             **hands((0.12, -0.06, 0.41), (0.0, 0.17, 0.985), (0, -1, 0.17)))
    HEAVE = P(GUARD, hips=(0, -0.16, 0.06, -10, 10, 0), chest=(-16, 26, 0), head=(0, 8, 0),
              lf=(0.14, 0.26, 0, 8, 0, 0), rf=(-0.16, -0.12, 0, -36, 0, 0),
              **hands((0.12, -0.28, 0.26), (0.1, -0.2, 0.97), (0, -1, -0.2)))
    return [(0, GUARD, "lin"), (0.10, DIP, "out"), (0.27, UP, "io"), (0.335, HANG, "out"), (0.40, C, "snap"),
            (0.46, SQ, "out3"), (0.62, HOLD, "io"), (0.82, HEAVE, "io"), (1.0, GUARD, "io")]


def whip_light():
    # reel_lash 9/3/14: an overhand crack down the facing line, with the wrist snap-back.
    A = P(GUARD, hips=(-0.02, -0.08, -0.05, -32, 2, 0), chest=(-52, -4, 4), head=(-4, 4, 0),
          rh=R((-0.16, 0.22, -0.22), w=(-0.2, 0.5, -0.85), e=(0, 0.85, 0.5), pole=(-0.9, -0.2, -0.3)),
          lh=L((0.10, -0.02, 0.38), fist=0.2))
    C = P(GUARD, hips=(0.02, -0.12, 0.12, 15, 8, 0), chest=(32, 18, -4), head=(0, 8, 0),
          rh=R((0.0, -0.02, 0.455), w=(0.0, -0.05, 1.0), e=(0, -1, 0)),
          lh=L((0.16, -0.16, -0.16)), lf=(0.12, 0.32, 0, 5, 0, 0), rf=(-0.15, -0.15, 0, -45, 28, 0))
    SN = P(C, chest=(36, 16, -4), rh=R((-0.02, 0.07, 0.33), w=(0.0, 0.5, 0.87), e=(0, -0.87, 0.5)))
    F = P(C, hips=(0.02, -0.12, 0.11, 18, 8, 0), chest=(40, 18, -4),
          rh=R((0.05, -0.25, 0.30), w=(0.2, -0.4, 0.9), e=(0, -0.9, -0.4)), lh=L((0.14, -0.2, -0.1)))
    return [(0, GUARD, "lin"), (0.20, A, "out3"), (0.40, C, "snap"), (0.47, SN, "out3"), (0.64, F, "io"),
            (1.0, GUARD, "io")]


def whip_heavy():
    # reel_lash 18/4/22: one lasso turn overhead, then a full-stretch lunging crack.
    def up(p, w, yaw, hy=-0.06):
        return P(GUARD, hips=(0, hy, -0.03, yaw * 0.5, 2, 0), chest=(yaw, -2, 2), head=(0, 2, 0),
                 rh=R(p, w=w, pole=(-0.9, -0.1, -0.3)), lh=L((0.14, -0.10, 0.30), fist=0.3))
    K1 = up((-0.10, 0.34, 0.06), (0.5, 0.5, 0.7), -18)
    K2 = up((-0.14, 0.36, -0.04), (-0.9, 0.2, 0.3), -30)
    K3 = up((-0.10, 0.37, -0.10), (-0.3, 0.2, -0.93), -44, -0.10)
    K4 = up((-0.03, 0.35, -0.05), (0.85, 0.25, -0.45), -56, -0.15)
    C = P(GUARD, hips=(0.02, -0.24, 0.20, 20, 12, 0), chest=(42, 28, -6), head=(0, 12, 0),
          rh=R((0.02, -0.10, 0.45), w=(0.0, -0.08, 1.0), e=(0, -1, 0)),
          lh=L((0.18, 0.0, -0.30), fist=0.3), lf=(0.13, 0.46, 0, 5, 0, 0), rf=(-0.16, -0.22, 0, -50, 40, 0))
    SN = P(C, chest=(46, 26, -6), rh=R((0.0, 0.02, 0.35), w=(0.0, 0.42, 0.9), e=(0, -0.9, 0.42)))
    F = P(C, hips=(0.02, -0.22, 0.19, 22, 12, 0), chest=(46, 28, -6),
          rh=R((0.06, -0.27, 0.30), w=(0.2, -0.3, 0.93), e=(0, -0.95, -0.3)), lh=L((0.16, -0.08, -0.22)))
    return [(0, GUARD, "lin"), (0.11, K1, "out"), (0.19, K2, "lin"), (0.26, K3, "lin"), (0.33, K4, "lin"),
            (0.40, C, "in"), (0.48, SN, "out3"), (0.66, F, "io"), (1.0, GUARD, "io")]


def gauntlet_light():
    # speaker_knuckles 2/3/5: a straight right off the back foot. Two-tick wind-up: one load frame.
    A = P(GUARD, hips=(-0.01, -0.09, -0.03, -30, 6, 0), chest=(-48, 10, 0), head=(0, 6, 0),
          rh=R((-0.04, -0.14, 0.08), pole=(-0.5, -0.6, -0.6)), lh=L((0.0, -0.06, 0.27), fist=1.0))
    C = P(GUARD, hips=(0.01, -0.10, 0.10, 25, 8, 0), chest=(50, 14, -4), head=(0, 8, 0),
          rh=R((0.06, -0.03, 0.452), w=(1, 0, 0), e=(0, 0, 1), pole=(-0.7, -0.5, -0.3)),
          lh=L((-0.02, -0.12, 0.16), fist=1.0), lf=(0.12, 0.28, 0, 5, 0, 0), rf=(-0.15, -0.14, 0, -30, 35, 0))
    C2 = P(C, hips=(0.01, -0.105, 0.115, 28, 8, 0), chest=(56, 15, -4),
           rh=R((0.07, -0.03, 0.458), w=(1, 0, 0), e=(0, 0, 1), pole=(-0.7, -0.5, -0.3)))
    B = P(GUARD, hips=(0.0, -0.08, 0.05, -6, 5, 0), chest=(-12, 10, 0),
          rh=R((-0.03, -0.15, 0.15), pole=(-0.5, -0.6, -0.6)), lh=L((0.02, -0.10, 0.24), fist=1.0),
          lf=(0.12, 0.23, 0, 6, 0, 0), rf=(-0.15, -0.14, 0, -38, 10, 0))
    return [(0, GUARD, "lin"), (0.15, A, "out3"), (0.40, C, "snap"), (0.51, C2, "out3"), (0.74, B, "out"),
            (1.0, GUARD, "io")]


def gauntlet_heavy():
    # speaker_knuckles 7/4/14: a rising uppercut that takes her off the floor.
    A = P(GUARD, hips=(0, -0.26, -0.02, -30, 12, 0), chest=(-56, 30, 6), head=(0, -4, 0),
          rh=R((-0.04, -0.40, 0.02), pole=(-0.3, -0.2, -0.95)), lh=L((0.02, -0.10, 0.25), fist=1.0))
    C = P(GUARD, hips=(0, -0.06, 0.12, 20, 0, 0), chest=(42, -6, -4), head=(0, -4, 0),
          rh=R((0.06, -0.02, 0.36), pole=(-0.3, -0.8, -0.5)), lh=L((0.06, -0.24, 0.06), fist=1.0),
          lf=(0.12, 0.28, 0, 5, 12, 0), rf=(-0.15, -0.10, 0, -35, 38, 0))
    AP = P(GUARD, hips=(0, 0.10, 0.16, 35, -6, 0), chest=(64, -14, -6), head=(0, -12, 0),
           rh=R((0.02, 0.38, 0.20), pole=(-0.6, -0.3, 0.7)), lh=L((0.10, -0.30, -0.12), fist=1.0),
           lf=(0.12, 0.30, 0.10, 5, 38, 0), rf=(-0.14, -0.02, 0.15, -25, 48, 0))
    LD = P(GUARD, hips=(0, -0.17, 0.16, 25, 8, 0), chest=(40, 12, 0), head=(0, 4, 0),
           rh=R((0.0, 0.10, 0.34), pole=(-0.6, -0.5, 0.2)), lh=L((0.08, -0.26, 0.04), fist=1.0),
           lf=(0.12, 0.30, 0, 5, 0, 0), rf=(-0.15, -0.06, 0, -32, 0, 0))
    LD2 = P(LD, hips=(0, -0.21, 0.14, 10, 10, 0), chest=(10, 16, 0),
            rh=R((-0.03, -0.16, 0.24)), lh=L((0.03, -0.18, 0.24), fist=1.0))
    return [(0, GUARD, "lin"), (0.22, A, "out3"), (0.40, C, "snap"), (0.50, AP, "out3"), (0.64, LD, "in"),
            (0.80, LD2, "out"), (1.0, GUARD, "io")]


GLAIVE_ON = -0.34


def _glaive_hands(p, w, e=None):
    return dict(rh=R(p, w=w, e=e, cf=True, pole=(-0.7, -0.6, -0.2)),
                lh=L((0, 0, 0), on=GLAIVE_ON, cf=True, pole=(0.5, -0.5, -0.7), fist=1.0))


def polearm_light():
    # vinyl_glaive 10/6/14: a 200-degree sweep, right to left, at arm's length.
    W = P(GUARD, hips=(-0.02, -0.11, -0.04, -36, 6, 0), chest=(-72, 8, 6), head=(-10, 6, 0),
          **_glaive_hands((0.05, -0.22, 0.28), (-0.64, 0.10, 0.76), (0.76, 0, 0.64)))
    C = P(GUARD, hips=(0.0, -0.13, 0.06, 0, 8, 0), chest=(-14, 12, 0), head=(0, 8, 0),
          lf=(0.13, 0.26, 0, 5, 0, 0), rf=(-0.16, -0.16, 0, -45, 15, 0),
          **_glaive_hands((0.05, -0.20, 0.36), (-0.36, -0.06, 0.93), (0.93, 0, 0.36)))
    T = P(C, hips=(0.02, -0.13, 0.07, 26, 8, 0), chest=(42, 12, -4),
          **_glaive_hands((0.05, -0.20, 0.37), (0.17, -0.06, 0.98), (0.98, 0, -0.17)))
    F = P(C, hips=(0.03, -0.12, 0.06, 46, 8, 0), chest=(82, 10, -8), head=(18, 8, 0),
          rf=(-0.14, -0.12, 0, -10, 40, 0), **_glaive_hands((0.05, -0.20, 0.34), (0.40, 0.0, 0.92), (0.92, 0, -0.4)))
    F2 = P(F, hips=(0.03, -0.11, 0.05, 38, 8, 0), chest=(66, 11, -6), head=(12, 8, 0),
           **_glaive_hands((0.05, -0.23, 0.30), (0.3, 0.1, 0.95), (0.95, 0, -0.3)))
    return [(0, GUARD, "lin"), (0.20, W, "out3"), (0.40, C, "snap"), (0.48, T, "lin"), (0.57, F, "out3"),
            (0.74, F2, "io"), (1.0, GUARD, "io")]


def polearm_heavy():
    # vinyl_glaive 20/8/24: coil, then a full 360-degree spinning sweep on the left foot.
    W = P(GUARD, hips=(-0.02, -0.14, -0.04, -30, 8, 0), chest=(-62, 12, 6), head=(-6, 6, 0),
          **_glaive_hands((0.05, -0.22, 0.28), (-0.64, 0.10, 0.76), (0.76, 0, 0.64)))
    W2 = P(W, hips=(-0.03, -0.19, -0.05, -40, 10, 0), chest=(-84, 16, 8), head=(-4, 8, 0), root=-22.0,
           **_glaive_hands((0.05, -0.23, 0.26), (-0.74, 0.14, 0.66), (0.66, 0, 0.74)))
    SP = dict(hips=(0.0, -0.11, 0.0, 14, 6, -3), chest=(24, 12, -6), head=(34, 6, 0),
              lf=(0.07, 0.04, 0, 20, 22, 0), rf=(-0.20, -0.22, 0.13, -30, 40, 0))
    C = P(GUARD, root=0.0, **SP, **_glaive_hands((0.05, -0.17, 0.38), (0.0, -0.10, 0.995), (1, 0, 0)))
    S1 = P(C, root=190.0)
    S2 = P(C, root=360.0, hips=(0.0, -0.13, 0.0, 20, 8, -3), chest=(40, 14, -6), head=(20, 6, 0),
           **_glaive_hands((0.05, -0.18, 0.37), (0.12, -0.10, 0.99), (1, 0, 0)))
    LD = P(GUARD, root=360.0, hips=(0.03, -0.20, 0.04, 40, 10, 0), chest=(72, 16, -8), head=(14, 8, 0),
           lf=(0.14, 0.24, 0, 10, 0, 0), rf=(-0.17, -0.20, 0, -30, 20, 0),
           **_glaive_hands((0.05, -0.22, 0.33), (0.42, -0.05, 0.9), (0.9, 0, -0.42)))
    LD2 = P(LD, hips=(0.02, -0.15, 0.03, 30, 8, 0), chest=(52, 14, -6))
    END = P(GUARD, root=360.0)
    return [(0, GUARD, "lin"), (0.15, W, "out"), (0.33, W2, "io"), (0.40, C, "snap"), (0.50, S1, "lin"),
            (0.60, S2, "out"), (0.72, LD, "out3"), (0.84, LD2, "io"), (1.0, END, "io")]


# ───────────────────────────── other actions ─────────────────────────────

def dodge():
    # 14 ticks; the sim carries her 2.4 tiles. A low scissoring dash that lands in a braking skid.
    S0 = P(GUARD, hips=(0, -0.14, 0, -8, 22, 0), chest=(-10, 34, 0), head=(0, 14, 0))
    back_r = R((-0.09, 0.12, -0.42), w=(-0.2, 0.35, -0.92), pole=(-0.6, 0.6, -0.4))
    back_l = L((0.09, 0.12, -0.42), pole=(0.6, 0.6, -0.4), fist=0.2)
    D1 = pose(hips=(0, -0.31, 0.05, 0, 55, 0), chest=(-16, 70, 0), head=(0, 32, 0), rh=back_r, lh=back_l,
              lf=(0.08, 0.12, 0, 0, 30, 0), rf=(-0.08, -0.55, 0.10, 0, 60, 0))
    D2 = pose(hips=(0, -0.37, 0.0, 0, 62, 0), chest=(16, 76, 0), head=(0, 34, 0), rh=back_r, lh=back_l,
              lf=(0.08, -0.50, 0.14, 0, 60, 0), rf=(-0.08, 0.16, 0, 0, 20, 0))
    SK = pose(hips=(0, -0.27, -0.04, -25, 15, 0), chest=(-36, 28, 0), head=(0, 10, 0),
              rh=R((-0.21, -0.26, -0.05), w=(-0.4, 0.5, -0.76), pole=(-0.7, -0.4, -0.6)),
              lh=L((0.10, -0.37, 0.22), fist=0.1),
              lf=(0.14, 0.30, 0, 10, 0, 0), rf=(-0.16, -0.24, 0, -50, 25, 0))
    return [(0, S0, "lin"), (0.20, D1, "out3"), (0.52, D2, "io"), (0.80, SK, "out3"), (1.0, GUARD, "io")]


WEAPON_BACK = R((-0.14, -0.37, -0.08), w=(-0.25, -0.72, -0.64), pole=(-0.6, -0.3, -0.75))


def _ranged(fire, aim, kick, settle, lead=0.22):
    """Common shape: snap to the aim pose, hold it into the launch tick, recoil, re-level, return."""
    f = fire
    return [(0, GUARD, "lin"), (max(0.08, f - lead), aim, "out3"), (f, aim, "lin"), (min(0.95, f + 0.09), kick, "out5"),
            (min(0.97, f + 0.34), settle, "io"), (1.0, GUARD, "io")]


def ranged_generic(fire=0.33):
    aim = P(GUARD, hips=(0, -0.08, 0, -20, 4, 0), chest=(-34, 6, 0), head=(0, 4, 0),
            lh=L((-0.02, -0.02, 0.455), fist=1.0, pole=(0.6, -0.8, 0)), rh=WEAPON_BACK)
    kick = P(aim, hips=(0, -0.07, -0.05, -22, 0, 0), chest=(-38, -6, 0), head=(0, 0, 0),
             lh=L((0.0, 0.11, 0.36), fist=1.0, pole=(0.6, -0.8, 0)))
    settle = P(aim, lh=L((-0.01, -0.06, 0.43), fist=1.0, pole=(0.6, -0.8, 0)))
    return _ranged(fire, aim, kick, settle)


def ranged_missile(fire=4 / 12):
    # mixtape_rocket: braced low, launcher angled up a little; the launch shoves her back onto her heel.
    aim = P(GUARD, hips=(0, -0.16, -0.02, -24, 6, 0), chest=(-40, 2, 0), head=(0, 2, 0),
            lh=L((-0.02, 0.06, 0.45), fist=1.0, pole=(0.6, -0.8, 0)), rh=WEAPON_BACK,
            lf=(0.12, 0.22, 0, 8, 0, 0), rf=(-0.16, -0.20, 0, -50, 0, 0))
    kick = P(aim, hips=(0, -0.12, -0.12, -28, -6, 0), chest=(-48, -16, 0), head=(0, -2, 0),
             lh=L((0.03, 0.26, 0.26), fist=1.0, pole=(0.7, -0.6, 0)), lf=(0.12, 0.20, 0, 8, -22, 0))
    settle = P(aim, hips=(0, -0.14, -0.06, -24, 4, 0), lh=L((0.0, 0.0, 0.42), fist=1.0, pole=(0.6, -0.8, 0)))
    return _ranged(fire, aim, kick, settle)


def ranged_pierce(fire=4 / 8):
    # needle_rail: an archer's line. Side-on, arm dead straight, sighting down it; a small sharp kick.
    aim = P(GUARD, hips=(0, -0.06, 0, -50, 2, 0), chest=(-76, 2, 0), head=(-6, 2, -8),
            lh=L((-0.06, 0.0, 0.455), fist=1.0, pole=(0.9, -0.3, 0)),
            rh=R((-0.24, -0.02, -0.26), w=(-0.5, 0.3, -0.8), pole=(-0.5, -0.5, -0.7)),
            lf=(0.10, 0.24, 0, 20, 0, 0), rf=(-0.14, -0.20, 0, -70, 0, 0))
    kick = P(aim, hips=(0, -0.06, -0.025, -52, 0, 0), chest=(-79, -2, 0),
             lh=L((-0.05, 0.035, 0.42), fist=1.0, pole=(0.9, -0.3, 0)))
    return _ranged(fire, aim, kick, aim, lead=0.34)


def ranged_phase(fire=4 / 14):
    # bleed_emitter: an open-palm shove that she leans through, as if pushing the shot into the wall.
    aim = P(GUARD, hips=(0, -0.10, 0.02, -10, 6, 0), chest=(-18, 10, 0), head=(0, 6, 0),
            lh=L((-0.04, -0.06, 0.38), w=(-1, 0, 0), e=(0, 1, 0.15), fist=0.0, pole=(0.7, -0.7, 0)), rh=WEAPON_BACK)
    push = P(aim, hips=(0, -0.13, 0.12, 5, 10, 0), chest=(14, 16, 0), head=(0, 8, 0),
             lh=L((-0.06, -0.04, 0.455), w=(-1, 0, 0), e=(0, 1, 0.0), fist=0.0, pole=(0.7, -0.7, 0)),
             lf=(0.12, 0.30, 0, 5, 0, 0), rf=(-0.15, -0.15, 0, -40, 25, 0))
    return _ranged(fire, aim, push, push, lead=0.18)


def ranged_arc(fire=4 / 16):
    # bass_drop: a mortar lob. Sinks, arm up at fifty degrees, then the whole body pops with the shot.
    aim = P(GUARD, hips=(0, -0.20, -0.03, -18, -4, 0), chest=(-28, -14, 0), head=(0, -12, 0),
            lh=L((0.0, 0.33, 0.31), fist=1.0, pole=(0.7, -0.7, 0)), rh=WEAPON_BACK)
    kick = P(aim, hips=(0, -0.03, -0.02, -18, -6, 0), chest=(-30, -20, 0), head=(0, -18, 0),
             lh=L((0.0, 0.40, 0.20), fist=1.0, pole=(0.7, -0.7, 0)),
             lf=(0.12, 0.17, 0, 8, 20, 0), rf=(-0.15, -0.15, 0, -40, 20, 0))
    settle = P(aim, hips=(0, -0.12, -0.02, -18, 0, 0), chest=(-28, -4, 0), head=(0, -14, 0),
               lh=L((0.0, 0.20, 0.40), fist=1.0, pole=(0.7, -0.7, 0)))
    return _ranged(fire, aim, kick, settle, lead=0.17)


def ranged_burst(fire=4 / 6):
    # static_spray: hip-fire. Wide stance, device at the waist, the torso rakes the fan across.
    def hip(yaw, z=0.34, y=-0.27):
        return P(GUARD, hips=(0, -0.15, 0, yaw * 0.4, 6, 0), chest=(yaw, 12, 0), head=(0, 6, 0),
                 lh=L((0.04, y, z), fist=1.0, pole=(0.9, -0.4, -0.2)), rh=WEAPON_BACK,
                 lf=(0.17, 0.16, 0, 16, 0, 0), rf=(-0.19, -0.12, 0, -40, 0, 0))
    return [(0, GUARD, "lin"), (0.30, hip(-34), "out3"), (0.60, hip(-30), "lin"), (0.67, hip(-10, 0.31, -0.24), "snap"),
            (0.80, hip(26, 0.30, -0.23), "out3"), (0.90, hip(18), "io"), (1.0, GUARD, "io")]


def interact():
    # 10 ticks: a step-in palm press with the left hand.
    REACH = P(GUARD, hips=(0, -0.07, 0.06, 6, 8, 0), chest=(20, 16, 0), head=(0, 10, 0),
              lh=L((-0.03, -0.13, 0.42), w=(-1, 0, 0), e=(0, 0.6, 0.8), fist=0.0, pole=(0.7, -0.7, 0)),
              rh=R((-0.10, -0.38, -0.04), w=(-0.2, -0.3, -0.93), pole=(-0.6, -0.3, -0.75)),
              lf=(0.12, 0.24, 0, 6, 0, 0))
    PRESS = P(REACH, hips=(0, -0.09, 0.08, 8, 10, 0), chest=(24, 19, 0),
              lh=L((-0.03, -0.14, 0.44), w=(-1, 0, 0), e=(0, 0.7, 0.7), fist=0.0, pole=(0.7, -0.7, 0)))
    return [(0, GUARD, "lin"), (0.36, REACH, "out3"), (0.50, PRESS, "out"), (0.66, REACH, "io"), (1.0, GUARD, "io")]


def death():
    JOLT = pose(hips=(0, -0.03, -0.10, 0, -12, 0), chest=(10, -30, 0), head=(0, -30, 0),
                rh=R((-0.34, 0.14, 0.08), w=(-0.6, 0.7, 0.3), fist=0.5, pole=(-0.3, -0.9, -0.2)),
                lh=L((0.34, 0.16, 0.06), fist=0.0, pole=(0.3, -0.9, -0.2)),
                lf=(0.12, 0.10, 0.06, 8, -10, 0), rf=(-0.15, -0.22, 0, -40, 0, 0))
    STAG = pose(hips=(-0.03, -0.10, -0.22, 8, 5, 6), chest=(15, 10, 10), head=(10, 22, 8),
                rh=R((-0.20, -0.36, 0.05), w=(-0.2, -0.6, 0.77), fist=0.4),
                lh=L((0.22, -0.34, 0.02), fist=0.0),
                lf=(0.10, -0.02, 0, 10, 0, 0), rf=(-0.16, -0.36, 0, -30, 0, 0))
    BUCK = pose(hips=(0, -0.46, -0.20, 5, 8, 4), chest=(10, 32, 6), head=(5, 40, 5),
                rh=R((-0.16, -0.40, 0.08), w=(-0.2, -0.5, 0.84), fist=0.3),
                lh=L((0.18, -0.40, 0.06), fist=0.0),
                lf=(0.13, -0.06, 0, 10, 30, 0), rf=(-0.16, -0.40, 0, -25, 50, 0))
    KNEES = pose(hips=(0, -0.57, -0.14, 0, 22, 0), chest=(5, 62, 4), head=(0, 66, 0),
                 rh=R((-0.08, -0.34, 0.26), w=(0.3, -0.2, 0.93), fist=0.2),
                 lh=L((0.08, -0.34, 0.26), fist=0.0),
                 lf=(0.14, -0.28, 0, 10, 72, 0), rf=(-0.15, -0.44, 0, -15, 74, 0))
    DOWN = pose(hips=(0, -0.60, -0.10, 0, 30, 0), chest=(4, 84, 4), head=(-20, 82, 0),
                rh=R((-0.12, -0.25, 0.36), w=(0.5, 0.0, 0.86), fist=0.1),
                lh=L((0.12, -0.24, 0.36), fist=0.0),
                lf=(0.14, -0.30, 0, 10, 78, 0), rf=(-0.15, -0.46, 0, -15, 80, 0))
    return [(0, GUARD, "lin"), (0.12, JOLT, "out5"), (0.36, STAG, "io"), (0.62, BUCK, "in"), (0.82, KNEES, "lin"),
            (1.0, DOWN, "out3")]


def win():
    GATHER = P(GUARD, hips=(0, -0.22, 0, -30, 12, 0), chest=(-50, 24, 0), head=(0, 14, 0),
               rh=R((0.10, -0.34, 0.20), w=(0.8, -0.3, 0.5)), lh=L((0.10, -0.30, 0.10), fist=1.0))
    UP = pose(hips=(0.02, -0.03, 0, 10, -2, -6), chest=(16, -10, -4), head=(18, -12, 0),
              rh=R((-0.10, 0.44, 0.06), w=(-0.12, 0.99, 0.08), e=(0, 0, 1), pole=(-0.9, -0.2, -0.3)),
              lh=L((0.19, -0.27, 0.0), fist=1.0, pole=(0.9, 0.0, -0.45)),
              lf=(0.15, 0.07, 0, 28, 26, 0), rf=(-0.09, -0.03, 0, -14, 0, 0))
    HOLD = P(UP, hips=(0.02, -0.05, 0, 10, -2, -7), chest=(16, -8, -4))
    return [(0, GUARD, "lin"), (0.22, GATHER, "out3"), (0.44, UP, "back"), (0.62, HOLD, "io"), (1.0, HOLD, "lin")]


def resync():
    # Three stepped "glitch" frames, then a hard snap wide and a settle into guard.
    GA = pose(hips=(0.03, -0.14, 0, 15, 10, -6), chest=(-20, 26, 10), head=(22, 26, -10),
              rh=R((-0.10, -0.30, 0.20), w=(0.6, 0.2, 0.77)), lh=L((0.20, -0.10, -0.20), fist=0.1),
              lf=(0.16, 0.10, 0, 30, 0, 0), rf=(-0.10, -0.06, 0, -5, 0, 0))
    GB = pose(hips=(-0.03, -0.10, 0, -18, 6, 6), chest=(24, 18, -10), head=(-20, 14, 10),
              rh=R((-0.26, -0.10, -0.12), w=(-0.6, 0.6, 0.5)), lh=L((0.06, -0.34, 0.22), fist=0.1),
              lf=(0.10, 0.02, 0, 0, 0, 0), rf=(-0.18, -0.12, 0, -40, 0, 0))
    X = pose(hips=(0, 0.01, 0, -10, -4, 0), chest=(-12, -10, 0), head=(0, -8, 0),
             rh=R((-0.36, -0.20, -0.02), w=(-0.7, -0.5, 0.5), pole=(0, -0.3, -1)),
             lh=L((0.36, -0.20, -0.02), fist=0.0, pole=(0, -0.3, -1)),
             lf=(0.17, 0.10, 0, 20, 14, 0), rf=(-0.17, -0.10, 0, -30, 14, 0))
    return [(0, GA, "lin"), (0.12, GB, "hold"), (0.24, GA, "hold"), (0.30, GB, "hold"), (0.44, X, "snap5"),
            (0.62, P(GUARD, hips=(0, -0.11, 0, -22, 6, 0)), "out3"), (1.0, GUARD, "io")]


# ───────────────────────────── registry ─────────────────────────────

# Melee style of each catalogue item (gear.json's melee.style is coarser: three items say "blade").
STYLE_OF_ITEM = {"splice_blade": "blade", "stylus_shiv": "shiv", "amp_sledge": "blunt", "reel_lash": "whip",
                 "speaker_knuckles": "gauntlet", "vinyl_glaive": "polearm"}
ITEM_OF_STYLE = {v: k for k, v in STYLE_OF_ITEM.items()}
TWO_HANDED = {"blunt": SLEDGE_ON, "polearm": GLAIVE_ON}
RANGED_FIRE = {"missile": 4 / 12, "pierce": 4 / 8, "phase": 4 / 14, "arc": 4 / 16, "burst": 4 / 6}


def all_clips():
    c = []
    c.append(Clip("idle", 2.0, True, fn=idle_fn))
    c.append(Clip("run", 0.6, True, fn=run_fn))
    c.append(Clip("stopped", 1.0, True, fn=lambda t: STOPPED))
    c.append(Clip("countin", 1.0, True, fn=countin_fn))
    melee = {"blade": (blade_light, blade_heavy), "shiv": (shiv_light, shiv_heavy), "blunt": (blunt_light, blunt_heavy),
             "whip": (whip_light, whip_heavy), "gauntlet": (gauntlet_light, gauntlet_heavy),
             "polearm": (polearm_light, polearm_heavy)}
    c.append(Clip("light", keys=blade_light(), meta={"melee": "light", "style": "blade"}))
    c.append(Clip("heavy", keys=blade_heavy(), meta={"melee": "heavy", "style": "blade"}))
    for style, (lf, hf) in melee.items():
        c.append(Clip("light_" + style, keys=lf(), meta={"melee": "light", "style": style}))
        c.append(Clip("heavy_" + style, keys=hf(), meta={"melee": "heavy", "style": style}))
    c.append(Clip("dodge", keys=dodge()))
    c.append(Clip("ranged", keys=ranged_generic(), meta={"fire": 0.33}))
    for arch, fn in (("missile", ranged_missile), ("pierce", ranged_pierce), ("phase", ranged_phase),
                     ("arc", ranged_arc), ("burst", ranged_burst)):
        c.append(Clip("ranged_" + arch, keys=fn(), meta={"fire": RANGED_FIRE[arch]}))
    c.append(Clip("interact", keys=interact()))
    c.append(Clip("death", keys=death()))
    c.append(Clip("win", keys=win()))
    c.append(Clip("resync", keys=resync()))
    return c
