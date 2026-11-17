/**
 * PlayerController — the ONLY place live player physics happens (ARCHITECTURE "One clock").
 *
 * Each call to `step` advances one LOCAL tick (1/LOCAL_HZ local seconds): it turns that tick's
 * input into the next pose plus any action events started on the tick. The kernel appends the pose
 * to the tape and then simulates the world by reading the tape exactly as playback does.
 *
 * Everything here is in local time, so movement and action timing feel identical at every tape
 * speed (TIME-02, COMBAT-04 "consistent in local tape time, then mapped to master time").
 *
 * Action timing is defined once, by `actionTiming`; the controller drives its state machine from
 * it and the kernel interprets recorded events through the same function (meleeHitWindow,
 * dodgeIframeWindow, rangedLaunchTick), so live play and playback cannot drift apart.
 */
import type { Grid, MoveOpts, MoveResult } from './grid';
import { angleDelta, wrapAngle } from './tape';
import { BASE } from './tuning';
import {
  LOCAL_HZ,
  type AbilityId,
  type ActionKind,
  type AnimState,
  type LifeState,
  type PlayerInput,
  type ResolvedLoadout,
  type TapeEvent,
} from './types';

const DT = 1 / LOCAL_HZ;

// ───────────────────────────── action timing (shared with the kernel) ─────────────────────────────

/**
 * Timing of one action, in local ticks as OFFSETS from the tick the action started. On a reverse
 * pass the kernel applies the same offsets from the crossing instant (a fresh swing; PLAY-06).
 */
export interface ActionTiming {
  kind: ActionKind;
  /** The actor cannot start another action for ticks [0, commit). */
  commit: number;
  /** Facing is locked to the action direction for ticks [0, faceLock). */
  faceLock: number;
  /** Movement speed multiplier while committed. */
  moveMul: number;
  /** Melee: hit volume live for [activeStart, activeEnd). Others: both equal `effect`. */
  activeStart: number;
  activeEnd: number;
  /** Dodge: invulnerable for [iframeStart, iframeEnd). Others: empty (0, 0). */
  iframeStart: number;
  iframeEnd: number;
  /**
   * The tick the action affects the world: melee hit-frame (activeStart), ranged projectile launch,
   * interact / ability / dodge 0.
   */
  effect: number;
  /** The same kind cannot start again before this offset (dodge / ranged cooldowns; others = commit). */
  cooldown: number;
}

/** Gear abilities that the ability button triggers (others are passive). */
export const ACTIVE_ABILITIES: readonly AbilityId[] = ['manualDesync'];

function ticksOf(v: number): number {
  return v > 0 ? Math.round(v) : 0;
}

