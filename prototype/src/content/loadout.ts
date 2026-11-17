/**
 * Loadout resolution: turns six equipped item ids into the numbers and flags the sim consumes,
 * plus the player-readable summary the loadout screen shows (APPAREL-03, APP-TEST-02).
 *
 * Robustness policy: content and saves can drift apart (an item renamed between builds, a hand-edited
 * save). Nothing here throws on bad ids; anything unknown or in the wrong slot falls back to that
 * slot's baseline item, which is always owned and always viable (GEAR-04, APP-TEST-03).
 */
import { GEAR_SLOTS } from '../core/types';
import type {
  AbilityId,
  GearItem,
  GearSlot,
  Loadout,
  MeleeWeaponDef,
  RangedArchetype,
  RangedWeaponDef,
  ResolvedLoadout,
  StatMods,
} from '../core/types';
import { BASE_LOADOUT, GEAR } from './gear';

type StatKey = keyof StatMods;

/**
 * Identity value of every StatMods key: 1 for multipliers, 0 for `*Add` keys (types.ts StatMods).
 * Also the canonical key order used for combining and describing.
 */
const IDENTITY: Readonly<Required<StatMods>> = Object.freeze({
  moveSpeed: 1,
  accel: 1,
  momentumRetention: 1,
  dodgeDistance: 1,
  dodgeIframes: 1,
  dodgeCooldown: 1,
  meleeImpact: 1,
  damage: 1,
  knockback: 1,
  knockbackCap: 1,
  stagger: 1,
  approachBonus: 1,
  sparkSpeed: 1,
  interactRadiusAdd: 0,
  projectileSpeed: 1,
  rangedCooldown: 1,
});

const STAT_KEYS = Object.keys(IDENTITY) as StatKey[];

/** True for keys that add rather than multiply (name ends in `Add`, per types.ts StatMods). */
export function isAdditiveStat(key: StatKey): boolean {
  return key.endsWith('Add');
}

/** A fresh StatMods object with every key at its identity value. */
export function identityMods(): Required<StatMods> {
  return { ...IDENTITY };
}

/**
 * Combine any number of partial StatMods: multipliers multiply, `*Add` keys add, missing keys are
 * identity. Non-finite values are ignored so one bad data entry cannot poison the whole loadout.
 */
export function combineMods(list: readonly (StatMods | undefined)[]): Required<StatMods> {
  const out = identityMods();
  for (const mods of list) {
    if (!mods) continue;
    for (const key of STAT_KEYS) {
      const v = mods[key];
      if (typeof v !== 'number' || !Number.isFinite(v)) continue;
      out[key] = isAdditiveStat(key) ? out[key] + v : out[key] * v;
    }
  }
  return out;
}

/** The item a slot should hold for `id`: the item itself if it exists and fits the slot, else the slot's baseline. */
function itemForSlot(slot: GearSlot, id: unknown): GearItem {
  if (typeof id === 'string' && Object.prototype.hasOwnProperty.call(GEAR, id)) {
    const found = GEAR[id]!;
    if (found.slot === slot) return found;
  }
  return GEAR[BASE_LOADOUT[slot]]!;
}

function cloneMelee(m: MeleeWeaponDef): MeleeWeaponDef {
  return { ...m, light: { ...m.light }, heavy: { ...m.heavy } };
}

function cloneRanged(r: RangedWeaponDef): RangedWeaponDef {
  return { ...r };
}

/**
 * Resolve a loadout into sim-ready numbers (contracts.ts content facade). Unknown ids, wrong-slot
 * ids and missing slots fall back to the baseline item for that slot. Weapon defs are copies, so the
 * sim may hold or adjust them without touching the catalogue.
 */
export function resolveLoadout(loadout: Partial<Loadout> | null | undefined): ResolvedLoadout {
  const items = GEAR_SLOTS.map((slot) => itemForSlot(slot, loadout?.[slot]));
  const resolved = {} as Loadout;
  GEAR_SLOTS.forEach((slot, i) => {
    resolved[slot] = items[i]!.id;
  });

  const abilities: AbilityId[] = [];
  for (const it of items) {
    for (const a of it.abilities ?? []) {
      if (!abilities.includes(a)) abilities.push(a);
    }
  }

  const meleeItem = items[GEAR_SLOTS.indexOf('melee')]!;
  const rangedItem = items[GEAR_SLOTS.indexOf('ranged')]!;
  // A melee/ranged item missing its weapon def would be a catalogue bug; fall back rather than crash.
  const melee = meleeItem.melee ?? GEAR[BASE_LOADOUT.melee]!.melee!;
  const ranged = rangedItem.ranged ?? GEAR[BASE_LOADOUT.ranged]!.ranged!;

  return {
    loadout: resolved,
    mods: combineMods(items.map((it) => it.mods)),
    abilities,
    melee: cloneMelee(melee),
    ranged: cloneRanged(ranged),
  };
}

// ─────────────────────────────── player-facing text ───────────────────────────────

export const SLOT_LABEL: Readonly<Record<GearSlot, string>> = {
  helmet: 'Headgear',
  top: 'Top',
  pants: 'Pants',
  shoes: 'Shoes',
  melee: 'Melee',
  ranged: 'Ranged',
};

/** Player-readable name of each stat, used in combined summaries. */
export const STAT_LABEL: Readonly<Record<StatKey, string>> = {
  moveSpeed: 'Run speed',
  accel: 'Acceleration',
  momentumRetention: 'Speed kept through turns and actions',
  dodgeDistance: 'Dodge distance',
  dodgeIframes: 'Dodge invulnerability',
  dodgeCooldown: 'Dodge cooldown',
  meleeImpact: 'Melee momentum',
  damage: 'Damage',
  knockback: 'Knockback',
  knockbackCap: 'Maximum knockback distance',
  stagger: 'Stagger',
  approachBonus: 'Run-in strike bonus',
  sparkSpeed: 'Recovery spark speed',
  interactRadiusAdd: 'Switch reach',
  projectileSpeed: 'Projectile speed',
  rangedCooldown: 'Ranged cooldown',
};

