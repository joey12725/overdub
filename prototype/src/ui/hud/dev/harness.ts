/**
 * Standalone HUD harness: drives createHud() with a fake SessionView through every phase and deck
 * state. Open /src/ui/hud/dev/harness.html under `npx vite`.
 *
 * Query params: scene=<id> (start there), t=<seconds> (freeze scene time, for screenshots),
 * bg=warm|dark, device=keyboard|gamepad, auto=0 (do not advance scenes).
 */
import {
  BEATS_PER_BAR,
  type ActionKind,
  type DeckStatus,
  type DeckView,
  type EndMode,
  type LevelDef,
  type LifeState,
  type Outcome,
  type SessionAction,
  type SessionPhase,
  type SessionView,
  type TapeIndex,
  type TapeSpeed,
} from '../../../core/types';
import type { MusicPulse } from '../../../contracts';
import { createHud, HUD_ACTION_EVENT, type HudActionDetail } from '../index';
import { recordingTicks } from '../model';

const BPM = 120;
const BARS = 4;
const LEVEL: LevelDef = {
  id: 'harness',
  index: 2,
  name: 'Gutter Cathedral',
  tagline: 'Two doors, one switch, and a wall that only a fast tape can break.',
  theme: 'upper',
  bpm: BPM,
  bars: BARS,
  horizonBars: 8,
  maxTapes: 4,
  speeds: [0.5, 1, 2, 4],
  endModes: ['stop', 'repeat', 'reverse'],
  map: ['#####', '#...#', '#####'],
  start: { x: 2, y: 1 },
  entities: [],
  objective: { type: 'eliminate', text: 'Break the wall and clear the nave', targets: [] },
  music: {
    root: 0,
    scale: 'minor',
    progression: [0, 5, 3, 4],
    tracks: [
      { role: 'drums', formula: 'x' },
      { role: 'bass', formula: 'x' },
      { role: 'melody', formula: 'x' },
      { role: 'chord', formula: 'x' },
    ],
  },
  loot: [],
  briefing: [
    'Every take starts at beat zero. Your earlier tapes play alongside you.',
    'A 2× tape hits twice as hard — the cracked wall needs one.',
    'Death does not end the take: keep playing as a ghost.',
  ],
  hints: { 2: 'Tape A opens the door at bar 2 — be through it before it closes.' },
};
const HORIZON_BEATS = LEVEL.horizonBars * BEATS_PER_BAR;
const TICKS = recordingTicks(BARS, BPM);

const MARK_PATTERNS: { tick: number; kind: ActionKind }[][] = [
  [
    { tick: 30, kind: 'light' },
    { tick: 75, kind: 'light' },
    { tick: 140, kind: 'interact' },
    { tick: 210, kind: 'dodge' },
    { tick: 290, kind: 'heavy' },
    { tick: 380, kind: 'ranged' },
  ],
  [
    { tick: 50, kind: 'dodge' },
    { tick: 120, kind: 'heavy' },
    { tick: 200, kind: 'light' },
    { tick: 260, kind: 'light' },
    { tick: 330, kind: 'ability' },
    { tick: 430, kind: 'heavy' },
  ],
  [
    { tick: 60, kind: 'ranged' },
    { tick: 150, kind: 'interact' },
    { tick: 240, kind: 'heavy' },
    { tick: 360, kind: 'dodge' },
  ],
  [
    { tick: 40, kind: 'light' },
    { tick: 180, kind: 'heavy' },
    { tick: 300, kind: 'interact' },
  ],
];

interface DeckSpec {
  status: DeckStatus;
  speed?: TapeSpeed;
  endMode?: EndMode;
  life?: LifeState | null;
  synced?: boolean;
  stateMarks?: DeckView['stateMarks'];
  /** For a live recording deck: marks recorded up to this local tick. */
  marksUpTo?: number;
}