/** Timing of an action of `kind` under a loadout. Pure; identical for live play and playback. */
export function actionTiming(kind: ActionKind, loadout: ResolvedLoadout): ActionTiming {
  const mods = loadout.mods;
  switch (kind) {
    case 'light':
    case 'heavy': {
      const s = kind === 'light' ? loadout.melee.light : loadout.melee.heavy;
      const w = ticksOf(s.windup);
      const a = Math.max(1, ticksOf(s.active));
      const r = ticksOf(s.recover);
      return {
        kind,
        commit: w + a + r,
        faceLock: w + a,
        moveMul: s.moveMul,
        activeStart: w,
        activeEnd: w + a,
        iframeStart: 0,
        iframeEnd: 0,
        effect: w,
        cooldown: w + a + r,
      };
    }
    case 'dodge': {
      const d = BASE.dodgeTicks;
      const is = BASE.dodgeIframeStart;
      const ie = is + ticksOf(BASE.dodgeIframes * mods.dodgeIframes);
      return {
        kind,
        commit: d,
        faceLock: d,
        moveMul: 1,
        activeStart: 0,
        activeEnd: 0,
        iframeStart: is,
        iframeEnd: ie,
        effect: 0,
        cooldown: d + ticksOf(BASE.dodgeCooldown * mods.dodgeCooldown),
      };
    }
    case 'ranged': {
      const c = Math.max(1, ticksOf(loadout.ranged.commit));
      const launch = Math.min(BASE.rangedLaunchDelay, c - 1);
      return {
        kind,
        commit: c,
        faceLock: c,
        moveMul: BASE.rangedMoveMul,
        activeStart: launch,
        activeEnd: launch,
        iframeStart: 0,
        iframeEnd: 0,
        effect: launch,
        cooldown: Math.max(c, ticksOf(loadout.ranged.cooldown * mods.rangedCooldown)),
      };
    }
    case 'interact': {
      const c = BASE.interactTicks;
      return {
        kind,
        commit: c,
        faceLock: 0,
        moveMul: BASE.interactMoveMul,
        activeStart: 0,
        activeEnd: 0,
        iframeStart: 0,
        iframeEnd: 0,
        effect: 0,
        cooldown: c,
      };
    }
    case 'ability':
      return {
        kind,
        commit: 0,
        faceLock: 0,
        moveMul: 1,
        activeStart: 0,
        activeEnd: 0,
        iframeStart: 0,
        iframeEnd: 0,
        effect: 0,
        cooldown: 0,
      };
  }
}

/** A half-open local tick window [start, end). */
export interface TickWindow {
  start: number;
  end: number;
}

/** Local ticks [start, end) in which a recorded melee event's hit volume is live; null for other kinds. */
export function meleeHitWindow(ev: Pick<TapeEvent, 'tick' | 'kind'>, loadout: ResolvedLoadout): TickWindow | null {
  if (ev.kind !== 'light' && ev.kind !== 'heavy') return null;
  const t = actionTiming(ev.kind, loadout);
  return { start: ev.tick + t.activeStart, end: ev.tick + t.activeEnd };
}

/** Local ticks [start, end) of a recorded dodge's invulnerability; null for other kinds. */
export function dodgeIframeWindow(ev: Pick<TapeEvent, 'tick' | 'kind'>, loadout: ResolvedLoadout): TickWindow | null {
  if (ev.kind !== 'dodge') return null;
  const t = actionTiming('dodge', loadout);
  return { start: ev.tick + t.iframeStart, end: ev.tick + t.iframeEnd };
}

/** Local tick on which a recorded ranged event launches its projectile; null for other kinds. */
export function rangedLaunchTick(ev: Pick<TapeEvent, 'tick' | 'kind'>, loadout: ResolvedLoadout): number | null {
  if (ev.kind !== 'ranged') return null;
  return ev.tick + actionTiming('ranged', loadout).effect;
}

/** Local tick on which any recorded event affects the world (see ActionTiming.effect). */
export function effectTick(ev: Pick<TapeEvent, 'tick' | 'kind'>, loadout: ResolvedLoadout): number {
  return ev.tick + actionTiming(ev.kind, loadout).effect;
}

/** Interaction reach for a loadout, tiles. */
export function interactRadius(loadout: ResolvedLoadout): number {
  return BASE.interactRadius + loadout.mods.interactRadiusAdd;
}

/** Run speed for a loadout, tiles per local second. */
export function runSpeed(loadout: ResolvedLoadout): number {
  return BASE.runSpeed * loadout.mods.moveSpeed;
}

/** Anim state of a committed action `elapsed` ticks after it started. */
export function actionAnim(kind: ActionKind, elapsed: number, timing: ActionTiming): AnimState | null {
  switch (kind) {
    case 'light':
      return elapsed < timing.activeStart ? 'lightWindup' : elapsed < timing.activeEnd ? 'lightActive' : 'lightRecover';
    case 'heavy':
      return elapsed < timing.activeStart ? 'heavyWindup' : elapsed < timing.activeEnd ? 'heavyActive' : 'heavyRecover';
    case 'dodge':
      return 'dodge';
    case 'ranged':
      return 'ranged';
    case 'interact':
      return 'interact';
    case 'ability':
      return null;
  }
}

