/**
 * Piercing shot (WEAPON-03, NEW-04): a fast straight shot that keeps going through up to
 * `def.pierce` enemies, striking each one once, and stops at the next one, at a wall or closed door,
 * or when its range runs out. Lining enemies up along its path is the puzzle.
 *
 * Piercing is this weapon's data, not a property every shot inherits: every straight archetype reads
 * `def.pierce`, and the shipped non-piercing weapons set it to 0 (NEW-04, NEW-05).
 */
import type { ProjectileArchetype } from '../projectiles';
import { hitEnemyStraight, hitWallStraight, selfShot } from './common';

export const PIERCE: ProjectileArchetype = {
  id: 'pierce',

  launch(w, self, ev, passDir) {
    w.projectiles.spawn(w, selfShot(w, self, 'pierce', ev.dir, passDir));
    return 1;
  },

  onHitEnemy: hitEnemyStraight,
  onHitWall: (w, p, hit) => hitWallStraight(w, p, hit.x, hit.y),
};
