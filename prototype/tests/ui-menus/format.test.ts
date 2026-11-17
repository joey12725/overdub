import { describe, expect, it } from 'vitest';
import { GEAR_SLOTS } from '../../src/core/types';
import {
  allSlotLabels,
  compareItems,
  itemDetailRows,
  meleeStatRows,
  modLines,
  num,
  pct,
  rangedDownside,
  rangedStatRows,
  slotLabel,
  speedLabel,
  ticksToSeconds,
  weaponHeadline,
} from '../../src/ui/menus/format';
import { BLADE, GEAR, MAUL, MISSILE, RAIL } from './fixtures';

describe('slot labelling (APPAREL-03)', () => {
  it('covers all six GearSlots with distinct titles, kinds and short codes', () => {
    const labels = allSlotLabels();
    expect(labels.map((l) => l.slot)).toEqual([...GEAR_SLOTS]);
    for (const key of ['title', 'kind', 'short'] as const) {
      expect(new Set(labels.map((l) => l.label[key])).size).toBe(6);
    }
  });

  it('uses the plain category names the requirement lists', () => {
    expect(slotLabel('helmet').title).toBe('HELMET / HEADGEAR');
    expect(slotLabel('top').title).toBe('TOP');
    expect(slotLabel('pants').title).toBe('PANTS');
    expect(slotLabel('shoes').title).toBe('SHOES');
    expect(slotLabel('melee').title).toBe('MELEE');
    expect(slotLabel('ranged').title).toBe('RANGED');
  });
});

describe('number formatting', () => {
  it('trims zeros and formats percentages and ticks', () => {
    expect(num(1.5)).toBe('1.5');
    expect(num(2)).toBe('2');
    expect(num(0.125, 2)).toBe('0.13');
    expect(pct(1.1)).toBe('+10%');
    expect(pct(0.85)).toBe('−15%');
    expect(pct(1)).toBe('±0%');
    expect(ticksToSeconds(6)).toBe('0.1 s');
    expect(ticksToSeconds(60)).toBe('1 s');
    expect(speedLabel(0.5)).toBe('½×');
    expect(speedLabel(4)).toBe('4×');
  });

  it('modLines states non-neutral mods in plain language', () => {
    expect(modLines({ moveSpeed: 1.1, dodgeCooldown: 0.8, interactRadiusAdd: 0.75, damage: 1 })).toEqual([
      'Run speed +10%',
      'Dodge cooldown −20%',
      'Interact reach +0.75 tiles',
    ]);
    expect(modLines(undefined)).toEqual([]);
  });
});

