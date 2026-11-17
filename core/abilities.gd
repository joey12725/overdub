class_name Abilities
extends RefCounted
## Gear abilities that are simulation rules (GEAR chapter, AbilityId in core/types/ability_id.gd).
## Port of prototype/src/core/abilities.ts.
##
## Where each ability lives:
##   manualDesync  `manual_desync` below, registered by core/sim.gd as the 'ability' event handler
##                 (OPEN-11: the only way a live self can desync). Held sparks are honoured in sim.gd
##                 phase 2.
##   lowProfile    `effective_distance` below; EnemyCommon.perceived_distance delegates to it.
##   loudmouth     ditto.
##   beatSight     `upcoming_attack_beats` below, exposed as ODSim.threat_beats (the HUD draws it).
##   laserProof    combat.gd CombatQueue.resolve (laser hits are ignored).
##   heavyStep     mechanisms.gd plate occupancy (heavy plates).
##   phaseDodge    player.gd (live dodge ignores low barriers) + actors.gd is_obstructed (playback).
##   slideStrike   `slide_strike_factor` below, applied inside Combat.melee_momentum.
##   parry         `parry_projectiles` below, run by sim.gd at the start of the projectile phase.
##   killRefresh   sim.gd on_melee_kill → PlayerController.refresh_dodge (live self only: a playback
##                 tape's dodges are already fixed, so there is nothing to refund).
##
## Every rule reads the shared loadout (all four cassettes wear the same gear) and recorded tape
## data only, so record mode and playback agree wherever the rule itself allows.

# ───────────────────────────── lowProfile / loudmouth ─────────────────────────────

## 'lowProfile': enemies read this loadout's selves as this many times farther away.
const LOW_PROFILE_FACTOR: float = 1.5
## 'loudmouth': enemies read this loadout's selves as this many times nearer (factor < 1).
const LOUDMOUTH_FACTOR: float = 0.75


## Distance between an enemy and a self as enemy decision logic perceives it, for a loadout's
## abilities. The single helper every enemy range / targeting rule goes through (via
## EnemyCommon.perceived_distance). Both abilities together multiply.
static func effective_distance(abilities: Array[StringName], d: float) -> float:
	var k := 1.0
	if abilities.has(AbilityId.LOW_PROFILE):
		k *= LOW_PROFILE_FACTOR
	if abilities.has(AbilityId.LOUDMOUTH):
		k *= LOUDMOUTH_FACTOR
	return d * k


# ───────────────────────────── manualDesync ─────────────────────────────

## Desync cause reported for a voluntary desync (SimEvent.detail, outcome notes).
const MANUAL_DESYNC_CAUSE: String = "manual desync"


## 'ability' event handler for 'manualDesync'. Each firing of the event toggles:
##
##   synced self          → voluntary desync: harmless and invulnerable like any desync (DESYNC-07);
##                          its spark appears where the body was and is HELD there (it does not
##                          chase the projection, so it cannot resync by itself).
##   held spark           → release. The live self simply re-syncs in place (its body is the
##                          projection). A playback self's spark now obeys the ordinary catch-up
##                          rules (DESYNC-02..05), so on replay it rejoins only once it has
##                          travelled to the projection.
##   involuntarily desynced (a playback self obstructed before its 'on' press) → its spark is held
##                          where it is, so the recorded on/off presses stay paired: the next press
##                          releases it instead of starting a new desync.
##
## A reverse pass fires the event again, so it toggles again. A dead playback ghost never gets here
## (the dispatcher drops its events); the recording ghost may toggle, which only matters in its take.
## Signature matches ODSim.register_ability_handler's handler: (w, self_actor, ev, pass_dir).
static func manual_desync(w: ODSim, self_actor: SelfActor, _ev: TapeEvent, _pass_dir: int) -> void:
	if self_actor.life == OD.LifeState.GHOST:
		return
	if self_actor.spark_held:
		self_actor.spark_held = false
		if self_actor.live and not self_actor.synced:
			self_actor.synced = true
			self_actor.spark = null
			self_actor.last_valid_x = self_actor.pose.x
			self_actor.last_valid_y = self_actor.pose.y
			w.emit(SimEvent.make(0, SimEventType.RESYNC, self_actor.pose.x, self_actor.pose.y) \
				.with_tape(self_actor.index).with_detail(MANUAL_DESYNC_CAUSE))
			w.log.resync(self_actor.index, w.s)
		return
	if self_actor.synced:
		w.desync(self_actor, MANUAL_DESYNC_CAUSE)
		self_actor.spark_held = not self_actor.synced
		return
	self_actor.spark_held = true


