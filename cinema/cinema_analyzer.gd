class_name CinemaAnalyzer
extends RefCounted
## Reads the solution's causal chain out of a resolved encounter: the actions (wind-up -> impact)
## the editor must never cut through, and the candidate moments (cause -> effect links) it may
## show. Pure: the same Resolution, level and context always give the same lists, in the same order.
##
## What counts as a link (docs/CINEMATIC.md "What the editor looks for"):
##   kills          multi-self kill (two tapes strike one enemy within 1.5 beats: the shielder
##                  pincer), knockback delivery (a hit moved the enemy > 0.75 tiles into another
##                  self's kill, or into a hazard), trap / environment kill, ranged kill (shot fired
##                  earlier), plain kill; a kill that interrupted an enemy winding up on ANOTHER self
##                  is a save.
##   rescue         a self that died in an earlier run of this attempt (Context.prior_events) is
##                  alive at that beat now; the cause is whoever killed / hit / distracted its killer.
##   desync         desync -> resync of one self, with the self that reopened the blocker.
##   mechanisms     switch / plate / break -> door / laser, and the OTHER self who then gets
##                  through (opened-for, plate-hold); otherwise a bare mechanism change.
##   boss           phase breaks; a memory strike whose remembered self is not there any more
##                  (fooled) or is (recall).
##   death          a self dying in the winning run.
##   objective      the climax, which absorbs the moment that completed it.

const MULTI_WINDOW_BEATS := 1.5
const KNOCKBACK_WINDOW_BEATS := 6.0
const KNOCKBACK_MIN_TILES := 0.75
const SAVE_WINDOW_BEATS := 3.0
const SHOT_WINDOW_BEATS := 8.0
const INTERACT_WINDOW_BEATS := 1.5
const BENEFIT_WINDOW_BEATS := 8.0
const BENEFIT_REACH := 1.0

var sc: CinemaScene
var ctx: CinemaTypes.Context
var ev: Array[SimEvent] = []
var moments: Array[CinemaMoment] = []
var actions: Array[CinemaTypes.Action] = []
## Wind-up start beat of each self swing, keyed "tape:sub".
var _swing_start: Dictionary[String, float] = {}
var _by_type: Dictionary[StringName, PackedInt32Array] = {}
var _frame_step_beats: float = 1.0


static func analyze(scene: CinemaScene, p_ctx: CinemaTypes.Context = null) -> CinemaAnalyzer:
	var a := CinemaAnalyzer.new()
	a.sc = scene
	a.ctx = p_ctx if p_ctx != null else CinemaTypes.Context.new()
	if scene.res != null:
		a.ev = scene.res.events
	a._index()
	a._build_actions()
	a._build_moments()
	return a


# ───────────────────────────── indexing ─────────────────────────────

func _index() -> void:
	for i: int in ev.size():
		var t := ev[i].type
		if not _by_type.has(t):
			_by_type[t] = PackedInt32Array()
		var arr: PackedInt32Array = _by_type[t]
		arr.append(i)
		_by_type[t] = arr
	if sc.frames.size() >= 2:
		_frame_step_beats = float(sc.frames[1].sub - sc.frames[0].sub) / sc.subs_per_beat


func _of(t: StringName) -> PackedInt32Array:
	return _by_type.get(t, PackedInt32Array())


func _b(i: int) -> float:
	return sc.beat_of(ev[i])


func _p(i: int) -> Vector2:
	return Vector2(ev[i].x, ev[i].y)


static func _who(t: int) -> String:
	return OD.tape_letter(t) if t >= 0 else "?"


func _name(id: String) -> String:
	if sc.enemy_types.has(id):
		return "%s %s" % [String(sc.enemy_types[id]), id]
	if sc.entity_kinds.has(id):
		return "%s %s" % [String(sc.entity_kinds[id]), id]
	return id


## The level entity id named inside a free-text cause ("struck by grunt g1", "blocked by door d1").
func _id_in_text(text: String) -> String:
	var best := ""
	for tok: String in text.replace("(", " ").replace(")", " ").replace(",", " ").split(" ", false):
		if sc.entity_kinds.has(tok) and tok.length() > best.length():
			best = tok
	return best


# ───────────────────────────── actions (never cut through these) ─────────────────────────────

func _windup_start(tape: int, beat: float, detail: String) -> float:
	var fallback := 0.7 if detail == "heavy" else 0.35
	var start := beat - fallback
	if _frame_step_beats <= 0.1:
		var b := beat - _frame_step_beats
		var found := -1.0
		while b > beat - 2.0:
			var an := sc.actor_anim(tape, b)
			if an == AnimState.LIGHT_WINDUP or an == AnimState.HEAVY_WINDUP:
				found = b
				b -= _frame_step_beats
			else:
				break
		if found >= 0.0:
			start = found
	return maxf(0.0, minf(start, beat - 0.2))


