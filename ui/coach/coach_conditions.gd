class_name CoachConditions
extends RefCounted
## Evaluates coach-mark conditions (docs/ONBOARDING.md "Conditions"; data/onboarding/vocabulary.json)
## against a CoachContext. Node-free.
##
## A condition is an object with one key (several keys are accepted and must all hold):
##   all [..] / any [..] / not cond
##   firstTimePhase, phaseIs, phaseElapsed, shownFor, beat, takeProgress, tapesCommitted,
##   deckStatusIs, speedsOffered, activeSpeedIs, endModesOffered, activeEndModeIs, outcomeIs,
##   retriesThisTake, levelsCleared, liveSelfIs, selfIs, selfFateChanged, liveSelfNear,
##   liveSelfTravelled, eventSeen, inputUsed, inputNotUsedFor, sessionActionUsed, markDone
## `N` is a number (exact) or { "min": a, "max": b } (inclusive, either optional).
## The first satisfied eventSeen / selfIs / selfFateChanged leaf (depth-first, never under `not`)
## binds the mark's subject (Binding). `scope: "save"` leaves that come true are stored as facts in
## the seen store (fact.<key>) so they stay true in later sessions.

const PREDICATES: Array[String] = [
	"firstTimePhase", "phaseIs", "phaseElapsed", "shownFor", "beat", "takeProgress", "tapesCommitted",
	"deckStatusIs", "speedsOffered", "activeSpeedIs", "endModesOffered", "activeEndModeIs", "outcomeIs",
	"retriesThisTake", "levelsCleared", "liveSelfIs", "selfIs", "selfFateChanged", "liveSelfNear",
	"liveSelfTravelled", "eventSeen", "inputUsed", "inputNotUsedFor", "sessionActionUsed", "markDone",
]
const COMBINATORS: Array[String] = ["all", "any", "not"]
const END_NAMES: Array[String] = ["stop", "repeat", "reverse"]
## Enemy ids vs mechanism ids for eventSeen `target` are told apart through the level / snapshot.


## The subject a trigger bound: an event (tape, id, x, y) or a self (tape).
class Binding:
	extends RefCounted
	var has: bool = false
	## "event" | "self"
	var kind: String = ""
	var tape: int = -1
	var id: String = ""
	var pos: Vector2 = Vector2.ZERO
	var has_pos: bool = false

	func copy() -> Binding:
		var b := Binding.new()
		b.has = has
		b.kind = kind
		b.tape = tape
		b.id = id
		b.pos = pos
		b.has_pos = has_pos
		return b


## Evaluate. `shown_at` is when the mark became visible (for shownFor / scope "shown"); `bind`
## (optional) receives the subject.
static func eval(cond: Variant, ctx: CoachContext, shown_at: float = 0.0, bind: Binding = null) -> bool:
	return _eval(cond, ctx, shown_at, bind, false)


static func _eval(cond: Variant, ctx: CoachContext, shown_at: float, bind: Binding, negated: bool) -> bool:
	if cond == null:
		return false
	if cond is bool:
		return cond
	if cond is Array:
		for c: Variant in cond:
			if not _eval(c, ctx, shown_at, bind, negated):
				return false
		return true
	if not (cond is Dictionary):
		return false
	var d: Dictionary = cond
	if d.is_empty():
		return true
	for k: Variant in d:
		if not _leaf(str(k), d[k], ctx, shown_at, bind, negated):
			return false
	return true


## Problems in a condition (unknown predicates). [] when fine.
static func validate(cond: Variant, where: String = "") -> Array[String]:
	var out: Array[String] = []
	_validate(cond, where, out)
	return out


static func _validate(cond: Variant, where: String, out: Array[String]) -> void:
	if cond == null or cond is bool:
		return
	if cond is Array:
		for c: Variant in cond:
			_validate(c, where, out)
		return
	if not (cond is Dictionary):
		out.append("%s: condition is not an object" % where)
		return
	for k: Variant in cond:
		var key := str(k)
		if COMBINATORS.has(key):
			var v: Variant = (cond as Dictionary)[k]
			if key == "not":
				_validate(v, where, out)
			elif v is Array:
				for c: Variant in v:
					_validate(c, where, out)
			else:
				out.append("%s: '%s' needs a list" % [where, key])
		elif not PREDICATES.has(key):
			out.append("%s: unknown condition '%s'" % [where, key])


# ───────────────────────────── leaves ─────────────────────────────

