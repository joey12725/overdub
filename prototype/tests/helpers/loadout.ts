/**
 * Test helper: a baseline ResolvedLoadout built from src/core/tuning.ts only, so core tests never
 * depend on src/content. The weapons are the plain baselines the tuning targets are written for.
 */
import { NEUTRAL_MODS } from '../../src/core/tuning';
import type { MeleeWeaponDef, RangedWeaponDef, ResolvedLoadout, StatMods } from '../../src/core/types';

/** Plain baseline melee weapon (light 6/4/10 ticks, heavy 16/5/18 ticks). */
export const BASE_MELEE: MeleeWeaponDef = {
  reach: 1.1,
  arcDeg: 110,
  light: { windup: 6, active: 4, recover: 10, impact: 1.2, moveMul: 0.5 },
  heavy: { windup: 16, active: 5, recover: 18, impact: 2, moveMul: 0.25 },
  damageEff: 1,
  knockbackEff: 1,
  staggerEff: 1,
  style: 'blade',
};

/** Plain homing missile: very slow, locks once at launch (WEAPON-02, MISSILE-03). */
export const BASE_MISSILE: RangedWeaponDef = {
  archetype: 'missile',
  speed: 2.5,
  range: 14,
  impact: 1.2,
  commit: 12,
  cooldown: 45,
  pierce: 0,
  passesWalls: false,
  lobbed: false,
  count: 1,
  spreadDeg: 0,
  turnRate: 2.5,
  blast: 0,
};

export interface LoadoutPatch {
  mods?: StatMods;
  abilities?: ResolvedLoadout['abilities'];
  melee?: Partial<MeleeWeaponDef>;
  ranged?: Partial<RangedWeaponDef>;
}

/** A fresh baseline loadout; `patch` overrides individual mods, abilities or weapon fields. */
export function baseLoadout(patch: LoadoutPatch = {}): ResolvedLoadout {
  return {
    loadout: {
      helmet: 'base-helmet',
      top: 'base-top',
      pants: 'base-pants',
      shoes: 'base-shoes',
      melee: 'base-melee',
      ranged: 'base-missile',
    },
    mods: { ...NEUTRAL_MODS, ...patch.mods },
    abilities: [...(patch.abilities ?? [])],
    melee: {
      ...BASE_MELEE,
      ...patch.melee,
      light: { ...BASE_MELEE.light, ...patch.melee?.light },
      heavy: { ...BASE_MELEE.heavy, ...patch.melee?.heavy },
    },
    ranged: { ...BASE_MISSILE, ...patch.ranged },
  };
}
