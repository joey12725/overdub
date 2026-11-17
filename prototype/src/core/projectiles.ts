/**
 * Projectiles: world objects simulated in master time (MISSILE-04, WEAPON-01..03, AI-06).
 *
 * EXTENSION POINTS (adding 'missile' | 'pierce' | 'phase' | 'arc' | 'burst' is purely additive)
 *
 *   registerProjectileArchetype(arch)
 *     An archetype is a ProjectileArchetype keyed by its id. Every hook is optional:
 *       launch(w, self, ev, passDir) → number   SELF weapons only. Called by `launchFromSelf`, the
 *                                               single dispatch point of a self's recorded 'ranged'
 *                                               event, at the weapon's launch tick, only when the
 *                                               self can act (alive or recording ghost, synced;
 *                                               Scenario F). Spawn projectiles with `w.projectiles
 *                                               .spawn(...)` and return how many were spawned; the
 *                                               framework emits the 'fire' event when > 0.
 *       step(w, p)                              Replaces the default straight flight (`flyStraight`)
 *                                               for homing, lobbing… It may call flyStraight itself.
 *       onHitEnemy(w, p, e) → 'stop' | 'pass'   Default: deliver p.momentum as an EnemyStrike, stop.
 *       onHitSelf(w, p, self) → 'stop' | 'pass' Default: pass (no friendly fire; OPEN-10).
 *       onHitWall(w, p, hit) → 'stop' | 'pass'  Default: stop. ('pass' = keep flying, e.g. phase.)
 *       onExpire(w, p)                          Range exhausted (e.g. an arc shell landing).
 *
 *   Projectile flags consulted by flyStraight: passesWalls, hitsSelves, hitsEnemies, radius, range.
 *   Per-projectile scratch lives in `p.data` (plain numbers) and `p.struck` (ids already hit).
 *
 * The player's five weapon archetypes live in src/core/weapons/ (one file each), registered when the
 * sim imports weapons/index.ts. The only archetype implemented here is the enemy 'bolt': straight, blocked by walls and closed
 * doors but not low barriers, kills the first vulnerable self it touches unless that self is inside
 * dodge i-frames (it then flies on through; TEST-21). It never hurts dead ghosts, the recording
 * ghost or desynced selves (passes through them). It also strikes other enemies it meets, so
 * knocking an enemy into a turret's lane matters (MOM-05, Scenario E).
 */
import type { SelfActor } from './actors';
import type { EnemyState } from './enemies/types';
import type { RayHit } from './grid';
import { BASE, ENEMY_SHOT_RADIUS } from './tuning';
import { SUB_HZ, type ProjectileSnap, type RangedArchetype, type TapeEvent, type TapeIndex } from './types';
import type { World } from './sim';

export type ProjectileArchetypeId = ProjectileSnap['archetype'];
export type ProjectileOwner = { tape: TapeIndex } | { enemy: string };

export interface Projectile {
  readonly id: number;
  readonly owner: ProjectileOwner;
  readonly archetype: ProjectileArchetypeId;
  x: number;
  y: number;
  /** Presentation height above the floor (arc shots). */
  z: number;
  /** Heading, radians. */
  dir: number;
  /** Tiles per master second. */
  speed: number;
  /** Collision radius, tiles. */
  radius: number;
  /** Remaining flight distance is range − travelled. */
  range: number;
  travelled: number;
  alive: boolean;
  /** Momentum delivered on hit (same damage/knockback/stagger model as melee). */
  momentum: number;
  passesWalls: boolean;
  hitsSelves: boolean;
  hitsEnemies: boolean;
  /** Enemies this projectile may still pass through after a hit (pierce). */
  pierceLeft: number;
  /** Ids already struck or passed ("enemy:<id>", "self:<index>"), never re-tested. */
  readonly struck: Set<string>;
  /** Missile lock (MISSILE-03). */
  targetId?: string;
  readonly spawnSub: number;
  /** +1 / -1: the tape pass direction of the event that launched it. */
  readonly passDir: 1 | -1;
  readonly data: Record<string, number>;
}

