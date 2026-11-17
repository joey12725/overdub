/**
 * The encounter simulation kernel (ARCHITECTURE "One clock", "What a tape is", "Life, ghosts and
 * desync", "Authoritative result", "Combat").
 *
 * Clock. The world steps in master substeps of 1/SUB_HZ s. Substep s simulates the interval
 * [s, s+1): tape events whose crossing sub lies in [s, s+1) fire during it, and every pose, signal
 * and beat it evaluates is the instant `now = s + 1` it produces. After it, `sub === now`, and
 * snapshot() describes exactly that instant (sub 0 = the initial state at beat zero; REC-02).
 *
 * Record mode (config.live): stepLocalTick(input) runs the PlayerController for one local tick,
 * appends the pose and its events to the live tape, then runs subsPerLocalTick(speed) substeps in
 * which the live self is read through the same tape interpolation as every playback self.
 * Playback mode: stepSub() advances one substep. resolveEncounter (resolve.ts) is playback mode
 * over the whole horizon.
 *
 * SUBSTEP ORDER (fixed; every system relies on it):
 *   1. playheads    every self's tape phase and projection pose at `now`; tape boundary events
 *   2. sync         playback selves: obstruction → desync (DESYNC-01); desynced selves: spark moves
 *                   toward the projection and resyncs on catch-up (DESYNC-02..05)
 *   3. dispatch     crossed tape events in [s, s+1), in tape-index order: melee swings open hit
 *                   windows, dodges open i-frames, interacts toggle the nearest switch, ranged and
 *                   ability effects are scheduled; due scheduled effects run (RANGED / ABILITY HOOKS)
 *   3b. trap sense  beam sensors and relays publish their signals (traps/system.ts; docs/TRAPS.md)
 *   4. mechanisms   plates, exits, signals, doors (grid solidity), lasers, wake-ups
 *   4b. traps       spikes, crushers (grid solidity), conveyors, flame jets, dart launchers,
 *                   bumpers, magnets, in entity order; their hits are queued for phase 7
 *   5. enemies      beat-grid decisions, movement, telegraph → attack, stagger, knockback
 *   6. projectiles  flight and contacts
 *   7. damage       live melee swings tested against bodies; all queued hits applied together
 *   8. objective    latch
 *   9. events       footsteps; the substep's events are now drainable
 *
 * Life and sync gates (GHOST-01..06, DESYNC-07): a dead playback self ('ghost') has no effect and
 * is never obstructed; a desynced self can neither act nor be hurt; the live self after death
 * ('recGhost') still acts but cannot be hurt. Nothing about life is ever stored on a tape.
 */
import { BEAT_SIGHT_LOOKAHEAD_BEATS, manualDesync, parryProjectiles, upcomingAttackBeats } from './abilities';
import { beginDesync, isObstructed, SelfActor, stepSpark, STRIDE } from './actors';
import { CombatQueue, openSwing, resolveSwings } from './combat';
import { createEnemyState, enemySnapshot, stepEnemies } from './enemies/common';
import { getEnemyBehaviour } from './enemies/registry';
import type { EnemyState } from './enemies/types';
import { Grid } from './grid';
import { Mechanisms } from './mechanisms';
import { buildOutcome, ObjectiveTracker, RunLog } from './objective';
import { Pathfinder } from './path';
import { actionTiming, PlayerController } from './player';
import { ProjectileSystem } from './projectiles';
import { displaceController } from './traps/live';
import { Traps } from './traps/system';
// Registers the player's ranged weapon archetypes (missile, pierce, phase, arc, burst).
import './weapons/index';
import { animIndex, wrapAngle } from './tape';
import { collectBoundaries, collectEventCrossings, horizonSubs, subsPerBeat, tapeTicks, type EventCrossing } from './time';
import { BASE } from './tuning';
import {
  subsPerLocalTick,
  type AbilityId,
  type ActorSnap,
  type BossMemory,
  type FrameSnapshot,
  type ISim,
  type LevelDef,
  type Outcome,
  type PlayerInput,
  type ResolvedLoadout,
  type SimConfig,
  type SimEvent,
  type Tape,
  type TapeEvent,
  type TapeIndex,
} from './types';

// ───────────────────────────── world context ─────────────────────────────