func _build_actions() -> void:
	for i: int in _of(SimEventType.SWING):
		var e := ev[i]
		var a := CinemaTypes.Action.new()
		a.what = "swing"
		a.impact_beat = _b(i)
		a.start_beat = _windup_start(e.tape, a.impact_beat, e.detail)
		a.tapes.append(e.tape)
		a.point = sc.actor_pos(e.tape, a.impact_beat, _p(i))
		for j: int in _of(SimEventType.HIT):
			if ev[j].sub == e.sub and ev[j].tape == e.tape and not ev[j].id.is_empty() and not a.ids.has(ev[j].id):
				a.ids.append(ev[j].id)
		_swing_start["%d:%d" % [e.tape, e.sub]] = a.start_beat
		actions.append(a)
	for i: int in _of(SimEventType.FIRE):
		var e := ev[i]
		var a := CinemaTypes.Action.new()
		a.what = "shot"
		a.start_beat = maxf(0.0, _b(i) - 0.25)
		a.impact_beat = _b(i) + 0.25
		a.tapes.append(e.tape)
		a.point = _p(i)
		for j: int in _of(SimEventType.PROJECTILE_HIT):
			if ev[j].sub > e.sub and ev[j].tape == e.tape and _b(j) - _b(i) <= 6.0:
				a.impact_beat = _b(j)
				if not ev[j].id.is_empty():
					a.ids.append(ev[j].id)
				break
		actions.append(a)
	var strikes := _merge_sorted([_of(SimEventType.ENEMY_ATTACK), _of(SimEventType.ENEMY_SHOT)])
	for i: int in _of(SimEventType.ENEMY_TELEGRAPH):
		var e := ev[i]
		var a := CinemaTypes.Action.new()
		a.what = "recall" if e.detail == "recall" else "telegraph"
		a.start_beat = _b(i)
		a.impact_beat = _b(i) + 1.0
		a.ids.append(e.id)
		if e.tape >= 0:
			a.tapes.append(e.tape)
		a.point = sc.enemy_pos(e.id, _b(i), _p(i))
		for j: int in strikes:
			if ev[j].sub > e.sub and ev[j].id == e.id:
				if _b(j) - _b(i) <= 4.0:
					a.impact_beat = _b(j)
				break
		# A memory strike lands on its remembered beat (bossRecall.power).
		if e.detail == "recall":
			for j: int in _of(SimEventType.BOSS_RECALL):
				if ev[j].sub == e.sub and ev[j].id == e.id and ev[j].has_power:
					a.impact_beat = maxf(a.impact_beat, ev[j].power)
		actions.append(a)
	for i: int in _of(SimEventType.INTERACT):
		var a := CinemaTypes.Action.new()
		a.what = "interact"
		a.start_beat = maxf(0.0, _b(i) - 0.25)
		a.impact_beat = _b(i)
		a.tapes.append(ev[i].tape)
		a.ids.append(ev[i].id)
		a.point = _p(i)
		actions.append(a)
	actions.sort_custom(func(x: CinemaTypes.Action, y: CinemaTypes.Action) -> bool:
		if not is_equal_approx(x.start_beat, y.start_beat):
			return x.start_beat < y.start_beat
		return x.impact_beat < y.impact_beat)


static func _merge_sorted(lists: Array[PackedInt32Array]) -> PackedInt32Array:
	var out := PackedInt32Array()
	for l: PackedInt32Array in lists:
		out.append_array(l)
	out.sort()
	return out


func _strike_start(tape: int, sub: int, beat: float) -> float:
	return _swing_start.get("%d:%d" % [tape, sub], maxf(0.0, beat - 0.35))


# ───────────────────────────── moments ─────────────────────────────

func _new(kind: StringName, cause_beat: float, key_beat: float) -> CinemaMoment:
	var m := CinemaMoment.new()
	m.kind = kind
	m.score = CinemaGrammar.score_of(kind)
	m.cause_beat = minf(cause_beat, key_beat)
	m.key_beat = key_beat
	return m


func _finish(m: CinemaMoment) -> void:
	if m.tapes.size() >= 2:
		m.score += CinemaGrammar.SCORE_MULTI_TAPE_BONUS
	moments.append(m)


func _build_moments() -> void:
	var kill_moment: Dictionary[int, CinemaMoment] = {}
	_kills(kill_moment)
	_boss_phases()
	var absorbed_deaths := _boss_recalls()
	_rescues(kill_moment)
	_desyncs()
	_mechanisms()
	_deaths(absorbed_deaths)
	_objective()
	moments.sort_custom(CinemaMoment.before)


