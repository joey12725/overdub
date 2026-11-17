/**
 * Gear abilities that are simulation rules (AbilityId): manualDesync, lowProfile, loudmouth,
 * beatSight, laserProof, heavyStep, phaseDodge, slideStrike, parry, killRefresh.
 */
import { describe, expect, it } from 'vitest';
import { effectiveDistance, LOUDMOUTH_FACTOR, LOW_PROFILE_FACTOR, SLIDE_STRIKE_MUL } from '../../../src/core/abilities';
import { createSim } from '../../../src/core/index';
import type { EntityDef, LevelDef, MapRows, Resolution, Tape } from '../../../src/core/types';
import { makeLevel, OPEN_ROOM } from '../../helpers/levels';
import { baseLoadout } from '../../helpers/loadout';
import { eventsOf, pathTape, recordTake, resolve, script } from '../../helpers/script';

const SLEEP = { const: false } as const;
const turretAt = (x: number, y: number, extra: Partial<EntityDef> = {}): EntityDef =>
  ({ kind: 'enemy', id: 't1', type: 'turret', x, y, facing: Math.PI, ...extra }) as EntityDef;

function actor(res: Resolution | { frames: Resolution['frames'] }, sub: number, tape = 0) {
  const f = res.frames.find((fr) => fr.sub >= sub) ?? res.frames[res.frames.length - 1];
  return f.actors.find((a) => a.tape === tape)!;
}

describe('manualDesync', () => {
  const lv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 } });
  const loadout = baseLoadout({ abilities: ['manualDesync'] });

  it('live: the first press desyncs in place and holds the spark; the second re-syncs the body where it is', () => {
    const take = recordTake({ level: lv, loadout, index: 0, speed: 1, script: script().run(0, 120, 1, 0).press(20, 'ability').press(80, 'ability'), ticks: 160 });
    const des = eventsOf(take.events, 'desync', { tape: 0 });
    expect(des.map((e) => [e.sub, e.detail])).toEqual([[80, 'manual desync']]);
    const res = eventsOf(take.events, 'resync', { tape: 0 });
    expect(res.map((e) => [e.sub, e.detail])).toEqual([[320, 'manual desync']]);
    // frames[i] is the snapshot after local tick i (sub 4(i + 1)).
    const held = take.frames.slice(21, 80);
    const spark = held[0].actors[0].spark!;
    expect(spark).toBeDefined();
    for (const f of held) {
      expect(f.actors[0].synced).toBe(false);
      expect(f.actors[0].spark).toEqual(spark);
    }
    expect(Math.abs(spark.x - des[0].x)).toBeLessThan(1e-9);
    // The body ran on meanwhile; after the second press it is synced exactly where it is.
    const after = take.frames[80].actors[0];
    expect(after.synced).toBe(true);
    expect(after.spark).toBeUndefined();
    expect(after.x).toBeGreaterThan(spark.x + 3);
  });

  it('playback: the released spark has to catch up with the projection by ordinary spark rules', () => {
    const take = recordTake({ level: lv, loadout, index: 0, speed: 1, script: script().run(0, 120, 1, 0).press(20, 'ability').press(80, 'ability'), ticks: 160 });
    const res = resolve(lv, [take.tape], loadout);
    expect(eventsOf(res.events, 'desync', { tape: 0 }).map((e) => [e.sub, e.detail])).toEqual([[80, 'manual desync']]);
    const sparkAt = (sub: number) => actor(res, sub).spark;
    const s0 = sparkAt(100)!;
    expect(sparkAt(300)).toEqual(s0);
    const resync = eventsOf(res.events, 'resync', { tape: 0 });
    expect(resync).toHaveLength(1);
    expect(resync[0].sub).toBeGreaterThan(320 + 60);
    // The spark only moves after the release, and never faster than spark speed.
    const moving = res.frames.filter((f) => f.sub > 320 && f.sub < resync[0].sub).map((f) => f.actors[0].spark!);
    expect(moving.length).toBeGreaterThan(5);
    expect(moving[moving.length - 1].x).toBeGreaterThan(s0.x + 2);
    expect(res.outcome.survivors).toEqual([0]);
  });

  it('while voluntarily desynced the self is harmless and invulnerable: a turret never shoots at it', () => {
    const tlv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [turretAt(8.5, 5.5)] });
    const tape = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 2.5, y: 5.5 }], events: [{ tick: 0, kind: 'ability' }, { tick: 30, kind: 'light', dir: 0 }] });
    const res = resolve(tlv, [tape], loadout);
    expect(eventsOf(res.events, 'enemyShot')).toHaveLength(0);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
    expect(eventsOf(res.events, 'swing')).toHaveLength(0);
    expect(res.outcome.survivors).toEqual([0]);
    const control = resolve(tlv, [tape], baseLoadout());
    expect(eventsOf(control.events, 'selfDeath', { tape: 0 })).toHaveLength(1);
  });

  it('an involuntary desync is held by the next press, so recorded on/off presses stay paired', () => {
    // The tape walks through a doorway that is shut in this run (desync at the door), presses at
    // ticks 60 and 200. The first press pins the stalled spark, the second lets it go again.
    const map: MapRows = OPEN_ROOM.map((row, r) => (r === 0 || r === OPEN_ROOM.length - 1 ? row : row.slice(0, 5) + (r === 5 ? '.' : '#') + row.slice(6)));
    // The door is shut for beats [0, 6) and open from beat 6 on.
    const dlv = makeLevel({
      speeds: [1],
      bars: 4,
      map,
      start: { x: 2.5, y: 5.5 },
      entities: [{ kind: 'door', id: 'd1', cells: [{ c: 5, r: 5 }], openWhen: { beat: { every: 16, from: 6, to: 16 } } }],
    });
    const tape = pathTape({
      index: 0,
      speed: 1,
      ticks: 480,
      path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 7.5, y: 5.5 }],
      events: [{ tick: 60, kind: 'ability' }, { tick: 300, kind: 'ability' }],
    });
    const res = resolve(dlv, [tape], loadout);
    const des = eventsOf(res.events, 'desync', { tape: 0 });
    expect(des).toHaveLength(1);
    expect(des[0].detail).toBe('blocked by door d1');
    // The door opens at beat 6 (sub 360), but the spark is pinned from tick 60 to tick 300.
    const pinned = res.frames.filter((f) => f.sub > 60 * 4 + 4 && f.sub <= 300 * 4).map((f) => f.actors[0].spark!);
    expect(pinned.every((p) => p.x === pinned[0].x && p.y === pinned[0].y)).toBe(true);
    const resync = eventsOf(res.events, 'resync', { tape: 0 });
    expect(resync).toHaveLength(1);
    expect(resync[0].sub).toBeGreaterThan(300 * 4);
    // Without the gear the same tape resyncs as soon as the door opens.
    const plain = resolve(dlv, [tape]);
    expect(eventsOf(plain.events, 'resync', { tape: 0 })[0].sub).toBeLessThan(300 * 4);
  });
});