/** What every subsystem sees of the running encounter. */
export interface World {
  readonly level: LevelDef;
  readonly loadout: ResolvedLoadout;
  readonly grid: Grid;
  readonly paths: Pathfinder;
  /** Master substeps per master beat. */
  readonly spb: number;
  readonly horizonSubs: number;
  /** Substep being simulated: the interval [s, s+1). */
  readonly s: number;
  /** Instant this substep produces (s + 1); poses, signals and beats are evaluated here. */
  readonly now: number;
  /** Master beat at `now`. */
  readonly beat: number;
  /** Selves sorted by tape index. */
  readonly selves: readonly SelfActor[];
  /** Enemies in entity order. */
  readonly enemies: readonly EnemyState[];
  readonly mechs: Mechanisms;
  readonly projectiles: ProjectileSystem;
  readonly signals: Map<string, boolean>;
  readonly combat: CombatQueue;
  readonly log: RunLog;
  emit(ev: Omit<SimEvent, 'sub'>): void;
  enemyById(id: string): EnemyState | undefined;
  /** A self's melee killed an enemy ('killRefresh' refunds the live self's dodge). */
  onMeleeKill(tape: TapeIndex): void;
  /** Put a self into desync on demand (gear abilities such as 'manualDesync'). */
  desync(self: SelfActor, cause: string): void;
  /** The outside-the-loop boss's memory for this run (SimConfig.bossMemory). Read-only. */
  readonly bossMemory: BossMemory | undefined;
}

// ───────────────────────────── ability hook ─────────────────────────────

/**
 * ═══ ABILITY DISPATCH HOOK ═══ — a self's recorded 'ability' event reaches the handler registered
 * for each active ability in the loadout, at the event's effect tick, for any self that is not a
 * dead playback ghost (the handler applies its own gates, e.g. manual desync works while desynced).
 * With no handler registered the event has no effect.
 */
export type AbilityHandler = (w: World, self: SelfActor, ev: TapeEvent, passDir: 1 | -1) => void;

const ABILITY_HANDLERS = new Map<AbilityId, AbilityHandler>();

export function registerAbilityHandler(id: AbilityId, handler: AbilityHandler): void {
  ABILITY_HANDLERS.set(id, handler);
}

// Built-in ability rules (src/core/abilities.ts). Registered here rather than from abilities.ts so
// that module never has to import this one at runtime.
registerAbilityHandler('manualDesync', manualDesync);

// ───────────────────────────── the sim ─────────────────────────────

export class Sim implements ISim, World {
  readonly config: SimConfig;
  readonly level: LevelDef;
  readonly loadout: ResolvedLoadout;
  readonly grid: Grid;
  readonly paths: Pathfinder;
  readonly spb: number;
  readonly horizonSubs: number;
  readonly tapeTicks: number;
  readonly selves: SelfActor[] = [];
  readonly enemies: EnemyState[] = [];
  readonly mechs: Mechanisms;
  /** Traps and automated machinery (docs/TRAPS.md). Inert when the level has none. */
  readonly traps: Traps;
  readonly projectiles = new ProjectileSystem();
  readonly signals = new Map<string, boolean>();
  readonly combat = new CombatQueue();
  readonly log = new RunLog();
  private readonly objective: ObjectiveTracker;
  private readonly enemyIndex = new Map<string, EnemyState>();

  private _sub = 0;
  private _s = 0;
  private events: SimEvent[] = [];
  private readonly crossBuf: EventCrossing[] = [];

  // record mode
  private readonly controller: PlayerController | null = null;
  private readonly liveSelf: SelfActor | null = null;
  private readonly liveTapeView: Tape | null = null;
  private liveTicks = 0;

