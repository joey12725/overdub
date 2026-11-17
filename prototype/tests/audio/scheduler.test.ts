import { describe, expect, test } from 'vitest';
import type { LayerNote } from '../../src/audio/director';
import { MusicDirector } from '../../src/audio/director';
import { TransportScheduler, type PlannedNote } from '../../src/audio/scheduler';
import { LayerSequencer } from '../../src/audio/sequencer';
import type { TrackAudioState } from '../../src/contracts';
import { standardLevel } from './fixtures';

const BPM = 120;
const BPS = BPM / 60;

/** One note on every sixteenth of track 0. */
function gridSource(from: number, to: number): LayerNote[] {
  const out: LayerNote[] = [];
  for (let k = Math.max(0, Math.ceil(from * 4 - 1e-9)); k / 4 < to - 1e-9; k++) {
    out.push({ track: 0, beat: k / 4, duration: 0.2, pitch: 60, velocity: 100, norm: 0.5, step: k });
  }
  return out;
}

/** Drives a scheduler like the game loop: 60 frames per second, beat from the sim. */
class Harness {
  now = 10;
  beat = 0;
  live = new Map<number, PlannedNote>();
  log: PlannedNote[] = [];
  chokes = 0;
  constructor(readonly s: TransportScheduler) {}
  frame(rate: number, playing = true, dt = 1 / 60) {
    this.now += dt;
    if (playing) this.beat += dt * rate * BPS;
    this.apply(this.s.update(this.now, this.beat, rate, playing));
  }
  apply(u: ReturnType<TransportScheduler['update']>) {
    for (const c of u.cancel) {
      expect(c.time).toBeGreaterThan(this.now);
      this.live.delete(c.id);
      this.log = this.log.filter((p) => p.id !== c.id);
    }
    if (u.choke) this.chokes++;
    for (const p of u.start) {
      this.live.set(p.id, p);
      this.log.push(p);
    }
  }
  jump(beat: number, rate: number) {
    this.beat = beat;
    this.now += 1 / 60;
    this.apply(this.s.update(this.now, this.beat, rate, true));
  }
  /** Notes that really play (planned and never cancelled), by beat. */
  played(fromTime = -Infinity) {
    return this.log.filter((p) => p.time >= fromTime).map((p) => p.note.beat);
  }
}

