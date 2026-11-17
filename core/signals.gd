class_name ODSignals
extends RefCounted
## Signal logic: the boolean expressions that drive doors, lasers, wake conditions and objectives.
## Port of prototype/src/core/signals.ts. Never instantiated.
##
## Signals are named booleans in one table owned by the kernel (switch states, plates, breakables,
## cores, exits…). An id missing from the table reads as false, so an expression referring to a
## mechanism that never fired is simply off. The table (signals.ts SignalTable) is a
## Dictionary[String, bool].


## Evaluate an expression against the signal table at a master beat.
##
##  and([]) is true, or([]) is false (identity elements).
##  beat { every, from, to } is true while (masterBeat mod every) ∈ [from, to). When from > to the
##  window wraps around the cycle (e.g. every 4, from 3, to 1 covers beats 3..4 and 0..1).
##  from == to is an empty window. every ≤ 0 is never true.
static func eval_signal(expr: SignalExpr, signals: Dictionary[String, bool], master_beat: float) -> bool:
	match expr.op:
		SignalExpr.Op.SIG:
			return signals.get(expr.sig, false) == true
		SignalExpr.Op.NOT:
			return not eval_signal(expr.args[0], signals, master_beat)
		SignalExpr.Op.AND:
			for e: SignalExpr in expr.args:
				if not eval_signal(e, signals, master_beat):
					return false
			return true
		SignalExpr.Op.OR:
			for e: SignalExpr in expr.args:
				if eval_signal(e, signals, master_beat):
					return true
			return false
		SignalExpr.Op.XOR:
			return eval_signal(expr.args[0], signals, master_beat) != eval_signal(expr.args[1], signals, master_beat)
		SignalExpr.Op.CONST:
			return expr.value
		SignalExpr.Op.BEAT:
			return in_beat_window(master_beat, expr.every, expr.from, expr.to)
	push_error("Unknown SignalExpr op %d" % expr.op)
	return false


## The beat-window predicate on its own (also used for HUD previews of beat-timed mechanisms).
static func in_beat_window(master_beat: float, every: float, from: float, to: float) -> bool:
	if not (every > 0.0):
		return false
	# JS `%` on doubles is fmod (sign follows the dividend), as here.
	var p := fmod(master_beat, every)
	if p < 0.0:
		p += every
	# Guard the representable edge where p + every rounds back to exactly `every`.
	if p >= every:
		p = 0.0
	var f := _mod(from, every)
	var t := _mod(to, every)
	if from == to:
		return false
	# A window of a whole cycle or more is always on.
	if absf(to - from) >= every:
		return true
	if f < t:
		return p >= f and p < t
	if f > t:
		return p >= f or p < t
	# Distinct from/to that coincide modulo `every` (and span < every) cannot happen; treat as empty.
	return false


static func _mod(a: float, m: float) -> float:
	var r := fmod(a, m)
	return r + m if r < 0.0 else r


## Every signal id an expression reads, added to `out` (insertion order follows a left-to-right walk;
## the prototype's Set<string> is a Dictionary[String, bool] with values true).
static func collect_signal_ids(expr: SignalExpr, out: Dictionary[String, bool] = {}) -> Dictionary[String, bool]:
	match expr.op:
		SignalExpr.Op.SIG:
			out[expr.sig] = true
		SignalExpr.Op.NOT:
			collect_signal_ids(expr.args[0], out)
		SignalExpr.Op.AND, SignalExpr.Op.OR:
			for e: SignalExpr in expr.args:
				collect_signal_ids(e, out)
		SignalExpr.Op.XOR:
			collect_signal_ids(expr.args[0], out)
			collect_signal_ids(expr.args[1], out)
	return out


## True if the expression depends on the beat clock (so it can change without any signal changing).
static func is_timed_expr(expr: SignalExpr) -> bool:
	match expr.op:
		SignalExpr.Op.BEAT:
			return true
		SignalExpr.Op.NOT:
			return is_timed_expr(expr.args[0])
		SignalExpr.Op.AND, SignalExpr.Op.OR:
			for e: SignalExpr in expr.args:
				if is_timed_expr(e):
					return true
			return false
		SignalExpr.Op.XOR:
			return is_timed_expr(expr.args[0]) or is_timed_expr(expr.args[1])
	return false


## Compact human-readable form ("door1 & !(plateA | beat%4∈[0,2))") for debugging and validator messages.
static func format_signal_expr(expr: SignalExpr) -> String:
	match expr.op:
		SignalExpr.Op.SIG:
			return expr.sig
		SignalExpr.Op.NOT:
			return "!" + _wrap(expr.args[0])
		SignalExpr.Op.AND, SignalExpr.Op.OR:
			if expr.args.is_empty():
				return "true" if expr.op == SignalExpr.Op.AND else "false"
			var parts := PackedStringArray()
			for e: SignalExpr in expr.args:
				parts.append(_wrap(e))
			return (" & " if expr.op == SignalExpr.Op.AND else " | ").join(parts)
		SignalExpr.Op.XOR:
			return "%s ^ %s" % [_wrap(expr.args[0]), _wrap(expr.args[1])]
		SignalExpr.Op.CONST:
			return "true" if expr.value else "false"
		SignalExpr.Op.BEAT:
			return "beat%%%s∈[%s,%s)" % [js_number(expr.every), js_number(expr.from), js_number(expr.to)]
	push_error("Unknown SignalExpr op %d" % expr.op)
	return ""


static func _wrap(e: SignalExpr) -> String:
	var s := format_signal_expr(e)
	return "(" + s + ")" if e.op == SignalExpr.Op.AND or e.op == SignalExpr.Op.OR or e.op == SignalExpr.Op.XOR else s


## A number as JavaScript's String(n) writes it in the common cases (integers without ".0").
static func js_number(f: float) -> String:
	if is_nan(f):
		return "NaN"
	if is_inf(f):
		return "Infinity" if f > 0.0 else "-Infinity"
	if f == floorf(f) and absf(f) < 1e15:
		return str(int(f))
	return ODJson.format_float(f)
