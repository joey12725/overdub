/**
 * Traps and automated machinery (docs/TRAPS.md): spikes, crushers, conveyors, flame jets, dart
 * launchers, bumpers, beam sensors, relays and magnets.
 *
 * Traps are deterministic machines driven by SignalExpr. They are indifferent to who triggers them:
 * the same rule kills a self and damages an enemy. Nothing here targets, randomises or remembers
 * anything across runs.
 *
 * WHERE THEY RUN IN A SUBSTEP (sim.ts SUBSTEP ORDER; `now = s + 1` is the instant being produced):
 *
 *   3b. traps.sense   sensors (entity order), then relays (entity order). Their signals are written
 *                     before mechanisms run, so a door reads a sensor of the SAME substep.
 *   4.  mechanisms    (unchanged)
 *   4b. traps.step    first: push living enemies out of any crusher that turned solid on the
 *                     previous substep; then every other trap in ENTITY ORDER:
 *                       spikes   raise/drop, contact hits
 *                       crusher  stroke (solid + lethal), hold, retract
 *                       conveyor carry enemies and floor-height projectiles
 *                       flame    measure reach, contact hits
 *                       dart     spawn on the beat grid
 *                       bumper   fire on the rising edge
 *                       magnet   pull enemies
 *                     Each trap writes its `id` signal as it goes, so a trap later in entity order
 *                     reads it the same substep; mechanisms and earlier traps read it on the next.
 *   5–9               (unchanged) — trap hits are queued on w.combat and applied in phase 7 together
 *                     with every other hit of the substep.
 *
 * THE LIVE SELF. Belts and bumpers physically move the live self (alive or recording ghost, synced).
 * That happens once per LOCAL tick, in Sim.stepLocalTick before the PlayerController runs
 * (`liveCarry`), by the amount the world moves in that tick, so the displacement is recorded on the
 * tape as ordinary movement. Playback selves are never displaced (PLAY-01, MOM-06).
 *
 * TELEGRAPH. `warn` (0..1) is presentation only. While a hazard is off, the system looks for the
 * first instant on the sixteenth grid within TRAP_WARN_BEATS at which its expression will be true,
 * holding every signal at its current value except relay outputs, which are forecast from their
 * armed / running state. The forecast never changes the simulation.
 *
 * A level with no trap entities constructs an empty system: every entry point returns immediately
 * and the run is bit-for-bit what it was before traps existed.
 */
import type { SelfActor } from '../actors';
import { applyKnockback } from '../enemies/common';
import { hoverMove, hoverSolidAt } from '../enemies/drone';
import { getEnemyBehaviour } from '../enemies/registry';
import type { EnemyState } from '../enemies/types';
import type { Grid } from '../grid';
import { evalSignal, type SignalTable } from '../signals';
import type { World } from '../sim';
import { BASE } from '../tuning';
import {
  SUB_HZ,
  type BumperDef,
  type ConveyorDef,
  type CrusherDef,
  type DartDef,
  type Dir4,
  type FlameDef,
  type LevelDef,
  type MagnetDef,
  type MechSnap,
  type RelayDef,
  type SensorDef,
  type SignalExpr,
  type SpikesDef,
  type TileRef,
  type Vec2,
} from '../types';
import { spawnDart } from './dart';
import {
  BUMPER_FLIGHT_SUBS,
  BUMPER_POWER,
  BUMPER_PULSE_SUBS,
  CONVEYOR_SPEED,
  CRUSHER_DAMAGE,
  CRUSHER_RETRACT_SUBS,
  DART_EVERY,
  DART_FLASH_SUBS,
  DART_OFFSET,
  DART_RADIUS,
  DART_SPEED,
  FLAME_DAMAGE,
  HAZARD_RETICK_BEATS,
  HAZARD_STAGGER,
  MAGNET_HOLD_RADIUS,
  MAGNET_PULL,
  RELAY_DELAY,
  RELAY_HOLD,
  RELAY_QUANTIZE,
  SPIKES_DAMAGE,
  TRAP_EVENT,
  TRAP_WARN_BEATS,
  TRAP_WARN_GRID_PER_BEAT,
  TRAP_WARN_REFRESH_PER_BEAT,
} from './tuning';

// ───────────────────────────── geometry helpers ─────────────────────────────

const DIR_VEC: Readonly<Record<Dir4, Vec2>> = {
  n: { x: 0, y: -1 },
  e: { x: 1, y: 0 },
  s: { x: 0, y: 1 },
  w: { x: -1, y: 0 },
};

const DIR_ANGLE: Readonly<Record<Dir4, number>> = {
  n: -Math.PI / 2,
  e: 0,
  s: Math.PI / 2,
  w: Math.PI,
};

/** Unit vector of a Dir4. */
export function dirVec(dir: Dir4): Vec2 {
  return DIR_VEC[dir];
}

/** Angle in radians (atan2(y, x)) of a Dir4. */
export function dirAngle(dir: Dir4): number {
  return DIR_ANGLE[dir];
}