  constructor(config: SimConfig) {
    this.config = config;
    this.level = config.level;
    this.loadout = config.loadout;
    this.grid = Grid.fromLevel(config.level);
    this.paths = new Pathfinder(this.grid);
    this.spb = subsPerBeat(config.level);
    if (!Number.isInteger(this.spb)) throw new Error(`Level ${config.level.id}: bpm ${config.level.bpm} does not give whole substeps per beat`);
    this.horizonSubs = horizonSubs(config.level);
    this.tapeTicks = tapeTicks(config.level);

    const used = new Set<number>();
    const live = config.live;
    for (const t of config.tapes) {
      if (live && t.index === live.index) continue;
      if (used.has(t.index)) throw new Error(`Two tapes share cassette index ${t.index}`);
      if (t.pos.length !== (t.ticks + 1) * 2 || t.facing.length !== t.ticks + 1 || t.anim.length !== t.ticks + 1) {
        throw new Error(`Tape ${t.index} arrays do not match its ${t.ticks} ticks`);
      }
      used.add(t.index);
      this.selves.push(new SelfActor(t.index, t, false));
    }
    if (live) {
      const T = this.tapeTicks;
      const start = config.level.start;
      const facing = Math.fround(wrapAngle(config.level.startFacing ?? 0));
      const view: Tape = {
        index: live.index,
        speed: live.speed,
        endMode: live.endMode,
        ticks: T,
        pos: new Float32Array((T + 1) * 2),
        facing: new Float32Array(T + 1),
        anim: new Uint8Array(T + 1),
        events: [],
      };
      view.pos[0] = start.x;
      view.pos[1] = start.y;
      view.facing[0] = facing;
      view.anim[0] = animIndex('idle');
      this.liveTapeView = view;
      this.controller = new PlayerController({ x: start.x, y: start.y, facing: config.level.startFacing ?? 0 });
      this.liveSelf = new SelfActor(live.index, view, true);
      this.selves.push(this.liveSelf);
    }
    this.selves.sort((a, b) => a.index - b.index);

    for (const ent of config.level.entities) {
      if (ent.kind !== 'enemy') continue;
      if (this.enemyIndex.has(ent.id)) throw new Error(`Duplicate enemy id ${ent.id}`);
      getEnemyBehaviour(ent.type);
      const e = createEnemyState(ent);
      this.enemies.push(e);
      this.enemyIndex.set(e.id, e);
    }
    this.mechs = new Mechanisms(config.level, this.grid, this.signals);
    this.objective = new ObjectiveTracker(config.level);
    this.traps = new Traps(config.level, this.grid, this.signals);
    // Trap signals first so doors can read them at beat zero, then again so traps read the doors.
    this.traps.init(this);
    this.mechs.init(this);
    this.traps.init(this);
    for (const e of this.enemies) getEnemyBehaviour(e.type).init?.(this, e);
  }

  // ── World ──

  get s(): number {
    return this._s;
  }
  get now(): number {
    return this._s + 1;
  }
  get beat(): number {
    return (this._s + 1) / this.spb;
  }
  get bossMemory(): BossMemory | undefined {
    return this.config.bossMemory;
  }

  emit(ev: Omit<SimEvent, 'sub'>): void {
    const out: SimEvent = { sub: this._s, type: ev.type, x: ev.x, y: ev.y };
    if (ev.tape !== undefined) out.tape = ev.tape;
    if (ev.id !== undefined) out.id = ev.id;
    if (ev.dir !== undefined) out.dir = ev.dir;
    if (ev.power !== undefined) out.power = ev.power;
    if (ev.detail !== undefined) out.detail = ev.detail;
    this.events.push(out);
  }

  enemyById(id: string): EnemyState | undefined {
    return this.enemyIndex.get(id);
  }

  onMeleeKill(tape: TapeIndex): void {
    if (this.controller && this.liveSelf && this.liveSelf.index === tape && this.loadout.abilities.includes('killRefresh')) {
      this.controller.refreshDodge();
    }
  }

  desync(self: SelfActor, cause: string): void {
    if (!self.synced || self.life === 'ghost') return;
    beginDesync(this.grid, self, this._s);
    this.emit({ type: 'desync', x: self.pose.x, y: self.pose.y, tape: self.index, detail: cause });
    this.log.desync(self.index, this._s, cause);
  }

  // ── ISim ──

  get sub(): number {
    return this._sub;
  }

  get localTick(): number {
    return this.liveTicks;
  }

  get done(): boolean {
    return this.config.live ? this.liveTicks >= this.tapeTicks : this._sub >= this.horizonSubs;
  }

  stepLocalTick(input: PlayerInput): void {
    const ctl = this.controller;
    const self = this.liveSelf;
    const view = this.liveTapeView;
    if (!ctl || !self || !view) throw new Error('stepLocalTick: this sim is not in record mode');
    if (this.done) return;
    // Belts and bumpers move the live body by what the world moves in this tick (docs/TRAPS.md).
    if (this.traps.count > 0) {
      const at = ctl.pose;
      const moved = this.traps.liveCarry(this, at.x, at.y, subsPerLocalTick(view.speed));
      if (moved) displaceController(ctl, moved.x, moved.y);
    }
    const r = ctl.step(input, this.grid, this.loadout, self.life === 'alive' ? 'alive' : 'recGhost');
    const i = ++this.liveTicks;
    view.pos[i * 2] = r.x;
    view.pos[i * 2 + 1] = r.y;
    view.facing[i] = r.facing;
    view.anim[i] = animIndex(r.anim);
    for (const ev of r.events) view.events.push({ ...ev });
    const m = subsPerLocalTick(view.speed);
    for (let k = 0; k < m; k++) this.substep();
  }

