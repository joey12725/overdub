/**
 * Boss memory (BOSS-01, BOSS-02): what buildBossMemory records from committed tapes and how
 * recallCandidates reads it. bpm 120 → 30 local ticks per beat at 1×.
 */
import { describe, expect, it } from 'vitest';
import { BOSS_DWELL_BEATS, buildBossMemory, recallCandidates } from '../../../src/core/bossMemory';
import { buildBossMemory as exported } from '../../../src/core/index';
import { makeLevel } from '../../helpers/levels';
import { pathTape } from '../../helpers/script';

const level = makeLevel({ speeds: [1, 2], bars: 1, horizonBars: 2, start: { x: 2, y: 2 } });

describe('buildBossMemory', () => {
  it('is the module the core index exports', () => {
    expect(exported).toBe(buildBossMemory);
  });

  it('samples every committed tape at each whole master beat, in cassette order', () => {
    const b = pathTape({ index: 1, speed: 1, ticks: 120, path: [{ tick: 0, x: 2, y: 2 }, { tick: 60, x: 8, y: 2 }] });
    const a = pathTape({ index: 0, speed: 2, ticks: 120, path: [{ tick: 0, x: 2, y: 2 }] });
    const mem = buildBossMemory(level, [b, a]);
    expect(mem.observed.map((o) => [o.tape, o.speed])).toEqual([
      [0, 2],
      [1, 1],
    ]);
    // Horizon 2 bars = 8 beats → samples for beats 0..8.
    expect(mem.observed[1].samples).toHaveLength(9);
    expect(mem.observed[1].samples[1]).toEqual({ beat: 1, x: 5, y: 2 });
    expect(mem.observed[1].samples[8]).toEqual({ beat: 8, x: 8, y: 2 }); // a 'stop' tape holds its end
  });

  it('records attack attempts (light, heavy, ranged) with end behaviour applied, never dodges or interacts', () => {
    const t = pathTape({
      index: 0,
      speed: 1,
      ticks: 120,
      endMode: 'repeat',
      path: [{ tick: 0, x: 2, y: 2 }, { tick: 120, x: 6, y: 2 }],
      events: [
        { tick: 30, kind: 'light', dir: 0 },
        { tick: 45, kind: 'dodge', dir: 0 },
        { tick: 60, kind: 'interact', dir: 0 },
        { tick: 90, kind: 'heavy', dir: 0 },
      ],
    });
    const mem = buildBossMemory(level, [t]);
    // One traversal = 4 beats; the 8-beat horizon replays it once.
    expect(mem.observed[0].actions!.map((a) => [a.beat, a.kind])).toEqual([
      [1, 'light'],
      [3, 'heavy'],
      [5, 'light'],
      [7, 'heavy'],
    ]);
    expect(mem.observed[0].actions![0]).toMatchObject({ x: 3, y: 2 });
    const rev = buildBossMemory(level, [{ ...t, endMode: 'reverse' }]);
    // Backward pass: the heavy (tick 90) fires again at beat 4 + 1, the light at beat 4 + 3.
    expect(rev.observed[0].actions!.map((a) => [a.beat, a.kind])).toEqual([
      [1, 'light'],
      [3, 'heavy'],
      [5, 'heavy'],
      [7, 'light'],
    ]);
  });

  it('is plain data: building it twice gives equal memories', () => {
    const t = pathTape({ index: 2, speed: 1, ticks: 120, path: [{ tick: 0, x: 2, y: 2 }], events: [{ tick: 10, kind: 'light' }] });
    expect(buildBossMemory(level, [t])).toEqual(structuredClone(buildBossMemory(level, [t])));
  });
});

describe('recallCandidates', () => {
  it('finds dwells of at least BOSS_DWELL_BEATS beats; a long wait is one dwell', () => {
    // Moves for 2 beats, waits 2 beats (a dwell), runs, then waits out the horizon (another one).
    const t = pathTape({
      index: 0,
      speed: 1,
      ticks: 240,
      path: [
        { tick: 0, x: 2, y: 2 },
        { tick: 60, x: 8, y: 2 },
        { tick: 120, x: 8, y: 2 },
        { tick: 150, x: 8, y: 7 },
      ],
    });
    const lvl = makeLevel({ speeds: [1], bars: 2, horizonBars: 3, start: { x: 2, y: 2 } });
    const c = recallCandidates(buildBossMemory(lvl, [t]));
    expect(c.map((x) => [x.reason, x.beat, x.lastBeat, x.x, x.y])).toEqual([
      ['dwell', 2, 4, 8, 2],
      ['dwell', 5, 12, 8, 7],
    ]);
    expect(BOSS_DWELL_BEATS).toBe(2);
  });

  it('turns attacks into moments on the nearest whole beat and orders by beat, cassette, attack first', () => {
    const a = pathTape({ index: 1, speed: 1, ticks: 240, path: [{ tick: 0, x: 2, y: 2 }, { tick: 240, x: 10, y: 2 }], events: [{ tick: 50, kind: 'heavy' }] });
    const b = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 2, y: 2 }, { tick: 240, x: 2, y: 8 }], events: [{ tick: 64, kind: 'light' }] });
    const lvl = makeLevel({ speeds: [1], bars: 2, start: { x: 2, y: 2 } });
    const c = recallCandidates(buildBossMemory(lvl, [a, b]));
    expect(c.map((x) => [x.tape, x.reason, x.beat])).toEqual([
      [0, 'attack', 2],
      [1, 'attack', 2],
    ]);
  });

  it('no memory means no moments', () => {
    expect(recallCandidates(undefined)).toEqual([]);
    expect(recallCandidates({ observed: [] })).toEqual([]);
  });
});