function pointSegDist(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
  const vx = bx - ax;
  const vy = by - ay;
  const l2 = vx * vx + vy * vy;
  let t = l2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / l2 : 0;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  return Math.hypot(ax + vx * t - px, ay + vy * t - py);
}

function centroid(cells: readonly TileRef[]): Vec2 {
  let x = 0;
  let y = 0;
  for (const c of cells) {
    x += c.c + 0.5;
    y += c.r + 0.5;
  }
  const n = Math.max(1, cells.length);
  return { x: x / n, y: y / n };
}

// ───────────────────────────── state ─────────────────────────────

/** Telegraph forecast of one hazard. */
interface Telegraph {
  /** Instant (`now` units) the hazard is forecast to activate, or -1. */
  onAt: number;
  /** 0..1 as of the last update. */
  warn: number;
}

interface SpikesState {
  kind: 'spikes';
  def: SpikesDef;
  cells: Set<number>;
  at: Vec2;
  up: boolean;
  /** Enemy id → substep of its next hit while contact is unbroken. */
  contact: Map<string, number>;
  tele: Telegraph;
}

interface CrusherState {
  kind: 'crusher';
  def: CrusherDef;
  cells: Set<number>;
  at: Vec2;
  phase: 'open' | 'extended' | 'retracting';
  /** Substeps of retract left. */
  k: number;
  tele: Telegraph;
}

interface ConveyorState {
  kind: 'conveyor';
  def: ConveyorDef;
  cells: Set<number>;
  at: Vec2;
  running: boolean;
  reversed: boolean;
}

interface FlameState {
  kind: 'flame';
  def: FlameDef;
  at: Vec2;
  on: boolean;
  /** Tiles currently covered (after cutting at the first shot-blocking tile). */
  reach: number;
  contact: Map<string, number>;
  tele: Telegraph;
}

interface DartState {
  kind: 'dart';
  def: DartDef;
  at: Vec2;
  enabled: boolean;
  /** Grid period and offset in substeps. */
  per: number;
  off: number;
  lastFire: number;
}

interface BumperState {
  kind: 'bumper';
  def: BumperDef;
  at: Vec2;
  /** fireWhen as of the previous substep (rising-edge detector). */
  prev: boolean;
  /** Substep the plate last fired, or -1. */
  firedAt: number;
  pulse: boolean;
}

interface SensorState {
  kind: 'sensor';
  def: SensorDef;
  at: Vec2;
  on: boolean;
  /** Live beam length in tiles (cut at the first shot-blocking tile). */
  reach: number;
}

interface RelayState {
  kind: 'relay';
  def: RelayDef;
  at: Vec2;
  prev: boolean;
  out: boolean;
  armed: boolean;
  /** Instant (`now` units) the trigger was accepted and the instant the relay fires. */
  armedAt: number;
  fireAt: number;
  /** Pulse mode: instant the output drops, or -1 when no pulse is running. */
  endAt: number;
}

interface MagnetState {
  kind: 'magnet';
  def: MagnetDef;
  at: Vec2;
  on: boolean;
}

type TrapState =
  | SpikesState
  | CrusherState
  | ConveyorState
  | FlameState
  | DartState
  | BumperState
  | SensorState
  | RelayState
  | MagnetState;

const TRAP_KINDS: ReadonlySet<string> = new Set(['spikes', 'crusher', 'conveyor', 'flame', 'dart', 'bumper', 'sensor', 'relay', 'magnet']);

/** True for an entity kind simulated by this module. */
export function isTrapKind(kind: string): boolean {
  return TRAP_KINDS.has(kind);
}

/**
 * The signal table as it is forecast to be at a future instant: every signal holds its current
 * value except relay outputs, which follow their armed / pulse schedule. Telegraph only.
 */
class FutureSignals {
  at = 0;
  constructor(
    private readonly base: SignalTable,
    private readonly relays: ReadonlyMap<string, RelayState>,
  ) {}

  get(id: string): boolean | undefined {
    const r = this.relays.get(id);
    if (!r) return this.base.get(id);
    let out = r.out;
    if (r.armed && r.fireAt <= this.at) {
      const mode = r.def.mode ?? 'pulse';
      if (mode === 'toggle') out = !out;
      else if (mode === 'latch') out = true;
      else out = this.at < r.fireAt + holdSubsOf(r, this.spb);
    } else if (r.endAt >= 0 && r.endAt <= this.at) {
      out = false;
    }
    return out;
  }

  spb = 1;
}

function holdSubsOf(r: RelayState, spb: number): number {
  return Math.max(1, Math.round((r.def.hold ?? RELAY_HOLD) * spb));
}

// ───────────────────────────── the system ─────────────────────────────

export class Traps {
  /** Number of trap entities in the level. 0 = the whole system is inert. */
  readonly count: number;
  /** Every trap, in entity order (= snapshot order). */
  private readonly order: TrapState[] = [];
  private readonly sensors: SensorState[] = [];
  private readonly relays: RelayState[] = [];
  private readonly conveyors: ConveyorState[] = [];
  /** Tile index → crusher id (for player-readable desync causes). */
  private readonly crusherCell = new Map<number, string>();
  private readonly future: FutureSignals;
  /** A crusher turned solid last substep: enemies left inside solid geometry must be pushed out. */
  private needsClear = false;
  /** Enemy id → substep it was last belt-carried (a body is carried by one belt per substep). */
  private readonly carriedAt = new Map<string, number>();
  /** Remaining bumper launch of the live self: per-substep displacement and substeps left. */
  private launchDx = 0;
  private launchDy = 0;
  private launchSubs = 0;

