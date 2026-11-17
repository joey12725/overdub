/**
 * Shared enemy machinery: state creation, the per-substep driver, beat-grid helpers, targeting,
 * navigation, knockback and stagger. Behaviours (grunt.ts, turret.ts, …) build on these.
 *
 * Knockback (MOM-05) is a real slide over KNOCKBACK_SECONDS with wall collision; the enemy keeps
 * whatever position it ends at and resumes from there. Hitting a wall mid-slide turns the
 * remaining distance into extra stagger. Neither ever applies to selves (MOM-06).
 */
import { effectiveDistance } from '../abilities';
import type { EnemyStrike, StrikeSource } from '../combat';
import type { SelfActor } from '../actors';
import type { World } from '../sim';
import { ENEMY_STATS, KNOCKBACK_SECONDS, WALL_SLAM_STAGGER_PER_TILE } from '../tuning';
import { SUB_HZ, TAPE_NAMES, type EnemyDef, type EnemySnap } from '../types';
import { getEnemyBehaviour } from './registry';
import type { EnemyState, EnemyStateName } from './types';

/** Substeps between navigation re-plans while chasing (re-planning also happens on any door change). */
export const ENEMY_REPLAN_SUBS = 60;

export function createEnemyState(def: EnemyDef): EnemyState {
  const stats = ENEMY_STATS[def.type];
  const hp = def.hp ?? stats.hp;
  return {
    id: def.id,
    type: def.type,
    def,
    stats,
    every: def.beat?.every ?? stats.every,
    offset: def.beat?.offset ?? stats.offset,
    x: def.x,
    y: def.y,
    facing: def.facing ?? 0,
    hp,
    maxHp: hp,
    alive: true,
    awake: def.wakeWhen === undefined,
    state: def.wakeWhen === undefined ? 'idle' : 'asleep',
    stateStart: 0,
    stateEnd: 0,
    target: undefined,
    attackSub: -1,
    staggerUntil: 0,
    knockDx: 0,
    knockDy: 0,
    knockSubs: 0,
    path: [],
    pathIdx: 0,
    planSub: -Infinity,
    planRev: -1,
    planTx: 0,
    planTy: 0,
    deathSub: -1,
    killedBy: '',
    mem: {},
  };
}

export function setState(e: EnemyState, state: EnemyStateName, start: number, end: number): void {
  e.state = state;
  e.stateStart = start;
  e.stateEnd = end;
}

/**
 * Enemies phase of a substep. Fixed order: entity order. For each living enemy: integrate any
 * knockback slide; if awake and neither staggered nor sliding, run onBeat on beat boundaries and
 * then step.
 */
export function stepEnemies(w: World): void {
  const s = w.s;
  for (const e of w.enemies) {
    if (!e.alive) continue;
    if (e.knockSubs > 0) integrateKnockback(w, e);
    if (!e.awake) continue;
    if (s < e.staggerUntil) {
      e.state = 'stagger';
      continue;
    }
    if (e.state === 'stagger') setState(e, 'idle', s, s);
    if (e.knockSubs > 0) continue;
    const beh = getEnemyBehaviour(e.type);
    if (s % w.spb === 0 && beh.onBeat) beh.onBeat(w, e, s / w.spb);
    beh.step(w, e);
  }
}

// ───────────────────────────── beat grid (AI-07) ─────────────────────────────

function gridPeriod(w: World, e: EnemyState): number {
  return Math.round(e.every * w.spb);
}

function gridOffset(w: World, e: EnemyState): number {
  return Math.round(e.offset * w.spb);
}

/** Is `sub` on this enemy's attack grid (offset + k · every beats)? */
export function isGridSub(w: World, e: EnemyState, sub: number): boolean {
  const p = gridPeriod(w, e);
  if (!(p > 0)) return false;
  const r = (sub - gridOffset(w, e)) % p;
  return (r < 0 ? r + p : r) === 0;
}

/** First grid substep at or after `from`. */
export function nextGridSub(w: World, e: EnemyState, from: number): number {
  const p = gridPeriod(w, e);
  const off = gridOffset(w, e);
  if (!(p > 0)) return Infinity;
  const k = Math.ceil((from - off) / p);
  return off + k * p;
}

/** Telegraph length in substeps (AI-04 legibility). */
export function telegraphSubs(w: World, e: EnemyState): number {
  return Math.max(0, Math.round(e.stats.telegraphBeats * w.spb));
}

