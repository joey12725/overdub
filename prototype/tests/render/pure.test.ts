import { describe, expect, it } from 'vitest';
import type { LevelDef, Theme } from '../../src/core/types';
import { PALETTES, hsl, paletteFor } from '../../src/render/palettes';
import { computeLayout, countFloorKinds, WALL_CUT_HEIGHT } from '../../src/render/env/layout';
import { BEAT_ACCENT, MECH_ACCENTS, buildAccentMap, exprAccent, exprSignals, signalAccent } from '../../src/render/mechs/accent';
import { planScatter } from '../../src/render/env/scatter';

const THEMES: Theme[] = ['upper', 'mid', 'lower', 'core'];
const PALETTE_KEYS = [
  'background', 'fog', 'floor', 'floorAlt', 'wall', 'wallTop', 'metal', 'trim', 'hazard', 'foliage',
  'neonA', 'neonB', 'neonC', 'graffiti', 'ink', 'keyLight', 'keyIntensity', 'ambient', 'ambientIntensity', 'bloom',
] as const;
const COLOR_KEYS = PALETTE_KEYS.filter((k) => !['keyIntensity', 'ambientIntensity', 'bloom'].includes(k));

describe('palettes', () => {
  it('defines a complete ThemePalette for every Theme', () => {
    for (const theme of THEMES) {
      const p = PALETTES[theme];
      expect(p, theme).toBeDefined();
      expect(p.theme).toBe(theme);
      expect(paletteFor(theme)).toBe(p);
      for (const key of PALETTE_KEYS) {
        const v = p[key];
        expect(typeof v, `${theme}.${key}`).toBe('number');
        expect(Number.isFinite(v), `${theme}.${key}`).toBe(true);
      }
      for (const key of COLOR_KEYS) {
        const v = p[key] as number;
        expect(Number.isInteger(v) && v >= 0 && v <= 0xffffff, `${theme}.${key}`).toBe(true);
      }
      expect(p.keyIntensity).toBeGreaterThan(0);
      expect(p.ambientIntensity).toBeGreaterThan(0);
      expect(p.bloom).toBeGreaterThanOrEqual(0);
      expect(p.bloom).toBeLessThanOrEqual(2);
    }
  });

  it('upper levels cast no purple light (chapter 18 lighting correction)', () => {
    const up = PALETTES.upper;
    for (const key of ['keyLight', 'ambient', 'fill'] as const) {
      const { h, s } = hsl(up[key]);
      const purple = h >= 250 && h <= 330 && s > 0.15;
      expect(purple, `upper.${key} hue ${h.toFixed(0)}`).toBe(false);
    }
    // ...while graffiti keeps its pink / purple (ART-03).
    const g = hsl(up.graffiti);
    expect(g.h > 280 || g.h < 20).toBe(true);
  });

  it('gets darker with depth while the floor stays readable (WORLD-04)', () => {
    const lum = (c: number) => hsl(c).l;
    expect(lum(PALETTES.upper.background)).toBeGreaterThan(lum(PALETTES.lower.background));
    expect(lum(PALETTES.lower.floor)).toBeGreaterThan(lum(PALETTES.lower.background) + 0.25);
    expect(lum(PALETTES.core.floor)).toBeGreaterThan(lum(PALETTES.core.background) + 0.25);
    expect(PALETTES.core.accent).not.toBe(PALETTES.lower.accent);
  });
});

const SMALL_MAP = [
  '#######',
  '#..:,~#',
  '#.=...#',
  '#.....#',
  '###.###',
  '  #.#  ',
  '  ###  ',
];

