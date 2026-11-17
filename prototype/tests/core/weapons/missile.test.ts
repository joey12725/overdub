/**
 * Guided missile: one-time nearest-target acquisition at launch, no retargeting, launch gating
 * (MISSILE-02..04, WEAPON-02, NEW-03, TEST-22, Scenario F).
 */
import { describe, expect, it } from 'vitest';
import { FRAME_SUBS, SUB_HZ, type EntityDef, type LevelDef, type Resolution, type Tape } from '../../../src/core/types';
import { makeLevel, OPEN_ROOM } from '../../helpers/levels';
import { baseLoadout, BASE_MISSILE } from '../../helpers/loadout';
import { eventsOf, pathTape, recordTake, resolve, script } from '../../helpers/script';

const SLEEP = { const: false } as const;

function grunt(id: string, x: number, y: number, hp = 5): EntityDef {
  return { kind: 'enemy', id, type: 'grunt', x, y, hp, wakeWhen: SLEEP };
}

const LAUNCH_TICK = 60;
/** Tape A: stands at (2.5, 5.5) and fires east at local tick 60 (launch 4 ticks later, sub 256). */
const A: Tape = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 2.5, y: 5.5 }], events: [{ tick: LAUNCH_TICK, kind: 'ranged', dir: 0 }] });
const LAUNCH_SUB = (LAUNCH_TICK + 4) * 4;

/** A self standing at (x, y) with one heavy swing along `dir` at local tick `tick`. */
function pusher(index: 1 | 2, x: number, y: number, tick: number, dir: number): Tape {
  return pathTape({ index, speed: 1, ticks: 480, path: [{ tick: 0, x, y }], events: [{ tick, kind: 'heavy', dir }] });
}

// g1 starts nearest to A (≈4.47 tiles); g2 (5 tiles) is the one later cassettes shove around.
const LEVEL: LevelDef = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [grunt('g1', 6.5, 3.5), grunt('g2', 7.5, 5.5)] });

function missileFrames(res: Resolution) {
  return res.frames.flatMap((f) => f.projectiles.filter((p) => p.archetype === 'missile').map((p) => ({ sub: f.sub, ...p })));
}

function lockOf(res: Resolution): (string | undefined)[] {
  return [...new Set(missileFrames(res).map((p) => p.targetId))];
}

