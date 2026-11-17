/**
 * Automated machinery that produces signals or fires on the grid: dart launchers, beam sensors,
 * relays (docs/TRAPS.md 5, 7, 8).
 */
import { describe, expect, it } from 'vitest';
import { baseLoadout } from '../../helpers/loadout';
import { TRAP_EVENT } from '../../../src/core/traps';
import type { EntityDef, Tape } from '../../../src/core/types';
import { eventsOf, pathTape, recordTake, resolve, script } from '../../helpers/script';
import { ALWAYS, NEVER, beats, enemyAt, lastFrame, mechAt, room, sleeper, stand, trapEvents } from './util';

/** A launcher in the west wall firing east along row 5 every 2 beats. */
const launcher = (extra: Partial<EntityDef> = {}): EntityDef => ({ kind: 'dart', id: 'dl', c: 0, r: 5, dir: 'e', every: 2, offset: 0, ...extra }) as EntityDef;

const toggler = (index: 0 | 1 | 2 | 3, ...at: number[]): Tape =>
  pathTape({ index, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 3.2 }], events: at.map((tick) => ({ tick, kind: 'interact' as const })) });

describe('dart launcher', () => {
  it('fires on its beat grid, never aims, and its darts stop at the far wall', () => {
    const res = resolve(room([launcher()]), [stand(0, 2.5, 2.5)]);
    expect(trapEvents(res, 'dl')).toEqual([
      [0, 'dart:fire'],
      [240, 'dart:fire'],
      [480, 'dart:fire'],
      [720, 'dart:fire'],
    ]);
    const p = res.frames.find((f) => f.sub >= 60)!.projectiles[0];
    expect(p).toMatchObject({ archetype: 'dart', owner: { enemy: 'dl' }, y: 5.5, dir: 0 });
    const walls = eventsOf(res.events, 'projectileHit').filter((e) => e.detail === 'dart:wall');
    // 9.87 tiles at 8 tiles/s is 296 substeps: the dart fired on beat 6 is still flying at the horizon.
    expect(walls.map((e) => e.sub)).toEqual([296, 536, 776]);
    expect(walls[0].x).toBeCloseTo(11, 6);
    expect(mechAt(res, 4, 'dl')).toMatchObject({ kind: 'dart', on: true, firing: true, dir: 0 });
    expect(mechAt(res, 120, 'dl').t).toBeCloseTo(0.5, 2);
    expect(mechAt(res, 120, 'dl').firing).toBe(false);
  });

  it('honours offset and enabledWhen', () => {
    const res = resolve(room([launcher({ every: 4, offset: 1, enabledWhen: { not: beats(8, 4, 8) } } as Partial<EntityDef>)]), [stand(0, 2.5, 2.5)]);
    // Grid: beats 1 and 5; the second falls in the disabled half.
    expect(trapEvents(res, 'dl').filter(([, d]) => d === 'dart:fire')).toEqual([[120, 'dart:fire']]);
  });

  it('kills the first vulnerable self in its lane and names the launcher', () => {
    const res = resolve(room([launcher()]), [stand(0, 5.5, 5.5), stand(1, 8.5, 5.5), stand(2, 5.5, 4.5)]);
    const deaths = eventsOf(res.events, 'selfDeath');
    expect(deaths.map((e) => [e.tape, e.detail])).toEqual([
      [0, 'shot by dart launcher dl'],
      [1, 'shot by dart launcher dl'],
    ]);
    // The first dart stops in tape 0; the second (two beats later) flies through its ghost to tape 1.
    expect(deaths[0].sub).toBeLessThan(240);
    expect(deaths[1].sub).toBeGreaterThan(240);
    expect(lastFrame(res).actors[2].life).toBe('alive');
  });

  it('passes through a self inside dodge i-frames and through the recording ghost', () => {
    // The first dart reaches x ≈ 5.08 at substep ~119: a dodge at tick 28 covers substeps [116, 156).
    const dodger = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 5.5, y: 5.5 }, { tick: 28, x: 5.5, y: 5.5 }, { tick: 42, x: 5.5, y: 3.5 }], events: [{ tick: 28, kind: 'dodge' }] });
    const res = resolve(room([launcher({ every: 8 } as Partial<EntityDef>)]), [dodger]);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
    const level = room([launcher({ every: 1 } as Partial<EntityDef>)], { start: { x: 5.5, y: 5.5 } });
    const take = recordTake({ level, index: 0, speed: 1, script: script() });
    expect(eventsOf(take.events, 'selfDeath')).toHaveLength(1);
    expect(take.frames[take.frames.length - 1].actors[0].life).toBe('recGhost');
  });

  it('strikes enemies in its lane: 1 damage, a stagger, no knockback, kill credited to the launcher', () => {
    const res = resolve(room([launcher(), sleeper('g', 'grunt', 6.5, 5.5), sleeper('b', 'brute', 9.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    const kills = eventsOf(res.events, 'kill');
    // The first dart stops in the grunt; the brute behind it takes the next three where it stands.
    expect(kills.map((e) => [e.id, e.detail, e.tape])).toEqual([
      ['g', 'dart', undefined],
      ['b', 'dart', undefined],
    ]);
    expect(eventsOf(res.events, 'hit', { id: 'b' })).toHaveLength(3);
    expect(enemyAt(res, 900, 'b')).toMatchObject({ alive: true, hp: 1, x: 9.5 });
    expect(res.frames[res.frames.length - 1].enemies.find((e) => e.id === 'b')).toMatchObject({ alive: false, x: 9.5 });
    expect(res.outcome.objectiveComplete).toBe(true);
  });

  it('is blocked by an extended crusher, and a sealed muzzle fires nothing', () => {
    const level = room([
      launcher({ every: 1 } as Partial<EntityDef>),
      { kind: 'crusher', id: 'cr', cells: [{ c: 6, r: 5 }], extendWhen: beats(8, 1.5, 4) },
      { kind: 'crusher', id: 'plug', cells: [{ c: 1, r: 5 }], extendWhen: beats(8, 5.5, 6.5) },
    ]);
    const res = resolve(level, [stand(0, 9.5, 2.5)]);
    const stops = eventsOf(res.events, 'projectileHit').filter((e) => e.detail === 'dart:wall').map((e) => Math.round(e.x));
    // In order of impact: the beat-1 dart meets the piston (which slammed at beat 1.5) before the
    // beat-0 dart reaches the east wall; beats 2 and 3 hit the piston face; beats 4 and 5 fly free.
    expect(stops).toEqual([6, 11, 6, 6, 11, 11]);
    // Beat 6 is plugged at the muzzle: no dart at all. Beat 7's dart is still flying at the horizon.
    expect(trapEvents(res, 'dl').map(([s]) => s)).toEqual([0, 120, 240, 360, 480, 600, 840]);
  });

  it("the 'parry' ability turns a dart like any enemy shot", () => {
    const level = room([launcher({ every: 8 } as Partial<EntityDef>)]);
    // Heavy swing facing west: windup 16 ticks, active ticks [28, 33) = substeps [112, 132).
    const parry = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 5.5, y: 5.5 }], events: [{ tick: 12, kind: 'heavy', dir: Math.PI }] });
    const res = resolve(level, [parry], baseLoadout({ abilities: ['parry'] }));
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
    expect(eventsOf(res.events, 'projectileHit').some((e) => e.detail === 'parry' && e.id === 'dl')).toBe(true);
  });
});

