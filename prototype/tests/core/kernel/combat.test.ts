/**
 * Kernel: enemies, momentum and dodging (TEST-18..21, Scenario K, AI-01..07, MOM-01..06).
 */
import { describe, expect, it } from 'vitest';
import { createSim } from '../../../src/core/index';
import { TUTORIAL_WALL_THRESHOLD } from '../../../src/core/tuning';
import type { LevelDef, Tape, TapeSpeed } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { baseLoadout } from '../../helpers/loadout';
import { eventsOf, pathTape, recordTake, resolve, script } from '../../helpers/script';

describe('enemy targeting (TEST-18, AI-01..04)', () => {
  const level = makeLevel({
    speeds: [1],
    bars: 3,
    start: { x: 2.5, y: 5.5 },
    entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 9.5, y: 5.5 }],
  });
  const tapeA = pathTape({ index: 0, speed: 1, ticks: 360, path: [{ tick: 0, x: 2.5, y: 5.5 }] });
  // B walks up close to the grunt's flank early on.
  const tapeB = pathTape({ index: 1, speed: 1, ticks: 360, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 8.5, y: 2.0 }] });

  it('TEST-18: a closer self changes the grunt’s target while the old tape’s path is unchanged', () => {
    const solo = resolve(level, [tapeA]);
    const both = resolve(level, [tapeA, tapeB]);
    const targetsSolo = new Set(solo.frames.map((f) => f.enemies[0].target).filter((t) => t !== undefined));
    expect([...targetsSolo]).toEqual([0]);
    // Once B is nearer, the grunt switches to B on a beat boundary.
    const switched = both.frames.find((f) => f.enemies[0].target === 1);
    expect(switched).toBeDefined();
    // (Frames are stored every 4 substeps; the decision is taken on the beat's first substep.)
    expect(switched!.sub % 120).toBeLessThanOrEqual(4);
    // The grunt now walks toward B (north) instead of west.
    const g = both.frames.find((f) => f.sub === 480)!.enemies[0];
    const gs = solo.frames.find((f) => f.sub === 480)!.enemies[0];
    expect(g.y).toBeLessThan(gs.y - 0.5);
    // Tape A did not re-aim or re-route: identical positions and facings.
    const path = (r: typeof solo) => r.frames.map((f) => [f.actors[0].x, f.actors[0].y, f.actors[0].facing]);
    expect(path(both)).toEqual(path(solo));
  });

  it('AI-07: the grunt strikes on its beat grid and one strike kills a self', () => {
    const solo = resolve(level, [tapeA]);
    const attacks = eventsOf(solo.events, 'enemyAttack', { id: 'g1' });
    expect(attacks.length).toBeGreaterThan(0);
    for (const a of attacks) expect(a.sub % 240).toBe(0);
    const tel = eventsOf(solo.events, 'enemyTelegraph', { id: 'g1' });
    expect(tel[0].sub).toBe(attacks[0].sub - 60);
    expect(eventsOf(solo.events, 'selfDeath').map((e) => [e.tape, e.detail, e.sub])).toEqual([[0, 'struck by grunt g1', attacks[0].sub]]);
    // A dead ghost is never targeted again (and never killed twice).
    const after = solo.frames.filter((f) => f.sub > attacks[0].sub + 4);
    expect(after.every((f) => f.enemies[0].target === undefined)).toBe(true);
  });

  it('ties between equally near selves go to the lowest tape index', () => {
    const twin = { ...tapeA, index: 2 as const };
    const res = resolve(level, [twin, tapeA]);
    expect(res.frames[2].enemies[0].target).toBe(0);
  });
});

describe('knockback changes later outcomes (TEST-19, MOM-05)', () => {
  const level = makeLevel({
    speeds: [1],
    bars: 1,
    start: { x: 1.5, y: 5.5 },
    entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 6.0, y: 5.5, hp: 2, wakeWhen: { const: false } }],
  });
  // A swings west at a spot where the grunt is not (yet).
  const tapeA = pathTape({
    index: 0,
    speed: 1,
    ticks: 120,
    path: [
      { tick: 0, x: 1.5, y: 5.5 },
      { tick: 20, x: 1.5, y: 3.5 },
      { tick: 50, x: 8.2, y: 3.5 },
      { tick: 60, x: 8.2, y: 5.5 },
    ],
    events: [{ tick: 90, kind: 'light', dir: Math.PI }],
  });
  // B stands west of the grunt and knocks it east with a light swing.
  const tapeB = pathTape({ index: 1, speed: 1, ticks: 120, path: [{ tick: 0, x: 1.5, y: 5.5 }, { tick: 30, x: 5.0, y: 5.5 }], events: [{ tick: 40, kind: 'light', dir: 0 }] });

  it('TEST-19: alone, A’s swing whiffs; after B knocks the grunt into it, the same swing kills', () => {
    const solo = resolve(level, [tapeA]);
    expect(eventsOf(solo.events, 'whiff', { tape: 0 })).toHaveLength(1);
    expect(eventsOf(solo.events, 'kill')).toHaveLength(0);

    const both = resolve(level, [tapeA, tapeB]);
    const hitB = eventsOf(both.events, 'hit', { tape: 1 });
    expect(hitB).toHaveLength(1);
    // The grunt really moved and stayed where it landed (it is asleep, so it does not walk back).
    const landed = both.frames.find((f) => f.sub === 300)!.enemies[0];
    expect(landed.x).toBeGreaterThan(6.9);
    expect(landed.hp).toBe(1);
    const kill = eventsOf(both.events, 'kill', { id: 'g1' });
    expect(kill.map((e) => e.tape)).toEqual([0]);
    expect(eventsOf(both.events, 'whiff', { tape: 0 })).toHaveLength(0);
  });
});

