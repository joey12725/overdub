/**
 * The plan compiler: turns a designer's plan (a short list of timed steps) into a closed-loop
 * controller for the headless bot (src/game/bot.ts). The controller steers with the bot's steerTo,
 * reads only the session's own snapshots (so a take is reproducible), and records every PlayerInput
 * it emits — that stream is what the solution file stores and what the Godot build replays.
 *
 * Language reference: data/levels/solutions/README.md.
 */
import { Grid } from '../../src/core/grid';
import { Pathfinder } from '../../src/core/path';
import { actionTiming } from '../../src/core/player';
import { ticksPerBeat } from '../../src/core/time';
import { BASE } from '../../src/core/tuning';
import { LOCAL_HZ } from '../../src/core/types';
import type { ActionKind, FrameSnapshot, LevelDef, PlayerInput, ResolvedLoadout, Vec2 } from '../../src/core/types';
import { idleInput, steerTo, type BotContext, type BotTake } from '../../src/game/bot';
import { COMPASS, parseTime, type AimValue, type Condition, type PlanStep, type SolutionTake, type TimeValue } from './solution';

/** A perturbation of one take, for the robustness check (mutate.ts). */
export interface TakeMutation {
  /** Local ticks every timed step is late (+) or early (−); a late take also starts late. */
  shift: number;
  /** Offset added to every goto / via target, tiles. */
  dx: number;
  dy: number;
}

export const NO_MUTATION: TakeMutation = { shift: 0, dx: 0, dy: 0 };

export interface StepReport {
  /** 1-based step number. */
  n: number;
  /** The step as the designer wrote it, on one line. */
  text: string;
  /** Local tick the step began / finished on; null when the take ended first. */
  startTick: number | null;
  endTick: number | null;
  /** Where the self stood when the step finished. */
  x: number;
  y: number;
  /** Remarks: late, blocked, timed out, press tick … */
  flags: string[];
  /** The step only stands still (wait, hold, waitUntil…): running out of tape inside it is harmless. */
  restful: boolean;
}

export interface PressRecord {
  tick: number;
  kind: ActionKind;
  step: number;
}

export interface TakeLog {
  /** The exact input of every local tick, in order. */
  inputs: PlayerInput[];
  steps: StepReport[];
  presses: PressRecord[];
  warnings: string[];
}

export interface CompiledTake {
  bot: BotTake;
  log: TakeLog;
}

/** Arrival distance defaults, tiles. */
export const GOTO_TOLERANCE = 0.12;
export const VIA_TOLERANCE = 0.3;
/** Clearance the path-finder keeps from walls: the body radius plus a little. */
const PATH_RADIUS = BASE.actorRadius + 0.02;
/** A running heading is kept while the wanted one is within this angle (keeps the input stream short). */
const HEADING_DEADBAND = 0.01;

const DEG = Math.PI / 180;

function q4(v: number): number {
  const r = Math.round(v * 1e4) / 1e4;
  return r === 0 ? 0 : r;
}

/** Wrap to (-π, π] and round to 1e-4 rad. */
function qAngle(a: number): number {
  let r = a % (2 * Math.PI);
  if (r <= -Math.PI) r += 2 * Math.PI;
  else if (r > Math.PI) r -= 2 * Math.PI;
  return q4(r);
}

export function describeStep(step: PlanStep): string {
  const parts: string[] = [];
  for (const [k, v] of Object.entries(step)) {
    if (k === 'note' || v === undefined) continue;
    parts.push(`${k} ${typeof v === 'object' ? JSON.stringify(v) : String(v)}`);
  }
  return parts.join(', ');
}

