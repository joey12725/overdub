/**
 * Shielder (Scenario A, AI-05): the shield recharges instantly; only a hit from a DIFFERENT self
 * inside the window after another self popped it does anything. One self alone can never kill it.
 *
 * Timing: bpm 120 → 120 substeps per beat; window SHIELDER_WINDOW_BEATS beats. A 1× light event on
 * tick t connects on substep (t + 6) · 4 (baseline windup 6 ticks).
 */
import { describe, expect, it } from 'vitest';
import { SHIELDER_WINDOW_BEATS } from '../../../src/core/tuning';
import type { ActionKind, EnemyDef, LevelDef, TapeIndex, TapeSpeed } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { eventsOf, frameAt, pathTape, resolve } from '../../helpers/script';

const SPB = 120;
const WINDOW = SHIELDER_WINDOW_BEATS * SPB;

// Asleep so it stands still and never strikes back: the rule under test is the shield alone.
const shielder: EnemyDef = { kind: 'enemy', id: 'sh', type: 'shielder', x: 6, y: 5, wakeWhen: { const: false } };
const level: LevelDef = makeLevel({ speeds: [0.5, 1, 2], bars: 2, start: { x: 4.9, y: 5 }, entities: [shielder] });

/** A self standing beside the shielder (west for A, east for B) swinging at it on the given ticks. */
function striker(index: TapeIndex, ticks: number[], kind: ActionKind = 'light', speed: TapeSpeed = 1) {
  const west = index % 2 === 0;
  const x = west ? 4.9 : 7.1;
  const dir = west ? 0 : Math.PI;
  return pathTape({ index, speed, ticks: 240, path: [{ tick: 0, x, y: 5 }], events: ticks.map((tick) => ({ tick, kind, dir })) });
}

const connect = (tick: number) => (tick + 6) * 4;

