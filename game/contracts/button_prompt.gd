class_name ButtonPrompt
extends RefCounted
## How to draw one button prompt (prototype ui/hud/model.ts Binding). The game's input module knows
## the real bindings and pushes a map of these to UiBase.set_bindings / HudBase.set_bindings whenever
## the device or bindings change.

const STYLE_KEY: StringName = &"key"
const STYLE_FACE_A: StringName = &"face-a"
const STYLE_FACE_B: StringName = &"face-b"
const STYLE_FACE_X: StringName = &"face-x"
const STYLE_FACE_Y: StringName = &"face-y"
const STYLE_SHOULDER: StringName = &"shoulder"
const STYLE_MENU: StringName = &"menu"

## Key / button glyph text ("Enter", "A", "LB", "Left click").
var key: String = ""
## STYLE_* - gamepad face buttons get their conventional colour treatment.
var style: StringName = STYLE_KEY


static func make(p_key: String, p_style: StringName = STYLE_KEY) -> ButtonPrompt:
	var p := ButtonPrompt.new()
	p.key = p_key
	p.style = p_style
	return p