/** Position of an entity a plan names: an enemy's current position, or a mechanism's fixed place. */
export function entityPosition(level: LevelDef, snap: FrameSnapshot, id: string): Vec2 | null {
  const enemy = snap.enemies.find((e) => e.id === id);
  if (enemy) return { x: enemy.x, y: enemy.y };
  for (const e of level.entities) {
    if (e.kind === 'decor' || e.id !== id) continue;
    switch (e.kind) {
      case 'enemy':
      case 'switch':
      case 'core':
        return { x: e.x, y: e.y };
      case 'plate':
      case 'breakable':
        return { x: e.c + 0.5, y: e.r + 0.5 };
      case 'exit':
        return { x: e.c + e.w / 2, y: e.r + e.h / 2 };
      case 'door': {
        const n = Math.max(1, e.cells.length);
        return { x: e.cells.reduce((a, c) => a + c.c + 0.5, 0) / n, y: e.cells.reduce((a, c) => a + c.r + 0.5, 0) / n };
      }
      case 'laser':
      case 'sensor':
        return { x: (e.from.x + e.to.x) / 2, y: (e.from.y + e.to.y) / 2 };
      // traps (docs/TRAPS.md)
      case 'spikes':
      case 'crusher':
      case 'conveyor': {
        const n = Math.max(1, e.cells.length);
        return { x: e.cells.reduce((a, c) => a + c.c + 0.5, 0) / n, y: e.cells.reduce((a, c) => a + c.r + 0.5, 0) / n };
      }
      case 'flame':
      case 'dart':
      case 'bumper':
        return { x: e.c + 0.5, y: e.r + 0.5 };
      case 'magnet':
        return { x: e.x, y: e.y };
      case 'relay':
        return e.x !== undefined && e.y !== undefined ? { x: e.x, y: e.y } : null;
    }
  }
  return null;
}

/** Local tick of a moment in a take at `speed` (master beats are converted; fractions round up). */
export function tickOfTime(level: LevelDef, speed: number, v: TimeValue): number {
  const t = parseTime(v);
  if (!t) throw new Error(`bad time value ${JSON.stringify(v)}`);
  const tpb = ticksPerBeat(level);
  if (t.unit === 'tick') return Math.round(t.n);
  if (t.unit === 'localBeat') return Math.ceil(t.n * tpb - 1e-9);
  return Math.ceil(t.n * tpb * speed - 1e-9);
}

