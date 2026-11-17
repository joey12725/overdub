class_name MusicReactive
extends RefCounted
## One emissive surface the fx layer may pulse with the music (prototype render/layer.ts
## MusicReactive; chapter 18 "Musical architecture"). The world view registers one per rune
## inscription, neon fixture, screen and core it builds, sets each to level 1 on load and never
## touches them again: the fx layer owns their modulation.

const KIND_RUNE: StringName = &"rune"
const KIND_NEON: StringName = &"neon"
const KIND_SCREEN: StringName = &"screen"
const KIND_CORE: StringName = &"core"

## KIND_*: rune inscriptions (floor glyphs, rune panels, wall etching), neon tubes and strips,
## screens (consoles / wave screens), the time machine heart.
var kind: StringName = KIND_RUNE
## The material whose emission is modulated (may be shared by many tiles).
var material: Material = null
## Sim-axes position when the material belongs to one object. Valid only when has_at.
var at: Vector2 = Vector2.ZERO
var has_at: bool = false
## Applies a brightness level; set by the world view: func(level: float) -> void.
var apply_level: Callable = Callable()


static func make(p_kind: StringName, p_material: Material, p_apply_level: Callable) -> MusicReactive:
	var m := MusicReactive.new()
	m.kind = p_kind
	m.material = p_material
	m.apply_level = p_apply_level
	return m


## Brightness relative to the authored look: 1 = as built, 0 = dark, > 1 brighter (blooms).
func set_level(level: float) -> void:
	if apply_level.is_valid():
		apply_level.call(level)
