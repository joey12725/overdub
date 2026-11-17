import { describe, expect, it } from 'vitest';
import { Grid } from '../../../src/core/grid';
import { horizonSubs, tapeTicks } from '../../../src/core/time';
import { makeLevel } from '../../helpers/levels';
import { baseLoadout } from '../../helpers/loadout';

describe('test helpers', () => {
  it('makeLevel builds a valid minimal level with a walkable start', () => {
    const level = makeLevel();
    expect(level.bpm).toBe(120);
    expect(level.bars).toBe(4);
    expect(level.horizonBars).toBe(8);
    expect(level.music.tracks).toHaveLength(4);
    expect(Number.isInteger(3600 / level.bpm)).toBe(true);
    const g = Grid.fromLevel(level);
    expect(g.isWalkable(Math.floor(level.start.x), Math.floor(level.start.y))).toBe(true);
    expect(tapeTicks(level)).toBe(480);
    expect(horizonSubs(level)).toBe(3840);
  });

  it('makeLevel honours overrides and derives start and horizon', () => {
    const level = makeLevel({ map: ['####', '#..#', '####'], speeds: [1, 2], bars: 2 });
    expect(level.start).toEqual({ x: 1.5, y: 1.5 });
    expect(level.horizonBars).toBe(2);
    expect(makeLevel({ horizonBars: 3 }).horizonBars).toBe(3);
  });

  it('baseLoadout is neutral and patchable without sharing state', () => {
    const a = baseLoadout();
    expect(a.mods.moveSpeed).toBe(1);
    expect(a.melee.light.windup).toBe(6);
    expect(a.ranged.archetype).toBe('missile');
    const b = baseLoadout({ mods: { damage: 2 }, melee: { light: { windup: 3, active: 4, recover: 10, impact: 1.2, moveMul: 0.5 } } });
    expect(b.mods.damage).toBe(2);
    expect(b.melee.light.windup).toBe(3);
    a.melee.light.windup = 99;
    expect(baseLoadout().melee.light.windup).toBe(6);
  });
});
