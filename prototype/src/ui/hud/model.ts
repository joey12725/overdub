/**
 * HUD view-model: every rule that turns SessionView data into what the decks and the master beat
 * ruler show. Pure and DOM-free so it can be tested in node; the DOM layer only renders the results.
 *
 * Terminology (requirements chapter 03): the ruler is always in MASTER bars/beats, a deck's
 * recording allowance is in LOCAL tape bars. Every string built here names which one it means.
 */
import {
  BEATS_PER_BAR,
  LOCAL_HZ,
  TAPE_NAMES,
  type ActionKind,
  type DeckStatus,
  type DeckView,
  type EndMode,
  type LifeState,
  type SessionAction,
  type TapeSpeed,
} from '../../core/types';

export type Device = 'keyboard' | 'gamepad';

// ───────────────────────────── time mapping (TIME-03) ─────────────────────────────

/** Master beats one LOCAL tick of a tape at `speed` covers: master = local / speed. */
export function masterBeatsPerLocalTick(speed: TapeSpeed, bpm: number): number {
  return bpm / 60 / LOCAL_HZ / speed;
}

/** Master beat (from the start of a traversal) at which a local tick falls on its first pass. */
export function localTickToMasterBeat(tick: number, speed: TapeSpeed, bpm: number): number {
  return tick * masterBeatsPerLocalTick(speed, bpm);
}

/** Master beats one traversal of a tape occupies: level.bars local bars become bars / speed master bars. */
export function traversalBeats(localBars: number, speed: TapeSpeed): number {
  return (localBars * BEATS_PER_BAR) / speed;
}

/** Local ticks in a full recording of `localBars` bars at `bpm` (identical for every speed; TIME-02). */
export function recordingTicks(localBars: number, bpm: number): number {
  return Math.round((localBars * BEATS_PER_BAR * 60 * LOCAL_HZ) / bpm);
}

export interface LaneSegment {
  /** Master beats. */
  start: number;
  end: number;
  /** 0 = the recorded pass itself, 1+ = repeats / reversals. */
  traversal: number;
  /** Playback direction across this segment. */
  dir: 1 | -1;
  /** True when the horizon cuts this traversal short. */
  partial: boolean;
}

export interface LaneLayout {
  spanBeats: number;
  segments: LaneSegment[];
  /** For 'stop' tapes that end before the horizon: master beat from which the self holds its pose. */
  holdFrom: number | null;
}

/** Hard ceiling so a degenerate span can never spin the layout loop forever. */
const MAX_SEGMENTS = 512;
const EPS = 1e-9;

/**
 * How one tape's traversals tile the master timeline up to the horizon (architecture: end behaviour).
 * stop: one pass then a hold; repeat: passes back to back, all forward; reverse: ping-pong.
 */
export function laneLayout(spanBeats: number, endMode: EndMode, horizonBeats: number): LaneLayout {
  const segments: LaneSegment[] = [];
  if (!(spanBeats > 0) || !(horizonBeats > 0)) return { spanBeats, segments, holdFrom: null };
  let start = 0;
  for (let k = 0; start < horizonBeats - EPS && k < MAX_SEGMENTS; k++) {
    const end = Math.min(start + spanBeats, horizonBeats);
    const dir: 1 | -1 = endMode === 'reverse' && k % 2 === 1 ? -1 : 1;
    segments.push({ start, end, traversal: k, dir, partial: end - start < spanBeats - EPS });
    if (endMode === 'stop') break;
    start += spanBeats;
  }
  const holdFrom = endMode === 'stop' && spanBeats < horizonBeats - EPS ? spanBeats : null;
  return { spanBeats, segments, holdFrom };
}

export interface PlacedMark {
  beat: number;
  kind: ActionKind;
  traversal: number;
  dir: 1 | -1;
}

/**
 * Every master beat at which a recorded action fires, across all traversals up to the horizon.
 * Repeats re-fire forward; reverse passes cross each action's tick from the far end (PLAY-06).
 */
