class_name HudDecision
extends HudPanel
## Decision panel (REC-04, REC-05, REC-07): the verdict of the combined run, its survivors and the
## outcome notes (failures explained in the game's own terms), then RETRY TAKE (keeps earlier
## tapes) / COMMIT TAPE / RESET ALL TAPES (wipes everything; hold to confirm, drawn as a ring that
## fills with set_hold_progress(); in press-twice mode the ring fills when the first press armed it
## and the text reads PRESS AGAIN TO CONFIRM). Only actions in view.actions are enabled.

var _max_notes: int = 99


func measure(max_w: float, max_h: float) -> Vector2:
	var w := minf(max_w, unit * 50.0)
	var n := view.outcome.notes.size() if view != null and view.outcome != null else 0
	_max_notes = n
	var h := _paint(w, false)
	while h > max_h and _max_notes > 0:
		_max_notes -= 1
		h = _paint(w, false)
	return Vector2(w, h)


func _draw() -> void:
	begin_zones()
	if view != null:
		_paint(size.x, true)


func _paint(w: float, paint: bool) -> float:
	var u := unit
	var ink := UiPalette.INK
	var display := UiPalette.font_display()
	var uif := UiPalette.font_ui()
	var o := view.outcome
	var v := HudModel.verdict(o)
	var pad := roundf(u * 1.1)
	var inner := w - 2.0 * pad
	var bw := maxf(4.0, u * 0.25)
	var head_h := roundf(u * 3.0)
	var tape_c := UiPalette.tape(view.active) if view.active >= 0 else UiPalette.PAPER
	var head_bg := UiPalette.PAPER
	if v.tone == &"win":
		head_bg = UiPalette.STATE_GOOD
	elif v.tone == &"fail":
		head_bg = UiPalette.STATE_BAD
	if paint:
		var h := _paint(w, false)
		HudDraw.panel(self, Rect2(0, 0, w, h), UiPalette.PANEL_SOLID, ink, bw, u * 0.9, roundf(u * 0.5))
		var hr := Rect2(bw, bw, w - 2.0 * bw, head_h)
		HudDraw.panel(self, hr, head_bg, ink, 0, u * 0.7)
		draw_rect(Rect2(hr.position.x, hr.end.y - u * 0.7, hr.size.x, u * 0.7), head_bg, true)
		draw_line(Vector2(hr.position.x, hr.end.y), Vector2(hr.end.x, hr.end.y), ink, bw)
		if v.tone == &"fail":
			HudDraw.hatch(self, Rect2(hr.end.x - u * 6.0, hr.position.y, u * 6.0, hr.size.y), UiPalette.alpha(ink, 0.18), u * 0.6, u * 0.22)
		var icon := HudModel.ICON_RESYNC if v.tone == &"win" else (HudModel.ICON_DEATH if v.tone == &"fail" else HudModel.ICON_TAKE)
		HudIcons.draw_icon(self, icon, Vector2(pad + u * 0.8, hr.position.y + head_h * 0.5), u * 1.6, ink, head_bg)
		var tfs := HudDraw.fit_size(display, v.title, roundi(u * 1.35), inner - u * 2.2, 10)
		HudDraw.text(self, display, Vector2(pad + u * 2.0, hr.position.y + head_h * 0.52), v.title, tfs, ink)
		var sfs := roundi(u * 0.62)
		HudDraw.text(self, uif, Vector2(pad + u * 2.0, hr.position.y + head_h * 0.52 + uif.get_height(sfs) * 1.05), HudDraw.ellipsize(uif, v.sub, sfs, inner - u * 2.2), sfs, UiPalette.alpha(ink, 0.85))
	var y := bw + head_h + u * 0.7

	# Survivors.
	if o != null:
		var sh := roundf(u * 1.3)
		if paint:
			var x := pad
			HudIcons.draw_icon(self, HudModel.ICON_SURVIVOR, Vector2(x + sh * 0.45, y + sh * 0.5), sh * 0.9, UiPalette.PAPER)
			x += sh + u * 0.2
			var mfs := roundi(u * 0.68)
			var lbl := "survivors:" if o.survivors.size() > 0 else "no survivors"
			HudDraw.text(self, uif, Vector2(x, HudDraw.baseline_in(uif, mfs, y, sh)), lbl, mfs, UiPalette.PAPER_DIM)
			x += HudDraw.text_width(uif, lbl, mfs) + u * 0.4
			for t: int in o.survivors:
				var cr := Rect2(x, y, sh * 1.1, sh)
				HudDraw.panel(self, cr, UiPalette.tape(t), ink, maxf(2.0, u * 0.1), u * 0.2)
				HudDraw.text_center(self, display, cr, OD.TAPE_NAMES[t] if t >= 0 and t < OD.TAPE_COUNT else "?", roundi(sh * 0.7), ink)
				x += cr.size.x + u * 0.25
		y += sh + u * 0.5
		# Notes (outcome explanations).
		var nfs := ts(u * 0.68)
		var shown := mini(o.notes.size(), _max_notes)
		for k in shown:
			var lines := wrap_text(uif, o.notes[k], nfs, inner - u * 1.2)
			var first := true
			for line: String in lines:
				if paint:
					if first:
						HudIcons.draw_icon(self, HudModel.ICON_TAKE, Vector2(pad + u * 0.4, y + uif.get_height(nfs) * 0.5), u * 0.75, UiPalette.STATE_WARN)
					HudDraw.text(self, uif, Vector2(pad + u * 1.1, y + uif.get_ascent(nfs)), line, nfs, UiPalette.PAPER)
				first = false
				y += uif.get_height(nfs) * 1.06
			y += u * 0.12
		if shown < o.notes.size():
			if paint:
				HudDraw.text(self, uif, Vector2(pad + u * 1.1, y + uif.get_ascent(nfs)), "+%d more" % (o.notes.size() - shown), nfs, UiPalette.PAPER_DIM)
			y += uif.get_height(nfs) * 1.06
		y += u * 0.4

	# Options.
	var opts := HudModel.decision_options(view.actions, view.active)
	var side := inner >= u * 36.0
	var gap := u * 0.6
	var ow := (inner - gap * 2.0) / 3.0 if side else inner
	var dfs := ts(u * 0.6)
	var detail_h := 0.0
	for op: HudModel.DecisionOption in opts:
		detail_h = maxf(detail_h, wrap_text(uif, _detail(op), dfs, ow - u * 1.2).size() * uif.get_height(dfs) * 1.05)
	var oh := roundf(u * 2.0) + detail_h + u * 0.7
	for k in opts.size():
		var op := opts[k]
		var r := Rect2(pad + (k * (ow + gap) if side else 0.0), y + (0.0 if side else k * (oh + gap)), ow, oh)
		if paint:
			_option(op, r, tape_c, dfs)
	y += (oh if side else oh * 3.0 + gap * 2.0) + pad
	return y


