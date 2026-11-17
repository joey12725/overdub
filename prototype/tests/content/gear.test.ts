import { describe, expect, it } from 'vitest';
import { GEAR_SLOTS } from '../../src/core/types';
import type { GearItem, GearSlot, Loadout, RangedArchetype, StatMods } from '../../src/core/types';
import {
  BASE_INVENTORY,
  BASE_LOADOUT,
  GEAR,
  LEVELS,
  SANDBOX,
  describeLoadout,
  identityMods,
  itemsForSlot,
  resolveLoadout,
  sanitiseLoadout,
} from '../../src/content';
import { isProblem, validateLevel } from '../../src/content/validate';

const ITEMS = Object.values(GEAR);
const bySlot = (slot: GearSlot): GearItem[] => ITEMS.filter((it) => it.slot === slot);
const CLOTHING: GearSlot[] = ['helmet', 'top', 'pants', 'shoes'];
const ARCHETYPES: RangedArchetype[] = ['missile', 'pierce', 'phase', 'arc', 'burst'];

describe('gear catalogue', () => {
  it('ids are unique and match their keys', () => {
    for (const [key, it] of Object.entries(GEAR)) expect(it.id).toBe(key);
    expect(new Set(ITEMS.map((it) => it.id)).size).toBe(ITEMS.length);
  });

  it('every item has a name, a non-empty effect and lore (APPAREL-03)', () => {
    for (const it of ITEMS) {
      expect(it.name.trim(), it.id).not.toBe('');
      expect(it.effect.trim(), it.id).not.toBe('');
      expect(it.lore.trim(), it.id).not.toBe('');
    }
  });

  it('every slot has at least 4 items', () => {
    for (const slot of GEAR_SLOTS) expect(bySlot(slot).length, slot).toBeGreaterThanOrEqual(4);
  });

  it('weapon defs live only on weapon slots, and every weapon has one', () => {
    for (const it of ITEMS) {
      expect(Boolean(it.melee), it.id).toBe(it.slot === 'melee');
      expect(Boolean(it.ranged), it.id).toBe(it.slot === 'ranged');
    }
  });

  it('every non-baseline clothing item changes stats or grants an ability (APPAREL-01)', () => {
    const base = new Set(Object.values(BASE_LOADOUT));
    for (const slot of CLOTHING) {
      for (const it of bySlot(slot)) {
        if (base.has(it.id)) continue;
        const hasMods = Object.keys(it.mods ?? {}).length > 0;
        const hasAbility = (it.abilities ?? []).length > 0;
        expect(hasMods || hasAbility, it.id).toBe(true);
      }
    }
  });

  it('pure stat clothing is a sidegrade, never strictly better (APPAREL-02)', () => {
    // A lower value is better only for cooldowns; everything else is better higher.
    const lowerIsBetter = new Set<keyof StatMods>(['dodgeCooldown', 'rangedCooldown']);
    for (const slot of CLOTHING) {
      for (const it of bySlot(slot)) {
        if ((it.abilities ?? []).length > 0 || !it.mods) continue;
        const entries = Object.entries(it.mods) as [keyof StatMods, number][];
        if (entries.length === 0) continue;
        // A single-stat item is allowed only when it is a niche perk (e.g. spark speed).
        if (entries.length === 1) continue;
        const gains = entries.filter(([k, v]) => (lowerIsBetter.has(k) ? v < 1 : k.endsWith('Add') ? v > 0 : v > 1));
        const losses = entries.filter(([k, v]) => (lowerIsBetter.has(k) ? v > 1 : k.endsWith('Add') ? v < 0 : v < 1));
        expect(gains.length, it.id).toBeGreaterThan(0);
        expect(losses.length, it.id).toBeGreaterThan(0);
      }
    }
  });
});

