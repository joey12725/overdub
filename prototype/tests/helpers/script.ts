/**
 * Test helper: script player input by local tick, record takes, build exact tapes, resolve runs.
 *
 *   const s = script()
 *     .run(0, 30, 1, 0)          // ticks [0, 30): move right
 *     .aim(0, 200, Math.PI / 2)  // aim down for ticks [0, 200)
 *     .press(40, 'light')        // light attack on tick 40 (aim = current aim)
 *     .press(60, 'interact');
 *   const take = recordTake({ level, index: 0, speed: 1, script: s });
 *   const res = resolve(level, [take.tape]);
 *
 * For kernel tests that need exact choreography independent of player physics, `pathTape` builds a
 * tape straight from waypoints (positions per local tick) plus events.
 */
import { createSim, resolveEncounter } from '../../src/core/index';
import { animIndex } from '../../src/core/tape';
import type {
  ActionKind,
  EndMode,
  FrameSnapshot,
  ISim,
  LevelDef,
  Outcome,
  PlayerInput,
  Resolution,
  ResolvedLoadout,
  SimEvent,
  Tape,
  TapeEvent,
  TapeIndex,
  TapeSpeed,
} from '../../src/core/types';
import { baseLoadout } from './loadout';

export type Button = 'light' | 'heavy' | 'dodge' | 'ranged' | 'interact' | 'ability';

interface Span<T> {
  from: number;
  to: number;
  value: T;
}

export class InputScript {
  private readonly moves: Span<{ x: number; y: number }>[] = [];
  private readonly aims: Span<number>[] = [];
  private readonly presses = new Map<number, { button: Button; aim?: number }[]>();

  /** Move along (x, y) for ticks [from, to). Later spans override earlier ones where they overlap. */
  run(from: number, to: number, x: number, y: number): this {
    this.moves.push({ from, to, value: { x, y } });
    return this;
  }

  /** Aim at `angle` (radians) for ticks [from, to). */
  aim(from: number, to: number, angle: number): this {
    this.aims.push({ from, to, value: angle });
    return this;
  }

  /** Press a button on one tick; `aim` (optional) overrides the aim on that tick. */
  press(tick: number, button: Button, aim?: number): this {
    const list = this.presses.get(tick) ?? [];
    list.push({ button, aim });
    this.presses.set(tick, list);
    return this;
  }

  /** The input for one local tick. */
  input(tick: number): PlayerInput {
    let mx = 0;
    let my = 0;
    for (const m of this.moves) if (tick >= m.from && tick < m.to) ({ x: mx, y: my } = m.value);
    let aim = 0;
    let aimSet = false;
    for (const a of this.aims) {
      if (tick >= a.from && tick < a.to) {
        aim = a.value;
        aimSet = true;
      }
    }
    if (!aimSet && (mx !== 0 || my !== 0)) aim = Math.atan2(my, mx);
    const inp: PlayerInput = { moveX: mx, moveY: my, aim, light: false, heavy: false, dodge: false, ranged: false, interact: false, ability: false };
    for (const p of this.presses.get(tick) ?? []) {
      inp[p.button] = true;
      if (p.aim !== undefined) inp.aim = p.aim;
    }
    return inp;
  }
}

export function script(): InputScript {
  return new InputScript();
}

export interface RecordOpts {
  level: LevelDef;
  loadout?: ResolvedLoadout;
  /** Already-recorded tapes playing alongside the take. */
  tapes?: Tape[];
  index: TapeIndex;
  speed: TapeSpeed;
  endMode?: EndMode;
  script: InputScript;
  /** Stop after this many local ticks (default: the whole allowance). */
  ticks?: number;
}

export interface TakeResult {
  tape: Tape;
  sim: ISim;
  /** Snapshot after every local tick (index i = after tick i, i.e. local tick i + 1 recorded). */
  frames: FrameSnapshot[];
  events: SimEvent[];
  outcome: Outcome;
}

