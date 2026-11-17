/**
 * Procedural pose functions for Moxie's rig. Pure: a pose is a flat record of joint values written
 * into a caller-owned object, so the hot path allocates nothing and the functions are unit-tested.
 *
 * Rig conventions (model space, Moxie faces +Z, +Y up, her left side is +X):
 *   *Raise  — forward/up swing of a limb from hanging straight down (radians, + = forward).
 *   *Out    — sideways swing away from the body (radians, + = outward on that side).
 *   *Twist  — rotation about the limb's own long axis.
 *   elbow / knee — flexion (+ = elbow folds forward, knee folds backward).
 *   hips/spine/head Pitch — + leans forward; Yaw — + turns toward her left; Roll — + tilts to her right.
 *   pig*Swing — pigtail swings backward (trailing); pig*Out — flares sideways; pig*Tip — bend of the tip.
 */
import type { AnimState, MeleeWeaponDef, RangedWeaponDef } from '../../core/types';
import { bump, clamp, clamp01, easeInCubic, easeInOutSine, easeOutCubic, lerp, smoothstep } from './math';

export const POSE_KEYS = [
  'rootY',
  'rootFwd',
  'stretch',
  'hipsPitch',
  'hipsYaw',
  'hipsRoll',
  'spinePitch',
  'spineYaw',
  'spineRoll',
  'headPitch',
  'headYaw',
  'headRoll',
  'phonesBob',
  'armLRaise',
  'armLOut',
  'armLTwist',
  'elbowL',
  'armRRaise',
  'armROut',
  'armRTwist',
  'elbowR',
  'legLRaise',
  'legLOut',
  'kneeL',
  'footL',
  'legRRaise',
  'legROut',
  'kneeR',
  'footR',
  'pigLSwing',
  'pigLOut',
  'pigLTip',
  'pigRSwing',
  'pigROut',
  'pigRTip',
  'jacketFlare',
  /** 0..1: how far along its arc the weapon trail has swept (drives the swing trail). */
  'swing',
  /** 0..1 wrist-device charge/flash for the ranged pose. */
  'wrist',
] as const;

export type PoseKey = (typeof POSE_KEYS)[number];
export type Pose = Record<PoseKey, number>;

/** Every pose function accepts these plus the pseudo-state 'death'. */
export type PoseState = AnimState | 'death';

export const POSE_STATES: readonly PoseState[] = [
  'idle',
  'run',
  'lightWindup',
  'lightActive',
  'lightRecover',
  'heavyWindup',
  'heavyActive',
  'heavyRecover',
  'dodge',
  'ranged',
  'interact',
  'stopped',
  'death',
];

export type MeleeStyle = MeleeWeaponDef['style'];

export interface PoseParams {
  /** Seconds of free-running presentation time (breathing, sway). */
  time: number;
  /** Run cycle phase in radians (advanced by distance travelled). */
  stride: number;
  /** 0..1 how fast the self is moving relative to a full run. */
  speed: number;
  /** 0..1 music beat pulse (headphone bob). */
  beat: number;
  /** Velocity in the self's own frame, normalised: + forward / + to her left. */
  leanF: number;
  leanS: number;
  style: MeleeStyle;
}

export function createPose(): Pose {
  const p = {} as Pose;
  for (const k of POSE_KEYS) p[k] = 0;
  return p;
}

export function createPoseParams(): PoseParams {
  return { time: 0, stride: 0, speed: 0, beat: 0, leanF: 0, leanS: 0, style: 'blade' };
}

export function copyPose(src: Pose, out: Pose): Pose {
  for (const k of POSE_KEYS) out[k] = src[k];
  return out;
}

export function blendPose(a: Pose, b: Pose, w: number, out: Pose): Pose {
  const t = clamp01(w);
  for (const k of POSE_KEYS) out[k] = a[k] + (b[k] - a[k]) * t;
  return out;
}

/** Nominal lengths (local ticks) for states whose length is not on the loadout. */
export const DODGE_TICKS = 18;
export const INTERACT_TICKS = 16;
/** Seconds the death transition takes before the ghost reading fully takes over. */
export const DEATH_SECONDS = 0.7;

