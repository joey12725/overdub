import { describe, expect, it } from 'vitest';
import {
  ALL_SPEEDS,
  BEATS_PER_BAR,
  LOCAL_HZ,
  type ActionKind,
  type DeckStatus,
  type LifeState,
  type SessionAction,
  type TapeSpeed,
} from '../../src/core/types';
import {
  barLabelStep,
  deckPresentation,
  decisionOptions,
  endModeInfo,
  formatSpeed,
  formatWorldRate,
  laneLayout,
  lifeBadge,
  localTickToMasterBeat,
  masterPositionText,
  placeMarks,
  promptFor,
  recordingTicks,
  recordingTimeLeft,
  reelSpin,
  spanCopy,
  spanScaleFill,
  speedConsequence,
  statusBadge,
  tapePackRadii,
  transportBadge,
  traversalAt,
  traversalBeats,
  HUD_BINDINGS,
} from '../../src/ui/hud/model';

const BPM = 120; // 30 local ticks per beat at 1×
const BARS = 4;

describe('tick → master beat mapping (TIME-03)', () => {
  it('maps a local tick through the tape speed at every speed', () => {
    const ticksPerBeat = (60 * LOCAL_HZ) / BPM; // 30
    for (const s of ALL_SPEEDS) {
      // One local beat of a tape at speed s occupies 1/s master beats.
      expect(localTickToMasterBeat(ticksPerBeat, s, BPM)).toBeCloseTo(1 / s, 12);
      expect(localTickToMasterBeat(0, s, BPM)).toBe(0);
    }
    expect(localTickToMasterBeat(90, 0.5, BPM)).toBeCloseTo(6);
    expect(localTickToMasterBeat(90, 1, BPM)).toBeCloseTo(3);
    expect(localTickToMasterBeat(90, 2, BPM)).toBeCloseTo(1.5);
    expect(localTickToMasterBeat(90, 4, BPM)).toBeCloseTo(0.75);
  });

  it('the last recorded tick lands exactly on the end of one traversal', () => {
    const ticks = recordingTicks(BARS, BPM);
    expect(ticks).toBe(480);
    for (const s of ALL_SPEEDS) {
      expect(localTickToMasterBeat(ticks, s, BPM)).toBeCloseTo(traversalBeats(BARS, s), 9);
      expect(traversalBeats(BARS, s)).toBe((BARS * BEATS_PER_BAR) / s);
    }
  });

  it('works for a tempo where a beat is a non-power-of-two tick count', () => {
    // 3600 / 90 = 40 ticks per beat.
    expect(localTickToMasterBeat(40, 1, 90)).toBeCloseTo(1);
    expect(localTickToMasterBeat(40, 2, 90)).toBeCloseTo(0.5);
  });
});

describe('lane segment layout against a horizon', () => {
  const H = 32; // 8 master bars

  it('stop: one pass then a hold to the horizon', () => {
    const l = laneLayout(8, 'stop', H);
    expect(l.segments).toEqual([{ start: 0, end: 8, traversal: 0, dir: 1, partial: false }]);
    expect(l.holdFrom).toBe(8);
  });

  it('stop: no hold when one pass reaches the horizon', () => {
    expect(laneLayout(32, 'stop', H).holdFrom).toBeNull();
    const longer = laneLayout(40, 'stop', H);
    expect(longer.segments).toEqual([{ start: 0, end: 32, traversal: 0, dir: 1, partial: true }]);
    expect(longer.holdFrom).toBeNull();
  });

  it('repeat: back-to-back forward passes tiling the horizon', () => {
    const l = laneLayout(8, 'repeat', H);
    expect(l.segments.map((s) => [s.start, s.end, s.dir, s.traversal])).toEqual([
      [0, 8, 1, 0],
      [8, 16, 1, 1],
      [16, 24, 1, 2],
      [24, 32, 1, 3],
    ]);
    expect(l.holdFrom).toBeNull();
  });

  it('reverse: ping-pong directions, last pass cut by the horizon', () => {
    const l = laneLayout(12, 'reverse', H);
    expect(l.segments.map((s) => [s.start, s.end, s.dir, s.partial])).toEqual([
      [0, 12, 1, false],
      [12, 24, -1, false],
      [24, 32, 1, true],
    ]);
  });

  it('degenerate spans produce nothing and never loop forever', () => {
    expect(laneLayout(0, 'repeat', H).segments).toEqual([]);
    expect(laneLayout(8, 'repeat', 0).segments).toEqual([]);
    expect(laneLayout(1e-6, 'repeat', H).segments.length).toBeLessThanOrEqual(512);
  });
});