// ───────────────────────────── sensor ─────────────────────────────

/** A vertical beam across the room at x = 5.5. */
const beam = (extra: Partial<EntityDef> = {}): EntityDef => ({ kind: 'sensor', id: 'trip', from: { x: 5.5, y: 1 }, to: { x: 5.5, y: 9 }, ...extra }) as EntityDef;

const crosser = (index: 0 | 1 | 2 | 3): Tape => pathTape({ index, speed: 1, ticks: 240, path: [{ tick: 0, x: 3.5, y: 5.5 }, { tick: 60, x: 7.5, y: 5.5 }] });

describe('beam sensor', () => {
  it('is true exactly while an effective self breaks the beam', () => {
    const res = resolve(room([beam()]), [crosser(0)]);
    const ev = trapEvents(res, 'trip');
    expect(ev.map(([, d]) => d)).toEqual(['sensor:on', 'sensor:off']);
    // The body (radius 0.3) overlaps x = 5.5 while its centre is in (5.2, 5.8): local ticks 25.5..34.5.
    expect(ev[0][0]).toBeGreaterThanOrEqual(100);
    expect(ev[0][0]).toBeLessThanOrEqual(104);
    expect(ev[1][0]).toBeGreaterThanOrEqual(136);
    expect(ev[1][0]).toBeLessThanOrEqual(140);
    expect(mechAt(res, 120, 'trip')).toMatchObject({ kind: 'sensor', on: true, reach: 8 });
    expect(mechAt(res, 200, 'trip').on).toBe(false);
  });

  it('feeds mechanisms the same substep: a door driven by it starts moving at once', () => {
    const level = room([beam(), { kind: 'door', id: 'd', cells: [{ c: 9, r: 8 }], openWhen: { sig: 'trip' } }]);
    const res = resolve(level, [crosser(0)]);
    const on = trapEvents(res, 'trip')[0][0];
    const open = eventsOf(res.events, 'door', { id: 'd' }).find((e) => e.detail === 'open')!;
    expect(open.sub).toBe(on + 17);
  });

  it('ignores dead ghosts and desynced projections; sees the recording ghost in its own take', () => {
    // Tape 0 dies on spikes before the beam: its ghost crosses unseen.
    const level = room([beam(), { kind: 'spikes', id: 'sp', cells: [{ c: 4, r: 5 }], upWhen: ALWAYS }]);
    const res = resolve(level, [crosser(0)]);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(1);
    expect(trapEvents(res, 'trip')).toEqual([]);
    // Tape 0 desyncs against a crusher wall before the beam; the projection crosses unseen.
    const walled = room([beam(), { kind: 'crusher', id: 'cr', cells: [1, 2, 3, 4, 5, 6, 7, 8].map((r) => ({ c: 4, r })), extendWhen: ALWAYS }]);
    const res2 = resolve(walled, [crosser(0)]);
    expect(eventsOf(res2.events, 'desync')).toHaveLength(1);
    expect(trapEvents(res2, 'trip')).toEqual([]);
    // The live take: the same death, but the recording ghost still has a body and trips it.
    const take = recordTake({ level: room([beam(), { kind: 'spikes', id: 'sp', cells: [{ c: 4, r: 5 }], upWhen: ALWAYS }], { start: { x: 3.5, y: 5.5 } }), index: 0, speed: 1, script: script().run(0, 60, 1, 0) });
    expect(take.frames[take.frames.length - 1].actors[0].life).toBe('recGhost');
    expect(take.events.some((e) => e.type === TRAP_EVENT && e.detail === 'sensor:on')).toBe(true);
  });

  it('detects enemies (drones too), and `detects` narrows who counts', () => {
    const belt: EntityDef = { kind: 'conveyor', id: 'belt', cells: [3, 4, 5, 6].map((c) => ({ c, r: 5 })), dir: 'e', speed: 2 };
    const any = resolve(room([beam(), belt, sleeper('g', 'grunt', 3.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    expect(trapEvents(any, 'trip').map(([, d]) => d)).toEqual(['sensor:on', 'sensor:off']);
    const selvesOnly = resolve(room([beam({ detects: 'selves' } as Partial<EntityDef>), belt, sleeper('g', 'grunt', 3.5, 5.5)]), [stand(0, 2.5, 2.5)]);
    expect(trapEvents(selvesOnly, 'trip')).toEqual([]);
    const enemiesOnly = resolve(room([beam({ detects: 'enemies' } as Partial<EntityDef>)]), [crosser(0)]);
    expect(trapEvents(enemiesOnly, 'trip')).toEqual([]);
    const drone = resolve(room([beam({ detects: 'enemies' } as Partial<EntityDef>), sleeper('dr', 'drone', 5.6, 3.5)]), [stand(0, 2.5, 2.5)]);
    expect(mechAt(drone, 0, 'trip').on).toBe(true);
  });

  it('is cut at the first tile that blocks shots: a body beyond a closed door is not seen', () => {
    const door: EntityDef = { kind: 'door', id: 'd', cells: [{ c: 5, r: 4 }], openWhen: NEVER };
    const res = resolve(room([beam(), door, sleeper('g', 'grunt', 5.5, 6.5), sleeper('h', 'grunt', 5.5, 2.5, { wakeWhen: { sig: 'trip' } })]), [stand(0, 2.5, 2.5)]);
    // The grunt at row 2 (before the door) trips it; reach stops at the door face (y = 4).
    expect(mechAt(res, 0, 'trip')).toMatchObject({ on: true, reach: 3 });
    const blind = resolve(room([beam(), door, sleeper('g', 'grunt', 5.5, 6.5)]), [stand(0, 2.5, 2.5)]);
    expect(mechAt(blind, 400, 'trip')).toMatchObject({ on: false, reach: 3 });
  });

  it('latches when asked to', () => {
    const res = resolve(room([beam({ latch: true } as Partial<EntityDef>)]), [crosser(0)]);
    expect(trapEvents(res, 'trip').map(([, d]) => d)).toEqual(['sensor:on']);
    expect(mechAt(res, 900, 'trip').on).toBe(true);
  });
});

// ───────────────────────────── relay ─────────────────────────────

describe('relay', () => {
  const sw: EntityDef = { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 };
  const relay = (extra: Partial<EntityDef> = {}): EntityDef => ({ kind: 'relay', id: 'rl', trigger: { sig: 'sw' }, ...extra }) as EntityDef;

  it('pulse: arms on the rising edge, fires on the next beat, holds one beat', () => {
    // The switch goes on at local tick 10 (substep 40).
    const res = resolve(room([sw, relay()]), [stand(0, 9.5, 8.5), toggler(1, 10)]);
    expect(trapEvents(res, 'rl')).toEqual([
      [40, 'relay:armed'],
      [119, 'relay:on'],
      [239, 'relay:off'],
    ]);
    expect(mechAt(res, 80, 'rl')).toMatchObject({ kind: 'relay', on: false, warn: 1 });
    expect(mechAt(res, 80, 'rl').t).toBeCloseTo((80 - 41) / (120 - 41), 5);
    expect(mechAt(res, 120, 'rl')).toMatchObject({ on: true, warn: 0, t: 0 });
  });

  it('quantize, delay and hold are in master beats; quantize 0 fires on the trigger substep', () => {
    const res = resolve(room([sw, relay({ quantize: 2, delay: 1, hold: 0.5 } as Partial<EntityDef>), relay({ id: 'now', quantize: 0, hold: 0.25 } as Partial<EntityDef>)]), [stand(0, 9.5, 8.5), toggler(1, 10)]);
    expect(trapEvents(res, 'rl').filter(([, d]) => d !== 'relay:armed')).toEqual([
      [359, 'relay:on'],
      [419, 'relay:off'],
    ]);
    expect(trapEvents(res, 'now').filter(([, d]) => d !== 'relay:armed')).toEqual([
      [40, 'relay:on'],
      [70, 'relay:off'],
    ]);
  });

  it('ignores triggers while armed or pulsing, and publishes <id>.armed', () => {
    // On at tick 10, off at 14, on again at 18 (still armed), off at 40, on at 50 (pulse running).
    const level = room([sw, relay({ hold: 2 } as Partial<EntityDef>), { kind: 'door', id: 'd', cells: [{ c: 9, r: 8 }], openWhen: { sig: 'rl.armed' } }]);
    const res = resolve(level, [stand(0, 9.5, 2.5), toggler(1, 10, 21, 32, 43, 54)]);
    expect(trapEvents(res, 'rl')).toEqual([
      [40, 'relay:armed'],
      [119, 'relay:on'],
      [359, 'relay:off'],
    ]);
    expect(eventsOf(res.events, 'door', { id: 'd' }).map((e) => e.detail)).toEqual(['open', 'closed']);
  });

  it('latch stays on; toggle flips on each firing', () => {
    const latch = resolve(room([sw, relay({ mode: 'latch' } as Partial<EntityDef>)]), [stand(0, 9.5, 8.5), toggler(1, 10, 80, 150)]);
    expect(trapEvents(latch, 'rl')).toEqual([
      [40, 'relay:armed'],
      [119, 'relay:on'],
    ]);
    expect(mechAt(latch, 950, 'rl').on).toBe(true);
    // Rising edges at ticks 10 and 150 (the press at 80 turns the switch off).
    const toggle = resolve(room([sw, relay({ mode: 'toggle' } as Partial<EntityDef>)]), [stand(0, 9.5, 8.5), toggler(1, 10, 80, 150)]);
    expect(trapEvents(toggle, 'rl').filter(([, d]) => d !== 'relay:armed')).toEqual([
      [119, 'relay:on'],
      [719, 'relay:off'],
    ]);
  });

  it('gives a signal-driven hazard its telegraph: the forecast follows the armed relay', () => {
    const level = room([sw, relay({ delay: 1 } as Partial<EntityDef>), { kind: 'crusher', id: 'cr', cells: [{ c: 6, r: 5 }], extendWhen: { sig: 'rl' } }]);
    const res = resolve(level, [stand(0, 9.5, 8.5), toggler(1, 10)]);
    // Armed at 40, fires at beat 2 (substep 239): the crusher warns from one beat before the slam.
    const cr = trapEvents(res, 'cr');
    expect(cr.find(([, d]) => d === 'crusher:slam')![0]).toBe(239);
    const warn = cr.find(([, d]) => d === 'crusher:warn')![0];
    expect(warn).toBeGreaterThanOrEqual(119);
    expect(warn).toBeLessThanOrEqual(135);
    expect(mechAt(res, 180, 'cr').warn).toBeCloseTo(0.5, 2);
    expect(mechAt(res, 60, 'cr').warn).toBe(0);
  });
});