describe('Scenario F / TEST-22 / NEW-03: one-time nearest-target acquisition', () => {
  it('alone, the missile locks the nearest enemy at launch and strikes it', () => {
    const res = resolve(LEVEL, [A]);
    expect(lockOf(res)).toEqual(['g1']);
    expect(eventsOf(res.events, 'hit', { id: 'g1' }).map((e) => [e.tape, e.detail])).toEqual([[0, 'missile']]);
    expect(eventsOf(res.events, 'hit', { id: 'g2' })).toHaveLength(0);
  });

  it('the same recorded launch picks a different enemy when a later tape knocks another one closer first', () => {
    // B heavy-swings g2 two tiles west (to x 5.5, 3 tiles from A) long before A's launch.
    const B = pusher(1, 8.6, 5.5, 10, Math.PI);
    const res = resolve(LEVEL, [A, B]);
    const push = eventsOf(res.events, 'hit', { id: 'g2' }).find((e) => e.tape === 1)!;
    expect(push.sub).toBeLessThan(LAUNCH_SUB);
    expect(res.frames.find((f) => f.sub >= LAUNCH_SUB)!.enemies.find((e) => e.id === 'g2')!.x).toBeCloseTo(5.5, 3);
    // Same tape A, same launch instant and direction: the world chose the target.
    expect(eventsOf(res.events, 'fire').map((e) => [e.sub, e.tape, e.dir])).toEqual([[LAUNCH_SUB, 0, 0]]);
    expect(lockOf(res)).toEqual(['g2']);
    expect(eventsOf(res.events, 'hit', { id: 'g2' }).filter((e) => e.tape === 0).map((e) => e.detail)).toEqual(['missile']);
    expect(eventsOf(res.events, 'hit', { id: 'g1' })).toHaveLength(0);
  });

  it('after launch it never retargets, even when another enemy becomes nearer to it', () => {
    // C shoves g2 two tiles west shortly after the launch: g2 is then much nearer the missile than g1.
    const C = pusher(2, 8.6, 5.5, LAUNCH_TICK + 2, Math.PI);
    const res = resolve(LEVEL, [A, C]);
    const pushed = eventsOf(res.events, 'hit', { id: 'g2' }).find((e) => e.tape === 2)!;
    expect(pushed.sub).toBeGreaterThan(LAUNCH_SUB);
    const later = missileFrames(res).find((p) => p.sub >= pushed.sub + 60)!;
    const f = res.frames.find((fr) => fr.sub === later.sub)!;
    const d = (id: string) => {
      const e = f.enemies.find((en) => en.id === id)!;
      return Math.hypot(e.x - later.x, e.y - later.y);
    };
    expect(d('g2')).toBeLessThan(d('g1'));
    expect(lockOf(res)).toEqual(['g1']);
    expect(eventsOf(res.events, 'hit', { id: 'g1' }).filter((e) => e.tape === 0)).toHaveLength(1);
    expect(eventsOf(res.events, 'hit', { id: 'g2' }).filter((e) => e.tape === 0)).toHaveLength(0);
  });

  it('when its target dies first it flies straight on and still never switches', () => {
    // g1 has 1 hp here and B kills it with a swing while the missile is on its way.
    const lv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [grunt('g1', 6.5, 3.5, 1), grunt('g2', 9.5, 8.5)] });
    const B = pathTape({ index: 1, speed: 1, ticks: 480, path: [{ tick: 0, x: 7.4, y: 3.5 }], events: [{ tick: LAUNCH_TICK + 10, kind: 'light', dir: Math.PI }] });
    const res = resolve(lv, [A, B]);
    const kill = eventsOf(res.events, 'kill', { id: 'g1' })[0];
    expect(kill.tape).toBe(1);
    expect(kill.sub).toBeGreaterThan(LAUNCH_SUB);
    const after = missileFrames(res).filter((p) => p.sub > kill.sub + FRAME_SUBS);
    expect(after.length).toBeGreaterThan(10);
    expect(after.every((p) => p.targetId === 'g1')).toBe(true);
    expect(new Set(after.map((p) => p.dir.toFixed(9))).size).toBe(1);
    expect(eventsOf(res.events, 'hit', { id: 'g2' }).filter((e) => e.tape === 0)).toHaveLength(0);
  });

  it('turns no faster than its turn rate', () => {
    // Fire away from the only enemy so the missile has to turn round.
    const lv = makeLevel({ speeds: [1], bars: 4, start: { x: 5.5, y: 5.5 }, entities: [grunt('g1', 2.5, 5.5)] });
    const tape = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 5.5, y: 5.5 }], events: [{ tick: 10, kind: 'ranged', dir: 0 }] });
    const res = resolve(lv, [tape]);
    const ps = missileFrames(res);
    const maxStep = (BASE_MISSILE.turnRate * FRAME_SUBS) / SUB_HZ + 1e-9;
    for (let i = 1; i < ps.length; i++) {
      let d = ps[i].dir - ps[i - 1].dir;
      while (d > Math.PI) d -= 2 * Math.PI;
      while (d < -Math.PI) d += 2 * Math.PI;
      expect(Math.abs(d)).toBeLessThanOrEqual(maxStep);
    }
    expect(eventsOf(res.events, 'hit', { id: 'g1' })).toHaveLength(1);
  });

  it('ties go to the enemy placed first; with no enemy it flies straight along the recorded direction', () => {
    const tie = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [grunt('b', 5.5, 7.5), grunt('a', 5.5, 3.5)] });
    expect(lockOf(resolve(tie, [A]))).toEqual(['b']);
    const empty = resolve(makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 } }), [A]);
    const ps = missileFrames(empty);
    expect(ps.length).toBeGreaterThan(0);
    expect(ps.every((p) => p.targetId === undefined && p.dir === 0 && Math.abs(p.y - 5.5) < 1e-9)).toBe(true);
  });
});

