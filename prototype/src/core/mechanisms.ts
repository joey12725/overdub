/**
 * Mechanisms: switches, pressure plates, doors, lasers, breakables, cores and exits, plus the signal
 * table that ties them together (LEVEL vocabulary, Scenarios B, C, H, K).
 *
 * Signals published (id → boolean), all readable by SignalExpr:
 *   switch id     — on/off (toggled by an 'interact' attempt in reach; PLAY-02)
 *   plate id      — an effective body stands on the tile this substep
 *   breakable id  — broken (latched)
 *   core id       — activated (latched)
 *   exit id       — an alive, synced self stands inside
 *   door id       — door is open (passable)
 *   laser id      — beam is on
 *
 * Mechanisms phase order (one substep): plates → exits → evaluate doors / lasers / wake conditions
 * against the updated table → door travel and grid solidity → laser contact.
 *
 * Doors travel for DOOR_TRAVEL_SUBS substeps and are solid while less than half open, which is
 * what drives the grid's dynamic overlay. A door that becomes solid never deletes a body inside
 * it: enemies are pushed to the nearest free side immediately; a playback self is desynced by the
 * obstruction test on the next substep (its projection continues); the live self is pushed out by
 * its own controller's collision on its next local tick.
 *
 * Only effective bodies operate anything: alive or recording-ghost selves that are synced, and
 * living enemies (GHOST-03/05, DESYNC-07). Dead playback ghosts never touch the world.
 */
import type { ActiveSwing, SelfActor } from './actors';
import { CORE_RADIUS, coreThreshold, inSwingVolume } from './combat';
import { hoverSolidAt } from './enemies/drone';
import { getEnemyBehaviour } from './enemies/registry';
import type { Grid } from './grid';
import { interactRadius } from './player';
import type { EnemyState } from './enemies/types';
import { evalSignal } from './signals';
import { BASE } from './tuning';
import type {
  BreakableDef,
  CoreDef,
  DoorDef,
  ExitDef,
  LaserDef,
  LevelDef,
  MechSnap,
  PlateDef,
  SwitchDef,
} from './types';
import type { World } from './sim';

/** Door open/close travel time, master substeps (0.15 master s). */
export const DOOR_TRAVEL_SUBS = 36;

interface DoorState {
  def: DoorDef;
  /** Travel progress in substeps, 0 (closed) … DOOR_TRAVEL_SUBS (open). */
  k: number;
  passable: boolean;
}

interface SwitchState {
  def: SwitchDef;
  on: boolean;
}

interface PlateState {
  def: PlateDef;
  on: boolean;
}

interface BreakableState {
  def: BreakableDef;
  broken: boolean;
}

interface LaserState {
  def: LaserDef;
  on: boolean;
}

interface CoreState {
  def: CoreDef;
  on: boolean;
}

interface ExitState {
  def: ExitDef;
  on: boolean;
}

type MechRef =
  | { kind: 'door'; s: DoorState }
  | { kind: 'switch'; s: SwitchState }
  | { kind: 'plate'; s: PlateState }
  | { kind: 'breakable'; s: BreakableState }
  | { kind: 'laser'; s: LaserState }
  | { kind: 'core'; s: CoreState }
  | { kind: 'exit'; s: ExitState };

/** Signal prefix of an enemy's death: `dead:<enemy id>` is true once that enemy died. */
export const DEAD_PREFIX = 'dead:';

export class Mechanisms {
  readonly doors: DoorState[] = [];
  readonly switches: SwitchState[] = [];
  readonly plates: PlateState[] = [];
  readonly breakables: BreakableState[] = [];
  readonly lasers: LaserState[] = [];
  readonly cores: CoreState[] = [];
  readonly exits: ExitState[] = [];
  /** Snapshot order = entity order. */
  private readonly order: MechRef[] = [];
  /** Tile index → id of the door / breakable occupying it (for player-readable desync causes). */
  private readonly cellOwner = new Map<number, string>();
  /** Enemies whose `dead:<id>` signal has been published. */
  private readonly deadPublished = new Set<EnemyState>();