static func _leaf(key: String, v: Variant, ctx: CoachContext, shown_at: float, bind: Binding, negated: bool) -> bool:
	var view := ctx.view
	match key:
		"all":
			var arr: Array = v if v is Array else [v]
			for c: Variant in arr:
				if not _eval(c, ctx, shown_at, bind, negated):
					return false
			return true
		"any":
			var arr: Array = v if v is Array else [v]
			for c: Variant in arr:
				if _eval(c, ctx, shown_at, bind, negated):
					return true
			return false
		"not":
			return not _eval(v, ctx, shown_at, bind, true)
		"firstTimePhase":
			return String(ctx.phase) == str(v) and ctx.first_visit
		"phaseIs":
			return _one_of(String(ctx.phase), v)
		"phaseElapsed":
			return num(ctx.phase_time(), v)
		"shownFor":
			return num(ctx.clock - shown_at, v)
		"beat":
			return view != null and num(view.beat, v)
		"takeProgress":
			if view == null:
				return false
			for d: DeckView in view.decks:
				if d.status == DeckStatus.RECORDING:
					return num(d.local_progress, v)
			return false
		"tapesCommitted":
			return num(_count_status(view, DeckStatus.COMMITTED), v)
		"deckStatusIs":
			return _deck_status(v, view)
		"speedsOffered":
			return view != null and num(view.speeds.size(), v)
		"activeSpeedIs":
			var d := _active_deck(view)
			return d != null and d.speed > 0.0 and num(d.speed, v)
		"endModesOffered":
			return view != null and num(view.end_modes.size(), v)
		"activeEndModeIs":
			var d := _active_deck(view)
			return d != null and d.end_mode >= 0 and d.end_mode < END_NAMES.size() and END_NAMES[d.end_mode] == str(v)
		"outcomeIs":
			var o: Outcome = view.outcome if view != null else null
			match str(v):
				"none":
					return o == null
				"win":
					return o != null and o.win
				"fail":
					return o != null and not o.win
			return false
		"retriesThisTake":
			return num(ctx.retries_this_take, v)
		"levelsCleared":
			return num(ctx.levels_cleared, v)
		"liveSelfIs":
			return _live_self_is(str(v), ctx)
		"selfIs":
			return _self_is(v, ctx, bind, negated)
		"selfFateChanged":
			return _fate_changed(v, ctx, bind, negated)
		"liveSelfNear":
			return _near(v, ctx)
		"liveSelfTravelled":
			if not (v is Dictionary):
				return false
			var sd: Dictionary = v
			var scope := str(sd.get("scope", "phase"))
			return _save_fact(key, v, ctx, func() -> bool:
				return ctx.travelled_since(ctx.scope_start(scope, shown_at)) + 1e-6 >= float(sd.get("tiles", 0.0)))
		"eventSeen":
			return _event_seen(v, ctx, shown_at, bind, negated)
		"inputUsed":
			if not (v is Dictionary):
				return false
			var id: Dictionary = v
			var scope := str(id.get("scope", "phase"))
			return _save_fact(key, v, ctx, func() -> bool:
				var n := _count_log(ctx.inputs, id.get("input", "any"), ctx.scope_start(scope, shown_at))
				return at_least(n, id.get("count", 1)))
		"inputNotUsedFor":
			if not (v is Dictionary) or ctx.phase != SessionPhase.RECORDING:
				return false
			var nd: Dictionary = v
			var last := ctx.phase_start
			for e: Array in ctx.inputs:
				if float(e[0]) >= ctx.phase_start and str(e[1]) == str(nd.get("input", "")):
					last = maxf(last, float(e[0]))
			return ctx.clock - last + 1e-6 >= float(nd.get("seconds", 0.0))
		"sessionActionUsed":
			if not (v is Dictionary):
				return false
			var ad: Dictionary = v
			var scope := str(ad.get("scope", "phase"))
			return _save_fact(key, v, ctx, func() -> bool:
				return _count_log(ctx.actions, ad.get("action", ""), ctx.scope_start(scope, shown_at)) >= 1)
		"markDone":
			return ctx.visit_done.has(str(v)) or (ctx.seen != null and ctx.seen.has("coach." + str(v)))
	return false


## N: a number (exact) or { min, max } (inclusive).
static func num(have: float, want: Variant) -> bool:
	if want is int or want is float:
		return is_equal_approx(have, float(want))
	if want is Dictionary:
		var d: Dictionary = want
		if d.has("min") and have < float(d["min"]) - 1e-6:
			return false
		if d.has("max") and have > float(d["max"]) + 1e-6:
			return false
		return true
	return false


