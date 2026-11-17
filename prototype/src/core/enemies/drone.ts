/**
 * Drone (AI-01, AI-06, AI-07, HEALTH-02): a hovering gun that keeps its distance and fires on the
 * off-beat.
 *
 *   - Hovers: low barriers ('=') and void (' ') do not stop it; walls and closed doors do. It never
 *     presses pressure plates (nothing touches the floor).
 *   - Spacing: its target is the NEAREST targetable self (re-chosen every beat), and it keeps
 *     DRONE_KEEP_DISTANCE tiles (± DRONE_KEEP_BAND) away. Any self closer than the band pushes it
 *     away (pushes from several selves add up, so between two of them it settles where they
 *     balance instead of ping-ponging); otherwise, with its target too far or out of sight, it
 *     closes in. With nothing pushing and its target in the band it holds position.
 *   - Fire: its attack instants are its beat grid (ENEMY_STATS / EnemyDef.beat) shifted by half a
 *     beat, so a drone always fires on an "and", never on the beat a grunt or turret uses. Exactly one
 *     telegraph before an instant, if its target is within range with a clear line, it stops, locks
 *     its aim and telegraphs; the bolt leaves ON the off-beat along the
 *     locked aim (dodgeable by moving or rolling). Bolts are the turret's: walls stop them, low
 *     barriers do not.
 *   - 2 hit points: a standing 1× light chips it, a 2× light (or two selves) kills it.
 *   - Knockback over ground it could not stand on would shove it to the nearest floor edge under
 *     walking collision, which reads as a teleport; there it takes the damage and stagger only.
 */
import type { EnemyStrike, HitResponse } from '../combat';
import type { Grid } from '../grid';
import { spawnBolt } from '../projectiles';
import { DRONE_KEEP_DISTANCE } from '../tuning';
import { SUB_HZ } from '../types';
import type { World } from '../sim';
import { isGridSub, nearestTarget, perceivedDistance, selfByIndex, setState, targetable, telegraphSubs, walkToward } from './common';
import type { EnemyBehaviour, EnemyState } from './types';

/** Half-width of the comfortable distance band around DRONE_KEEP_DISTANCE, tiles. */
export const DRONE_KEEP_BAND = 0.5;
/** Recovery after a shot, master beats. */
export const DRONE_RECOVER_BEATS = 0.25;
/** Off-beat shift of the drone's attack grid, master beats. */
export const DRONE_OFFBEAT = 0.5;
/** With no line of sight it closes in until this near (it will have sight long before). */
const NO_SIGHT_STOP = 1;
/** Largest single collision step while hovering, tiles. */
const HOVER_STEP = 0.1;

/** Does a hovering circle overlap anything that stops flight (walls, closed doors)? */
export function hoverSolidAt(grid: Grid, x: number, y: number, radius: number): boolean {
  const c0 = Math.floor(x - radius);
  const c1 = Math.floor(x + radius);
  const r0 = Math.floor(y - radius);
  const r1 = Math.floor(y + radius);
  const r2 = radius * radius;
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      if (!grid.blocksShot(c, r)) continue;
      const qx = x < c ? c : x > c + 1 ? c + 1 : x;
      const qy = y < r ? r : y > r + 1 ? r + 1 : y;
      const dx = x - qx;
      const dy = y - qy;
      if (dx * dx + dy * dy < r2) return true;
    }
  }
  return false;
}

/**
 * Fly by (dx, dy) under hover collision, sliding along walls axis by axis. Steps are short so it
 * cannot tunnel. Returns true if it moved.
 */
export function hoverMove(w: World, e: EnemyState, dx: number, dy: number): boolean {
  const r = e.stats.radius;
  const n = Math.max(1, Math.ceil(Math.hypot(dx, dy) / HOVER_STEP));
  const sx = dx / n;
  const sy = dy / n;
  let x = e.x;
  let y = e.y;
  for (let i = 0; i < n; i++) {
    if (!hoverSolidAt(w.grid, x + sx, y + sy, r)) {
      x += sx;
      y += sy;
    } else if (sx !== 0 && !hoverSolidAt(w.grid, x + sx, y, r)) {
      x += sx;
    } else if (sy !== 0 && !hoverSolidAt(w.grid, x, y + sy, r)) {
      y += sy;
    } else {
      break;
    }
  }
  const moved = x !== e.x || y !== e.y;
  e.x = x;
  e.y = y;
  return moved;
}

/** Is `sub` one of this drone's (off-beat) firing instants? */
export function isDroneFireSub(w: World, e: EnemyState, sub: number): boolean {
  return isGridSub(w, e, sub - Math.round(DRONE_OFFBEAT * w.spb));
}

