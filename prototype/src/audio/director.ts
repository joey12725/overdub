/**
 * MusicDirector: turns a level's music definition into Harmonograph channels and compiles the
 * notes each cassette layer plays for a given layer state (MUSIC-01..04, MUSIC-08, MUSIC-09).
 *
 * Pure and deterministic: no Web Audio, no clocks. Same level + same layer variant + same bar
 * always gives the same notes.
 *
 * Time model. The engine state runs on the MASTER beat clock (tempo = level.bpm) and its chord
 * progression is keyed to the master beat, so every layer maps pitch under the chord active at the
 * current master beat. A cassette recorded at speed `s` occupies `1/s` of the master time its local
 * timeline does (TIME-03), so its layer's step length on the master clock is `localRate / s`: steps
 * of 0.5x / 1x / 2x / 4x layers nest by powers of two and stay on one grid (MUSIC-03). The step
 * index `n = masterBeat / (localRate / s)` is therefore the LOCAL step, so contour, gate and accent
 * patterns are the same music, just faster or slower. Retrograde / hold only change how the
 * contour is read at the current step; they never rewind the chord clock.
 */
import type { LevelDef, TapeIndex, TapeSpeed, TrackMusicDef } from '../core/types';
import { BEATS_PER_BAR } from '../core/types';
import { HG, type HGChannel, type HGChannelType, type HGState } from './hg';
import { type MusicRole, ROLE_DEFAULTS, resolveFormula, splitParams } from './formulas';

export type DrumKind = 'kick' | 'snare' | 'clap' | 'hatClosed' | 'hatOpen' | 'tom' | 'rim' | 'perc';

/** Everything about a layer's situation that changes the generated notes. */
export interface LayerVariant {
  speed: TapeSpeed;
  /** The self is a ghost (dead this run): the pattern thins and falls onto chord tones. */
  dead: boolean;
  /** 1 forward, -1 reverse pass (retrograde contour), 0 stopped (hold figure). */
  transport: 1 | -1 | 0;
  /** Desync drift 0..1 in quarter steps; 0 is the exact baseline. */
  drift: number;
}

export interface LayerNote {
  track: TapeIndex;
  /** Master beat of the onset. */
  beat: number;
  /** Master beats. Never crosses a chord change, so a held note cannot clash with the next chord. */
  duration: number;
  /** MIDI pitch (drums: a GM-style note number, see `drum`). */
  pitch: number;
  /** 1..127. */
  velocity: number;
  drum?: DrumKind;
  /** Pitch normalised into the layer range 0..1 (for MusicPulse.pitches). */
  norm: number;
  step: number;
}

export interface ChordInfo {
  /** Index into the level progression. */
  index: number;
  degree: number;
  root: number;
  pcs: number[];
}

export interface LayerInfo {
  role: MusicRole;
  formula: string;
  low: number;
  high: number;
}

const BASELINE: Omit<LayerVariant, 'speed'> = { dead: false, transport: 1, drift: 0 };

export function variantKey(v: LayerVariant): string {
  return `${v.speed}|${v.dead ? 1 : 0}|${v.transport}|${v.drift}`;
}

export function baselineVariant(speed: TapeSpeed): LayerVariant {
  return { speed, ...BASELINE };
}

interface RoleShape {
  type: HGChannelType;
  rate: number;
  pulses: number;
  steps: number;
  gravity: number;
  contour: number;
  palette: number;
  /** Lowest allowed bottom of the range; the range starts on the first scale root at or above it. */
  floor: number;
  span: number;
  gateLength: number;
  accent: number;
  ghost: number;
}

/**
 * Per-role starting points (layer-param defaults come from ROLE_DEFAULTS, which is what content
 * authors are shown), chosen so any formula lands somewhere consonant and uncluttered.
 */
