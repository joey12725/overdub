/**
 * MusicPulse from what was actually scheduled (MUSIC-12, MUSIC-13 visuals). Pure.
 *
 * Levels and pitches come from planned notes whose start time has passed on the listening clock,
 * not from the composition, so visuals never show a note that was cancelled or never played.
 */
import type { MusicPulse } from '../contracts';
import { BEATS_PER_BAR, TAPE_COUNT } from '../core/types';
import type { PlannedNote } from './scheduler';

/** Seconds for a layer level to decay to 1/e after a note. */
const LEVEL_DECAY = 0.22;
/** Notes older than this no longer contribute to levels. */
const HISTORY = 1.5;

export function silentPulse(beat = 0, chord = 0): MusicPulse {
  return {
    beat: Number.isFinite(beat) ? beat : 0,
    beatPulse: beatPulse(beat),
    barPulse: barPulse(beat),
    levels: [0, 0, 0, 0],
    pitches: [0.5, 0.5, 0.5, 0.5],
    chord: Number.isFinite(chord) ? chord : 0,
  };
}

const frac = (x: number) => x - Math.floor(x);

/** Saw that is 1 exactly on each beat and falls to 0 just before the next. */
export function beatPulse(beat: number): number {
  if (!Number.isFinite(beat)) return 0;
  return Math.min(1, Math.max(0, 1 - frac(beat)));
}

export function barPulse(beat: number): number {
  if (!Number.isFinite(beat)) return 0;
  return Math.min(1, Math.max(0, 1 - frac(beat / BEATS_PER_BAR)));
}

export class PulseMeter {
  private notes: PlannedNote[][] = [[], [], [], []];
  private lastPitch: number[] = [0.5, 0.5, 0.5, 0.5];
  private lastOnset: number[] = [-Infinity, -Infinity, -Infinity, -Infinity];

  add(p: PlannedNote): void {
    const list = this.notes[p.note.track];
    list.push(p);
    if (list.length > 256) list.splice(0, list.length - 192);
  }

  cancel(ids: Iterable<number>): void {
    const gone = new Set(ids);
    if (!gone.size) return;
    for (let t = 0; t < TAPE_COUNT; t++) this.notes[t] = this.notes[t].filter((p) => !gone.has(p.id));
  }

  clear(): void {
    this.notes = [[], [], [], []];
    this.lastPitch = [0.5, 0.5, 0.5, 0.5];
    this.lastOnset = [-Infinity, -Infinity, -Infinity, -Infinity];
  }

  /**
   * @param now   listening time on the clock notes were planned on (already latency-compensated)
   * @param beat  master beat to report
   * @param chord progression index at that beat
   */
  sample(now: number, beat: number, chord: number): MusicPulse {
    const levels: [number, number, number, number] = [0, 0, 0, 0];
    const pitches: [number, number, number, number] = [0.5, 0.5, 0.5, 0.5];
    for (let t = 0; t < TAPE_COUNT; t++) {
      const list = this.notes[t];
      let keepFrom = 0;
      let level = 0;
      let onset = this.lastOnset[t];
      let pitch = this.lastPitch[t];
      for (let i = 0; i < list.length; i++) {
        const p = list[i];
        if (p.time + p.dur < now - HISTORY) {
          keepFrom = i + 1;
          continue;
        }
        if (p.time > now) continue;
        const age = Math.max(0, now - p.time);
        const sustain = age < p.dur ? 0.35 : 0;
        const energy = (p.note.velocity / 127) * Math.max(Math.exp(-age / LEVEL_DECAY), sustain);
        if (energy > level) level = energy;
        // Chords start together: report the top voice of the latest onset.
        if (p.time > onset + 1e-6 || (Math.abs(p.time - onset) <= 1e-6 && p.note.norm > pitch)) {
          onset = p.time;
          pitch = p.note.norm;
        }
      }
      if (keepFrom) list.splice(0, keepFrom);
      this.lastOnset[t] = onset;
      this.lastPitch[t] = pitch;
      levels[t] = Math.min(1, Math.max(0, level));
      pitches[t] = Math.min(1, Math.max(0, Number.isFinite(pitch) ? pitch : 0.5));
    }
    const safeBeat = Number.isFinite(beat) ? beat : 0;
    return {
      beat: safeBeat,
      beatPulse: beatPulse(safeBeat),
      barPulse: barPulse(safeBeat),
      levels,
      pitches,
      chord: Number.isFinite(chord) ? chord : 0,
    };
  }
}
