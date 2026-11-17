import { describe, expect, it } from 'vitest';
import type { ActorSnap, EnemySnap, ProjectileSnap } from '../../src/core/types';
import {
  createActorInterp,
  createEnemyInterp,
  createProjectileInterp,
  findActor,
  findEnemy,
  interpActor,
  interpEnemy,
  interpProjectile,
  TELEPORT_DIST,
} from '../../src/render/actors/interp';
import { angleDelta, lerpAngle, wrapAngle } from '../../src/render/actors/math';

function actor(over: Partial<ActorSnap> = {}): ActorSnap {
  return {
    tape: 0,
    live: false,
    x: 0,
    y: 0,
    facing: 0,
    anim: 'idle',
    life: 'alive',
    synced: true,
    iframes: false,
    phase: { tick: 0, dir: 1, traversal: 0, ended: false },
    vx: 0,
    vy: 0,
    ...over,
  };
}

describe('angle helpers', () => {
  it('wraps into (-PI, PI]', () => {
    expect(wrapAngle(Math.PI * 3)).toBeCloseTo(Math.PI);
    expect(wrapAngle(-Math.PI * 3)).toBeCloseTo(Math.PI);
    expect(wrapAngle(0.5 + Math.PI * 8)).toBeCloseTo(0.5);
    expect(wrapAngle(Number.NaN)).toBe(0);
  });

  it('lerps facing along the shortest arc across the ±PI seam', () => {
    // 170° → -170° is a 20° turn through 180°, not a 340° spin through 0°.
    const a = (170 * Math.PI) / 180;
    const b = (-170 * Math.PI) / 180;
    expect(Math.abs(angleDelta(a, b))).toBeCloseTo((20 * Math.PI) / 180);
    const mid = lerpAngle(a, b, 0.5);
    expect(Math.abs(Math.abs(mid) - Math.PI)).toBeLessThan(1e-9);
    const quarter = lerpAngle(a, b, 0.25);
    expect(quarter).toBeCloseTo((175 * Math.PI) / 180);
  });

  it('lerpAngle endpoints are the inputs (wrapped)', () => {
    for (const [a, b] of [
      [0, 1],
      [3, -3],
      [-2, 2.5],
    ]) {
      expect(lerpAngle(a, b, 0)).toBeCloseTo(wrapAngle(a));
      expect(lerpAngle(a, b, 1)).toBeCloseTo(wrapAngle(b));
    }
  });
});

describe('interpActor', () => {
  it('interpolates position, facing (shortest arc) and playhead', () => {
    const out = createActorInterp();
    const p = actor({ x: 1, y: 2, facing: 3.0, phase: { tick: 10, dir: 1, traversal: 0, ended: false } });
    const c = actor({ x: 2, y: 4, facing: -3.0, phase: { tick: 11, dir: 1, traversal: 0, ended: false } });
    interpActor(p, c, 0.5, out);
    expect(out.x).toBeCloseTo(1.5);
    expect(out.y).toBeCloseTo(3);
    expect(Math.abs(out.facing)).toBeGreaterThan(3.0);
    expect(out.tick).toBeCloseTo(10.5);
    expect(out.teleported).toBe(false);
  });

  it('snaps (no smear) when a repeat tape cuts back to its start', () => {
    const out = createActorInterp();
    const p = actor({ x: 8, y: 8, phase: { tick: 400, dir: 1, traversal: 0, ended: false } });
    const c = actor({ x: 0.2, y: 0.1, phase: { tick: 1, dir: 1, traversal: 1, ended: false } });
    interpActor(p, c, 0.3, out);
    expect(out.teleported).toBe(true);
    expect(out.x).toBe(0.2);
    expect(out.y).toBe(0.1);
    expect(out.tick).toBe(1);
  });

  it('treats a step longer than TELEPORT_DIST as a cut', () => {
    const out = createActorInterp();
    interpActor(actor({ x: 0 }), actor({ x: TELEPORT_DIST + 0.1 }), 0.5, out);
    expect(out.teleported).toBe(true);
    interpActor(actor({ x: 0 }), actor({ x: TELEPORT_DIST - 0.1 }), 0.5, out);
    expect(out.teleported).toBe(false);
  });

  it('interpolates the spark even across a projection cut (it must travel)', () => {
    const out = createActorInterp();
    const p = actor({ x: 8, synced: false, spark: { x: 4, y: 4 }, phase: { tick: 400, dir: 1, traversal: 0, ended: false } });
    const c = actor({ x: 0, synced: false, spark: { x: 5, y: 4 }, phase: { tick: 1, dir: 1, traversal: 1, ended: false } });
    interpActor(p, c, 0.5, out);
    expect(out.hasSpark).toBe(true);
    expect(out.sparkX).toBeCloseTo(4.5);
  });

  it('handles a spark that appears or disappears between snapshots', () => {
    const out = createActorInterp();
    interpActor(actor(), actor({ synced: false, spark: { x: 3, y: 1 } }), 0.2, out);
    expect(out.hasSpark).toBe(true);
    expect(out.sparkX).toBe(3);
    interpActor(actor({ synced: false, spark: { x: 3, y: 1 } }), actor(), 0.2, out);
    expect(out.hasSpark).toBe(false);
  });

  it('takes discrete state from the newer snapshot and works with no previous one', () => {
    const out = createActorInterp();
    interpActor(undefined, actor({ x: 3, anim: 'dodge', iframes: true, life: 'recGhost' }), 0.7, out);
    expect(out.x).toBe(3);
    expect(out.anim).toBe('dodge');
    expect(out.iframes).toBe(true);
    expect(out.life).toBe('recGhost');
  });

  it('clamps alpha outside [0, 1]', () => {
    const out = createActorInterp();
    interpActor(actor({ x: 0 }), actor({ x: 1 }), 2, out);
    expect(out.x).toBe(1);
    interpActor(actor({ x: 0 }), actor({ x: 1 }), -1, out);
    expect(out.x).toBe(0);
  });

  it('finds actors by tape regardless of list order', () => {
    const list = [actor({ tape: 2 }), actor({ tape: 0 })];
    expect(findActor(list, 0, 0)?.tape).toBe(0);
    expect(findActor(list, 2, 0)?.tape).toBe(2);
    expect(findActor(list, 3, 3)).toBeUndefined();
  });
});

