class_name ExitDef
extends EntityDef
## An exit zone (types.ts ExitDef). `id` is the signal id, true while an alive + synced self stands
## inside the w x h tile rectangle whose top-left tile is (c, r).

var c: int = 0
var r: int = 0
var w: int = 1
var h: int = 1


func _init() -> void:
	kind = EntityKind.EXIT


func copy() -> EntityDef:
	var o := ExitDef.new()
	o.id = id
	o.c = c
	o.r = r
	o.w = w
	o.h = h
	return o


static func from_dict(d: Dictionary) -> ExitDef:
	var o := ExitDef.new()
	o.id = ODJson.string(d, "id")
	o.c = ODJson.integer(d, "c")
	o.r = ODJson.integer(d, "r")
	o.w = ODJson.integer(d, "w", 1)
	o.h = ODJson.integer(d, "h", 1)
	return o


func to_dict() -> Dictionary:
	return {"kind": String(kind), "id": id, "c": c, "r": r, "w": w, "h": h}