  constructor(
    level: LevelDef,
    private readonly grid: Grid,
    private readonly signals: Map<string, boolean>,
  ) {
    const relayById = new Map<string, RelayState>();
    const tele = (): Telegraph => ({ onAt: -1, warn: 0 });
    const cellSet = (cells: readonly TileRef[]): Set<number> => {
      const out = new Set<number>();
      for (const c of cells) if (grid.inBounds(c.c, c.r)) out.add(grid.index(c.c, c.r));
      return out;
    };
    for (const ent of level.entities) {
      switch (ent.kind) {
        case 'spikes':
          this.order.push({ kind: 'spikes', def: ent, cells: cellSet(ent.cells), at: centroid(ent.cells), up: false, contact: new Map(), tele: tele() });
          break;
        case 'crusher': {
          const cells = cellSet(ent.cells);
          for (const i of cells) this.crusherCell.set(i, ent.id);
          this.order.push({ kind: 'crusher', def: ent, cells, at: centroid(ent.cells), phase: 'open', k: 0, tele: tele() });
          break;
        }
        case 'conveyor': {
          const s: ConveyorState = { kind: 'conveyor', def: ent, cells: cellSet(ent.cells), at: centroid(ent.cells), running: false, reversed: false };
          this.order.push(s);
          this.conveyors.push(s);
          break;
        }
        case 'flame':
          this.order.push({ kind: 'flame', def: ent, at: { x: ent.c + 0.5, y: ent.r + 0.5 }, on: false, reach: 0, contact: new Map(), tele: tele() });
          break;
        case 'dart':
          this.order.push({ kind: 'dart', def: ent, at: { x: ent.c + 0.5, y: ent.r + 0.5 }, enabled: false, per: 1, off: 0, lastFire: -1 });
          break;
        case 'bumper':
          this.order.push({ kind: 'bumper', def: ent, at: { x: ent.c + 0.5, y: ent.r + 0.5 }, prev: false, firedAt: -1, pulse: false });
          break;
        case 'sensor': {
          const s: SensorState = { kind: 'sensor', def: ent, at: { x: (ent.from.x + ent.to.x) / 2, y: (ent.from.y + ent.to.y) / 2 }, on: false, reach: 0 };
          this.order.push(s);
          this.sensors.push(s);
          break;
        }
        case 'relay': {
          const s: RelayState = { kind: 'relay', def: ent, at: { x: ent.x ?? 0, y: ent.y ?? 0 }, prev: false, out: false, armed: false, armedAt: -1, fireAt: -1, endAt: -1 };
          this.order.push(s);
          this.relays.push(s);
          relayById.set(ent.id, s);
          break;
        }
        case 'magnet':
          this.order.push({ kind: 'magnet', def: ent, at: { x: ent.x, y: ent.y }, on: false });
          break;
        default:
          break;
      }
    }
    this.count = this.order.length;
    this.future = new FutureSignals(signals, relayById);
  }

  /**
   * State at beat zero. Idempotent: the sim calls it before AND after Mechanisms.init so that doors
   * see trap signals and traps see door signals in the initial state. Nothing strokes, fires or
   * launches at beat zero: a crusher whose expression starts true starts extended, harmlessly.
   */
  init(w: World): void {
    if (this.count === 0) return;
    const spb = w.spb;
    this.future.spb = spb;
    for (const t of this.sensors) {
      t.on = false;
      this.senseOne(w, t, true);
    }
    for (const t of this.order) {
      switch (t.kind) {
        case 'relay':
          t.out = false;
          t.armed = false;
          t.endAt = -1;
          t.prev = evalSignal(t.def.trigger, this.signals, 0);
          this.signals.set(t.def.id, false);
          this.signals.set(`${t.def.id}.armed`, false);
          break;
        case 'spikes':
          t.up = evalSignal(t.def.upWhen, this.signals, 0);
          this.signals.set(t.def.id, t.up);
          break;
        case 'crusher': {
          const ext = evalSignal(t.def.extendWhen, this.signals, 0);
          t.phase = ext ? 'extended' : 'open';
          t.k = 0;
          this.setSolid(t, ext);
          this.signals.set(t.def.id, ext);
          break;
        }
        case 'conveyor':
          t.running = t.def.runWhen ? evalSignal(t.def.runWhen, this.signals, 0) : true;
          t.reversed = t.def.reverseWhen ? evalSignal(t.def.reverseWhen, this.signals, 0) : false;
          this.signals.set(t.def.id, t.running);
          this.signals.set(`${t.def.id}.rev`, t.reversed);
          break;
        case 'flame':
          t.on = evalSignal(t.def.onWhen, this.signals, 0);
          t.reach = this.flameReach(t);
          this.signals.set(t.def.id, t.on);
          break;
        case 'dart':
          t.per = Math.max(1, Math.round((t.def.every ?? DART_EVERY) * spb));
          t.off = Math.round((t.def.offset ?? DART_OFFSET) * spb);
          t.enabled = t.def.enabledWhen ? evalSignal(t.def.enabledWhen, this.signals, 0) : true;
          this.signals.set(t.def.id, t.enabled);
          break;
        case 'bumper':
          t.prev = evalSignal(t.def.fireWhen, this.signals, 0);
          t.pulse = false;
          this.signals.set(t.def.id, false);
          break;
        case 'magnet':
          t.on = evalSignal(t.def.onWhen, this.signals, 0);
          this.signals.set(t.def.id, t.on);
          break;
        case 'sensor':
          break;
      }
    }
  }

