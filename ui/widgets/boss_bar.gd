class_name WidgetBossBar
extends Control
## Top-of-screen boss health bar (HEALTH-03) with phase pips, armour state, a damage-lag ghost bar
## and the MEMORY tell (BOSS-01..03, chapter 10 "Fairness": what the boss remembers must be readable).
##
## API (all driven by snapshot data; see docs/WIDGETS.md):
##   set_boss_name(name)              title on the bar (default "THE ARCHIVIST")
##   set_memory(memory: BossMemory)   which committed tapes it remembers (null = none / first take)
##   update_from_snapshot(snap)       find the boss in a FrameSnapshot and show it (hides if none)
##   update_boss(e: EnemySnap, beat)  same, given the boss snapshot directly (null hides)
##   on_events(events)                'bossRecall' landing beat, armour clangs, phase changes
##   top_inset() -> float             pixels at the top the bar covers (0 when hidden)
## The node is a full-rect, mouse-transparent overlay that draws itself; mount it on the UI layer.

signal top_inset_changed(px: float)

const BOSS_FILL := Color("#ff7a2f")
const BOSS_FILL_DEEP := Color("#b8461a")

var model: WidgetBossModel = WidgetBossModel.new()
var boss_name: String = "THE ARCHIVIST"
var _beat: float = 0.0
var _time: float = 0.0
var _fade: float = 0.0
var _last_inset: float = -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_boss_name(n: String) -> void:
	boss_name = n.to_upper()
	queue_redraw()


func set_memory(memory: BossMemory) -> void:
	model.set_memory(memory)
	queue_redraw()


func update_from_snapshot(snap: FrameSnapshot) -> void:
	update_boss(WidgetBossModel.find_boss(snap), snap.beat if snap != null else 0.0)


func update_boss(e: EnemySnap, beat: float) -> void:
	_beat = beat
	model.update(e, beat, 0.0)
	queue_redraw()


func on_events(events: Array[SimEvent]) -> void:
	model.on_events(events)
	queue_redraw()


func clear() -> void:
	model = WidgetBossModel.new()
	_fade = 0.0
	queue_redraw()


func top_inset() -> float:
	if _fade <= 0.01:
		return 0.0
	var u := WidgetDraw.unit(self)
	# A boss with memory reserves room for the MEMORY sticker so the inset does not jump mid-fight.
	var extra := u * 3.8 if (not model.remembered.is_empty() or model.recalling) else 0.0
	return _layout(u).end.y + u * 0.6 + extra


func _process(delta: float) -> void:
	_time += delta
	model.advance(delta)
	var want := 1.0 if model.present and (model.alive or model.ghost > 0.001) else 0.0
	_fade = move_toward(_fade, want, delta * 4.0)
	var inset := top_inset()
	if absf(inset - _last_inset) > 0.5:
		_last_inset = inset
		top_inset_changed.emit(inset)
	if _fade > 0.0 or want > 0.0:
		queue_redraw()


## The bar's panel rect for unit `u`.
func _layout(u: float) -> Rect2:
	var w := clampf(size.x * 0.5, u * 30.0, u * 62.0)
	w = minf(w, size.x - u * 2.0)
	var h := u * 5.3
	return Rect2(Vector2((size.x - w) * 0.5, u * 0.8), Vector2(w, h))


