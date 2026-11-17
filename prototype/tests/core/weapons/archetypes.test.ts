/**
 * Ranged weapon archetypes (WEAPON-01..03, NEW-02, NEW-04, NEW-05): fixed trigger, simulated
 * projectile. Every scene uses a stationary shooter built with pathTape and sleeping enemies, so the
 * only thing that changes between runs is the weapon data.
 */
import { describe, expect, it } from 'vitest';
import { arcHeight } from '../../../src/core/weapons/index';
import { BASE } from '../../../src/core/tuning';
import type { EntityDef, LevelDef, RangedWeaponDef, Resolution, TapeSpeed } from '../../../src/core/types';
import { makeLevel, OPEN_ROOM } from '../../helpers/levels';
import { baseLoadout } from '../../helpers/loadout';
import { eventsOf, pathTape, resolve } from '../../helpers/script';

const SLEEP = { const: false } as const;

function grunt(id: string, x: number, y: number, hp = 1): EntityDef {
  return { kind: 'enemy', id, type: 'grunt', x, y, hp, wakeWhen: SLEEP };
}

function level(entities: EntityDef[], map = OPEN_ROOM): LevelDef {
  return makeLevel({ speeds: [1], bars: 4, map, start: { x: 2.5, y: 5.5 }, entities });
}

/** Shooter standing at (2.5, 5.5) firing once at local tick 10 along `dir`. */
function shooter(dir = 0, speed: TapeSpeed = 1, x = 2.5, y = 5.5) {
  return pathTape({ index: 0, speed, ticks: 480, path: [{ tick: 0, x, y }], events: [{ tick: 10, kind: 'ranged', dir }] });
}

/** Launch substep of the tick-10 shot at 1x (commit ≥ 5 ⇒ launch delay = BASE.rangedLaunchDelay). */
const LAUNCH = (10 + BASE.rangedLaunchDelay) * 4;

const WEAPONS: Record<RangedWeaponDef['archetype'], Partial<RangedWeaponDef>> = {
  missile: { archetype: 'missile', speed: 2.5, range: 14, turnRate: 2.5, pierce: 0 },
  pierce: { archetype: 'pierce', speed: 24, range: 12, pierce: 3, radius: 0.12, turnRate: 0 },
  phase: { archetype: 'phase', speed: 6, range: 9, passesWalls: true, pierce: 0, turnRate: 0 },
  arc: { archetype: 'arc', speed: 7, range: 6, lobbed: true, blast: 1.2, pierce: 0, turnRate: 0 },
  burst: { archetype: 'burst', speed: 16, range: 8, count: 5, spreadDeg: 40, pierce: 0, turnRate: 0, radius: 0.2 },
};

function fire(lv: LevelDef, ranged: Partial<RangedWeaponDef>, dir = 0, speed: TapeSpeed = 1): Resolution {
  return resolve(lv, [shooter(dir, speed)], baseLoadout({ ranged }));
}

function hitsOn(res: Resolution, id: string) {
  return eventsOf(res.events, 'hit', { id }).filter((e) => e.tape === 0);
}

describe('launch', () => {
  it("every archetype launches through the ranged hook at the launch tick and announces 'fire'", () => {
    for (const w of Object.values(WEAPONS)) {
      const res = fire(level([]), w);
      const fires = eventsOf(res.events, 'fire');
      expect(fires.map((e) => [e.sub, e.tape, e.detail])).toEqual([[LAUNCH, 0, w.archetype]]);
      expect(fires[0].power).toBe(w.archetype === 'burst' ? 5 : 1);
      const after = res.frames.find((f) => f.sub === LAUNCH + 4)!;
      expect(after.projectiles.length).toBe(w.archetype === 'burst' ? 5 : 1);
      for (const p of after.projectiles) expect(p).toMatchObject({ owner: { tape: 0 }, archetype: w.archetype });
    }
  });
});

