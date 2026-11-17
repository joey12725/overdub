import type { CampaignScreenModel, LoadoutScreenModel, ResultsModel, UiIntent } from '../../src/contracts';
import type { GearItem, LevelDef, Loadout, MeleeWeaponDef, RangedWeaponDef, Theme } from '../../src/core/types';

export function level(index: number, over: Partial<LevelDef> = {}): LevelDef {
  return {
    id: `L${index + 1}`,
    index,
    name: `Level ${index + 1}`,
    tagline: `Tagline ${index + 1}`,
    theme: 'upper' as Theme,
    bpm: 120,
    bars: 4,
    horizonBars: 8,
    maxTapes: 2,
    speeds: [1, 2],
    endModes: [],
    map: ['###', '#.#', '###'],
    start: { x: 1.5, y: 1.5 },
    entities: [],
    objective: { type: 'reach', text: 'Reach the exit' },
    music: {
      root: 0,
      scale: 'minor',
      progression: [0],
      tracks: [
        { role: 'drums', formula: 'x' },
        { role: 'bass', formula: 'x' },
        { role: 'chord', formula: 'x' },
        { role: 'melody', formula: 'x' },
      ],
    },
    loot: [],
    briefing: [],
    ...over,
  };
}

export function campaign(clearedCount: number, total = 5): CampaignScreenModel {
  const current = Math.min(clearedCount, total - 1);
  return {
    levels: Array.from({ length: total }, (_, i) => ({
      level: level(i, { loot: i === 0 ? ['boots'] : [] }),
      cleared: i < clearedCount,
      unlocked: i <= current,
    })),
    current,
  };
}

export const BLADE: MeleeWeaponDef = {
  reach: 1.2,
  arcDeg: 110,
  light: { windup: 6, active: 4, recover: 10, impact: 1, moveMul: 0.4 },
  heavy: { windup: 18, active: 5, recover: 18, impact: 2.2, moveMul: 0.2 },
  damageEff: 1,
  knockbackEff: 1,
  staggerEff: 1,
  style: 'blade',
};

export const MAUL: MeleeWeaponDef = {
  reach: 1.5,
  arcDeg: 150,
  light: { windup: 12, active: 5, recover: 16, impact: 1.4, moveMul: 0.3 },
  heavy: { windup: 30, active: 6, recover: 24, impact: 3.2, moveMul: 0.1 },
  damageEff: 0.8,
  knockbackEff: 1.6,
  staggerEff: 1.2,
  style: 'blunt',
};

export const MISSILE: RangedWeaponDef = {
  archetype: 'missile',
  speed: 2.5,
  range: 18,
  impact: 1.2,
  commit: 12,
  cooldown: 90,
  pierce: 0,
  passesWalls: false,
  lobbed: false,
  count: 1,
  spreadDeg: 0,
  turnRate: Math.PI,
  blast: 0,
};

export const RAIL: RangedWeaponDef = { ...MISSILE, archetype: 'pierce', speed: 22, range: 12, pierce: 3, turnRate: 0, cooldown: 45, commit: 8, impact: 0.9 };

export const GEAR: GearItem[] = [
  { id: 'cap', slot: 'helmet', name: 'Cap', effect: 'No special effect.', lore: '' },
  { id: 'hood', slot: 'helmet', name: 'Hood', effect: 'Enemies think you are farther away.', lore: 'quiet', abilities: ['lowProfile'] },
  { id: 'crop', slot: 'top', name: 'Crop', effect: 'No special effect.', lore: '' },
  { id: 'cargo', slot: 'pants', name: 'Cargo', effect: 'No special effect.', lore: '' },
  { id: 'glide', slot: 'pants', name: 'Glide', effect: 'Momentum +25%.', lore: '', mods: { momentumRetention: 1.25, accel: 0.9 } },
  { id: 'kicks', slot: 'shoes', name: 'Kicks', effect: 'No special effect.', lore: '' },
  { id: 'boots', slot: 'shoes', name: 'Boots', effect: 'Faster dodge.', lore: '', mods: { dodgeCooldown: 0.8, moveSpeed: 1.1 } },
  { id: 'blade', slot: 'melee', name: 'Blade', effect: 'Baseline.', lore: '', melee: BLADE },
  { id: 'maul', slot: 'melee', name: 'Maul', effect: 'Big knockback.', lore: '', melee: MAUL },
  { id: 'missile', slot: 'ranged', name: 'Missile', effect: 'Slow homing.', lore: '', ranged: MISSILE },
  { id: 'rail', slot: 'ranged', name: 'Rail', effect: 'Pierces.', lore: '', ranged: RAIL },
];

export const BASE: Loadout = { helmet: 'cap', top: 'crop', pants: 'cargo', shoes: 'kicks', melee: 'blade', ranged: 'missile' };

export function loadoutModel(over: Partial<LoadoutScreenModel> = {}): LoadoutScreenModel {
  return { inventory: GEAR, loadout: { ...BASE }, summary: [], fresh: ['boots'], ...over };
}

export function results(over: Partial<ResultsModel> = {}): ResultsModel {
  return {
    level: level(2, { maxTapes: 3 }),
    outcome: { win: true, objectiveComplete: true, survivors: [0], notes: ['Tape A held the plate.'] },
    tapesUsed: 2,
    loot: [GEAR[1]],
    hasNext: true,
    ...over,
  };
}

export function recorder(): { emit: (i: UiIntent) => void; intents: UiIntent[] } {
  const intents: UiIntent[] = [];
  return { emit: (i) => intents.push(i), intents };
}