func _kills(kill_moment: Dictionary[int, CinemaMoment]) -> void:
	var strikes := _merge_sorted([_of(SimEventType.HIT), _of(SimEventType.CLANG), _of(SimEventType.PROJECTILE_HIT)])
	var targets: Array[String] = []
	if sc.level != null:
		targets = sc.level.objective.targets
	for i: int in _of(SimEventType.KILL):
		var e := ev[i]
		var bk := _b(i)
		var k := e.tape
		var kp := _p(i)
		var who := _name(e.id)
		var m: CinemaMoment = null
		# Multi-self kill: another tape struck the same enemy just before.
		var partner := -1
		var partner_ev := -1
		for j: int in strikes:
			if ev[j].id != e.id or ev[j].tape < 0 or ev[j].tape == k:
				continue
			var bj := _b(j)
			if bj > bk + 1e-6 or bj < bk - MULTI_WINDOW_BEATS:
				continue
			if partner_ev < 0 or ev[j].sub < ev[partner_ev].sub:
				partner = ev[j].tape
				partner_ev = j
		if partner >= 0 and k >= 0:
			m = _new(CinemaGrammar.KIND_MULTI_KILL, _strike_start(partner, ev[partner_ev].sub, _b(partner_ev)), bk)
			m.cause_tape = partner
			m.effect_tape = k
			m.cause_point = sc.actor_pos(partner, _b(partner_ev))
			m.effect_point = kp
			m.source_events.append(partner_ev)
			var note := " - the shield can only face one of them" if sc.enemy_types.get(e.id, &"") == EnemyType.SHIELDER else ""
			m.reason = "%s and %s strike %s together%s; %s's %s finishes it" % [_who(partner), _who(k), who, note, _who(k), e.detail]
		else:
			# Knockback delivery: an earlier hit by someone else moved the enemy into this kill.
			var kb := -1
			for j: int in _of(SimEventType.HIT):
				if ev[j].id != e.id or ev[j].tape < 0 or ev[j].tape == k:
					continue
				var bj := _b(j)
				if bj >= bk - 0.02 or bj < bk - KNOCKBACK_WINDOW_BEATS:
					continue
				if _p(j).distance_to(kp) >= KNOCKBACK_MIN_TILES:
					kb = j
			if kb >= 0:
				var t := ev[kb].tape
				m = _new(CinemaGrammar.KIND_KNOCKBACK, _strike_start(t, ev[kb].sub, _b(kb)), bk)
				m.cause_tape = t
				m.effect_tape = k
				m.cause_point = _p(kb)
				m.effect_point = kp
				m.source_events.append(kb)
				var dist := _p(kb).distance_to(kp)
				if k >= 0:
					m.reason = "%s's %s knocks %s %.1f tiles - straight into %s's %s" % [_who(t), ev[kb].detail, who, dist, _who(k), e.detail]
				else:
					m.reason = "%s's %s knocks %s %.1f tiles - into the hazard" % [_who(t), ev[kb].detail, who, dist]
			elif k < 0:
				m = _new(CinemaGrammar.KIND_TRAP_KILL, maxf(0.0, bk - 1.0), bk)
				var hz := _hazard_before(bk, kp)
				m.cause_point = _p(hz) if hz >= 0 else kp
				if hz >= 0:
					m.source_events.append(hz)
					m.add_id(ev[hz].id)
					m.cause_beat = minf(m.cause_beat, _b(hz))
					m.reason = "%s springs on %s" % [_name(ev[hz].id), who]
				else:
					m.reason = "the level itself takes %s (%s)" % [who, e.detail]
				m.effect_point = kp
			else:
				var fire := -1
				if e.detail != "light" and e.detail != "heavy":
					for j: int in _of(SimEventType.FIRE):
						if ev[j].tape == k and ev[j].sub <= e.sub and _b(j) >= bk - SHOT_WINDOW_BEATS:
							fire = j
				if fire >= 0 and bk - _b(fire) >= 0.5:
					m = _new(CinemaGrammar.KIND_SHOT_KILL, maxf(0.0, _b(fire) - 0.25), bk)
					m.cause_point = _p(fire)
					m.source_events.append(fire)
					m.reason = "%s's %s from beat %.1f finds %s at beat %.1f" % [_who(k), ev[fire].detail, _b(fire), who, bk]
				else:
					m = _new(CinemaGrammar.KIND_KILL, _strike_start(k, e.sub, bk), bk)
					m.cause_point = sc.actor_pos(k, bk, kp)
					m.reason = "%s takes down %s (%s)" % [_who(k), who, e.detail]
				m.cause_tape = k
				m.effect_tape = k
				m.effect_point = kp
		m.add_tape(m.cause_tape)
		m.add_tape(k)
		m.add_id(e.id)
		m.source_events.append(i)
		if m.cause_tape >= 0:
			m.add_callout(CinemaTypes.Callout.of_tape(m.cause_tape, CinemaGrammar.ROLE_CAUSE))
		if k >= 0 and k != m.cause_tape:
			m.add_callout(CinemaTypes.Callout.of_tape(k, CinemaGrammar.ROLE_EFFECT))
		m.add_callout(CinemaTypes.Callout.of_id(e.id, CinemaGrammar.ROLE_TARGET, k if k >= 0 else m.cause_tape))
		if targets.has(e.id):
			m.score += CinemaGrammar.SCORE_TARGET_BONUS
		# A save: the enemy was winding up on another self and never got to strike.
		var saved := _saved_tape(e.id, e.sub, bk, k)
		if saved >= 0:
			if m.kind == CinemaGrammar.KIND_KILL:
				m.kind = CinemaGrammar.KIND_SAVE
				m.score = CinemaGrammar.score_of(CinemaGrammar.KIND_SAVE) + (CinemaGrammar.SCORE_TARGET_BONUS if targets.has(e.id) else 0.0)
			else:
				m.score += CinemaGrammar.SCORE_SAVE_BONUS
			m.reason += " - it was winding up on %s" % _who(saved)
			m.add_tape(saved)
			m.add_callout(CinemaTypes.Callout.of_tape(saved, CinemaGrammar.ROLE_EFFECT))
		m.source_events.sort()
		kill_moment[i] = m
		_finish(m)