describe('placing action marks on the master timeline', () => {
  const marks: { tick: number; kind: ActionKind }[] = [
    { tick: 30, kind: 'light' },
    { tick: 150, kind: 'heavy' },
  ];
  const H = 32;

  it('stop places marks once', () => {
    const l = laneLayout(traversalBeats(BARS, 1), 'stop', H);
    const p = placeMarks(marks, 1, BPM, l);
    expect(p.map((m) => [m.beat, m.kind])).toEqual([
      [1, 'light'],
      [5, 'heavy'],
    ]);
  });

  it('repeat re-fires each mark on every pass at every speed', () => {
    for (const s of ALL_SPEEDS) {
      const span = traversalBeats(BARS, s);
      const l = laneLayout(span, 'repeat', H);
      const p = placeMarks(marks, s, BPM, l);
      expect(p.length).toBe(l.segments.reduce((n, seg) => n + marks.filter((m) => seg.start + m.tick / 30 / s <= seg.end + 1e-9).length, 0));
      for (const m of p) {
        const local = m.beat - m.traversal * span;
        expect([1 / s, 5 / s].some((b) => Math.abs(b - local) < 1e-9)).toBe(true);
        expect(m.dir).toBe(1);
      }
    }
  });

  it('reverse passes mirror marks from the far end of the traversal', () => {
    const span = traversalBeats(BARS, 2); // 8 master beats
    const l = laneLayout(span, 'reverse', H);
    const p = placeMarks(marks, 2, BPM, l);
    const second = p.filter((m) => m.traversal === 1).map((m) => m.beat);
    // forward pass: 0.5 and 2.5; backward pass from 8: 16-0.5 = 15.5 and 16-2.5 = 13.5
    expect(p.filter((m) => m.traversal === 0).map((m) => m.beat)).toEqual([0.5, 2.5]);
    expect(second.sort((a, b) => a - b)).toEqual([13.5, 15.5]);
    expect(p.filter((m) => m.traversal === 1).every((m) => m.dir === -1)).toBe(true);
  });

  it('marks past the horizon are dropped', () => {
    const l = laneLayout(16, 'repeat', 18); // 0.5× of 2 local bars: second pass is cut at 18
    const p = placeMarks(marks, 1, BPM, l);
    expect(p.every((m) => m.beat <= 18)).toBe(true);
    expect(p.map((m) => m.beat)).toEqual([1, 5, 17]);
  });

  it('traversalAt counts passes', () => {
    expect(traversalAt(0, 8)).toBe(0);
    expect(traversalAt(7.99, 8)).toBe(0);
    expect(traversalAt(8, 8)).toBe(1);
    expect(traversalAt(17, 8)).toBe(2);
  });
});

