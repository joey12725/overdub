/**
 * OVERDUB music analysis library (composer's tools; not shipped in the game).
 *
 * Renders the note streams the game will really play, by driving the prototype's own code path
 * (prototype/src/audio/director.ts + the vendored Harmonograph engine), and measures them.
 *
 * Two renderers are provided and compared note-for-note by `verify-statemaps.ts`:
 *   - `protoNotes`  : MusicDirector.notes(), the hard-coded state behaviour of the prototype;
 *   - `mapNotes`    : the same baseline channel, with the dead / desynced / reversing / stopped
 *                     changes applied from the DATA in data/music/*.json "stateMaps".
 * With the default state maps the two are identical, which is what makes the state-map data a
 * faithful description of what the audio engineer has to apply.
 *
 * Run from prototype/:  npx vite-node ../art/music/<script>.ts
 */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MusicDirector, ROLE_SHAPES, DRUM_NOTE, type LayerNote, type LayerVariant, type DrumKind } from '../../prototype/src/audio/director';
import { HG } from '../../prototype/src/audio/hg';

export const HERE = dirname(fileURLToPath(import.meta.url));
export const REPO = resolve(HERE, '..', '..');
export const MUSIC_DIR = join(REPO, 'data', 'music');

export type Speed = 0.5 | 1 | 2 | 4;
export const SPEEDS3: Speed[] = [0.5, 1, 2];
export const SPEEDS4: Speed[] = [0.5, 1, 2, 4];
export const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
export const noteName = (p: number) => NOTE_NAMES[((p % 12) + 12) % 12] + (Math.floor(p / 12) - 1);
export const midiHz = (p: number) => 440 * 2 ** ((p - 69) / 12);

export interface TrackDef {
  role: 'bass' | 'drums' | 'melody' | 'chord';
  formula: string;
  params?: Record<string, number>;
  genre?: string;
}
export interface MusicDef {
  root: number;
  scale: string;
  progression: number[];
  chordBars?: number;
  tracks: TrackDef[];
}
export interface PieceFile {
  id: string;
  bpm: number;
  music: MusicDef;
  stateMaps: StateMaps;
  [k: string]: unknown;
}

export function loadPieces(dir = MUSIC_DIR): PieceFile[] {
  return readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => JSON.parse(readFileSync(join(dir, f), 'utf8')) as PieceFile);
}

// ───────────────────────────── state maps (data) ─────────────────────────────

export interface Op {
  param: string;
  op: 'set' | 'add' | 'mul' | 'max' | 'min';
  value: number | boolean | string;
  /** Scale by the drift level d (0..1): set → value·d, add → value·d, mul → 1 + (value − 1)·d. */
  drift?: boolean;
  round?: boolean;
  min?: number;
  max?: number;
  /** Restrict to these roles (pitched ops) or lane classes (drum ops). */
  only?: string[];
}
export interface StateMap {
  pitched: Op[];
  drums: { lanes?: string[]; backbeatAs?: string; ops: Op[] };
  [k: string]: unknown;
}
export interface StateMaps {
  dead: StateMap;
  desynced: StateMap;
  reversing: StateMap;
  stopped: StateMap;
  [k: string]: unknown;
}

function applyOps(target: Record<string, any>, ops: Op[], drift: number, tag: string): void {
  for (const o of ops) {
    if (o.only && !o.only.includes(tag)) continue;
    const cur = target[o.param];
    let next: any;
    if (typeof o.value !== 'number') next = o.value;
    else {
      const v = o.value;
      if (o.op === 'set') next = o.drift ? v * drift : v;
      else if (o.op === 'add') next = cur + (o.drift ? v * drift : v);
      else if (o.op === 'mul') next = cur * (o.drift ? 1 + (v - 1) * drift : v);
      else if (o.op === 'max') next = Math.max(cur, v);
      else next = Math.min(cur, v);
      if (o.round) next = Math.round(next);
      if (o.min !== undefined) next = Math.max(o.min, next);
      if (o.max !== undefined) next = Math.min(o.max, next);
    }
    target[o.param] = next;
  }
}

const clamp = (x: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, x));
function snapRate(rate: number | undefined, fallback: number): number {
  if (rate === undefined || !Number.isFinite(rate) || rate <= 0) return fallback;
  return 2 ** Math.round(Math.log2(Math.min(4, Math.max(0.25, rate))));
}

const CLAP_GENRES = new Set(['House', 'Trap', 'Jersey club', 'Reggaeton', 'Dancehall']);
const TOM_GENRES = new Set(['Rock', 'Funk / disco', 'Boom bap', 'Lo-fi 80', 'Jungle']);
const SWING_GENRES = new Set(['Lo-fi 80', 'Boom bap', 'Funk / disco']);
const DRUM_NORM: Record<string, number> = { kick: 0.05, tom: 0.3, snare: 0.45, clap: 0.5, rim: 0.55, perc: 0.65, hatClosed: 0.85, hatOpen: 0.95 };

/** The states of a variant, in the order the maps are applied. */
function activeStates(v: LayerVariant): (keyof StateMaps)[] {
  const out: (keyof StateMaps)[] = [];
  if (v.dead) out.push('dead');
  if (v.drift > 0) out.push('desynced');
  if (v.transport === -1) out.push('reversing');
  if (v.transport === 0) out.push('stopped');
  return out;
}

