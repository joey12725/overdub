/**
 * Stalker (AI-01, AI-02, AI-07): hunts the FARTHEST effective self; fast; one hit.
 * bpm 120 → 120 substeps per beat; a 1× tape advances 4 substeps per local tick.
 */
import { describe, expect, it } from 'vitest';
import type { EnemyDef, LevelDef } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { eventsOf, frameAt, pathTape, resolve } from '../../helpers/script';

const SPB = 120;

/** Wakes at beat 1, by which time the selves have spread out (they all start together; REC-02). */
const stalker: EnemyDef = { kind: 'enemy', id: 's1', type: 'stalker', x: 6, y: 5, wakeWhen: { beat: { every: 1000, from: 1, to: 1000 } } };

const level: LevelDef = makeLevel({ speeds: [1], bars: 4, start: { x: 2, y: 5 }, entities: [stalker] });

// A stays at the start, 4 tiles from the stalker. B runs to the far corner (5 tiles away).
const tapeA = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 2, y: 5 }] });
const tapeB = pathTape({ index: 1, speed: 1, ticks: 480, path: [{ tick: 0, x: 2, y: 5 }, { tick: 20, x: 10, y: 8 }] });

describe('stalker targeting (AI-01, AI-02)', () => {
  it('alone with one self it hunts that self', () => {
    const res = resolve(level, [tapeA]);
    const f = frameAt(res, SPB + 40);
    expect(f.enemies[0].target).toBe(0);
    expect(f.enemies[0].x).toBeLessThan(6);
  });

  it('a self far away drags it across the room, past a nearer self', () => {
    const solo = resolve(level, [tapeA]);
    const both = resolve(level, [tapeA, tapeB]);
    const f = frameAt(both, SPB + 40);
    expect(f.enemies[0].target).toBe(1);
    // It heads for B (east and south) instead of toward A (west), and A's path is unchanged.
    const g = frameAt(both, 2 * SPB).enemies[0];
    const gs = frameAt(solo, 2 * SPB).enemies[0];
    expect(g.x).toBeGreaterThan(7);
    expect(gs.x).toBeLessThan(5);
    const path = (r: typeof solo) => r.frames.map((fr) => [fr.actors[0].x, fr.actors[0].y]);
    expect(path(both)).toEqual(path(solo));
    // B is the one it kills first.
    const deaths = eventsOf(both.events, 'selfDeath');
    expect(deaths[0].tape).toBe(1);
    expect(deaths[0].detail).toBe('struck by stalker s1');
  });

  it('strikes land on its beat grid (beats 1, 3, 5 …) after a telegraph, then it re-picks the farthest survivor', () => {
    const both = resolve(level, [tapeA, tapeB]);
    const attacks = eventsOf(both.events, 'enemyAttack', { id: 's1' });
    expect(attacks.length).toBeGreaterThanOrEqual(2);
    for (const a of attacks) expect(a.sub % (2 * SPB)).toBe(SPB);
    const tel = eventsOf(both.events, 'enemyTelegraph', { id: 's1' });
    expect(tel[0].sub).toBe(attacks[0].sub - SPB / 2);
    expect(tel[0].tape).toBe(1);
    // After killing B it hunts the only one left.
    const later = tel.find((t) => t.sub > attacks[0].sub);
    expect(later?.tape).toBe(0);
    expect(eventsOf(both.events, 'selfDeath').map((d) => d.tape)).toEqual([1, 0]);
  });

  it('ties go to the lowest tape index', () => {
    const twinA = pathTape({ index: 2, speed: 1, ticks: 480, path: [{ tick: 0, x: 2, y: 5 }] });
    const res = resolve(level, [twinA, tapeA]);
    expect(frameAt(res, SPB + 8).enemies[0].target).toBe(0);
  });

  it('one hit kills it', () => {
    const lvl = makeLevel({ speeds: [1], bars: 1, start: { x: 5, y: 5 }, entities: [{ ...stalker, wakeWhen: { const: false } }] });
    const swing = pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 5, y: 5 }], events: [{ tick: 10, kind: 'light', dir: 0 }] });
    const res = resolve(lvl, [swing]);
    expect(eventsOf(res.events, 'kill', { id: 's1' })).toHaveLength(1);
  });
});
