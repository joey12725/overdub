/**
 * Wall-penetrator (WEAPON-03, NEW-05): a straight shot that passes through walls, closed doors and
 * unbroken breakables, and stops at the first enemy it touches (unless the weapon data gives it
 * pierce). The map edge is the one thing it does not cross: it ends there with a 'projectileHit'
 * detailed 'phase:edge', so a shot never wanders outside the level.
 *
 * Passing walls is this archetype's rule; it is always on for 'phase' whatever `passesWalls` says,
 * and no other archetype gets it unless its own weapon data asks for it (NEW-05).
 */
import { flyStraight, type ProjectileArchetype } from '../projectiles';
import { SUB_HZ } from '../types';
import { distanceToEdge, EDGE_MARGIN, hitEnemyStraight, ownerTape, selfShot } from './common';

export const PHASE: ProjectileArchetype = {
  id: 'phase',

  launch(w, self, ev, passDir) {
    const spec = selfShot(w, self, 'phase', ev.dir, passDir);
    spec.passesWalls = true;
    w.projectiles.spawn(w, spec);
    return 1;
  },

  step(w, p) {
    const step = p.speed / SUB_HZ;
    const edge = distanceToEdge(w.grid, p.x, p.y, p.dir) - EDGE_MARGIN;
    if (edge >= step) {
      flyStraight(w, p);
      return;
    }
    flyStraight(w, p, edge > 0 ? edge : 0);
    if (!p.alive) return;
    p.alive = false;
    w.emit({ type: 'projectileHit', x: p.x, y: p.y, tape: ownerTape(p), dir: p.dir, detail: 'phase:edge' });
  },

  onHitEnemy: hitEnemyStraight,
};
