/**
 * Kernel: mechanisms, bodies under closing doors, objectives and the extension hooks.
 */
import { describe, expect, it } from 'vitest';
import { createSim, registerAbilityHandler, registerProjectileArchetype } from '../../../src/core/index';
import { DOOR_TRAVEL_SUBS } from '../../../src/core/mechanisms';
import { BASE } from '../../../src/core/tuning';
import type { LevelDef, Tape } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { baseLoadout } from '../../helpers/loadout';
import { eventsOf, pathTape, recordTake, resolve, script } from '../../helpers/script';

/** A room with a single door cell at (6, 5), closed while switch "sw" is on. */
const doorRoom = (extra: LevelDef['entities'] = []): LevelDef =>
  makeLevel({
    speeds: [1],
    bars: 2,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'switch', id: 'sw', x: 2.5, y: 4.5 },
      { kind: 'door', id: 'd1', cells: [{ c: 6, r: 5 }], openWhen: { not: { sig: 'sw' } } },
      ...extra,
    ],
  });

/** Tape B: closes the door at local tick `at`. */
const closer = (at: number): Tape => pathTape({ index: 1, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }], events: [{ tick: at, kind: 'interact' }] });

describe('doors never delete a body', () => {
  it('a door closing on a playback self desyncs it; the projection stays on its recording', () => {
    const standIn: Tape = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 6.5, y: 5.5 }] });
    const res = resolve(doorRoom(), [standIn, closer(60)]);
    const closed = eventsOf(res.events, 'door', { id: 'd1' }).filter((e) => e.detail === 'closed');
    expect(closed).toHaveLength(1);
    // Travel starts on the toggle's substep; the door turns solid once it is less than half open.
    expect(closed[0].sub).toBe(60 * 4 + DOOR_TRAVEL_SUBS / 2);
    const d = eventsOf(res.events, 'desync', { tape: 0 });
    expect(d.map((e) => [e.sub, e.detail])).toEqual([[closed[0].sub + 1, 'blocked by door d1']]);
    const last = res.frames[res.frames.length - 1].actors[0];
    expect([last.x, last.y]).toEqual([6.5, 5.5]);
    expect(last.life).toBe('alive');
    // The spark starts beside the door, never inside it.
    const spark = last.spark!;
    expect(spark.x < 6 - BASE.sparkRadius || spark.x > 7 + BASE.sparkRadius).toBe(true);
  });

  it('a door closing on the live self pushes it out to the nearest free side', () => {
    const level = doorRoom();
    // The live self walks into the doorway and stands there; tape B closes the door on it.
    const s = script().run(0, 52, 1, 0);
    const take = recordTake({ level, tapes: [closer(60)], index: 0, speed: 1, script: s });
    const closedSub = eventsOf(take.events, 'door', { id: 'd1' }).find((e) => e.detail === 'closed')!.sub;
    const before = take.frames.find((f) => f.sub >= closedSub - 4)!.actors[0];
    expect(Math.floor(before.x)).toBe(6);
    const after = take.frames.find((f) => f.sub >= closedSub + 8)!.actors[0];
    // Out of the door cell, beside it, alive and synced; and it does not fly off from the push.
    expect(after.x <= 6 - BASE.actorRadius + 1e-6 || after.x >= 7 + BASE.actorRadius - 1e-6).toBe(true);
    expect(after).toMatchObject({ life: 'alive', synced: true });
    const later = take.frames.find((f) => f.sub >= closedSub + 200)!.actors[0];
    expect(Math.abs(later.x - after.x)).toBeLessThan(0.05);
    expect(eventsOf(take.events, 'desync')).toHaveLength(0);
  });

  it('a door closing on an enemy pushes it out', () => {
    const level = doorRoom([{ kind: 'enemy', id: 'g1', type: 'grunt', x: 6.5, y: 5.3, wakeWhen: { const: false } }]);
    const res = resolve(level, [closer(10)]);
    const g = res.frames[res.frames.length - 1].enemies[0];
    expect(g.alive).toBe(true);
    const insideX = g.x > 6 - 0.32 && g.x < 7 + 0.32;
    const insideY = g.y > 5 - 0.32 && g.y < 6 + 0.32;
    expect(insideX && insideY).toBe(false);
  });
});