func _option(op: HudModel.DecisionOption, r: Rect2, tape_c: Color, dfs: int) -> void:
	var u := unit
	var ink := UiPalette.INK
	var display := UiPalette.font_display()
	var uif := UiPalette.font_ui()
	var bg := UiPalette.INK_SOFT
	var fg := UiPalette.PAPER
	match op.tone:
		&"commit":
			bg = tape_c
			fg = ink
		&"reset":
			bg = Color("#4a1a1f")
			fg = UiPalette.PAPER
	var hot := zone(r, op.action, op.enabled)
	var br := button_box(r, bg, op.enabled, hot, u * 0.55)
	if not op.enabled:
		fg = UiPalette.MUTED_TEXT
	if op.tone == &"reset" and op.enabled:
		HudDraw.hatch(self, Rect2(br.position + Vector2(4, 4), Vector2(br.size.x - 8.0, u * 0.5)), UiPalette.alpha(UiPalette.STATE_WARN, 0.8), u * 0.55, u * 0.2)
	var pr := prompt(op.action)
	var kh := u * 1.35
	var top := br.position.y + u * 0.75 + kh * 0.5
	var kx := br.position.x + u * 0.6
	if op.hold and op.enabled:
		# Hold-to-confirm ring before the keycap, filling clockwise with set_hold_progress().
		var rad := kh * 0.55
		var c := Vector2(kx + rad, top)
		var p := clampf(hold_progress, 0.0, 1.0)
		draw_circle(c, rad, UiPalette.INK, true, -1.0, true)
		draw_arc(c, rad * 0.78, 0, TAU, 40, UiPalette.alpha(UiPalette.PAPER, 0.25), maxf(2.0, rad * 0.3), true)
		if p > 0.0:
			draw_arc(c, rad * 0.78, -PI * 0.5, -PI * 0.5 + TAU * p, maxi(4, roundi(40 * p)), UiPalette.STATE_WARN, maxf(3.0, rad * 0.36), true)
		if p >= 1.0:
			draw_circle(c, rad * 0.35, UiPalette.STATE_WARN, true, -1.0, true)
		kx += rad * 2.0 + u * 0.3
	var kw := HudDraw.keycap(self, Vector2(kx, top), pr.binding, kh, not op.enabled)
	var tfs := HudDraw.fit_size(display, op.title, roundi(u * 0.82), br.end.x - (kx + kw + u * 0.5) - u * 0.4, 8)
	HudDraw.text(self, display, Vector2(kx + kw + u * 0.5, HudDraw.baseline_in(display, tfs, top - kh * 0.5, kh)), op.title, tfs, fg)
	var y := top + kh * 0.5 + u * 0.4
	for line: String in wrap_text(uif, _detail(op), dfs, br.size.x - u * 1.2):
		HudDraw.text(self, uif, Vector2(br.position.x + u * 0.6, y + uif.get_ascent(dfs)), line, dfs, UiPalette.alpha(fg, 0.9))
		y += uif.get_height(dfs) * 1.05


## Option detail line; the hold-to-confirm option says so (and changes while held / once armed).
func _detail(op: HudModel.DecisionOption) -> String:
	if op.hold and op.enabled:
		var c := confirm_text()
		return c + (" " if c.ends_with("…") else " — ") + op.detail
	return op.detail


## The confirm instruction shown on RESET ALL TAPES right now (tests read it).
func confirm_text() -> String:
	return HudModel.confirm_copy(press_twice, hold_progress)
