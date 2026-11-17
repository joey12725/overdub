/**
 * Stalker (AI-01, AI-02, AI-07): fast, one hit, and it hunts the FARTHEST effective self.
 *
 * The rule is the grunt's mirror image, so the two read as a pair: the grunt punishes whoever is
 * closest, the stalker goes for the straggler. Adding a self on the far side of the room drags the
 * stalker across it (AI-02: more selves change circumstances, not the rule).
 *
 * Targeting cadence. "Farthest from me" measured continuously would make a stalker between two
 * selves turn back the moment it passes the midpoint and dither there forever. So it CHOOSES on a
 * legible schedule and then commits:
 *   - on every bar line (master beat divisible by BEATS_PER_BAR), unless its quarry is already
 *     within STALKER_COMMIT_RANGE (it never abandons prey it is about to lunge at),
 *   - right after each of its own strikes,
 *   - immediately when its quarry stops being targetable (dies, desyncs),
 * it picks the farthest targetable self (perceived distance; ties → lowest tape index), and hunts
 * that self until the next choice. Strikes land on its beat grid like every melee enemy (AI-07).
 *
 * This file also hosts the shared beat-grid melee chaser used by the stalker, the shielder and the
 * brute (they differ in targeting, strike shape, timing and what hits do to them, not in how a
 * walk-telegraph-strike cycle works).
 */
import type { SelfActor } from '../actors';
import { angleDelta } from '../tape';
import { BASE } from '../tuning';
import { BEATS_PER_BAR, type EnemyType } from '../types';
import type { World } from '../sim';
import { isGridSub, perceivedDistance, selfByIndex, setState, targetable, telegraphSubs, walkToward } from './common';
import type { EnemyBehaviour, EnemyState } from './types';

// ───────────────────────────── shared melee chaser ─────────────────────────────

/** Shape and rhythm of a beat-grid melee enemy. */
export interface MeleeProfile {
  readonly type: EnemyType;
  /** Total strike arc in radians, centred on the facing locked at telegraph start. */
  readonly arc: number;
  /** Time the enemy stays committed after a strike, master beats. */
  readonly recoverBeats: number;
  /** Stops walking at this fraction of its reach from the target's centre. */
  readonly stopFraction: number;
  /** SimEvent.detail of its telegraph and attack (lets audio / render tell strikes apart). */
  readonly strikeName: string;
  /** Choose a quarry. Called by `retargetDue` moments and on target loss. */
  pick(w: World, e: EnemyState): SelfActor | null;
  /** Re-pick on this master beat boundary? (the grunt-like default is every beat) */
  retargetOnBeat(w: World, e: EnemyState, beat: number): boolean;
  /** Re-pick right after each strike? */
  readonly retargetAfterStrike: boolean;
}

/**
 * Hit every vulnerable self inside reach + body radius and the strike arc, with line of sight, at
 * this instant. One hit is lethal (HEALTH-01); i-frames are judged by the combat queue.
 */
export function meleeStrike(w: World, e: EnemyState, reach: number, arc: number, detail: string): void {
  const r = reach + BASE.actorRadius;
  for (const s of w.selves) {
    if (!targetable(s)) continue;
    const dx = s.pose.x - e.x;
    const dy = s.pose.y - e.y;
    const d = Math.hypot(dx, dy);
    if (d > r) continue;
    if (d > BASE.actorRadius && arc < Math.PI * 2) {
      const slack = Math.asin(Math.min(1, BASE.actorRadius / d));
      if (Math.abs(angleDelta(e.facing, Math.atan2(dy, dx))) > arc / 2 + slack) continue;
    }
    if (w.grid.segmentBlocked(e.x, e.y, s.pose.x, s.pose.y, true)) continue;
    w.combat.hitSelf({ self: s, cause: `struck by ${e.type} ${e.id}`, x: e.x, y: e.y, dir: e.facing });
  }
  w.emit({ type: 'enemyAttack', x: e.x, y: e.y, id: e.id, dir: e.facing, detail });
}

function repick(w: World, e: EnemyState, p: MeleeProfile): void {
  const t = p.pick(w, e);
  e.target = t ? t.index : undefined;
}

function strikeNow(w: World, e: EnemyState, p: MeleeProfile): void {
  meleeStrike(w, e, e.stats.reach, p.arc, p.strikeName);
  e.attackSub = -1;
  setState(e, 'attack', w.s, w.s + Math.round(p.recoverBeats * w.spb));
  if (p.retargetAfterStrike) e.mem.repickAfterRecover = true;
}