describe('lowProfile / loudmouth', () => {
  it('effectiveDistance scales perceived distance, and both together multiply', () => {
    expect(effectiveDistance([], 4)).toBe(4);
    expect(effectiveDistance(['lowProfile'], 4)).toBe(4 * LOW_PROFILE_FACTOR);
    expect(effectiveDistance(['loudmouth'], 4)).toBe(4 * LOUDMOUTH_FACTOR);
    expect(effectiveDistance(['lowProfile', 'loudmouth'], 4)).toBeCloseTo(4 * LOW_PROFILE_FACTOR * LOUDMOUTH_FACTOR, 12);
  });

  // A long hall: turret (reach 12) at x 2.5, the self further down the hall.
  const HALL: MapRows = ['#'.repeat(22), '#' + '.'.repeat(20) + '#', '#' + '.'.repeat(20) + '#', '#' + '.'.repeat(20) + '#', '#'.repeat(22)];
  const hall = (selfX: number): { lv: LevelDef; tape: Tape } => ({
    lv: makeLevel({ speeds: [1], bars: 2, map: HALL, start: { x: selfX, y: 2.5 }, entities: [turretAt(2.5, 2.5, { facing: 0 })] }),
    tape: pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: selfX, y: 2.5 }] }),
  });

  it('lowProfile: a self inside the turret’s reach is read as out of range', () => {
    const { lv, tape } = hall(11.5); // 9 tiles: 13.5 perceived
    expect(eventsOf(resolve(lv, [tape]).events, 'enemyShot').length).toBeGreaterThan(0);
    expect(eventsOf(resolve(lv, [tape], baseLoadout({ abilities: ['lowProfile'] })).events, 'enemyShot')).toHaveLength(0);
  });

  it('loudmouth: a self beyond the turret’s reach is read as in range', () => {
    const { lv, tape } = hall(16.5); // 14 tiles: 10.5 perceived
    expect(eventsOf(resolve(lv, [tape]).events, 'enemyShot')).toHaveLength(0);
    expect(eventsOf(resolve(lv, [tape], baseLoadout({ abilities: ['loudmouth'] })).events, 'enemyShot').length).toBeGreaterThan(0);
  });
});