// ───────────────────────────── controller ─────────────────────────────

export interface PlayerPose {
  x: number;
  y: number;
  /** Radians, wrapped to (-π, π]. */
  facing: number;
  anim: AnimState;
  /** Local-space velocity, tiles per local second. */
  vx: number;
  vy: number;
}

export interface PlayerStepResult extends PlayerPose {
  /** Events started on this tick (their `tick` is the tick just simulated). */
  events: TapeEvent[];
  /** Dodge invulnerability covers the tick just simulated. */
  iframes: boolean;
}

export interface PlayerStart {
  x: number;
  y: number;
  facing?: number;
}

interface ActiveAction {
  kind: ActionKind;
  start: number;
  dir: number;
  timing: ActionTiming;
  /** Dodge dash direction (unit). */
  dx: number;
  dy: number;
}

/** Press priority when several buttons go down on the same tick. */
const PRESS_ORDER: readonly ActionKind[] = ['dodge', 'heavy', 'light', 'ranged', 'interact'];

export class PlayerController {
  private x: number;
  private y: number;
  private vx = 0;
  private vy = 0;
  private facing: number;
  private _tick = 0;
  private action: ActiveAction | null = null;
  private nextDodge = 0;
  private nextRanged = 0;
  private buffered: { kind: ActionKind; until: number } | null = null;
  private readonly moveRes: MoveResult = { x: 0, y: 0, blocked: false };

  constructor(start: PlayerStart) {
    this.x = Math.fround(start.x);
    this.y = Math.fround(start.y);
    this.facing = Math.fround(wrapAngle(start.facing ?? 0));
  }

  /** The local tick the next `step` will simulate (= ticks simulated so far). */
  get tick(): number {
    return this._tick;
  }

  /** Current pose (the pose of sample `tick`). */
  get pose(): PlayerPose {
    return {
      x: this.x,
      y: this.y,
      facing: this.facing,
      anim: this.currentAnim(this._tick - 1),
      vx: this.vx,
      vy: this.vy,
    };
  }

  /** Kind of the action in progress, if any (for HUD prompts). */
  get actionKind(): ActionKind | null {
    return this.action ? this.action.kind : null;
  }

  /** Ticks until a dodge may start (0 = ready). */
  get dodgeCooldown(): number {
    return Math.max(0, this.nextDodge - this._tick);
  }

  /** Ticks until a ranged shot may start (0 = ready). */
  get rangedCooldown(): number {
    return Math.max(0, this.nextRanged - this._tick);
  }

  /** 'killRefresh' ability: the kernel calls this when the live self's melee kills an enemy. */
  refreshDodge(): void {
    this.nextDodge = this._tick;
  }