describe('status / state tables (NEW-08, NEW-11)', () => {
  const statuses: DeckStatus[] = ['unavailable', 'empty', 'armed', 'recording', 'pending', 'committed'];
  const lives: (LifeState | null)[] = [null, 'alive', 'recGhost', 'ghost'];

  it('every status has its own word and icon', () => {
    const labels = new Set(statuses.map((s) => statusBadge(s).label));
    const icons = new Set(statuses.map((s) => statusBadge(s).icon));
    expect(labels.size).toBe(statuses.length);
    expect(icons.size).toBe(statuses.length);
    expect(statusBadge('empty').label).toBe('NOT RECORDED');
    expect(statusBadge('pending').label).toBe('TAKE — NOT COMMITTED');
    expect(statusBadge('committed').icon).toBe('lock');
    expect(statusBadge('recording').label).toBe('RECORDING');
  });

  it('every status × life × synced combination is presented distinctly', () => {
    const keys = new Map<string, string>();
    for (const s of statuses)
      for (const l of lives)
        for (const sy of [true, false]) {
          const p = deckPresentation(s, l, sy);
          expect(p.status.label.length).toBeGreaterThan(0);
          if (l === null) {
            // No self in the run: sync has no meaning, nothing extra is shown.
            expect(p.state).toBeNull();
            continue;
          }
          expect(p.state).not.toBeNull();
          const id = `${s}/${l}/${sy}`;
          expect(keys.has(p.key), `${id} collides with ${keys.get(p.key)}`).toBe(false);
          keys.set(p.key, id);
        }
    expect(keys.size).toBe(statuses.length * 3 * 2);
  });

  it('life states never rely on colour alone: distinct word + icon per state', () => {
    const combos: [LifeState, boolean][] = [
      ['alive', true],
      ['alive', false],
      ['recGhost', true],
      ['recGhost', false],
      ['ghost', true],
      ['ghost', false],
    ];
    const words = new Set(combos.map(([l, s]) => lifeBadge(l, s)!.label));
    expect(words.size).toBe(combos.length);
    expect(lifeBadge('alive', true)!.icon).toBe('alive');
    expect(lifeBadge('alive', false)!.icon).toBe('desync');
    expect(lifeBadge('ghost', true)!.icon).toBe('ghost');
    expect(lifeBadge('recGhost', true)!.icon).toBe('recGhost');
    // A recording ghost is obviously distinct from a playback ghost (UI-03).
    expect(lifeBadge('recGhost', true)!.label).not.toBe(lifeBadge('ghost', true)!.label);
  });

  it('transport states: playing, looping, reversing, stopped, cued, paused', () => {
    const base = { status: 'committed' as DeckStatus, localProgress: 0.4, spanBars: 2 };
    expect(transportBadge({ ...base, endMode: 'repeat', transport: 1 }, 2)!.label).toBe('PLAYING');
    expect(transportBadge({ ...base, endMode: 'repeat', transport: 1 }, 9)!.label).toBe('LOOPING · PASS 2');
    expect(transportBadge({ ...base, endMode: 'reverse', transport: -1 }, 9)!.label).toBe('REVERSING · PASS 2');
    expect(transportBadge({ ...base, endMode: 'reverse', transport: 1 }, 17)!.label).toBe('FORWARD · PASS 3');
    expect(transportBadge({ ...base, endMode: 'stop', transport: 0, localProgress: 1 }, 12)!.label).toBe('STOPPED — HOLDING POSE');
    expect(transportBadge({ ...base, endMode: 'stop', transport: 0, localProgress: 0 }, 0)!.label).toBe('CUED AT BEAT 0');
    expect(transportBadge({ ...base, endMode: 'repeat', transport: 0 }, 5)!.label).toBe('PAUSED');
    expect(transportBadge({ ...base, status: 'empty', endMode: null, transport: 0 }, 0)).toBeNull();
    expect(transportBadge({ ...base, status: 'armed', endMode: 'stop', transport: 0 }, 0)).toBeNull();
    const icons = new Set(
      [
        transportBadge({ ...base, endMode: 'repeat', transport: 1 }, 9)!,
        transportBadge({ ...base, endMode: 'reverse', transport: -1 }, 9)!,
        transportBadge({ ...base, endMode: 'stop', transport: 0, localProgress: 1 }, 12)!,
      ].map((b) => b.icon),
    );
    expect(icons.size).toBe(3);
  });

  it('end modes each have a word, an icon and an explanation', () => {
    const modes = (['stop', 'repeat', 'reverse'] as const).map(endModeInfo);
    expect(new Set(modes.map((m) => m.label)).size).toBe(3);
    expect(new Set(modes.map((m) => m.icon)).size).toBe(3);
    for (const m of modes) expect(m.copy.length).toBeGreaterThan(10);
  });
});

