/**
 * Selves: one per cassette in the run. Owns the per-run life and sync state (GHOST-01..06,
 * DESYNC-01..08), the playhead/pose read from the tape, the recovery spark, and the per-self action
 * state opened by crossed tape events (melee swings, dodge i-frames, scheduled effects).
 *
 * Nothing in here is ever written back to a tape: life and sync are recomputed every run (GHOST-06).
 *
 * The live self is read through exactly the same pose interpolation as a playback self; the only
 * differences are who produces the samples (the PlayerController, one local tick ahead of the
 * world) and the death state it falls into ('recGhost' rather than 'ghost').
 */
import type { Grid, MoveOpts } from './grid';
import type { Pathfinder } from './path';
import { samplePoseInto, type PoseSample } from './tape';
import { tapePhaseInto } from './time';
import { BASE, DESYNC_PENETRATION_TOLERANCE } from './tuning';
import {
  LOCAL_HZ,
  SUB_HZ,
  subsPerLocalTick,
  type LifeState,
  type ResolvedLoadout,
  type Tape,
  type TapeEvent,
  type TapeIndex,
  type TapePhase,
  type Vec2,
} from './types';

/** A half-open window of master substeps [start, end). */
export interface SubWindow {
  start: number;
  end: number;
}

/** One firing of a recorded melee event: a fresh swing at the recorded place and direction (PLAY-02). */
export interface ActiveSwing {
  kind: 'light' | 'heavy';
  /** Recorded swing direction (never re-aimed; PLAY-01). */
  dir: number;
  /** Master substep the event was crossed (windup starts). */
  crossSub: number;
  /** Hit volume live for substeps [start, end). */
  start: number;
  end: number;
  /** Momentum of this swing, computed once when it was crossed (MOM-01). */
  momentum: number;
  /** +1 forward pass, -1 a reverse pass re-firing the event (PLAY-06). */
  passDir: 1 | -1;
  /** Ids of enemies / objects this swing already struck: a swing hits each target at most once. */
  struck: Set<string>;
  /** True once the swing has been live while its self was effective ('swing' event emitted). */
  announced: boolean;
  connected: boolean;
}

/** An action effect that lands some substeps after its event was crossed (ranged launch, …). */
export interface ScheduledEffect {
  sub: number;
  event: TapeEvent;
  passDir: 1 | -1;
  traversal: number;
}

/** The recovery spark: the physically reachable position of a desynced self (DESYNC-02). */
export interface SparkState {
  x: number;
  y: number;
  /** Current route toward the projection (excluding the spark's own position). */
  path: Vec2[];
  pathIdx: number;
  /** Grid revision and substep the route was planned at (re-planned on any door change; DESYNC-04). */
  planRev: number;
  planSub: number;
  /** Substep the desync began (for notes). */
  since: number;
}

/** Effective collision radius used to decide that a recorded pose is obstructed (DESYNC trigger). */
export const OBSTRUCTION_RADIUS = BASE.actorRadius - DESYNC_PENETRATION_TOLERANCE;

const PHASE_DODGE_OPTS: MoveOpts = { ignoreLow: true };

export class SelfActor {
  readonly index: TapeIndex;
  readonly live: boolean;
  /** The tape being read. For the live self it is a growing view whose `ticks` is the full allowance. */
  readonly tape: Tape;
  /** Master substeps per local tick of this tape. */
  readonly m: number;

  life: LifeState = 'alive';
  synced = true;

  readonly phase: TapePhase = { tick: 0, dir: 1, traversal: 0, ended: false };
  readonly pose: PoseSample = { x: 0, y: 0, facing: 0, anim: 'idle' };
  /** Projection position at the previous instant (for the straight-step obstruction test). */
  prevX = 0;
  prevY = 0;
  /** True when the last advance crossed a repeat cut (the projection teleported). */
  cut = false;
  /** Master-space velocity of the projection, tiles per master second. */
  vx = 0;
  vy = 0;

  spark: SparkState | null = null;
  /**
   * 'manualDesync' (abilities.ts): the spark is held where the self left its body and neither
   * moves nor resyncs until the ability is pressed again.
   */
  sparkHeld = false;
  /** Last position at which this self was physically valid (spark origin on desync). */
  lastValidX = 0;
  lastValidY = 0;

