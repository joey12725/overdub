/**
 * The one clock (TIME-01..07) and fixed-choreography playback geometry (PLAY-05, PLAY-06).
 *
 * Coordinates:
 *   sub   — master substep index (1/SUB_HZ master s). The world steps one sub at a time.
 *   tick  — local tick on a tape (1/LOCAL_HZ local s). Pose sample i sits at tick i.
 *   u     — "unwrapped" local time: local ticks elapsed since beat zero, ignoring end behaviour.
 *           u = sub · speed / (SUB_HZ / LOCAL_HZ). It only ever increases.
 *
 * master = local / speed (TIME-03): a tape at speed s covers `subsPerLocalTick(s)` = 4 / s substeps
 * per local tick, so its traversal of T ticks spans T · 4 / s substeps. Nothing is ever stretched.
 * Because every speed is a power of two dividing 4·2, each integer tick lands on an integer sub, so
 * all crossing arithmetic below is exact.
 */
import {
  BEATS_PER_BAR,
  LOCAL_HZ,
  SUB_HZ,
  subsPerLocalTick,
  type EndMode,
  type LevelDef,
  type Tape,
  type TapeEvent,
  type TapePhase,
  type TapeSpeed,
} from './types';

/** Substeps per local tick at 1× (4). */
const SUBS_PER_TICK_1X = SUB_HZ / LOCAL_HZ;

// ───────────────────────────── level-level conversions ─────────────────────────────

/** Local ticks in one beat at the level tempo. LevelDef requires 3600 / bpm to be an integer. */
export function ticksPerBeat(level: Pick<LevelDef, 'bpm'>): number {
  return (LOCAL_HZ * 60) / level.bpm;
}

/** Master substeps in one master beat. */
export function subsPerBeat(level: Pick<LevelDef, 'bpm'>): number {
  return (SUB_HZ * 60) / level.bpm;
}

/** Local ticks in one recording: level.bars of the level tempo, identical for every speed (TIME-02, TIME-04). */
export function tapeTicks(level: Pick<LevelDef, 'bpm' | 'bars'>): number {
  return Math.round(level.bars * BEATS_PER_BAR * ticksPerBeat(level));
}

/** Total master substeps in the encounter horizon (level-authored, OPEN-02). */
export function horizonSubs(level: Pick<LevelDef, 'bpm' | 'horizonBars'>): number {
  return Math.round(level.horizonBars * BEATS_PER_BAR * subsPerBeat(level));
}

/** Master beat (float) at a substep. */
export function subToBeat(level: Pick<LevelDef, 'bpm'>, sub: number): number {
  return sub / subsPerBeat(level);
}

/** Substep (float) at a master beat. */
export function beatToSub(level: Pick<LevelDef, 'bpm'>, beat: number): number {
  return beat * subsPerBeat(level);
}

/** Master seconds at a substep. */
export function subToSeconds(sub: number): number {
  return sub / SUB_HZ;
}

/** Re-exported so callers have the whole clock in one module. 8, 4, 2, 1 for 0.5×, 1×, 2×, 4×. */
export { subsPerLocalTick };

/** Master substep at which a tape at `speed` reaches unwrapped local tick `tick`. */
export function localTickToSub(speed: TapeSpeed, tick: number): number {
  return tick * subsPerLocalTick(speed);
}

/** Unwrapped local tick a tape at `speed` has reached at master substep `sub`. */
export function subToLocalTick(speed: TapeSpeed, sub: number): number {
  return (sub * speed) / SUBS_PER_TICK_1X;
}

/** Master substeps one full traversal of a tape spans (TIME-03: bars / speed master bars). */
export function traversalSubs(tape: Pick<Tape, 'speed' | 'ticks'>): number {
  return tape.ticks * subsPerLocalTick(tape.speed);
}

/** Master bars one traversal spans (DeckView.spanBars). */
export function spanBars(level: Pick<LevelDef, 'bars'>, speed: TapeSpeed): number {
  return level.bars / speed;
}

// ───────────────────────────── playhead ─────────────────────────────

type PhaseTape = Pick<Tape, 'speed' | 'endMode' | 'ticks'>;