/** Record one take by feeding the script tick by tick. */
export function recordTake(opts: RecordOpts): TakeResult {
  const sim = createSim({
    level: opts.level,
    loadout: opts.loadout ?? baseLoadout(),
    tapes: opts.tapes ?? [],
    live: { index: opts.index, speed: opts.speed, endMode: opts.endMode ?? 'stop' },
  });
  const frames: FrameSnapshot[] = [];
  const events: SimEvent[] = [];
  const limit = opts.ticks ?? sim.tapeTicks;
  for (let t = 0; t < limit && !sim.done; t++) {
    sim.stepLocalTick(opts.script.input(t));
    frames.push(sim.snapshot());
    for (const e of sim.drainEvents()) events.push(e);
  }
  return { tape: sim.liveTape(), sim, frames, events, outcome: sim.outcome() };
}

/** Resolve the combined run under playback rules. */
export function resolve(level: LevelDef, tapes: Tape[], loadout: ResolvedLoadout = baseLoadout()): Resolution {
  return resolveEncounter({ level, loadout, tapes });
}

export interface Waypoint {
  tick: number;
  x: number;
  y: number;
}

export interface PathTapeOpts {
  index: TapeIndex;
  speed: TapeSpeed;
  endMode?: EndMode;
  ticks: number;
  /** Piecewise-linear route by local tick; held before the first and after the last waypoint. */
  path: Waypoint[];
  /** Recorded attempts. dir defaults to the motion direction at that tick (or 0). */
  events?: { tick: number; kind: ActionKind; dir?: number }[];
}

function pointAt(path: Waypoint[], tick: number): { x: number; y: number } {
  if (tick <= path[0].tick) return { x: path[0].x, y: path[0].y };
  for (let i = 1; i < path.length; i++) {
    const a = path[i - 1];
    const b = path[i];
    if (tick <= b.tick) {
      const f = b.tick === a.tick ? 1 : (tick - a.tick) / (b.tick - a.tick);
      return { x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f };
    }
  }
  const l = path[path.length - 1];
  return { x: l.x, y: l.y };
}

/** A tape built directly from waypoints: exact, physics-free choreography for kernel tests. */
export function pathTape(o: PathTapeOpts): Tape {
  const T = o.ticks;
  const pos = new Float32Array((T + 1) * 2);
  const facing = new Float32Array(T + 1);
  const anim = new Uint8Array(T + 1);
  let lastFacing = 0;
  for (let i = 0; i <= T; i++) {
    const p = pointAt(o.path, i);
    pos[i * 2] = p.x;
    pos[i * 2 + 1] = p.y;
  }
  for (let i = 0; i <= T; i++) {
    const j = Math.min(i, T - 1);
    const dx = pos[j * 2 + 2] - pos[j * 2];
    const dy = pos[j * 2 + 3] - pos[j * 2 + 1];
    const moving = T > 0 && (dx !== 0 || dy !== 0);
    if (moving) lastFacing = Math.atan2(dy, dx);
    facing[i] = lastFacing;
    anim[i] = animIndex(moving ? 'run' : 'idle');
  }
  const events: TapeEvent[] = (o.events ?? [])
    .slice()
    .sort((a, b) => a.tick - b.tick)
    .map((e) => {
      const i = Math.min(e.tick, T - 1);
      const vx = (pos[i * 2 + 2] - pos[i * 2]) * 60;
      const vy = (pos[i * 2 + 3] - pos[i * 2 + 1]) * 60;
      return { tick: e.tick, kind: e.kind, dir: e.dir ?? facing[e.tick], x: pos[e.tick * 2], y: pos[e.tick * 2 + 1], vx, vy };
    });
  return { index: o.index, speed: o.speed, endMode: o.endMode ?? 'stop', ticks: T, pos, facing, anim, events };
}

/** Events of one type (optionally for one tape / id). */
export function eventsOf(events: SimEvent[], type: SimEvent['type'], filter: { tape?: TapeIndex; id?: string } = {}): SimEvent[] {
  return events.filter((e) => e.type === type && (filter.tape === undefined || e.tape === filter.tape) && (filter.id === undefined || e.id === filter.id));
}

/** The frame of a resolution at (or just after) a master substep. */
export function frameAt(res: Resolution, sub: number): FrameSnapshot {
  for (const f of res.frames) if (f.sub >= sub) return f;
  return res.frames[res.frames.length - 1];
}
