/**
 * Kernel: desynchronisation and the recovery spark (TEST-13..17, Scenarios I and J, DESYNC-01..08).
 */
import { describe, expect, it } from 'vitest';
import { BASE } from '../../../src/core/tuning';
import { SUB_HZ, type LevelDef, type Resolution, type Tape } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { eventsOf, pathTape, resolve } from '../../helpers/script';

/**
 * Corridor with a door and (optionally) a detour above it:
 *
 *          0         1
 *          01234567890123
 *     r0   ##############
 *     r1   #............#      detour corridor (solid wall when `detour` is false)
 *     r2   #S##########.#      S switch "sw" (1.5, 2.5); the right-hand gap is wall when `detour` is false
 *     r3   #@.....D....E#      @ start (1.5, 3.5); D door "d1" (7, 3), open unless sw is on; E exit
 *     r4   ##############
 */
function corridor(detour: boolean): LevelDef {
  return makeLevel({
    speeds: [1],
    bars: 4,
    map: [
      '##############',
      detour ? '#............#' : '##############',
      detour ? '#.##########.#' : '#.############',
      '#............#',
      '##############',
    ],
    start: { x: 1.5, y: 3.5 },
    entities: [
      { kind: 'switch', id: 'sw', x: 1.5, y: 2.5 },
      { kind: 'door', id: 'd1', cells: [{ c: 7, r: 3 }], openWhen: { not: { sig: 'sw' } } },
      { kind: 'exit', id: 'exit', c: 12, r: 3, w: 1, h: 1 },
    ],
    objective: { type: 'reach', text: 'Reach the end' },
  });
}

const T = 480;

/** Tape A walks the corridor at 3 tiles/s from the start to the far end and waits there. */
const runner = (): Tape =>
  pathTape({
    index: 0,
    speed: 1,
    ticks: T,
    path: [
      { tick: 0, x: 1.5, y: 3.5 },
      { tick: 220, x: 12.5, y: 3.5 },
    ],
  });

/** Tape B flips the switch at local tick `closeAt` (and again at `reopenAt`, if given). */
function switcher(closeAt: number, reopenAt?: number): Tape {
  const events: { tick: number; kind: 'interact' }[] = [{ tick: closeAt, kind: 'interact' }];
  if (reopenAt !== undefined) events.push({ tick: reopenAt, kind: 'interact' });
  return pathTape({ index: 1, speed: 1, ticks: T, path: [{ tick: 0, x: 1.5, y: 3.5 }], events });
}

function sparkTrack(res: Resolution, tape: number): { sub: number; x: number; y: number }[] {
  const out: { sub: number; x: number; y: number }[] = [];
  for (const f of res.frames) {
    const a = f.actors.find((x) => x.tape === tape)!;
    if (a.spark) out.push({ sub: f.sub, x: a.spark.x, y: a.spark.y });
  }
  return out;
}