/** One light swing at a tough sleeping grunt; returns what it did. */
function strike(speed: TapeSpeed, motion: 'stand' | 'into' | 'away') {
  const level = makeLevel({
    speeds: [0.5, 1, 2],
    bars: 1,
    start: { x: 5.0, y: 5.5 },
    entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 6.0, y: 5.5, hp: 10, wakeWhen: { const: false } }],
  });
  // Hit frame is 6 local ticks after the event. Approach speed 4.5 tiles per local second.
  const v = 4.5 / 60;
  const path =
    motion === 'stand'
      ? [{ tick: 0, x: 5.0, y: 5.5 }]
      : motion === 'into'
        ? [
            { tick: 0, x: 5.0 - 26 * v, y: 5.5 },
            { tick: 26, x: 5.0, y: 5.5 },
          ]
        : [
            { tick: 0, x: 5.0 + 6 * v, y: 5.5 },
            { tick: 20, x: 5.0 + 6 * v, y: 5.5 },
            { tick: 26, x: 5.0, y: 5.5 },
          ];
  const tape: Tape = pathTape({ index: 0, speed, ticks: 120, path, events: [{ tick: 20, kind: 'light', dir: 0 }] });
  const res = resolve(level, [tape]);
  const hit = eventsOf(res.events, 'hit')[0];
  const stagger = eventsOf(res.events, 'enemyStagger')[0];
  const end = res.frames[res.frames.length - 1].enemies[0];
  return { momentum: hit.power!, damage: 10 - end.hp, knockback: end.x - 6.0, stagger: stagger?.power ?? 0, clang: eventsOf(res.events, 'clang').length };
}

describe('momentum (TEST-20, MOM-01..04)', () => {
  it('TEST-20: tape speed and movement into the strike change momentum, damage, knockback and stagger', () => {
    const slow = strike(0.5, 'stand');
    const mid = strike(1, 'stand');
    const fast = strike(2, 'stand');
    const into = strike(1, 'into');
    const away = strike(1, 'away');
    expect(slow.momentum).toBeCloseTo(0.6, 5);
    expect(mid.momentum).toBeCloseTo(1.2, 5);
    expect(fast.momentum).toBeCloseTo(2.4, 5);
    expect(into.momentum).toBeGreaterThan(mid.momentum);
    expect(away.momentum).toBeLessThan(mid.momentum);
    // Damage: 0.5x standing does nothing (and says so), 1x one point, 2x two points.
    expect([slow.damage, mid.damage, fast.damage]).toEqual([0, 1, 2]);
    expect(slow.clang).toBe(1);
    expect(mid.clang).toBe(0);
    // Knockback and stagger scale with momentum.
    for (const k of ['knockback', 'stagger'] as const) {
      expect(slow[k]).toBeLessThan(mid[k]);
      expect(mid[k]).toBeLessThan(fast[k]);
      expect(away[k]).toBeLessThan(mid[k]);
      expect(into[k]).toBeGreaterThan(mid[k]);
    }
    expect(mid.knockback).toBeCloseTo(1.2, 1);
  });
});

