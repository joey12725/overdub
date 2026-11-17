/**
 * One level attempt (ARCHITECTURE "Session flow", REC-01..08, OPEN-07, OPEN-21).
 *
 *   briefing → setup → countin → recording → review → decision → (setup | cinematic → results)
 *
 * The session is DOM-free and deterministic: the app feeds it wall time (`advance`), one input per
 * local tick while recording (`tickLocal`) and player choices (`act`). Everything the HUD, the
 * renderer and the audio layer need comes back out through `view()`, `currentFrame()`,
 * `drainEvents()`, `drainCues()` and `trackAudioStates()`.
 *
 * Rules this file is responsible for:
 *  - every take restarts the encounter at beat zero with the COMMITTED tapes playing and nothing
 *    else (REC-02, REC-03; future cassettes do not exist yet);
 *  - retryTake discards only the pending take (REC-04); commit locks it and arms the next cassette;
 *    resetAll wipes every cassette and is the only way to change an older one (REC-05);
 *  - the authoritative result is resolveEncounter over committed + pending under playback rules,
 *    never the live take's own run, so a recording ghost's provisional effects cannot win
 *    (REC-06, OPEN-07, chapter 06 "final-tape edge case");
 *  - a winning resolution plays as the locked cinematic and goes to results (CINE-01..05); a
 *    failing one plays as a skippable review (REC-08) and then waits for a decision; nothing is
 *    ever committed automatically (chapter 04);
 *  - boss memory is rebuilt from committed tapes only, on commit and on reset (BOSS-01/02);
 *  - pausing mid-take aborts the take back to setup; there is no tactical pause (OPEN-21).
 */
import type { TrackAudioState } from '../contracts';
import { buildBossMemory, createSim, horizonSubs, resolveEncounter, spanBars, subsPerBeat, tapeTicks } from '../core/index';
import { ENEMY_STATS } from '../core/tuning';
import {
  SUB_HZ,
  TAPE_COUNT,
  type ActionKind,
  type BossMemory,
  type DeckStatus,
  type DeckView,
  type EndMode,
  type EnemyDef,
  type FrameSnapshot,
  type ISim,
  type LevelDef,
  type LifeState,
  type Outcome,
  type PlayerInput,
  type Resolution,
  type ResolvedLoadout,
  type SessionAction,
  type SessionPhase,
  type SessionView,
  type SimEvent,
  type Tape,
  type TapeIndex,
  type TapeSpeed,
} from '../core/types';

/** Count-in length in beats ("five, six, seven, eight"; UI-04). */
export const COUNT_IN_BEATS = 4;
/** How far ahead the beatSight ruler looks for enemy attacks, in master beats. */
const THREAT_LOOKAHEAD_BEATS = 8;
const MAX_THREATS = 8;

/** Presentation cues that are not simulation events (audio blips, count-in, phase changes). */
export type SessionCue =
  | { kind: 'phase'; phase: SessionPhase; from: SessionPhase }
  | { kind: 'count'; n: 5 | 6 | 7 | 8 }
  | { kind: 'ui'; sound: 'select' | 'speed' | 'commit' | 'retry' | 'reset' | 'win' | 'fail' }
  /** A take was abandoned (pause during count-in or recording). */
  | { kind: 'takeAborted' }
  /** The authoritative result of the take just recorded is known. */
  | { kind: 'resolved'; outcome: Outcome };

export interface SessionFrame {
  snap: FrameSnapshot;
  prev: FrameSnapshot;
  alpha: number;
}

export interface SessionOptions {
  level: LevelDef;
  loadout: ResolvedLoadout;
  /** Start in setup instead of briefing (level revisits, tests). */
  skipBriefing?: boolean;
}

type StateMark = DeckView['stateMarks'][number];

function emptyMarks(): StateMark[][] {
  return [[], [], [], []];
}

function clamp01(v: number): number {
  return v < 0 ? 0 : v > 1 ? 1 : v;
}

export class Session {
  readonly level: LevelDef;
  readonly loadout: ResolvedLoadout;
  /** Master substeps in the encounter. */
  readonly horizonSubs: number;
  /** Local ticks in one recording. */
  readonly tapeTicks: number;
  private readonly spb: number;
  private readonly speeds: TapeSpeed[];

