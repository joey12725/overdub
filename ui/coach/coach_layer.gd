class_name CoachLayer
extends Control
## Draws the CoachEngine's visible mark (docs/ONBOARDING.md "Presentation"): a small one-line label
## (wrapping to two lines below about 420 px), a thin leader line to its anchor and a dot on the
## anchor. Edge colour: the cassette's colour for deck, ruler and self anchors, neutral otherwise.
## No panel over the world, no dimming. The label never covers the four decks, the ruler body or the
## objective chip (it sits above the dock for dock anchors); an anchor that cannot be resolved draws
## the label in the coach slot, centred just above the dock, without a leader (a prompt anchor then
## shows its button glyph in the label). In: 120 ms fade + 6 px slide; out by the player: the dot
## ticks and the label fades in 200 ms; out by time or phase: 300 ms fade. Never takes input.

const IN_TIME := 0.12
const OUT_PLAYER := 0.2
const OUT_PLAIN := 0.3
const SLIDE_PX := 6.0

var engine: CoachEngine = null:
	set(v):
		if engine != null and engine.hidden.is_connected(_on_hidden):
			engine.hidden.disconnect(_on_hidden)
		engine = v
		if engine != null:
			engine.hidden.connect(_on_hidden)
var anchors: CoachAnchors = CoachAnchors.new()
## SessionAction / ActionKind (and move / aim) -> ButtonPrompt, as pushed to UiBase.set_bindings.
var bindings: Dictionary = {}
## Colour-blind patterns (SaveSettings.patterns): the dot gets a ring per cassette.
var patterns: bool = false
var unit: float = 14.0
var time: float = 0.0

var _mark: CoachMarkDef = null
var _t: float = 0.0
## Fading out: the last mark's drawing state.
var _out_t: float = -1.0
var _out_len: float = OUT_PLAIN
var _out_player: bool = false
var _anchor: CoachAnchors.Resolved = CoachAnchors.Resolved.new()
var _label: Rect2 = Rect2()
var _lines: PackedStringArray = PackedStringArray()
var _glyph: String = ""
var _edge: Color = UiPalette.PAPER
var _tip: Vector2 = Vector2.ZERO
var _base: Vector2 = Vector2.ZERO
var _side: String = "none"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func current_mark() -> CoachMarkDef:
	return _mark


func label_rect() -> Rect2:
	return _label


func anchor_resolved() -> CoachAnchors.Resolved:
	return _anchor


## The rendered text of the visible mark (tokens substituted).
func label_text() -> String:
	return " ".join(_lines)


func is_drawing() -> bool:
	return _mark != null or _out_t >= 0.0


func _on_hidden(m: CoachMarkDef, reason: String, _done: bool) -> void:
	if m != _mark:
		return
	_out_t = 0.0
	_out_player = reason == "player"
	_out_len = OUT_PLAYER if _out_player else OUT_PLAIN


func _process(delta: float) -> void:
	time += delta
	var m: CoachMarkDef = engine.current if engine != null else null
	if m != null and m != _mark:
		_mark = m
		_t = 0.0
		_out_t = -1.0
	if m == null and _mark != null and _out_t < 0.0:
		_out_t = 0.0
		_out_len = OUT_PLAIN
	_t += delta
	if _out_t >= 0.0:
		_out_t += delta
		if _out_t >= _out_len:
			_out_t = -1.0
			_mark = null
			queue_redraw()
			return
	if _mark != null:
		refresh()