describe('launch gating: only an alive, synced self launches', () => {
  it('a dead playback ghost launches nothing; the recording ghost launches in its own take only', () => {
    const lv = makeLevel({
      speeds: [1],
      bars: 4,
      start: { x: 2.5, y: 5.5 },
      entities: [{ kind: 'enemy', id: 't1', type: 'turret', x: 9.5, y: 5.5, facing: Math.PI }],
    });
    const take = recordTake({ level: lv, index: 0, speed: 1, script: script().aim(0, 480, 0).press(150, 'ranged', 0) });
    const death = eventsOf(take.events, 'selfDeath', { tape: 0 })[0];
    expect(death.sub).toBeLessThan(150 * 4);
    // In its own take the recording ghost's missile flies and kills the turret (GHOST-03).
    expect(eventsOf(take.events, 'fire', { tape: 0 })).toHaveLength(1);
    expect(eventsOf(take.events, 'kill', { id: 't1' }).map((e) => e.tape)).toEqual([0]);
    // Under playback the self dies at the same moment and its ghost fires nothing.
    const res = resolve(lv, [take.tape]);
    expect(eventsOf(res.events, 'selfDeath', { tape: 0 }).map((e) => e.sub)).toEqual([death.sub]);
    expect(eventsOf(res.events, 'fire')).toHaveLength(0);
    expect(res.frames.every((f) => f.projectiles.every((p) => !('tape' in p.owner)))).toBe(true);
    expect(eventsOf(res.events, 'kill', { id: 't1' })).toHaveLength(0);
  });

  it('a desynced self launches nothing', () => {
    // A wall at column 5 with a door at (5, 5): the tape walks through the doorway, then fires.
    const map = OPEN_ROOM.map((row, r) => (r === 0 || r === OPEN_ROOM.length - 1 ? row : row.slice(0, 5) + (r === 5 ? '.' : '#') + row.slice(6)));
    const tape = pathTape({
      index: 0,
      speed: 1,
      ticks: 480,
      path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 7.5, y: 5.5 }],
      events: [{ tick: 60, kind: 'ranged', dir: 0 }],
    });
    const lv = (open: boolean) =>
      makeLevel({ speeds: [1], bars: 4, map, start: { x: 2.5, y: 5.5 }, entities: [{ kind: 'door', id: 'd1', cells: [{ c: 5, r: 5 }], openWhen: { const: open } }, grunt('g1', 9.5, 5.5)] });
    const shut = resolve(lv(false), [tape]);
    expect(eventsOf(shut.events, 'desync', { tape: 0 })).toHaveLength(1);
    expect(eventsOf(shut.events, 'resync', { tape: 0 })).toHaveLength(0);
    expect(eventsOf(shut.events, 'fire')).toHaveLength(0);
    expect(shut.frames.every((f) => f.projectiles.length === 0)).toBe(true);
    const open = resolve(lv(true), [tape]);
    expect(eventsOf(open.events, 'fire', { tape: 0 })).toHaveLength(1);
  });

  it('a reverse pass fires again with the recorded direction and can hurt again', () => {
    const lv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [grunt('g1', 9.5, 5.5, 9)] });
    const tape = pathTape({ index: 0, speed: 1, endMode: 'reverse', ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }], events: [{ tick: 20, kind: 'ranged', dir: 0 }] });
    const res = resolve(lv, [tape], baseLoadout({ ranged: { archetype: 'pierce', speed: 20, range: 12, pierce: 0, turnRate: 0 } }));
    const fires = eventsOf(res.events, 'fire');
    expect(fires.length).toBeGreaterThanOrEqual(2);
    expect(fires.every((e) => e.dir === 0)).toBe(true);
    // Every shot with time to arrive before the horizon (≈ 7 tiles at 20 tiles/s) hurts again (PLAY-06).
    const arrived = fires.filter((e) => e.sub + 0.5 * SUB_HZ < res.horizonSubs);
    expect(arrived.length).toBeGreaterThanOrEqual(2);
    expect(eventsOf(res.events, 'hit', { id: 'g1' }).length).toBe(arrived.length);
  });
});
