/**
 * Every gameplay constant in one place.
 *
 * Units are explicit in each name's doc comment. "Local" quantities belong to a self's own tape clock
 * (they feel identical at every tape speed, TIME-02); "master" quantities belong to the shared world.
 * Values are first-pass tuning (TIME-05, OPEN-09, OPEN-12, OPEN-13 leave them to playtesting); the
 * combat targets from docs/ARCHITECTURE.md are asserted by tests/core/foundation/tuning.test.ts so a
 * retune that breaks them fails loudly.
 *
 * Pure data plus the momentum model's arithmetic. No imports besides core types.
 */
import type { EnemyType, MeleeSwingDef, StatMods, TapeSpeed } from './types';

// ───────────────────────────── base actor stats ─────────────────────────────

/**
 * Base (unmodified) stats of a self. Gear multiplies these through `ResolvedLoadout.mods`
 * (see `StatMods`: multipliers unless the key ends in `Add`). The content module should resolve
 * loadouts against these, never against literals of its own.
 */
export interface BaseStats {
  /** Collision radius of a self, tiles. Under 0.5 so a 1-tile corridor is comfortable. */
  readonly actorRadius: number;
  /** Top running speed, tiles per local second. */
  readonly runSpeed: number;
  /** Acceleration toward the input direction, tiles per local second². */
  readonly accel: number;
  /** Braking with no input (and when reversing), tiles per local second². */
  readonly decel: number;
  /**
   * Exponential decay rate (per local second) of velocity perpendicular to the input direction.
   * Divided by `momentumRetention`, so retention gear makes turns carry more sideways drift.
   */
  readonly turnDamping: number;
  /** Exponential decay rate (per local second) of speed above the current cap (after a dodge, a swing slowdown). */
  readonly overspeedDecay: number;
  /** How quickly the body turns to face its movement direction, radians per local second. */
  readonly facingTurnRate: number;
  /** Speeds below this (tiles per local second) animate as idle rather than run. */
  readonly runAnimThreshold: number;

  /** Dodge length, local ticks. Constant across gear so the dash reads the same; distance scales speed. */
  readonly dodgeTicks: number;
  /** Dodge travel distance, tiles (scaled by mods.dodgeDistance). */
  readonly dodgeDistance: number;
  /** First i-frame tick, as an offset from the dodge's start tick. */
  readonly dodgeIframeStart: number;
  /** I-frame window length, local ticks (scaled by mods.dodgeIframes). */
  readonly dodgeIframes: number;
  /** Ticks after the dodge ends before another may start (scaled by mods.dodgeCooldown). */
  readonly dodgeCooldown: number;
  /** Fraction of run speed carried out of a dodge along the dash direction. */
  readonly dodgeExitSpeed: number;

  /** Movement multiplier while committed to a ranged shot. */
  readonly rangedMoveMul: number;
  /** Ticks from the ranged event to the projectile launch (clamped to the weapon's commit). */
  readonly rangedLaunchDelay: number;

  /** Interaction commitment, local ticks. */
  readonly interactTicks: number;
  /** Movement multiplier during an interaction. */
  readonly interactMoveMul: number;
  /** Interaction reach from the actor centre, tiles (mods.interactRadiusAdd is added). */
  readonly interactRadius: number;

  /** A press that cannot start yet is remembered this many local ticks (so presses in recovery are not dropped). */
  readonly inputBufferTicks: number;

  /** Recovery spark speed, tiles per MASTER second (DESYNC-02: faster than running, not instant). */
  readonly sparkSpeed: number;
  /** Spark radius for path smoothing / wall clearance, tiles. */
  readonly sparkRadius: number;
  /** Spark resyncs when within this distance of the projection with a clear line (DESYNC-05), tiles. */
  readonly resyncTolerance: number;
  /** Minimum time between spark re-plans, master substeps (re-planning also happens on any grid change). */
  readonly sparkReplanSubs: number;

  /** Momentum bonus fraction for running fully into a strike (MOM-03). */
  readonly approachBonus: number;
  /** Maximum knockback distance, tiles (scaled by mods.knockbackCap). */
  readonly knockbackCap: number;
}

export const BASE: BaseStats = {
  actorRadius: 0.3,
  runSpeed: 4.5,
  accel: 42,
  decel: 34,
  turnDamping: 16,
  overspeedDecay: 9,
  facingTurnRate: 28,
  runAnimThreshold: 0.4,

  dodgeTicks: 14,
  dodgeDistance: 2.4,
  dodgeIframeStart: 1,
  dodgeIframes: 10,
  dodgeCooldown: 22,
  dodgeExitSpeed: 0.85,

  rangedMoveMul: 0.5,
  rangedLaunchDelay: 4,

  interactTicks: 10,
  interactMoveMul: 0.4,
  interactRadius: 1.2,

  inputBufferTicks: 8,

  sparkSpeed: 7.5,
  sparkRadius: 0.2,
  resyncTolerance: 0.35,
  sparkReplanSubs: 24,

  approachBonus: 0.5,
  knockbackCap: 3,
};

