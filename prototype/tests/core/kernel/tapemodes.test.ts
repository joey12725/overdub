/**
 * Kernel: end-of-tape behaviour against a world that keeps going (TEST-25, TEST-26, PLAY-05/06).
 */
import { describe, expect, it } from 'vitest';
import type { EndMode, LevelDef, Tape } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { eventsOf, pathTape, resolve } from '../../helpers/script';

/** 1 bar of recording, horizon 2 bars: a 2x tape traverses four times (Scenario G). */
const level = (): LevelDef =>
  makeLevel({
    speeds: [0.5, 1, 2],
    bars: 1,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'switch', id: 'sw', x: 5.5, y: 1.5 },
      // Never fires inside the horizon; four hit points so it can take more than one swing.
      { kind: 'enemy', id: 't1', type: 'turret', x: 6.8, y: 2.5, hp: 4, beat: { every: 1000, offset: 999 } },
    ],
  });

function shortTape(endMode: EndMode): Tape {
  return pathTape({
    index: 0,
    speed: 2,
    endMode,
    ticks: 120,
    path: [
      { tick: 0, x: 2.5, y: 5.5 },
      { tick: 60, x: 5.5, y: 2.5 },
    ],
    events: [
      { tick: 70, kind: 'interact' },
      { tick: 80, kind: 'light', dir: 0 },
    ],
  });
}

const TRAV = 120 * 2; // master substeps per traversal of a 2x tape of 120 ticks

describe('repeat (TEST-25)', () => {
  const res = resolve(level(), [shortTape('repeat')]);

  it('TEST-25: the self cuts straight back to its start and plays again; the encounter is not reset', () => {
    expect(res.horizonSubs).toBe(4 * TRAV);
    const wraps = eventsOf(res.events, 'tapeWrap', { tape: 0 });
    expect(wraps.map((e) => e.sub + 1)).toEqual([TRAV, 2 * TRAV, 3 * TRAV]);
    const at = (sub: number) => res.frames.find((f) => f.sub === sub)!.actors[0];
    for (let k = 1; k <= 3; k++) {
      expect(at(k * TRAV - 4).x).toBeCloseTo(5.5, 5); // just before the cut: at the far end
      expect([at(k * TRAV).x, at(k * TRAV).y]).toEqual([2.5, 5.5]); // cut, not a walk back
      expect(at(k * TRAV).phase.traversal).toBe(k);
    }
    // Every traversal's events fire again against the current world: the switch toggles each time.
    expect(eventsOf(res.events, 'interact', { id: 'sw' }).map((e) => e.detail)).toEqual(['on', 'off', 'on', 'off']);
    // The turret is not revived between traversals: 2 + 2 damage kills it on the second pass, and
    // the later passes' swings find nothing.
    const hits = eventsOf(res.events, 'hit', { id: 't1' });
    expect(hits).toHaveLength(2);
    expect(eventsOf(res.events, 'kill', { id: 't1' })).toHaveLength(1);
    expect(eventsOf(res.events, 'whiff', { tape: 0 })).toHaveLength(2);
    expect(res.frames[res.frames.length - 1].enemies[0].alive).toBe(false);
  });
});

describe('reverse (TEST-26)', () => {
  const res = resolve(level(), [shortTape('reverse')]);

  it('TEST-26: recorded actions run backward; the world keeps evolving forward', () => {
    const turns = eventsOf(res.events, 'tapeTurn', { tape: 0 });
    expect(turns.map((e) => [e.sub + 1, e.detail])).toEqual([
      [TRAV, 'backward'],
      [2 * TRAV, 'forward'],
      [3 * TRAV, 'backward'],
    ]);
    // The backward pass retraces the path: mirrored around the turn.
    const bySub = new Map(res.frames.map((f) => [f.sub, f.actors[0]]));
    for (let d = 4; d <= TRAV; d += 4) {
      const a = bySub.get(TRAV - d)!;
      const b = bySub.get(TRAV + d)!;
      expect(b.x).toBeCloseTo(a.x, 5);
      expect(b.y).toBeCloseTo(a.y, 5);
    }
    expect(bySub.get(TRAV + 4)!.phase.dir).toBe(-1);
    // The switch is moved back on the backward pass (on → off), then on again, then off again.
    const toggles = eventsOf(res.events, 'interact', { id: 'sw' });
    expect(toggles.map((e) => e.detail)).toEqual(['on', 'off', 'on', 'off']);
    // The backward crossing of tick 70 happens (120 - 70) local ticks after the turn.
    expect(toggles[1].sub).toBe(TRAV + 50 * 2);
    // A backward swing is a fresh swing: it hurts again (it never heals).
    const hits = eventsOf(res.events, 'hit', { id: 't1' });
    expect(hits).toHaveLength(2);
    expect(hits[1].sub).toBeGreaterThan(TRAV);
    expect(eventsOf(res.events, 'kill', { id: 't1' })).toHaveLength(1);
  });

  it('a stop tape holds its final pose and stays a physical, living survivor', () => {
    const r = resolve(level(), [shortTape('stop')]);
    expect(eventsOf(r.events, 'tapeEnd', { tape: 0 }).map((e) => e.sub + 1)).toEqual([TRAV]);
    const last = r.frames[r.frames.length - 1].actors[0];
    expect([last.x, last.y]).toEqual([5.5, 2.5]);
    expect(last.phase).toEqual({ tick: 120, dir: 0, traversal: 1, ended: true });
    expect(eventsOf(r.events, 'interact')).toHaveLength(1);
    expect(r.outcome.survivors).toEqual([0]);
  });
});
