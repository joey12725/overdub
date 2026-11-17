import { describe, expect, test } from 'vitest';
import type { TapeIndex, TapeSpeed, TrackMusicDef } from '../../src/core/types';
import { ALL_SPEEDS } from '../../src/core/types';
import { baselineVariant, MusicDirector, type LayerNote, type LayerVariant } from '../../src/audio/director';
import { listMusicFormulas, type MusicRole } from '../../src/audio/formulas';
import { HG } from '../../src/audio/hg';
import { LayerSequencer } from '../../src/audio/sequencer';
import type { TrackAudioState } from '../../src/contracts';
import { musicLevel, standardLevel, STANDARD_TRACKS } from './fixtures';

const pc = (p: number) => ((p % 12) + 12) % 12;
const strip = (ns: LayerNote[]) => ns.map((n) => [n.track, +n.beat.toFixed(6), n.pitch, n.velocity, +n.duration.toFixed(6), n.drum ?? '']);
const v = (speed: TapeSpeed, extra: Partial<LayerVariant> = {}): LayerVariant => ({ ...baselineVariant(speed), ...extra });

const VARIANTS: [string, Partial<LayerVariant>][] = [
  ['baseline', {}],
  ['dead', { dead: true }],
  ['desync', { drift: 0.5 }],
  ['full drift', { drift: 1 }],
  ['reverse', { transport: -1 }],
  ['stopped', { transport: 0 }],
  ['dead reverse', { dead: true, transport: -1 }],
  ['desync reverse', { drift: 0.75, transport: -1 }],
];

describe('MusicDirector: state from LevelDef.music', () => {
  test('key, scale, progression and tempo come from the level', () => {
    const d = new MusicDirector(standardLevel({ root: 2, scale: 'Dorian', progression: [0, 3, 4], chordBars: 2, bpm: 90 }));
    expect(d.bpm).toBe(90);
    expect(d.scale).toBe('Dorian');
    expect(d.scalePcs).toEqual(HG.SCALES.Dorian.map((x) => (x + 2) % 12));
    expect(d.chordBeats).toBe(8);
    expect(d.chordAt(0).index).toBe(0);
    expect(d.chordAt(8).index).toBe(1);
    expect(d.chordAt(16).index).toBe(2);
    expect(d.chordAt(24).index).toBe(0);
    expect(d.chordAt(8).degree).toBe(3);
  });

  test('unknown scale / formula / genre fall back instead of throwing', () => {
    const d = new MusicDirector(
      musicLevel(
        [
          { role: 'melody', formula: 'not-a-formula' },
          { role: 'bass', formula: 'groove' },
          { role: 'drums', formula: 'fibonacci', genre: 'polka' },
          { role: 'chord', formula: 'plr' },
        ],
        { scale: 'nonsense' },
      ),
    );
    expect(d.scale).toBe('Minor');
    expect(d.layer(0).formula).toBe('sine');
    expect(d.layer(1).formula).toBe('triangle');
    expect(d.layer(3).formula).toBe('sine');
    expect(d.notes(2, v(1), 0, 8).length).toBeGreaterThan(0);
  });
});

describe('determinism (MUSIC determinism)', () => {
  test('same level + same layer states give the same notes, independent of compile order', () => {
    const a = new MusicDirector(standardLevel());
    const b = new MusicDirector(standardLevel());
    for (const t of [0, 1, 2, 3] as TapeIndex[]) {
      for (const [, extra] of VARIANTS) {
        const forward = a.notes(t, v(2, extra), 0, 32);
        // b compiles bars backwards and in odd windows: results must not depend on history.
        const pieces: LayerNote[] = [];
        for (let bar = 7; bar >= 0; bar--) pieces.unshift(...b.notes(t, v(2, extra), bar * 4, bar * 4 + 4));
        expect(strip(pieces)).toEqual(strip(forward));
      }
    }
  });

  test('the full sequencer output is reproducible from the same track-state history', () => {
    const run = () => {
      const s = new LayerSequencer(new MusicDirector(standardLevel()));
      const t = (o: Partial<TrackAudioState>): TrackAudioState => ({ present: true, speed: 1, life: 'alive', synced: true, transport: 1, ...o });
      const out: LayerNote[] = [];
      s.setTracks([t({ speed: 2 }), t({}), t({ speed: 0.5 }), t({ speed: 4 })], 0);
      out.push(...s.collect(0, 6));
      s.setTracks([t({ speed: 2, synced: false }), t({}), t({ speed: 0.5 }), t({ speed: 4, life: 'ghost' })], 6);
      out.push(...s.collect(6, 20));
      s.setTracks([t({ speed: 2 }), t({ transport: -1 }), t({ speed: 0.5 }), t({ speed: 4, life: 'ghost' })], 20);
      out.push(...s.collect(20, 40));
      return strip(out);
    };
    expect(run()).toEqual(run());
  });
});

