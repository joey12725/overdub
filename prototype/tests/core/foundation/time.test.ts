import { describe, expect, it } from 'vitest';
import {
  ALL_END_MODES,
  beatToSub,
  collectBoundaries,
  collectEventCrossings,
  eventCrossings,
  horizonSubs,
  localTickToSub,
  spanBars,
  subToBeat,
  subToLocalTick,
  subsPerBeat,
  subsPerLocalTick,
  tapePhaseAt,
  tapeTicks,
  ticksPerBeat,
  traversalSubs,
  type EventCrossing,
} from '../../../src/core/time';
import { ALL_SPEEDS, SUB_HZ, type EndMode, type Tape, type TapeEvent, type TapeSpeed } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';

function ev(tick: number, kind: TapeEvent['kind'] = 'light'): TapeEvent {
  return { tick, kind, dir: 0, x: 0, y: 0, vx: 0, vy: 0 };
}

function mkTape(speed: TapeSpeed, endMode: EndMode, ticks: number, events: TapeEvent[] = []): Tape {
  return {
    index: 0,
    speed,
    endMode,
    ticks,
    pos: new Float32Array((ticks + 1) * 2),
    facing: new Float32Array(ticks + 1),
    anim: new Uint8Array(ticks + 1),
    events,
  };
}

describe('level clock', () => {
  it('converts beats, ticks and substeps at bpm 120', () => {
    const level = makeLevel({ bpm: 120, bars: 4, horizonBars: 8 });
    expect(ticksPerBeat(level)).toBe(30);
    expect(subsPerBeat(level)).toBe(120);
    expect(tapeTicks(level)).toBe(480);
    expect(horizonSubs(level)).toBe(8 * 4 * 120);
    expect(subToBeat(level, 240)).toBe(2);
    expect(beatToSub(level, 2.5)).toBe(300);
    expect(subToBeat(level, beatToSub(level, 7.25))).toBe(7.25);
  });

  it('maps local ticks to substeps for every speed (8, 4, 2, 1 subs per tick)', () => {
    expect(ALL_SPEEDS.map((s) => subsPerLocalTick(s))).toEqual([8, 4, 2, 1]);
    for (const s of ALL_SPEEDS) {
      expect(localTickToSub(s, 60)).toBe(60 * subsPerLocalTick(s));
      expect(subToLocalTick(s, localTickToSub(s, 37))).toBe(37);
    }
  });

  it('TEST-01: the local recording allowance is identical at every speed', () => {
    const level = makeLevel({ bpm: 80, bars: 5 });
    // 5 bars at 80 bpm = 20 beats = 15 local seconds = 900 ticks, regardless of speed.
    expect(tapeTicks(level)).toBe(900);
    for (const s of ALL_SPEEDS) {
      const t = mkTape(s, 'stop', tapeTicks(level));
      expect(t.ticks).toBe(900);
    }
  });

  it('TEST-02 groundwork: a 2x tape\'s 15 local seconds occupy 7.5 master seconds (never stretched)', () => {
    const level = makeLevel({ bpm: 80, bars: 5, horizonBars: 10 });
    const T = tapeTicks(level);
    const expectSeconds: Record<number, number> = { 0.5: 30, 1: 15, 2: 7.5, 4: 3.75 };
    for (const s of ALL_SPEEDS) {
      const subs = traversalSubs(mkTape(s, 'stop', T));
      expect(subs / SUB_HZ).toBe(expectSeconds[s]);
      expect(spanBars(level, s)).toBe(5 / s);
      // The horizon does not change a traversal's length.
      expect(traversalSubs(mkTape(s, 'repeat', T))).toBe(subs);
    }
    // A 2x tape's tick k lands at master time k / 60 / 2 seconds: the landing keeps its master beat.
    expect(localTickToSub(2, 450) / SUB_HZ).toBe(3.75);
  });
});