/** Notes of one layer in one master bar, with state behaviour taken from `maps` (data). */
export function mapBar(d: MusicDirector, maps: StateMaps, track: number, v: LayerVariant, bar: number): LayerNote[] {
  const dd = d as any;
  const l = dd.layers[track];
  const start = bar * 4;
  const out: LayerNote[] = [];
  const states = activeStates(v);
  if (l.role === 'drums') {
    const clap = CLAP_GENRES.has(l.genre);
    const all = [
      { cls: 'kick', lane: 0, kind: 'kick', signature: false, grooveVoice: 0, accent: 112, ghost: 76 },
      { cls: 'backbeat', lane: clap ? 4 : 1, kind: clap ? 'clap' : 'snare', signature: false, grooveVoice: 1, accent: 100, ghost: 62 },
      { cls: 'hat', lane: 2, kind: 'hatClosed', signature: true, grooveVoice: 2, accent: 84, ghost: 30 },
      { cls: 'perc', lane: 5, kind: TOM_GENRES.has(l.genre) ? 'tom' : 'perc', signature: false, grooveVoice: 5, accent: 78, ghost: 40 },
    ];
    let keep = all.map((x) => x.cls);
    let backbeatAs: string | undefined;
    for (const s of states) {
      const m = maps[s] as StateMap;
      if (m.drums.lanes) keep = keep.filter((k) => m.drums.lanes!.includes(k));
      if (m.drums.backbeatAs) backbeatAs = m.drums.backbeatAs;
    }
    const genreIndex = Object.keys(HG.GENRES).indexOf(l.genre);
    for (const spec of all) {
      if (!keep.includes(spec.cls)) continue;
      const lp = l.layerParams;
      const P: Record<string, any> = {
        density: clamp(lp.density ?? 1, 0.25, 2),
        threshold: clamp(lp.threshold ?? 0.5, 0.15, 0.95),
        velocity: 1,
        rotation: 0,
        phase: 0,
        microSteps: 0,
        retrograde: false,
        rate: snapRate(lp.rate, ROLE_SHAPES.drums.rate),
        ignoreSpeed: false,
      };
      for (const s of states) applyOps(P, (maps[s] as StateMap).drums.ops, v.drift, spec.cls);
      const c = dd.channelBase('Drums');
      const useFormula = spec.signature && l.formula !== 'groove';
      const formula = useFormula ? l.formula : 'groove';
      const params = useFormula ? { ...l.formulaParams } : HG.cleanParams('groove', { genre: genreIndex, voice: spec.grooveVoice, density: P.density, rotation: P.rotation });
      c.formula = formula;
      c.params = params;
      c.drumLane = spec.lane;
      c.drumFormula = true;
      c.drumVelocity = 'formula';
      c.drumThreshold = useFormula ? P.threshold : 0.5;
      c.rate = P.ignoreSpeed ? P.rate : P.rate / v.speed;
      c.cycle = Math.round(clamp(lp.cycle ?? 16, 4, 64));
      c.phrase = 16;
      c.gateLength = 0.5;
      c.swing = SWING_GENRES.has(l.genre) ? 0.56 : 0.5;
      c.phase = P.phase;
      c.micro = (P.microSteps * c.rate * 60000) / d.bpm;
      c.retrograde = !!P.retrograde;
      c.lanes = c.lanes.map((lane: any, j: number) => ({
        ...lane,
        mute: j !== spec.lane,
        gate: formula,
        params: { ...params },
        accent: Math.round(clamp(spec.accent * P.velocity, 1, 127)),
        ghost: Math.round(clamp(spec.ghost * P.velocity, 1, 127)),
        micro: 0,
      }));
      for (const e of HG.compileChannel(dd.stateWith(c), 0, start, 1)) {
        let kind = spec.cls === 'backbeat' && backbeatAs ? backbeatAs : spec.kind;
        if (kind === 'hatClosed' && (e.formulaValue ?? 0) >= 0.92 && e.step % 2 === 1) kind = 'hatOpen';
        out.push({ track: track as any, beat: e.beat, duration: Math.min(e.duration, 1), pitch: DRUM_NOTE[kind as DrumKind], velocity: e.velocity, drum: kind as DrumKind, norm: DRUM_NORM[kind], step: e.step });
      }
    }
  } else {
    const shape = ROLE_SHAPES[l.role as 'melody'];
    const lp = l.layerParams;
    const steps0 = Math.round(clamp(lp.steps ?? shape.steps, 1, 16));
    const P: Record<string, any> = {
      rate: snapRate(lp.rate, shape.rate),
      ignoreSpeed: false,
      pulses: Math.min(Math.round(clamp(lp.pulses ?? shape.pulses, 1, 16)), steps0),
      steps: steps0,
      gravity: clamp(lp.gravity ?? shape.gravity, 0, 1),
      contour: clamp(lp.contour ?? shape.contour, 0, 0.8),
      cycle: Math.round(clamp(lp.cycle ?? 16, 4, 64)),
      phrase: Math.round(clamp(lp.phrase ?? 16, 4, 32)),
      accent: shape.accent,
      ghost: shape.ghost,
      palette: shape.palette,
      gateLength: shape.gateLength,
      shape: 'arch',
      extension: 1,
      cadence: true,
      phase: 0,
      microSteps: 0,
      retrograde: false,
      rootAnchor: false,
      strum: 10,
    };
    for (const s of states) applyOps(P, (maps[s] as StateMap).pitched, v.drift, l.role);
    const c = dd.channelBase(shape.type);
    c.formula = l.formula;
    c.params = { ...l.formulaParams };
    c.low = l.low;
    c.high = l.high;
    c.mode = 'absolute';
    c.fold = 'reflect';
    c.rate = P.ignoreSpeed ? P.rate : P.rate / v.speed;
    c.phase = P.phase;
    c.micro = (P.microSteps * c.rate * 60000) / d.bpm;
    c.retrograde = !!P.retrograde;
    c.gate = 'euclid';
    c.gateParams = { k: P.pulses, n: P.steps, rot: 0 };
    c.gateLength = P.gateLength;
    c.gravity = P.gravity;
    c.contour = P.contour;
    c.shape = P.shape;
    c.palette = P.palette;
    c.cycle = P.cycle;
    c.phrase = P.phrase;
    c.cadence = !!P.cadence;
    c.leap = 2;
    c.recovery = true;
    c.velocity = 'accent';
    c.velocityParams = {};
    c.accent = clamp(P.accent, 1, 127);
    c.ghost = clamp(Math.min(P.ghost, P.accent), 1, 127);
    if (l.role === 'bass') {
      c.rootAnchor = !!P.rootAnchor;
      c.octavePattern = 0;
    }
    if (l.role === 'chord') {
      c.extension = P.extension;
      c.voicingFormula = false;
      c.followContour = true;
      c.minimal = true;
      c.inversion = 0;
      c.spread = 0;
      c.strum = P.strum;
      c.strumDirection = 1;
    }
    for (const e of HG.compileChannel(dd.stateWith(c), 0, start, 1)) {
      const nextChord = (Math.floor(e.beat / d.chordBeats + 1e-9) + 1) * d.chordBeats;
      const duration = Math.max(0.02, Math.min(e.duration, nextChord - e.beat - 0.02));
      out.push({ track: track as any, beat: e.beat, duration, pitch: e.pitch, velocity: e.velocity, norm: clamp((e.pitch - l.low) / Math.max(1, l.high - l.low), 0, 1), step: e.step });
    }
    if (l.role === 'chord') strumUpward(out);
  }
  out.sort((a, b) => a.beat - b.beat || a.pitch - b.pitch);
  return out;
}