describe('shielder (Scenario A)', () => {
  it('the window is a readable fraction-of-a-bar span, stated in beats', () => {
    expect(SHIELDER_WINDOW_BEATS).toBeGreaterThan(0);
    expect(SHIELDER_WINDOW_BEATS).toBeLessThanOrEqual(1);
    expect(WINDOW).toBe(SPB * SHIELDER_WINDOW_BEATS);
  });

  it('one self alone can never hurt it, whatever it swings', () => {
    const lights = resolve(level, [striker(0, [10, 14, 18, 22, 40, 60, 80, 100])]);
    expect(eventsOf(lights.events, 'hit', { id: 'sh' })).toHaveLength(0);
    expect(eventsOf(lights.events, 'clang', { id: 'sh' }).every((c) => c.detail === 'shield')).toBe(true);
    expect(eventsOf(lights.events, 'clang', { id: 'sh' })).toHaveLength(8);
    expect(lights.frames[lights.frames.length - 1].enemies[0]).toMatchObject({ hp: 2, alive: true });
    // A 2× heavy (momentum 4) is no better on its own.
    const heavy = resolve(level, [striker(0, [10, 50, 90, 130, 170], 'heavy', 2)]);
    expect(eventsOf(heavy.events, 'hit', { id: 'sh' })).toHaveLength(0);
    expect(heavy.frames[heavy.frames.length - 1].enemies[0]).toMatchObject({ hp: 2, alive: true });
  });

  it('a hit from a second self inside the window lands; the shield is back at once', () => {
    // A pops on tick 30, B follows 3 ticks later (12 substeps): damage. A swings again right after,
    // still inside the old window: the shield is already back up, so that hit only pops it again.
    const res = resolve(level, [striker(0, [30, 36]), striker(1, [33])]);
    expect(eventsOf(res.events, 'hit', { id: 'sh' }).map((h) => [h.sub, h.tape])).toEqual([[connect(33), 1]]);
    expect(eventsOf(res.events, 'clang', { id: 'sh' }).map((c) => [c.sub, c.tape, c.detail])).toEqual([
      [connect(30), 0, 'shield'],
      [connect(36), 0, 'shield'],
    ]);
    const end = res.frames[res.frames.length - 1].enemies[0];
    expect(end).toMatchObject({ hp: 1, alive: true });
  });

  it('two coordinated pairs kill it (MOM-05: the landed hit shoves it, so the pair re-forms)', () => {
    // B's landed hit knocks it 1 tile toward A; a third self C waiting further west supplies the
    // second follow-up after A pops it again.
    const c = pathTape({ index: 2, speed: 1, ticks: 240, path: [{ tick: 0, x: 3.9, y: 5 }], events: [{ tick: 63, kind: 'light', dir: 0 }] });
    const res = resolve(level, [striker(0, [30, 60]), striker(1, [33]), c]);
    expect(eventsOf(res.events, 'hit', { id: 'sh' }).map((h) => h.tape)).toEqual([1, 2]);
    expect(eventsOf(res.events, 'kill', { id: 'sh' }).map((k) => k.tape)).toEqual([2]);
    expect(res.outcome.win).toBe(true);
  });

  it('a follow-up outside the window only pops the shield again', () => {
    const late = (WINDOW + 20) / 4; // ticks after A's hit
    const res = resolve(level, [striker(0, [30]), striker(1, [30 + late])]);
    expect(eventsOf(res.events, 'hit', { id: 'sh' })).toHaveLength(0);
    expect(eventsOf(res.events, 'clang', { id: 'sh' })).toHaveLength(2);
  });

  it('a follow-up by the same self that popped it never counts', () => {
    const res = resolve(level, [striker(0, [30, 33, 36])]);
    expect(eventsOf(res.events, 'hit', { id: 'sh' })).toHaveLength(0);
  });

  it('two selves striking on the same substep is the classic two-hit kill', () => {
    const res = resolve(level, [striker(0, [30], 'heavy'), striker(1, [30], 'heavy')]);
    // 1× standing heavy = momentum 2 = 2 damage: the follow-up alone kills a 2-hp shielder.
    expect(eventsOf(res.events, 'clang', { id: 'sh' }).map((c) => c.tape)).toEqual([0]);
    expect(eventsOf(res.events, 'kill', { id: 'sh' }).map((k) => [k.sub, k.tape])).toEqual([[(30 + 16) * 4, 1]]);
  });

  it('the snapshot shows the shield down only during the window', () => {
    const res = resolve(level, [striker(0, [30])]);
    const pop = connect(30);
    expect(frameAt(res, pop - 4).enemies[0].shield).toBe(true);
    expect(frameAt(res, pop + 4).enemies[0].shield).toBe(false);
    expect(frameAt(res, pop + WINDOW + 8).enemies[0].shield).toBe(true);
  });

  it('non-self hits (an enemy bolt) clang off without popping the shield', () => {
    const lvl = makeLevel({
      speeds: [1],
      bars: 2,
      start: { x: 2, y: 2 },
      entities: [shielder, { kind: 'enemy', id: 't1', type: 'turret', x: 10, y: 5, facing: Math.PI }],
    });
    // The self hides behind the shielder from the turret (the shielder is in the bolt's lane).
    const self = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 2, y: 5 }] });
    const res = resolve(lvl, [self]);
    const clangs = eventsOf(res.events, 'clang', { id: 'sh' });
    expect(clangs.length).toBeGreaterThan(0);
    expect(eventsOf(res.events, 'hit', { id: 'sh' })).toHaveLength(0);
    expect(res.frames.every((f) => f.enemies[0].shield === true)).toBe(true);
  });

  it('awake, it walks at the nearest self', () => {
    const lvl = makeLevel({ speeds: [1], bars: 1, start: { x: 2, y: 5 }, entities: [{ ...shielder, wakeWhen: undefined }] });
    const near = pathTape({ index: 1, speed: 1, ticks: 120, path: [{ tick: 0, x: 9, y: 5 }] });
    const far = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2, y: 5 }] });
    const res = resolve(lvl, [far, near]);
    const f = frameAt(res, SPB);
    expect(f.enemies[0].target).toBe(1);
    expect(f.enemies[0].x).toBeGreaterThan(6.5);
  });
});
