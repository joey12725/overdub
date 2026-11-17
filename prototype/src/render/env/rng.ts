/**
 * Deterministic randomness for set dressing. The environment must look identical every time a
 * level loads (and identical between record, review and the cinematic), so nothing in the render
 * kit uses Math.random: every choice is derived from the level id and tile coordinates.
 */

/** FNV-1a 32-bit hash of a string. */
export function hashString(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** Integer mix of a seed with two coordinates; stable across platforms (32-bit integer maths only). */
export function hash3(seed: number, a: number, b: number): number {
  let h = (seed ^ Math.imul(a | 0, 0x27d4eb2d) ^ Math.imul(b | 0, 0x165667b1)) >>> 0;
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  return (h ^ (h >>> 16)) >>> 0;
}

/** Uniform 0..1 value for a tile, stable for a given seed. */
export function tileNoise(seed: number, c: number, r: number): number {
  return hash3(seed, c, r) / 4294967296;
}

/** Small seeded PRNG (mulberry32). */
export class Rng {
  private s: number;

  constructor(seed: number) {
    this.s = seed >>> 0;
  }

  next(): number {
    this.s = (this.s + 0x6d2b79f5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  range(a: number, b: number): number {
    return a + (b - a) * this.next();
  }

  int(a: number, bInclusive: number): number {
    return a + Math.floor(this.next() * (bInclusive - a + 1));
  }

  chance(p: number): boolean {
    return this.next() < p;
  }

  pick<T>(items: readonly T[]): T {
    return items[Math.floor(this.next() * items.length) % items.length];
  }
}
