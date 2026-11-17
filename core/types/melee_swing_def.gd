class_name MeleeSwingDef
extends RefCounted
## One swing of a melee weapon (types.ts MeleeSwingDef). Timings are in LOCAL ticks; they are floats
## like the prototype's `number` (player.ts rounds them with ticksOf).

## Local ticks before the hit frame.
var windup: float = 0.0
## Local ticks the hit volume stays live.
var active: float = 0.0
## Local ticks of recovery after the active window.
var recover: float = 0.0
## Base momentum of the swing at 1x tape speed, standing still.
var impact: float = 0.0
## Move-speed multiplier while the swing is in progress.
var move_mul: float = 1.0


func copy() -> MeleeSwingDef:
	var o := MeleeSwingDef.new()
	o.windup = windup
	o.active = active
	o.recover = recover
	o.impact = impact
	o.move_mul = move_mul
	return o


static func from_dict(d: Dictionary) -> MeleeSwingDef:
	var o := MeleeSwingDef.new()
	o.windup = ODJson.num(d, "windup")
	o.active = ODJson.num(d, "active")
	o.recover = ODJson.num(d, "recover")
	o.impact = ODJson.num(d, "impact")
	o.move_mul = ODJson.num(d, "moveMul", 1.0)
	return o


func to_dict() -> Dictionary:
	return {"windup": windup, "active": active, "recover": recover, "impact": impact, "moveMul": move_mul}