/** The identity modifier set: what a loadout of items with no `mods` resolves to. */
export const NEUTRAL_MODS: Readonly<Required<StatMods>> = {
  moveSpeed: 1,
  accel: 1,
  momentumRetention: 1,
  dodgeDistance: 1,
  dodgeIframes: 1,
  dodgeCooldown: 1,
  meleeImpact: 1,
  damage: 1,
  knockback: 1,
  knockbackCap: 1,
  stagger: 1,
  approachBonus: 1,
  sparkSpeed: 1,
  interactRadiusAdd: 0,
  projectileSpeed: 1,
  rangedCooldown: 1,
};

/** Fresh mutable copy of NEUTRAL_MODS (resolvers multiply into it). */
export function neutralMods(): Required<StatMods> {
  return { ...NEUTRAL_MODS };
}

// ───────────────────────────── collision ─────────────────────────────

/**
 * Collision resolution leaves circles this far outside walls. Tapes store positions as float32
 * (~4e-6 tiles of precision on a 40-tile map); the skin keeps a recorded wall-hugging pose from
 * rounding into the wall and spuriously desyncing on playback.
 */
export const COLLISION_SKIN = 1e-3;

/**
 * Penetration the kernel should forgive before calling a recorded position "inside solid geometry"
 * (DESYNC trigger). Smaller than any meaningful obstruction, larger than float32 noise.
 */
export const DESYNC_PENETRATION_TOLERANCE = 0.02;

// ───────────────────────────── momentum model (MOM-01..06) ─────────────────────────────

/**
 * Momentum per point of damage. With the baseline weapon (light impact 1.2, damageEff 1) a 1×
 * standing light deals floor(1.2) = 1 (kills a 1-hit enemy) and a 0.5× one floor(0.6) = 0.
 */
export const DAMAGE_UNIT = 1;

/** Approach factor bounds: running away still delivers half the swing, running in at most doubles the bonus term. */
export const APPROACH_MIN = -0.5;
export const APPROACH_MAX = 1;

/**
 * Momentum a tutorial breakable needs. A 2× running heavy (2 × 2 × 1.5 = 6) breaks it; a 1× running
 * heavy (3) and a 2× standing heavy (4) do not (architecture tuning target; Scenario K).
 */
export const TUTORIAL_WALL_THRESHOLD = 5;

/** Default momentum a core needs when CoreDef.threshold is omitted (a 1× standing light suffices). */
export const DEFAULT_CORE_THRESHOLD = 1;

/**
 * Normalised approach: how much of the self's local velocity points along the swing (MOM-03).
 * Normalised by BASE.runSpeed (not the loadout's run speed) so faster shoes do add momentum until the cap.
 */
export function strikeApproach(localVx: number, localVy: number, swingDir: number): number {
  const along = localVx * Math.cos(swingDir) + localVy * Math.sin(swingDir);
  const a = along / BASE.runSpeed;
  return a < APPROACH_MIN ? APPROACH_MIN : a > APPROACH_MAX ? APPROACH_MAX : a;
}

/**
 * Effective momentum of a strike. `tapeSpeed` appears exactly once: it is the master-time conversion
 * of both the swing and the body velocity (MOM-01, "do not count tape speed twice").
 * `approachBonusMod` is mods.approachBonus (multiplies BASE.approachBonus).
 */
export function strikeMomentum(
  impact: number,
  meleeImpactMod: number,
  tapeSpeed: TapeSpeed | number,
  approach: number,
  approachBonusMod = 1,
): number {
  return impact * meleeImpactMod * tapeSpeed * (1 + BASE.approachBonus * approachBonusMod * approach);
}

/** Momentum of a recorded melee swing, from the event's recorded velocity and direction. */
export function swingMomentum(
  swing: Pick<MeleeSwingDef, 'impact'>,
  mods: Pick<Required<StatMods>, 'meleeImpact' | 'approachBonus'>,
  tapeSpeed: TapeSpeed | number,
  localVx: number,
  localVy: number,
  dir: number,
): number {
  return strikeMomentum(swing.impact, mods.meleeImpact, tapeSpeed, strikeApproach(localVx, localVy, dir), mods.approachBonus);
}

/** Damage points from momentum (never negative). */
export function strikeDamage(momentum: number, damageEff: number, damageMod: number): number {
  const d = Math.floor((momentum * damageEff * damageMod) / DAMAGE_UNIT + 1e-9);
  return d > 0 ? d : 0;
}