/** Local ticks a timed state lasts, from the equipped weapons; 0 for cyclic / held states. */
export function animDurationTicks(
  anim: AnimState,
  melee: Pick<MeleeWeaponDef, 'light' | 'heavy'>,
  ranged: Pick<RangedWeaponDef, 'commit'>,
): number {
  switch (anim) {
    case 'lightWindup':
      return Math.max(1, melee.light.windup);
    case 'lightActive':
      return Math.max(1, melee.light.active);
    case 'lightRecover':
      return Math.max(1, melee.light.recover);
    case 'heavyWindup':
      return Math.max(1, melee.heavy.windup);
    case 'heavyActive':
      return Math.max(1, melee.heavy.active);
    case 'heavyRecover':
      return Math.max(1, melee.heavy.recover);
    case 'dodge':
      return DODGE_TICKS;
    case 'ranged':
      return Math.max(1, ranged.commit);
    case 'interact':
      return INTERACT_TICKS;
    default:
      return 0;
  }
}

/**
 * Progress 0..1 through a timed state. Measured on the tape's own local ticks, so speed changes how
 * long it occupies master time without changing its shape (TIME-03). On a reverse pass the state
 * is entered at its recorded end, so progress runs backwards and the motion reads as rewinding.
 */
export function animProgress(entryTick: number, tick: number, dir: 1 | -1 | 0, durationTicks: number): number {
  if (durationTicks <= 0) return 0;
  const elapsed = Math.abs(tick - entryTick) / durationTicks;
  const t = clamp01(elapsed);
  return dir === -1 ? 1 - t : t;
}

function base(p: PoseParams, out: Pose): void {
  for (const k of POSE_KEYS) out[k] = 0;
  // Confident wide stance with soft knees (R01: weight on one hip, feet apart).
  out.legLOut = 0.1;
  out.legROut = 0.1;
  out.kneeL = 0.08;
  out.kneeR = 0.08;
  out.armLOut = 0.18;
  out.armROut = 0.18;
  out.elbowL = 0.25;
  out.elbowR = 0.25;
  out.pigLOut = 0.35;
  out.pigROut = 0.35;
  out.pigLTip = 0.2;
  out.pigRTip = 0.2;
  out.phonesBob = p.beat * 0.025;
  out.headPitch = -p.beat * 0.06;
}

function idle(p: PoseParams, out: Pose, breathe: boolean): void {
  base(p, out);
  const tm = breathe ? p.time : 0;
  const br = Math.sin(tm * 2.1);
  const sway = Math.sin(tm * 0.9);
  out.rootY = br * 0.006;
  out.spinePitch = -0.04 + br * 0.025;
  out.hipsRoll = 0.06 + sway * 0.02;
  out.spineRoll = -0.07 - sway * 0.02;
  out.headRoll = 0.08 + sway * 0.03;
  out.headYaw = Math.sin(tm * 0.5) * 0.12;
  // Right hand on hip (R01 pose language): elbow out, forearm folded back to the waist.
  out.armROut = 0.55;
  out.armRRaise = -0.25;
  out.elbowR = 1.5;
  out.armRTwist = -0.6;
  out.armLRaise = 0.05 + br * 0.02;
  out.pigLSwing = Math.sin(tm * 1.3) * 0.08;
  out.pigRSwing = Math.sin(tm * 1.3 + 1.2) * 0.08;
  out.pigLTip += Math.sin(tm * 1.7) * 0.06;
  out.pigRTip += Math.sin(tm * 1.7 + 2) * 0.06;
  out.legLOut = 0.13;
  out.legROut = 0.08;
}

