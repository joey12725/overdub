class_name HudBanner
extends HudPanel
## Top-centre phase banner: setup ("TAKE 2 / 4 · SET UP TAPE B"), recording (pulsing REC lamp, tape
## and speed, time left on the tape in LOCAL bars, and the "YOU DIED — keep playing" banner while
## the live self is a recording ghost), review (watching the combined take + SKIP / END ATTEMPT
## prompts) and the slim cinematic title.


func measure(max_w: float, _max_h: float) -> Vector2:
	return Vector2(max_w, _paint(max_w, false))


func _draw() -> void:
	begin_zones()
	if view != null:
		_paint(size.x, true)


func _paint(w: float, paint: bool) -> float:
	if view == null:
		return 0.0
	match view.phase:
		SessionPhase.SETUP:
			return _pill(w, paint)
		SessionPhase.RECORDING:
			return _recording(w, paint)
		SessionPhase.REVIEW:
			return _review(w, paint)
		SessionPhase.CINEMATIC:
			return _cinematic(w, paint)
	return 0.0


func _active_color() -> Color:
	return UiPalette.tape(view.active) if view.active >= 0 else UiPalette.PAPER


func _pill(w: float, paint: bool) -> float:
	var u := unit
	var h := roundf(u * 2.3)
	if not paint:
		return h + u * 0.4
	var display := UiPalette.font_display()
	var mono := UiPalette.font_mono()
	var uif := UiPalette.font_ui()
	var a := view.active
	var k := "TAKE %s / %d" % [str(a + 1) if a >= 0 else "-", HudModel.offered_count(view)]
	var main := "SET UP TAPE %s" % (OD.TAPE_NAMES[a] if a >= 0 and a < OD.TAPE_COUNT else "")
	var sub := "every take starts at master beat 0"
	var confirm := reset_confirm_text()
	if confirm != "":
		# Reset all is being held / was armed by a first press: say what the next input does.
		main = "RESET ALL TAPES?"
		sub = confirm
	var kfs := roundi(u * 0.66)
	var mfs := roundi(u * 1.0)
	var sfs := roundi(u * 0.6)
	var tw := HudDraw.text_width(mono, k, kfs) + u * 0.6 + HudDraw.text_width(display, main, mfs) + u * 0.6 + HudDraw.text_width(uif, sub, sfs)
	var show_sub := tw + u * 2.0 <= w
	if not show_sub:
		tw -= u * 0.6 + HudDraw.text_width(uif, sub, sfs)
	var pw := minf(w, tw + u * 2.0)
	var r := Rect2((w - pw) * 0.5, 0, pw, h)
	HudDraw.panel(self, r, UiPalette.PANEL_SOLID, UiPalette.INK, maxf(3.0, u * 0.2), u * 0.55, roundf(u * 0.3))
	draw_rect(r.grow(-maxf(3.0, u * 0.2) - 1.0), _active_color(), false, maxf(2.0, u * 0.12), true)
	var x := r.position.x + u
	HudDraw.text(self, mono, Vector2(x, HudDraw.baseline_in(mono, kfs, 0, h)), k, kfs, _active_color())
	x += HudDraw.text_width(mono, k, kfs) + u * 0.6
	HudDraw.text(self, display, Vector2(x, HudDraw.baseline_in(display, mfs, 0, h)), main, mfs, UiPalette.PAPER)
	x += HudDraw.text_width(display, main, mfs) + u * 0.6
	if show_sub:
		HudDraw.text(self, uif, Vector2(x, HudDraw.baseline_in(uif, sfs, 0, h)), sub, sfs, UiPalette.PAPER_DIM)
	return h + u * 0.4


## Setup has no reset button, only the key: while "reset all" is held (or armed by a first press in
## press-twice mode) the pill shows the confirm instruction. "" when nothing is pending.
func reset_confirm_text() -> String:
	if view == null or view.phase != SessionPhase.SETUP or hold_progress <= 0.0 or not can(SessionAction.RESET_ALL):
		return ""
	return HudModel.confirm_copy(press_twice, hold_progress)


