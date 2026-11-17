/**
 * Look-ahead scheduler that follows the simulation's master transport. Pure: it is driven with an
 * explicit clock (`now`, seconds on whatever clock the caller plays notes on) and returns what to
 * start and what to cancel, so it is testable without Web Audio.
 *
 * The caller reports `(masterBeat, rate, playing)` every frame, where `rate` is master seconds per
 * wall second. Master beats therefore advance at `rate · bpm / 60` per wall second and a note at
 * master beat `b` is due `(b − masterBeat) / (rate · bpm / 60)` seconds from now; its length scales
 * the same way. While recording at tape speed `s` the world runs at `rate = 1/s` and the active
 * layer's step length is `localRate / s` master beats (see director.ts), so its steps last
 * `localRate / (bpm/60)` wall seconds: the active cassette is heard at the level's base tempo and
 * the others at `speed_j / s` of it, with no special case needed here.
 *
 * Rules that keep notes from sticking or doubling:
 *   - only notes not yet started (`time > now`) are ever cancelled; started notes are left to end;
 *   - every planned note is remembered by identity, so re-planning a window never plays it twice;
 *   - a backwards jump (every take restarts at beat 0), a seek, a pause or a rate change cancels the
 *     unstarted notes and re-plans from the current beat; jumps and pauses also ask the caller to
 *     choke sounding notes (`choke`).
 */
import type { LayerNote } from './director';

export interface PlannedNote {
  id: number;
  note: LayerNote;
  /** Start time on the caller's clock (seconds). */
  time: number;
  /** Length in seconds. */
  dur: number;
}

export interface SchedulerUpdate {
  start: PlannedNote[];
  cancel: PlannedNote[];
  /** Sounding notes belong to a timeline position that no longer exists: release them quickly. */
  choke: boolean;
}

export interface SchedulerOptions {
  bpm: number;
  /** Seconds of notes kept planned ahead of `now`. */
  lookahead?: number;
  /** A discrepancy between the reported and the predicted beat larger than this (seconds) is a seek. */
  jumpTolerance?: number;
  /** Notes up to this many seconds late are still played (immediately); older ones are skipped. */
  lateTolerance?: number;
  /** Longest wall-time note (seconds); keeps very slow world rates from producing endless drones. */
  maxDuration?: number;
}

export type NoteSource = (fromBeat: number, toBeat: number) => LayerNote[];

const noteKey = (n: LayerNote) => `${n.track}|${n.beat.toFixed(6)}|${n.pitch}|${n.drum ?? ''}`;

export class TransportScheduler {
  readonly lookahead: number;
  private readonly bps: number;
  private readonly jumpTolerance: number;
  private readonly lateTolerance: number;
  private readonly maxDuration: number;
  private pending: PlannedNote[] = [];
  private planned = new Map<string, PlannedNote>();
  private cursor = 0;
  private nextId = 1;
  private last: { now: number; beat: number; rate: number; playing: boolean } | null = null;

  constructor(
    private readonly source: NoteSource,
    opts: SchedulerOptions,
  ) {
    this.bps = opts.bpm / 60;
    this.lookahead = opts.lookahead ?? 0.12;
    this.jumpTolerance = opts.jumpTolerance ?? 0.1;
    this.lateTolerance = opts.lateTolerance ?? 0.03;
    this.maxDuration = opts.maxDuration ?? 8;
  }

  /** Master beats per second of the caller's clock at `rate`. */
  beatsPerSecond(rate: number): number {
    return rate * this.bps;
  }

  /** Where the transport is predicted to be at `now`, from the last update. */
  predictBeat(now: number): number | null {
    const l = this.last;
    if (!l) return null;
    return l.playing ? l.beat + (now - l.now) * l.rate * this.bps : l.beat;
  }

  /** Planned but not yet started notes (for inspection / tests). */
  get upcoming(): readonly PlannedNote[] {
    return this.pending;
  }

  /** Forget everything (e.g. the note clock changed); returns the notes the caller must cancel. */
  reset(): PlannedNote[] {
    const cancelled = this.pending;
    this.pending = [];
    this.planned.clear();
    this.last = null;
    return cancelled;
  }

