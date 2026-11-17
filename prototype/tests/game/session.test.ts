/**
 * Session state machine (ARCHITECTURE "Session flow"; REC-01..08, OPEN-07, OPEN-21; TEST-03..06,
 * TEST-31, TEST-32), driven headlessly.
 */
import { describe, expect, it } from 'vitest';
import { BASE_LOADOUT, resolveLoadout, SANDBOX } from '../../src/content/index';
import { buildBossMemory, resolveEncounter } from '../../src/core/index';
import type { FrameSnapshot, SessionPhase, SimEvent, Tape } from '../../src/core/types';
import type { BotTake } from '../../src/game/bot';
import { createSession, type Session, type SessionCue } from '../../src/game/session';
import { baseLoadout } from '../helpers/loadout';
import { script } from '../helpers/script';
import { planTake } from './plans';
import { ALL_BUTTONS, advanceUntilPhaseChanges, laserHall, newSession, NO_INPUT, recordWith, rescueRoom, setSpeed, STEP } from './util';

/** Scenario C tape A: the turret kills it early; as a recording ghost it strikes, flips the lever and leaves. */
const tapeA = () =>
  script()
    .aim(0, 480, -Math.PI / 2)
    .press(100, 'light', -Math.PI / 2)
    .run(130, 150, -0.3, -1)
    .press(160, 'interact')
    .run(175, 200, 0.55, 1)
    .run(200, 300, 1, 0);

/** TEST-11 tape B (2x): destroys the turret before its first shot, which saves tape A. */
const tapeB = () => script().run(0, 9, -1.5, 1).press(9, 'light', Math.atan2(1, -1.5)).run(30, 60, 1, -1);

function phasesOf(cues: SessionCue[]): SessionPhase[] {
  return cues.filter((c): c is Extract<SessionCue, { kind: 'phase' }> => c.kind === 'phase').map((c) => c.phase);
}

/** Feed a closed-loop plan take through the session's own snapshots. */
function planInputs(s: Session, take: BotTake) {
  return (tick: number) => {
    const snap = s.currentFrame().snap;
    const self = snap.actors.find((a) => a.live)!;
    return take.inputs(tick, { tick, index: s.activeIndex!, snap, self });
  };
}

function drainAll(s: Session): SimEvent[] {
  return s.drainEvents();
}

/** Record take A on the rescue room and play its review through to the decision. */
function takeAToDecision(s: Session): void {
  recordWith(s, tapeA());
  expect(s.phase).toBe('review');
  advanceUntilPhaseChanges(s);
  expect(s.phase).toBe('decision');
}