// ───────────────────────────── targeting ─────────────────────────────

/**
 * Only alive, synced selves are ever targeted: dead ghosts, the recording ghost (GHOST-04) and
 * desynced projections (DESYNC-07) are ignored by enemy decisions (ARCHITECTURE, AI-07 policy).
 */
export function targetable(self: SelfActor): boolean {
  return self.vulnerable;
}

/**
 * Distance as enemy decision logic perceives it. Loadout abilities: 'lowProfile' selves read as
 * farther, 'loudmouth' selves as nearer (factors and rule in abilities.ts effectiveDistance, the
 * single source). The loadout is shared by every cassette, so these change ranges (who is in
 * reach / in aggro), not which self is nearest.
 */
export function perceivedDistance(w: World, d: number): number {
  return effectiveDistance(w.loadout.abilities, d);
}

/**
 * Nearest targetable self from (x, y) by perceived straight-line distance, optionally filtered.
 * Ties go to the lowest tape index (selves are kept sorted by index; strict comparison).
 */
export function nearestTarget(
  w: World,
  x: number,
  y: number,
  accept?: (self: SelfActor, dist: number) => boolean,
): SelfActor | null {
  let best: SelfActor | null = null;
  let bestD = Infinity;
  for (const s of w.selves) {
    if (!targetable(s)) continue;
    const d = perceivedDistance(w, Math.hypot(s.pose.x - x, s.pose.y - y));
    if (accept && !accept(s, d)) continue;
    if (d < bestD) {
      bestD = d;
      best = s;
    }
  }
  return best;
}

export function selfByIndex(w: World, index: number | undefined): SelfActor | undefined {
  if (index === undefined) return undefined;
  for (const s of w.selves) if (s.index === index) return s;
  return undefined;
}

// ───────────────────────────── navigation ─────────────────────────────

/**
 * Walk toward (tx, ty) for one substep, stopping `stop` tiles short. Heads straight when the swept
 * body has a clear line, otherwise follows an A* route re-planned on door changes, periodically,
 * and when the goal has moved more than a tile. Movement collides with walls (no tunnelling).
 * Returns true if the enemy moved.
 */
export function walkToward(w: World, e: EnemyState, tx: number, ty: number, stop: number): boolean {
  const dist = Math.hypot(tx - e.x, ty - e.y);
  if (dist <= stop) return false;
  let budget = Math.min(e.stats.speed / SUB_HZ, dist - stop);
  if (!(budget > 0)) return false;
  const r = e.stats.radius;
  let gx = tx;
  let gy = ty;
  if (w.grid.sweepCircleBlocked(e.x, e.y, tx, ty, r * 0.95)) {
    const stale =
      e.planRev !== w.grid.revision ||
      w.s - e.planSub >= ENEMY_REPLAN_SUBS ||
      e.pathIdx >= e.path.length ||
      Math.hypot(tx - e.planTx, ty - e.planTy) > 1;
    if (stale) {
      const res = w.paths.findPath(e.x, e.y, tx, ty, { allowPartial: true, radius: r });
      e.path = res ? res.points : [];
      e.pathIdx = 0;
      e.planRev = w.grid.revision;
      e.planSub = w.s;
      e.planTx = tx;
      e.planTy = ty;
    }
    // Skip waypoints already reached.
    while (e.pathIdx < e.path.length && Math.hypot(e.path[e.pathIdx].x - e.x, e.path[e.pathIdx].y - e.y) < 1e-6) e.pathIdx++;
    if (e.pathIdx >= e.path.length) return false;
    gx = e.path[e.pathIdx].x;
    gy = e.path[e.pathIdx].y;
    const dg = Math.hypot(gx - e.x, gy - e.y);
    if (dg <= budget) {
      budget = dg;
      e.pathIdx++;
    }
  }
  const dx = gx - e.x;
  const dy = gy - e.y;
  const d = Math.hypot(dx, dy);
  if (!(d > 0)) return false;
  const res = w.grid.moveCircle(e.x, e.y, (dx / d) * budget, (dy / d) * budget, r);
  const moved = res.x !== e.x || res.y !== e.y;
  e.x = res.x;
  e.y = res.y;
  e.facing = Math.atan2(dy, dx);
  return moved;
}

// ───────────────────────────── knockback, stagger, death ─────────────────────────────