describe('beatSight', () => {
  const lv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [turretAt(8.5, 5.5, { beat: { every: 2, offset: 0 } } as Partial<EntityDef>)] });
  const tape = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 2.5, y: 5.5 }] });

  it('lists the beats of upcoming enemy attacks within the look-ahead, and they are the beats the attacks land on', () => {
    const sim = createSim({ level: lv, loadout: baseLoadout({ abilities: ['beatSight'] }), tapes: [tape] });
    expect(sim.threatBeats!(5)).toEqual([2, 4]);
    // During the telegraph the committed attack is listed exactly.
    while (sim.sub < 180) sim.stepSub();
    expect(sim.snapshot().enemies[0].state).toBe('telegraph');
    expect(sim.threatBeats!(1)).toEqual([2]);
    const shots: number[] = [];
    while (!sim.done) {
      sim.stepSub();
      for (const e of sim.drainEvents()) if (e.type === 'enemyShot') shots.push(e.sub / 120);
    }
    expect(shots[0]).toBe(2);
  });

  it('is empty without the gear, and ignores sleeping and dead enemies', () => {
    const plain = createSim({ level: lv, loadout: baseLoadout(), tapes: [tape] });
    expect(plain.threatBeats!(8)).toEqual([]);
    const asleep = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [turretAt(8.5, 5.5, { wakeWhen: SLEEP } as Partial<EntityDef>)] });
    const sim = createSim({ level: asleep, loadout: baseLoadout({ abilities: ['beatSight'] }), tapes: [tape] });
    expect(sim.threatBeats!(8)).toEqual([]);
  });
});

describe('laserProof and heavyStep', () => {
  it('laserProof: a live laser does not kill', () => {
    const lv = makeLevel({
      speeds: [1],
      bars: 2,
      start: { x: 2.5, y: 5.5 },
      entities: [{ kind: 'laser', id: 'beam', from: { x: 6.5, y: 1.5 }, to: { x: 6.5, y: 8.5 }, onWhen: { const: true } }],
    });
    const tape = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 120, x: 9.5, y: 5.5 }] });
    expect(eventsOf(resolve(lv, [tape]).events, 'selfDeath')).toHaveLength(1);
    expect(eventsOf(resolve(lv, [tape], baseLoadout({ abilities: ['laserProof'] })).events, 'selfDeath')).toHaveLength(0);
  });

  it('heavyStep: a self holds a heavy plate', () => {
    const lv = makeLevel({ speeds: [1], bars: 2, start: { x: 5.5, y: 5.5 }, entities: [{ kind: 'plate', id: 'p1', c: 5, r: 5, heavy: true }] });
    const tape = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 5.5, y: 5.5 }] });
    expect(eventsOf(resolve(lv, [tape]).events, 'plate')).toHaveLength(0);
    expect(eventsOf(resolve(lv, [tape], baseLoadout({ abilities: ['heavyStep'] })).events, 'plate').map((e) => e.detail)).toEqual(['on']);
  });
});

describe('phaseDodge', () => {
  // A full column of low barriers at x ∈ [6, 7).
  const map: MapRows = OPEN_ROOM.map((row, r) => (r === 0 || r === OPEN_ROOM.length - 1 ? row : row.slice(0, 6) + '=' + row.slice(7)));
  const lv = makeLevel({ speeds: [1], bars: 2, map, start: { x: 5, y: 5.5 }, startFacing: 0 });
  const dodge = script().aim(0, 240, 0).press(0, 'dodge');

  it('a dodge passes through low barriers live, and replays without desync', () => {
    const blocked = recordTake({ level: lv, index: 0, speed: 1, script: dodge, ticks: 40 });
    expect(blocked.frames[39].actors[0].x).toBeLessThan(6);
    const loadout = baseLoadout({ abilities: ['phaseDodge'] });
    const phased = recordTake({ level: lv, loadout, index: 0, speed: 1, script: dodge, ticks: 40 });
    expect(phased.frames[39].actors[0].x).toBeGreaterThan(7.3);
    const res = resolve(lv, [phased.tape], loadout);
    expect(eventsOf(res.events, 'desync')).toHaveLength(0);
    // The same tape replayed without the gear cannot cross: it desyncs at the barrier.
    expect(eventsOf(resolve(lv, [phased.tape]).events, 'desync', { tape: 0 })).toHaveLength(1);
  });
});

