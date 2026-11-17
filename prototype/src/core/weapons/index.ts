/**
 * The player's ranged weapon archetypes (WEAPON-01..03). Importing this module registers all five
 * with the projectile registry (src/core/projectiles.ts); the sim imports it, so any sim has them.
 * One file per archetype; every behaviour reads its numbers from the equipped RangedWeaponDef.
 */
import { registerProjectileArchetype, type ProjectileArchetype } from '../projectiles';
import { ARC } from './arc';
import { BURST } from './burst';
import { MISSILE } from './missile';
import { PHASE } from './phase';
import { PIERCE } from './pierce';

export const SELF_WEAPONS: readonly ProjectileArchetype[] = [MISSILE, PIERCE, PHASE, ARC, BURST];

/** (Re-)register the built-in weapon archetypes, e.g. after a test replaced one. */
export function registerSelfWeapons(): void {
  for (const a of SELF_WEAPONS) registerProjectileArchetype(a);
}

registerSelfWeapons();

export { ARC, arcBlast, arcHeight } from './arc';
export { BURST, burstHeadings } from './burst';
export { MISSILE, acquireNearestEnemy } from './missile';
export { PHASE } from './phase';
export { PIERCE } from './pierce';
export { detonate, distanceToEdge, projectileStrike, RANGED_EFFICIENCY, shotRadius, shotSpeed } from './common';