  /** Name of the trap making a tile solid, if any ("crusher cr1"). */
  ownerAt(c: number, r: number): string | undefined {
    if (this.count === 0 || !this.grid.inBounds(c, r)) return undefined;
    const id = this.crusherCell.get(this.grid.index(c, r));
    return id === undefined ? undefined : `crusher ${id}`;
  }

  // ───────────────────────────── phase 3b: signal sources ─────────────────────────────

  sense(w: World): void {
    if (this.count === 0) return;
    for (const t of this.sensors) this.senseOne(w, t, false);
    for (const t of this.relays) this.stepRelay(w, t);
  }

  private senseOne(w: World, t: SensorState, initial: boolean): void {
    const { from, to } = t.def;
    const len = Math.hypot(to.x - from.x, to.y - from.y);
    let reach = len;
    if (len > 0) {
      const hit = this.grid.raycast(from.x, from.y, to.x - from.x, to.y - from.y, len, true);
      if (hit.hit) reach = hit.dist;
    }
    t.reach = reach;
    if (t.on && t.def.latch) return;
    const k = len > 0 ? reach / len : 0;
    const ex = from.x + (to.x - from.x) * k;
    const ey = from.y + (to.y - from.y) * k;
    const detects = t.def.detects ?? 'any';
    let on = false;
    if (detects !== 'enemies') {
      for (const s of w.selves) {
        if (!s.canAct) continue;
        if (pointSegDist(s.pose.x, s.pose.y, from.x, from.y, ex, ey) < BASE.actorRadius) {
          on = true;
          break;
        }
      }
    }
    if (!on && detects !== 'selves') {
      for (const e of w.enemies) {
        if (!e.alive) continue;
        if (pointSegDist(e.x, e.y, from.x, from.y, ex, ey) < e.stats.radius) {
          on = true;
          break;
        }
      }
    }
    if (initial) {
      t.on = on;
      this.signals.set(t.def.id, on);
      return;
    }
    if (on !== t.on) {
      t.on = on;
      this.signals.set(t.def.id, on);
      w.emit({ type: TRAP_EVENT, x: t.at.x, y: t.at.y, id: t.def.id, detail: on ? 'sensor:on' : 'sensor:off' });
    }
  }

  private stepRelay(w: World, t: RelayState): void {
    const now = w.now;
    const mode = t.def.mode ?? 'pulse';
    const trig = evalSignal(t.def.trigger, this.signals, w.beat);
    const rising = trig && !t.prev;
    t.prev = trig;
    // A running pulse ends first, so a pulse of exactly one period can be re-armed back to back.
    if (t.endAt >= 0 && now >= t.endAt) {
      t.endAt = -1;
      this.setRelayOut(w, t, false);
    }
    if (rising && !t.armed && t.endAt < 0 && !(mode === 'latch' && t.out)) {
      const q = Math.round((t.def.quantize ?? RELAY_QUANTIZE) * w.spb);
      const base = q > 0 ? Math.ceil(now / q) * q : now;
      t.armed = true;
      t.armedAt = now;
      t.fireAt = base + Math.max(0, Math.round((t.def.delay ?? RELAY_DELAY) * w.spb));
      this.signals.set(`${t.def.id}.armed`, true);
      w.emit({ type: TRAP_EVENT, x: t.at.x, y: t.at.y, id: t.def.id, detail: 'relay:armed', power: (t.fireAt - now) / w.spb });
    }
    if (t.armed && now >= t.fireAt) {
      t.armed = false;
      this.signals.set(`${t.def.id}.armed`, false);
      if (mode === 'toggle') {
        this.setRelayOut(w, t, !t.out);
      } else if (mode === 'latch') {
        this.setRelayOut(w, t, true);
      } else {
        t.endAt = t.fireAt + holdSubsOf(t, w.spb);
        this.setRelayOut(w, t, true);
      }
    }
  }

  private setRelayOut(w: World, t: RelayState, out: boolean): void {
    if (t.out === out) return;
    t.out = out;
    this.signals.set(t.def.id, out);
    w.emit({ type: TRAP_EVENT, x: t.at.x, y: t.at.y, id: t.def.id, detail: out ? 'relay:on' : 'relay:off' });
  }

  // ───────────────────────────── phase 4b: machines ─────────────────────────────

