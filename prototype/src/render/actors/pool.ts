/**
 * Object pools. Views for enemies and projectiles come and go between snapshots; building three.js
 * objects on demand would stall frames, so views are created once and recycled.
 */

export class Pool<T> {
  private readonly free: T[] = [];
  private created = 0;

  constructor(
    private readonly factory: () => T,
    private readonly onRelease?: (item: T) => void,
  ) {}

  acquire(): T {
    const item = this.free.pop();
    if (item !== undefined) return item;
    this.created++;
    return this.factory();
  }

  release(item: T): void {
    this.onRelease?.(item);
    this.free.push(item);
  }

  /** Build `n` items up front so the first frames do not allocate. */
  prewarm(n: number): void {
    const tmp: T[] = [];
    for (let i = 0; i < n; i++) tmp.push(this.acquire());
    for (const t of tmp) this.release(t);
  }

  get freeCount(): number {
    return this.free.length;
  }

  get totalCreated(): number {
    return this.created;
  }

  /** Remove and return every free item (for disposal). */
  drain(): T[] {
    const out = this.free.slice();
    this.free.length = 0;
    return out;
  }
}

interface Entry<K, T> {
  key: K;
  item: T;
  gen: number;
}

/**
 * Keyed mark-and-sweep pool: each frame, `begin()`, `touch(key)` every key that is present, then
 * `sweep()` releases the views whose keys were not touched. Lets the layer follow snapshot lists
 * whose members appear and disappear without diffing them. Steady-state frames allocate nothing:
 * entries live in a dense array (swap-remove) indexed by a Map, and entry records are recycled.
 */
export class KeyedPool<K, T> {
  private readonly index = new Map<K, Entry<K, T>>();
  private readonly list: Entry<K, T>[] = [];
  private readonly spare: Entry<K, T>[] = [];
  private gen = 0;
  private readonly pool: Pool<T>;
  private pendingKey: K | undefined;
  /** True when the last `touch` acquired a new view (the caller should reset/attach it). */
  lastNew = false;

  constructor(
    factory: (key: K) => T,
    private readonly onRelease?: (item: T, key: K) => void,
  ) {
    // The factory may need the key for typed construction; it is passed through `pendingKey`.
    this.pool = new Pool<T>(() => factory(this.pendingKey as K));
  }

  /** Start a frame. */
  begin(): void {
    this.gen++;
  }

  /** The view for `key`, acquiring one if the key is new. */
  touch(key: K): T {
    const e = this.index.get(key);
    if (e) {
      e.gen = this.gen;
      this.lastNew = false;
      return e.item;
    }
    this.pendingKey = key;
    const item = this.pool.acquire();
    this.pendingKey = undefined;
    const rec = this.spare.pop() ?? { key, item, gen: this.gen };
    rec.key = key;
    rec.item = item;
    rec.gen = this.gen;
    this.index.set(key, rec);
    this.list.push(rec);
    this.lastNew = true;
    return item;
  }

  has(key: K): boolean {
    return this.index.has(key);
  }

  get(key: K): T | undefined {
    return this.index.get(key)?.item;
  }

  /**
   * Release every view not touched since `begin()`. `keep` may veto a release (e.g. a death burst
   * still playing); vetoed views stay live and are offered again at the next sweep.
   */
  sweep(keep?: (item: T, key: K) => boolean): void {
    for (let i = this.list.length - 1; i >= 0; i--) {
      const e = this.list[i];
      if (e.gen === this.gen) continue;
      if (keep && keep(e.item, e.key)) continue;
      this.removeAt(i);
    }
  }

  private removeAt(i: number): void {
    const e = this.list[i];
    const last = this.list.pop()!;
    if (last !== e) this.list[i] = last;
    this.index.delete(e.key);
    this.onRelease?.(e.item, e.key);
    this.pool.release(e.item);
    this.spare.push(e);
  }

  forEach(fn: (item: T, key: K) => void): void {
    for (let i = 0; i < this.list.length; i++) fn(this.list[i].item, this.list[i].key);
  }

  get size(): number {
    return this.list.length;
  }

  get freeCount(): number {
    return this.pool.freeCount;
  }

  get totalCreated(): number {
    return this.pool.totalCreated;
  }

  /** Release everything (level change). */
  clear(): void {
    for (let i = this.list.length - 1; i >= 0; i--) this.removeAt(i);
  }

  /** Every item, live and free (for disposal). Empties the pool. */
  all(): T[] {
    const out: T[] = [];
    for (const e of this.list) out.push(e.item);
    this.list.length = 0;
    this.index.clear();
    return out.concat(this.pool.drain());
  }
}
