/**
 * Guided missile (MISSILE-01..04, WEAPON-02, NEW-02, NEW-03, TEST-22, Scenario F).
 *
 *   - Deliberately very slow: it flies at the weapon's own (low) speed, which leaves the battlefield
 *     time to change before it arrives (WEAPON-02).
 *   - At launch it acquires the nearest living enemy exactly once, by straight-line distance from
 *     the launch point; ties go to the enemy placed first in the level (entity order), so the choice
 *     is deterministic (MISSILE-03 leaves ties open). Line of sight is not required: the missile
 *     steers, and walls simply stop it if they are in the way. Sleeping enemies are living enemies.
 *   - It then turns toward that one target at most `turnRate` radians per master second and never
 *     retargets: not when another enemy becomes nearer, not when its target dies. With a dead or
 *     absent target it flies straight on until it hits something or its range runs out.
 *   - It strikes whatever enemy it actually touches first (the lock steers it; it does not make it
 *     pass through other bodies). Blocked by walls and closed doors unless the weapon data says it
 *     passes walls. No enemy at launch: it flies straight along the recorded direction.
 *   - The recorded direction is the initial heading on every pass, including a reverse pass (the
 *     requirements leave reverse behaviour open; a re-fired shot is a fresh shot with its recorded
 *     aim, like a re-fired swing; PLAY-06).
 *   - The missile is a world object: it keeps flying if its launcher later dies or desyncs (left
 *     open by the requirements; nothing about the launch is undone).
 */
import type { SelfActor } from '../actors';
import type { EnemyState } from '../enemies/types';
import { flyStraight, type ProjectileArchetype } from '../projectiles';
import type { World } from '../sim';
import { angleDelta, wrapAngle } from '../tape';
import { SUB_HZ } from '../types';
import { hitEnemyStraight, hitWallStraight, selfShot } from './common';

/** The nearest living enemy to (x, y); ties go to entity order. Null when none is alive. */
export function acquireNearestEnemy(w: World, x: number, y: number): EnemyState | null {
  let best: EnemyState | null = null;
  let bestD = Infinity;
  for (const e of w.enemies) {
    if (!e.alive) continue;
    const d = Math.hypot(e.x - x, e.y - y);
    if (d < bestD) {
      bestD = d;
      best = e;
    }
  }
  return best;
}

export const MISSILE: ProjectileArchetype = {
  id: 'missile',

  launch(w, self: SelfActor, ev, passDir) {
    const spec = selfShot(w, self, 'missile', ev.dir, passDir);
    const target = acquireNearestEnemy(w, self.pose.x, self.pose.y);
    if (target) spec.targetId = target.id;
    spec.data = { ...spec.data, turnRate: Math.max(0, w.loadout.ranged.turnRate) };
    w.projectiles.spawn(w, spec);
    return 1;
  },

  step(w, p) {
    const turn = (p.data.turnRate ?? 0) / SUB_HZ;
    if (p.targetId !== undefined && turn > 0) {
      const t = w.enemyById(p.targetId);
      // MISSILE-03: the lock is never moved to another enemy; a dead target just stops the homing.
      if (t && t.alive) {
        const want = Math.atan2(t.y - p.y, t.x - p.x);
        const d = angleDelta(p.dir, want);
        p.dir = wrapAngle(Math.abs(d) <= turn ? want : p.dir + Math.sign(d) * turn);
      }
    }
    flyStraight(w, p);
  },

  onHitEnemy: hitEnemyStraight,
  onHitWall: (w, p, hit) => hitWallStraight(w, p, hit.x, hit.y),
};