func _recording(w: float, paint: bool) -> float:
	var u := unit
	var a := view.active
	var deck: DeckView = view.decks[a] if a >= 0 and a < view.decks.size() else null
	var died := deck != null and deck.life == OD.LifeState.REC_GHOST
	var row_h := roundf(u * 2.3)
	var time_h := roundf(u * 1.7)
	var died_h := roundf(u * 2.6) if died else 0.0
	var total := row_h + u * 0.35 + time_h + (u * 0.45 + died_h if died else 0.0) + u * 0.4
	if not paint:
		return total
	var display := UiPalette.font_display()
	var tape_c := _active_color()
	# REC row.
	var main := "REC · TAPE %s" % (OD.TAPE_NAMES[a] if a >= 0 and a < OD.TAPE_COUNT else "")
	var mfs := roundi(u * 1.05)
	var sp := HudModel.format_speed(deck.speed if deck != null else 0.0)
	var spfs := roundi(u * 1.05)
	var spw := HudDraw.text_width(display, sp, spfs) + u * 0.8
	var rw := u * 1.9 + HudDraw.text_width(display, main, mfs) + u * 0.7 + spw + u * 0.8
	var r := Rect2((w - rw) * 0.5, 0, rw, row_h)
	HudDraw.panel(self, r, UiPalette.PANEL_SOLID, UiPalette.INK, maxf(3.0, u * 0.2), u * 0.55, roundf(u * 0.3))
	draw_rect(r.grow(-maxf(3.0, u * 0.2) - 1.0), UiPalette.REC_RED, false, maxf(2.0, u * 0.14), true)
	var on := reduce_flashing or fmod(time, 0.9) < 0.45
	var lc := Vector2(r.position.x + u * 1.05, row_h * 0.5)
	draw_circle(lc, u * 0.5, UiPalette.INK, true, -1.0, true)
	draw_circle(lc, u * 0.38, UiPalette.REC_RED if on else UiPalette.alpha(UiPalette.REC_RED, 0.3), true, -1.0, true)
	if on:
		draw_circle(lc, u * 0.62, UiPalette.alpha(UiPalette.REC_RED, 0.25), false, 2.0, true)
	var x := r.position.x + u * 1.9
	HudDraw.text(self, display, Vector2(x, HudDraw.baseline_in(display, mfs, 0, row_h)), main, mfs, Color.WHITE)
	x += HudDraw.text_width(display, main, mfs) + u * 0.7
	var spr := Rect2(x, row_h * 0.17, spw, row_h * 0.66)
	HudDraw.panel(self, spr, tape_c, UiPalette.INK, maxf(2.0, u * 0.12), u * 0.25)
	HudDraw.text_center(self, display, spr, sp, spfs, UiPalette.INK)

	# Time left on the tape (LOCAL bars - the player's own bars).
	var y := row_h + u * 0.35
	var tl := HudModel.recording_time_left(deck.local_progress if deck != null else 0.0, view.level.bars if view.level != null else 8.0)
	var bw := minf(w, u * 28.0)
	var tr := Rect2((w - bw) * 0.5, y, bw, time_h)
	var tfs := roundi(u * 0.9)
	var label_w := HudDraw.text_width(display, tl.text.to_upper(), tfs) + u * 1.4
	# Inked backing so the readout stays legible over any playfield.
	HudDraw.panel(self, tr, UiPalette.alpha(UiPalette.PANEL_SOLID, 0.92), UiPalette.INK, maxf(2.0, u * 0.14), u * 0.4, roundf(u * 0.2))
	var track := Rect2(tr.position.x + u * 0.45, y + time_h * 0.22, bw - label_w - u * 0.45, time_h * 0.56)
	HudDraw.panel(self, track, UiPalette.TRACK, UiPalette.INK, maxf(2.0, u * 0.12), u * 0.25)
	var low := tl.fraction < 0.2
	var fill_c := (UiPalette.REC_RED if on else UiPalette.STATE_WARN) if low else tape_c
	var fr := Rect2(track.position + Vector2(2, 2), Vector2(maxf(0.0, (track.size.x - 4.0) * tl.fraction), track.size.y - 4.0))
	if fr.size.x > 0.5:
		draw_rect(fr, fill_c, true)
	# Bar notches along the tape (local bars).
	var bars := int(view.level.bars) if view.level != null else 8
	for k in range(1, bars):
		var nx := track.position.x + 2.0 + (track.size.x - 4.0) * k / bars
		draw_line(Vector2(nx, track.position.y + 2.0), Vector2(nx, track.end.y - 2.0), UiPalette.alpha(UiPalette.INK, 0.7), 1.0)
	var label_pos := Vector2(track.end.x + u * 0.5, HudDraw.baseline_in(display, tfs, y, time_h))
	HudDraw.text(self, display, label_pos, tl.text.to_upper(), tfs, UiPalette.STATE_WARN if low else UiPalette.PAPER)

	# "YOU DIED" banner while the live self is a recording ghost (GHOST-01).
	if died:
		y += time_h + u * 0.45
		var dfs := roundi(u * 1.05)
		var sfs := roundi(u * 0.8)
		var uif := UiPalette.font_ui()
		var head := "YOU DIED"
		var tail := "— keep playing: this take continues as a ghost"
		var dw := u * 2.6 + HudDraw.text_width(display, head, dfs) + u * 0.5 + HudDraw.text_width(uif, tail, sfs) + u * 1.0
		if dw > w:
			sfs = HudDraw.fit_size(uif, tail, sfs, w - (u * 4.1 + HudDraw.text_width(display, head, dfs)), 8)
			dw = minf(w, u * 2.6 + HudDraw.text_width(display, head, dfs) + u * 0.5 + HudDraw.text_width(uif, tail, sfs) + u * 1.0)
		var dr := Rect2((w - dw) * 0.5, y, dw, died_h)
		draw_set_transform(dr.get_center(), deg_to_rad(-1.2), Vector2.ONE)
		var lr := Rect2(-dr.size * 0.5, dr.size)
		HudDraw.panel(self, lr, UiPalette.STATE_DEAD, UiPalette.INK, maxf(3.0, u * 0.2), u * 0.4, roundf(u * 0.3))
		HudDraw.hatch(self, Rect2(lr.position + Vector2(4, 4), Vector2(u * 1.9, lr.size.y - 8.0)), UiPalette.alpha(UiPalette.INK, 0.25), u * 0.4, u * 0.12)
		HudIcons.draw_icon(self, HudModel.ICON_REC_GHOST, Vector2(lr.position.x + u * 1.3, 0), died_h * 0.7, UiPalette.INK, UiPalette.STATE_DEAD)
		var x2 := lr.position.x + u * 2.6
		HudDraw.text(self, display, Vector2(x2, HudDraw.baseline_in(display, dfs, lr.position.y, died_h)), head, dfs, UiPalette.INK)
		x2 += HudDraw.text_width(display, head, dfs) + u * 0.5
		HudDraw.text(self, uif, Vector2(x2, HudDraw.baseline_in(uif, sfs, lr.position.y, died_h)), tail, sfs, UiPalette.INK)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	return total