export function placeMarks(
  marks: readonly { tick: number; kind: ActionKind }[],
  speed: TapeSpeed,
  bpm: number,
  layout: LaneLayout,
): PlacedMark[] {
  const out: PlacedMark[] = [];
  const span = layout.spanBeats;
  const per = masterBeatsPerLocalTick(speed, bpm);
  for (const seg of layout.segments) {
    for (const m of marks) {
      const local = m.tick * per;
      if (local < -EPS || local > span + EPS) continue;
      const beat = seg.dir === 1 ? seg.start + local : seg.start + (span - local);
      if (beat < seg.start - EPS || beat > seg.end + EPS) continue;
      out.push({ beat, kind: m.kind, traversal: seg.traversal, dir: seg.dir });
    }
  }
  out.sort((a, b) => a.beat - b.beat);
  return out;
}

/** Which traversal is playing at master beat `beat` (0-based). */
export function traversalAt(beat: number, spanBeats: number): number {
  if (!(spanBeats > 0) || beat <= 0) return 0;
  return Math.floor(beat / spanBeats + EPS);
}

/** Label every n-th master bar so labels stay at least `minPx` apart. n is a power of two. */
export function barLabelStep(horizonBars: number, trackPx: number, minPx = 30): number {
  if (!(horizonBars > 0) || !(trackPx > 0)) return 1;
  const barPx = trackPx / horizonBars;
  let step = 1;
  while (step * barPx < minPx && step < 1024) step *= 2;
  return step;
}

// ───────────────────────────── speed (UI-05, UI-07, NEW-10) ─────────────────────────────

export function formatSpeed(speed: TapeSpeed | null): string {
  if (speed === null) return '--';
  return `${speed}×`;
}

export function formatBars(n: number): string {
  return String(Math.round(n * 100) / 100);
}

/** One-line consequence of a speed choice, in the game's own terms (momentum × tapeSpeed; world 1/s). */
export function speedConsequence(speed: TapeSpeed): string {
  switch (speed) {
    case 0.5:
      return '0.5× — this take plays back over twice the time and hits half as hard; the world runs at double speed while you record';
    case 1:
      return '1× — this take plays back in the time it took to record, at normal force; the world runs at normal speed while you record';
    case 2:
      return '2× — this take plays back in half the time and hits twice as hard; the world runs at half speed while you record';
    case 4:
      return '4× — this take plays back in a quarter of the time and hits four times as hard; the world runs at quarter speed while you record';
  }
}

/** "8 local bars → 4 master bars": the TIME-03 conversion stated explicitly (chapter 03 warning). */
export function spanCopy(localBars: number, speed: TapeSpeed): string {
  const master = localBars / speed;
  return `${formatBars(localBars)} local ${plural(localBars, 'bar')} → ${formatBars(master)} master ${plural(master, 'bar')}`;
}

function plural(n: number, word: string): string {
  return Math.abs(n - 1) < EPS ? word : `${word}s`;
}

/** World speed relative to the person playing, as shown on the ruler ("world ×0.5"). */
export function formatWorldRate(rate: number): string {
  if (!(rate > 0)) return 'world paused';
  const r = Math.round(rate * 100) / 100;
  return `world ×${formatBars(r)}`;
}

/**
 * Fraction (0..1) of the deck's span-scale that one pass fills: the slowest offered speed fills the
 * whole scale, so a 2× tape visibly fills half of what a 1× tape does (UI-07).
 */
export function spanScaleFill(speed: TapeSpeed, offered: readonly TapeSpeed[]): number {
  const slowest = offered.length ? Math.min(...offered, speed) : speed;
  return Math.max(0, Math.min(1, slowest / speed));
}

// ───────────────────────────── end behaviour ─────────────────────────────

