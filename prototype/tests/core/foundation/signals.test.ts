import { describe, expect, it } from 'vitest';
import { collectSignalIds, evalSignal, formatSignalExpr, inBeatWindow, isTimedExpr } from '../../../src/core/signals';
import type { SignalExpr } from '../../../src/core/types';

const table = new Map<string, boolean>([
  ['a', true],
  ['b', false],
  ['c', true],
]);

describe('evalSignal', () => {
  it('reads signals; missing ids are false', () => {
    expect(evalSignal({ sig: 'a' }, table, 0)).toBe(true);
    expect(evalSignal({ sig: 'b' }, table, 0)).toBe(false);
    expect(evalSignal({ sig: 'nope' }, table, 0)).toBe(false);
  });

  it('combines with not / and / or / xor / const', () => {
    expect(evalSignal({ not: { sig: 'b' } }, table, 0)).toBe(true);
    expect(evalSignal({ and: [{ sig: 'a' }, { sig: 'c' }] }, table, 0)).toBe(true);
    expect(evalSignal({ and: [{ sig: 'a' }, { sig: 'b' }] }, table, 0)).toBe(false);
    expect(evalSignal({ or: [{ sig: 'b' }, { sig: 'c' }] }, table, 0)).toBe(true);
    expect(evalSignal({ or: [{ sig: 'b' }, { sig: 'x' }] }, table, 0)).toBe(false);
    expect(evalSignal({ and: [] }, table, 0)).toBe(true);
    expect(evalSignal({ or: [] }, table, 0)).toBe(false);
    for (const [p, q, r] of [
      ['a', 'b', true],
      ['a', 'c', false],
      ['b', 'x', false],
    ] as const) {
      expect(evalSignal({ xor: [{ sig: p }, { sig: q }] }, table, 0)).toBe(r);
    }
    expect(evalSignal({ const: true }, table, 0)).toBe(true);
    expect(evalSignal({ const: false }, table, 0)).toBe(false);
  });

  it('beat windows follow the master beat, half-open, with wrap-around', () => {
    const w: SignalExpr = { beat: { every: 4, from: 0, to: 2 } };
    expect(evalSignal(w, table, 0)).toBe(true);
    expect(evalSignal(w, table, 1.999)).toBe(true);
    expect(evalSignal(w, table, 2)).toBe(false);
    expect(evalSignal(w, table, 3.5)).toBe(false);
    expect(evalSignal(w, table, 4)).toBe(true);
    expect(evalSignal(w, table, 9)).toBe(true);
    const wrap: SignalExpr = { beat: { every: 4, from: 3, to: 1 } };
    expect([0, 0.5, 1, 2, 3, 3.5, 7.25].map((b) => evalSignal(wrap, table, b))).toEqual([true, true, false, false, true, true, true]);
    expect(inBeatWindow(5, 4, 1, 1)).toBe(false);
    expect(inBeatWindow(5, 0, 0, 1)).toBe(false);
    expect(inBeatWindow(5, 4, 0, 4)).toBe(true);
    expect(inBeatWindow(-1, 4, 3, 4)).toBe(true); // negative beats wrap like positive ones
    expect(inBeatWindow(2.5, 4, -1, 1)).toBe(false);
    expect(inBeatWindow(3.5, 4, -1, 1)).toBe(true);
  });

  it('composes timed and signal logic (a laser that fires on beats 0-1 while a switch is off)', () => {
    const laser: SignalExpr = { and: [{ not: { sig: 'sw' } }, { beat: { every: 2, from: 0, to: 1 } }] };
    const t = new Map<string, boolean>();
    expect(evalSignal(laser, t, 0.5)).toBe(true);
    expect(evalSignal(laser, t, 1.5)).toBe(false);
    t.set('sw', true);
    expect(evalSignal(laser, t, 0.5)).toBe(false);
  });
});

describe('introspection', () => {
  const e: SignalExpr = {
    or: [{ and: [{ sig: 'door' }, { not: { sig: 'plate' } }] }, { xor: [{ sig: 'door' }, { sig: 'core' }] }, { beat: { every: 4, from: 0, to: 2 } }, { const: true }],
  };

  it('collects every referenced id once', () => {
    expect([...collectSignalIds(e)]).toEqual(['door', 'plate', 'core']);
    const s = new Set(['x']);
    collectSignalIds({ sig: 'y' }, s);
    expect([...s]).toEqual(['x', 'y']);
  });

  it('detects beat-timed expressions and formats readably', () => {
    expect(isTimedExpr(e)).toBe(true);
    expect(isTimedExpr({ not: { sig: 'a' } })).toBe(false);
    expect(formatSignalExpr(e)).toBe('(door & !plate) | (door ^ core) | beat%4∈[0,2) | true');
  });
});
