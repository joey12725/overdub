/**
 * The outside-the-loop boss (BOSS-01..03, HEALTH-03, AI-04, AI-07).
 *
 * A stationary, anchored colossus with a health bar (EnemyDef.hp, else ENEMY_STATS.boss.hp). It is
 * built so that one self can never beat it and a coordinated group can, and so that what it
 * remembers from committed takes is visible, telegraphed and exploitable.
 *
 * ATTENTION AND ARMOUR (BOSS-03). The boss always watches one self: its attention is the NEAREST
 * targetable self, re-chosen on every beat while it is not committed to an attack (and at once when
 * that self stops being targetable). It turns toward it at BOSS_TURN_RATE. Its front is armour:
 *   a hit does damage only if it comes from a self that is NOT holding its attention, and lands on
 *   its back (the push direction within BOSS_BACK_HALF_ARC of the way it faces).
 * Everything else clangs ('clang', detail 'armour'). So one self can never hurt it — whoever is
 * alone is always the one it watches — and the basic plan is "one self holds its eye up close,
 * another strikes from behind". It is never shoved (anchored); only a hit of at least
 * BOSS_STAGGER_MOMENTUM through the armour staggers it, which cancels whatever it is telegraphing.
 *
 * BASE PATTERN (the bar grid; AI-07). Attacks land on its beat grid (ENEMY_STATS boss: every bar),
 * each announced by a telegraph of telegraphBeats:
 *   - 'cleave' : a wide frontal arc (BOSS_CLEAVE_ARC) of radius + reach at its attention, facing
 *                locked at telegraph start;
 *   - 'volley' : instead of a cleave when its attention is out of cleave range, BOSS_VOLLEY_COUNT
 *                bolts fanned at it (aim locked at telegraph start);
 *   - 'sweep'  : from phase 2, every other attack is a ring of BOSS_SWEEP_SHOTS shockwave shots
 *                (range BOSS_SWEEP_RANGE; walls stop them; i-frames pass through them).
 * PHASES (HEALTH-03). Phase 2 at hp ≤ 2/3 max, phase 3 at hp ≤ 1/3 max. Each change emits
 * 'bossPhase' (power = new phase) and interrupts the current telegraph. Phase 3 attacks twice as
 * often (half the grid period; the telegraph shortens only as much as that requires).
 *
 * MEMORY (BOSS-01, BOSS-02). Given SimConfig.bossMemory — built only from committed tapes
 * (bossMemory.ts) — it pre-empts remembered selves. Each remembered moment (a dwell or an attack;
 * `recallCandidates`) becomes a MEMORY STRIKE planned before the run starts:
 *   - it lands on a whole master beat at the remembered place: for a dwell, on the dwell's second
 *     beat (or the first beat a full telegraph allows), for an attack on the beat nearest to it;
 *   - BOSS_RECALL_TELEGRAPH_BEATS before that it turns to the place, telegraphs and emits
 *     'bossRecall' (tape = the remembered cassette, power = landing beat, detail = 'dwell' |
 *     'attack'); EnemySnap.bossRecall / bossRecallTape / bossRecallAt mark the whole commitment so
 *     the renderer can draw it differently from ordinary reactivity;
 *   - the strike hits every vulnerable self within BOSS_RECALL_RADIUS of the place (walls do not
 *     shelter: it is a memory, not a projectile);
 *   - while it is busy with a memory its attention IS the remembered cassette, so every other self
 *     can strike its back (it is busy punishing tape A's old position while tape C hits it);
 *   - it handles one memory at a time: moments whose telegraph would overlap an earlier planned one
 *     (or its recovery) are skipped, ties going to the earlier beat, then the lower cassette, attacks
 *     before dwells; base attacks never start if they would overlap a memory strike;
 *   - a memory strike whose telegraph start finds the boss staggered is dropped, and a stagger or
 *     phase change during its telegraph cancels it — protecting a committed tape is a tactic.
 * With no memory (the first take) it uses only the base pattern. The plan is computed from the
 * memory once per run and the memory itself is never written, so identical memory always gives an
 * identical fight and a resolve or a replay cannot alter what the boss knows.
 */
