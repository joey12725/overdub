/**
 * Shared machinery for the player's ranged weapons (WEAPON-01..03, MISSILE-01..04).
 *
 * The rule is "fixed trigger, simulated projectile" (Revision 1): a tape records when, where and in
 * which direction it fired; everything after the launch is a world object simulated in master time
 * against the current run. Every number comes from the equipped RangedWeaponDef, so an archetype
 * file only decides how its projectile moves and what stops it.
 *
 * Momentum. A projectile delivers `def.impact` through the same momentum → damage / knockback /
 * stagger arithmetic as melee (tuning.ts strikeDamage / strikeKnockback / strikeStagger) and the
 * loadout's damage / knockback / stagger modifiers. Tape speed is deliberately NOT multiplied in:
 * a melee swing's momentum carries the tape speed because the swing and the body move in the
 * self's local time (MOM-01), but a projectile's speed (RangedWeaponDef.speed) is already a
 * master-time property of the object once it leaves the weapon. Multiplying again would count tape
 * speed for something that no longer lives on the tape. The ranged weapon has no efficiency fields
 * of its own, so its efficiencies are 1; the melee weapon's efficiencies never touch a shot.
 */
import type { SelfActor } from '../actors';
import type { EnemyStrike } from '../combat';
import type { EnemyState } from '../enemies/types';
import type { Grid } from '../grid';
import type { HitVerdict, Projectile, SpawnSpec } from '../projectiles';
import type { World } from '../sim';
import { SELF_SHOT_RADIUS, strikeDamage, strikeKnockback, strikeStagger } from '../tuning';
import type { RangedArchetype, RangedWeaponDef } from '../types';

/** Momentum → effect multiplier for projectiles (RangedWeaponDef has no efficiency fields). */
export const RANGED_EFFICIENCY = 1;

/** Arc shells and phase shots stop this far inside the map edge, so they never leave the grid. */
export const EDGE_MARGIN = 1e-3;

/** Projectile speed of the equipped weapon, tiles per master second (StatMods.projectileSpeed applies). */
export function shotSpeed(w: World): number {
  return w.loadout.ranged.speed * w.loadout.mods.projectileSpeed;
}

/** Collision radius of each projectile of a weapon, tiles. */
export function shotRadius(def: RangedWeaponDef): number {
  return def.radius !== undefined && def.radius > 0 ? def.radius : SELF_SHOT_RADIUS;
}

/** Enemies one projectile may pass through, from the weapon definition (0 = stops at the first). */
export function pierceCount(def: RangedWeaponDef): number {
  return def.pierce > 0 ? Math.floor(def.pierce) : 0;
}

/**
 * The spawn spec of one of a self's shots, filled from the equipped weapon. Projectiles start at the
 * self's centre (its recorded position at the launch instant, PLAY-01): a muzzle offset could poke
 * through a wall the self is standing against.
 */
export function selfShot(w: World, self: SelfActor, archetype: RangedArchetype, dir: number, passDir: 1 | -1): SpawnSpec {
  const def = w.loadout.ranged;
  return {
    owner: { tape: self.index },
    archetype,
    x: self.pose.x,
    y: self.pose.y,
    dir,
    speed: shotSpeed(w),
    radius: shotRadius(def),
    range: def.range,
    momentum: def.impact,
    passesWalls: def.passesWalls,
    hitsSelves: false,
    hitsEnemies: true,
    pierce: pierceCount(def),
    passDir,
    data: { blast: def.blast > 0 ? def.blast : 0 },
  };
}