describe('melee weapons (WEAPON-04, NEW-01)', () => {
  const melee = bySlot('melee').map((it) => ({ id: it.id, def: it.melee! }));

  it('there are at least 5', () => {
    expect(melee.length).toBeGreaterThanOrEqual(5);
  });

  it('are pairwise distinct on reach, arc and light timing', () => {
    for (let i = 0; i < melee.length; i++) {
      for (let j = i + 1; j < melee.length; j++) {
        const a = melee[i]!.def;
        const b = melee[j]!.def;
        const pair = `${melee[i]!.id} vs ${melee[j]!.id}`;
        expect(a.reach, pair).not.toBe(b.reach);
        expect(a.arcDeg, pair).not.toBe(b.arcDeg);
        expect(a.light.windup, pair).not.toBe(b.light.windup);
      }
    }
  });

  it('differ in what the momentum is good for (damage vs knockback vs stagger)', () => {
    const best = (key: 'damageEff' | 'knockbackEff' | 'staggerEff'): string =>
      melee.reduce((top, m) => (m.def[key] > top.def[key] ? m : top)).id;
    expect(new Set([best('damageEff'), best('knockbackEff'), best('staggerEff')]).size).toBe(3);
  });

  it('every one is viable: a 1x standing light carries the baseline blade’s damage or more', () => {
    const base = GEAR[BASE_LOADOUT.melee]!.melee!;
    expect(base.light.impact).toBe(1);
    expect(base.damageEff).toBe(1);
    expect(base.heavy.impact).toBeGreaterThanOrEqual(1.6);
    expect(base.heavy.impact).toBeLessThanOrEqual(2);
    for (const m of melee) {
      expect(m.def.light.impact * m.def.damageEff, m.id).toBeGreaterThanOrEqual(1);
      expect(m.def.heavy.impact, m.id).toBeGreaterThan(m.def.light.impact);
    }
  });

  it('timings are positive whole local ticks', () => {
    for (const m of melee) {
      for (const swing of [m.def.light, m.def.heavy]) {
        for (const t of [swing.windup, swing.active, swing.recover]) {
          expect(Number.isInteger(t) && t > 0, m.id).toBe(true);
        }
      }
    }
  });
});

describe('ranged weapons (WEAPON-01..03, NEW-02..05)', () => {
  const ranged = bySlot('ranged').map((it) => ({ id: it.id, def: it.ranged! }));

  it('every archetype appears', () => {
    const present = new Set(ranged.map((r) => r.def.archetype));
    for (const a of ARCHETYPES) expect(present.has(a), a).toBe(true);
  });

  it('every missile is slower than every non-missile projectile (NEW-02)', () => {
    const missiles = ranged.filter((r) => r.def.archetype === 'missile');
    const others = ranged.filter((r) => r.def.archetype !== 'missile');
    expect(missiles.length).toBeGreaterThan(0);
    for (const m of missiles) for (const o of others) expect(m.def.speed, `${m.id} vs ${o.id}`).toBeLessThan(o.def.speed);
  });

  it('only missiles home', () => {
    for (const r of ranged) expect(r.def.turnRate > 0, r.id).toBe(r.def.archetype === 'missile');
  });

  it('only the phase weapon passes walls and only the arc weapon is lobbed (NEW-05)', () => {
    for (const r of ranged) {
      expect(r.def.passesWalls, r.id).toBe(r.def.archetype === 'phase');
      expect(r.def.lobbed, r.id).toBe(r.def.archetype === 'arc');
    }
  });

  it('only the pierce weapon pierces and only the burst fires several projectiles (NEW-04)', () => {
    for (const r of ranged) {
      expect(r.def.pierce > 0, r.id).toBe(r.def.archetype === 'pierce');
      expect(r.def.count > 1, r.id).toBe(r.def.archetype === 'burst');
    }
  });

  it('the burst is short range and the arc shot has a minimum range and a blast', () => {
    const burst = ranged.find((r) => r.def.archetype === 'burst')!.def;
    const longest = Math.max(...ranged.filter((r) => r.def.archetype !== 'burst').map((r) => r.def.range));
    expect(burst.range).toBeLessThan(longest);
    for (const r of ranged.filter((x) => x.def.archetype !== 'burst')) expect(burst.range, r.id).toBeLessThan(r.def.range);
    const arc = ranged.find((r) => r.def.archetype === 'arc')!.def;
    expect(arc.blast).toBeGreaterThan(0);
    expect(arc.minRange ?? 0).toBeGreaterThan(0);
    expect(arc.minRange!).toBeLessThan(arc.range);
  });
});

