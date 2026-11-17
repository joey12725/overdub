/**
 * The solution file format (data/levels/solutions/README.md): types, checks, the run-length input
 * encoding, loadout resolution and the canonical text layout the tools write.
 *
 * The file is also a plan file of the Godot bot (game/bot.gd `GameBot.load_plan`), which reads
 * `version`, `level`, `loadout` (by slot), `expect` and each take's `speed`, `endMode` and `inputs`;
 * the input encoding here is that reader's span format, so one file serves both engines.
 *
 * Node-free on purpose: tests/levels/campaign.test.ts imports this through Vite, and the project
 * type-checks without Node typings. File access lives in files.ts (CLI only).
 */
import { BASE_LOADOUT, GEAR, resolveLoadout } from '../../src/content/index';
import type { SerializedTape } from '../../src/core/tape';
import { ALL_SPEEDS, GEAR_SLOTS } from '../../src/core/types';
import type { ActionKind, EndMode, GearSlot, LevelDef, Loadout, Outcome, PlayerInput, ResolvedLoadout, TapeSpeed } from '../../src/core/types';

// ───────────────────────────── hand-written part ─────────────────────────────

/** A point in world coordinates: [x, y]. Tile (c, r) covers x in [c, c+1), y in [r, r+1). */
export type Point = [number, number];

/**
 * A moment or a length of time.
 *   6        master beats (the shared world clock, counted from 0 like the HUD ruler)
 *   "90t"    local ticks of this take (60 per recorded second)
 *   "3lb"    local beats of this take (what the player hears while recording)
 */
export type TimeValue = number | string;

/**
 * A direction.
 *   90            degrees, clockwise on the map: 0 = east (+x), 90 = south (+y, down the map), 180 = west, 270 = north
 *   "N" … "NW"    compass names (N is up the map)
 *   [x, y]        toward that point
 *   "g1"          toward the entity with that id (an enemy's current position, or a mechanism)
 */
export type AimValue = number | string | Point;

/** Something to wait for in the world (closed loop: read from the live snapshot every tick). */
export interface Condition {
  /** Enemy id (or mechanism id): true once it is within `dist` tiles of this self. */
  near?: string;
  dist?: number;
  /** Mechanism id: true while it is on (door open, switch on, plate pressed, breakable broken, laser firing, core lit). */
  on?: string;
  /** Mechanism id: true while it is off. */
  off?: string;
  /** Enemy id: true once it is dead. */
  dead?: string;
  /** Enemy id: true while it is telegraphing an attack. */
  telegraph?: string;
  /** True while an enemy projectile heading for this self is within this many tiles. */
  boltWithin?: number;
}

/** One step of a plan. Exactly one verb (see README); `at` / `landAt` and `note` may accompany any verb. */
export interface PlanStep {
  /** Do nothing until this moment, then perform the step. Alone, it is simply "wait until". */
  at?: TimeValue;
  /** With `press`: press early enough that the action's effect (hit frame, launch) lands at this moment. */
  landAt?: TimeValue;
  /** Run to a point and stop there (path-finds around walls and closed doors). */
  goto?: Point;
  /** Run through a point at full speed without slowing down (a waypoint, or a run-up). */
  via?: Point;
  /** Arrival distance for goto / via, tiles. */
  tol?: number;
  /** goto / via: steer in a straight line, no path-finding. */
  straight?: boolean;
  /** Press a button for one tick. With goto / via: on arrival. */
  press?: ActionKind;
  /** Direction of the press (default: the direction last faced or travelled). */
  aim?: AimValue;
  /** After a press: do not wait for the action to finish before the next step. */
  nowait?: boolean;
  /** Set the direction later presses use when they give no `aim`. */
  face?: AimValue;
  /** Stand still for a length of time. `hold` is the same thing. */
  wait?: TimeValue;
  hold?: TimeValue;
  /** Stand still until a master beat / a local tick. */
  waitUntilBeat?: number;
  waitUntilTick?: number;
  /** Stand still until something is true in the world. */
  waitFor?: Condition;
  /** With waitFor: give up after this long and carry on. */
  timeout?: TimeValue;
  /** Free text for the reader; ignored by the tools. */
  note?: string;
}

