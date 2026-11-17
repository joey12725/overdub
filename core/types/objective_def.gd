class_name ObjectiveDef
extends RefCounted
## A level's objective (types.ts ObjectiveDef).

## ObjectiveType.*
##   eliminate - every enemy (or those listed in `targets`) is dead.
##   reach     - an alive + synced self is inside the exit when the horizon ends.
##   activate  - every core (or those in `targets`) is activated.
##   boss      - the boss is dead.
##   signal    - custom: `when_expr` latches true at any point of the run.
var type: StringName = ObjectiveType.ELIMINATE
## Optional target ids. Empty = all (the prototype treats an absent and an empty list alike).
var targets: Array[String] = []
## Prototype key "when" (renamed: `when` is a GDScript keyword). null = absent.
var when_expr: SignalExpr = null
## Short imperative shown in the HUD ("Break the wall", "Kill both turrets").
var text: String = ""


func copy() -> ObjectiveDef:
	var o := ObjectiveDef.new()
	o.type = type
	o.targets = targets.duplicate()
	o.when_expr = when_expr.copy() if when_expr != null else null
	o.text = text
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> ObjectiveDef:
	var o := ObjectiveDef.new()
	o.type = ODJson.sname(d, "type", ObjectiveType.ELIMINATE)
	o.targets = ODJson.strings(d.get("targets"))
	if d.has("when"):
		o.when_expr = SignalExpr.from_dict(d["when"], errors, "objective.when")
	o.text = ODJson.string(d, "text")
	return o


func to_dict() -> Dictionary:
	var out := {"type": String(type)}
	if not targets.is_empty():
		out["targets"] = ODJson.strings_to_array(targets)
	if when_expr != null:
		out["when"] = when_expr.to_dict()
	out["text"] = text
	return out
