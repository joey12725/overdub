class_name WidgetMath
extends RefCounted
## Pure maths behind the force/danger widgets (MOM-01..04, HEALTH-02, Scenario K). No nodes.
##
## Everything that says how hard a swing hits calls the SAME core functions the simulation uses
## (Tuning.strike_approach / swing_momentum / strike_damage, Combat.core_threshold, the boss and brute
## constants); nothing here re-derives the momentum model. What it adds is presentation: which target
## the live self is facing, how momentum maps onto the gauge's segments, which thresholds to mark,
## and how to phrase a failed swing.
##
## Units: one gauge segment / one badge pip = PIP_MOMENTUM of momentum = Tuning.DAMAGE_UNIT, so with
## the baseline weapon one pip is one point of damage and a breakable's pips read directly against
## the gauge ("needs 5 pips, my heavy fills 3").

const KIND_NONE: StringName = &"none"
const KIND_BREAKABLE: StringName = &"breakable"
const KIND_CORE: StringName = &"core"
const KIND_ENEMY: StringName = &"enemy"
const KIND_BOSS: StringName = &"boss"

## Tick kinds on the gauge.
const TICK_THRESHOLD: StringName = &"threshold"
const TICK_DAMAGE: StringName = &"damage"
const TICK_KILL: StringName = &"kill"
const TICK_STAGGER: StringName = &"stagger"
const TICK_SHOVE: StringName = &"shove"

## Momentum per gauge segment / badge pip.
const PIP_MOMENTUM: float = Tuning.DAMAGE_UNIT
## Gauge scale bounds, segments.
const MIN_SEGMENTS: int = 4
const MAX_SEGMENTS: int = 16
## Facing cone and range used to pick "the thing she is facing", on top of the weapon's reach.
const FACING_HALF_ANGLE: float = 0.9599310885968813 # 55 deg
const FACING_EXTRA_RANGE: float = 2.25

## Presentation heights (scene units above the floor) where world-anchored widgets sit. Not sim data.
const HEAD_HEIGHT: Dictionary[StringName, float] = {
	EnemyType.GRUNT: 1.45,
	EnemyType.STALKER: 1.45,
	EnemyType.TURRET: 1.35,
	EnemyType.SHIELDER: 1.6,
	EnemyType.BRUTE: 2.2,
	EnemyType.DRONE: 1.9,
	EnemyType.BOSS: 3.8,
}
const SELF_HEAD_HEIGHT: float = 1.75
const BREAKABLE_BADGE_HEIGHT: float = 1.7
const CORE_BADGE_HEIGHT: float = 1.35


## What the next light or heavy swing would deliver if pressed right now.
class SwingPreview:
	extends RefCounted
	## ActionKind.LIGHT / HEAVY.
	var kind: StringName = &""
	## Momentum with the current motion (approach from the current local velocity).
	var momentum: float = 0.0
	## Same swing standing still (approach 0).
	var standing: float = 0.0
	## Same swing running fully into it (approach APPROACH_MAX).
	var full: float = 0.0
	## Same swing and motion on a 1x tape (for the "faster tape hits harder" mark).
	var at_1x: float = 0.0
	## Damage points it would deal (Tuning.strike_damage with the weapon and mods).
	var damage: int = 0


## A threshold mark on the gauge.
class Tick:
	extends RefCounted
	var momentum: float = 0.0
	## TICK_*.
	var kind: StringName = &""
	var label: String = ""

	static func make(m: float, k: StringName, l: String) -> Tick:
		var t := Tick.new()
		t.momentum = m
		t.kind = k
		t.label = l
		return t


## The thing the live self is facing.
class Target:
	extends RefCounted
	## KIND_*.
	var kind: StringName = &"none"
	var id: String = ""
	## Sim position (tile centre for breakables).
	var pos: Vector2 = Vector2.ZERO
	var distance: float = 0.0
	## Momentum a single hit needs (breakables, cores); 0 otherwise.
	var threshold: float = 0.0
	## Enemies: hit points left / max, type, shield.
	var hp: int = 0
	var max_hp: int = 0
	var enemy_type: StringName = &""
	var shielded: bool = false