/** A projectile's strike on an enemy: the melee momentum model with ranged efficiencies (module doc). */
export function projectileStrike(w: World, p: Projectile, e: EnemyState, momentum: number, dir: number): EnemyStrike {
  const mods = w.loadout.mods;
  return {
    source: 'tape' in p.owner ? { tape: p.owner.tape } : { enemy: p.owner.enemy },
    kind: p.archetype,
    momentum,
    dir,
    x: e.x,
    y: e.y,
    damage: strikeDamage(momentum, RANGED_EFFICIENCY, mods.damage),
    knockback: strikeKnockback(momentum, RANGED_EFFICIENCY, mods.knockback, mods.knockbackCap, e.stats.mass),
    stagger: strikeStagger(momentum, RANGED_EFFICIENCY, mods.stagger, e.stats.poise),
  };
}

/**
 * Strike every living enemy whose body overlaps a blast of `radius` centred on (x, y), each pushed
 * away from the centre. Walls and closed doors shield an enemy from the blast unless the centre
 * itself sits in a shot-blocking tile (a shell landing on top of a wall bursts over it). Returns how
 * many enemies were caught. `exclude` is an enemy already struck directly by the same projectile.
 */
export function detonate(w: World, p: Projectile, x: number, y: number, radius: number, exclude?: string): number {
  if (!(radius > 0)) return 0;
  const inSolid = w.grid.blocksShot(Math.floor(x), Math.floor(y));
  let n = 0;
  for (const e of w.enemies) {
    if (!e.alive || e.id === exclude) continue;
    const dx = e.x - x;
    const dy = e.y - y;
    const d = Math.hypot(dx, dy);
    if (d > radius + e.stats.radius) continue;
    if (!inSolid && w.grid.segmentBlocked(x, y, e.x, e.y, true)) continue;
    p.struck.add(`enemy:${e.id}`);
    const dir = d > 1e-9 ? Math.atan2(dy, dx) : p.dir;
    w.combat.strikeEnemy(e, projectileStrike(w, p, e, p.momentum, dir));
    n++;
  }
  return n;
}

/**
 * Contact with an enemy for every self projectile that flies straight (missile, pierce, phase,
 * burst): deliver the momentum, then keep going while the weapon may still pierce (NEW-04). A
 * pass-through is announced as its own 'projectileHit'; the stopping hit is announced by flyStraight.
 * A stopping hit bursts the weapon's blast radius around the struck enemy, if it has one.
 */
export function hitEnemyStraight(w: World, p: Projectile, e: EnemyState): HitVerdict {
  p.struck.add(`enemy:${e.id}`);
  w.combat.strikeEnemy(e, projectileStrike(w, p, e, p.momentum, p.dir));
  if (p.pierceLeft > 0) {
    p.pierceLeft--;
    w.emit({ type: 'projectileHit', x: e.x, y: e.y, id: e.id, tape: ownerTape(p), dir: p.dir, detail: `${p.archetype}:pass` });
    return 'pass';
  }
  detonate(w, p, e.x, e.y, p.data.blast ?? 0, e.id);
  return 'stop';
}

/** A straight shot stopping against a wall bursts its blast radius at the impact point. */
export function hitWallStraight(w: World, p: Projectile, x: number, y: number): HitVerdict {
  detonate(w, p, x, y, p.data.blast ?? 0);
  return 'stop';
}

export function ownerTape(p: Projectile): SelfActor['index'] | undefined {
  return 'tape' in p.owner ? p.owner.tape : undefined;
}

/**
 * Distance from (x, y) along `dir` to the edge of the map rectangle [0, cols] × [0, rows]. Infinity
 * never comes back: every direction leaves a finite rectangle.
 */
export function distanceToEdge(grid: Grid, x: number, y: number, dir: number): number {
  const ux = Math.cos(dir);
  const uy = Math.sin(dir);
  let t = Infinity;
  if (ux > 1e-12) t = Math.min(t, (grid.cols - x) / ux);
  else if (ux < -1e-12) t = Math.min(t, -x / ux);
  if (uy > 1e-12) t = Math.min(t, (grid.rows - y) / uy);
  else if (uy < -1e-12) t = Math.min(t, -y / uy);
  return t > 0 ? t : 0;
}