export interface SpawnSpec {
  owner: ProjectileOwner;
  archetype: ProjectileArchetypeId;
  x: number;
  y: number;
  dir: number;
  speed: number;
  radius: number;
  range: number;
  momentum?: number;
  z?: number;
  passesWalls?: boolean;
  hitsSelves?: boolean;
  hitsEnemies?: boolean;
  pierce?: number;
  targetId?: string;
  passDir?: 1 | -1;
  data?: Record<string, number>;
}

export type HitVerdict = 'stop' | 'pass';

export interface ProjectileArchetype {
  readonly id: ProjectileArchetypeId;
  launch?(w: World, self: SelfActor, ev: TapeEvent, passDir: 1 | -1): number;
  step?(w: World, p: Projectile): void;
  onHitEnemy?(w: World, p: Projectile, e: EnemyState): HitVerdict;
  onHitSelf?(w: World, p: Projectile, self: SelfActor): HitVerdict;
  onHitWall?(w: World, p: Projectile, hit: RayHit): HitVerdict;
  onExpire?(w: World, p: Projectile): void;
}

const ARCHETYPES = new Map<ProjectileArchetypeId, ProjectileArchetype>();

/** Register (or replace) a projectile archetype. */
export function registerProjectileArchetype(a: ProjectileArchetype): void {
  ARCHETYPES.set(a.id, a);
}

export function getProjectileArchetype(id: ProjectileArchetypeId): ProjectileArchetype | undefined {
  return ARCHETYPES.get(id);
}

export class ProjectileSystem {
  readonly list: Projectile[] = [];
  private nextId = 1;

  spawn(w: World, spec: SpawnSpec): Projectile {
    const p: Projectile = {
      id: this.nextId++,
      owner: spec.owner,
      archetype: spec.archetype,
      x: spec.x,
      y: spec.y,
      z: spec.z ?? 0,
      dir: spec.dir,
      speed: spec.speed,
      radius: spec.radius,
      range: spec.range,
      travelled: 0,
      alive: true,
      momentum: spec.momentum ?? 0,
      passesWalls: spec.passesWalls ?? false,
      hitsSelves: spec.hitsSelves ?? 'enemy' in spec.owner,
      hitsEnemies: spec.hitsEnemies ?? true,
      pierceLeft: spec.pierce ?? 0,
      struck: new Set(),
      targetId: spec.targetId,
      spawnSub: w.s,
      passDir: spec.passDir ?? 1,
      data: { ...spec.data },
    };
    this.list.push(p);
    return p;
  }

  /**
   * ═══ RANGED DISPATCH HOOK ═══ — the single place a self's recorded 'ranged' event becomes world
   * objects. Called by the sim at the event's launch tick, already gated on the self being able to
   * act. With no archetype handler registered for the loadout's weapon this is a no-op that emits
   * nothing.
   */
  launchFromSelf(w: World, self: SelfActor, ev: TapeEvent, passDir: 1 | -1): void {
    const arch = ARCHETYPES.get(w.loadout.ranged.archetype as RangedArchetype);
    if (!arch || !arch.launch) return;
    const n = arch.launch(w, self, ev, passDir);
    if (n > 0) {
      // power = projectiles launched (a burst's pellet count).
      w.emit({ type: 'fire', x: self.pose.x, y: self.pose.y, tape: self.index, dir: ev.dir, power: n, detail: w.loadout.ranged.archetype });
    }
  }

  /** Projectiles phase of a substep: every live projectile in spawn order, then removal of the dead. */
  step(w: World): void {
    const list = this.list;
    for (let i = 0; i < list.length; i++) {
      const p = list[i];
      if (!p.alive) continue;
      const arch = ARCHETYPES.get(p.archetype);
      if (arch?.step) arch.step(w, p);
      else flyStraight(w, p);
    }
    let j = 0;
    for (let i = 0; i < list.length; i++) if (list[i].alive) list[j++] = list[i];
    list.length = j;
  }