describe('level layout', () => {
  const layout = computeLayout({ id: 'test-small', theme: 'upper', map: SMALL_MAP });

  it('counts one placement per map tile of each kind', () => {
    const walls = SMALL_MAP.join('').split('').filter((c) => c === '#').length;
    const floors = SMALL_MAP.join('').split('').filter((c) => '.:,~='.includes(c)).length;
    expect(layout.walls.length).toBe(walls);
    expect(layout.floors.length).toBe(floors);
    expect(layout.barriers.length).toBe(1);
    const kinds = countFloorKinds(layout);
    expect(kinds.grate).toBe(1);
    expect(kinds.overgrown).toBe(1);
    expect(kinds.rune).toBe(1);
    expect(kinds.solid + kinds.alt + kinds.cracked).toBe(floors - 3);
  });

  it('puts a cliff skirt under every tile that borders the void and nowhere else', () => {
    const at = (c: number, r: number) => (r >= 0 && r < SMALL_MAP.length && c >= 0 && c < SMALL_MAP[r].length ? SMALL_MAP[r][c] : ' ');
    let expected = 0;
    for (let r = 0; r < SMALL_MAP.length; r++) {
      for (let c = 0; c < SMALL_MAP[r].length; c++) {
        if (at(c, r) === ' ') continue;
        if ([at(c + 1, r), at(c - 1, r), at(c, r + 1), at(c, r - 1)].includes(' ')) expected++;
      }
    }
    expect(layout.cliffs.length).toBe(expected);
    expect(layout.bounds).toMatchObject({ minX: 0, minZ: 0, maxX: 7, maxZ: 7 });
    expect(layout.bounds.minY).toBeLessThan(-1);
  });

  it('cuts walls that would hide floor behind them, keeps back walls tall (chapter 16 cutaway)', () => {
    const wall = (c: number, r: number) => layout.walls.find((w) => w.c === c && w.r === r)!;
    // back walls (row 0 / column 0) have no floor behind them
    expect(wall(3, 0).cut).toBe(false);
    expect(wall(0, 2).cut).toBe(false);
    expect(wall(3, 0).height).toBeGreaterThan(1);
    // the front wall row 4 and right column hide floor behind them from the +X/+Z camera
    expect(wall(1, 4).cut).toBe(true);
    expect(wall(6, 2).cut).toBe(true);
    expect(wall(6, 2).height).toBe(WALL_CUT_HEIGHT);
  });

  it('is deterministic per level id', () => {
    const again = computeLayout({ id: 'test-small', theme: 'upper', map: SMALL_MAP });
    expect(again.floors).toEqual(layout.floors);
    expect(again.walls).toEqual(layout.walls);
  });

  it('scatters ambient dressing deterministically and never onto entity tiles', () => {
    const level = {
      id: 'scatter-test',
      theme: 'upper' as Theme,
      map: SMALL_MAP,
      start: { x: 1.5, y: 1.5 },
      entities: [{ kind: 'switch', id: 's1', x: 4.5, y: 3.5 }],
    } as unknown as LevelDef;
    const a = planScatter(level, computeLayout(level));
    const b = planScatter(level, computeLayout(level));
    expect(a).toEqual(b);
    for (const item of a) {
      expect(Math.floor(item.x) === 4 && Math.floor(item.y) === 3).toBe(false);
      expect(Math.floor(item.x) === 1 && Math.floor(item.y) === 1).toBe(false);
    }
  });
});

describe('mechanism accents', () => {
  it('maps a signal id to the same accent every time', () => {
    for (const id of ['s1', 'plateA', 'dead:grunt2', 'core-north']) {
      expect(signalAccent(id)).toBe(signalAccent(id));
      expect(MECH_ACCENTS).toContain(signalAccent(id));
    }
  });

  it('gives a door the accent of the switch that opens it', () => {
    const entities = [
      { kind: 'switch', id: 'lever', x: 1, y: 1 },
      { kind: 'plate', id: 'pad', c: 2, r: 2 },
      { kind: 'door', id: 'gate', cells: [{ c: 3, r: 3 }], openWhen: { and: [{ sig: 'lever' }, { not: { sig: 'pad' } }] } },
    ] as LevelDef['entities'];
    const map = buildAccentMap({ entities });
    expect(exprAccent({ and: [{ sig: 'lever' }, { not: { sig: 'pad' } }] }, map)).toBe(map.get('lever'));
    expect(map.get('lever')).not.toBe(map.get('pad'));
    expect(buildAccentMap({ entities })).toEqual(map);
  });

  it('lists referenced signals in order without duplicates', () => {
    expect(exprSignals({ or: [{ sig: 'a' }, { xor: [{ sig: 'b' }, { sig: 'a' }] }, { const: true }] })).toEqual(['a', 'b']);
    expect(exprAccent({ beat: { every: 4, from: 0, to: 2 } })).toBe(BEAT_ACCENT);
  });
});
