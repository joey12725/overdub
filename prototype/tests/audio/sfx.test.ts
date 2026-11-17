import { describe, expect, test } from 'vitest';
import type { SimEvent, SimEventType } from '../../src/core/types';
import { SUB_HZ } from '../../src/core/types';
import { MusicDirector } from '../../src/audio/director';
import { AUDIBLE_EVENTS, chordTone, quantizeLate, SfxPlanner, sfxGrid, subToMasterBeat, type SfxClock } from '../../src/audio/sfx';
import { standardLevel } from './fixtures';

const BPM = 120;
const subOf = (beat: number) => Math.round((beat * 60 * SUB_HZ) / BPM);
const clockAt = (beat: number, rate: number, now = 5): SfxClock => ({ now, beat, rate, playing: true, bpm: BPM });

describe('SFX quantisation: late only, at most one sixteenth (MUSIC-05, MUSIC-07)', () => {
  test('the grid is the master sixteenth, subdivided by the world slow-down', () => {
    expect(sfxGrid(1)).toBe(0.25);
    expect(sfxGrid(2)).toBe(0.25);
    expect(sfxGrid(0.5)).toBe(0.125);
    expect(sfxGrid(0.25)).toBe(0.0625);
  });

  test('never early and never more than one heard sixteenth late, at every world rate', () => {
    const baseSixteenth = 60 / BPM / 4;
    for (const rate of [0.25, 0.5, 1, 2]) {
      const masterSixteenthWall = 0.25 / (rate * (BPM / 60));
      for (let i = 0; i < 400; i++) {
        const eventBeat = subToMasterBeat(subOf(i * 0.0371), BPM);
        const q = quantizeLate(eventBeat, clockAt(eventBeat, rate));
        expect(q.delay).toBeGreaterThanOrEqual(0);
        expect(q.beat).toBeGreaterThanOrEqual(eventBeat - 1e-9);
        expect(q.beat - eventBeat).toBeLessThanOrEqual(sfxGrid(rate) + 1e-9);
        expect(q.lateness).toBeLessThanOrEqual(Math.min(baseSixteenth, masterSixteenthWall) + 1e-9);
        // It lands exactly on the grid.
        expect(Math.abs(q.beat / sfxGrid(rate) - Math.round(q.beat / sfxGrid(rate)))).toBeLessThan(1e-6);
      }
    }
  });

  test('an event a frame in the past only waits for what is left of its sixteenth', () => {
    const q = quantizeLate(1.05, clockAt(1.1, 1));
    expect(q.beat).toBe(1.25);
    expect(q.delay).toBeCloseTo(0.15 / 2, 9);
    expect(q.lateness).toBeCloseTo(0.2 / 2, 9);
    const old = quantizeLate(1.05, clockAt(1.4, 1));
    expect(old.delay).toBe(0);
  });

  test('with the transport stopped sounds are immediate', () => {
    expect(quantizeLate(3.1, { now: 1, beat: 3.1, rate: 0, playing: false, bpm: BPM }).delay).toBe(0);
  });
});

