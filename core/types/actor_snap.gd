class_name ActorSnap
extends RefCounted
## One self at one instant (types.ts ActorSnap).

## TapeIndex 0..3.
var tape: int = 0
## True for the self currently under live control.
var live: bool = false
## Projection position: always the recorded/intended pose.
var x: float = 0.0
var y: float = 0.0
var facing: float = 0.0
## AnimState.*
var anim: StringName = AnimState.IDLE
## OD.LifeState.
var life: int = OD.LifeState.ALIVE
## False while desynchronised (DESYNC-07): harmless, invulnerable, cannot operate mechanisms.
var synced: bool = true
## Recovery spark position while desynced (DESYNC-02). Valid only when has_spark.
var spark: Vector2 = Vector2.ZERO
var has_spark: bool = false
## True while dodge invulnerability is active.
var iframes: bool = false
## Playhead on this actor's tape.
var phase: TapePhase = TapePhase.new()
## Master-space velocity in tiles per master second (for animation lean / motion trails).
var vx: float = 0.0
var vy: float = 0.0


func copy() -> ActorSnap:
	var o := ActorSnap.new()
	o.tape = tape
	o.live = live
	o.x = x
	o.y = y
	o.facing = facing
	o.anim = anim
	o.life = life
	o.synced = synced
	o.spark = spark
	o.has_spark = has_spark
	o.iframes = iframes
	o.phase = phase.copy()
	o.vx = vx
	o.vy = vy
	return o


static func from_dict(d: Dictionary) -> ActorSnap:
	var o := ActorSnap.new()
	o.tape = ODJson.integer(d, "tape")
	o.live = ODJson.boolean(d, "live")
	o.x = ODJson.num(d, "x")
	o.y = ODJson.num(d, "y")
	o.facing = ODJson.num(d, "facing")
	o.anim = ODJson.sname(d, "anim", AnimState.IDLE)
	o.life = maxi(0, OD.life_state_from_name(ODJson.string(d, "life", "alive")))
	o.synced = ODJson.boolean(d, "synced", true)
	o.has_spark = d.get("spark") is Dictionary
	o.spark = ODJson.vec2(d.get("spark"))
	o.iframes = ODJson.boolean(d, "iframes")
	o.phase = TapePhase.from_dict(ODJson.dict(d, "phase"))
	o.vx = ODJson.num(d, "vx")
	o.vy = ODJson.num(d, "vy")
	return o


func to_dict() -> Dictionary:
	var out := {
		"tape": tape,
		"live": live,
		"x": x,
		"y": y,
		"facing": facing,
		"anim": String(anim),
		"life": OD.life_state_name(life),
		"synced": synced,
	}
	if has_spark:
		out["spark"] = ODJson.vec2_to_dict(spark)
	out["iframes"] = iframes
	out["phase"] = phase.to_dict()
	out["vx"] = vx
	out["vy"] = vy
	return out