  step(w: World): void {
    if (this.count === 0) return;
    if (this.needsClear) {
      this.needsClear = false;
      this.clearEnemies(w);
    }
    for (const t of this.order) {
      switch (t.kind) {
        case 'spikes':
          this.stepSpikes(w, t);
          break;
        case 'crusher':
          this.stepCrusher(w, t);
          break;
        case 'conveyor':
          this.stepConveyor(w, t);
          break;
        case 'flame':
          this.stepFlame(w, t);
          break;
        case 'dart':
          this.stepDart(w, t);
          break;
        case 'bumper':
          this.stepBumper(w, t);
          break;
        case 'magnet':
          this.stepMagnet(w, t);
          break;
        case 'sensor':
        case 'relay':
          break;
      }
    }
  }

  private emit(w: World, t: TrapState, what: string, extra?: { dir?: number; power?: number }): void {
    w.emit({ type: TRAP_EVENT, x: t.at.x, y: t.at.y, id: t.def.id, detail: `${t.kind}:${what}`, dir: extra?.dir, power: extra?.power });
  }

  /**
   * Telegraph forecast for a hazard that is currently off (see file header). Emits '<kind>:warn'
   * once when an activation first comes into view.
   */
  private telegraph(w: World, t: SpikesState | CrusherState | FlameState, expr: SignalExpr, active: boolean): void {
    const tele = t.tele;
    if (active) {
      tele.onAt = -1;
      tele.warn = 0;
      return;
    }
    const now = w.now;
    const spb = w.spb;
    const span = Math.round(TRAP_WARN_BEATS * spb);
    const refresh = Math.max(1, Math.round(spb / TRAP_WARN_REFRESH_PER_BEAT));
    if (tele.onAt <= now || now % refresh === 0) {
      const had = tele.onAt > now;
      const g = Math.max(1, Math.round(spb / TRAP_WARN_GRID_PER_BEAT));
      let found = -1;
      const fut = this.future;
      // Nothing is forecast past the end of the encounter: no activation follows the horizon.
      const until = Math.min(now + span, w.horizonSubs);
      for (let at = (Math.floor(now / g) + 1) * g; at <= until; at += g) {
        fut.at = at;
        if (evalSignal(expr, fut as unknown as SignalTable, at / spb)) {
          found = at;
          break;
        }
      }
      tele.onAt = found;
      if (found >= 0 && !had) this.emit(w, t, 'warn', { power: (found - now) / spb });
    }
    tele.warn = tele.onAt > now ? Math.max(0, Math.min(1, 1 - (tele.onAt - now) / span)) : 0;
  }

  /** One hazard contact test for an enemy: hit on first contact, then once per full beat of contact. */
  private hazardTouch(w: World, t: SpikesState | FlameState, e: EnemyState, touching: boolean, damage: number, cause: string): void {
    const next = t.contact.get(e.id);
    if (!touching) {
      if (next !== undefined) t.contact.delete(e.id);
      return;
    }
    const s = w.s;
    if (next !== undefined && s < next) return;
    const retick = Math.max(1, Math.round(HAZARD_RETICK_BEATS * w.spb));
    t.contact.set(e.id, next === undefined ? s + retick : next + retick);
    w.combat.strikeEnemy(e, {
      source: { env: cause },
      kind: t.kind,
      momentum: 1,
      dir: 0,
      x: e.x,
      y: e.y,
      damage,
      knockback: 0,
      stagger: HAZARD_STAGGER,
    });
  }

  private tileIndexAt(x: number, y: number): number {
    const c = Math.floor(x);
    const r = Math.floor(y);
    return this.grid.inBounds(c, r) ? this.grid.index(c, r) : -1;
  }

  // ── spikes ──

  private stepSpikes(w: World, t: SpikesState): void {
    const up = evalSignal(t.def.upWhen, this.signals, w.beat);
    if (up !== t.up) {
      t.up = up;
      this.signals.set(t.def.id, up);
      this.emit(w, t, up ? 'up' : 'down');
      if (!up) t.contact.clear();
    }
    this.telegraph(w, t, t.def.upWhen, up);
    if (!up) return;
    const cause = `spikes ${t.def.id}`;
    for (const s of w.selves) {
      if (!s.vulnerable) continue;
      if (t.cells.has(this.tileIndexAt(s.pose.x, s.pose.y))) {
        w.combat.hitSelf({ self: s, cause: `skewered by ${cause}`, x: s.pose.x, y: s.pose.y, dir: 0 });
      }
    }
    const damage = t.def.damage ?? SPIKES_DAMAGE;
    for (const e of w.enemies) {
      if (!e.alive) continue;
      const touching = !getEnemyBehaviour(e.type).hovering && t.cells.has(this.tileIndexAt(e.x, e.y));
      this.hazardTouch(w, t, e, touching, damage, cause);
    }
  }

  // ── crusher ──

  private setSolid(t: CrusherState, solid: boolean): void {
    for (const c of t.def.cells) this.grid.setDynamicSolid(c.c, c.r, solid);
  }