function run(p: PoseParams, out: Pose): void {
  base(p, out);
  const s = p.stride;
  const sp = clamp01(p.speed);
  const sin = Math.sin(s);
  const amp = 0.25 + 0.75 * sp;
  out.legLRaise = sin * 0.85 * amp;
  out.legRRaise = -sin * 0.85 * amp;
  out.kneeL = 0.15 + Math.max(0, -Math.cos(s)) * 1.1 * amp + Math.max(0, sin) * 0.3;
  out.kneeR = 0.15 + Math.max(0, Math.cos(s)) * 1.1 * amp + Math.max(0, -sin) * 0.3;
  out.footL = -sin * 0.25 * amp;
  out.footR = sin * 0.25 * amp;
  out.armLRaise = -sin * 0.75 * amp;
  out.armRRaise = sin * 0.75 * amp;
  out.elbowL = 1.1;
  out.elbowR = 1.1;
  out.armLOut = 0.15;
  out.armROut = 0.15;
  out.rootY = Math.abs(Math.cos(s)) * 0.035 * amp - 0.015 * sp;
  // Lean into velocity (and into acceleration via leanF/leanS beyond the steady-state value).
  out.hipsPitch = 0.12 * sp + clamp(p.leanF, -1, 1.5) * 0.1;
  out.spinePitch = 0.1 * sp;
  out.hipsRoll = clamp(p.leanS, -1, 1) * -0.12;
  out.spineYaw = sin * 0.18 * amp;
  out.hipsYaw = -sin * 0.12 * amp;
  out.headPitch += -0.12 * sp;
  // Pigtails stream behind and bounce twice per stride.
  const bounce = Math.cos(s * 2) * 0.12;
  out.pigLSwing = 0.75 * sp + bounce;
  out.pigRSwing = 0.75 * sp - bounce;
  out.pigLTip = 0.35 + 0.2 * sp + Math.sin(s * 2 + 0.6) * 0.12;
  out.pigRTip = 0.35 + 0.2 * sp + Math.sin(s * 2 + 2.1) * 0.12;
  out.pigLOut = 0.45;
  out.pigROut = 0.45;
  out.jacketFlare = 0.55 * sp + Math.abs(sin) * 0.1;
}

/** Arm pose for a weapon held at the ready, used by every melee phase as a start point. */
function guard(p: PoseParams, out: Pose): void {
  base(p, out);
  out.legLRaise = 0.25;
  out.legRRaise = -0.25;
  out.kneeL = 0.35;
  out.kneeR = 0.3;
  out.rootY = -0.02;
  out.hipsPitch = 0.08;
  out.armRRaise = 0.5;
  out.armROut = 0.35;
  out.elbowR = 0.9;
  out.armLRaise = 0.6;
  out.armLOut = 0.1;
  out.elbowL = 1.3;
  out.pigLSwing = 0.15;
  out.pigRSwing = 0.15;
}

function lightWindup(p: PoseParams, t: number, out: Pose): void {
  guard(p, out);
  const e = easeOutCubic(t);
  if (p.style === 'gauntlet') {
    // Chamber the fist at the hip.
    out.armRRaise = lerp(0.5, -0.4, e);
    out.elbowR = lerp(0.9, 1.9, e);
    out.spineYaw = lerp(0, 0.45, e);
    out.armLRaise = lerp(0.6, 1.2, e);
  } else if (p.style === 'whip') {
    // Hand cocked back over the shoulder.
    out.armRRaise = lerp(0.5, 2.3, e);
    out.armROut = lerp(0.35, 0.5, e);
    out.elbowR = lerp(0.9, 1.6, e);
    out.spinePitch = lerp(0, -0.15, e);
    out.spineYaw = lerp(0, 0.3, e);
  } else {
    // Blade/blunt: weapon drawn back across the off side for a forehand slash.
    out.armRRaise = lerp(0.5, 1.0, e);
    out.armROut = lerp(0.35, 1.25, e);
    out.armRTwist = lerp(0, -0.6, e);
    out.elbowR = lerp(0.9, 1.0, e);
    out.spineYaw = lerp(0, 0.55, e);
  }
  out.hipsYaw = out.spineYaw * 0.3;
}