describe('NEW-02: the missile is very slow', () => {
  it('a missile reaches the same target much later than the direct-fire archetypes', () => {
    const lv = level([grunt('g1', 8.5, 5.5)]);
    const firstHit = (w: Partial<RangedWeaponDef>) => hitsOn(fire(lv, w), 'g1')[0]?.sub ?? Infinity;
    const missile = firstHit(WEAPONS.missile);
    const pierce = firstHit(WEAPONS.pierce);
    const burst = firstHit(WEAPONS.burst);
    expect(missile).toBeLessThan(Infinity);
    expect(pierce).toBeLessThan(missile);
    expect(burst).toBeLessThan(missile);
    // ~5.5 tiles at 2.5 tiles/s is over two master seconds; the needle covers it in about a quarter second.
    expect(missile - LAUNCH).toBeGreaterThan(2 * 240);
    expect(pierce - LAUNCH).toBeLessThan(0.3 * 240);
  });

  it('projectile speed is master-time: the same shot flies identically from a 0.5x, 1x or 2x tape', () => {
    const lv = makeLevel({ speeds: [0.5, 1, 2], bars: 2, start: { x: 2.5, y: 5.5 }, entities: [grunt('g1', 8.5, 5.5, 5)] });
    const travel = (speed: TapeSpeed) => {
      const tape = pathTape({ index: 0, speed, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }], events: [{ tick: 10, kind: 'ranged', dir: 0 }] });
      const res = resolve(lv, [tape], baseLoadout({ ranged: { ...WEAPONS.pierce, pierce: 0, impact: 2.4 } }));
      const fireSub = eventsOf(res.events, 'fire')[0].sub;
      const hit = hitsOn(res, 'g1')[0];
      return { flight: hit.sub - fireSub, power: hit.power };
    };
    const a = travel(0.5);
    const b = travel(1);
    const c = travel(2);
    expect(a).toEqual(b);
    expect(c).toEqual(b);
    // Tape speed is not multiplied into a projectile's momentum (weapons/common.ts).
    expect(b.power).toBe(2.4);
  });

  it('StatMods.projectileSpeed scales flight speed', () => {
    const lv = level([grunt('g1', 8.5, 5.5)]);
    const base = hitsOn(resolve(lv, [shooter()], baseLoadout({ ranged: WEAPONS.missile })), 'g1')[0].sub - LAUNCH;
    const fast = hitsOn(resolve(lv, [shooter()], baseLoadout({ ranged: WEAPONS.missile, mods: { projectileSpeed: 2 } })), 'g1')[0].sub - LAUNCH;
    expect(fast).toBeLessThan(base * 0.6);
  });
});

describe('momentum model', () => {
  it('a hit delivers def.impact through the melee damage / knockback / stagger arithmetic, with ranged efficiencies of 1', () => {
    const lv = level([grunt('g1', 6.5, 5.5, 5)]);
    // A heavy-handed melee weapon must not change what the gun does.
    const res = resolve(lv, [shooter()], baseLoadout({ ranged: { ...WEAPONS.pierce, pierce: 0, impact: 2.4 }, melee: { damageEff: 3, knockbackEff: 3 } }));
    const hit = hitsOn(res, 'g1')[0];
    expect(hit.power).toBe(2.4);
    const last = res.frames[res.frames.length - 1].enemies[0];
    expect(last.hp).toBe(5 - 2); // floor(2.4)
    expect(last.x).toBeCloseTo(6.5 + 2.4, 3); // knockback = 2.4 / mass 1, along the shot
    expect(eventsOf(res.events, 'enemyStagger', { id: 'g1' })).toHaveLength(1);
    // The loadout's damage modifier applies to shots too.
    const strong = resolve(lv, [shooter()], baseLoadout({ ranged: { ...WEAPONS.pierce, pierce: 0, impact: 2.4 }, mods: { damage: 1.5 } }));
    expect(strong.frames[strong.frames.length - 1].enemies[0].hp).toBe(5 - 3); // floor(3.6)
  });
});

describe('NEW-04: piercing', () => {
  const lv = level([grunt('g1', 5.5, 5.5, 5), grunt('g2', 7.5, 5.5, 5), grunt('g3', 9.5, 5.5, 5)]);

  it('a piercing shot strikes successive enemies in its line, each exactly once', () => {
    const res = fire(lv, WEAPONS.pierce);
    const subs = ['g1', 'g2', 'g3'].map((id) => {
      const h = hitsOn(res, id);
      expect(h).toHaveLength(1);
      expect(h[0].detail).toBe('pierce');
      return h[0].sub;
    });
    expect(subs[0]).toBeLessThan(subs[1]);
    expect(subs[1]).toBeLessThan(subs[2]);
    expect(eventsOf(res.events, 'projectileHit').filter((e) => e.detail === 'pierce:pass').map((e) => e.id)).toEqual(['g1', 'g2', 'g3']);
    // Three pass-throughs left nothing to stop it, so it ends at the far wall.
    expect(eventsOf(res.events, 'projectileHit').filter((e) => e.detail === 'pierce:wall')).toHaveLength(1);
  });

  it('pierce N passes through N enemies and stops at the next', () => {
    const res = fire(lv, { ...WEAPONS.pierce, pierce: 1 });
    expect(hitsOn(res, 'g1')).toHaveLength(1);
    expect(hitsOn(res, 'g2')).toHaveLength(1);
    expect(hitsOn(res, 'g3')).toHaveLength(0);
  });

  it('a normal projectile does not inherit piercing', () => {
    for (const w of [WEAPONS.missile, { ...WEAPONS.burst, count: 1 }, WEAPONS.phase]) {
      const res = fire(lv, w);
      expect(hitsOn(res, 'g1')).toHaveLength(1);
      expect(hitsOn(res, 'g2')).toHaveLength(0);
      expect(hitsOn(res, 'g3')).toHaveLength(0);
    }
  });
});

