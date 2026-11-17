import { describe, expect, it } from 'vitest';
import {
  allFinite,
  dft,
  epicycleChain,
  epicycleTrace,
  lissajous,
  rose,
  runeGlyph,
  sigilParamsForChord,
  sigilPoints,
  strongestHarmonics,
  type SigilParams,
} from '../../src/render/fx/curves';
import { momentumTier, TIER_THRESHOLDS } from '../../src/render/fx/words';

function closed(pts: Float32Array, n: number, eps = 1e-5): boolean {
  return Math.abs(pts[0] - pts[(n - 1) * 2]) < eps && Math.abs(pts[1] - pts[(n - 1) * 2 + 1]) < eps;
}

describe('curve generators', () => {
  it('Lissajous figures are finite, bounded and closed', () => {
    for (const [a, b] of [
      [1, 2],
      [3, 2],
      [5, 4],
      [7, 6],
    ]) {
      const n = 200;
      const out = lissajous(new Float32Array(n * 2), n, a, b, Math.PI / 5);
      expect(allFinite(out)).toBe(true);
      expect(closed(out, n)).toBe(true);
      for (let i = 0; i < n * 2; i++) expect(Math.abs(out[i])).toBeLessThanOrEqual(1 + 1e-6);
    }
  });

  it('rose curves close for rational k = p/q', () => {
    for (const [p, q] of [
      [3, 1],
      [2, 1],
      [5, 2],
      [5, 3],
      [7, 4],
      [6, 4],
    ]) {
      const n = 300;
      const out = rose(new Float32Array(n * 2), n, p, q);
      expect(allFinite(out)).toBe(true);
      expect(closed(out, n)).toBe(true);
      for (let i = 0; i < n; i++) expect(Math.hypot(out[i * 2], out[i * 2 + 1])).toBeLessThanOrEqual(1 + 1e-6);
    }
  });

  it('sigil parameters are deterministic per chord and vary across the progression', () => {
    const a: SigilParams = { kind: 'lissajous', a: 0, b: 0, delta: 0, p: 0, q: 0 };
    const b: SigilParams = { ...a };
    const shapes = new Set<string>();
    for (let chord = 0; chord < 8; chord++) {
      sigilParamsForChord(chord, 1, a);
      sigilParamsForChord(chord, 1, b);
      expect(a).toEqual(b);
      shapes.add(JSON.stringify(a));
      const pts = sigilPoints(new Float32Array(160 * 2), 160, a);
      expect(allFinite(pts)).toBe(true);
      expect(closed(pts, 160)).toBe(true);
    }
    expect(shapes.size).toBeGreaterThan(3);
    // Negative / non-integer chord indices are tolerated.
    expect(() => sigilParamsForChord(-3.4, 0, a)).not.toThrow();
  });

  it('epicycle trace is finite and closed for integer frequencies', () => {
    const freq = Float32Array.from([1, 2, 3, 5, 8]);
    const amp = Float32Array.from([0.5, 0.25, 0.12, 0.06, 0.03]);
    const phase = Float32Array.from([0, 1, 2, 0.5, 3]);
    const n = 256;
    const out = epicycleTrace(freq, amp, phase, 5, n, new Float32Array(n * 2));
    expect(allFinite(out)).toBe(true);
    expect(closed(out, n, 1e-5)).toBe(true);
    const chain = epicycleChain(freq, amp, phase, 5, 0, new Float32Array(12));
    expect(chain[0]).toBe(0);
    expect(chain[1]).toBe(0);
    // The chain's tip is the trace's first point.
    expect(chain[10]).toBeCloseTo(out[0], 5);
    expect(chain[11]).toBeCloseTo(out[1], 5);
  });

  it('strongestHarmonics recovers the dominant components of a known signal, strongest first', () => {
    const N = 64;
    const sig = new Float32Array(N);
    for (let t = 0; t < N; t++) {
      const th = (2 * Math.PI * t) / N;
      sig[t] = 0.2 + 0.7 * Math.cos(3 * th + 0.4) + 0.3 * Math.cos(7 * th - 1.1) + 0.1 * Math.cos(12 * th);
    }
    const re = new Float32Array(N);
    const im = new Float32Array(N);
    dft(sig, N, re, im);
    const f = new Float32Array(16);
    const a = new Float32Array(16);
    const p = new Float32Array(16);
    const count = strongestHarmonics(re, im, N, 16, f, a, p);
    expect(count).toBeGreaterThanOrEqual(3);
    expect([f[0], f[1], f[2]]).toEqual([3, 7, 12]);
    expect(a[0]).toBeCloseTo(0.7, 3);
    expect(a[1]).toBeCloseTo(0.3, 3);
    expect(p[0]).toBeCloseTo(0.4, 3);
    for (let i = 1; i < count; i++) expect(a[i]).toBeLessThanOrEqual(a[i - 1]);
    // Reconstruction (dc + Σ a·cos(fθ+φ)) matches the input.
    for (let t = 0; t < N; t += 5) {
      const th = (2 * Math.PI * t) / N;
      let v = re[0] / N;
      for (let i = 0; i < count; i++) v += a[i] * Math.cos(f[i] * th + p[i]);
      expect(v).toBeCloseTo(sig[t], 3);
    }
  });

  it('rune glyphs are deterministic and stay inside their cell', () => {
    for (let s = 0; s < 50; s++) {
      const g1 = runeGlyph(s * 7919);
      const g2 = runeGlyph(s * 7919);
      expect(g1).toEqual(g2);
      expect(g1.length).toBeGreaterThanOrEqual(2);
      for (const stroke of g1) {
        expect(stroke.length % 2).toBe(0);
        expect(stroke.length).toBeGreaterThanOrEqual(4);
        for (const v of stroke) expect(Math.abs(v)).toBeLessThanOrEqual(0.8 + 1e-9);
      }
    }
  });
});

describe('momentum tiers', () => {
  it('grades power against the 1x standing light blow', () => {
    expect(momentumTier(10, 10)).toBe(1);
    expect(momentumTier(4, 10)).toBe(0);
    expect(momentumTier(20, 10)).toBe(2);
    expect(momentumTier(30, 10)).toBe(3);
    expect(momentumTier(100, 10)).toBe(4);
    expect(momentumTier(-5, 10)).toBe(0);
    expect(momentumTier(5, 0)).toBe(4);
    expect(TIER_THRESHOLDS.length).toBe(5);
  });
});
