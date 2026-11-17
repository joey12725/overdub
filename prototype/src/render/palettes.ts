/**
 * Theme palettes for the descent (WORLD-04: warmer at the top, more metallic / neon / cold going
 * down). Every layer (env kit, actors, fx) draws from these so a level reads as one picture.
 *
 * Upper: the user rejected a purple lighting cast on the warm board (chapter 18 "Upper layers").
 * Graffiti stays pink / purple, but key, ambient and fill lights are warm or neutral there.
 */
import type { Theme } from '../core/types';
import type { ThemePalette } from './layer';

/** Extra colours the environment kit needs beyond the shared ThemePalette contract. */
export interface EnvPalette extends ThemePalette {
  /** Masonry / stone tint used for ruins and cliff faces. */
  stone: number;
  /** Cliff face colour at the top of the skirt and at its deepest point (fades into background). */
  cliff: number;
  cliffDeep: number;
  /** Mortar / grout and dark recesses. */
  grout: number;
  /** Orange rust / wear. */
  rust: number;
  /** Second graffiti hue (the boards pair pink with purple). */
  graffitiAlt: number;
  /** Warm practical source (lamps, the "occasional warm orange source" of the lower board). */
  warm: number;
  /** Glow used for rune inscriptions on this theme. */
  rune: number;
  /** A theme's signature accent (core: the time machine's chronal glow). */
  accent: number;
  /** Hemisphere ground colour (bounce light from below). */
  bounce: number;
  /** Secondary fill light from the opposite side of the key. */
  fill: number;
  fillIntensity: number;
  /** Ambient motes: colour and count factor 0..1. */
  mote: number;
  moteDensity: number;
  /** Surface finish of floors: 'stone' paints masonry slabs, 'metal' paints inscribed plates. */
  floorFinish: 'stone' | 'mixed' | 'metal';
  /** Fraction of tiles that get ambient overgrowth / vegetation dressing. */
  overgrowth: number;
}

