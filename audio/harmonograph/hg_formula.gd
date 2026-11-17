class_name HGFormula
extends RefCounted
## One entry of the Harmonograph formula catalogue (engine `catalogue[i]`), without the function
## itself: evaluate with `Harmonograph.value(id, n, params, P)`.

const CATEGORY_NUMBER := "Number sequences"
const CATEGORY_DYNAMICAL := "Dynamical systems"
const CATEGORY_GEOMETRY := "Geometry & waves"
const CATEGORY_RHYTHM := "Rhythm & gates"
const CATEGORY_HARMONY := "Harmony"
const CATEGORY_EXPRESSION := "Expression"
const CATEGORIES: Array[String] = [CATEGORY_NUMBER, CATEGORY_DYNAMICAL, CATEGORY_GEOMETRY, CATEGORY_RHYTHM, CATEGORY_HARMONY, CATEGORY_EXPRESSION]

## Stable id used in states and level data ("fibonacci", "lorenz", ...).
var id: String = ""
var name: String = ""
var category: String = ""
## Human-readable equation (engine field `formula`).
var equation: String = ""
var params: Array[HGParamDef] = []
## The formula yields integers (normalised by modulus); otherwise its value is already 0..1-ish.
var integer: bool = false
## The engine declares a period function for it (period() may still compute one for
## fibonacci/lucas/collatz/logistic without it).
var has_period: bool = false
## Position in the catalogue (dispatch index).
var index: int = -1


func param(key: String) -> HGParamDef:
	for p: HGParamDef in params:
		if p.key == key:
			return p
	return null


func param_keys() -> Array[String]:
	var out: Array[String] = []
	for p: HGParamDef in params:
		out.append(p.key)
	return out


func to_dict() -> Dictionary:
	var ps: Array = []
	for p: HGParamDef in params:
		ps.append(p.to_dict())
	return {"id": id, "name": name, "category": category, "formula": equation, "params": ps, "integer": integer}
