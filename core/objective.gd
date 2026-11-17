class_name ObjectiveTracker
extends RefCounted
## Objectives, the run log and the Outcome (prototype core/objective.ts; REC-06, REC-07,
## HEALTH-04, TEST-23/24).
##
## The objective latches the first substep it is satisfied ('reach' is judged at the horizon). The
## Outcome is: win = objective latched AND at least one self 'alive' (a desynced-but-alive self
## counts as a survivor; it cannot hold an exit).
##
## Notes explain the run in the game's own terms (TEST chapter: "failures can be explained"): who
## died at which beat and to what, which self desynced, where, and whether its spark caught up,
## which swing lacked the momentum for what, and what part of the objective is missing.
##
## JS vs GDScript: numbers in notes are printed the way JS String(n) prints them (js_number: "5",
## "1.2", never "5.0"); Math.round is round-half-up (floor(x + 0.5)).


class DeathRecord:
	extends RefCounted
	var tape: int = 0
	var sub: int = 0
	var cause: String = ""


class DesyncRecord:
	extends RefCounted
	var tape: int = 0
	var sub: int = 0
	var cause: String = ""


class ResyncRecord:
	extends RefCounted
	var tape: int = 0
	var sub: int = 0


class WeakHitRecord:
	extends RefCounted
	var tape: int = 0
	var sub: int = 0
	var kind: String = ""
	var target: String = ""
	var momentum: float = 0.0
	## Threshold that was needed, when there is one (has_need).
	var need: float = 0.0
	var has_need: bool = false
	var reason: String = ""


class KillRecord:
	extends RefCounted
	var id: String = ""
	var sub: int = 0
	var by: String = ""


var complete: bool = false
var complete_sub: int = -1
var _level: LevelDef = null


func _init(level: LevelDef) -> void:
	_level = level


## Objective-latch phase of a substep.
func update(w: ODSim) -> void:
	if complete:
		return
	if _satisfied_now(w):
		complete = true
		complete_sub = w.s
		w.emit(SimEvent.make(0, SimEventType.OBJECTIVE, 0.0, 0.0).with_detail(String(_level.objective.type)))


func _satisfied_now(w: ODSim) -> bool:
	var obj: ObjectiveDef = _level.objective
	match obj.type:
		ObjectiveType.ELIMINATE:
			for e: EnemyState in w.enemies:
				if _is_target(obj.targets, e.id) and e.alive:
					return false
			return true
		ObjectiveType.ACTIVATE:
			for c: Mechanisms.CoreState in w.mechs.cores:
				if _is_target(obj.targets, c.def.id) and not c.on:
					return false
			return true
		ObjectiveType.BOSS:
			var any: bool = false
			for e: EnemyState in w.enemies:
				if not _is_boss(obj.targets, e):
					continue
				any = true
				if e.alive:
					return false
			return any
		ObjectiveType.REACH:
			return w.now >= w.horizon_subs and _exit_held(w, obj.targets)
		ObjectiveType.SIGNAL:
			return ODSignals.eval_signal(obj.when_expr, w.signals, w.beat) if obj.when_expr != null else false
	return false


func progress(w: ODSim) -> float:
	var obj: ObjectiveDef = _level.objective
	if complete:
		return 1.0
	match obj.type:
		ObjectiveType.ELIMINATE:
			var n: int = 0
			var dead: int = 0
			for e: EnemyState in _target_enemies(w, obj.targets):
				n += 1
				if not e.alive:
					dead += 1
			return 1.0 if n == 0 else float(dead) / n
		ObjectiveType.ACTIVATE:
			var cn: int = 0
			var on: int = 0
			for c: Mechanisms.CoreState in _target_cores(w, obj.targets):
				cn += 1
				if c.on:
					on += 1
			return 1.0 if cn == 0 else float(on) / cn
		ObjectiveType.BOSS:
			var hp: float = 0.0
			var mx: float = 0.0
			for b: EnemyState in _boss_enemies(w, obj.targets):
				hp += b.hp
				mx += b.max_hp
			return 1.0 - hp / mx if mx > 0.0 else 0.0
		ObjectiveType.REACH:
			return 1.0 if _exit_held(w, obj.targets) else 0.0
		ObjectiveType.SIGNAL:
			return 0.0
	return 0.0


