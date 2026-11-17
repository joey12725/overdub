class_name ShielderBehaviour
extends MeleeChaser
## Shielder (Scenario A, AI-05, HEALTH-02): a shield that recharges instantly, so only two selves
## working together can hurt it. Port of prototype/src/core/enemies/shielder.ts.
##
## The rule, stated the way the player learns it:
##   - The shield is up. A hit from a self POPS it: the hit itself does nothing ('clang', detail
##     'shield') and the shield stays down for SHIELDER_WINDOW_BEATS master beats.
##   - While it is down, a hit from a DIFFERENT self lands normally (damage, knockback, stagger) and
##     the shield is instantly back up. That self has to pop it again for anyone to follow up.
##   - A second hit from the same self that popped it is just another pop: it re-opens the window for
##     that same self, which can never use it. So one self alone, at any speed or momentum, can
##     never damage a shielder.
##   - Hits from anything that is not a self (an enemy's bolt, the environment) clang off the shield
##     and do not pop it: the lesson is cooperation between cassettes.
## Hits on the same substep from two selves count as "within the window" (Scenario A's
## simultaneous hits). The window is generous and stated in beats so the rule never depends on an
## unexplained single-frame coincidence (Scenario A).
##
## Otherwise it walks at the NEAREST targetable self and strikes on its beat grid like a grunt.

## Shielder strike arc, radians (a shield bash: the grunt's width).
const SHIELDER_ARC: float = (2.0 * PI) / 3.0
const SHIELDER_RECOVER_BEATS: float = 0.5

## mem keys: substep of the last pop (-1 = shield up) and the tape that popped it (-1 = none).
const MEM_POP_SUB: String = "popSub"
const MEM_POP_BY: String = "popBy"


func _init() -> void:
	type = EnemyType.SHIELDER
	var p := StalkerBehaviour.MeleeProfile.new()
	p.type = EnemyType.SHIELDER
	p.arc = SHIELDER_ARC
	p.recover_beats = SHIELDER_RECOVER_BEATS
	p.stop_fraction = 0.6
	p.strike_name = "bash"
	p.pick = func(w: ODSim, e: EnemyState) -> SelfActor: return EnemyCommon.nearest_target(w, e.x, e.y)
	p.retarget_on_beat = func(_w: ODSim, _e: EnemyState, _beat: int) -> bool: return true
	p.retarget_after_strike = false
	profile = p


## The follow-up window in master substeps.
static func shield_window_subs(w: ODSim) -> int:
	# Math.round of a non-negative value: floor(x + 0.5) keeps JS rounding of halves.
	return floori(Tuning.SHIELDER_WINDOW_BEATS * w.spb + 0.5)


## Is the shield down at substep `sub` (i.e. would a different self's hit on `sub` land)?
static func shield_down_at(w: ODSim, e: EnemyState, sub: int) -> bool:
	var pop: Variant = e.mem.get(MEM_POP_SUB)
	return pop is int and pop >= 0 and sub - int(pop) <= shield_window_subs(w)


func init(_w: ODSim, e: EnemyState) -> void:
	e.mem[MEM_POP_SUB] = -1
	e.mem[MEM_POP_BY] = -1


func on_hit(w: ODSim, e: EnemyState, strike: EnemyStrike) -> HitResponse:
	if not strike.source.is_tape():
		return HitResponse.block("shield")
	var by: int = strike.source.tape
	if shield_down_at(w, e, w.s) and int(e.mem.get(MEM_POP_BY, -1)) != by:
		# The follow-up landed: the shield snaps back up at once.
		e.mem[MEM_POP_SUB] = -1
		e.mem[MEM_POP_BY] = -1
		return HitResponse.apply()
	e.mem[MEM_POP_SUB] = w.s
	e.mem[MEM_POP_BY] = by
	return HitResponse.block("shield")


func snapshot(w: ODSim, e: EnemyState, snap: EnemySnap) -> void:
	# The snapshot describes the instant after substep w.s: the shield is down if a hit on the next
	# substep would still be inside the window.
	snap.shield = e.alive and not shield_down_at(w, e, w.s + 1)
	snap.has_shield = true