describe('weapon stat formatting (WEAPON-01..04)', () => {
  it('melee rows show reach, arc, light/heavy timing and knockback/damage/stagger character', () => {
    const rows = Object.fromEntries(meleeStatRows(MAUL).map((r) => [r.label, r.value]));
    expect(rows.Style).toBe('Blunt');
    expect(rows.Reach).toBe('1.5 tiles');
    expect(rows.Arc).toBe('150°');
    expect(rows.Light).toBe('0.2 s windup · 0.08 s hit · 0.27 s recover (0.55 s total at 1×)');
    expect(rows.Heavy).toBe('0.5 s windup · 0.1 s hit · 0.4 s recover (1 s total at 1×)');
    expect(rows.Impact).toBe('light 1.4 · heavy 3.2');
    expect(rows.Knockback).toBe('1.6× (very high)');
    expect(rows.Damage).toBe('0.8× (low)');
    expect(rows.Stagger).toBe('1.2× (high)');
  });

  it('ranged rows show archetype, speed, range and special behaviour', () => {
    const missile = Object.fromEntries(rangedStatRows(MISSILE).map((r) => [r.label, r.value]));
    expect(missile.Type).toBe('Homing missile');
    expect(missile.Speed).toBe('2.5 tiles/s (very slow)');
    expect(missile.Range).toBe('18 tiles');
    expect(missile.Homing).toBe('180°/s turn, one lock at launch');
    const rail = Object.fromEntries(rangedStatRows(RAIL).map((r) => [r.label, r.value]));
    expect(rail.Speed).toBe('22 tiles/s (fast)');
    expect(rail.Pierce).toBe('passes through 3 enemies');
    expect(rail.Homing).toBeUndefined();
    const mortar = rangedStatRows({ ...MISSILE, archetype: 'arc', lobbed: true, blast: 1.2, minRange: 3, turnRate: 0 });
    expect(mortar.map((r) => r.label)).toEqual(expect.arrayContaining(['Trajectory', 'Blast', 'Min range']));
  });

  it('every ranged weapon states a downside; the missile is slow by design (WEAPON-02)', () => {
    expect(rangedDownside({ ranged: MISSILE })).toMatch(/slow/i);
    expect(rangedDownside({ ranged: MISSILE })).toMatch(/long cooldown \(1\.5 s\)/);
    expect(rangedDownside({ ranged: RAIL })).toMatch(/straight/i);
    expect(rangedDownside({ ranged: RAIL, downside: 'Custom.' })).toBe('Custom.');
    const rows = itemDetailRows(GEAR.find((g) => g.id === 'rail')!);
    expect(rows.find((r) => r.label === 'Downside')).toBeTruthy();
  });

  it('headline summarises a weapon in one line, null for apparel', () => {
    expect(weaponHeadline(GEAR.find((g) => g.id === 'blade')!)).toBe('Blade · reach 1.2 · 110° arc · light 0.1 s windup');
    expect(weaponHeadline(GEAR.find((g) => g.id === 'missile')!)).toBe('Homing missile · 2.5 tiles/s · 18 tiles');
    expect(weaponHeadline(GEAR[0])).toBeNull();
  });
});

describe('comparison', () => {
  it('melee comparison marks faster windups as better and lower impact as worse', () => {
    const rows = compareItems(
      { id: 'a', slot: 'melee', name: 'A', effect: '', lore: '', melee: MAUL },
      { id: 'b', slot: 'melee', name: 'B', effect: '', lore: '', melee: BLADE },
    );
    const by = Object.fromEntries(rows.map((r) => [r.label, r]));
    expect(by['Light windup'].dir).toBe(1);
    expect(by['Light impact'].dir).toBe(-1);
    expect(by.Reach).toMatchObject({ from: '1.5 tiles', to: '1.2 tiles', dir: -1 });
    expect(by.Knockback.dir).toBe(-1);
    expect(by.Damage.dir).toBe(1);
  });

  it('ranged comparison treats lower cooldown as better', () => {
    const rows = compareItems(GEAR.find((g) => g.id === 'missile')!, GEAR.find((g) => g.id === 'rail')!);
    const by = Object.fromEntries(rows.map((r) => [r.label, r]));
    expect(by.Cooldown.dir).toBe(1);
    expect(by.Speed.dir).toBe(1);
    expect(by.Range.dir).toBe(-1);
    expect(by.Type).toMatchObject({ from: 'Homing missile', to: 'Piercing shot', dir: 0 });
  });

  it('apparel comparison lists only changed mods and gained/lost abilities', () => {
    const cargo = GEAR.find((g) => g.id === 'cargo')!;
    const glide = GEAR.find((g) => g.id === 'glide')!;
    expect(compareItems(cargo, glide)).toEqual([
      { label: 'Acceleration', from: '±0%', to: '−10%', dir: -1 },
      { label: 'Momentum kept on turns', from: '±0%', to: '+25%', dir: 1 },
    ]);
    const kicks = GEAR.find((g) => g.id === 'kicks')!;
    const boots = GEAR.find((g) => g.id === 'boots')!;
    const shoeRows = compareItems(kicks, boots);
    expect(shoeRows.find((r) => r.label === 'Dodge cooldown')!.dir).toBe(1);
    const cap = GEAR[0];
    const hood = GEAR[1];
    expect(compareItems(cap, hood)).toEqual([{ label: 'Low profile', from: '—', to: 'gained', dir: 1 }]);
    expect(compareItems(hood, cap)).toEqual([{ label: 'Low profile', from: 'yes', to: 'lost', dir: -1 }]);
  });
});
