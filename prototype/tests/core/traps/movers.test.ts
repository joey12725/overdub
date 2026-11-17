/**
 * Traps that move bodies: conveyors, bumpers, magnets (docs/TRAPS.md 3, 6, 9).
 */
import { describe, expect, it } from 'vitest';
import { BUMPER_PULSE_SUBS } from '../../../src/core/traps';
import { TRAP_EVENT } from '../../../src/core/traps';
import type { EntityDef, Tape } from '../../../src/core/types';
import { eventsOf, pathTape, recordTake, resolve, script } from '../../helpers/script';
import { ALWAYS, beats, enemyAt, lastFrame, mechAt, room, sleeper, stand, trapEvents } from './util';

/** A belt along row 5, columns 3..6, running east at 2 tiles per master second. */
const belt = (extra: Partial<EntityDef> = {}): EntityDef =>
  ({ kind: 'conveyor', id: 'belt', cells: [3, 4, 5, 6].map((c) => ({ c, r: 5 })), dir: 'e', speed: 2, ...extra }) as EntityDef;

/** Tape that toggles switch "sw" (at 2.5, 2.5) on local tick `at`. */
const toggler = (index: 0 | 1 | 2 | 3, at: number): Tape =>
  pathTape({ index, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 3.2 }], events: [{ tick: at, kind: 'interact' }] });

