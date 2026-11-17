/**
 * The application shell (wired to the concrete modules by src/game/app.ts).
 *
 * Owns the screens (title → campaign → loadout ↔ → play → results → next level → … → ending, plus
 * settings and pause), the save, the campaign and the current Session, and runs the main loop:
 *
 *  - recording: session.tickLocal runs at exactly LOCAL_HZ from a wall-time accumulator, with a
 *    bounded catch-up so a hitch never turns into a burst of hidden ticks (local == wall; TIME-02);
 *  - count-in / review / cinematic: session.advance(dt) moves their wall-driven clocks;
 *  - every animation frame: interpolated render, HUD, audio transport / layers / events.
 *
 * It talks to render / audio / ui only through the src/contracts.ts facades, so the whole flow can be
 * driven headlessly in tests with stand-ins.
 */
import type { IAudio, IRenderer, IUi, MusicPulse, RenderFrame, Screen, UiIntent, ViewMode } from '../contracts';
import type { TrackAudioState } from '../contracts';
import { LEVELS } from '../content/index';
import { createSim } from '../core/index';
import {
  LOCAL_HZ,
  TAPE_NAMES,
  type FrameSnapshot,
  type LevelDef,
  type ResolvedLoadout,
  type SaveData,
  type SessionAction,
  type SessionPhase,
  type SimEvent,
} from '../core/types';
import { Campaign } from './campaign';
import { createInput, type GameInput, type InputAction } from './input';
import { eraseSave as eraseStored, freshSave, loadSave, writeSave, defaultStorage, type SaveStorage } from './save';
import { createSession, type Session, type SessionCue } from './session';

/** Seconds per local tick. */
const TICK = 1 / LOCAL_HZ;
/** Most local ticks run in one animation frame; anything beyond is dropped, not hurried. */
const MAX_CATCHUP_TICKS = 8;
/** Longest wall step any clock accepts from one frame (tab switches, debugger pauses). */
const MAX_FRAME_DT = 0.25;
const MAX_PIXEL_RATIO = 2;
/** Adaptive quality: average frame time (s) over a window above which 'high' drops to 'low'. */
const SLOW_FRAME_SECONDS = 1 / 36;
const QUALITY_WINDOW_FRAMES = 240;

const SILENT_TRACKS: [TrackAudioState, TrackAudioState, TrackAudioState, TrackAudioState] = [0, 1, 2, 3].map(() => ({
  present: false,
  speed: 1,
  life: 'alive',
  synced: true,
  transport: 0,
})) as [TrackAudioState, TrackAudioState, TrackAudioState, TrackAudioState];

function silentPulse(beat = 0): MusicPulse {
  return { beat, beatPulse: 0, barPulse: 0, levels: [0, 0, 0, 0], pitches: [0, 0, 0, 0], chord: 0 };
}

/** Minimal mount surface (an HTMLElement in the browser). */
export interface MountLike {
  append(...nodes: unknown[]): void;
}

export interface AppDeps {
  renderer: IRenderer;
  audio: IAudio;
  ui: IUi;
  input: GameInput;
  storage: SaveStorage | null;
  levels: readonly LevelDef[];
  /** Host for window-level listeners (resize, first gesture, visibility). Default: globalThis. */
  host: EventTarget | null;
}

/** Stand-in when WebGL cannot start: the menus and the HUD still work, the world is not drawn. */
class NullRenderer implements IRenderer {
  readonly canvas: HTMLCanvasElement;
  constructor() {
    const doc = (globalThis as { document?: Document }).document;
    this.canvas = (doc ? doc.createElement('canvas') : ({ addEventListener() {}, removeEventListener() {} } as unknown)) as HTMLCanvasElement;
  }
  loadLevel(): void {}
  render(): void {}
  resize(): void {}
  screenUpInWorld(): { x: number; y: number } {
    return { x: 0, y: -1 };
  }
  screenToWorld(px: number, py: number): { x: number; y: number } {
    return { x: px / 32, y: py / 32 };
  }
  setQuality(): void {}
  dispose(): void {}
}

export class App {
  readonly renderer: IRenderer;
  readonly audio: IAudio;
  readonly ui: IUi;
  readonly input: GameInput;
  readonly campaign: Campaign;

