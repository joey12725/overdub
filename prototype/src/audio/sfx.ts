/**
 * Gameplay sounds as music (MUSIC-05..07). Pure planning: which cue each SimEvent becomes, its
 * pitches from the chord in force, when it sounds, and how repeats are merged. Web Audio rendering
 * of the cues lives in voices.ts.
 *
 * Latency policy (MUSIC-07). Events are never moved in the simulation; only their audible accent is
 * placed, and only LATE: to the next line of the sixteenth grid, never more than one sixteenth
 * after the event. The grid is the master sixteenth subdivided by the same power of two the world
 * is slowed by, so while recording at tape speed s (world rate 1/s) the grid is one sixteenth of
 * the base tempo as the player hears it, and it always nests inside the master sixteenth grid.
 * Impacts additionally get an immediate soft transient so feedback is never mushy.
 */
import type { SimEvent, SimEventType, TapeIndex } from '../core/types';
import { BEATS_PER_BAR, SUB_HZ } from '../core/types';
import type { ChordInfo } from './director';

export type SfxKind =
  | 'step'
  | 'swingLight'
  | 'swingHeavy'
  | 'hit'
  | 'kill'
  | 'break'
  | 'clang'
  | 'dodge'
  | 'fire'
  | 'projectileHit'
  | 'interact'
  | 'interactFail'
  | 'door'
  | 'plate'
  | 'laser'
  | 'core'
  | 'selfDeath'
  | 'desync'
  | 'resync'
  | 'tapeWrap'
  | 'tapeTurn'
  | 'tapeEnd'
  | 'enemyTelegraph'
  | 'enemyAttack'
  | 'enemyShot'
  | 'enemyStagger'
  | 'bossPhase'
  | 'bossRecall'
  | 'objective'
  /** Immediate soft attack played ahead of a quantised impact. */
  | 'transient';

export interface SfxCue {
  kind: SfxKind;
  /** Start time on the audio clock (seconds). */
  time: number;
  /** MIDI pitches, in the order the recipe plays them. */
  pitches: number[];
  /** 0..1. */
  gain: number;
  /** -1..1. */
  pan: number;
  /** 'on' | 'off' | archetype | 'light' | 'heavy' … passed through from the event. */
  detail?: string;
  tape?: TapeIndex;
  /** Seconds per master sixteenth at the current transport, for recipes with internal rhythm. */
  sixteenth: number;
  /** How many events were merged into this cue. */
  count: number;
}

export interface SfxClock {
  /** Audio-clock time now. */
  now: number;
  /** Master beat of the transport now. */
  beat: number;
  /** Master seconds per wall second (0 when paused). */
  rate: number;
  playing: boolean;
  bpm: number;
}

export interface Harmony {
  chordAt(beat: number): ChordInfo;
}

// ───────────────────────────── quantisation ─────────────────────────────

/** Sixteenth-grid spacing in master beats at a given world rate (see the latency policy above). */
export function sfxGrid(rate: number): number {
  const sixteenth = BEATS_PER_BAR / 16;
  if (!(rate > 0) || rate >= 1) return sixteenth;
  const k = Math.ceil(Math.log2(1 / rate) - 1e-9);
  return sixteenth / 2 ** Math.max(0, k);
}

export interface Quantised {
  /** Master beat the accent lands on. */
  beat: number;
  /** Seconds from now until it sounds (≥ 0). */
  delay: number;
  /** Seconds the accent lands after the event itself (≥ 0, ≤ one sixteenth). */
  lateness: number;
}

/**
 * Places an event's accent on the next sixteenth line at or after the event. The event happened at
 * master `eventBeat`; the transport is at `clock.beat` now. Never early, never more than one grid
 * step (≤ one sixteenth of the heard tempo) after the event.
 */
export function quantizeLate(eventBeat: number, clock: SfxClock): Quantised {
  const bps = clock.rate * (clock.bpm / 60);
  if (!clock.playing || !(bps > 0) || !Number.isFinite(eventBeat)) return { beat: clock.beat, delay: 0, lateness: 0 };
  const g = sfxGrid(clock.rate);
  const target = Math.ceil(eventBeat / g - 1e-9) * g;
  // How long ago (≥ 0) the event happened, as far as the transport is concerned.
  const since = Math.max(0, (clock.beat - eventBeat) / bps);
  const latenessWanted = (target - eventBeat) / bps;
  const delay = Math.max(0, latenessWanted - since);
  return { beat: Math.max(target, clock.beat), delay, lateness: since + delay };
}

export function subToMasterBeat(sub: number, bpm: number): number {
  return (sub / SUB_HZ) * (bpm / 60);
}

