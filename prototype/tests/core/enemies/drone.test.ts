/**
 * Drone (AI-01, AI-06, AI-07, HEALTH-02): hovers over void and low barriers, keeps its distance from
 * the nearest self, fires bolts on the off-beat, takes two hits.
 */
import { describe, expect, it } from 'vitest';
import { Grid } from '../../../src/core/grid';
import { DRONE_KEEP_BAND, DRONE_OFFBEAT } from '../../../src/core/enemies/drone';
import { DRONE_KEEP_DISTANCE, ENEMY_STATS } from '../../../src/core/tuning';
import type { EnemyDef, LevelDef } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { eventsOf, frameAt, pathTape, resolve } from '../../helpers/script';

const SPB = 120;
/** A grid far beyond the horizon: the drone never fires, so spacing can be watched on its own. */
const HOLD_FIRE = { every: 1000, offset: 999 };

function droneAt(x: number, y: number, extra: Partial<EnemyDef> = {}): EnemyDef {
  return { kind: 'enemy', id: 'd1', type: 'drone', x, y, ...extra };
}

const still = (x: number, y: number, ticks = 480) => pathTape({ index: 0, speed: 1, ticks, path: [{ tick: 0, x, y }] });

const dist = (e: { x: number; y: number }, x: number, y: number) => Math.hypot(e.x - x, e.y - y);

describe('drone spacing (AI-01)', () => {
  it('backs off from a self that is too close', () => {
    const lvl = makeLevel({ speeds: [1], bars: 4, start: { x: 2, y: 5 }, entities: [droneAt(4, 5, { beat: HOLD_FIRE })] });
    const res = resolve(lvl, [still(2, 5)]);
    const end = res.frames[res.frames.length - 1].enemies[0];
    expect(dist(end, 2, 5)).toBeGreaterThanOrEqual(DRONE_KEEP_DISTANCE - DRONE_KEEP_BAND - 1e-6);
    expect(dist(end, 2, 5)).toBeLessThanOrEqual(DRONE_KEEP_DISTANCE + DRONE_KEEP_BAND);
  });

  it('closes in on a self that is too far, and then holds position', () => {
    const lvl = makeLevel({ speeds: [1], bars: 4, start: { x: 1.5, y: 5 }, entities: [droneAt(10.5, 5, { beat: HOLD_FIRE })] });
    const res = resolve(lvl, [still(1.5, 5)]);
    const mid = frameAt(res, 8 * SPB).enemies[0];
    const end = res.frames[res.frames.length - 1].enemies[0];
    expect(dist(end, 1.5, 5)).toBeLessThanOrEqual(DRONE_KEEP_DISTANCE + DRONE_KEEP_BAND + 1e-6);
    expect(dist(end, 1.5, 5)).toBeGreaterThanOrEqual(DRONE_KEEP_DISTANCE - DRONE_KEEP_BAND);
    expect(end.x).toBe(mid.x);
  });

  it('targets the NEAREST self, and between two selves settles where their pushes balance', () => {
    const lvl = makeLevel({ speeds: [1], bars: 2, start: { x: 1.5, y: 5 }, entities: [droneAt(6, 5, { beat: HOLD_FIRE })] });
    const near = pathTape({ index: 1, speed: 1, ticks: 240, path: [{ tick: 0, x: 8, y: 5 }] });
    const res = resolve(lvl, [still(1.5, 5, 240), near]);
    expect(frameAt(res, SPB / 2).enemies[0].target).toBe(1);
    // Pushed by both (A 4.5 west, B 2 east): the balance point is x = 4.75, and it stays there.
    const settled = frameAt(res, 4 * SPB).enemies[0];
    expect(settled.x).toBeCloseTo(4.75, 6);
    expect(res.frames.at(-1)!.enemies[0].x).toBe(settled.x);
  });
});

describe('drone hovering', () => {
  // A void trench (columns 6..8) and a low barrier column (4) between the self and the drone.
  const map = [
    '##############',
    '#...=.   ....#',
    '#...=.   ....#',
    '#...=.   ....#',
    '#...=.   ....#',
    '#...=.   ....#',
    '#...=.   ....#',
    '##############',
  ];

  it('flies over void and low barriers that stop walkers', () => {
    const mk = (type: 'drone' | 'grunt'): LevelDef =>
      makeLevel({ map, speeds: [1], bars: 4, start: { x: 1.5, y: 3.5 }, entities: [{ ...droneAt(12.5, 3.5, { beat: HOLD_FIRE }), type }] });
    const self = still(1.5, 3.5);
    const drone = resolve(mk('drone'), [self]).frames.at(-1)!.enemies[0];
    // 5 tiles from the self is x = 6.5: over the trench.
    expect(drone.x).toBeLessThan(9);
    expect(map[Math.floor(drone.y)][Math.floor(drone.x)]).toBe(' ');
    expect(dist(drone, 1.5, 3.5)).toBeLessThanOrEqual(DRONE_KEEP_DISTANCE + DRONE_KEEP_BAND + 1e-6);
    // A grunt with the same goal is stopped at the trench's edge.
    const grunt = resolve(mk('grunt'), [self]).frames.at(-1)!.enemies[0];
    expect(grunt.x).toBeGreaterThan(9);
  });

  it('never presses a pressure plate it hovers over', () => {
    const plate = (type: 'drone' | 'grunt'): LevelDef =>
      makeLevel({
        speeds: [1],
        bars: 1,
        start: { x: 2, y: 2 },
        entities: [{ ...droneAt(6.5, 5.5, { wakeWhen: { const: false } }), type }, { kind: 'plate', id: 'p1', c: 6, r: 5 }],
      });
    const self = still(2, 2, 120);
    expect(resolve(plate('drone'), [self]).frames[2].mechs.find((m) => m.id === 'p1')?.on).toBe(false);
    expect(resolve(plate('grunt'), [self]).frames[2].mechs.find((m) => m.id === 'p1')?.on).toBe(true);
  });
});

