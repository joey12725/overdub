/**
 * Deterministic curve generators for the music-linked environment (MUSIC-12): Lissajous and rose
 * floor sigils, the Epicycles-style Fourier hologram and procedural rune glyphs.
 *
 * Pure math, no three.js and no allocation in the per-frame paths: every generator writes into a
 * caller-owned Float32Array so the ambient visuals can re-run them while the music plays.
 * Point lists are interleaved x, y pairs in the unit square [-1, 1]².
 */

const TAU = Math.PI * 2;

/**
 * Lissajous figure x = sin(a·t + δ), y = sin(b·t) over one full period t ∈ [0, 2π].
 * With integer a, b the figure is closed; `n` points are written and the last equals the first.
 */
export function lissajous(out: Float32Array, n: number, a: number, b: number, delta: number): Float32Array {
  const last = n - 1;
  for (let i = 0; i < n; i++) {
    const t = (i === last ? 0 : i / last) * TAU;
    out[i * 2] = Math.sin(a * t + delta);
    out[i * 2 + 1] = Math.sin(b * t);
  }
  return out;
}

function gcd(a: number, b: number): number {
  a = Math.abs(Math.round(a));
  b = Math.abs(Math.round(b));
  while (b !== 0) {
    const t = a % b;
    a = b;
    b = t;
  }
  return a || 1;
}

/**
 * Rose curve r = cos(k·θ) with k = p / q (reduced). The curve closes after θ = 2π·q, so sampling
 * over that range always yields a closed figure; the last point is written equal to the first.
 */
export function rose(out: Float32Array, n: number, p: number, q: number): Float32Array {
  const g = gcd(p, q);
  const pp = Math.round(p) / g;
  const qq = Math.max(1, Math.round(q) / g);
  const k = pp / qq;
  const span = TAU * qq;
  const last = n - 1;
  for (let i = 0; i < n; i++) {
    const th = (i === last ? 0 : i / last) * span;
    const r = Math.cos(k * th);
    out[i * 2] = r * Math.cos(th);
    out[i * 2 + 1] = r * Math.sin(th);
  }
  return out;
}

/** Parameters of one floor sigil. Either a Lissajous (a, b, δ) or a rose (p / q). */
export interface SigilParams {
  kind: 'lissajous' | 'rose';
  a: number;
  b: number;
  delta: number;
  p: number;
  q: number;
}

const LISSAJOUS_RATIOS: readonly (readonly [number, number])[] = [
  [1, 2],
  [3, 2],
  [3, 4],
  [5, 4],
  [2, 3],
  [5, 6],
  [4, 5],
];
const ROSE_RATIOS: readonly (readonly [number, number])[] = [
  [3, 1],
  [2, 1],
  [5, 2],
  [5, 3],
  [7, 4],
  [4, 3],
  [3, 2],
];

/**
 * Sigil shape for a chord index. The same chord always yields the same figure (so the floor reads
 * as a notation of the progression); `variant` lets several sigils in one room differ.
 */
export function sigilParamsForChord(chord: number, variant: number, out: SigilParams): SigilParams {
  const c = ((Math.round(chord) % 64) + 64) % 64;
  const v = ((Math.round(variant) % 64) + 64) % 64;
  const useRose = (c + v) % 2 === 1;
  out.kind = useRose ? 'rose' : 'lissajous';
  const lr = LISSAJOUS_RATIOS[(c * 3 + v) % LISSAJOUS_RATIOS.length];
  const rr = ROSE_RATIOS[(c * 5 + v * 2) % ROSE_RATIOS.length];
  out.a = lr[0];
  out.b = lr[1];
  out.delta = (Math.PI / 8) * ((c + v * 3) % 8);
  out.p = rr[0];
  out.q = rr[1];
  return out;
}