  private readonly storage: SaveStorage | null;
  private readonly host: EventTarget | null;
  private _screen: Screen = 'title';
  private _session: Session | null = null;
  private level: LevelDef | null = null;
  private loadout: ResolvedLoadout;
  /** Level currently built in the renderer, and its beat-zero picture for menus. */
  private shown: { id: string; idle: FrameSnapshot | null } | null = null;
  private recordAcc = 0;
  private lastTs: number | null = null;
  private raf: number | null = null;
  private pendingEvents: SimEvent[] = [];
  private tracksKey = '';
  private lastDevice: 'keyboard' | 'gamepad' | null = null;
  private lastFrame: { snap: FrameSnapshot; prev: FrameSnapshot; alpha: number } | null = null;
  private unlocked = false;
  private quality: 'low' | 'high' = 'high';
  private qualityAuto = true;
  private perf = { sum: 0, n: 0 };
  private disposed = false;
  private readonly listeners: [EventTarget, string, EventListener][] = [];

  constructor(mount: MountLike | null, deps: Partial<AppDeps> & Pick<AppDeps, 'renderer' | 'audio' | 'ui'>) {
    this.renderer = deps.renderer;
    this.audio = deps.audio;
    this.ui = deps.ui;
    this.host = deps.host === undefined ? ((globalThis as { addEventListener?: unknown }).addEventListener ? (globalThis as unknown as EventTarget) : null) : deps.host;
    this.storage = deps.storage === undefined ? defaultStorage() : deps.storage;
    this.input =
      deps.input ??
      createInput(this.renderer.canvas, {
        host: this.host ?? undefined,
        screenToWorld: (px, py) => this.renderer.screenToWorld(px, py),
      });
    this.campaign = new Campaign(deps.levels ?? LEVELS, loadSave(this.storage));
    this.loadout = this.campaign.resolvedLoadout();

    if (mount) mount.append(this.renderer.canvas, this.ui.root);
    this.ui.onIntent((intent) => this.onIntent(intent));
    this.applySettings(this.campaign.save.settings);
    this.applyQuality('high');
    this.ui.setCampaign(this.campaign.campaignModel());
    this.ui.setLoadout(this.campaign.loadoutModel());
    this.listenHost();
    this.resize();
    this.showMenu('title');
  }

  // ───────────────────────────── public surface ─────────────────────────────

  get screen(): Screen {
    return this._screen;
  }
  get session(): Session | null {
    return this._session;
  }
  get save(): SaveData {
    return this.campaign.save;
  }

  /** Start the requestAnimationFrame loop (browser only). */
  start(): void {
    const raf = (globalThis as { requestAnimationFrame?: (cb: (t: number) => void) => number }).requestAnimationFrame;
    if (!raf || this.raf !== null) return;
    const loop = (t: number): void => {
      if (this.disposed) return;
      this.frame(t);
      this.raf = raf(loop);
    };
    this.raf = raf(loop);
  }

  /** One animation frame at wall time `nowMs`. Public so tests and tools can drive the loop. */
  frame(nowMs: number): void {
    const dt = this.lastTs === null ? 0 : Math.min(MAX_FRAME_DT, Math.max(0, (nowMs - this.lastTs) / 1000));
    this.lastTs = nowMs;
    this.trackPerformance(dt);
    this.syncDevice();
    for (const a of this.input.drainActions()) this.onInputAction(a);

    const s = this._session;
    let alpha = 1;
    if (s && this._screen === 'play') {
      if (s.phase === 'recording') {
        alpha = this.runLocalTicks(s, dt);
      } else {
        s.advance(dt);
        // A count-in that just finished starts recording on the next frame from a clean accumulator.
      }
      this.consumeCues(s);
      for (const e of s.drainEvents()) this.pendingEvents.push(e);
    }
    this.present(dt, alpha);
  }

  /** Simulate `seconds` of wall time in fixed frames (tests / tools). */
  runFor(seconds: number, fps = 60): void {
    const step = 1000 / fps;
    let t = this.lastTs ?? 0;
    if (this.lastTs === null) this.frame(t);
    const n = Math.round(seconds * fps);
    for (let i = 0; i < n; i++) {
      t += step;
      this.frame(t);
    }
  }

