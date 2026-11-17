/**
 * Save data: round trip, validation and corrupt-save recovery (never throws).
 */
import { describe, expect, it } from 'vitest';
import { BASE_INVENTORY, BASE_LOADOUT } from '../../src/content/index';
import type { SaveData } from '../../src/core/types';
import { eraseSave, freshSave, loadSave, memoryStorage, SAVE_KEY, validateSave, writeSave, type SaveStorage } from '../../src/game/save';

function sample(): SaveData {
  return {
    version: 1,
    cleared: ['sandbox'],
    inventory: [...BASE_INVENTORY, 'reel_lash', 'needle_rail', 'hush_hood'],
    loadout: { ...BASE_LOADOUT, melee: 'reel_lash', ranged: 'needle_rail', helmet: 'hush_hood' },
    settings: { master: 0.5, music: 0.25, sfx: 1, avOffsetMs: -40, screenShake: false, patterns: true },
  };
}

describe('save', () => {
  it('a fresh save is the baseline kit with nothing cleared', () => {
    const s = freshSave();
    expect(s.version).toBe(1);
    expect(s.cleared).toEqual([]);
    expect(s.loadout).toEqual(BASE_LOADOUT);
    expect([...s.inventory].sort()).toEqual([...BASE_INVENTORY].sort());
  });

  it('round-trips through storage under a versioned key', () => {
    const store = memoryStorage();
    expect(writeSave(sample(), store)).toBe(true);
    expect(store.data.has(SAVE_KEY)).toBe(true);
    expect(SAVE_KEY).toMatch(/v1$/);
    expect(loadSave(store)).toEqual(sample());
  });

  it('missing, corrupt or foreign data falls back to a fresh save', () => {
    expect(loadSave(memoryStorage())).toEqual(freshSave());
    expect(loadSave(memoryStorage({ [SAVE_KEY]: '{not json' }))).toEqual(freshSave());
    expect(loadSave(memoryStorage({ [SAVE_KEY]: 'null' }))).toEqual(freshSave());
    expect(loadSave(memoryStorage({ [SAVE_KEY]: '[1,2,3]' }))).toEqual(freshSave());
    expect(loadSave(memoryStorage({ [SAVE_KEY]: JSON.stringify({ ...sample(), version: 2 }) }))).toEqual(freshSave());
    expect(loadSave(null)).toEqual(freshSave());
  });

  it('storage that throws never breaks loading or saving', () => {
    const hostile: SaveStorage = {
      getItem() {
        throw new Error('SecurityError');
      },
      setItem() {
        throw new Error('QuotaExceededError');
      },
      removeItem() {
        throw new Error('nope');
      },
    };
    expect(loadSave(hostile)).toEqual(freshSave());
    expect(writeSave(sample(), hostile)).toBe(false);
    expect(eraseSave(hostile)).toBe(false);
  });

  it('repairs a damaged save field by field', () => {
    const damaged = {
      version: 1,
      cleared: ['sandbox', 42, 'sandbox', null],
      inventory: ['reel_lash', 'no_such_item', 7],
      loadout: { helmet: 'hush_hood', top: 'reel_lash', melee: 'reel_lash', shoes: 12 },
      settings: { master: 7, music: -1, sfx: 'loud', avOffsetMs: 9999, screenShake: 'yes', patterns: true },
    };
    const v = validateSave(damaged);
    expect(v.cleared).toEqual(['sandbox']);
    expect(v.inventory).toContain('reel_lash');
    expect(v.inventory).not.toContain('no_such_item');
    for (const id of BASE_INVENTORY) expect(v.inventory).toContain(id);
    // Not owned → baseline; wrong slot → baseline; owned and right slot → kept.
    expect(v.loadout.helmet).toBe(BASE_LOADOUT.helmet);
    expect(v.loadout.top).toBe(BASE_LOADOUT.top);
    expect(v.loadout.melee).toBe('reel_lash');
    expect(v.loadout.shoes).toBe(BASE_LOADOUT.shoes);
    expect(v.settings).toEqual({ master: 1, music: 0, sfx: 0.8, avOffsetMs: 300, screenShake: true, patterns: true });
  });

  it('erase removes the stored save', () => {
    const store = memoryStorage();
    writeSave(sample(), store);
    expect(eraseSave(store)).toBe(true);
    expect(loadSave(store)).toEqual(freshSave());
  });
});
