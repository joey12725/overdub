class_name HudPanel
extends Control
## Base for the HUD's drawn panels (setup surface, banner, objective, count-in, briefing, decision).
## A panel draws itself in _draw() and registers clickable zones while drawing; only those zones
## take the mouse (_has_point), so the rest of the panel never blocks clicks meant for the game.
## A click emits `pressed(action, times)`; the HUD root re-emits it as HudBase.action.

signal pressed(action: StringName, times: int)

var view: SessionView = null
var device: StringName = HudModel.DEVICE_KEYBOARD
var bindings: Dictionary = {}
var unit: float = 14.0
var time: float = 0.0
var hold_progress: float = 0.0
## Accessibility "hold actions: press twice": the confirm control arms on a press instead of a hold.
var press_twice: bool = false
## Accessibility: blinking lamps hold steady.
var reduce_flashing: bool = false

## [Rect2, action, times, enabled]
var _zones: Array = []
var _hover: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func set_view(v: SessionView) -> void:
	view = v
	queue_redraw()


func advance(dt: float) -> void:
	time += dt
	if visible:
		queue_redraw()


## Preferred size for at most `max_w` × `max_h` (panels whose height depends on content).
func measure(max_w: float, _max_h: float) -> Vector2:
	return Vector2(max_w, unit * 4.0)


## Font size for text the player reads (notes, briefing lines, hints): `px` times the Text size
## option. Labels inside fixed geometry (decks, ruler, keycaps, pills) keep their size.
func ts(px: float) -> int:
	return roundi(px * UiPalette.text_scale)


func prompt(action: StringName) -> HudModel.Prompt:
	return HudModel.prompt_for(action, device, bindings)


func can(action: StringName) -> bool:
	return view != null and view.actions.has(action)


## Call at the start of _draw().
func begin_zones() -> void:
	_zones.clear()


## Register a clickable rect (in local coordinates) while drawing. Returns true when hovered.
func zone(r: Rect2, action: StringName, enabled: bool, times: int = 1) -> bool:
	_zones.append([r, action, times, enabled])
	return enabled and _hover == _zones.size() - 1


## Clickable rects registered by the last draw: [[Rect2, action, times, enabled], ...] (tests, tools).
func zones() -> Array:
	return _zones


func _has_point(point: Vector2) -> bool:
	if not visible:
		return false
	for z: Array in _zones:
		if (z[0] as Rect2).has_point(point):
			return true
	return false


func _zone_at(p: Vector2) -> int:
	for i in _zones.size():
		if (_zones[i][0] as Rect2).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _zone_at((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var i := _zone_at(mb.position)
			if i >= 0:
				accept_event()
				if _zones[i][3]:
					pressed.emit(_zones[i][1], _zones[i][2])


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


## Simulate a click at a local point (tests and tools); returns the action pressed or &"".
func click_at(p: Vector2) -> StringName:
	var i := _zone_at(p)
	if i < 0 or not _zones[i][3]:
		return &""
	pressed.emit(_zones[i][1], _zones[i][2])
	return _zones[i][1]


# ───────────────────────────── shared drawing ─────────────────────────────

## Word-wrap `text` to `max_w` at `size`.
static func wrap_text(font: Font, text: String, size: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word: String in text.split(" ", false):
		var t := word if line == "" else line + " " + word
		if line != "" and HudDraw.text_width(font, t, size) > max_w:
			out.append(line)
			line = word
		else:
			line = t
	if line != "":
		out.append(line)
	return out


## A chunky clickable button: inked panel, optional hover lift. Returns the drawn rect.
func button_box(r: Rect2, bg: Color, enabled: bool, hot: bool, radius: float) -> Rect2:
	var u := unit
	var rr := r
	var shadow := roundf(u * 0.28)
	if hot:
		rr = Rect2(r.position - Vector2(1, 2), r.size)
		shadow = roundf(u * 0.4)
	var c := bg if enabled else UiPalette.MUTED
	HudDraw.panel(self, rr, c, UiPalette.INK, maxf(2.0, roundf(u * 0.16)), radius, shadow if enabled else 0.0)
	if hot:
		draw_rect(rr.grow(u * 0.12), UiPalette.alpha(UiPalette.PAPER, 0.9), false, 2.0, true)
	return rr
