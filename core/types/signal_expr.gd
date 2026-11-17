class_name SignalExpr
extends RefCounted
## Boolean logic over named signals; drives doors, lasers and objectives (types.ts SignalExpr).
##
## Representation of the recursive union: one class with an `op` tag and the operands the op uses.
##   prototype JSON                         op         fields used
##   { sig: "lever" }                       Op.SIG     sig
##   { not: e }                             Op.NOT     args[0]
##   { and: [e...] }                        Op.AND     args (any length, empty = true)
##   { or: [e...] }                         Op.OR      args (any length, empty = false)
##   { xor: [a, b] }                        Op.XOR     args[0], args[1]
##   { const: true }                        Op.CONST   value
##   { beat: { every, from, to } }          Op.BEAT    every, from, to
## Build with the of_* constructors; evaluate with ODSignals.eval_signal (core/signals.gd).

enum Op { SIG, NOT, AND, OR, XOR, CONST, BEAT }

var op: Op = Op.CONST
## Op.SIG: signal id.
var sig: String = ""
## Op.NOT / AND / OR / XOR operands.
var args: Array[SignalExpr] = []
## Op.CONST value.
var value: bool = false
## Op.BEAT: true while masterBeat mod `every` is within [from, to). Beat-timed mechanisms.
var every: float = 0.0
var from: float = 0.0
var to: float = 0.0


static func of_sig(id: String) -> SignalExpr:
	var e := SignalExpr.new()
	e.op = Op.SIG
	e.sig = id
	return e


static func of_not(a: SignalExpr) -> SignalExpr:
	var e := SignalExpr.new()
	e.op = Op.NOT
	e.args = [a]
	return e


static func of_and(list: Array[SignalExpr]) -> SignalExpr:
	var e := SignalExpr.new()
	e.op = Op.AND
	e.args = list.duplicate()
	return e


static func of_or(list: Array[SignalExpr]) -> SignalExpr:
	var e := SignalExpr.new()
	e.op = Op.OR
	e.args = list.duplicate()
	return e


static func of_xor(a: SignalExpr, b: SignalExpr) -> SignalExpr:
	var e := SignalExpr.new()
	e.op = Op.XOR
	e.args = [a, b]
	return e


static func of_const(v: bool) -> SignalExpr:
	var e := SignalExpr.new()
	e.op = Op.CONST
	e.value = v
	return e


static func of_beat(p_every: float, p_from: float, p_to: float) -> SignalExpr:
	var e := SignalExpr.new()
	e.op = Op.BEAT
	e.every = p_every
	e.from = p_from
	e.to = p_to
	return e


## Deep copy.
func copy() -> SignalExpr:
	var e := SignalExpr.new()
	e.op = op
	e.sig = sig
	e.value = value
	e.every = every
	e.from = from
	e.to = to
	for a: SignalExpr in args:
		e.args.append(a.copy())
	return e


## Parse the prototype JSON shape. Returns null and appends to `errors` when malformed.
static func from_dict(v: Variant, errors: Array[String] = [], where: String = "signal") -> SignalExpr:
	if not (v is Dictionary):
		errors.append("%s: expression must be an object" % where)
		return null
	var d: Dictionary = v
	if d.has("sig"):
		if not (d["sig"] is String):
			errors.append("%s: sig must be a string" % where)
			return null
		return of_sig(d["sig"])
	if d.has("not"):
		var a := from_dict(d["not"], errors, where + ".not")
		return of_not(a) if a != null else null
	if d.has("and") or d.has("or"):
		var key := "and" if d.has("and") else "or"
		if not (d[key] is Array):
			errors.append("%s: %s must be an array" % [where, key])
			return null
		var list: Array[SignalExpr] = []
		var i := 0
		for item: Variant in d[key]:
			var a := from_dict(item, errors, "%s.%s[%d]" % [where, key, i])
			if a == null:
				return null
			list.append(a)
			i += 1
		return of_and(list) if key == "and" else of_or(list)
	if d.has("xor"):
		if not (d["xor"] is Array) or (d["xor"] as Array).size() != 2:
			errors.append("%s: xor must be a two-element array" % where)
			return null
		var a := from_dict(d["xor"][0], errors, where + ".xor[0]")
		var b := from_dict(d["xor"][1], errors, where + ".xor[1]")
		return of_xor(a, b) if a != null and b != null else null
	if d.has("const"):
		if not (d["const"] is bool):
			errors.append("%s: const must be a boolean" % where)
			return null
		return of_const(d["const"])
	if d.has("beat"):
		if not (d["beat"] is Dictionary):
			errors.append("%s: beat must be an object" % where)
			return null
		var bd: Dictionary = d["beat"]
		return of_beat(ODJson.num(bd, "every"), ODJson.num(bd, "from"), ODJson.num(bd, "to"))
	errors.append("%s: unknown expression %s" % [where, ODJson.stringify(d)])
	return null


func to_dict() -> Dictionary:
	match op:
		Op.SIG:
			return {"sig": sig}
		Op.NOT:
			return {"not": args[0].to_dict()}
		Op.AND, Op.OR:
			var list: Array = []
			for a: SignalExpr in args:
				list.append(a.to_dict())
			return {"and": list} if op == Op.AND else {"or": list}
		Op.XOR:
			return {"xor": [args[0].to_dict(), args[1].to_dict()]}
		Op.CONST:
			return {"const": value}
		Op.BEAT:
			return {"beat": {"every": every, "from": from, "to": to}}
	return {"const": false}