/**
 * The walk → telegraph → strike → recover cycle (AI-04 legibility, AI-07 grid):
 *   - when an attack-grid instant is exactly one telegraph away and the quarry is within reach, it
 *     plants, locks its facing and telegraphs; the strike lands ON the grid instant;
 *   - otherwise it walks toward the quarry (A* around walls and closed doors).
 * Being shoved or staggered cancels a telegraph (framework), so a strike never lands off-grid.
 */
export function meleeChaser(p: MeleeProfile): Pick<EnemyBehaviour, 'onBeat' | 'step'> {
  return {
    onBeat(w, e, beat) {
      if (e.state === 'telegraph' || e.state === 'attack') return;
      if (p.retargetOnBeat(w, e, beat)) repick(w, e, p);
    },
    step(w, e) {
      const s = w.s;
      if (e.state === 'telegraph') {
        if (s >= e.attackSub) strikeNow(w, e, p);
        return;
      }
      if (e.state === 'attack') {
        if (s < e.stateEnd) return;
        setState(e, 'idle', s, s);
        if (e.mem.repickAfterRecover) {
          e.mem.repickAfterRecover = false;
          repick(w, e, p);
        }
      }
      let target = selfByIndex(w, e.target);
      if (!target || !targetable(target)) {
        repick(w, e, p);
        target = selfByIndex(w, e.target);
      }
      if (!target) {
        if (e.state !== 'idle') setState(e, 'idle', s, s);
        return;
      }
      const dx = target.pose.x - e.x;
      const dy = target.pose.y - e.y;
      const d = Math.hypot(dx, dy);
      const tel = telegraphSubs(w, e);
      if (d <= e.stats.reach && isGridSub(w, e, s + tel)) {
        e.facing = Math.atan2(dy, dx);
        e.attackSub = s + tel;
        setState(e, 'telegraph', s, s + tel);
        w.emit({ type: 'enemyTelegraph', x: e.x, y: e.y, id: e.id, tape: target.index, dir: e.facing, detail: p.strikeName });
        if (tel === 0) strikeNow(w, e, p);
        return;
      }
      const moved = walkToward(w, e, target.pose.x, target.pose.y, e.stats.reach * p.stopFraction);
      if (!moved) e.facing = Math.atan2(dy, dx);
      if (moved && e.state !== 'move') setState(e, 'move', s, s);
      else if (!moved && e.state !== 'idle') setState(e, 'idle', s, s);
    },
  };
}

// ───────────────────────────── stalker ─────────────────────────────

/** Stalker strike arc (a quick lunge: narrower than the grunt's swing). */
export const STALKER_ARC = Math.PI / 2;
/** Recovery after a lunge, master beats. */
export const STALKER_RECOVER_BEATS = 0.25;
/** Within this many tiles of its quarry it stops reconsidering on bar lines, tiles. */
export const STALKER_COMMIT_RANGE = 2.5;

/**
 * Farthest targetable self from (x, y) by perceived distance. Ties go to the lowest tape index
 * (selves are sorted by index; strict comparison keeps the first).
 */
export function farthestTarget(w: World, x: number, y: number): SelfActor | null {
  let best: SelfActor | null = null;
  let bestD = -Infinity;
  for (const s of w.selves) {
    if (!targetable(s)) continue;
    const d = perceivedDistance(w, Math.hypot(s.pose.x - x, s.pose.y - y));
    if (d > bestD) {
      bestD = d;
      best = s;
    }
  }
  return best;
}

const STALKER_PROFILE: MeleeProfile = {
  type: 'stalker',
  arc: STALKER_ARC,
  recoverBeats: STALKER_RECOVER_BEATS,
  stopFraction: 0.6,
  strikeName: 'lunge',
  pick: (w, e) => farthestTarget(w, e.x, e.y),
  retargetOnBeat: (w, e, beat) => {
    if (beat % BEATS_PER_BAR !== 0) return false;
    const q = selfByIndex(w, e.target);
    return !q || !targetable(q) || Math.hypot(q.pose.x - e.x, q.pose.y - e.y) > STALKER_COMMIT_RANGE;
  },
  retargetAfterStrike: true,
};

export const STALKER: EnemyBehaviour = {
  type: 'stalker',
  ...meleeChaser(STALKER_PROFILE),
};