describe('resolveLoadout', () => {
  it('baseline resolves to identity: all multipliers 1, adds 0, no abilities', () => {
    const r = resolveLoadout(BASE_LOADOUT);
    expect(r.mods).toEqual(identityMods());
    for (const [k, v] of Object.entries(r.mods)) expect(v, k).toBe(k.endsWith('Add') ? 0 : 1);
    expect(r.abilities).toEqual([]);
    expect(r.loadout).toEqual(BASE_LOADOUT);
    expect(r.melee).toEqual(GEAR[BASE_LOADOUT.melee]!.melee);
    expect(r.ranged).toEqual(GEAR[BASE_LOADOUT.ranged]!.ranged);
  });

  it('returns weapon copies, not the catalogue objects', () => {
    const r = resolveLoadout(BASE_LOADOUT);
    r.melee.light.impact = 99;
    r.ranged.speed = 99;
    expect(GEAR[BASE_LOADOUT.melee]!.melee!.light.impact).toBe(1);
    expect(GEAR[BASE_LOADOUT.ranged]!.ranged!.speed).not.toBe(99);
  });

  it('multipliers multiply and adds add across slots', () => {
    const top = GEAR.ballast_puffer!; // moveSpeed 0.92, meleeImpact 1.25
    const shoes = GEAR.grip_sprinters!; // moveSpeed 1.12, dodgeIframes 0.8
    const pants = GEAR.parachute_pants!; // dodgeIframes 1.3, dodgeCooldown 1.2
    const r = resolveLoadout({ ...BASE_LOADOUT, top: top.id, shoes: shoes.id, pants: pants.id });
    expect(r.mods.moveSpeed).toBeCloseTo(top.mods!.moveSpeed! * shoes.mods!.moveSpeed!, 10);
    expect(r.mods.dodgeIframes).toBeCloseTo(shoes.mods!.dodgeIframes! * pants.mods!.dodgeIframes!, 10);
    expect(r.mods.meleeImpact).toBeCloseTo(1.25, 10);

    const hoodie = resolveLoadout({ ...BASE_LOADOUT, top: 'patchcord_hoodie' });
    expect(hoodie.mods.interactRadiusAdd).toBeCloseTo(0.75, 10);
  });

  it('unions abilities without duplicates', () => {
    const r = resolveLoadout({ ...BASE_LOADOUT, helmet: 'hush_hood', top: 'dropout_jacket', shoes: 'static_runners' });
    expect([...r.abilities].sort()).toEqual(['lowProfile', 'manualDesync', 'phaseDodge']);
  });

  it('unknown, wrong-slot and missing ids fall back to baseline instead of throwing', () => {
    const bad = { helmet: 'no_such_item', top: 'splice_blade', melee: 'mixtape_rocket' } as unknown as Loadout;
    const r = resolveLoadout(bad);
    expect(r.loadout).toEqual(BASE_LOADOUT);
    expect(r.melee.style).toBe('blade');
    expect(r.ranged.archetype).toBe('missile');
    expect(() => resolveLoadout(null)).not.toThrow();
    expect(resolveLoadout(undefined).loadout).toEqual(BASE_LOADOUT);
  });

  it('picks the equipped weapons', () => {
    const r = resolveLoadout({ ...BASE_LOADOUT, melee: 'reel_lash', ranged: 'bass_drop' });
    expect(r.melee.style).toBe('whip');
    expect(r.ranged.archetype).toBe('arc');
  });

  it('swapping each clothing slot away from baseline changes the resolved numbers or abilities (APP-TEST-01)', () => {
    const base = resolveLoadout(BASE_LOADOUT);
    for (const slot of CLOTHING) {
      const alternatives = bySlot(slot).filter((it) => it.id !== BASE_LOADOUT[slot]);
      expect(alternatives.length, slot).toBeGreaterThan(0);
      for (const alt of alternatives) {
        const r = resolveLoadout({ ...BASE_LOADOUT, [slot]: alt.id });
        const changed = JSON.stringify(r.mods) !== JSON.stringify(base.mods) || r.abilities.length !== base.abilities.length;
        expect(changed, `${slot}: ${alt.id}`).toBe(true);
      }
    }
  });
});

describe('describeLoadout', () => {
  it('names both weapons and says the baseline has no clothing modifiers', () => {
    const lines = describeLoadout(BASE_LOADOUT);
    expect(lines.some((l) => l.includes(GEAR[BASE_LOADOUT.melee]!.name))).toBe(true);
    expect(lines.some((l) => l.includes(GEAR[BASE_LOADOUT.ranged]!.name))).toBe(true);
    expect(lines.some((l) => /no modifiers/i.test(l))).toBe(true);
  });

  it('reports combined stats and abilities after a swap (APP-TEST-02)', () => {
    const lines = describeLoadout({ ...BASE_LOADOUT, shoes: 'spring_soles', helmet: 'click_visor', top: 'patchcord_hoodie' });
    expect(lines).toContain('Dodge distance +17%'); // 1.3 * 0.9 = 1.17
    expect(lines).toContain('Dodge cooldown +20%');
    expect(lines).toContain('Switch reach +0.75 tiles');
    expect(lines.some((l) => /beat ruler/.test(l))).toBe(true);
    expect(lines.some((l) => /no modifiers/i.test(l))).toBe(false);
  });

  it('every clothing swap changes the description', () => {
    const base = describeLoadout(BASE_LOADOUT).join('\n');
    for (const slot of CLOTHING) {
      for (const alt of bySlot(slot)) {
        if (alt.id === BASE_LOADOUT[slot]) continue;
        expect(describeLoadout({ ...BASE_LOADOUT, [slot]: alt.id }).join('\n'), alt.id).not.toBe(base);
      }
    }
  });
});

