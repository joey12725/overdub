class_name ObjectiveView
extends ObjectiveSnap
## SessionView.objective (types.ts `ObjectiveSnap & { text: string }`).

## The level objective's HUD text (ObjectiveDef.text).
var text: String = ""


static func make(snap: ObjectiveSnap, p_text: String) -> ObjectiveView:
	var o := ObjectiveView.new()
	o.copy_from(snap)
	o.text = p_text
	return o


## Returns an ObjectiveView (typed as the base for override compatibility).
func copy() -> ObjectiveSnap:
	return ObjectiveView.make(self, text)


func to_dict() -> Dictionary:
	var out := super.to_dict()
	out["text"] = text
	return out
