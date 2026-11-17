/**
 * Gear abilities that are simulation rules (GEAR chapter, AbilityId in types.ts).
 *
 * Where each ability lives:
 *   manualDesync  `manualDesync` below, registered by sim.ts as the 'ability' event handler (OPEN-11:
 *                 the only way a live self can desync). Held sparks are honoured in sim.ts phase 2.
 *   lowProfile    `effectiveDistance` below; enemies/common.ts perceivedDistance delegates to it.
 *   loudmouth     ditto.
 *   beatSight     `upcomingAttackBeats` below, exposed as ISim.threatBeats (the HUD draws it).
 *   laserProof    combat.ts CombatQueue.resolve (laser hits are ignored).
 *   heavyStep     mechanisms.ts plate occupancy (heavy plates).
 *   phaseDodge    player.ts (live dodge ignores low barriers) + actors.ts isObstructed (playback).
 *   slideStrike   `slideStrikeFactor` below, applied inside combat.ts meleeMomentum.
 *   parry         `parryProjectiles` below, run by sim.ts at the start of the projectile phase.
 *   killRefresh   sim.ts onMeleeKill → PlayerController.refreshDodge (live self only: a playback
 *                 tape's dodges are already fixed, so there is nothing to refund).
 *
 * Every rule reads the shared loadout (all four cassettes wear the same gear) and recorded tape
 * data only, so record mode and playback agree wherever the rule itself allows.
 */
import type { SelfActor } from './actors';
import { inSwingVolume } from './combat';
import { nextGridSub, targetable, telegraphSubs } from './enemies/common';
import type { EnemyState } from './enemies/types';
import { actionTiming } from './player';
import { BOLT_RANGE } from './projectiles';
import type { World } from './sim';
import { wrapAngle } from './tape';
import type { AbilityId, TapeEvent } from './types';

// ───────────────────────────── lowProfile / loudmouth ─────────────────────────────

/** 'lowProfile': enemies read this loadout's selves as this many times farther away. */
export const LOW_PROFILE_FACTOR = 1.5;
/** 'loudmouth': enemies read this loadout's selves as this many times nearer (factor < 1). */
export const LOUDMOUTH_FACTOR = 0.75;

/**
 * Distance between an enemy and a self as enemy decision logic perceives it, for a loadout's
 * abilities. The single helper every enemy range / targeting rule goes through (via
 * enemies/common.ts perceivedDistance). Both abilities together multiply.
 */
export function effectiveDistance(abilities: readonly AbilityId[], d: number): number {
  let k = 1;
  if (abilities.includes('lowProfile')) k *= LOW_PROFILE_FACTOR;
  if (abilities.includes('loudmouth')) k *= LOUDMOUTH_FACTOR;
  return d * k;
}

// ───────────────────────────── manualDesync ─────────────────────────────

/** Desync cause reported for a voluntary desync (SimEvent.detail, outcome notes). */
export const MANUAL_DESYNC_CAUSE = 'manual desync';

/**
 * 'ability' event handler for 'manualDesync'. Each firing of the event toggles:
 *
 *   synced self          → voluntary desync: harmless and invulnerable like any desync (DESYNC-07);
 *                          its spark appears where the body was and is HELD there (it does not
 *                          chase the projection, so it cannot resync by itself).
 *   held spark           → release. The live self simply re-syncs in place (its body is the
 *                          projection). A playback self's spark now obeys the ordinary catch-up
 *                          rules (DESYNC-02..05), so on replay it rejoins only once it has
 *                          travelled to the projection.
 *   involuntarily desynced (a playback self obstructed before its 'on' press) → its spark is held
 *                          where it is, so the recorded on/off presses stay paired: the next press
 *                          releases it instead of starting a new desync.
 *
 * A reverse pass fires the event again, so it toggles again. A dead playback ghost never gets here
 * (the dispatcher drops its events); the recording ghost may toggle, which only matters in its take.
 */
export function manualDesync(w: World, self: SelfActor, _ev: TapeEvent, _passDir: 1 | -1): void {
  if (self.life === 'ghost') return;
  if (self.sparkHeld) {
    self.sparkHeld = false;
    if (self.live && !self.synced) {
      self.synced = true;
      self.spark = null;
      self.lastValidX = self.pose.x;
      self.lastValidY = self.pose.y;
      w.emit({ type: 'resync', x: self.pose.x, y: self.pose.y, tape: self.index, detail: MANUAL_DESYNC_CAUSE });
      w.log.resync(self.index, w.s);
    }
    return;
  }
  if (self.synced) {
    w.desync(self, MANUAL_DESYNC_CAUSE);
    self.sparkHeld = !self.synced;
    return;
  }
  self.sparkHeld = true;
}

// ───────────────────────────── slideStrike ─────────────────────────────

/** 'slideStrike': momentum multiplier of a swing started straight out of a dodge. */
export const SLIDE_STRIKE_MUL = 1.5;
/** A swing counts as "ending a dodge into a strike" if it starts within this many local ticks of the dodge's end. */
export const SLIDE_STRIKE_WINDOW_TICKS = 8;

/**
 * Momentum multiplier 'slideStrike' gives a recorded swing: SLIDE_STRIKE_MUL when the swing started
 * within SLIDE_STRIKE_WINDOW_TICKS local ticks after a recorded dodge on the same tape finished,
 * else 1. Judged from the tape alone, so record and replay agree. Only on a forward pass: on a
 * reverse pass the body runs backward out of the swing into the dodge, which is not a slide into a
 * strike (MOM-03: direction matters).
 */
