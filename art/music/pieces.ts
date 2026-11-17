/**
 * The OVERDUB score: one piece per campaign level plus the menu bed.
 *
 * DRAFTS is the first pass, written from the level ideas before any measurement (formula picks
 * with engine and role defaults). It is kept so `analyze.ts --drafts` can reproduce the "before"
 * column of docs/MUSIC.md.
 *
 * PIECES is the art direction of the real score: key, scale, tempo, which cassette carries which
 * role, each layer's rhythmic identity, and for each layer a short list of formulas that fit the
 * level's idea with the parameter values worth trying. tune.ts searches inside that space for the
 * cleanest result across the whole speed / subset / state matrix and writes art/music/tuned.json;
 * compose.ts turns that into data/music/*.json.
 */
import type { MusicDef, TrackDef } from './lib';

export interface LayerSpec {
  role: TrackDef['role'];
  genre?: string;
  /** Rhythm identity and register: fixed by the composer, never searched. */
  fixed: Record<string, number>;
  /** Thematically acceptable formulas, in order of preference, each with the parameter values to try. */
  formulas: [string, Record<string, number[]>][];
  /** Layer-shaping values to try (defaults per role in tune.ts). */
  grid?: Record<string, number[]>;
  /** Reuse another piece's tuned formula and formula parameters (the finale's reprise). */
  reprise?: { piece: string; track: number };
}
export interface Piece {
  file: string;
  /** Campaign level id (slug), or 'menu'. */
  level: string;
  index: number;
  title: string;
  bpm: number;
  arc: 'upper' | 'middle' | 'lower' | 'boss' | 'finale' | 'menu';
  sfxPalette: 'warm' | 'hollow' | 'neon' | 'boss' | 'resolved';
  description: string;
  /** What each cassette's function is, in words (cassette 1..4). */
  layers: string[];
  root: number;
  scale: string;
  /** Candidate progressions (0-based scale degrees); the tuner keeps the cleanest. */
  progressions: number[][];
  chordBars: number;
  tracks: LayerSpec[];
  /** Menu only: which layers the bed plays and at which tape speed. */
  bed?: { present: boolean; speed: number }[];
}

const t = (role: TrackDef['role'], formula: string, params: Record<string, number> = {}, genre?: string): TrackDef =>
  genre ? { role, formula, genre, params } : { role, formula, params };

// Pitch classes.
const C = 0, Cs = 1, D = 2, E = 4, F = 5, Fs = 6, G = 7, A = 9, As = 10, B = 11;