describe('tapePhaseAt', () => {
  const T = 100;

  it('stop: forward, then holds the last tick, ended', () => {
    for (const s of ALL_SPEEDS) {
      const tape = mkTape(s, 'stop', T);
      const m = subsPerLocalTick(s);
      expect(tapePhaseAt(tape, 0)).toEqual({ tick: 0, dir: 1, traversal: 0, ended: false });
      expect(tapePhaseAt(tape, 50 * m)).toEqual({ tick: 50, dir: 1, traversal: 0, ended: false });
      expect(tapePhaseAt(tape, T * m - 1).tick).toBeCloseTo(T - s / 4, 12);
      expect(tapePhaseAt(tape, T * m)).toEqual({ tick: T, dir: 0, traversal: 1, ended: true });
      expect(tapePhaseAt(tape, 10 * T * m)).toEqual({ tick: T, dir: 0, traversal: 1, ended: true });
    }
  });

  it('repeat: cuts straight back to tick 0 each traversal', () => {
    for (const s of ALL_SPEEDS) {
      const tape = mkTape(s, 'repeat', T);
      const m = subsPerLocalTick(s);
      expect(tapePhaseAt(tape, T * m)).toEqual({ tick: 0, dir: 1, traversal: 1, ended: false });
      expect(tapePhaseAt(tape, (2 * T + 30) * m)).toEqual({ tick: 30, dir: 1, traversal: 2, ended: false });
      expect(tapePhaseAt(tape, 2 * T * m - 1).tick).toBeCloseTo(T - s / 4, 12);
    }
  });

  it('reverse: ping-pongs continuously', () => {
    for (const s of ALL_SPEEDS) {
      const tape = mkTape(s, 'reverse', T);
      const m = subsPerLocalTick(s);
      expect(tapePhaseAt(tape, T * m)).toEqual({ tick: T, dir: -1, traversal: 1, ended: false });
      expect(tapePhaseAt(tape, (T + 30) * m)).toEqual({ tick: 70, dir: -1, traversal: 1, ended: false });
      expect(tapePhaseAt(tape, 2 * T * m)).toEqual({ tick: 0, dir: 1, traversal: 2, ended: false });
      expect(tapePhaseAt(tape, (3 * T + 1) * m)).toEqual({ tick: T - 1, dir: -1, traversal: 3, ended: false });
      // Continuity: consecutive substeps never move the playhead more than one sub's worth of ticks.
      let prev = tapePhaseAt(tape, 0).tick;
      for (let sub = 1; sub < 5 * T * m; sub++) {
        const p = tapePhaseAt(tape, sub).tick;
        expect(Math.abs(p - prev)).toBeLessThanOrEqual(s / 4 + 1e-12);
        prev = p;
      }
    }
  });

  it('treats negative subs as sub 0 and zero-length tapes as ended', () => {
    expect(tapePhaseAt(mkTape(1, 'repeat', 10), -5)).toEqual({ tick: 0, dir: 1, traversal: 0, ended: false });
    expect(tapePhaseAt(mkTape(1, 'reverse', 0), 50)).toEqual({ tick: 0, dir: 0, traversal: 0, ended: true });
  });
});

/**
 * Independent oracle for event crossings: walk every substep, read the playhead with tapePhaseAt and
 * record which integer ticks it visits (with the direction of arrival). Repeat wraps visit both the
 * end (tick T) and the start (tick 0) of the next traversal at the cut instant.
 */
function oracle(tape: Tape, horizon: number): { sub: number; index: number; dir: 1 | -1; traversal: number }[] {
  const T = tape.ticks;
  const out: { sub: number; index: number; dir: 1 | -1; traversal: number }[] = [];
  const visit = (sub: number, tick: number, dir: 1 | -1, traversal: number): void => {
    tape.events.forEach((e, index) => {
      if (e.tick === tick) out.push({ sub, index, dir, traversal });
    });
  };
  for (let s = 0; s < horizon; s++) {
    const p = tapePhaseAt(tape, s);
    const prev = s > 0 ? tapePhaseAt(tape, s - 1) : null;
    if (tape.endMode === 'repeat' && prev && p.traversal > prev.traversal) {
      visit(s, T, 1, prev.traversal);
      visit(s, 0, 1, p.traversal);
    } else if (tape.endMode === 'stop' && p.ended) {
      if (prev && !prev.ended) visit(s, T, 1, 0);
    } else if (Number.isInteger(p.tick)) {
      const dir: 1 | -1 = prev ? (p.tick - prev.tick >= 0 ? 1 : -1) : 1;
      visit(s, p.tick, dir, prev ? prev.traversal : 0);
    }
  }
  out.sort((a, b) => a.sub - b.sub || a.traversal - b.traversal || a.index - b.index);
  return out;
}

function simplify(c: EventCrossing[]): { sub: number; index: number; dir: 1 | -1; traversal: number }[] {
  return c.map(({ sub, index, dir, traversal }) => ({ sub, index, dir, traversal }));
}

