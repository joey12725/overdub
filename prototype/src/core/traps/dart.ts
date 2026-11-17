/**
 * The 'dart' projectile fired by dart launcher traps (docs/TRAPS.md "Dart launcher").
 *
 * A dart is an enemy 'bolt' with no owner to blame and no target: straight flight, stopped by walls,
 * closed doors, unbroken breakables and extended crushers (anything that blocks shots), over low
 * barriers. It kills the first vulnerable self it touches unless that self is inside dodge i-frames
 * (it then flies on through and never re-tests that self), passes through dead ghosts, the recording
 * ghost and desynced projections, and strikes the first living enemy it meets for DART_DAMAGE with a
 * short stagger and no knockback.
 *
 * Snapshots carry `owner: { enemy: <launcher id> }` because ProjectileSnap.owner has no trap member;
 * no enemy has that id, so nothing is excluded from the dart's contacts.
 */
import { registerProjectileArchetype, type Projectile, type ProjectileArchetype } from '../projectiles';
import type { World } from '../sim';
import { DART_DAMAGE, DART_RADIUS, DART_RANGE, HAZARD_STAGGER } from './tuning';

function launcherId(p: Projectile): string {
  return 'enemy' in p.owner ? p.owner.enemy : '?';
}

export const DART: ProjectileArchetype = {
  id: 'dart',
  onHitSelf(w, p, self) {
    if (!self.vulnerable) return 'pass';
    if (self.inIframes(w.s)) {
      p.struck.add(`self:${self.index}`);
      return 'pass';
    }
    w.combat.hitSelf({ self, cause: `shot by dart launcher ${launcherId(p)}`, x: p.x, y: p.y, dir: p.dir });
    return 'stop';
  },
  onHitEnemy(w, p, e) {
    p.struck.add(`enemy:${e.id}`);
    w.combat.strikeEnemy(e, {
      source: { env: `dart launcher ${launcherId(p)}` },
      kind: 'dart',
      momentum: 1,
      dir: p.dir,
      x: e.x,
      y: e.y,
      damage: DART_DAMAGE,
      knockback: 0,
      stagger: HAZARD_STAGGER,
    });
    return 'stop';
  },
};
registerProjectileArchetype(DART);

/** Spawn one dart at (x, y) flying along `dir` (radians) at `speed` tiles per master second. */
export function spawnDart(w: World, launcher: string, x: number, y: number, dir: number, speed: number): Projectile {
  return w.projectiles.spawn(w, {
    owner: { enemy: launcher },
    archetype: 'dart',
    x,
    y,
    dir,
    speed,
    radius: DART_RADIUS,
    range: DART_RANGE,
    momentum: 1,
    hitsSelves: true,
    hitsEnemies: true,
  });
}