describe('conveyor', () => {
  it('carries a grounded enemy at its speed in master time and lets go at the end of the belt', () => {
    const res = resolve(room([belt(), sleeper('g', 'grunt', 3.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    // 2 tiles per master second = 1/120 tile per substep.
    expect(enemyAt(res, 120, 'g').x).toBeCloseTo(4.5, 6);
    expect(enemyAt(res, 240, 'g').x).toBeCloseTo(5.5, 6);
    // Its centre leaves the last cell at x = 7 (substep 420) and it stays where the belt dropped it.
    const end = lastFrame(res).enemies[0];
    expect(end.x).toBeGreaterThanOrEqual(7);
    expect(end.x).toBeLessThan(7.01);
    expect(end.y).toBe(5.5);
    expect(mechAt(res, 0, 'belt')).toMatchObject({ kind: 'conveyor', on: true, dir: 0 });
  });

  it('does not carry turrets (bolted down), drones (hovering) or playback selves (their path is the tape)', () => {
    const res = resolve(
      room([belt(), sleeper('t', 'turret', 3.5, 5.5), sleeper('dr', 'drone', 4.5, 5.5)]),
      [stand(0, 5.5, 5.5)],
    );
    expect(enemyAt(res, 900, 't')).toMatchObject({ x: 3.5, y: 5.5 });
    expect(enemyAt(res, 900, 'dr')).toMatchObject({ x: 4.5, y: 5.5 });
    expect(lastFrame(res).actors[0]).toMatchObject({ x: 5.5, y: 5.5, synced: true, life: 'alive' });
    expect(eventsOf(res.events, 'desync')).toHaveLength(0);
  });

  it('stops against a wall instead of pushing a body through it', () => {
    const wallBelt: EntityDef = { kind: 'conveyor', id: 'belt', cells: [8, 9, 10].map((c) => ({ c, r: 5 })), dir: 'e', speed: 2 };
    const res = resolve(room([wallBelt, sleeper('g', 'grunt', 8.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    const end = lastFrame(res).enemies[0];
    expect(end.x).toBeLessThanOrEqual(11 - 0.32 + 1e-6);
    expect(end.x).toBeGreaterThan(10.6);
  });

  it('reverses on its signal the substep it changes, and publishes <id> and <id>.rev', () => {
    const level = room([
      belt({ reverseWhen: { sig: 'sw' } } as Partial<EntityDef>),
      { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
      { kind: 'door', id: 'd', cells: [{ c: 9, r: 8 }], openWhen: { sig: 'belt.rev' } },
      sleeper('g', 'grunt', 3.5, 5.5),
    ]);
    // The switch flips at local tick 30 = substep 120: one beat east, then west.
    const res = resolve(level, [stand(0, 9.5, 2.5), toggler(1, 30)]);
    expect(trapEvents(res, 'belt')).toEqual([[120, 'conveyor:reverse']]);
    expect(enemyAt(res, 120, 'g').x).toBeCloseTo(4.5, 6);
    expect(enemyAt(res, 240, 'g').x).toBeCloseTo(3.5, 5);
    expect(Math.abs(mechAt(res, 240, 'belt').dir!)).toBeCloseTo(Math.PI, 6);
    expect(eventsOf(res.events, 'door', { id: 'd' }).some((e) => e.detail === 'open')).toBe(true);
  });

  it('stops while runWhen is false', () => {
    const res = resolve(room([belt({ runWhen: beats(4, 0, 1) } as Partial<EntityDef>), sleeper('g', 'grunt', 3.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    expect(trapEvents(res, 'belt').slice(0, 2)).toEqual([
      [119, 'conveyor:off'],
      [479, 'conveyor:on'],
    ]);
    // Runs for substeps 0..118 of the first beat only.
    expect(enemyAt(res, 400, 'g').x).toBeCloseTo(3.5 + 119 / 120, 5);
    expect(mechAt(res, 240, 'belt').on).toBe(false);
  });

  it('carries the LIVE self by what the world moves per local tick, and bakes the ride into the take', () => {
    const level = room([belt()], { start: { x: 3.5, y: 5.5 }, speeds: [1, 2] });
    const at1 = recordTake({ level, index: 0, speed: 1, script: script(), ticks: 30 });
    // 30 local ticks at 1× = 120 substeps = one tile.
    expect(at1.tape.pos[30 * 2]).toBeCloseTo(4.5, 4);
    expect(at1.tape.pos[30 * 2 + 1]).toBeCloseTo(5.5, 6);
    // At 2× the world moves half as far per local tick: the belt feels half as fast to the hands.
    const at2 = recordTake({ level, index: 0, speed: 2, script: script(), ticks: 30 });
    expect(at2.tape.pos[30 * 2]).toBeCloseTo(4.0, 4);
    // The live self is read back through its own tape: the world saw it where the belt put it.
    expect(at1.frames[29].actors[0].x).toBeCloseTo(4.5, 4);
  });

  it('a recorded ride replays unchanged when a later tape reverses the belt (no carry, no desync)', () => {
    const level = room(
      [belt({ reverseWhen: { sig: 'sw' } } as Partial<EntityDef>), { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 }],
      { start: { x: 3.5, y: 5.5 } },
    );
    const ride = recordTake({ level, index: 0, speed: 1, script: script() });
    const rideEnd = ride.tape.pos[240 * 2];
    expect(rideEnd).toBeGreaterThanOrEqual(7);
    const res = resolve(level, [ride.tape, toggler(1, 10)]);
    expect(eventsOf(res.events, 'desync')).toHaveLength(0);
    for (const f of res.frames) {
      const tick = Math.min(240, f.sub / 4);
      expect(f.actors[0].x).toBeCloseTo(ride.tape.pos[tick * 2], 5);
    }
    expect(lastFrame(res).actors[0]).toMatchObject({ life: 'alive', synced: true });
  });

  it('carries the recording ghost too: a dead live body is still a body', () => {
    const level = room([belt(), { kind: 'spikes', id: 'sp', cells: [{ c: 3, r: 5 }], upWhen: ALWAYS }], { start: { x: 3.5, y: 5.5 } });
    const take = recordTake({ level, index: 0, speed: 1, script: script(), ticks: 60 });
    expect(take.frames[59].actors[0].life).toBe('recGhost');
    expect(take.tape.pos[60 * 2]).toBeCloseTo(5.5, 4);
  });

  it('drifts a floor-height projectile sideways without turning it', () => {
    // A dart flies east along row 5 and crosses a belt running south.
    const south: EntityDef = { kind: 'conveyor', id: 'belt', cells: [4, 5, 6, 7].map((c) => ({ c, r: 5 })), dir: 's', speed: 2 };
    const level = room([south, { kind: 'dart', id: 'dl', c: 0, r: 5, dir: 'e', every: 8, speed: 4 }]);
    const res = resolve(level, [stand(0, 2.5, 2.5)]);
    const before = res.frames.find((f) => f.sub >= 160)!.projectiles[0];
    expect(before.y).toBe(5.5);
    // It is over the belt for x ∈ [4, 8) or until it drifts off row 5: 4 tiles/s east, 2 tiles/s south.
    const after = res.frames.find((f) => f.sub >= 320)!.projectiles[0];
    expect(after.y).toBeGreaterThan(5.9);
    expect(after.dir).toBe(0);
  });
});

// ───────────────────────────── bumper ─────────────────────────────

const bumper = (extra: Partial<EntityDef> = {}): EntityDef =>
  ({ kind: 'bumper', id: 'bm', c: 4, r: 5, dir: 'e', power: 3, fireWhen: beats(8, 1, 2), ...extra }) as EntityDef;

describe('bumper', () => {
  it('fires once on each rising edge and launches a grounded enemy with real knockback', () => {
    const res = resolve(room([bumper(), sleeper('g', 'grunt', 4.5, 5.5)], { bars: 4 }), [stand(0, 2.5, 2.5, 480)]);
    const fires = res.events.filter((e) => e.type === TRAP_EVENT && e.detail === 'bumper:fire');
    expect(fires.map((e) => [e.sub, e.power, e.dir])).toEqual([
      [119, 1, 0],
      [1079, 0, 0],
    ]);
    // Mass 1: thrown the full 3 tiles over the knockback slide, then it stays where it landed.
    expect(enemyAt(res, 116, 'g').x).toBe(4.5);
    expect(enemyAt(res, 200, 'g').x).toBeCloseTo(7.5, 5);
    expect(lastFrame(res).enemies[0].x).toBeCloseTo(7.5, 5);
    expect(eventsOf(res.events, 'hit')).toHaveLength(0);
  });

  it('scales the throw by mass and never moves turrets, drones or a recorded self', () => {
    const level = room([
      bumper(),
      sleeper('b', 'brute', 4.5, 5.5),
      { kind: 'bumper', id: 'bm2', c: 4, r: 3, dir: 'e', fireWhen: beats(8, 1, 2) },
      sleeper('t', 'turret', 4.5, 3.5),
      { kind: 'bumper', id: 'bm3', c: 4, r: 7, dir: 'e', fireWhen: beats(8, 1, 2) },
      sleeper('dr', 'drone', 4.5, 7.5),
      { kind: 'bumper', id: 'bm4', c: 2, r: 8, dir: 'e', fireWhen: beats(8, 1, 2) },
    ]);
    const res = resolve(level, [stand(0, 2.5, 8.5)]);
    expect(enemyAt(res, 400, 'b').x).toBeCloseTo(5.5, 5);
    expect(enemyAt(res, 400, 't').x).toBe(4.5);
    expect(enemyAt(res, 400, 'dr').x).toBe(4.5);
    expect(lastFrame(res).actors[0]).toMatchObject({ x: 2.5, y: 8.5, synced: true });
    expect(res.events.find((e) => e.type === TRAP_EVENT && e.id === 'bm4')!.power).toBe(0);
  });

  it('slams a launched enemy into a wall: the rest of the throw becomes stagger', () => {
    const res = resolve(room([bumper({ c: 9, power: 3 } as Partial<EntityDef>), sleeper('g', 'grunt', 9.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    expect(lastFrame(res).enemies[0].x).toBeLessThanOrEqual(11 - 0.32 + 1e-6);
    expect(eventsOf(res.events, 'enemyStagger', { id: 'g' }).length).toBeGreaterThan(0);
  });

  it('throws the LIVE self and records the flight as ordinary movement; playback repeats it without the plate', () => {
    const level = room([bumper()], { start: { x: 4.5, y: 5.5 } });
    const take = recordTake({ level, index: 0, speed: 1, script: script() });
    expect(take.tape.pos[29 * 2]).toBeCloseTo(4.5, 6);
    // Fired in substep 119; the 3 tiles are spread over 43 substeps = the next 11 local ticks.
    expect(take.tape.pos[45 * 2]).toBeCloseTo(7.5, 4);
    expect(take.tape.pos[240 * 2]).toBeCloseTo(7.5, 4);
    expect(take.events.find((e) => e.type === TRAP_EVENT && e.detail === 'bumper:fire')!.power).toBe(1);
    // Played back, the plate fires under nobody (the self is no longer live) and the path is the tape.
    const res = resolve(level, [take.tape]);
    expect(res.events.find((e) => e.type === TRAP_EVENT && e.detail === 'bumper:fire')!.power).toBe(0);
    expect(lastFrame(res).actors[0].x).toBeCloseTo(7.5, 4);
    expect(eventsOf(res.events, 'desync')).toHaveLength(0);
  });

  it('publishes a short pulse on its id after firing', () => {
    const res = resolve(room([bumper()]), [stand(0, 2.5, 2.5)]);
    expect(mechAt(res, 116, 'bm')).toMatchObject({ kind: 'bumper', on: false, firing: false, t: 0 });
    expect(mechAt(res, 120, 'bm')).toMatchObject({ on: true, firing: true, t: 1 });
    expect(mechAt(res, 120 + BUMPER_PULSE_SUBS + 4, 'bm')).toMatchObject({ on: false, firing: false, t: 0 });
  });
});

// ───────────────────────────── magnet ─────────────────────────────

describe('magnet', () => {
  const magnet = (onWhen = ALWAYS): EntityDef => ({ kind: 'magnet', id: 'mag', x: 8.5, y: 5.5, radius: 4, pull: 1.5, onWhen });

  it('drags enemies in range toward its centre at pull / mass and holds them just short of it', () => {
    const res = resolve(
      room([magnet(), sleeper('g', 'grunt', 5.5, 5.5), sleeper('b', 'brute', 8.5, 2.5), sleeper('far', 'grunt', 2.5, 5.5), sleeper('t', 'turret', 8.5, 7.5)]),
      [stand(0, 7.5, 5.5)],
    );
    // 1.5 tiles per second for mass 1; a third of that for the brute.
    expect(enemyAt(res, 240, 'g').x).toBeCloseTo(7.0, 5);
    expect(enemyAt(res, 240, 'b').y).toBeCloseTo(3.0, 5);
    expect(enemyAt(res, 900, 'g').x).toBeCloseTo(8.5 - 0.6, 5);
    expect(enemyAt(res, 900, 'far').x).toBe(2.5);
    expect(enemyAt(res, 900, 't')).toMatchObject({ x: 8.5, y: 7.5 });
    // Selves are never pulled.
    expect(lastFrame(res).actors[0]).toMatchObject({ x: 7.5, y: 5.5 });
  });

  it('pulls drones, and only while its signal is on', () => {
    const res = resolve(room([magnet(beats(8, 1, 2)), sleeper('dr', 'drone', 5.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    expect(trapEvents(res, 'mag')).toEqual([
      [119, 'magnet:on'],
      [239, 'magnet:off'],
    ]);
    // One beat (0.5 s) at 1.5 / 0.7 tiles per second.
    expect(lastFrame(res).enemies[0].x).toBeCloseTo(5.5 + (1.5 / 0.7) * 0.5, 4);
  });
});
