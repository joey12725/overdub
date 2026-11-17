import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { createAudio } from '../../src/audio';
import { PulseMeter, silentPulse } from '../../src/audio/pulse';
import type { MusicPulse, TrackAudioState } from '../../src/contracts';
import { standardLevel } from './fixtures';

function expectPulseSane(p: MusicPulse) {
  for (const x of [p.beat, p.beatPulse, p.barPulse, p.chord, ...p.levels, ...p.pitches]) expect(Number.isFinite(x)).toBe(true);
  for (const x of [p.beatPulse, p.barPulse, ...p.levels, ...p.pitches]) {
    expect(x).toBeGreaterThanOrEqual(0);
    expect(x).toBeLessThanOrEqual(1);
  }
  expect(p.levels).toHaveLength(4);
  expect(p.pitches).toHaveLength(4);
}

const track = (o: Partial<TrackAudioState> = {}): TrackAudioState => ({ present: true, speed: 1, life: 'alive', synced: true, transport: 1, ...o });

describe('createAudio without Web Audio (node)', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['performance', 'Date', 'setInterval', 'clearInterval', 'setTimeout'] });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  test('every method is safe before unlock and with no AudioContext', async () => {
    const audio = createAudio();
    expectPulseSane(audio.pulse());
    await audio.unlock();
    audio.ui('select');
    audio.countIn(5);
    audio.onEvents([{ sub: 0, type: 'hit', x: 0, y: 0, tape: 0, power: 2 }]);
    audio.loadLevel(standardLevel());
    audio.setMode('cinematic');
    audio.setVolumes(0.5, 0.7, 0.9);
    audio.setVolumes(50, 70, 90);
    audio.setTracks([track(), track({ speed: 2 }), track({ life: 'ghost' }), track({ transport: -1 })]);
    audio.setTransport(0, 1, true);
    audio.onEvents([{ sub: 10, type: 'kill', x: 0, y: 0 }]);
    audio.countIn(8);
    expectPulseSane(audio.pulse());
    audio.dispose();
    audio.dispose();
    expectPulseSane(audio.pulse());
  });

  test('pulse follows the transport and what was scheduled', () => {
    const audio = createAudio();
    audio.loadLevel(standardLevel());
    audio.setTracks([track(), track(), track(), track({ present: false })]);
    let beat = 0;
    let sawLevel = [0, 0, 0, 0];
    let sawBeatPulse = false;
    let sawBarPulse = false;
    for (let f = 0; f < 600; f++) {
      vi.advanceTimersByTime(1000 / 60);
      beat += 2 / 60; // 120 bpm, rate 1
      audio.setTransport(beat, 1, true);
      const p = audio.pulse();
      expectPulseSane(p);
      expect(Math.abs(p.beat - beat)).toBeLessThan(0.1);
      sawLevel = sawLevel.map((x, i) => Math.max(x, p.levels[i]));
      if (p.beatPulse > 0.9) sawBeatPulse = true;
      if (p.barPulse > 0.9) sawBarPulse = true;
      expect(p.chord).toBe(Math.floor(beat / 4) % 4);
    }
    expect(sawLevel[0]).toBeGreaterThan(0.2);
    expect(sawLevel[1]).toBeGreaterThan(0.2);
    expect(sawLevel[2]).toBeGreaterThan(0.2);
    // A cassette that is not present makes no sound and so shows no level.
    expect(sawLevel[3]).toBe(0);
    expect(sawBeatPulse && sawBarPulse).toBe(true);
    // Pausing lets the levels decay to silence.
    audio.setTransport(beat, 0, false);
    vi.advanceTimersByTime(3000);
    const quiet = audio.pulse();
    expect(Math.max(...quiet.levels)).toBe(0);
    audio.dispose();
  });

  test('silentPulse and PulseMeter stay finite on odd input', () => {
    expectPulseSane(silentPulse(NaN, NaN));
    const m = new PulseMeter();
    m.add({ id: 1, time: 1, dur: 0.5, note: { track: 0, beat: 0, duration: 1, pitch: 60, velocity: 127, norm: 2, step: 0 } });
    expectPulseSane(m.sample(1.01, Infinity, 2));
    m.cancel([1]);
    expect(m.sample(1.02, 0, 0).levels[0]).toBe(0);
  });
});
