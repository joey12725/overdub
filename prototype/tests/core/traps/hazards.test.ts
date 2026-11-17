/**
 * Traps that hurt: spikes, crushers, flame jets (docs/TRAPS.md 1, 2, 4).
 */
import { describe, expect, it } from 'vitest';
import { BASE } from '../../../src/core/tuning';
import { CRUSHER_RETRACT_SUBS } from '../../../src/core/traps';
import { TRAP_EVENT } from '../../../src/core/traps';
import type { EntityDef, Tape } from '../../../src/core/types';
import { eventsOf, pathTape, recordTake, resolve, script } from '../../helpers/script';
import { ALWAYS, NEVER, beats, enemyAt, lastFrame, mechAt, room, sleeper, stand, trapEvents } from './util';

const spikes = (upWhen = beats(4, 1, 2), extra: Partial<EntityDef> = {}): EntityDef =>
  ({ kind: 'spikes', id: 'sp', cells: [{ c: 5, r: 5 }, { c: 6, r: 5 }], upWhen, ...extra }) as EntityDef;

describe('spikes', () => {
  it('raise and drop exactly with the signal, publish their id and telegraph one beat ahead', () => {
    const res = resolve(room([spikes(), { kind: 'door', id: 'd', cells: [{ c: 9, r: 8 }], openWhen: { sig: 'sp' } }]), [stand(0, 2.5, 2.5)]);
    expect(trapEvents(res, 'sp')).toEqual([
      [0, 'spikes:warn'],
      [119, 'spikes:up'],
      [239, 'spikes:down'],
      [479, 'spikes:warn'],
      [599, 'spikes:up'],
      [719, 'spikes:down'],
    ]);
    expect(mechAt(res, 0, 'sp')).toMatchObject({ kind: 'spikes', on: false, t: 0, warn: 0 });
    expect(mechAt(res, 60, 'sp').warn).toBeCloseTo(0.5, 5);
    expect(mechAt(res, 120, 'sp')).toMatchObject({ on: true, t: 1, warn: 0 });
    expect(mechAt(res, 240, 'sp')).toMatchObject({ on: false, t: 0 });
    // The id is an ordinary signal: a door driven by it opens one substep after the spikes rise.
    const opened = eventsOf(res.events, 'door', { id: 'd' }).filter((e) => e.detail === 'open');
    // Spikes rise in substep 119; the door reads the signal from substep 120 and is half open (18 of
    // 36 travel substeps) in substep 137.
    expect(opened[0].sub).toBe(120 + 17);
  });

  it('kill a playback self standing on a raised cell, and only there', () => {
    const res = resolve(room([spikes()]), [stand(0, 5.5, 5.5), stand(1, 7.2, 5.5)]);
    const deaths = eventsOf(res.events, 'selfDeath');
    expect(deaths.map((e) => [e.tape, e.sub, e.detail])).toEqual([[0, 119, 'skewered by spikes sp']]);
    expect(lastFrame(res).actors.map((a) => a.life)).toEqual(['ghost', 'alive']);
    expect(res.outcome.notes.join(' ')).toMatch(/spikes sp/);
  });

  it('a recorded dodge carries a playback self across; without it the same path dies', () => {
    // Raised for a quarter beat (30 substeps). The dodge at local tick 28 is invulnerable for
    // ticks [29, 39) = substeps [116, 156), which covers the whole window [119, 149).
    const path = [{ tick: 0, x: 4.4, y: 5.5 }, { tick: 28, x: 4.4, y: 5.5 }, { tick: 42, x: 7.4, y: 5.5 }];
    const level = room([spikes(beats(8, 1, 1.25))]);
    const dodging: Tape = pathTape({ index: 0, speed: 1, ticks: 240, path, events: [{ tick: 28, kind: 'dodge' }] });
    const walking: Tape = pathTape({ index: 0, speed: 1, ticks: 240, path });
    expect(eventsOf(resolve(level, [dodging]).events, 'selfDeath')).toHaveLength(0);
    const d = eventsOf(resolve(level, [walking]).events, 'selfDeath');
    expect(d).toHaveLength(1);
    expect(d[0].sub).toBeGreaterThanOrEqual(119);
    expect(d[0].sub).toBeLessThan(149);
  });

  it('kill the live self once; the recording ghost then walks over raised spikes freely', () => {
    const level = room([spikes(ALWAYS)], { start: { x: 3.5, y: 5.5 } });
    const take = recordTake({ level, index: 0, speed: 1, script: script().run(0, 200, 1, 0) });
    const deaths = eventsOf(take.events, 'selfDeath');
    expect(deaths).toHaveLength(1);
    expect(deaths[0].detail).toBe('skewered by spikes sp');
    const end = take.frames[take.frames.length - 1].actors[0];
    expect(end.life).toBe('recGhost');
    expect(end.x).toBeGreaterThan(8);
  });

  it('never touch a dead ghost: a self killed elsewhere crosses raised spikes without a second death', () => {
    // Tape 0 dies on the first spike strip at x 2..3, then its ghost walks through the second.
    const level = room([
      { kind: 'spikes', id: 'a', cells: [{ c: 2, r: 5 }], upWhen: ALWAYS },
      spikes(ALWAYS),
    ]);
    const walker = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 1.5, y: 5.5 }, { tick: 120, x: 9.5, y: 5.5 }] });
    const res = resolve(level, [walker]);
    expect(eventsOf(res.events, 'selfDeath').map((e) => e.detail)).toEqual(['skewered by spikes a']);
    expect(lastFrame(res).actors[0]).toMatchObject({ life: 'ghost', x: 9.5 });
  });

  it('kill a grunt on contact and credit the trap; hit a brute once per beat of contact', () => {
    const res = resolve(room([spikes(ALWAYS), sleeper('g', 'grunt', 5.5, 5.5), sleeper('b', 'brute', 6.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    const kills = eventsOf(res.events, 'kill');
    expect(kills.map((e) => [e.id, e.sub, e.detail, e.tape])).toEqual([
      ['g', 0, 'spikes', undefined],
      ['b', 240, 'spikes', undefined],
    ]);
    expect(eventsOf(res.events, 'hit', { id: 'b' }).map((e) => e.sub)).toEqual([0, 120, 240]);
    expect(enemyAt(res, 124, 'b').hp).toBe(1);
    expect(res.outcome.objectiveComplete).toBe(true);
  });

  it('leaving the spikes resets the contact clock; a drone overhead is never touched', () => {
    // The brute rides a belt off the spikes after one hit; the drone hovers on a raised cell throughout.
    const res = resolve(
      room([
        spikes(ALWAYS),
        { kind: 'conveyor', id: 'belt', cells: [{ c: 6, r: 5 }], dir: 'e', speed: 2 },
        sleeper('b', 'brute', 6.5, 5.5),
        sleeper('dr', 'drone', 5.5, 5.5),
      ]),
      [stand(0, 2.5, 2.5)],
    );
    expect(eventsOf(res.events, 'hit', { id: 'b' }).map((e) => e.sub)).toEqual([0]);
    expect(eventsOf(res.events, 'hit', { id: 'dr' })).toHaveLength(0);
    expect(enemyAt(res, 900, 'dr')).toMatchObject({ alive: true, hp: 2 });
  });

  it("a shielder's shield and the boss's armour absorb trap damage like any other non-tape hit", () => {
    const res = resolve(room([spikes(ALWAYS), sleeper('s', 'shielder', 5.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    expect(eventsOf(res.events, 'kill')).toHaveLength(0);
    expect(eventsOf(res.events, 'clang', { id: 's' }).length).toBeGreaterThan(0);
    expect(enemyAt(res, 900, 's')).toMatchObject({ alive: true, hp: 2 });
  });
});

// ───────────────────────────── crusher ─────────────────────────────

/** A piston across the whole room at column 5 (interior rows 1..8). */
const wallCrusher = (extendWhen = beats(8, 1, 2), extra: Partial<EntityDef> = {}): EntityDef =>
  ({ kind: 'crusher', id: 'cr', cells: [1, 2, 3, 4, 5, 6, 7, 8].map((r) => ({ c: 5, r })), extendWhen, ...extra }) as EntityDef;

describe('crusher', () => {
  it('strokes on the signal, stays solid through a fixed retract, then opens', () => {
    const res = resolve(room([wallCrusher()]), [stand(0, 2.5, 2.5)]);
    expect(trapEvents(res, 'cr')).toEqual([
      [0, 'crusher:warn'],
      [119, 'crusher:slam'],
      [239, 'crusher:retract'],
      [239 + CRUSHER_RETRACT_SUBS, 'crusher:open'],
    ]);
    expect(mechAt(res, 116, 'cr')).toMatchObject({ kind: 'crusher', on: false, t: 0 });
    expect(mechAt(res, 120, 'cr')).toMatchObject({ on: true, t: 1, warn: 0 });
    const mid = mechAt(res, 272, 'cr');
    expect(mid.on).toBe(true);
    expect(mid.t).toBeCloseTo(1 - 32 / CRUSHER_RETRACT_SUBS, 5);
    expect(mechAt(res, 300, 'cr')).toMatchObject({ on: false, t: 0 });
    // Inferred from the first two cells: the piston travels toward higher rows.
    expect(mechAt(res, 0, 'cr').dir).toBeCloseTo(Math.PI / 2, 6);
  });

  it('kills a self standing on a cell at the stroke; one standing beside it is only walled off', () => {
    const res = resolve(room([wallCrusher()]), [stand(0, 5.5, 4.5), stand(1, 4.5, 4.5)]);
    expect(eventsOf(res.events, 'selfDeath').map((e) => [e.tape, e.sub, e.detail])).toEqual([[0, 119, 'crushed by crusher cr']]);
    expect(eventsOf(res.events, 'desync')).toHaveLength(0);
    expect(lastFrame(res).actors[1]).toMatchObject({ life: 'alive', synced: true });
    expect(res.events.find((e) => e.type === TRAP_EVENT && e.detail === 'crusher:slam')!.power).toBe(1);
  });

  it('is not lethal to touch: a playback self walking into the extended piston desyncs and recovers when it retracts', () => {
    // Extended for beats [0.5, 3). The walker reaches the piston face around substep 176.
    const level = room([wallCrusher(beats(8, 0.5, 3))]);
    const walker = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 120, x: 8.5, y: 5.5 }] });
    const res = resolve(level, [walker]);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
    const desync = eventsOf(res.events, 'desync', { tape: 0 });
    expect(desync).toHaveLength(1);
    expect(desync[0].detail).toBe('blocked by crusher cr');
    expect(desync[0].sub).toBeGreaterThan(160);
    expect(desync[0].sub).toBeLessThan(200);
    // While the piston is out the spark waits on the near side: the piston seals the room.
    const waiting = res.frames.find((f) => f.sub >= 340)!.actors[0];
    expect(waiting.synced).toBe(false);
    expect(waiting.spark!.x).toBeLessThan(5 - BASE.sparkRadius + 1e-6);
    expect(waiting.x).toBeGreaterThan(6);
    // It opens at 359 + 60; only then can the spark cross and catch the projection.
    const open = trapEvents(res, 'cr').find(([, d]) => d === 'crusher:open')![0];
    expect(open).toBe(359 + CRUSHER_RETRACT_SUBS);
    const resync = eventsOf(res.events, 'resync', { tape: 0 });
    expect(resync).toHaveLength(1);
    expect(resync[0].sub).toBeGreaterThan(open);
    expect(lastFrame(res).actors[0]).toMatchObject({ life: 'alive', synced: true, x: 8.5 });
    expect(lastFrame(res).actors[0].spark).toBeUndefined();
    expect(res.outcome.notes.join(' ')).toMatch(/crusher cr/);
  });

  it('a self that dodges through the stroke survives it but is desynced by the solid piston', () => {
    // Standing on the cell, dodging on the spot: i-frames cover the stroke substep 119.
    const dodger = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 5.5, y: 4.5 }], events: [{ tick: 28, kind: 'dodge' }] });
    const res = resolve(room([wallCrusher()]), [dodger]);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
    expect(eventsOf(res.events, 'desync').map((e) => [e.sub, e.detail])).toEqual([[120, 'blocked by crusher cr']]);
  });

  it('crushes enemies on the stroke and pushes survivors out of the piston; a dead ghost is ignored', () => {
    const res = resolve(
      room([wallCrusher(), sleeper('g', 'grunt', 5.5, 2.5), sleeper('b', 'brute', 5.5, 4.5), sleeper('dr', 'drone', 5.5, 6.5), sleeper('tough', 'grunt', 5.4, 7.5, { hp: 5 })]),
      [stand(0, 2.5, 2.5)],
    );
    expect(eventsOf(res.events, 'kill').map((e) => [e.id, e.sub, e.detail])).toEqual([
      ['g', 119, 'crusher'],
      ['b', 119, 'crusher'],
      ['dr', 119, 'crusher'],
    ]);
    // The tough grunt (5 hp) takes 3 and is shoved out to the nearest side.
    const tough = enemyAt(res, 124, 'tough');
    expect(tough).toMatchObject({ alive: true, hp: 2 });
    expect(tough.x).toBeLessThanOrEqual(5 - 0.32 + 1e-6);
    // Bodies die where they were crushed.
    expect(enemyAt(res, 124, 'g')).toMatchObject({ x: 5.5, y: 2.5 });
  });

  it('kills the live self on the stroke and its body is pushed out, never deleted', () => {
    const level = room([wallCrusher()], { start: { x: 5.5, y: 4.5 } });
    const take = recordTake({ level, index: 0, speed: 1, script: script() });
    expect(eventsOf(take.events, 'selfDeath').map((e) => e.detail)).toEqual(['crushed by crusher cr']);
    const after = take.frames.find((f) => f.sub >= 140)!.actors[0];
    expect(after.life).toBe('recGhost');
    expect(after.x <= 5 - BASE.actorRadius + 1e-6 || after.x >= 6 + BASE.actorRadius - 1e-6).toBe(true);
  });

  it('starts extended, with no stroke, when its signal is true at beat zero', () => {
    const res = resolve(room([wallCrusher(ALWAYS), sleeper('g', 'grunt', 3.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    expect(trapEvents(res, 'cr')).toEqual([]);
    expect(mechAt(res, 0, 'cr')).toMatchObject({ on: true, t: 1 });
    expect(eventsOf(res.events, 'kill')).toHaveLength(0);
  });

  it('re-extends without a second stroke if the signal returns during the retract', () => {
    // Off for an eighth of a beat (15 substeps) — shorter than the retract.
    const level = room([wallCrusher({ or: [beats(8, 1, 2), beats(8, 2.125, 3)] }), sleeper('g', 'grunt', 3.5, 5.5)]);
    const res = resolve(level, [stand(0, 2.5, 2.5)]);
    expect(trapEvents(res, 'cr').filter(([, d]) => d !== 'crusher:warn')).toEqual([
      [119, 'crusher:slam'],
      [239, 'crusher:retract'],
      [254, 'crusher:hold'],
      [359, 'crusher:retract'],
      [359 + CRUSHER_RETRACT_SUBS, 'crusher:open'],
    ]);
  });
});

// ───────────────────────────── flame ─────────────────────────────

const flame = (onWhen = beats(4, 1, 2), extra: Partial<EntityDef> = {}): EntityDef =>
  ({ kind: 'flame', id: 'fl', c: 0, r: 5, dir: 'e', range: 8, onWhen, ...extra }) as EntityDef;

describe('flame jet', () => {
  it('burns selves on the covered tiles while on, and nothing off its lane', () => {
    const res = resolve(room([flame()]), [stand(0, 3.5, 5.5), stand(1, 3.5, 4.5), stand(2, 9.5, 5.5)]);
    expect(eventsOf(res.events, 'selfDeath').map((e) => [e.tape, e.sub, e.detail])).toEqual([[0, 119, 'burned by flame jet fl']]);
    expect(trapEvents(res, 'fl').slice(0, 3)).toEqual([
      [0, 'flame:warn'],
      [119, 'flame:on'],
      [239, 'flame:off'],
    ]);
    expect(mechAt(res, 120, 'fl')).toMatchObject({ kind: 'flame', on: true, reach: 8, dir: 0 });
    // Range 8 from the nozzle at column 0 covers columns 1..8; column 9 is out of reach.
    expect(lastFrame(res).actors[2].life).toBe('alive');
  });

  it('is cut short by a closed door and released the moment it opens (doors are shields)', () => {
    // The door at column 5 is shut until tape 1 throws the switch at local tick 150 (substep 600).
    const level = room([
      flame(ALWAYS),
      { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
      { kind: 'door', id: 'door', cells: [{ c: 5, r: 5 }], openWhen: { sig: 'sw' } },
    ]);
    const behind = stand(0, 7.5, 5.5);
    const opener = pathTape({ index: 1, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 3.2 }], events: [{ tick: 150, kind: 'interact' }] });
    const shut = resolve(level, [behind]);
    expect(eventsOf(shut.events, 'selfDeath')).toHaveLength(0);
    expect(mechAt(shut, 400, 'fl').reach).toBe(4);
    const opened = resolve(level, [behind, opener]);
    const doorOpen = eventsOf(opened.events, 'door', { id: 'door' }).find((e) => e.detail === 'open')!.sub;
    const death = eventsOf(opened.events, 'selfDeath', { tape: 0 });
    expect(death).toHaveLength(1);
    // Traps run after mechanisms in the same substep: the fire is through as the door turns passable.
    expect(death[0].sub).toBe(doorOpen);
    expect(mechAt(opened, doorOpen + 4, 'fl').reach).toBe(8);
  });

  it('is stopped by an extended crusher and passes over a low barrier', () => {
    const map = ['############', '#..........#', '#..........#', '#..........#', '#..........#', '#..=.......#', '#..........#', '#..........#', '#..........#', '############'];
    const level = room(
      [flame(ALWAYS), { kind: 'crusher', id: 'cr', cells: [{ c: 7, r: 5 }], extendWhen: beats(8, 2, 4) }],
      { map, start: { x: 1.5, y: 1.5 } },
    );
    const res = resolve(level, [stand(0, 2.5, 2.5)]);
    expect(mechAt(res, 60, 'fl').reach).toBe(8);
    expect(mechAt(res, 300, 'fl').reach).toBe(6);
  });

  it('burns every enemy type on contact and once per beat, drones included', () => {
    const res = resolve(room([flame(ALWAYS), sleeper('dr', 'drone', 2.5, 5.5), sleeper('b', 'brute', 4.5, 5.5), sleeper('t', 'turret', 6.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    expect(eventsOf(res.events, 'kill').map((e) => [e.id, e.sub, e.detail])).toEqual([
      ['t', 0, 'flame'],
      ['dr', 120, 'flame'],
      ['b', 240, 'flame'],
    ]);
  });

  it('does not hurt the recording ghost or a desynced projection', () => {
    const level = room([flame(ALWAYS), { kind: 'crusher', id: 'cr', cells: [1, 2, 3, 4, 6, 7, 8].map((r) => ({ c: 2, r })), extendWhen: NEVER }], { start: { x: 3.5, y: 3.5 } });
    const take = recordTake({ level, index: 0, speed: 1, script: script().run(0, 60, 0, 1) });
    expect(eventsOf(take.events, 'selfDeath')).toHaveLength(1);
    expect(take.frames[take.frames.length - 1].actors[0].life).toBe('recGhost');
  });
});