## Everything the gauge draws, as data.
class GaugeState:
	extends RefCounted
	var visible: bool = false
	var tape: int = -1
	var speed: float = 1.0
	## Current approach factor (-0.5 .. 1): positive = moving into the swing.
	var approach: float = 0.0
	var light: SwingPreview = SwingPreview.new()
	var heavy: SwingPreview = SwingPreview.new()
	## Segments on the arc (each PIP_MOMENTUM).
	var segments: int = MIN_SEGMENTS
	var target: Target = Target.new()
	var ticks: Array[Tick] = []
	## Would the light / heavy swing meet the target's main threshold right now?
	var light_meets: bool = false
	var heavy_meets: bool = false
	## Could a heavy meet it at this speed if she ran fully into it?
	var heavy_can_meet: bool = false
	## Hits to kill the faced enemy with a light / heavy now (-1 = no damage / not an enemy).
	var light_hits: int = -1
	var heavy_hits: int = -1
	## Slowest offered tape speed whose full run-in heavy meets the target (0 = none / not applicable).
	var min_speed: float = 0.0


## A failed swing explained.
class FailInfo:
	extends RefCounted
	var valid: bool = false
	## Short sticker word: CLANG, ARMOUR, SHIELD, NO DAMAGE, WHIFF.
	var title: String = ""
	## One line: why, in player terms.
	var line: String = ""
	var had: float = 0.0
	## Momentum that would have been enough (0 = not a momentum problem).
	var need: float = 0.0
	var tape: int = -1
	var pos: Vector2 = Vector2.ZERO


# ───────────────────────────── momentum (core functions only) ─────────────────────────────

## A self's LOCAL velocity from its snapshot (ActorSnap.vx/vy are master-space: v_master = s * v_local).
static func local_velocity(actor: ActorSnap, tape_speed: float) -> Vector2:
	if actor == null or not (tape_speed > 0.0):
		return Vector2.ZERO
	return Vector2(actor.vx / tape_speed, actor.vy / tape_speed)


## Preview of a swing of `kind` (ActionKind.LIGHT/HEAVY) at `tape_speed`, body moving at local
## velocity (vx, vy), aimed along `dir` (sim radians).
static func preview_swing(loadout: ResolvedLoadout, kind: StringName, tape_speed: float, local_vx: float, local_vy: float, dir: float) -> SwingPreview:
	var p := SwingPreview.new()
	p.kind = kind
	if loadout == null:
		return p
	var swing: MeleeSwingDef = loadout.melee.heavy if kind == ActionKind.HEAVY else loadout.melee.light
	var mods: StatMods = loadout.mods
	p.momentum = Tuning.swing_momentum(swing, mods, tape_speed, local_vx, local_vy, dir)
	p.standing = Tuning.strike_momentum(swing.impact, mods.melee_impact, tape_speed, 0.0, mods.approach_bonus)
	p.full = Tuning.strike_momentum(swing.impact, mods.melee_impact, tape_speed, Tuning.APPROACH_MAX, mods.approach_bonus)
	p.at_1x = Tuning.swing_momentum(swing, mods, 1.0, local_vx, local_vy, dir)
	p.damage = damage_for(loadout, p.momentum)
	return p


## Damage points a strike of `momentum` deals with this loadout (the sim's formula).
static func damage_for(loadout: ResolvedLoadout, momentum: float) -> int:
	if loadout == null:
		return 0
	return Tuning.strike_damage(momentum, loadout.melee.damage_eff, loadout.mods.damage)