describe('plates, lasers and switches', () => {
  const plateLevel = (heavy: boolean): LevelDef =>
    makeLevel({
      speeds: [1],
      bars: 1,
      start: { x: 2.5, y: 5.5 },
      entities: [
        { kind: 'plate', id: 'p1', c: 5, r: 5, heavy },
        { kind: 'laser', id: 'beam', from: { x: 8.5, y: 1.5 }, to: { x: 8.5, y: 8.5 }, onWhen: { not: { sig: 'p1' } } },
      ],
    });
  const onPlate: Tape = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 30, x: 5.5, y: 5.5 }] });
  // C crosses the laser line late.
  const crosser: Tape = pathTape({ index: 2, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 60, x: 2.5, y: 7.5 }, { tick: 100, x: 10.5, y: 7.5 }] });

  it('an effective body holds a plate, which can switch a laser off for another self', () => {
    const res = resolve(plateLevel(false), [onPlate, crosser]);
    expect(eventsOf(res.events, 'plate', { id: 'p1' }).map((e) => e.detail)).toEqual(['on']);
    expect(eventsOf(res.events, 'laser', { id: 'beam' }).map((e) => e.detail)).toEqual(['off']);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
  });

  it('without the plate held the laser kills; laserProof gear ignores it', () => {
    const res = resolve(plateLevel(false), [crosser]);
    expect(eventsOf(res.events, 'selfDeath').map((e) => e.detail)).toEqual(['burned by laser beam']);
    const proof = resolve(plateLevel(false), [crosser], baseLoadout({ abilities: ['laserProof'] }));
    expect(eventsOf(proof.events, 'selfDeath')).toHaveLength(0);
  });

  it('a heavy plate needs heavyStep', () => {
    expect(eventsOf(resolve(plateLevel(true), [onPlate]).events, 'plate')).toHaveLength(0);
    expect(eventsOf(resolve(plateLevel(true), [onPlate], baseLoadout({ abilities: ['heavyStep'] })).events, 'plate')).toHaveLength(1);
  });

  it('a dead ghost does not hold a plate', () => {
    // A dies to the laser on the way, then its ghost stands on the plate.
    const level = makeLevel({
      speeds: [1],
      bars: 1,
      start: { x: 2.5, y: 5.5 },
      entities: [
        { kind: 'laser', id: 'beam', from: { x: 1.5, y: 3.5 }, to: { x: 10.5, y: 3.5 }, onWhen: { const: true } },
        { kind: 'plate', id: 'p1', c: 5, r: 1 },
      ],
    });
    const t = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 5.5, y: 1.5 }] });
    const res = resolve(level, [t]);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(1);
    expect(eventsOf(res.events, 'plate')).toHaveLength(0);
  });

  it('an interact with nothing in reach says so', () => {
    const t = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 8.5, y: 8.5 }], events: [{ tick: 10, kind: 'interact' }] });
    const res = resolve(doorRoom(), [t]);
    expect(eventsOf(res.events, 'interactFail').map((e) => e.detail)).toEqual(['nothing in reach']);
  });
});

describe('objectives', () => {
  it('reach: an alive, synced self must be in the exit when the horizon ends', () => {
    const level = makeLevel({
      speeds: [1],
      bars: 1,
      start: { x: 2.5, y: 5.5 },
      entities: [{ kind: 'exit', id: 'exit', c: 9, r: 4, w: 2, h: 2 }],
      objective: { type: 'reach', text: 'Get out' },
    });
    const goIn = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 60, x: 9.5, y: 5.0 }] });
    const ok = resolve(level, [goIn]);
    expect(ok.outcome.win).toBe(true);
    expect(eventsOf(ok.events, 'objective')).toHaveLength(1);
    expect(eventsOf(ok.events, 'objective')[0].sub).toBe(ok.horizonSubs - 1);
    // Passing through and leaving again does not count.
    const passBy = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 50, x: 9.5, y: 5.0 }, { tick: 80, x: 5.5, y: 5.0 }] });
    const no = resolve(level, [passBy]);
    expect(no.outcome.objectiveComplete).toBe(false);
    expect(no.outcome.notes.some((n) => /No alive, synced self was in the exit/.test(n))).toBe(true);
  });

  it('activate: a core needs a strike with enough momentum, and clangs otherwise', () => {
    const level = makeLevel({
      speeds: [0.5, 1],
      bars: 1,
      start: { x: 5.0, y: 5.5 },
      entities: [{ kind: 'core', id: 'c1', x: 6.0, y: 5.5, threshold: 1 }],
      objective: { type: 'activate', text: 'Light the core' },
    });
    const swing = (speed: 0.5 | 1): Tape => pathTape({ index: 0, speed, ticks: 120, path: [{ tick: 0, x: 5.0, y: 5.5 }], events: [{ tick: 10, kind: 'light', dir: 0 }] });
    const weak = resolve(level, [swing(0.5)]);
    expect(eventsOf(weak.events, 'clang', { id: 'c1' })).toHaveLength(1);
    expect(weak.outcome.objectiveComplete).toBe(false);
    expect(weak.outcome.notes.some((n) => /hit core c1 with momentum 0\.6; it needs 1\./.test(n))).toBe(true);
    const ok = resolve(level, [swing(1)]);
    expect(eventsOf(ok.events, 'core', { id: 'c1' })).toHaveLength(1);
    expect(ok.outcome.win).toBe(true);
    expect(ok.frames[ok.frames.length - 1].objective).toMatchObject({ complete: true, progress: 1, survivors: 1 });
  });
});