func _saved_tape(id: String, sub: int, bk: float, killer: int) -> int:
	var tele := -1
	for j: int in _of(SimEventType.ENEMY_TELEGRAPH):
		if ev[j].id == id and ev[j].sub <= sub and _b(j) >= bk - SAVE_WINDOW_BEATS:
			tele = j
	if tele < 0 or ev[tele].tape < 0 or ev[tele].tape == killer:
		return -1
	for j: int in _merge_sorted([_of(SimEventType.ENEMY_ATTACK), _of(SimEventType.ENEMY_SHOT)]):
		if ev[j].id == id and ev[j].sub > ev[tele].sub and ev[j].sub <= sub:
			return -1
	return ev[tele].tape


## The latest hazard-ish event (trap / laser / door) near `p` in the two beats before `beat`.
func _hazard_before(beat: float, p: Vector2) -> int:
	var best := -1
	for t: StringName in [&"trap", SimEventType.LASER, SimEventType.DOOR]:
		for j: int in _of(t):
			var bj := _b(j)
			if bj > beat + 1e-6 or bj < beat - 2.0:
				continue
			var hp := _p(j)
			if hp.distance_to(p) > 4.0 and sc.entity_points.get(ev[j].id, hp).distance_to(p) > 4.0:
				continue
			if best < 0 or ev[j].sub > ev[best].sub:
				best = j
	return best


func _boss_phases() -> void:
	for i: int in _of(SimEventType.BOSS_PHASE):
		var e := ev[i]
		var bb := _b(i)
		var m := _new(CinemaGrammar.KIND_BOSS_PHASE, _strike_start(e.tape, e.sub, bb), bb)
		m.cause_tape = e.tape
		m.effect_tape = e.tape
		m.cause_point = sc.actor_pos(e.tape, bb, _p(i)) if e.tape >= 0 else _p(i)
		m.effect_point = _p(i)
		m.add_tape(e.tape)
		m.add_id(e.id)
		m.source_events.append(i)
		for j: int in _of(SimEventType.HIT):
			if ev[j].sub == e.sub and ev[j].id == e.id:
				m.source_events.append(j)
		m.source_events.sort()
		m.reason = "%s breaks %s's armour: %s" % [_who(e.tape), _name(e.id), e.detail]
		if e.tape >= 0:
			m.add_callout(CinemaTypes.Callout.of_tape(e.tape, CinemaGrammar.ROLE_CAUSE))
		m.add_callout(CinemaTypes.Callout.of_id(e.id, CinemaGrammar.ROLE_TARGET, e.tape))
		_finish(m)


