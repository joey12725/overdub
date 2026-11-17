import { describe, expect, test } from 'vitest';
import { HG } from '../../src/audio/hg';
import { isMusicFormulaAllowed, LAYER_PARAMS, listMusicFormulas, MUSIC_ROLES, ROLE_DEFAULTS } from '../../src/audio/formulas';

describe('vendored Harmonograph engine wrapper (MUSIC-01)', () => {
  test('loads the real engine onto the typed wrapper', () => {
    expect(typeof HG.compileChannel).toBe('function');
    expect(HG.catalogue.length).toBeGreaterThanOrEqual(60);
    expect(Object.keys(HG.SCALES)).toContain('Dorian');
    expect(Object.keys(HG.GENRES)).toContain('Lo-fi 80');
  });

  test('compiles notes from its own initial state', () => {
    const s = HG.initialState();
    const notes = HG.compileChannel(s, 0, 0, 1);
    expect(notes.length).toBeGreaterThan(0);
    for (const n of notes) {
      expect(Number.isInteger(n.pitch)).toBe(true);
      expect(n.beat).toBeGreaterThanOrEqual(0);
      expect(n.beat).toBeLessThan(4);
      expect(n.velocity).toBeGreaterThanOrEqual(1);
    }
  });

  test('the engine maps pitch under the chord of the master beat', () => {
    const s = HG.initialState();
    s.progression = [0, 3];
    s.chordRate = 4;
    expect(HG.chordAt(s, 0).degree).toBe(0);
    expect(HG.chordAt(s, 4).degree).toBe(3);
    expect(HG.chordAt(s, 8).degree).toBe(0);
  });
});

describe('listMusicFormulas (authoring helper)', () => {
  const list = listMusicFormulas();

  test('describes every offered formula with roles and parameter ranges', () => {
    expect(list.length).toBeGreaterThan(40);
    for (const f of list) {
      expect(HG.byId[f.id]).toBeDefined();
      expect(f.roles.length).toBeGreaterThan(0);
      for (const r of f.roles) expect(MUSIC_ROLES).toContain(r);
      for (const p of f.params) {
        expect(p.min).toBeLessThanOrEqual(p.default);
        expect(p.max).toBeGreaterThanOrEqual(p.default);
      }
    }
  });

  test('keeps harmony/expression formulas out and groove drum-only', () => {
    const ids = new Set(list.map((f) => f.id));
    for (const id of ['circlechord', 'extension', 'voicelead', 'spread', 'plr', 'accent', 'crescendo']) expect(ids.has(id)).toBe(false);
    expect(isMusicFormulaAllowed('drums', 'groove')).toBe(true);
    expect(isMusicFormulaAllowed('melody', 'groove')).toBe(false);
    expect(isMusicFormulaAllowed('drums', 'euclid')).toBe(true);
    expect(isMusicFormulaAllowed('bass', 'euclid')).toBe(false);
    expect(isMusicFormulaAllowed('melody', 'fibonacci')).toBe(true);
  });

  test('layer parameter keys never collide with formula parameter keys', () => {
    const formulaKeys = new Set(HG.catalogue.flatMap((f) => f.params.map((p) => p.key)));
    for (const p of LAYER_PARAMS) if (p.key !== 'density') expect(formulaKeys.has(p.key)).toBe(false);
    // 'density' is shared on purpose: it is the groove formula's own density control.
    expect(HG.byId.groove.params.some((p) => p.key === 'density')).toBe(true);
    expect(ROLE_DEFAULTS.melody.rate).toBe(0.5);
  });
});