  private stepCrusher(w: World, t: CrusherState): void {
    const want = evalSignal(t.def.extendWhen, this.signals, w.beat);
    if (t.phase === 'open') {
      if (want) this.stroke(w, t);
    } else if (t.phase === 'extended') {
      if (!want) {
        t.phase = 'retracting';
        t.k = CRUSHER_RETRACT_SUBS;
        this.emit(w, t, 'retract');
      }
    } else if (want) {
      // Re-extends without a stroke: the tiles never opened, so nothing can be under the head.
      t.phase = 'extended';
      t.k = 0;
      this.emit(w, t, 'hold');
    } else if (--t.k <= 0) {
      t.k = 0;
      t.phase = 'open';
      this.setSolid(t, false);
      this.signals.set(t.def.id, false);
      this.emit(w, t, 'open');
    }
    this.telegraph(w, t, t.def.extendWhen, t.phase !== 'open');
  }

  private stroke(w: World, t: CrusherState): void {
    t.phase = 'extended';
    t.k = 0;
    const cause = `crusher ${t.def.id}`;
    let struck = 0;
    for (const s of w.selves) {
      if (!s.vulnerable) continue;
      if (t.cells.has(this.tileIndexAt(s.pose.x, s.pose.y))) {
        struck++;
        w.combat.hitSelf({ self: s, cause: `crushed by ${cause}`, x: s.pose.x, y: s.pose.y, dir: 0 });
      }
    }
    const damage = t.def.damage ?? CRUSHER_DAMAGE;
    for (const e of w.enemies) {
      if (!e.alive || !t.cells.has(this.tileIndexAt(e.x, e.y))) continue;
      struck++;
      w.combat.strikeEnemy(e, {
        source: { env: cause },
        kind: 'crusher',
        momentum: damage,
        dir: 0,
        x: e.x,
        y: e.y,
        damage,
        knockback: 0,
        stagger: HAZARD_STAGGER,
      });
    }
    this.setSolid(t, true);
    this.signals.set(t.def.id, true);
    this.needsClear = true;
    this.emit(w, t, 'slam', { power: struck });
  }

  /** Push living enemies out of solid geometry (never delete a body); same rule as a closing door. */
  private clearEnemies(w: World): void {
    for (const e of w.enemies) {
      if (!e.alive) continue;
      const hovering = getEnemyBehaviour(e.type).hovering === true;
      const solid = hovering ? hoverSolidAt(this.grid, e.x, e.y, e.stats.radius) : this.grid.isSolidAt(e.x, e.y, e.stats.radius);
      if (!solid) continue;
      const res = this.grid.moveCircle(e.x, e.y, 0, 0, e.stats.radius);
      e.x = res.x;
      e.y = res.y;
      e.path = [];
      e.pathIdx = 0;
    }
  }

  // ── conveyor ──

  private stepConveyor(w: World, t: ConveyorState): void {
    const beat = w.beat;
    const running = t.def.runWhen ? evalSignal(t.def.runWhen, this.signals, beat) : true;
    const reversed = t.def.reverseWhen ? evalSignal(t.def.reverseWhen, this.signals, beat) : false;
    if (running !== t.running) {
      t.running = running;
      this.signals.set(t.def.id, running);
      this.emit(w, t, running ? 'on' : 'off', { dir: beltAngle(t) });
    }
    if (reversed !== t.reversed) {
      t.reversed = reversed;
      this.signals.set(`${t.def.id}.rev`, reversed);
      this.emit(w, t, reversed ? 'reverse' : 'forward', { dir: beltAngle(t) });
    }
    if (!running) return;
    const v = DIR_VEC[t.def.dir];
    const d = ((t.def.speed ?? CONVEYOR_SPEED) / SUB_HZ) * (reversed ? -1 : 1);
    const dx = v.x * d;
    const dy = v.y * d;
    const s = w.s;
    for (const e of w.enemies) {
      if (!e.alive || !groundedMovable(e)) continue;
      if (this.carriedAt.get(e.id) === s) continue;
      if (!t.cells.has(this.tileIndexAt(e.x, e.y))) continue;
      this.carriedAt.set(e.id, s);
      const res = this.grid.moveCircle(e.x, e.y, dx, dy, e.stats.radius);
      e.x = res.x;
      e.y = res.y;
    }
    for (const p of w.projectiles.list) {
      if (!p.alive || p.z > 0) continue;
      if (!t.cells.has(this.tileIndexAt(p.x, p.y))) continue;
      const nx = p.x + dx;
      const ny = p.y + dy;
      if (!p.passesWalls && this.grid.blocksShot(Math.floor(nx), Math.floor(ny))) continue;
      p.x = nx;
      p.y = ny;
    }
  }

  // ── flame ──

  private flameReach(t: FlameState): number {
    const v = DIR_VEC[t.def.dir];
    const range = Math.max(0, Math.floor(t.def.range));
    let n = 0;
    for (let k = 1; k <= range; k++) {
      if (this.grid.blocksShot(t.def.c + v.x * k, t.def.r + v.y * k)) break;
      n = k;
    }
    return n;
  }