/** Playhead on a tape at master beat `beat` (mirrors the architecture's end-behaviour rules). */
function phaseAt(speed: TapeSpeed, endMode: EndMode, beat: number): { p: number; dir: 1 | -1 | 0 } {
  const span = (BARS * BEATS_PER_BAR) / speed;
  if (beat <= 0) return { p: 0, dir: 0 };
  const tr = Math.floor(beat / span);
  const frac = (beat - tr * span) / span;
  if (endMode === 'stop') return tr >= 1 ? { p: 1, dir: 0 } : { p: frac, dir: 1 };
  if (endMode === 'repeat') return { p: frac, dir: 1 };
  return tr % 2 === 1 ? { p: 1 - frac, dir: -1 } : { p: frac, dir: 1 };
}

function deck(i: TapeIndex, s: DeckSpec, beat: number, worldRate: number, playing: boolean): DeckView {
  const speed = s.speed ?? null;
  const endMode = s.endMode ?? (speed !== null ? 'stop' : null);
  let localProgress = 0;
  let transport: 1 | -1 | 0 = 0;
  if (speed !== null && endMode !== null && (s.status === 'committed' || s.status === 'pending' || s.status === 'recording')) {
    const ph = phaseAt(speed, endMode, beat);
    localProgress = ph.p;
    transport = playing ? ph.dir : 0;
  }
  const marks =
    s.status === 'recording'
      ? MARK_PATTERNS[i].filter((m) => m.tick <= (s.marksUpTo ?? 0))
      : s.status === 'committed' || s.status === 'pending'
        ? MARK_PATTERNS[i]
        : [];
  return {
    index: i,
    status: s.status,
    speed,
    endMode,
    localProgress,
    transport,
    // Local tape seconds per viewer second: master rate × tape speed.
    reelRate: speed !== null ? speed * worldRate : 0,
    life: s.life === undefined ? (s.status === 'committed' || s.status === 'pending' || s.status === 'recording' ? 'alive' : null) : s.life,
    synced: s.synced ?? true,
    spanBars: speed !== null ? BARS / speed : 0,
    marks,
    stateMarks: s.stateMarks ?? [],
  };
}

interface Frame {
  phase: SessionPhase;
  active: TapeIndex | null;
  beat: number;
  worldRate: number;
  count?: 0 | 5 | 6 | 7 | 8;
  decks: [DeckSpec, DeckSpec, DeckSpec, DeckSpec];
  actions: SessionAction[];
  outcome?: Outcome | null;
  objective?: { complete: boolean; progress: number; survivors: number };
  threatBeats?: number[];
  hint?: string | null;
  playing?: boolean;
}

interface Scene {
  id: string;
  label: string;
  duration: number;
  frame(t: number): Frame;
}

const SETUP_ACTIONS: SessionAction[] = ['speedUp', 'speedDown', 'cycleEndMode', 'record', 'quit'];
const cyc = <T,>(arr: readonly T[], t: number, every: number): T => arr[Math.floor(t / every) % arr.length];

