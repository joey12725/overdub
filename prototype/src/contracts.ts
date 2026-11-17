/**
 * OVERDUB — module facades.
 *
 * Each top-level module exports exactly one factory matching an interface below. The game layer
 * (src/game) is the only place that wires modules together; modules never import each other
 * (render must not import audio, ui must not import render, …). Everyone may import src/core/types.ts.
 *
 * Same editing rules as src/core/types.ts: add, never rename/remove.
 */
import type {
  ActionKind,
  FrameSnapshot,
  GearItem,
  GearSlot,
  LevelDef,
  Loadout,
  Outcome,
  PlayerInput,
  ResolvedLoadout,
  SaveData,
  SessionAction,
  SessionView,
  SimEvent,
  TapeIndex,
  TapeSpeed,
  LifeState,
} from './core/types';

// ───────────────────────────── core (src/core/index.ts) ─────────────────────────────
//
//   export function createSim(config: SimConfig): ISim
//   export function resolveEncounter(config: Omit<SimConfig, 'live'>): Resolution
//   export function buildBossMemory(level: LevelDef, committed: Tape[]): BossMemory
//   export function tapePhaseAt(tape: Pick<Tape,'speed'|'endMode'|'ticks'>, sub: number): TapePhase
//   export function horizonSubs(level: LevelDef): number
//   export function tapeTicks(level: LevelDef): number
//   export function subToBeat(level: LevelDef, sub: number): number
//
// ───────────────────────────── content (src/content/index.ts) ─────────────────────────────
//
//   export const LEVELS: LevelDef[]            // fixed campaign order
//   export const GEAR: Record<string, GearItem>
//   export const BASE_LOADOUT: Loadout
//   export function resolveLoadout(loadout: Loadout): ResolvedLoadout
//   export function describeLoadout(loadout: Loadout): string[]

// ───────────────────────────── render (src/render/index.ts) ─────────────────────────────

export type ViewMode =
  /** Player is in control: readability first. */
  | 'record'
  /** Watching a non-winning combined run. */
  | 'review'
  /** Winning performance: cinematic camera + music-linked flourishes (CINE-03, MUSIC-13). */
  | 'cinematic'
  /** Calm framing behind menus / briefing. */
  | 'idle';

/** Per-frame presentation inputs that are not part of the simulation. */
export interface RenderFrame {
  /** Snapshot to draw. */
  snap: FrameSnapshot;
  /** Previous snapshot, for interpolation; may equal `snap`. */
  prev: FrameSnapshot;
  /** 0..1 interpolation factor from prev to snap. */
  alpha: number;
  /** Wall-clock seconds since the last render call. */
  dt: number;
  mode: ViewMode;
  /** Events that happened since the last render call (hit sparks, shakes, flashes). */
  events: SimEvent[];
  /** How fast master time passes relative to wall time (drives world-speed visual treatment). */
  worldRate: number;
  /** Live music analysis for music-linked visuals (runes, panels, flourishes). */
  music: MusicPulse;
  /** Which cassette is under live control, if any (gets the camera + highlight). */
  active: TapeIndex | null;
}

/** Cheap per-frame musical state shared with visuals. All values are safe defaults when audio is off. */
export interface MusicPulse {
  /** Master beat position (float). */
  beat: number;
  /** 0..1 saw that hits 1 on each beat and decays. */
  beatPulse: number;
  /** 0..1 saw that hits 1 on each bar. */
  barPulse: number;
  /** Per-cassette layer level 0..1 (recent note energy), index = tape. */
  levels: [number, number, number, number];
  /** Per-cassette most recent normalised pitch 0..1 (for contour drawing). */
  pitches: [number, number, number, number];
  /** Current chord degree index within the level progression. */
  chord: number;
}

export interface IRenderer {
  /** Canvas element to mount. */
  readonly canvas: HTMLCanvasElement;
  /** Build the scene for a level (tiles, props, lighting by theme). Disposes the previous level. */
  loadLevel(level: LevelDef, loadout: ResolvedLoadout): void;
  render(frame: RenderFrame): void;
  resize(width: number, height: number, pixelRatio: number): void;
  /**
   * World-space direction (unit vector, sim axes) that the screen-up direction maps to; lets the
   * input layer turn WASD / stick into camera-relative movement.
   */
  screenUpInWorld(): { x: number; y: number };
  /** Convert a pointer position (CSS pixels relative to the canvas) to a point on the floor plane. */
  screenToWorld(px: number, py: number): { x: number; y: number };
  setQuality(q: 'low' | 'high'): void;
  /** Honour SaveData.settings.screenShake; layers' RenderCtx.shake() requests are ignored when off. */
  setScreenShake?(enabled: boolean): void;
  dispose(): void;
}
//   export function createRenderer(): IRenderer

// ───────────────────────────── audio (src/audio/index.ts) ─────────────────────────────

/** State of one cassette's music layer for this instant. */
export interface TrackAudioState {
  /** Layer is silent when false (cassette not yet recorded / not armed). */
  present: boolean;
  speed: TapeSpeed;
  life: LifeState;
  synced: boolean;
  /** 1 forward, -1 reversing (retrograde contour), 0 stopped. */
  transport: 1 | -1 | 0;
}