  /** Is world point (x, y) on one of the first `reach` tiles of the jet? */
  private inFlame(t: FlameState, x: number, y: number): boolean {
    const v = DIR_VEC[t.def.dir];
    const dc = Math.floor(x) - t.def.c;
    const dr = Math.floor(y) - t.def.r;
    const k = dc * v.x + dr * v.y;
    return k >= 1 && k <= t.reach && dc === v.x * k && dr === v.y * k;
  }

  private stepFlame(w: World, t: FlameState): void {
    const on = evalSignal(t.def.onWhen, this.signals, w.beat);
    t.reach = this.flameReach(t);
    if (on !== t.on) {
      t.on = on;
      this.signals.set(t.def.id, on);
      this.emit(w, t, on ? 'on' : 'off', { dir: DIR_ANGLE[t.def.dir], power: t.reach });
      if (!on) t.contact.clear();
    }
    this.telegraph(w, t, t.def.onWhen, on);
    if (!on) return;
    const cause = `flame jet ${t.def.id}`;
    for (const s of w.selves) {
      if (!s.vulnerable) continue;
      if (this.inFlame(t, s.pose.x, s.pose.y)) {
        w.combat.hitSelf({ self: s, cause: `burned by ${cause}`, x: s.pose.x, y: s.pose.y, dir: DIR_ANGLE[t.def.dir] });
      }
    }
    const damage = t.def.damage ?? FLAME_DAMAGE;
    for (const e of w.enemies) {
      if (!e.alive) continue;
      this.hazardTouch(w, t, e, this.inFlame(t, e.x, e.y), damage, cause);
    }
  }

  // ── dart launcher ──

  private stepDart(w: World, t: DartState): void {
    const enabled = t.def.enabledWhen ? evalSignal(t.def.enabledWhen, this.signals, w.beat) : true;
    if (enabled !== t.enabled) {
      t.enabled = enabled;
      this.signals.set(t.def.id, enabled);
      this.emit(w, t, enabled ? 'on' : 'off');
    }
    const s = w.s;
    if (!enabled || s < t.off || (s - t.off) % t.per !== 0) return;
    const v = DIR_VEC[t.def.dir];
    // A muzzle sealed by a door or an extended crusher fires nothing.
    if (this.grid.blocksShot(t.def.c + v.x, t.def.r + v.y)) return;
    const lead = 0.5 + DART_RADIUS + 0.01;
    const dir = DIR_ANGLE[t.def.dir];
    spawnDart(w, t.def.id, t.at.x + v.x * lead, t.at.y + v.y * lead, dir, t.def.speed ?? DART_SPEED);
    t.lastFire = s;
    this.emit(w, t, 'fire', { dir });
  }

  // ── bumper ──

  private stepBumper(w: World, t: BumperState): void {
    const s = w.s;
    if (t.pulse && s >= t.firedAt + BUMPER_PULSE_SUBS) {
      t.pulse = false;
      this.signals.set(t.def.id, false);
    }
    const want = evalSignal(t.def.fireWhen, this.signals, w.beat);
    const rising = want && !t.prev;
    t.prev = want;
    if (!rising) return;
    const power = t.def.power ?? BUMPER_POWER;
    const dir = DIR_ANGLE[t.def.dir];
    const tile = this.grid.inBounds(t.def.c, t.def.r) ? this.grid.index(t.def.c, t.def.r) : -2;
    let launched = 0;
    for (const e of w.enemies) {
      if (!e.alive || !groundedMovable(e)) continue;
      if (this.tileIndexAt(e.x, e.y) !== tile) continue;
      applyKnockback(w, e, dir, power / e.stats.mass);
      launched++;
    }
    const live = liveBody(w);
    if (live && this.tileIndexAt(live.pose.x, live.pose.y) === tile) {
      const v = DIR_VEC[t.def.dir];
      this.launchDx = (v.x * power) / BUMPER_FLIGHT_SUBS;
      this.launchDy = (v.y * power) / BUMPER_FLIGHT_SUBS;
      this.launchSubs = BUMPER_FLIGHT_SUBS;
      launched++;
    }
    t.firedAt = s;
    t.pulse = true;
    this.signals.set(t.def.id, true);
    this.emit(w, t, 'fire', { dir, power: launched });
  }

  // ── magnet ──

  private stepMagnet(w: World, t: MagnetState): void {
    const on = evalSignal(t.def.onWhen, this.signals, w.beat);
    if (on !== t.on) {
      t.on = on;
      this.signals.set(t.def.id, on);
      this.emit(w, t, on ? 'on' : 'off');
    }
    if (!on) return;
    const pull = (t.def.pull ?? MAGNET_PULL) / SUB_HZ;
    for (const e of w.enemies) {
      if (!e.alive || !Number.isFinite(e.stats.mass) || !(e.stats.mass > 0)) continue;
      const dx = t.def.x - e.x;
      const dy = t.def.y - e.y;
      const d = Math.hypot(dx, dy);
      if (d > t.def.radius || d <= MAGNET_HOLD_RADIUS) continue;
      const step = Math.min(pull / e.stats.mass, d - MAGNET_HOLD_RADIUS);
      const mx = (dx / d) * step;
      const my = (dy / d) * step;
      if (getEnemyBehaviour(e.type).hovering) {
        hoverMove(w, e, mx, my);
      } else {
        const res = this.grid.moveCircle(e.x, e.y, mx, my, e.stats.radius);
        e.x = res.x;
        e.y = res.y;
      }
    }
  }

