class_name OD
extends RefCounted
## OVERDUB shared constants and helpers (port of prototype/src/core/types.ts, the non-type parts).
##
## Every data interface of types.ts is a small RefCounted class under res://core/types/ (one file per
## class, see core/README.md for the full name map). This class holds the constants, the two closed
## enums (EndMode, LifeState) and subs_per_local_tick(). It is never instantiated.
##
## Vocabulary (docs/ARCHITECTURE.md):
##   wall time    - real seconds experienced by the person holding the controller.
##   local time   - progress along one cassette's recording. While recording, local == wall.
##   master time  - the single shared world timeline. master = local / tape_speed.
##   substep      - the atomic master simulation step: 1/SUB_HZ master seconds.
##   local tick   - one recorded sample: 1/LOCAL_HZ local seconds.

# ───────────────────────────── time ─────────────────────────────

## Master substeps per master second. Every tape speed divides this evenly.
const SUB_HZ: int = 240
## Recorded samples (local ticks) per local second.
const LOCAL_HZ: int = 60
const BEATS_PER_BAR: int = 4
## Substeps between stored snapshots in a Resolution (60 snapshots per master second).
const FRAME_SUBS: int = 4
const TAPE_COUNT: int = 4

## Tape speed relative to the middle option. Powers of two only. A TapeSpeed is a float holding one
## of these values; 0.0 means "no speed" where the prototype allows null (DeckView.speed).
const ALL_SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]


## Master substeps the world advances per local tick of a tape at `speed` (8, 4, 2, 1).
static func subs_per_local_tick(speed: float) -> int:
	return roundi(float(SUB_HZ) / float(LOCAL_HZ) / speed)


## True when `speed` is one of ALL_SPEEDS.
static func is_speed(speed: float) -> bool:
	return ALL_SPEEDS.has(speed)

# ───────────────────────────── end mode ─────────────────────────────

## What a cassette does when its recording runs out before the master horizon does.
## JSON / prototype spelling: END_MODE_NAMES[mode] ("stop", "repeat", "reverse").
enum EndMode { STOP, REPEAT, REVERSE }

const END_MODE_NAMES: Array[String] = ["stop", "repeat", "reverse"]
## Every end mode in prototype order (time.ts ALL_END_MODES).
const ALL_END_MODES: Array[int] = [EndMode.STOP, EndMode.REPEAT, EndMode.REVERSE]


## "stop" | "repeat" | "reverse" -> EndMode; -1 for anything else.
static func end_mode_from_name(name: String) -> int:
	return END_MODE_NAMES.find(name)


## EndMode -> "stop" | "repeat" | "reverse"; "" for -1 / out of range.
static func end_mode_name(mode: int) -> String:
	return END_MODE_NAMES[mode] if mode >= 0 and mode < END_MODE_NAMES.size() else ""

# ───────────────────────────── life state ─────────────────────────────

## Life state of a self within the current run. Recalculated every run (GHOST-06).
##   ALIVE     - physically effective.
##   REC_GHOST - the live take after death: still constrained by walls, still interactive, takes no
##               damage (GHOST-02..04). Prototype spelling "recGhost".
##   GHOST     - a played-back tape after death: follows its path, intangible, harmless (GHOST-05).
enum LifeState { ALIVE, REC_GHOST, GHOST }

const LIFE_STATE_NAMES: Array[String] = ["alive", "recGhost", "ghost"]


## "alive" | "recGhost" | "ghost" -> LifeState; -1 for anything else.
static func life_state_from_name(name: String) -> int:
	return LIFE_STATE_NAMES.find(name)


## LifeState -> prototype spelling; "" for -1 / out of range.
static func life_state_name(state: int) -> String:
	return LIFE_STATE_NAMES[state] if state >= 0 and state < LIFE_STATE_NAMES.size() else ""

# ───────────────────────────── animation, gear ─────────────────────────────

## AnimState values in index order: a tape's `anim` byte i means ANIM_STATES[i]. Same as AnimState.ALL.
const ANIM_STATES: Array[StringName] = [
	&"idle",
	&"run",
	&"lightWindup",
	&"lightActive",
	&"lightRecover",
	&"heavyWindup",
	&"heavyActive",
	&"heavyRecover",
	&"dodge",
	&"ranged",
	&"interact",
	&"stopped",
]

## Gear slots in prototype order. Same as GearSlot.ALL.
const GEAR_SLOTS: Array[StringName] = [&"helmet", &"top", &"pants", &"shoes", &"melee", &"ranged"]

# ───────────────────────────── cassette identity ─────────────────────────────

## Cassette identity colours, shared by the HUD, the world and the music UI (UI-02). Hex strings as in
## the prototype; TAPE_COLORS_RGB holds the same colours as Color.
const TAPE_COLORS: Array[String] = ["#ff4d6d", "#ffd23f", "#3ec5ff", "#7dff6b"]
const TAPE_COLORS_RGB: Array[Color] = [Color("#ff4d6d"), Color("#ffd23f"), Color("#3ec5ff"), Color("#7dff6b")]
const TAPE_NAMES: Array[String] = ["A", "B", "C", "D"]


## The cassette colours in use. Empty = TAPE_COLORS_RGB (the prototype's set). Presentation only: the
## simulation never reads a colour. The game points this at the player's chosen accessibility set
## (docs/ACCESSIBILITY.md; ActorOptions.apply_settings), so the HUD, the world, the effects and the
## music displays, which all ask tape_color(), show the same four colours as the Moxie copies.
static var _tape_palette: PackedColorArray = PackedColorArray()


## Use `colors` (one per cassette) as the identity colours; fewer than TAPE_COUNT restores the
## built-in set.
static func set_tape_palette(colors: PackedColorArray) -> void:
	_tape_palette = colors if colors.size() >= TAPE_COUNT else PackedColorArray()


## Identity colour of cassette `tape` (0..3).
static func tape_color(tape: int) -> Color:
	if not _tape_palette.is_empty():
		return _tape_palette[tape]
	return TAPE_COLORS_RGB[tape]


## Identity letter of cassette `tape` (0..3): "A".."D". (objective.ts tapeName, "Tape A", is
## ObjectiveTracker.tape_name in the port.)
static func tape_letter(tape: int) -> String:
	return TAPE_NAMES[tape]