describe('NEW-05: walls and cover follow each archetype’s own rules', () => {
  // A full-height wall at column 5 between the shooter (x 2.5) and the enemy (x 8.5).
  const WALLED = OPEN_ROOM.map((row, r) => (r === 0 || r === OPEN_ROOM.length - 1 ? row : row.slice(0, 5) + '#' + row.slice(6)));

  it("only 'phase' passes walls and only 'arc' clears them by flying over; the rest are stopped", () => {
    const lv = level([grunt('g1', 8.5, 5.5)], WALLED);
    for (const arch of ['missile', 'pierce', 'burst'] as const) {
      const res = fire(lv, WEAPONS[arch]);
      expect(hitsOn(res, 'g1')).toHaveLength(0);
      expect(eventsOf(res.events, 'projectileHit').filter((e) => e.detail === `${arch}:wall`).length).toBeGreaterThan(0);
    }
    const phase = fire(lv, WEAPONS.phase);
    expect(hitsOn(phase, 'g1')).toHaveLength(1);
    expect(eventsOf(phase.events, 'kill', { id: 'g1' })).toHaveLength(1);
    const arc = fire(lv, WEAPONS.arc);
    expect(hitsOn(arc, 'g1')).toHaveLength(1);
    expect(eventsOf(arc.events, 'projectileHit').filter((e) => e.detail === 'arc:land')).toHaveLength(1);
  });

  it('a weapon only passes walls when its own data says so', () => {
    const lv = level([grunt('g1', 8.5, 5.5)], WALLED);
    expect(hitsOn(fire(lv, { ...WEAPONS.pierce, passesWalls: true }), 'g1')).toHaveLength(1);
  });

  it('a closed door stops a straight shot but not a phase shot', () => {
    const map = OPEN_ROOM.map((row, r) => (r === 0 || r === OPEN_ROOM.length - 1 ? row : row.slice(0, 5) + (r === 5 ? '.' : '#') + row.slice(6)));
    const lv = level([{ kind: 'door', id: 'd1', cells: [{ c: 5, r: 5 }], openWhen: { const: false } }, grunt('g1', 8.5, 5.5)], map);
    expect(hitsOn(fire(lv, WEAPONS.pierce), 'g1')).toHaveLength(0);
    expect(hitsOn(fire(lv, WEAPONS.phase), 'g1')).toHaveLength(1);
    const open = level([{ kind: 'door', id: 'd1', cells: [{ c: 5, r: 5 }], openWhen: { const: true } }, grunt('g1', 8.5, 5.5)], map);
    expect(hitsOn(fire(open, WEAPONS.pierce), 'g1')).toHaveLength(1);
  });

  it('a phase shot never crosses the map edge', () => {
    const res = fire(level([]), { ...WEAPONS.phase, range: 40 });
    const edge = eventsOf(res.events, 'projectileHit').filter((e) => e.detail === 'phase:edge');
    expect(edge).toHaveLength(1);
    expect(edge[0].x).toBeGreaterThan(11.99);
    expect(edge[0].x).toBeLessThanOrEqual(12);
    for (const f of res.frames) for (const p of f.projectiles) expect(p.x).toBeLessThanOrEqual(12);
  });

  it('a phase shot stops at the first enemy it meets', () => {
    const res = fire(level([grunt('g1', 5.5, 5.5, 5), grunt('g2', 7.5, 5.5, 5)]), WEAPONS.phase);
    expect(hitsOn(res, 'g1')).toHaveLength(1);
    expect(hitsOn(res, 'g2')).toHaveLength(0);
  });
});