describe('inventory helpers', () => {
  it('BASE_INVENTORY holds exactly the baseline items', () => {
    expect([...BASE_INVENTORY].sort()).toEqual(Object.values(BASE_LOADOUT).sort());
  });

  it('itemsForSlot lists baseline first, then owned items of that slot only', () => {
    const inv = ['reel_lash', 'hush_hood', 'nonsense', 'reel_lash', 'splice_blade'];
    const melee = itemsForSlot(inv, 'melee').map((it) => it.id);
    expect(melee).toEqual(['splice_blade', 'reel_lash']);
    expect(itemsForSlot([], 'helmet').map((it) => it.id)).toEqual([BASE_LOADOUT.helmet]);
    expect(itemsForSlot(inv, 'helmet').map((it) => it.id)).toEqual([BASE_LOADOUT.helmet, 'hush_hood']);
  });

  it('sanitiseLoadout keeps valid owned picks', () => {
    const inv = [...BASE_INVENTORY, 'reel_lash', 'hush_hood'];
    const lo: Loadout = { ...BASE_LOADOUT, melee: 'reel_lash', helmet: 'hush_hood' };
    expect(sanitiseLoadout(lo, inv)).toEqual(lo);
  });

  it('sanitiseLoadout repairs unknown, unowned, wrong-slot and missing entries', () => {
    const bad = {
      helmet: 'feedback_crown', // not owned
      top: 'amp_sledge', // owned, wrong slot
      pants: 'ghost_pants', // unknown
      melee: 'reel_lash', // fine
      ranged: 42, // garbage
      // shoes missing
    } as unknown as Loadout;
    const out = sanitiseLoadout(bad, ['reel_lash', 'amp_sledge']);
    expect(out).toEqual({ ...BASE_LOADOUT, melee: 'reel_lash' });
    expect(sanitiseLoadout(null, [])).toEqual(BASE_LOADOUT);
    for (const slot of GEAR_SLOTS) expect(GEAR[out[slot]]!.slot).toBe(slot);
  });
});

describe('levels registry and sandbox', () => {
  it('LEVELS is the campaign ordered by index 1, 2, 3 …, with the sandbox kept off the path', () => {
    expect(LEVELS.length).toBeGreaterThan(0);
    LEVELS.forEach((l, i) => expect(l.index).toBe(i + 1));
    expect(LEVELS.some((l) => l.id === 'sandbox')).toBe(false);
    expect(SANDBOX.index).toBe(0);
  });

  it('every level’s loot names real gear', () => {
    for (const l of LEVELS) for (const id of l.loot) expect(GEAR[id], `${l.id}: ${id}`).toBeDefined();
  });

  it('the sandbox passes level validation', () => {
    const problems = validateLevel(SANDBOX).filter(isProblem);
    expect(problems).toEqual([]);
  });

  it('the sandbox exposes every speed and end mode, 4 tapes, and the mechanics it promises', () => {
    expect(SANDBOX.maxTapes).toBe(4);
    expect([...SANDBOX.speeds].sort()).toEqual([0.5, 1, 2, 4]);
    expect([...SANDBOX.endModes].sort()).toEqual(['repeat', 'reverse', 'stop']);
    const kinds = new Set(SANDBOX.entities.map((e) => e.kind));
    for (const k of ['door', 'switch', 'plate', 'breakable', 'enemy']) expect(kinds.has(k as never), k).toBe(true);
    const enemies = SANDBOX.entities.filter((e) => e.kind === 'enemy');
    expect(enemies.filter((e) => e.kind === 'enemy' && e.type === 'grunt').length).toBe(2);
    expect(enemies.filter((e) => e.kind === 'enemy' && e.type === 'turret').length).toBe(1);
    expect(SANDBOX.objective.type).toBe('eliminate');
  });
});