export type IconId =
  | 'lock'
  | 'rec'
  | 'arm'
  | 'empty'
  | 'none'
  | 'take'
  | 'alive'
  | 'ghost'
  | 'recGhost'
  | 'desync'
  | 'resync'
  | 'stop'
  | 'repeat'
  | 'reverse'
  | 'play'
  | 'rewind'
  | 'hold'
  | 'cue'
  | 'death'
  | 'survivor'
  | 'world';

export type Tone = 'muted' | 'idle' | 'armed' | 'rec' | 'pending' | 'locked' | 'good' | 'dead' | 'desync' | 'warn';

export interface Badge {
  label: string;
  icon: IconId;
  tone: Tone;
}

export interface EndModeInfo extends Badge {
  /** What happens when this tape runs out before the horizon. */
  copy: string;
}

export function endModeInfo(mode: EndMode): EndModeInfo {
  switch (mode) {
    case 'stop':
      return {
        label: 'STOP',
        icon: 'stop',
        tone: 'idle',
        copy: 'at the end this self holds its last pose: still solid, still a target',
      };
    case 'repeat':
      return {
        label: 'REPEAT',
        icon: 'repeat',
        tone: 'idle',
        copy: 'at the end it cuts back to the start and plays again, every action re-fires',
      };
    case 'reverse':
      return {
        label: 'REVERSE',
        icon: 'reverse',
        tone: 'idle',
        copy: 'at the end it plays backward, then forward again; every action re-fires on the way',
      };
  }
}

// ───────────────────────────── status / state tables (NEW-08, NEW-11, UI-03) ─────────────────────────────

/** Cassette status. Never colour-only: each has its own word and icon. */
export function statusBadge(status: DeckStatus): Badge {
  switch (status) {
    case 'unavailable':
      return { label: 'NOT IN THIS LEVEL', icon: 'none', tone: 'muted' };
    case 'empty':
      return { label: 'NOT RECORDED', icon: 'empty', tone: 'idle' };
    case 'armed':
      return { label: 'ARMED', icon: 'arm', tone: 'armed' };
    case 'recording':
      return { label: 'RECORDING', icon: 'rec', tone: 'rec' };
    case 'pending':
      return { label: 'TAKE — NOT COMMITTED', icon: 'take', tone: 'pending' };
    case 'committed':
      return { label: 'COMMITTED', icon: 'lock', tone: 'locked' };
  }
}

/**
 * The self's state in the current run (GHOST-01..06, DESYNC-07). Null when the cassette has no self
 * in the run. `synced` is reported even for ghosts: the HUD shows what the sim says, never hides it.
 */
export function lifeBadge(life: LifeState | null, synced: boolean): Badge | null {
  if (life === null) return null;
  switch (life) {
    case 'alive':
      return synced
        ? { label: 'ALIVE', icon: 'alive', tone: 'good' }
        : { label: 'DESYNCED — SPARK CHASING', icon: 'desync', tone: 'desync' };
    case 'recGhost':
      return synced
        ? { label: 'DIED — RECORDING AS GHOST', icon: 'recGhost', tone: 'dead' }
        : { label: 'GHOST TAKE — DESYNCED', icon: 'desync', tone: 'desync' };
    case 'ghost':
      return synced
        ? { label: 'DEAD — GHOST', icon: 'ghost', tone: 'dead' }
        : { label: 'DEAD — GHOST, OUT OF SYNC', icon: 'ghost', tone: 'desync' };
  }
}

export interface DeckPresentation {
  status: Badge;
  state: Badge | null;
  /** Stable identity of what is shown; two inputs look different iff their keys differ. */
  key: string;
}

export function deckPresentation(status: DeckStatus, life: LifeState | null, synced: boolean): DeckPresentation {
  const s = statusBadge(status);
  const st = lifeBadge(life, synced);
  const key = `${s.label}|${s.icon}|${s.tone}#${st ? `${st.label}|${st.icon}|${st.tone}` : '-'}`;
  return { status: s, state: st, key };
}

/**
 * What the transport is doing right now (NEW-11: stopped / looping / reversing). Only meaningful for
 * tapes that have a recording to play.
 */