export const DRAFTS: Record<string, { bpm: number; music: MusicDef }> = {
  '01-soft-open': { bpm: 90, music: { root: D, scale: 'Major Pentatonic', progression: [0, 3, 1, 3], chordBars: 2, tracks: [t('melody', 'fibonacci', { m: 8 }), t('chord', 'sine'), t('bass', 'triangle'), t('drums', 'euclid', { k: 5, n: 8 }, 'Lo-fi 80')] } },
  '02-hit-harder': { bpm: 100, music: { root: A, scale: 'Mixolydian', progression: [0, 6, 3, 0], chordBars: 2, tracks: [t('drums', 'euclid', { k: 7, n: 16 }, 'Boom bap'), t('bass', 'collatz', { s: 27 }), t('melody', 'squares', { m: 7 }), t('chord', 'saw')] } },
  '03-hold-the-door': { bpm: 120, music: { root: G, scale: 'Lydian', progression: [0, 1, 0, 4], chordBars: 2, tracks: [t('chord', 'spiral'), t('bass', 'ruler'), t('melody', 'stern'), t('drums', 'modgate', { d: 3 }, 'Dancehall')] } },
  '04-second-opinion': { bpm: 100, music: { root: E, scale: 'Dorian', progression: [0, 3, 0, 6], chordBars: 2, tracks: [t('melody', 'norgard'), t('bass', 'linear', { a: 2, c: 0, m: 7 }), t('chord', 'lissajous', { p: 2, q: 3 }), t('drums', 'staircase', { k: 5, n: 8 }, 'Lo-fi 80')] } },
  '05-dead-air': { bpm: 120, music: { root: B, scale: 'Minor', progression: [0, 5, 3, 4], chordBars: 2, tracks: [t('bass', 'recaman'), t('melody', 'primes', { m: 7 }), t('chord', 'cardioid'), t('drums', 'logistic', {}, 'Trap')] } },
  '06-crossfire': { bpm: 100, music: { root: Fs, scale: 'Dorian', progression: [0, 3, 6, 4], chordBars: 2, tracks: [t('drums', 'polymeter', { a: 3, b: 4 }, 'Jungle'), t('melody', 'lissajous', { p: 3, q: 4 }), t('bass', 'times', { m: 3, N: 8 }), t('chord', 'rose', { k: 3 })] } },
  '07-out-of-phase': { bpm: 80, music: { root: E, scale: 'Phrygian', progression: [0, 1, 0, 6], chordBars: 2, tracks: [t('melody', 'circle', { omega: 0.4, K: 0.8 }), t('chord', 'sine', { phase: 0.25 }), t('bass', 'triangle', { phase: 0.5 }), t('drums', 'beatty', {}, 'Drill')] } },
  '08-loop-pedal': { bpm: 120, music: { root: C, scale: 'Minor Pentatonic', progression: [0, 0, 3, 2], chordBars: 2, tracks: [t('bass', 'polygon', { p: 5, q: 2 }), t('drums', 'zeno', {}, 'House'), t('melody', 'lsystem'), t('chord', 'triangle')] } },
  '09-rewind': { bpm: 120, music: { root: F, scale: 'Minor', progression: [0, 5, 2, 6], chordBars: 2, tracks: [t('melody', 'triangle', { cycles: 2 }), t('bass', 'kolakoski'), t('drums', 'gray', { bit: 2 }, 'Reggaeton'), t('chord', 'saw')] } },
  '10-heavy-rotation': { bpm: 150, music: { root: As, scale: 'Phrygian', progression: [0, 1, 5, 6], chordBars: 2, tracks: [t('drums', 'vertices', { sides: 5 }, 'Funk / disco'), t('bass', 'spirograph'), t('melody', 'rose', { k: 5 }), t('chord', 'polygon', { p: 7, q: 3 })] } },
  '11-the-archivist': { bpm: 90, music: { root: Cs, scale: 'Harmonic Minor', progression: [0, 5, 3, 4], chordBars: 2, tracks: [t('bass', 'collatz', { s: 871 }), t('drums', 'ca', { rule: 30 }, 'Drill'), t('melody', 'bytebeat'), t('chord', 'primes', { m: 12 })] } },
  '12-master-tape': { bpm: 120, music: { root: D, scale: 'Major', progression: [0, 3, 5, 4], chordBars: 2, tracks: [t('melody', 'fibonacci', { m: 8 }), t('chord', 'harmonograph'), t('bass', 'lucas', { m: 7 }), t('drums', 'euclid', { k: 5, n: 8 }, 'Funk / disco')] } },
  menu: { bpm: 72, music: { root: D, scale: 'Major Pentatonic', progression: [0, 3], chordBars: 2, tracks: [t('chord', 'spiral'), t('melody', 'cardioid'), t('bass', 'sine'), t('drums', 'modgate', { d: 4 }, 'Lo-fi 80')] } },
};

const L = (role: TrackDef['role'], fixed: Record<string, number>, formulas: [string, Record<string, number[]>][], extra: Partial<LayerSpec> = {}): LayerSpec => ({ role, fixed, formulas, ...extra });