  constructor(
    level: LevelDef,
    private readonly grid: Grid,
    private readonly signals: Map<string, boolean>,
  ) {
    for (const ent of level.entities) {
      switch (ent.kind) {
        case 'door': {
          const s: DoorState = { def: ent, k: 0, passable: false };
          this.doors.push(s);
          this.order.push({ kind: 'door', s });
          for (const c of ent.cells) this.cellOwner.set(grid.index(c.c, c.r), `door ${ent.id}`);
          break;
        }
        case 'switch': {
          const s: SwitchState = { def: ent, on: ent.initial === true };
          this.switches.push(s);
          this.order.push({ kind: 'switch', s });
          break;
        }
        case 'plate': {
          const s: PlateState = { def: ent, on: false };
          this.plates.push(s);
          this.order.push({ kind: 'plate', s });
          break;
        }
        case 'breakable': {
          const s: BreakableState = { def: ent, broken: false };
          this.breakables.push(s);
          this.order.push({ kind: 'breakable', s });
          this.cellOwner.set(grid.index(ent.c, ent.r), `breakable wall ${ent.id}`);
          break;
        }
        case 'laser': {
          const s: LaserState = { def: ent, on: false };
          this.lasers.push(s);
          this.order.push({ kind: 'laser', s });
          break;
        }
        case 'core': {
          const s: CoreState = { def: ent, on: false };
          this.cores.push(s);
          this.order.push({ kind: 'core', s });
          break;
        }
        case 'exit': {
          const s: ExitState = { def: ent, on: false };
          this.exits.push(s);
          this.order.push({ kind: 'exit', s });
          break;
        }
        default:
          break;
      }
    }
  }

  /** Initial state at beat zero: switches, breakables solid, doors settled (no travel at start). */
  init(w: World): void {
    for (const s of this.switches) this.signals.set(s.def.id, s.on);
    for (const p of this.plates) this.signals.set(p.def.id, false);
    for (const b of this.breakables) {
      this.signals.set(b.def.id, false);
      this.grid.setDynamicSolid(b.def.c, b.def.r, true);
    }
    for (const c of this.cores) this.signals.set(c.def.id, false);
    for (const x of this.exits) this.signals.set(x.def.id, false);
    for (const d of this.doors) {
      const open = evalSignal(d.def.openWhen, this.signals, 0);
      d.k = open ? DOOR_TRAVEL_SUBS : 0;
      d.passable = open;
      this.signals.set(d.def.id, open);
      for (const c of d.def.cells) this.grid.setDynamicSolid(c.c, c.r, !open);
    }
    for (const l of this.lasers) {
      l.on = evalSignal(l.def.onWhen, this.signals, 0);
      this.signals.set(l.def.id, l.on);
    }
    for (const e of w.enemies) if (!e.awake && e.def.wakeWhen && evalSignal(e.def.wakeWhen, this.signals, 0)) wake(e);
  }

  /** Name of the dynamic obstacle at a tile, if any ("door d1", "breakable wall w1"). */
  ownerAt(c: number, r: number): string | undefined {
    if (!this.grid.inBounds(c, r)) return undefined;
    return this.cellOwner.get(this.grid.index(c, r));
  }

  // ───────────────────────────── actions ─────────────────────────────

  /**
   * An 'interact' attempt by a self that can act: toggles the nearest switch within reach (ties by
   * entity order). Reverse passes toggle again (PLAY-06: on → off). Returns true if one toggled.
   */
  interact(w: World, self: SelfActor): boolean {
    const reach = interactRadius(w.loadout);
    let best: SwitchState | null = null;
    let bestD = Infinity;
    for (const s of this.switches) {
      const d = Math.hypot(s.def.x - self.pose.x, s.def.y - self.pose.y);
      if (d <= reach && d < bestD) {
        bestD = d;
        best = s;
      }
    }
    if (!best) {
      w.emit({ type: 'interactFail', x: self.pose.x, y: self.pose.y, tape: self.index, detail: 'nothing in reach' });
      return false;
    }
    best.on = !best.on;
    this.signals.set(best.def.id, best.on);
    w.emit({ type: 'interact', x: best.def.x, y: best.def.y, tape: self.index, id: best.def.id, detail: best.on ? 'on' : 'off' });
    return true;
  }

