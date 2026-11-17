/**
 * Kernel: death, ghosts and survival (TEST-07..12, TEST-23, TEST-24, Scenarios C and D).
 */
import { describe, expect, it } from 'vitest';
import type { LevelDef, Tape } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { eventsOf, pathTape, recordTake, resolve, script } from '../../helpers/script';

/**
 * The rescue room (Scenario C):
 *
 *          0         1
 *          012345678901
 *     r0   ############
 *     r1   #.L...#....#     L  lever (2.5, 1.5)
 *     r2   #..g..#....#     g  grunt g1, asleep (3.0, 2.55)
 *     r3   #..@..D....#     @  start (3.0, 3.5)    D door "gate" (6, 3), opened by the lever
 *     r4   #T....#....#     T  turret t1 (1.5, 4.5)
 *     r5   ############
 */
const rescueRoom = (): LevelDef =>
  makeLevel({
    speeds: [1, 2],
    bars: 4,
    map: ['############', '#.....#....#', '#.....#....#', '#..........#', '#.....#....#', '############'],
    start: { x: 3.0, y: 3.5 },
    entities: [
      { kind: 'enemy', id: 't1', type: 'turret', x: 1.5, y: 4.5 },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 3.0, y: 2.55, wakeWhen: { const: false } },
      { kind: 'switch', id: 'lever', x: 2.5, y: 1.5 },
      { kind: 'door', id: 'gate', cells: [{ c: 6, r: 3 }], openWhen: { sig: 'lever' } },
    ],
    objective: { type: 'eliminate', targets: ['g1'], text: 'Destroy the grunt' },
  });

/** Tape A: stands at the start (the turret kills it early), then — as a ghost — strikes, flips the lever and walks through the door. */
const tapeAScript = () =>
  script()
    .aim(0, 480, -Math.PI / 2)
    .press(100, 'light', -Math.PI / 2)
    .run(130, 150, -0.3, -1)
    .press(160, 'interact')
    .run(175, 200, 0.55, 1)
    .run(200, 300, 1, 0);

describe('ghosts while recording (TEST-07..09)', () => {
  const level = rescueRoom();
  const take = recordTake({ level, index: 0, speed: 1, script: tapeAScript() });
  const deaths = eventsOf(take.events, 'selfDeath');

  it('TEST-07: dying does not end the take; the self continues as a recording ghost', () => {
    expect(deaths).toHaveLength(1);
    expect(deaths[0].detail).toBe('shot by turret t1');
    expect(take.sim.done).toBe(true);
    expect(take.tape.ticks).toBe(take.sim.tapeTicks);
    const last = take.frames[take.frames.length - 1].actors[0];
    expect(last.life).toBe('recGhost');
    expect(last.live).toBe(true);
    // It kept moving after death (it walked to the lever and through the door).
    const atDeath = take.frames.find((f) => f.sub > deaths[0].sub)!.actors[0];
    expect(Math.hypot(last.x - atDeath.x, last.y - atDeath.y)).toBeGreaterThan(2);
  });

  it('TEST-08: the recording ghost is still blocked by a closed door', () => {
    const blocked = rescueRoom();
    blocked.entities = blocked.entities.map((e) => (e.kind === 'door' ? { ...e, openWhen: { const: false } } : e));
    const t = recordTake({ level: blocked, index: 0, speed: 1, script: tapeAScript() });
    expect(eventsOf(t.events, 'selfDeath')).toHaveLength(1);
    const maxX = Math.max(...t.frames.map((f) => f.actors[0].x));
    expect(maxX).toBeLessThan(6 - 0.29);
    expect(t.frames[t.frames.length - 1].actors[0].life).toBe('recGhost');
  });

  it('TEST-09: the recording ghost strikes and flips a switch in its own provisional run', () => {
    const kills = eventsOf(take.events, 'kill', { id: 'g1' });
    expect(kills).toHaveLength(1);
    expect(kills[0].tape).toBe(0);
    expect(kills[0].sub).toBeGreaterThan(deaths[0].sub);
    expect(eventsOf(take.events, 'interact', { id: 'lever' }).map((e) => e.detail)).toEqual(['on']);
    expect(eventsOf(take.events, 'door', { id: 'gate' }).map((e) => e.detail)).toEqual(['open']);
    // It walked through the door it opened.
    expect(take.frames[take.frames.length - 1].actors[0].x).toBeGreaterThan(7);
    // And it could not be hurt again: one death only, even though the turret kept its lane.
    expect(take.outcome.survivors).toEqual([]);
  });
});

