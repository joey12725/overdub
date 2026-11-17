/**
 * Brute (HEALTH-02, MOM-01..05, AI-04, AI-07): 3 hit points, poise against weak hits, a high-momentum
 * hit still shoves it, and a slow, wide slam on its beat grid.
 */
import { describe, expect, it } from 'vitest';
import { BRUTE_POISE_MOMENTUM } from '../../../src/core/enemies/brute';
import { ENEMY_STATS } from '../../../src/core/tuning';
import type { EnemyDef, EnemyType, LevelDef } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { eventsOf, frameAt, pathTape, resolve } from '../../helpers/script';

const SPB = 120;

function sleeper(type: EnemyType, hp?: number): EnemyDef {
  return { kind: 'enemy', id: 'b1', type, x: 6, y: 5, wakeWhen: { const: false }, ...(hp !== undefined ? { hp } : {}) };
}

function level(type: EnemyType, hp?: number): LevelDef {
  return makeLevel({ speeds: [1, 2], bars: 2, start: { x: 4.9, y: 5 }, entities: [sleeper(type, hp)] });
}

/** A self standing west of the enemy, swinging east on the given ticks. */
function swings(ticks: number[], kind: 'light' | 'heavy' = 'light', speed: 1 | 2 = 1) {
  return pathTape({ index: 0, speed, ticks: 240, path: [{ tick: 0, x: 4.9, y: 5 }], events: ticks.map((tick) => ({ tick, kind, dir: 0 })) });
}

describe('brute hit points and poise (HEALTH-02, MOM-05)', () => {
  it('three standing 1× lights kill it; the first two do not move or stagger it', () => {
    const res = resolve(level('brute'), [swings([20, 60, 100])]);
    const hits = eventsOf(res.events, 'hit', { id: 'b1' });
    expect(hits).toHaveLength(3);
    expect(eventsOf(res.events, 'kill', { id: 'b1' })).toHaveLength(1);
    expect(eventsOf(res.events, 'kill', { id: 'b1' })[0].sub).toBe(hits[2].sub);
    expect(eventsOf(res.events, 'enemyStagger', { id: 'b1' })).toHaveLength(0);
    const beforeKill = frameAt(res, hits[2].sub - 4).enemies[0];
    expect(beforeKill).toMatchObject({ x: 6, y: 5, hp: 1 });
  });

  it('the same light shoves a grunt but not a brute', () => {
    const grunt = resolve(level('grunt', 3), [swings([20])]);
    const brute = resolve(level('brute'), [swings([20])]);
    expect(frameAt(grunt, 200).enemies[0].x).toBeGreaterThan(7);
    expect(frameAt(brute, 200).enemies[0].x).toBe(6);
  });

  it('a hit at or above its poise threshold really moves and staggers it', () => {
    // 2× standing heavy: momentum 2 × 2 = 4 ≥ BRUTE_POISE_MOMENTUM. hp raised so it survives.
    expect(4).toBeGreaterThanOrEqual(BRUTE_POISE_MOMENTUM);
    const res = resolve(level('brute', 10), [swings([20], 'heavy', 2)]);
    const hit = eventsOf(res.events, 'hit', { id: 'b1' })[0];
    expect(hit.power).toBeCloseTo(4, 6);
    expect(eventsOf(res.events, 'enemyStagger', { id: 'b1' })).toHaveLength(1);
    const after = frameAt(res, hit.sub + 120).enemies[0];
    // knockback = momentum / mass = 4 / 3 tiles, straight along the swing.
    expect(after.x).toBeCloseTo(6 + 4 / ENEMY_STATS.brute.mass, 3);
    expect(after.hp).toBe(10 - 4);
  });

  it('one 1× running heavy is the momentum lesson: it kills outright', () => {
    // Running east at (slightly over) full run speed when the heavy starts: approach clamps to 1, so momentum
    // 2 × (1 + 0.5) = 3 = 3 damage (tuning.test asserts the same arithmetic).
    const lvl = makeLevel({ speeds: [1], bars: 2, start: { x: 1.5, y: 5 }, entities: [{ ...sleeper('brute'), x: 5.9 }] });
    const runIn = pathTape({
      index: 0,
      speed: 1,
      ticks: 240,
      path: [
        { tick: 0, x: 1.5, y: 5 },
        { tick: 40, x: 4.8, y: 5 },
      ],
      events: [{ tick: 39, kind: 'heavy', dir: 0 }],
    });
    const res = resolve(lvl, [runIn]);
    expect(eventsOf(res.events, 'hit', { id: 'b1' })[0].power).toBeCloseTo(3, 4);
    expect(eventsOf(res.events, 'kill', { id: 'b1' })).toHaveLength(1);
  });
});

describe('brute slam (AI-04, AI-07)', () => {
  const lvl = makeLevel({ speeds: [1], bars: 2, start: { x: 4.9, y: 5 }, entities: [{ kind: 'enemy', id: 'b1', type: 'brute', x: 6, y: 5 }] });
  // A stands in front (nearest: its target). B stands off its flank, 90° from where it will face.
  const a = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 4.9, y: 5 }] });
  const b = pathTape({ index: 1, speed: 1, ticks: 240, path: [{ tick: 0, x: 6, y: 3.6 }] });

  it('telegraphs for telegraphBeats and lands on its grid beat (every 4, offset 2)', () => {
    const res = resolve(lvl, [a]);
    const attacks = eventsOf(res.events, 'enemyAttack', { id: 'b1' });
    expect(attacks.length).toBeGreaterThan(0);
    for (const at of attacks) expect((at.sub - 2 * SPB) % (4 * SPB)).toBe(0);
    const tel = eventsOf(res.events, 'enemyTelegraph', { id: 'b1' });
    expect(tel[0].sub).toBe(attacks[0].sub - ENEMY_STATS.brute.telegraphBeats * SPB);
    expect(tel[0].detail).toBe('slam');
    expect(eventsOf(res.events, 'selfDeath', { tape: 0 })[0]).toMatchObject({ sub: attacks[0].sub, detail: 'struck by brute b1' });
  });

  it('the slam is wide: it also catches a self standing at its side', () => {
    const res = resolve(lvl, [a, b]);
    const attack = eventsOf(res.events, 'enemyAttack', { id: 'b1' })[0];
    expect(eventsOf(res.events, 'selfDeath').map((d) => [d.tape, d.sub])).toEqual([
      [0, attack.sub],
      [1, attack.sub],
    ]);
  });

  it('its body holds a heavy plate', () => {
    const plate = makeLevel({
      speeds: [1],
      bars: 1,
      start: { x: 2, y: 2 },
      entities: [{ ...sleeper('brute'), x: 6.5, y: 5.5 }, { kind: 'plate', id: 'p1', c: 6, r: 5, heavy: true }],
    });
    const idle = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2, y: 2 }] });
    const res = resolve(plate, [idle]);
    expect(res.frames[2].mechs.find((m) => m.id === 'p1')?.on).toBe(true);
  });
});
