class_name SimEventType
extends RefCounted
## SimEvent.type (types.ts SimEventType). Open-ended: add members here, never rename.
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## Footstep of a self.
const STEP: StringName = &"step"
## Melee swing became active.
const SWING: StringName = &"swing"
## A self's attack connected with an enemy / object.
const HIT: StringName = &"hit"
## A swing's active window ended without connecting.
const WHIFF: StringName = &"whiff"
## Enemy died.
const KILL: StringName = &"kill"
## Breakable wall destroyed.
const BREAK: StringName = &"break"
## Hit lacked the momentum to matter (below a breakable's threshold, shield up).
const CLANG: StringName = &"clang"
const DODGE: StringName = &"dodge"
## A self launched a ranged projectile.
const FIRE: StringName = &"fire"
const PROJECTILE_HIT: StringName = &"projectileHit"
## A self toggled a switch.
const INTERACT: StringName = &"interact"
## Interact attempt with nothing in range / while ineffective.
const INTERACT_FAIL: StringName = &"interactFail"
## Door changed state.
const DOOR: StringName = &"door"
## Plate changed state.
const PLATE: StringName = &"plate"
## Laser changed state.
const LASER: StringName = &"laser"
## Core activated.
const CORE: StringName = &"core"
## A self died (becomes ghost / recGhost).
const SELF_DEATH: StringName = &"selfDeath"
const DESYNC: StringName = &"desync"
const RESYNC: StringName = &"resync"
## A 'repeat' tape cut back to its start.
const TAPE_WRAP: StringName = &"tapeWrap"
## A 'reverse' tape turned around.
const TAPE_TURN: StringName = &"tapeTurn"
## A 'stop' tape ran out.
const TAPE_END: StringName = &"tapeEnd"
const ENEMY_TELEGRAPH: StringName = &"enemyTelegraph"
const ENEMY_ATTACK: StringName = &"enemyAttack"
const ENEMY_SHOT: StringName = &"enemyShot"
const ENEMY_STAGGER: StringName = &"enemyStagger"
const BOSS_PHASE: StringName = &"bossPhase"
## The outside-the-loop boss acts on a remembered recording.
const BOSS_RECALL: StringName = &"bossRecall"
## Objective latched complete.
const OBJECTIVE: StringName = &"objective"
## A trap changed state (docs/TRAPS.md "Events for audio and fx"): id = trap id, detail =
## "<kind>:<what>". Deliberately NOT in ALL yet, exactly as the prototype keeps 'trap' out of its
## SimEventType union (traps/tuning.ts TRAP_EVENT): tests/fx/test_fx_routing.gd requires an fx route
## for every ALL member, and fx/fx_catalog.gd belongs to the fx engineer. Add TRAP to ALL together
## with its route.
const TRAP: StringName = &"trap"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	STEP,
	SWING,
	HIT,
	WHIFF,
	KILL,
	BREAK,
	CLANG,
	DODGE,
	FIRE,
	PROJECTILE_HIT,
	INTERACT,
	INTERACT_FAIL,
	DOOR,
	PLATE,
	LASER,
	CORE,
	SELF_DEATH,
	DESYNC,
	RESYNC,
	TAPE_WRAP,
	TAPE_TURN,
	TAPE_END,
	ENEMY_TELEGRAPH,
	ENEMY_ATTACK,
	ENEMY_SHOT,
	ENEMY_STAGGER,
	BOSS_PHASE,
	BOSS_RECALL,
	OBJECTIVE,
]


## True when `value` is a member: one of ALL, or TRAP (a real event type kept out of ALL until fx
## routes it; see TRAP).
static func has(value: StringName) -> bool:
	return ALL.has(value) or value == TRAP
