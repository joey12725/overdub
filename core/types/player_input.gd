class_name PlayerInput
extends RefCounted
## One local tick of player intent (types.ts PlayerInput). Movement is already camera-corrected into
## world (sim) axes.

## Desired move direction, each component in [-1, 1]; length is clamped to 1 by the controller.
var move_x: float = 0.0
var move_y: float = 0.0
## Aim direction in radians (world space, atan2(y, x)).
var aim: float = 0.0
## Edge-triggered buttons: true only on the tick the button went down.
var light: bool = false
var heavy: bool = false
var dodge: bool = false
var ranged: bool = false
var interact: bool = false
## Gear ability button (e.g. manual desync), edge-triggered.
var ability: bool = false


static func make(p_move_x: float = 0.0, p_move_y: float = 0.0, p_aim: float = 0.0) -> PlayerInput:
	var i := PlayerInput.new()
	i.move_x = p_move_x
	i.move_y = p_move_y
	i.aim = p_aim
	return i


func copy() -> PlayerInput:
	var o := PlayerInput.new()
	o.copy_from(self)
	return o


func copy_from(o: PlayerInput) -> void:
	move_x = o.move_x
	move_y = o.move_y
	aim = o.aim
	light = o.light
	heavy = o.heavy
	dodge = o.dodge
	ranged = o.ranged
	interact = o.interact
	ability = o.ability


## Back to "no movement, no buttons" (aim is kept unless given).
func clear(p_aim: float = aim) -> void:
	move_x = 0.0
	move_y = 0.0
	aim = p_aim
	light = false
	heavy = false
	dodge = false
	ranged = false
	interact = false
	ability = false


static func from_dict(d: Dictionary) -> PlayerInput:
	var i := PlayerInput.new()
	i.move_x = ODJson.num(d, "moveX")
	i.move_y = ODJson.num(d, "moveY")
	i.aim = ODJson.num(d, "aim")
	i.light = ODJson.boolean(d, "light")
	i.heavy = ODJson.boolean(d, "heavy")
	i.dodge = ODJson.boolean(d, "dodge")
	i.ranged = ODJson.boolean(d, "ranged")
	i.interact = ODJson.boolean(d, "interact")
	i.ability = ODJson.boolean(d, "ability")
	return i


func to_dict() -> Dictionary:
	return {
		"moveX": move_x,
		"moveY": move_y,
		"aim": aim,
		"light": light,
		"heavy": heavy,
		"dodge": dodge,
		"ranged": ranged,
		"interact": interact,
		"ability": ability,
	}