// ───────────────────────────── pitch ─────────────────────────────

/** Chord tone `i` (0 = root, 1 = third, … wrapping up octaves) at or above the chord root in `octave`. */
export function chordTone(chord: ChordInfo, i: number, octave: number): number {
  const pcs = chord.pcs.length ? chord.pcs : [chord.root];
  const base = 12 * (octave + 1) + chord.root;
  const stack = pcs.map((pc) => base + ((((pc - chord.root) % 12) + 12) % 12)).sort((a, b) => a - b);
  const idx = ((i % stack.length) + stack.length) % stack.length;
  return stack[idx] + 12 * Math.floor(i / stack.length);
}

// ───────────────────────────── event → cue ─────────────────────────────

interface Recipe {
  kind: SfxKind;
  pitches: (c: ChordInfo, e: SimEvent, t: number) => number[];
  gain: (e: SimEvent) => number;
  /** Merge key: events with the same key on the same grid line become one cue. */
  key: (e: SimEvent) => string;
  /** Minimum seconds between cues with the same key (rate limit across frames). */
  minInterval: number;
  impact: boolean;
  priority: number;
}

const tapeOf = (e: SimEvent) => e.tape ?? 0;
/** Momentum → 0..1 loudness; logarithmic so a 4x heavy is louder than a 0.5x light without clipping. */
const powerGain = (e: SimEvent, lo: number, hi: number) => {
  const p = Math.max(0, e.power ?? 1);
  return Math.min(hi, lo + (hi - lo) * Math.min(1, Math.log2(1 + p) / 4));
};
const fixed = (g: number) => () => g;
const byKind = (k: string) => () => k;
const byTape = (k: string) => (e: SimEvent) => `${k}:${tapeOf(e)}`;
const isOff = (e: SimEvent) => e.detail === 'off' || e.detail === 'close' || e.detail === 'closed';

/**
 * Selves sound on different chord tones (A root, B third, C fifth, D seventh/octave), so four
 * selves acting together spell the chord instead of piling onto one pitch.
 */