describe('phase order (sandbox)', () => {
  const loadout = resolveLoadout(BASE_LOADOUT);

  it('briefing → setup → countin → recording → review → decision, with a four-beat count-in', () => {
    const s = createSession({ level: SANDBOX, loadout });
    expect(s.phase).toBe('briefing');
    expect(s.view().actions).toEqual(['start', 'quit']);
    expect(s.act('record')).toBe(false);
    expect(s.act('start')).toBe(true);
    expect(s.phase).toBe('setup');
    expect(s.act('record')).toBe(true);
    expect(s.phase).toBe('countin');
    expect(s.view().count).toBe(5);
    expect(s.tickLocal(NO_INPUT())).toBe(false);
    expect(s.liveSim!.localTick).toBe(0);

    // 120 bpm: one count per 0.5 s of wall time (UI-04), at the base tempo regardless of speed.
    const counts: number[] = [];
    for (let t = 0; t < 1.99; t += 0.01) {
      s.advance(0.01);
      counts.push(s.view().count);
    }
    expect(s.phase).toBe('countin');
    expect([...new Set(counts)]).toEqual([5, 6, 7, 8]);
    expect(s.liveSim!.localTick).toBe(0);
    s.advance(0.02);
    expect(s.phase).toBe('recording');
    expect(s.view().count).toBe(0);

    let ticks = 0;
    while (s.phase === 'recording') {
      s.tickLocal(NO_INPUT());
      ticks++;
    }
    expect(ticks).toBe(s.tapeTicks);
    expect(s.phase).toBe('review');
    advanceUntilPhaseChanges(s);
    expect(s.phase).toBe('decision');
    expect(s.view().actions).toEqual(['retryTake', 'commit', 'resetAll', 'quit']);

    const cues = s.drainCues();
    expect(phasesOf(cues)).toEqual(['setup', 'countin', 'recording', 'review', 'decision']);
    expect(cues.filter((c) => c.kind === 'count').map((c) => (c as { n: number }).n)).toEqual([5, 6, 7, 8]);
  });

  it('nothing auto-commits: the decision waits for the player', () => {
    const s = newSession(SANDBOX, loadout);
    recordWith(s, NO_INPUT);
    advanceUntilPhaseChanges(s);
    for (let i = 0; i < 600; i++) s.advance(STEP);
    expect(s.phase).toBe('decision');
    expect(s.committedTapes).toHaveLength(0);
    expect(s.pendingTape).not.toBeNull();
  });

  it('speed and end mode are constrained to what the level offers', () => {
    const s = newSession(rescueRoom());
    expect(s.speed).toBe(1);
    expect(s.view().speeds).toEqual([1, 2]);
    expect(s.act('speedDown')).toBe(false);
    expect(s.act('speedUp')).toBe(true);
    expect(s.speed).toBe(2);
    expect(s.act('speedUp')).toBe(false);
    expect(s.endMode).toBe('stop');
    const modes = [s.endMode];
    for (let i = 0; i < 3; i++) {
      s.act('cycleEndMode');
      modes.push(s.endMode);
    }
    expect(modes).toEqual(['stop', 'repeat', 'reverse', 'stop']);

    const hall = newSession(laserHall());
    expect(hall.view().actions).not.toContain('cycleEndMode');
    expect(hall.act('cycleEndMode')).toBe(false);
    expect(hall.act('speedUp')).toBe(false);
  });
});