func snapshot(w: ODSim) -> ObjectiveSnap:
	var survivors: int = 0
	for s: SelfActor in w.selves:
		if s.life == OD.LifeState.ALIVE:
			survivors += 1
	var o := ObjectiveSnap.new()
	o.complete = complete
	o.progress = progress(w)
	o.survivors = survivors
	return o


static func _is_target(targets: Array[String], id: String) -> bool:
	return targets.is_empty() or targets.has(id)


static func _is_boss(targets: Array[String], e: EnemyState) -> bool:
	if not targets.is_empty():
		return targets.has(e.id)
	return e.type == EnemyType.BOSS


static func _target_enemies(w: ODSim, targets: Array[String]) -> Array[EnemyState]:
	if targets.is_empty():
		return w.enemies
	var out: Array[EnemyState] = []
	for e: EnemyState in w.enemies:
		if targets.has(e.id):
			out.append(e)
	return out


static func _boss_enemies(w: ODSim, targets: Array[String]) -> Array[EnemyState]:
	var out: Array[EnemyState] = []
	for e: EnemyState in w.enemies:
		if _is_boss(targets, e):
			out.append(e)
	return out


static func _target_cores(w: ODSim, targets: Array[String]) -> Array[Mechanisms.CoreState]:
	var out: Array[Mechanisms.CoreState] = []
	for c: Mechanisms.CoreState in w.mechs.cores:
		if _is_target(targets, c.def.id):
			out.append(c)
	return out


## Any listed exit (all exits when none are listed) currently held by an alive, synced self.
static func _exit_held(w: ODSim, targets: Array[String]) -> bool:
	for x: Mechanisms.ExitState in w.mechs.exits:
		if not targets.is_empty() and not targets.has(x.def.id):
			continue
		if x.on:
			return true
	return false

# ───────────────────────────── outcome ─────────────────────────────


## "Tape A" ... "Tape D".
static func tape_name(t: int) -> String:
	return "Tape %s" % OD.TAPE_NAMES[t]


## A number as JavaScript's String(n) prints it ("5", "1.2", "0.6"): integers without a fraction,
## otherwise the shortest decimal that reads back as the same float.
static func js_number(v: float) -> String:
	if is_nan(v):
		return "NaN"
	if is_inf(v):
		return "Infinity" if v > 0.0 else "-Infinity"
	if v == floorf(v) and absf(v) < 1e15:
		return str(int(v))
	for d: int in range(1, 18):
		var s: String = String.num(v, d)
		if s.to_float() == v:
			return s
	return String.num(v, 17)


## JS Math.round(n * 100) / 100.
static func _round2(n: float) -> float:
	return floorf(n * 100.0 + 0.5) / 100.0


## Master beat of a substep event, formatted for notes (beats count from 0 like the ruler).
static func format_beat(w: ODSim, sub: int) -> String:
	return "beat %s" % js_number(_round2(float(sub) / w.spb))


static func _fmt_num(n: float) -> String:
	return js_number(_round2(n))