describe('SfxPlanner', () => {
  const d = new MusicDirector(standardLevel());
  const ev = (type: SimEventType, beat: number, o: Partial<SimEvent> = {}): SimEvent => ({ sub: subOf(beat), type, x: 0, y: 0, ...o });
  const ALL: SimEventType[] = [
    'step', 'swing', 'hit', 'kill', 'break', 'clang', 'dodge', 'fire', 'projectileHit', 'interact', 'interactFail', 'door', 'plate',
    'laser', 'core', 'selfDeath', 'desync', 'resync', 'tapeWrap', 'tapeTurn', 'tapeEnd', 'enemyTelegraph', 'enemyAttack',
    'enemyShot', 'enemyStagger', 'bossPhase', 'bossRecall', 'objective',
  ];

  test('every gameplay event type in the brief is audible; whiff is deliberately silent', () => {
    for (const t of ALL) expect(AUDIBLE_EVENTS).toContain(t);
    expect(AUDIBLE_EVENTS).not.toContain('whiff');
    const p = new SfxPlanner();
    expect(p.plan([ev('whiff', 1, { tape: 0 })], clockAt(1, 1), d)).toEqual([]);
  });

  test('cue pitches are in the level scale and drawn from the chord at the accent', () => {
    const scale = new Set(d.scalePcs);
    let n = 0;
    for (const t of ALL) {
      const p = new SfxPlanner();
      for (const beat of [0.1, 4.3, 9.7, 13.2]) {
        for (const cue of p.plan([ev(t, beat, { tape: 1, power: 5, detail: 'heavy' })], clockAt(beat, 1), d)) {
          for (const pitch of cue.pitches) {
            expect(scale.has(((pitch % 12) + 12) % 12)).toBe(true);
            n++;
          }
          if (cue.kind !== 'transient') {
            const chord = d.chordAt(Math.ceil(beat * 4) / 4);
            for (const pitch of cue.pitches) expect(chord.pcs).toContain(((pitch % 12) + 12) % 12);
          }
        }
      }
    }
    expect(n).toBeGreaterThan(100);
  });

  test('impacts get an immediate soft transient when their accent is delayed', () => {
    const p = new SfxPlanner();
    const cues = p.plan([ev('hit', 2.03, { tape: 0, power: 3 })], clockAt(2.03, 1), d);
    const transient = cues.find((c) => c.kind === 'transient')!;
    const hit = cues.find((c) => c.kind === 'hit')!;
    expect(transient.time).toBe(5);
    expect(transient.gain).toBeLessThan(hit.gain);
    expect(hit.time).toBeGreaterThan(5);
    // On the grid already: no separate transient.
    const onGrid = new SfxPlanner().plan([ev('hit', 2.0, { tape: 0 })], clockAt(2.0, 1), d);
    expect(onGrid.some((c) => c.kind === 'transient')).toBe(false);
  });

  test('hits scale with power', () => {
    const soft = new SfxPlanner().plan([ev('hit', 1, { tape: 0, power: 0.5 })], clockAt(1, 1), d)[0];
    const hard = new SfxPlanner().plan([ev('hit', 1, { tape: 0, power: 20 })], clockAt(1, 1), d)[0];
    expect(hard.gain).toBeGreaterThan(soft.gain);
  });

  test('four selves stepping at once become one step; four selves striking spell the chord', () => {
    const p = new SfxPlanner();
    const steps = [0, 1, 2, 3].map((tape) => ev('step', 3.01 + tape * 0.01, { tape: tape as 0 | 1 | 2 | 3 }));
    const stepCues = p.plan(steps, clockAt(3.05, 1), d);
    expect(stepCues.length).toBe(1);
    expect(stepCues[0].count).toBe(4);
    const hits = [0, 1, 2, 3].map((tape) => ev('hit', 5.01, { tape: tape as 0 | 1 | 2 | 3, power: 2 }));
    const hitCues = new SfxPlanner().plan(hits, clockAt(5.01, 1), d).filter((c) => c.kind === 'hit');
    expect(hitCues.length).toBe(4);
    expect(new Set(hitCues.map((c) => c.pitches[0])).size).toBeGreaterThanOrEqual(3);
  });

  test('repeats across frames are rate-limited', () => {
    const p = new SfxPlanner();
    let total = 0;
    for (let f = 0; f < 60; f++) {
      const beat = f / 30;
      total += p.plan([ev('step', beat, { tape: 0 }), ev('step', beat, { tape: 1 })], clockAt(beat, 1, 5 + f / 60), d).length;
    }
    // 60 frames x 2 selves = 120 step events in one second; the grid + limiter keep it musical.
    expect(total).toBeLessThanOrEqual(15);
    expect(total).toBeGreaterThanOrEqual(8);
  });

  test('chordTone stacks tones upward from the root', () => {
    const c = { index: 0, degree: 0, root: 9, pcs: [9, 0, 4] };
    expect([0, 1, 2, 3].map((i) => chordTone(c, i, 4))).toEqual([69, 72, 76, 81]);
  });
});