/**
 * Where a tape's playhead is at master substep `sub` (PLAY-05).
 *
 *  stop    — forward until tick T, then holds T with dir 0, ended, traversal 1.
 *  repeat  — traversal k = floor(u / T), tick = u − kT. At u = kT the playhead has already cut back
 *            to tick 0 (it is never reported "at T" on a repeat).
 *  reverse — even traversals run forward, odd ones backward (tick = T − (u − kT)). The playhead is
 *            continuous; at a turn instant it reports the new traversal and direction.
 *
 * Negative subs are treated as sub 0. A zero-length tape is permanently at tick 0, ended.
 */
export function tapePhaseAt(tape: PhaseTape, sub: number): TapePhase {
  const out: TapePhase = { tick: 0, dir: 1, traversal: 0, ended: false };
  return tapePhaseInto(tape, sub, out);
}

/** Allocation-free tapePhaseAt. Returns `out`. */
export function tapePhaseInto(tape: PhaseTape, sub: number, out: TapePhase): TapePhase {
  const T = tape.ticks;
  const u = sub > 0 ? subToLocalTick(tape.speed, sub) : 0;
  if (T <= 0) {
    out.tick = 0;
    out.dir = 0;
    out.traversal = 0;
    out.ended = true;
    return out;
  }
  if (tape.endMode === 'stop') {
    if (u < T) {
      out.tick = u;
      out.dir = 1;
      out.traversal = 0;
      out.ended = false;
    } else {
      out.tick = T;
      out.dir = 0;
      out.traversal = 1;
      out.ended = true;
    }
    return out;
  }
  const k = Math.floor(u / T);
  const f = u - k * T;
  out.traversal = k;
  out.ended = false;
  if (tape.endMode === 'repeat' || (k & 1) === 0) {
    out.tick = f;
    out.dir = 1;
  } else {
    out.tick = T - f;
    out.dir = -1;
  }
  return out;
}

// ───────────────────────────── event crossings ─────────────────────────────

/** One firing of a recorded event: the playhead reached the event's tick during a query interval. */
export interface EventCrossing {
  event: TapeEvent;
  /** Index into tape.events. */
  index: number;
  /** Exact master substep of the crossing (an integer for integer event ticks). */
  sub: number;
  /** Direction of the pass that crossed it: +1 forward, −1 backward (reverse mode). */
  dir: 1 | -1;
  /** Traversal number of that pass (0 = first forward pass). */
  traversal: number;
}

/**
 * Collects the events whose ticks the playhead crosses in master substeps [subA, subB), ordered by
 * crossing sub, then traversal, then event index. Appends to `out` and returns it.
 *
 * Half-open on purpose: consecutive queries [a, b), [b, c) partition time, so an event is never
 * fired twice or skipped at a query boundary; and an event recorded on live tick i (whose substeps
 * are [i·m, (i+1)·m)) fires in the first substep of that tick's batch, after the controller has
 * produced it. The first query of a run starts at sub 0 and so includes events on tick 0.
 *
 * Visits (each fires the event once):
 *  stop    — the single forward pass, u ∈ [0, T]. An event on tick T fires as the tape ends.
 *  repeat  — every pass k covers u ∈ [kT, (k+1)T]. At a wrap instant the event on tick T (end of
 *            pass k) and the event on tick 0 (start of pass k+1) both fire; they are different
 *            events, so nothing doubles.
 *  reverse — the playhead touches a turn tick only once per turn, so the turn instant belongs to the
 *            pass that ARRIVES there: pass 0 owns u ∈ [0, T], pass k ≥ 1 owns u ∈ (kT, (k+1)T].
 *            An event on tick T fires forward on arrival and does not fire again leaving the turn;
 *            an event on tick 0 fires backward on arrival at the next turn (PLAY-06: fresh again).
 *
 * Events with ticks outside [0, T] never fire. Events need not be sorted.
 */
