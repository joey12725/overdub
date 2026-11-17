class_name ActorInterp
extends RefCounted
## Interpolation between two FrameSnapshots (prototype render/actors/interp.ts). Everything writes
## into caller-owned objects so the per-frame path allocates nothing. Pure (no nodes): unit-tested.
##
## Rules kept from the prototype:
##  - discrete fields (anim, life, sync, i-frames) come from the newer snapshot; a state change is an
##    event, not a blend (the pose layer cross-fades it on its own clock);
##  - facing interpolates along the shortest arc;
##  - a jump longer than TELEPORT_DIST, or a change of tape traversal (a 'repeat' cut back to sample
##    0, a reverse turn), is a cut: the projection snaps instead of smearing across the room;
##  - the recovery spark never teleports (ARCHITECTURE: "a desynced self's spark does not - it must
##    travel"), so it is interpolated even when the projection cut.

## A step longer than this between consecutive snapshots is a cut, not motion (tiles).
const TELEPORT_DIST: float = 2.5
## Enemies are knocked back fast but continuously; only a far larger jump (a seek) is a cut.
const ENEMY_TELEPORT_DIST: float = TELEPORT_DIST * 2.0


## One self, interpolated.
class SelfFrame:
	extends RefCounted
	var tape: int = 0
	var live: bool = false
	var x: float = 0.0
	var y: float = 0.0
	var facing: float = 0.0
	var anim: StringName = AnimState.IDLE
	var life: int = OD.LifeState.ALIVE
	var synced: bool = true
	var has_spark: bool = false
	var spark_x: float = 0.0
	var spark_y: float = 0.0
	var iframes: bool = false
	## Fractional local tick of the playhead.
	var tick: float = 0.0
	var dir: int = 1
	var traversal: int = 0
	var ended: bool = false
	var vx: float = 0.0
	var vy: float = 0.0
	## True when this frame's position is a cut rather than continuous motion.
	var teleported: bool = false


## One enemy, interpolated.
class EnemyFrame:
	extends RefCounted
	var id: String = ""
	var type: StringName = EnemyType.GRUNT
	var x: float = 0.0
	var y: float = 0.0
	var facing: float = 0.0
	var hp: int = 1
	var max_hp: int = 1
	var alive: bool = true
	var state: StringName = EnemyStateName.IDLE
	var state_t: float = 0.0
	var target: int = -1
	var shield: bool = false
	var has_shield: bool = false
	var boss_phase: int = 0
	var boss_recall: bool = false
	## Tape whose memory the boss acts on, or -1.
	var recall_tape: int = -1
	var has_recall_at: bool = false
	var recall_x: float = 0.0
	var recall_y: float = 0.0
	var teleported: bool = false


## One projectile, interpolated.
class ShotFrame:
	extends RefCounted
	var id: int = 0
	var x: float = 0.0
	var y: float = 0.0
	var z: float = 0.0
	var dir: float = 0.0
	## True on the first frame this projectile is drawn (no previous sample).
	var fresh: bool = true


# ───────────────────────────── lookups ─────────────────────────────

## Index-hinted lookup: snapshot lists are normally in stable order, so try the same slot first.
static func find_actor(list: Array[ActorSnap], tape: int, hint: int) -> ActorSnap:
	if hint >= 0 and hint < list.size() and list[hint].tape == tape:
		return list[hint]
	for a: ActorSnap in list:
		if a.tape == tape:
			return a
	return null


static func find_enemy(list: Array[EnemySnap], id: String, hint: int) -> EnemySnap:
	if hint >= 0 and hint < list.size() and list[hint].id == id:
		return list[hint]
	for e: EnemySnap in list:
		if e.id == id:
			return e
	return null


static func find_projectile(list: Array[ProjectileSnap], id: int, hint: int) -> ProjectileSnap:
	if hint >= 0 and hint < list.size() and list[hint].id == id:
		return list[hint]
	for p: ProjectileSnap in list:
		if p.id == id:
			return p
	return null


# ───────────────────────────── interpolation ─────────────────────────────