function enemy(over: Partial<EnemySnap> = {}): EnemySnap {
  return { id: 'e', type: 'grunt', x: 0, y: 0, facing: 0, hp: 1, maxHp: 1, alive: true, state: 'idle', stateT: 0, ...over };
}

describe('interpEnemy', () => {
  it('lerps stateT within a state and takes the new value across a state change', () => {
    const out = createEnemyInterp();
    interpEnemy(enemy({ state: 'telegraph', stateT: 0.2 }), enemy({ state: 'telegraph', stateT: 0.4 }), 0.5, out);
    expect(out.stateT).toBeCloseTo(0.3);
    interpEnemy(enemy({ state: 'telegraph', stateT: 0.95 }), enemy({ state: 'attack', stateT: 0.1 }), 0.5, out);
    expect(out.stateT).toBeCloseTo(0.1);
    expect(out.state).toBe('attack');
  });

  it('carries target, shield and boss memory fields', () => {
    const out = createEnemyInterp();
    interpEnemy(undefined, enemy({ type: 'boss', target: 2, bossPhase: 1, bossRecall: true, bossRecallTape: 3 }), 0, out);
    expect(out.hasTarget).toBe(true);
    expect(out.target).toBe(2);
    expect(out.bossPhase).toBe(1);
    expect(out.bossRecall).toBe(true);
    expect(out.recallTape).toBe(3);
    interpEnemy(undefined, enemy({ shield: true }), 0, out);
    expect(out.hasTarget).toBe(false);
    expect(out.shield).toBe(true);
    expect(out.recallTape).toBe(-1);
  });

  it('interpolates knockback but snaps a genuine jump', () => {
    const out = createEnemyInterp();
    interpEnemy(enemy({ x: 0 }), enemy({ x: 1.5 }), 0.5, out);
    expect(out.x).toBeCloseTo(0.75);
    interpEnemy(enemy({ x: 0 }), enemy({ x: 40 }), 0.5, out);
    expect(out.x).toBe(40);
    expect(out.teleported).toBe(true);
  });

  it('finds enemies by id', () => {
    expect(findEnemy([enemy({ id: 'a' }), enemy({ id: 'b' })], 'b', 0)?.id).toBe('b');
  });
});

describe('interpProjectile', () => {
  const proj = (over: Partial<ProjectileSnap> = {}): ProjectileSnap => ({
    id: 1,
    owner: { tape: 0 },
    archetype: 'arc',
    x: 0,
    y: 0,
    z: 0,
    dir: 0,
    ...over,
  });
  it('flags fresh projectiles and interpolates height', () => {
    const out = createProjectileInterp();
    interpProjectile(undefined, proj({ z: 1 }), 0.5, out);
    expect(out.fresh).toBe(true);
    expect(out.z).toBe(1);
    interpProjectile(proj({ z: 1, x: 0 }), proj({ z: 2, x: 1 }), 0.5, out);
    expect(out.fresh).toBe(false);
    expect(out.z).toBeCloseTo(1.5);
    expect(out.x).toBeCloseTo(0.5);
  });
});
