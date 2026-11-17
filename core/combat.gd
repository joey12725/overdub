class_name Combat
extends RefCounted
## Combat resolution (prototype core/combat.ts; COMBAT-01..04, MOM-01..06, HEALTH-01..04).
##
## Everything that hurts something is queued during a substep and applied together in the
## damage-resolution phase (CombatQueue), so hits that land on the same substep are simultaneous and
## the order systems run in never decides who wins a trade.
##
##   SelfHit      - something tries to kill a self (enemy strike, bolt, laser). One hit is lethal
##                  (HEALTH-01) unless the self is no longer vulnerable or is inside dodge i-frames.
##                  Enemy hits never displace a recorded self (MOM-06): they kill it or do nothing.
##   EnemyStrike  - momentum delivered to an enemy (melee, projectiles, environment). Converted into
##                  damage, real knockback (MOM-05) and stagger by the shared formulas in Tuning;
##                  an enemy behaviour's on_hit hook may veto or rewrite it (shields, armour).
##   Object hits  - melee swings (and, in the port, a self's projectiles) against breakables and
##                  cores compare momentum with a threshold and 'clang' when too weak (Scenario K),
##                  naming the momentum that was missing (Mechanisms.strike_objects /
##                  Mechanisms.projectile_strike_object).
##
## Extension points:
##   - `melee_momentum` is the single place a swing's momentum is computed. Gear that changes it
##     (slideStrike, ...) should wrap or extend this function rather than recomputing elsewhere.
##   - `w.combat.strike_enemy(...)` is the entry point projectile archetypes use to deliver
##     momentum; `w.combat.hit_self(...)` is how enemy weapons kill selves.
##
## JS vs GDScript: Math.hypot -> sqrt(a*a + b*b); Math.round -> EnemyCommon._js_round (half up).

## Radius of a core's struck body, tiles.
const CORE_RADIUS: float = 0.4


## A self dies (or, for the live take, becomes a recording ghost).
static func _kill_self(w: ODSim, s: SelfActor, h: SelfHit) -> void:
	s.life = OD.LifeState.REC_GHOST if s.live else OD.LifeState.GHOST
	s.death_sub = w.s
	s.death_cause = h.cause
	# A playback self's pending attempts die with it (GHOST-05). The recording ghost keeps acting in
	# its own take (GHOST-03), so an attack already under way still lands.
	if not s.live:
		s.swings.clear()
		s.scheduled.clear()
	w.emit(SimEvent.make(0, SimEventType.SELF_DEATH, s.pose.x, s.pose.y).with_tape(s.index).with_dir(h.dir).with_detail(h.cause))
	w.log.death(s.index, w.s, h.cause)


## Apply one strike to an enemy: behaviour veto, damage, knockback, stagger, death.
static func apply_strike(w: ODSim, e: EnemyState, strike: EnemyStrike) -> void:
	if not e.alive:
		return
	var st: EnemyStrike = strike
	var r: HitResponse = e.beh.on_hit(w, e, st)
	if r.kind == HitResponse.KIND_BLOCK:
		var bt: int = st.source.tape
		w.emit(
			SimEvent.make(0, SimEventType.CLANG, e.x, e.y)
			.with_id(e.id)
			.with_tape(bt)
			.with_power(st.momentum)
			.with_dir(st.dir)
			.with_detail(r.reason)
		)
		if bt >= 0:
			w.log.weak(bt, w.s, st.kind, e.id, st.momentum, NAN, r.reason)
		return
	if r.kind == HitResponse.KIND_REPLACE:
		st = r.strike
	var mel: MeleeWeaponDef = w.loadout.melee
	var mods: StatMods = w.loadout.mods
	var dmg: float = st.damage if st.has_damage else float(Tuning.strike_damage(st.momentum, mel.damage_eff, mods.damage))
	var kb: float = (
		st.knockback
		if st.has_knockback
		else Tuning.strike_knockback(st.momentum, mel.knockback_eff, mods.knockback, mods.knockback_cap, e.stats.mass)
	)
	var stg: float = (
		st.stagger if st.has_stagger else Tuning.strike_stagger(st.momentum, mel.stagger_eff, mods.stagger, e.stats.poise)
	)
	var t: int = st.source.tape
	w.emit(
		SimEvent.make(0, SimEventType.HIT, e.x, e.y).with_id(e.id).with_tape(t).with_power(st.momentum).with_dir(st.dir).with_detail(st.kind)
	)
	if dmg <= 0.0:
		# The hit landed but did no damage: say so, so the player can tell the swing lacked momentum.
		w.emit(
			SimEvent.make(0, SimEventType.CLANG, e.x, e.y)
			.with_id(e.id)
			.with_tape(t)
			.with_power(st.momentum)
			.with_dir(st.dir)
			.with_detail("momentum")
		)
		if t >= 0:
			w.log.weak(t, w.s, st.kind, e.id, st.momentum, NAN, "no damage")
	# hp is an int in the port; damage is a whole number of points (Tuning.strike_damage floors it).
	e.hp -= int(dmg)
	if e.hp <= 0:
		e.hp = 0
		EnemyCommon.kill_enemy(w, e, st)
		if st.melee and t >= 0:
			w.on_melee_kill(t)
		return
	if kb > 0.0:
		EnemyCommon.apply_knockback(w, e, st.dir, kb)
	if stg > 0.0:
		EnemyCommon.apply_stagger(w, e, EnemyCommon._js_round(stg * OD.SUB_HZ))