function lightActive(p: PoseParams, t: number, out: Pose): void {
  guard(p, out);
  const e = easeOutCubic(t);
  out.swing = e;
  out.rootFwd = 0.06 * e;
  if (p.style === 'gauntlet') {
    out.armRRaise = lerp(-0.4, 1.55, e);
    out.armROut = lerp(0.35, -0.05, e);
    out.elbowR = lerp(1.9, 0.05, e);
    out.spineYaw = lerp(0.45, -0.5, e);
    out.armLRaise = 1.0;
    out.elbowL = 1.8;
  } else if (p.style === 'whip') {
    out.armRRaise = lerp(2.3, 0.9, e);
    out.elbowR = lerp(1.6, 0.05, e);
    out.spinePitch = lerp(-0.15, 0.2, e);
    out.spineYaw = lerp(0.3, -0.25, e);
  } else {
    out.armRRaise = 1.35;
    out.armROut = lerp(1.25, -0.55, e);
    out.armRTwist = lerp(-0.6, 0.4, e);
    out.elbowR = lerp(1.0, 0.15, e);
    out.spineYaw = lerp(0.55, -0.6, e);
  }
  out.hipsYaw = out.spineYaw * 0.35;
  out.pigLSwing = 0.15 + 0.35 * e;
  out.pigRSwing = 0.15 + 0.35 * e;
  out.pigLOut = 0.35 + 0.4 * e;
  out.jacketFlare = 0.3 * e;
}

function lightRecover(p: PoseParams, t: number, out: Pose): void {
  // Follow-through then settle back to guard.
  lightActive(p, 1, out);
  const end = createScratch();
  guard(p, end);
  blendInto(out, end, easeInOutSine(t));
  out.swing = 1;
}

function heavyWindup(p: PoseParams, t: number, out: Pose): void {
  guard(p, out);
  const e = easeOutCubic(t);
  // Deep coil: low squat, torso leaning back, weapon hauled overhead with both hands — a tall,
  // clearly different silhouette from the light swing's sideways draw.
  out.rootY = lerp(-0.02, -0.11, e);
  out.legLRaise = lerp(0.25, 0.75, e);
  out.legRRaise = lerp(-0.25, -0.35, e);
  out.kneeL = lerp(0.35, 1.25, e);
  out.kneeR = lerp(0.3, 0.9, e);
  out.hipsPitch = lerp(0.08, 0.25, e);
  out.spinePitch = lerp(0, -0.55, e);
  out.headPitch += lerp(0, 0.2, e);
  if (p.style === 'gauntlet') {
    out.armRRaise = lerp(0.5, -0.6, e);
    out.elbowR = lerp(0.9, 2.1, e);
    out.armLRaise = lerp(0.6, -0.5, e);
    out.elbowL = lerp(1.3, 2.0, e);
    out.spineYaw = lerp(0, 0.8, e);
  } else {
    out.armRRaise = lerp(0.5, 2.85, e);
    out.armROut = lerp(0.35, 0.15, e);
    out.elbowR = lerp(0.9, 0.85, e);
    out.armLRaise = lerp(0.6, 2.7, e);
    out.armLOut = lerp(0.1, -0.15, e);
    out.elbowL = lerp(1.3, 0.95, e);
    out.spineYaw = lerp(0, 0.15, e);
  }
  out.pigLSwing = lerp(0.15, -0.35, e);
  out.pigRSwing = lerp(0.15, -0.35, e);
  out.jacketFlare = 0.15 * e;
  out.wrist = 0;
}