  /** Route a UI intent (also used by tests). */
  onIntent(intent: UiIntent): void {
    this.unlockAudio();
    switch (intent.type) {
      case 'session':
        this.onSessionAction(intent.action);
        return;
      case 'openCampaign':
        this.leaveLevel();
        this.showMenu('campaign');
        return;
      case 'openLoadout':
        // GEAR-03: equipment changes between levels only; a finished level counts as "between".
        if (this._session && this._session.phase !== 'results') {
          this.ui.toast('Gear is locked until this level ends.', 'warn');
          return;
        }
        this.leaveLevel();
        this.ui.setLoadout(this.campaign.loadoutModel(true));
        this.showMenu('loadout');
        return;
      case 'openSettings':
        this.showMenu('settings');
        return;
      case 'openTitle':
        this.leaveLevel();
        this.showMenu('title');
        return;
      case 'playLevel':
        this.playLevel(intent.id);
        return;
      case 'equip':
        if (this.campaign.equip(intent.slot, intent.id)) {
          this.loadout = this.campaign.resolvedLoadout();
          this.persist();
          this.ui.setLoadout(this.campaign.loadoutModel());
          this.audio.ui('select');
        } else {
          this.ui.toast('That item cannot be equipped right now.', 'warn');
        }
        return;
      case 'setting': {
        const settings = { ...this.campaign.save.settings, [intent.key]: intent.value } as SaveData['settings'];
        this.campaign.setSettings(settings);
        this.applySettings(this.campaign.save.settings);
        this.persist();
        return;
      }
      case 'resume':
        if (this._screen === 'pause') this.setScreen('play');
        return;
      case 'eraseSave':
        this.leaveLevel();
        eraseStored(this.storage);
        this.campaign.replaceSave(freshSave());
        this.loadout = this.campaign.resolvedLoadout();
        this.persist();
        this.applySettings(this.campaign.save.settings);
        this.ui.setCampaign(this.campaign.campaignModel());
        this.ui.setLoadout(this.campaign.loadoutModel());
        return;
    }
  }

  /** Start (or restart) a level attempt. Returns false if it is locked or cannot run. */
  playLevel(id: string): boolean {
    const level = this.campaign.level(id);
    if (!level || !this.campaign.isUnlocked(id)) {
      this.ui.toast('That level is still locked.', 'warn');
      return false;
    }
    this.leaveLevel();
    this.campaign.beginLevel(id);
    this.loadout = this.campaign.resolvedLoadout();
    let session: Session;
    try {
      session = createSession({ level, loadout: this.loadout, skipBriefing: level.briefing.length === 0 });
    } catch (err) {
      this.campaign.endLevel();
      this.ui.toast(`This level cannot start: ${err instanceof Error ? err.message : String(err)}`, 'warn');
      return false;
    }
    this._session = session;
    this.level = level;
    this.showLevel(level, null);
    this.audio.loadLevel(level);
    this.audio.setMode('record');
    this.tracksKey = '';
    this.recordAcc = 0;
    this.pendingEvents = [];
    this.input.clearPresses();
    this.setScreen('play');
    return true;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    const caf = (globalThis as { cancelAnimationFrame?: (id: number) => void }).cancelAnimationFrame;
    if (this.raf !== null && caf) caf(this.raf);
    for (const [t, type, fn] of this.listeners) t.removeEventListener(type, fn);
    this.input.dispose();
    this.ui.dispose();
    this.audio.dispose();
    this.renderer.dispose();
  }

  // ───────────────────────────── loop pieces ─────────────────────────────

  private runLocalTicks(s: Session, dt: number): number {
    this.recordAcc += dt;
    let n = 0;
    while (this.recordAcc >= TICK && n < MAX_CATCHUP_TICKS && s.phase === 'recording') {
      const snap = s.currentFrame().snap;
      const live = snap.actors.find((a) => a.live);
      const sample = this.input.sample(this.renderer.screenUpInWorld(), live ? { x: live.x, y: live.y } : null);
      s.tickLocal(sample);
      this.recordAcc -= TICK;
      n++;
    }
    if (s.phase !== 'recording') {
      this.recordAcc = 0;
      return 1;
    }
    // A long hitch: drop the backlog rather than replaying it in a burst the player never saw.
    if (this.recordAcc >= TICK) this.recordAcc = this.recordAcc % TICK;
    return this.recordAcc / TICK;
  }