## Interpolate one self from `prev` (may be null) to `cur` by `alpha`, into `out`.
static func interp_actor(prev: ActorSnap, cur: ActorSnap, alpha: float, out: SelfFrame) -> SelfFrame:
	var a := ActorMath.clamp01(alpha)
	out.tape = cur.tape
	out.live = cur.live
	out.anim = cur.anim
	out.life = cur.life
	out.synced = cur.synced
	out.iframes = cur.iframes
	out.dir = cur.phase.dir
	out.traversal = cur.phase.traversal
	out.ended = cur.phase.ended
	out.vx = cur.vx
	out.vy = cur.vy
	var p: ActorSnap = prev if prev != null else cur
	var dx := cur.x - p.x
	var dy := cur.y - p.y
	var cut := p != cur and (p.phase.traversal != cur.phase.traversal or dx * dx + dy * dy > TELEPORT_DIST * TELEPORT_DIST)
	out.teleported = cut
	if cut:
		out.x = cur.x
		out.y = cur.y
		out.facing = cur.facing
		out.tick = cur.phase.tick
	else:
		out.x = lerpf(p.x, cur.x, a)
		out.y = lerpf(p.y, cur.y, a)
		out.facing = ActorMath.lerp_angle_short(p.facing, cur.facing, a)
		out.tick = lerpf(p.phase.tick, cur.phase.tick, a)
		out.vx = lerpf(p.vx, cur.vx, a)
		out.vy = lerpf(p.vy, cur.vy, a)
	if cur.has_spark:
		out.has_spark = true
		if p.has_spark:
			out.spark_x = lerpf(p.spark.x, cur.spark.x, a)
			out.spark_y = lerpf(p.spark.y, cur.spark.y, a)
		else:
			out.spark_x = cur.spark.x
			out.spark_y = cur.spark.y
	else:
		out.has_spark = false
	return out


static func interp_enemy(prev: EnemySnap, cur: EnemySnap, alpha: float, out: EnemyFrame) -> EnemyFrame:
	var a := ActorMath.clamp01(alpha)
	var p: EnemySnap = prev if prev != null else cur
	out.id = cur.id
	out.type = cur.type
	out.hp = cur.hp
	out.max_hp = cur.max_hp
	out.alive = cur.alive
	out.state = cur.state
	out.target = cur.target
	out.shield = cur.shield
	out.has_shield = cur.has_shield
	out.boss_phase = maxi(0, cur.boss_phase)
	out.boss_recall = cur.boss_recall
	out.recall_tape = cur.boss_recall_tape if cur.boss_recall else -1
	out.has_recall_at = cur.boss_recall and cur.has_boss_recall_at
	out.recall_x = cur.boss_recall_at.x
	out.recall_y = cur.boss_recall_at.y
	var dx := cur.x - p.x
	var dy := cur.y - p.y
	var cut := p != cur and dx * dx + dy * dy > ENEMY_TELEPORT_DIST * ENEMY_TELEPORT_DIST
	out.teleported = cut
	if cut:
		out.x = cur.x
		out.y = cur.y
		out.facing = cur.facing
	else:
		out.x = lerpf(p.x, cur.x, a)
		out.y = lerpf(p.y, cur.y, a)
		out.facing = ActorMath.lerp_angle_short(p.facing, cur.facing, a)
	# state_t only means something within one state; across a state change take the new value.
	if p.state == cur.state and cur.state_t >= p.state_t:
		out.state_t = lerpf(p.state_t, cur.state_t, a)
	else:
		out.state_t = cur.state_t
	return out


static func interp_projectile(prev: ProjectileSnap, cur: ProjectileSnap, alpha: float, out: ShotFrame) -> ShotFrame:
	var a := ActorMath.clamp01(alpha)
	out.id = cur.id
	out.fresh = prev == null
	var p: ProjectileSnap = prev if prev != null else cur
	out.x = lerpf(p.x, cur.x, a)
	out.y = lerpf(p.y, cur.y, a)
	out.z = lerpf(p.z, cur.z, a)
	out.dir = ActorMath.lerp_angle_short(p.dir, cur.dir, a)
	return out