describe('dodge i-frames (TEST-21, COMBAT-04)', () => {
  const level = makeLevel({
    speeds: [1],
    bars: 2,
    start: { x: 5.0, y: 5.5 },
    // One shot only (beat 2), so the test is about that bolt.
    entities: [{ kind: 'enemy', id: 't1', type: 'turret', x: 10.5, y: 5.5, facing: Math.PI, beat: { every: 64, offset: 2 } }],
  });
  const stand = (dodgeAt?: number): Tape =>
    pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 5.0, y: 5.5 }], events: dodgeAt === undefined ? [] : [{ tick: dodgeAt, kind: 'dodge' }] });

  it('TEST-21: a bolt arriving inside the dodge’s i-frames passes through; outside them it kills', () => {
    const none = resolve(level, [stand()]);
    const death = eventsOf(none.events, 'selfDeath');
    expect(death).toHaveLength(1);
    const hitTick = Math.floor(death[0].sub / 4);
    // I-frames cover local ticks [dodge + 1, dodge + 11): start the dodge 4 ticks before contact.
    const dodged = resolve(level, [stand(hitTick - 4)]);
    expect(eventsOf(dodged.events, 'selfDeath')).toHaveLength(0);
    expect(eventsOf(dodged.events, 'dodge')).toHaveLength(1);
    // The bolt flew on and broke on the wall behind.
    expect(eventsOf(dodged.events, 'projectileHit').some((e) => e.detail === 'bolt:wall')).toBe(true);
    const late = resolve(level, [stand(hitTick - 30)]);
    expect(eventsOf(late.events, 'selfDeath')).toHaveLength(1);
  });

  it('a recorded dodge gives the live self the same i-frames', () => {
    const take = recordTake({ level, index: 0, speed: 1, script: script().press(101, 'dodge') });
    const snaps = take.frames.filter((f) => f.actors[0].iframes);
    expect(snaps.length).toBe(10);
  });
});

/** Scenario K: one breakable wall in front of the exit. */
const wallLevel = (): LevelDef =>
  makeLevel({
    speeds: [0.5, 1, 2],
    bars: 2,
    start: { x: 1.5, y: 5.5 },
    entities: [{ kind: 'breakable', id: 'w1', c: 8, r: 5, threshold: TUTORIAL_WALL_THRESHOLD }],
    objective: { type: 'signal', when: { sig: 'w1' }, text: 'Break the wall' },
  });

/** Record a run at the wall; press `button` when the self first reaches x ≥ pressX (or after it stops, when standing). */
function wallTake(speed: TapeSpeed, button: 'light' | 'heavy', running: boolean) {
  const level = wallLevel();
  const probe = createSim({ level, loadout: baseLoadout(), tapes: [], live: { index: 0, speed, endMode: 'stop' } });
  const run = script().run(0, 1000, 1, 0);
  let pressAt = -1;
  for (let t = 0; t < probe.tapeTicks; t++) {
    probe.stepLocalTick(run.input(t));
    const x = probe.snapshot().actors[0].x;
    if (running && x >= 6.6) {
      pressAt = t + 1;
      break;
    }
    if (!running && x >= 7.69) {
      pressAt = t + 20;
      break;
    }
  }
  expect(pressAt).toBeGreaterThan(0);
  const s = running ? script().run(0, 1000, 1, 0).press(pressAt, button, 0) : script().run(0, pressAt - 15, 1, 0).press(pressAt, button, 0);
  const take = recordTake({ level, index: 0, speed, script: s });
  return { take, res: resolve(level, [take.tape]) };
}

describe('momentum threshold wall (Scenario K)', () => {
  it('a 1x standing light clangs, and the outcome says how much momentum was missing', () => {
    const { take, res } = wallTake(1, 'light', false);
    const clang = eventsOf(take.events, 'clang', { id: 'w1' });
    expect(clang).toHaveLength(1);
    expect(clang[0].power).toBeCloseTo(1.2, 5);
    expect(eventsOf(res.events, 'break')).toHaveLength(0);
    expect(res.outcome.win).toBe(false);
    expect(res.outcome.notes.some((n) => /Tape A's light at beat [\d.]+ hit breakable wall w1 with momentum 1\.2; it needs 5\./.test(n))).toBe(true);
  });

  it('a 1x running heavy and a 2x standing heavy are still too weak', () => {
    const runHeavy = wallTake(1, 'heavy', true);
    expect(eventsOf(runHeavy.res.events, 'break')).toHaveLength(0);
    expect(eventsOf(runHeavy.res.events, 'clang', { id: 'w1' })[0].power).toBeCloseTo(3, 5);
    const standHeavy = wallTake(2, 'heavy', false);
    expect(eventsOf(standHeavy.res.events, 'break')).toHaveLength(0);
    expect(eventsOf(standHeavy.res.events, 'clang', { id: 'w1' })[0].power).toBeCloseTo(4, 5);
  });

  it('a 2x running heavy breaks it, and the self can walk through the gap', () => {
    const { take, res } = wallTake(2, 'heavy', true);
    const brk = eventsOf(res.events, 'break', { id: 'w1' });
    expect(brk).toHaveLength(1);
    expect(brk[0].power).toBeCloseTo(6, 5);
    expect(eventsOf(take.events, 'break', { id: 'w1' })).toHaveLength(1);
    expect(res.outcome.win).toBe(true);
    expect(take.frames[take.frames.length - 1].actors[0].x).toBeGreaterThan(9);
    expect(res.frames[res.frames.length - 1].mechs.find((m) => m.id === 'w1')!.on).toBe(true);
  });
});