function strumUpward(notes: LayerNote[]): void {
  const byStep = new Map<number, LayerNote[]>();
  for (const n of notes) {
    const g = byStep.get(n.step);
    if (g) g.push(n);
    else byStep.set(n.step, [n]);
  }
  for (const group of byStep.values()) {
    if (group.length < 2) continue;
    const beats = group.map((n) => n.beat).sort((a, b) => a - b);
    const end = Math.min(...group.map((n) => n.beat + n.duration));
    group.sort((a, b) => a.pitch - b.pitch);
    group.forEach((n, i) => {
      n.beat = beats[i];
      n.duration = Math.max(0.02, end - n.beat);
    });
  }
}

export function mapNotes(d: MusicDirector, maps: StateMaps, track: number, v: LayerVariant, bars: number): LayerNote[] {
  const out: LayerNote[] = [];
  for (let b = 0; b < bars; b++) out.push(...mapBar(d, maps, track, v, b));
  return out;
}
export function protoNotes(d: MusicDirector, track: number, v: LayerVariant, bars: number): LayerNote[] {
  return d.notes(track as any, v, 0, bars * 4);
}

/** Master beats per step of a baseline layer at a tape speed. */
export function stepBeats(d: MusicDirector, track: number, speed: number): number {
  const l = (d as any).layers[track];
  return snapRate(l.layerParams.rate, ROLE_SHAPES[l.role as 'melody'].rate) / speed;
}

export const variant = (speed: Speed, o: Partial<LayerVariant> = {}): LayerVariant => ({ speed, dead: false, transport: 1, drift: 0, ...o });

// ───────────────────────────── metrics ─────────────────────────────

export const BARS = 16;
const GRID_TOL = 0.045;

/** Chord strums and drum flams collapsed to one onset per (step, lane-ish). */
export function onsets(notes: LayerNote[], isChord: boolean): number[] {
  if (!isChord) return notes.map((n) => n.beat);
  const seen = new Map<number, number>();
  for (const n of notes) if (!seen.has(n.step) || n.beat < seen.get(n.step)!) seen.set(n.step, n.beat);
  return [...seen.values()].sort((a, b) => a - b);
}
const onGrid = (b: number, g: number) => Math.abs(b / g - Math.round(b / g)) * g <= GRID_TOL;

/** Pitches sounding at time t (a hair after the beat so strums have landed). */
function soundingAt(notes: LayerNote[], t: number): number[] {
  const out: number[] = [];
  const tt = t + 0.085;
  for (const n of notes) if (n.beat <= tt && n.beat + n.duration > tt && n.beat > t - 16) out.push(n.pitch);
  return out;
}

export interface PairStat {
  n: number;
  harsh: number;
  ic: number[];
}
const newPair = (): PairStat => ({ n: 0, harsh: 0, ic: [0, 0, 0, 0, 0, 0, 0] });
/** m2 / m9 always rub; a tritone rubs inside an octave and a half. Wider compounds are counted but not penalised. */
export function isHarsh(dist: number): boolean {
  return dist === 1 || dist === 13 || (dist % 12 === 6 && dist <= 18);
}
function addPairs(st: PairStat, a: number[], b: number[]): void {
  for (const x of a)
    for (const y of b) {
      const dist = Math.abs(x - y);
      const ic = Math.min(dist % 12, 12 - (dist % 12));
      st.n++;
      st.ic[ic]++;
      if (isHarsh(dist)) st.harsh++;
    }
}
const mergePair = (into: PairStat, x: PairStat) => {
  into.n += x.n;
  into.harsh += x.harsh;
  x.ic.forEach((v, i) => (into.ic[i] += v));
};

