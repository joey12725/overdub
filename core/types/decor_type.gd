class_name DecorType
extends RefCounted
## DecorDef.type (types.ts). Values keep the prototype camelCase; the kit model for a decor type
## is its snake_case form (runePanel -> rune_panel), see docs/GODOT-PORT.md.
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const GRAFFITI: StringName = &"graffiti"
const VINES: StringName = &"vines"
const BUSH: StringName = &"bush"
const CRATE: StringName = &"crate"
const BARREL: StringName = &"barrel"
const PIPE: StringName = &"pipe"
const CONSOLE: StringName = &"console"
const GENERATOR: StringName = &"generator"
const VENT: StringName = &"vent"
const ARCH: StringName = &"arch"
const RUBBLE: StringName = &"rubble"
const CHEST: StringName = &"chest"
const NEON: StringName = &"neon"
const RUNE_PANEL: StringName = &"runePanel"
const WAVE_SCREEN: StringName = &"waveScreen"
const CABLE: StringName = &"cable"
const LAMP: StringName = &"lamp"
const TIME_MACHINE: StringName = &"timeMachine"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	GRAFFITI,
	VINES,
	BUSH,
	CRATE,
	BARREL,
	PIPE,
	CONSOLE,
	GENERATOR,
	VENT,
	ARCH,
	RUBBLE,
	CHEST,
	NEON,
	RUNE_PANEL,
	WAVE_SCREEN,
	CABLE,
	LAMP,
	TIME_MACHINE,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