  private _phase: SessionPhase;
  private committed: Tape[] = [];
  private pending: Tape | null = null;
  private _speed: TapeSpeed;
  private _endMode: EndMode;

  private live: ISim | null = null;
  private liveSnap: FrameSnapshot | null = null;
  private livePrev: FrameSnapshot | null = null;
  private liveMarks: StateMark[][] = emptyMarks();
  private liveMarkCache: { tick: number; marks: DeckView['marks'] } | null = null;

  /** Latest authoritative run: committed tapes (+ the pending take during review → results). */
  private _resolution: Resolution | null = null;
  private resolvedMarks: StateMark[][] = emptyMarks();

  private _bossMemory: BossMemory;
  private _bossMemoryBuilds = 0;

  private countT = 0;
  private count: 0 | 5 | 6 | 7 | 8 = 0;
  /** Master substeps (float) into the review / cinematic playback. */
  private playSub = 0;
  /** Index of the next Resolution event to re-emit during review / cinematic. */
  private eventCursor = 0;

  private idle: FrameSnapshot | null = null;
  private events: SimEvent[] = [];
  private cues: SessionCue[] = [];

  constructor(opts: SessionOptions) {
    this.level = opts.level;
    this.loadout = opts.loadout;
    this.horizonSubs = horizonSubs(opts.level);
    this.tapeTicks = tapeTicks(opts.level);
    this.spb = subsPerBeat(opts.level);
    this.speeds = [...new Set(opts.level.speeds)].sort((a, b) => a - b);
    if (this.speeds.length === 0) throw new Error(`Level ${opts.level.id} offers no tape speeds`);
    if (opts.level.endModes.length === 0) throw new Error(`Level ${opts.level.id} offers no end modes`);
    this._speed = this.defaultSpeed();
    this._endMode = this.defaultEndMode();
    this._bossMemory = this.rebuildBossMemory();
    this._phase = opts.skipBriefing ? 'setup' : 'briefing';
    // Built eagerly so a level the kernel cannot run (e.g. an unregistered enemy type) fails here,
    // where the app can report it, rather than mid-frame.
    this.idleFrame();
  }

  // ───────────────────────────── read-only state ─────────────────────────────

  get phase(): SessionPhase {
    return this._phase;
  }
  /** Committed tapes in cassette order (copies of the array; tapes themselves are immutable by convention). */
  get committedTapes(): readonly Tape[] {
    return this.committed.slice();
  }
  get pendingTape(): Tape | null {
    return this.pending;
  }
  get resolution(): Resolution | null {
    return this._resolution;
  }
  get bossMemory(): BossMemory {
    return this._bossMemory;
  }
  /** How many times boss memory has been (re)built; it changes only on commit and reset. */
  get bossMemoryBuilds(): number {
    return this._bossMemoryBuilds;
  }
  get speed(): TapeSpeed {
    return this._speed;
  }
  get endMode(): EndMode {
    return this._endMode;
  }
  /** The live record-mode sim while counting in / recording, else null. */
  get liveSim(): ISim | null {
    return this.live;
  }
  /** Cassette being configured / recorded / decided on, or null when no take is in play. */
  get activeIndex(): TapeIndex | null {
    if (this._phase === 'briefing' || this._phase === 'cinematic' || this._phase === 'results') return null;
    return this.committed.length < this.level.maxTapes ? (this.committed.length as TapeIndex) : null;
  }
  /** Tapes that make up the latest resolved run (committed + pending). */
  get tapesUsed(): number {
    return this.committed.length + (this.pending ? 1 : 0);
  }
  get outcome(): Outcome | null {
    return this._resolution && this.pending ? this._resolution.outcome : null;
  }
  /** Seconds of wall time one count-in beat lasts (base tempo; UI-04). */
  get countBeatSeconds(): number {
    return 60 / this.level.bpm;
  }

  // ───────────────────────────── actions ─────────────────────────────

