/**
 * Cross-recording memory of the outside-the-loop boss (BOSS-01, BOSS-02).
 *
 * Policy (the requirements leave it open; this is the resolved reading):
 *   - Memory is built ONLY from committed tapes. A discarded take, a whole-attempt reset (which
 *     discards the tapes) and the cinematic never feed it, so the replay of a resolved run can never
 *     re-teach the boss (CINE-04).
 *   - It records choreography, not outcomes: where each committed tape is at every whole master beat
 *     of the horizon and every attack attempt it makes, with end behaviour (stop / repeat / reverse)
 *     applied. What happened to the tape in some run (death, desync) is not memory: the boss
 *     remembers what you rehearsed, which is exactly what the player can see on the cassette lane.
 *   - It is read-only data. The simulation copies what it needs at the start of a run and never
 *     writes to it, so the same memory always produces the same fight.
 *
 * `recallCandidates` is the single interpretation of that memory: the moments a remembered self
 * "stood somewhere for a while" (a dwell) or "attacked". The boss (enemies/boss.ts) turns those
 * candidates into telegraphed memory strikes.
 */
import { samplePoseAtSub, type PoseSample } from './tape';
import { collectEventCrossings, horizonSubs, subsPerBeat, type EventCrossing } from './time';
import type { ActionKind, BossMemory, BossMemoryAction, LevelDef, Tape, TapeIndex } from './types';

/** Recorded attempts the boss remembers as attacks. Dodges and interactions are not threats. */
export const REMEMBERED_ACTIONS: readonly ActionKind[] = ['light', 'heavy', 'ranged'];

/** A remembered self "stood somewhere" while it stayed within this many tiles of where it stopped. */
export const BOSS_DWELL_RADIUS = 0.75;
/** …for at least this many whole master beats (so two consecutive samples are not yet a dwell). */
export const BOSS_DWELL_BEATS = 2;

/**
 * Build the boss memory from the committed tapes. Each tape contributes its position at every whole
 * master beat 0..floor(horizon / beat) and every light / heavy / ranged attempt it makes inside the
 * horizon (end behaviour applied: a repeating tape attacks again every traversal, a reversing one
 * on its backward passes too). Tapes are listed in cassette order.
 */
export function buildBossMemory(level: LevelDef, committed: Tape[]): BossMemory {
  const spb = subsPerBeat(level);
  const H = horizonSubs(level);
  const beats = Math.floor(H / spb);
  const observed: BossMemory['observed'] = [];
  const pose: PoseSample = { x: 0, y: 0, facing: 0, anim: 'idle' };
  const sorted = [...committed].sort((a, b) => a.index - b.index);
  const crossings: EventCrossing[] = [];
  for (const t of sorted) {
    const samples: { beat: number; x: number; y: number }[] = [];
    for (let b = 0; b <= beats; b++) {
      samplePoseAtSub(t, b * spb, pose);
      samples.push({ beat: b, x: pose.x, y: pose.y });
    }
    crossings.length = 0;
    collectEventCrossings(t, 0, H, crossings);
    const actions: BossMemoryAction[] = [];
    for (const c of crossings) {
      if (!REMEMBERED_ACTIONS.includes(c.event.kind)) continue;
      samplePoseAtSub(t, c.sub, pose);
      actions.push({ beat: c.sub / spb, x: pose.x, y: pose.y, kind: c.event.kind });
    }
    observed.push({ tape: t.index, speed: t.speed, samples, actions });
  }
  return { observed };
}

/** Why the boss remembers a moment. */
export type RecallReason = 'dwell' | 'attack';

/** One remembered moment the boss may pre-empt: a place and the earliest whole beat it applies to. */
export interface RecallCandidate {
  tape: TapeIndex;
  reason: RecallReason;
  /** First whole master beat at which the remembered self is expected at (x, y). */
  beat: number;
  /** Last whole master beat of the moment (equal to `beat` for an attack). */
  lastBeat: number;
  x: number;
  y: number;
}

/**
 * Every moment the memory describes, ordered by beat, then cassette, then reason (attack first).
 *
 *   dwell  — a run of whole-beat samples that all stay within BOSS_DWELL_RADIUS of the run's first
 *            sample for at least BOSS_DWELL_BEATS beats. The place is the run's first sample.
 *            Scanning restarts after the run, so a long wait is one dwell, not many.
 *   attack — each remembered attempt, at the whole beat nearest to it (enemy attacks keep to the
 *            beat grid; AI-07) and the position the self had when it fired.
 *
 * Pure: reads the memory, never writes it.
 */
export function recallCandidates(memory: BossMemory | undefined): RecallCandidate[] {
  const out: RecallCandidate[] = [];
  if (!memory) return out;
  for (const o of memory.observed) {
    const s = o.samples;
    let i = 0;
    while (i < s.length) {
      let j = i;
      while (j + 1 < s.length && Math.hypot(s[j + 1].x - s[i].x, s[j + 1].y - s[i].y) <= BOSS_DWELL_RADIUS) j++;
      if (s[j].beat - s[i].beat >= BOSS_DWELL_BEATS) {
        out.push({ tape: o.tape, reason: 'dwell', beat: s[i].beat, lastBeat: s[j].beat, x: s[i].x, y: s[i].y });
      }
      i = j + 1;
    }
    for (const a of o.actions ?? []) {
      const b = Math.round(a.beat);
      out.push({ tape: o.tape, reason: 'attack', beat: b, lastBeat: b, x: a.x, y: a.y });
    }
  }
  out.sort((a, b) => a.beat - b.beat || a.tape - b.tape || (a.reason === b.reason ? 0 : a.reason === 'attack' ? -1 : 1));
  return out;
}
