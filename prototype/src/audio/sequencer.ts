/**
 * LayerSequencer: which variant each cassette layer is in, bar by bar, and the merged note stream
 * the scheduler pulls from. Pure; no Web Audio.
 *
 * Desync drift needs memory (MUSIC-08, MUSIC-09, DESYNC): the drift grows while a self stays
 * desynced and converges back after resync, so the track state alone is not enough. Drift is a
 * deterministic function of the transitions seen on the master timeline, quantised per bar, so a
 * bar's notes can be compiled ahead of time and recompiled identically.
 */
import type { TapeIndex } from '../core/types';
import { BEATS_PER_BAR, TAPE_COUNT } from '../core/types';
import type { TrackAudioState } from '../contracts';
import type { LayerNote, LayerVariant, MusicDirector } from './director';

/** Drift added per bar while desynced (reaches full drift on the fourth bar). */
export const DRIFT_RISE_PER_BAR = 0.25;
/** Drift removed per bar after resync: the layer is exactly back on its baseline within two bars. */
export const DRIFT_FALL_PER_BAR = 0.5;

interface DriftSegment {
  desynced: boolean;
  sinceBar: number;
  /** Drift level in force at the moment of the transition. */
  from: number;
}

export class DesyncDrift {
  private seg: (DriftSegment | null)[] = [null, null, null, null];

  reset(): void {
    this.seg = [null, null, null, null];
  }

  /** Records the sync state of `track` at master `beat`. Returns true when it changed. */
  update(track: TapeIndex, desynced: boolean, beat: number): boolean {
    const cur = this.seg[track];
    if ((cur?.desynced ?? false) === desynced) return false;
    const bar = Math.max(0, Math.floor(beat / BEATS_PER_BAR));
    this.seg[track] = { desynced, sinceBar: bar, from: this.at(track, bar) };
    return true;
  }

  /** Drift level of `track` during master bar `bar`, in quarter steps 0..1. */
  at(track: TapeIndex, bar: number): number {
    const s = this.seg[track];
    if (!s) return 0;
    const elapsed = Math.max(0, bar - s.sinceBar);
    const level = s.desynced
      ? Math.min(1, s.from + DRIFT_RISE_PER_BAR * (elapsed + 1))
      : Math.max(0, s.from - DRIFT_FALL_PER_BAR * elapsed);
    return Math.round(level * 4) / 4;
  }
}

const SILENT: TrackAudioState = { present: false, speed: 1, life: 'alive', synced: true, transport: 1 };

function sameComposition(a: TrackAudioState, b: TrackAudioState): boolean {
  return a.present === b.present && a.speed === b.speed && a.life === b.life && a.synced === b.synced && a.transport === b.transport;
}

export class LayerSequencer {
  readonly drift = new DesyncDrift();
  private tracks: TrackAudioState[] = [SILENT, SILENT, SILENT, SILENT];

  constructor(readonly director: MusicDirector) {}

  /** Current per-track states (copies). */
  states(): TrackAudioState[] {
    return this.tracks.map((t) => ({ ...t }));
  }

  /**
   * Applies new track states at master `beat`. Returns true when the generated notes from now on
   * differ, so already-planned notes must be re-planned.
   */
  setTracks(tracks: readonly TrackAudioState[], beat: number): boolean {
    let changed = false;
    for (let i = 0; i < TAPE_COUNT; i++) {
      const t = tracks[i] ?? SILENT;
      const track = i as TapeIndex;
      const desynced = t.present && t.life === 'alive' && !t.synced;
      if (this.drift.update(track, desynced, beat)) changed = true;
      if (!sameComposition(t, this.tracks[i])) {
        changed = true;
        this.tracks[i] = { ...t };
      }
    }
    return changed;
  }

  /** Every take restarts at beat 0 with fresh selves: forget the old run's drift history. */
  restart(): void {
    this.drift.reset();
  }

  variantAt(track: TapeIndex, bar: number): LayerVariant | null {
    const t = this.tracks[track];
    if (!t.present) return null;
    const dead = t.life !== 'alive';
    return {
      speed: t.speed,
      dead,
      transport: t.transport,
      // Death and desync are distinct semantics: a ghost never drifts back to life (MUSIC-08).
      drift: dead ? 0 : this.drift.at(track, bar),
    };
  }

  /** All present layers' notes with onsets in [from, to), sorted by beat. */
  collect(from: number, to: number): LayerNote[] {
    const out: LayerNote[] = [];
    if (to <= from) return out;
    const firstBar = Math.max(0, Math.floor(from / BEATS_PER_BAR));
    for (let i = 0; i < TAPE_COUNT; i++) {
      const track = i as TapeIndex;
      for (let bar = firstBar; bar * BEATS_PER_BAR < to; bar++) {
        const v = this.variantAt(track, bar);
        if (!v) break;
        for (const n of this.director.barNotes(track, v, bar)) if (n.beat >= from - 1e-9 && n.beat < to - 1e-9) out.push(n);
      }
    }
    out.sort((a, b) => a.beat - b.beat || a.track - b.track || a.pitch - b.pitch);
    return out;
  }
}