  /**
   * The music from the current position on has changed (layer states changed): cancel unstarted
   * notes and re-plan them on the next update. Started notes keep their identity, so nothing that
   * already sounded is played again.
   */
  invalidate(now: number): PlannedNote[] {
    const cancelled = this.cancelUnstarted(now);
    const at = this.predictBeat(now);
    if (at !== null) this.cursor = Math.min(this.cursor, at);
    return cancelled;
  }

  update(now: number, beat: number, rate: number, playing: boolean): SchedulerUpdate {
    const result: SchedulerUpdate = { start: [], cancel: [], choke: false };
    const running = playing && rate > 0 && Number.isFinite(rate) && Number.isFinite(beat);
    const prev = this.last;
    this.retireStarted(now);

    if (!running) {
      if (prev?.playing) {
        result.cancel = this.cancelUnstarted(now);
        result.choke = true;
      }
      this.last = { now, beat: Number.isFinite(beat) ? beat : 0, rate: 0, playing: false };
      this.cursor = this.last.beat;
      return result;
    }

    const bpsNow = rate * this.bps;
    const lateBeats = this.lateTolerance * bpsNow;
    if (!prev || !prev.playing) {
      // Starting (or resuming): a downbeat that is a few milliseconds behind still sounds.
      this.cursor = beat - lateBeats;
      // Resuming where we paused keeps the record of what already sounded; only a seek while
      // paused (or a restart at 0) makes the same beats playable again.
      if (prev && (beat < prev.beat - 1e-6 || beat - prev.beat > this.jumpTolerance * bpsNow)) this.forgetPlanned();
    } else {
      const predicted = prev.beat + (now - prev.now) * prev.rate * this.bps;
      const errorSeconds = Math.abs(beat - predicted) / bpsNow;
      if (errorSeconds > this.jumpTolerance) {
        // A seek: every take jumps back to beat 0, reviews can be skipped.
        result.cancel = this.cancelUnstarted(now);
        result.choke = true;
        this.forgetPlanned();
        this.cursor = beat - lateBeats;
      } else if (Math.abs(rate - prev.rate) > 1e-6 * Math.max(1, prev.rate)) {
        // Unstarted notes were timed for the old rate; re-plan them for the new one.
        result.cancel = this.cancelUnstarted(now);
        this.cursor = Math.min(this.cursor, beat);
      }
    }

    // Fell behind (a long frame): skip what is too late rather than playing a burst of old notes.
    if (this.cursor < beat - lateBeats) this.cursor = beat - lateBeats;
    const horizon = beat + this.lookahead * bpsNow;
    if (horizon > this.cursor) {
      for (const note of this.source(this.cursor, horizon)) {
        const key = noteKey(note);
        if (this.planned.has(key)) continue;
        const time = Math.max(now, now + (note.beat - beat) / bpsNow);
        const dur = Math.min(this.maxDuration, Math.max(0.01, note.duration / bpsNow));
        const p: PlannedNote = { id: this.nextId++, note, time, dur };
        this.planned.set(key, p);
        this.pending.push(p);
        result.start.push(p);
      }
      this.cursor = horizon;
    }
    this.prunePlanned(beat);
    this.last = { now, beat, rate, playing: true };
    return result;
  }

  private retireStarted(now: number): void {
    if (this.pending.some((p) => p.time <= now)) this.pending = this.pending.filter((p) => p.time > now);
  }

  private cancelUnstarted(now: number): PlannedNote[] {
    const cancelled: PlannedNote[] = [];
    const kept: PlannedNote[] = [];
    for (const p of this.pending) (p.time > now ? cancelled : kept).push(p);
    this.pending = kept;
    for (const p of cancelled) this.planned.delete(noteKey(p.note));
    return cancelled;
  }

  /** After a seek the same beats can legitimately play again. */
  private forgetPlanned(): void {
    this.planned.clear();
    for (const p of this.pending) this.planned.set(noteKey(p.note), p);
  }

  private prunePlanned(beat: number): void {
    if (this.planned.size < 512) return;
    for (const [k, p] of this.planned) if (p.note.beat < beat - 8) this.planned.delete(k);
  }
}
