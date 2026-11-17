/**
 * Which Harmonograph formulas level designers may assign to a cassette layer (MUSIC-02), and the
 * extra layer-shaping keys the audio module reads from `TrackMusicDef.params`.
 *
 * Pure data derived from the engine catalogue; no Web Audio.
 */
import type { TrackMusicDef } from '../core/types';
import { HG } from './hg';

export type MusicRole = TrackMusicDef['role'];
export const MUSIC_ROLES: readonly MusicRole[] = ['melody', 'bass', 'chord', 'drums'];

/**
 * Categories whose formulas produce a pitch contour. 'Harmony' formulas describe chord choice /
 * voicing and 'Expression' formulas are velocity ramps, so as a layer's main contour they would
 * produce a static or saw-tooth line; they are deliberately not offered.
 */
const CONTOUR_CATEGORIES = new Set(['Number sequences', 'Dynamical systems', 'Geometry & waves']);
/** A drum layer's formula drives its hat lane through a hit threshold, so gate formulas suit it too. */
const DRUM_CATEGORIES = new Set([...CONTOUR_CATEGORIES, 'Rhythm & gates']);

export interface MusicParamInfo {
  key: string;
  label: string;
  default: number;
  min: number;
  max: number;
  step: number;
}

export interface MusicFormulaInfo {
  id: string;
  name: string;
  category: string;
  /** The engine's own one-line equation. */
  equation: string;
  /** Roles this formula is safe for. */
  roles: MusicRole[];
  /** Formula parameters accepted in `TrackMusicDef.params` (clamped by the engine). */
  params: MusicParamInfo[];
}

/**
 * Role defaults for the layer-shaping keys. director.ts builds its channels from these, so the
 * values listed to content authors are the values actually used.
 */
export const ROLE_DEFAULTS: Record<MusicRole, { rate: number; pulses: number; steps: number; gravity: number; contour: number }> = {
  // Eighth-note line with a tresillo-like E(5,8) gate; strong beats lean on chord tones.
  melody: { rate: 0.5, pulses: 5, steps: 8, gravity: 0.5, contour: 0.15 },
  // Tresillo E(3,8) on chord tones only.
  bass: { rate: 0.5, pulses: 3, steps: 8, gravity: 0.8, contour: 0.1 },
  // One chord per half bar at 1x; register follows the formula.
  chord: { rate: 2, pulses: 1, steps: 1, gravity: 0.5, contour: 0.2 },
  // Sixteenth-note kit.
  drums: { rate: 0.25, pulses: 1, steps: 1, gravity: 0, contour: 0 },
};

/** Layer-shaping keys accepted in `TrackMusicDef.params` alongside the formula's own parameters. */
export interface LayerParamInfo {
  key: string;
  label: string;
  /** A single default, or one per role. */
  default: number | Partial<Record<MusicRole, number>>;
  min: number;
  max: number;
  step: number;
  roles: MusicRole[];
  description: string;
}

const perRole = (key: 'rate' | 'pulses' | 'steps' | 'gravity' | 'contour', roles: MusicRole[]) =>
  Object.fromEntries(roles.map((r) => [r, ROLE_DEFAULTS[r][key]])) as Partial<Record<MusicRole, number>>;

/**
 * None of these keys collide with any engine formula parameter, so one flat `params` record can
 * carry both (the content validator already accepts any numeric map there).
 */