  /**
   * A live melee swing against breakables and cores (Scenario K). A breakable or core needs one
   * swing with momentum ≥ its threshold; a weaker swing 'clang's and is logged with the momentum it
   * had and needed, so the outcome can say which swing lacked momentum.
   */
  strikeObjects(w: World, self: SelfActor, sw: ActiveSwing, ox: number, oy: number, reach: number, arc: number): void {
    for (const b of this.breakables) {
      if (b.broken || sw.struck.has(b.def.id)) continue;
      if (!boxInSwing(this.grid, ox, oy, sw.dir, reach, arc, b.def.c, b.def.r)) continue;
      sw.struck.add(b.def.id);
      sw.connected = true;
      const cx = b.def.c + 0.5;
      const cy = b.def.r + 0.5;
      if (sw.momentum >= b.def.threshold) {
        b.broken = true;
        this.signals.set(b.def.id, true);
        this.grid.setDynamicSolid(b.def.c, b.def.r, false);
        w.emit({ type: 'hit', x: cx, y: cy, tape: self.index, id: b.def.id, power: sw.momentum, dir: sw.dir, detail: sw.kind });
        w.emit({ type: 'break', x: cx, y: cy, tape: self.index, id: b.def.id, power: sw.momentum, dir: sw.dir, detail: sw.kind });
      } else {
        w.emit({ type: 'clang', x: cx, y: cy, tape: self.index, id: b.def.id, power: sw.momentum, dir: sw.dir, detail: `needs ${b.def.threshold}` });
        w.log.weak(self.index, w.s, sw.kind, `breakable wall ${b.def.id}`, sw.momentum, b.def.threshold, 'too weak');
      }
    }
    for (const c of this.cores) {
      if (c.on || sw.struck.has(c.def.id)) continue;
      if (!inSwingVolume(ox, oy, sw.dir, reach, arc, c.def.x, c.def.y, CORE_RADIUS)) continue;
      if (this.grid.segmentBlocked(ox, oy, c.def.x, c.def.y, true)) continue;
      sw.struck.add(c.def.id);
      sw.connected = true;
      const need = coreThreshold(c.def.threshold);
      if (sw.momentum >= need) {
        c.on = true;
        this.signals.set(c.def.id, true);
        w.emit({ type: 'hit', x: c.def.x, y: c.def.y, tape: self.index, id: c.def.id, power: sw.momentum, dir: sw.dir, detail: sw.kind });
        w.emit({ type: 'core', x: c.def.x, y: c.def.y, tape: self.index, id: c.def.id, power: sw.momentum, detail: 'on' });
      } else {
        w.emit({ type: 'clang', x: c.def.x, y: c.def.y, tape: self.index, id: c.def.id, power: sw.momentum, dir: sw.dir, detail: `needs ${need}` });
        w.log.weak(self.index, w.s, sw.kind, `core ${c.def.id}`, sw.momentum, need, 'too weak');
      }
    }
  }

  // ───────────────────────────── per-substep update ─────────────────────────────

  step(w: World): void {
    const heavyStep = w.loadout.abilities.includes('heavyStep');
    for (const p of this.plates) {
      const on = this.plateOccupied(w, p.def, heavyStep);
      if (on !== p.on) {
        p.on = on;
        this.signals.set(p.def.id, on);
        w.emit({ type: 'plate', x: p.def.c + 0.5, y: p.def.r + 0.5, id: p.def.id, detail: on ? 'on' : 'off' });
      }
    }
    for (const x of this.exits) {
      let on = false;
      for (const s of w.selves) {
        if (s.life !== 'alive' || !s.synced) continue;
        const { x: px, y: py } = s.pose;
        if (px >= x.def.c && px < x.def.c + x.def.w && py >= x.def.r && py < x.def.r + x.def.h) {
          on = true;
          break;
        }
      }
      if (on !== x.on) {
        x.on = on;
        this.signals.set(x.def.id, on);
      }
    }

    // dead:<enemy id> (data/levels/README.md "Signal expressions"): true from the first update after
    // the enemy died. Published once per enemy; an id missing from the table reads as false.
    for (const e of w.enemies) {
      if (!e.alive && !this.deadPublished.has(e)) {
        this.deadPublished.add(e);
        this.signals.set(`${DEAD_PREFIX}${e.def.id}`, true);
      }
    }

    const beat = w.beat;
    for (const e of w.enemies) {
      if (e.alive && !e.awake && e.def.wakeWhen && evalSignal(e.def.wakeWhen, this.signals, beat)) wake(e, w.s);
    }
    for (const d of this.doors) {
      const want = evalSignal(d.def.openWhen, this.signals, beat);
      if (want && d.k < DOOR_TRAVEL_SUBS) d.k++;
      else if (!want && d.k > 0) d.k--;
      const passable = d.k * 2 >= DOOR_TRAVEL_SUBS;
      if (passable !== d.passable) {
        d.passable = passable;
        this.signals.set(d.def.id, passable);
        for (const c of d.def.cells) this.grid.setDynamicSolid(c.c, c.r, !passable);
        const cx = d.def.cells.reduce((a, c) => a + c.c + 0.5, 0) / Math.max(1, d.def.cells.length);
        const cy = d.def.cells.reduce((a, c) => a + c.r + 0.5, 0) / Math.max(1, d.def.cells.length);
        w.emit({ type: 'door', x: cx, y: cy, id: d.def.id, detail: passable ? 'open' : 'closed' });
        if (!passable) this.clearEnemiesFrom(w);
      }
    }
    for (const l of this.lasers) {
      const on = evalSignal(l.def.onWhen, this.signals, beat);
      if (on !== l.on) {
        l.on = on;
        this.signals.set(l.def.id, on);
        w.emit({ type: 'laser', x: (l.def.from.x + l.def.to.x) / 2, y: (l.def.from.y + l.def.to.y) / 2, id: l.def.id, detail: on ? 'on' : 'off' });
      }
      if (!on) continue;
      for (const s of w.selves) {
        if (!s.vulnerable) continue;
        if (pointSegDist(s.pose.x, s.pose.y, l.def.from.x, l.def.from.y, l.def.to.x, l.def.to.y) < BASE.actorRadius) {
          w.combat.hitSelf({ self: s, cause: `burned by laser ${l.def.id}`, x: s.pose.x, y: s.pose.y, dir: 0, laser: true });
        }
      }
    }
  }