## Event / input counts: a plain number means "at least" (ONBOARDING.md); { min, max } as N.
static func at_least(n: int, need: Variant) -> bool:
	if need is int or need is float:
		return n >= int(need)
	return num(n, need)


static func _one_of(have: String, want: Variant) -> bool:
	if want is Array:
		for w: Variant in want:
			if str(w) == have:
				return true
		return false
	return str(want) == have


static func _active_deck(view: SessionView) -> DeckView:
	if view == null or view.active < 0 or view.active >= view.decks.size():
		return null
	return view.decks[view.active]


static func _count_status(view: SessionView, status: StringName) -> int:
	var n := 0
	if view != null:
		for d: DeckView in view.decks:
			if d.status == status:
				n += 1
	return n


static func _deck_status(v: Variant, view: SessionView) -> bool:
	if view == null or not (v is Dictionary):
		return false
	var spec: Dictionary = v
	var which: Variant = spec.get("deck", "active")
	var status := str(spec.get("status", ""))
	if which is String and which == "any":
		for d: DeckView in view.decks:
			if String(d.status) == status:
				return true
		return false
	var d: DeckView = null
	if which is String and which == "active":
		d = _active_deck(view)
	elif (which is int or which is float) and int(which) >= 0 and int(which) < view.decks.size():
		d = view.decks[int(which)]
	return d != null and String(d.status) == status


## Actor state for a tape: from the snapshot when there is one, else from its deck.
static func _state_of(ctx: CoachContext, tape: int) -> Dictionary:
	var a := ctx.actor(tape)
	if a != null:
		return {"life": a.life, "synced": a.synced}
	if ctx.view != null and tape >= 0 and tape < ctx.view.decks.size():
		var d := ctx.view.decks[tape]
		if d.life >= 0:
			return {"life": d.life, "synced": d.synced}
	return {}


static func _live_self_is(want: String, ctx: CoachContext) -> bool:
	var s := _state_of(ctx, ctx.live_tape())
	if s.is_empty():
		return false
	match want:
		"alive":
			return s["life"] == OD.LifeState.ALIVE and s["synced"]
		"recGhost":
			return s["life"] == OD.LifeState.REC_GHOST
		"desynced":
			return s["life"] == OD.LifeState.ALIVE and not s["synced"]
	return false


static func _who(v: Variant, ctx: CoachContext) -> Array[int]:
	var out: Array[int] = []
	if v is String and v == "previous":
		out = ctx.previous_tapes()
	elif v is int or v is float:
		out.append(int(v))
	out.sort()
	return out


static func _self_is(v: Variant, ctx: CoachContext, bind: Binding, negated: bool) -> bool:
	if not (v is Dictionary):
		return false
	var d: Dictionary = v
	var want := str(d.get("state", ""))
	for t: int in _who(d.get("who", "previous"), ctx):
		var s := _state_of(ctx, t)
		if s.is_empty():
			continue
		var ok := false
		match want:
			"alive":
				ok = s["life"] == OD.LifeState.ALIVE and s["synced"]
			"ghost":
				ok = s["life"] != OD.LifeState.ALIVE
			"desynced":
				ok = s["life"] == OD.LifeState.ALIVE and not s["synced"]
		if ok:
			_bind_self(bind, negated, t, ctx)
			return true
	return false


static func _fate_changed(v: Variant, ctx: CoachContext, bind: Binding, negated: bool) -> bool:
	if not (v is Dictionary) or ctx.view == null:
		return false
	var d: Dictionary = v
	var to := str(d.get("to", ""))
	for t: int in _who(d.get("who", "previous"), ctx):
		if t < 0 or t >= ctx.view.decks.size():
			continue
		var deck := ctx.view.decks[t]
		if deck.status != DeckStatus.COMMITTED:
			continue
		var death_beat := -1.0
		for m: DeckStateMark in deck.state_marks:
			if m.kind == StateMarkKind.DEATH:
				death_beat = m.beat
				break
		var ok := false
		if to == "dead":
			if death_beat < 0.0:
				for e: Array in ctx.events:
					if float(e[0]) >= ctx.phase_start and str(e[1]) == String(SimEventType.SELF_DEATH) and int(e[2]) == t:
						ok = true
						break
		elif to == "alive":
			if death_beat >= 0.0 and ctx.view.beat >= death_beat + 0.5:
				var s := _state_of(ctx, t)
				ok = not s.is_empty() and s["life"] == OD.LifeState.ALIVE
		if ok:
			_bind_self(bind, negated, t, ctx)
			return true
	return false