  /**
   * Advance one local tick.
   *
   * `life` does not change physics on purpose: a recording ghost keeps normal movement, collision
   * and actions (GHOST-02, GHOST-03); invulnerability (GHOST-04) is the kernel's rule. It is taken
   * so the call site states which body it is driving, and to keep the signature stable if gear ever
   * differentiates the two.
   */
  step(input: PlayerInput, grid: Grid, loadout: ResolvedLoadout, life: Extract<LifeState, 'alive' | 'recGhost'>): PlayerStepResult {
    void life;
    const t = this._tick;
    const events: TapeEvent[] = [];
    const mods = loadout.mods;

    // Sanitise input: NaN-safe, length clamped to 1.
    let mx = Number.isFinite(input.moveX) ? input.moveX : 0;
    let my = Number.isFinite(input.moveY) ? input.moveY : 0;
    const mlen = Math.hypot(mx, my);
    if (mlen > 1) {
      mx /= mlen;
      my /= mlen;
    }
    const moveLen = Math.min(1, mlen);
    const aim = Number.isFinite(input.aim) ? wrapAngle(input.aim) : this.facing;
    const startX = this.x;
    const startY = this.y;
    const startVx = this.vx;
    const startVy = this.vy;

    // Ability presses are instant and never commit the body.
    if (input.ability && loadout.abilities.some((a) => ACTIVE_ABILITIES.includes(a))) {
      events.push({ tick: t, kind: 'ability', dir: aim, x: startX, y: startY, vx: startVx, vy: startVy });
    }

    // Buffer the highest-priority press of this tick (a newer press replaces an older one).
    for (const k of PRESS_ORDER) {
      if (input[k]) {
        this.buffered = { kind: k, until: t + BASE.inputBufferTicks };
        break;
      }
    }
    if (this.buffered && t > this.buffered.until) this.buffered = null;

    // End finished actions; a dodge hands its dash speed back as running momentum.
    if (this.action && t - this.action.start >= this.action.timing.commit) {
      if (this.action.kind === 'dodge') {
        const exit = BASE.runSpeed * mods.moveSpeed * BASE.dodgeExitSpeed;
        this.vx = this.action.dx * exit;
        this.vy = this.action.dy * exit;
      }
      this.action = null;
    }
    // A buffered dodge may cancel a melee swing's recovery (never its windup or hit frames).
    if (
      this.action &&
      this.buffered?.kind === 'dodge' &&
      t >= this.nextDodge &&
      (this.action.kind === 'light' || this.action.kind === 'heavy') &&
      t - this.action.start >= this.action.timing.activeEnd
    ) {
      this.action = null;
    }

    // Start the buffered action if the body is free and its cooldown has elapsed.
    if (!this.action && this.buffered) {
      const kind = this.buffered.kind;
      const ready = kind === 'dodge' ? t >= this.nextDodge : kind === 'ranged' ? t >= this.nextRanged : true;
      if (ready) {
        this.buffered = null;
        const timing = actionTiming(kind, loadout);
        let dir = aim;
        let dx = 0;
        let dy = 0;
        if (kind === 'dodge') {
          if (moveLen > 1e-6) dir = Math.atan2(my, mx);
          else dir = this.facing;
          dx = Math.cos(dir);
          dy = Math.sin(dir);
          this.nextDodge = t + timing.cooldown;
        } else if (kind === 'ranged') {
          this.nextRanged = t + timing.cooldown;
        }
        this.action = { kind, start: t, dir, timing, dx, dy };
        events.push({ tick: t, kind, dir, x: startX, y: startY, vx: startVx, vy: startVy });
      }
    }

    // ── locomotion ──
    const act = this.action;
    const elapsed = act ? t - act.start : 0;
    const moveOpts: MoveOpts | undefined =
      act?.kind === 'dodge' && loadout.abilities.includes('phaseDodge') ? PHASE_OPTS : undefined;
    // A door can close onto the body between ticks (the kernel never deletes a body): step out to
    // the nearest free side first, so the push is not mistaken for running speed below.
    if (grid.isSolidAt(this.x, this.y, BASE.actorRadius, moveOpts)) {
      const out = grid.moveCircle(this.x, this.y, 0, 0, BASE.actorRadius, moveOpts, this.moveRes);
      this.x = Math.fround(out.x);
      this.y = Math.fround(out.y);
    }
    if (act?.kind === 'dodge') {
      const speed = (BASE.dodgeDistance * mods.dodgeDistance) / (act.timing.commit * DT);
      this.vx = act.dx * speed;
      this.vy = act.dy * speed;
    } else {
      const mul = act ? act.timing.moveMul : 1;
      this.locomote(mx, my, moveLen, BASE.runSpeed * mods.moveSpeed * mul, mods.accel, mods.momentumRetention);
    }

    const res = grid.moveCircle(this.x, this.y, this.vx * DT, this.vy * DT, BASE.actorRadius, moveOpts, this.moveRes);
    const nx = Math.fround(res.x);
    const ny = Math.fround(res.y);
    if (res.blocked) {
      // Keep only the motion the walls allowed: sliding survives, the normal component dies.
      this.vx = (nx - this.x) / DT;
      this.vy = (ny - this.y) / DT;
    }
    this.x = nx;
    this.y = ny;

    // ── facing ──
    if (act && elapsed < act.timing.faceLock) {
      this.facing = act.dir;
    } else if (moveLen > 1e-6) {
      const want = Math.atan2(my, mx);
      const d = angleDelta(this.facing, want);
      const maxTurn = BASE.facingTurnRate * DT;
      this.facing = Math.abs(d) <= maxTurn ? want : wrapAngle(this.facing + Math.sign(d) * maxTurn);
    }
    this.facing = Math.fround(this.facing);

    const anim = this.currentAnim(t);
    const iframes = act !== null && act.kind === 'dodge' && elapsed >= act.timing.iframeStart && elapsed < act.timing.iframeEnd;
    this._tick = t + 1;
    return { x: this.x, y: this.y, facing: this.facing, anim, vx: this.vx, vy: this.vy, events, iframes };
  }