  // ───────────────────────────── the live self ─────────────────────────────

  /**
   * Belt carry and bumper launch of the live self for one local tick of `subs` master substeps.
   * `x`, `y` is the PlayerController's current position. Returns the displaced position, or null
   * when nothing moves it. Called by Sim.stepLocalTick before the controller steps.
   */
  liveCarry(w: World, x: number, y: number, subs: number): Vec2 | null {
    if (this.count === 0) return null;
    const live = liveBody(w);
    let dx = 0;
    let dy = 0;
    if (this.launchSubs > 0) {
      const n = Math.min(subs, this.launchSubs);
      this.launchSubs -= n;
      if (live) {
        dx += this.launchDx * n;
        dy += this.launchDy * n;
      }
    }
    if (!live) return null;
    const tile = this.tileIndexAt(x, y);
    for (const t of this.conveyors) {
      if (!t.running || !t.cells.has(tile)) continue;
      const v = DIR_VEC[t.def.dir];
      const d = ((t.def.speed ?? CONVEYOR_SPEED) / SUB_HZ) * subs * (t.reversed ? -1 : 1);
      dx += v.x * d;
      dy += v.y * d;
      break;
    }
    if (dx === 0 && dy === 0) return null;
    const res = this.grid.moveCircle(x, y, dx, dy, BASE.actorRadius);
    return { x: res.x, y: res.y };
  }

  // ───────────────────────────── snapshot ─────────────────────────────

  snapshot(sub: number): MechSnap[] {
    return this.order.map((t): MechSnap => {
      switch (t.kind) {
        case 'spikes':
          return { id: t.def.id, kind: 'spikes', on: t.up, t: t.up ? 1 : 0, warn: t.tele.warn };
        case 'crusher': {
          const snap: MechSnap = {
            id: t.def.id,
            kind: 'crusher',
            on: t.phase !== 'open',
            t: t.phase === 'extended' ? 1 : t.phase === 'retracting' ? t.k / CRUSHER_RETRACT_SUBS : 0,
            warn: t.tele.warn,
          };
          const dir = crusherDir(t.def);
          if (dir !== undefined) snap.dir = dir;
          return snap;
        }
        case 'conveyor':
          return { id: t.def.id, kind: 'conveyor', on: t.running, dir: beltAngle(t) };
        case 'flame':
          return { id: t.def.id, kind: 'flame', on: t.on, dir: DIR_ANGLE[t.def.dir], reach: t.reach, warn: t.tele.warn };
        case 'dart': {
          const phase = sub <= t.off ? 0 : ((sub - 1 - t.off) % t.per) / t.per;
          return {
            id: t.def.id,
            kind: 'dart',
            on: t.enabled,
            t: phase,
            dir: DIR_ANGLE[t.def.dir],
            firing: t.lastFire >= 0 && sub - 1 - t.lastFire < DART_FLASH_SUBS,
          };
        }
        case 'bumper': {
          const since = t.firedAt >= 0 ? sub - 1 - t.firedAt : Infinity;
          return {
            id: t.def.id,
            kind: 'bumper',
            on: t.pulse,
            t: since < BUMPER_PULSE_SUBS ? 1 - since / BUMPER_PULSE_SUBS : 0,
            dir: DIR_ANGLE[t.def.dir],
            firing: t.pulse,
          };
        }
        case 'sensor':
          return { id: t.def.id, kind: 'sensor', on: t.on, reach: t.reach };
        case 'relay': {
          const span = t.fireAt - t.armedAt;
          return {
            id: t.def.id,
            kind: 'relay',
            on: t.out,
            t: t.armed ? (span > 0 ? Math.max(0, Math.min(1, (sub - t.armedAt) / span)) : 1) : 0,
            warn: t.armed ? 1 : 0,
          };
        }
        case 'magnet':
          return { id: t.def.id, kind: 'magnet', on: t.on };
      }
    });
  }
}

/** A body belts and bumpers can move: on the floor and not bolted down. */
function groundedMovable(e: EnemyState): boolean {
  return !getEnemyBehaviour(e.type).hovering && Number.isFinite(e.stats.mass);
}

/** The live self while it has a physical body (alive or recording ghost, synced), if any. */
function liveBody(w: World): SelfActor | undefined {
  for (const s of w.selves) if (s.live) return s.canAct ? s : undefined;
  return undefined;
}

function beltAngle(t: ConveyorState): number {
  const a = DIR_ANGLE[t.def.dir];
  if (!t.reversed) return a;
  return a > 0 ? a - Math.PI : a + Math.PI;
}

function crusherDir(def: CrusherDef): number | undefined {
  if (def.dir) return DIR_ANGLE[def.dir];
  if (def.cells.length < 2) return undefined;
  const dc = def.cells[1].c - def.cells[0].c;
  const dr = def.cells[1].r - def.cells[0].r;
  if (dc === 0 && dr === 0) return undefined;
  return Math.atan2(dr, dc);
}
