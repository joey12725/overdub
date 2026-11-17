class_name HudObjective
extends HudPanel
## Objective chip (top-left): the level objective's text, its progress, and how many selves are
## alive right now against the one survivor the horizon needs (REC-07).


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func measure(max_w: float, _max_h: float) -> Vector2:
	return Vector2(max_w, _paint(max_w, false))


func _draw() -> void:
	if view != null:
		_paint(size.x, true)


func _paint(w: float, paint: bool) -> float:
	var u := unit
	var o := view.objective
	var display := UiPalette.font_display()
	var uif := UiPalette.font_ui()
	var mono := UiPalette.font_mono()
	var pad := roundf(u * 0.75)
	var tab_h := roundf(u * 1.2)
	var y := tab_h * 0.55
	var card_top := y
	y += pad * 0.9
	var tfs := ts(u * 0.95)
	var lines := wrap_text(display, o.text, tfs, w - 2.0 * pad)
	if lines.size() > 3:
		lines = lines.slice(0, 3)
		lines[2] = HudDraw.ellipsize(display, lines[2] + "…", tfs, w - 2.0 * pad)
	var text_y := y
	y += lines.size() * display.get_height(tfs) * 1.02
	y += u * 0.3
	var bar_y := y
	var bar_h := roundf(u * 0.65)
	y += bar_h + u * 0.35
	var surv_y := y
	var sfs := roundi(u * 0.66)
	y += uif.get_height(sfs) + pad * 0.8
	if not paint:
		return y + roundf(u * 0.35)
	var done := o.complete
	var card := Rect2(0, card_top, w, y - card_top)
	draw_set_transform(card.get_center(), deg_to_rad(-0.6), Vector2.ONE)
	var lc := Rect2(-card.size * 0.5, card.size)
	var off := card.position - lc.position
	HudDraw.panel(self, lc, UiPalette.PANEL_SOLID, UiPalette.INK, maxf(3.0, u * 0.2), u * 0.55, roundf(u * 0.3))
	draw_rect(lc.grow(-maxf(3.0, u * 0.2) - 1.0), UiPalette.alpha(UiPalette.PAPER, 0.18), false, 1.5, true)
	# Tab.
	var tab := "OBJECTIVE"
	var kfs := roundi(u * 0.62)
	var tw := HudDraw.text_width(display, tab, kfs) + u * 0.9
	var tr := Rect2(lc.position + Vector2(-u * 0.2, -tab_h * 0.55), Vector2(tw, tab_h))
	HudDraw.panel(self, tr, UiPalette.STATE_GOOD if done else UiPalette.MOXIE_YELLOW, UiPalette.INK, maxf(2.0, u * 0.12), u * 0.2)
	HudDraw.text_center(self, display, tr, tab, kfs, UiPalette.INK)
	var ty := text_y - off.y
	for line: String in lines:
		HudDraw.text(self, display, Vector2(lc.position.x + pad, ty + display.get_ascent(tfs)), line, tfs, UiPalette.PAPER)
		ty += display.get_height(tfs) * 1.02
	# Progress bar.
	var p := 1.0 if done else clampf(o.progress, 0.0, 1.0)
	var pct := "DONE" if done else "%d%%" % roundi(p * 100.0)
	var pfs := roundi(u * 0.68)
	var pw := HudDraw.text_width(mono, pct, pfs) + (u * 1.1 if done else 0.0) + u * 0.4
	var bar := Rect2(lc.position.x + pad, bar_y - off.y, lc.size.x - 2.0 * pad - pw, bar_h)
	HudDraw.panel(self, bar, UiPalette.TRACK, UiPalette.INK, maxf(2.0, u * 0.1), u * 0.2)
	if p > 0.0:
		draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4.0) * p, bar.size.y - 4.0)), UiPalette.STATE_GOOD if done else UiPalette.MOXIE_YELLOW, true)
	var px := bar.end.x + u * 0.4
	if done:
		HudIcons.draw_icon(self, HudModel.ICON_RESYNC, Vector2(px + u * 0.45, bar.get_center().y), u * 0.95, UiPalette.STATE_GOOD)
		px += u * 1.1
	HudDraw.text(self, mono, Vector2(px, HudDraw.baseline_in(mono, pfs, bar.position.y - u * 0.2, bar_h + u * 0.4)), pct, pfs, UiPalette.STATE_GOOD if done else UiPalette.PAPER)
	# Survivors.
	var sy := surv_y - off.y
	var sx := lc.position.x + pad
	var sh := uif.get_height(sfs)
	var no_one := o.survivors <= 0
	HudIcons.draw_icon(self, HudModel.ICON_SURVIVOR if not no_one else HudModel.ICON_DEATH, Vector2(sx + sh * 0.45, sy + sh * 0.5), sh * 0.95, UiPalette.STATE_BAD if no_one else UiPalette.PAPER)
	sx += sh + u * 0.2
	var n := str(o.survivors)
	var nfs := roundi(sfs * 1.25)
	HudDraw.text(self, display, Vector2(sx, HudDraw.baseline_in(display, nfs, sy, sh)), n, nfs, UiPalette.STATE_BAD if no_one else UiPalette.PAPER)
	sx += HudDraw.text_width(display, n, nfs) + u * 0.25
	var s1 := ("self" if o.survivors == 1 else "selves") + " alive"
	HudDraw.text(self, uif, Vector2(sx, HudDraw.baseline_in(uif, sfs, sy, sh)), s1, sfs, UiPalette.PAPER_DIM)
	sx += HudDraw.text_width(uif, s1, sfs) + u * 0.3
	var need := "· need 1 at the end"
	if sx + HudDraw.text_width(uif, need, sfs) < lc.end.x - pad * 0.5:
		HudDraw.text(self, uif, Vector2(sx, HudDraw.baseline_in(uif, sfs, sy, sh)), need, sfs, UiPalette.alpha(UiPalette.PAPER_DIM, 0.7))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	return y + roundf(u * 0.35)