## Smallest momentum that deals at least `points` damage with this loadout (0 if impossible).
static func momentum_for_damage(loadout: ResolvedLoadout, points: int) -> float:
	if loadout == null or points <= 0:
		return 0.0
	var k := loadout.melee.damage_eff * loadout.mods.damage
	if not (k > 0.0):
		return 0.0
	var m := float(points) * Tuning.DAMAGE_UNIT / k
	# Guard against float rounding putting the mark a hair under the sim's floor().
	while Tuning.strike_damage(m, loadout.melee.damage_eff, loadout.mods.damage) < points:
		m = m * (1.0 + 1e-9) + 1e-12
	return m


## Hits of `damage` points needed for `hp` (-1 when the hit does no damage).
static func hits_to_kill(hp: int, damage: int) -> int:
	if damage <= 0:
		return -1
	if hp <= 0:
		return 0
	return ceili(float(hp) / float(damage))


## The sim's object test: a strike breaks / activates when momentum >= threshold.
static func meets(momentum: float, threshold: float) -> bool:
	return momentum >= threshold


## Momentum a breakable or core needs (cores fall back to the sim default when the level omits it).
static func breakable_threshold(b: BreakableDef) -> float:
	return b.threshold


static func core_threshold(c: CoreDef) -> float:
	return Combat.core_threshold(c.threshold, c.has_threshold)


## Pips shown for a force requirement, as a float (4.5 -> 4.5: four full pips and a half one).
static func force_pips(threshold: float) -> float:
	return maxf(0.0, threshold / PIP_MOMENTUM)


## Whole pip slots needed to draw `threshold` (ceil, tolerant of float noise).
static func pip_slots(threshold: float) -> int:
	return maxi(1, ceili(force_pips(threshold) - 1e-6))


## Slowest of `speeds` at which a heavy swing run fully into the target meets `threshold`; 0 if none.
static func min_speed_for(loadout: ResolvedLoadout, threshold: float, speeds: Array[float]) -> float:
	if loadout == null:
		return 0.0
	var sorted: Array[float] = speeds.duplicate()
	sorted.sort()
	var swing: MeleeSwingDef = loadout.melee.heavy
	for s: float in sorted:
		var full := Tuning.strike_momentum(swing.impact, loadout.mods.melee_impact, s, Tuning.APPROACH_MAX, loadout.mods.approach_bonus)
		if meets(full, threshold):
			return s
	return 0.0


## Gauge segment count: enough for the full run-in heavy and the target's top tick (+15% headroom).
static func gauge_segments(heavy_full: float, top_tick: float) -> int:
	var need := maxf(heavy_full, top_tick * 1.15) / PIP_MOMENTUM
	return clampi(ceili(need - 1e-6), MIN_SEGMENTS, MAX_SEGMENTS)


## 0..1 position of `momentum` on a gauge of `segments` segments.
static func gauge_fraction(momentum: float, segments: int) -> float:
	if segments <= 0:
		return 0.0
	return clampf(momentum / (float(segments) * PIP_MOMENTUM), 0.0, 1.0)


# ───────────────────────────── what is she facing ─────────────────────────────