export const ROLE_SHAPES: Record<MusicRole, RoleShape> = {
  melody: { type: 'Melody', ...ROLE_DEFAULTS.melody, palette: 2, floor: 55, span: 19, gateLength: 0.8, accent: 96, ghost: 50 },
  // Bass picks only chord tones (palette 0) so it can never rub against the harmony.
  bass: { type: 'Bass', ...ROLE_DEFAULTS.bass, palette: 0, floor: 31, span: 17, gateLength: 0.85, accent: 104, ghost: 64 },
  chord: { type: 'Chord', ...ROLE_DEFAULTS.chord, palette: 2, floor: 50, span: 19, gateLength: 0.92, accent: 82, ghost: 58 },
  drums: { type: 'Drums', ...ROLE_DEFAULTS.drums, palette: 2, floor: 36, span: 12, gateLength: 0.5, accent: 110, ghost: 40 },
};

const ENGINE_BASE_INDEX: Record<HGChannelType, number> = { Melody: 0, Bass: 2, Chord: 3, Drums: 4 };

/** Genres whose backbeat reads better as a clap than a snare. */
const CLAP_GENRES = new Set(['House', 'Trap', 'Jersey club', 'Reggaeton', 'Dancehall']);
/** Genres whose perc lane is a tom rather than a pitched perc blip. */
const TOM_GENRES = new Set(['Rock', 'Funk / disco', 'Boom bap', 'Lo-fi 80', 'Jungle']);
const SWING_GENRES = new Set(['Lo-fi 80', 'Boom bap', 'Funk / disco']);
const DEFAULT_GENRE = 'Lo-fi 80';

export function resolveGenre(name: string | undefined): string {
  const names = Object.keys(HG.GENRES);
  if (!name) return DEFAULT_GENRE;
  const norm = (x: string) => x.toLowerCase().replace(/[^a-z0-9]/g, '');
  const want = norm(name);
  return names.find((g) => norm(g) === want) ?? names.find((g) => norm(g).startsWith(want) || want.startsWith(norm(g))) ?? DEFAULT_GENRE;
}

export function resolveScale(name: string): string {
  if (HG.SCALES[name]) return name;
  const lower = name.toLowerCase();
  return Object.keys(HG.SCALES).find((k) => k.toLowerCase() === lower) ?? 'Minor';
}

/** Snap a step length to a power of two in [0.25, 4] so speed scaling stays on the master grid. */
function snapRate(rate: number | undefined, fallback: number): number {
  if (rate === undefined || !Number.isFinite(rate) || rate <= 0) return fallback;
  return 2 ** Math.round(Math.log2(Math.min(4, Math.max(0.25, rate))));
}

const clamp = (x: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, x));
const MS_PER_MINUTE = 60000;

interface DrumLaneSpec {
  lane: number;
  kind: DrumKind;
  /** Whether this lane carries the cassette's own formula (the "signature" lane). */
  signature: boolean;
  grooveVoice: number;
  accent: number;
  ghost: number;
}

interface CompiledLayer {
  role: MusicRole;
  formula: string;
  formulaParams: Record<string, number>;
  layerParams: Record<string, number>;
  genre: string;
  low: number;
  high: number;
}

export class MusicDirector {
  readonly bpm: number;
  readonly root: number;
  readonly scale: string;
  /** Pitch classes of the level scale. */
  readonly scalePcs: readonly number[];
  readonly progression: readonly number[];
  /** Master beats per chord. */
  readonly chordBeats: number;
  private readonly base: HGState;
  private readonly layers: CompiledLayer[];
  private readonly cache = new Map<string, LayerNote[]>();