describe('desync on obstruction (TEST-13, TEST-14, Scenario I)', () => {
  it('TEST-13: a door closed across a living tape desyncs it; its projection keeps the recording', () => {
    const level = corridor(true);
    const solo = resolve(level, [runner()]);
    expect(eventsOf(solo.events, 'desync')).toHaveLength(0);
    const res = resolve(level, [runner(), switcher(5)]);
    const desyncs = eventsOf(res.events, 'desync', { tape: 0 });
    expect(desyncs).toHaveLength(1);
    expect(desyncs[0].detail).toBe('blocked by door d1');
    // DESYNC-01: the projection follows its exact recorded performance.
    expect(res.frames.map((f) => [f.actors[0].x, f.actors[0].y])).toEqual(solo.frames.map((f) => [f.actors[0].x, f.actors[0].y]));
    // While desynced the self is shown with a spark and is not synced.
    const during = res.frames.find((f) => f.sub > desyncs[0].sub + 8)!.actors[0];
    expect(during.synced).toBe(false);
    expect(during.spark).toBeDefined();
    expect(during.life).toBe('alive');
  });

  it('TEST-14 / Scenario I: the spark takes the open detour at finite speed and resyncs on catch-up', () => {
    const level = corridor(true);
    const res = resolve(level, [runner(), switcher(5)]);
    const d = eventsOf(res.events, 'desync', { tape: 0 })[0];
    const r = eventsOf(res.events, 'resync', { tape: 0 });
    expect(r).toHaveLength(1);
    const track = sparkTrack(res, 0);
    // Finite speed: never more than sparkSpeed per master second between frames.
    const maxStep = (BASE.sparkSpeed / SUB_HZ) * 4 + 1e-9;
    for (let i = 1; i < track.length; i++) {
      const step = Math.hypot(track[i].x - track[i - 1].x, track[i].y - track[i - 1].y);
      expect(step).toBeLessThanOrEqual(maxStep);
    }
    // It really went round: the detour row (y < 2) was visited.
    expect(track.some((p) => p.y < 2)).toBe(true);
    // No instant overlap-only recovery: the projection is clear of the door long before the resync.
    const clearOfDoor = res.frames.find((f) => f.actors[0].x > 8.5)!.sub;
    expect(r[0].sub).toBeGreaterThan(clearOfDoor + 0.5 * SUB_HZ);
    // The detour is ~20 tiles: the spark cannot have made it faster than its speed allows.
    expect((r[0].sub - d.sub) / SUB_HZ).toBeGreaterThan(18 / BASE.sparkSpeed);
    const end = res.frames[res.frames.length - 1].actors[0];
    expect(end.synced).toBe(true);
    expect(end.spark).toBeUndefined();
    expect(res.outcome.notes.some((n) => /Tape A desynced at beat [\d.]+ \(blocked by door d1\); its spark caught up at beat/.test(n))).toBe(true);
    expect(res.outcome.win).toBe(true);
  });

  it('Scenario I: reopening the direct route lets the spark catch up sooner than the detour', () => {
    const level = corridor(true);
    const detourOnly = eventsOf(resolve(level, [runner(), switcher(5)]).events, 'resync', { tape: 0 })[0].sub;
    const reopened = eventsOf(resolve(level, [runner(), switcher(5, 150)]).events, 'resync', { tape: 0 })[0].sub;
    expect(reopened).toBeLessThan(detourOnly);
  });
});

describe('blocked recovery (TEST-15, DESYNC-03)', () => {
  it('with no route the spark never catches up, and nothing teleports or kills it', () => {
    const level = corridor(false);
    const res = resolve(level, [runner(), switcher(5)]);
    expect(eventsOf(res.events, 'desync', { tape: 0 })).toHaveLength(1);
    expect(eventsOf(res.events, 'resync', { tape: 0 })).toHaveLength(0);
    const end = res.frames[res.frames.length - 1].actors[0];
    expect(end.synced).toBe(false);
    expect(end.life).toBe('alive');
    // The spark waits on its own side of the door.
    expect(end.spark!.x).toBeLessThan(7);
    // Alive but desynced: a survivor that cannot hold the exit.
    expect(res.outcome.survivors).toContain(0);
    expect(res.outcome.objectiveComplete).toBe(false);
    expect(res.outcome.notes.some((n) => /its spark never caught up/.test(n))).toBe(true);
    expect(res.outcome.notes.some((n) => /ended the run desynced/.test(n))).toBe(true);
  });

  it('TEST-15: another tape reopening the blocked route lets the spark recover', () => {
    const level = corridor(false);
    const res = resolve(level, [runner(), switcher(5, 300)]);
    const reopen = eventsOf(res.events, 'door', { id: 'd1' }).filter((e) => e.detail === 'open');
    expect(reopen).toHaveLength(1);
    const r = eventsOf(res.events, 'resync', { tape: 0 });
    expect(r).toHaveLength(1);
    expect(r[0].sub).toBeGreaterThan(reopen[0].sub);
    expect(res.frames[res.frames.length - 1].actors[0].synced).toBe(true);
    expect(res.outcome.win).toBe(true);
  });
});