static func _bind_self(bind: Binding, negated: bool, tape: int, ctx: CoachContext) -> void:
	if bind == null or negated or bind.has:
		return
	bind.has = true
	bind.kind = "self"
	bind.tape = tape
	var a := ctx.actor(tape)
	if a != null:
		bind.pos = Vector2(a.x, a.y)
		bind.has_pos = true


static func _near(v: Variant, ctx: CoachContext) -> bool:
	if not (v is Dictionary):
		return false
	var d: Dictionary = v
	var a := ctx.actor(ctx.live_tape())
	if a == null:
		return false
	var p := CoachWorld.nearest(ctx, str(d.get("kind", "")), Vector2(a.x, a.y))
	return p != Vector2.INF and p.distance_to(Vector2(a.x, a.y)) <= float(d.get("tiles", 0.0)) + 1e-6


static func _tape_ok(tape: int, sel: Variant, ctx: CoachContext) -> bool:
	if sel == null:
		return true
	if sel is String:
		match sel:
			"any":
				return true
			"live":
				return tape >= 0 and tape == ctx.live_tape()
			"previous":
				return tape >= 0 and ctx.previous_tapes().has(tape)
		return false
	return tape == int(sel)


static func _event_seen(v: Variant, ctx: CoachContext, shown_at: float, bind: Binding, negated: bool) -> bool:
	if not (v is Dictionary):
		return false
	var d: Dictionary = v
	var scope := str(d.get("scope", "phase"))
	if scope == "save" and ctx.seen != null and ctx.seen.has(fact_key("eventSeen", v)):
		return true
	var from := ctx.scope_start(scope, shown_at)
	var want_type := str(d.get("type", ""))
	var need: Variant = d.get("count", 1)
	var n := 0
	var last: Array = []
	for e: Array in ctx.events:
		if float(e[0]) < from - 1e-6 or str(e[1]) != want_type:
			continue
		if d.has("tape") and not _tape_ok(int(e[2]), d["tape"], ctx):
			continue
		var det := str(e[3])
		if d.has("detail") and det != str(d["detail"]):
			continue
		if d.has("detailPrefix") and not det.begins_with(str(d["detailPrefix"])):
			continue
		if d.has("detailSuffix") and not det.ends_with(str(d["detailSuffix"])):
			continue
		if d.has("detailIn") and not (d["detailIn"] is Array and (d["detailIn"] as Array).has(det)):
			continue
		if d.has("target") and CoachWorld.target_kind(ctx, str(e[4])) != str(d["target"]):
			continue
		n += 1
		last = e
	var ok := at_least(n, need)
	if ok and not last.is_empty() and bind != null and not negated and not bind.has:
		bind.has = true
		bind.kind = "event"
		bind.tape = int(last[2])
		bind.id = str(last[4])
		bind.pos = Vector2(float(last[5]), float(last[6]))
		bind.has_pos = true
	if ok and scope == "save" and ctx.seen != null:
		ctx.seen.mark(fact_key("eventSeen", v))
	return ok


## `scope: "save"` leaves: true when the stored fact exists; else evaluate and store when true.
static func _save_fact(pred: String, v: Variant, ctx: CoachContext, test: Callable) -> bool:
	var is_save := v is Dictionary and str((v as Dictionary).get("scope", "phase")) == "save"
	if is_save and ctx.seen != null and ctx.seen.has(fact_key(pred, v)):
		return true
	var ok: bool = test.call()
	if ok and is_save and ctx.seen != null:
		ctx.seen.mark(fact_key(pred, v))
	return ok


## Stable seen-store key for a save-scope leaf.
static func fact_key(pred: String, v: Variant) -> String:
	return "fact.%s:%s" % [pred, JSON.stringify(v, "", true)]


static func _count_log(log: Array[Array], want: Variant, from: float) -> int:
	var n := 0
	for e: Array in log:
		if float(e[0]) < from - 1e-6:
			continue
		var name := str(e[1])
		if want is Array:
			if (want as Array).has(name):
				n += 1
		elif str(want) == "any" or str(want) == name:
			n += 1
	return n