  constructor(level: Pick<LevelDef, 'bpm' | 'music'>) {
    const m = level.music;
    this.bpm = clamp(level.bpm, 20, 999);
    this.root = ((Math.round(m.root) % 12) + 12) % 12;
    this.scale = resolveScale(m.scale);
    const sc = HG.SCALES[this.scale];
    this.scalePcs = sc.map((p) => (p + this.root) % 12);
    this.progression = m.progression.length ? m.progression.map((d) => Math.round(d)) : [0];
    this.chordBeats = Math.max(1, Math.round(m.chordBars ?? 1)) * BEATS_PER_BAR;

    const s = HG.initialState();
    s.sections = [];
    s.channels = [];
    s.tempo = this.bpm;
    s.root = this.root;
    s.scale = this.scale;
    s.chordSource = 'progression';
    s.progression = [...this.progression];
    s.chordRate = this.chordBeats;
    s.extension = 0;
    s.inversion = 0;
    s.spread = 0;
    s.chordOctave = 0;
    s.quality = 'diatonic';
    s.borrowed = '';
    s.shift = false;
    // Chromatic escape stays off: every voice is snapped into the level scale (MUSIC-04).
    s.escape = false;
    s.queuedSection = null;
    this.base = s;

    this.layers = m.tracks.map((t) => this.prepareLayer(t));
  }

  layer(track: TapeIndex): LayerInfo {
    const l = this.layers[track];
    return { role: l.role, formula: l.formula, low: l.low, high: l.high };
  }

  /** Chord in force at a master beat; `extension` 0 = triad, 1 = seventh (what the chord layer voices). */
  chordAt(beat: number, extension = 0): ChordInfo {
    const c = HG.chordAt(extension ? { ...this.base, extension } : this.base, Math.max(0, beat));
    const index = ((Math.floor(Math.max(0, beat) / this.chordBeats) % this.progression.length) + this.progression.length) % this.progression.length;
    return { index, degree: c.degree, root: c.root, pcs: c.pcs };
  }

  /** MIDI note of scale degree `degree` (0-based, may exceed the scale length) in MIDI octave `octave` (C4 = 60). */
  scaleMidi(degree: number, octave: number): number {
    return 12 * (octave + 1) + HG.degreeMidi(degree, { root: this.root, scale: this.scale });
  }

  /** The MIDI note with pitch class `pc` closest to `around`. */
  static nearestWithPc(pc: number, around: number): number {
    const base = around - (((around - pc) % 12) + 12) % 12;
    return around - base <= 6 ? base : base + 12;
  }

  /**
   * Notes of one layer in one master bar for a given variant, sorted by beat. Each note belongs to
   * exactly one bar (the bar containing its onset), so concatenating bars never duplicates notes.
   */
  barNotes(track: TapeIndex, variant: LayerVariant, bar: number): LayerNote[] {
    if (bar < 0) return [];
    const key = `${track}|${variantKey(variant)}|${bar}`;
    const hit = this.cache.get(key);
    if (hit) return hit;
    const notes = this.compileBar(track, variant, bar);
    if (this.cache.size > 768) this.cache.clear();
    this.cache.set(key, notes);
    return notes;
  }

  /** Notes of one layer with onsets in [from, to). */
  notes(track: TapeIndex, variant: LayerVariant, from: number, to: number): LayerNote[] {
    const out: LayerNote[] = [];
    if (to <= from) return out;
    for (let bar = Math.max(0, Math.floor(from / BEATS_PER_BAR)); bar * BEATS_PER_BAR < to; bar++) {
      for (const n of this.barNotes(track, variant, bar)) if (n.beat >= from - 1e-9 && n.beat < to - 1e-9) out.push(n);
    }
    return out;
  }

  // ───────────────────────────── construction ─────────────────────────────

  private prepareLayer(def: TrackMusicDef): CompiledLayer {
    const role: MusicRole = (['bass', 'drums', 'melody', 'chord'] as const).includes(def.role) ? def.role : 'melody';
    const formula = resolveFormula(role, def.formula);
    const { formula: formulaParams, layer: layerParams } = splitParams(formula, def.params);
    const shape = ROLE_SHAPES[role];
    const register = Math.round(clamp(layerParams.register ?? 0, -1, 1));
    // Start the range on a scale root so the contour's midpoint sits on a stable degree.
    const low = shape.floor + ((((this.root - shape.floor) % 12) + 12) % 12) + 12 * register;
    return { role, formula, formulaParams, layerParams, genre: resolveGenre(def.genre), low, high: low + shape.span };
  }