export interface LayerSpeedStat {
  onsetsPerBar: number;
  maxPerBar: number;
  minPerBar: number;
  longestGapBeats: number;
  grid16: number;
  grid32: number;
  notesPerSec: number;
}

export interface ContourStat {
  notes: number;
  stepPct: number;
  skipPct: number;
  leapPct: number;
  repeatPct: number;
  maxLeap: number;
  range: number;
  distinctPitches: number;
  distinctBars: number;
  barSelfSimilarity: number;
}

/**
 * Melodic motion is counted in SCALE DEGREES (so a pentatonic neighbour is a step):
 * step = 1 degree, skip = 2, leap = 3 or more. maxLeap and range stay in semitones.
 */
export function contour(notes: LayerNote[], bars = 8, scalePcs: readonly number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]): ContourStat {
  const degreeOf = (pitch: number) => {
    let k = 0;
    for (let q = 0; q < pitch; q++) if (scalePcs.includes(q % 12)) k++;
    return k;
  };
  const ns = notes.filter((n) => n.beat < bars * 4);
  const p = ns.map((n) => n.pitch);
  let step = 0, skip = 0, leap = 0, rep = 0, maxLeap = 0;
  for (let i = 1; i < p.length; i++) {
    const dlt = Math.abs(p[i] - p[i - 1]);
    const deg = Math.abs(degreeOf(p[i]) - degreeOf(p[i - 1]));
    maxLeap = Math.max(maxLeap, dlt);
    if (dlt === 0) rep++;
    else if (deg <= 1) step++;
    else if (deg === 2) skip++;
    else leap++;
  }
  const iv = Math.max(1, p.length - 1);
  const barSig: string[] = [];
  // Shape signature of a bar: where the notes fall and whether each moves up, down or repeats.
  // Two bars with the same signature are the same motif, even when transposed by the chord.
  for (let b = 0; b < bars; b++) {
    const bn = ns.filter((n) => Math.floor(n.beat / 4 + 1e-9) === b);
    barSig.push(bn.map((n, i) => `${(n.beat - b * 4).toFixed(2)}${i ? Math.sign(n.pitch - bn[i - 1].pitch) : ''}`).join(','));
  }
  let same = 0, pairs = 0;
  for (let i = 0; i < bars; i++) for (let j = i + 1; j < bars; j++) { pairs++; if (barSig[i] === barSig[j]) same++; }
  return {
    notes: p.length,
    stepPct: (100 * step) / iv,
    skipPct: (100 * skip) / iv,
    leapPct: (100 * leap) / iv,
    repeatPct: (100 * rep) / iv,
    maxLeap,
    range: p.length ? Math.max(...p) - Math.min(...p) : 0,
    distinctPitches: new Set(p).size,
    distinctBars: new Set(barSig).size,
    barSelfSimilarity: (100 * same) / Math.max(1, pairs),
  };
}

export interface LevelReport {
  id: string;
  bpm: number;
  key: string;
  roles: string[];
  formulas: string[];
  /** % of pitched notes in the level scale, over baseline + every state variant. */
  inScalePct: number;
  notesChecked: number;
  /** Over the 81 combos of 0.5/1/2 with all four layers: mean and worst harsh % of cross-layer pairs. */
  harshDownMean81: number;
  harshDownWorst81: number;
  harshBeatMean81: number;
  harshBeatWorst81: number;
  /** Same over the 175 combos that include at least one 4x layer. */
  harshDownMean4x: number;
  harshDownWorst4x: number;
  /** Worst single layer-pair/speed-pair on downbeats: bounds every subset of layers. */
  harshDownWorstPair: number;
  worstPairLabel: string;
  /** % of pitched notes sounding on downbeats / strong beats that are tones of the active seventh chord. */
  chordToneDownPct: number;
  chordToneBeatPct: number;
  icHistogramDownPct: number[];
  layers: Record<string, LayerSpeedStat>[];
  /** Share of onsets (all layers, 0.5/1/2) on the master sixteenth grid; and with 4x on the 32nd grid. */
  grid16Pct: number;
  grid32Pct: number;
  grid32Pct4x: number;
  /** Largest deliberate displacement of an onset from its step (swing), in beats. */
  maxSwingBeats: number;
  /** Fewest / most onsets in any bar of any of the 81 full combos, and of any single layer alone. */
  mixMinPerBar: number;
  mixMaxPerBar: number;
  densityFlags: string[];
  register: { role: string; medianHz: number; lowHz: number; highHz: number }[];
  mudPct: number;
  leadAboveChordPct: number;
  /** Bass at 1x: % of downbeat notes on the chord root, and number of distinct pitches in 8 bars. */
  bassRootDownPct: number;
  bassDistinctPitches: number;
  bassRepeatPct: number;
  /** % of chord-layer strums (0.5/1/2x) whose own voicing contains a semitone cluster. */
  chordClusterPct: number;
  /** Mean over layers and speeds (0.5/1/2) of the share of onsets off the 16th / 32nd grid; and at 4x off the 32nd grid. Independent of how many notes a layer plays. */
  offGrid16LayerMean: number;
  offGrid32LayerMean: number;
  offGrid32LayerMean4x: number;
  melody: Record<string, ContourStat>;
  states: {
    deadDensityRatio: number;
    deadChordTonePct: number;
    deadInScalePct: number;
    driftChangedPct: number;
    driftInScalePct: number;
    driftMaxLateBeats: number;
    reverseChangedPct: number;
    reverseInScalePct: number;
    stoppedOnsetsPerBar: number;
    stoppedInScalePct: number;
  };
  score: number;
  penalties: Record<string, number>;
}

