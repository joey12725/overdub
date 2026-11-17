/**
 * Short-range burst (WEAPON-03): `def.count` straight pellets fanned evenly across `def.spreadDeg`
 * degrees, centred on the recorded direction (the outermost pellets fly at ±spread/2). Each pellet
 * is its own projectile with the weapon's full impact, short range and ordinary collision (stops at
 * the first enemy, wall or closed door), so a close target can take several pellets.
 */
import type { ProjectileArchetype } from '../projectiles';
import { wrapAngle } from '../tape';
import { hitEnemyStraight, hitWallStraight, selfShot } from './common';

/** Headings of a burst's pellets, in launch (spawn) order from one edge of the fan to the other. */
export function burstHeadings(dir: number, count: number, spreadDeg: number): number[] {
  const n = count >= 1 ? Math.floor(count) : 1;
  if (n === 1) return [dir];
  const spread = (spreadDeg * Math.PI) / 180;
  const out: number[] = [];
  for (let i = 0; i < n; i++) out.push(wrapAngle(dir - spread / 2 + (spread * i) / (n - 1)));
  return out;
}

export const BURST: ProjectileArchetype = {
  id: 'burst',

  launch(w, self, ev, passDir) {
    const def = w.loadout.ranged;
    const headings = burstHeadings(ev.dir, def.count, def.spreadDeg);
    for (const h of headings) w.projectiles.spawn(w, selfShot(w, self, 'burst', h, passDir));
    return headings.length;
  },

  onHitEnemy: hitEnemyStraight,
  onHitWall: (w, p, hit) => hitWallStraight(w, p, hit.x, hit.y),
};