describe('drone fire (AI-06, AI-07)', () => {
  const lvl = makeLevel({ speeds: [1], bars: 4, start: { x: 1.5, y: 5 }, entities: [droneAt(6.5, 5)] });

  it('fires bolts only on the off-beat, after a telegraph, along its locked aim', () => {
    // Three selves spaced out so it keeps finding targets after each kill.
    const a = still(1.5, 2);
    const b = pathTape({ index: 1, speed: 1, ticks: 480, path: [{ tick: 0, x: 1.5, y: 8 }] });
    const c = pathTape({ index: 2, speed: 1, ticks: 480, path: [{ tick: 0, x: 10.5, y: 8 }] });
    const res = resolve(lvl, [a, b, c]);
    const shots = eventsOf(res.events, 'enemyShot', { id: 'd1' });
    expect(shots.length).toBeGreaterThanOrEqual(2);
    const half = DRONE_OFFBEAT * SPB;
    for (const s of shots) {
      expect(s.sub % SPB).toBe(half);
      // Its grid (every 2, offset 1) shifted by half a beat: beats 1.5, 3.5, 5.5 …
      expect((s.sub - half - ENEMY_STATS.drone.offset * SPB) % (ENEMY_STATS.drone.every * SPB)).toBe(0);
    }
    const tels = eventsOf(res.events, 'enemyTelegraph', { id: 'd1' });
    expect(tels[0].sub).toBe(shots[0].sub - ENEMY_STATS.drone.telegraphBeats * SPB);
    expect(shots[0].dir).toBe(tels[0].dir);
    expect(eventsOf(res.events, 'selfDeath').some((d) => d.detail === 'shot by drone d1')).toBe(true);
  });

  it('only telegraphs at a self it can see: behind a pillar it comes around first', () => {
    const walled = makeLevel({
      map: ['############', '#..........#', '#..........#', '#....#.....#', '#....#.....#', '#....#.....#', '#..........#', '#..........#', '############'],
      speeds: [1],
      bars: 2,
      start: { x: 2, y: 4 },
      entities: [droneAt(8.5, 4.5)],
    });
    const grid = Grid.fromLevel(walled);
    const res = resolve(walled, [still(2.5, 4.5, 240)]);
    const tels = eventsOf(res.events, 'enemyTelegraph', { id: 'd1' });
    expect(tels.length).toBeGreaterThan(0);
    // At the start the pillar hides the self entirely.
    expect(grid.segmentBlocked(8.5, 4.5, 2.5, 4.5, true)).toBe(true);
    for (const t of tels) {
      const f = res.frames.find((fr) => fr.sub === t.sub + 1) ?? frameAt(res, t.sub + 1);
      const d = f.enemies[0];
      expect(grid.segmentBlocked(d.x, d.y, 2.5, 4.5, true)).toBe(false);
    }
  });
});

describe('drone hit points (HEALTH-02)', () => {
  const lvl = makeLevel({ speeds: [1, 2], bars: 1, start: { x: 5.5, y: 5 }, entities: [droneAt(6.5, 5, { wakeWhen: { const: false } })] });
  it('a standing 1× light chips it; a 2× light (2 damage) kills it', () => {
    const one = resolve(lvl, [pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 5.5, y: 5 }], events: [{ tick: 10, kind: 'light', dir: 0 }] })]);
    expect(eventsOf(one.events, 'kill')).toHaveLength(0);
    expect(one.frames.at(-1)!.enemies[0]).toMatchObject({ hp: 1, alive: true });
    const two = resolve(lvl, [pathTape({ index: 0, speed: 2, ticks: 120, path: [{ tick: 0, x: 5.5, y: 5 }], events: [{ tick: 10, kind: 'light', dir: 0 }] })]);
    expect(eventsOf(two.events, 'kill', { id: 'd1' })).toHaveLength(1);
  });
});
