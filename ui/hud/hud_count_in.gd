class_name HudCountIn
extends HudPanel
## Count-in (UI-04): a big punchy 5 · 6 · 7 · 8 in the active cassette's colour (the audio counts
## along), then a REC stamp the moment the take starts.

const STAMP_LEN := 0.9
const POP_LEN := 0.26

var _last_count: int = 0
var _last_phase: StringName = &""
var _pop_t: float = 0.0
var _stamp_t: float = 0.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_view(v: SessionView) -> void:
	var counting := v.phase == SessionPhase.COUNTIN
	if counting and v.count != _last_count and v.count >= 5:
		_pop_t = POP_LEN
	if v.phase == SessionPhase.RECORDING and _last_phase == SessionPhase.COUNTIN:
		_stamp_t = STAMP_LEN
	_last_count = v.count if counting else 0
	_last_phase = v.phase
	super.set_view(v)


func advance(dt: float) -> void:
	_pop_t = maxf(0.0, _pop_t - dt)
	_stamp_t = maxf(0.0, _stamp_t - dt)
	super.advance(dt)


## True while the count-in or the REC stamp is showing.
func is_showing() -> bool:
	return view != null and (view.phase == SessionPhase.COUNTIN or _stamp_t > 0.0)


func _draw() -> void:
	if view == null:
		return
	var u := unit
	var tape_c := UiPalette.tape(view.active) if view.active >= 0 else UiPalette.PAPER
	var display := UiPalette.font_display()
	var c := size * 0.5
	if view.phase == SessionPhase.COUNTIN:
		var big := roundi(u * 7.0)
		var small := roundi(u * 3.2)
		var dot_fs := roundi(u * 2.4)
		var widths: Array[float] = []
		var total := 0.0
		for n in [5, 6, 7, 8]:
			var fs := big if n == view.count else small
			var ww := HudDraw.text_width(display, str(n), fs) + u * 0.8
			if n == view.count:
				ww = maxf(ww, u * 9.8) # room for the ink burst
			widths.append(ww)
			total += ww
		var dot_w := HudDraw.text_width(display, "·", dot_fs) + u * 0.6
		total += dot_w * 3.0
		var x := c.x - total * 0.5
		var base_y := c.y - u * 0.5
		# Inked tape strip behind the row so every number holds contrast over any playfield.
		var band_h := small * 1.45
		draw_set_transform(Vector2(c.x, base_y), deg_to_rad(-3.0), Vector2.ONE)
		var band := Rect2(-total * 0.5 - u * 0.9, -band_h * 0.5, total + u * 1.8, band_h)
		HudDraw.panel(self, band, UiPalette.alpha(UiPalette.PANEL_SOLID, 0.9), UiPalette.INK, maxf(3.0, u * 0.2), u * 0.35, roundf(u * 0.3))
		draw_rect(Rect2(band.position.x, band.position.y + band_h * 0.1, band.size.x, maxf(2.0, u * 0.14)), UiPalette.alpha(tape_c, 0.8), true)
		draw_rect(Rect2(band.position.x, band.end.y - band_h * 0.1 - maxf(2.0, u * 0.14), band.size.x, maxf(2.0, u * 0.14)), UiPalette.alpha(tape_c, 0.8), true)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		for k in 4:
			var n := 5 + k
			var cur := n == view.count
			var past := view.count != 0 and n < view.count
			var fs := big if cur else small
			var cx := x + widths[k] * 0.5
			if cur:
				var t := 1.0 - _pop_t / POP_LEN if _pop_t > 0.0 else 1.0
				var sc := lerpf(1.7, 1.0, ease(t, 0.4)) if t < 1.0 else 1.0
				var rot := lerpf(-8.0, -3.0, t)
				# Ink "burst" behind the current number.
				draw_set_transform(Vector2(cx, base_y), deg_to_rad(rot), Vector2(sc, sc))
				var burst := PackedVector2Array()
				for i in 16:
					var rr := u * (4.6 if i % 2 == 0 else 3.6)
					var a := TAU * i / 16.0
					burst.append(Vector2(cos(a), sin(a)) * rr)
				HudIcons.fill_poly(self, burst, UiPalette.INK)
				var inner := PackedVector2Array()
				for p: Vector2 in burst:
					inner.append(p * 0.86)
				HudIcons.fill_poly(self, inner, UiPalette.alpha(tape_c, 0.25))
				draw_set_transform_matrix(Transform2D.IDENTITY)
				HudDraw.text_rotated(self, display, Vector2(cx, base_y), str(n), fs, tape_c, deg_to_rad(rot), maxf(4.0, u * 0.45), sc)
			elif past:
				HudDraw.text_rotated(self, display, Vector2(cx, base_y), str(n), fs, UiPalette.alpha(UiPalette.PAPER, 0.6), deg_to_rad(-3.0), maxf(3.0, u * 0.25))
			else:
				# Still to come: outlined numbers.
				_outline_number(cx, base_y, str(n), fs)
			x += widths[k]
			if k < 3:
				HudDraw.text_rotated(self, display, Vector2(x + dot_w * 0.5, base_y), "·", dot_fs, UiPalette.PAPER, 0.0, maxf(2.0, u * 0.2))
				x += dot_w
		# Caption.
		var cap := HudModel.count_in_caption(view)
		var mono := UiPalette.font_mono()
		var cfs := roundi(u * 0.75)
		var cw := HudDraw.text_width(mono, cap, cfs) + u * 1.6
		var cr := Rect2(c.x - cw * 0.5, base_y + u * 4.6, cw, u * 1.7)
		HudDraw.panel(self, cr, UiPalette.PANEL_SOLID, UiPalette.INK, maxf(3.0, u * 0.18), u * 0.45, roundf(u * 0.25))
		draw_rect(cr.grow(-maxf(3.0, u * 0.18) - 1.0), tape_c, false, 2.0, true)
		HudDraw.text_center(self, mono, cr, cap, cfs, UiPalette.PAPER)
	if _stamp_t > 0.0:
		var k := 1.0 - _stamp_t / STAMP_LEN
		var alpha := 1.0
		var sc := 1.0
		if k < 0.18:
			sc = lerpf(2.2, 1.0, k / 0.18)
			alpha = k / 0.18
		elif k > 0.7:
			sc = lerpf(1.0, 1.15, (k - 0.7) / 0.3)
			alpha = 1.0 - (k - 0.7) / 0.3
		var fs := roundi(u * 4.2)
		var txt := "REC"
		var tw := HudDraw.text_width(display, txt, fs)
		var bw := tw + u * 4.4
		var bh := fs * 1.35
		draw_set_transform(c, deg_to_rad(-6.0), Vector2(sc, sc))
		var r := Rect2(-bw * 0.5, -bh * 0.5, bw, bh)
		HudDraw.panel(self, r, UiPalette.alpha(UiPalette.REC_RED, alpha), UiPalette.alpha(UiPalette.INK, alpha), maxf(4.0, u * 0.35), u * 0.6, roundf(u * 0.45), UiPalette.alpha(UiPalette.INK, alpha))
		draw_rect(r.grow(-u * 0.55), UiPalette.alpha(Color.WHITE, alpha), false, maxf(2.0, u * 0.14), true)
		draw_circle(Vector2(r.position.x + u * 1.9, 0), u * 0.95, UiPalette.alpha(Color.WHITE, alpha), true, -1.0, true)
		var asc := display.get_ascent(fs)
		var desc := display.get_descent(fs)
		draw_string(display, Vector2(r.position.x + u * 3.4, (asc - desc) * 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.alpha(Color.WHITE, alpha))
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _outline_number(cx: float, cy: float, s: String, fs: int) -> void:
	var display := UiPalette.font_display()
	var w := HudDraw.text_width(display, s, fs)
	var asc := display.get_ascent(fs)
	var desc := display.get_descent(fs)
	draw_set_transform(Vector2(cx, cy), deg_to_rad(-3.0), Vector2.ONE)
	draw_string_outline(display, Vector2(-w * 0.5, (asc - desc) * 0.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, roundi(unit * 0.16)), UiPalette.PAPER)
	draw_string(display, Vector2(-w * 0.5, (asc - desc) * 0.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.INK)
	draw_set_transform_matrix(Transform2D.IDENTITY)