  stepSub(): void {
    if (this.config.live) throw new Error('stepSub: this sim is in record mode; use stepLocalTick');
    if (this._sub >= this.horizonSubs) return;
    this.substep();
  }

  liveTape(): Tape {
    const view = this.liveTapeView;
    if (!view) throw new Error('liveTape: this sim is not in record mode');
    const n = this.done ? view.ticks : this.liveTicks;
    return {
      index: view.index,
      speed: view.speed,
      endMode: view.endMode,
      ticks: n,
      pos: view.pos.slice(0, (n + 1) * 2),
      facing: view.facing.slice(0, n + 1),
      anim: view.anim.slice(0, n + 1),
      events: view.events.filter((e) => e.tick <= n).map((e) => ({ ...e })),
    };
  }

  drainEvents(): SimEvent[] {
    const out = this.events;
    this.events = [];
    return out;
  }

  outcome(): Outcome {
    return buildOutcome(this, this.objective, this.level);
  }

  /**
   * 'beatSight': master beats of upcoming enemy attacks from now to `lookAheadBeats` beats ahead
   * (see abilities.ts upcomingAttackBeats). Empty unless the loadout has the ability.
   */
  threatBeats(lookAheadBeats: number = BEAT_SIGHT_LOOKAHEAD_BEATS): number[] {
    if (!this.loadout.abilities.includes('beatSight')) return [];
    return upcomingAttackBeats(this, this._sub, lookAheadBeats);
  }

  snapshot(): FrameSnapshot {
    const actors: ActorSnap[] = this.selves.map((s) => {
      const a: ActorSnap = {
        tape: s.index,
        live: s.live,
        x: s.pose.x,
        y: s.pose.y,
        facing: s.pose.facing,
        anim: s.pose.anim,
        life: s.life,
        synced: s.synced,
        iframes: s.life !== 'ghost' && s.inIframes(this._sub),
        phase: { tick: s.phase.tick, dir: s.phase.dir, traversal: s.phase.traversal, ended: s.phase.ended },
        vx: s.vx,
        vy: s.vy,
      };
      if (s.spark) a.spark = { x: s.spark.x, y: s.spark.y };
      return a;
    });
    return {
      sub: this._sub,
      beat: this._sub / this.spb,
      actors,
      enemies: this.enemies.map((e) => enemySnapshot(this, e, this._sub)),
      projectiles: this.projectiles.snapshot(),
      mechs: this.traps.count > 0 ? [...this.mechs.snapshot(), ...this.traps.snapshot(this._sub)] : this.mechs.snapshot(),
      objective: this.objective.snapshot(this),
    };
  }

  // ───────────────────────────── one substep ─────────────────────────────

  private substep(): void {
    const s = this._sub;
    this._s = s;
    const now = s + 1;

    // 1. playheads
    for (const self of this.selves) {
      self.advance(now, self.live ? this.liveTicks : self.tape.ticks);
      if (!self.live) this.emitBoundaries(self, now);
    }

    // 2. sync: obstruction → desync; spark catch-up → resync
    for (const self of this.selves) {
      if (self.life === 'ghost') continue;
      if (!self.synced) {
        // 'manualDesync' holds the spark where the self left its body until released (abilities.ts).
        if (self.sparkHeld) continue;
        if (stepSpark(this.grid, this.paths, self, this.loadout, s)) {
          this.emit({ type: 'resync', x: self.pose.x, y: self.pose.y, tape: self.index });
          this.log.resync(self.index, s);
        }
        continue;
      }
      if (!self.live && isObstructed(this.grid, self, this.loadout)) {
        this.desync(self, this.obstructionCause(self));
        continue;
      }
      self.lastValidX = self.pose.x;
      self.lastValidY = self.pose.y;
    }

    // 3. dispatch crossed tape events, then due scheduled effects
    for (const self of this.selves) {
      self.prune(s);
      const crossings = this.crossBuf;
      crossings.length = 0;
      collectEventCrossings(self.tape, s, now, crossings);
      for (const c of crossings) this.dispatch(self, c);
      this.runScheduled(self, s);
    }

    // 3b. trap signal sources (sensors, relays)
    this.traps.sense(this);

    // 4. mechanisms
    this.mechs.step(this);

    // 4b. traps
    this.traps.step(this);

    // 5. enemies
    stepEnemies(this);

    // 6. projectiles ('parry' turns enemy shots inside live heavy swings first, before they move)
    parryProjectiles(this);
    this.projectiles.step(this);

    // 7. damage
    resolveSwings(this);
    this.combat.resolve(this);

    // 8. objective
    this.objective.update(this);

    // 9. footsteps
    for (const self of this.selves) {
      if (self.life === 'ghost' || self.cut) continue;
      if (self.pose.anim !== 'run') {
        self.strideAcc = 0;
        continue;
      }
      self.strideAcc += Math.hypot(self.pose.x - self.prevX, self.pose.y - self.prevY);
      if (self.strideAcc >= STRIDE) {
        self.strideAcc -= STRIDE;
        this.emit({ type: 'step', x: self.pose.x, y: self.pose.y, tape: self.index, detail: self.life });
      }
    }

    this._sub = now;
  }