const KNOCK_SUBS = Math.max(1, Math.round(KNOCKBACK_SECONDS * SUB_HZ));

/** Start (or add to) a knockback slide of `dist` tiles in direction `dir` (MOM-05). */
export function applyKnockback(w: World, e: EnemyState, dir: number, dist: number): void {
  if (!(dist > 0)) return;
  const remX = e.knockDx * e.knockSubs;
  const remY = e.knockDy * e.knockSubs;
  const tx = remX + Math.cos(dir) * dist;
  const ty = remY + Math.sin(dir) * dist;
  e.knockDx = tx / KNOCK_SUBS;
  e.knockDy = ty / KNOCK_SUBS;
  e.knockSubs = KNOCK_SUBS;
  // A shove breaks a telegraph: the attack would otherwise land off the beat grid (AI-07).
  if (e.state === 'telegraph') {
    e.attackSub = -1;
    setState(e, 'idle', w.s, w.s);
  }
  e.path = [];
  e.pathIdx = 0;
}

function integrateKnockback(w: World, e: EnemyState): void {
  const want = Math.hypot(e.knockDx, e.knockDy);
  const res = w.grid.moveCircle(e.x, e.y, e.knockDx, e.knockDy, e.stats.radius);
  const got = Math.hypot(res.x - e.x, res.y - e.y);
  e.x = res.x;
  e.y = res.y;
  e.knockSubs--;
  if (res.blocked && want - got > want * 0.5) {
    // Slammed into a wall: the rest of the slide becomes stagger.
    const remaining = want - got + want * e.knockSubs;
    e.knockSubs = 0;
    applyStagger(w, e, Math.round(remaining * WALL_SLAM_STAGGER_PER_TILE * SUB_HZ));
  }
  if (e.knockSubs <= 0) {
    e.knockSubs = 0;
    e.knockDx = 0;
    e.knockDy = 0;
  }
}

/** Stagger for `subs` master substeps: cancels any telegraph, emits 'enemyStagger'. */
export function applyStagger(w: World, e: EnemyState, subs: number): void {
  if (!(subs > 0) || !e.alive) return;
  const until = w.s + subs;
  if (until <= e.staggerUntil) return;
  e.staggerUntil = until;
  e.attackSub = -1;
  setState(e, 'stagger', w.s, until);
  w.emit({ type: 'enemyStagger', x: e.x, y: e.y, id: e.id, power: subs / SUB_HZ });
}

/** Player-readable name of a strike source ("Tape A", "turret t1", "laser beam"). */
export function describeSource(w: World, src: StrikeSource): string {
  if ('tape' in src) return `Tape ${TAPE_NAMES[src.tape]}`;
  if ('enemy' in src) {
    const e = w.enemyById(src.enemy);
    return e ? `${e.type} ${e.id}` : src.enemy;
  }
  return src.env;
}

export function killEnemy(w: World, e: EnemyState, strike: EnemyStrike): void {
  e.alive = false;
  e.hp = 0;
  e.deathSub = w.s;
  e.killedBy = describeSource(w, strike.source);
  e.knockSubs = 0;
  e.attackSub = -1;
  setState(e, 'dead', w.s, w.s);
  w.emit({ type: 'kill', x: e.x, y: e.y, id: e.id, tape: 'tape' in strike.source ? strike.source.tape : undefined, power: strike.momentum, dir: strike.dir, detail: strike.kind });
  w.log.kill(e.id, w.s, e.killedBy);
  getEnemyBehaviour(e.type).onDeath?.(w, e);
}

/** Plain-data snapshot of an enemy at master instant `at`. */
export function enemySnapshot(w: World, e: EnemyState, at: number): EnemySnap {
  const span = e.stateEnd - e.stateStart;
  let progress = span > 0 ? (at - e.stateStart) / span : 0;
  progress = progress < 0 ? 0 : progress > 1 ? 1 : progress;
  const snap: EnemySnap = {
    id: e.id,
    type: e.type,
    x: e.x,
    y: e.y,
    facing: e.facing,
    hp: e.hp,
    maxHp: e.maxHp,
    alive: e.alive,
    state: e.state,
    stateT: progress,
  };
  // Only report a target that can still be targeted: a self that died or desynced is let go.
  const t = selfByIndex(w, e.target);
  if (e.alive && t && targetable(t)) snap.target = t.index;
  getEnemyBehaviour(e.type).snapshot?.(w, e, snap);
  return snap;
}