describe('desynced selves are harmless and invulnerable (TEST-16)', () => {
  /** Open room; a low barrier at (6, 5) that tape A's recording stands on. */
  const level = makeLevel({
    speeds: [1],
    bars: 2,
    map: [
      '############',
      '#..........#',
      '#..........#',
      '#..........#',
      '#..........#',
      '#.....=....#',
      '#..........#',
      '#..........#',
      '#..........#',
      '############',
    ],
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'enemy', id: 't1', type: 'turret', x: 10.5, y: 5.5, facing: Math.PI },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 7.4, y: 6.3, wakeWhen: { const: false } },
    ],
    objective: { type: 'eliminate', targets: ['g1'], text: 'Destroy the grunt' },
  });
  // A walks onto the low barrier (impossible in this world: desync) and swings at the grunt from there.
  const tapeA = pathTape({
    index: 0,
    speed: 1,
    ticks: 240,
    path: [
      { tick: 0, x: 2.5, y: 5.5 },
      { tick: 40, x: 6.5, y: 5.5 },
    ],
    events: [{ tick: 120, kind: 'light', dir: Math.atan2(0.8, 0.9) }],
  });
  // C stands still at the start, behind A in the turret's lane.
  const tapeC = pathTape({ index: 2, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }] });

  it('a desynced swing deals no damage and a bolt passes through the desynced projection', () => {
    const res = resolve(level, [tapeA, tapeC]);
    expect(eventsOf(res.events, 'desync', { tape: 0 })).toHaveLength(1);
    expect(eventsOf(res.events, 'resync', { tape: 0 })).toHaveLength(0);
    expect(eventsOf(res.events, 'hit')).toHaveLength(0);
    expect(eventsOf(res.events, 'kill')).toHaveLength(0);
    // The turret ignores A and shoots C straight through A's projection.
    const shots = eventsOf(res.events, 'enemyShot', { id: 't1' });
    expect(shots.length).toBeGreaterThan(0);
    expect(shots.every((s) => s.tape === 2)).toBe(true);
    expect(eventsOf(res.events, 'selfDeath').map((e) => e.tape)).toEqual([2]);
    const end = res.frames[res.frames.length - 1];
    expect(end.actors[0]).toMatchObject({ life: 'alive', synced: false });
    expect(end.enemies.find((e) => e.id === 'g1')!.alive).toBe(true);
  });

  it('the same swing, synced, destroys the grunt (control)', () => {
    const synced = { ...level, map: level.map.map((r) => r.replace('=', '.')), entities: level.entities.filter((e) => e.kind !== 'enemy' || e.type !== 'turret') };
    const res = resolve(synced, [tapeA]);
    expect(eventsOf(res.events, 'desync')).toHaveLength(0);
    expect(eventsOf(res.events, 'kill', { id: 'g1' }).map((e) => e.tape)).toEqual([0]);
  });
});

/**
 * The wall-and-turret teaching case (Scenario J):
 *
 *          0         1
 *          0123456789012345
 *     r0   ################
 *     r1   #S.............#     S switch "sw" (1.5, 1.5); @ start (2.5, 1.5)
 *     r2   #..............#
 *     r3   #####D######...#     D door "d1" (5, 3), open unless sw is on; the gap at c 12..14 is the detour
 *     r4   #..............#
 *     r5   #..............#     T turret t1 (8.5, 5.0), aim arc: the western half-plane
 *     r6   ################
 */
function turretLevel(detour: boolean): LevelDef {
  return makeLevel({
    speeds: [1],
    bars: 4,
    map: [
      '################',
      '#..............#',
      '#..............#',
      detour ? '#####.######...#' : '#####.##########',
      '#..............#',
      '#..............#',
      '################',
    ],
    start: { x: 2.5, y: 1.5 },
    entities: [
      { kind: 'switch', id: 'sw', x: 1.5, y: 1.5 },
      { kind: 'door', id: 'd1', cells: [{ c: 5, r: 3 }], openWhen: { not: { sig: 'sw' } } },
      { kind: 'enemy', id: 't1', type: 'turret', x: 8.5, y: 5.0, facing: Math.PI, arc: Math.PI },
    ],
    objective: { type: 'eliminate', targets: ['t1'], text: 'Destroy the turret' },
  });
}

/** Tape A: through the door, a pause in the turret's lane, round to its rear, then a strike. */
function crosser(strikeAt: number): Tape {
  return pathTape({
    index: 0,
    speed: 1,
    ticks: T,
    path: [
      { tick: 0, x: 2.5, y: 1.5 },
      { tick: 60, x: 5.5, y: 1.5 },
      { tick: 120, x: 5.5, y: 4.5 },
      { tick: 130, x: 6.5, y: 4.5 },
      { tick: 200, x: 6.5, y: 4.5 },
      { tick: 260, x: 9.6, y: 4.4 },
      { tick: 270, x: 9.6, y: 5.0 },
    ],
    events: [{ tick: strikeAt, kind: 'light', dir: Math.PI }],
  });
}