import type { EnemyStrike, HitResponse } from '../combat';
import { recallCandidates } from '../bossMemory';
import { registerProjectileArchetype, spawnBolt, type ProjectileArchetype } from '../projectiles';
import { angleDelta, wrapAngle } from '../tape';
import { BASE, strikeDamage, strikeStagger } from '../tuning';
import { SUB_HZ, TAPE_NAMES, type TapeIndex } from '../types';
import type { World } from '../sim';
import { nearestTarget, selfByIndex, setState, targetable, telegraphSubs } from './common';
import { meleeStrike } from './stalker';
import type { EnemyBehaviour, EnemyState } from './types';

/** Turn rate toward its attention, radians per master second. */
export const BOSS_TURN_RATE = 2.4;
/** Half-width of the back arc that armour does not cover, radians (90° = the whole rear half). */
export const BOSS_BACK_HALF_ARC = Math.PI / 2;
/** Total cleave arc, radians. */
export const BOSS_CLEAVE_ARC = (5 * Math.PI) / 6;
/** Bolts in a volley and the angle between neighbours, radians. */
export const BOSS_VOLLEY_COUNT = 3;
export const BOSS_VOLLEY_SPREAD = Math.PI / 12;
/** Sweep ring: shots, range (tiles) and shot radius (tiles; dense enough to leave no gaps in range). */
export const BOSS_SWEEP_SHOTS = 24;
export const BOSS_SWEEP_RANGE = 6;
export const BOSS_SWEEP_RADIUS = 0.35;
/** Recovery after a base attack, master beats. */
export const BOSS_RECOVER_BEATS = 0.5;
/** Memory strikes: telegraph (whole beats, so landings stay on the beat), radius, recovery. */
export const BOSS_RECALL_TELEGRAPH_BEATS = 2;
export const BOSS_RECALL_RADIUS = 1.25;
export const BOSS_RECALL_RECOVER_BEATS = 1;
/** A hit through the armour needs this much momentum to stagger the boss (a 2× standing heavy). */
export const BOSS_STAGGER_MOMENTUM = 4;

type BossMode = '' | 'cleave' | 'volley' | 'sweep' | 'recall';

/** One planned memory strike. */
interface RecallPlan {
  tape: TapeIndex;
  reason: 'dwell' | 'attack';
  startSub: number;
  landSub: number;
  x: number;
  y: number;
}

/** Per-run plan derived from the memory (kept off EnemyState.mem, which holds scalars only). */
interface BossRuntime {
  recalls: RecallPlan[];
  /** Index of the next memory strike that has not started (or been dropped). */
  next: number;
}

const RUNTIME = new WeakMap<EnemyState, BossRuntime>();

function runtime(e: EnemyState): BossRuntime {
  let rt = RUNTIME.get(e);
  if (!rt) {
    rt = { recalls: [], next: 0 };
    RUNTIME.set(e, rt);
  }
  return rt;
}

/** Boss phase for a hit-point total: 1, 2 at ≤ 2/3 of max, 3 at ≤ 1/3 of max. */
export function bossPhaseFor(hp: number, maxHp: number): number {
  if (hp * 3 <= maxHp) return 3;
  if (hp * 3 <= maxHp * 2) return 2;
  return 1;
}

/** What it is committed to. Only a telegraph or its recovery is a commitment (a stagger ends it). */
function mode(e: EnemyState): BossMode {
  if (e.state !== 'telegraph' && e.state !== 'attack') return '';
  return (e.mem.mode as BossMode | undefined) ?? '';
}

function cleaveReach(e: EnemyState): number {
  return e.stats.radius + e.stats.reach;
}

function recoverSubs(w: World): number {
  return Math.round(BOSS_RECOVER_BEATS * w.spb);
}

function recallRecoverSubs(w: World): number {
  return Math.round(BOSS_RECALL_RECOVER_BEATS * w.spb);
}

