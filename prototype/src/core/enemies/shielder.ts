/**
 * Shielder (Scenario A, AI-05, HEALTH-02): a shield that recharges instantly, so only two selves
 * working together can hurt it.
 *
 * The rule, stated the way the player learns it:
 *   - The shield is up. A hit from a self POPS it: the hit itself does nothing ('clang', detail
 *     'shield') and the shield stays down for SHIELDER_WINDOW_BEATS master beats.
 *   - While it is down, a hit from a DIFFERENT self lands normally (damage, knockback, stagger) and
 *     the shield is instantly back up. That self has to pop it again for anyone to follow up.
 *   - A second hit from the same self that popped it is just another pop: it re-opens the window for
 *     that same self, which can never use it. So one self alone, at any speed or momentum, can
 *     never damage a shielder.
 *   - Hits from anything that is not a self (an enemy's bolt, the environment) clang off the shield
 *     and do not pop it: the lesson is cooperation between cassettes.
 * Hits on the same substep from two selves count as "within the window" (Scenario A's
 * simultaneous hits). The window is generous and stated in beats so the rule never depends on an
 * unexplained single-frame coincidence (Scenario A).
 *
 * Otherwise it walks at the NEAREST targetable self and strikes on its beat grid like a grunt.
 */
import type { EnemyStrike, HitResponse } from '../combat';
import { SHIELDER_WINDOW_BEATS } from '../tuning';
import type { World } from '../sim';
import { nearestTarget } from './common';
import { meleeChaser, type MeleeProfile } from './stalker';
import type { EnemyBehaviour, EnemyState } from './types';

/** Shielder strike arc, radians (a shield bash: the grunt's width). */
export const SHIELDER_ARC = (2 * Math.PI) / 3;
export const SHIELDER_RECOVER_BEATS = 0.5;

/** The follow-up window in master substeps. */
export function shieldWindowSubs(w: World): number {
  return Math.round(SHIELDER_WINDOW_BEATS * w.spb);
}

/** Is the shield down at substep `sub` (i.e. would a different self's hit on `sub` land)? */
export function shieldDownAt(w: World, e: EnemyState, sub: number): boolean {
  const pop = e.mem.popSub;
  return typeof pop === 'number' && pop >= 0 && sub - pop <= shieldWindowSubs(w);
}

const PROFILE: MeleeProfile = {
  type: 'shielder',
  arc: SHIELDER_ARC,
  recoverBeats: SHIELDER_RECOVER_BEATS,
  stopFraction: 0.6,
  strikeName: 'bash',
  pick: (w, e) => nearestTarget(w, e.x, e.y),
  retargetOnBeat: () => true,
  retargetAfterStrike: false,
};

export const SHIELDER: EnemyBehaviour = {
  type: 'shielder',
  ...meleeChaser(PROFILE),

  init(_w, e) {
    e.mem.popSub = -1;
    e.mem.popBy = -1;
  },

  onHit(w: World, e: EnemyState, strike: EnemyStrike): HitResponse {
    if (!('tape' in strike.source)) return { kind: 'block', reason: 'shield' };
    const by = strike.source.tape;
    if (shieldDownAt(w, e, w.s) && e.mem.popBy !== by) {
      // The follow-up landed: the shield snaps back up at once.
      e.mem.popSub = -1;
      e.mem.popBy = -1;
      return { kind: 'apply' };
    }
    e.mem.popSub = w.s;
    e.mem.popBy = by;
    return { kind: 'block', reason: 'shield' };
  },

  snapshot(w, e, snap) {
    // The snapshot describes the instant after substep w.s: the shield is down if a hit on the next
    // substep would still be inside the window.
    snap.shield = e.alive && !shieldDownAt(w, e, w.s + 1);
  },
};