/**
 * One entry of a take's recorded input stream (the Godot bot's "inputs" format, game/bot.gd):
 *   { from, to, move: [x, y], aim }   the stick and aim for local ticks [from, to)
 *   { tick, press, aim }              one button going down on one tick
 * Later spans override earlier ones where they overlap; a press's aim overrides the span's.
 */
export type InputEntry = { from: number; to: number; move?: [number, number]; aim?: number } | { tick: number; press: ActionKind; aim?: number };

export interface SolutionTake {
  speed: TapeSpeed;
  endMode: EndMode;
  /** What this take is for, in a sentence. */
  note: string;
  plan: PlanStep[];
  /** GENERATED: the exact input of every local tick of this take, run-length encoded. */
  inputs?: InputEntry[];
}

// ───────────────────────────── generated part ─────────────────────────────

/** A gameplay event of the final combined run: [master beat, type, tape letter or "", id or "", detail or ""]. */
export type TimelineEntry = [number, string, string, string, string];

export interface GeneratedSection {
  /** Format version of this section. */
  format: 1;
  /** Fingerprints of the level file and of the hand-written part when this was generated. */
  levelHash: string;
  planHash: string;
  /** The gear every take wore (ids per slot). */
  loadout: Loadout;
  ticksPerBeat: number;
  /** Takes recorded (= the number of takes: the tools refuse to store a plan with unused takes). */
  takesRecorded: number;
  /** Per take: local ticks recorded, i.e. how many ticks its `inputs` cover. */
  ticks: number[];
  /** Per take: the recorded trajectory (src/core/tape.ts serializeTape). */
  tapes: SerializedTape[];
  /** Result of the combined run of those tapes. */
  outcome: Outcome;
  /** The combined run's gameplay events, for comparing another engine's replay against. */
  timeline: TimelineEntry[];
}

export interface SolutionFile {
  /** File format version: 1. Written by the tools; the Godot bot refuses a file without it. */
  version?: 1;
  /** Level id (= the level file name without .json). */
  level: string;
  /**
   * Gear worn instead of the baseline: `{ "<slot>": "<gear id>" }` (the shape the Godot bot reads),
   * or a plain list of gear ids, which the tools turn into that shape when they write the file.
   * Omit for the baseline loadout.
   */
  loadout?: string[] | Partial<Record<GearSlot, string>>;
  /** GENERATED: what the Godot bot checks after replaying (`tools/bot.gd`). */
  expect?: { win: boolean; takes?: number };
  takes: SolutionTake[];
  generated?: GeneratedSection;
}

// ───────────────────────────── checks ─────────────────────────────

export const PRESS_KINDS: readonly ActionKind[] = ['light', 'heavy', 'dodge', 'ranged', 'interact', 'ability'];
const END_MODES: readonly EndMode[] = ['stop', 'repeat', 'reverse'];
const VERBS = ['goto', 'via', 'press', 'face', 'wait', 'hold', 'waitUntilBeat', 'waitUntilTick', 'waitFor'] as const;
const STEP_KEYS: ReadonlySet<string> = new Set([...VERBS, 'at', 'landAt', 'tol', 'straight', 'aim', 'nowait', 'timeout', 'note']);
const FILE_KEYS: ReadonlySet<string> = new Set(['version', 'level', 'loadout', 'expect', 'takes', 'generated']);
const TAKE_KEYS: ReadonlySet<string> = new Set(['speed', 'endMode', 'note', 'plan', 'inputs']);
const CONDITION_KEYS: ReadonlySet<string> = new Set(['near', 'dist', 'on', 'off', 'dead', 'telegraph', 'boltWithin']);
export const COMPASS: Readonly<Record<string, number>> = { E: 0, SE: 45, S: 90, SW: 135, W: 180, NW: 225, N: 270, NE: 315 };

function isNum(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v);
}

function isPoint(v: unknown): v is Point {
  return Array.isArray(v) && v.length === 2 && isNum(v[0]) && isNum(v[1]);
}