  snapshot(): ProjectileSnap[] {
    return this.list.map((p) => {
      const snap: ProjectileSnap = {
        id: p.id,
        owner: 'tape' in p.owner ? { tape: p.owner.tape } : { enemy: p.owner.enemy },
        archetype: p.archetype,
        x: p.x,
        y: p.y,
        z: p.z,
        dir: p.dir,
      };
      if (p.targetId !== undefined) snap.targetId = p.targetId;
      return snap;
    });
  }
}

// ───────────────────────────── default flight ─────────────────────────────

interface Contact {
  t: number;
  /** 0 = self, 1 = enemy (ties: selves first, then lower index / entity order). */
  order: number;
  index: number;
  self?: SelfActor;
  enemy?: EnemyState;
}

/** Earliest t ∈ [0, len] at which a point moving along (ux, uy) from (x0, y0) comes within R of (cx, cy). */
function sweepCircle(x0: number, y0: number, ux: number, uy: number, len: number, cx: number, cy: number, R: number): number {
  const fx = x0 - cx;
  const fy = y0 - cy;
  const c = fx * fx + fy * fy - R * R;
  if (c <= 0) return 0;
  const b = fx * ux + fy * uy;
  if (b >= 0) return -1;
  const disc = b * b - c;
  if (disc < 0) return -1;
  const t = -b - Math.sqrt(disc);
  return t >= 0 && t <= len ? t : -1;
}

/**
 * Move a projectile straight along `p.dir` for one substep, resolving body contacts in the order
 * they happen along the path and stopping at walls (unless passesWalls). Archetype hooks decide
 * whether each contact stops it. `dist` defaults to speed / SUB_HZ.
 */
export function flyStraight(w: World, p: Projectile, dist = p.speed / SUB_HZ): void {
  const arch = ARCHETYPES.get(p.archetype);
  const remaining = p.range - p.travelled;
  const len = Math.min(dist, Math.max(0, remaining));
  const ux = Math.cos(p.dir);
  const uy = Math.sin(p.dir);

  let wallT = Infinity;
  let wall: RayHit | null = null;
  if (!p.passesWalls && len > 0) {
    const hit = w.grid.raycast(p.x, p.y, ux, uy, len, true);
    if (hit.hit) {
      wallT = hit.dist;
      wall = { ...hit };
    }
  } else if (!p.passesWalls && w.grid.blocksShot(Math.floor(p.x), Math.floor(p.y))) {
    wallT = 0;
    wall = { hit: true, dist: 0, x: p.x, y: p.y, c: Math.floor(p.x), r: Math.floor(p.y), nx: 0, ny: 0 };
  }

  const contacts: Contact[] = [];
  const reach = Math.min(len, wallT);
  if (p.hitsSelves) {
    for (const s of w.selves) {
      if (s.life === 'ghost' || p.struck.has(`self:${s.index}`)) continue;
      const t = sweepCircle(p.x, p.y, ux, uy, reach, s.pose.x, s.pose.y, BASE.actorRadius + p.radius);
      if (t >= 0) contacts.push({ t, order: 0, index: s.index, self: s });
    }
  }
  if (p.hitsEnemies) {
    const ownerEnemy = 'enemy' in p.owner ? p.owner.enemy : null;
    for (let i = 0; i < w.enemies.length; i++) {
      const e = w.enemies[i];
      if (!e.alive || e.id === ownerEnemy || p.struck.has(`enemy:${e.id}`)) continue;
      const t = sweepCircle(p.x, p.y, ux, uy, reach, e.x, e.y, e.stats.radius + p.radius);
      if (t >= 0) contacts.push({ t, order: 1, index: i, enemy: e });
    }
  }
  contacts.sort((a, b) => a.t - b.t || a.order - b.order || a.index - b.index);
  for (const c of contacts) {
    let verdict: HitVerdict;
    if (c.self) verdict = arch?.onHitSelf ? arch.onHitSelf(w, p, c.self) : 'pass';
    else verdict = arch?.onHitEnemy ? arch.onHitEnemy(w, p, c.enemy!) : defaultHitEnemy(w, p, c.enemy!);
    if (verdict === 'stop') {
      p.x += ux * c.t;
      p.y += uy * c.t;
      p.travelled += c.t;
      p.alive = false;
      w.emit({ type: 'projectileHit', x: p.x, y: p.y, id: c.enemy?.id, tape: c.self?.index, dir: p.dir, detail: p.archetype });
      return;
    }
  }
  if (wall && wallT <= len) {
    const verdict = arch?.onHitWall ? arch.onHitWall(w, p, wall) : 'stop';
    if (verdict === 'stop') {
      p.x += ux * wallT;
      p.y += uy * wallT;
      p.travelled += wallT;
      p.alive = false;
      w.emit({ type: 'projectileHit', x: p.x, y: p.y, dir: p.dir, detail: `${p.archetype}:wall` });
      return;
    }
  }
  p.x += ux * len;
  p.y += uy * len;
  p.travelled += len;
  if (p.travelled >= p.range - 1e-9) {
    p.alive = false;
    arch?.onExpire?.(w, p);
  }
}

