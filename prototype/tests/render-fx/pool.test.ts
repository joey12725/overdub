import { describe, expect, it } from 'vitest';
import { SpritePool, TextPool } from '../../src/render/fx/pool';

describe('SpritePool', () => {
  it('never grows past capacity and recycles slots when full', () => {
    const pool = new SpritePool(32);
    const posBuf = pool.pos;
    for (let i = 0; i < 100; i++) {
      const s = pool.spawn(1);
      expect(s).toBeGreaterThanOrEqual(0);
      expect(s).toBeLessThan(32);
      pool.life[s] = 1;
    }
    expect(pool.count).toBe(32);
    expect(pool.pos).toBe(posBuf);
    expect(pool.pos.length).toBe(32 * 3);
  });

  it('reuses a freed slot before stealing', () => {
    const pool = new SpritePool(4);
    const a = pool.spawn(0);
    pool.spawn(0);
    pool.kill(a);
    expect(pool.count).toBe(1);
    expect(pool.spawn(0)).toBe(a);
    expect(pool.count).toBe(2);
  });

  it('steals the sprite closest to the end of its life when full', () => {
    const pool = new SpritePool(3);
    for (let i = 0; i < 3; i++) {
      const s = pool.spawn(0);
      pool.life[s] = 1;
      pool.age[s] = [0.1, 0.9, 0.5][i];
    }
    const stolen = pool.spawn(7);
    expect(stolen).toBe(1);
    expect(pool.tag[stolen]).toBe(7);
    expect(pool.age[stolen]).toBe(0);
  });

  it('expires sprites and returns them to the free list', () => {
    const pool = new SpritePool(8);
    for (let i = 0; i < 8; i++) pool.life[pool.spawn(0)] = 0.2;
    pool.update(0.1);
    expect(pool.count).toBe(8);
    pool.update(0.15);
    expect(pool.count).toBe(0);
    for (let i = 0; i < 8; i++) pool.spawn(0);
    expect(pool.count).toBe(8);
  });

  it('freezes motion during the effect hit-stop, then resumes', () => {
    const pool = new SpritePool(2);
    const s = pool.spawn(0);
    pool.life[s] = 1;
    pool.vel[s * 3] = 10;
    pool.freeze[s] = 0.05;
    pool.update(0.04);
    expect(pool.pos[s * 3]).toBe(0);
    expect(pool.age[s]).toBe(0);
    pool.update(0.02);
    pool.update(0.1);
    expect(pool.pos[s * 3]).toBeGreaterThan(0.5);
  });

  it('holds delayed sprites invisible until their delay elapses', () => {
    const pool = new SpritePool(2);
    const s = pool.spawn(0);
    pool.life[s] = 1;
    pool.age[s] = -0.2;
    const buf = () => [new Float32Array(8), new Float32Array(8), new Float32Array(8), new Float32Array(8)] as const;
    let b = buf();
    expect(pool.writeInstances(b[0], b[1], b[2], b[3])).toBe(0);
    pool.update(0.25);
    b = buf();
    expect(pool.writeInstances(b[0], b[1], b[2], b[3])).toBe(1);
  });

  it('packs shape and orientation mode into the params channel', () => {
    const pool = new SpritePool(1);
    const s = pool.spawn(0);
    pool.shape[s] = 7;
    pool.mode[s] = 2;
    pool.life[s] = 1;
    const p = new Float32Array(4);
    pool.writeInstances(new Float32Array(4), new Float32Array(4), new Float32Array(4), p);
    expect(p[0]).toBe(7 + 64);
  });
});

describe('TextPool', () => {
  it('never grows past capacity and recycles', () => {
    const pool = new TextPool(6);
    for (let i = 0; i < 40; i++) pool.life[pool.spawn(0, i % 5)] = 1;
    expect(pool.count).toBe(6);
    pool.update(2);
    expect(pool.count).toBe(0);
  });

  it('pops oversized at birth and settles to rest size', () => {
    const pool = new TextPool(1);
    const s = pool.spawn(0, 1);
    pool.height[s] = 1;
    pool.life[s] = 2;
    pool.pop[s] = 0.6;
    const ps = new Float32Array(4);
    pool.writeInstances(ps, new Float32Array(4), new Float32Array(4));
    expect(ps[3]).toBeCloseTo(1.6, 5);
    pool.update(0.6);
    pool.writeInstances(ps, new Float32Array(4), new Float32Array(4));
    expect(Math.abs(ps[3] - 1)).toBeLessThan(0.01);
  });
});