describe('always in key (MUSIC-03, MUSIC-04)', () => {
  const formulas = listMusicFormulas();
  const pitchedRoles: MusicRole[] = ['melody', 'bass', 'chord'];

  for (const role of pitchedRoles) {
    test(`every ${role} pitch is in the scale for every allowed formula, speed and state`, () => {
      const scales: [number, string][] = [
        [9, 'Minor'],
        [2, 'Dorian'],
        [7, 'Major Pentatonic'],
      ];
      let checked = 0;
      for (const [root, scale] of scales) {
        for (const f of formulas.filter((x) => x.roles.includes(role))) {
          const track: TrackMusicDef = { role, formula: f.id };
          const d = new MusicDirector(musicLevel([track, track, track, track], { root, scale, progression: [0, 3, 4, 5] }));
          const inScale = new Set(d.scalePcs);
          for (const speed of ALL_SPEEDS) {
            for (const [name, extra] of VARIANTS) {
              const notes = d.notes(0, v(speed, extra), 0, 16);
              for (const n of notes) {
                if (!inScale.has(pc(n.pitch))) throw new Error(`${f.id} ${role} ${speed}x ${name}: pitch ${n.pitch} out of ${scale}`);
                checked++;
              }
            }
          }
        }
      }
      expect(checked).toBeGreaterThan(1000);
    });
  }

  test('bass and chord layers only ever sound tones of the chord at their master beat', () => {
    const d = new MusicDirector(standardLevel());
    for (const speed of ALL_SPEEDS) {
      for (const [name, extra] of VARIANTS) {
        // Bass: triad tones only. Chord layer: its seventh chord (a dead layer drops to the triad).
        for (const [t, ext] of [
          [1, 0],
          [3, extra.dead ? 0 : 1],
        ] as [TapeIndex, number][]) {
          const notes = d.notes(t, v(speed, extra), 0, 32);
          expect(notes.length).toBeGreaterThan(0);
          for (const n of notes) {
            // Strummed tones start a few ms late; the chord is the one at the step's onset.
            const chord = d.chordAt(n.beat - 0.1 < 0 ? 0 : Math.floor(n.beat * 2) / 2, ext);
            if (!chord.pcs.includes(pc(n.pitch))) throw new Error(`track ${t} ${speed}x ${name}: ${n.pitch} at beat ${n.beat} not in chord ${chord.pcs}`);
          }
        }
      }
    }
  });

  test('no pitched note sustains across a chord change', () => {
    const d = new MusicDirector(standardLevel());
    for (const t of [0, 1, 3] as TapeIndex[]) {
      for (const speed of ALL_SPEEDS) {
        for (const [, extra] of VARIANTS) {
          for (const n of d.notes(t, v(speed, extra), 0, 32)) {
            const next = (Math.floor(n.beat / d.chordBeats + 1e-9) + 1) * d.chordBeats;
            expect(n.beat + n.duration).toBeLessThanOrEqual(next + 1e-9);
          }
        }
      }
    }
  });
});

