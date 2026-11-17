/**
 * Running solutions: compile the plans and play them through the real Session with the headless
 * bot, replay a stored input stream or stored tapes, and perturb a solution to see whether it still
 * wins. Node-free (see solution.ts).
 */
import { buildBossMemory, resolveEncounter } from '../../src/core/index';
import { deserializeTape, serializeTape } from '../../src/core/tape';
import { subsPerBeat, ticksPerBeat } from '../../src/core/time';
import { TAPE_NAMES } from '../../src/core/types';
import type { LevelDef, Outcome, Resolution, ResolvedLoadout, SimEvent, Tape } from '../../src/core/types';
import { runBotDetailed } from '../../src/game/bot';
import { compileTake, NO_MUTATION, replayTake, type TakeLog, type TakeMutation } from './plan';
import {
  decodeInputs,
  encodeInputs,
  levelHash,
  loadoutBySlot,
  planHash,
  solutionLoadout,
  solutionLoadoutIds,
  type GeneratedSection,
  type SolutionFile,
  type TimelineEntry,
} from './solution';

export interface RunOptions {
  /** Record only the first N takes. */
  upto?: number;
  /** One perturbation per take (default: none). */
  mutations?: readonly TakeMutation[];
  /** Gear for every take. Default: the solution's loadout (the baseline when it names none). */
  loadout?: ResolvedLoadout;
}

export interface SolutionRun {
  loadout: ResolvedLoadout;
  /** One log per take the bot started (a win can come before the plan runs out). */
  logs: TakeLog[];
  takesRecorded: number;
  /** The recorded tapes, in cassette order. */
  tapes: Tape[];
  /** The authoritative combined run of those tapes, as the Session resolved it. */
  resolution: Resolution;
  outcome: Outcome;
  warnings: string[];
}

/** Compile the solution's plans and play them through a real Session. */
export function runSolution(level: LevelDef, sol: SolutionFile, opts: RunOptions = {}): SolutionRun {
  const loadout = opts.loadout ?? solutionLoadout(sol);
  const takes = opts.upto !== undefined ? sol.takes.slice(0, Math.max(1, opts.upto)) : sol.takes;
  const compiled = takes.map((t, i) => compileTake(level, loadout, t, opts.mutations?.[i] ?? NO_MUTATION));
  const run = runBotDetailed(level, compiled.map((c) => c.bot), { loadout });
  const session = run.session;
  const tapes = [...session.committedTapes];
  if (session.pendingTape) tapes.push(session.pendingTape);
  const logs = compiled.slice(0, run.takesRecorded).map((c) => c.log);
  const warnings: string[] = [];
  logs.forEach((log, t) => {
    const name = `take ${t + 1} (tape ${TAPE_NAMES[t]})`;
    const tape = tapes[t];
    // A press the controller could not start within its input buffer never reaches the tape.
    for (const p of log.presses) {
      const started = tape.events.some((e) => e.kind === p.kind && e.tick >= p.tick && e.tick <= p.tick + 8);
      if (!started) {
        const why = p.kind === 'ability' ? 'the loadout has no ability on that button' : 'the body was still busy or the action was cooling down';
        warnings.push(`${name} step ${p.step}: the ${p.kind} press on tick ${p.tick} was dropped (${why})`);
      }
    }
    for (const s of log.steps) {
      for (const f of s.flags) if (f.startsWith('LATE') || f === 'TIMED OUT') warnings.push(`${name} step ${s.n} (${s.text}): ${f}`);
      if (s.startTick === null) warnings.push(`${name} step ${s.n} (${s.text}): never reached; the take ran out first`);
      else if (s.endTick === null && !(s.n === log.steps.length && s.restful)) {
        // (A final wait / hold that simply outlasts the take is what the designer meant.)
        const blocked = s.flags.includes('way blocked') ? ' (the way was blocked)' : '';
        warnings.push(`${name} step ${s.n} (${s.text}): still in progress when the take ended${blocked}`);
      }
    }
  });
  if (run.takesRecorded < takes.length) {
    warnings.push(`the run already wins after take ${run.takesRecorded}; take${takes.length - run.takesRecorded > 1 ? 's' : ''} ${run.takesRecorded + 1}..${takes.length} were never recorded (delete them or make them matter)`);
  }
  return { loadout, logs, takesRecorded: run.takesRecorded, tapes, resolution: session.resolution!, outcome: run.outcome, warnings };
}

