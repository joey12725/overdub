class_name HGParamDef
extends RefCounted
## One formula parameter (engine `param(key, label, value, min, max, step, detents)`).
## `step == 1` marks an integer parameter: clean_params rounds it.

var key: String = ""
var label: String = ""
## Default value.
var value: float = 0.0
var min_value: float = 0.0
var max_value: float = 0.0
var step: float = 1.0
## Values a UI may snap to.
var detents: PackedFloat64Array = PackedFloat64Array()


static func make(p_key: String, p_label: String, p_value: float, p_min: float, p_max: float, p_step: float = 1.0, p_detents: PackedFloat64Array = PackedFloat64Array()) -> HGParamDef:
	var d := HGParamDef.new()
	d.key = p_key
	d.label = p_label
	d.value = p_value
	d.min_value = p_min
	d.max_value = p_max
	d.step = p_step
	d.detents = p_detents
	return d


func is_integer() -> bool:
	return step == 1.0


func to_dict() -> Dictionary:
	var det: Array = []
	for v: float in detents:
		det.append(v)
	return {"key": key, "label": label, "value": value, "min": min_value, "max": max_value, "step": step, "detents": det}