  private channelBase(type: HGChannelType): HGChannel {
    const c = HG.channel(ENGINE_BASE_INDEX[type]);
    c.id = 0;
    c.active = true;
    c.solo = false;
    c.sumEnabled = false;
    c.sumGate = false;
    c.sumVelocity = false;
    c.variation = 0;
    c.invert = false;
    c.octave = 0;
    c.speed = 1;
    c.phase = 0;
    c.micro = 0;
    c.swing = 0.5;
    c.repeated = 'retrigger';
    return c;
  }

  /** Builds the single engine channel for a pitched layer under `v`. */
  private pitchedChannel(l: CompiledLayer, v: LayerVariant): HGChannel {
    const shape = ROLE_SHAPES[l.role];
    const lp = l.layerParams;
    const c = this.channelBase(shape.type);
    const localRate = snapRate(lp.rate, shape.rate);
    let pulses = Math.round(clamp(lp.pulses ?? shape.pulses, 1, 16));
    let steps = Math.round(clamp(lp.steps ?? shape.steps, 1, 16));
    pulses = Math.min(pulses, steps);
    let gravity = clamp(lp.gravity ?? shape.gravity, 0, 1);
    let contour = clamp(lp.contour ?? shape.contour, 0, 0.8);
    let cycle = Math.round(clamp(lp.cycle ?? 16, 4, 64));
    let phrase = Math.round(clamp(lp.phrase ?? 16, 4, 32));
    let accent = shape.accent;
    let ghost = shape.ghost;
    let palette = shape.palette;
    let rate = localRate / v.speed;
    let gateLength = shape.gateLength;
    let shapeName: HGChannel['shape'] = 'arch';
    let extension = 1;
    let cadence = true;
    const leap = 2;

    c.formula = l.formula;
    c.params = { ...l.formulaParams };
    c.low = l.low;
    c.high = l.high;
    c.mode = 'absolute';
    c.fold = 'reflect';

    if (v.dead) {
      // MUSIC-08/09, death: fewer gated steps, softer, chord tones only, a short repetitive cycle.
      if (steps === 1) steps = 2;
      pulses = Math.max(1, Math.round(pulses / 2));
      gravity = 1;
      palette = 0;
      contour = Math.max(contour, 0.35);
      cycle = Math.max(4, Math.round(cycle / 4));
      phrase = 8;
      accent = Math.round(accent * 0.65);
      ghost = Math.round(ghost * 0.65);
      extension = 0;
    }

    if (v.drift > 0) {
      // MUSIC-08/09, desync: the contour slips ahead of the rhythm and smooths toward the arch.
      // The rhythmic grid itself (gate on step n) is untouched so the layer stays in time.
      c.phase = Math.round(v.drift * 4);
      contour = Math.min(0.8, contour + 0.45 * v.drift);
      accent = Math.round(accent * (1 - 0.15 * v.drift));
      // A slight lateness (≤ 18% of a step) gives the loose, slipping feel without flamming chords.
      c.micro = ((v.drift * 0.18 * rate) * MS_PER_MINUTE) / this.bpm;
    }

    if (v.transport === -1) c.retrograde = true;

    if (v.transport === 0) {
      // Stopped tape: a sustained hold figure on a chord tone, re-voiced as the chords move.
      rate = l.role === 'melody' ? 2 : 4;
      pulses = 1;
      steps = 1;
      gateLength = 1;
      contour = 1;
      shapeName = 'flat';
      palette = 0;
      gravity = 1;
      cadence = false;
      accent = Math.round(accent * 0.7);
      ghost = Math.round(ghost * 0.7);
      c.retrograde = false;
      c.phase = 0;
      c.micro = 0;
      if (l.role === 'bass') c.rootAnchor = true;
    }

    c.rate = rate;
    c.gate = 'euclid';
    c.gateParams = { k: pulses, n: steps, rot: 0 };
    c.gateLength = gateLength;
    c.gravity = gravity;
    c.contour = contour;
    c.shape = shapeName;
    c.palette = palette;
    c.cycle = cycle;
    c.phrase = phrase;
    c.cadence = cadence;
    c.leap = leap;
    c.recovery = true;
    c.velocity = 'accent';
    c.velocityParams = {};
    c.accent = clamp(accent, 1, 127);
    c.ghost = clamp(Math.min(ghost, accent), 1, 127);
    if (l.role === 'bass') {
      if (v.transport !== 0) c.rootAnchor = false;
      c.octavePattern = 0;
    }
    if (l.role === 'chord') {
      c.extension = extension;
      c.voicingFormula = false;
      c.followContour = true;
      c.minimal = true;
      c.inversion = 0;
      c.spread = 0;
      c.strum = v.transport === 0 ? 0 : 10;
      c.strumDirection = 1;
    }
    return c;
  }