export const LAYER_PARAMS: readonly LayerParamInfo[] = [
  {
    key: 'rate',
    label: 'Step length',
    default: perRole('rate', ['melody', 'bass', 'chord', 'drums']),
    min: 0.25,
    max: 4,
    step: 0,
    roles: ['melody', 'bass', 'chord', 'drums'],
    description: 'Beats per step at 1x tape speed; snapped to a power of two (0.25, 0.5, 1, 2, 4) so every tape speed stays on the master grid.',
  },
  {
    key: 'register',
    label: 'Octave shift',
    default: 0,
    min: -1,
    max: 1,
    step: 1,
    roles: ['melody', 'bass', 'chord'],
    description: 'Moves the layer range by whole octaves.',
  },
  {
    key: 'pulses',
    label: 'Gate pulses',
    default: perRole('pulses', ['melody', 'bass', 'chord']),
    min: 1,
    max: 16,
    step: 1,
    roles: ['melody', 'bass', 'chord'],
    description: 'Euclidean gate E(pulses, steps): how many steps of each gate cycle sound.',
  },
  {
    key: 'steps',
    label: 'Gate steps',
    default: perRole('steps', ['melody', 'bass', 'chord']),
    min: 1,
    max: 16,
    step: 1,
    roles: ['melody', 'bass', 'chord'],
    description: 'Length of the Euclidean gate cycle in steps.',
  },
  {
    key: 'gravity',
    label: 'Chord gravity',
    default: perRole('gravity', ['melody', 'bass']),
    min: 0,
    max: 1,
    step: 0.01,
    roles: ['melody', 'bass'],
    description: 'How strongly metrically strong steps are pulled onto chord tones (bass always plays chord tones).',
  },
  {
    key: 'contour',
    label: 'Arch blend',
    default: perRole('contour', ['melody', 'bass', 'chord']),
    min: 0,
    max: 0.8,
    step: 0.01,
    roles: ['melody', 'bass', 'chord'],
    description: 'Blend of a phrase-long arch over the raw formula contour (smooths wild formulas).',
  },
  {
    key: 'cycle',
    label: 'Cycle',
    default: 16,
    min: 4,
    max: 64,
    step: 1,
    roles: ['melody', 'bass', 'chord', 'drums'],
    description: 'Period P (in steps) for wave formulas and for retrograde reflection.',
  },
  {
    key: 'phrase',
    label: 'Phrase',
    default: 16,
    min: 4,
    max: 32,
    step: 1,
    roles: ['melody', 'bass', 'chord'],
    description: 'Phrase length in steps; the last step of each phrase cadences on the chord root.',
  },
  {
    key: 'threshold',
    label: 'Hit threshold',
    default: 0.5,
    min: 0.15,
    max: 0.95,
    step: 0.01,
    roles: ['drums'],
    description: "Formula height needed for a hat hit: the drum layer's formula plays its hat lane.",
  },
  {
    key: 'density',
    label: 'Groove density',
    default: 1,
    min: 0.25,
    max: 2,
    step: 0.05,
    roles: ['drums'],
    description: 'Scales the genre groove pulses (kick, snare, perc).',
  },
];

const LAYER_KEYS = new Set(LAYER_PARAMS.map((p) => p.key));

function rolesFor(category: string): MusicRole[] {
  const roles: MusicRole[] = [];
  if (CONTOUR_CATEGORIES.has(category)) roles.push('melody', 'bass', 'chord');
  if (DRUM_CATEGORIES.has(category)) roles.push('drums');
  return roles;
}

/** Every engine formula a level designer may use for some role, with its parameters. */
export function listMusicFormulas(): MusicFormulaInfo[] {
  const out: MusicFormulaInfo[] = [];
  for (const f of HG.catalogue) {
    const roles = rolesFor(f.category);
    // 'groove' is a drum-only formula: its value is a kit pattern, not a contour.
    if (f.id === 'groove') roles.splice(0, roles.length, 'drums');
    if (!roles.length) continue;
    out.push({
      id: f.id,
      name: f.name,
      category: f.category,
      equation: f.formula,
      roles,
      params: f.params.map((p) => ({ key: p.key, label: p.label, default: p.value, min: p.min, max: p.max, step: p.step })),
    });
  }
  return out;
}

const ALLOWED: Map<string, Set<MusicRole>> = new Map(listMusicFormulas().map((f) => [f.id, new Set(f.roles)]));

export function isMusicFormulaAllowed(role: MusicRole, id: string): boolean {
  return ALLOWED.get(id)?.has(role) ?? false;
}

/** Role defaults used when a level names a formula that is unknown or unsuitable for its role. */
export const FALLBACK_FORMULA: Record<MusicRole, string> = {
  melody: 'sine',
  bass: 'triangle',
  chord: 'sine',
  drums: 'euclid',
};

/** The formula a layer will actually use (falls back rather than failing a level load). */
export function resolveFormula(role: MusicRole, id: string): string {
  return isMusicFormulaAllowed(role, id) ? id : FALLBACK_FORMULA[role];
}

/** Splits `TrackMusicDef.params` into formula parameters (engine-cleaned) and layer parameters. */
export function splitParams(
  formula: string,
  params: Record<string, number> | undefined,
): { formula: Record<string, number>; layer: Record<string, number> } {
  const formulaRaw: Record<string, number> = {};
  const layer: Record<string, number> = {};
  for (const [k, v] of Object.entries(params ?? {})) {
    if (!Number.isFinite(v)) continue;
    if (LAYER_KEYS.has(k)) layer[k] = v;
    else formulaRaw[k] = v;
  }
  return { formula: HG.cleanParams(formula, formulaRaw), layer };
}