## Recompute anchor, text and placement (also called by tools before a screenshot).
func refresh() -> void:
	if _mark == null:
		return
	var s := size
	if s.x < 2.0 or s.y < 2.0:
		s = get_viewport_rect().size
	unit = UiPalette.unit_for(s)
	var u := unit
	anchors.unit = u
	var ctx: CoachContext = engine.ctx if engine != null else null
	var subj: CoachConditions.Binding = engine.subject if engine != null else null
	if _out_t < 0.0:
		_anchor = anchors.resolve(_mark.anchor, self, ctx, subj)
	var text := substitute(_mark.text, bindings, ctx, subj)
	_glyph = ""
	if not _anchor.ok and _mark.anchor.begins_with("prompt:"):
		var act := _mark.anchor.substr(7)
		# The text already names that button ("{btn:move} to move."): no second glyph.
		if not _mark.text.contains("{btn:%s}" % act):
			_glyph = DlgPrompts.label_for(act, bindings)
	# colour: the cassette for deck / ruler / self anchors
	_edge = UiPalette.tape(_anchor.tape) if _anchor.ok and _anchor.tape >= 0 else UiPalette.PAPER_DIM
	var f := UiPalette.font_ui()
	var fs := roundi(u * 1.08 * UiPalette.text_scale)
	var max_w := maxf(u * 18.0, minf(s.x * 0.45, 420.0 * u / 14.0))
	_lines = BarkToast._wrap(f, text, fs, max_w)
	if _lines.size() > 2:
		_lines = BarkToast._wrap(f, text, fs, max_w * 1.5)
	var w := 0.0
	for l: String in _lines:
		w = maxf(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var glyph_w := 0.0
	if _glyph != "":
		glyph_w = UiPalette.font_mono().get_string_size(_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + u * 1.4
	var line_h := f.get_height(fs) * 1.05
	var sz := Vector2(w + glyph_w + u * 1.8, line_h * _lines.size() + u * 0.9)
	var avoid := _avoid_rects()
	var screen := Rect2(Vector2.ZERO, s)
	var dock_top := _dock_top(s)
	var safe := Rect2(Vector2.ZERO, Vector2(s.x, dock_top))
	if _anchor.ok:
		var pl := CoachLayout.place(_anchor.rect, true, sz, safe if _anchor.rect.position.y < dock_top else screen, avoid, _prefer(), u * 1.6, u)
		_label = pl.rect
		_side = pl.side
		_tip = _anchor.rect.get_center()
		_base = _closest_point(_label, _tip)
	else:
		# the coach slot: centred just above the dock
		_label = Rect2(Vector2((s.x - sz.x) * 0.5, dock_top - u * 1.2 - sz.y), sz)
		_side = "none"
	queue_redraw()


func _prefer() -> String:
	if _anchor.kind == "world":
		return "right"
	return "auto"


## The dock's top edge in this node's space (HudBase.bottom_inset() when available, else the top of
## the ruler / decks, else 80 % of the height).
func dock_top() -> float:
	var s := size
	if s.x < 2.0 or s.y < 2.0:
		s = get_viewport_rect().size
	return _dock_top(s)


func _dock_top(s: Vector2) -> float:
	var hud := anchors.hud_root
	if hud != null and hud.has_method("bottom_inset"):
		var inset: Variant = hud.call("bottom_inset")
		if (inset is float or inset is int) and float(inset) > 0.0:
			return s.y - float(inset)
	var top := s.y
	for g: String in ["ruler", "deck:0", "deck:1", "deck:2", "deck:3"]:
		var r := anchors.resolve(g, self, null, null)
		if r.ok:
			top = minf(top, r.rect.position.y)
	return top if top < s.y else s.y * 0.8


## Everything an overlay label must not cover, in this node's space: the four decks, the ruler, the
## objective chip, the HUD's visible panels (setup, decision, briefing, banner, count-in) and the
## whole dock band (so the active deck's tab is clear too). Shared by barks and the hint card.
const AVOID_ANCHORS: Array[String] = ["ruler", "deck:0", "deck:1", "deck:2", "deck:3", "objective", "setup", "decision", "briefing", "banner", "countin"]


func avoid_rects() -> Array[Rect2]:
	var s := size
	if s.x < 2.0 or s.y < 2.0:
		s = get_viewport_rect().size
	var u := UiPalette.unit_for(s)
	var out: Array[Rect2] = []
	for g: String in AVOID_ANCHORS:
		var r := anchors.resolve(g, self, null, null)
		if r.ok:
			out.append(r.rect.grow(u * 0.3))
	var top := _dock_top(s)
	if top < s.y - 1.0:
		out.append(Rect2(Vector2(0.0, top - u * 0.3), Vector2(s.x, s.y - top + u * 0.3)))
	return out


func _avoid_rects() -> Array[Rect2]:
	return avoid_rects()


static func _closest_point(r: Rect2, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


## Coach text tokens: {btn:<action>}, {speed} (the active deck, "2x"), {tape} (the subject, "Tape A").
static func substitute(text: String, bindings: Dictionary, ctx: CoachContext, subj: CoachConditions.Binding) -> String:
	var t := text
	if t.contains("{speed}"):
		var sp := ""
		if ctx != null and ctx.view != null and ctx.view.active >= 0 and ctx.view.active < ctx.view.decks.size():
			sp = format_speed(ctx.view.decks[ctx.view.active].speed)
		t = t.replace("{speed}", sp)
	if t.contains("{tape}"):
		var nm := "this tape"
		if subj != null and subj.has and subj.tape >= 0 and subj.tape < OD.TAPE_NAMES.size():
			nm = "Tape " + OD.TAPE_NAMES[subj.tape]
		t = t.replace("{tape}", nm)
	return DlgPrompts.substitute(t, bindings)


static func format_speed(s: float) -> String:
	if s <= 0.0:
		return "--"
	var r := snappedf(s, 0.01)
	var txt := str(int(r)) if is_equal_approx(r, roundf(r)) else String.num(r, 2).rstrip("0")
	return txt + "x"


func _alpha() -> float:
	var a := clampf(_t / IN_TIME, 0.0, 1.0)
	if _out_t >= 0.0:
		a *= clampf(1.0 - _out_t / _out_len, 0.0, 1.0)
	return a


func _draw() -> void:
	if _mark == null:
		return
	var u := unit
	var a := _alpha()
	var slide := (1.0 - clampf(_t / IN_TIME, 0.0, 1.0)) * SLIDE_PX
	var r := Rect2(_label.position + Vector2(0, slide), _label.size)
	# leader line + dot
	if _side != "none" and _anchor.ok:
		var base := _closest_point(r, _tip)
		draw_line(base, _tip, Color(_edge, 0.9 * a), maxf(1.5, u * 0.12), true)
		var dr := u * 0.38
		if _out_player and _out_t >= 0.0:
			dr *= 1.0 + 0.6 * sin(clampf(_out_t / _out_len, 0.0, 1.0) * PI)
		draw_circle(_tip, dr + maxf(1.5, u * 0.12), Color(UiPalette.INK, a))
		draw_circle(_tip, dr, Color(_edge, a))
		if patterns and _anchor.tape >= 0:
			for k in _anchor.tape + 1:
				draw_arc(_tip, dr + u * 0.25 * (k + 1), 0.0, TAU, 24, Color(_edge, 0.6 * a), 1.0, true)
		if _out_player and _out_t >= 0.0:
			# the tick
			var c := _tip
			draw_polyline(PackedVector2Array([c + Vector2(-dr * 0.5, 0), c + Vector2(-dr * 0.1, dr * 0.4), c + Vector2(dr * 0.55, -dr * 0.45)]), Color(UiPalette.INK, a), maxf(1.5, u * 0.14), true)
	# label
	draw_rect(Rect2(r.position + Vector2(u * 0.18, u * 0.22), r.size), Color(UiPalette.INK, 0.75 * a))
	draw_rect(r, Color(UiPalette.PANEL_SOLID, 0.94 * a))
	draw_rect(Rect2(r.position, Vector2(maxf(3.0, u * 0.28), r.size.y)), Color(_edge, a))
	draw_rect(r, Color(UiPalette.INK, a), false, maxf(1.5, roundf(u * 0.12)))
	var f := UiPalette.font_ui()
	var fs := roundi(u * 1.08 * UiPalette.text_scale)
	var line_h := f.get_height(fs) * 1.05
	var x := r.position.x + u * 0.95
	var y := r.position.y + u * 0.45
	if _glyph != "":
		var fm := UiPalette.font_mono()
		var gw := fm.get_string_size(_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + u * 0.8
		var gr := Rect2(Vector2(x, y + (line_h - u * 1.4) * 0.5), Vector2(gw, u * 1.4))
		draw_rect(gr, Color(UiPalette.PAPER, a))
		draw_string(fm, Vector2(gr.position.x + u * 0.4, gr.position.y + (gr.size.y + fm.get_ascent(fs) - fm.get_descent(fs)) * 0.5), _glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiPalette.INK, a))
		x += gw + u * 0.6
	for i in _lines.size():
		draw_string(f, Vector2(x, y + f.get_ascent(fs) + line_h * i), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiPalette.PAPER, a))