  private emitBoundaries(self: SelfActor, now: number): void {
    // A boundary that coincides with the end of the encounter is not announced: nothing follows it.
    if (now >= this.horizonSubs) return;
    const bs = collectBoundaries(self.tape, now, now + 1);
    for (const b of bs) {
      const type = b.kind === 'end' ? 'tapeEnd' : b.kind === 'wrap' ? 'tapeWrap' : 'tapeTurn';
      this.emit({ type, x: self.pose.x, y: self.pose.y, tape: self.index, power: b.traversal, detail: b.kind === 'turn' ? (b.dir === -1 ? 'backward' : 'forward') : undefined });
    }
  }

  /** Player-readable name of what obstructs a self's recorded pose. */
  private obstructionCause(self: SelfActor): string {
    const r = BASE.actorRadius;
    const { x, y } = self.pose;
    const c0 = Math.floor(Math.min(x, self.prevX) - r);
    const c1 = Math.floor(Math.max(x, self.prevX) + r);
    const r0 = Math.floor(Math.min(y, self.prevY) - r);
    const r1 = Math.floor(Math.max(y, self.prevY) + r);
    for (let rr = r0; rr <= r1; rr++) {
      for (let cc = c0; cc <= c1; cc++) {
        if (!this.grid.isDynamicSolid(cc, rr)) continue;
        const owner = this.mechs.ownerAt(cc, rr) ?? this.traps.ownerAt(cc, rr);
        if (owner) return `blocked by ${owner}`;
      }
    }
    return 'blocked by a wall';
  }

  private dispatch(self: SelfActor, c: EventCrossing): void {
    // GHOST-05: a dead playback self's attempts have no effect at all.
    if (self.life === 'ghost') return;
    const ev = c.event;
    const passDir = c.dir;
    switch (ev.kind) {
      case 'light':
      case 'heavy':
        // The swing itself checks canAct on every live substep: a self that dies or desyncs during
        // the windup does not hit, one that resyncs before the hit frame does (TEST-11, TEST-17).
        openSwing(this, self, ev, c.sub, passDir);
        return;
      case 'dodge': {
        const t = actionTiming('dodge', this.loadout);
        self.iframes.push({ start: c.sub + t.iframeStart * self.m, end: c.sub + t.iframeEnd * self.m });
        this.emit({ type: 'dodge', x: self.pose.x, y: self.pose.y, tape: self.index, dir: ev.dir });
        return;
      }
      case 'interact':
      case 'ranged':
      case 'ability': {
        const t = actionTiming(ev.kind, this.loadout);
        self.scheduled.push({ sub: c.sub + t.effect * self.m, event: ev, passDir, traversal: c.traversal });
        return;
      }
    }
  }

  private runScheduled(self: SelfActor, s: number): void {
    if (self.scheduled.length === 0) return;
    let j = 0;
    const list = self.scheduled;
    for (let i = 0; i < list.length; i++) {
      const fx = list[i];
      if (fx.sub > s) {
        list[j++] = fx;
        continue;
      }
      if (self.life === 'ghost') continue;
      const ev = fx.event;
      if (ev.kind === 'interact') {
        if (self.canAct) this.mechs.interact(this, self);
        else this.emit({ type: 'interactFail', x: self.pose.x, y: self.pose.y, tape: self.index, detail: 'desynced' });
      } else if (ev.kind === 'ranged') {
        // Only a self that can act launches (Scenario F); see ProjectileSystem.launchFromSelf.
        if (self.canAct) this.projectiles.launchFromSelf(this, self, ev, fx.passDir);
      } else if (ev.kind === 'ability') {
        for (const id of this.loadout.abilities) ABILITY_HANDLERS.get(id)?.(this, self, ev, fx.passDir);
      }
    }
    list.length = j;
  }
}

export function createSim(config: SimConfig): ISim {
  return new Sim(config);
}
