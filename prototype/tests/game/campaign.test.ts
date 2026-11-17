/**
 * Fixed-path campaign (LEVEL-08, LEVEL-09), loot (GEAR-04) and between-level loadouts (GEAR-03).
 */
import { describe, expect, it } from 'vitest';
import { BASE_LOADOUT, GEAR } from '../../src/content/index';
import type { LevelDef } from '../../src/core/types';
import { Campaign } from '../../src/game/campaign';
import { freshSave } from '../../src/game/save';
import { makeLevel } from '../helpers/levels';

const LOOT_1 = ['reel_lash', 'hush_hood'];
const LOOT_2 = ['needle_rail'];

function path(): LevelDef[] {
  return [
    makeLevel({ id: 'l2', index: 2, name: 'Third', loot: [] }),
    makeLevel({ id: 'l0', index: 0, name: 'First', loot: LOOT_1 }),
    makeLevel({ id: 'l1', index: 1, name: 'Second', loot: LOOT_2 }),
  ];
}

describe('campaign', () => {
  it('orders the path by index and opens only the first level on a fresh save', () => {
    const c = new Campaign(path(), freshSave());
    expect(c.levels.map((l) => l.id)).toEqual(['l0', 'l1', 'l2']);
    expect(['l0', 'l1', 'l2'].map((id) => c.isUnlocked(id))).toEqual([true, false, false]);
    expect(c.currentIndex()).toBe(0);
    expect(c.beginLevel('l1')).toBe(false);
    expect(c.isUnlocked('nope')).toBe(false);
  });

  it('clearing a level opens the next one; cleared levels stay replayable (LEVEL-09)', () => {
    const c = new Campaign(path(), freshSave());
    c.recordClear('l0');
    expect(['l0', 'l1', 'l2'].map((id) => c.isUnlocked(id))).toEqual([true, true, false]);
    expect(c.currentIndex()).toBe(1);
    c.recordClear('l1');
    c.recordClear('l2');
    expect(c.allCleared()).toBe(true);
    expect(c.currentIndex()).toBe(2);
    for (const id of ['l0', 'l1', 'l2']) expect(c.beginLevel(id)).toBe(true);
    expect(c.nextLevel('l0')!.id).toBe('l1');
    expect(c.nextLevel('l2')).toBeNull();
  });

  it('awards loot once, on the first clear only', () => {
    const c = new Campaign(path(), freshSave());
    const first = c.recordClear('l0');
    expect(first.firstClear).toBe(true);
    expect(first.loot.map((g) => g.id)).toEqual(LOOT_1);
    for (const id of LOOT_1) expect(c.save.inventory).toContain(id);
    const size = c.save.inventory.length;
    const again = c.recordClear('l0');
    expect(again).toEqual({ firstClear: false, loot: [] });
    expect(c.save.inventory).toHaveLength(size);
    expect(c.save.cleared).toEqual(['l0']);
    // The loadout screen marks the new items once.
    expect(c.loadoutModel(true).fresh).toEqual(LOOT_1);
    expect(c.loadoutModel().fresh).toEqual([]);
  });

  it('loadout changes only between levels, only to owned items of the right slot (GEAR-03)', () => {
    const c = new Campaign(path(), freshSave());
    expect(c.equip('melee', 'reel_lash')).toBe(false); // not owned yet
    c.recordClear('l0');
    expect(c.equip('helmet', 'reel_lash')).toBe(false); // wrong slot
    expect(c.equip('melee', 'no_such_item')).toBe(false);
    expect(c.beginLevel('l1')).toBe(true);
    expect(c.equip('melee', 'reel_lash')).toBe(false); // locked during an attempt
    expect(c.save.loadout.melee).toBe(BASE_LOADOUT.melee);
    c.endLevel();
    expect(c.equip('melee', 'reel_lash')).toBe(true);
    expect(c.save.loadout.melee).toBe('reel_lash');
    expect(c.resolvedLoadout().melee).toEqual(GEAR.reel_lash.melee);
    // Baseline gear is always available to swap back to.
    expect(c.equip('melee', BASE_LOADOUT.melee)).toBe(true);
  });

  it('builds the campaign screen model', () => {
    const c = new Campaign(path(), freshSave());
    c.recordClear('l0');
    const m = c.campaignModel();
    expect(m.current).toBe(1);
    expect(m.levels.map((l) => [l.level.id, l.cleared, l.unlocked])).toEqual([
      ['l0', true, true],
      ['l1', false, true],
      ['l2', false, false],
    ]);
    expect(m.levels[0].loot!.map((g) => g.id)).toEqual(LOOT_1);
    expect(m.levels[1].loot).toBeUndefined();
  });

  it('sanitises a save it is handed', () => {
    const save = freshSave();
    save.loadout = { ...save.loadout, melee: 'reel_lash' };
    const c = new Campaign(path(), save);
    expect(c.save.loadout.melee).toBe(BASE_LOADOUT.melee);
  });
});
