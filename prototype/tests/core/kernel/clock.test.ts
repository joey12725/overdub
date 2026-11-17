/**
 * Kernel: one clock, recording vs playback, take management and determinism
 * (TEST-01..06, full determinism, record → resolve reproduction).
 */
import { describe, expect, it } from 'vitest';
import { createSim, resolveEncounter, buildBossMemory } from '../../../src/core/index';
import { subsPerLocalTick } from '../../../src/core/types';
import type { FrameSnapshot, LevelDef, TapeSpeed } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { baseLoadout } from '../../helpers/loadout';
import { eventsOf, recordTake, resolve, script } from '../../helpers/script';

const busyLevel = (): LevelDef =>
  makeLevel({
    speeds: [0.5, 1, 2],
    bars: 2,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 9.5, y: 2.5 },
      { kind: 'enemy', id: 't1', type: 'turret', x: 10.5, y: 8.5, facing: Math.PI },
      { kind: 'switch', id: 'sw', x: 4.5, y: 2.5 },
      { kind: 'door', id: 'd1', cells: [{ c: 7, r: 5 }], openWhen: { sig: 'sw' } },
      { kind: 'plate', id: 'p1', c: 5, r: 7 },
    ],
  });

const busyScript = () =>
  script()
    .run(0, 25, 0.6, -1)
    .press(26, 'interact')
    .run(30, 70, 1, 0.3)
    .press(72, 'light', 0)
    .run(80, 110, -0.4, 1)
    .press(112, 'dodge')
    .run(120, 160, 1, 0)
    .press(165, 'heavy', -0.5)
    .run(200, 240, 0, -1);

describe('kernel clock (TEST-01, TEST-02)', () => {
  it('TEST-01: the recording allowance is the same at every speed; the world advances 1/s as far', () => {
    const level = makeLevel({ speeds: [0.5, 1, 2, 4], bars: 1 });
    const results = ([0.5, 1, 2, 4] as TapeSpeed[]).map((speed) => {
      const take = recordTake({ level, index: 0, speed, script: script().run(0, 1000, 1, 0) });
      return { speed, ticks: take.sim.localTick, sub: take.sim.sub, done: take.sim.done, tapeTicks: take.tape.ticks };
    });
    const T = results[0].ticks;
    expect(T).toBe(120);
    for (const r of results) {
      expect(r.ticks).toBe(T);
      expect(r.tapeTicks).toBe(T);
      expect(r.done).toBe(true);
      expect(r.sub).toBe(T * subsPerLocalTick(r.speed));
    }
    // A 2x take sees half as much world as a 1x take; a 0.5x take twice as much (TIME-03).
    expect(results[2].sub * 2).toBe(results[1].sub);
    expect(results[0].sub).toBe(results[1].sub * 2);
  });

  it('TEST-02: a 2x take lands on a plate at the same master substep in recording and in true-speed replay', () => {
    const level = makeLevel({
      speeds: [1, 2],
      bars: 1,
      start: { x: 2.5, y: 5.5 },
      entities: [{ kind: 'plate', id: 'p1', c: 7, r: 5 }],
      objective: { type: 'signal', when: { sig: 'p1' }, text: 'Stand on the plate' },
    });
    const take = recordTake({ level, index: 0, speed: 2, script: script().run(0, 1000, 1, 0) });
    const recPlate = eventsOf(take.events, 'plate');
    expect(recPlate.length).toBeGreaterThan(0);
    const res = resolve(level, [take.tape]);
    const repPlate = eventsOf(res.events, 'plate');
    expect(repPlate.map((e) => [e.sub, e.detail])).toEqual(recPlate.map((e) => [e.sub, e.detail]));
    // Every recorded frame is reproduced exactly at the same master substep.
    const bySub = new Map(res.frames.map((f) => [f.sub, f]));
    let compared = 0;
    for (const f of take.frames) {
      const g = bySub.get(f.sub);
      if (!g) continue;
      expect([g.actors[0].x, g.actors[0].y]).toEqual([f.actors[0].x, f.actors[0].y]);
      compared++;
    }
    expect(compared).toBeGreaterThan(50);
    expect(res.outcome.objectiveComplete).toBe(true);
  });
});