/** Player-readable statement of each ability, used in combined summaries and tooltips. */
export const ABILITY_TEXT: Readonly<Record<AbilityId, string>> = {
  manualDesync: 'Ability button: desync on purpose.',
  lowProfile: 'Enemies treat you as farther away than you are.',
  loudmouth: 'Enemies treat you as nearer than you are.',
  beatSight: 'Enemy attack beats are marked on the beat ruler.',
  laserProof: 'Lasers cannot kill you.',
  heavyStep: 'Standing still holds heavy plates and counts double on normal ones.',
  phaseDodge: 'Dodges pass through enemies and low barriers.',
  slideStrike: 'Striking out of a dodge adds momentum.',
  parry: 'Heavy swings reflect projectiles inside the arc.',
  killRefresh: 'A melee kill refreshes your dodge.',
};

const ARCHETYPE_TEXT: Readonly<Record<RangedArchetype, string>> = {
  missile: 'Homing missile, locks the nearest enemy once',
  pierce: 'Piercing shot',
  phase: 'Passes through walls',
  arc: 'Lobbed over low cover',
  burst: 'Short-range spread',
};

/** Format a number with at most `digits` decimals and no trailing zeros. */
function num(v: number, digits = 2): string {
  return String(Number(v.toFixed(digits)));
}

function seconds(localTicks: number): string {
  return `${num(localTicks / 60)} s`;
}

function statLine(key: StatKey, value: number): string | null {
  if (isAdditiveStat(key)) {
    const rounded = Number(value.toFixed(2));
    if (rounded === 0) return null;
    return `${STAT_LABEL[key]} ${rounded > 0 ? '+' : '-'}${num(Math.abs(rounded))} tiles`;
  }
  const pct = Math.round((value - 1) * 100);
  if (pct === 0) return null;
  return `${STAT_LABEL[key]} ${pct > 0 ? '+' : '-'}${Math.abs(pct)}%`;
}

/**
 * Player-readable combined effect lines for the loadout screen (APPAREL-03). Order: the two weapons,
 * then every stat the loadout moves away from baseline, then granted abilities. Weapon numbers
 * already include the loadout's projectile-speed and ranged-cooldown modifiers.
 */
export function describeLoadout(loadout: Partial<Loadout> | null | undefined): string[] {
  const r = resolveLoadout(loadout);
  const lines: string[] = [];

  const meleeName = GEAR[r.loadout.melee]!.name;
  const m = r.melee;
  const lightTicks = m.light.windup + m.light.active + m.light.recover;
  const heavyTicks = m.heavy.windup + m.heavy.active + m.heavy.recover;
  lines.push(
    `Melee: ${meleeName}. ${num(m.reach)}-tile reach, ${num(m.arcDeg, 0)}° arc, light ${seconds(lightTicks)}, heavy ${seconds(heavyTicks)}.`,
  );

  const rangedName = GEAR[r.loadout.ranged]!.name;
  const g = r.ranged;
  const speed = g.speed * r.mods.projectileSpeed;
  const cooldown = g.cooldown * r.mods.rangedCooldown;
  lines.push(
    `Ranged: ${rangedName}. ${ARCHETYPE_TEXT[g.archetype]}, ${num(speed, 1)} tiles/s, ${num(g.range, 1)}-tile range, ${seconds(cooldown)} cooldown.`,
  );

  const statLines: string[] = [];
  for (const key of STAT_KEYS) {
    const line = statLine(key, r.mods[key]);
    if (line !== null) statLines.push(line);
  }
  lines.push(...statLines);
  for (const a of r.abilities) lines.push(ABILITY_TEXT[a]);

  if (statLines.length === 0 && r.abilities.length === 0) {
    lines.push('Clothing: no modifiers. The plain kit.');
  }
  return lines;
}

// ─────────────────────────────── inventory helpers ───────────────────────────────

/** True when `id` names a baseline item; baseline items are owned implicitly and can never be lost. */
export function isBaseline(id: string): boolean {
  return (Object.values(BASE_LOADOUT) as string[]).includes(id);
}

/**
 * Owned items for one slot, in catalogue order, baseline first. The baseline item is always
 * included even when the inventory list omits it, so a slot can never be left empty. Unknown ids
 * and duplicates in the inventory are ignored.
 */
export function itemsForSlot(inventory: readonly string[], slot: GearSlot): GearItem[] {
  const owned = new Set(inventory);
  const base = GEAR[BASE_LOADOUT[slot]]!;
  const out: GearItem[] = [base];
  for (const it of Object.values(GEAR)) {
    if (it.slot === slot && it.id !== base.id && owned.has(it.id)) out.push(it);
  }
  return out;
}

/**
 * Repair a loadout so every slot holds an owned item of the right slot. Anything missing, unknown,
 * unowned or in the wrong slot becomes that slot's baseline. Safe on hand-edited or stale saves.
 */
export function sanitiseLoadout(loadout: Partial<Loadout> | null | undefined, inventory: readonly string[]): Loadout {
  const owned = new Set(inventory);
  const out = {} as Loadout;
  for (const slot of GEAR_SLOTS) {
    const id = loadout?.[slot];
    const it = typeof id === 'string' && Object.prototype.hasOwnProperty.call(GEAR, id) ? GEAR[id]! : null;
    out[slot] = it !== null && it.slot === slot && (owned.has(it.id) || isBaseline(it.id)) ? it.id : BASE_LOADOUT[slot];
  }
  return out;
}