/** Parse a TimeValue into its unit. Null when malformed. */
export function parseTime(v: unknown): { unit: 'beat' | 'tick' | 'localBeat'; n: number } | null {
  if (isNum(v)) return v >= 0 ? { unit: 'beat', n: v } : null;
  if (typeof v !== 'string') return null;
  const m = /^(\d+(?:\.\d+)?)\s*(t|lb|b)$/.exec(v.trim());
  if (!m) return null;
  const n = Number(m[1]);
  return { unit: m[2] === 't' ? 'tick' : m[2] === 'lb' ? 'localBeat' : 'beat', n };
}

/** Ids a plan may name, by what they are. */
export function levelIds(level: LevelDef): { enemies: Set<string>; mechs: Set<string> } {
  const enemies = new Set<string>();
  const mechs = new Set<string>();
  for (const e of level.entities) {
    if (e.kind === 'enemy') enemies.add(e.id);
    else if (e.kind !== 'decor') mechs.add(e.id);
  }
  return { enemies, mechs };
}

function checkAim(v: unknown, where: string, level: LevelDef, out: string[]): void {
  if (isNum(v) || isPoint(v)) return;
  if (typeof v === 'string') {
    if (v in COMPASS) return;
    const ids = levelIds(level);
    if (ids.enemies.has(v) || ids.mechs.has(v)) return;
    out.push(`${where}: "${v}" is neither a compass direction (${Object.keys(COMPASS).join(', ')}) nor an entity id of this level`);
    return;
  }
  out.push(`${where}: must be degrees, a compass name, a point [x, y] or an entity id`);
}