  private present(dt: number, alpha: number): void {
    const s = this._session;
    const events = this.pendingEvents;
    this.pendingEvents = [];
    if (s && (this._screen === 'play' || this._screen === 'pause' || this._screen === 'results')) {
      const playing = this._screen === 'play';
      const delay = playing ? this.campaign.save.settings.avOffsetMs / 1000 : 0;
      const f = s.currentFrame(alpha, delay);
      this.lastFrame = f;
      const view = s.view();
      const worldRate = playing ? view.worldRate : 0;
      const masterPlaying = playing && s.isPlaying();
      this.audio.setTransport(view.beat, masterPlaying ? worldRate : 0, masterPlaying);
      this.pushTracks(s.trackAudioStates());
      if (events.length) {
        this.audio.onEvents(events);
        this.deckFeedback(s, events);
      }
      const pulse = this.audio.pulse();
      this.ui.updateHud(view, pulse);
      const frame: RenderFrame = {
        snap: f.snap,
        prev: f.prev,
        alpha: f.alpha,
        dt,
        mode: this.viewMode(s.phase),
        events,
        worldRate,
        music: pulse,
        active: s.phase === 'countin' || s.phase === 'recording' ? view.active : null,
      };
      this.renderer.render(frame);
      return;
    }
    // Menus: the current level sits behind them, calm and still.
    const idle = this.shown?.idle;
    if (idle) {
      this.renderer.render({ snap: idle, prev: idle, alpha: 1, dt, mode: 'idle', events: [], worldRate: 0, music: silentPulse(), active: null });
    }
  }

  private viewMode(phase: SessionPhase): ViewMode {
    switch (phase) {
      case 'setup':
      case 'countin':
      case 'recording':
        return 'record';
      case 'review':
      case 'decision':
        return 'review';
      case 'cinematic':
      case 'results':
        return 'cinematic';
      default:
        return 'idle';
    }
  }

  private pushTracks(tracks: [TrackAudioState, TrackAudioState, TrackAudioState, TrackAudioState]): void {
    const key = tracks.map((t) => `${+t.present}${t.speed}${t.life}${+t.synced}${t.transport}`).join('|');
    if (key === this.tracksKey) return;
    this.tracksKey = key;
    this.audio.setTracks(tracks);
  }

  private deckFeedback(s: Session, events: SimEvent[]): void {
    for (const e of events) {
      if (e.tape === undefined) continue;
      switch (e.type) {
        case 'swing':
          this.ui.deckEvent(e.tape, e.detail === 'heavy' ? 'heavy' : 'light');
          break;
        case 'dodge':
          this.ui.deckEvent(e.tape, 'dodge');
          break;
        case 'fire':
          this.ui.deckEvent(e.tape, 'ranged');
          break;
        case 'interact':
        case 'interactFail':
          this.ui.deckEvent(e.tape, 'interact');
          break;
        case 'selfDeath':
          this.ui.deckEvent(e.tape, 'death');
          if (s.phase === 'recording' && e.tape === s.activeIndex) {
            // GHOST-01: death never ends the take.
            this.ui.toast(`Tape ${TAPE_NAMES[e.tape]} died. Keep recording: you are a ghost for this take.`, 'warn');
          }
          break;
        case 'desync':
          this.ui.deckEvent(e.tape, 'desync');
          break;
        case 'resync':
          this.ui.deckEvent(e.tape, 'resync');
          break;
        default:
          break;
      }
    }
  }

  private consumeCues(s: Session): void {
    for (const c of s.drainCues()) this.onCue(s, c);
  }

  private onCue(s: Session, c: SessionCue): void {
    switch (c.kind) {
      case 'count':
        this.audio.countIn(c.n);
        return;
      case 'ui':
        this.audio.ui(c.sound);
        return;
      case 'takeAborted':
        this.ui.toast('Take abandoned. Takes always restart from beat zero.', 'info');
        return;
      case 'resolved':
        return;
      case 'phase':
        if (c.phase === 'recording') {
          // The press that started the count-in must not become the first recorded action.
          this.input.clearPresses();
          this.recordAcc = 0;
        }
        this.audio.setMode(c.phase === 'review' || c.phase === 'decision' ? 'review' : c.phase === 'cinematic' || c.phase === 'results' ? 'cinematic' : 'record');
        if (c.phase === 'results') this.onLevelWon(s);
        return;
    }
  }

  private onLevelWon(s: Session): void {
    const level = s.level;
    const clear = this.campaign.recordClear(level.id);
    // The attempt is over: gear may change from the results screen (GEAR-03).
    this.campaign.endLevel();
    this.persist();
    const next = this.campaign.nextLevel(level.id);
    this.ui.setResults({
      level,
      outcome: s.outcome!,
      tapesUsed: s.tapesUsed,
      loot: clear.loot,
      hasNext: next !== null,
      nextId: next?.id,
    });
    this.ui.setCampaign(this.campaign.campaignModel());
    this.ui.setLoadout(this.campaign.loadoutModel());
    for (const it of clear.loot) this.ui.toast(`New gear: ${it.name}`, 'good');
    if (clear.loot.length > 0) this.audio.ui('loot');
    this.setScreen('results');
  }