export function collectEventCrossings(
  tape: Pick<Tape, 'speed' | 'endMode' | 'ticks' | 'events'>,
  subA: number,
  subB: number,
  out: EventCrossing[] = [],
): EventCrossing[] {
  if (!(subB > subA) || tape.events.length === 0) return out;
  const T = tape.ticks;
  const m = subsPerLocalTick(tape.speed);
  const start = out.length;
  const events = tape.events;

  if (T <= 0 || tape.endMode === 'stop') {
    // Single pass. Zero-length tapes fire tick-0 events once at sub 0.
    for (let i = 0; i < events.length; i++) {
      const e = events[i].tick;
      if (!(e >= 0 && e <= Math.max(T, 0))) continue;
      const s = e * m;
      if (s >= subA && s < subB) out.push({ event: events[i], index: i, sub: s, dir: 1, traversal: 0 });
    }
  } else {
    const travSubs = T * m;
    // Passes whose owned spans can intersect [subA, subB). A pass k spans subs [kT·m, (k+1)T·m].
    const kFirst = Math.max(0, Math.floor(subA / travSubs) - 1);
    const kLast = Math.floor(subB / travSubs);
    const reverse = tape.endMode === 'reverse';
    for (let k = kFirst; k <= kLast; k++) {
      const base = k * T;
      const backward = reverse && (k & 1) === 1;
      for (let i = 0; i < events.length; i++) {
        const e = events[i].tick;
        if (!(e >= 0 && e <= T)) continue;
        const uOff = backward ? T - e : e;
        // Reverse: a pass k ≥ 1 does not own its departure instant (the previous pass arrived there).
        if (reverse && k > 0 && uOff === 0) continue;
        const s = (base + uOff) * m;
        if (s >= subA && s < subB) {
          out.push({ event: events[i], index: i, sub: s, dir: backward ? -1 : 1, traversal: k });
        }
      }
    }
  }

  if (out.length - start > 1) sortCrossings(out, start);
  return out;
}

/** Convenience wrapper returning a fresh array. */
export function eventCrossings(
  tape: Pick<Tape, 'speed' | 'endMode' | 'ticks' | 'events'>,
  subA: number,
  subB: number,
): EventCrossing[] {
  return collectEventCrossings(tape, subA, subB, []);
}

function sortCrossings(arr: EventCrossing[], from: number): void {
  // Insertion sort over the appended slice: tiny, stable and allocation-free.
  for (let i = from + 1; i < arr.length; i++) {
    const x = arr[i];
    let j = i - 1;
    while (j >= from && crossingAfter(arr[j], x)) {
      arr[j + 1] = arr[j];
      j--;
    }
    arr[j + 1] = x;
  }
}

function crossingAfter(a: EventCrossing, b: EventCrossing): boolean {
  if (a.sub !== b.sub) return a.sub > b.sub;
  if (a.traversal !== b.traversal) return a.traversal > b.traversal;
  return a.index > b.index;
}

// ───────────────────────────── end-of-tape boundaries ─────────────────────────────

export type BoundaryKind = 'end' | 'wrap' | 'turn';

/** An end-of-tape boundary (feeds the tapeEnd / tapeWrap / tapeTurn SimEvents). */
export interface TapeBoundary {
  kind: BoundaryKind;
  /** Master substep of the boundary. */
  sub: number;
  /** Traversal that begins at this boundary (1 for the first boundary). */
  traversal: number;
  /** For 'turn': the direction of the pass that begins (−1 after the far end, +1 after tick 0). */
  dir: 1 | -1 | 0;
}

/** Boundaries the playhead reaches in master substeps [subA, subB), in order. Appends to `out`. */
export function collectBoundaries(
  tape: Pick<Tape, 'speed' | 'endMode' | 'ticks'>,
  subA: number,
  subB: number,
  out: TapeBoundary[] = [],
): TapeBoundary[] {
  if (!(subB > subA) || tape.ticks <= 0) return out;
  const travSubs = traversalSubs(tape);
  if (tape.endMode === 'stop') {
    if (travSubs >= subA && travSubs < subB) out.push({ kind: 'end', sub: travSubs, traversal: 1, dir: 0 });
    return out;
  }
  const kind: BoundaryKind = tape.endMode === 'repeat' ? 'wrap' : 'turn';
  let k = Math.max(1, Math.ceil(subA / travSubs));
  for (; k * travSubs < subB; k++) {
    const dir: 1 | -1 = kind === 'wrap' ? 1 : (k & 1) === 1 ? -1 : 1;
    out.push({ kind, sub: k * travSubs, traversal: k, dir });
  }
  return out;
}

/** All end modes, for exhaustive iteration in tools and tests. */
export const ALL_END_MODES: readonly EndMode[] = ['stop', 'repeat', 'reverse'];
