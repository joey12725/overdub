/**
 * Combat resolution (COMBAT-01..04, MOM-01..06, HEALTH-01..04).
 *
 * Everything that hurts something is queued during a substep and applied together in the
 * damage-resolution phase, so hits that land on the same substep are simultaneous (a self and a
 * grunt that strike each other on the same substep both die) and the order systems run in never
 * decides who wins a trade.
 *
 *   SelfHit      — something tries to kill a self (enemy strike, bolt, laser). One hit is lethal
 *                  (HEALTH-01) unless the self is no longer vulnerable or is inside dodge i-frames.
 *                  Enemy hits never displace a recorded self (MOM-06): they kill it or do nothing.
 *   EnemyStrike  — momentum delivered to an enemy (melee, projectiles, environment). Converted into
 *                  damage, real knockback (MOM-05) and stagger by the shared formulas in tuning.ts;
 *                  an enemy behaviour's onHit hook may veto or rewrite it (shields, armour).
 *   Object hits  — melee swings against breakables and cores compare momentum with a threshold and
 *                  'clang' when too weak (Scenario K), naming the momentum that was missing.
 *
 * Extension points:
 *   - `meleeMomentum` is the single place a swing's momentum is computed. Gear that changes it
 *     (slideStrike, …) should wrap or extend this function rather than recomputing elsewhere.
 *   - `world.combat.strikeEnemy(...)` is the entry point projectile archetypes use to deliver
 *     momentum; `world.combat.hitSelf(...)` is how enemy weapons kill selves.
 */
import { slideStrikeFactor } from './abilities';
import type { SelfActor } from './actors';
import type { EnemyState } from './enemies/types';
import { killEnemy, applyKnockback, applyStagger } from './enemies/common';
import { getEnemyBehaviour } from './enemies/registry';
import { actionTiming } from './player';
import { angleDelta } from './tape';
import {
  DEFAULT_CORE_THRESHOLD,
  strikeDamage,
  strikeKnockback,
  strikeStagger,
  swingMomentum,
} from './tuning';
import { SUB_HZ, type TapeEvent, type TapeIndex } from './types';
import type { World } from './sim';

// ───────────────────────────── strikes ─────────────────────────────

/** Who delivered a strike. */
export type StrikeSource = { tape: TapeIndex } | { enemy: string } | { env: string };

/** Momentum delivered to an enemy. Damage / knockback / stagger are derived from it unless overridden. */
export interface EnemyStrike {
  source: StrikeSource;
  /** 'light' | 'heavy' | projectile archetype | 'bolt' | … (SimEvent.detail of the 'hit'). */
  kind: string;
  momentum: number;
  /** Direction of the push, radians. */
  dir: number;
  /** Where the strike landed (event position). */
  x: number;
  y: number;
  /** Explicit damage points; absent = strikeDamage(momentum, …) with the loadout's melee efficiencies. */
  damage?: number;
  /** Explicit knockback distance in tiles; absent = strikeKnockback(...). */
  knockback?: number;
  /** Explicit stagger in master seconds; absent = strikeStagger(...). */
  stagger?: number;
  /** True for melee swings (killRefresh refunds the live self's dodge on a melee kill). */
  melee?: boolean;
}

/** An attempt to kill a self. */
export interface SelfHit {
  self: SelfActor;
  /** Player-readable cause, e.g. "struck by grunt g1", "shot by turret t1", "burned by laser beam". */
  cause: string;
  x: number;
  y: number;
  dir: number;
  /** Laser hazards respect 'laserProof'. */
  laser?: boolean;
}

/** Response of an enemy behaviour's onHit hook. */
export type HitResponse =
  /** Apply the strike normally. */
  | { kind: 'apply' }
  /** The strike is blocked entirely (shield up, invulnerable phase): emits 'clang'. */
  | { kind: 'block'; reason: string }
  /** Apply a modified strike instead. */
  | { kind: 'replace'; strike: EnemyStrike };

export class CombatQueue {
  private readonly selfHits: SelfHit[] = [];
  private readonly enemyStrikes: { enemy: EnemyState; strike: EnemyStrike }[] = [];

  hitSelf(hit: SelfHit): void {
    this.selfHits.push(hit);
  }

  strikeEnemy(enemy: EnemyState, strike: EnemyStrike): void {
    this.enemyStrikes.push({ enemy, strike });
  }