describe('arc', () => {
  it('flies over enemies in flight and bursts at its landing point', () => {
    const lv = level([grunt('near', 4.5, 5.5), grunt('far', 8.5, 5.5)]);
    const arc = fire(lv, WEAPONS.arc);
    expect(hitsOn(arc, 'near')).toHaveLength(0);
    expect(hitsOn(arc, 'far')).toHaveLength(1);
    const land = eventsOf(arc.events, 'projectileHit').find((e) => e.detail === 'arc:land')!;
    expect(land.x).toBeCloseTo(8.5, 5);
    expect(land.y).toBeCloseTo(5.5, 5);
    expect(land.power).toBe(1.2);
    // A straight, non-piercing shot is stopped by the first body instead.
    const straight = fire(lv, { ...WEAPONS.burst, count: 1 });
    expect(hitsOn(straight, 'near')).toHaveLength(1);
    expect(hitsOn(straight, 'far')).toHaveLength(0);
  });

  it('reports its height: above the floor in flight, peaking mid-way, on the floor at landing', () => {
    const res = fire(level([]), WEAPONS.arc);
    const zs = res.frames.flatMap((f) => f.projectiles.filter((p) => p.archetype === 'arc').map((p) => p.z));
    expect(zs.length).toBeGreaterThan(10);
    expect(zs.slice(1).every((z) => z > 0)).toBe(true);
    const peak = Math.max(...zs);
    expect(peak).toBeCloseTo(arcHeight(0.5), 1);
    const i = zs.indexOf(peak);
    expect(i).toBeGreaterThan(zs.length * 0.3);
    expect(i).toBeLessThan(zs.length * 0.7);
  });

  it('lands at its range, never short of minRange, and never beyond the map edge', () => {
    const landX = (w: Partial<RangedWeaponDef>) => eventsOf(fire(level([]), w).events, 'projectileHit').find((e) => e.detail === 'arc:land')!.x;
    expect(landX({ ...WEAPONS.arc, range: 5 })).toBeCloseTo(7.5, 5);
    expect(landX({ ...WEAPONS.arc, range: 2, minRange: 4 })).toBeCloseTo(6.5, 5);
    const edge = landX({ ...WEAPONS.arc, range: 30 });
    expect(edge).toBeLessThan(12);
    expect(edge).toBeGreaterThan(11.99);
  });

  it('the landing blast strikes every enemy it overlaps and pushes each away from the centre', () => {
    const lv = level([grunt('centre', 8.5, 5.5), grunt('side', 8.5, 6.5, 5), grunt('out', 8.5, 7.9)]);
    const res = fire(lv, WEAPONS.arc);
    expect(eventsOf(res.events, 'kill', { id: 'centre' })).toHaveLength(1);
    expect(hitsOn(res, 'side')).toHaveLength(1);
    expect(hitsOn(res, 'out')).toHaveLength(0);
    const side = res.frames[res.frames.length - 1].enemies.find((e) => e.id === 'side')!;
    expect(side.y).toBeGreaterThan(6.5 + 0.5);
    expect(side.x).toBeCloseTo(8.5, 5);
  });

  it('a wall shields an enemy from the blast', () => {
    const map = OPEN_ROOM.map((row, r) => (r === 6 ? row.slice(0, 7) + '###' + row.slice(10) : row));
    const res = fire(level([grunt('centre', 8.5, 5.5), grunt('behind', 8.5, 7.1)], map), WEAPONS.arc);
    expect(hitsOn(res, 'centre')).toHaveLength(1);
    expect(hitsOn(res, 'behind')).toHaveLength(0);
  });
});

describe('burst', () => {
  it('fans def.count pellets evenly across def.spreadDeg around the recorded direction', () => {
    const res = fire(level([]), WEAPONS.burst);
    const f = res.frames.find((fr) => fr.sub === LAUNCH + 4)!;
    const degs = f.projectiles.map((p) => Math.round((p.dir * 180) / Math.PI));
    expect(degs).toEqual([-20, -10, 0, 10, 20]);
  });

  it('pellets reach enemies on the edges of the fan but fizzle out at short range', () => {
    const a = (20 * Math.PI) / 180;
    const lv = level([
      grunt('up', 2.5 + 2.5 * Math.cos(a), 5.5 - 2.5 * Math.sin(a), 9),
      grunt('down', 2.5 + 2.5 * Math.cos(a), 5.5 + 2.5 * Math.sin(a), 9),
      grunt('far', 9.5, 5.5, 9),
    ]);
    const res = fire(lv, { ...WEAPONS.burst, range: 3.5 });
    expect(hitsOn(res, 'up').length).toBeGreaterThan(0);
    expect(hitsOn(res, 'down').length).toBeGreaterThan(0);
    expect(hitsOn(res, 'far')).toHaveLength(0);
    // Every pellet is gone well before the far enemy's distance.
    for (const fr of res.frames) for (const p of fr.projectiles) expect(Math.hypot(p.x - 2.5, p.y - 5.5)).toBeLessThanOrEqual(3.5 + 1e-6);
  });
});