## The outcome as of now (authoritative for playback at the horizon).
static func build_outcome(w: ODSim, tracker: ObjectiveTracker, level: LevelDef) -> Outcome:
	var survivors: Array[int] = []
	for s: SelfActor in w.selves:
		if s.life == OD.LifeState.ALIVE:
			survivors.append(s.index)
	var objective_complete: bool = tracker.complete
	var win: bool = objective_complete and survivors.size() > 0
	var notes: Array[String] = []
	var log: RunLog = w.log

	if objective_complete:
		notes.append("Objective complete at %s: %s." % [format_beat(w, tracker.complete_sub), level.objective.text])
	else:
		notes.append("Objective not complete: %s. %s" % [level.objective.text, _missing_objective(w, level)])

	for d: DeathRecord in log.deaths:
		notes.append("%s died at %s: %s." % [tape_name(d.tape), format_beat(w, d.sub), d.cause])

	for s: SelfActor in w.selves:
		var ds: Array[DesyncRecord] = []
		for d: DesyncRecord in log.desyncs:
			if d.tape == s.index:
				ds.append(d)
		var rs: Array[ResyncRecord] = []
		for r: ResyncRecord in log.resyncs:
			if r.tape == s.index:
				rs.append(r)
		for i: int in ds.size():
			var d: DesyncRecord = ds[i]
			var head: String = "%s desynced at %s (%s)" % [tape_name(d.tape), format_beat(w, d.sub), d.cause]
			if i < rs.size():
				notes.append("%s; its spark caught up at %s." % [head, format_beat(w, rs[i].sub)])
			else:
				notes.append("%s; its spark never caught up." % head)
		if not s.synced and s.life == OD.LifeState.ALIVE:
			notes.append("%s ended the run desynced: it survives, but it could not act or hold an exit." % tape_name(s.index))

	var seen: Dictionary[String, bool] = {}
	for h: WeakHitRecord in log.weak_hits:
		var key: String = "%d|%s|%s" % [h.tape, h.kind, h.target]
		if seen.has(key):
			continue
		seen[key] = true
		if h.has_need:
			notes.append(
				(
					"%s's %s at %s hit %s with momentum %s; it needs %s."
					% [tape_name(h.tape), h.kind, format_beat(w, h.sub), h.target, _fmt_num(h.momentum), _fmt_num(h.need)]
				)
			)
		else:
			notes.append(
				(
					"%s's %s at %s hit %s but did no damage (%s, momentum %s)."
					% [tape_name(h.tape), h.kind, format_beat(w, h.sub), h.target, h.reason, _fmt_num(h.momentum)]
				)
			)

	var reason: StringName = &""
	if not objective_complete:
		reason = FailReason.OBJECTIVE
	elif survivors.is_empty():
		reason = FailReason.NO_SURVIVOR
		notes.append("No self survived to the end: the objective needs at least one survivor.")
	if not survivors.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for t: int in survivors:
			names.append(tape_name(t))
		notes.append("Survivors: %s." % ", ".join(names))

	var out := Outcome.new()
	out.win = win
	out.objective_complete = objective_complete
	out.survivors = survivors
	out.notes = notes
	out.reason = reason
	return out


static func _missing_objective(w: ODSim, level: LevelDef) -> String:
	var obj: ObjectiveDef = level.objective
	match obj.type:
		ObjectiveType.ELIMINATE:
			var left: PackedStringArray = PackedStringArray()
			for e: EnemyState in _target_enemies(w, obj.targets):
				if e.alive:
					left.append("%s %s" % [e.type, e.id])
			return "Still standing: %s." % ", ".join(left) if not left.is_empty() else ""
		ObjectiveType.ACTIVATE:
			var cl: PackedStringArray = PackedStringArray()
			for c: Mechanisms.CoreState in _target_cores(w, obj.targets):
				if not c.on:
					cl.append("core %s" % c.def.id)
			return "Not activated: %s." % ", ".join(cl) if not cl.is_empty() else ""
		ObjectiveType.BOSS:
			var bosses: Array[EnemyState] = _boss_enemies(w, obj.targets)
			if bosses.is_empty():
				return "There is no boss in this level."
			var parts: PackedStringArray = PackedStringArray()
			for b: EnemyState in bosses:
				if b.alive:
					parts.append("%s survived with %d of %d hp." % [b.id, b.hp, b.max_hp])
			return " ".join(parts)
		ObjectiveType.REACH:
			if w.now >= w.horizon_subs:
				return "No alive, synced self was in the exit when the encounter ended."
			return "The encounter has not ended yet."
		ObjectiveType.SIGNAL:
			return "The required condition never happened."
	return ""