  /** Session actions currently offered (exactly what `act` will accept, plus 'quit'). */
  actions(): SessionAction[] {
    const a: SessionAction[] = [];
    switch (this._phase) {
      case 'briefing':
        a.push('start', 'quit');
        break;
      case 'setup': {
        const i = this.speeds.indexOf(this._speed);
        if (i < this.speeds.length - 1) a.push('speedUp');
        if (i > 0) a.push('speedDown');
        if (this.level.endModes.length > 1) a.push('cycleEndMode');
        a.push('record');
        if (this.committed.length > 0) a.push('resetAll');
        a.push('quit');
        break;
      }
      case 'countin':
        break;
      case 'recording':
        a.push('quit');
        break;
      case 'review':
        a.push('skip', 'endAttempt');
        break;
      case 'decision':
        a.push('retryTake');
        if (this.canCommit()) a.push('commit');
        a.push('resetAll', 'quit');
        break;
      case 'cinematic':
        // Skipping only stops watching; the result is already fixed (CINE-02, TEST-32).
        a.push('skip');
        break;
      case 'results':
        a.push('continue', 'quit');
        break;
    }
    return a;
  }

  /**
   * Apply a player choice. Returns true when it changed something (or, for 'quit' / 'continue',
   * when the app should act on it). Actions not offered in the current phase are ignored.
   */
  act(action: SessionAction): boolean {
    if (action === 'quit') {
      if (this._phase === 'countin' || this._phase === 'recording') this.abortTake();
      return true;
    }
    if (!this.actions().includes(action)) return false;
    switch (action) {
      case 'start':
        this.setPhase('setup');
        this.cue({ kind: 'ui', sound: 'select' });
        return true;
      case 'speedUp':
      case 'speedDown': {
        const i = this.speeds.indexOf(this._speed) + (action === 'speedUp' ? 1 : -1);
        this._speed = this.speeds[Math.max(0, Math.min(this.speeds.length - 1, i))];
        this.idle = null;
        this.cue({ kind: 'ui', sound: 'speed' });
        return true;
      }
      case 'cycleEndMode': {
        const modes = this.level.endModes;
        this._endMode = modes[(modes.indexOf(this._endMode) + 1) % modes.length];
        this.idle = null;
        this.cue({ kind: 'ui', sound: 'select' });
        return true;
      }
      case 'record':
        this.beginCountIn();
        return true;
      case 'skip':
      case 'endAttempt':
        if (this._phase === 'cinematic') this.enterResults();
        else this.enterDecision();
        return true;
      case 'retryTake':
        this.retryTake();
        return true;
      case 'commit':
        this.commit();
        return true;
      case 'resetAll':
        this.resetAll();
        return true;
      case 'continue':
        return true;
      default:
        return false;
    }
  }

  /**
   * Abandon a take in count-in or recording and return to setup with the same cassette armed
   * (OPEN-21: no mid-take tactical pause). Returns false when no take was in progress.
   */
  abortTake(): boolean {
    if (this._phase !== 'countin' && this._phase !== 'recording') return false;
    this.dropLive();
    this.count = 0;
    this.cue({ kind: 'takeAborted' });
    this.setPhase('setup');
    return true;
  }

  /**
   * Wipe every cassette from any phase (the pause menu's "restart"; REC-05). Unlike act('resetAll'),
   * which is offered only where the HUD shows it, this always applies, except once the level has
   * been won (cinematic / results), where there is no attempt left to restart.
   */
  restartAttempt(): boolean {
    if (this._phase === 'cinematic' || this._phase === 'results') return false;
    this.resetAll();
    return true;
  }

  // ───────────────────────────── clocks ─────────────────────────────

  /**
   * One local tick of live control. Only meaningful while recording; returns false otherwise.
   * The take ends when the local allowance is used up (or the encounter horizon is reached).
   * Death does not end it (GHOST-01).
   */
  tickLocal(input: PlayerInput): boolean {
    if (this._phase !== 'recording' || !this.live) return false;
    const sim = this.live;
    this.livePrev = this.liveSnap;
    sim.stepLocalTick(input);
    this.liveSnap = sim.snapshot();
    for (const e of sim.drainEvents()) {
      this.events.push(e);
      this.noteStateMark(this.liveMarks, e);
    }
    if (sim.done || sim.sub >= this.horizonSubs) this.finishTake();
    return true;
  }

