class_name HudSetup
extends HudPanel
## The active deck's control surface in 'setup' (UI-05, UI-07, NEW-10): a speed selector over
## view.speeds with a one-line consequence of the selected speed and the local→master conversion,
## an end-mode selector over view.end_modes (when the level offers a choice) with what it means,
## the level's hint, and a big RECORD prompt. Every control shows its button prompt for the current
## device; clicking a speed or end mode emits the speedUp/speedDown/cycleEndMode steps to reach it.


func measure(max_w: float, _max_h: float) -> Vector2:
	return Vector2(max_w, _paint(max_w, false))


func _draw() -> void:
	begin_zones()
	if view == null or view.active < 0:
		return
	_paint(size.x, true)


func _sorted_speeds() -> Array[float]:
	var s: Array[float] = view.speeds.duplicate()
	s.sort()
	return s


func _paint(w: float, paint: bool) -> float:
	if view == null or view.active < 0 or view.active >= OD.TAPE_COUNT:
		return 0.0
	var u := unit
	var a := view.active
	var d := view.decks[a]
	var tape_c := UiPalette.tape(a)
	var ink := UiPalette.INK
	var display := UiPalette.font_display()
	var uif := UiPalette.font_ui()
	var mono := UiPalette.font_mono()
	var pad := roundf(u * 0.8)
	var inner_w := w - 2.0 * pad
	var y := pad

	# We need the full height before drawing the card, so measure first when painting.
	if paint:
		var h := _paint(w, false)
		var card := Rect2(0, 0, w, h)
		HudDraw.panel(self, card, UiPalette.PANEL_SOLID, ink, maxf(3.0, roundf(u * 0.22)), u * 0.7, roundf(u * 0.35))
		draw_rect(card.grow(-roundf(u * 0.22) - 2.0), UiPalette.alpha(tape_c, 0.6), false, 2.0, true)
		# Pointer notch down to the deck.
		var nx := w * 0.5
		HudIcons.fill_poly(self, PackedVector2Array([Vector2(nx - u * 0.8, h - 2.0), Vector2(nx + u * 0.8, h - 2.0), Vector2(nx, h + u * 0.55)]), ink)

	# Head: tag + tape name.
	var head_h := roundf(u * 1.7)
	if paint:
		var tag := "SET UP"
		var tfs := roundi(u * 0.68)
		var tw := HudDraw.text_width(display, tag, tfs) + u * 0.8
		var tr := Rect2(pad, y + head_h * 0.12, tw, head_h * 0.76)
		draw_set_transform(tr.get_center(), deg_to_rad(-3.0), Vector2.ONE)
		var lr := Rect2(-tr.size * 0.5, tr.size)
		HudDraw.panel(self, lr, tape_c, ink, maxf(2.0, u * 0.12), u * 0.2, maxf(1.0, u * 0.1))
		HudDraw.text_center(self, display, lr, tag, tfs, ink)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var name := "TAPE " + OD.TAPE_NAMES[a]
		var nfs := roundi(u * 1.15)
		HudDraw.text(self, display, Vector2(tr.end.x + u * 0.6, HudDraw.baseline_in(display, nfs, y, head_h)), name, nfs, UiPalette.PAPER, maxf(2.0, u * 0.14))
		var nx2 := tr.end.x + u * 0.6 + HudDraw.text_width(display, name, nfs) + u * 0.6
		var sub := "speed and end behaviour for this take"
		var sfs := HudDraw.fit_size(uif, sub, roundi(u * 0.6), w - pad - nx2, 8)
		if w - pad - nx2 > u * 4.0:
			HudDraw.text(self, uif, Vector2(nx2, HudDraw.baseline_in(uif, sfs, y, head_h)), HudDraw.ellipsize(uif, sub, sfs, w - pad - nx2), sfs, UiPalette.PAPER_DIM)
	y += head_h + u * 0.35

	# Speed selector.
	var row_h := roundf(u * 2.2)
	var speeds := _sorted_speeds()
	var speed_ok := can(SessionAction.SPEED_UP) or can(SessionAction.SPEED_DOWN)
	var speed_item := func(k: int) -> Array:
		var s: float = speeds[k]
		var on := is_equal_approx(s, d.speed)
		var cur := speeds.find(d.speed)
		var steps := k - cur if cur >= 0 else 0
		var act := SessionAction.SPEED_UP if steps > 0 else SessionAction.SPEED_DOWN
		return [HudModel.format_speed(s), &"", on, speed_ok and cur >= 0 and steps != 0, act, absi(steps)]
	_selector_row(paint, y, row_h, pad, inner_w, "SPEED", SessionAction.SPEED_DOWN, SessionAction.SPEED_UP, speeds.size(), speed_item, tape_c)
	y += row_h + u * 0.45

	# Consequence of the selected speed + the local→master conversion.
	if d.speed > 0.0:
		var cfs := ts(u * 0.66)
		for line: String in wrap_text(uif, HudModel.speed_consequence(d.speed), cfs, inner_w):
			if paint:
				HudDraw.text(self, uif, Vector2(pad, y + uif.get_ascent(cfs)), line, cfs, UiPalette.PAPER)
			y += uif.get_height(cfs) * 1.05
		y += u * 0.15
		var conv := "%s per pass" % HudModel.span_copy(view.level.bars if view.level != null else 8.0, d.speed)
		var mfs := HudDraw.fit_size(mono, conv, roundi(u * 0.62), inner_w, 8)
		if paint:
			HudDraw.text(self, mono, Vector2(pad, y + mono.get_ascent(mfs)), conv, mfs, tape_c)
		y += mono.get_height(mfs) + u * 0.45

	# End behaviour selector (once the level offers a choice).
	if view.end_modes.size() > 1:
		var modes: Array[int] = view.end_modes
		var end_ok := can(SessionAction.CYCLE_END_MODE)
		var end_item := func(k: int) -> Array:
			var m: int = modes[k]
			var info := HudModel.end_mode_info(m)
			var cur := modes.find(d.end_mode)
			var steps := 1 if cur < 0 else (k - cur + modes.size()) % modes.size()
			return [info.label, info.icon, m == d.end_mode, end_ok and steps != 0, SessionAction.CYCLE_END_MODE, steps]
		_selector_row(paint, y, row_h, pad, inner_w, "AT THE END", &"", SessionAction.CYCLE_END_MODE, modes.size(), end_item, tape_c)
		y += row_h + u * 0.35
		if d.end_mode >= 0:
			var efs := ts(u * 0.6)
			for line: String in wrap_text(uif, HudModel.end_mode_info(d.end_mode).copy, efs, inner_w):
				if paint:
					HudDraw.text(self, uif, Vector2(pad, y + uif.get_ascent(efs)), line, efs, UiPalette.PAPER_DIM)
				y += uif.get_height(efs) * 1.05
			y += u * 0.35

	# Contextual hint.
	if view.hint != "":
		var hfs := ts(u * 0.62)
		var lines := wrap_text(uif, view.hint, hfs, inner_w - u * 1.4)
		var hh := lines.size() * uif.get_height(hfs) * 1.05 + u * 0.6
		if paint:
			var hr := Rect2(pad, y, inner_w, hh)
			HudDraw.panel(self, hr, UiPalette.MOXIE_YELLOW, ink, maxf(2.0, u * 0.12), u * 0.25)
			var ly := y + u * 0.3
			for line: String in lines:
				HudDraw.text(self, uif, Vector2(pad + u * 0.7, ly + uif.get_ascent(hfs)), line, hfs, ink)
				ly += uif.get_height(hfs) * 1.05
		y += hh + u * 0.5

	# RECORD.
	var rec_h := roundf(u * 2.7)
	if paint:
		var ok := can(SessionAction.RECORD)
		var rr := Rect2(pad, y, inner_w, rec_h)
		var hot := zone(rr, SessionAction.RECORD, ok)
		var br := button_box(rr, UiPalette.REC_RED, ok, hot, u * 0.55)
		var cy := br.get_center().y
		var on := reduce_flashing or fmod(time, 0.9) < 0.45 or not ok
		draw_circle(Vector2(br.position.x + u * 1.3, cy), u * 0.62, ink, true, -1.0, true)
		draw_circle(Vector2(br.position.x + u * 1.3, cy), u * 0.48, Color.WHITE if on else Color(1, 1, 1, 0.35), true, -1.0, true)
		var rfs := roundi(u * 1.3)
		var fg := Color.WHITE if ok else UiPalette.MUTED_TEXT
		HudDraw.text(self, display, Vector2(br.position.x + u * 2.4, HudDraw.baseline_in(display, rfs, br.position.y, rec_h)), "RECORD", rfs, fg, maxf(2.0, u * 0.14))
		var pr := prompt(SessionAction.RECORD)
		var kh := u * 1.5
		var kw := HudDraw.keycap_width(pr.binding, kh)
		HudDraw.keycap(self, Vector2(br.end.x - u * 0.7 - kw, cy), pr.binding, kh, not ok)
		var cap := "count-in 5 · 6 · 7 · 8"
		var cfs2 := roundi(u * 0.55)
		var cx := br.position.x + u * 2.4 + HudDraw.text_width(display, "RECORD", rfs) + u * 0.7
		if br.end.x - u * 1.2 - kw - cx > HudDraw.text_width(mono, cap, cfs2):
			HudDraw.text(self, mono, Vector2(cx, HudDraw.baseline_in(mono, cfs2, br.position.y, rec_h)), cap, cfs2, UiPalette.alpha(fg, 0.85))
	y += rec_h + pad
	return y