/** The combined run of tapes[0..k], exactly as the Session resolves it after take k+1. */
export function resolvePrefix(level: LevelDef, loadout: ResolvedLoadout, tapes: readonly Tape[], count: number): Resolution {
  const used = tapes.slice(0, count);
  // The boss remembers committed tapes only: every tape but the one just recorded.
  return resolveEncounter({ level, loadout, tapes: used, bossMemory: buildBossMemory(level, used.slice(0, -1)) });
}

export interface StoredReplay {
  outcome: Outcome;
  tapes: Tape[];
  takesRecorded: number;
}

/** Replay the stored per-tick inputs open-loop through a real Session (APP-TEST-03). */
export function replayStoredInputs(level: LevelDef, sol: SolutionFile, loadout: ResolvedLoadout = solutionLoadout(sol)): StoredReplay {
  const g = requireGenerated(sol);
  const bots = sol.takes.map((take, i) => {
    if (!Array.isArray(take.inputs) || typeof g.ticks?.[i] !== 'number') throw new Error(`take ${i + 1} has no recorded inputs; run \`level.ts run <level> --write\``);
    return replayTake(take, decodeInputs(take.inputs, g.ticks[i]));
  });
  const run = runBotDetailed(level, bots, { loadout });
  const tapes = [...run.session.committedTapes];
  if (run.session.pendingTape) tapes.push(run.session.pendingTape);
  return { outcome: run.outcome, tapes, takesRecorded: run.takesRecorded };
}

/** Resolve the stored tapes under playback rules, without recording anything. */
export function replayStoredTapes(level: LevelDef, sol: SolutionFile, loadout: ResolvedLoadout = solutionLoadout(sol)): Resolution {
  const g = requireGenerated(sol);
  const tapes = g.tapes.map(deserializeTape);
  return resolvePrefix(level, loadout, tapes, tapes.length);
}

function requireGenerated(sol: SolutionFile): GeneratedSection {
  if (!sol.generated) throw new Error('the solution has no generated section; run `level.ts run <level> --write`');
  return sol.generated;
}

/** Event types the timeline keeps: what happened, without footsteps and telegraphs. */
const TIMELINE_TYPES: ReadonlySet<string> = new Set([
  'swing', 'hit', 'kill', 'break', 'clang', 'dodge', 'fire', 'interact', 'interactFail', 'door', 'plate', 'laser', 'core',
  'selfDeath', 'desync', 'resync', 'tapeWrap', 'tapeTurn', 'tapeEnd', 'enemyAttack', 'enemyShot', 'bossPhase', 'objective',
]);

export function timelineOf(level: LevelDef, events: readonly SimEvent[]): TimelineEntry[] {
  const spb = subsPerBeat(level);
  const out: TimelineEntry[] = [];
  for (const e of events) {
    if (!TIMELINE_TYPES.has(e.type)) continue;
    out.push([Math.round((e.sub / spb) * 1000) / 1000, e.type, e.tape !== undefined ? TAPE_NAMES[e.tape] : '', e.id ?? '', e.detail ?? '']);
  }
  return out;
}

/**
 * The solution with everything the tools generate filled in from a finished run: each take's
 * recorded inputs, the `expect` block the Godot bot checks, and the generated section.
 * Throws when the run did not use every take (a stored solution has no dead takes).
 */
export function compiledSolution(level: LevelDef, sol: SolutionFile, run: SolutionRun): SolutionFile {
  if (run.takesRecorded !== sol.takes.length) throw new Error(`the run used ${run.takesRecorded} of ${sol.takes.length} takes; delete the takes that are never recorded`);
  const generated: GeneratedSection = {
    format: 1,
    levelHash: levelHash(level),
    planHash: planHash(sol),
    loadout: solutionLoadoutIds(sol),
    ticksPerBeat: ticksPerBeat(level),
    takesRecorded: run.takesRecorded,
    ticks: run.logs.map((l) => l.inputs.length),
    tapes: run.tapes.map(serializeTape),
    outcome: run.outcome,
    timeline: timelineOf(level, run.resolution.events),
  };
  const worn = loadoutBySlot(sol);
  return {
    version: 1,
    level: sol.level,
    ...(worn !== undefined ? { loadout: worn } : {}),
    expect: { win: run.outcome.win, takes: run.takesRecorded },
    takes: sol.takes.map((t, i) => ({ speed: t.speed, endMode: t.endMode, note: t.note, plan: t.plan, inputs: encodeInputs(run.logs[i].inputs) })),
    generated,
  };
}