  private plateOccupied(w: World, def: PlateDef, heavyStep: boolean): boolean {
    if (!def.heavy || heavyStep) {
      for (const s of w.selves) {
        if (!s.canAct) continue;
        if (Math.floor(s.pose.x) === def.c && Math.floor(s.pose.y) === def.r) return true;
      }
    }
    for (const e of w.enemies) {
      if (!e.alive) continue;
      const beh = getEnemyBehaviour(e.type);
      if (beh.hovering) continue;
      if (def.heavy && !beh.heavyBody) continue;
      if (Math.floor(e.x) === def.c && Math.floor(e.y) === def.r) return true;
    }
    return false;
  }

  /** Push living enemies out of anything that just became solid (never delete a body). */
  private clearEnemiesFrom(w: World): void {
    for (const e of w.enemies) {
      if (!e.alive) continue;
      const solid = getEnemyBehaviour(e.type).hovering ? hoverSolidAt(this.grid, e.x, e.y, e.stats.radius) : this.grid.isSolidAt(e.x, e.y, e.stats.radius);
      if (!solid) continue;
      const res = this.grid.moveCircle(e.x, e.y, 0, 0, e.stats.radius);
      e.x = res.x;
      e.y = res.y;
      e.path = [];
      e.pathIdx = 0;
    }
  }

  snapshot(): MechSnap[] {
    return this.order.map((m): MechSnap => {
      switch (m.kind) {
        case 'door':
          return { id: m.s.def.id, kind: 'door', on: m.s.passable, t: m.s.k / DOOR_TRAVEL_SUBS };
        case 'switch':
          return { id: m.s.def.id, kind: 'switch', on: m.s.on };
        case 'plate':
          return { id: m.s.def.id, kind: 'plate', on: m.s.on };
        case 'breakable':
          return { id: m.s.def.id, kind: 'breakable', on: m.s.broken };
        case 'laser':
          return { id: m.s.def.id, kind: 'laser', on: m.s.on };
        case 'core':
          return { id: m.s.def.id, kind: 'core', on: m.s.on };
        case 'exit':
          return { id: m.s.def.id, kind: 'exit', on: m.s.on };
      }
    });
  }
}

function wake(e: { awake: boolean; state: string; stateStart: number; stateEnd: number }, sub = 0): void {
  e.awake = true;
  e.state = 'idle';
  e.stateStart = sub;
  e.stateEnd = sub;
}

function pointSegDist(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
  const vx = bx - ax;
  const vy = by - ay;
  const l2 = vx * vx + vy * vy;
  let t = l2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / l2 : 0;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  return Math.hypot(ax + vx * t - px, ay + vy * t - py);
}

/**
 * Is tile box (c, r) inside a swing volume? The nearest point of the box must be within reach and
 * either it or the box centre must lie inside the arc; the line to the face must not pass another
 * wall first.
 */
function boxInSwing(grid: Grid, ox: number, oy: number, dir: number, reach: number, arc: number, c: number, r: number): boolean {
  const qx = ox < c ? c : ox > c + 1 ? c + 1 : ox;
  const qy = oy < r ? r : oy > r + 1 ? r + 1 : oy;
  const dx = qx - ox;
  const dy = qy - oy;
  const d = Math.hypot(dx, dy);
  if (d > reach) return false;
  if (d > 1e-9) {
    const half = arc / 2;
    const inArc = (x: number, y: number): boolean => {
      const a = Math.atan2(y - oy, x - ox) - dir;
      const w = Math.atan2(Math.sin(a), Math.cos(a));
      return Math.abs(w) <= half;
    };
    if (!inArc(qx, qy) && !inArc(c + 0.5, r + 0.5)) return false;
    // Probe a point just short of the face so the breakable itself does not count as the blocker.
    const k = Math.max(0, d - 0.02) / d;
    if (grid.segmentBlocked(ox, oy, ox + dx * k, oy + dy * k, true)) return false;
  }
  return true;
}