describe('ghosts on playback (TEST-10, TEST-11, Scenario C)', () => {
  const level = rescueRoom();
  const take = recordTake({ level, index: 0, speed: 1, script: tapeAScript() });

  it('TEST-10 / Scenario C: replayed, the tape dies again and its later strike and switch have no effect', () => {
    const res = resolve(level, [take.tape]);
    const deaths = eventsOf(res.events, 'selfDeath', { tape: 0 });
    expect(deaths).toHaveLength(1);
    expect(eventsOf(res.events, 'kill')).toHaveLength(0);
    expect(eventsOf(res.events, 'interact')).toHaveLength(0);
    // The door the recording ghost opened stays shut for the whole run.
    expect(res.frames.every((f) => f.mechs.find((m) => m.id === 'gate')!.on === false)).toBe(true);
    // The ghost still follows the recorded path exactly, through the closed door.
    const bySub = new Map(res.frames.map((f) => [f.sub, f]));
    for (const f of take.frames) {
      const g = bySub.get(f.sub);
      if (g) expect([g.actors[0].x, g.actors[0].y]).toEqual([f.actors[0].x, f.actors[0].y]);
    }
    const last = res.frames[res.frames.length - 1].actors[0];
    expect(last.life).toBe('ghost');
    expect(last.x).toBeGreaterThan(7);
    expect(res.outcome.win).toBe(false);
    expect(res.outcome.reason).toBe('objective');
    expect(res.outcome.notes.some((n) => /Tape A died at beat [\d.]+: shot by turret t1/.test(n))).toBe(true);
  });

  it('TEST-11: when another tape prevents the fatal hit, the later recorded actions become effective', () => {
    // Tape B (2x) runs at the turret and destroys it before its first shot.
    const takeB = recordTake({
      level,
      tapes: [take.tape],
      index: 1,
      speed: 2,
      script: script().run(0, 9, -1.5, 1).press(9, 'light', Math.atan2(1, -1.5)).run(30, 60, 1, -1),
    });
    expect(eventsOf(takeB.events, 'kill', { id: 't1' })).toHaveLength(1);
    const res = resolve(level, [take.tape, takeB.tape]);
    expect(eventsOf(res.events, 'kill', { id: 't1' })).toHaveLength(1);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
    expect(eventsOf(res.events, 'kill', { id: 'g1' }).map((e) => e.tape)).toEqual([0]);
    expect(eventsOf(res.events, 'interact', { id: 'lever' })).toHaveLength(1);
    expect(eventsOf(res.events, 'desync')).toHaveLength(0);
    const last = res.frames[res.frames.length - 1];
    expect(last.mechs.find((m) => m.id === 'gate')!.on).toBe(true);
    expect(res.outcome.win).toBe(true);
    expect(res.outcome.survivors).toEqual([0, 1]);
  });
});

/**
 * Scenario D room:
 *
 *          0         1
 *          01234567890123
 *     r0   ##############
 *     r1   #.....L.......#    L lamp switch (6.5, 1.5)
 *     r2   #.G...........#    G gate switch (2.5, 2.5)
 *     r3   #.......######
 *     r4   #.@.....D...T#     @ start (2.5, 4.5); D door "door" (8, 4); T turret (12.5, 4.5)
 *     r5   #.......######
 *     r6   #.............#
 *     r7   ##############
 */
const scenarioD = (): LevelDef =>
  makeLevel({
    speeds: [1],
    bars: 4,
    map: [
      '##############',
      '#............#',
      '#............#',
      '#.......######',
      '#............#',
      '#.......######',
      '#............#',
      '##############',
    ],
    start: { x: 2.5, y: 4.5 },
    entities: [
      { kind: 'switch', id: 'gate', x: 2.5, y: 2.5 },
      { kind: 'switch', id: 'lamp', x: 6.5, y: 1.5 },
      { kind: 'door', id: 'door', cells: [{ c: 8, r: 4 }], openWhen: { sig: 'gate' } },
      { kind: 'enemy', id: 't1', type: 'turret', x: 12.5, y: 4.5, facing: Math.PI },
    ],
    objective: { type: 'signal', when: { sig: 'gate' }, text: 'Open the gate' },
  });