## Returns the selfDeath event indices folded into a recall moment.
func _boss_recalls() -> PackedInt32Array:
	var used := PackedInt32Array()
	for i: int in _of(SimEventType.BOSS_RECALL):
		var e := ev[i]
		var rb := _b(i)
		var land := e.power if e.has_power and e.power >= rb else rb + 1.0
		var t := e.tape
		var death := -1
		for j: int in _of(SimEventType.SELF_DEATH):
			if ev[j].tape == t and _b(j) >= rb and _b(j) <= land + 0.5:
				death = j
				break
		var boss_at := sc.enemy_pos(e.id, rb)
		var m: CinemaMoment
		if death < 0:
			m = _new(CinemaGrammar.KIND_BOSS_FOOLED, rb, land)
			var real := sc.actor_pos(t, land) if t >= 0 else _p(i)
			m.reason = "%s remembers %s at (%.0f, %.0f) and strikes there on beat %.1f - but %s is not there any more" % [_name(e.id), _who(t), e.x, e.y, land, _who(t)]
			m.effect_point = _p(i)
			if real.distance_to(_p(i)) > CinemaGrammar.TWO_SHOT_MAX_DIST and not sc.same_room(real, _p(i)):
				m.simultaneous_far = true
		else:
			m = _new(CinemaGrammar.KIND_BOSS_RECALL, rb, _b(death))
			m.reason = "%s remembers %s's route (%s) - and the memory lands" % [_name(e.id), _who(t), e.detail]
			m.effect_point = _p(death)
			m.source_events.append(death)
			used.append(death)
		m.cause_point = boss_at
		m.cause_tape = -1
		m.effect_tape = t
		m.add_tape(t)
		m.add_id(e.id)
		m.source_events.append(i)
		m.source_events.sort()
		m.add_callout(CinemaTypes.Callout.of_id(e.id, CinemaGrammar.ROLE_CAUSE, t))
		if t >= 0:
			m.add_callout(CinemaTypes.Callout.of_tape(t, CinemaGrammar.ROLE_EFFECT))
		_finish(m)
	return used


func _rescues(kill_moment: Dictionary[int, CinemaMoment]) -> void:
	# One rescue per self: its latest prior death (the run the player just fixed).
	var latest: Dictionary[int, SimEvent] = {}
	for p: SimEvent in ctx.prior_events:
		if p.type == SimEventType.SELF_DEATH and p.tape >= 0:
			latest[p.tape] = p
	var keys: Array[int] = []
	for t: int in latest.keys():
		keys.append(t)
	keys.sort()
	for t: int in keys:
		var p: SimEvent = latest[t]
		var bp := sc.beat_of(p)
		if bp >= float(sc.horizon_beats):
			continue
		var died_now := false
		for j: int in _of(SimEventType.SELF_DEATH):
			if ev[j].tape == t and _b(j) <= bp + 0.25:
				died_now = true
		if died_now or not sc.tapes.has(t):
			continue
		var killer := _id_in_text(p.detail)
		var saver_ev := -1
		var how := ""
		if not killer.is_empty():
			for j: int in _of(SimEventType.KILL):
				if ev[j].id == killer and ev[j].tape >= 0 and ev[j].tape != t and _b(j) <= bp:
					saver_ev = j
					how = "takes out %s first" % _name(killer)
			if saver_ev < 0:
				for j: int in _merge_sorted([_of(SimEventType.HIT), _of(SimEventType.CLANG), _of(SimEventType.PROJECTILE_HIT)]):
					if ev[j].id == killer and ev[j].tape >= 0 and ev[j].tape != t and _b(j) <= bp and _b(j) >= bp - 3.0:
						saver_ev = j
						how = "knocks %s off its strike" % _name(killer)
		var m := _new(CinemaGrammar.KIND_RESCUE, maxf(0.0, bp - 1.0), bp)
		m.effect_tape = t
		m.effect_point = sc.actor_pos(t, bp, Vector2(p.x, p.y))
		m.cause_point = m.effect_point
		if saver_ev >= 0:
			var k := ev[saver_ev].tape
			m.cause_tape = k
			m.cause_beat = _strike_start(k, ev[saver_ev].sub, _b(saver_ev))
			m.cause_point = sc.actor_pos(k, _b(saver_ev), _p(saver_ev))
			m.add_tape(k)
			m.source_events.append(saver_ev)
			m.add_callout(CinemaTypes.Callout.of_tape(k, CinemaGrammar.ROLE_CAUSE))
			m.reason = "Last take %s died here at beat %.1f (%s). This time %s %s - %s lives" % [_who(t), bp, p.detail, _who(k), how, _who(t)]
			# The kill that did it is this rescue's cause: fold it in.
			if kill_moment.has(saver_ev):
				var km: CinemaMoment = kill_moment[saver_ev]
				var idx := moments.find(km)
				if idx >= 0:
					moments.remove_at(idx)
					m.absorb(km)
					m.score = maxf(m.score, km.score)
		else:
			m.reason = "Last take %s died here at beat %.1f (%s). This time %s walks on" % [_who(t), bp, p.detail, _who(t)]
		if not killer.is_empty():
			m.add_id(killer)
			m.add_callout(CinemaTypes.Callout.of_id(killer, CinemaGrammar.ROLE_TARGET, m.cause_tape))
		m.add_tape(t)
		m.add_callout(CinemaTypes.Callout.of_tape(t, CinemaGrammar.ROLE_EFFECT))
		m.source_events.sort()
		_finish(m)