describe('tape speeds stay aligned on the master grid (MUSIC-03)', () => {
  const d = new MusicDirector(standardLevel());
  const firstPerStep = (ns: LayerNote[]) => {
    const m = new Map<number, LayerNote>();
    for (const n of ns) if (!m.has(n.step) || m.get(n.step)!.beat > n.beat) m.set(n.step, n);
    return [...m.values()].sort((a, b) => a.beat - b.beat);
  };

  test('pitched onsets fall on the layer step grid, which nests by powers of two', () => {
    const local = { 0: 0.5, 1: 0.5, 3: 2 } as Record<number, number>;
    for (const t of [0, 1, 3] as TapeIndex[]) {
      for (const speed of ALL_SPEEDS) {
        const grid = local[t] / speed;
        for (const n of firstPerStep(d.notes(t, v(speed), 0, 32))) {
          expect(Math.abs(n.beat / grid - Math.round(n.beat / grid))).toBeLessThan(1e-6);
          // Even the fastest layer (4x eighths) lands on a 64th of the master grid.
          expect(Math.abs(n.beat * 16 - Math.round(n.beat * 16))).toBeLessThan(1e-6);
        }
      }
    }
  });

  test('a layer at 2s plays the same rhythm as at s, exactly twice as fast in master time', () => {
    for (const t of [0, 1, 2, 3] as TapeIndex[]) {
      for (const [slow, fast] of [
        [0.5, 1],
        [1, 2],
        [2, 4],
      ] as [TapeSpeed, TapeSpeed][]) {
        const a = firstPerStep(d.notes(t, v(slow), 0, 32));
        const b = firstPerStep(d.notes(t, v(fast), 0, 16));
        if (t === 2) {
          // Drums: every hit (kit lanes are step-locked, swing scales with the step).
          const all = (ns: LayerNote[], k: number) => ns.map((n) => [+(n.beat * k).toFixed(6), n.drum, n.velocity]).sort();
          expect(all(d.notes(t, v(fast), 0, 16), 2)).toEqual(all(d.notes(t, v(slow), 0, 32), 1));
        } else {
          expect(b.map((n) => [n.step, +(n.beat * 2).toFixed(6)])).toEqual(a.map((n) => [n.step, +n.beat.toFixed(6)]));
        }
      }
    }
  });
});

