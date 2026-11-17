class_name FrameSnapshot
extends RefCounted
## Everything a renderer / HUD / audio layer needs for one instant of the encounter
## (types.ts FrameSnapshot).

## Master substep index.
var sub: int = 0
## Master beat position (float).
var beat: float = 0.0
var actors: Array[ActorSnap] = []
var enemies: Array[EnemySnap] = []
var projectiles: Array[ProjectileSnap] = []
var mechs: Array[MechSnap] = []
var objective: ObjectiveSnap = ObjectiveSnap.new()


## The snapshot of self `tape`, or null.
func actor(tape: int) -> ActorSnap:
	for a: ActorSnap in actors:
		if a.tape == tape:
			return a
	return null


## The enemy snapshot with `id`, or null.
func enemy(id: String) -> EnemySnap:
	for e: EnemySnap in enemies:
		if e.id == id:
			return e
	return null


## The mechanism snapshot with `id`, or null.
func mech(id: String) -> MechSnap:
	for m: MechSnap in mechs:
		if m.id == id:
			return m
	return null


## Deep copy.
func copy() -> FrameSnapshot:
	var o := FrameSnapshot.new()
	o.sub = sub
	o.beat = beat
	for a: ActorSnap in actors:
		o.actors.append(a.copy())
	for e: EnemySnap in enemies:
		o.enemies.append(e.copy())
	for p: ProjectileSnap in projectiles:
		o.projectiles.append(p.copy())
	for m: MechSnap in mechs:
		o.mechs.append(m.copy())
	o.objective = objective.copy()
	return o


static func from_dict(d: Dictionary) -> FrameSnapshot:
	var o := FrameSnapshot.new()
	o.sub = ODJson.integer(d, "sub")
	o.beat = ODJson.num(d, "beat")
	for v: Variant in ODJson.array(d, "actors"):
		if v is Dictionary:
			o.actors.append(ActorSnap.from_dict(v))
	for v: Variant in ODJson.array(d, "enemies"):
		if v is Dictionary:
			o.enemies.append(EnemySnap.from_dict(v))
	for v: Variant in ODJson.array(d, "projectiles"):
		if v is Dictionary:
			o.projectiles.append(ProjectileSnap.from_dict(v))
	for v: Variant in ODJson.array(d, "mechs"):
		if v is Dictionary:
			o.mechs.append(MechSnap.from_dict(v))
	o.objective = ObjectiveSnap.from_dict(ODJson.dict(d, "objective"))
	return o


func to_dict() -> Dictionary:
	var a: Array = []
	for s: ActorSnap in actors:
		a.append(s.to_dict())
	var e: Array = []
	for s: EnemySnap in enemies:
		e.append(s.to_dict())
	var p: Array = []
	for s: ProjectileSnap in projectiles:
		p.append(s.to_dict())
	var m: Array = []
	for s: MechSnap in mechs:
		m.append(s.to_dict())
	return {"sub": sub, "beat": beat, "actors": a, "enemies": e, "projectiles": p, "mechs": m, "objective": objective.to_dict()}