func _draw() -> void:
	if _fade <= 0.001 or not model.present:
		return
	var u := WidgetDraw.unit(self)
	var r := _layout(u)
	var a := _fade
	var display := UiPalette.font_display()
	var mono := UiPalette.font_mono()
	var ui := UiPalette.font_ui()
	draw_set_transform(Vector2(0, (1.0 - a) * -u * 2.0))
	WidgetDraw.panel(self, r, UiPalette.alpha(UiPalette.PANEL, a), UiPalette.alpha(UiPalette.INK, a), maxf(2.0, u * 0.16), u * 0.5, u * 0.25)

	# ── title row: name, phase pips ──
	var pad := u * 0.8
	var title_size := int(u * 1.2)
	var ty := r.position.y + u * 1.55
	WidgetDraw.text(self, display, Vector2(r.position.x + pad, ty), boss_name, title_size, UiPalette.alpha(UiPalette.PAPER, a), u * 0.25)
	var phase_txt := "PHASE %d" % model.phase
	var pw := WidgetDraw.text_width(mono, phase_txt, int(u * 0.85))
	var pip_size := u * 0.8
	var pips_w := 3.0 * pip_size + 2.0 * pip_size * 0.35
	var px := r.end.x - pad - pips_w
	var phase_col := BOSS_FILL.lerp(UiPalette.PAPER, clampf(model.phase_flash * 2.0, 0.0, 1.0))
	WidgetDraw.pips(self, Vector2(px + pips_w * 0.5, ty - u * 0.35), 3, float(model.phase), pip_size, UiPalette.alpha(phase_col, a), UiPalette.alpha(UiPalette.MUTED, a))
	WidgetDraw.text(self, mono, Vector2(px - pw - u * 0.5, ty - u * 0.08), phase_txt, int(u * 0.85), UiPalette.alpha(UiPalette.PAPER_DIM, a))

	# ── health bar ──
	var bar := Rect2(r.position.x + pad, r.position.y + u * 2.1, r.size.x - pad * 2.0, u * 1.5)
	draw_rect(bar.grow(maxf(1.5, u * 0.12)), UiPalette.alpha(UiPalette.INK, a))
	draw_rect(bar, UiPalette.alpha(UiPalette.TRACK, a))
	var ghost_w := bar.size.x * model.ghost
	var fill_w := bar.size.x * model.frac
	if ghost_w > fill_w:
		draw_rect(Rect2(bar.position.x + fill_w, bar.position.y, ghost_w - fill_w, bar.size.y), UiPalette.alpha(UiPalette.PAPER, a * 0.9))
	var fill_col := BOSS_FILL.lerp(UiPalette.PAPER, clampf(model.hit_flash / WidgetBossModel.FLASH_TIME, 0.0, 1.0) * 0.7)
	if fill_w > 0.0:
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), UiPalette.alpha(fill_col, a))
		draw_rect(Rect2(bar.position + Vector2(0, bar.size.y * 0.62), Vector2(fill_w, bar.size.y * 0.38)), UiPalette.alpha(BOSS_FILL_DEEP, a))
		draw_rect(Rect2(bar.position + Vector2(0, bar.size.y * 0.12), Vector2(fill_w, maxf(1.0, bar.size.y * 0.12))), UiPalette.alpha(Color(1, 1, 1, 0.35), a))
	# Phase marks: a notch through the bar and a diamond above it at each phase boundary.
	for f: float in model.phase_marks:
		var x := bar.position.x + bar.size.x * f
		draw_line(Vector2(x, bar.position.y - u * 0.1), Vector2(x, bar.end.y + u * 0.1), UiPalette.alpha(UiPalette.INK, a), maxf(2.0, u * 0.18))
		var passed := model.frac <= f
		var dm := Rect2(Vector2(x, bar.position.y - u * 0.05) - Vector2(u * 0.32, u * 0.32), Vector2(u * 0.64, u * 0.64))
		draw_colored_polygon(WidgetDraw._diamond(dm.grow(u * 0.08)), UiPalette.alpha(UiPalette.INK, a))
		draw_colored_polygon(WidgetDraw._diamond(dm), UiPalette.alpha(BOSS_FILL if passed else UiPalette.PAPER, a))
	var hp_txt := "%d / %d" % [model.hp, model.max_hp]
	var hs := int(u * 0.9)
	# An ink pill behind the numbers keeps them readable over the pale damage-lag ghost.
	var hw := WidgetDraw.text_width(mono, hp_txt, hs)
	draw_rect(Rect2(Vector2(bar.end.x - hw - u * 0.6, bar.position.y + u * 0.08), Vector2(hw + u * 0.5, bar.size.y - u * 0.16)), UiPalette.alpha(UiPalette.INK, a * 0.75))
	WidgetDraw.text(self, mono, Vector2(bar.end.x - WidgetDraw.text_width(mono, hp_txt, hs) - u * 0.35, bar.position.y + bar.size.y * 0.5 + hs * 0.36), hp_txt, hs, UiPalette.alpha(UiPalette.PAPER, a), u * 0.2)

	# ── armour row (left): plates, guard state, whose eye it holds ──
	var row_y := bar.end.y + u * 0.95
	var x0 := bar.position.x
	var icon_s := u * 1.15
	for i: int in WidgetBossModel.PLATES:
		var on := i < model.plates
		var c := Vector2(x0 + icon_s * 0.5 + i * icon_s * 0.95, row_y)
		WidgetDraw.icon(self, WidgetDraw.ICON_SHIELD, c + Vector2(1, 1), icon_s, UiPalette.alpha(UiPalette.INK, a))
		WidgetDraw.icon(self, WidgetDraw.ICON_SHIELD, c, icon_s, UiPalette.alpha(UiPalette.PAPER if on else UiPalette.MUTED, a))
	var tx := x0 + WidgetBossModel.PLATES * icon_s * 0.95 + u * 0.4
	var label := ""
	var lcol := UiPalette.PAPER_DIM
	match model.armour:
		WidgetBossModel.ARMOUR_OPEN:
			label = "STAGGERED — GUARD DOWN"
			lcol = UiPalette.STATE_GOOD
		WidgetBossModel.ARMOUR_BROKEN:
			label = "DOWN"
			lcol = UiPalette.STATE_DEAD
		_:
			label = "FRONT ARMOURED · WATCHING"
	if model.clang_flash > 0.0:
		label = "CLANG — HIT ITS BACK"
		lcol = UiPalette.STATE_WARN.lerp(UiPalette.PAPER, model.clang_flash / WidgetBossModel.FLASH_TIME)
	var ls := int(u * 0.8)
	WidgetDraw.text(self, ui, Vector2(tx, row_y + ls * 0.36), label, ls, UiPalette.alpha(lcol, a))
	var lw := WidgetDraw.text_width(ui, label, ls)
	if model.armour == WidgetBossModel.ARMOUR_GUARDED and model.attention >= 0 and model.clang_flash <= 0.0:
		var ec := Vector2(tx + lw + u * 0.85, row_y)
		WidgetDraw.icon(self, WidgetDraw.ICON_EYE, ec, u * 1.0, UiPalette.alpha(UiPalette.PAPER, a))
		WidgetDraw.tape_badge(self, ec + Vector2(u * 1.15, 0), u * 0.95, model.attention)

	# ── memory (right): remembered tapes, lit when acting on one ──
	_draw_memory(r, bar, row_y, u, a)
	draw_set_transform(Vector2.ZERO)