/** Structural problems of a solution against its level (empty = fine). Does not run anything. */
export function checkSolution(sol: SolutionFile, level: LevelDef): string[] {
  const out: string[] = [];
  if (typeof sol !== 'object' || sol === null) return ['solution must be a JSON object'];
  for (const k of Object.keys(sol)) if (!FILE_KEYS.has(k)) out.push(`unknown key "${k}" (a solution has version, level, loadout, takes; the tools add expect and generated)`);
  if (sol.version !== undefined && sol.version !== 1) out.push(`"version" is ${JSON.stringify(sol.version)}; this format is version 1`);
  if (sol.level !== level.id) out.push(`"level" is ${JSON.stringify(sol.level)} but the level's id is "${level.id}"`);
  out.push(...loadoutProblems(sol.loadout));
  if (!Array.isArray(sol.takes) || sol.takes.length === 0) {
    out.push('"takes" must be a non-empty array');
    return out;
  }
  if (sol.takes.length > level.maxTapes) out.push(`${sol.takes.length} takes but the level offers ${level.maxTapes} cassette(s)`);
  const ids = levelIds(level);
  sol.takes.forEach((take, t) => {
    const T = `take ${t + 1}`;
    if (typeof take !== 'object' || take === null) {
      out.push(`${T}: must be an object`);
      return;
    }
    for (const k of Object.keys(take)) {
      if (TAKE_KEYS.has(k)) continue;
      if (k === 'steps' || k === 'reflex') out.push(`${T}: "${k}" belongs to the Godot bot's own step list (game/bot.gd); the level tools compile a "plan" instead`);
      else out.push(`${T}: unknown key "${k}"`);
    }
    if (!ALL_SPEEDS.includes(take.speed)) out.push(`${T}: speed ${JSON.stringify(take.speed)} is not one of ${ALL_SPEEDS.join(', ')}`);
    else if (!level.speeds.includes(take.speed)) out.push(`${T}: speed ${take.speed}x is not offered by the level (${level.speeds.join(', ')})`);
    if (!END_MODES.includes(take.endMode)) out.push(`${T}: endMode ${JSON.stringify(take.endMode)} is not one of ${END_MODES.join(', ')}`);
    else if (!level.endModes.includes(take.endMode)) out.push(`${T}: end mode '${take.endMode}' is not offered by the level (${level.endModes.join(', ')})`);
    if (typeof take.note !== 'string' || take.note.trim() === '') out.push(`${T}: "note" must say what the take is for`);
    if (!Array.isArray(take.plan)) {
      out.push(`${T}: "plan" must be an array of steps`);
      return;
    }
    take.plan.forEach((step, s) => {
      const S = `${T} step ${s + 1}`;
      if (typeof step !== 'object' || step === null || Array.isArray(step)) {
        out.push(`${S}: must be an object`);
        return;
      }
      for (const k of Object.keys(step)) if (!STEP_KEYS.has(k)) out.push(`${S}: unknown key "${k}"`);
      const verbs = VERBS.filter((v) => (step as Record<string, unknown>)[v] !== undefined);
      const moves = verbs.filter((v) => v === 'goto' || v === 'via');
      const others = verbs.filter((v) => v !== 'goto' && v !== 'via' && v !== 'press');
      if (moves.length > 1) out.push(`${S}: goto and via cannot be combined`);
      if (others.length > 1 || (others.length === 1 && (moves.length > 0 || step.press !== undefined))) {
        out.push(`${S}: one verb per step (found ${verbs.join(' + ')}); only press may ride on goto / via`);
      }
      if (verbs.length === 0 && step.at === undefined) out.push(`${S}: has no verb (goto, via, press, face, wait, hold, waitUntilBeat, waitUntilTick, waitFor, or at alone)`);
      for (const k of ['at', 'landAt', 'wait', 'hold', 'timeout'] as const) {
        if (step[k] !== undefined && parseTime(step[k]) === null) out.push(`${S}: ${k} must be master beats (a number), local ticks ("90t") or local beats ("3lb")`);
      }
      if (step.at !== undefined && step.landAt !== undefined) out.push(`${S}: use at or landAt, not both`);
      if (step.landAt !== undefined && step.press === undefined) out.push(`${S}: landAt needs a press`);
      if (step.goto !== undefined && !isPoint(step.goto)) out.push(`${S}: goto must be [x, y]`);
      if (step.via !== undefined && !isPoint(step.via)) out.push(`${S}: via must be [x, y]`);
      if (step.tol !== undefined && !(isNum(step.tol) && step.tol > 0)) out.push(`${S}: tol must be a positive number of tiles`);
      if (step.tol !== undefined && moves.length === 0) out.push(`${S}: tol only applies to goto / via`);
      if (step.press !== undefined && !PRESS_KINDS.includes(step.press)) out.push(`${S}: press must be one of ${PRESS_KINDS.join(', ')}`);
      if (step.aim !== undefined) {
        if (step.press === undefined) out.push(`${S}: aim needs a press (use face to set a direction on its own)`);
        checkAim(step.aim, `${S} aim`, level, out);
      }
      if (step.face !== undefined) checkAim(step.face, `${S} face`, level, out);
      if (step.waitUntilBeat !== undefined && !(isNum(step.waitUntilBeat) && step.waitUntilBeat >= 0)) out.push(`${S}: waitUntilBeat must be a master beat (number >= 0)`);
      if (step.waitUntilTick !== undefined && !(Number.isInteger(step.waitUntilTick) && step.waitUntilTick >= 0)) out.push(`${S}: waitUntilTick must be a local tick (integer >= 0)`);
      if (step.timeout !== undefined && step.waitFor === undefined) out.push(`${S}: timeout only applies to waitFor`);
      if (step.waitFor !== undefined) {
        const c = step.waitFor;
        if (typeof c !== 'object' || c === null || Array.isArray(c)) {
          out.push(`${S}: waitFor must be an object such as { "near": "g1", "dist": 1.3 }`);
        } else {
          for (const k of Object.keys(c)) if (!CONDITION_KEYS.has(k)) out.push(`${S}: waitFor has unknown key "${k}"`);
          const kinds = (['near', 'on', 'off', 'dead', 'telegraph', 'boltWithin'] as const).filter((k) => c[k] !== undefined);
          if (kinds.length !== 1) out.push(`${S}: waitFor needs exactly one of near, on, off, dead, telegraph, boltWithin`);
          if (c.near !== undefined) {
            if (!ids.enemies.has(c.near) && !ids.mechs.has(c.near)) out.push(`${S}: waitFor.near "${c.near}" is not an entity id of this level`);
            if (!(isNum(c.dist) && c.dist > 0)) out.push(`${S}: waitFor.near needs "dist" (tiles)`);
          }
          for (const k of ['on', 'off'] as const) if (c[k] !== undefined && !ids.mechs.has(c[k]!)) out.push(`${S}: waitFor.${k} "${c[k]}" is not a mechanism id of this level`);
          for (const k of ['dead', 'telegraph'] as const) if (c[k] !== undefined && !ids.enemies.has(c[k]!)) out.push(`${S}: waitFor.${k} "${c[k]}" is not an enemy id of this level`);
          if (c.boltWithin !== undefined && !(isNum(c.boltWithin) && c.boltWithin > 0)) out.push(`${S}: waitFor.boltWithin must be a distance in tiles`);
        }
      }
    });
  });
  return out;
}