  /** Advance wall-clock driven phases: count-in, review and cinematic playback. */
  advance(dtWallSeconds: number): void {
    const dt = Number.isFinite(dtWallSeconds) && dtWallSeconds > 0 ? dtWallSeconds : 0;
    if (dt === 0) return;
    if (this._phase === 'countin') {
      this.countT += dt;
      const beat = Math.floor(this.countT / this.countBeatSeconds);
      if (beat >= COUNT_IN_BEATS) {
        this.count = 0;
        this.setPhase('recording');
        return;
      }
      const n = (5 + beat) as 5 | 6 | 7 | 8;
      if (n !== this.count) {
        this.count = n;
        this.cue({ kind: 'count', n });
      }
      return;
    }
    if (this._phase === 'review' || this._phase === 'cinematic') {
      // True master speed: SUB_HZ substeps per wall second (CINE-01, CINE-04).
      this.playSub = Math.min(this.horizonSubs, this.playSub + dt * SUB_HZ);
      this.emitPlaybackEvents();
      if (this.playSub >= this.horizonSubs) {
        if (this._phase === 'review') this.enterDecision();
        else this.enterResults();
      }
    }
  }

  // ───────────────────────────── outputs ─────────────────────────────

  /**
   * The snapshot pair to draw. While recording, `recordAlpha` is the fraction of the next local
   * tick that has elapsed in wall time (the app's fixed-step accumulator); playback phases compute
   * their own interpolation from the playback clock.
   */
  currentFrame(recordAlpha = 1, visualDelaySeconds = 0): SessionFrame {
    switch (this._phase) {
      case 'countin':
      case 'recording': {
        const snap = this.liveSnap ?? this.idleFrame();
        return { snap, prev: this.livePrev ?? snap, alpha: this._phase === 'recording' ? clamp01(recordAlpha) : 1 };
      }
      case 'review':
      case 'cinematic':
      case 'decision':
      case 'results':
        if (this._resolution) {
          // Settings A/V offset (positive = picture later): playback is presentation only, so the
          // picture can be shifted against the audible playhead. A live take cannot be.
          const delay = this._phase === 'review' || this._phase === 'cinematic' ? visualDelaySeconds * SUB_HZ : 0;
          return this.playbackFrame(Math.min(this.horizonSubs, Math.max(0, this.playSub - (Number.isFinite(delay) ? delay : 0))));
        }
        break;
      default:
        break;
    }
    const snap = this.idleFrame();
    return { snap, prev: snap, alpha: 1 };
  }

  /** Simulation events since the last drain: live events while recording, re-emitted ones in playback. */
  drainEvents(): SimEvent[] {
    const out = this.events;
    this.events = [];
    return out;
  }

  drainCues(): SessionCue[] {
    const out = this.cues;
    this.cues = [];
    return out;
  }

  /** Music layer state per cassette for this instant (MUSIC-02; dead / desynced / reversing layers). */
  trackAudioStates(): [TrackAudioState, TrackAudioState, TrackAudioState, TrackAudioState] {
    const snap = this.currentFrame().snap;
    const playing = this.isPlaying();
    const out: TrackAudioState[] = [];
    for (let i = 0; i < TAPE_COUNT; i++) {
      const idx = i as TapeIndex;
      const cfg = this.deckConfig(idx);
      const actor = snap.actors.find((a) => a.tape === idx);
      out.push({
        present: cfg !== null,
        speed: cfg?.speed ?? 1,
        life: actor?.life ?? 'alive',
        synced: actor?.synced ?? true,
        transport: playing && actor ? actor.phase.dir : 0,
      });
    }
    return out as [TrackAudioState, TrackAudioState, TrackAudioState, TrackAudioState];
  }

  /** Everything the HUD needs this frame. */
  view(): SessionView {
    const snap = this.currentFrame().snap;
    const worldRate = this.worldRate();
    const decks = [0, 1, 2, 3].map((i) => this.deckView(i as TapeIndex, snap, worldRate)) as SessionView['decks'];
    const active = this.activeIndex;
    return {
      phase: this._phase,
      level: this.level,
      decks,
      active,
      beat: snap.beat,
      horizonBeats: this.horizonSubs / this.spb,
      worldRate,
      count: this.count,
      speeds: this.speeds.slice(),
      endModes: this.level.endModes.slice(),
      objective: { ...snap.objective, text: this.level.objective.text },
      outcome: this._phase === 'decision' || this._phase === 'cinematic' || this._phase === 'results' ? this.outcome : null,
      actions: this.actions(),
      threatBeats: this.threatBeats(snap),
      hint: this._phase === 'setup' && active !== null ? this.level.hints?.[active + 1] ?? null : null,
    };
  }

