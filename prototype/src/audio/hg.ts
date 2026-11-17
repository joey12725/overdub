/**
 * Typed access to the vendored Harmonograph engine (src/vendor/harmonograph.js, MUSIC-01).
 *
 * The engine is a UMD file that installs itself on `globalThis.HG` when evaluated; it is pure
 * (no clocks, no randomness), so it is safe in node tests and before audio is unlocked. Only the
 * parts of its API that OVERDUB uses are described here; field names mirror the engine verbatim.
 */
import '../vendor/harmonograph.js';

export type HGChannelType = 'Melody' | 'Bass' | 'Chord' | 'Drums';

export interface HGParamDef {
  key: string;
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  detents: number[];
}

export interface HGFormula {
  id: string;
  name: string;
  category: string;
  /** Human-readable equation. */
  formula: string;
  params: HGParamDef[];
  integer: boolean;
}

export interface HGLane {
  name: string;
  note: number;
  mute: boolean;
  gate: string;
  params: Record<string, number>;
  velocity: string;
  velocityParams: Record<string, number>;
  accent: number;
  ghost: number;
  micro: number;
  logic: string;
  other: number;
  approach: boolean;
  anticipation: boolean;
}

/** One engine voice. Only the fields OVERDUB sets are listed; the rest keep engine defaults. */
export interface HGChannel {
  id: number;
  name: string;
  type: HGChannelType;
  formula: string;
  params: Record<string, number>;
  active: boolean;
  solo: boolean;
  /** Beats per step on the engine's clock. */
  rate: number;
  cycle: number;
  /** Contour index offset in steps (`at = n·speed + phase`). */
  phase: number;
  swing: number;
  /** Late offset in milliseconds at the state tempo. */
  micro: number;
  gate: string;
  gateParams: Record<string, number>;
  gateLength: number;
  velocity: string;
  velocityParams: Record<string, number>;
  accent: number;
  ghost: number;
  repeated: 'retrigger' | 'tie' | 'suppress';
  low: number;
  high: number;
  gravity: number;
  palette: number;
  mode: 'absolute' | 'step';
  fold: 'reflect' | 'wrap' | 'nearest' | 'drift';
  leap: number;
  recovery: boolean;
  /** Blend weight of the phrase shape over the formula contour. */
  contour: number;
  shape: 'arch' | 'ramp' | 'flat';
  phrase: number;
  cadence: boolean;
  variation: number;
  octave: number;
  rootAnchor: boolean;
  octavePattern: number;
  invert: boolean;
  retrograde: boolean;
  speed: number;
  sumEnabled: boolean;
  sumGate: boolean;
  sumVelocity: boolean;
  extension: number;
  inversion: number;
  minimal: boolean;
  spread: number;
  strum: number;
  strumDirection: number;
  voicingFormula: boolean;
  followContour: boolean;
  drumLane: number | null;
  drumFormula: boolean;
  drumThreshold: number;
  drumVelocity: 'formula' | 'fixed' | 'legacy';
  lanes: HGLane[];
}

export interface HGState {
  version: number;
  tempo: number;
  root: number;
  scale: string;
  degree: number;
  borrowed: string;
  quality: string;
  extension: number;
  inversion: number;
  spread: number;
  chordOctave: number;
  shift: boolean;
  escape: boolean;
  chordSource: 'pads' | 'progression' | 'formula';
  progression: number[];
  /** Beats per chord. */
  chordRate: number;
  phrase: number;
  channels: HGChannel[];
  sections: unknown[];
  queuedSection: unknown;
  build: { held: boolean; released: boolean; start: number; end: number | null; [k: string]: unknown };
}

export interface HGNote {
  pitch: number;
  velocity: number;
  /** Engine-clock beat, including swing / micro offsets. */
  beat: number;
  /** Beats. */
  duration: number;
  /** Step index the note was generated from. */
  step: number;
  lane?: number;
  formulaValue?: number;
}

export interface HGChord {
  degree: number;
  /** Pitch class of the chord root. */
  root: number;
  /** Pitch classes of the chord, root first, all inside the scale unless `escape` is set. */
  pcs: number[];
  name: string;
}

export interface HarmonographApi {
  SCALES: Record<string, number[]>;
  GENRES: Record<string, [number, number, number][]>;
  NOTES: string[];
  catalogue: HGFormula[];
  byId: Record<string, HGFormula>;
  defaults(id: string): Record<string, number>;
  cleanParams(id: string, params?: Record<string, number>): Record<string, number>;
  value(id: string, n: number, params?: Record<string, number>, P?: number): number;
  normal(id: string, n: number, params?: Record<string, number>, P?: number): number;
  channel(i: number): HGChannel;
  initialState(): HGState;
  copy<T>(x: T): T;
  degreeMidi(degree: number, s: Pick<HGState, 'root' | 'scale'>): number;
  chordAt(s: HGState, beat: number): HGChord;
  scaleNotes(c: HGChannel, s: HGState): number[];
  compileChannel(s: HGState, index: number, startBeat?: number, bars?: number): HGNote[];
  command(s: HGState, cmd: { type: string; [k: string]: unknown }): HGState;
}

const api = (globalThis as { HG?: HarmonographApi }).HG;
if (!api || typeof api.compileChannel !== 'function') {
  throw new Error('Harmonograph engine failed to load (globalThis.HG missing)');
}

export const HG: HarmonographApi = api;