describe('takes, retries and resets (REC-02..05)', () => {
  it('TEST-03: the next cassette starts at beat zero with the committed tape playing from its start', () => {
    const level = rescueRoom();
    const s = newSession(level);
    takeAToDecision(s);
    const a = s.pendingTape!;
    expect(s.act('commit')).toBe(true);
    expect(s.phase).toBe('setup');
    expect(s.act('record')).toBe(true);
    const sim = s.liveSim!;
    expect(sim.sub).toBe(0);
    const snap = s.currentFrame().snap;
    expect(snap.sub).toBe(0);
    expect(snap.beat).toBe(0);
    const actorA = snap.actors.find((x) => x.tape === 0)!;
    expect([actorA.x, actorA.y]).toEqual([a.pos[0], a.pos[1]]);
    expect(actorA.phase.tick).toBe(0);
    expect(actorA.life).toBe('alive');
  });

  it('TEST-04: only already-recorded tapes are present while recording; future cassettes do not exist', () => {
    const s = newSession(rescueRoom());
    s.act('record');
    expect(s.liveSim!.config.tapes).toEqual([]);
    expect(s.currentFrame().snap.actors.map((x) => x.tape)).toEqual([0]);
    s.abortTake();
    takeAToDecision(s);
    s.act('commit');
    s.act('record');
    const committed = s.committedTapes;
    expect(s.liveSim!.config.tapes).toHaveLength(1);
    expect(s.liveSim!.config.tapes[0]).toBe(committed[0]);
    advanceUntilPhaseChanges(s, 10);
    s.tickLocal(NO_INPUT());
    expect(s.currentFrame().snap.actors.map((x) => x.tape)).toEqual([0, 1]);
    const decks = s.view().decks;
    expect(decks[2].status).toBe('empty');
    expect(decks[3].status).toBe('empty');
  });

  it('TEST-05: retryTake replaces only the current take; committed tapes are untouched', () => {
    const s = newSession(rescueRoom());
    takeAToDecision(s);
    s.act('commit');
    const committedBefore = s.committedTapes;
    recordWith(s, NO_INPUT);
    advanceUntilPhaseChanges(s);
    const first = s.pendingTape!;
    expect(s.act('retryTake')).toBe(true);
    expect(s.phase).toBe('setup');
    expect(s.pendingTape).toBeNull();
    expect(s.activeIndex).toBe(1);
    expect(s.committedTapes).toHaveLength(1);
    expect(s.committedTapes[0]).toBe(committedBefore[0]);
    setSpeed(s, 2);
    recordWith(s, tapeB());
    const second = s.pendingTape!;
    expect(second).not.toBe(first);
    expect(second.index).toBe(1);
    expect(second.speed).toBe(2);
    expect(s.committedTapes[0]).toBe(committedBefore[0]);
  });

  it('TEST-06: an older cassette cannot be re-recorded except by resetAll, which wipes every cassette', () => {
    const s = newSession(rescueRoom());
    takeAToDecision(s);
    s.act('commit');
    recordWith(s, NO_INPUT);
    advanceUntilPhaseChanges(s);
    s.act('commit');
    expect(s.committedTapes).toHaveLength(2);
    expect(s.activeIndex).toBe(2);
    // No offered action touches cassette A or B.
    expect(s.view().actions).toEqual(['speedUp', 'cycleEndMode', 'record', 'resetAll', 'quit']);
    expect(s.act('retryTake')).toBe(false);
    expect(s.act('commit')).toBe(false);
    s.act('record');
    expect(s.liveSim!.config.live!.index).toBe(2);
    s.abortTake();

    expect(s.act('resetAll')).toBe(true);
    expect(s.phase).toBe('setup');
    expect(s.committedTapes).toEqual([]);
    expect(s.pendingTape).toBeNull();
    expect(s.resolution).toBeNull();
    expect(s.activeIndex).toBe(0);
    expect(s.bossMemory.observed).toEqual([]);
    const v = s.view();
    expect(v.decks.map((d) => d.status)).toEqual(['armed', 'empty', 'empty', 'empty']);
    expect(v.decks.every((d) => d.stateMarks.length === 0)).toBe(true);
    s.act('record');
    expect(s.liveSim!.config.tapes).toEqual([]);
  });

  it('resetAll from the decision wipes the pending take and every committed one', () => {
    const s = newSession(rescueRoom());
    takeAToDecision(s);
    s.act('commit');
    recordWith(s, NO_INPUT);
    advanceUntilPhaseChanges(s);
    expect(s.act('resetAll')).toBe(true);
    expect(s.committedTapes).toEqual([]);
    expect(s.pendingTape).toBeNull();
    expect(s.activeIndex).toBe(0);
  });

  it('OPEN-21: pausing mid-take (count-in or recording) aborts the take back to setup', () => {
    const s = newSession(rescueRoom());
    takeAToDecision(s);
    s.act('commit');
    const committed = s.committedTapes;
    s.act('record');
    expect(s.abortTake()).toBe(true);
    expect(s.phase).toBe('setup');
    s.act('record');
    advanceUntilPhaseChanges(s, 10);
    for (let i = 0; i < 50; i++) s.tickLocal(NO_INPUT());
    s.drainCues();
    expect(s.abortTake()).toBe(true);
    expect(s.drainCues().map((c) => c.kind)).toEqual(['takeAborted', 'phase']);
    expect(s.phase).toBe('setup');
    expect(s.liveSim).toBeNull();
    expect(s.pendingTape).toBeNull();
    expect(s.committedTapes).toEqual(committed);
    expect(s.activeIndex).toBe(1);
    expect(s.abortTake()).toBe(false);
  });

  it('pause-menu restart wipes the attempt from any phase before the win', () => {
    const s = newSession(rescueRoom());
    takeAToDecision(s);
    s.act('commit');
    recordWith(s, NO_INPUT);
    expect(s.phase).toBe('review');
    expect(s.restartAttempt()).toBe(true);
    expect(s.phase).toBe('setup');
    expect(s.committedTapes).toEqual([]);
  });
});