/** Base attack grid period in substeps for the current phase (phase 3 halves it). */
function basePeriod(w: World, e: EnemyState): number {
  const p = Math.round(e.every * w.spb);
  return (e.mem.phase as number) >= 3 ? Math.max(1, Math.round(p / 2)) : p;
}

function baseTelegraph(w: World, e: EnemyState): number {
  return Math.max(0, Math.min(telegraphSubs(w, e), basePeriod(w, e) - recoverSubs(w)));
}

/** Index of the base attack landing on `sub`, or -1 when `sub` is not on the grid. */
function baseAttackIndex(w: World, e: EnemyState, sub: number): number {
  const p = basePeriod(w, e);
  if (!(p > 0)) return -1;
  const off = Math.round(e.offset * w.spb);
  const r = (((sub - off) % p) + p) % p;
  return r === 0 ? Math.floor((sub - off) / p) : -1;
}

/** Who holds the boss's attention right now (the remembered cassette during a memory strike). */
export function bossAttention(w: World, e: EnemyState): TapeIndex | undefined {
  if (mode(e) === 'recall') return e.mem.recallTape as TapeIndex;
  const t = selfByIndex(w, e.target);
  return t && targetable(t) ? t.index : undefined;
}

function retarget(w: World, e: EnemyState): void {
  const t = nearestTarget(w, e.x, e.y);
  e.target = t ? t.index : undefined;
}

/** Plan the run's memory strikes from the (read-only) memory. */
function planRecalls(w: World): RecallPlan[] {
  const out: RecallPlan[] = [];
  const telBeats = Math.ceil(BOSS_RECALL_TELEGRAPH_BEATS);
  const tel = telBeats * w.spb;
  const rec = recallRecoverSubs(w);
  let busyUntil = -Infinity;
  for (const c of recallCandidates(w.bossMemory)) {
    const landBeat = c.reason === 'dwell' ? Math.max(c.beat + 1, telBeats) : c.beat;
    if (landBeat > c.lastBeat && c.reason === 'dwell') continue;
    const landSub = landBeat * w.spb;
    const startSub = landSub - tel;
    if (startSub < 0 || landSub >= w.horizonSubs) continue;
    if (startSub < busyUntil) continue;
    out.push({ tape: c.tape, reason: c.reason, startSub, landSub, x: c.x, y: c.y });
    busyUntil = landSub + rec;
  }
  return out;
}

/** Would an attack occupying substeps [a, b) collide with a memory strike still to come? */
function clashesWithRecall(rt: BossRuntime, a: number, b: number, rec: number): boolean {
  for (let i = rt.next; i < rt.recalls.length; i++) {
    const r = rt.recalls[i];
    if (r.startSub >= b) break;
    if (r.landSub + rec > a) return true;
  }
  return false;
}

function cancelTelegraph(w: World, e: EnemyState): void {
  if (e.state !== 'telegraph') return;
  e.attackSub = -1;
  e.mem.mode = '';
  setState(e, 'idle', w.s, w.s);
}

function startRecall(w: World, e: EnemyState, r: RecallPlan): void {
  e.mem.mode = 'recall';
  e.mem.recallTape = r.tape;
  e.mem.recallX = r.x;
  e.mem.recallY = r.y;
  e.facing = Math.atan2(r.y - e.y, r.x - e.x);
  e.attackSub = r.landSub;
  setState(e, 'telegraph', w.s, r.landSub);
  const landBeat = r.landSub / w.spb;
  w.emit({ type: 'bossRecall', x: r.x, y: r.y, id: e.id, tape: r.tape, dir: e.facing, power: landBeat, detail: r.reason });
  w.emit({ type: 'enemyTelegraph', x: r.x, y: r.y, id: e.id, tape: r.tape, dir: e.facing, detail: 'recall' });
}