## The breakable, core or enemy the self at `pos` facing `dir` would most plausibly swing at: inside
## a FACING_HALF_ANGLE cone and within reach + FACING_EXTRA_RANGE, scored by distance plus an angle
## penalty. Broken breakables, activated cores and dead enemies are skipped.
static func pick_target(pos: Vector2, dir: float, reach: float, level: LevelDef, snap: FrameSnapshot) -> Target:
	var best := Target.new()
	var best_score := INF
	var max_d := reach + FACING_EXTRA_RANGE
	if level != null:
		for e: EntityDef in level.entities_of(EntityKind.BREAKABLE):
			var b := e as BreakableDef
			if _mech_on(snap, b.id):
				continue
			var c := Vector2(b.c + 0.5, b.r + 0.5)
			var sc := _score(pos, dir, c, max_d, 0.5)
			if sc < best_score:
				best_score = sc
				best = Target.new()
				best.kind = KIND_BREAKABLE
				best.id = b.id
				best.pos = c
				best.threshold = breakable_threshold(b)
				best.distance = pos.distance_to(c)
		for e: EntityDef in level.entities_of(EntityKind.CORE):
			var co := e as CoreDef
			if _mech_on(snap, co.id):
				continue
			var c := Vector2(co.x, co.y)
			var sc := _score(pos, dir, c, max_d, Combat.CORE_RADIUS)
			if sc < best_score:
				best_score = sc
				best = Target.new()
				best.kind = KIND_CORE
				best.id = co.id
				best.pos = c
				best.threshold = core_threshold(co)
				best.distance = pos.distance_to(c)
	if snap != null:
		for en: EnemySnap in snap.enemies:
			if not en.alive or en.state == EnemyStateName.DEAD:
				continue
			var st: Tuning.EnemyStats = Tuning.enemy_stats(en.type)
			var r := st.radius if st != null else 0.3
			var c := Vector2(en.x, en.y)
			var sc := _score(pos, dir, c, max_d + r, r)
			# Enemies win ties against scenery: they are what usually decides a fight.
			sc -= 0.15
			if sc < best_score:
				best_score = sc
				best = Target.new()
				best.kind = KIND_BOSS if en.type == EnemyType.BOSS else KIND_ENEMY
				best.id = en.id
				best.pos = c
				best.hp = en.hp
				best.max_hp = en.max_hp
				best.enemy_type = en.type
				best.shielded = en.has_shield and en.shield
				best.distance = pos.distance_to(c)
	return best


static func _mech_on(snap: FrameSnapshot, id: String) -> bool:
	if snap == null:
		return false
	var m := snap.mech(id)
	return m != null and m.on


## Distance + angle penalty, INF when outside the cone / range. `body` widens the cone like
## Combat.in_swing_volume does for a target's angular radius.
static func _score(pos: Vector2, dir: float, c: Vector2, max_d: float, body: float) -> float:
	var d := pos.distance_to(c)
	if d > max_d:
		return INF
	if d <= body:
		return d
	var ang := absf(TapeLib.angle_delta(dir, atan2(c.y - pos.y, c.x - pos.x)))
	var slack := asin(minf(1.0, body / d))
	if ang > FACING_HALF_ANGLE + slack:
		return INF
	return d + maxf(0.0, ang - slack) * 1.5


# ───────────────────────────── the gauge, as data ─────────────────────────────

## Build the gauge for the live self `actor` on a `tape_speed` tape, aimed along `dir` (pass NAN to
## use the body facing). `speeds` are the level's offered speeds (for "needs a faster tape").
static func gauge_state(actor: ActorSnap, tape_speed: float, dir: float, loadout: ResolvedLoadout, level: LevelDef, snap: FrameSnapshot, speeds: Array[float]) -> GaugeState:
	var g := GaugeState.new()
	if actor == null or loadout == null or not (tape_speed > 0.0):
		return g
	g.visible = true
	g.tape = actor.tape
	g.speed = tape_speed
	var aim := dir if is_finite(dir) else actor.facing
	var lv := local_velocity(actor, tape_speed)
	g.approach = Tuning.strike_approach(lv.x, lv.y, aim)
	g.light = preview_swing(loadout, ActionKind.LIGHT, tape_speed, lv.x, lv.y, aim)
	g.heavy = preview_swing(loadout, ActionKind.HEAVY, tape_speed, lv.x, lv.y, aim)
	g.target = pick_target(Vector2(actor.x, actor.y), aim, loadout.melee.reach, level, snap)
	g.ticks = target_ticks(g.target, loadout)
	var main := main_threshold(g.target, loadout)
	if main > 0.0:
		g.light_meets = meets(g.light.momentum, main)
		g.heavy_meets = meets(g.heavy.momentum, main)
		g.heavy_can_meet = meets(g.heavy.full, main)
		if g.target.kind == KIND_BREAKABLE or g.target.kind == KIND_CORE:
			g.min_speed = min_speed_for(loadout, main, speeds)
	if g.target.kind == KIND_ENEMY:
		g.light_hits = hits_to_kill(g.target.hp, g.light.damage)
		g.heavy_hits = hits_to_kill(g.target.hp, g.heavy.damage)
	var top := 0.0
	for t: Tick in g.ticks:
		top = maxf(top, t.momentum)
	g.segments = gauge_segments(g.heavy.full, top)
	return g