describe('authoritative result, review and cinematic (REC-06..08, OPEN-07, CINE)', () => {
  it('a win plays the locked cinematic; its frames are exactly the Resolution frames (TEST-32)', () => {
    const level = rescueRoom();
    const loadout = baseLoadout();
    const s = newSession(level, loadout);
    takeAToDecision(s);
    s.act('commit');
    setSpeed(s, 2);
    recordWith(s, tapeB());
    expect(s.phase).toBe('cinematic');
    expect(s.outcome!.win).toBe(true);
    expect(s.tapesUsed).toBe(2);

    const a = s.committedTapes[0];
    const b = s.pendingTape!;
    const expected = resolveEncounter({ level, loadout, tapes: [a, b], bossMemory: buildBossMemory(level, [a]) });
    const res = s.resolution!;
    expect(res.frames).toEqual(expected.frames);
    expect(res.events).toEqual(expected.events);
    expect(res.outcome).toEqual(expected.outcome);

    s.drainEvents();
    const drawn: FrameSnapshot[] = [];
    const events: SimEvent[] = [];
    let k = 0;
    while (s.phase === 'cinematic') {
      // TEST-32 / CINE-02: gameplay input does nothing during the cinematic.
      expect(s.tickLocal(ALL_BUTTONS())).toBe(false);
      for (const act of ['retryTake', 'commit', 'resetAll', 'record', 'endAttempt', 'speedUp', 'cycleEndMode', 'start'] as const) {
        expect(s.act(act)).toBe(false);
      }
      s.advance(STEP);
      const f = s.currentFrame();
      drawn.push(f.prev);
      events.push(...drainAll(s));
      expect(f.alpha).toBeGreaterThanOrEqual(0);
      expect(f.alpha).toBeLessThanOrEqual(1);
      if (++k > 100000) throw new Error('cinematic never ended');
    }
    expect(s.phase).toBe('results');
    expect(s.resolution).toBe(res);
    expect(s.committedTapes).toEqual([a]);
    // Every drawn frame is one of the resolution's own snapshots, in order, ending on the last.
    let last = -1;
    for (const f of drawn) {
      const i = res.frames.indexOf(f);
      expect(i).toBeGreaterThanOrEqual(last);
      last = i;
    }
    expect(last).toBe(res.frames.length - 1);
    // True master speed: one wall second per master second (CINE-01, CINE-04).
    expect(k).toBeGreaterThanOrEqual(Math.floor((res.horizonSubs / 240) * 60) - 1);
    expect(k).toBeLessThanOrEqual(Math.ceil((res.horizonSubs / 240) * 60) + 1);
    // Every resolved event is re-emitted once, in order, for audio / fx.
    expect(events).toEqual(res.events);
    expect(s.view().outcome!.win).toBe(true);
    expect(s.view().actions).toEqual(['continue', 'quit']);
  });

  it('the cinematic can be skipped to results without changing the result', () => {
    const s = newSession(rescueRoom());
    takeAToDecision(s);
    s.act('commit');
    setSpeed(s, 2);
    recordWith(s, tapeB());
    const res = s.resolution!;
    s.advance(1);
    expect(s.act('skip')).toBe(true);
    expect(s.phase).toBe('results');
    expect(s.resolution).toBe(res);
    expect(s.outcome!.win).toBe(true);
  });

  it('a level can be won with fewer cassettes than it offers', () => {
    const s = newSession(rescueRoom(4));
    takeAToDecision(s);
    s.act('commit');
    setSpeed(s, 2);
    recordWith(s, tapeB());
    expect(s.phase).toBe('cinematic');
    expect(s.tapesUsed).toBe(2);
    expect(s.view().decks.map((d) => d.status)).toEqual(['committed', 'committed', 'empty', 'empty']);
  });

  it('final-tape edge case: objectives completed only by the recording ghost do not win (OPEN-07)', () => {
    const level = laserHall(2);
    const s = newSession(level);
    recordWith(s, NO_INPUT);
    advanceUntilPhaseChanges(s);
    s.act('commit');
    s.drainEvents();
    // Tape B walks through the permanent laser (dies), then as a recording ghost kills the grunt.
    const b = planTake(1, 'stop', [
      { kind: 'goto', x: 7.6, y: 5.5 },
      { kind: 'hold', x: 7.6, y: 5.5 },
    ]);
    const liveEvents: SimEvent[] = [];
    recordWithLive(s, planInputs(s, b), liveEvents);
    const deaths = liveEvents.filter((e) => e.type === 'selfDeath' && e.tape === 1);
    const kills = liveEvents.filter((e) => e.type === 'kill' && e.id === 'g1');
    expect(deaths).toHaveLength(1);
    expect(kills).toHaveLength(1);
    expect(kills[0].sub).toBeGreaterThan(deaths[0].sub);
    // The provisional live run latched the objective with tape A alive…
    expect(liveEvents.some((e) => e.type === 'objective')).toBe(true);
    // …but the authoritative playback run does not: tape B dies again and its strike never lands.
    expect(s.phase).toBe('review');
    const out = s.resolution!.outcome;
    expect(out.win).toBe(false);
    expect(out.objectiveComplete).toBe(false);
    expect(out.reason).toBe('objective');
    expect(out.survivors).toEqual([0]);
    expect(s.resolution!.events.some((e) => e.type === 'kill')).toBe(false);
  });

  it('TEST-31: a failed final cassette can be ended early and then offers only retry / reset', () => {
    const s = newSession(rescueRoom(1));
    recordWith(s, tapeA());
    expect(s.phase).toBe('review');
    expect(s.view().actions).toEqual(['skip', 'endAttempt']);
    s.advance(1.5);
    expect(s.phase).toBe('review');
    expect(s.act('endAttempt')).toBe(true);
    expect(s.phase).toBe('decision');
    const v = s.view();
    expect(v.actions).toEqual(['retryTake', 'resetAll', 'quit']);
    expect(v.outcome!.win).toBe(false);
    expect(s.act('commit')).toBe(false);
    expect(s.committedTapes).toEqual([]);
    expect(s.act('retryTake')).toBe(true);
    expect(s.phase).toBe('setup');
  });

  it('TEST-31: left alone, a failed playback runs to the horizon and then waits for a decision', () => {
    const s = newSession(rescueRoom(1));
    recordWith(s, tapeA());
    const res = s.resolution!;
    s.drainEvents();
    const events: SimEvent[] = [];
    let wall = 0;
    while (s.phase === 'review') {
      s.advance(STEP);
      wall += STEP;
      events.push(...s.drainEvents());
    }
    expect(s.phase).toBe('decision');
    expect(wall).toBeCloseTo(res.horizonSubs / 240, 1);
    expect(events).toEqual(res.events);
    expect(s.currentFrame().snap).toBe(res.frames[res.frames.length - 1]);
  });

  it('skipping a review drops the rest of its playback events', () => {
    const s = newSession(rescueRoom(1));
    recordWith(s, tapeA());
    s.drainEvents();
    s.advance(0.5);
    const early = s.drainEvents();
    s.act('skip');
    expect(s.drainEvents()).toEqual([]);
    expect(early.length).toBeLessThan(s.resolution!.events.length);
  });
});