describe('kernel takes (TEST-03..06)', () => {
  const level = busyLevel();
  const first = recordTake({ level, index: 0, speed: 1, script: busyScript() });

  it('TEST-03: the next take starts at beat zero with the earlier tape at its start', () => {
    const sim = createSim({ level, loadout: baseLoadout(), tapes: [first.tape], live: { index: 1, speed: 2, endMode: 'stop' } });
    const snap = sim.snapshot();
    expect(snap.sub).toBe(0);
    expect(snap.beat).toBe(0);
    const a = snap.actors.find((x) => x.tape === 0)!;
    expect(a.phase.tick).toBe(0);
    expect([a.x, a.y]).toEqual([Math.fround(level.start.x), Math.fround(level.start.y)]);
    // The world is reconstructed from its initial state (the grunt is back where it started).
    expect(snap.enemies.find((e) => e.id === 'g1')).toMatchObject({ x: 9.5, y: 2.5, alive: true });
  });

  it('TEST-04: earlier tapes are simulated while recording; unrecorded cassettes do not appear', () => {
    const sim = createSim({ level, loadout: baseLoadout(), tapes: [first.tape], live: { index: 1, speed: 1, endMode: 'stop' } });
    for (let t = 0; t < 40; t++) sim.stepLocalTick(busyScript().input(t));
    const snap = sim.snapshot();
    expect(snap.actors.map((a) => [a.tape, a.live])).toEqual([
      [0, false],
      [1, true],
    ]);
    // Tape A is where its own recording put it at this master substep.
    const fa = first.frames.find((f) => f.sub === snap.sub)!;
    expect([snap.actors[0].x, snap.actors[0].y]).toEqual([fa.actors[0].x, fa.actors[0].y]);
  });

  it('TEST-05: retrying a take replaces it and leaves the committed tape untouched', () => {
    const takeB1 = recordTake({ level, tapes: [first.tape], index: 1, speed: 1, script: script().run(0, 30, 1, -0.5).press(40, 'interact') });
    const takeB2 = recordTake({ level, tapes: [first.tape], index: 1, speed: 1, script: script().run(0, 30, 0, 1) });
    const r1 = resolve(level, [first.tape, takeB1.tape]);
    const r2 = resolve(level, [first.tape, takeB2.tape]);
    const pathA = (r: typeof r1) => r.frames.map((f) => [f.actors[0].x, f.actors[0].y]);
    expect(pathA(r2)).toEqual(pathA(r1));
    // Nothing of the discarded take survives in the new run: only tape B2 plays as cassette B.
    expect(r2.frames[0].actors.map((a) => a.tape)).toEqual([0, 1]);
    expect(eventsOf(r2.events, 'interact', { tape: 1 })).toHaveLength(0);
  });

  it('TEST-06: after a reset the encounter contains no earlier cassette at all', () => {
    const sim = createSim({ level, loadout: baseLoadout(), tapes: [], live: { index: 0, speed: 1, endMode: 'stop' } });
    expect(sim.snapshot().actors.map((a) => a.tape)).toEqual([0]);
    const res = resolveEncounter({ level, loadout: baseLoadout(), tapes: [] });
    expect(res.frames.every((f) => f.actors.length === 0)).toBe(true);
    // Frames: substep 0, every FRAME_SUBS, and the final substep.
    expect(res.frames[0].sub).toBe(0);
    expect(res.frames[res.frames.length - 1].sub).toBe(res.horizonSubs);
    expect(res.frames).toHaveLength(res.horizonSubs / 4 + 1);
    expect(res.frames.every((f, i) => f.sub === i * 4)).toBe(true);
    expect(res.outcome.survivors).toEqual([]);
  });
});

/** A recorded frame as playback would describe it: no live self, a recording ghost is a ghost. */
function asPlayback(f: FrameSnapshot): FrameSnapshot {
  return { ...f, actors: f.actors.map((a) => ({ ...a, live: false, life: a.life === 'recGhost' ? 'ghost' : a.life })) };
}

