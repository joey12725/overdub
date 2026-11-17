/**
 * Arc / vertical shot (WEAPON-03, NEW-05): a lobbed shell.
 *
 *   - It travels along the recorded direction to a landing point `def.range` tiles away (never less
 *     than `def.minRange`), cut short only by the map edge.
 *   - In flight it is above everything: low barriers, walls of ordinary height, closed doors and
 *     enemies do not touch it. The snapshot reports its height `z` (> 0 in flight, peak
 *     ARC_PEAK_HEIGHT at mid-flight) so the renderer can draw the lob.
 *   - On landing it bursts: every living enemy whose body overlaps the blast radius (def.blast, at
 *     least ARC_MIN_BLAST) is struck with the weapon's impact and pushed away from the centre.
 *     Walls shield enemies from the blast unless the shell lands on top of the wall itself.
 *   - Speed is horizontal tiles per master second, like every other projectile.
 */
import type { ProjectileArchetype } from '../projectiles';
import { ARC_MIN_BLAST, ARC_PEAK_HEIGHT } from '../tuning';
import { SUB_HZ } from '../types';
import { detonate, distanceToEdge, EDGE_MARGIN, ownerTape, selfShot } from './common';

/** Height of a shell that has covered fraction `f` of its flight (a parabola peaking mid-flight). */
export function arcHeight(f: number): number {
  const t = f < 0 ? 0 : f > 1 ? 1 : f;
  return 4 * ARC_PEAK_HEIGHT * t * (1 - t);
}

/** Blast radius an arc weapon actually uses. */
export function arcBlast(blast: number): number {
  return blast > ARC_MIN_BLAST ? blast : ARC_MIN_BLAST;
}

export const ARC: ProjectileArchetype = {
  id: 'arc',

  launch(w, self, ev, passDir) {
    const def = w.loadout.ranged;
    const spec = selfShot(w, self, 'arc', ev.dir, passDir);
    const wanted = Math.max(def.minRange ?? 0, def.range);
    const edge = distanceToEdge(w.grid, self.pose.x, self.pose.y, ev.dir) - EDGE_MARGIN;
    spec.range = Math.max(0, Math.min(wanted, edge));
    spec.passesWalls = true;
    spec.hitsEnemies = false;
    spec.pierce = 0;
    spec.data = { blast: arcBlast(def.blast) };
    w.projectiles.spawn(w, spec);
    return 1;
  },

  step(w, p) {
    const remaining = p.range - p.travelled;
    const d = Math.min(p.speed / SUB_HZ, remaining > 0 ? remaining : 0);
    p.x += Math.cos(p.dir) * d;
    p.y += Math.sin(p.dir) * d;
    p.travelled += d;
    if (p.travelled < p.range - 1e-9) {
      p.z = arcHeight(p.travelled / p.range);
      return;
    }
    p.z = 0;
    p.alive = false;
    const radius = p.data.blast ?? ARC_MIN_BLAST;
    w.emit({ type: 'projectileHit', x: p.x, y: p.y, tape: ownerTape(p), dir: p.dir, power: radius, detail: 'arc:land' });
    detonate(w, p, p.x, p.y, radius);
  },
};