function land(w: World, e: EnemyState): void {
  const m = mode(e);
  const s = w.s;
  e.attackSub = -1;
  if (m === 'recall') {
    const x = e.mem.recallX as number;
    const y = e.mem.recallY as number;
    const tape = e.mem.recallTape as TapeIndex;
    const reach = BOSS_RECALL_RADIUS + BASE.actorRadius;
    for (const self of w.selves) {
      if (!targetable(self)) continue;
      if (Math.hypot(self.pose.x - x, self.pose.y - y) > reach) continue;
      w.combat.hitSelf({ self, cause: `struck by boss ${e.id} (remembering Tape ${TAPE_NAMES[tape]})`, x, y, dir: e.facing });
    }
    w.emit({ type: 'enemyAttack', x, y, id: e.id, tape, dir: e.facing, detail: 'recall' });
    setState(e, 'attack', s, s + recallRecoverSubs(w));
    return;
  }
  if (m === 'cleave') {
    meleeStrike(w, e, cleaveReach(e), BOSS_CLEAVE_ARC, 'cleave');
  } else if (m === 'volley') {
    const half = (BOSS_VOLLEY_COUNT - 1) / 2;
    for (let i = 0; i < BOSS_VOLLEY_COUNT; i++) spawnBolt(w, e, wrapAngle(e.facing + (i - half) * BOSS_VOLLEY_SPREAD));
    w.emit({ type: 'enemyShot', x: e.x, y: e.y, id: e.id, tape: e.target, dir: e.facing, detail: 'volley' });
  } else if (m === 'sweep') {
    spawnSweep(w, e);
    w.emit({ type: 'enemyAttack', x: e.x, y: e.y, id: e.id, dir: e.facing, detail: 'sweep' });
  }
  setState(e, 'attack', s, s + recoverSubs(w));
}

// ───────────────────────────── sweep shockwave ─────────────────────────────

/**
 * 'shock' — the sweep's ring segments. Like a bolt against selves (kills the vulnerable, passes
 * through i-frames, dead ghosts and desynced selves) but it never touches enemies; walls stop it.
 */
const SHOCK: ProjectileArchetype = {
  id: 'shock',
  onHitSelf(w, p, self) {
    if (!self.vulnerable) return 'pass';
    if (self.inIframes(w.s)) {
      p.struck.add(`self:${self.index}`);
      return 'pass';
    }
    const owner = 'enemy' in p.owner ? p.owner.enemy : '?';
    w.combat.hitSelf({ self, cause: `swept by boss ${owner}`, x: p.x, y: p.y, dir: p.dir });
    return 'stop';
  },
};
registerProjectileArchetype(SHOCK);

function spawnSweep(w: World, e: EnemyState): void {
  const off = e.stats.radius + BOSS_SWEEP_RADIUS + 0.01;
  for (let i = 0; i < BOSS_SWEEP_SHOTS; i++) {
    const dir = wrapAngle(e.facing + (i * 2 * Math.PI) / BOSS_SWEEP_SHOTS);
    w.projectiles.spawn(w, {
      owner: { enemy: e.id },
      archetype: 'shock',
      x: e.x + Math.cos(dir) * off,
      y: e.y + Math.sin(dir) * off,
      dir,
      speed: e.stats.shotSpeed,
      radius: BOSS_SWEEP_RADIUS,
      range: BOSS_SWEEP_RANGE - off,
      hitsSelves: true,
      hitsEnemies: false,
    });
  }
}

// ───────────────────────────── behaviour ─────────────────────────────