describe('state-driven composition (MUSIC-08, MUSIC-09, MUSIC-11)', () => {
  const d = new MusicDirector(standardLevel());
  const window = (t: TapeIndex, extra: Partial<LayerVariant>, speed: TapeSpeed = 1) => strip(d.notes(t, v(speed, extra), 0, 32));

  test('dead, desync, reverse and stopped each change the generated notes, not just the mix', () => {
    for (const t of [0, 1, 2, 3] as TapeIndex[]) {
      const base = window(t, {});
      for (const [name, extra] of VARIANTS.slice(1)) {
        expect(window(t, extra), `track ${t} ${name}`).not.toEqual(base);
      }
    }
  });

  test('death thins the layer and softens it', () => {
    for (const t of [0, 1, 2, 3] as TapeIndex[]) {
      const base = d.notes(t, v(1), 0, 32);
      const dead = d.notes(t, v(1, { dead: true }), 0, 32);
      expect(dead.length).toBeLessThan(base.length);
      const avg = (ns: LayerNote[]) => ns.reduce((s, n) => s + n.velocity, 0) / ns.length;
      expect(avg(dead)).toBeLessThan(avg(base));
    }
  });

  test('a dead melody falls onto chord tones', () => {
    for (const n of d.notes(0, v(1, { dead: true }), 0, 32)) expect(d.chordAt(n.beat).pcs).toContain(pc(n.pitch));
  });

  test('reverse is a retrograde contour on the same rhythm', () => {
    const base = d.notes(0, v(1), 0, 32);
    const rev = d.notes(0, v(1, { transport: -1 }), 0, 32);
    expect(rev.map((n) => n.beat)).toEqual(base.map((n) => n.beat));
    expect(rev.map((n) => n.pitch)).not.toEqual(base.map((n) => n.pitch));
  });

  test('stopped plays a sustained hold figure', () => {
    const hold = d.notes(0, v(1, { transport: 0 }), 0, 32);
    const base = d.notes(0, v(1), 0, 32);
    expect(hold.length).toBeLessThan(base.length / 2);
    expect(Math.min(...hold.map((n) => n.duration))).toBeGreaterThan(1);
  });

  test('desync drift pushes notes late by less than a step, never early', () => {
    const base = d.notes(0, v(2), 0, 32);
    const drift = d.notes(0, v(2, { drift: 1 }), 0, 32);
    const step = 0.5 / 2;
    expect(drift.map((n) => n.step)).toEqual(base.map((n) => n.step));
    drift.forEach((n, i) => {
      expect(n.beat).toBeGreaterThan(base[i].beat);
      expect(n.beat - base[i].beat).toBeLessThan(step * 0.25);
    });
  });

  test('desync drifts over bars and resync converges back to the exact baseline', () => {
    const t = (o: Partial<TrackAudioState>): TrackAudioState => ({ present: true, speed: 1, life: 'alive', synced: true, transport: 1, ...o });
    const tracks = (synced: boolean): [TrackAudioState, TrackAudioState, TrackAudioState, TrackAudioState] => [t({ synced }), t({}), t({ synced }), t({})];
    const base = new LayerSequencer(new MusicDirector(standardLevel()));
    base.setTracks(tracks(true), 0);
    const s = new LayerSequencer(new MusicDirector(standardLevel()));
    s.setTracks(tracks(true), 0);
    expect(s.setTracks(tracks(false), 8.5)).toBe(true);
    const drifts = [2, 3, 4, 5, 6].map((bar) => s.variantAt(0, bar)!.drift);
    expect(drifts).toEqual([0.25, 0.5, 0.75, 1, 1]);
    s.setTracks(tracks(true), 24.2);
    expect([6, 7, 8, 9].map((bar) => s.variantAt(0, bar)!.drift)).toEqual([1, 0.5, 0, 0]);
    // While drifting, the composition differs …
    expect(strip(s.collect(12, 24))).not.toEqual(strip(base.collect(12, 24)));
    // … and from bar 8 on (two bars after resync) it is the baseline again, note for note.
    expect(strip(s.collect(32, 64))).toEqual(strip(base.collect(32, 64)));
  });

  test('death is not desync: a ghost never drifts', () => {
    const s = new LayerSequencer(new MusicDirector(standardLevel()));
    const st: TrackAudioState = { present: true, speed: 1, life: 'ghost', synced: false, transport: 1 };
    s.setTracks([st, st, st, st], 0);
    expect(s.variantAt(0, 3)).toEqual({ speed: 1, dead: true, transport: 1, drift: 0 });
  });

  test('a layer is silent until its cassette is present', () => {
    const s = new LayerSequencer(new MusicDirector(standardLevel()));
    expect(s.collect(0, 16)).toEqual([]);
    const off: TrackAudioState = { present: false, speed: 1, life: 'alive', synced: true, transport: 1 };
    s.setTracks([{ ...off, present: true }, off, off, off], 0);
    const notes = s.collect(0, 16);
    expect(notes.length).toBeGreaterThan(0);
    expect(new Set(notes.map((n) => n.track))).toEqual(new Set([0]));
  });

  test('layers depend only on their own cassette state (enemies cannot touch them)', () => {
    const a = new LayerSequencer(new MusicDirector(standardLevel()));
    const b = new LayerSequencer(new MusicDirector(standardLevel()));
    const alive: TrackAudioState = { present: true, speed: 1, life: 'alive', synced: true, transport: 1 };
    a.setTracks([alive, alive, alive, alive], 0);
    b.setTracks([alive, { ...alive, life: 'ghost' }, alive, alive], 0);
    const only = (ns: LayerNote[], t: number) => strip(ns.filter((n) => n.track === t));
    for (const t of [0, 2, 3]) expect(only(b.collect(0, 32), t)).toEqual(only(a.collect(0, 32), t));
    expect(STANDARD_TRACKS.length).toBe(4);
  });
});