  /** Apply everything queued this substep. Vulnerability is judged once, before anything applies. */
  resolve(w: World): void {
    const hits = this.selfHits;
    const strikes = this.enemyStrikes;
    // Snapshot who was vulnerable when the substep's hits landed, so a self killed by one hit is not
    // reported dead twice and mutual kills on the same substep both happen.
    const dying = new Set<SelfActor>();
    for (const h of hits) {
      const s = h.self;
      if (dying.has(s) || !s.vulnerable) continue;
      if (s.inIframes(w.s)) continue;
      if (h.laser && w.loadout.abilities.includes('laserProof')) continue;
      dying.add(s);
      killSelf(w, s, h);
    }
    for (const { enemy, strike } of strikes) applyStrike(w, enemy, strike);
    hits.length = 0;
    strikes.length = 0;
  }
}

function killSelf(w: World, s: SelfActor, h: SelfHit): void {
  s.life = s.live ? 'recGhost' : 'ghost';
  s.deathSub = w.s;
  s.deathCause = h.cause;
  // A playback self's pending attempts die with it (GHOST-05). The recording ghost keeps acting in
  // its own take (GHOST-03), so an attack already under way still lands.
  if (!s.live) {
    s.swings.length = 0;
    s.scheduled.length = 0;
  }
  w.emit({ type: 'selfDeath', x: s.pose.x, y: s.pose.y, tape: s.index, dir: h.dir, detail: h.cause });
  w.log.death(s.index, w.s, h.cause);
}

function sourceTape(src: StrikeSource): TapeIndex | undefined {
  return 'tape' in src ? src.tape : undefined;
}

/** Apply one strike to an enemy: behaviour veto, damage, knockback, stagger, death. */
export function applyStrike(w: World, e: EnemyState, strike: EnemyStrike): void {
  if (!e.alive) return;
  const beh = getEnemyBehaviour(e.type);
  let st = strike;
  if (beh.onHit) {
    const r = beh.onHit(w, e, st);
    if (r.kind === 'block') {
      w.emit({ type: 'clang', x: e.x, y: e.y, id: e.id, tape: sourceTape(st.source), power: st.momentum, dir: st.dir, detail: r.reason });
      const t = sourceTape(st.source);
      if (t !== undefined) w.log.weak(t, w.s, st.kind, e.id, st.momentum, null, r.reason);
      return;
    }
    if (r.kind === 'replace') st = r.strike;
  }
  const mel = w.loadout.melee;
  const mods = w.loadout.mods;
  const dmg = st.damage ?? strikeDamage(st.momentum, mel.damageEff, mods.damage);
  const kb = st.knockback ?? strikeKnockback(st.momentum, mel.knockbackEff, mods.knockback, mods.knockbackCap, e.stats.mass);
  const stg = st.stagger ?? strikeStagger(st.momentum, mel.staggerEff, mods.stagger, e.stats.poise);
  const t = sourceTape(st.source);
  w.emit({ type: 'hit', x: e.x, y: e.y, id: e.id, tape: t, power: st.momentum, dir: st.dir, detail: st.kind });
  if (dmg <= 0) {
    // The hit landed but did no damage: say so, so the player can tell the swing lacked momentum.
    w.emit({ type: 'clang', x: e.x, y: e.y, id: e.id, tape: t, power: st.momentum, dir: st.dir, detail: 'momentum' });
    if (t !== undefined) w.log.weak(t, w.s, st.kind, e.id, st.momentum, null, 'no damage');
  }
  e.hp -= dmg;
  if (e.hp <= 0) {
    e.hp = 0;
    killEnemy(w, e, st);
    if (st.melee && t !== undefined) w.onMeleeKill(t);
    return;
  }
  if (kb > 0) applyKnockback(w, e, st.dir, kb);
  if (stg > 0) applyStagger(w, e, Math.round(stg * SUB_HZ));
}

// ───────────────────────────── melee ─────────────────────────────

/**
 * Momentum of a recorded swing when it fires (MOM-01..04). The event's recorded local velocity is
 * the body's motion into the strike; on a reverse pass the body is moving backward along its path,
 * so that velocity is negated (MOM-03: direction matters). Tape speed enters once, inside
 * swingMomentum (the master-time conversion of both swing and body velocity).
 */