describe('speed copy (UI-05, UI-07)', () => {
  it('one consequence line per speed, stating playback time, force and world rate', () => {
    expect(speedConsequence(2)).toBe(
      '2× — this take plays back in half the time and hits twice as hard; the world runs at half speed while you record',
    );
    expect(speedConsequence(0.5)).toMatch(/^0\.5× — .*twice the time.*half as hard.*double speed/);
    expect(speedConsequence(1)).toMatch(/^1× — .*normal speed/);
    expect(speedConsequence(4)).toMatch(/^4× — .*quarter of the time.*four times as hard.*quarter speed/);
    expect(new Set(ALL_SPEEDS.map(speedConsequence)).size).toBe(4);
  });

  it('readouts and local/master conversions name their units', () => {
    expect(ALL_SPEEDS.map(formatSpeed)).toEqual(['0.5×', '1×', '2×', '4×']);
    expect(formatSpeed(null)).toBe('--');
    expect(spanCopy(4, 2)).toBe('4 local bars → 2 master bars');
    expect(spanCopy(4, 4)).toBe('4 local bars → 1 master bar');
    expect(spanCopy(4, 0.5)).toBe('4 local bars → 8 master bars');
    expect(spanCopy(3, 2)).toBe('3 local bars → 1.5 master bars');
    expect(formatWorldRate(0.5)).toBe('world ×0.5');
    expect(formatWorldRate(2)).toBe('world ×2');
    expect(formatWorldRate(0)).toBe('world paused');
  });

  it('span scale: a 2× pass fills half of what a 1× pass does', () => {
    const offered: TapeSpeed[] = [0.5, 1, 2, 4];
    expect(spanScaleFill(0.5, offered)).toBe(1);
    expect(spanScaleFill(1, offered)).toBe(0.5);
    expect(spanScaleFill(2, offered)).toBe(0.25);
    expect(spanScaleFill(4, offered)).toBe(0.125);
    expect(spanScaleFill(1, [1])).toBe(1);
    expect(spanScaleFill(2, [1, 2])).toBe(0.5);
  });

  it('reels: 2× spins twice as fast as 1×, reverse spins backward, stopped is still', () => {
    expect(reelSpin(2, 1)).toBeCloseTo(2 * reelSpin(1, 1));
    expect(reelSpin(1, -1)).toBeCloseTo(-reelSpin(1, 1));
    expect(reelSpin(2, 0)).toBe(0);
    const [l0, r0] = tapePackRadii(0, 9, 21);
    const [l1, r1] = tapePackRadii(1, 9, 21);
    expect(l0).toBeCloseTo(21);
    expect(r0).toBeCloseTo(9);
    expect(l1).toBeCloseTo(9);
    expect(r1).toBeCloseTo(21);
    const [lm, rm] = tapePackRadii(0.5, 9, 21);
    expect(lm).toBeCloseTo(rm);
  });

  it('recording time left counts local bars down', () => {
    expect(recordingTimeLeft(0, 4).text).toBe('4 local bars left');
    expect(recordingTimeLeft(0.5, 4).text).toBe('2 local bars left');
    expect(recordingTimeLeft(0.7, 4).text).toBe('2 local bars left');
    expect(recordingTimeLeft(0.75, 4).text).toBe('1 local bar left');
    expect(recordingTimeLeft(0.8, 4).text).toBe('0.8 local bars left');
    expect(recordingTimeLeft(0.9, 4).text).toBe('0.4 local bars left');
    expect(recordingTimeLeft(1, 4).fraction).toBe(0);
  });

  it('master position text', () => {
    expect(masterPositionText(0)).toBe('bar 1 · beat 1');
    expect(masterPositionText(5.5)).toBe('bar 2 · beat 2');
    expect(masterPositionText(32, 32)).toBe('end · 8 bars');
  });

  it('bar labels thin out on narrow rulers', () => {
    expect(barLabelStep(8, 800, 30)).toBe(1);
    expect(barLabelStep(64, 800, 30)).toBe(4);
    expect(barLabelStep(0, 800)).toBe(1);
  });
});

describe('prompts per device', () => {
  const actions: SessionAction[] = [
    'start',
    'speedUp',
    'speedDown',
    'cycleEndMode',
    'record',
    'skip',
    'endAttempt',
    'retryTake',
    'commit',
    'resetAll',
    'continue',
    'quit',
  ];

  it('every session action has a prompt on both devices', () => {
    for (const dev of ['keyboard', 'gamepad'] as const) {
      for (const a of actions) {
        const p = promptFor(a, dev);
        expect(p.binding.key).not.toBe('?');
        expect(p.text).toBe(`[${p.binding.key}] ${p.label}`);
      }
    }
    expect(promptFor('record', 'keyboard').text).toBe('[Space] RECORD');
    expect(promptFor('record', 'gamepad').text).toBe('[A] RECORD');
    expect(promptFor('speedUp', 'gamepad').binding.style).toBe('shoulder');
  });

  it('the three decision actions never share a button on one device', () => {
    for (const dev of ['keyboard', 'gamepad'] as const) {
      const keys = (['retryTake', 'commit', 'resetAll'] as const).map((a) => HUD_BINDINGS[dev][a]!.key);
      expect(new Set(keys).size).toBe(3);
    }
  });

  it('setup controls never share a button on one device', () => {
    for (const dev of ['keyboard', 'gamepad'] as const) {
      const keys = (['speedUp', 'speedDown', 'cycleEndMode', 'record'] as const).map((a) => HUD_BINDINGS[dev][a]!.key);
      expect(new Set(keys).size).toBe(4);
    }
  });
});

describe('decision options (REC-04, REC-05)', () => {
  it('offers retry / commit / reset, enabled only when in view.actions', () => {
    const o = decisionOptions(['retryTake', 'commit'], 1);
    expect(o.map((x) => x.action)).toEqual(['retryTake', 'commit', 'resetAll']);
    expect(o.map((x) => x.enabled)).toEqual([true, true, false]);
    expect(o[0].detail).toMatch(/keeps every earlier tape/);
    expect(o[2].detail).toMatch(/wipes every cassette/);
    expect(o[0].detail).toMatch(/tape B/);
  });
});