describe('event crossings', () => {
  const T = 12;
  // Events on tick 0, interior ticks, the last recorded tick (T-1), the end sample (T), and a duplicate tick.
  const events = [ev(0), ev(1, 'dodge'), ev(5, 'interact'), ev(5, 'ranged'), ev(T - 1, 'heavy'), ev(T, 'ability')];

  for (const speed of ALL_SPEEDS) {
    for (const mode of ALL_END_MODES) {
      it(`${speed}x ${mode}: matches the substep oracle for any partition of time`, () => {
        const tape = mkTape(speed, mode, T, events);
        const horizon = traversalSubs(tape) * 5 + 3;
        const expected = oracle(tape, horizon);

        // Whole range in one query.
        expect(simplify(eventCrossings(tape, 0, horizon))).toEqual(expected);

        // Every fixed step size, including 1-substep stepping as the kernel does.
        for (const step of [1, 2, 3, 4, 7, 8, 13, 48]) {
          const acc: EventCrossing[] = [];
          for (let a = 0; a < horizon; a += step) collectEventCrossings(tape, a, Math.min(horizon, a + step), acc);
          expect(simplify(acc)).toEqual(expected);
        }

        // Irregular partition from a fixed LCG (deterministic).
        let seed = 12345;
        const acc: EventCrossing[] = [];
        for (let a = 0; a < horizon; ) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          const b = Math.min(horizon, a + 1 + (seed % 17));
          collectEventCrossings(tape, a, b, acc);
          a = b;
        }
        expect(simplify(acc)).toEqual(expected);
      });
    }
  }

  it('fires a stop tape\'s events exactly once, including tick 0 and the end tick', () => {
    for (const speed of ALL_SPEEDS) {
      const tape = mkTape(speed, 'stop', T, events);
      const all = eventCrossings(tape, 0, traversalSubs(tape) * 10);
      expect(all.map((c) => c.index)).toEqual([0, 1, 2, 3, 4, 5]);
      expect(all.every((c) => c.dir === 1 && c.traversal === 0)).toBe(true);
      expect(all[5].sub).toBe(traversalSubs(tape));
    }
  });

  it('repeat: tick-0 events fire again each traversal; the cut fires end-of-tape then start events', () => {
    const tape = mkTape(1, 'repeat', T, [ev(0), ev(T)]);
    const m = subsPerLocalTick(1);
    const all = eventCrossings(tape, 0, 3 * T * m + 1);
    expect(all.map((c) => [c.sub, c.index, c.traversal])).toEqual([
      [0, 0, 0],
      [T * m, 1, 0],
      [T * m, 0, 1],
      [2 * T * m, 1, 1],
      [2 * T * m, 0, 2],
      [3 * T * m, 1, 2],
      [3 * T * m, 0, 3],
    ]);
  });

  it('reverse: events fire again on the backward pass with dir -1; turn ticks fire once per turn', () => {
    const tape = mkTape(2, 'reverse', T, [ev(0), ev(4), ev(T)]);
    const m = subsPerLocalTick(2);
    const all = eventCrossings(tape, 0, 4 * T * m + 1);
    expect(all.map((c) => [c.sub / m, c.index, c.dir, c.traversal])).toEqual([
      [0, 0, 1, 0],
      [4, 1, 1, 0],
      [T, 2, 1, 0], // arrives at the far end going forward: fires once
      [2 * T - 4, 1, -1, 1], // backward pass
      [2 * T, 0, -1, 1], // arrives back at tick 0 going backward: fires once
      [2 * T + 4, 1, 1, 2],
      [3 * T, 2, 1, 2],
      [4 * T - 4, 1, -1, 3],
      [4 * T, 0, -1, 3],
    ]);
  });

  it('ignores events outside the tape and empty or inverted intervals', () => {
    const tape = mkTape(1, 'repeat', T, [ev(-1), ev(T + 1), ev(3)]);
    expect(eventCrossings(tape, 0, 1000).every((c) => c.index === 2)).toBe(true);
    expect(eventCrossings(tape, 12, 12)).toEqual([]);
    expect(eventCrossings(tape, 20, 10)).toEqual([]);
  });

  it('a live tick-i event fires in the first substep of tick i (half-open intervals)', () => {
    for (const speed of ALL_SPEEDS) {
      const tape = mkTape(speed, 'stop', T, [ev(7)]);
      const m = subsPerLocalTick(speed);
      expect(eventCrossings(tape, 7 * m, 7 * m + 1)).toHaveLength(1);
      expect(eventCrossings(tape, 6 * m, 7 * m)).toHaveLength(0);
    }
  });

  it('handles unsorted events and keeps a deterministic order', () => {
    const tape = mkTape(1, 'stop', T, [ev(9), ev(2), ev(2)]);
    expect(eventCrossings(tape, 0, 100).map((c) => c.index)).toEqual([1, 2, 0]);
  });

  it('zero-length tapes fire tick-0 events once', () => {
    for (const mode of ALL_END_MODES) {
      const tape = mkTape(1, mode, 0, [ev(0)]);
      expect(eventCrossings(tape, 0, 1000)).toHaveLength(1);
    }
  });
});

describe('boundaries', () => {
  it('stop ends once, repeat wraps, reverse turns with alternating direction', () => {
    const T = 10;
    for (const speed of ALL_SPEEDS) {
      const m = subsPerLocalTick(speed);
      const H = 4 * T * m + 1;
      expect(collectBoundaries(mkTape(speed, 'stop', T), 0, H)).toEqual([{ kind: 'end', sub: T * m, traversal: 1, dir: 0 }]);
      expect(collectBoundaries(mkTape(speed, 'repeat', T), 0, H).map((b) => [b.kind, b.sub, b.traversal])).toEqual([
        ['wrap', T * m, 1],
        ['wrap', 2 * T * m, 2],
        ['wrap', 3 * T * m, 3],
        ['wrap', 4 * T * m, 4],
      ]);
      expect(collectBoundaries(mkTape(speed, 'reverse', T), 0, H).map((b) => b.dir)).toEqual([-1, 1, -1, 1]);
      // Partitioned queries find each boundary once.
      const acc = [];
      for (let a = 0; a < H; a += 3) acc.push(...collectBoundaries(mkTape(speed, 'repeat', T), a, Math.min(H, a + 3)));
      expect(acc).toHaveLength(4);
      expect(collectBoundaries(mkTape(speed, 'repeat', T), 0, T * m)).toEqual([]);
    }
  });
});