describe('boss memory (BOSS-01/02)', () => {
  it('is rebuilt only from committed tapes, on commit and reset, and never by review or cinematic', () => {
    const level = rescueRoom();
    const s = newSession(level);
    expect(s.bossMemoryBuilds).toBe(1);
    expect(s.bossMemory.observed).toEqual([]);
    const m0 = s.bossMemory;

    s.act('record');
    expect(s.liveSim!.config.bossMemory).toBe(m0);
    s.abortTake();
    takeAToDecision(s);
    expect(s.bossMemory).toBe(m0);
    s.act('retryTake');
    expect(s.bossMemory).toBe(m0);
    takeAToDecision(s);
    s.act('commit');
    expect(s.bossMemoryBuilds).toBe(2);
    const m1 = s.bossMemory;
    expect(m1).toEqual(buildBossMemory(level, s.committedTapes as Tape[]));
    expect(m1.observed.map((o) => o.tape)).toEqual([0]);

    setSpeed(s, 2);
    s.act('record');
    expect(s.liveSim!.config.bossMemory).toBe(m1);
    s.abortTake();
    recordWith(s, tapeB());
    expect(s.phase).toBe('cinematic');
    expect(s.bossMemory).toBe(m1);
    while (s.phase === 'cinematic') s.advance(0.25);
    expect(s.phase).toBe('results');
    expect(s.bossMemory).toBe(m1);
    expect(s.bossMemoryBuilds).toBe(2);
  });

  it('resetAll rebuilds it empty', () => {
    const s = newSession(rescueRoom());
    takeAToDecision(s);
    s.act('commit');
    expect(s.bossMemory.observed).toHaveLength(1);
    s.act('resetAll');
    expect(s.bossMemory.observed).toEqual([]);
    expect(s.bossMemoryBuilds).toBe(3);
  });
});