  /** Master seconds per wall second right now (1/speed while recording; TIME-03). */
  worldRate(): number {
    if (this._phase === 'recording') return 1 / this._speed;
    if (this._phase === 'review' || this._phase === 'cinematic') return 1;
    return 0;
  }

  /** True while master time is moving (recording, review, cinematic). */
  isPlaying(): boolean {
    return this._phase === 'recording' || this._phase === 'review' || this._phase === 'cinematic';
  }

  // ───────────────────────────── transitions ─────────────────────────────

  private setPhase(p: SessionPhase): void {
    if (p === this._phase) return;
    const from = this._phase;
    this._phase = p;
    // The beat-zero picture differs between briefing (no armed self) and setup (armed self).
    if (p === 'setup' || p === 'briefing') this.idle = null;
    this.cue({ kind: 'phase', phase: p, from });
  }

  private cue(c: SessionCue): void {
    this.cues.push(c);
  }

  private canCommit(): boolean {
    return this.pending !== null && this.committed.length + 1 < this.level.maxTapes;
  }

  private beginCountIn(): void {
    const index = this.committed.length as TapeIndex;
    // REC-02 / REC-03: the encounter is rebuilt from beat zero with exactly the committed tapes.
    this.live = createSim({
      level: this.level,
      loadout: this.loadout,
      tapes: this.committed.slice(),
      live: { index, speed: this._speed, endMode: this._endMode },
      bossMemory: this._bossMemory,
    });
    this.liveSnap = this.live.snapshot();
    this.livePrev = this.liveSnap;
    this.liveMarks = emptyMarks();
    this.liveMarkCache = null;
    this.events = [];
    this.countT = 0;
    this.count = 5;
    this.setPhase('countin');
    this.cue({ kind: 'count', n: 5 });
  }

  private finishTake(): void {
    const sim = this.live!;
    const take = sim.liveTape();
    this.dropLive();
    this.pending = take;
    // OPEN-07: only the combined run under playback rules decides; the live run (with any
    // recording-ghost effects) is discarded here.
    this.setResolution(this.resolve([...this.committed, take]));
    this.playSub = 0;
    this.eventCursor = 0;
    const outcome = this._resolution!.outcome;
    this.cue({ kind: 'resolved', outcome });
    if (outcome.win) {
      this.cue({ kind: 'ui', sound: 'win' });
      this.setPhase('cinematic');
    } else {
      this.setPhase('review');
    }
  }

  private enterDecision(): void {
    this.playSub = this.horizonSubs;
    this.eventCursor = this._resolution ? this._resolution.events.length : 0;
    this.cue({ kind: 'ui', sound: 'fail' });
    this.setPhase('decision');
  }

  private enterResults(): void {
    this.playSub = this.horizonSubs;
    this.eventCursor = this._resolution ? this._resolution.events.length : 0;
    this.setPhase('results');
  }

  private retryTake(): void {
    this.pending = null;
    // The latest resolved run now describes only the committed tapes again.
    this.setResolution(this.committed.length > 0 ? this.resolve(this.committed) : null);
    this.idle = null;
    this.cue({ kind: 'ui', sound: 'retry' });
    this.setPhase('setup');
  }

  private commit(): void {
    const take = this.pending!;
    this.committed.push(take);
    this.pending = null;
    this._bossMemory = this.rebuildBossMemory();
    // The reviewed run was resolved with the previous memory; only a boss reads it, so only then
    // does the committed set's run need resolving again.
    if (this.levelHasBoss()) this.setResolution(this.resolve(this.committed));
    this._speed = this.defaultSpeed();
    this._endMode = this.defaultEndMode();
    this.idle = null;
    this.cue({ kind: 'ui', sound: 'commit' });
    this.setPhase('setup');
  }

  private resetAll(): void {
    this.dropLive();
    this.committed = [];
    this.pending = null;
    this.setResolution(null);
    this._bossMemory = this.rebuildBossMemory();
    this._speed = this.defaultSpeed();
    this._endMode = this.defaultEndMode();
    this.idle = null;
    this.count = 0;
    this.cue({ kind: 'ui', sound: 'reset' });
    this.setPhase('setup');
  }

  private dropLive(): void {
    this.live = null;
    this.liveSnap = null;
    this.livePrev = null;
    this.liveMarks = emptyMarks();
    this.liveMarkCache = null;
  }