# ───────────────────────────── melee ─────────────────────────────


## Momentum of a recorded swing when it fires (MOM-01..04). The event's recorded local velocity is
## the body's motion into the strike; on a reverse pass the body is moving backward along its path,
## so that velocity is negated (MOM-03: direction matters). Tape speed enters once, inside
## swing_momentum (the master-time conversion of both swing and body velocity).
static func melee_momentum(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> float:
	var swing: MeleeSwingDef = w.loadout.melee.heavy if ev.kind == ActionKind.HEAVY else w.loadout.melee.light
	var base: float = Tuning.swing_momentum(
		swing, w.loadout.mods, self_actor.tape.speed, ev.vx * pass_dir, ev.vy * pass_dir, ev.dir
	)
	# 'slideStrike' gear: a swing started straight out of a dodge hits harder (Abilities).
	return base * Abilities.slide_strike_factor(w, self_actor, ev, pass_dir)


## Open a swing for a crossed light/heavy event: windup now, hit volume live for the active window.
static func open_swing(w: ODSim, self_actor: SelfActor, ev: TapeEvent, cross_sub: int, pass_dir: int) -> void:
	if ev.kind != ActionKind.LIGHT and ev.kind != ActionKind.HEAVY:
		return
	var t: PlayerController.ActionTiming = PlayerController.action_timing(ev.kind, w.loadout)
	var sw := SelfActor.ActiveSwing.new()
	sw.kind = ev.kind
	sw.dir = ev.dir
	sw.cross_sub = cross_sub
	sw.start = cross_sub + t.active_start * self_actor.m
	sw.end = cross_sub + t.active_end * self_actor.m
	sw.momentum = melee_momentum(w, self_actor, ev, pass_dir)
	sw.pass_dir = pass_dir
	self_actor.swings.append(sw)


## Is point (px, py) with radius pr inside a swing's hit volume from (ox, oy)?
static func in_swing_volume(ox: float, oy: float, dir: float, reach: float, arc_rad: float, px: float, py: float, pr: float) -> bool:
	var dx: float = px - ox
	var dy: float = py - oy
	var d: float = sqrt(dx * dx + dy * dy)
	if d > reach + pr:
		return false
	if d <= pr:
		return true
	# Widen the arc by the target's angular radius so a body grazing the edge of the arc is struck.
	var slack: float = asin(minf(1.0, pr / d))
	return absf(TapeLib.angle_delta(dir, atan2(dy, dx))) <= arc_rad / 2.0 + slack


## Test every live swing against enemies, breakables and cores. Runs in the damage-resolution phase,
## after enemies and knockback have moved, so a body delivered into a recorded swing is struck
## (TEST-19, MOM-05). The swing's origin is the self's current recorded position (PLAY-01).
static func resolve_swings(w: ODSim) -> void:
	var mel: MeleeWeaponDef = w.loadout.melee
	var arc: float = (mel.arc_deg * PI) / 180.0
	var reach: float = mel.reach
	var s: int = w.s
	for self_actor: SelfActor in w.selves:
		var swings: Array[SelfActor.ActiveSwing] = self_actor.swings
		if swings.is_empty():
			continue
		for i: int in range(swings.size() - 1, -1, -1):
			var ended: SelfActor.ActiveSwing = swings[i]
			if s >= ended.end:
				if ended.announced and not ended.connected:
					w.emit(
						SimEvent.make(0, SimEventType.WHIFF, self_actor.pose.x, self_actor.pose.y)
						.with_tape(self_actor.index)
						.with_dir(ended.dir)
						.with_power(ended.momentum)
						.with_detail(ended.kind)
					)
				swings.remove_at(i)
		if not self_actor.can_act:
			continue
		for sw: SelfActor.ActiveSwing in swings:
			if s < sw.start or s >= sw.end:
				continue
			var ox: float = self_actor.pose.x
			var oy: float = self_actor.pose.y
			if not sw.announced:
				sw.announced = true
				w.emit(
					SimEvent.make(0, SimEventType.SWING, ox, oy)
					.with_tape(self_actor.index)
					.with_dir(sw.dir)
					.with_power(sw.momentum)
					.with_detail(sw.kind)
				)
			for e: EnemyState in w.enemies:
				if not e.alive or sw.struck.has(e.id):
					continue
				if not in_swing_volume(ox, oy, sw.dir, reach, arc, e.x, e.y, e.stats.radius):
					continue
				if w.grid.segment_blocked(ox, oy, e.x, e.y, true):
					continue
				sw.struck[e.id] = true
				sw.connected = true
				w.combat.strike_enemy(
					e, EnemyStrike.make(StrikeSource.of_tape(self_actor.index), sw.kind, sw.momentum, sw.dir, e.x, e.y).with_melee()
				)
			w.mechs.strike_objects(w, self_actor, sw, ox, oy, reach, arc)


## Threshold of a core (CoreDef.threshold, or the default when the level gives none).
static func core_threshold(threshold: float, has_threshold: bool) -> float:
	return threshold if has_threshold else Tuning.DEFAULT_CORE_THRESHOLD
