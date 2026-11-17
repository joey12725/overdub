class_name EntityDef
extends RefCounted
## Base of every level entity (types.ts EntityDef union). The `kind` field (EntityKind.*) is the
## discriminator; test with `is EnemyDef` (or compare kind) and cast with `as EnemyDef`. Parse with
## LevelDef.entity_from_dict(); every subclass implements copy() and to_dict().

## EntityKind.*
var kind: StringName = &""
## Entity / signal id. DecorDef has none ("").
var id: String = ""


## Deep copy; every subclass overrides.
func copy() -> EntityDef:
	push_error("EntityDef.copy() not overridden for kind '%s'" % kind)
	return null


## Prototype JSON shape; every subclass overrides.
func to_dict() -> Dictionary:
	push_error("EntityDef.to_dict() not overridden for kind '%s'" % kind)
	return {}
