class_name EnemySnap
extends RefCounted
## One enemy at one instant (types.ts EnemySnap).

var id: String = ""
## EnemyType.*
var type: StringName = EnemyType.GRUNT
var x: float = 0.0
var y: float = 0.0
var facing: float = 0.0
var hp: int = 0
var max_hp: int = 0
var alive: bool = true
## EnemyStateName.*
var state: StringName = EnemyStateName.IDLE
## 0..1 progress through the current state (telegraph fill, stagger recovery...).
var state_t: float = 0.0
## Tape index of the self it is currently targeting; -1 = none.
var target: int = -1
## Shielder: shield currently up. Valid only when has_shield.
var shield: bool = false
var has_shield: bool = false
## Boss only: current phase; -1 = not a boss / absent.
var boss_phase: int = -1
## Boss only: true while the current telegraph/attack is driven by BossMemory (BOSS-02).
var boss_recall: bool = false
## Boss only: the committed tape whose memory is being acted on, when boss_recall; -1 = none.
var boss_recall_tape: int = -1
## Boss only: the remembered place a memory strike will land on, while boss_recall. Valid only when
## has_boss_recall_at.
var boss_recall_at: Vector2 = Vector2.ZERO
var has_boss_recall_at: bool = false


func copy() -> EnemySnap:
	var o := EnemySnap.new()
	o.id = id
	o.type = type
	o.x = x
	o.y = y
	o.facing = facing
	o.hp = hp
	o.max_hp = max_hp
	o.alive = alive
	o.state = state
	o.state_t = state_t
	o.target = target
	o.shield = shield
	o.has_shield = has_shield
	o.boss_phase = boss_phase
	o.boss_recall = boss_recall
	o.boss_recall_tape = boss_recall_tape
	o.boss_recall_at = boss_recall_at
	o.has_boss_recall_at = has_boss_recall_at
	return o


static func from_dict(d: Dictionary) -> EnemySnap:
	var o := EnemySnap.new()
	o.id = ODJson.string(d, "id")
	o.type = ODJson.sname(d, "type", EnemyType.GRUNT)
	o.x = ODJson.num(d, "x")
	o.y = ODJson.num(d, "y")
	o.facing = ODJson.num(d, "facing")
	o.hp = ODJson.integer(d, "hp")
	o.max_hp = ODJson.integer(d, "maxHp")
	o.alive = ODJson.boolean(d, "alive", true)
	o.state = ODJson.sname(d, "state", EnemyStateName.IDLE)
	o.state_t = ODJson.num(d, "stateT")
	o.target = ODJson.integer(d, "target", -1)
	o.has_shield = d.get("shield") is bool
	o.shield = ODJson.boolean(d, "shield")
	o.boss_phase = ODJson.integer(d, "bossPhase", -1)
	o.boss_recall = ODJson.boolean(d, "bossRecall")
	o.boss_recall_tape = ODJson.integer(d, "bossRecallTape", -1)
	o.has_boss_recall_at = d.get("bossRecallAt") is Dictionary
	o.boss_recall_at = ODJson.vec2(d.get("bossRecallAt"))
	return o


func to_dict() -> Dictionary:
	var out := {
		"id": id,
		"type": String(type),
		"x": x,
		"y": y,
		"facing": facing,
		"hp": hp,
		"maxHp": max_hp,
		"alive": alive,
		"state": String(state),
		"stateT": state_t,
	}
	if target >= 0:
		out["target"] = target
	if has_shield:
		out["shield"] = shield
	if boss_phase >= 0:
		out["bossPhase"] = boss_phase
	# The prototype's boss snapshot always writes bossRecall (a boolean) next to bossPhase.
	if boss_phase >= 0 or boss_recall:
		out["bossRecall"] = boss_recall
	if boss_recall_tape >= 0:
		out["bossRecallTape"] = boss_recall_tape
	if has_boss_recall_at:
		out["bossRecallAt"] = ODJson.vec2_to_dict(boss_recall_at)
	return out