const RECIPES: Partial<Record<SimEventType, Recipe>> = {
  step: { kind: 'step', pitches: (c, e) => [chordTone(c, tapeOf(e), 3)], gain: fixed(0.1), key: byKind('step'), minInterval: 0.07, impact: false, priority: 0 },
  swing: {
    kind: 'swingLight',
    pitches: (c, e) => [chordTone(c, tapeOf(e) + (e.detail === 'heavy' ? 0 : 2), e.detail === 'heavy' ? 3 : 4)],
    gain: (e) => (e.detail === 'heavy' ? 0.3 : 0.2),
    key: byTape('swing'),
    minInterval: 0.05,
    impact: false,
    priority: 3,
  },
  hit: {
    kind: 'hit',
    pitches: (c, e) => {
      const lift = (e.power ?? 0) >= 6 ? 2 : 0;
      return [chordTone(c, tapeOf(e) + lift, 4), chordTone(c, tapeOf(e) + lift + 2, 5)];
    },
    gain: (e) => powerGain(e, 0.35, 0.9),
    key: byTape('hit'),
    minInterval: 0.04,
    impact: true,
    priority: 6,
  },
  kill: { kind: 'kill', pitches: (c) => [chordTone(c, 0, 5), chordTone(c, 1, 5), chordTone(c, 2, 5)], gain: fixed(0.55), key: byKind('kill'), minInterval: 0.06, impact: true, priority: 8 },
  break: { kind: 'break', pitches: (c) => [chordTone(c, 0, 2), chordTone(c, 0, 3)], gain: (e) => powerGain(e, 0.6, 0.85), key: byKind('break'), minInterval: 0.08, impact: true, priority: 8 },
  clang: { kind: 'clang', pitches: (c, e) => [chordTone(c, tapeOf(e) + 1, 5)], gain: (e) => powerGain(e, 0.25, 0.45), key: byKind('clang'), minInterval: 0.06, impact: true, priority: 4 },
  dodge: { kind: 'dodge', pitches: (c, e) => [chordTone(c, tapeOf(e) + 1, 5)], gain: fixed(0.2), key: byTape('dodge'), minInterval: 0.06, impact: false, priority: 2 },
  fire: { kind: 'fire', pitches: (c, e) => [chordTone(c, tapeOf(e), 4), chordTone(c, tapeOf(e) + 2, 5)], gain: fixed(0.32), key: byTape('fire'), minInterval: 0.05, impact: false, priority: 4 },
  projectileHit: { kind: 'projectileHit', pitches: (c, e) => [chordTone(c, tapeOf(e) + 1, 5)], gain: (e) => powerGain(e, 0.25, 0.6), key: byKind('projectileHit'), minInterval: 0.04, impact: true, priority: 5 },
  interact: {
    kind: 'interact',
    pitches: (c, e) => (isOff(e) ? [chordTone(c, 2, 5), chordTone(c, 1, 5)] : [chordTone(c, 1, 5), chordTone(c, 2, 5)]),
    gain: fixed(0.34),
    key: byTape('interact'),
    minInterval: 0.05,
    impact: false,
    priority: 6,
  },
  interactFail: { kind: 'interactFail', pitches: (c) => [chordTone(c, 0, 3)], gain: fixed(0.14), key: byKind('interactFail'), minInterval: 0.1, impact: false, priority: 1 },
  door: {
    kind: 'door',
    pitches: (c, e) => (isOff(e) ? [chordTone(c, 2, 2), chordTone(c, 0, 2)] : [chordTone(c, 0, 2), chordTone(c, 2, 2)]),
    gain: fixed(0.38),
    key: (e) => `door:${e.id ?? ''}`,
    minInterval: 0.1,
    impact: false,
    priority: 5,
  },
  plate: { kind: 'plate', pitches: (c, e) => [chordTone(c, isOff(e) ? 0 : 2, 4)], gain: fixed(0.28), key: (e) => `plate:${e.id ?? ''}`, minInterval: 0.08, impact: false, priority: 4 },
  laser: { kind: 'laser', pitches: (c) => [chordTone(c, 0, 3)], gain: fixed(0.22), key: (e) => `laser:${e.id ?? ''}`, minInterval: 0.08, impact: false, priority: 3 },
  core: { kind: 'core', pitches: (c) => [0, 1, 2, 3].map((i) => chordTone(c, i, 5)), gain: fixed(0.5), key: byKind('core'), minInterval: 0.1, impact: true, priority: 8 },
  selfDeath: { kind: 'selfDeath', pitches: (c) => [chordTone(c, 2, 4), chordTone(c, 1, 4), chordTone(c, 0, 4)], gain: fixed(0.6), key: byTape('selfDeath'), minInterval: 0.1, impact: true, priority: 9 },
  desync: { kind: 'desync', pitches: (c, e) => [chordTone(c, tapeOf(e), 4)], gain: fixed(0.34), key: byTape('desync'), minInterval: 0.1, impact: false, priority: 7 },
  resync: { kind: 'resync', pitches: (c, e) => [chordTone(c, tapeOf(e), 4), chordTone(c, tapeOf(e) + 3, 4)], gain: fixed(0.34), key: byTape('resync'), minInterval: 0.1, impact: false, priority: 7 },
  tapeWrap: { kind: 'tapeWrap', pitches: (c) => [chordTone(c, 0, 5)], gain: fixed(0.14), key: byTape('tapeWrap'), minInterval: 0.1, impact: false, priority: 2 },
  tapeTurn: { kind: 'tapeTurn', pitches: (c) => [chordTone(c, 2, 4)], gain: fixed(0.18), key: byTape('tapeTurn'), minInterval: 0.1, impact: false, priority: 2 },
  tapeEnd: { kind: 'tapeEnd', pitches: (c) => [chordTone(c, 0, 3)], gain: fixed(0.24), key: byTape('tapeEnd'), minInterval: 0.1, impact: false, priority: 3 },
  enemyTelegraph: { kind: 'enemyTelegraph', pitches: (c) => [chordTone(c, 0, 3), chordTone(c, 1, 3)], gain: fixed(0.22), key: byKind('enemyTelegraph'), minInterval: 0.06, impact: false, priority: 5 },
  enemyAttack: { kind: 'enemyAttack', pitches: (c) => [chordTone(c, 0, 2)], gain: fixed(0.36), key: byKind('enemyAttack'), minInterval: 0.06, impact: true, priority: 5 },
  enemyShot: { kind: 'enemyShot', pitches: (c) => [chordTone(c, 2, 4)], gain: fixed(0.22), key: byKind('enemyShot'), minInterval: 0.05, impact: false, priority: 4 },
  enemyStagger: { kind: 'enemyStagger', pitches: (c) => [chordTone(c, 1, 3)], gain: fixed(0.26), key: byKind('enemyStagger'), minInterval: 0.06, impact: false, priority: 3 },
  bossPhase: { kind: 'bossPhase', pitches: (c) => [chordTone(c, 0, 1), chordTone(c, 0, 2), chordTone(c, 2, 2)], gain: fixed(0.75), key: byKind('bossPhase'), minInterval: 0.3, impact: true, priority: 9 },
  bossRecall: { kind: 'bossRecall', pitches: (c) => [chordTone(c, 0, 4), chordTone(c, 2, 4), chordTone(c, 3, 4)], gain: fixed(0.42), key: byKind('bossRecall'), minInterval: 0.2, impact: false, priority: 7 },
  objective: { kind: 'objective', pitches: (c) => [chordTone(c, 0, 5), chordTone(c, 1, 5), chordTone(c, 2, 5), chordTone(c, 0, 6)], gain: fixed(0.6), key: byKind('objective'), minInterval: 0.3, impact: false, priority: 10 },
  // 'whiff' is deliberately silent: the swing already made its whoosh, and a second "miss" sound
  // would be noise rather than information.
};

