/**
 * Grunt (AI-01, AI-07): walks at the NEAREST targetable self and strikes on its beat grid.
 *
 *   - Re-targets on every master beat (and immediately if its target stops being targetable), so a
 *     closer self changes what it does at a legible moment (TEST-18, AI-02).
 *   - When an attack-grid instant is exactly one telegraph away and its target is within reach, it
 *     plants, locks its facing and telegraphs; the strike lands ON the grid beat (AI-07) and hits
 *     every vulnerable self inside its reach + arc at that instant (one hit is lethal; HEALTH-01).
 *     Locking the facing at telegraph start makes the strike dodgeable by moving or rolling.
 *   - Otherwise it walks toward the target (path-finding around walls and closed doors).
 */
import { BASE } from '../tuning';
import { angleDelta } from '../tape';
import type { World } from '../sim';
import { isGridSub, nearestTarget, selfByIndex, setState, targetable, telegraphSubs, walkToward } from './common';
import type { EnemyBehaviour, EnemyState } from './types';

/** Total strike arc, radians. */
export const GRUNT_ARC = (2 * Math.PI) / 3;
/** Recovery after a strike, master beats. */
export const GRUNT_RECOVER_BEATS = 0.25;
/** The grunt stops walking this fraction of its reach from its target's centre. */
const STOP_FRACTION = 0.6;

function retarget(w: World, e: EnemyState): void {
  const t = nearestTarget(w, e.x, e.y);
  e.target = t ? t.index : undefined;
}

function strike(w: World, e: EnemyState): void {
  const reach = e.stats.reach + BASE.actorRadius;
  for (const s of w.selves) {
    if (!targetable(s)) continue;
    const dx = s.pose.x - e.x;
    const dy = s.pose.y - e.y;
    const d = Math.hypot(dx, dy);
    if (d > reach) continue;
    if (d > BASE.actorRadius) {
      const slack = Math.asin(Math.min(1, BASE.actorRadius / d));
      if (Math.abs(angleDelta(e.facing, Math.atan2(dy, dx))) > GRUNT_ARC / 2 + slack) continue;
    }
    if (w.grid.segmentBlocked(e.x, e.y, s.pose.x, s.pose.y, true)) continue;
    w.combat.hitSelf({ self: s, cause: `struck by grunt ${e.id}`, x: e.x, y: e.y, dir: e.facing });
  }
  w.emit({ type: 'enemyAttack', x: e.x, y: e.y, id: e.id, dir: e.facing, detail: 'strike' });
}

export const GRUNT: EnemyBehaviour = {
  type: 'grunt',

  onBeat(w, e) {
    if (e.state === 'telegraph' || e.state === 'attack') return;
    retarget(w, e);
  },

  step(w, e) {
    const s = w.s;
    if (e.state === 'telegraph') {
      if (s >= e.attackSub) {
        strike(w, e);
        e.attackSub = -1;
        setState(e, 'attack', s, s + Math.round(GRUNT_RECOVER_BEATS * w.spb));
      }
      return;
    }
    if (e.state === 'attack') {
      if (s < e.stateEnd) return;
      setState(e, 'idle', s, s);
    }
    let target = selfByIndex(w, e.target);
    if (!target || !targetable(target)) {
      retarget(w, e);
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
      w.emit({ type: 'enemyTelegraph', x: e.x, y: e.y, id: e.id, tape: target.index, dir: e.facing, detail: 'strike' });
      if (tel === 0) {
        strike(w, e);
        e.attackSub = -1;
        setState(e, 'attack', s, s + Math.round(GRUNT_RECOVER_BEATS * w.spb));
      }
      return;
    }
    const moved = walkToward(w, e, target.pose.x, target.pose.y, e.stats.reach * STOP_FRACTION);
    if (!moved) e.facing = Math.atan2(dy, dx);
    if (moved && e.state !== 'move') setState(e, 'move', s, s);
    else if (!moved && e.state !== 'idle') setState(e, 'idle', s, s);
  },
};
