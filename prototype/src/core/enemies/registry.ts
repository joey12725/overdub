/**
 * Enemy-type registry. One entry per EnemyType; each behaviour lives in its own file.
 *
 * To add a type: import its behaviour here and append it to `builtin()` (or call
 * registerEnemyBehaviour before creating a sim). A level that places an enemy whose type has no
 * registered behaviour fails loudly when the sim is created, rather than spawning an inert body.
 *
 * The table is built lazily on first use because behaviour files import enemies/common.ts, which
 * imports this module: an eager table could read a behaviour binding before its module finished
 * evaluating, depending on which file an importer happened to load first.
 */
import type { EnemyType } from '../types';
import { BOSS } from './boss';
import { BRUTE } from './brute';
import { DRONE } from './drone';
import { GRUNT } from './grunt';
import { SHIELDER } from './shielder';
import { STALKER } from './stalker';
import { TURRET } from './turret';
import type { EnemyBehaviour } from './types';

function builtin(): EnemyBehaviour[] {
  return [GRUNT, TURRET, STALKER, SHIELDER, BRUTE, DRONE, BOSS];
}

let registry: Map<EnemyType, EnemyBehaviour> | null = null;
const overrides: EnemyBehaviour[] = [];

function table(): Map<EnemyType, EnemyBehaviour> {
  if (!registry) {
    registry = new Map(builtin().map((b) => [b.type, b]));
    for (const b of overrides) registry.set(b.type, b);
  }
  return registry;
}

/** Register (or replace) the behaviour for an enemy type. */
export function registerEnemyBehaviour(b: EnemyBehaviour): void {
  if (registry) registry.set(b.type, b);
  else overrides.push(b);
}

export function hasEnemyBehaviour(type: EnemyType): boolean {
  return table().has(type);
}

/** The behaviour for a type. Throws for unregistered types (see module doc). */
export function getEnemyBehaviour(type: EnemyType): EnemyBehaviour {
  const b = table().get(type);
  if (!b) throw new Error(`No enemy behaviour registered for type '${type}' (src/core/enemies/registry.ts)`);
  return b;
}

/** Registered types, for tools and validators. */
export function registeredEnemyTypes(): EnemyType[] {
  return [...table().keys()];
}