  readonly iframes: SubWindow[] = [];
  readonly swings: ActiveSwing[] = [];
  readonly scheduled: ScheduledEffect[] = [];

  /** Distance travelled since the last footstep event. */
  strideAcc = 0;

  deathSub = -1;
  deathCause = '';

  constructor(index: TapeIndex, tape: Tape, live: boolean) {
    this.index = index;
    this.tape = tape;
    this.live = live;
    this.m = subsPerLocalTick(tape.speed);
    tapePhaseInto(tape, 0, this.phase);
    samplePoseInto(tape, 0, this.pose);
    this.prevX = this.pose.x;
    this.prevY = this.pose.y;
    this.lastValidX = this.pose.x;
    this.lastValidY = this.pose.y;
  }

  /**
   * Move the playhead to master instant `at` and re-sample the projection. `maxTick` bounds the
   * velocity estimate for a live tape whose later samples are not written yet.
   */
  advance(at: number, maxTick: number): void {
    const prevTraversal = this.phase.traversal;
    this.prevX = this.pose.x;
    this.prevY = this.pose.y;
    tapePhaseInto(this.tape, at, this.phase);
    samplePoseInto(this.tape, this.phase.tick, this.pose);
    this.cut = this.tape.endMode === 'repeat' && this.phase.traversal !== prevTraversal;
    segmentVelocity(this.tape, this.phase.tick, maxTick, this.phase.dir, this);
  }

  /** Can this self's attempts affect the world right now? (alive or recording ghost, and synced) */
  get canAct(): boolean {
    return this.synced && (this.life === 'alive' || this.life === 'recGhost');
  }

  /** Can this self be hurt / targeted right now? (alive and synced; DESYNC-07, GHOST-04/05) */
  get vulnerable(): boolean {
    return this.synced && this.life === 'alive';
  }

  inIframes(sub: number): boolean {
    for (const w of this.iframes) if (sub >= w.start && sub < w.end) return true;
    return false;
  }

  /** Drop action state that can no longer matter. */
  prune(sub: number): void {
    for (let i = this.iframes.length - 1; i >= 0; i--) if (this.iframes[i].end <= sub) this.iframes.splice(i, 1);
  }
}

/**
 * Master-space velocity of a tape's motion at fractional tick t: the slope of the segment that ends
 * at or after t, never reading past `maxTick` (the live tape's newest sample).
 */
function segmentVelocity(tape: Tape, t: number, maxTick: number, dir: 1 | -1 | 0, out: { vx: number; vy: number }): void {
  const last = Math.min(tape.ticks, maxTick);
  if (last <= 0 || dir === 0) {
    out.vx = 0;
    out.vy = 0;
    return;
  }
  let i = t > 0 ? Math.ceil(t) - 1 : 0;
  if (i > last - 1) i = last - 1;
  if (i < 0) i = 0;
  const p = tape.pos;
  const k = LOCAL_HZ * tape.speed * dir;
  const vx = (p[i * 2 + 2] - p[i * 2]) * k;
  const vy = (p[i * 2 + 3] - p[i * 2 + 1]) * k;
  out.vx = vx === 0 ? 0 : vx;
  out.vy = vy === 0 ? 0 : vy;
}

// ───────────────────────────── obstruction & desync (DESYNC-01..05) ─────────────────────────────

/**
 * Is the recorded step prev → current impossible in the current world? True when the recorded
 * position overlaps solid geometry (walls, void, low barriers, closed doors, unbroken breakables)
 * by more than DESYNC_PENETRATION_TOLERANCE, or the straight step to it is blocked. A repeat cut is
 * a teleport, not a step, so only its landing point is tested.
 */
export function isObstructed(grid: Grid, self: SelfActor, loadout: ResolvedLoadout): boolean {
  const opts = self.pose.anim === 'dodge' && loadout.abilities.includes('phaseDodge') ? PHASE_DODGE_OPTS : undefined;
  const { x, y } = self.pose;
  if (grid.isSolidAt(x, y, OBSTRUCTION_RADIUS, opts)) return true;
  if (!self.cut && (self.prevX !== x || self.prevY !== y)) {
    if (grid.sweepCircleBlocked(self.prevX, self.prevY, x, y, OBSTRUCTION_RADIUS, opts)) return true;
  }
  return false;
}