describe('TransportScheduler (look-ahead on the audio clock)', () => {
  test('plays every note exactly once at the right time at a steady rate', () => {
    const h = new Harness(new TransportScheduler(gridSource, { bpm: BPM }));
    for (let i = 0; i < 240; i++) h.frame(1);
    const beats = h.played();
    expect(new Set(beats).size).toBe(beats.length);
    expect(beats.slice(0, 20)).toEqual(Array.from({ length: 20 }, (_, k) => k / 4));
    for (const p of h.log) {
      // The note is due when the transport reaches its beat (start was 10 s, beat 0).
      const due = 10 + p.note.beat / BPS;
      expect(Math.abs(p.time - Math.max(due, p.time))).toBeLessThan(1e-9);
      expect(p.time - due).toBeLessThan(1 / 60 + 1e-9);
    }
    // Planned no further ahead than the look-ahead.
    expect(Math.max(...h.log.map((p) => p.note.beat))).toBeLessThanOrEqual(h.beat + 0.12 * BPS + 1e-9);
  });

  test('note durations scale with the transport rate', () => {
    const slow = new Harness(new TransportScheduler(gridSource, { bpm: BPM }));
    const fast = new Harness(new TransportScheduler(gridSource, { bpm: BPM }));
    for (let i = 0; i < 30; i++) {
      slow.frame(0.25);
      fast.frame(2);
    }
    expect(slow.log[0].dur).toBeCloseTo(0.2 / (0.25 * BPS), 9);
    expect(fast.log[0].dur).toBeCloseTo(0.2 / (2 * BPS), 9);
  });

  test('follows rate changes without gaps or duplicates', () => {
    const h = new Harness(new TransportScheduler(gridSource, { bpm: BPM }));
    const rates = [1, 0.25, 2, 0.5, 4, 1];
    for (const r of rates) for (let i = 0; i < 50; i++) h.frame(r);
    const beats = h.played().sort((a, b) => a - b);
    expect(new Set(beats).size).toBe(beats.length);
    const expected = Array.from({ length: Math.floor(h.beat * 4) + 1 }, (_, k) => k / 4);
    // Everything up to where the transport is now has been planned, once.
    expect(beats.filter((b) => b <= h.beat)).toEqual(expected.filter((b) => b <= h.beat));
    // Times are monotonic in beat, so no note was timed for a stale rate.
    const byBeat = [...h.log].sort((a, b) => a.note.beat - b.note.beat);
    for (let i = 1; i < byBeat.length; i++) expect(byBeat[i].time).toBeGreaterThanOrEqual(byBeat[i - 1].time - 1e-9);
  });

  test('a jump back to beat 0 (new take) cancels unplayed notes, chokes, and restarts cleanly', () => {
    const h = new Harness(new TransportScheduler(gridSource, { bpm: BPM }));
    for (let i = 0; i < 100; i++) h.frame(1);
    const before = h.log.length;
    const chokes = h.chokes;
    const jumpTime = h.now + 1 / 60;
    h.jump(0, 1);
    expect(h.chokes).toBe(chokes + 1);
    for (const p of h.live.values()) if (p.time > jumpTime) expect(p.note.beat).toBeLessThan(1);
    for (let i = 0; i < 100; i++) h.frame(1);
    const after = h.played(jumpTime);
    expect(after[0]).toBe(0);
    expect(new Set(after).size).toBe(after.length);
    expect(after).toEqual(Array.from({ length: after.length }, (_, k) => k / 4));
    expect(before).toBeGreaterThan(0);
  });

  test('a forward seek skips ahead instead of bursting the skipped notes', () => {
    const h = new Harness(new TransportScheduler(gridSource, { bpm: BPM }));
    for (let i = 0; i < 30; i++) h.frame(1);
    const t = h.now + 1 / 60;
    h.jump(40, 1);
    for (let i = 0; i < 10; i++) h.frame(1);
    const after = h.played(t);
    expect(Math.min(...after)).toBeGreaterThanOrEqual(40 - 0.1);
  });

  test('pause cancels planned notes and resume continues without repeats', () => {
    const h = new Harness(new TransportScheduler(gridSource, { bpm: BPM }));
    for (let i = 0; i < 60; i++) h.frame(1);
    h.frame(1, false);
    expect(h.chokes).toBe(1);
    for (const p of h.log) expect(p.time).toBeLessThanOrEqual(h.now + 1e-9);
    for (let i = 0; i < 30; i++) h.frame(1, false);
    for (let i = 0; i < 60; i++) h.frame(1);
    const beats = h.played();
    expect(new Set(beats).size).toBe(beats.length);
    const sorted = [...beats].sort((a, b) => a - b);
    expect(sorted.filter((b) => b <= h.beat)).toEqual(Array.from({ length: Math.floor(h.beat * 4) + 1 }, (_, k) => k / 4));
  });

  test('invalidation (layer state change) re-plans upcoming notes without doubling started ones', () => {
    const level = standardLevel();
    const seq = new LayerSequencer(new MusicDirector(level));
    const st = (o: Partial<TrackAudioState> = {}): TrackAudioState => ({ present: true, speed: 1, life: 'alive', synced: true, transport: 1, ...o });
    seq.setTracks([st(), st(), st(), st()], 0);
    const s = new TransportScheduler((a, b) => seq.collect(a, b), { bpm: level.bpm });
    const h = new Harness(s);
    for (let i = 0; i < 200; i++) {
      h.frame(1);
      if (i === 90) {
        seq.setTracks([st({ life: 'ghost' }), st(), st({ synced: false }), st({ transport: -1 })], h.beat);
        for (const c of s.invalidate(h.now)) {
          h.live.delete(c.id);
          h.log = h.log.filter((p) => p.id !== c.id);
        }
      }
    }
    const keys = h.log.map((p) => `${p.note.track}|${p.note.beat}|${p.note.pitch}|${p.note.drum ?? ''}`);
    expect(new Set(keys).size).toBe(keys.length);
    // Every note of the composition actually in force was planned.
    const end = h.beat - 0.1;
    const wantAfter = seq.collect(h.log.find((p) => p.time > 10 + 91 / 60)!.note.beat, end).length;
    const gotAfter = h.log.filter((p) => p.note.beat >= h.log.find((q) => q.time > 10 + 91 / 60)!.note.beat && p.note.beat < end).length;
    expect(gotAfter).toBe(wantAfter);
  });

  test('a stalled frame loop does not replay a backlog', () => {
    const h = new Harness(new TransportScheduler(gridSource, { bpm: BPM }));
    for (let i = 0; i < 20; i++) h.frame(1);
    h.frame(1, true, 1.5); // 1.5 s hitch: beat advanced 3 beats
    const late = h.log.filter((p) => p.note.beat < h.beat - 0.1);
    const beforeHitch = 20 / 60 * BPS + 0.12 * BPS;
    expect(late.every((p) => p.note.beat <= beforeHitch + 1e-9)).toBe(true);
  });
});
