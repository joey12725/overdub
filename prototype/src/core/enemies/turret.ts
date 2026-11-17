/**
 * Turret (AI-06, AI-07): stationary, immovable (mass/poise Infinity), destroyed by melee.
 *
 *   - One telegraph before each attack-grid instant it picks the nearest targetable self that is in
 *     range, in line of sight (projectile solidity: walls and closed doors block, low barriers do
 *     not) and inside its optional aim arc (EnemyDef.arc, total width in radians centred on facing).
 *   - It tracks that target while telegraphing and fires one straight bolt ON the grid beat at the
 *     target's position at that instant. If the target became invalid it re-picks; if nothing is
 *     valid when the beat arrives, the shot is withheld (a turret does not fire at nothing).
 *   - Dead ghosts and desynced selves are never targeted (Scenario J: desync crosses the lane).
 */
import type { SelfActor } from '../actors';
import { spawnBolt } from '../projectiles';
import { angleDelta } from '../tape';
import type { World } from '../sim';
import { isGridSub, nearestTarget, perceivedDistance, selfByIndex, setState, targetable, telegraphSubs } from './common';
import type { EnemyBehaviour, EnemyState } from './types';

/** Recovery after a shot, master beats. */
export const TURRET_RECOVER_BEATS = 0.25;

function aimBase(e: EnemyState): number {
  return e.def.facing ?? 0;
}

/** Can the turret shoot at this self right now? */
function canShoot(w: World, e: EnemyState, s: SelfActor): boolean {
  if (!targetable(s)) return false;
  const dx = s.pose.x - e.x;
  const dy = s.pose.y - e.y;
  if (perceivedDistance(w, Math.hypot(dx, dy)) > e.stats.reach) return false;
  if (e.def.arc !== undefined && e.def.arc < Math.PI * 2) {
    if (Math.abs(angleDelta(aimBase(e), Math.atan2(dy, dx))) > e.def.arc / 2) return false;
  }
  return !w.grid.segmentBlocked(e.x, e.y, s.pose.x, s.pose.y, true);
}

function pick(w: World, e: EnemyState): SelfActor | null {
  return nearestTarget(w, e.x, e.y, (s) => canShoot(w, e, s));
}

function fire(w: World, e: EnemyState): void {
  let t = selfByIndex(w, e.target);
  if (!t || !canShoot(w, e, t)) t = pick(w, e) ?? undefined;
  e.attackSub = -1;
  const s = w.s;
  if (!t) {
    e.target = undefined;
    setState(e, 'idle', s, s);
    return;
  }
  e.target = t.index;
  e.facing = Math.atan2(t.pose.y - e.y, t.pose.x - e.x);
  spawnBolt(w, e, e.facing);
  w.emit({ type: 'enemyShot', x: e.x, y: e.y, id: e.id, tape: t.index, dir: e.facing, detail: 'bolt' });
  setState(e, 'attack', s, s + Math.round(TURRET_RECOVER_BEATS * w.spb));
}

export const TURRET: EnemyBehaviour = {
  type: 'turret',

  init(_w, e) {
    e.facing = aimBase(e);
  },

  step(w, e) {
    const s = w.s;
    if (e.state === 'telegraph') {
      const t = selfByIndex(w, e.target);
      if (t && canShoot(w, e, t)) e.facing = Math.atan2(t.pose.y - e.y, t.pose.x - e.x);
      if (s >= e.attackSub) fire(w, e);
      return;
    }
    if (e.state === 'attack') {
      if (s < e.stateEnd) return;
      setState(e, 'idle', s, s);
    }
    const tel = telegraphSubs(w, e);
    if (!isGridSub(w, e, s + tel)) return;
    const t = pick(w, e);
    if (!t) {
      e.target = undefined;
      return;
    }
    e.target = t.index;
    e.facing = Math.atan2(t.pose.y - e.y, t.pose.x - e.x);
    e.attackSub = s + tel;
    setState(e, 'telegraph', s, s + tel);
    w.emit({ type: 'enemyTelegraph', x: e.x, y: e.y, id: e.id, tape: t.index, dir: e.facing, detail: 'bolt' });
    if (tel === 0) fire(w, e);
  },
};