// ───────────────────────────── loadout ─────────────────────────────

function loadoutProblems(loadout: SolutionFile['loadout']): string[] {
  const out: string[] = [];
  if (loadout === undefined) return out;
  if (Array.isArray(loadout)) {
    const slots = new Set<string>();
    for (const id of loadout) {
      const item = GEAR[id];
      if (!item) out.push(`loadout: unknown gear id ${JSON.stringify(id)}`);
      else if (slots.has(item.slot)) out.push(`loadout: two items for the ${item.slot} slot`);
      else slots.add(item.slot);
    }
  } else if (typeof loadout === 'object' && loadout !== null) {
    for (const [slot, id] of Object.entries(loadout)) {
      if (!(GEAR_SLOTS as readonly string[]).includes(slot)) out.push(`loadout: "${slot}" is not a gear slot (${GEAR_SLOTS.join(', ')})`);
      else if (typeof id !== 'string' || !GEAR[id]) out.push(`loadout: unknown gear id ${JSON.stringify(id)}`);
      else if (GEAR[id].slot !== slot) out.push(`loadout: "${id}" is a ${GEAR[id].slot} item, not ${slot}`);
    }
  } else out.push('"loadout" must be { "<slot>": "<gear id>" } or a list of gear ids (omit it for the baseline)');
  return out;
}

/** The gear ids per slot a solution wears: the baseline with the named items swapped in. */
export function solutionLoadoutIds(sol: Pick<SolutionFile, 'loadout'>): Loadout {
  const problems = loadoutProblems(sol.loadout);
  if (problems.length) throw new Error(`solution ${problems[0]}`);
  const ids: Loadout = { ...BASE_LOADOUT };
  const worn = sol.loadout === undefined ? [] : Array.isArray(sol.loadout) ? sol.loadout : Object.values(sol.loadout);
  for (const id of worn) ids[GEAR[id as string].slot] = id as string;
  return ids;
}

/** The loadout as the file stores it: only the slots that differ from the baseline, by slot. Undefined for the baseline. */
export function loadoutBySlot(sol: Pick<SolutionFile, 'loadout'>): Partial<Record<GearSlot, string>> | undefined {
  const ids = solutionLoadoutIds(sol);
  const out: Partial<Record<GearSlot, string>> = {};
  for (const slot of GEAR_SLOTS) if (ids[slot] !== BASE_LOADOUT[slot]) out[slot] = ids[slot];
  return Object.keys(out).length ? out : undefined;
}

export function solutionLoadout(sol: Pick<SolutionFile, 'loadout'>): ResolvedLoadout {
  return resolveLoadout(solutionLoadoutIds(sol));
}

export function baselineLoadout(): ResolvedLoadout {
  return resolveLoadout(BASE_LOADOUT);
}

export function usesBaseline(sol: Pick<SolutionFile, 'loadout'>): boolean {
  return loadoutProblems(sol.loadout).length === 0 && loadoutBySlot(sol) === undefined;
}

// ───────────────────────────── input stream encoding ─────────────────────────────

