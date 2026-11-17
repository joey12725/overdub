import { describe, expect, it } from 'vitest';
import { KeyedPool, Pool } from '../../src/render/actors/pool';

describe('Pool', () => {
  it('reuses released items instead of creating new ones', () => {
    let made = 0;
    const pool = new Pool(() => ({ n: made++ }));
    const a = pool.acquire();
    pool.release(a);
    const b = pool.acquire();
    expect(b).toBe(a);
    expect(pool.totalCreated).toBe(1);
  });

  it('prewarms', () => {
    const pool = new Pool(() => ({}));
    pool.prewarm(5);
    expect(pool.freeCount).toBe(5);
    for (let i = 0; i < 5; i++) pool.acquire();
    expect(pool.totalCreated).toBe(5);
  });

  it('calls onRelease', () => {
    const released: number[] = [];
    const pool = new Pool(
      () => ({ v: 1 }),
      (x) => released.push(x.v),
    );
    pool.release(pool.acquire());
    expect(released).toEqual([1]);
  });
});

describe('KeyedPool (mark and sweep)', () => {
  it('keeps touched keys, releases untouched ones and recycles their views', () => {
    const made: string[] = [];
    const released: string[] = [];
    const pool = new KeyedPool<string, { key: string }>(
      (key) => {
        made.push(key);
        return { key };
      },
      (_item, key) => released.push(key),
    );
    pool.begin();
    const a = pool.touch('a');
    expect(pool.lastNew).toBe(true);
    pool.touch('b');
    pool.sweep();
    expect(pool.size).toBe(2);

    pool.begin();
    expect(pool.touch('a')).toBe(a);
    expect(pool.lastNew).toBe(false);
    pool.sweep();
    expect(released).toEqual(['b']);
    expect(pool.size).toBe(1);

    // 'c' appears: it gets b's recycled view, no new construction.
    pool.begin();
    pool.touch('a');
    pool.touch('c');
    expect(pool.lastNew).toBe(true);
    pool.sweep();
    expect(made).toEqual(['a', 'b']);
    expect(pool.totalCreated).toBe(2);
  });

  it('lets a view veto its release (death burst still playing) until it is done', () => {
    const pool = new KeyedPool<number, { frames: number }>(() => ({ frames: 0 }));
    pool.begin();
    pool.touch(1);
    pool.sweep();
    for (let f = 0; f < 3; f++) {
      pool.begin();
      pool.sweep((v) => ++v.frames < 3);
      expect(pool.has(1)).toBe(f < 2);
    }
  });

  it('clear releases everything and all() returns live + free', () => {
    const pool = new KeyedPool<string, object>(() => ({}));
    pool.begin();
    pool.touch('x');
    pool.touch('y');
    pool.clear();
    expect(pool.size).toBe(0);
    expect(pool.freeCount).toBe(2);
    expect(pool.all().length).toBe(2);
  });
});
