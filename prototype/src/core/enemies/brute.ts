/**
 * Brute (HEALTH-02, MOM-01..05, AI-04, AI-07): three hit points, heavy, and slow to hit back.
 *
 *   - Hit points 3 (ENEMY_STATS): three standing 1× lights, or one 1× running heavy
 *     (floor(2 × 1.5) = 3), which is the momentum lesson.
 *   - Poise. A hit below BRUTE_POISE_MOMENTUM still does its damage but neither shoves nor staggers
 *     it: chip damage cannot interrupt the slam. A hit at or above it is applied in full through the
 *     shared formulas, where the brute's mass and poise still shrink the result: a high-momentum hit
 *     really moves it (MOM-05) and can break its telegraph.
 *   - Its slam is wide (BRUTE_ARC) and slow to arrive: the long telegraph (ENEMY_STATS
 *     telegraphBeats) is the window to roll out or to knock it out of the windup.
 *   - It walks at the NEAREST targetable self, re-choosing on every beat, like the grunt.
 *   - Its body is heavy enough to hold 'heavy' pressure plates.
 */
import type { EnemyStrike, HitResponse } from '../combat';
import type { World } from '../sim';
import { nearestTarget } from './common';
import { meleeChaser, type MeleeProfile } from './stalker';
import type { EnemyBehaviour, EnemyState } from './types';

/** Total slam arc, radians (240°: it is hard to stand anywhere near it except squarely behind). */
export const BRUTE_ARC = (4 * Math.PI) / 3;
/** Recovery after a slam, master beats (the punish window). */
export const BRUTE_RECOVER_BEATS = 1;
/**
 * Momentum a single hit needs to shove or stagger a brute. 3 = a 1× running heavy or anything
 * stronger; a 1× light (1.2) or a 2× standing light (2.4) just chips it.
 */
export const BRUTE_POISE_MOMENTUM = 3;

const PROFILE: MeleeProfile = {
  type: 'brute',
  arc: BRUTE_ARC,
  recoverBeats: BRUTE_RECOVER_BEATS,
  stopFraction: 0.6,
  strikeName: 'slam',
  pick: (w, e) => nearestTarget(w, e.x, e.y),
  retargetOnBeat: () => true,
  retargetAfterStrike: false,
};

export const BRUTE: EnemyBehaviour = {
  type: 'brute',
  heavyBody: true,
  ...meleeChaser(PROFILE),

  onHit(_w: World, _e: EnemyState, strike: EnemyStrike): HitResponse {
    if (strike.momentum >= BRUTE_POISE_MOMENTUM) return { kind: 'apply' };
    return { kind: 'replace', strike: { ...strike, knockback: 0, stagger: 0 } };
  },
};