## The game layer's resolving beat (GameSessionView.resolving / status_text / resolve_progress):
## the combined run is being computed, so there is nothing to watch or skip yet.
func is_resolving() -> bool:
	return view != null and view.get("resolving") == true


func _resolving(w: float, paint: bool) -> float:
	var u := unit
	var h := roundf(u * 2.3)
	var bar_h := roundf(u * 0.9)
	var total := h + u * 0.35 + bar_h + u * 0.5
	if not paint:
		return total
	var display := UiPalette.font_display()
	var uif := UiPalette.font_ui()
	var st: Variant = view.get("status_text")
	var main := (String(st) if st is String and String(st) != "" else "Rewinding tape…").to_upper()
	var sub := "lining every take up from beat zero"
	var mfs := roundi(u * 1.0)
	var sfs := roundi(u * 0.6)
	var tw := u * 2.0 + HudDraw.text_width(display, main, mfs) + u * 0.6 + HudDraw.text_width(uif, sub, sfs)
	var show_sub := tw + u * 1.2 <= w
	if not show_sub:
		tw -= u * 0.6 + HudDraw.text_width(uif, sub, sfs)
	var pw := minf(w, tw + u * 1.2)
	var r := Rect2((w - pw) * 0.5, 0, pw, h)
	HudDraw.panel(self, r, UiPalette.PANEL_SOLID, UiPalette.INK, maxf(3.0, u * 0.2), u * 0.55, roundf(u * 0.3))
	draw_rect(r.grow(-maxf(3.0, u * 0.2) - 1.0), UiPalette.PAPER, false, maxf(2.0, u * 0.12), true)
	# Two rewinding reels: they turn backwards (a still pair under reduce flashing).
	var ang := 0.0 if reduce_flashing else -time * 7.0
	for k in 2:
		var c := Vector2(r.position.x + u * (0.85 + 0.75 * k), h * 0.5)
		draw_circle(c, u * 0.36, UiPalette.PAPER, true, -1.0, true)
		draw_circle(c, u * 0.14, UiPalette.INK, true, -1.0, true)
		for s in 3:
			var a := ang + TAU * s / 3.0
			draw_line(c + Vector2(cos(a), sin(a)) * u * 0.14, c + Vector2(cos(a), sin(a)) * u * 0.3, UiPalette.INK, maxf(1.5, u * 0.1), true)
	var x := r.position.x + u * 2.0
	HudDraw.text(self, display, Vector2(x, HudDraw.baseline_in(display, mfs, 0, h)), main, mfs, UiPalette.PAPER)
	x += HudDraw.text_width(display, main, mfs) + u * 0.6
	if show_sub:
		HudDraw.text(self, uif, Vector2(x, HudDraw.baseline_in(uif, sfs, 0, h)), sub, sfs, UiPalette.PAPER_DIM)
	# Progress (resolve_progress 0..1), as a tape running back onto its reel.
	var p: Variant = view.get("resolve_progress")
	var frac := clampf(float(p) if p != null else 0.0, 0.0, 1.0)
	var bw := minf(w, u * 22.0)
	var track := Rect2((w - bw) * 0.5, h + u * 0.35, bw, bar_h)
	HudDraw.panel(self, track, UiPalette.TRACK, UiPalette.INK, maxf(2.0, u * 0.12), bar_h * 0.5)
	var fr := Rect2(track.position + Vector2(2, 2), Vector2(maxf(0.0, (track.size.x - 4.0) * frac), track.size.y - 4.0))
	if fr.size.x > 0.5:
		HudDraw.panel(self, fr, UiPalette.PAPER, UiPalette.PAPER, 0.0, fr.size.y * 0.5)
	return total


