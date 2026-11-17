/**
 * Interpolation between two FrameSnapshots. Everything writes into caller-owned mutable structs so
 * the per-frame path allocates nothing. Pure (no three.js) so it is unit-tested in node.
 */
import type {
  ActorSnap,
  AnimState,
  EnemySnap,
  EnemyType,
  LifeState,
  ProjectileSnap,
  TapeIndex,
} from '../../core/types';
import { clamp01, lerp, lerpAngle } from './math';

/**
 * A step longer than this between two consecutive snapshots is a cut, not motion: a 'repeat' tape
 * jumping back to sample 0, a cinematic seek. Interpolating across it would smear the self across
 * the room, so we snap instead.
 */
export const TELEPORT_DIST = 2.5;

export interface ActorInterp {
  tape: TapeIndex;
  live: boolean;
  x: number;
  y: number;
  facing: number;
  anim: AnimState;
  life: LifeState;
  synced: boolean;
  hasSpark: boolean;
  sparkX: number;
  sparkY: number;
  iframes: boolean;
  /** Fractional local tick of the playhead. */
  tick: number;
  dir: 1 | -1 | 0;
  traversal: number;
  ended: boolean;
  vx: number;
  vy: number;
  /** True when this frame's position is a cut rather than continuous motion. */
  teleported: boolean;
}

export function createActorInterp(): ActorInterp {
  return {
    tape: 0,
    live: false,
    x: 0,
    y: 0,
    facing: 0,
    anim: 'idle',
    life: 'alive',
    synced: true,
    hasSpark: false,
    sparkX: 0,
    sparkY: 0,
    iframes: false,
    tick: 0,
    dir: 1,
    traversal: 0,
    ended: false,
    vx: 0,
    vy: 0,
    teleported: false,
  };
}

/** Index-hinted lookup: snapshot lists are normally in stable order, so try the same slot first. */
export function findActor(list: readonly ActorSnap[], tape: TapeIndex, hint: number): ActorSnap | undefined {
  if (hint >= 0 && hint < list.length && list[hint].tape === tape) return list[hint];
  for (let i = 0; i < list.length; i++) if (list[i].tape === tape) return list[i];
  return undefined;
}

export function findEnemy(list: readonly EnemySnap[], id: string, hint: number): EnemySnap | undefined {
  if (hint >= 0 && hint < list.length && list[hint].id === id) return list[hint];
  for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
  return undefined;
}

export function findProjectile(list: readonly ProjectileSnap[], id: number, hint: number): ProjectileSnap | undefined {
  if (hint >= 0 && hint < list.length && list[hint].id === id) return list[hint];
  for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
  return undefined;
}

/**
 * Interpolate one self. Discrete fields (anim, life, sync, iframes) come from the newer snapshot:
 * a state change is an event, not a blend, and the pose layer cross-fades it on its own clock.
 */
export function interpActor(prev: ActorSnap | undefined, cur: ActorSnap, alpha: number, out: ActorInterp): ActorInterp {
  const a = clamp01(alpha);
  out.tape = cur.tape;
  out.live = cur.live;
  out.anim = cur.anim;
  out.life = cur.life;
  out.synced = cur.synced;
  out.iframes = cur.iframes;
  out.dir = cur.phase.dir;
  out.traversal = cur.phase.traversal;
  out.ended = cur.phase.ended;
  out.vx = cur.vx;
  out.vy = cur.vy;

  const p = prev ?? cur;
  const dx = cur.x - p.x;
  const dy = cur.y - p.y;
  const cut = p !== cur && (p.phase.traversal !== cur.phase.traversal || dx * dx + dy * dy > TELEPORT_DIST * TELEPORT_DIST);
  out.teleported = cut;
  if (cut) {
    out.x = cur.x;
    out.y = cur.y;
    out.facing = cur.facing;
    out.tick = cur.phase.tick;
  } else {
    out.x = lerp(p.x, cur.x, a);
    out.y = lerp(p.y, cur.y, a);
    out.facing = lerpAngle(p.facing, cur.facing, a);
    out.tick = lerp(p.phase.tick, cur.phase.tick, a);
    out.vx = lerp(p.vx, cur.vx, a);
    out.vy = lerp(p.vy, cur.vy, a);
  }

  // The spark never teleports (ARCHITECTURE: "a desynced self's spark does not — it must travel"),
  // so it is interpolated even when the projection cut.
  if (cur.spark) {
    out.hasSpark = true;
    if (p.spark) {
      out.sparkX = lerp(p.spark.x, cur.spark.x, a);
      out.sparkY = lerp(p.spark.y, cur.spark.y, a);
    } else {
      out.sparkX = cur.spark.x;
      out.sparkY = cur.spark.y;
    }
  } else {
    out.hasSpark = false;
  }
  return out;
}