func _desyncs() -> void:
	for i: int in _of(SimEventType.DESYNC):
		var e := ev[i]
		var t := e.tape
		var bd := _b(i)
		var re := -1
		for j: int in _of(SimEventType.RESYNC):
			if ev[j].tape == t and ev[j].sub > e.sub:
				re = j
				break
		var blocker := _id_in_text(e.detail)
		var m := _new(CinemaGrammar.KIND_DESYNC, maxf(0.0, bd - 0.75), _b(re) if re >= 0 else bd)
		m.cause_tape = t
		m.effect_tape = t
		m.cause_point = _p(i)
		m.effect_point = _p(re) if re >= 0 else _p(i)
		m.add_tape(t)
		m.add_id(blocker)
		m.source_events.append(i)
		m.add_callout(CinemaTypes.Callout.of_tape(t, CinemaGrammar.ROLE_SUBJECT))
		var reopen_by := -1
		if re >= 0:
			m.source_events.append(re)
			if not blocker.is_empty():
				for j: int in _merge_sorted([_of(SimEventType.DOOR), _of(SimEventType.BREAK)]):
					if ev[j].id == blocker and ev[j].sub > e.sub and ev[j].sub <= ev[re].sub and (ev[j].type == SimEventType.BREAK or ev[j].detail == "open"):
						var drv := _driver(j)
						reopen_by = drv[0]
						if reopen_by == t:
							reopen_by = -1
			if reopen_by >= 0:
				m.add_tape(reopen_by)
				m.add_callout(CinemaTypes.Callout.of_tape(reopen_by, CinemaGrammar.ROLE_CAUSE))
				m.reason = "%s's path is shut (%s) - she desyncs; %s reopens it and the spark catches up on beat %.1f" % [_who(t), e.detail, _who(reopen_by), _b(re)]
			else:
				m.reason = "%s desyncs (%s); her spark finds a way round and resyncs on beat %.1f" % [_who(t), e.detail, _b(re)]
		else:
			m.reason = "%s desyncs (%s) and plays on as a harmless projection" % [_who(t), e.detail]
		if not blocker.is_empty():
			m.add_callout(CinemaTypes.Callout.of_id(blocker, CinemaGrammar.ROLE_TARGET, reopen_by if reopen_by >= 0 else t))
		_finish(m)


## [driver tape (-1 none), cause beat, cause point x, cause point y, via (0 none, 1 switch, 2 plate,
## 3 strike), switch/plate id index into ev or -1] for a mechanism event.
func _driver(i: int) -> Array:
	var e := ev[i]
	var bi := _b(i)
	if e.type == SimEventType.BREAK or e.type == SimEventType.CORE:
		return [e.tape, _strike_start(e.tape, e.sub, bi), e.x, e.y, 3, -1]
	var best := -1
	for j: int in _of(SimEventType.INTERACT):
		var bj := _b(j)
		if ev[j].sub <= e.sub and bj >= bi - INTERACT_WINDOW_BEATS:
			best = j
	if best >= 0:
		return [ev[best].tape, _b(best), ev[best].x, ev[best].y, 1, best]
	for j: int in _of(SimEventType.PLATE):
		if absi(ev[j].sub - e.sub) <= 2 and ev[j].detail == "on":
			var pp := _p(j)
			var holder := -1
			var hd := 0.9
			var f := sc.frame_at_beat(bi)
			if f != null:
				for a: ActorSnap in f.actors:
					var d := sc.actor_pos(a.tape, bi).distance_to(pp)
					if d < hd and a.life != OD.LifeState.GHOST:
						hd = d
						holder = a.tape
			return [holder, _b(j), pp.x, pp.y, 2, j]
	return [-1, bi, e.x, e.y, 0, -1]