export function transportBadge(
  deck: Pick<DeckView, 'status' | 'endMode' | 'transport' | 'localProgress' | 'spanBars'>,
  beat: number,
): Badge | null {
  if (deck.status !== 'pending' && deck.status !== 'committed' && deck.status !== 'recording') return null;
  const span = deck.spanBars * BEATS_PER_BAR;
  const pass = traversalAt(beat, span) + 1;
  if (deck.transport === -1) return { label: `REVERSING · PASS ${pass}`, icon: 'rewind', tone: 'idle' };
  if (deck.transport === 1) {
    if (deck.endMode === 'repeat' && pass > 1) return { label: `LOOPING · PASS ${pass}`, icon: 'repeat', tone: 'idle' };
    if (deck.endMode === 'reverse' && pass > 1) return { label: `FORWARD · PASS ${pass}`, icon: 'play', tone: 'idle' };
    return { label: 'PLAYING', icon: 'play', tone: 'idle' };
  }
  if (deck.status !== 'recording' && (deck.localProgress >= 1 - 1e-6 || (deck.endMode === 'stop' && beat >= span - 1e-6))) {
    return { label: 'STOPPED — HOLDING POSE', icon: 'hold', tone: 'idle' };
  }
  if (beat <= 1e-6) return { label: 'CUED AT BEAT 0', icon: 'cue', tone: 'idle' };
  return { label: 'PAUSED', icon: 'hold', tone: 'idle' };
}

// ───────────────────────────── reels ─────────────────────────────

/** Reel revolutions per viewer second at reelRate 1. Chosen so 0.5× still visibly turns and 4× is not a blur. */
export const BASE_REEL_RPS = 0.55;

/** Signed reel spin in revolutions per second: magnitude from reelRate, sign from the transport. */
export function reelSpin(reelRate: number, transport: 1 | -1 | 0): number {
  if (transport === 0) return 0;
  return Math.abs(reelRate) * transport * BASE_REEL_RPS;
}

/** Radii of the supply (left) and take-up (right) tape packs as tape transfers with progress. */
export function tapePackRadii(progress: number, hub: number, full: number): [number, number] {
  const p = Math.max(0, Math.min(1, progress));
  // Area, not radius, is conserved as tape moves between reels.
  const hub2 = hub * hub;
  const cap = full * full - hub2;
  return [Math.sqrt(hub2 + cap * (1 - p)), Math.sqrt(hub2 + cap * p)];
}

// ───────────────────────────── prompts ─────────────────────────────

export interface Binding {
  /** Key / button glyph text. */
  key: string;
  /** Gamepad face buttons get their conventional colour treatment. */
  style: 'key' | 'face-a' | 'face-b' | 'face-x' | 'face-y' | 'shoulder' | 'menu';
}

/**
 * Button prompts per device. These mirror the bindings the input layer (src/game/input.ts) is expected
 * to use; kept in one table so a rebinding is a one-line change.
 */
export const HUD_BINDINGS: Record<Device, Partial<Record<SessionAction, Binding>>> = {
  keyboard: {
    start: { key: 'Enter', style: 'key' },
    speedDown: { key: 'Q', style: 'key' },
    speedUp: { key: 'E', style: 'key' },
    cycleEndMode: { key: 'Tab', style: 'key' },
    record: { key: 'Space', style: 'key' },
    skip: { key: 'Enter', style: 'key' },
    endAttempt: { key: 'Backspace', style: 'key' },
    retryTake: { key: 'R', style: 'key' },
    commit: { key: 'Enter', style: 'key' },
    resetAll: { key: 'Delete', style: 'key' },
    continue: { key: 'Enter', style: 'key' },
    quit: { key: 'Esc', style: 'key' },
  },
  gamepad: {
    start: { key: 'A', style: 'face-a' },
    speedDown: { key: 'LB', style: 'shoulder' },
    speedUp: { key: 'RB', style: 'shoulder' },
    cycleEndMode: { key: 'Y', style: 'face-y' },
    record: { key: 'A', style: 'face-a' },
    skip: { key: 'A', style: 'face-a' },
    endAttempt: { key: 'B', style: 'face-b' },
    retryTake: { key: 'X', style: 'face-x' },
    commit: { key: 'A', style: 'face-a' },
    resetAll: { key: 'Y', style: 'face-y' },
    continue: { key: 'A', style: 'face-a' },
    quit: { key: 'Start', style: 'menu' },
  },
};