/**
 * Run-length encode a take's input stream: first every button press (tick, button, aim on that
 * tick), then one span per run of ticks with the same stick and aim. The spans tile [0, ticks)
 * without gaps or overlaps, so the stream decodes to exactly the inputs that were recorded.
 */
export function encodeInputs(inputs: readonly PlayerInput[]): InputEntry[] {
  const presses: InputEntry[] = [];
  const spans: { from: number; to: number; move: [number, number]; aim: number }[] = [];
  inputs.forEach((i, tick) => {
    for (const k of PRESS_KINDS) if (i[k]) presses.push({ tick, press: k, aim: i.aim });
    const last = spans[spans.length - 1];
    if (last && last.move[0] === i.moveX && last.move[1] === i.moveY && last.aim === i.aim) last.to = tick + 1;
    else spans.push({ from: tick, to: tick + 1, move: [i.moveX, i.moveY], aim: i.aim });
  });
  return [...presses, ...spans];
}

/**
 * The input of every local tick 0 .. ticks-1 from an encoded stream, by the rules of the Godot
 * bot's reader (game/bot.gd TickScript): the last span covering a tick wins, separately for the
 * stick and the aim; with no aim span the aim follows the stick; a press sets its button and, when
 * it carries one, the aim of that tick.
 */
export function decodeInputs(entries: readonly InputEntry[], ticks: number): PlayerInput[] {
  if (!(Number.isInteger(ticks) && ticks >= 0)) throw new Error('solution inputs: bad tick count');
  const out: PlayerInput[] = [];
  const aimSet: boolean[] = [];
  for (let t = 0; t < ticks; t++) {
    out.push({ moveX: 0, moveY: 0, aim: 0, light: false, heavy: false, dodge: false, ranged: false, interact: false, ability: false });
    aimSet.push(false);
  }
  const num = (v: unknown, what: string): number => {
    if (typeof v !== 'number' || !Number.isFinite(v)) throw new Error(`solution inputs: ${what} must be a number`);
    return v;
  };
  for (const e of entries) {
    if ('press' in e) continue;
    const from = Math.max(0, Math.ceil(num(e.from, 'from')));
    const to = Math.min(ticks, Math.ceil(num(e.to, 'to')));
    for (let t = from; t < to; t++) {
      if (e.move !== undefined) {
        out[t].moveX = num(e.move[0], 'move x');
        out[t].moveY = num(e.move[1], 'move y');
      }
      if (e.aim !== undefined) {
        out[t].aim = num(e.aim, 'aim');
        aimSet[t] = true;
      }
    }
  }
  for (let t = 0; t < ticks; t++) if (!aimSet[t] && (out[t].moveX !== 0 || out[t].moveY !== 0)) out[t].aim = Math.atan2(out[t].moveY, out[t].moveX);
  for (const e of entries) {
    if (!('press' in e)) continue;
    if (!PRESS_KINDS.includes(e.press)) throw new Error(`solution inputs: unknown button ${JSON.stringify(e.press)}`);
    const t = num(e.tick, 'tick');
    if (!Number.isInteger(t) || t < 0 || t >= ticks) continue;
    out[t][e.press] = true;
    if (e.aim !== undefined) out[t].aim = num(e.aim, 'aim');
  }
  return out;
}

// ───────────────────────────── fingerprints ─────────────────────────────