  private resolve(tapes: Tape[]): Resolution {
    return resolveEncounter({ level: this.level, loadout: this.loadout, tapes, bossMemory: this._bossMemory });
  }

  private setResolution(r: Resolution | null): void {
    this._resolution = r;
    this.resolvedMarks = emptyMarks();
    if (r) for (const e of r.events) this.noteStateMark(this.resolvedMarks, e);
  }

  private rebuildBossMemory(): BossMemory {
    this._bossMemoryBuilds++;
    return buildBossMemory(this.level, this.committed.slice());
  }

  private levelHasBoss(): boolean {
    return this.level.entities.some((e) => e.kind === 'enemy' && e.type === 'boss');
  }

  private defaultSpeed(): TapeSpeed {
    return this.speeds.includes(1) ? 1 : this.speeds[0];
  }

  private defaultEndMode(): EndMode {
    return this.level.endModes.includes('stop') ? 'stop' : this.level.endModes[0];
  }

  // ───────────────────────────── frames ─────────────────────────────

  /** Beat-zero picture for briefing / setup: committed tapes plus (in setup) the armed self. */
  private idleFrame(): FrameSnapshot {
    if (this.idle) return this.idle;
    const index = this.committed.length;
    const armed = this._phase !== 'briefing' && index < this.level.maxTapes;
    const sim = createSim({
      level: this.level,
      loadout: this.loadout,
      tapes: this.committed.slice(),
      live: armed ? { index: index as TapeIndex, speed: this._speed, endMode: this._endMode } : undefined,
      bossMemory: this._bossMemory,
    });
    this.idle = sim.snapshot();
    return this.idle;
  }

  private playbackFrame(at: number): SessionFrame {
    const frames = this._resolution!.frames;
    const last = frames.length - 1;
    // frames[k].sub === k · FRAME_SUBS except possibly the final one; search from the estimate.
    let k = Math.min(last, Math.max(0, Math.floor(at / (frames[1]?.sub || 1))));
    while (k > 0 && frames[k].sub > at) k--;
    while (k < last && frames[k + 1].sub <= at) k++;
    if (k >= last) return { snap: frames[last], prev: frames[last], alpha: 1 };
    const prev = frames[k];
    const snap = frames[k + 1];
    return { snap, prev, alpha: clamp01((at - prev.sub) / (snap.sub - prev.sub)) };
  }

  /** Re-emit resolution events whose instant (sub + 1) the playback clock has reached. */
  private emitPlaybackEvents(): void {
    const r = this._resolution;
    if (!r) return;
    const evs = r.events;
    while (this.eventCursor < evs.length && evs[this.eventCursor].sub + 1 <= this.playSub) {
      this.events.push(evs[this.eventCursor]);
      this.eventCursor++;
    }
  }

  // ───────────────────────────── decks ─────────────────────────────

  /** Speed / end mode / tape of a cassette that exists in some form right now, else null. */
  private deckConfig(i: TapeIndex): { speed: TapeSpeed; endMode: EndMode; tape: Tape | null; live: boolean } | null {
    if (i >= this.level.maxTapes) return null;
    if (i < this.committed.length) {
      const t = this.committed[i];
      return { speed: t.speed, endMode: t.endMode, tape: t, live: false };
    }
    if (i !== this.committed.length) return null;
    if (this.pending) return { speed: this.pending.speed, endMode: this.pending.endMode, tape: this.pending, live: false };
    if (this._phase === 'setup' || this._phase === 'countin' || this._phase === 'recording') {
      return { speed: this._speed, endMode: this._endMode, tape: null, live: true };
    }
    return null;
  }

  private deckStatus(i: TapeIndex): DeckStatus {
    if (i >= this.level.maxTapes) return 'unavailable';
    if (i < this.committed.length) return 'committed';
    if (i !== this.committed.length) return 'empty';
    if (this.pending) {
      // A winning take is final: the attempt is over and it is locked into the performance.
      return this._phase === 'cinematic' || this._phase === 'results' ? 'committed' : 'pending';
    }
    switch (this._phase) {
      case 'setup':
      case 'countin':
        return 'armed';
      case 'recording':
        return 'recording';
      default:
        return 'empty';
    }
  }