/** Density bounds (onsets per master bar), documented in docs/MUSIC.md. */
export const BOUNDS = {
  pitchedMin: 0.5,
  pitchedMax: 16,
  pitchedMax4x: 24,
  drumsMin: 2,
  drumsMax: 32,
  drumsMax4x: 48,
  maxGapBeats: 8,
  notesPerSecMax: 16,
};

export function analyse(piece: { id: string; bpm: number; music: MusicDef; stateMaps: StateMaps }): LevelReport {
  const d = new MusicDirector({ bpm: piece.bpm, music: piece.music as any });
  const maps = piece.stateMaps;
  const roles = piece.music.tracks.map((t) => t.role);
  const scalePcs = new Set(d.scalePcs);
  const beats = BARS * 4;
  const R = (t: number, v: LayerVariant) => mapNotes(d, maps, t, v, BARS);

  // Baseline streams.
  const base: LayerNote[][][] = roles.map((_, t) => SPEEDS4.map((s) => R(t, variant(s))));
  const pitched = roles.map((r) => r !== 'drums');

  // ── in scale: baseline and all states ──
  let inScale = 0, checked = 0;
  const countScale = (ns: LayerNote[]) => {
    let ok = 0;
    for (const n of ns) if (scalePcs.has(n.pitch % 12)) ok++;
    inScale += ok;
    checked += ns.length;
    return ns.length ? (100 * ok) / ns.length : 100;
  };

  // ── per layer / speed rhythm ──
  const layers: Record<string, LayerSpeedStat>[] = [];
  const densityFlags: string[] = [];
  let g16 = 0, g16n = 0, g32 = 0, g32n = 0, g32lo = 0, maxSwing = 0;
  const perBar: number[][][] = [];
  roles.forEach((role, t) => {
    const rec: Record<string, LayerSpeedStat> = {};
    perBar.push([]);
    SPEEDS4.forEach((s, si) => {
      const ns = base[t][si];
      if (pitched[t]) countScale(ns);
      const on = onsets(ns, role === 'chord');
      const bars = new Array(BARS).fill(0);
      for (const b of on) bars[Math.min(BARS - 1, Math.floor(b / 4 + 1e-9))]++;
      perBar[t].push(bars);
      let gap = on.length ? on[0] : beats;
      for (let i = 1; i < on.length; i++) gap = Math.max(gap, on[i] - on[i - 1]);
      if (on.length) gap = Math.max(gap, beats - on[on.length - 1]);
      // Grid alignment is judged on the step each onset belongs to (swing and strum are deliberate
      // displacements of a step, reported separately as maxSwingBeats).
      const sb = stepBeats(d, t, s);
      const seenStep = new Set<number>();
      const nominal: number[] = [];
      for (const n of ns) {
        if (role === 'chord') { if (seenStep.has(n.step)) continue; seenStep.add(n.step); }
        nominal.push(n.step * sb);
        if (role !== 'chord') maxSwing = Math.max(maxSwing, Math.abs(n.beat - n.step * sb));
      }
      const on16 = nominal.filter((b) => onGrid(b, 0.25)).length;
      const on32 = nominal.filter((b) => onGrid(b, 0.125)).length;
      if (s !== 4) { g16 += on16; g32lo += on32; g16n += on.length; } else { g32 += on32; g32n += on.length; }
      const st: LayerSpeedStat = {
        onsetsPerBar: on.length / BARS,
        maxPerBar: Math.max(...bars),
        minPerBar: Math.min(...bars),
        longestGapBeats: gap,
        grid16: on.length ? (100 * on16) / on.length : 100,
        grid32: on.length ? (100 * on32) / on.length : 100,
        notesPerSec: (Math.max(...bars) / 4) * (piece.bpm / 60),
      };
      rec[String(s)] = st;
      const lo = role === 'drums' ? BOUNDS.drumsMin : BOUNDS.pitchedMin;
      const hi = role === 'drums' ? (s === 4 ? BOUNDS.drumsMax4x : BOUNDS.drumsMax) : s === 4 ? BOUNDS.pitchedMax4x : BOUNDS.pitchedMax;
      if (st.onsetsPerBar < lo) densityFlags.push(`${role}@${s}x thin ${st.onsetsPerBar.toFixed(2)}/bar`);
      if (st.maxPerBar > hi) densityFlags.push(`${role}@${s}x dense ${st.maxPerBar}/bar`);
      if (st.longestGapBeats > BOUNDS.maxGapBeats + 1e-6) densityFlags.push(`${role}@${s}x gap ${st.longestGapBeats.toFixed(1)} beats`);
    });
    layers.push(rec);
  });

  // ── vertical consonance ──
  const sound: number[][][][] = roles.map((_, t) => SPEEDS4.map((_, si) => (pitched[t] ? Array.from({ length: beats }, (_, b) => soundingAt(base[t][si], b)) : [])));
  const chordPcs = Array.from({ length: beats }, (_, b) => new Set(d.chordAt(b, 1).pcs));
  const pairDown: PairStat[][][][] = [], pairBeat: PairStat[][][][] = [];
  let worstPair = 0, worstPairLabel = '-';
  for (let i = 0; i < 4; i++) {
    pairDown.push([]); pairBeat.push([]);
    for (let j = 0; j < 4; j++) {
      pairDown[i].push([]); pairBeat[i].push([]);
      for (let si = 0; si < 4; si++) {
        pairDown[i][j].push([]); pairBeat[i][j].push([]);
        for (let sj = 0; sj < 4; sj++) {
          const pd = newPair(), pb = newPair();
          if (i < j && pitched[i] && pitched[j]) {
            for (let b = 0; b < beats; b++) {
              addPairs(pb, sound[i][si][b], sound[j][sj][b]);
              if (b % 4 === 0) addPairs(pd, sound[i][si][b], sound[j][sj][b]);
            }
            if (si < 3 && sj < 3 && pd.n && (100 * pd.harsh) / pd.n > worstPair) {
              worstPair = (100 * pd.harsh) / pd.n;
              worstPairLabel = `${roles[i]}@${SPEEDS4[si]}x + ${roles[j]}@${SPEEDS4[sj]}x`;
            }
          }
          pairDown[i][j][si].push(pd); pairBeat[i][j][si].push(pb);
        }
      }
    }
  }
  const agg = { d81: [] as number[], b81: [] as number[], d4: [] as number[] };
  const icTotal = newPair();
  let mixMin = Infinity, mixMax = 0;
  for (let c = 0; c < 256; c++) {
    const sp = [c & 3, (c >> 2) & 3, (c >> 4) & 3, (c >> 6) & 3];
    const has4 = sp.includes(3);
    const pd = newPair(), pb = newPair();
    for (let i = 0; i < 4; i++) for (let j = i + 1; j < 4; j++) { mergePair(pd, pairDown[i][j][sp[i]][sp[j]]); mergePair(pb, pairBeat[i][j][sp[i]][sp[j]]); }
    const hd = pd.n ? (100 * pd.harsh) / pd.n : 0, hb = pb.n ? (100 * pb.harsh) / pb.n : 0;
    if (has4) agg.d4.push(hd);
    else {
      agg.d81.push(hd); agg.b81.push(hb); mergePair(icTotal, pd);
      for (let b = 0; b < BARS; b++) {
        const tot = perBar[0][sp[0]][b] + perBar[1][sp[1]][b] + perBar[2][sp[2]][b] + perBar[3][sp[3]][b];
        mixMin = Math.min(mixMin, tot); mixMax = Math.max(mixMax, tot);
      }
    }
  }
  const mean = (a: number[]) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
  let ctD = 0, ctDn = 0, ctB = 0, ctBn = 0;
  for (let t = 0; t < 4; t++) if (pitched[t]) for (let si = 0; si < 3; si++) for (let b = 0; b < beats; b++) for (const p of sound[t][si][b]) {
    const ok = chordPcs[b].has(p % 12) ? 1 : 0;
    ctB += ok; ctBn++;
    if (b % 4 === 0) { ctD += ok; ctDn++; }
  }

  // ── register ──
  const register: LevelReport['register'] = [];
  roles.forEach((role, t) => {
    if (!pitched[t]) return;
    const ps = base[t][1].map((n) => n.pitch).sort((a, b) => a - b);
    const q = (f: number) => ps[Math.min(ps.length - 1, Math.floor(f * ps.length))] ?? 0;
    register.push({ role, medianHz: midiHz(q(0.5)), lowHz: midiHz(q(0.05)), highHz: midiHz(q(0.95)) });
  });
  // Mud: sixteenth-sampled moments where two different pitched layers both sound below 150 Hz.
  // Lead above chords: moments where melody and chord both sound and the melody is at or above the chord's top note.
  let mud = 0, mudN = 0, lead = 0, leadN = 0;
  const lowSound = (t: number, si: number) => Array.from({ length: beats * 4 }, (_, k) => soundingAt(base[t][si], k / 4 - 0.06));
  const cache = new Map<string, number[][]>();
  const snd = (t: number, si: number) => { const k = `${t}|${si}`; if (!cache.has(k)) cache.set(k, lowSound(t, si)); return cache.get(k)!; };
  for (let i = 0; i < 4; i++) for (let j = i + 1; j < 4; j++) {
    if (!pitched[i] || !pitched[j]) continue;
    for (let si = 0; si < 3; si++) for (let sj = 0; sj < 3; sj++) {
      const a = snd(i, si), b = snd(j, sj);
      for (let k = 0; k < a.length; k++) {
        if (!a[k].length || !b[k].length) continue;
        mudN++;
        if (Math.min(...a[k]) <= 50 && Math.min(...b[k]) <= 50) mud++;
        const mi = roles[i] === 'melody' ? a[k] : roles[j] === 'melody' ? b[k] : null;
        const ci = roles[i] === 'chord' ? a[k] : roles[j] === 'chord' ? b[k] : null;
        if (mi && ci) { leadN++; if (Math.max(...mi) >= Math.max(...ci)) lead++; }
      }
    }
  }

  // ── bass grounding ──
  let bassRoot = 0, bassDown = 0, bassRep = 0, bassIv = 0, bassPrev = -1;
  const bassPitches = new Set<number>();
  const bt = roles.indexOf('bass');
  if (bt >= 0) for (const n of base[bt][1]) {
    if (n.beat < 32) bassPitches.add(n.pitch);
    if (bassPrev >= 0) { bassIv++; if (bassPrev === n.pitch) bassRep++; }
    bassPrev = n.pitch;
    if (Math.abs(n.beat / 4 - Math.round(n.beat / 4)) < 0.03) { bassDown++; if (n.pitch % 12 === d.chordAt(n.beat, 0).root) bassRoot++; }
  }

  // ── chord voicing: semitone clusters inside the chord layer itself ──
  let strums = 0, clusters = 0;
  roles.forEach((role, t) => {
    if (role !== 'chord') return;
    for (let si = 0; si < 3; si++) {
      const byStep = new Map<number, number[]>();
      for (const n of base[t][si]) byStep.set(n.step, [...(byStep.get(n.step) ?? []), n.pitch]);
      for (const ps of byStep.values()) {
        strums++;
        if (ps.some((a) => ps.some((b) => Math.abs(a - b) === 1))) clusters++;
      }
    }
  });

  // ── melody contour ──
  const melody: Record<string, ContourStat> = {};
  const mt = roles.indexOf('melody');
  if (mt >= 0) SPEEDS4.forEach((s, si) => (melody[String(s)] = contour(base[mt][si], 8, d.scalePcs)));

  // ── states ──
  let deadRatio = 0, deadRatioN = 0, deadCT = 0, deadCTn = 0, deadScale: number[] = [];
  let driftChanged = 0, driftN = 0, driftScale: number[] = [], driftLate = 0;
  let revChanged = 0, revN = 0, revScale: number[] = [];
  let stopOn = 0, stopScale: number[] = [];
  roles.forEach((role, t) => {
    SPEEDS4.forEach((s, si) => {
      const alive = base[t][si];
      const dead = R(t, variant(s, { dead: true }));
      const a = onsets(alive, role === 'chord').length, b = onsets(dead, role === 'chord').length;
      if (a) { deadRatio += b / a; deadRatioN++; }
      if (pitched[t]) {
        deadScale.push(countScale(dead));
        for (const n of dead) { deadCTn++; if (d.chordAt(n.beat, 0).pcs.includes(n.pitch % 12)) deadCT++; }
      }
      if (s === 4) return;
      for (const dr of [0.25, 0.5, 0.75, 1]) {
        const dn = R(t, variant(s, { drift: dr }));
        if (pitched[t]) driftScale.push(countScale(dn));
        if (dr === 1) {
          const byStep = new Map<number, string>();
          for (const n of alive) byStep.set(n.step, (byStep.get(n.step) ?? '') + n.pitch + ',');
          const dStep = new Map<number, string>();
          for (const n of dn) dStep.set(n.step, (dStep.get(n.step) ?? '') + n.pitch + ',');
          const stepsAll = new Set([...byStep.keys(), ...dStep.keys()]);
          for (const st of stepsAll) { driftN++; if (byStep.get(st) !== dStep.get(st)) driftChanged++; }
          const first = (ns: LayerNote[]) => {
            const m = new Map<number, number>();
            for (const n of ns) if (!m.has(n.step) || n.beat < m.get(n.step)!) m.set(n.step, n.beat);
            return m;
          };
          const fa0 = first(alive);
          for (const [st, b0] of first(dn)) if (fa0.has(st)) driftLate = Math.max(driftLate, b0 - fa0.get(st)!);
        }
      }
      const rv = R(t, variant(s, { transport: -1 }));
      if (pitched[t]) revScale.push(countScale(rv));
      const sig = (ns: LayerNote[]) => { const m = new Map<number, string>(); for (const n of ns) m.set(n.step, (m.get(n.step) ?? '') + (n.drum ?? n.pitch) + ','); return m; };
      const fa = sig(alive), fr = sig(rv);
      for (const st of new Set([...fa.keys(), ...fr.keys()])) { revN++; if (fa.get(st) !== fr.get(st)) revChanged++; }
    });
    const stop = R(t, variant(1, { transport: 0 }));
    if (pitched[t]) stopScale.push(countScale(stop));
    stopOn += onsets(stop, role === 'chord').length / BARS;
  });
  // A dead + stopped and a drifting + reversing layer must stay in key too.
  roles.forEach((_, t) => {
    if (!pitched[t]) return;
    countScale(R(t, variant(1, { dead: true, transport: 0 })));
    countScale(R(t, variant(2, { dead: true, transport: -1 })));
    countScale(R(t, variant(0.5, { drift: 1, transport: -1 })));
  });

  const r: LevelReport = {
    id: piece.id,
    bpm: piece.bpm,
    key: `${NOTE_NAMES[d.root]} ${d.scale}`,
    roles,
    formulas: piece.music.tracks.map((t) => t.formula),
    inScalePct: checked ? (100 * inScale) / checked : 100,
    notesChecked: checked,
    harshDownMean81: mean(agg.d81),
    harshDownWorst81: Math.max(0, ...agg.d81),
    harshBeatMean81: mean(agg.b81),
    harshBeatWorst81: Math.max(0, ...agg.b81),
    harshDownMean4x: mean(agg.d4),
    harshDownWorst4x: Math.max(0, ...agg.d4),
    harshDownWorstPair: worstPair,
    worstPairLabel,
    chordToneDownPct: ctDn ? (100 * ctD) / ctDn : 100,
    chordToneBeatPct: ctBn ? (100 * ctB) / ctBn : 100,
    icHistogramDownPct: icTotal.ic.map((v) => (100 * v) / Math.max(1, icTotal.n)),
    layers,
    grid16Pct: g16n ? (100 * g16) / g16n : 100,
    grid32Pct: g16n ? (100 * g32lo) / g16n : 100,
    grid32Pct4x: g32n ? (100 * g32) / g32n : 100,
    maxSwingBeats: maxSwing,
    mixMinPerBar: mixMin,
    mixMaxPerBar: mixMax,
    densityFlags,
    register,
    mudPct: mudN ? (100 * mud) / mudN : 0,
    leadAboveChordPct: leadN ? (100 * lead) / leadN : 100,
    bassRootDownPct: bassDown ? (100 * bassRoot) / bassDown : 100,
    bassDistinctPitches: bassPitches.size,
    bassRepeatPct: bassIv ? (100 * bassRep) / bassIv : 0,
    chordClusterPct: strums ? (100 * clusters) / strums : 0,
    offGrid16LayerMean: mean(layers.flatMap((l) => ['0.5', '1', '2'].map((k) => 100 - l[k].grid16))),
    offGrid32LayerMean: mean(layers.flatMap((l) => ['0.5', '1', '2'].map((k) => 100 - l[k].grid32))),
    offGrid32LayerMean4x: mean(layers.map((l) => 100 - l['4'].grid32)),
    melody,
    states: {
      deadDensityRatio: deadRatioN ? deadRatio / deadRatioN : 1,
      deadChordTonePct: deadCTn ? (100 * deadCT) / deadCTn : 100,
      deadInScalePct: Math.min(100, ...deadScale),
      driftChangedPct: driftN ? (100 * driftChanged) / driftN : 0,
      driftInScalePct: Math.min(100, ...driftScale),
      driftMaxLateBeats: driftLate,
      reverseChangedPct: revN ? (100 * revChanged) / revN : 0,
      reverseInScalePct: Math.min(100, ...revScale),
      stoppedOnsetsPerBar: stopOn,
      stoppedInScalePct: Math.min(100, ...stopScale),
    },
    score: 0,
    penalties: {},
  };
  scoreReport(r);
  return r;
}