func _draw_memory(r: Rect2, bar: Rect2, row_y: float, u: float, a: float) -> void:
	var mono := UiPalette.font_mono()
	var display := UiPalette.font_display()
	var ui := UiPalette.font_ui()
	var chip := u * 1.1
	var right := bar.end.x
	# Remembered tapes as small chips, right-aligned; the punished one lights up.
	if not model.remembered.is_empty():
		var n := model.remembered.size()
		var x := right - chip * 0.5
		for k: int in range(n - 1, -1, -1):
			var t := model.remembered[k]
			var lit := model.recalling and model.recall_tape == t
			WidgetDraw.tape_badge(self, Vector2(x, row_y), chip * (1.2 if lit else 1.0), t, lit)
			x -= chip * 1.15
		var cap := "REMEMBERS"
		var cs := int(u * 0.7)
		WidgetDraw.text(self, mono, Vector2(x - WidgetDraw.text_width(mono, cap, cs) + chip * 0.3, row_y + cs * 0.36), cap, cs, UiPalette.alpha(UiPalette.PAPER_DIM, a))
	if not model.recalling or model.recall_tape < 0:
		return
	# The tell: a sticker hanging under the bar in the punished cassette's colour.
	var t := model.recall_tape
	var col := UiPalette.tape(t)
	var pulse := 0.5 + 0.5 * sin(_time * TAU * 2.0)
	var ts := int(u * 1.2)
	var what := "WAITED" if model.recall_reason == BossMemoryLib.REASON_DWELL else ("STRUCK" if model.recall_reason == BossMemoryLib.REASON_ATTACK else "WAS")
	var line1 := "MEMORY"
	var line2 := "punishing where TAPE %s %s" % [OD.tape_letter(t), what]
	if model.recall_beats_left >= 0.0:
		line2 += " · lands in %s" % _beats_text(model.recall_beats_left)
	var l2s := int(u * 0.82)
	var w := u * 3.6 + maxf(WidgetDraw.text_width(display, line1, ts), WidgetDraw.text_width(ui, line2, l2s)) + u * 1.2
	var h := u * 3.0
	var box := Rect2(Vector2(r.get_center().x - w * 0.5, r.end.y + u * 0.45), Vector2(w, h))
	# Tab connecting it to the bar.
	var tab := PackedVector2Array([Vector2(box.get_center().x - u * 0.7, box.position.y + 1), Vector2(box.get_center().x + u * 0.7, box.position.y + 1), Vector2(box.get_center().x, box.position.y - u * 0.55)])
	draw_colored_polygon(tab, UiPalette.alpha(col, a))
	WidgetDraw.panel(self, box.grow(u * 0.12 * pulse), UiPalette.alpha(UiPalette.alpha(col, 0.35), a), UiPalette.alpha(col, a), maxf(2.0, u * 0.14), u * 0.45)
	WidgetDraw.panel(self, box, UiPalette.alpha(UiPalette.tape_night(t), a * 0.96), UiPalette.alpha(col, a), maxf(2.0, u * 0.18), u * 0.4, u * 0.2)
	# Reels spinning backwards (the Archivist's playback look) + the cassette badge.
	var rc := box.position + Vector2(u * 1.25, h * 0.5)
	draw_set_transform(Vector2(0, (1.0 - a) * -u * 2.0) + rc, -_time * 4.0, Vector2.ONE)
	WidgetDraw.icon(self, WidgetDraw.ICON_REELS, Vector2.ZERO, u * 1.7, UiPalette.alpha(col, a))
	draw_set_transform(Vector2(0, (1.0 - a) * -u * 2.0))
	WidgetDraw.tape_badge(self, rc + Vector2(u * 1.65, 0), u * 1.35, t, true)
	var tx := box.position.x + u * 3.6
	WidgetDraw.text(self, display, Vector2(tx, box.position.y + h * 0.46), line1, ts, UiPalette.alpha(col, a), u * 0.22)
	WidgetDraw.text(self, ui, Vector2(tx, box.position.y + h * 0.8), line2, l2s, UiPalette.alpha(UiPalette.PAPER, a))


static func _beats_text(b: float) -> String:
	var n := ceili(b - 1e-6)
	if n <= 0:
		return "NOW"
	return "%d beat%s" % [n, "" if n == 1 else "s"]