  private drumLanes(l: CompiledLayer, v: LayerVariant): DrumLaneSpec[] {
    const clap = CLAP_GENRES.has(l.genre);
    const lanes: DrumLaneSpec[] = [
      { lane: 0, kind: 'kick', signature: false, grooveVoice: 0, accent: 112, ghost: 76 },
      { lane: clap ? 4 : 1, kind: v.dead ? 'rim' : clap ? 'clap' : 'snare', signature: false, grooveVoice: 1, accent: 100, ghost: 62 },
      { lane: 2, kind: 'hatClosed', signature: true, grooveVoice: 2, accent: 84, ghost: 30 },
      { lane: 5, kind: TOM_GENRES.has(l.genre) ? 'tom' : 'perc', signature: false, grooveVoice: 5, accent: 78, ghost: 40 },
    ];
    if (v.transport === 0) return lanes.slice(0, 1);
    // Death drops the perc lane entirely: the kit is reduced to its skeleton.
    if (v.dead) return lanes.slice(0, 3);
    return lanes;
  }

  private drumChannel(l: CompiledLayer, v: LayerVariant, spec: DrumLaneSpec): HGChannel {
    const lp = l.layerParams;
    const c = this.channelBase('Drums');
    const genreIndex = Object.keys(HG.GENRES).indexOf(l.genre);
    const hold = v.transport === 0;
    let density = clamp(lp.density ?? 1, 0.25, 2);
    let threshold = clamp(lp.threshold ?? 0.5, 0.15, 0.95);
    let velScale = 1;
    if (v.dead) {
      density *= 0.5;
      threshold = Math.max(threshold, 0.8);
      velScale = 0.65;
    }
    if (hold) {
      // One soft kick per bar: a heartbeat under the held layers.
      density = 0.34;
      velScale *= 0.6;
    }

    const useFormula = spec.signature && l.formula !== 'groove';
    const formula = useFormula ? l.formula : 'groove';
    const params = useFormula
      ? { ...l.formulaParams }
      : HG.cleanParams('groove', {
          genre: genreIndex,
          voice: spec.grooveVoice,
          density,
          rotation: spec.kind === 'perc' || spec.kind === 'tom' ? Math.round(v.drift * 2) : 0,
        });

    c.formula = formula;
    c.params = params;
    c.drumLane = spec.lane;
    c.drumFormula = true;
    c.drumVelocity = 'formula';
    c.drumThreshold = useFormula ? threshold : 0.5;
    // Hold ignores tape speed: a stopped tape has no tempo of its own.
    c.rate = hold ? ROLE_SHAPES.drums.rate : snapRate(lp.rate, ROLE_SHAPES.drums.rate) / v.speed;
    c.cycle = Math.round(clamp(lp.cycle ?? 16, 4, 64));
    c.phrase = 16;
    c.gateLength = 0.5;
    c.swing = SWING_GENRES.has(l.genre) ? 0.56 : 0.5;
    const varies = spec.kind !== 'kick' && spec.kind !== 'snare' && spec.kind !== 'clap' && spec.kind !== 'rim';
    if (varies && !hold) {
      if (v.drift > 0) {
        c.phase = Math.round(v.drift * 4);
        c.micro = ((v.drift * 0.18 * c.rate) * MS_PER_MINUTE) / this.bpm;
      }
      if (v.transport === -1) c.retrograde = true;
    }
    c.lanes = c.lanes.map((lane, j) => ({
      ...lane,
      mute: j !== spec.lane,
      gate: formula,
      params: { ...params },
      accent: Math.round(clamp(spec.accent * velScale, 1, 127)),
      ghost: Math.round(clamp(spec.ghost * velScale, 1, 127)),
      micro: 0,
    }));
    return c;
  }