/** Tape B closes the door just before A reaches it. */
const doorman = (): Tape => pathTape({ index: 1, speed: 1, ticks: T, path: [{ tick: 0, x: 2.5, y: 1.5 }], events: [{ tick: 5, kind: 'interact' }] });

describe('the wall-and-turret case (TEST-17, Scenario J)', () => {
  it('without desync the turret kills the crossing tape in its lane', () => {
    const res = resolve(turretLevel(true), [crosser(400)]);
    expect(eventsOf(res.events, 'selfDeath', { tape: 0 }).map((e) => e.detail)).toEqual(['shot by turret t1']);
    expect(eventsOf(res.events, 'kill')).toHaveLength(0);
    expect(res.outcome.win).toBe(false);
  });

  it('Scenario J: desync protects the crossing, the spark detours, the tape resyncs behind the turret and breaks it', () => {
    const res = resolve(turretLevel(true), [crosser(400), doorman()]);
    const d = eventsOf(res.events, 'desync', { tape: 0 });
    const r = eventsOf(res.events, 'resync', { tape: 0 });
    expect(d).toHaveLength(1);
    expect(r).toHaveLength(1);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
    // Not one shot was fired at the desynced projection.
    expect(eventsOf(res.events, 'enemyShot').filter((e) => e.tape === 0 && e.sub > d[0].sub && e.sub < r[0].sub)).toHaveLength(0);
    // The resync happened before the strike, and the strike destroyed the turret.
    const kill = eventsOf(res.events, 'kill', { id: 't1' });
    expect(kill.map((e) => e.tape)).toEqual([0]);
    expect(r[0].sub).toBeLessThan(kill[0].sub);
    expect(res.outcome.win).toBe(true);
  });

  it('TEST-17: if the spark has not caught up, the desynced strike cannot hurt the turret', () => {
    const res = resolve(turretLevel(false), [crosser(400), doorman()]);
    expect(eventsOf(res.events, 'desync', { tape: 0 })).toHaveLength(1);
    expect(eventsOf(res.events, 'resync', { tape: 0 })).toHaveLength(0);
    expect(eventsOf(res.events, 'kill')).toHaveLength(0);
    expect(eventsOf(res.events, 'selfDeath', { tape: 0 })).toHaveLength(0);
    expect(res.outcome.objectiveComplete).toBe(false);
    expect(res.outcome.survivors).toEqual([0, 1]);
  });
});

describe('repeat cuts and the spark (DESYNC, ARCHITECTURE "What a tape is")', () => {
  it('a repeat cut teleports the projection but the spark has to travel', () => {
    const level = corridor(false);
    // A 2x repeat runner: it desyncs at the closed door, then its projection cuts back to the start.
    const fast = pathTape({ index: 0, speed: 2, endMode: 'repeat', ticks: T, path: [{ tick: 0, x: 1.5, y: 3.5 }, { tick: 220, x: 12.5, y: 3.5 }] });
    const res = resolve(level, [fast, switcher(2)]);
    const cut = T * 2;
    expect(eventsOf(res.events, 'tapeWrap', { tape: 0 }).map((e) => e.sub + 1)).toContain(cut);
    const before = res.frames.find((f) => f.sub === cut - 4)!.actors[0];
    const after = res.frames.find((f) => f.sub === cut)!.actors[0];
    expect(before.synced).toBe(false);
    expect(after.x).toBe(1.5); // the projection is back at the start
    // The spark did not jump with it: it moved at most its speed in those 4 substeps.
    expect(Math.hypot(after.spark!.x - before.spark!.x, after.spark!.y - before.spark!.y)).toBeLessThanOrEqual((BASE.sparkSpeed / SUB_HZ) * 4 + 1e-9);
    // It then walks back along the corridor and resyncs with the new traversal.
    const r = eventsOf(res.events, 'resync', { tape: 0 });
    expect(r.length).toBeGreaterThan(0);
    expect(r[0].sub).toBeGreaterThan(cut);
  });
});
