class_name HudBriefing
extends HudPanel
## Briefing card (phase 'briefing'): level number, name, tagline, the briefing lines, the level's
## facts (objective, cassettes, offered speeds, local bars per take, master horizon) and START.


func measure(max_w: float, max_h: float) -> Vector2:
	var w := minf(max_w, unit * 40.0)
	return Vector2(w, minf(max_h, _paint(w, false)))


func _draw() -> void:
	begin_zones()
	if view != null and view.level != null:
		_paint(size.x, true)


func _paint(w: float, paint: bool) -> float:
	if view == null or view.level == null:
		return 0.0
	var L := view.level
	var u := unit
	var ink := UiPalette.INK
	var display := UiPalette.font_display()
	var uif := UiPalette.font_ui()
	var mono := UiPalette.font_mono()
	var pad := roundf(u * 1.4)
	var inner := w - 2.0 * pad
	var tag_h := roundf(u * 1.5)
	var y := tag_h * 0.5 + pad * 0.6
	var top := tag_h * 0.5
	if paint:
		var h := _paint(w, false)
		var card := Rect2(0, top, w, h - top)
		HudDraw.panel(self, card, UiPalette.PANEL_SOLID, ink, maxf(4.0, u * 0.25), u * 0.9, roundf(u * 0.5))
		draw_rect(card.grow(-maxf(4.0, u * 0.25) - 2.0), UiPalette.alpha(UiPalette.PAPER, 0.16), false, 2.0, true)
		# Four cassette-colour stripes down the left edge (the cast of this level).
		for i in 4:
			var sr := Rect2(card.position.x + maxf(4.0, u * 0.25) + 2.0, card.position.y + u * (1.2 + i * 1.05), u * 0.5, u * 0.85)
			draw_rect(sr, UiPalette.tape(i) if i < L.max_tapes else UiPalette.MUTED, true)
		# Campaign levels are numbered from 1 (data/levels/README.md): the index is the number.
		var tag := "LEVEL %02d" % L.index
		var tfs := roundi(u * 0.75)
		var tw := HudDraw.text_width(display, tag, tfs) + u * 1.0
		var tr := Rect2(pad, 0, tw, tag_h)
		draw_set_transform(tr.get_center(), deg_to_rad(-3.0), Vector2.ONE)
		var lr := Rect2(-tr.size * 0.5, tr.size)
		HudDraw.panel(self, lr, UiPalette.MOXIE_YELLOW, ink, maxf(2.0, u * 0.14), u * 0.22, maxf(2.0, u * 0.14))
		HudDraw.text_center(self, display, lr, tag, tfs, ink)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	y += u * 0.4
	# Title.
	var nfs := HudDraw.fit_size(display, L.name.to_upper(), roundi(u * 2.3), inner, 12)
	if paint:
		HudDraw.text(self, display, Vector2(pad, y + display.get_ascent(nfs)), L.name.to_upper(), nfs, UiPalette.PAPER, maxf(3.0, u * 0.22))
	y += display.get_height(nfs) + u * 0.1
	if L.tagline != "":
		var gfs := ts(u * 0.85)
		for line: String in wrap_text(uif, L.tagline, gfs, inner):
			if paint:
				HudDraw.text(self, uif, Vector2(pad, y + uif.get_ascent(gfs)), line, gfs, UiPalette.MOXIE_YELLOW)
			y += uif.get_height(gfs) * 1.05
	y += u * 0.5
	# Briefing lines.
	var bfs := ts(u * 0.78)
	for b: String in L.briefing:
		var lines := wrap_text(uif, b, bfs, inner - u * 1.2)
		var first := true
		for line: String in lines:
			if paint:
				if first:
					var by := y + uif.get_height(bfs) * 0.5
					HudIcons.fill_poly(self, PackedVector2Array([Vector2(pad, by - u * 0.25), Vector2(pad + u * 0.5, by), Vector2(pad, by + u * 0.25)]), UiPalette.PAPER_DIM)
				HudDraw.text(self, uif, Vector2(pad + u * 1.0, y + uif.get_ascent(bfs)), line, bfs, UiPalette.PAPER)
			first = false
			y += uif.get_height(bfs) * 1.08
		y += u * 0.2
	y += u * 0.4
	# Facts as chips (wrapping).
	var speeds: Array[float] = L.speeds.duplicate()
	speeds.sort()
	var sp: Array[String] = []
	for s: float in speeds:
		sp.append(HudModel.format_speed(s))
	var facts: Array[String] = [
		L.objective.text,
		"%d %s" % [L.max_tapes, "cassette" if L.max_tapes == 1 else "cassettes"],
		"speeds " + " / ".join(sp),
		"%s local bars per take" % HudModel.format_bars(L.bars),
		"%s master bars in all" % HudModel.format_bars(L.horizon_bars),
	]
	var ffs := roundi(u * 0.66)
	var fh := roundf(u * 1.45)
	var fx := pad
	for k in facts.size():
		var f := facts[k]
		var font := display if k == 0 else mono
		var fw := minf(inner, HudDraw.text_width(font, f, ffs) + u * 1.0)
		if fx + fw > pad + inner + 0.5 and fx > pad:
			fx = pad
			y += fh + u * 0.35
		if paint:
			var fr := Rect2(fx, y, fw, fh)
			HudDraw.panel(self, fr, UiPalette.PAPER if k == 0 else UiPalette.INK_SOFT, ink, maxf(2.0, u * 0.12), u * 0.3)
			HudDraw.text_center(self, font, fr, HudDraw.ellipsize(font, f, ffs, fw - u * 0.8), ffs, ink if k == 0 else UiPalette.PAPER)
		fx += fw + u * 0.35
	y += fh + u * 0.9
	# START.
	var bh := roundf(u * 2.5)
	if paint:
		var ok := can(SessionAction.START)
		var pr := prompt(SessionAction.START)
		var lfs := roundi(u * 1.1)
		var bw := minf(inner, HudDraw.prompt_width(pr, u * 1.5, lfs) + u * 2.4)
		var br := Rect2(pad + inner - bw, y, bw, bh)
		var hot := zone(br, SessionAction.START, ok)
		var rr := button_box(br, UiPalette.MOXIE_YELLOW, ok, hot, u * 0.5)
		HudDraw.prompt(self, Vector2(rr.position.x + u * 1.2, rr.get_center().y), pr, u * 1.5, ink if ok else UiPalette.MUTED_TEXT, lfs, not ok)
	y += bh + pad
	return y