/** Write the sigil figure for `params` into `out` (n points, closed). */
export function sigilPoints(out: Float32Array, n: number, params: SigilParams): Float32Array {
  return params.kind === 'rose' ? rose(out, n, params.p, params.q) : lissajous(out, n, params.a, params.b, params.delta);
}

/**
 * Discrete Fourier transform of a real periodic signal of length n (O(n²); n is small, ~64).
 * Writes bins 0..n-1 into re / im.
 */
export function dft(signal: Float32Array, n: number, re: Float32Array, im: Float32Array): void {
  for (let k = 0; k < n; k++) {
    let sr = 0;
    let si = 0;
    for (let t = 0; t < n; t++) {
      const ang = (TAU * k * t) / n;
      sr += signal[t] * Math.cos(ang);
      si -= signal[t] * Math.sin(ang);
    }
    re[k] = sr;
    im[k] = si;
  }
}

/**
 * Pick the `count` strongest harmonics (frequencies 1..n/2) of a real signal's DFT, strongest
 * first, as epicycles: amplitude and phase such that the signal ≈ dc + Σ amp·cos(freq·θ + phase).
 * Returns how many were written (≤ count). Allocation-free (insertion sort into the outputs).
 */
export function strongestHarmonics(
  re: Float32Array,
  im: Float32Array,
  n: number,
  count: number,
  outFreq: Float32Array,
  outAmp: Float32Array,
  outPhase: Float32Array,
): number {
  let filled = 0;
  const half = n >> 1;
  for (let k = 1; k <= half; k++) {
    // Real signal: bins k and n-k are conjugates, so the k-th cosine has amplitude 2|X_k|/n
    // (Nyquist bin counted once).
    const scale = k === half && n % 2 === 0 ? 1 / n : 2 / n;
    const amp = Math.hypot(re[k], im[k]) * scale;
    if (!(amp > 1e-9)) continue;
    const phase = Math.atan2(im[k], re[k]);
    let pos = filled < count ? filled : count;
    while (pos > 0 && outAmp[pos - 1] < amp) pos--;
    if (pos >= count) continue;
    const end = Math.min(filled, count - 1);
    for (let j = end; j > pos; j--) {
      outFreq[j] = outFreq[j - 1];
      outAmp[j] = outAmp[j - 1];
      outPhase[j] = outPhase[j - 1];
    }
    outFreq[pos] = k;
    outAmp[pos] = amp;
    outPhase[pos] = phase;
    if (filled < count) filled++;
  }
  return filled;
}

/**
 * Centres of a chain of nested rotating circles at angle θ: point 0 is the origin, point i+1 is the
 * tip after circle i. Writes (count + 1) points as x, y pairs. Circle i has radius amp[i] and turns
 * at freq[i] (integer ⇒ the tip's path closes after θ = 2π).
 */
export function epicycleChain(
  freq: Float32Array,
  amp: Float32Array,
  phase: Float32Array,
  count: number,
  theta: number,
  out: Float32Array,
): Float32Array {
  let x = 0;
  let y = 0;
  out[0] = 0;
  out[1] = 0;
  for (let i = 0; i < count; i++) {
    const a = freq[i] * theta + phase[i];
    x += amp[i] * Math.cos(a);
    y += amp[i] * Math.sin(a);
    out[(i + 1) * 2] = x;
    out[(i + 1) * 2 + 1] = y;
  }
  return out;
}

/** The epicycle tip's full path over θ ∈ [0, 2π]: n points, last equals first for integer freqs. */
export function epicycleTrace(
  freq: Float32Array,
  amp: Float32Array,
  phase: Float32Array,
  count: number,
  n: number,
  out: Float32Array,
): Float32Array {
  const last = n - 1;
  for (let s = 0; s < n; s++) {
    const th = (s === last ? 0 : s / last) * TAU;
    let x = 0;
    let y = 0;
    for (let i = 0; i < count; i++) {
      const a = freq[i] * th + phase[i];
      x += amp[i] * Math.cos(a);
      y += amp[i] * Math.sin(a);
    }
    out[s * 2] = x;
    out[s * 2 + 1] = y;
  }
  return out;
}

