class_name HitResponse
extends RefCounted
## Response of an enemy behaviour's on_hit hook (prototype core/combat.ts HitResponse):
##   apply()            apply the strike normally;
##   block(reason)      the strike is blocked entirely (shield up, invulnerable phase): emits 'clang';
##   replace(strike)    apply a modified strike instead.

const KIND_APPLY: StringName = &"apply"
const KIND_BLOCK: StringName = &"block"
const KIND_REPLACE: StringName = &"replace"

## KIND_*
var kind: StringName = KIND_APPLY
## KIND_BLOCK: the reason shown on the 'clang' (SimEvent.detail) and in the run log.
var reason: String = ""
## KIND_REPLACE: the strike applied instead.
var strike: EnemyStrike = null


## Apply normally.
static func apply() -> HitResponse:
	return HitResponse.new()


static func block(p_reason: String) -> HitResponse:
	var r := HitResponse.new()
	r.kind = KIND_BLOCK
	r.reason = p_reason
	return r


static func replace(p_strike: EnemyStrike) -> HitResponse:
	var r := HitResponse.new()
	r.kind = KIND_REPLACE
	r.strike = p_strike
	return r