/** SimEvent types that produce sound (everything except 'whiff'). */
export const AUDIBLE_EVENTS: readonly SimEventType[] = Object.keys(RECIPES) as SimEventType[];

const TAPE_PAN = [-0.28, -0.09, 0.09, 0.28];
/** Most cues one sixteenth slot may hold; lower-priority cues beyond it are dropped. */
const MAX_CUES_PER_SLOT = 8;
/** Below this delay the accent is effectively immediate, so no separate transient is needed. */
const TRANSIENT_MIN_DELAY = 0.012;

export class SfxPlanner {
  private lastByKey = new Map<string, number>();

  reset(): void {
    this.lastByKey.clear();
  }

  /** Turns one frame's events into cues. Deterministic given the same events and clock. */
  plan(events: readonly SimEvent[], clock: SfxClock, harmony: Harmony): SfxCue[] {
    const bps = clock.rate * (clock.bpm / 60);
    const sixteenth = bps > 0 ? BEATS_PER_BAR / 16 / bps : 60 / clock.bpm / 4;
    const merged = new Map<string, { cue: SfxCue; priority: number; key: string; slot: number }>();
    const transients = new Map<string, SfxCue>();

    for (const e of events) {
      const r = RECIPES[e.type];
      if (!r) continue;
      const q = quantizeLate(subToMasterBeat(e.sub, clock.bpm), clock);
      const time = clock.now + q.delay;
      const key = r.key(e);
      const slot = Math.round(q.beat / sfxGrid(clock.rate));
      const mergeKey = `${key}@${slot}`;
      const existing = merged.get(mergeKey);
      if (existing) {
        existing.cue.count++;
        // Merged repeats get a touch louder, never louder than one strong hit.
        existing.cue.gain = Math.min(1, Math.max(existing.cue.gain, r.gain(e)) * 1.08);
        continue;
      }
      const last = this.lastByKey.get(key);
      if (last !== undefined && time - last < r.minInterval && time >= last) continue;
      const kind: SfxKind = e.type === 'swing' && e.detail === 'heavy' ? 'swingHeavy' : r.kind;
      const chord = harmony.chordAt(q.beat);
      const cue: SfxCue = {
        kind,
        time,
        pitches: r.pitches(chord, e, tapeOf(e)),
        gain: r.gain(e),
        pan: e.tape !== undefined ? TAPE_PAN[e.tape] : 0,
        detail: e.detail,
        tape: e.tape,
        sixteenth,
        count: 1,
      };
      merged.set(mergeKey, { cue, priority: r.priority, key, slot });
      if (r.impact && q.delay > TRANSIENT_MIN_DELAY && !transients.has(key)) {
        transients.set(key, { kind: 'transient', time: clock.now, pitches: [cue.pitches[0]], gain: cue.gain * 0.3, pan: cue.pan, detail: e.type, tape: e.tape, sixteenth, count: 1 });
      }
    }

    const bySlot = new Map<number, { cue: SfxCue; priority: number; key: string }[]>();
    for (const m of merged.values()) {
      const list = bySlot.get(m.slot);
      if (list) list.push(m);
      else bySlot.set(m.slot, [m]);
    }
    const out: SfxCue[] = [];
    for (const list of bySlot.values()) {
      list.sort((a, b) => b.priority - a.priority);
      for (const m of list.slice(0, MAX_CUES_PER_SLOT)) {
        out.push(m.cue);
        this.lastByKey.set(m.key, m.cue.time);
      }
    }
    out.push(...transients.values());
    out.sort((a, b) => a.time - b.time);
    if (this.lastByKey.size > 256) {
      const cutoff = clock.now - 2;
      for (const [k, t] of this.lastByKey) if (t < cutoff) this.lastByKey.delete(k);
    }
    return out;
  }
}