function sameJson(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

export function sameOutcome(a: Outcome, b: Outcome): boolean {
  return a.win === b.win && a.objectiveComplete === b.objectiveComplete && a.reason === b.reason && sameJson(a.survivors, b.survivors) && sameJson(a.notes, b.notes);
}

/**
 * Check a generated section against the engine: the stored inputs must reproduce the stored tapes
 * bit for bit and the stored outcome, and the stored tapes alone must resolve to that outcome.
 * Returns the discrepancies (empty = the section is sound).
 */
export function verifyGenerated(level: LevelDef, sol: SolutionFile): string[] {
  const g = requireGenerated(sol);
  const out: string[] = [];
  const loadout = solutionLoadout(sol);
  const byInputs = replayStoredInputs(level, sol, loadout);
  if (!sameOutcome(byInputs.outcome, g.outcome)) out.push(`replaying the stored inputs gives a different outcome: ${byInputs.outcome.notes.join(' ')}`);
  if (byInputs.tapes.length !== g.tapes.length) out.push(`replaying the stored inputs records ${byInputs.tapes.length} tape(s), the file stores ${g.tapes.length}`);
  else {
    byInputs.tapes.forEach((t, i) => {
      if (!sameJson(serializeTape(t), g.tapes[i])) out.push(`replaying the stored inputs records a different tape ${TAPE_NAMES[i]} than the one stored`);
    });
  }
  const byTapes = replayStoredTapes(level, sol, loadout);
  if (!sameOutcome(byTapes.outcome, g.outcome)) out.push(`resolving the stored tapes gives a different outcome: ${byTapes.outcome.notes.join(' ')}`);
  if (!sameJson(timelineOf(level, byTapes.events), g.timeline)) out.push('resolving the stored tapes gives a different event timeline than the one stored');
  return out;
}

// ───────────────────────────── robustness ─────────────────────────────

export interface Variant {
  label: string;
  mutations: TakeMutation[];
}

export interface VariantResult {
  label: string;
  win: boolean;
  /** Why it failed, in the game's words (empty for a win). */
  notes: string[];
}

/** Position nudge used by the robustness check, tiles. */
export const NUDGE = 0.08;

/**
 * The perturbations to try.
 *   quick — every take one local tick late / early together, then each take on its own (the test).
 *   full  — the same for one and two ticks, plus every goto / via target nudged NUDGE tiles in the
 *           four axis directions, plus a tick of lateness combined with each diagonal nudge.
 */
export function mutationVariants(takes: number, depth: 'quick' | 'full'): Variant[] {
  const out: Variant[] = [];
  const all = (m: TakeMutation): TakeMutation[] => Array.from({ length: takes }, () => m);
  const sign = (n: number): string => (n > 0 ? `+${n}` : `${n}`);
  const shifts = depth === 'quick' ? [1, -1] : [1, -1, 2, -2];
  for (const s of shifts) out.push({ label: `all takes ${sign(s)} tick${Math.abs(s) > 1 ? 's' : ''}`, mutations: all({ shift: s, dx: 0, dy: 0 }) });
  if (takes > 1) {
    for (let t = 0; t < takes; t++) {
      for (const s of shifts) {
        const mutations = all(NO_MUTATION);
        mutations[t] = { shift: s, dx: 0, dy: 0 };
        out.push({ label: `take ${t + 1} (${TAPE_NAMES[t]}) ${sign(s)} tick${Math.abs(s) > 1 ? 's' : ''}`, mutations });
      }
    }
  }
  if (depth === 'full') {
    const dirs: [string, number, number][] = [['east', 1, 0], ['west', -1, 0], ['south', 0, 1], ['north', 0, -1]];
    for (const [name, x, y] of dirs) out.push({ label: `targets ${NUDGE} tiles ${name}`, mutations: all({ shift: 0, dx: x * NUDGE, dy: y * NUDGE }) });
    const diag: [string, number, number, number][] = [['south-east', 1, 1, 1], ['north-west', -1, -1, 1], ['north-east', 1, -1, -1], ['south-west', -1, 1, -1]];
    for (const [name, x, y, s] of diag) {
      out.push({ label: `all takes ${sign(s)} tick, targets ${NUDGE} tiles ${name}`, mutations: all({ shift: s, dx: x * NUDGE * Math.SQRT1_2, dy: y * NUDGE * Math.SQRT1_2 }) });
    }
  }
  return out;
}

export function runVariants(level: LevelDef, sol: SolutionFile, variants: readonly Variant[], loadout?: ResolvedLoadout): VariantResult[] {
  return variants.map((v) => {
    const run = runSolution(level, sol, { mutations: v.mutations, loadout });
    return { label: v.label, win: run.outcome.win, notes: run.outcome.win ? [] : run.outcome.notes };
  });
}