/** Knockback distance, tiles, capped. Immovable targets (mass Infinity) get 0. */
export function strikeKnockback(
  momentum: number,
  knockbackEff: number,
  knockbackMod: number,
  knockbackCapMod: number,
  enemyMass: number,
): number {
  if (!(enemyMass > 0) || enemyMass === Infinity) return 0;
  const k = (momentum * knockbackEff * knockbackMod) / enemyMass;
  const cap = BASE.knockbackCap * knockbackCapMod;
  return k < 0 ? 0 : k > cap ? cap : k;
}

/** Stagger duration in master seconds. Unstaggerable targets (poise Infinity) get 0. */
export function strikeStagger(momentum: number, staggerEff: number, staggerMod: number, enemyPoise: number): number {
  if (!(enemyPoise > 0) || enemyPoise === Infinity) return 0;
  const s = (momentum * staggerEff * staggerMod) / enemyPoise;
  return s > 0 ? s : 0;
}

// ───────────────────────────── knockback motion ─────────────────────────────

/** Knockback is applied as a slide over this many master seconds (MOM-05: enemies really move). */
export const KNOCKBACK_SECONDS = 0.18;
/** Hitting a wall during knockback converts remaining distance into this much extra stagger (master s per tile). */
export const WALL_SLAM_STAGGER_PER_TILE = 0.25;

// ───────────────────────────── enemies ─────────────────────────────

export interface EnemyStats {
  /** Damage points to kill (EnemyDef.hp overrides). */
  readonly hp: number;
  /** Knockback divisor. Infinity = immovable. */
  readonly mass: number;
  /** Stagger divisor. Infinity = never staggers. */
  readonly poise: number;
  /** Body radius, tiles. */
  readonly radius: number;
  /** Walk speed, tiles per master second (0 = stationary). */
  readonly speed: number;
  /** Default attack grid in master beats. */
  readonly every: number;
  readonly offset: number;
  /** Reach of a melee strike / max range of a shot, tiles. */
  readonly reach: number;
  /** Telegraph length before an attack lands, master beats (AI-04 legibility). */
  readonly telegraphBeats: number;
  /** Projectile speed for ranged enemies, tiles per master second (0 for melee enemies). */
  readonly shotSpeed: number;
}

/**
 * Enemy roster numbers (AI-01..07, HEALTH-02). One-hit enemies have hp 1; the brute takes 3
 * standing 1× lights but one 1× running heavy (floor(2 × 1.5) = 3), which is the momentum lesson.
 */
export const ENEMY_STATS: Readonly<Record<EnemyType, EnemyStats>> = {
  grunt: { hp: 1, mass: 1, poise: 2, radius: 0.32, speed: 2.2, every: 2, offset: 0, reach: 0.9, telegraphBeats: 0.5, shotSpeed: 0 },
  stalker: { hp: 1, mass: 0.8, poise: 1.5, radius: 0.3, speed: 3.6, every: 2, offset: 1, reach: 0.9, telegraphBeats: 0.5, shotSpeed: 0 },
  turret: { hp: 1, mass: Infinity, poise: Infinity, radius: 0.4, speed: 0, every: 2, offset: 0, reach: 12, telegraphBeats: 1, shotSpeed: 6 },
  shielder: { hp: 2, mass: 1.2, poise: 2.5, radius: 0.35, speed: 1.8, every: 4, offset: 0, reach: 0.9, telegraphBeats: 0.75, shotSpeed: 0 },
  brute: { hp: 3, mass: 3, poise: 6, radius: 0.5, speed: 1.4, every: 4, offset: 2, reach: 1.4, telegraphBeats: 1.5, shotSpeed: 0 },
  drone: { hp: 2, mass: 0.7, poise: 1.5, radius: 0.3, speed: 2.5, every: 2, offset: 1, reach: 8, telegraphBeats: 0.5, shotSpeed: 5 },
  boss: { hp: 40, mass: 8, poise: 20, radius: 0.9, speed: 1.8, every: 4, offset: 0, reach: 2.2, telegraphBeats: 2, shotSpeed: 5 },
};

/** Shielder: a second hit must land within this many master beats of the first (shield recharges instantly otherwise). */
export const SHIELDER_WINDOW_BEATS = 1;
/** Drone: preferred distance it keeps from its target, tiles. */
export const DRONE_KEEP_DISTANCE = 5;
/** Enemy bolt collision radius, tiles. */
export const ENEMY_SHOT_RADIUS = 0.15;
/** Self projectile collision radius, tiles. */
export const SELF_SHOT_RADIUS = 0.15;
/** Arc (lobbed) shots: peak height in tiles for presentation, and landing blast if the weapon's is 0. */
export const ARC_PEAK_HEIGHT = 1.5;
export const ARC_MIN_BLAST = 0.6;