export interface EnemyInterp {
  id: string;
  type: EnemyType;
  x: number;
  y: number;
  facing: number;
  hp: number;
  maxHp: number;
  alive: boolean;
  state: EnemySnap['state'];
  stateT: number;
  hasTarget: boolean;
  target: TapeIndex;
  shield: boolean;
  bossPhase: number;
  bossRecall: boolean;
  /** Tape whose memory the boss is acting on, or -1. */
  recallTape: number;
  teleported: boolean;
}

export function createEnemyInterp(): EnemyInterp {
  return {
    id: '',
    type: 'grunt',
    x: 0,
    y: 0,
    facing: 0,
    hp: 1,
    maxHp: 1,
    alive: true,
    state: 'idle',
    stateT: 0,
    hasTarget: false,
    target: 0,
    shield: false,
    bossPhase: 0,
    bossRecall: false,
    recallTape: -1,
    teleported: false,
  };
}

export function interpEnemy(prev: EnemySnap | undefined, cur: EnemySnap, alpha: number, out: EnemyInterp): EnemyInterp {
  const a = clamp01(alpha);
  const p = prev ?? cur;
  out.id = cur.id;
  out.type = cur.type;
  out.hp = cur.hp;
  out.maxHp = cur.maxHp;
  out.alive = cur.alive;
  out.state = cur.state;
  out.hasTarget = cur.target !== undefined;
  out.target = cur.target ?? 0;
  out.shield = cur.shield === true;
  out.bossPhase = cur.bossPhase ?? 0;
  out.bossRecall = cur.bossRecall === true;
  out.recallTape = out.bossRecall && cur.bossRecallTape !== undefined ? cur.bossRecallTape : -1;
  const dx = cur.x - p.x;
  const dy = cur.y - p.y;
  // Knockback is fast but continuous; only a genuine jump (cinematic seek) is treated as a cut.
  const cut = p !== cur && dx * dx + dy * dy > TELEPORT_DIST * TELEPORT_DIST * 4;
  out.teleported = cut;
  if (cut) {
    out.x = cur.x;
    out.y = cur.y;
    out.facing = cur.facing;
  } else {
    out.x = lerp(p.x, cur.x, a);
    out.y = lerp(p.y, cur.y, a);
    out.facing = lerpAngle(p.facing, cur.facing, a);
  }
  // stateT only means something within one state; across a state change take the new value.
  out.stateT = p.state === cur.state && cur.stateT >= p.stateT ? lerp(p.stateT, cur.stateT, a) : cur.stateT;
  return out;
}

export interface ProjectileInterp {
  id: number;
  x: number;
  y: number;
  z: number;
  dir: number;
  /** True on the first frame this projectile is drawn (no previous sample). */
  fresh: boolean;
}

export function createProjectileInterp(): ProjectileInterp {
  return { id: 0, x: 0, y: 0, z: 0, dir: 0, fresh: true };
}

export function interpProjectile(
  prev: ProjectileSnap | undefined,
  cur: ProjectileSnap,
  alpha: number,
  out: ProjectileInterp,
): ProjectileInterp {
  const a = clamp01(alpha);
  out.id = cur.id;
  out.fresh = prev === undefined;
  const p = prev ?? cur;
  out.x = lerp(p.x, cur.x, a);
  out.y = lerp(p.y, cur.y, a);
  out.z = lerp(p.z, cur.z, a);
  out.dir = lerpAngle(p.dir, cur.dir, a);
  return out;
}
