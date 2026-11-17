/** Colour helpers for effects: everything is linear-ish 0..1 floats in plain arrays (no allocation). */
import { TAPE_COLORS } from '../../core/types';

export function hexToRgb(hex: number, out: Float32Array | number[], o = 0): void {
  out[o] = ((hex >> 16) & 255) / 255;
  out[o + 1] = ((hex >> 8) & 255) / 255;
  out[o + 2] = (hex & 255) / 255;
}

function parseCss(c: string): number {
  const m = /^#?([0-9a-f]{6})$/i.exec(c.trim());
  return m ? parseInt(m[1], 16) : 0xffffff;
}

/** Cassette identity colours (UI-02) as hex numbers, index = tape. */
export const TAPE_HEX: readonly number[] = TAPE_COLORS.map(parseCss);

/** Effect colours that are not part of the theme palette. */
export const FX_HEX = {
  white: 0xffffff,
  /** "Not enough momentum": a dull, cold grey so a clang never reads as a real hit. */
  clang: 0x8f969e,
  dust: 0xcfc3ad,
  enemy: 0xff3d5a,
  /** Fallback for boss recall when the remembered tape is unknown. */
  recall: 0xb26bff,
  slowWorld: 0x7cc8ff,
  fastWorld: 0xffb066,
} as const;
