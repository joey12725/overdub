class_name StrikeSource
extends RefCounted
## Who delivered a strike (prototype core/combat.ts StrikeSource = {tape} | {enemy} | {env}).
## Exactly one of the three is set: `tape` >= 0, or `enemy` non-empty, or `env` non-empty.

## Tape index of the self that struck; -1 = not a self.
var tape: int = -1
## Id of the enemy that struck; "" = not an enemy.
var enemy: String = ""
## Environment cause ("laser beam"...); "" = not the environment.
var env: String = ""


static func of_tape(p_tape: int) -> StrikeSource:
	var s := StrikeSource.new()
	s.tape = p_tape
	return s


static func of_enemy(p_enemy: String) -> StrikeSource:
	var s := StrikeSource.new()
	s.enemy = p_enemy
	return s


static func of_env(p_env: String) -> StrikeSource:
	var s := StrikeSource.new()
	s.env = p_env
	return s


func is_tape() -> bool:
	return tape >= 0


func is_enemy() -> bool:
	return tape < 0 and not enemy.is_empty()


func copy() -> StrikeSource:
	var s := StrikeSource.new()
	s.tape = tape
	s.enemy = enemy
	s.env = env
	return s
