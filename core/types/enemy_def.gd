class_name EnemyDef
extends EntityDef
## An enemy placement (types.ts EnemyDef).

## EnemyType.*
var type: StringName = EnemyType.GRUNT
var x: float = 0.0
var y: float = 0.0
## Initial facing in radians (absent in JSON = 0).
var facing: float = 0.0
## Override hit points (boss health, tougher variants). Valid only when has_hp.
var hp: int = 0
var has_hp: bool = false
## Attack grid override (JSON { beat: { every, offset } }): fires/strikes every `beat_every` beats,
## offset by `beat_offset` beats. Valid only when has_beat.
var beat_every: int = 0
var beat_offset: float = 0.0
var has_beat: bool = false
## Turret only: restrict aim to an arc (radians) around `facing`. Valid only when has_arc
## (absent = 360 degrees).
var arc: float = 0.0
var has_arc: bool = false
## Stays asleep until this signal is true; null = awake from the start.
var wake_when: SignalExpr = null


func _init() -> void:
	kind = EntityKind.ENEMY


func copy() -> EntityDef:
	var o := EnemyDef.new()
	o.id = id
	o.type = type
	o.x = x
	o.y = y
	o.facing = facing
	o.hp = hp
	o.has_hp = has_hp
	o.beat_every = beat_every
	o.beat_offset = beat_offset
	o.has_beat = has_beat
	o.arc = arc
	o.has_arc = has_arc
	o.wake_when = wake_when.copy() if wake_when != null else null
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> EnemyDef:
	var o := EnemyDef.new()
	o.id = ODJson.string(d, "id")
	o.type = ODJson.sname(d, "type", EnemyType.GRUNT)
	o.x = ODJson.num(d, "x")
	o.y = ODJson.num(d, "y")
	o.facing = ODJson.num(d, "facing")
	o.has_hp = ODJson.is_number(d.get("hp"))
	o.hp = ODJson.integer(d, "hp")
	if d.get("beat") is Dictionary:
		var bd: Dictionary = d["beat"]
		o.has_beat = true
		o.beat_every = ODJson.integer(bd, "every")
		o.beat_offset = ODJson.num(bd, "offset")
	o.has_arc = ODJson.is_number(d.get("arc"))
	o.arc = ODJson.num(d, "arc")
	if d.has("wakeWhen"):
		o.wake_when = SignalExpr.from_dict(d["wakeWhen"], errors, "enemy %s.wakeWhen" % o.id)
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "type": String(type), "x": x, "y": y}
	if facing != 0.0:
		out["facing"] = facing
	if has_hp:
		out["hp"] = hp
	if has_beat:
		out["beat"] = {"every": beat_every, "offset": beat_offset}
	if has_arc:
		out["arc"] = arc
	if wake_when != null:
		out["wakeWhen"] = wake_when.to_dict()
	return out