export function slideStrikeFactor(w: World, self: SelfActor, ev: TapeEvent, passDir: 1 | -1): number {
  if (passDir !== 1 || (ev.kind !== 'light' && ev.kind !== 'heavy')) return 1;
  if (!w.loadout.abilities.includes('slideStrike')) return 1;
  const dodgeLen = actionTiming('dodge', w.loadout).commit;
  for (const d of self.tape.events) {
    if (d.kind !== 'dodge' || d.tick >= ev.tick) continue;
    const since = ev.tick - (d.tick + dodgeLen);
    if (since >= 0 && since <= SLIDE_STRIKE_WINDOW_TICKS) return SLIDE_STRIKE_MUL;
  }
  return 1;
}

// ───────────────────────────── parry ─────────────────────────────

/**
 * 'parry': while a heavy swing's hit volume is live, every enemy projectile inside the volume (with
 * a clear line from the swinging self) is reflected straight back the way it came. The reflected
 * shot is a fresh bolt owned by the parrying tape: it no longer hurts selves, it strikes enemies
 * (including the one that fired it) and a kill is credited to that tape. A parry counts as the swing
 * connecting (no 'whiff'). Runs at the start of the projectile phase, before projectiles move, so a
 * bolt is turned before it can touch the self. Only a self that can act parries.
 */
export function parryProjectiles(w: World): void {
  if (!w.loadout.abilities.includes('parry')) return;
  const mel = w.loadout.melee;
  const arc = (mel.arcDeg * Math.PI) / 180;
  const s = w.s;
  for (const self of w.selves) {
    if (!self.canAct || self.swings.length === 0) continue;
    for (const sw of self.swings) {
      if (sw.kind !== 'heavy' || s < sw.start || s >= sw.end) continue;
      const ox = self.pose.x;
      const oy = self.pose.y;
      const list = w.projectiles.list;
      const n = list.length;
      for (let i = 0; i < n; i++) {
        const p = list[i];
        if (!p.alive || !('enemy' in p.owner)) continue;
        if (!inSwingVolume(ox, oy, sw.dir, mel.reach, arc, p.x, p.y, p.radius)) continue;
        if (w.grid.segmentBlocked(ox, oy, p.x, p.y, true)) continue;
        p.alive = false;
        sw.connected = true;
        const dir = wrapAngle(p.dir + Math.PI);
        w.projectiles.spawn(w, {
          owner: { tape: self.index },
          archetype: 'bolt',
          x: p.x,
          y: p.y,
          dir,
          speed: p.speed,
          radius: p.radius,
          range: BOLT_RANGE,
          momentum: p.momentum,
          hitsSelves: false,
          hitsEnemies: true,
        });
        w.emit({ type: 'projectileHit', x: p.x, y: p.y, tape: self.index, id: p.owner.enemy, dir, detail: 'parry' });
      }
    }
  }
}

// ───────────────────────────── beatSight ─────────────────────────────

/** Default look-ahead of ISim.threatBeats, master beats. */
export const BEAT_SIGHT_LOOKAHEAD_BEATS = 8;

/** Is this enemy currently set on attacking someone? (has a live target, or a target within its reach in sight) */
function engaged(w: World, e: EnemyState): boolean {
  if (e.target !== undefined) {
    for (const s of w.selves) if (s.index === e.target && targetable(s)) return true;
  }
  for (const s of w.selves) {
    if (!targetable(s)) continue;
    const d = effectiveDistance(w.loadout.abilities, Math.hypot(s.pose.x - e.x, s.pose.y - e.y));
    if (d <= e.stats.reach && !w.grid.segmentBlocked(e.x, e.y, s.pose.x, s.pose.y, true)) return true;
  }
  return false;
}

/**
 * Master beats of upcoming enemy attacks, from the instant `at` (a substep boundary) up to
 * `lookAheadBeats` beats later, sorted and without duplicates. This is what the 'beatSight' HUD
 * draws on the master ruler; it is a forecast from the current state, not a simulation of the
 * future (the live take's future input is unknown):
 *   - a telegraphing enemy contributes its committed attack instant exactly;
 *   - every other living, awake enemy that is engaged (it has a target, or a self is inside its
 *     reach in line of sight) contributes each instant of its beat grid in the window that it could
 *     still telegraph for (a stagger or knockback slide that outlasts the telegraph start rules a
 *     grid instant out; AI-07 attacks only land on the grid).
 * Sleeping and dead enemies contribute nothing.
 */
export function upcomingAttackBeats(w: World, at: number, lookAheadBeats: number): number[] {
  const end = at + Math.max(0, lookAheadBeats) * w.spb;
  const subs = new Set<number>();
  for (const e of w.enemies) {
    if (!e.alive || !e.awake) continue;
    if (e.state === 'telegraph' && e.attackSub >= at) {
      if (e.attackSub <= end) subs.add(e.attackSub);
    }
    if (!engaged(w, e)) continue;
    const tel = telegraphSubs(w, e);
    const busyUntil = Math.max(e.staggerUntil, at + e.knockSubs);
    for (let g = nextGridSub(w, e, at); g <= end && Number.isFinite(g); g = nextGridSub(w, e, g + 1)) {
      if (e.state === 'telegraph' && e.attackSub >= at && g <= e.attackSub) continue;
      // Its telegraph would have had to start already (or while it is still reeling): it cannot land.
      if (g - tel < at || g - tel < busyUntil) continue;
      subs.add(g);
    }
  }
  return [...subs].sort((a, b) => a - b).map((s) => s / w.spb);
}