# ───────────────────────────── slideStrike ─────────────────────────────

## 'slideStrike': momentum multiplier of a swing started straight out of a dodge.
const SLIDE_STRIKE_MUL: float = 1.5
## A swing counts as "ending a dodge into a strike" if it starts within this many local ticks of the dodge's end.
const SLIDE_STRIKE_WINDOW_TICKS: int = 8


## Momentum multiplier 'slideStrike' gives a recorded swing: SLIDE_STRIKE_MUL when the swing started
## within SLIDE_STRIKE_WINDOW_TICKS local ticks after a recorded dodge on the same tape finished,
## else 1. Judged from the tape alone, so record and replay agree. Only on a forward pass: on a
## reverse pass the body runs backward out of the swing into the dodge, which is not a slide into a
## strike (MOM-03: direction matters).
static func slide_strike_factor(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> float:
	if pass_dir != 1 or (ev.kind != ActionKind.LIGHT and ev.kind != ActionKind.HEAVY):
		return 1.0
	if not w.loadout.abilities.has(AbilityId.SLIDE_STRIKE):
		return 1.0
	var dodge_len: int = PlayerController.action_timing(ActionKind.DODGE, w.loadout).commit
	for d: TapeEvent in self_actor.tape.events:
		if d.kind != ActionKind.DODGE or d.tick >= ev.tick:
			continue
		var since := ev.tick - (d.tick + dodge_len)
		if since >= 0 and since <= SLIDE_STRIKE_WINDOW_TICKS:
			return SLIDE_STRIKE_MUL
	return 1.0


# ───────────────────────────── parry ─────────────────────────────

## 'parry': while a heavy swing's hit volume is live, every enemy projectile inside the volume (with
## a clear line from the swinging self) is reflected straight back the way it came. The reflected
## shot is a fresh bolt owned by the parrying tape: it no longer hurts selves, it strikes enemies
## (including the one that fired it) and a kill is credited to that tape. A parry counts as the swing
## connecting (no 'whiff'). Runs at the start of the projectile phase, before projectiles move, so a
## bolt is turned before it can touch the self. Only a self that can act parries.
## Runs every substep: allocates nothing unless a projectile is actually parried.
static func parry_projectiles(w: ODSim) -> void:
	if not w.loadout.abilities.has(AbilityId.PARRY):
		return
	var mel: MeleeWeaponDef = w.loadout.melee
	var arc := (mel.arc_deg * PI) / 180.0
	var s: int = w.s
	for self_actor: SelfActor in w.selves:
		if not self_actor.can_act or self_actor.swings.is_empty():
			continue
		for sw: SelfActor.ActiveSwing in self_actor.swings:
			if sw.kind != ActionKind.HEAVY or s < sw.start or s >= sw.end:
				continue
			var ox: float = self_actor.pose.x
			var oy: float = self_actor.pose.y
			var list: Array[Projectile] = w.projectiles.list
			# The count is taken once: reflected bolts appended below are not re-examined this pass.
			var n := list.size()
			for i in n:
				var p: Projectile = list[i]
				if not p.alive or p.owner_enemy.is_empty():
					continue
				if not Combat.in_swing_volume(ox, oy, sw.dir, mel.reach, arc, p.x, p.y, p.radius):
					continue
				if w.grid.segment_blocked(ox, oy, p.x, p.y, true):
					continue
				p.alive = false
				sw.connected = true
				var dir := TapeLib.wrap_angle(p.dir + PI)
				var spec := SpawnSpec.new()
				spec.owner_tape = self_actor.index
				spec.archetype = RangedArchetype.BOLT
				spec.x = p.x
				spec.y = p.y
				spec.dir = dir
				spec.speed = p.speed
				spec.radius = p.radius
				spec.range = ProjectileSystem.BOLT_RANGE
				spec.momentum = p.momentum
				spec.set_hits_selves(false)
				spec.hits_enemies = true
				w.projectiles.spawn(w, spec)
				w.emit(SimEvent.make(0, SimEventType.PROJECTILE_HIT, p.x, p.y).with_tape(self_actor.index) \
					.with_id(p.owner_enemy).with_dir(dir).with_detail("parry"))


# ───────────────────────────── beatSight ─────────────────────────────

## Default look-ahead of ODSim.threat_beats, master beats.
const BEAT_SIGHT_LOOKAHEAD_BEATS: float = 8.0


## Is this enemy currently set on attacking someone? (has a live target, or a target within its reach in sight)
static func _engaged(w: ODSim, e: EnemyState) -> bool:
	if e.target >= 0:
		for s: SelfActor in w.selves:
			if s.index == e.target and EnemyCommon.targetable(s):
				return true
	for s: SelfActor in w.selves:
		if not EnemyCommon.targetable(s):
			continue
		# Math.hypot: ODGrid.hypot reproduces V8 bit for bit (a naive sqrt can differ in the last bit).
		var d := effective_distance(w.loadout.abilities, ODGrid.hypot(s.pose.x - e.x, s.pose.y - e.y))
		if d <= e.stats.reach and not w.grid.segment_blocked(e.x, e.y, s.pose.x, s.pose.y, true):
			return true
	return false


## Master beats of upcoming enemy attacks, from the instant `at` (a substep boundary) up to
## `look_ahead_beats` beats later, sorted and without duplicates. This is what the 'beatSight' HUD
## draws on the master ruler; it is a forecast from the current state, not a simulation of the
## future (the live take's future input is unknown):
##   - a telegraphing enemy contributes its committed attack instant exactly;
##   - every other living, awake enemy that is engaged (it has a target, or a self is inside its
##     reach in line of sight) contributes each instant of its beat grid in the window that it could
##     still telegraph for (a stagger or knockback slide that outlasts the telegraph start rules a
##     grid instant out; AI-07 attacks only land on the grid).
## Sleeping and dead enemies contribute nothing.
##
## Port addition: an enemy whose behaviour implements EnemyBehaviour.forecast_attack_subs (returns
## true) replaces the generic grid rule above with its own sharper forecast; the committed instant
## of a telegraphing enemy is listed either way.
static func upcoming_attack_beats(w: ODSim, at: int, look_ahead_beats: float) -> Array[float]:
	var spb: int = w.spb
	var end: float = at + maxf(0.0, look_ahead_beats) * spb
	# Grid instants are whole substeps, so `g <= end` and `g <= floor(end)` agree.
	var end_sub: int = floori(end)
	# Set<number> in the prototype; the keys are sorted below, so insertion order never matters.
	var subs: Dictionary[int, bool] = {}
	var forecast: Array[int] = []
	for e: EnemyState in w.enemies:
		if not e.alive or not e.awake:
			continue
		var telegraphing: bool = e.state == EnemyStateName.TELEGRAPH and e.attack_sub >= at
		if telegraphing and e.attack_sub <= end:
			subs[e.attack_sub] = true
		if e.beh != null:
			forecast.clear()
			if e.beh.forecast_attack_subs(w, e, at, end_sub, forecast):
				for g: int in forecast:
					if g >= at and g <= end_sub:
						subs[g] = true
				continue
		if not _engaged(w, e):
			continue
		var tel: int = EnemyCommon.telegraph_subs(w, e)
		var busy_until: int = maxi(e.stagger_until, at + e.knock_subs)
		var g: float = EnemyCommon.next_grid_sub(w, e, at)
		while g <= end and is_finite(g):
			var gi := int(g)
			# Skipped: the committed attack (already listed) and grid instants before it.
			if not (telegraphing and gi <= e.attack_sub):
				# Its telegraph would have had to start already (or while it is still reeling): it cannot land.
				if not (gi - tel < at or gi - tel < busy_until):
					subs[gi] = true
			g = EnemyCommon.next_grid_sub(w, e, gi + 1)
	var keys: Array[int] = []
	keys.assign(subs.keys())
	keys.sort()
	var out: Array[float] = []
	out.resize(keys.size())
	for i in keys.size():
		# Float division as in JS (s / w.spb).
		out[i] = float(keys[i]) / float(spb)
	return out