func _review(w: float, paint: bool) -> float:
	if is_resolving():
		return _resolving(w, paint)
	var u := unit
	var h := roundf(u * 2.3)
	var chip_h := roundf(u * 2.1)
	var any := can(SessionAction.SKIP) or can(SessionAction.END_ATTEMPT)
	var total := h + (u * 0.4 + chip_h if any else 0.0) + u * 0.5
	if not paint:
		return total
	var display := UiPalette.font_display()
	var uif := UiPalette.font_ui()
	var main := "WATCHING THE COMBINED TAKE"
	var sub := "every tape together, at true master speed"
	var mfs := roundi(u * 1.0)
	var sfs := roundi(u * 0.6)
	var tw := u * 1.6 + HudDraw.text_width(display, main, mfs) + u * 0.6 + HudDraw.text_width(uif, sub, sfs)
	var show_sub := tw + u * 1.2 <= w
	if not show_sub:
		tw -= u * 0.6 + HudDraw.text_width(uif, sub, sfs)
	var pw := minf(w, tw + u * 1.2)
	var r := Rect2((w - pw) * 0.5, 0, pw, h)
	HudDraw.panel(self, r, UiPalette.PANEL_SOLID, UiPalette.INK, maxf(3.0, u * 0.2), u * 0.55, roundf(u * 0.3))
	draw_rect(r.grow(-maxf(3.0, u * 0.2) - 1.0), UiPalette.PAPER, false, maxf(2.0, u * 0.12), true)
	HudIcons.draw_icon(self, HudModel.ICON_PLAY, Vector2(r.position.x + u * 1.0, h * 0.5), u * 1.0, UiPalette.PAPER)
	var x := r.position.x + u * 1.7
	HudDraw.text(self, display, Vector2(x, HudDraw.baseline_in(display, mfs, 0, h)), main, mfs, UiPalette.PAPER)
	x += HudDraw.text_width(display, main, mfs) + u * 0.6
	if show_sub:
		HudDraw.text(self, uif, Vector2(x, HudDraw.baseline_in(uif, sfs, 0, h)), sub, sfs, UiPalette.PAPER_DIM)
	if any:
		var chips: Array[StringName] = []
		for act: StringName in [SessionAction.SKIP, SessionAction.END_ATTEMPT]:
			if can(act):
				chips.append(act)
		var lfs := roundi(u * 0.8)
		var kh := u * 1.3
		var widths: Array[float] = []
		var all_w := 0.0
		for act: StringName in chips:
			var cw := HudDraw.prompt_width(prompt(act), kh, lfs) + u * 1.2
			widths.append(cw)
			all_w += cw + u * 0.6
		all_w -= u * 0.6
		var cx := (w - all_w) * 0.5
		var cy := h + u * 0.4
		for i in chips.size():
			var act := chips[i]
			var cr := Rect2(cx, cy, widths[i], chip_h)
			var hot := zone(cr, act, true)
			var bg := UiPalette.PANEL_SOLID if act == SessionAction.SKIP else Color("#3a1d1d")
			var br := button_box(cr, bg, true, hot, u * 0.5)
			if act == SessionAction.END_ATTEMPT:
				draw_rect(br.grow(-maxf(2.0, u * 0.16) - 1.0), UiPalette.alpha(UiPalette.STATE_BAD, 0.8), false, 2.0, true)
			HudDraw.prompt(self, Vector2(br.position.x + u * 0.6, br.get_center().y), prompt(act), kh, UiPalette.PAPER, lfs)
			cx += widths[i] + u * 0.6
	return total


func _cinematic(w: float, paint: bool) -> float:
	var u := unit
	var h := roundf(u * 1.7)
	if not paint:
		return h + u * 0.3
	var display := UiPalette.font_display()
	var main := "THE PERFORMANCE"
	var fs := roundi(u * 0.75)
	var spaced := " ".join(main.split(""))
	var tw := HudDraw.text_width(display, spaced, fs) + u * 1.6
	var r := Rect2((w - tw) * 0.5, 0, tw, h)
	HudDraw.panel(self, r, UiPalette.alpha(UiPalette.PANEL_SOLID, 0.85), UiPalette.INK, maxf(2.0, u * 0.16), u * 0.5, roundf(u * 0.2))
	HudDraw.text_center(self, display, r, spaced, fs, UiPalette.PAPER)
	return h + u * 0.3
