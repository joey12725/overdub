class_name HGTerm
extends RefCounted
## One Sum term of a channel (engine `channel.terms[j]`): `amplitude · f(n · ratio + phase · cycle)`
## combined into the running sum with `operator`. A term with `source >= 0` samples that channel
## (its formula, or its own Sum) instead of `formula`.

const OPERATORS: Array[String] = ["+", "×", "∘", "mod", "interleave", "mask", "max", "min", "AND", "OR", "XOR"]

## 0 disables the term.
var amplitude: float = 0.0
var formula: String = "sine"
var params: Dictionary[String, float] = {}
var ratio: float = 1.0
var phase: float = 0.0
## One of OPERATORS (the first active term always adds).
var operator: String = "+"
## Index of a channel to sample, or -1.
var source: int = -1


func copy() -> HGTerm:
	var t := HGTerm.new()
	t.amplitude = amplitude
	t.formula = formula
	t.params = params.duplicate()
	t.ratio = ratio
	t.phase = phase
	t.operator = operator
	t.source = source
	return t


## Overwrites the fields present in `d` (engine JSON keys).
func apply_dict(d: Dictionary) -> void:
	amplitude = ODJson.num(d, "amplitude", amplitude)
	formula = ODJson.string(d, "formula", formula)
	if d.get("params") is Dictionary:
		params = HGMath.params_from(d["params"])
	ratio = ODJson.num(d, "ratio", ratio)
	phase = ODJson.num(d, "phase", phase)
	operator = ODJson.string(d, "operator", operator)
	source = ODJson.integer(d, "source", source)


func to_dict() -> Dictionary:
	return {"amplitude": amplitude, "formula": formula, "params": HGMath.params_to_dict(params), "ratio": ratio, "phase": phase, "operator": operator, "source": source}