  // ───────────────────────────── compilation ─────────────────────────────

  private stateWith(channel: HGChannel): HGState {
    return { ...this.base, channels: [channel] };
  }

  private compileBar(track: TapeIndex, v: LayerVariant, bar: number): LayerNote[] {
    const l = this.layers[track];
    const start = bar * BEATS_PER_BAR;
    const out: LayerNote[] = [];
    if (l.role === 'drums') {
      for (const spec of this.drumLanes(l, v)) {
        const ch = this.drumChannel(l, v, spec);
        for (const e of HG.compileChannel(this.stateWith(ch), 0, start, 1)) {
          let kind = spec.kind;
          // The signature lane opens its hat on contour peaks that fall off the beat.
          if (kind === 'hatClosed' && (e.formulaValue ?? 0) >= 0.92 && e.step % 2 === 1) kind = 'hatOpen';
          out.push({
            track,
            beat: e.beat,
            duration: Math.min(e.duration, 1),
            pitch: DRUM_NOTE[kind],
            velocity: e.velocity,
            drum: kind,
            norm: DRUM_NORM[kind],
            step: e.step,
          });
        }
      }
    } else {
      const ch = this.pitchedChannel(l, v);
      for (const e of HG.compileChannel(this.stateWith(ch), 0, start, 1)) {
        // Clip at the next chord change: a note chosen under one chord never sustains into the next.
        const nextChord = (Math.floor(e.beat / this.chordBeats + 1e-9) + 1) * this.chordBeats;
        const duration = Math.max(0.02, Math.min(e.duration, nextChord - e.beat - 0.02));
        out.push({
          track,
          beat: e.beat,
          duration,
          pitch: e.pitch,
          velocity: e.velocity,
          norm: clamp((e.pitch - l.low) / Math.max(1, l.high - l.low), 0, 1),
          step: e.step,
        });
      }
    }
    if (l.role === 'chord') strumUpward(out);
    out.sort((a, b) => a.beat - b.beat || a.pitch - b.pitch);
    return out;
  }
}

/**
 * The engine strums in voicing order, so a tone folded down below the range top would sound last.
 * Re-deal the onsets of each chord so the strum always rises from the lowest tone.
 */
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
    const ends = group.map((n) => n.beat + n.duration);
    const end = Math.min(...ends);
    group.sort((a, b) => a.pitch - b.pitch);
    group.forEach((n, i) => {
      n.beat = beats[i];
      n.duration = Math.max(0.02, end - n.beat);
    });
  }
}

export const DRUM_NOTE: Record<DrumKind, number> = {
  kick: 36,
  rim: 37,
  snare: 38,
  clap: 39,
  hatClosed: 42,
  tom: 45,
  hatOpen: 46,
  perc: 56,
};

/** Rough "height" of each drum for contour visuals: low drums low, cymbals high. */
const DRUM_NORM: Record<DrumKind, number> = {
  kick: 0.05,
  tom: 0.3,
  snare: 0.45,
  clap: 0.5,
  rim: 0.55,
  perc: 0.65,
  hatClosed: 0.85,
  hatOpen: 0.95,
};