const SCENES: Scene[] = [
  {
    id: 'briefing',
    label: 'briefing',
    duration: 4,
    frame: () => ({
      phase: 'briefing',
      active: null,
      beat: 0,
      worldRate: 0,
      decks: [{ status: 'empty' }, { status: 'empty' }, { status: 'empty' }, { status: 'empty' }],
      actions: ['start', 'quit'],
    }),
  },
  {
    id: 'setupA',
    label: 'setup A (speed cycling)',
    duration: 7,
    frame: (t) => ({
      phase: 'setup',
      active: 0,
      beat: 0,
      worldRate: 0,
      decks: [
        { status: 'armed', speed: cyc([1, 2, 4, 0.5] as TapeSpeed[], t, 1.6), endMode: cyc(['stop', 'repeat', 'reverse'] as EndMode[], t, 2.3), life: null },
        { status: 'empty' },
        { status: 'empty' },
        { status: 'empty' },
      ],
      actions: SETUP_ACTIONS,
    }),
  },
  {
    id: 'countin',
    label: 'count-in',
    duration: 2,
    frame: (t) => ({
      phase: 'countin',
      active: 0,
      beat: 0,
      worldRate: 0,
      count: ([5, 6, 7, 8] as const)[Math.min(3, Math.floor(t / 0.5))],
      decks: [{ status: 'armed', speed: 2, endMode: 'repeat', life: null }, { status: 'empty' }, { status: 'empty' }, { status: 'empty' }],
      actions: [],
    }),
  },
  {
    id: 'recA',
    label: 'recording A at 2×',
    duration: 8,
    frame: (t) => {
      // 2× tape: wall time = local time; world (and ruler) at 0.5×.
      const local = t / 8;
      const beat = local * (BARS * BEATS_PER_BAR) / 2;
      return {
        phase: 'recording',
        active: 0,
        beat,
        worldRate: 0.5,
        decks: [
          { status: 'recording', speed: 2, endMode: 'repeat', marksUpTo: local * TICKS },
          { status: 'empty' },
          { status: 'empty' },
          { status: 'empty' },
        ],
        actions: ['quit'],
        playing: true,
        threatBeats: [6, 10, 14].filter((b) => b > beat),
        objective: { complete: false, progress: Math.min(0.5, local), survivors: 1 },
      };
    },
  },
  {
    id: 'reviewA',
    label: 'review',
    duration: 6,
    frame: (t) => ({
      phase: 'review',
      active: 0,
      beat: (t / 6) * HORIZON_BEATS,
      worldRate: 1,
      decks: [{ status: 'pending', speed: 2, endMode: 'repeat' }, { status: 'empty' }, { status: 'empty' }, { status: 'empty' }],
      actions: ['skip', 'endAttempt'],
      playing: true,
      objective: { complete: false, progress: 0.5, survivors: 1 },
    }),
  },
  {
    id: 'decisionA',
    label: 'decision (fail)',
    duration: 4,
    frame: () => ({
      phase: 'decision',
      active: 0,
      beat: HORIZON_BEATS,
      worldRate: 0,
      decks: [{ status: 'pending', speed: 2, endMode: 'repeat' }, { status: 'empty' }, { status: 'empty' }, { status: 'empty' }],
      actions: ['retryTake', 'commit', 'resetAll'],
      outcome: {
        win: false,
        objectiveComplete: false,
        survivors: [0],
        reason: 'objective',
        notes: ['Tape A broke the wall at bar 3, beat 2', 'Two grunts were still standing when the horizon ended'],
      },
      objective: { complete: false, progress: 0.5, survivors: 1 },
    }),
  },
  {
    id: 'setupB',
    label: 'setup B (A committed)',
    duration: 4,
    frame: (t) => ({
      phase: 'setup',
      active: 1,
      beat: 0,
      worldRate: 0,
      decks: [
        { status: 'committed', speed: 2, endMode: 'repeat', life: null },
        { status: 'armed', speed: cyc([0.5, 1] as TapeSpeed[], t, 2), endMode: 'reverse', life: null },
        { status: 'empty' },
        { status: 'empty' },
      ],
      actions: SETUP_ACTIONS,
      hint: LEVEL.hints?.[2] ?? null,
    }),
  },
  {
    id: 'recBdead',
    label: 'recording B — died (recGhost)',
    duration: 8,
    frame: (t) => {
      const local = t / 8;
      const beat = local * BARS * BEATS_PER_BAR; // 1× tape
      const died = local > 0.35;
      return {
        phase: 'recording',
        active: 1,
        beat,
        worldRate: 1,
        decks: [
          { status: 'committed', speed: 2, endMode: 'repeat' },
          {
            status: 'recording',
            speed: 1,
            endMode: 'reverse',
            life: died ? 'recGhost' : 'alive',
            marksUpTo: local * TICKS,
            stateMarks: died ? [{ beat: 0.35 * 16, kind: 'death' }] : [],
          },
          { status: 'empty' },
          { status: 'empty' },
        ],
        actions: ['quit'],
        playing: true,
        objective: { complete: false, progress: 0.25, survivors: died ? 1 : 2 },
      };
    },
  },
  {
    id: 'gallery',
    label: 'state gallery (review)',
    duration: 10,
    frame: (t) => {
      const beat = (t / 10) * HORIZON_BEATS;
      return {
        phase: 'review',
        active: 3,
        beat,
        worldRate: 1,
        decks: [
          { status: 'committed', speed: 2, endMode: 'repeat', stateMarks: [] },
          { status: 'committed', speed: 1, endMode: 'reverse', life: beat > 9 && beat < 18 ? 'alive' : 'alive', synced: !(beat > 9 && beat < 18), stateMarks: [{ beat: 9, kind: 'desync' }, { beat: 18, kind: 'resync' }] },
          { status: 'committed', speed: 4, endMode: 'stop', life: beat > 20 ? 'ghost' : 'alive', stateMarks: [{ beat: 20, kind: 'death' }] },
          { status: 'pending', speed: 0.5, endMode: 'stop' },
        ],
        actions: ['skip', 'endAttempt'],
        playing: true,
        threatBeats: [8, 12, 16, 24].filter((b) => b > beat),
        objective: { complete: beat > 26, progress: Math.min(1, beat / 26), survivors: beat > 20 ? 3 : 4 },
      };
    },
  },
  {
    id: 'decisionWin',
    label: 'decision (win, last tape)',
    duration: 4,
    frame: () => ({
      phase: 'decision',
      active: 3,
      beat: HORIZON_BEATS,
      worldRate: 0,
      decks: [
        { status: 'committed', speed: 2, endMode: 'repeat' },
        { status: 'committed', speed: 1, endMode: 'reverse' },
        { status: 'committed', speed: 4, endMode: 'stop', life: 'ghost', stateMarks: [{ beat: 20, kind: 'death' }] },
        { status: 'pending', speed: 0.5, endMode: 'stop' },
      ],
      actions: ['retryTake', 'commit', 'resetAll'],
      outcome: {
        win: true,
        objectiveComplete: true,
        survivors: [0, 1, 3],
        notes: ['Tape C died at bar 6 — the others carried it'],
      },
      objective: { complete: true, progress: 1, survivors: 3 },
    }),
  },
  {
    id: 'cinematic',
    label: 'cinematic (slim)',
    duration: 8,
    frame: (t) => {
      const beat = (t / 8) * HORIZON_BEATS;
      return {
        phase: 'cinematic',
        active: null,
        beat,
        worldRate: 1,
        decks: [
          { status: 'committed', speed: 2, endMode: 'repeat' },
          { status: 'committed', speed: 1, endMode: 'reverse', synced: !(beat > 9 && beat < 18), stateMarks: [{ beat: 9, kind: 'desync' }, { beat: 18, kind: 'resync' }] },
          { status: 'committed', speed: 4, endMode: 'stop', life: beat > 20 ? 'ghost' : 'alive', stateMarks: [{ beat: 20, kind: 'death' }] },
          { status: 'committed', speed: 0.5, endMode: 'stop' },
        ],
        actions: [],
        playing: true,
        objective: { complete: beat > 26, progress: Math.min(1, beat / 26), survivors: 3 },
      };
    },
  },
  {
    id: 'tutorial',
    label: 'one-tape tutorial setup',
    duration: 3,
    frame: () => ({
      phase: 'setup',
      active: 0,
      beat: 0,
      worldRate: 0,
      decks: [{ status: 'armed', speed: 1, endMode: 'stop', life: null }, { status: 'unavailable' }, { status: 'unavailable' }, { status: 'unavailable' }],
      actions: ['record', 'quit'],
    }),
  },
];

