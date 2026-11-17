/**
 * Floating combat readouts: the word list baked into the canvas atlas and the momentum tiers.
 *
 * Tier words are graded against the momentum of a 1× standing light attack with the current loadout
 * (docs/ARCHITECTURE.md "Combat": that blow is tuned to kill a 1-hit enemy), so "HIT!" means "a
 * normal blow" no matter which weapon is equipped, and the bigger words show the player that speed
 * and approach (MOM-01, MOM-03) are what made the difference.
 */

export const WORDS = [
  'TAP',
  'HIT!',
  'SMASH!',
  'CRUSH!!',
  'OVERDUB!!',
  'CLANG',
  'DESYNC',
  'RESYNC',
  'A',
  'B',
  'C',
  'D',
  'KO!',
  'BREAK!',
  'REMEMBERS',
  'PHASE',
  'CLEAR!',
] as const;

export type Word = (typeof WORDS)[number];

export const W_TAP = 0;
export const W_HIT = 1;
export const W_SMASH = 2;
export const W_CRUSH = 3;
export const W_OVERDUB = 4;
export const W_CLANG = 5;
export const W_DESYNC = 6;
export const W_RESYNC = 7;
/** Tape letters A..D are W_TAPE_A + tape index. */
export const W_TAPE_A = 8;
export const W_KO = 12;
export const W_BREAK = 13;
export const W_REMEMBERS = 14;
export const W_PHASE = 15;
export const W_CLEAR = 16;

/** Lower bounds of each momentum tier as a multiple of the reference (1× standing light) momentum. */
export const TIER_THRESHOLDS: readonly number[] = [0, 0.85, 1.6, 2.6, 4.0];

/** Momentum tier 0..4 for `power` relative to `reference`. */
export function momentumTier(power: number, reference: number): number {
  const ref = reference > 1e-6 ? reference : 1;
  const r = Math.max(0, power) / ref;
  let tier = 0;
  for (let i = 1; i < TIER_THRESHOLDS.length; i++) if (r >= TIER_THRESHOLDS[i]) tier = i;
  return tier;
}

/** Atlas word index for a momentum tier. */
export function tierWord(tier: number): number {
  return W_TAP + Math.max(0, Math.min(4, tier | 0));
}