/** Start a desync: the projection keeps following the tape; a spark appears at the last valid position. */
export function beginDesync(grid: Grid, self: SelfActor, sub: number): void {
  self.synced = false;
  let sx = self.lastValidX;
  let sy = self.lastValidY;
  // A door can close onto the last valid position itself; the spark then starts just outside it.
  if (grid.isSolidAt(sx, sy, BASE.sparkRadius)) {
    const res = grid.moveCircle(sx, sy, 0, 0, BASE.sparkRadius);
    sx = res.x;
    sy = res.y;
  }
  // Open swings are kept: they are gated on every live substep, so a swing whose hit frame comes
  // after a resync still lands (and one that comes while desynced does nothing).
  self.spark = { x: sx, y: sy, path: [], pathIdx: 0, planRev: -1, planSub: -Infinity, since: sub };
}

/** Can the spark resync with the projection right now? (DESYNC-05: within tolerance, clear line, valid pose) */
function canResync(grid: Grid, self: SelfActor, spark: SparkState): boolean {
  const dx = self.pose.x - spark.x;
  const dy = self.pose.y - spark.y;
  if (dx * dx + dy * dy > BASE.resyncTolerance * BASE.resyncTolerance) return false;
  if (grid.isSolidAt(self.pose.x, self.pose.y, OBSTRUCTION_RADIUS)) return false;
  return !grid.sweepCircleBlocked(spark.x, spark.y, self.pose.x, self.pose.y, BASE.sparkRadius);
}

/**
 * Move a desynced self's spark one substep toward its projection and resync on catch-up.
 * Returns true if the self resynced this substep.
 *
 * The spark heads straight for the projection whenever that line is clear; otherwise it follows an
 * A* route over walkable tiles, re-planned whenever the grid changes (a door opening gives it the
 * shorter route; DESYNC-04) and periodically as the projection moves. When the projection is
 * unreachable it waits as close as it can get (partial route). No timeout, no teleport (DESYNC).
 */
export function stepSpark(grid: Grid, paths: Pathfinder, self: SelfActor, loadout: ResolvedLoadout, sub: number): boolean {
  const spark = self.spark;
  if (!spark) return false;
  if (canResync(grid, self, spark)) return resync(self);
  let budget = (BASE.sparkSpeed * loadout.mods.sparkSpeed) / SUB_HZ;
  const tx = self.pose.x;
  const ty = self.pose.y;

  const direct = !grid.isSolidAt(tx, ty, BASE.sparkRadius) && !grid.sweepCircleBlocked(spark.x, spark.y, tx, ty, BASE.sparkRadius);
  if (direct) {
    moveToward(spark, tx, ty, budget);
  } else {
    const stale =
      spark.planRev !== grid.revision || sub - spark.planSub >= BASE.sparkReplanSubs || spark.pathIdx >= spark.path.length;
    if (stale) {
      const res = paths.findPath(spark.x, spark.y, tx, ty, { allowPartial: true, radius: BASE.sparkRadius });
      spark.path = res ? res.points : [];
      spark.pathIdx = 0;
      spark.planRev = grid.revision;
      spark.planSub = sub;
    }
    while (budget > 1e-12 && spark.pathIdx < spark.path.length) {
      const p = spark.path[spark.pathIdx];
      const d = Math.hypot(p.x - spark.x, p.y - spark.y);
      if (d <= budget) {
        spark.x = p.x;
        spark.y = p.y;
        budget -= d;
        spark.pathIdx++;
      } else {
        moveToward(spark, p.x, p.y, budget);
        budget = 0;
      }
    }
  }
  if (canResync(grid, self, spark)) return resync(self);
  return false;
}

function moveToward(p: Vec2, tx: number, ty: number, dist: number): void {
  const dx = tx - p.x;
  const dy = ty - p.y;
  const d = Math.hypot(dx, dy);
  if (d <= dist || d === 0) {
    p.x = tx;
    p.y = ty;
  } else {
    p.x += (dx / d) * dist;
    p.y += (dy / d) * dist;
  }
}

function resync(self: SelfActor): boolean {
  self.synced = true;
  self.spark = null;
  self.lastValidX = self.pose.x;
  self.lastValidY = self.pose.y;
  return true;
}

/** Stride length (tiles) between footstep events. */
export const STRIDE = 0.85;