function heavyActive(p: PoseParams, t: number, out: Pose): void {
  guard(p, out);
  const e = easeInCubic(Math.min(1, t * 1.6)) * 0.35 + easeOutCubic(t) * 0.65;
  out.swing = e;
  // Explosive lunge: front leg drives forward, rear leg extends, torso slams down.
  out.rootFwd = lerp(0, 0.22, e);
  out.rootY = lerp(-0.11, -0.13, e);
  out.legLRaise = lerp(0.75, 0.95, e);
  out.kneeL = lerp(1.25, 1.0, e);
  out.legRRaise = lerp(-0.35, -0.75, e);
  out.kneeR = lerp(0.9, 0.35, e);
  out.hipsPitch = lerp(0.25, 0.4, e);
  out.spinePitch = lerp(-0.55, 0.55, e);
  out.headPitch += lerp(0.2, -0.3, e);
  if (p.style === 'gauntlet') {
    out.armRRaise = lerp(-0.6, 1.4, e);
    out.elbowR = lerp(2.1, 0.0, e);
    out.armLRaise = lerp(-0.5, 1.3, e);
    out.elbowL = lerp(2.0, 0.1, e);
    out.armLOut = -0.2;
    out.armROut = -0.2;
    out.spineYaw = lerp(0.8, 0, e);
  } else {
    out.armRRaise = lerp(2.85, 0.55, e);
    out.armROut = lerp(0.15, -0.1, e);
    out.elbowR = lerp(0.85, 0.05, e);
    out.armLRaise = lerp(2.7, 0.65, e);
    out.armLOut = lerp(-0.15, -0.3, e);
    out.elbowL = lerp(0.95, 0.2, e);
    out.spineYaw = lerp(0.15, -0.05, e);
  }
  out.pigLSwing = lerp(-0.35, 0.9, e);
  out.pigRSwing = lerp(-0.35, 0.9, e);
  out.pigLOut = 0.6;
  out.pigROut = 0.6;
  out.jacketFlare = lerp(0.15, 0.8, e);
}

function heavyRecover(p: PoseParams, t: number, out: Pose): void {
  heavyActive(p, 1, out);
  const end = createScratch();
  guard(p, end);
  // Heavy recovery holds the slam longer before rising: a visible punish window.
  blendInto(out, end, smoothstep(0.35, 1, t));
  out.swing = 1;
}

function dodge(p: PoseParams, t: number, out: Pose): void {
  base(p, out);
  const b = bump(t);
  const e = easeOutCubic(t);
  // Low stretched dash: body pitched hard forward, limbs trailing, stretched along the motion.
  out.stretch = 0.28 * b;
  out.rootY = -0.08 * b;
  out.hipsPitch = 0.65 * b;
  out.spinePitch = 0.25 * b;
  out.headPitch += -0.45 * b;
  out.legLRaise = lerp(0.2, 0.7, e) * b;
  out.kneeL = 0.3 + 0.9 * b;
  out.legRRaise = -0.9 * b;
  out.kneeR = 0.2 + 0.4 * b;
  out.armLRaise = -1.1 * b;
  out.armRRaise = -1.0 * b;
  out.armLOut = 0.35;
  out.armROut = 0.35;
  out.elbowL = 0.3;
  out.elbowR = 0.3;
  out.pigLSwing = 1.2 * b;
  out.pigRSwing = 1.2 * b;
  out.pigLTip = 0.5;
  out.pigRTip = 0.5;
  out.jacketFlare = 1.0 * b;
}

function ranged(p: PoseParams, t: number, out: Pose): void {
  base(p, out);
  const aim = smoothstep(0, 0.2, t) * (1 - smoothstep(0.8, 1, t));
  const recoil = Math.exp(-((t - 0.3) * (t - 0.3)) / 0.006);
  // Side-on shooting stance, wrist device thrust at the target, off hand bracing the forearm.
  out.legLRaise = 0.3 * aim;
  out.legRRaise = -0.25 * aim;
  out.kneeL = 0.2 + 0.2 * aim;
  out.spineYaw = -0.4 * aim;
  out.hipsYaw = -0.2 * aim;
  out.headYaw = 0.4 * aim;
  out.armLRaise = 1.5 * aim;
  out.armLOut = lerp(0.18, -0.15, aim);
  out.armLTwist = 0.3 * aim;
  out.elbowL = lerp(0.25, 0.02, aim) + recoil * 0.4;
  out.armRRaise = 1.15 * aim;
  out.armROut = lerp(0.18, -0.6, aim);
  out.elbowR = lerp(0.25, 1.1, aim);
  out.spinePitch = -0.1 * recoil;
  out.rootFwd = -0.04 * recoil;
  out.wrist = Math.max(aim * 0.6, recoil);
}