## First self other than `driver` that passes the mechanism while it stays favourable.
func _beneficiary(i: int, driver: int) -> Array:
	var e := ev[i]
	var b0 := _b(i)
	var b1 := minf(float(sc.horizon_beats), b0 + BENEFIT_WINDOW_BEATS)
	for j: int in range(i + 1, ev.size()):
		if ev[j].id == e.id and ev[j].type == e.type and ev[j].sub > e.sub:
			b1 = minf(b1, _b(j))
			break
	var laser_from := Vector2.INF
	var laser_to := Vector2.INF
	if e.type == SimEventType.LASER and sc.level != null:
		for ent: EntityDef in sc.level.entities:
			if ent.id == e.id and ent is LaserDef:
				laser_from = (ent as LaserDef).from
				laser_to = (ent as LaserDef).to
	var mp: Vector2 = sc.entity_points.get(e.id, _p(i))
	var step := 0.25
	var b := b0 + step
	while b <= b1 + 1e-6:
		for t: int in sc.tapes:
			if t == driver:
				continue
			if sc.actor_life(t, b) == OD.LifeState.GHOST:
				continue
			var p := sc.actor_body_pos(t, b)
			var d: float
			if laser_from != Vector2.INF:
				d = p.distance_to(Geometry2D.get_closest_point_to_segment(p, laser_from, laser_to))
			else:
				d = p.distance_to(mp)
			if d <= BENEFIT_REACH:
				return [t, b, p.x, p.y]
		b += step
	return [-1, 0.0, 0.0, 0.0]


func _mechanisms() -> void:
	var mech := _merge_sorted([_of(SimEventType.DOOR), _of(SimEventType.LASER), _of(SimEventType.BREAK)])
	for i: int in mech:
		var e := ev[i]
		var bi := _b(i)
		var favourable := e.type == SimEventType.BREAK or (e.type == SimEventType.DOOR and e.detail == "open") or (e.type == SimEventType.LASER and e.detail == "off")
		var drv := _driver(i)
		var driver: int = drv[0]
		var via: int = drv[4]
		var cause_point := Vector2(float(drv[2]), float(drv[3]))
		var ben := _beneficiary(i, driver) if favourable else [-1, 0.0, 0.0, 0.0]
		var bt: int = ben[0]
		var m: CinemaMoment
		var what := "%s %s" % [_name(e.id), e.detail if e.type != SimEventType.BREAK else "breaks"]
		if bt >= 0 and driver >= 0:
			var kind := CinemaGrammar.KIND_PLATE_HOLD if via == 2 else CinemaGrammar.KIND_OPENED_FOR
			m = _new(kind, float(drv[1]), float(ben[1]))
			m.effect_point = Vector2(float(ben[2]), float(ben[3]))
			m.effect_tape = bt
			if via == 2:
				m.reason = "%s holds the plate while %s crosses %s" % [_who(driver), _who(bt), _name(e.id)]
				# The holder is still standing on the plate when the other self crosses.
				if not sc.same_room(cause_point, m.effect_point) or cause_point.distance_to(m.effect_point) > CinemaGrammar.TWO_SHOT_MAX_DIST:
					m.simultaneous_far = true
			elif via == 1:
				m.reason = "%s throws %s - %s - %s goes through" % [_who(driver), _name(ev[int(drv[5])].id), what, _who(bt)]
			else:
				m.reason = "%s's hit: %s - %s goes through" % [_who(driver), what, _who(bt)]
			m.add_tape(driver)
			m.add_tape(bt)
			m.add_callout(CinemaTypes.Callout.of_tape(driver, CinemaGrammar.ROLE_CAUSE))
			m.add_callout(CinemaTypes.Callout.of_tape(bt, CinemaGrammar.ROLE_EFFECT))
		else:
			var kind2 := CinemaGrammar.KIND_BREAK if e.type == SimEventType.BREAK else CinemaGrammar.KIND_MECHANISM
			m = _new(kind2, float(drv[1]), bi)
			m.effect_point = sc.entity_points.get(e.id, _p(i))
			m.effect_tape = driver
			if driver >= 0:
				m.reason = "%s: %s" % [_who(driver), what]
				m.add_tape(driver)
				m.add_callout(CinemaTypes.Callout.of_tape(driver, CinemaGrammar.ROLE_CAUSE))
			else:
				m.reason = what
			if not favourable:
				m.score -= 6.0
		m.cause_tape = driver
		m.cause_point = cause_point
		m.add_id(e.id)
		m.source_events.append(i)
		if int(drv[5]) >= 0:
			m.source_events.append(int(drv[5]))
		m.source_events.sort()
		m.add_callout(CinemaTypes.Callout.of_id(e.id, CinemaGrammar.ROLE_TARGET, driver))
		_finish(m)