  // ───────────────────────────── input routing ─────────────────────────────

  private onInputAction(a: InputAction): void {
    this.unlockAudio();
    if (this._screen !== 'play') {
      if (this._screen === 'pause' && a === 'pause') {
        this.ui.navigate('back');
        return;
      }
      switch (a) {
        case 'up':
        case 'down':
        case 'left':
        case 'right':
        case 'accept':
        case 'back':
          this.ui.navigate(a);
          return;
        case 'pause':
          this.ui.navigate('back');
          return;
        default:
          return;
      }
    }
    const s = this._session;
    if (!s) return;
    if (a === 'pause') {
      this.pause();
      return;
    }
    // While a take is live, only pause leaves it; everything else is gameplay (sampled per tick).
    if (s.phase === 'recording' || s.phase === 'countin') return;
    switch (a) {
      case 'accept':
        this.onSessionAction(this.acceptAction(s));
        return;
      case 'left':
        if (s.phase === 'setup') this.onSessionAction('speedDown');
        return;
      case 'right':
        if (s.phase === 'setup') this.onSessionAction('speedUp');
        return;
      case 'up':
      case 'down':
      case 'back':
        return;
      default:
        this.onSessionAction(a);
    }
  }

  /** What Enter / Space / A means in each phase. */
  private acceptAction(s: Session): SessionAction {
    switch (s.phase) {
      case 'briefing':
        return 'start';
      case 'setup':
        return 'record';
      case 'review':
      case 'cinematic':
        return 'skip';
      case 'decision':
        return s.actions().includes('commit') ? 'commit' : 'retryTake';
      default:
        return 'continue';
    }
  }

  private onSessionAction(action: SessionAction): void {
    const s = this._session;
    if (action === 'quit') {
      this.leaveLevel();
      this.showMenu('campaign');
      return;
    }
    if (action === 'continue') {
      if (s && s.phase !== 'results') return;
      const level = this.level;
      this.leaveLevel();
      if (level && this.campaign.nextLevel(level.id) === null && this.campaign.allCleared()) this.showMenu('ending');
      else this.showMenu('campaign');
      return;
    }
    if (!s) return;
    if (action === 'resetAll' && this._screen === 'pause') {
      // Pause menu "restart": the take (if any) was already abandoned when pausing.
      s.restartAttempt();
      this.consumeCues(s);
      return;
    }
    if (this._screen !== 'play') return;
    if (s.act(action)) this.consumeCues(s);
  }

  private pause(): void {
    const s = this._session;
    if (!s || this._screen !== 'play') return;
    // OPEN-21: no tactical pause mid-take; pausing abandons the take.
    if (s.phase === 'countin' || s.phase === 'recording') s.abortTake();
    this.consumeCues(s);
    this.audio.setTransport(s.view().beat, 0, false);
    this.setScreen('pause');
  }

  // ───────────────────────────── screens ─────────────────────────────

  private setScreen(screen: Screen): void {
    this._screen = screen;
    this.ui.showScreen(screen);
    if (screen !== 'play' && screen !== 'pause' && screen !== 'results') this.audio.setMode('menu');
  }

  private showMenu(screen: Screen): void {
    if (screen === 'campaign' || screen === 'title' || screen === 'ending') this.ui.setCampaign(this.campaign.campaignModel());
    const backdrop = this.campaign.levels[this.campaign.currentIndex()];
    if (backdrop && !this._session) this.showLevel(backdrop, this.idleSnapshot(backdrop));
    this.setScreen(screen);
  }

  /** End the current attempt (if any) and silence it. Gear unlocks again. */
  private leaveLevel(): void {
    if (!this._session) return;
    this._session = null;
    this.level = null;
    this.campaign.endLevel();
    this.pendingEvents = [];
    this.tracksKey = '';
    this.audio.setTransport(0, 0, false);
    this.audio.setTracks(SILENT_TRACKS);
    this.audio.setMode('menu');
    // The renderer still holds the level; its beat-zero picture becomes the menu backdrop.
    if (this.shown && this.shown.idle === null) {
      const level = this.campaign.level(this.shown.id);
      if (level) this.shown.idle = this.idleSnapshot(level);
    }
  }

  private showLevel(level: LevelDef, idle: FrameSnapshot | null): void {
    if (!this.shown || this.shown.id !== level.id) {
      try {
        this.renderer.loadLevel(level, this.loadout);
      } catch (err) {
        this.ui.toast(`Could not draw ${level.name}: ${err instanceof Error ? err.message : String(err)}`, 'warn');
      }
    }
    this.shown = { id: level.id, idle };
  }