export function meleeMomentum(w: World, self: SelfActor, ev: TapeEvent, passDir: 1 | -1): number {
  const swing = ev.kind === 'heavy' ? w.loadout.melee.heavy : w.loadout.melee.light;
  const base = swingMomentum(swing, w.loadout.mods, self.tape.speed, ev.vx * passDir, ev.vy * passDir, ev.dir);
  // 'slideStrike' gear: a swing started straight out of a dodge hits harder (abilities.ts).
  return base * slideStrikeFactor(w, self, ev, passDir);
}

/** Open a swing for a crossed light/heavy event: windup now, hit volume live for the active window. */
export function openSwing(w: World, self: SelfActor, ev: TapeEvent, crossSub: number, passDir: 1 | -1): void {
  if (ev.kind !== 'light' && ev.kind !== 'heavy') return;
  const t = actionTiming(ev.kind, w.loadout);
  self.swings.push({
    kind: ev.kind,
    dir: ev.dir,
    crossSub,
    start: crossSub + t.activeStart * self.m,
    end: crossSub + t.activeEnd * self.m,
    momentum: meleeMomentum(w, self, ev, passDir),
    passDir,
    struck: new Set(),
    announced: false,
    connected: false,
  });
}

/** Is point (px, py) with radius pr inside a swing's hit volume from (ox, oy)? */
export function inSwingVolume(
  ox: number,
  oy: number,
  dir: number,
  reach: number,
  arcRad: number,
  px: number,
  py: number,
  pr: number,
): boolean {
  const dx = px - ox;
  const dy = py - oy;
  const d = Math.hypot(dx, dy);
  if (d > reach + pr) return false;
  if (d <= pr) return true;
  // Widen the arc by the target's angular radius so a body grazing the edge of the arc is struck.
  const slack = Math.asin(Math.min(1, pr / d));
  return Math.abs(angleDelta(dir, Math.atan2(dy, dx))) <= arcRad / 2 + slack;
}

/**
 * Test every live swing against enemies, breakables and cores. Runs in the damage-resolution phase,
 * after enemies and knockback have moved, so a body delivered into a recorded swing is struck
 * (TEST-19, MOM-05). The swing's origin is the self's current recorded position (PLAY-01).
 */
export function resolveSwings(w: World): void {
  const mel = w.loadout.melee;
  const arc = (mel.arcDeg * Math.PI) / 180;
  const reach = mel.reach;
  const s = w.s;
  for (const self of w.selves) {
    if (self.swings.length === 0) continue;
    for (let i = self.swings.length - 1; i >= 0; i--) {
      const sw = self.swings[i];
      if (s >= sw.end) {
        if (sw.announced && !sw.connected) {
          w.emit({ type: 'whiff', x: self.pose.x, y: self.pose.y, tape: self.index, dir: sw.dir, power: sw.momentum, detail: sw.kind });
        }
        self.swings.splice(i, 1);
      }
    }
    if (!self.canAct) continue;
    for (const sw of self.swings) {
      if (s < sw.start || s >= sw.end) continue;
      const ox = self.pose.x;
      const oy = self.pose.y;
      if (!sw.announced) {
        sw.announced = true;
        w.emit({ type: 'swing', x: ox, y: oy, tape: self.index, dir: sw.dir, power: sw.momentum, detail: sw.kind });
      }
      for (const e of w.enemies) {
        if (!e.alive || sw.struck.has(e.id)) continue;
        if (!inSwingVolume(ox, oy, sw.dir, reach, arc, e.x, e.y, e.stats.radius)) continue;
        if (w.grid.segmentBlocked(ox, oy, e.x, e.y, true)) continue;
        sw.struck.add(e.id);
        sw.connected = true;
        w.combat.strikeEnemy(e, {
          source: { tape: self.index },
          kind: sw.kind,
          momentum: sw.momentum,
          dir: sw.dir,
          x: e.x,
          y: e.y,
          melee: true,
        });
      }
      w.mechs.strikeObjects(w, self, sw, ox, oy, reach, arc);
    }
  }
}

/** Radius of a core's struck body, tiles. */
export const CORE_RADIUS = 0.4;

/** Threshold of a core (CoreDef.threshold or the default). */
export function coreThreshold(threshold: number | undefined): number {
  return threshold ?? DEFAULT_CORE_THRESHOLD;
}