/** Compile one take's plan into a bot take plus the log it fills in while the bot runs it. */
export function compileTake(level: LevelDef, loadout: ResolvedLoadout, take: SolutionTake, mutation: TakeMutation = NO_MUTATION): CompiledTake {
  const steps = take.plan;
  const speed = take.speed;
  const log: TakeLog = {
    inputs: [],
    steps: steps.map((s, i) => ({
      n: i + 1,
      text: describeStep(s),
      startTick: null,
      endTick: null,
      x: NaN,
      y: NaN,
      flags: [],
      restful: s.goto === undefined && s.via === undefined && s.press === undefined && s.face === undefined && s.waitFor === undefined,
    })),
    presses: [],
    warnings: [],
  };

  // The room as the path-finder sees it; doors and breakables are synced from each tick's snapshot.
  const grid = Grid.parse(level.map);
  const pathfinder = new Pathfinder(grid);
  const solids: { id: string; cells: { c: number; r: number }[]; solidWhenOn: boolean }[] = [];
  for (const e of level.entities) {
    if (e.kind === 'door') solids.push({ id: e.id, cells: e.cells, solidWhenOn: false });
    else if (e.kind === 'breakable') solids.push({ id: e.id, cells: [{ c: e.c, r: e.r }], solidWhenOn: false });
    else if (e.kind === 'crusher') solids.push({ id: e.id, cells: e.cells, solidWhenOn: true });
  }
  const syncGrid = (snap: FrameSnapshot): void => {
    for (const s of solids) {
      const m = snap.mechs.find((x) => x.id === s.id);
      // Door: on = passable. Breakable: on = broken. Crusher: on = extended, a wall while it lasts.
      const solid = s.solidWhenOn ? m?.on === true : m ? !m.on : true;
      for (const c of s.cells) grid.setDynamicSolid(c.c, c.r, solid);
    }
  };

  const time = (v: TimeValue): number => tickOfTime(level, speed, v);

  let i = 0;
  let aim = level.startFacing ?? 0;
  let busyUntil = 0;
  let busyMove: Vec2 | null = null;
  let until: number | null = null;
  let arrived = false;
  let lastMove: { x: number; y: number; k: number } | null = null;
  const readyAt: Partial<Record<ActionKind, number>> = {};
  const startDelay = Math.max(0, mutation.shift);
  // The body's own velocity in tiles per local second, measured from its last two recorded positions.
  const vel = { x: 0, y: 0, speed: 0 };
  let prev: Vec2 | null = null;
  /** Braking with the stick released, tiles per local second squared (PlayerController.locomote). */
  const brake = (BASE.decel * loadout.mods.accel) / Math.max(0.05, loadout.mods.momentumRetention);

  const resolveAim = (v: AimValue, ctx: BotContext): number => {
    if (typeof v === 'number') return v * DEG;
    if (Array.isArray(v)) return Math.atan2(v[1] - ctx.self.y, v[0] - ctx.self.x);
    if (v in COMPASS) return COMPASS[v] * DEG;
    const p = entityPosition(level, ctx.snap, v);
    if (!p) throw new Error(`plan: no entity "${v}" to aim at`);
    return Math.atan2(p.y - ctx.self.y, p.x - ctx.self.x);
  };

  const holds = (c: Condition, ctx: BotContext): boolean => {
    const { snap, self } = ctx;
    if (c.near !== undefined) {
      const enemy = snap.enemies.find((e) => e.id === c.near);
      if (enemy && !enemy.alive) return false;
      const p = entityPosition(level, snap, c.near);
      return p !== null && Math.hypot(p.x - self.x, p.y - self.y) <= (c.dist ?? 0);
    }
    if (c.on !== undefined) return snap.mechs.find((m) => m.id === c.on)?.on === true;
    if (c.off !== undefined) return snap.mechs.find((m) => m.id === c.off)?.on === false;
    if (c.dead !== undefined) return snap.enemies.find((e) => e.id === c.dead)?.alive === false;
    if (c.telegraph !== undefined) return snap.enemies.find((e) => e.id === c.telegraph)?.state === 'telegraph';
    if (c.boltWithin !== undefined) {
      for (const p of snap.projectiles) {
        if (!('enemy' in p.owner)) continue;
        const dx = self.x - p.x;
        const dy = self.y - p.y;
        if (Math.hypot(dx, dy) <= c.boltWithin && Math.cos(p.dir) * dx + Math.sin(p.dir) * dy > 0) return true;
      }
      return false;
    }
    return false;
  };

  const finish = (tick: number, ctx: BotContext): void => {
    const rep = log.steps[i];
    rep.endTick = tick;
    rep.x = ctx.self.x;
    rep.y = ctx.self.y;
    until = null;
    arrived = false;
    i++;
  };

  /** Steering toward a target: straight when the way is clear, else along the path-finder's route. */
  const steer = (step: PlanStep, ctx: BotContext, tx: number, ty: number, flatOut: boolean): PlayerInput => {
    const self = ctx.self;
    let wx = tx;
    let wy = ty;
    let last = true;
    if (!step.straight && grid.sweepCircleBlocked(self.x, self.y, tx, ty, PATH_RADIUS)) {
      const route = pathfinder.findPath(self.x, self.y, tx, ty, { allowPartial: true, radius: PATH_RADIUS });
      if (route && route.points.length > 0) {
        wx = route.points[0].x;
        wy = route.points[0].y;
        last = route.complete && route.points.length === 1;
        const rep = log.steps[i];
        if (!route.complete && !rep.flags.includes('way blocked')) rep.flags.push('way blocked');
      }
    }
    // Stopping at the target: let go of the stick once the braking distance covers what is left,
    // so the body comes to rest on the spot instead of coasting past it.
    if (last && !flatOut && vel.speed > 0.2) {
      const d = Math.hypot(wx - self.x, wy - self.y);
      if (d <= (vel.speed * vel.speed) / (2 * brake) + vel.speed / (2 * LOCAL_HZ)) return idleInput(aim);
    }
    const inp = steerTo(self, wx, wy, 0.02);
    const len = Math.hypot(inp.moveX, inp.moveY);
    if (len > 1e-9 && (flatOut || !last)) {
      inp.moveX /= len;
      inp.moveY /= len;
    }
    return inp;
  };

  const decide = (tick: number, ctx: BotContext): PlayerInput => {
    if (tick < startDelay) return idleInput(aim);
    if (tick < busyUntil) {
      const inp = idleInput(aim);
      if (busyMove) {
        inp.moveX = busyMove.x;
        inp.moveY = busyMove.y;
      }
      return inp;
    }
    busyMove = null;
    syncGrid(ctx.snap);
    for (;;) {
      if (i >= steps.length) return idleInput(aim);
      const step = steps[i];
      const rep = log.steps[i];
      const timing = step.press ? actionTiming(step.press, loadout) : null;
      if (rep.startTick === null) rep.startTick = tick;

      // "at" / "landAt": stand still until the moment comes.
      let gate: number | null = null;
      if (step.at !== undefined) gate = time(step.at) + mutation.shift;
      else if (step.landAt !== undefined && timing) gate = time(step.landAt) - timing.effect + mutation.shift;
      const isMove = step.goto !== undefined || step.via !== undefined;
      // On a move with a press the gate times the press, not the departure.
      const gateMovesPress = isMove && step.press !== undefined;
      if (gate !== null && !gateMovesPress) {
        if (tick < gate) return idleInput(aim);
        if (tick > gate && rep.startTick === tick && mutation.shift === 0) rep.flags.push(`LATE: wanted tick ${gate}, was free at tick ${tick}`);
      }

      if (step.face !== undefined) {
        aim = resolveAim(step.face, ctx);
        finish(tick, ctx);
        continue;
      }

      const pause = step.wait ?? step.hold;
      if (pause !== undefined) {
        if (until === null) until = tick + tickOfDuration(pause);
        if (tick < until) return idleInput(aim);
        finish(tick, ctx);
        continue;
      }

      if (step.waitUntilBeat !== undefined || step.waitUntilTick !== undefined) {
        const target = (step.waitUntilTick !== undefined ? step.waitUntilTick : time(step.waitUntilBeat!)) + mutation.shift;
        if (tick < target) return idleInput(aim);
        if (tick > target && rep.startTick === tick && mutation.shift === 0) rep.flags.push(`LATE: that moment was tick ${target}, reached at tick ${tick}`);
        finish(tick, ctx);
        continue;
      }

      if (step.waitFor !== undefined) {
        if (holds(step.waitFor, ctx)) {
          finish(tick, ctx);
          continue;
        }
        if (step.timeout !== undefined) {
          if (until === null) until = tick + tickOfDuration(step.timeout);
          if (tick >= until) {
            rep.flags.push('TIMED OUT');
            finish(tick, ctx);
            continue;
          }
        }
        return idleInput(aim);
      }

      let travel: number | null = null;
      if (isMove) {
        const flatOut = step.via !== undefined;
        const target = (step.via ?? step.goto)!;
        const tx = target[0] + mutation.dx;
        const ty = target[1] + mutation.dy;
        const d = Math.hypot(tx - ctx.self.x, ty - ctx.self.y);
        const tol = step.tol ?? (flatOut ? VIA_TOLERANCE : GOTO_TOLERANCE);
        if (d > tol && !arrived) {
          const inp = steer(step, ctx, tx, ty, flatOut);
          if (inp.moveX !== 0 || inp.moveY !== 0) aim = Math.atan2(inp.moveY, inp.moveX);
          return inp;
        }
        // goto means "run there and stop": brake to a standstill (a couple of ticks) before the
        // step counts as done, so a press that follows is a true standing press. via never brakes.
        arrived = true;
        if (!flatOut && vel.speed > 1e-6) return idleInput(aim);
        if (step.press === undefined) {
          finish(tick, ctx);
          continue;
        }
        if (gate !== null) {
          if (tick < gate) return idleInput(aim);
          if (tick > gate && mutation.shift === 0 && !rep.flags.some((f) => f.startsWith('LATE'))) rep.flags.push(`LATE: wanted tick ${gate}, arrived at tick ${tick}`);
        }
        if (flatOut) travel = vel.speed > 1e-6 ? Math.atan2(vel.y, vel.x) : aim;
      }

      if (step.press !== undefined && timing) {
        const kind = step.press;
        // A dodge or a shot still cooling down would be dropped by the controller: wait it out.
        if (tick < (readyAt[kind] ?? 0)) return idleInput(aim);
        const dir = step.aim !== undefined ? resolveAim(step.aim, ctx) : travel ?? aim;
        aim = dir;
        const inp = idleInput(dir);
        inp[kind] = true;
        if (kind === 'dodge') {
          // The controller dashes along the stick, not the aim.
          inp.moveX = Math.cos(dir);
          inp.moveY = Math.sin(dir);
        } else if (travel !== null) {
          inp.moveX = Math.cos(travel);
          inp.moveY = Math.sin(travel);
        }
        readyAt[kind] = tick + timing.cooldown;
        if (!step.nowait) {
          busyUntil = tick + timing.commit;
          busyMove = travel !== null && kind !== 'dodge' ? { x: Math.cos(travel), y: Math.sin(travel) } : null;
        }
        log.presses.push({ tick, kind, step: i + 1 });
        rep.flags.push(`pressed ${kind} on tick ${tick}`);
        finish(tick, ctx);
        return inp;
      }

      // "at" on its own: the wait was the whole step.
      finish(tick, ctx);
    }
  };

  function tickOfDuration(v: TimeValue): number {
    return Math.max(0, time(v));
  }

  const bot: BotTake = {
    speed: take.speed,
    endMode: take.endMode,
    inputs(tick: number, ctx: BotContext): PlayerInput {
      vel.x = prev ? (ctx.self.x - prev.x) * LOCAL_HZ : 0;
      vel.y = prev ? (ctx.self.y - prev.y) * LOCAL_HZ : 0;
      vel.speed = Math.hypot(vel.x, vel.y);
      prev = { x: ctx.self.x, y: ctx.self.y };
      const raw = decide(tick, ctx);
      // Stored inputs are rounded to 1e-4 so the file stays small and exact in any JSON reader; the
      // controller is closed-loop, so the rounding is corrected on the next tick.
      const inp: PlayerInput = { ...raw, moveX: q4(raw.moveX), moveY: q4(raw.moveY), aim: qAngle(raw.aim) };
      const pressed = inp.light || inp.heavy || inp.dodge || inp.ranged || inp.interact || inp.ability;
      const k = Math.hypot(inp.moveX, inp.moveY);
      if (!pressed && lastMove && k > 0.999 && lastMove.k > 0.999) {
        const turn = Math.abs(Math.atan2(inp.moveY, inp.moveX) - Math.atan2(lastMove.y, lastMove.x));
        if (Math.min(turn, 2 * Math.PI - turn) < HEADING_DEADBAND) {
          inp.moveX = lastMove.x;
          inp.moveY = lastMove.y;
          inp.aim = qAngle(Math.atan2(lastMove.y, lastMove.x));
        }
      }
      lastMove = k > 1e-9 ? { x: inp.moveX, y: inp.moveY, k } : null;
      log.inputs.push(inp);
      return inp;
    },
  };
  return { bot, log };
}

/** An open-loop bot take that replays a stored input stream (idle once the stream runs out). */
export function replayTake(take: Pick<SolutionTake, 'speed' | 'endMode'>, inputs: readonly PlayerInput[]): BotTake {
  return {
    speed: take.speed,
    endMode: take.endMode,
    inputs: (tick: number) => inputs[tick] ?? idleInput(inputs.length ? inputs[inputs.length - 1].aim : 0),
  };
}