/** FNV-1a (32 bit) of a string, as 8 hex digits. */
export function fnv1a(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

/** Fingerprint of a level's data (whitespace-independent; key order as in the file). */
export function levelHash(level: LevelDef): string {
  return fnv1a(JSON.stringify(level));
}

/** Fingerprint of the hand-written part of a solution: level, gear worn, and each take's speed, end mode, note and plan. */
export function planHash(sol: SolutionFile): string {
  const takes = sol.takes.map((t) => ({ speed: t.speed, endMode: t.endMode, note: t.note, plan: t.plan }));
  return fnv1a(JSON.stringify({ level: sol.level, loadout: solutionLoadoutIds(sol), takes }));
}

/** Why a generated section no longer matches its level / plan (empty = current). */
export function staleReasons(sol: SolutionFile, level: LevelDef): string[] {
  const g = sol.generated;
  if (!g) return ['the solution has no generated section yet'];
  const out: string[] = [];
  if (g.format !== 1) out.push(`generated.format is ${String(g.format)}, the tools write 1`);
  if (g.levelHash !== levelHash(level)) out.push('the level file changed since the solution was compiled');
  if (g.planHash !== planHash(sol)) out.push('the plan changed since the solution was compiled');
  if (sol.takes.some((t) => !Array.isArray(t.inputs)) || !Array.isArray(g.ticks) || g.ticks.length !== sol.takes.length) {
    out.push('a take has no recorded inputs');
  }
  return out;
}

// ───────────────────────────── canonical text ─────────────────────────────

function oneLine(v: unknown): string {
  // JSON on one line with a space after separators, for steps, runs and events.
  if (Array.isArray(v)) return `[${v.map(oneLine).join(', ')}]`;
  if (v && typeof v === 'object') {
    const parts = Object.entries(v as Record<string, unknown>)
      .filter(([, x]) => x !== undefined)
      .map(([k, x]) => `${JSON.stringify(k)}: ${oneLine(x)}`);
    return parts.length ? `{ ${parts.join(', ')} }` : '{}';
  }
  return JSON.stringify(v);
}

function lines(items: readonly unknown[], indent: string): string {
  if (items.length === 0) return '[]';
  return `[\n${items.map((i) => `${indent}  ${oneLine(i)}`).join(',\n')}\n${indent}]`;
}

/**
 * The text the tools write: one plan step and one input entry per line inside each take, then the
 * generated section with one tape / event per line. Stable, so diffs stay small.
 */
export function formatSolution(sol: SolutionFile): string {
  const out: string[] = ['{'];
  out.push('  "version": 1,');
  out.push(`  "level": ${JSON.stringify(sol.level)},`);
  const worn = loadoutBySlot(sol);
  if (worn !== undefined) out.push(`  "loadout": ${oneLine(worn)},`);
  if (sol.expect !== undefined) out.push(`  "expect": ${oneLine(sol.expect)},`);
  out.push('  "takes": [');
  sol.takes.forEach((t, i) => {
    out.push('    {');
    out.push(`      "speed": ${JSON.stringify(t.speed)},`);
    out.push(`      "endMode": ${JSON.stringify(t.endMode)},`);
    out.push(`      "note": ${JSON.stringify(t.note)},`);
    out.push(`      "plan": ${lines(t.plan, '      ')}${t.inputs !== undefined ? ',' : ''}`);
    if (t.inputs !== undefined) out.push(`      "inputs": ${lines(t.inputs, '      ')}`);
    out.push(i === sol.takes.length - 1 ? '    }' : '    },');
  });
  const g = sol.generated;
  out.push(g ? '  ],' : '  ]');
  if (g) {
    out.push('  "generated": {');
    out.push(`    "format": ${g.format},`);
    out.push(`    "levelHash": ${JSON.stringify(g.levelHash)},`);
    out.push(`    "planHash": ${JSON.stringify(g.planHash)},`);
    out.push(`    "loadout": ${oneLine(g.loadout)},`);
    out.push(`    "ticksPerBeat": ${g.ticksPerBeat},`);
    out.push(`    "takesRecorded": ${g.takesRecorded},`);
    out.push(`    "ticks": ${oneLine(g.ticks)},`);
    out.push(`    "tapes": ${lines(g.tapes, '    ')},`);
    out.push('    "outcome": {');
    out.push(`      "win": ${g.outcome.win},`);
    out.push(`      "objectiveComplete": ${g.outcome.objectiveComplete},`);
    out.push(`      "survivors": ${oneLine(g.outcome.survivors)},`);
    if (g.outcome.reason !== undefined) out.push(`      "reason": ${JSON.stringify(g.outcome.reason)},`);
    out.push(`      "notes": ${lines(g.outcome.notes, '      ')}`);
    out.push('    },');
    out.push(`    "timeline": ${lines(g.timeline, '    ')}`);
    out.push('  }');
  }
  out.push('}');
  return out.join('\n') + '\n';
}