export const BOSS: EnemyBehaviour = {
  type: 'boss',
  heavyBody: true,

  init(w, e) {
    e.mem.phase = 1;
    e.mem.mode = '';
    e.mem.recallTape = -1;
    RUNTIME.set(e, { recalls: planRecalls(w), next: 0 });
  },

  onBeat(w, e) {
    if (e.state === 'telegraph' || e.state === 'attack') return;
    retarget(w, e);
  },

  step(w, e) {
    const s = w.s;
    const rt = runtime(e);
    // A stagger ends a telegraph from outside (framework): forget what it was going to do.
    if (e.state !== 'telegraph' && e.state !== 'attack') e.mem.mode = '';

    if (e.state === 'telegraph') {
      if (s >= e.attackSub) land(w, e);
      return;
    }
    if (e.state === 'attack') {
      if (s < e.stateEnd) return;
      e.mem.mode = '';
      setState(e, 'idle', s, s);
    }

    // Memory strikes whose start passed while it was staggered or busy are dropped, not delayed:
    // a late memory strike would land off its remembered beat.
    while (rt.next < rt.recalls.length && rt.recalls[rt.next].startSub < s) rt.next++;
    if (rt.next < rt.recalls.length && rt.recalls[rt.next].startSub === s) {
      startRecall(w, e, rt.recalls[rt.next]);
      rt.next++;
      return;
    }

    let target = selfByIndex(w, e.target);
    if (!target || !targetable(target)) {
      retarget(w, e);
      target = selfByIndex(w, e.target);
    }
    if (target) {
      const want = Math.atan2(target.pose.y - e.y, target.pose.x - e.x);
      const d = angleDelta(e.facing, want);
      const maxTurn = BOSS_TURN_RATE / SUB_HZ;
      e.facing = wrapAngle(e.facing + (Math.abs(d) <= maxTurn ? d : Math.sign(d) * maxTurn));
    }

    const tel = baseTelegraph(w, e);
    const k = baseAttackIndex(w, e, s + tel);
    if (k < 0 || s + tel <= 0) return;
    if (clashesWithRecall(rt, s, s + tel + recoverSubs(w), recallRecoverSubs(w))) return;
    let next: BossMode;
    if ((e.mem.phase as number) >= 2 && (k & 1) === 1) {
      next = 'sweep';
    } else if (target && Math.hypot(target.pose.x - e.x, target.pose.y - e.y) > cleaveReach(e) + BASE.actorRadius) {
      next = 'volley';
    } else {
      next = 'cleave';
    }
    if (target && next !== 'sweep') e.facing = Math.atan2(target.pose.y - e.y, target.pose.x - e.x);
    e.mem.mode = next;
    e.attackSub = s + tel;
    setState(e, 'telegraph', s, s + tel);
    w.emit({ type: 'enemyTelegraph', x: e.x, y: e.y, id: e.id, tape: target?.index, dir: e.facing, detail: next });
    if (tel === 0) land(w, e);
  },

  onHit(w: World, e: EnemyState, strike: EnemyStrike): HitResponse {
    if (!('tape' in strike.source)) return { kind: 'block', reason: 'armour' };
    if (strike.source.tape === bossAttention(w, e)) return { kind: 'block', reason: 'armour' };
    if (Math.abs(angleDelta(e.facing, strike.dir)) > BOSS_BACK_HALF_ARC) return { kind: 'block', reason: 'armour' };
    const mel = w.loadout.melee;
    const mods = w.loadout.mods;
    const damage = strike.damage ?? strikeDamage(strike.momentum, mel.damageEff, mods.damage);
    const stagger = strike.momentum >= BOSS_STAGGER_MOMENTUM ? (strike.stagger ?? strikeStagger(strike.momentum, mel.staggerEff, mods.stagger, e.stats.poise)) : 0;
    const after = e.hp - damage;
    if (after > 0) {
      const phase = bossPhaseFor(after, e.maxHp);
      const was = e.mem.phase as number;
      if (phase > was) {
        for (let p = was + 1; p <= phase; p++) {
          w.emit({ type: 'bossPhase', x: e.x, y: e.y, id: e.id, tape: strike.source.tape, power: p, detail: `phase ${p}` });
        }
        e.mem.phase = phase;
        cancelTelegraph(w, e);
      }
    }
    return { kind: 'replace', strike: { ...strike, damage, knockback: 0, stagger } };
  },

  onDeath(_w, e) {
    e.mem.mode = '';
  },

  snapshot(_w, e, snap) {
    snap.bossPhase = e.mem.phase as number;
    const recalling = e.alive && mode(e) === 'recall';
    snap.bossRecall = recalling;
    if (recalling) {
      snap.bossRecallTape = e.mem.recallTape as TapeIndex;
      snap.bossRecallAt = { x: e.mem.recallX as number, y: e.mem.recallY as number };
    }
  },
};