/**
 * One number to steer iteration with (100 = nothing to complain about). The weights are the
 * composer's judgement, written down so the before/after comparison is reproducible.
 */
export function scoreReport(r: LevelReport): void {
  const p: Record<string, number> = {};
  p.outOfScale = (100 - r.inScalePct) * 10;
  p.harshDownbeats = r.harshDownMean81 * 2 + Math.max(0, r.harshDownWorst81 - 8) * 1;
  p.harshWorstPair = Math.max(0, r.harshDownWorstPair - 15) * 0.5;
  p.harshBeats = Math.max(0, r.harshBeatMean81 - 4) * 1;
  p.nonChordDownbeats = Math.max(0, 90 - r.chordToneDownPct) * 0.5;
  p.offGrid = r.offGrid32LayerMean * 0.5 + r.offGrid16LayerMean * 0.05 + r.offGrid32LayerMean4x * 0.05;
  p.density = r.densityFlags.length * 3;
  p.mud = r.mudPct * 1;
  p.leadBelowChords = Math.max(0, 85 - r.leadAboveChordPct) * 0.3;
  const m = r.melody['1'];
  if (m) {
    const conj = m.stepPct + m.repeatPct;
    p.melodyLeapy = Math.max(0, m.leapPct - 25) * 0.4 + Math.max(0, m.maxLeap - 12) * 1;
    p.melodyStatic = Math.max(0, m.repeatPct - 35) * 0.3 + Math.max(0, 45 - conj) * 0.2;
    p.melodyRange = (m.range < 7 ? (7 - m.range) * 1.5 : 0) + (m.range > 19 ? (m.range - 19) * 1 : 0);
    p.melodyForm = (m.distinctBars < 2 ? 6 : 0) + (m.distinctBars > 7 ? 3 : 0) + (m.distinctPitches < 4 ? 4 : 0);
  }
  if (r.roles.includes('bass')) p.bassUngrounded = Math.max(0, 60 - r.bassRootDownPct) * 0.2 + (r.bassDistinctPitches < 3 ? 3 : 0) + Math.max(0, r.bassRepeatPct - 50) * 0.15;
  for (const sp of ['0.5', '2']) {
    const m2 = r.melody[sp];
    if (m2) p['melodyLeapy@' + sp] = Math.max(0, m2.leapPct - 30) * 0.15 + Math.max(0, m2.maxLeap - 12) * 0.3;
  }
  p.chordClusters = r.chordClusterPct * 0.25;
  p.deadNotThinner = Math.max(0, r.states.deadDensityRatio - 0.8) * 40;
  p.driftInert = Math.max(0, 15 - r.states.driftChangedPct) * 0.4;
  let total = 0;
  for (const k of Object.keys(p)) { p[k] = Math.round(p[k] * 100) / 100; total += p[k]; }
  r.penalties = p;
  r.score = Math.round((100 - total) * 10) / 10;
}