describe('kernel determinism', () => {
  const level = busyLevel();

  it('two sims with the same config and inputs produce deep-equal snapshots at every step', () => {
    const tapeA = recordTake({ level, index: 0, speed: 2, script: busyScript() }).tape;
    const mk = () => createSim({ level, loadout: baseLoadout(), tapes: [tapeA], live: { index: 1, speed: 1, endMode: 'reverse' } });
    const s1 = mk();
    const s2 = mk();
    const sc = busyScript();
    expect(s2.snapshot()).toEqual(s1.snapshot());
    for (let t = 0; t < s1.tapeTicks; t++) {
      s1.stepLocalTick(sc.input(t));
      s2.stepLocalTick(sc.input(t));
      expect(s2.snapshot()).toEqual(s1.snapshot());
      expect(s2.drainEvents()).toEqual(s1.drainEvents());
    }
    expect(s2.liveTape()).toEqual(s1.liveTape());
    const r1 = resolve(level, [tapeA, s1.liveTape()]);
    const r2 = resolve(level, [tapeA, s2.liveTape()]);
    expect(r2).toEqual(r1);
  });

  it('snapshots are plain data that later steps never mutate', () => {
    const sim = createSim({ level, loadout: baseLoadout(), tapes: [], live: { index: 0, speed: 1, endMode: 'stop' } });
    const sc = busyScript();
    for (let t = 0; t < 30; t++) sim.stepLocalTick(sc.input(t));
    const snap = sim.snapshot();
    const copy = JSON.parse(JSON.stringify(snap));
    for (let t = 30; t < 120; t++) sim.stepLocalTick(sc.input(t));
    expect(JSON.parse(JSON.stringify(snap))).toEqual(copy);
  });

  it('recording a take and resolving it reproduces the same positions, kills and deaths', () => {
    const take = recordTake({ level, index: 0, speed: 1, script: busyScript() });
    const res = resolve(level, [take.tape]);
    // The busy script walks into the turret's lane and dies part-way: the comparison covers both the
    // alive part (everything identical) and the ghost part (positions identical; the recording
    // ghost's provisional effects are allowed to differ, Scenario C).
    const death = eventsOf(take.events, 'selfDeath');
    expect(death).toHaveLength(1);
    const deathSub = death[0].sub;
    const bySub = new Map(res.frames.map((f) => [f.sub, f]));
    let compared = 0;
    for (const f of take.frames) {
      const g = bySub.get(f.sub);
      if (!g) continue;
      expect(g.actors).toEqual(asPlayback(f).actors);
      if (f.sub <= deathSub) {
        expect(g.enemies).toEqual(f.enemies);
        expect(g.mechs).toEqual(f.mechs);
        expect(g.projectiles).toEqual(f.projectiles);
      }
      compared++;
    }
    expect(compared).toBe(take.frames.length);
    const key = (e: { sub: number; type: string; id?: string; tape?: number }) => `${e.sub}:${e.type}:${e.id ?? ''}:${e.tape ?? ''}`;
    for (const type of ['kill', 'selfDeath', 'interact', 'door', 'enemyShot', 'hit', 'swing'] as const) {
      const recorded = eventsOf(take.events, type).filter((e) => e.sub <= deathSub).map(key);
      const replayed = eventsOf(res.events, type).filter((e) => e.sub <= deathSub).map(key);
      expect(replayed).toEqual(recorded);
    }
  });

  it('a take that survives is reproduced exactly, kills included', () => {
    const calm = makeLevel({
      speeds: [1],
      bars: 2,
      start: { x: 2.5, y: 5.5 },
      entities: [
        { kind: 'enemy', id: 'g1', type: 'grunt', x: 6.5, y: 5.5 },
        { kind: 'switch', id: 'sw', x: 3.5, y: 4.5 },
        { kind: 'door', id: 'd1', cells: [{ c: 9, r: 5 }], openWhen: { sig: 'sw' } },
      ],
    });
    // Wait for the grunt to walk in, then strike it as it arrives (1x standing light kills a grunt).
    const s = script().press(2, 'interact').aim(0, 400, 0).press(80, 'light', 0).run(120, 160, 1, 0);
    const take = recordTake({ level: calm, index: 0, speed: 1, script: s });
    expect(eventsOf(take.events, 'kill')).toHaveLength(1);
    expect(eventsOf(take.events, 'selfDeath')).toHaveLength(0);
    const res = resolve(calm, [take.tape]);
    const bySub = new Map(res.frames.map((f) => [f.sub, f]));
    for (const f of take.frames) {
      const g = bySub.get(f.sub)!;
      expect(g.actors).toEqual(asPlayback(f).actors);
      expect(g.enemies).toEqual(f.enemies);
      expect(g.mechs).toEqual(f.mechs);
    }
    expect(eventsOf(res.events, 'kill').map((e) => [e.sub, e.id, e.tape])).toEqual(eventsOf(take.events, 'kill').map((e) => [e.sub, e.id, e.tape]));
    expect(res.outcome.win).toBe(true);
  });

  it('buildBossMemory samples each committed tape once per master beat', () => {
    const take = recordTake({ level, index: 2, speed: 2, endMode: 'repeat', script: busyScript() });
    const mem = buildBossMemory(level, [take.tape]);
    expect(mem.observed).toHaveLength(1);
    expect(mem.observed[0].tape).toBe(2);
    const beats = level.horizonBars * 4;
    expect(mem.observed[0].samples).toHaveLength(beats + 1);
    expect(mem.observed[0].samples[0]).toEqual({ beat: 0, x: Math.fround(level.start.x), y: Math.fround(level.start.y) });
  });
});

