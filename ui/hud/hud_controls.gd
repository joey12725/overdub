class_name HudControls
extends HudPanel
## The controls strip: one keycap + action glyph per gameplay input (move, aim, light, heavy, dodge,
## ranged, interact, ability), shown just above the dock while recording / counting in, in the
## bottom-right corner (the setup surface and banner live elsewhere). Each prompt is also a coach-mark
## anchor: `prompt_rect(action)` returns its rect, and the HUD's anchor_rect("prompt:<action>")
## answers from it, so marks like "{btn:light} swings" point at the real key instead of the slot.
##
## Glyphs are the generated HUD icons (assets/ui/icons/actions/*.png, white with an ink outline,
## tinted with the live tape's colour); move / aim use small drawn arrows. Missing bindings fall back
## to GameInput.prompts(device) so the strip shows real keys even before the game pushes bindings.

const ACTIONS: Array[StringName] = [&"move", &"aim", &"light", &"heavy", &"dodge", &"ranged", &"interact", &"ability"]
const LABELS: Dictionary = {
	&"move": "MOVE", &"aim": "AIM", &"light": "LIGHT", &"heavy": "HEAVY", &"dodge": "DODGE",
	&"ranged": "SHOOT", &"interact": "USE", &"ability": "ABILITY",
}

## Which actions to show (the game may drop ranged / ability when the loadout has none).
var shown: Array[StringName] = ACTIONS.duplicate()
## Opacity multiplier (the strip fades back once the take is under way).
var fade: float = 1.0
var _rects: Dictionary[StringName, Rect2] = {}


func _ready() -> void:
	super()
	# Purely informative: never takes the mouse.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _has_point(_p: Vector2) -> bool:
	return false


func binding_for(action: StringName) -> ButtonPrompt:
	var b: ButtonPrompt = bindings.get(action) as ButtonPrompt if bindings.has(action) else null
	if b == null:
		var gp: Dictionary = GameInput.prompts(device)
		b = gp.get(action) as ButtonPrompt
	return b


## Width / height the strip needs at the current unit.
func measure(max_w: float, _max_h: float) -> Vector2:
	var u := unit
	var h := roundf(u * 2.0)
	var w := u * 0.5
	for a: StringName in shown:
		w += _item_w(a) + u * 0.45
	return Vector2(minf(max_w, w + u * 0.1), h)


func _item_w(a: StringName) -> float:
	var u := unit
	var kh := roundf(u * 1.25)
	var b := binding_for(a)
	var kw := HudDraw.keycap_width(b, kh) if b != null else 0.0
	return kw + u * 0.3 + u * 1.15 + u * 0.25 + HudDraw.text_width(UiPalette.font_display(), String(LABELS.get(a, a)), roundi(u * 0.62))


## Rect of one prompt in this control's coordinates (Rect2() when not shown).
func prompt_rect(action: StringName) -> Rect2:
	return _rects.get(action, Rect2())


func _draw() -> void:
	_rects.clear()
	if view == null:
		return
	var u := unit
	var a := clampf(fade, 0.0, 1.0)
	var h := size.y
	HudDraw.panel(self, Rect2(Vector2.ZERO, size), UiPalette.alpha(UiPalette.PANEL_SOLID, 0.82 * a), UiPalette.alpha(UiPalette.INK, a), maxf(2.0, u * 0.14), u * 0.45)
	var tint := UiPalette.tape(view.active) if view.active >= 0 else UiPalette.PAPER
	var display := UiPalette.font_display()
	var kh := roundf(u * 1.25)
	var lfs := roundi(u * 0.62)
	var x := u * 0.5
	var cy := h * 0.5
	for act: StringName in shown:
		var w := _item_w(act)
		if x + w > size.x - u * 0.2:
			break
		var x0 := x
		var b := binding_for(act)
		if b != null:
			x += HudDraw.keycap(self, Vector2(x, cy), b, kh, a < 0.6) + u * 0.3
		var gc := Vector2(x + u * 0.55, cy)
		_glyph(act, gc, u * 1.15, UiPalette.alpha(tint, a))
		x += u * 1.15 + u * 0.25
		var label := String(LABELS.get(act, act))
		HudDraw.text(self, display, Vector2(x, HudDraw.baseline_in(display, lfs, 0, h)), label, lfs, UiPalette.alpha(UiPalette.PAPER, a))
		x += HudDraw.text_width(display, label, lfs)
		_rects[act] = Rect2(x0 - u * 0.15, 0, x - x0 + u * 0.3, h)
		x += u * 0.45


func _glyph(act: StringName, c: Vector2, s: float, col: Color) -> void:
	if act == &"move" or act == &"aim":
		# Four-way arrows for move, a crosshair ring for aim (no generated glyph for these two).
		var w := maxf(2.0, s * 0.13)
		if act == &"move":
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				var tip := c + d * s * 0.46
				var side := Vector2(-d.y, d.x) * s * 0.17
				var base := c + d * s * 0.2
				HudIcons.fill_poly(self, PackedVector2Array([tip, base + side, base - side]), col)
			draw_circle(c, s * 0.09, col, true, -1.0, true)
		else:
			draw_arc(c, s * 0.34, 0, TAU, 24, col, w, true)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * s * 0.2, c + d * s * 0.5, col, w, true)
		return
	if not UiArt.draw_centered(self, UiArt.action_icon(act, s), c, s, col):
		HudIcons.draw_glyph(self, act, c.x, c.y, s * 0.7, col)