  private deckView(i: TapeIndex, snap: FrameSnapshot, worldRate: number): DeckView {
    const status = this.deckStatus(i);
    const cfg = this.deckConfig(i);
    const actor = cfg ? snap.actors.find((a) => a.tape === i) : undefined;
    const ticks = cfg?.tape ? cfg.tape.ticks : this.tapeTicks;
    const playing = this.isPlaying();
    const transport: 1 | -1 | 0 = playing && actor ? actor.phase.dir : 0;
    const life: LifeState | null = cfg ? actor?.life ?? 'alive' : null;
    return {
      index: i,
      status,
      speed: cfg?.speed ?? null,
      endMode: cfg?.endMode ?? null,
      localProgress: actor && ticks > 0 ? clamp01(actor.phase.tick / ticks) : 0,
      transport,
      // Local seconds per wall second: the live tape always spins at 1 while every other tape spins
      // at its speed relative to the world's current rate (UI-07, NEW-10).
      reelRate: cfg ? cfg.speed * worldRate * Math.abs(transport) : 0,
      life,
      synced: actor?.synced ?? true,
      spanBars: cfg ? spanBars(this.level, cfg.speed) : 0,
      marks: cfg ? this.marksFor(i, cfg.tape, cfg.live) : [],
      stateMarks: this.stateMarksFor(i),
    };
  }

  private marksFor(i: TapeIndex, tape: Tape | null, live: boolean): DeckView['marks'] {
    if (tape) return tape.events.map((e) => ({ tick: e.tick, kind: e.kind }));
    if (!live || !this.live || i !== this.committed.length) return [];
    const tick = this.live.localTick;
    if (this.liveMarkCache && this.liveMarkCache.tick === tick) return this.liveMarkCache.marks;
    const marks = this.live.liveTape().events.map((e) => ({ tick: e.tick, kind: e.kind as ActionKind }));
    this.liveMarkCache = { tick, marks };
    return marks;
  }

  private stateMarksFor(i: TapeIndex): StateMark[] {
    if (this._phase === 'countin' || this._phase === 'recording') return this.liveMarks[i].slice();
    if (i >= this.committed.length + (this.pending ? 1 : 0)) return [];
    return this.resolvedMarks[i].slice();
  }

  private noteStateMark(into: StateMark[][], e: SimEvent): void {
    if (e.tape === undefined) return;
    const kind = e.type === 'selfDeath' ? 'death' : e.type === 'desync' ? 'desync' : e.type === 'resync' ? 'resync' : null;
    if (!kind) return;
    into[e.tape].push({ beat: (e.sub + 1) / this.spb, kind });
  }

  // ───────────────────────────── beatSight ─────────────────────────────

  /**
   * Upcoming enemy attack beats for the 'beatSight' helmet. A telegraphing enemy's strike lands on
   * its next grid beat (AI-07); in review / cinematic the resolved run also tells exactly when
   * attacks happen.
   */
  private threatBeats(snap: FrameSnapshot): number[] {
    if (!this.loadout.abilities.includes('beatSight')) return [];
    const now = snap.beat;
    const out: number[] = [];
    for (const e of snap.enemies) {
      if (!e.alive || e.state !== 'telegraph') continue;
      const def = this.level.entities.find((d): d is EnemyDef => d.kind === 'enemy' && d.id === e.id);
      const stats = ENEMY_STATS[e.type];
      const every = def?.beat?.every ?? stats.every;
      const offset = def?.beat?.offset ?? stats.offset;
      if (!(every > 0)) continue;
      const k = Math.ceil((now - offset) / every - 1e-9);
      out.push(offset + k * every);
    }
    if ((this._phase === 'review' || this._phase === 'cinematic') && this._resolution) {
      for (const ev of this._resolution.events) {
        if (ev.type !== 'enemyAttack' && ev.type !== 'enemyShot') continue;
        const b = (ev.sub + 1) / this.spb;
        if (b > now && b <= now + THREAT_LOOKAHEAD_BEATS) out.push(b);
      }
    }
    const uniq = [...new Set(out.map((b) => Math.round(b * 1000) / 1000))].filter((b) => b >= now - 1e-6);
    return uniq.sort((a, b) => a - b).slice(0, MAX_THREATS);
  }
}

export function createSession(opts: SessionOptions): Session {
  return new Session(opts);
}