export interface IAudio {
  /** Must be called from a user gesture; resumes the AudioContext. */
  unlock(): Promise<void>;
  /** Load a level's key, progression and four cassette functions. */
  loadLevel(level: LevelDef): void;
  /**
   * Called every frame. Tells the music where the master timeline is and how fast it is moving
   * relative to wall time (`rate` = master seconds per wall second; 0 pauses the music).
   * The audio layer schedules notes slightly ahead from this.
   */
  setTransport(masterBeat: number, rate: number, playing: boolean): void;
  setTracks(tracks: [TrackAudioState, TrackAudioState, TrackAudioState, TrackAudioState]): void;
  /**
   * Gameplay sounds. The audio layer plays them roughly quantised to a sixteenth-note grid
   * (MUSIC-05) and pitched from the current chord; it never delays or alters gameplay (MUSIC-07).
   */
  onEvents(events: SimEvent[]): void;
  /** Count-in tick: n is 5, 6, 7 or 8 ("five, six, seven, eight"). */
  countIn(n: 5 | 6 | 7 | 8): void;
  /** UI feedback blips. */
  ui(kind: 'move' | 'select' | 'back' | 'commit' | 'retry' | 'reset' | 'win' | 'fail' | 'loot' | 'speed'): void;
  /** Cinematic mode opens the mix up (wider, brighter) without changing the notes. */
  setMode(mode: 'menu' | 'record' | 'review' | 'cinematic'): void;
  setVolumes(master: number, music: number, sfx: number): void;
  pulse(): MusicPulse;
  dispose(): void;
}
//   export function createAudio(): IAudio

// ───────────────────────────── ui (src/ui/index.ts) ─────────────────────────────

export interface LoadoutScreenModel {
  inventory: GearItem[];
  loadout: Loadout;
  /** Player-readable summary lines of the combined effects. */
  summary: string[];
  /** Item ids picked up since the screen was last opened. */
  fresh: string[];
}

export interface CampaignScreenModel {
  levels: {
    level: LevelDef;
    cleared: boolean;
    unlocked: boolean;
    /**
     * Optional: the resolved GearItems of `level.loot`, so the path can name what was found on a
     * cleared level. Absent = the path shows only how many items the level holds.
     */
    loot?: GearItem[];
  }[];
  /** Index of the next uncleared level. */
  current: number;
}

export interface ResultsModel {
  level: LevelDef;
  outcome: Outcome;
  tapesUsed: number;
  loot: GearItem[];
  hasNext: boolean;
  /**
   * Optional: id of the next level on the path. When present, "Next level" emits playLevel(nextId);
   * when absent it emits session 'continue' (back to the path, focused on the next level).
   */
  nextId?: string;
}

export type UiIntent =
  | { type: 'session'; action: SessionAction }
  | { type: 'openCampaign' }
  | { type: 'openLoadout' }
  | { type: 'openSettings' }
  | { type: 'openTitle' }
  | { type: 'playLevel'; id: string }
  | { type: 'equip'; slot: GearSlot; id: string }
  | { type: 'setting'; key: keyof SaveData['settings']; value: number | boolean }
  | { type: 'resume' }
  | { type: 'eraseSave' };

export type Screen = 'title' | 'campaign' | 'loadout' | 'settings' | 'play' | 'pause' | 'results' | 'ending';

export interface IUi {
  /** Root element to mount above the canvas. */
  readonly root: HTMLElement;
  /** Emits player intents from clicks / menu keys. The game layer owns all state changes. */
  onIntent(handler: (intent: UiIntent) => void): void;
  showScreen(screen: Screen): void;
  /** In-level HUD: four cassette decks, master beat ruler, objective, count-in, decision prompts. */
  updateHud(view: SessionView, pulse: MusicPulse): void;
  setCampaign(model: CampaignScreenModel): void;
  setLoadout(model: LoadoutScreenModel): void;
  setResults(model: ResultsModel): void;
  setSettings(settings: SaveData['settings']): void;
  /** Short toast ("Tape B desynced", "New gear: …"). */
  toast(text: string, tone?: 'info' | 'good' | 'warn'): void;
  /** Flash a deck when its self performs an action / dies / desyncs. */
  deckEvent(tape: TapeIndex, kind: ActionKind | 'death' | 'desync' | 'resync'): void;
  /** Menu navigation from keyboard / gamepad when a menu screen is up. */
  navigate(dir: 'up' | 'down' | 'left' | 'right' | 'accept' | 'back'): void;
  dispose(): void;
  /**
   * Optional: which device the player is using, so the HUD and menus show matching button prompts.
   * Call it whenever IInput.device() changes.
   */
  setDevice?(device: 'keyboard' | 'gamepad'): void;
}
//   export function createUi(): IUi

// ───────────────────────────── game (src/game) ─────────────────────────────

/** Raw device state turned into sim input + menu navigation. Owned by src/game/input.ts. */
export interface IInput {
  /** Sample the devices for one local tick. `screenUp` comes from IRenderer.screenUpInWorld(). */
  sample(screenUp: { x: number; y: number }, actorPos: { x: number; y: number } | null): PlayerInput;
  /** Session / menu actions requested since the last call (edge-triggered). */
  drainActions(): (SessionAction | 'pause' | 'up' | 'down' | 'left' | 'right' | 'accept' | 'back')[];
  /** Used by the HUD for button prompts. */
  device(): 'keyboard' | 'gamepad';
  dispose(): void;
}