describe('extension hooks', () => {
  const shooter: Tape = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }], events: [{ tick: 10, kind: 'ranged', dir: 0 }] });
  const level = makeLevel({ speeds: [1], bars: 1, start: { x: 2.5, y: 5.5 }, entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 8.5, y: 5.5, wakeWhen: { const: false } }] });

  it("a recorded 'ranged' event with no archetype registered does nothing and emits nothing", () => {
    const res = resolve(level, [shooter], baseLoadout({ ranged: { archetype: 'none' as never } }));
    expect(eventsOf(res.events, 'fire')).toHaveLength(0);
    expect(res.frames.every((f) => f.projectiles.length === 0)).toBe(true);
  });

  it('a registered archetype is launched through the single ranged hook at the launch tick', () => {
    const launches: number[] = [];
    registerProjectileArchetype({
      id: 'pierce',
      launch(w, self, ev) {
        launches.push(w.s);
        w.projectiles.spawn(w, { owner: { tape: self.index }, archetype: 'pierce', x: self.pose.x, y: self.pose.y, dir: ev.dir, speed: 12, radius: 0.15, range: 20, momentum: 1.2 });
        return 1;
      },
    });
    const res = resolve(level, [shooter], baseLoadout({ ranged: { archetype: 'pierce', commit: 12 } }));
    // Launch tick = event tick + min(rangedLaunchDelay, commit - 1) local ticks.
    expect(launches).toEqual([(10 + BASE.rangedLaunchDelay) * 4]);
    expect(eventsOf(res.events, 'fire').map((e) => [e.tape, e.detail])).toEqual([[0, 'pierce']]);
    expect(eventsOf(res.events, 'kill', { id: 'g1' }).map((e) => [e.tape, e.detail])).toEqual([[0, 'pierce']]);
  });

  it('the ability hook reaches registered handlers, which can desync a self on demand', () => {
    registerAbilityHandler('manualDesync', (w, self) => w.desync(self, 'manual desync'));
    const t = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 60, x: 6.5, y: 5.5 }], events: [{ tick: 20, kind: 'ability' }] });
    const res = resolve(level, [t], baseLoadout({ abilities: ['manualDesync'] }));
    expect(eventsOf(res.events, 'desync').map((e) => [e.sub, e.detail])).toEqual([[80, 'manual desync']]);
    // The spark is right there, so it resyncs as soon as it is allowed to check.
    expect(eventsOf(res.events, 'resync')).toHaveLength(1);
  });

  it('an enemy type without a registered behaviour fails loudly', () => {
    const bad = makeLevel({ entities: [{ kind: 'enemy', id: 'b', type: 'nope' as never, x: 5, y: 5 }] });
    expect(() => createSim({ level: bad, loadout: baseLoadout(), tapes: [] })).toThrow(/No enemy behaviour registered for type 'nope'/);
  });
});

describe('dead:<enemy id> signals (data/levels/README.md "Signal expressions")', () => {
  // A sleeping one-hit grunt east of the start; a door that opens once it is dead.
  const level = makeLevel({
    speeds: [1],
    bars: 1,
    start: { x: 5.0, y: 5.5 },
    entities: [
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 6.0, y: 5.5, hp: 1, wakeWhen: { const: false } },
      { kind: 'door', id: 'gate', cells: [{ c: 9, r: 2 }], openWhen: { sig: 'dead:g1' } },
    ],
  });
  const swinger = (events: Parameters<typeof pathTape>[0]['events']): Tape => pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 5.0, y: 5.5 }], events });

  it('is false while the enemy lives and true from the update after it died', () => {
    const res = resolve(level, [swinger([{ tick: 20, kind: 'light', dir: 0 }])]);
    const kill = eventsOf(res.events, 'kill', { id: 'g1' });
    expect(kill).toHaveLength(1);
    const opened = eventsOf(res.events, 'door', { id: 'gate' }).filter((e) => e.detail === 'open');
    expect(opened).toHaveLength(1);
    expect(opened[0].sub).toBeGreaterThan(kill[0].sub);
    // Door travel starts on the first mechanisms update after the kill.
    expect(opened[0].sub).toBeLessThanOrEqual(kill[0].sub + 1 + DOOR_TRAVEL_SUBS);
  });

  it('never fires for an enemy that survives', () => {
    const res = resolve(level, [swinger([])]);
    expect(eventsOf(res.events, 'kill')).toHaveLength(0);
    expect(eventsOf(res.events, 'door', { id: 'gate' })).toHaveLength(0);
  });
});