/** Points on a circle (closed: last equals first). */
export function circlePoints(out: Float32Array, n: number, cx: number, cy: number, r: number): Float32Array {
  const last = n - 1;
  for (let i = 0; i < n; i++) {
    const a = (i === last ? 0 : i / last) * TAU;
    out[i * 2] = cx + r * Math.cos(a);
    out[i * 2 + 1] = cy + r * Math.sin(a);
  }
  return out;
}

/** Small, fast, deterministic PRNG (mulberry32). Returns a function-free state holder to avoid closures per call. */
export class Rng {
  private s: number;
  constructor(seed = 1) {
    this.s = seed >>> 0;
  }
  seed(seed: number): void {
    this.s = seed >>> 0;
  }
  /** Uniform in [0, 1). */
  next(): number {
    let t = (this.s = (this.s + 0x6d2b79f5) >>> 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  range(a: number, b: number): number {
    return a + (b - a) * this.next();
  }
  /** Symmetric in [-a, a). */
  sym(a: number): number {
    return (this.next() * 2 - 1) * a;
  }
}

/** Integer hash of a few numbers, for seeding per-event / per-tile randomness. */
export function hash4(a: number, b: number, c: number, d: number): number {
  let h = 0x811c9dc5;
  h = Math.imul(h ^ (a | 0), 0x01000193);
  h = Math.imul(h ^ (b | 0), 0x01000193);
  h = Math.imul(h ^ (c | 0), 0x01000193);
  h = Math.imul(h ^ (d | 0), 0x01000193);
  h ^= h >>> 13;
  h = Math.imul(h, 0x5bd1e995);
  h ^= h >>> 15;
  return h >>> 0;
}

/**
 * A procedural rune glyph inside the unit cell [-1, 1]²: a few angular strokes on a 3×3 lattice,
 * so glyphs feel engraved and machine-cut rather than like generic fantasy letters (chapter 18 runes).
 * Each stroke is a polyline of 2–3 lattice points. Returns stroke list; called at level load only.
 */
export function runeGlyph(seed: number): number[][] {
  const rng = new Rng(seed);
  const lattice = (i: number) => (i - 1) * 0.8;
  const strokes: number[][] = [];
  // A spine gives every glyph a readable vertical body, like inscribed machine marks.
  const spineX = rng.next() < 0.5 ? 1 : rng.next() < 0.5 ? 0 : 2;
  strokes.push([lattice(spineX), lattice(0), lattice(spineX), lattice(2)]);
  const extra = 1 + Math.floor(rng.next() * 3);
  for (let s = 0; s < extra; s++) {
    const pts = 2 + (rng.next() < 0.45 ? 1 : 0);
    const stroke: number[] = [];
    let cx = Math.floor(rng.next() * 3);
    let cy = Math.floor(rng.next() * 3);
    stroke.push(lattice(cx), lattice(cy));
    for (let p = 1; p < pts; p++) {
      let nx = cx;
      let ny = cy;
      // Step to a different lattice point (orthogonal or diagonal), never staying put.
      for (let guard = 0; guard < 8 && nx === cx && ny === cy; guard++) {
        nx = Math.max(0, Math.min(2, cx + Math.floor(rng.next() * 3) - 1));
        ny = Math.max(0, Math.min(2, cy + Math.floor(rng.next() * 3) - 1));
      }
      if (nx === cx && ny === cy) nx = cx === 1 ? 0 : 1;
      stroke.push(lattice(nx), lattice(ny));
      cx = nx;
      cy = ny;
    }
    strokes.push(stroke);
  }
  return strokes;
}

/** True when every value in the first `len` entries is finite. */
export function allFinite(arr: Float32Array, len = arr.length): boolean {
  for (let i = 0; i < len; i++) if (!Number.isFinite(arr[i])) return false;
  return true;
}
