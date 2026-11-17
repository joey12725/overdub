class_name SpawnSpec
extends RefCounted
## What to spawn (prototype core/projectiles.ts SpawnSpec), passed to w.projectiles.spawn(w, spec).
##
##     var spec := SpawnSpec.make(self_actor.index, "", RangedArchetype.PIERCE, x, y, dir, 12.0, 0.15, 20.0)
##     spec.momentum = 1.2
##
## Optional fields hold their prototype defaults; `hits_selves` defaults to "owned by an enemy" unless
## has_hits_selves is set (set_hits_selves()).

## Owner: exactly one of owner_tape >= 0 / owner_enemy != "".
var owner_tape: int = -1
var owner_enemy: String = ""
var archetype: StringName = &""
var x: float = 0.0
var y: float = 0.0
var dir: float = 0.0
var speed: float = 0.0
var radius: float = 0.0
var range: float = 0.0
var momentum: float = 0.0
var z: float = 0.0
var passes_walls: bool = false
var hits_selves: bool = false
var has_hits_selves: bool = false
var hits_enemies: bool = true
var pierce: int = 0
## "" = no lock.
var target_id: String = ""
var pass_dir: int = 1
var data: Dictionary[String, float] = {}


static func make(
	p_owner_tape: int,
	p_owner_enemy: String,
	p_archetype: StringName,
	p_x: float,
	p_y: float,
	p_dir: float,
	p_speed: float,
	p_radius: float,
	p_range: float
) -> SpawnSpec:
	var s := SpawnSpec.new()
	s.owner_tape = p_owner_tape
	s.owner_enemy = p_owner_enemy
	s.archetype = p_archetype
	s.x = p_x
	s.y = p_y
	s.dir = p_dir
	s.speed = p_speed
	s.radius = p_radius
	s.range = p_range
	return s


## Set hits_selves explicitly (prototype: `hitsSelves` present in the spec).
func set_hits_selves(v: bool) -> SpawnSpec:
	hits_selves = v
	has_hits_selves = true
	return self
