/**
 * Public face of the simulation core (see src/contracts.ts "core").
 *
 * Extension points for later engineers:
 *   - enemy types:          src/core/enemies/registry.ts (+ one file per type)
 *   - projectile archetypes: registerProjectileArchetype in src/core/projectiles.ts
 *   - gear abilities:        registerAbilityHandler in src/core/sim.ts
 */
export { createSim, registerAbilityHandler, type AbilityHandler, type World } from './sim';
export { resolveEncounter } from './resolve';
export { buildBossMemory, recallCandidates, type RecallCandidate } from './bossMemory';
export { tapePhaseAt, horizonSubs, tapeTicks, subToBeat, subsPerBeat, ticksPerBeat, beatToSub, spanBars, traversalSubs } from './time';
export { registerEnemyBehaviour, getEnemyBehaviour, registeredEnemyTypes } from './enemies/registry';
export type { EnemyBehaviour, EnemyState } from './enemies/types';
export {
  registerProjectileArchetype,
  getProjectileArchetype,
  flyStraight,
  defaultHitEnemy,
  type Projectile,
  type ProjectileArchetype,
  type SpawnSpec,
} from './projectiles';
export type { SelfActor } from './actors';