  private idleSnapshot(level: LevelDef): FrameSnapshot | null {
    try {
      return createSim({ level, loadout: this.loadout, tapes: [] }).snapshot();
    } catch {
      return null;
    }
  }

  // ───────────────────────────── settings, save, host ─────────────────────────────

  /**
   * Render quality. SaveData has no quality field, so it is chosen live: 'high' until frames run
   * slow during play, then 'low' for the rest of the session. Calling this pins the choice.
   */
  setQuality(q: 'low' | 'high'): void {
    this.qualityAuto = false;
    this.applyQuality(q);
  }

  get renderQuality(): 'low' | 'high' {
    return this.quality;
  }

  private applyQuality(q: 'low' | 'high'): void {
    this.quality = q;
    this.renderer.setQuality(q);
  }

  private trackPerformance(dt: number): void {
    if (!this.qualityAuto || this.quality === 'low' || this._screen !== 'play' || dt <= 0) return;
    this.perf.sum += dt;
    this.perf.n++;
    if (this.perf.n < QUALITY_WINDOW_FRAMES) return;
    const avg = this.perf.sum / this.perf.n;
    this.perf = { sum: 0, n: 0 };
    if (avg > SLOW_FRAME_SECONDS) {
      this.applyQuality('low');
      this.ui.toast('Switched to low graphics quality to keep the beat steady.', 'info');
    }
  }

  private applySettings(s: SaveData['settings']): void {
    this.audio.setVolumes(s.master, s.music, s.sfx);
    this.renderer.setScreenShake?.(s.screenShake);
    this.ui.setSettings(s);
  }

  private persist(): void {
    writeSave(this.campaign.save, this.storage);
  }

  private syncDevice(): void {
    const d = this.input.device();
    if (d !== this.lastDevice) {
      this.lastDevice = d;
      this.ui.setDevice?.(d);
    }
  }

  private unlockAudio(): void {
    if (this.unlocked) return;
    this.unlocked = true;
    this.audio.unlock().catch(() => {
      // Audio refused (no device / autoplay policy): the game is fully playable silently.
    });
  }

  private resize(): void {
    const g = globalThis as { innerWidth?: number; innerHeight?: number; devicePixelRatio?: number };
    const w = g.innerWidth ?? 1280;
    const h = g.innerHeight ?? 720;
    const dpr = Math.min(MAX_PIXEL_RATIO, Math.max(1, g.devicePixelRatio ?? 1));
    this.renderer.resize(w, h, dpr);
  }

  private listenHost(): void {
    const host = this.host;
    if (!host) return;
    const on = (t: EventTarget, type: string, fn: EventListener): void => {
      t.addEventListener(type, fn);
      this.listeners.push([t, type, fn]);
    };
    on(host, 'resize', () => this.resize());
    // Audio may only start from a user gesture.
    on(host, 'pointerdown', () => this.unlockAudio());
    on(host, 'keydown', () => this.unlockAudio());
    // A hidden tab stops the frame loop; a take must not silently continue or stall half-recorded.
    on(host, 'visibilitychange', () => {
      const doc = (globalThis as { document?: { visibilityState?: string } }).document;
      if (doc?.visibilityState === 'hidden') this.pause();
    });
    on(host, 'blur', () => {
      if (this._session && (this._session.phase === 'recording' || this._session.phase === 'countin')) this.pause();
    });
  }

  /** Last frame handed to the renderer (smoke tests). */
  get lastRenderedFrame(): { snap: FrameSnapshot; prev: FrameSnapshot; alpha: number } | null {
    return this.lastFrame;
  }
}

/**
 * Build the app from facade factories, falling back to a world-less renderer when WebGL cannot
 * start (the menus and HUD keep working).
 */
export function buildApp(
  mount: MountLike | null,
  factories: { createRenderer: () => IRenderer; createAudio: () => IAudio; createUi: () => IUi },
): App {
  let renderer: IRenderer;
  let webglFailed = false;
  try {
    renderer = factories.createRenderer();
  } catch {
    renderer = new NullRenderer();
    webglFailed = true;
  }
  const app = new App(mount, { renderer, audio: factories.createAudio(), ui: factories.createUi() });
  if (webglFailed) app.ui.toast('WebGL is unavailable: the world cannot be drawn in this browser.', 'warn');
  return app;
}