export const PALETTES: Readonly<Record<Theme, EnvPalette>> = {
  upper: {
    theme: 'upper',
    background: 0x221917,
    fog: 0x2a1f1c,
    floor: 0xdcb9a0,
    floorAlt: 0xcaa58e,
    wall: 0xb99178,
    wallTop: 0xeed4b8,
    metal: 0x8e8178,
    trim: 0x6b5446,
    hazard: 0xffc21a,
    foliage: 0x93c22c,
    neonA: 0x4fe6e0,
    neonB: 0xff3d9a,
    neonC: 0xc06bff,
    graffiti: 0xff3fa4,
    ink: 0x1f1412,
    keyLight: 0xfff0d6,
    keyIntensity: 2.7,
    // Neutral sky fill: sunlit faces stay warm, shadows go neutral rather than orange (and never purple).
    ambient: 0xd2d8de,
    ambientIntensity: 1.35,
    bloom: 0.45,
    stone: 0xb7906c,
    cliff: 0x9a7356,
    cliffDeep: 0x2a1f1c,
    grout: 0x5d4334,
    rust: 0xd8742a,
    graffitiAlt: 0xa65ee0,
    warm: 0xffb45a,
    rune: 0xffd27a,
    accent: 0xff3d9a,
    bounce: 0x7a6656,
    fill: 0xffe2bc,
    fillIntensity: 0.35,
    mote: 0xfff0c8,
    moteDensity: 0.6,
    floorFinish: 'stone',
    overgrowth: 0.22,
  },
  mid: {
    theme: 'mid',
    background: 0x17151d,
    fog: 0x1c1a22,
    floor: 0xa49a90,
    floorAlt: 0x8e857e,
    wall: 0x857a72,
    wallTop: 0xb0a598,
    metal: 0x707784,
    trim: 0x474b56,
    hazard: 0xffb81c,
    foliage: 0x76ad3c,
    neonA: 0x2fe6ff,
    neonB: 0xff3fb4,
    neonC: 0x9b5cff,
    graffiti: 0xff4fae,
    ink: 0x121018,
    keyLight: 0xf4e6d2,
    keyIntensity: 2.3,
    ambient: 0xa9b0c4,
    ambientIntensity: 1.15,
    bloom: 0.7,
    stone: 0x8f8378,
    cliff: 0x6b6470,
    cliffDeep: 0x17151d,
    grout: 0x3b3a42,
    rust: 0xc8662a,
    graffitiAlt: 0xa65ee0,
    warm: 0xffa04a,
    rune: 0x4ff0ff,
    accent: 0x2fe6ff,
    bounce: 0x4a4656,
    fill: 0x8fc8ff,
    fillIntensity: 0.55,
    mote: 0xbfe8ff,
    moteDensity: 0.45,
    floorFinish: 'mixed',
    overgrowth: 0.1,
  },
  lower: {
    theme: 'lower',
    background: 0x0d0912,
    fog: 0x0e0a14,
    // The playable floor stays a mid value so selves, enemy tells and sparks read against it
    // (chapter 18 "Lower layers": darkness must not make the floor unreadable).
    floor: 0x7a6884,
    floorAlt: 0x6b5a75,
    wall: 0x463a4f,
    wallTop: 0x7a6684,
    metal: 0x5e5066,
    trim: 0x2b2132,
    hazard: 0xffb020,
    foliage: 0x568f4c,
    neonA: 0x3ff0ff,
    neonB: 0xff2fa0,
    neonC: 0xc040ff,
    graffiti: 0xff3fa4,
    ink: 0x0a0610,
    keyLight: 0xcdc2f0,
    keyIntensity: 2.2,
    ambient: 0x7e6ca6,
    ambientIntensity: 1.2,
    bloom: 1.0,
    stone: 0x5b5060,
    cliff: 0x3a2f42,
    cliffDeep: 0x0d0912,
    grout: 0x1e1724,
    rust: 0xd06a28,
    graffitiAlt: 0xb04dff,
    warm: 0xff8a2a,
    rune: 0xff3fd0,
    accent: 0xff2fa0,
    bounce: 0x2a1a38,
    fill: 0xff4fc0,
    fillIntensity: 0.7,
    mote: 0xff9cf0,
    moteDensity: 0.5,
    floorFinish: 'metal',
    overgrowth: 0.05,
  },
  core: {
    theme: 'core',
    background: 0x06050c,
    fog: 0x07060d,
    floor: 0x58566f,
    floorAlt: 0x4c4a62,
    wall: 0x34324c,
    wallTop: 0x5e5c80,
    metal: 0x4c4a66,
    trim: 0x1d1b2c,
    hazard: 0xffc23a,
    foliage: 0x3f7a6a,
    neonA: 0x3ff0ff,
    neonB: 0xff2fa0,
    neonC: 0x8a4dff,
    graffiti: 0xff3fa4,
    ink: 0x05040a,
    keyLight: 0xbfc8ff,
    keyIntensity: 1.7,
    ambient: 0x6a6aa0,
    ambientIntensity: 1.15,
    bloom: 1.2,
    stone: 0x47455a,
    cliff: 0x29273c,
    cliffDeep: 0x06050c,
    grout: 0x14121f,
    rust: 0xc0602a,
    graffitiAlt: 0x9a5cff,
    warm: 0xff9a3a,
    // The time-machine depth gets its own chronal amber so it reads apart from the lower neon.
    rune: 0xffb347,
    accent: 0xffb347,
    bounce: 0x1c1830,
    fill: 0x5fe8ff,
    fillIntensity: 0.75,
    mote: 0xffd59a,
    moteDensity: 0.7,
    floorFinish: 'metal',
    overgrowth: 0.02,
  },
};

/** Palette for a theme; unknown themes fall back to 'upper' so a bad level still renders. */
export function paletteFor(theme: Theme): EnvPalette {
  return PALETTES[theme] ?? PALETTES.upper;
}

/** Hue (degrees), saturation and lightness of a 0xRRGGBB colour. Used by tests and colour tweaks. */
export function hsl(color: number): { h: number; s: number; l: number } {
  const r = ((color >> 16) & 255) / 255;
  const g = ((color >> 8) & 255) / 255;
  const b = (color & 255) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return { h: 0, s: 0, l };
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h: number;
  if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return { h: h * 60, s, l };
}

/** Linear blend of two 0xRRGGBB colours. */
export function mixColor(a: number, b: number, t: number): number {
  const k = Math.min(1, Math.max(0, t));
  const ch = (shift: number): number => {
    const x = (a >> shift) & 255;
    const y = (b >> shift) & 255;
    return Math.round(x + (y - x) * k) & 255;
  };
  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/** Multiply a colour's channels by `f` (clamped). */
export function scaleColor(c: number, f: number): number {
  const ch = (shift: number): number => Math.min(255, Math.max(0, Math.round(((c >> shift) & 255) * f)));
  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/** CSS string for a colour. */
export function css(c: number, alpha = 1): string {
  const r = (c >> 16) & 255;
  const g = (c >> 8) & 255;
  const b = c & 255;
  return alpha >= 1 ? `rgb(${r},${g},${b})` : `rgba(${r},${g},${b},${alpha})`;
}
