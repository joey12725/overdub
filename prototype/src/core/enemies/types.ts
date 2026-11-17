/**
 * Enemy framework contracts (AI-01..07).
 *
 * HOW TO ADD AN ENEMY TYPE
 *   1. Create `src/core/enemies/<type>.ts` exporting an `EnemyBehaviour` (see grunt.ts / turret.ts).
 *   2. Add it to the table in `registry.ts` (or call `registerEnemyBehaviour` before creating a sim).
 *   3. Put its numbers in `ENEMY_STATS` (tuning.ts); `EnemyDef.beat` / `hp` override per placement.
 *
 * The framework (enemies/common.ts, driven by sim.ts) owns everything shared, so a behaviour only
 * makes decisions:
 *   - wake-up (EnemyDef.wakeWhen), knockback integration with wall collision (MOM-05), stagger
 *     timing, death, beat bookkeeping and snapshots;
 *   - per substep, for an awake, alive enemy that is neither staggered nor sliding from knockback:
 *       onBeat(w, e, beat)   once on every master beat boundary (sub % subsPerBeat === 0), first;
 *       step(w, e)           every substep (movement, telegraph → attack progression).
 *   - onHit(w, e, strike) may veto or rewrite incoming momentum (shields, armour, boss phases);
 *     returning nothing special applies the strike normally (combat.applyStrike).
 *   - snapshot(w, e, snap) fills type-specific EnemySnap extras (shield, bossPhase, bossRecall…).
 *
 * Determinism rules every behaviour must keep: no randomness, decisions only from world state, ties
 * broken by lowest tape index / entity order, attacks landing on the beat grid (AI-07; use
 * `isGridSub` / `nextGridSub` from common.ts). Dead ghosts, recording ghosts and desynced selves are
 * never targets (`targetable` in common.ts).
 */
import type { EnemyStrike, HitResponse } from '../combat';
import type { World } from '../sim';
import type { EnemyStats } from '../tuning';
import type { EnemyDef, EnemySnap, EnemyType, TapeIndex, Vec2 } from '../types';

export type EnemyStateName = EnemySnap['state'];

/** Mutable per-run state of one enemy. Created fresh for every run (REC-02). */
export interface EnemyState {
  readonly id: string;
  readonly type: EnemyType;
  readonly def: EnemyDef;
  readonly stats: EnemyStats;
  /** Attack grid in master beats (EnemyDef.beat overrides the type default). */
  readonly every: number;
  readonly offset: number;

  x: number;
  y: number;
  facing: number;
  hp: number;
  maxHp: number;
  alive: boolean;
  awake: boolean;

  state: EnemyStateName;
  /** Substeps bounding the current state (for EnemySnap.stateT). */
  stateStart: number;
  stateEnd: number;
  /** Self currently targeted (lowest tape index on ties). */
  target: TapeIndex | undefined;
  /** Substep on which the telegraphed attack lands, or -1. */
  attackSub: number;

  /** Stagger lasts until this substep (exclusive). */
  staggerUntil: number;
  /** Remaining knockback slide: per-substep displacement and substeps left (MOM-05). */
  knockDx: number;
  knockDy: number;
  knockSubs: number;

  /** Navigation route (framework-managed by walkToward). */
  path: Vec2[];
  pathIdx: number;
  planSub: number;
  planRev: number;
  planTx: number;
  planTy: number;

  deathSub: number;
  killedBy: string;

  /** Behaviour-private extras (shield timers, boss phase…). Plain data only. */
  mem: Record<string, number | boolean | string | undefined>;
}

export interface EnemyBehaviour {
  readonly type: EnemyType;
  /** Bodies of this type hold 'heavy' pressure plates. */
  readonly heavyBody?: boolean;
  /**
   * Bodies of this type fly: they never press plates, and only walls and closed doors (projectile
   * solidity) count as solid for them, so a door closing elsewhere never shoves one hovering over void.
   */
  readonly hovering?: boolean;
  /** Called once when the run starts (after the framework filled the state). */
  init?(w: World, e: EnemyState): void;
  /** Called on every master beat boundary, before `step`, while awake and able to act. */
  onBeat?(w: World, e: EnemyState, beat: number): void;
  /** Called every substep while awake and able to act. */
  step(w: World, e: EnemyState): void;
  /** Incoming strike hook; absent = apply normally. */
  onHit?(w: World, e: EnemyState, strike: EnemyStrike): HitResponse;
  /** Called after the enemy died. */
  onDeath?(w: World, e: EnemyState): void;
  /** Fill type-specific snapshot fields. */
  snapshot?(w: World, e: EnemyState, snap: EnemySnap): void;
}