## A labelled segmented selector: [label] [prev key] [seg][seg]... [next key]. `item(k)` returns
## [text, icon, on, enabled, action, times].
func _selector_row(paint: bool, y: float, h: float, x0: float, w: float, label: String, prev_action: StringName, next_action: StringName, n: int, item: Callable, tape_c: Color) -> void:
	if not paint or n <= 0:
		return
	var u := unit
	var mono := UiPalette.font_mono()
	var display := UiPalette.font_display()
	var lfs := roundi(u * 0.55)
	var label_w := maxf(u * 4.2, HudDraw.text_width(mono, label, lfs) + u * 0.4)
	HudDraw.text(self, mono, Vector2(x0, HudDraw.baseline_in(mono, lfs, y, h)), label, lfs, UiPalette.PAPER_DIM)
	var x := x0 + label_w
	var kh := u * 1.35
	var cy := y + h * 0.5
	var any_enabled := false
	for k in n:
		if (item.call(k) as Array)[3]:
			any_enabled = true
	if prev_action != &"":
		var pp := prompt(prev_action)
		x += HudDraw.keycap(self, Vector2(x, cy), pp.binding, kh, not can(prev_action)) + u * 0.35
	var right_w := 0.0
	var np := prompt(next_action)
	right_w = HudDraw.keycap_width(np.binding, kh) + u * 0.35
	var seg_w := (x0 + w - right_w - x) / n
	for k in n:
		var it: Array = item.call(k)
		var r := Rect2(x + k * seg_w + 2.0, y + h * 0.08, seg_w - 4.0, h * 0.84)
		var on: bool = it[2]
		var enabled: bool = it[3]
		var hot := zone(r, it[4], enabled, it[5])
		var bg := tape_c if on else UiPalette.INK_SOFT
		if hot:
			bg = bg.lightened(0.12)
		HudDraw.panel(self, r, bg, UiPalette.INK, maxf(2.0, u * 0.12), u * 0.3, roundf(u * 0.18) if on else 0.0)
		var fg := UiPalette.INK if on else (UiPalette.PAPER if enabled or any_enabled else UiPalette.MUTED_TEXT)
		var txt: String = it[0]
		var icon: StringName = it[1]
		var fs := HudDraw.fit_size(display, txt, roundi(h * (0.42 if icon != &"" else 0.5)), r.size.x - (h * 0.7 if icon != &"" else 0.0) - u * 0.4, 7)
		if icon != &"":
			var tw := HudDraw.text_width(display, txt, fs)
			var gx := r.get_center().x - (tw + h * 0.55) * 0.5
			HudIcons.draw_icon(self, icon, Vector2(gx + h * 0.22, r.get_center().y), h * 0.45, fg, bg)
			HudDraw.text(self, display, Vector2(gx + h * 0.55, HudDraw.baseline_in(display, fs, r.position.y, r.size.y)), txt, fs, fg)
		else:
			HudDraw.text_center(self, display, r, txt, fs, fg)
		if on:
			# Selected: a little "ink tick" under the segment so the choice reads without colour.
			draw_rect(Rect2(r.position.x + r.size.x * 0.3, r.end.y - u * 0.22, r.size.x * 0.4, maxf(2.0, u * 0.1)), UiPalette.INK, true)
	HudDraw.keycap(self, Vector2(x0 + w - right_w + u * 0.35, cy), np.binding, kh, not can(next_action))