describe('slideStrike', () => {
  const lv = makeLevel({ speeds: [1], bars: 2, start: { x: 2.5, y: 5.5 }, entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 3.3, y: 5.5, hp: 20, wakeWhen: SLEEP }] });
  // A dodge at tick 10 ends at tick 24; a light at 24 slides out of it, a light at 60 does not.
  const tape = pathTape({
    index: 0,
    speed: 1,
    ticks: 100,
    endMode: 'reverse',
    path: [{ tick: 0, x: 2.5, y: 5.5 }],
    events: [{ tick: 10, kind: 'dodge', dir: 0 }, { tick: 24, kind: 'light', dir: 0 }, { tick: 60, kind: 'light', dir: 0 }],
  });

  it('a strike started straight out of a dodge carries extra momentum, only on a forward pass', () => {
    const powers = (abilities: ('slideStrike')[]) => eventsOf(resolve(lv, [tape], baseLoadout({ abilities })).events, 'swing').map((e) => +e.power!.toFixed(6));
    const plain = powers([]);
    const slide = powers(['slideStrike']);
    expect(plain.every((p) => p === 1.2)).toBe(true);
    // Forward: [24 → slide, 60 → plain]; backward pass: 60 then 24, both plain; forward again …
    expect(slide.slice(0, 4)).toEqual([+(1.2 * SLIDE_STRIKE_MUL).toFixed(6), 1.2, 1.2, 1.2]);
    expect(slide[4]).toBe(+(1.2 * SLIDE_STRIKE_MUL).toFixed(6));
  });
});

describe('parry', () => {
  const lv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [turretAt(6.5, 5.5, { beat: { every: 8, offset: 0 } } as Partial<EntityDef>)] });
  const still = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 2.5, y: 5.5 }] });
  const deathSub = eventsOf(resolve(lv, [still]).events, 'selfDeath', { tape: 0 })[0].sub;
  // Heavy windup 16 ticks, active 5: put the live window just before the bolt would touch the self.
  const heavyTick = Math.round((deathSub - 24) / 4) - 16;
  const swinger = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 2.5, y: 5.5 }], events: [{ tick: heavyTick, kind: 'heavy', dir: 0 }] });

  it('a heavy swing turns an enemy shot inside its arc back at the shooter', () => {
    const res = resolve(lv, [swinger], baseLoadout({ abilities: ['parry'] }));
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
    const parry = eventsOf(res.events, 'projectileHit').filter((e) => e.detail === 'parry');
    expect(parry.map((e) => [e.tape, e.id])).toEqual([[0, 't1']]);
    // The reflected bolt belongs to the tape and destroys the turret that fired it.
    expect(eventsOf(res.events, 'kill', { id: 't1' }).map((e) => [e.tape, e.detail])).toEqual([[0, 'bolt']]);
    expect(eventsOf(res.events, 'whiff')).toHaveLength(0);
    expect(res.outcome.win).toBe(true);
  });

  it('without the gear the same swing does nothing to the shot', () => {
    const res = resolve(lv, [swinger]);
    expect(eventsOf(res.events, 'selfDeath', { tape: 0 }).map((e) => e.sub)).toEqual([deathSub]);
    expect(eventsOf(res.events, 'projectileHit').filter((e) => e.detail === 'parry')).toHaveLength(0);
  });
});

describe('killRefresh', () => {
  it('a melee kill by the live self refunds its dodge cooldown', () => {
    const lv0 = makeLevel({ speeds: [1], bars: 2, start: { x: 8.5, y: 5.5 }, startFacing: Math.PI });
    const s = script().aim(0, 240, Math.PI).press(0, 'dodge').press(14, 'light', Math.PI).press(26, 'dodge');
    // Where the self is when the light swing's hit frame comes (tick 20).
    const probe = recordTake({ level: lv0, index: 0, speed: 1, script: script().aim(0, 240, Math.PI).press(0, 'dodge').press(14, 'light', Math.PI), ticks: 30 });
    const at = probe.frames[20].actors[0];
    const lv = makeLevel({ ...lv0, entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: at.x - 0.8, y: at.y, wakeWhen: SLEEP }] });
    const dodges = (abilities: ('killRefresh')[]) =>
      recordTake({ level: lv, loadout: baseLoadout({ abilities }), index: 0, speed: 1, script: s, ticks: 60 }).tape.events.filter((e) => e.kind === 'dodge').map((e) => e.tick);
    const withGear = recordTake({ level: lv, loadout: baseLoadout({ abilities: ['killRefresh'] }), index: 0, speed: 1, script: s, ticks: 60 });
    expect(eventsOf(withGear.events, 'kill', { id: 'g1' })).toHaveLength(1);
    expect(dodges(['killRefresh'])).toEqual([0, 26]);
    // Without the gear the second press falls inside the cooldown and is dropped from the buffer.
    expect(dodges([])).toEqual([0]);
  });
});
