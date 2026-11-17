/**
 * Small, allocation-free numeric helpers shared by the actor layer. Pure: no three.js, no DOM,
 * so the interpolation and pose logic built on them is testable in node.
 */

export const TAU = Math.PI * 2;

export function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}

export function clamp01(v: number): number {
  return v < 0 ? 0 : v > 1 ? 1 : v;
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/** Wrap an angle into (-PI, PI]. */
export function wrapAngle(a: number): number {
  if (!Number.isFinite(a)) return 0;
  a = a % TAU;
  if (a <= -Math.PI) a += TAU;
  else if (a > Math.PI) a -= TAU;
  return a;
}

/** Signed shortest difference b - a in (-PI, PI]. */
export function angleDelta(a: number, b: number): number {
  return wrapAngle(b - a);
}

/** Interpolate angles along the shortest arc; result wrapped to (-PI, PI]. */
export function lerpAngle(a: number, b: number, t: number): number {
  return wrapAngle(a + angleDelta(a, b) * t);
}

export function smoothstep(e0: number, e1: number, x: number): number {
  const t = clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
}

/** Frame-rate independent exponential approach: fraction of the gap to close this frame. */
export function dampFactor(rate: number, dt: number): number {
  return 1 - Math.exp(-rate * Math.max(0, dt));
}

export function easeOutCubic(t: number): number {
  const u = 1 - clamp01(t);
  return 1 - u * u * u;
}

export function easeInCubic(t: number): number {
  const u = clamp01(t);
  return u * u * u;
}

export function easeInOutSine(t: number): number {
  return -(Math.cos(Math.PI * clamp01(t)) - 1) / 2;
}

/** 0 → 1 → 0 bump over t in [0, 1]. */
export function bump(t: number): number {
  return Math.sin(Math.PI * clamp01(t));
}

/** Parse '#rrggbb' / '#rgb' / 'rrggbb' into 0xRRGGBB. Falls back when the string is not a colour. */
export function parseHexColor(s: string | undefined, fallback: number): number {
  if (!s) return fallback;
  let h = s.trim();
  if (h.startsWith('#')) h = h.slice(1);
  if (/^[0-9a-fA-F]{3}$/.test(h)) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
  if (!/^[0-9a-fA-F]{6}$/.test(h)) return fallback;
  return parseInt(h, 16);
}

/** Cheap deterministic hash → [0, 1); used for per-instance visual jitter (never for gameplay). */
export function hash01(n: number): number {
  const s = Math.sin(n * 127.1 + 311.7) * 43758.5453123;
  return s - Math.floor(s);
}

export function hashString(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0) / 4294967296;
}