  /** Anim for tick `t` given the current action state (called after the tick's state is settled). */
  private currentAnim(t: number): AnimState {
    const act = this.action;
    if (act && t >= act.start && t - act.start < act.timing.commit) {
      const a = actionAnim(act.kind, t - act.start, act.timing);
      if (a) return a;
    }
    return Math.hypot(this.vx, this.vy) >= BASE.runAnimThreshold ? 'run' : 'idle';
  }

  /**
   * Velocity update toward the input. The component along the input accelerates linearly to the
   * cap; sideways velocity and overspeed decay exponentially at rates divided by momentum
   * retention (so retention gear carries momentum through turns and out of dashes); with no input
   * the body brakes linearly.
   */
  private locomote(mx: number, my: number, moveLen: number, maxSpeed: number, accelMod: number, retentionMod: number): void {
    const ret = retentionMod > 0.05 ? retentionMod : 0.05;
    if (moveLen > 1e-6) {
      const inv = 1 / Math.hypot(mx, my);
      const ux = mx * inv;
      const uy = my * inv;
      const target = maxSpeed * moveLen;
      let par = this.vx * ux + this.vy * uy;
      let px = this.vx - par * ux;
      let py = this.vy - par * uy;
      const keep = Math.exp((-BASE.turnDamping / ret) * DT);
      px *= keep;
      py *= keep;
      if (par < target) {
        // Reversing brakes with decel on top of accel so direction changes stay snappy.
        const a = (par < 0 ? BASE.accel + BASE.decel : BASE.accel) * accelMod;
        par = Math.min(target, par + a * DT);
      } else if (par > target) {
        par = target + (par - target) * Math.exp((-BASE.overspeedDecay / ret) * DT);
      }
      this.vx = par * ux + px;
      this.vy = par * uy + py;
    } else {
      const speed = Math.hypot(this.vx, this.vy);
      if (speed > 0) {
        const ns = Math.max(0, speed - ((BASE.decel * accelMod) / ret) * DT);
        const k = ns / speed;
        this.vx *= k;
        this.vy *= k;
      }
    }
    // Snap tiny residuals so a released stick reaches true rest (stable idle anim, clean tapes).
    if (Math.abs(this.vx) < 1e-6) this.vx = 0;
    if (Math.abs(this.vy) < 1e-6) this.vy = 0;
  }
}

const PHASE_OPTS: MoveOpts = { ignoreLow: true };

/** A neutral input (no movement, no buttons), handy for tests and for idling the live self. */
export function idleInput(aim = 0): PlayerInput {
  return { moveX: 0, moveY: 0, aim, light: false, heavy: false, dodge: false, ranged: false, interact: false, ability: false };
}