function hasShot(w: World, e: EnemyState, tx: number, ty: number): boolean {
  if (perceivedDistance(w, Math.hypot(tx - e.x, ty - e.y)) > e.stats.reach) return false;
  return !w.grid.segmentBlocked(e.x, e.y, tx, ty, true);
}

function fire(w: World, e: EnemyState): void {
  const s = w.s;
  e.attackSub = -1;
  spawnBolt(w, e, e.facing);
  w.emit({ type: 'enemyShot', x: e.x, y: e.y, id: e.id, tape: e.target, dir: e.facing, detail: 'bolt' });
  setState(e, 'attack', s, s + Math.round(DRONE_RECOVER_BEATS * w.spb));
}

function retarget(w: World, e: EnemyState): void {
  const t = nearestTarget(w, e.x, e.y);
  e.target = t ? t.index : undefined;
}

export const DRONE: EnemyBehaviour = {
  type: 'drone',
  hovering: true,

  onBeat(w, e) {
    if (e.state === 'telegraph' || e.state === 'attack') return;
    retarget(w, e);
  },

  step(w, e) {
    const s = w.s;
    if (e.state === 'telegraph') {
      if (s >= e.attackSub) fire(w, e);
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
    const tx = target.pose.x;
    const ty = target.pose.y;
    const dx = tx - e.x;
    const dy = ty - e.y;
    const d = Math.hypot(dx, dy);
    const tel = telegraphSubs(w, e);
    const clear = hasShot(w, e, tx, ty);
    if (clear && isDroneFireSub(w, e, s + tel)) {
      e.facing = Math.atan2(dy, dx);
      e.attackSub = s + tel;
      setState(e, 'telegraph', s, s + tel);
      w.emit({ type: 'enemyTelegraph', x: e.x, y: e.y, id: e.id, tape: target.index, dir: e.facing, detail: 'bolt' });
      if (tel === 0) fire(w, e);
      return;
    }
    const step = e.stats.speed / SUB_HZ;
    let moved = false;
    const sight = !w.grid.segmentBlocked(e.x, e.y, tx, ty, true);
    // Backing off weighs every self inside the comfort distance, not just the target: backing
    // straight away from the nearest would carry it into the next one and it would ping-pong
    // between them. Summed, it settles where the pushes balance.
    let rx = 0;
    let ry = 0;
    let crowd = 0;
    for (const o of w.selves) {
      if (!targetable(o)) continue;
      const ox = e.x - o.pose.x;
      const oy = e.y - o.pose.y;
      const od = Math.hypot(ox, oy);
      if (!(od > 0) || od >= DRONE_KEEP_DISTANCE - DRONE_KEEP_BAND) continue;
      rx += (ox / od) * (DRONE_KEEP_DISTANCE - od);
      ry += (oy / od) * (DRONE_KEEP_DISTANCE - od);
      crowd++;
    }
    const push = Math.hypot(rx, ry);
    if (crowd > 0) {
      // Never overshoot the balance point: each unit of travel changes the summed push by about
      // one unit per self pushing.
      if (push > 1e-3) {
        const back = Math.min(step, push / crowd);
        moved = hoverMove(w, e, (rx / push) * back, (ry / push) * back);
      }
    } else if (!sight && d > NO_SIGHT_STOP) {
      // Regaining line of sight. Around walls it follows a walking route while it is over walkable
      // ground; over void or barriers it flies straight and slides along whatever stops it.
      if (!w.grid.isSolidAt(e.x, e.y, e.stats.radius)) moved = walkToward(w, e, tx, ty, NO_SIGHT_STOP);
      else moved = hoverMove(w, e, (dx / d) * Math.min(step, d - NO_SIGHT_STOP), (dy / d) * Math.min(step, d - NO_SIGHT_STOP));
    } else if (sight && d > DRONE_KEEP_DISTANCE + DRONE_KEEP_BAND) {
      const fwd = Math.min(step, d - DRONE_KEEP_DISTANCE);
      moved = hoverMove(w, e, (dx / d) * fwd, (dy / d) * fwd);
    }
    e.facing = Math.atan2(dy, dx);
    if (moved && e.state !== 'move') setState(e, 'move', s, s);
    else if (!moved && e.state !== 'idle') setState(e, 'idle', s, s);
  },

  onHit(w: World, e: EnemyState, strike: EnemyStrike): HitResponse {
    if (w.grid.isSolidAt(e.x, e.y, e.stats.radius)) return { kind: 'replace', strike: { ...strike, knockback: 0 } };
    return { kind: 'apply' };
  },
};
