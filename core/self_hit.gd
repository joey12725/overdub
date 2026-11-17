class_name SelfHit
extends RefCounted
## An attempt to kill a self (prototype core/combat.ts SelfHit). Queued with w.combat.hit_self(...).

var self_actor: SelfActor = null
## Player-readable cause, e.g. "struck by grunt g1", "shot by turret t1", "burned by laser beam".
var cause: String = ""
var x: float = 0.0
var y: float = 0.0
var dir: float = 0.0
## Laser hazards respect 'laserProof'.
var laser: bool = false


static func make(p_self: SelfActor, p_cause: String, p_x: float, p_y: float, p_dir: float, p_laser: bool = false) -> SelfHit:
	var h := SelfHit.new()
	h.self_actor = p_self
	h.cause = p_cause
	h.x = p_x
	h.y = p_y
	h.dir = p_dir
	h.laser = p_laser
	return h