export const PIECES: Piece[] = [
  {
    file: '01-soft-open', level: 'soft-open', index: 1, title: 'Soft Open', bpm: 90, arc: 'upper', sfxPalette: 'warm',
    description: 'A Fibonacci lead over a breathing sine pad in G major pentatonic: five notes, no possible clash, the warmest the game ever sounds.',
    layers: [
      'Lead: the Fibonacci sequence mod m, a tune that keeps almost repeating. Recorded first, it stands alone as a music-box line.',
      'Pad: a slow sine moves the voicing up and down the register, like breath.',
      'Bass: a triangle wave walking between chord tones, three notes a bar.',
      'Kit: Euclidean hats E(k,n) over a lo-fi kick and snare.',
    ],
    root: G, scale: 'Major Pentatonic', progressions: [[0, 3, 1, 3], [0, 3, 0, 4], [0, 2, 3, 0], [0, 4, 3, 0]], chordBars: 2,
    tracks: [
      L('melody', { register: 1, pulses: 5, steps: 8 }, [['fibonacci', { m: [8, 5, 7, 12, 16, 11, 13] }]]),
      L('chord', {}, [['sine', { cycles: [1, 2, 0.5], phase: [0, 0.25, 0.5, 0.75] }], ['cardioid', {}]]),
      L('bass', {}, [['triangle', { cycles: [1, 2, 3], phase: [0, 0.25, 0.5, 0.75] }], ['sine', { cycles: [1, 2], phase: [0, 0.25, 0.5, 0.75] }]]),
      L('drums', { rate: 0.25 }, [['euclid', { k: [5, 3, 7], n: [8, 16], rot: [0, 1, 2] }]], { genre: 'Lo-fi 80', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85] } }),
    ],
  },
  {
    file: '02-hit-harder', level: 'hit-harder', index: 2, title: 'Hit Harder', bpm: 100, arc: 'upper', sfxPalette: 'warm',
    description: 'Boom-bap swagger in A Mixolydian: a Collatz hailstone bass that climbs and crashes, alone at first (the level has one cassette), under a lead made of triangular numbers.',
    layers: [
      'Bass: a Collatz orbit (halve if even, 3n+1 if odd), a riff that surges up and tumbles down to 4-2-1. Recorded first: this level has a single cassette, so the riff IS the level, walking at 1x and driving at 2x.',
      'Kit: boom bap with Euclidean hats.',
      'Lead: a figurate-number riff (triangular or square numbers mod m), played as sparse stabs.',
      'Chords: a ramp sweeps the voicing upward and drops it, bar after bar.',
    ],
    root: A, scale: 'Mixolydian', progressions: [[0, 6, 3, 0], [0, 3, 0, 6], [0, 4, 3, 0], [0, 1, 3, 0], [0, 5, 3, 0], [0, 4, 1, 0], [0, 4, 5, 4], [0, 1, 4, 0], [0, 5, 1, 4]], chordBars: 2,
    tracks: [
      L('bass', { pulses: 5, steps: 8 }, [['collatz', { s: [27, 7, 9, 15, 19, 25, 31, 41, 54, 73, 97], after: [1, 0, 2] }]]),
      L('drums', { rate: 0.25 }, [['euclid', { k: [7, 5, 9, 6], n: [16], rot: [0, 2] }], ['staircase', { k: [5, 7], n: [8, 16] }]], { genre: 'Boom bap', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85] } }),
      L('melody', { register: 1, pulses: 3, steps: 8 }, [['squares', { m: [7, 5, 8, 9, 11, 12, 13, 16] }], ['triangular', { m: [7, 5, 8, 9, 11, 12] }]]),
      L('chord', {}, [['saw', { cycles: [1, 2, 0.5], phase: [0, 0.25, 0.5, 0.75] }], ['triangle', { cycles: [1, 2], phase: [0, 0.5] }]]),
    ],
  },
  {
    file: '03-hold-the-door', level: 'hold-the-door', index: 3, title: 'Hold the Door', bpm: 120, arc: 'upper', sfxPalette: 'warm',
    description: 'Long held chords in C Lydian winding on a spiral over a ruler-sequence bass, later joined by a lead that counts the 1-bits of the step number: music that waits for you.',
    layers: [
      'Chords: a slow closed curve winds the voicing outward; one long chord per bar. Recorded first: holding is the level (two cassettes here: the held chords and the bass).',
      'Bass: a fractal integer sequence in slow quarter steps, small moves with ever rarer tall ones.',
      'Lead: a self-similar integer sequence (binary digit counts, or its relatives) that rises in terraces, three notes a bar.',
      'Kit: a dancehall pulse with a modulo-gate hat that only speaks every d-th step.',
    ],
    root: C, scale: 'Lydian', progressions: [[0, 1, 0, 4], [0, 4, 0, 2], [0, 5, 0, 4], [0, 2, 5, 4], [0, 6, 5, 4], [0, 1, 5, 1], [0, 1, 2, 1], [0, 5, 1, 0], [0, 1, 0, 5], [0, 2, 1, 0]], chordBars: 2,
    tracks: [
      L('chord', { rate: 4 }, [['spiral', {}], ['cardioid', {}], ['astroid', {}]]),
      L('bass', { rate: 1, pulses: 3, steps: 8 }, [['ruler', {}]]),
      L('melody', { register: 1, pulses: 3, steps: 8 }, [['stern', {}], ['popcount', { bits: [3, 4, 8] }], ['thue', {}]]),
      L('drums', { rate: 0.25 }, [['modgate', { d: [3, 4, 5, 6], rot: [0, 1, 2] }]], { genre: 'Dancehall', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85, 0.7] } }),
    ],
  },
  {
    file: '04-second-opinion', level: 'second-opinion', index: 4, title: 'Second Opinion', bpm: 100, arc: 'upper', sfxPalette: 'warm',
    description: 'E Dorian, the first shadow: a self-similar lead that contains itself at half speed, answered by Lissajous chords.',
    layers: [
      'Lead: a self-similar sequence: every second note of it is the same melody again, so a double-speed take and a normal-speed take sing in canon.',
      'Chords: a Lissajous figure p:q answers the lead in off-beat stabs.',
      'Bass: a modular walk, an even stride through the chord tones on every beat.',
      'Kit: a Bresenham / Beatty hat over a lo-fi kit.',
    ],
    root: E, scale: 'Dorian', progressions: [[0, 3, 0, 6], [0, 6, 3, 0], [0, 4, 3, 0], [0, 1, 4, 0], [0, 4, 1, 0]], chordBars: 2,
    tracks: [
      L('melody', { register: 0, pulses: 5, steps: 8 }, [['norgard', {}]]),
      L('chord', { rate: 1, pulses: 3, steps: 8 }, [['lissajous', { p: [2, 3, 1], q: [3, 2, 4, 5], phase: [0.25, 0, 0.5] }]]),
      L('bass', { register: -1, pulses: 4, steps: 8 }, [['linear', { a: [2, 3, 4, 5], c: [0, 1, 3], m: [7, 5, 8, 12] }], ['times', { m: [2, 3, 5], N: [12, 8, 7] }]]),
      L('drums', { rate: 0.25 }, [['staircase', { k: [5, 3, 7], n: [8, 16] }], ['beatty', { alpha: [1.61803398875, 1.5, 2.41421356] }]], { genre: 'Lo-fi 80', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85] } }),
    ],
  },
  {
    file: '05-dead-air', level: 'dead-air', index: 5, title: 'Dead Air', bpm: 120, arc: 'middle', sfxPalette: 'hollow',
    description: 'B minor, the home key gone cold: seven-step phrases that never sit square on the bar, a Recaman bass and a lead that only knows primes.',
    layers: [
      'Bass: Recaman\'s sequence (step back n if you can, else forward), slow and searching, gated in sevens.',
      'Lead: a prime-number sequence, an irregular signal through static, four notes every seven steps.',
      'Chords: one long swell per bar on a closed curve, mostly silence around it.',
      'Kit: a trap skeleton whose hats are a chaotic map: bursts, then nothing.',
    ],
    root: B, scale: 'Minor', progressions: [[0, 5, 3, 4], [0, 3, 0, 4], [0, 4, 3, 0], [0, 3, 4, 0], [0, 6, 3, 4], [0, 4, 0, 3]], chordBars: 2,
    tracks: [
      L('bass', { rate: 1, pulses: 3, steps: 7 }, [['recaman', {}]]),
      L('melody', { register: 1, pulses: 4, steps: 7 }, [['primes', { m: [7, 5, 8, 9, 11, 12, 13, 16] }], ['primegaps', {}], ['totient', {}]]),
      L('chord', { rate: 4 }, [['cardioid', {}], ['astroid', {}], ['butterfly', {}]]),
      L('drums', { rate: 0.25 }, [['logistic', { r: [3.83, 3.55, 3.7, 3.95, 3.99, 3.6] }], ['tent', { r: [1.9, 1.7, 1.999] }]], { genre: 'Trap', grid: { threshold: [0.5, 0.6, 0.7, 0.8], density: [0.5, 0.75] } }),
    ],
  },
  {
    file: '06-crossfire', level: 'crossfire', index: 6, title: 'Crossfire', bpm: 100, arc: 'middle', sfxPalette: 'hollow',
    description: 'Three against four in F# Dorian: a polymeter kit, a Lissajous lead phrased in threes and chords that land every third beat, crossing every barline.',
    layers: [
      'Kit: a polymeter hat (every 3rd OR every b-th step) over a jungle kick. Recorded first: the crossfire is the rhythm.',
      'Lead: a Lissajous curve p:q, two sines at odds, phrased in threes over the four-beat bar.',
      'Bass: a modular star pattern that keeps returning to the root.',
      'Chords: a rose curve, struck every third beat so the harmony cuts across the bar.',
    ],
    root: Fs, scale: 'Dorian', progressions: [[0, 3, 6, 4], [0, 6, 3, 0], [0, 4, 6, 0], [0, 1, 4, 0], [0, 4, 1, 0], [0, 6, 4, 0]], chordBars: 2,
    tracks: [
      L('drums', { rate: 0.25 }, [['polymeter', { a: [3], b: [4, 8] }]], { genre: 'Jungle', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85, 1.25] } }),
      L('melody', { register: 0, pulses: 4, steps: 6 }, [['lissajous', { p: [3], q: [4, 2, 5], phase: [0.25, 0, 0.5, 0.75] }]]),
      L('bass', { register: -1, pulses: 3, steps: 8 }, [['times', { m: [3, 2, 5, 7], N: [8, 12, 7, 9, 16] }], ['polygon', { p: [5, 7, 8], q: [2, 3] }]]),
      L('chord', { rate: 1, pulses: 1, steps: 3 }, [['rose', { k: [3, 2, 4, 5, 7] }]]),
    ],
  },
  {
    file: '07-out-of-phase', level: 'out-of-phase', index: 7, title: 'Out of Phase', bpm: 80, arc: 'middle', sfxPalette: 'hollow',
    description: 'C# Phrygian phase music: loops of 8, 7 and 5 steps slide against each other and only line up again every few bars.',
    layers: [
      'Lead: a circle map (a rotation nudged by a sine), locking and slipping against its own period, on an 8-step loop.',
      'Chords: a sine a quarter-cycle away, on a 5-step loop.',
      'Bass: a triangle wave out of phase with the lead, on a 7-step loop.',
      'Kit: a golden-ratio hat that never repeats, over a drill kit.',
    ],
    root: Cs, scale: 'Phrygian', progressions: [[0, 1, 0, 6], [0, 6, 0, 1], [0, 3, 0, 6], [0, 6, 3, 0], [0, 3, 6, 0], [0, 5, 6, 0]], chordBars: 2,
    tracks: [
      L('melody', { register: 1, pulses: 5, steps: 8 }, [['circle', { omega: [0.4, 0.25, 0.3333333333, 0.5, 0.6666667, 0.2], K: [0.8, 0.4, 1.2, 0] }], ['sine', { cycles: [1, 2, 3], phase: [0] }]]),
      L('chord', { rate: 1, pulses: 2, steps: 5 }, [['sine', { cycles: [1, 2], phase: [0.25, 0.75] }]]),
      L('bass', { pulses: 3, steps: 7 }, [['triangle', { cycles: [1, 2, 3], phase: [0.5, 0.25] }]]),
      L('drums', { rate: 0.25 }, [['beatty', { alpha: [1.61803398875, 1.5, 2.41421356, 1.3, 2] }], ['kolakoski', {}]], { genre: 'Drill', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85, 1.25] } }),
    ],
  },
  {
    file: '08-loop-pedal', level: 'loop-pedal', index: 8, title: 'Loop Pedal', bpm: 120, arc: 'lower', sfxPalette: 'neon',
    description: 'C minor pentatonic, neon and hypnotic: every layer is a short loop, a self-describing Kolakoski lead over a star-polygon bass and a half-time house kick.',
    layers: [
      'Bass: a modular star figure, visiting its points in a fixed skip pattern: a loop you can count.',
      'Kit: house; half-time at 1x, four-on-the-floor when the tape runs double.',
      'Lead: a self-generating sequence (Kolakoski: the run lengths of the sequence are the sequence; or an L-system rewriting its own output) on a one-bar loop: long and short runs that never quite settle.',
      'Chords: a triangle wave, up one bar and down the next.',
    ],
    root: C, scale: 'Minor Pentatonic', progressions: [[0, 0, 3, 2], [0, 0, 2, 3], [0, 3, 0, 2], [0, 0, 3, 4], [0, 0, 0, 3]], chordBars: 2,
    tracks: [
      L('bass', { pulses: 5, steps: 8, phrase: 8 }, [['polygon', { p: [5, 7, 8, 9, 6], q: [2, 3] }], ['times', { m: [2, 3, 5], N: [8, 12, 5] }]], { grid: { contour: [0.1, 0.25], cycle: [8] } }),
      L('drums', { rate: 0.5 }, [['bit', { bit: [0, 1, 2] }], ['euclid', { k: [5, 7, 3], n: [8, 16], rot: [0, 2] }]], { genre: 'House', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85, 1.25] } }),
      L('melody', { register: 1, pulses: 5, steps: 8, phrase: 8 }, [['lsystem', { depth: [10, 6, 8, 12] }], ['kolakoski', {}], ['thue', {}]], { grid: { contour: [0.15, 0.3, 0.45, 0.6, 0.7], gravity: [0.5, 0.67, 0.85], cycle: [8, 16] } }),
      L('chord', {}, [['triangle', { cycles: [1, 2, 0.5], phase: [0, 0.25, 0.5, 0.75] }]]),
    ],
  },
  {
    file: '09-rewind', level: 'rewind', index: 9, title: 'Rewind', bpm: 120, arc: 'lower', sfxPalette: 'neon',
    description: 'F minor mirrors: a bass line that is note for note the same when its tape runs backwards, under a triangle-wave lead whose reverse is its own variation and saw chords that audibly turn around.',
    layers: [
      'Lead: a triangle wave, a contour that is its own mirror image; reversed, the phrase shaping turns it into a variation of itself rather than a copy.',
      'Bass: one sine cycle placed so its mirror axis sits mid-loop: the reversed tape plays the identical line.',
      'Kit: reggaeton dembow with a Gray-code hat, where each step flips exactly one bit.',
      'Chords: a saw ramp; the one layer that audibly runs backwards when the tape does.',
    ],
    root: F, scale: 'Minor', progressions: [[0, 5, 2, 6], [0, 3, 0, 4], [0, 5, 3, 4], [0, 6, 5, 4], [0, 3, 6, 0], [0, 4, 3, 0]], chordBars: 2,
    tracks: [
      L('melody', { register: 0, pulses: 5, steps: 8 }, [['triangle', { cycles: [2, 1, 3, 4, 1.5], phase: [0, 0.25, 0.5, 0.75] }]]),
      // Phase 0.8125 puts the mirror axis of a one-cycle sine between steps 3 and 4 of an 8-step cycle, so the engine's
      // retrograde (index -> cycle - 1 - index) reads exactly the same values: measured 0% of steps change in reverse.
      L('bass', { register: -1, pulses: 3, steps: 8, cycle: 8 }, [['sine', { cycles: [1], phase: [0.8125] }]]),
      L('drums', { rate: 0.5 }, [['gray', { bit: [2, 0, 1, 3] }], ['bit', { bit: [1, 2] }]], { genre: 'Reggaeton', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85, 1.25] } }),
      L('chord', {}, [['saw', { cycles: [1, 2, 0.5], phase: [0, 0.25, 0.5, 0.75] }]]),
    ],
  },
  {
    file: '10-heavy-rotation', level: 'heavy-rotation', index: 10, title: 'Heavy Rotation', bpm: 150, arc: 'lower', sfxPalette: 'neon',
    description: 'A# Phrygian at 150, half-time and enormous: everything is a wheel, a spirograph bass, a rose-curve lead and chords on a three-beat turn.',
    layers: [
      'Kit: disco hats driven by the vertices of a rotating polygon. Recorded first: the wheel starts turning.',
      'Bass: a spirograph (a wheel rolling inside a wheel), a heavy looping orbit on a three-beat cycle.',
      'Lead: a petalled closed curve on a six-beat cycle.',
      'Chords: a star polygon, one stab every third beat, rotating against the bar.',
    ],
    root: As, scale: 'Phrygian', progressions: [[0, 1, 5, 6], [0, 6, 0, 1], [0, 3, 6, 0], [0, 6, 3, 0], [0, 5, 6, 0], [0, 1, 0, 6]], chordBars: 2,
    tracks: [
      L('drums', { rate: 0.5 }, [['vertices', { sides: [5, 3, 4, 6, 7, 8], speed: [1, 2, 3] }]], { genre: 'Funk / disco', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85, 1.25] } }),
      L('bass', { pulses: 4, steps: 6 }, [['spirograph', { R: [5, 7, 8], r: [3, 2, 1], d: [2, 1, 3] }]]),
      L('melody', { register: 1, pulses: 5, steps: 12 }, [['rose', { k: [5, 3, 2, 4, 7] }], ['superformula', { m: [5, 3, 4, 6, 8] }]]),
      L('chord', { rate: 1, pulses: 1, steps: 3 }, [['polygon', { p: [7, 5, 8, 9], q: [3, 2] }]]),
    ],
  },
  {
    file: '11-the-archivist', level: 'the-archivist', index: 11, title: 'The Archivist', bpm: 90, arc: 'boss', sfxPalette: 'boss',
    description: 'F# harmonic minor, one semitone under home and pulling at it: a relentless Collatz bass, a cellular-automaton kit and a lead reading out an endless digit stream, over two chords that never reach a dominant. The thing that remembers everything.',
    layers: [
      'Bass: a long Collatz orbit, six notes in every eight steps: it never settles, and nobody has proved it must.',
      'Kit: drill, with hats read off an elementary cellular automaton (Rule 90 draws the Sierpinski triangle; Rule 30 is chaos): a machine counting.',
      'Lead: an endless deterministic digit stream, an archive with every sequence in it.',
      'Chords: a number-theoretic sequence, stabbed on a tresillo.',
    ],
    root: Fs, scale: 'Harmonic Minor', // Three chords of two bars: the level loop is 6 bars (its horizon has been 6 and 12 bars at different times), so the
    // progression turns exactly once per loop and always ends on a chord that pulls back to the tonic.
    progressions: [[0, 3, 4], [0, 5, 4], [0, 0, 4], [0, 3, 3], [0, 5, 3]], chordBars: 2,
    tracks: [
      L('bass', { register: -1, pulses: 6, steps: 8 }, [['collatz', { s: [871, 27, 97, 703, 6171, 327, 649], after: [1, 2] }]]),
      L('drums', { rate: 0.25 }, [['ca', { rule: [30, 110, 90], cell: [31, 20, 28, 33, 40] }]], { genre: 'Drill', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85, 1.25] } }),
      L('melody', { register: 0, pulses: 5, steps: 8 }, [['digits', { constant: [0, 1, 2, 3], base: [7, 5, 8, 10, 12] }], ['bytebeat', { a: [3, 2, 4], b: [5, 6, 7], mask: [31, 15, 63] }]]),
      L('chord', { rate: 1, pulses: 3, steps: 8 }, [['primes', { m: [12, 7, 8, 5, 16] }], ['divisors', {}]]),
    ],
  },
  {
    file: '12-master-tape', level: 'master-tape', index: 12, title: 'Master Tape', bpm: 120, arc: 'finale', sfxPalette: 'resolved',
    description: 'Home again, G major with every note filled in: the first level\'s Fibonacci lead and Euclidean kit return over a Lucas bass and chords drawn by the harmonograph itself.',
    layers: [
      'Lead: the very same Fibonacci function as Soft Open, now in the full major scale and a third faster: the tune you started with, grown up.',
      'Chords: the harmonograph curve (two decaying pendulums), the machine the whole score is named after.',
      'Bass: the Lucas numbers, the same rule as Fibonacci from a different start: the lead\'s sibling, underneath it.',
      'Kit: Soft Open\'s Euclidean hats again, on a disco kit: half-time at 1x, dancing at 2x.',
    ],
    root: G, scale: 'Major', progressions: [[0, 3, 5, 4], [0, 4, 5, 3], [0, 5, 3, 4], [0, 2, 3, 4], [0, 5, 1, 4], [0, 3, 1, 4], [0, 4, 5, 4], [0, 1, 5, 4], [0, 5, 2, 4], [0, 2, 5, 4], [0, 4, 1, 4]], chordBars: 2,
    tracks: [
      L('melody', { register: 1, pulses: 5, steps: 8 }, [], { reprise: { piece: '01-soft-open', track: 0 } }),
      L('chord', {}, [['harmonograph', { p: [2, 1, 3], q: [3, 2, 5], decay: [0.02, 0, 0.05], phase: [0.25, 0, 0.5] }]]),
      L('bass', { pulses: 5, steps: 8 }, [['lucas', { m: [7, 5, 8, 12, 16, 11] }]]),
      L('drums', { rate: 0.5 }, [], { genre: 'Funk / disco', grid: { threshold: [0.4, 0.5, 0.6, 0.7], density: [1, 0.85, 1.25] }, reprise: { piece: '01-soft-open', track: 3 } }),
    ],
  },
  {
    file: 'menu', level: 'menu', index: 0, title: 'Menu Bed', bpm: 72, arc: 'menu', sfxPalette: 'warm',
    description: 'A calm G major pentatonic bed at 72 bpm: a slow pad, a music-box line and a soft bass, all at half tape speed, no drums.',
    layers: [
      'Pad: a slow closed curve, one long chord per bar.',
      'Line: a few soft notes that lean into each chord.',
      'Bass: a slow sine.',
      'Kit: a single modulo-gate tick. Not part of the bed; present so the block is a complete four-layer piece.',
    ],
    root: G, scale: 'Major Pentatonic', progressions: [[0, 3], [0, 3, 1, 3], [0, 2, 3, 0], [0, 4]], chordBars: 2,
    tracks: [
      L('chord', { rate: 4 }, [['spiral', {}], ['cardioid', {}], ['sine', { cycles: [1, 0.5], phase: [0, 0.25, 0.75] }]]),
      L('melody', { register: 1, rate: 1, pulses: 3, steps: 8 }, [['cardioid', {}], ['astroid', {}], ['sine', { cycles: [1, 2], phase: [0, 0.25, 0.75] }]]),
      L('bass', { rate: 1, pulses: 3, steps: 8 }, [['sine', { cycles: [1, 2, 0.5], phase: [0, 0.25, 0.5, 0.75] }]]),
      L('drums', { rate: 0.5 }, [['modgate', { d: [4, 8, 6], rot: [0, 2] }]], { genre: 'Lo-fi 80', grid: { density: [0.5], threshold: [0.5] } }),
    ],
    bed: [{ present: true, speed: 0.5 }, { present: true, speed: 0.5 }, { present: true, speed: 0.5 }, { present: false, speed: 1 }],
  },
];
void C; void F; void Cs; void E; void B;