func _deaths(absorbed: PackedInt32Array) -> void:
	for i: int in _of(SimEventType.SELF_DEATH):
		if absorbed.has(i):
			continue
		var e := ev[i]
		var bd := _b(i)
		var killer := _id_in_text(e.detail)
		var m := _new(CinemaGrammar.KIND_DEATH, maxf(0.0, bd - 1.0), bd)
		m.effect_tape = e.tape
		m.effect_point = _p(i)
		m.cause_point = sc.enemy_pos(killer, bd, _p(i)) if not killer.is_empty() else _p(i)
		m.add_tape(e.tape)
		m.add_id(killer)
		m.source_events.append(i)
		m.reason = "%s falls (%s) - the others carry the plan" % [_who(e.tape), e.detail]
		m.add_callout(CinemaTypes.Callout.of_tape(e.tape, CinemaGrammar.ROLE_SUBJECT))
		if not killer.is_empty():
			m.add_callout(CinemaTypes.Callout.of_id(killer, CinemaGrammar.ROLE_CAUSE, e.tape))
		_finish(m)


func _objective() -> void:
	var obj := _of(SimEventType.OBJECTIVE)
	if obj.is_empty():
		return
	var i := obj[0]
	var bo := _b(i)
	var text := sc.level.objective.text if sc.level != null else ""
	var otype := sc.level.objective.type if sc.level != null else &""
	# The moment that completed it (the final kill, the last core, the phase break ...).
	var best: CinemaMoment = null
	for m: CinemaMoment in moments:
		if m.kind == CinemaGrammar.KIND_DEATH:
			continue
		if m.kind == CinemaGrammar.KIND_MECHANISM and otype != ObjectiveType.SIGNAL:
			continue
		if absf(m.key_beat - bo) <= 0.05 and (best == null or CinemaMoment.before(m, best)):
			best = m
	var core_ev := -1
	for j: int in _of(SimEventType.CORE):
		if absi(ev[j].sub - ev[i].sub) <= 2:
			core_ev = j
	if best == null and core_ev < 0 and bo < 1.0:
		# Satisfied at the start (nothing to destroy): the opening shows it.
		return
	var c := _new(CinemaGrammar.KIND_CLIMAX, maxf(0.0, bo - 1.0), bo)
	c.source_events.append(i)
	var survivors: Array[int] = []
	if sc.res != null:
		survivors = sc.res.outcome.survivors
	if best != null:
		moments.erase(best)
		c.absorb(best)
		c.cause_beat = best.cause_beat
		c.cause_point = best.cause_point
		c.effect_point = best.effect_point
		c.cause_tape = best.cause_tape
		c.effect_tape = best.effect_tape
		c.simultaneous_far = best.simultaneous_far
		c.reason = "Objective: %s - %s" % [text, best.reason]
	elif core_ev >= 0:
		var k := ev[core_ev].tape
		c.cause_tape = k
		c.effect_tape = k
		c.cause_beat = _strike_start(k, ev[core_ev].sub, _b(core_ev))
		c.cause_point = sc.actor_pos(k, bo, _p(core_ev))
		c.effect_point = _p(core_ev)
		c.add_tape(k)
		c.add_id(ev[core_ev].id)
		c.source_events.append(core_ev)
		c.add_callout(CinemaTypes.Callout.of_tape(k, CinemaGrammar.ROLE_CAUSE))
		c.add_callout(CinemaTypes.Callout.of_id(ev[core_ev].id, CinemaGrammar.ROLE_TARGET, k))
		c.reason = "Objective: %s - %s lights the last core" % [text, _who(k)]
	elif otype == ObjectiveType.REACH:
		var exit_p := sc.level_centre()
		for ent: EntityDef in sc.level.entities:
			if ent is ExitDef:
				exit_p = sc.entity_points.get(ent.id, exit_p)
		c.cause_beat = maxf(0.0, bo - 2.0)
		c.cause_point = sc.crowd_pos(c.cause_beat, survivors)
		c.effect_point = exit_p
		var who := ""
		for t: int in survivors:
			c.add_tape(t)
			c.add_callout(CinemaTypes.Callout.of_tape(t, CinemaGrammar.ROLE_EFFECT))
			who += _who(t)
		c.cause_tape = survivors[0] if not survivors.is_empty() else -1
		c.effect_tape = c.cause_tape
		c.reason = "Objective: %s - %s on the exit as the tape runs out" % [text, who if not who.is_empty() else "a self"]
	else:
		c.cause_point = sc.crowd_pos(bo)
		c.effect_point = c.cause_point
		c.reason = "Objective: %s" % text
	c.score = CinemaGrammar.score_of(CinemaGrammar.KIND_CLIMAX)
	c.source_events.sort()
	moments.append(c)