const TUTORIAL_LEVEL: LevelDef = { ...LEVEL, id: 'tut', index: 0, name: 'First Take', maxTapes: 1, speeds: [1], endModes: ['stop'], horizonBars: 4 };

function buildView(scene: Scene, t: number): SessionView {
  const f = scene.frame(t);
  const level = scene.id === 'tutorial' ? TUTORIAL_LEVEL : LEVEL;
  const playing = f.playing ?? false;
  const decks = f.decks.map((s, i) => deck(i as TapeIndex, s, f.beat, f.worldRate, playing)) as SessionView['decks'];
  return {
    phase: f.phase,
    level,
    decks,
    active: f.active,
    beat: f.beat,
    horizonBeats: level.horizonBars * BEATS_PER_BAR,
    worldRate: f.worldRate,
    count: f.count ?? 0,
    speeds: level.speeds,
    endModes: level.endModes,
    objective: { text: level.objective.text, ...(f.objective ?? { complete: false, progress: 0, survivors: 0 }) },
    outcome: f.outcome ?? null,
    actions: f.actions,
    threatBeats: f.threatBeats ?? [],
    hint: f.hint ?? null,
  };
}

function pulseFor(beat: number): MusicPulse {
  const fb = beat - Math.floor(beat);
  const fbar = beat / BEATS_PER_BAR - Math.floor(beat / BEATS_PER_BAR);
  return {
    beat,
    beatPulse: Math.max(0, 1 - fb * 3),
    barPulse: Math.max(0, 1 - fbar * 3),
    levels: [0.5, 0.5, 0.5, 0.5],
    pitches: [0.5, 0.5, 0.5, 0.5],
    chord: 0,
  };
}