## The target's headline threshold: break / activate momentum, the kill tick for an enemy, the
## stagger tick for the boss. 0 when there is none.
static func main_threshold(t: Target, loadout: ResolvedLoadout) -> float:
	match t.kind:
		KIND_BREAKABLE, KIND_CORE:
			return t.threshold
		KIND_ENEMY:
			return momentum_for_damage(loadout, t.hp)
		KIND_BOSS:
			return BossBehaviour.BOSS_STAGGER_MOMENTUM
	return 0.0


## Ticks for a target: the threshold of a breakable/core; one tick per damage point an enemy still
## has (the last is the kill), plus the brute's shove line; the boss's stagger line.
static func target_ticks(t: Target, loadout: ResolvedLoadout) -> Array[Tick]:
	var out: Array[Tick] = []
	match t.kind:
		KIND_BREAKABLE:
			out.append(Tick.make(t.threshold, TICK_THRESHOLD, "BREAK"))
		KIND_CORE:
			out.append(Tick.make(t.threshold, TICK_THRESHOLD, "CHARGE"))
		KIND_ENEMY:
			for k: int in range(1, maxi(1, t.hp) + 1):
				var kind := TICK_KILL if k == t.hp else TICK_DAMAGE
				out.append(Tick.make(momentum_for_damage(loadout, k), kind, "KO" if k == t.hp else ""))
			if t.enemy_type == EnemyType.BRUTE:
				out.append(Tick.make(BruteBehaviour.BRUTE_POISE_MOMENTUM, TICK_SHOVE, "SHOVE"))
		KIND_BOSS:
			out.append(Tick.make(BossBehaviour.BOSS_STAGGER_MOMENTUM, TICK_STAGGER, "STAGGER"))
	return out


# ───────────────────────────── why did that swing fail ─────────────────────────────

## Explain a 'clang' or 'whiff' event of tape `tape` (other events / tapes: invalid).
static func failure_info(ev: SimEvent, tape: int, loadout: ResolvedLoadout) -> FailInfo:
	var f := FailInfo.new()
	if ev == null or (tape >= 0 and ev.tape != tape):
		return f
	f.tape = ev.tape
	f.pos = Vector2(ev.x, ev.y)
	f.had = ev.power if ev.has_power else 0.0
	if ev.type == SimEventType.CLANG:
		f.valid = true
		var d := ev.detail
		if d.begins_with("needs "):
			f.need = d.substr(6).to_float()
			f.title = "CLANG"
			f.line = "needs %s · had %s — run in or use a faster tape" % [fmt(f.need), fmt(f.had)]
		elif d == "momentum":
			f.need = momentum_for_damage(loadout, 1)
			f.title = "NO DAMAGE"
			f.line = "needs %s · had %s — swing harder" % [fmt(f.need), fmt(f.had)]
		elif d == "armour":
			f.title = "ARMOUR"
			f.line = "it is watching this tape — hit its back with another"
		elif d == "shield":
			f.title = "SHIELD"
			f.line = "shield popped — another tape must follow up"
		else:
			f.title = "CLANG"
			f.line = d
	elif ev.type == SimEventType.WHIFF:
		f.valid = true
		f.title = "WHIFF"
		f.line = "nothing in reach"
	return f


## Momentum formatted for a sticker: one decimal, trailing .0 dropped.
static func fmt(m: float) -> String:
	var r := roundf(m * 10.0) / 10.0
	if is_equal_approx(r, roundf(r)):
		return str(int(roundf(r)))
	return "%.1f" % r


## "0.5×", "2×".
static func speed_label(s: float) -> String:
	return "%s×" % fmt(s)
