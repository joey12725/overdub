class_name GearLook
extends RefCounted
## Presentation hints for the character model (types.ts GearItem.look: { color?, variant? }).
## "" = absent for either field.

## CSS-style hex colour ("#3b3442"), or "".
var color: String = ""
## Silhouette variant id ("cap", "hood"...), or "".
var variant: String = ""


## The colour as a Color, or `fallback` when absent / unparsable.
func color_or(fallback: Color) -> Color:
	return Color.from_string(color, fallback) if not color.is_empty() else fallback


func copy() -> GearLook:
	var o := GearLook.new()
	o.color = color
	o.variant = variant
	return o


static func from_dict(d: Dictionary) -> GearLook:
	var o := GearLook.new()
	o.color = ODJson.string(d, "color")
	o.variant = ODJson.string(d, "variant")
	return o


func to_dict() -> Dictionary:
	var out := {}
	if not color.is_empty():
		out["color"] = color
	if not variant.is_empty():
		out["variant"] = variant
	return out