// ───────────────────────────── page wiring ─────────────────────────────

const params = new URLSearchParams(location.search);
const stage = document.getElementById('stage') as HTMLElement;
const hud = createHud();
stage.append(hud.el);
hud.setDevice(params.get('device') === 'gamepad' ? 'gamepad' : 'keyboard');
document.body.dataset.bg = params.get('bg') === 'dark' ? 'dark' : 'warm';

let sceneIdx = Math.max(0, SCENES.findIndex((s) => s.id === params.get('scene')));
const frozen = params.has('t') ? Number(params.get('t')) : null;
let auto = params.get('auto') !== '0' && frozen === null;
let sceneStart = performance.now();

const bar = document.getElementById('controls') as HTMLElement;
const log = document.getElementById('log') as HTMLElement;
function renderControls(): void {
  bar.innerHTML =
    SCENES.map((s, i) => `<button data-i="${i}" class="${i === sceneIdx ? 'on' : ''}">${s.label}</button>`).join('') +
    `<button data-auto>${auto ? 'auto ✓' : 'auto ✗'}</button>` +
    `<button data-bg>bg: ${document.body.dataset.bg}</button>` +
    `<button data-dev>device</button>` +
    `<button data-flash>flash events</button>`;
}
let dev: 'keyboard' | 'gamepad' = params.get('device') === 'gamepad' ? 'gamepad' : 'keyboard';
bar.addEventListener('click', (e) => {
  const b = (e.target as HTMLElement).closest('button');
  if (!b) return;
  if (b.dataset.i) {
    sceneIdx = Number(b.dataset.i);
    sceneStart = performance.now();
  } else if (b.hasAttribute('data-auto')) auto = !auto;
  else if (b.hasAttribute('data-bg')) document.body.dataset.bg = document.body.dataset.bg === 'dark' ? 'warm' : 'dark';
  else if (b.hasAttribute('data-dev')) {
    dev = dev === 'keyboard' ? 'gamepad' : 'keyboard';
    hud.setDevice(dev);
  } else if (b.hasAttribute('data-flash')) {
    const kinds = ['light', 'heavy', 'dodge', 'ranged', 'interact', 'ability', 'death', 'desync', 'resync'] as const;
    kinds.forEach((k, n) => setTimeout(() => hud.deckEvent((n % 4) as TapeIndex, k), n * 260));
  }
  renderControls();
});
hud.el.addEventListener(HUD_ACTION_EVENT, (e) => {
  const d = (e as CustomEvent<HudActionDetail>).detail;
  log.textContent = `HUD action: ${d.action}\n${log.textContent ?? ''}`.slice(0, 400);
});
renderControls();

// Fire deck flashes while recording / reviewing so the event treatment is visible.
let lastMarkBeat = -1;
function frame(now: number): void {
  let t = frozen ?? (now - sceneStart) / 1000;
  const scene = SCENES[sceneIdx];
  if (frozen === null && t > scene.duration) {
    if (auto) {
      sceneIdx = (sceneIdx + 1) % SCENES.length;
      sceneStart = now;
      t = 0;
      lastMarkBeat = -1;
      renderControls();
    } else {
      t = t % scene.duration;
    }
  }
  const view = buildView(SCENES[sceneIdx], t);
  hud.update(view, pulseFor(view.beat));
  if (frozen === null && (view.phase === 'recording' || view.phase === 'review') && view.active !== null) {
    const d = view.decks[view.active];
    for (const m of d.marks) {
      const mb = d.speed ? (m.tick / 30) / d.speed : 0;
      if (mb > lastMarkBeat && mb <= view.beat) hud.deckEvent(view.active, m.kind);
    }
    lastMarkBeat = view.beat;
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