function interact(p: PoseParams, t: number, out: Pose): void {
  idle(p, out, true);
  const b = bump(t);
  // Reach out with the left hand and press: lean in, head down to look at the mechanism.
  out.hipsPitch = 0.15 * b;
  out.spinePitch = 0.2 * b;
  out.headPitch += 0.3 * b;
  out.armLRaise = 1.25 * b + 0.05;
  out.armLOut = lerp(0.18, -0.1, b);
  out.elbowL = lerp(0.25, 0.15, b);
  out.legLRaise = 0.3 * b;
  out.kneeL = 0.08 + 0.25 * b;
  out.wrist = b * 0.5;
}

function death(p: PoseParams, t: number, out: Pose): void {
  base(p, out);
  const hit = easeOutCubic(Math.min(1, t * 2.5));
  const fall = smoothstep(0.3, 1, t);
  out.spinePitch = -0.55 * hit + 0.35 * fall;
  out.hipsPitch = -0.15 * hit + 0.3 * fall;
  out.headPitch = -0.5 * hit + 0.5 * fall;
  out.headRoll = 0.3 * hit;
  out.armLOut = 0.2 + 1.0 * hit - 0.5 * fall;
  out.armROut = 0.2 + 1.1 * hit - 0.5 * fall;
  out.armLRaise = 0.6 * hit - 0.4 * fall;
  out.armRRaise = 0.4 * hit - 0.3 * fall;
  out.elbowL = 0.4;
  out.elbowR = 0.6;
  out.rootFwd = -0.12 * hit;
  out.kneeL = 0.1 + 1.3 * fall;
  out.kneeR = 0.1 + 1.0 * fall;
  out.legLRaise = 0.7 * fall;
  out.legRRaise = 0.45 * fall;
  out.rootY = -0.2 * fall;
  out.hipsRoll = 0.25 * fall;
  out.pigLSwing = -0.6 * hit + 0.4 * fall;
  out.pigRSwing = -0.6 * hit + 0.4 * fall;
  out.pigLOut = 0.8 * hit;
  out.pigROut = 0.8 * hit;
  out.jacketFlare = 0.6 * hit;
  out.phonesBob = 0.04 * hit;
}

// Scratch pose for the recover blends. Module-level so the pure functions still never allocate
// per call; nothing re-enters while it is in use.
let scratch: Pose | null = null;
function createScratch(): Pose {
  if (!scratch) scratch = createPose();
  return scratch;
}
function blendInto(a: Pose, b: Pose, w: number): void {
  for (const k of POSE_KEYS) a[k] = a[k] + (b[k] - a[k]) * w;
}

/**
 * Write the pose for `state` at progress `t` (0..1, ignored by cyclic states) into `out`.
 * Always returns finite values for any finite input.
 */
export function computePose(state: PoseState, t: number, p: PoseParams, out: Pose): Pose {
  const u = clamp01(Number.isFinite(t) ? t : 0);
  switch (state) {
    case 'idle':
      idle(p, out, true);
      break;
    case 'run':
      run(p, out);
      break;
    case 'lightWindup':
      lightWindup(p, u, out);
      break;
    case 'lightActive':
      lightActive(p, u, out);
      break;
    case 'lightRecover':
      lightRecover(p, u, out);
      break;
    case 'heavyWindup':
      heavyWindup(p, u, out);
      break;
    case 'heavyActive':
      heavyActive(p, u, out);
      break;
    case 'heavyRecover':
      heavyRecover(p, u, out);
      break;
    case 'dodge':
      dodge(p, u, out);
      break;
    case 'ranged':
      ranged(p, u, out);
      break;
    case 'interact':
      interact(p, u, out);
      break;
    case 'stopped':
      idle(p, out, false);
      break;
    case 'death':
      death(p, u, out);
      break;
  }
  for (const k of POSE_KEYS) if (!Number.isFinite(out[k])) out[k] = 0;
  return out;
}

/** True for the six melee phases (the swing trail and weapon-forward handling key off this). */
export function isMeleeState(s: AnimState): boolean {
  return (
    s === 'lightWindup' ||
    s === 'lightActive' ||
    s === 'lightRecover' ||
    s === 'heavyWindup' ||
    s === 'heavyActive' ||
    s === 'heavyRecover'
  );
}

export function isHeavyState(s: AnimState): boolean {
  return s === 'heavyWindup' || s === 'heavyActive' || s === 'heavyRecover';
}