/** Default enemy contact: deliver the projectile's momentum and stop unless it can pierce. */
export function defaultHitEnemy(w: World, p: Projectile, e: EnemyState): HitVerdict {
  p.struck.add(`enemy:${e.id}`);
  w.combat.strikeEnemy(e, {
    source: 'tape' in p.owner ? { tape: p.owner.tape } : { enemy: p.owner.enemy },
    kind: p.archetype,
    momentum: p.momentum,
    dir: p.dir,
    x: e.x,
    y: e.y,
  });
  if (p.pierceLeft > 0) {
    p.pierceLeft--;
    return 'pass';
  }
  return 'stop';
}

// ───────────────────────────── enemy bolt ─────────────────────────────

/** Bolts fly until they hit something; this only bounds runaway bolts in open maps. */
export const BOLT_RANGE = 64;
/** Stagger a bolt inflicts on an enemy it strikes, master seconds. */
export const BOLT_ENEMY_STAGGER = 0.25;

const BOLT: ProjectileArchetype = {
  id: 'bolt',
  onHitSelf(w, p, self) {
    if (!self.vulnerable) return 'pass';
    if (self.inIframes(w.s)) {
      // Dodged: the bolt flies on through and never re-tests this self (TEST-21).
      p.struck.add(`self:${self.index}`);
      return 'pass';
    }
    const owner = 'enemy' in p.owner ? w.enemyById(p.owner.enemy) : undefined;
    const who = owner ? `${owner.type} ${owner.id}` : 'a bolt';
    w.combat.hitSelf({ self, cause: `shot by ${who}`, x: p.x, y: p.y, dir: p.dir });
    return 'stop';
  },
  onHitEnemy(w, p, e) {
    p.struck.add(`enemy:${e.id}`);
    w.combat.strikeEnemy(e, {
      source: 'enemy' in p.owner ? { enemy: p.owner.enemy } : { tape: p.owner.tape },
      kind: 'bolt',
      momentum: 1,
      dir: p.dir,
      x: e.x,
      y: e.y,
      damage: 1,
      knockback: 0,
      stagger: BOLT_ENEMY_STAGGER,
    });
    return 'stop';
  },
};
registerProjectileArchetype(BOLT);

/** Fire a bolt from an enemy's rim along `dir` at the enemy's shot speed. */
export function spawnBolt(w: World, e: EnemyState, dir: number): Projectile {
  const off = e.stats.radius + ENEMY_SHOT_RADIUS + 0.01;
  return w.projectiles.spawn(w, {
    owner: { enemy: e.id },
    archetype: 'bolt',
    x: e.x + Math.cos(dir) * off,
    y: e.y + Math.sin(dir) * off,
    dir,
    speed: e.stats.shotSpeed,
    radius: ENEMY_SHOT_RADIUS,
    range: BOLT_RANGE,
    momentum: 1,
    hitsSelves: true,
    hitsEnemies: true,
  });
}