export const ACTION_LABELS: Record<SessionAction, string> = {
  start: 'START',
  speedUp: 'FASTER',
  speedDown: 'SLOWER',
  cycleEndMode: 'END MODE',
  record: 'RECORD',
  skip: 'SKIP',
  endAttempt: 'END ATTEMPT',
  retryTake: 'RETRY TAKE',
  commit: 'COMMIT TAPE',
  resetAll: 'RESET ALL TAPES',
  continue: 'CONTINUE',
  quit: 'QUIT',
};

export interface Prompt {
  action: SessionAction;
  binding: Binding;
  label: string;
  /** Plain-text form for screen readers and tests: "[Space] RECORD". */
  text: string;
}

export function promptFor(action: SessionAction, device: Device): Prompt {
  const binding = HUD_BINDINGS[device][action] ?? { key: '?', style: 'key' };
  const label = ACTION_LABELS[action];
  return { action, binding, label, text: `[${binding.key}] ${label}` };
}

// ───────────────────────────── decision (REC-04, REC-05) ─────────────────────────────

export interface DecisionOption {
  action: 'retryTake' | 'commit' | 'resetAll';
  title: string;
  /** What it keeps / destroys, so retry and reset can never be confused. */
  detail: string;
  tone: 'retry' | 'commit' | 'reset';
  enabled: boolean;
}

export function decisionOptions(actions: readonly SessionAction[], activeTape: number | null): DecisionOption[] {
  const tapeName = activeTape === null ? 'this tape' : `tape ${TAPE_NAMES[activeTape]}`;
  return [
    {
      action: 'retryTake',
      title: 'RETRY TAKE',
      detail: `re-record ${tapeName} — keeps every earlier tape`,
      tone: 'retry',
      enabled: actions.includes('retryTake'),
    },
    {
      action: 'commit',
      title: 'COMMIT TAPE & CONTINUE',
      detail: `lock ${tapeName} in and arm the next cassette`,
      tone: 'commit',
      enabled: actions.includes('commit'),
    },
    {
      action: 'resetAll',
      title: 'RESET ALL TAPES',
      detail: 'wipes every cassette — start the attempt from tape A',
      tone: 'reset',
      enabled: actions.includes('resetAll'),
    },
  ];
}

// ───────────────────────────── recording ─────────────────────────────

export interface TimeLeft {
  /** 0..1 of the take still to record. */
  fraction: number;
  /** Remaining LOCAL bars (the player's own bars; TIME-02). */
  localBars: number;
  text: string;
}

export function recordingTimeLeft(localProgress: number, localBars: number): TimeLeft {
  const fraction = Math.max(0, Math.min(1, 1 - localProgress));
  const left = localBars * fraction;
  const shown = left >= 1 ? Math.ceil(left - 1e-6) : Math.round(left * 10) / 10;
  return { fraction, localBars: left, text: `${formatBars(shown)} local ${plural(shown, 'bar')} left` };
}

/** "bar 3 · beat 2" for a master beat position (both 1-based, as a musician counts). */
export function masterPositionText(beat: number, horizonBeats = Infinity): string {
  if (beat >= horizonBeats - 1e-6) return `end · ${formatBars(horizonBeats / BEATS_PER_BAR)} bars`;
  const b = Math.max(0, beat);
  const bar = Math.floor(b / BEATS_PER_BAR) + 1;
  const inBar = Math.floor(b % BEATS_PER_BAR) + 1;
  return `bar ${bar} · beat ${inBar}`;
}