describe('a clean take killed at a new time (TEST-12, Scenario D)', () => {
  const level = scenarioD();
  const T = 480;
  // Tape A: walks into the corridor in front of the door, waits, then goes to flip the lamp.
  const tapeA: Tape = pathTape({
    index: 0,
    speed: 1,
    ticks: T,
    path: [
      { tick: 0, x: 2.5, y: 4.5 },
      { tick: 60, x: 6.0, y: 4.5 },
      { tick: 440, x: 6.0, y: 4.5 },
      { tick: 460, x: 6.3, y: 2.3 },
    ],
    events: [{ tick: 470, kind: 'interact' }],
  });
  // Tape B: steps up to the gate switch late and opens the door, exposing A's corridor.
  const tapeB: Tape = pathTape({
    index: 1,
    speed: 1,
    ticks: T,
    path: [
      { tick: 0, x: 2.5, y: 4.5 },
      { tick: 30, x: 2.5, y: 3.0 },
    ],
    events: [{ tick: 300, kind: 'interact' }],
  });

  it('alone, tape A survives and lights the lamp', () => {
    const solo = resolve(level, [tapeA]);
    expect(eventsOf(solo.events, 'selfDeath')).toHaveLength(0);
    expect(eventsOf(solo.events, 'interact', { id: 'lamp' }).map((e) => e.detail)).toEqual(['on']);
  });

  it('TEST-12 / Scenario D: with B opening the door, A dies late, keeps moving as a ghost, and its later switch does not count', () => {
    const solo = resolve(level, [tapeA]);
    const res = resolve(level, [tapeA, tapeB]);
    const deaths = eventsOf(res.events, 'selfDeath', { tape: 0 });
    expect(deaths).toHaveLength(1); // never killed twice
    expect(deaths[0].detail).toBe('shot by turret t1');
    expect(deaths[0].sub).toBeGreaterThan(300 * 4); // after B opened the door at local tick 300
    expect(deaths[0].sub).toBeLessThan(440 * 4); // while A still waited in the lane
    // Movement continues exactly.
    expect(res.frames.map((f) => [f.actors[0].x, f.actors[0].y])).toEqual(solo.frames.map((f) => [f.actors[0].x, f.actors[0].y]));
    // The lamp interaction after death does not count.
    expect(eventsOf(res.events, 'interact', { id: 'lamp' })).toHaveLength(0);
    expect(res.frames[res.frames.length - 1].mechs.find((m) => m.id === 'lamp')!.on).toBe(false);
    // The other tape carries on: B opened the gate and survives; the attempt is won by B.
    expect(eventsOf(res.events, 'interact', { id: 'gate', tape: 1 })).toHaveLength(1);
    expect(res.outcome.survivors).toEqual([1]);
    expect(res.outcome.win).toBe(true);
    const last = res.frames[res.frames.length - 1].actors[0];
    expect(last.life).toBe('ghost');
  });
});

/** Open room with an always-on laser across row 2 and a sleeping grunt to destroy. */
const survivalRoom = (): LevelDef =>
  makeLevel({
    speeds: [1],
    bars: 2,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'laser', id: 'beam', from: { x: 1.5, y: 2.5 }, to: { x: 10.5, y: 2.5 }, onWhen: { const: true } },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 8.0, y: 7.5, wakeWhen: { const: false } },
    ],
    objective: { type: 'eliminate', text: 'Destroy the grunt' },
  });

function walkIntoLaser(index: 0 | 1 | 2 | 3, x: number): Tape {
  return pathTape({ index, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x, y: 5.5 }, { tick: 90, x, y: 2.5 }] });
}

function killGrunt(index: 0 | 1 | 2 | 3, thenDie: boolean): Tape {
  const path = [
    { tick: 0, x: 2.5, y: 5.5 },
    { tick: 60, x: 7.0, y: 7.5 },
  ];
  if (thenDie) path.push({ tick: 100, x: 7.0, y: 7.5 }, { tick: 160, x: 7.0, y: 2.5 });
  return pathTape({ index, speed: 1, ticks: 240, path, events: [{ tick: 70, kind: 'light', dir: 0 }] });
}

describe('survivors (TEST-23, TEST-24)', () => {
  it('TEST-23: three selves die and one survivor completes the objective: the attempt is won', () => {
    const level = survivalRoom();
    const res = resolve(level, [walkIntoLaser(0, 3.5), walkIntoLaser(1, 5.5), walkIntoLaser(2, 9.5), killGrunt(3, false)]);
    expect(eventsOf(res.events, 'selfDeath').map((e) => [e.tape, e.detail])).toEqual([
      [0, 'burned by laser beam'],
      [1, 'burned by laser beam'],
      [2, 'burned by laser beam'],
    ]);
    expect(res.outcome.objectiveComplete).toBe(true);
    expect(res.outcome.survivors).toEqual([3]);
    expect(res.outcome.win).toBe(true);
    expect(res.outcome.reason).toBeUndefined();
  });

  it('TEST-24: the objective completed with no survivor is not a win', () => {
    const level = survivalRoom();
    const res = resolve(level, [walkIntoLaser(0, 3.5), killGrunt(1, true)]);
    expect(res.outcome.objectiveComplete).toBe(true);
    expect(res.outcome.survivors).toEqual([]);
    expect(res.outcome.win).toBe(false);
    expect(res.outcome.reason).toBe('noSurvivor');
    expect(res.outcome.notes.some((n) => n.startsWith('No self survived'))).toBe(true);
    expect(res.frames[res.frames.length - 1].objective).toMatchObject({ complete: true, survivors: 0 });
  });
});