describe('SessionView decks (UI-06, UI-07, NEW-07..11)', () => {
  it('reports every deck status with its fields', () => {
    const level = rescueRoom(3);
    const s = newSession(level);
    let v = s.view();
    expect(v.phase).toBe('setup');
    expect(v.active).toBe(0);
    expect(v.worldRate).toBe(0);
    expect(v.horizonBeats).toBe(level.horizonBars * 4);
    expect(v.decks.map((d) => d.status)).toEqual(['armed', 'empty', 'empty', 'unavailable']);
    expect(v.decks[0]).toMatchObject({ index: 0, speed: 1, endMode: 'stop', transport: 0, reelRate: 0, life: 'alive', synced: true, spanBars: 4, marks: [] });
    expect(v.decks[1]).toMatchObject({ speed: null, endMode: null, life: null, spanBars: 0, reelRate: 0, marks: [], stateMarks: [] });
    expect(v.decks[3]).toMatchObject({ status: 'unavailable', speed: null, life: null });

    s.act('speedUp');
    v = s.view();
    expect(v.decks[0]).toMatchObject({ speed: 2, spanBars: 2 });
    s.act('speedDown');

    // recording
    s.act('record');
    expect(s.view().decks[0].status).toBe('armed');
    advanceUntilPhaseChanges(s, 10);
    const script = tapeA();
    for (let t = 0; t < 120; t++) s.tickLocal(script.input(t));
    v = s.view();
    expect(v.worldRate).toBe(1);
    expect(v.decks[0]).toMatchObject({ status: 'recording', transport: 1, reelRate: 1 });
    expect(v.decks[0].localProgress).toBeCloseTo(120 / s.tapeTicks, 5);
    expect(v.decks[0].marks).toEqual([{ tick: 100, kind: 'light' }]);
    expect(v.decks[0].stateMarks.map((m) => m.kind)).toEqual(['death']);
    expect(v.decks[0].life).toBe('recGhost');
    let tick = 120;
    while (s.phase === 'recording') s.tickLocal(script.input(tick++));

    // review (pending)
    s.advance(0.5);
    v = s.view();
    expect(v.decks[0]).toMatchObject({ status: 'pending', speed: 1, transport: 1, reelRate: 1 });
    expect(v.outcome).toBeNull();
    expect(v.decks[0].stateMarks.map((m) => m.kind)).toEqual(['death']);
    expect(v.decks[0].marks.map((m) => m.kind)).toEqual(['light', 'interact']);

    // decision
    s.act('skip');
    v = s.view();
    expect(v.decks[0]).toMatchObject({ status: 'pending', transport: 0, reelRate: 0, life: 'ghost' });
    expect(v.outcome!.win).toBe(false);

    // committed, next deck armed
    const a = s.pendingTape!;
    s.act('commit');
    v = s.view();
    expect(v.decks.map((d) => d.status)).toEqual(['committed', 'armed', 'empty', 'unavailable']);
    expect(v.decks[0].marks).toEqual(a.events.map((e) => ({ tick: e.tick, kind: e.kind })));
    expect(v.decks[0].stateMarks).toHaveLength(1);
    expect(v.decks[0].stateMarks[0].beat).toBeGreaterThan(0);
    expect(v.decks[0].life).toBe('alive');
    expect(v.hint).toBeNull();

    // A 2x take: the world runs at half speed, so the 1x committed reel spins at half the viewer's rate.
    setSpeed(s, 2);
    s.act('record');
    advanceUntilPhaseChanges(s, 10);
    for (let t = 0; t < 10; t++) s.tickLocal(NO_INPUT());
    v = s.view();
    expect(v.worldRate).toBe(0.5);
    expect(v.decks[1]).toMatchObject({ status: 'recording', speed: 2, reelRate: 1, spanBars: 2 });
    expect(v.decks[0]).toMatchObject({ status: 'committed', transport: 1, reelRate: 0.5 });
    expect(v.beat).toBeCloseTo(s.currentFrame().snap.sub / 120, 9);
  });

  it('shows the setup hint for the armed cassette and the objective text', () => {
    const s = createSession({ level: SANDBOX, loadout: resolveLoadout(BASE_LOADOUT) });
    expect(s.view().hint).toBeNull();
    s.act('start');
    const v = s.view();
    expect(v.hint).toBe(SANDBOX.hints![1]);
    expect(v.objective.text).toBe(SANDBOX.objective.text);
    expect(v.objective.complete).toBe(false);
  });

  it('beatSight lists upcoming enemy attack beats; without it the list is empty', () => {
    const level = rescueRoom(1);
    const plain = newSession(level);
    recordWith(plain, tapeA());
    let sawPlain = false;
    while (plain.phase === 'review') {
      plain.advance(STEP);
      if (plain.view().threatBeats.length) sawPlain = true;
    }
    expect(sawPlain).toBe(false);

    const sighted = newSession(level, baseLoadout({ abilities: ['beatSight'] }));
    recordWith(sighted, tapeA());
    const shots = sighted.resolution!.events.filter((e) => e.type === 'enemyShot').map((e) => (e.sub + 1) / 120);
    expect(shots.length).toBeGreaterThan(0);
    const seen = new Set<number>();
    while (sighted.phase === 'review') {
      sighted.advance(STEP);
      const v = sighted.view();
      for (const b of v.threatBeats) {
        expect(b).toBeGreaterThanOrEqual(v.beat - 1e-6);
        seen.add(Math.round(b * 1000) / 1000);
      }
    }
    for (const b of shots) expect(seen.has(Math.round(b * 1000) / 1000)).toBe(true);
  });

  it('trackAudioStates follow the decks: present, speed, life and transport', () => {
    const s = newSession(rescueRoom());
    let tracks = s.trackAudioStates();
    expect(tracks.map((t) => t.present)).toEqual([true, false, false, false]);
    expect(tracks[0].transport).toBe(0);
    recordWith(s, tapeA());
    s.advance(0.1);
    tracks = s.trackAudioStates();
    expect(tracks[0]).toMatchObject({ present: true, speed: 1, transport: 1, life: 'alive' });
    s.act('skip');
    tracks = s.trackAudioStates();
    expect(tracks[0]).toMatchObject({ present: true, transport: 0, life: 'ghost' });
  });
});

/** recordWith, but keeps every live event drained during the take. */
function recordWithLive(s: Session, fn: (tick: number) => ReturnType<typeof NO_INPUT>, out: SimEvent[]): void {
  s.act('record');
  advanceUntilPhaseChanges(s, 10);
  let tick = 0;
  while (s.phase === 'recording') {
    s.tickLocal(fn(tick++));
    out.push(...s.drainEvents());
  }
}
