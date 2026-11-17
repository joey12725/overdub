class_name HudDeck
extends Control
## One cassette deck (UI-06, UI-07, NEW-07, NEW-08, NEW-10, NEW-11): an illustrated cassette in its
## cassette colour with its letter, spinning reels and tape moving between them; a big speed readout
## with a master-bar span scale; status, the self's run state, end behaviour and transport as icon +
## word badges. The active deck is haloed and wears a tab. Drawn entirely in _draw(); the HUD root
## positions it and feeds it the DeckView each frame. It holds no game state.

var index: int = 0
var deck: DeckView = DeckView.new()
var phase: StringName = SessionPhase.BRIEFING
var is_active: bool = false
var beat: float = 0.0
var local_bars: float = 8.0
var level_speeds: Array[float] = []
var beat_pulse: float = 0.0
var unit: float = 14.0
var slim: bool = false
var patterns: bool = false
## Accessibility: REC lamp and desync glitch hold still.
var reduce_flashing: bool = false
## Height of the tab drawn above an active deck (outside the rect; part of the dock inset).
var tab_h: float = 0.0

var _angle: float = 0.0
var _flash_kind: StringName = &""
var _flash_t: float = 0.0
var _flash_len: float = 0.0
var _pop_t: float = 0.0
var _last_speed: float = -1.0
var _time: float = 0.0
var _geo: HudModel.DeckGeometry = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false


## Feed the latest view (called by the HUD root every update).
func set_deck(d: DeckView, p_phase: StringName, p_active: bool, p_beat: float, p_local_bars: float, p_level_speeds: Array[float], p_pulse: float) -> void:
	if _last_speed >= 0.0 and not is_equal_approx(_last_speed, d.speed) and d.speed > 0.0:
		_pop_t = 0.32 # speed readout pops when it changes (NEW-10)
	_last_speed = d.speed
	deck = d
	phase = p_phase
	is_active = p_active
	beat = p_beat
	local_bars = p_local_bars
	level_speeds = p_level_speeds
	beat_pulse = p_pulse
	queue_redraw()


## Advance reel rotation and animations by `dt` viewer seconds.
func advance(dt: float) -> void:
	var setting_up := phase == SessionPhase.SETUP and is_active
	var rps := HudModel.deck_reel_spin(deck, setting_up)
	_angle = fmod(_angle + rps * TAU * minf(dt, 0.1), TAU)
	_time += dt
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - dt)
	if _pop_t > 0.0:
		_pop_t = maxf(0.0, _pop_t - dt)
	queue_redraw()


## deck_event(): flash the deck (over the cassette window, never the speed readout).
func flash(kind: StringName) -> void:
	_flash_kind = kind
	_flash_len = 0.9 if HudModel.flash_is_big(kind) else 0.5
	_flash_t = _flash_len
	queue_redraw()


## The current reel angle in radians (exposed for tests / tools).
func reel_angle() -> float:
	return _angle


func geometry() -> HudModel.DeckGeometry:
	return HudModel.deck_geometry(size, unit, slim)


# ───────────────────────────── drawing ─────────────────────────────

func _shell_color() -> Color:
	var c := UiPalette.tape(index)
	if deck.status == DeckStatus.UNAVAILABLE:
		return Color("#3a332d")
	if deck.status == DeckStatus.EMPTY:
		return UiPalette.tape_night(index)
	if deck.life == OD.LifeState.GHOST or deck.life == OD.LifeState.REC_GHOST:
		return c.lerp(UiPalette.STATE_DEAD, 0.62)
	return c


func _draw() -> void:
	var u := unit
	_geo = geometry()
	var g := _geo
	var r := Rect2(Vector2.ZERO, size)
	var tape_c := UiPalette.tape(index)
	var unavailable := deck.status == DeckStatus.UNAVAILABLE
	var bw := maxf(2.0, roundf(u * (0.16 if slim else 0.2)))
	var radius := u * (0.45 if slim else 0.7)

	# Active halo + tab (the active cassette is unmistakable).
	if is_active and not slim:
		var glow := 0.55 + 0.45 * clampf(beat_pulse, 0.0, 1.0)
		HudDraw.panel(self, r.grow(u * 0.32), UiPalette.alpha(tape_c, 0.35 * glow), Color(0, 0, 0, 0), 0, radius + u * 0.3)
		HudDraw.panel(self, r.grow(u * 0.16), Color(0, 0, 0, 0), UiPalette.alpha(UiPalette.PAPER, 0.95), maxf(2.0, u * 0.14), radius + u * 0.15)
		_draw_tab(u, tape_c)

	# Shell.
	var shell := _shell_color()
	HudDraw.panel(self, r, shell, UiPalette.INK, bw, radius, roundf(u * (0.18 if slim else 0.3)))
	var inner := r.grow(-bw)
	if deck.status == DeckStatus.EMPTY:
		# No tape loaded: dashed tape-colour outline inside a dark shell (reads without colour too).
		HudIcons._dashed_rect(self, inner.grow(-u * 0.12), UiPalette.alpha(tape_c, 0.85), maxf(1.5, u * 0.1), u * 0.45)
	elif unavailable:
		HudDraw.hatch(self, inner, Color("#4a423b"), u * 0.5, maxf(1.0, u * 0.1))
	else:
		# Shell sheen + moulding line.
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.42)), Color(1, 1, 1, 0.08), true)
	if patterns and not unavailable:
		HudDraw.tape_pattern(self, inner, index, UiPalette.alpha(UiPalette.INK, 0.22), u * 0.7)

	if not (use_shell_art and _draw_cassette_art(g.cassette, u, tape_c)):
		_draw_cassette(g.cassette, u, tape_c)
	_draw_speed(g, u, tape_c)
	_draw_badges(g, u, tape_c)
	_draw_flash(g, u, tape_c)


func _draw_tab(u: float, tape_c: Color) -> void:
	var font := UiPalette.font_display()
	var label := "THIS TAKE"
	var bg := tape_c
	var fg := UiPalette.INK
	match phase:
		SessionPhase.SETUP:
			label = "SETTING UP"
		SessionPhase.COUNTIN:
			label = "GET READY"
		SessionPhase.RECORDING:
			label = "RECORDING"
			bg = UiPalette.REC_RED
			fg = Color.WHITE
		SessionPhase.REVIEW:
			label = "PLAYING BACK"
		SessionPhase.DECISION:
			label = "YOUR CALL"
		SessionPhase.BRIEFING:
			label = "FIRST UP"
	var fs := roundi(tab_h * 0.68)
	var lamp := phase == SessionPhase.RECORDING
	var w := HudDraw.text_width(font, label, fs) + tab_h * (1.9 if lamp else 0.9)
	var tr := Rect2(u * 0.7, -tab_h - u * 0.16, w, tab_h + u * 0.55)
	HudDraw.panel(self, tr, bg, UiPalette.INK, maxf(2.0, u * 0.14), u * 0.3)
	var x := tr.position.x + tab_h * 0.45
	var cy := tr.position.y + tab_h * 0.55
	if lamp:
		var on := reduce_flashing or fmod(_time, 0.9) < 0.45
		draw_circle(Vector2(x + tab_h * 0.28, cy), tab_h * 0.3, UiPalette.INK, true, -1.0, true)
		draw_circle(Vector2(x + tab_h * 0.28, cy), tab_h * 0.22, Color.WHITE if on else Color(1, 1, 1, 0.3), true, -1.0, true)
		x += tab_h * 0.95
	HudDraw.text(self, font, Vector2(x, HudDraw.baseline_in(font, fs, tr.position.y + tab_h * 0.04, tab_h)), label, fs, fg)


## Draw the generated cassette shell (assets/ui/art/ui/cassette_shell_<colour>.png) with rotating
## reel art behind its window instead of the drawn cassette. Off by default: at deck size the drawn
## cassette reads better (letter sticker, tape packs, state stickers, dead / empty / unavailable
## looks); see the integration report. Returns false when the art is missing.
static var use_shell_art: bool = false
const SHELL_TINTS: Array[String] = ["red", "yellow", "blue", "green"]


func _draw_cassette_art(c: Rect2, u: float, tape_c: Color) -> bool:
	if deck.status == DeckStatus.UNAVAILABLE or deck.status == DeckStatus.EMPTY:
		return false
	var shell := UiArt.tex(UiArt.ART + "ui/cassette_shell_%s.png" % SHELL_TINTS[index % 4])
	var reel := UiArt.icon(UiArt.ART + "ui/cassette_reel.png", c.size.y * 0.5)
	if shell == null or reel == null:
		return false
	var ss := shell.get_size()
	var k := minf(c.size.x / ss.x, c.size.y / ss.y)
	var d := ss * k
	var o := c.position + (c.size - d) * 0.5
	var radii := HudModel.tape_pack_radii(deck.local_progress, 0.45, 0.8)
	var hubs: Array[Vector2] = [Vector2(228, 211), Vector2(411, 211)]
	for h in 2:
		var centre := o + hubs[h] * k
		var sc := (radii.x if h == 0 else radii.y) * 256.0 * k
		draw_set_transform(centre, _angle, Vector2.ONE)
		draw_texture_rect(reel, Rect2(-Vector2(sc, sc) * 0.5, Vector2(sc, sc)), false)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_texture_rect(shell, Rect2(o, d), false)
	# Letter sticker and shape on the label band.
	var font := UiPalette.font_display()
	var lab := Rect2(o + Vector2(60, 62) * k, Vector2(520, 90) * k)
	var lfs := roundi(lab.size.y * 0.8)
	HudDraw.text(self, font, Vector2(lab.position.x, HudDraw.baseline_in(font, lfs, lab.position.y, lab.size.y)), OD.TAPE_NAMES[index], lfs, UiPalette.INK)
	AccessKit.draw_shape(self, index, Vector2(lab.position.x + lab.size.y * 1.1, lab.get_center().y), lab.size.y * 0.3, tape_c, UiPalette.INK, 1.5)
	return true


func _draw_cassette(c: Rect2, u: float, tape_c: Color) -> void:
	var ink := UiPalette.INK
	var unavailable := deck.status == DeckStatus.UNAVAILABLE
	var empty := deck.status == DeckStatus.EMPTY
	var dead := deck.life == OD.LifeState.GHOST or deck.life == OD.LifeState.REC_GHOST
	var body_c := UiPalette.tape_deep(index)
	if unavailable:
		body_c = Color("#2e2824")
	elif empty:
		body_c = UiPalette.INK_SOFT
	elif dead:
		body_c = body_c.lerp(UiPalette.STATE_DEAD, 0.55)
	var cbw := maxf(1.5, roundf(u * 0.12))
	HudDraw.panel(self, c, body_c, ink, cbw, u * 0.35)

	# Label strip (the J-card): letter + name, coloured stripes.
	var lab_h := roundf(c.size.y * (0.4 if slim else 0.34))
	var lab := Rect2(c.position + Vector2(c.size.x * 0.07, c.size.y * 0.08), Vector2(c.size.x * 0.86, lab_h))
	var paper := UiPalette.PAPER if not unavailable else Color("#6d645b")
	HudDraw.panel(self, lab, paper, ink, maxf(1.0, cbw * 0.8), u * 0.18)
	var font := UiPalette.font_display()
	var letter := OD.TAPE_NAMES[index]
	var lfs := roundi(lab_h * 0.92)
	var lw := HudDraw.text_width(font, letter, lfs)
	var letter_box := Rect2(lab.position + Vector2(lab_h * 0.12, 0), Vector2(lw + lab_h * 0.3, lab_h))
	# Letter sticker in the cassette colour, inked.
	HudDraw.panel(self, letter_box.grow(-lab_h * 0.08), tape_c if not unavailable else Color("#4a423b"), ink, maxf(1.0, cbw * 0.8), u * 0.14)
	HudDraw.text_center(self, font, letter_box, letter, lfs, ink)
	var tx := letter_box.end.x + lab_h * 0.18
	# The cassette's shape beside its letter (A circle, B triangle, C square, D plus): the same mark
	# as the floor ring and the lane cap (ACCESSIBILITY.md H3).
	if not unavailable and lab_h >= 9.0:
		AccessKit.draw_shape(self, index, Vector2(tx + lab_h * 0.3, lab.position.y + lab_h * 0.5), lab_h * 0.3, tape_c, ink, maxf(1.0, lab_h * 0.07))
		tx += lab_h * 0.72
	var rest := lab.end.x - tx - lab_h * (0.95 if deck.status == DeckStatus.RECORDING else 0.18)
	# Keep the name clear of the corner sticker (lock / desync) when the cassette is short enough
	# for the sticker to reach up into the label strip.
	var st_d := maxf(10.0, u * (1.1 if slim else 1.45))
	var has_sticker := (not deck.synced and deck.life >= 0) or deck.status == DeckStatus.COMMITTED
	if has_sticker and c.end.y - st_d * 0.8 < lab.end.y:
		rest = minf(rest, c.end.x - st_d * 0.85 - tx)
	if not slim and rest > u * 1.0:
		# The letter sticker names the tape; the strip reads "[A] CASSETTE" like a J-card.
		var name := "CASSETTE"
		var nfs := HudDraw.fit_size(font, name, roundi(lab_h * 0.42), rest, 7)
		if rest > u * 2.5 and HudDraw.text_width(font, name, nfs) <= rest:
			HudDraw.text(self, font, Vector2(tx, lab.position.y + lab_h * 0.5), name, nfs, ink)
		# Stripes under the name, J-card style.
		var sy := lab.position.y + lab_h * 0.66
		draw_rect(Rect2(tx, sy, rest, lab_h * 0.1), tape_c if not unavailable else Color("#4a423b"), true)
		draw_rect(Rect2(tx, sy + lab_h * 0.16, rest * 0.7, lab_h * 0.06), UiPalette.alpha(ink, 0.6), true)
	if deck.status == DeckStatus.PENDING:
		# Uncommitted take: hazard stripes over the label's free part (reads without colour).
		HudDraw.hatch(self, Rect2(tx, lab.position.y + cbw, maxf(0.0, lab.end.x - tx - cbw), lab_h - 2.0 * cbw), UiPalette.alpha(UiPalette.STATE_WARN, 0.55), lab_h * 0.32, lab_h * 0.12)
	if deck.status == DeckStatus.RECORDING:
		var on := reduce_flashing or fmod(_time, 0.9) < 0.45
		var lc := Vector2(lab.end.x - lab_h * 0.42, lab.position.y + lab_h * 0.5)
		draw_circle(lc, lab_h * 0.3, ink, true, -1.0, true)
		draw_circle(lc, lab_h * 0.22, UiPalette.REC_RED if on else UiPalette.alpha(UiPalette.REC_RED, 0.3), true, -1.0, true)

	# Window with reels.
	var wy := lab.end.y + c.size.y * 0.06
	var win := Rect2(c.position.x + c.size.x * 0.12, wy, c.size.x * 0.76, c.end.y - wy - c.size.y * (0.1 if slim else 0.2))
	if win.size.y < 4.0:
		return
	HudDraw.panel(self, win, Color("#0e0c0b") if not unavailable else Color("#221e1b"), ink, maxf(1.0, cbw * 0.8), win.size.y * 0.32)
	var full := minf(win.size.y * 0.5, win.size.x * 0.2)
	var hub := full * 0.42
	var lc2 := Vector2(win.position.x + win.size.x * 0.25, win.get_center().y)
	var rc := Vector2(win.position.x + win.size.x * 0.75, win.get_center().y)
	var has_tape := not empty and not unavailable
	if has_tape:
		var radii := HudModel.tape_pack_radii(deck.local_progress, hub, full)
		var pack := Color("#4a3426") if not dead else Color("#59565c")
		# Tape run along the bottom to the head.
		var by := win.end.y - win.size.y * 0.06
		draw_line(lc2 + Vector2(-radii.x * 0.55, radii.x * 0.83), Vector2(win.get_center().x - win.size.x * 0.12, by), pack.lightened(0.15), maxf(1.0, u * 0.08), true)
		draw_line(rc + Vector2(radii.y * 0.55, radii.y * 0.83), Vector2(win.get_center().x + win.size.x * 0.12, by), pack.lightened(0.15), maxf(1.0, u * 0.08), true)
		draw_circle(lc2, radii.x, pack, true, -1.0, true)
		draw_circle(rc, radii.y, pack, true, -1.0, true)
		draw_arc(lc2, radii.x, 0, TAU, 32, pack.lightened(0.25), maxf(1.0, u * 0.06), true)
		draw_arc(rc, radii.y, 0, TAU, 32, pack.lightened(0.25), maxf(1.0, u * 0.06), true)
	_draw_hub(lc2, hub, u, has_tape)
	_draw_hub(rc, hub, u, has_tape)
	# Transport chevrons between the reels.
	if has_tape and not slim:
		var mid := win.get_center()
		var ch := win.size.y * 0.16
		var col := UiPalette.alpha(tape_c, 0.9)
		var setting_up := phase == SessionPhase.SETUP and is_active
		var dir := 1 if setting_up and deck.speed > 0.0 else deck.transport
		if dir == 0:
			draw_rect(Rect2(mid.x - ch * 0.8, mid.y - ch, ch * 0.5, ch * 2.0), UiPalette.alpha(UiPalette.PAPER, 0.5), true)
			draw_rect(Rect2(mid.x + ch * 0.3, mid.y - ch, ch * 0.5, ch * 2.0), UiPalette.alpha(UiPalette.PAPER, 0.5), true)
		else:
			for k in 2:
				var x0 := mid.x + (k - 0.5) * ch * 1.2
				draw_polyline(PackedVector2Array([Vector2(x0 - dir * ch * 0.5, mid.y - ch), Vector2(x0 + dir * ch * 0.5, mid.y), Vector2(x0 - dir * ch * 0.5, mid.y + ch)]), col, maxf(1.5, u * 0.12), true)
	# Window glare.
	draw_rect(Rect2(win.position + Vector2(win.size.x * 0.06, win.size.y * 0.1), Vector2(win.size.x * 0.88, win.size.y * 0.08)), Color(1, 1, 1, 0.07), true)

	# Head notch (trapezoid) and screws.
	if not slim:
		var ny := c.end.y - c.size.y * 0.12
		var nw := c.size.x * 0.42
		var notch := PackedVector2Array([Vector2(c.get_center().x - nw * 0.5, c.end.y - cbw), Vector2(c.get_center().x - nw * 0.38, ny), Vector2(c.get_center().x + nw * 0.38, ny), Vector2(c.get_center().x + nw * 0.5, c.end.y - cbw)])
		HudIcons.fill_poly(self, notch, body_c.darkened(0.3))
		for p: Vector2 in [c.position + Vector2(c.size.x * 0.045, c.size.y * 0.08), Vector2(c.end.x - c.size.x * 0.045, c.position.y + c.size.y * 0.08), Vector2(c.position.x + c.size.x * 0.045, c.end.y - c.size.y * 0.1), c.end - Vector2(c.size.x * 0.045, c.size.y * 0.1)]:
			var sr := maxf(1.5, u * 0.16)
			draw_circle(p, sr, UiPalette.alpha(UiPalette.PAPER, 0.75), true, -1.0, true)
			draw_line(p - Vector2(sr * 0.7, 0), p + Vector2(sr * 0.7, 0), ink, maxf(1.0, sr * 0.4), true)

	# State stickers on the cassette (life / commitment), icon-shaped so they never rely on colour.
	var st := maxf(10.0, u * (1.1 if slim else 1.45))
	var corner := Vector2(c.end.x - st * 0.3, c.end.y - st * 0.3)
	if dead and not slim:
		var gc := win.get_center()
		HudIcons.draw_icon(self, HudModel.ICON_GHOST if deck.life == OD.LifeState.GHOST else HudModel.ICON_REC_GHOST, gc, win.size.y * 0.95, UiPalette.alpha(UiPalette.PAPER, 0.85), UiPalette.INK)
	if not deck.synced and deck.life >= 0:
		# Glitch slices: the shell looks torn sideways (desync), plus the zigzag sticker.
		for k in 3:
			var yy := c.position.y + c.size.y * (0.22 + 0.27 * k)
			var off := (u * 0.25) * (1 if k % 2 == 0 else -1) * (1.0 + (0.0 if reduce_flashing else 0.5 * sin(_time * 9.0 + k)))
			draw_rect(Rect2(c.position.x + off, yy, c.size.x, maxf(2.0, c.size.y * 0.05)), UiPalette.alpha(UiPalette.STATE_DESYNC, 0.75), true)
		_sticker(corner, st, UiPalette.STATE_DESYNC, HudModel.ICON_DESYNC)
	elif deck.status == DeckStatus.COMMITTED:
		_sticker(corner, st, UiPalette.PAPER, HudModel.ICON_LOCK)


func _sticker(c: Vector2, d: float, bg: Color, icon: StringName) -> void:
	draw_circle(c + Vector2(d * 0.06, d * 0.08), d * 0.5, UiPalette.INK, true, -1.0, true)
	draw_circle(c, d * 0.5, UiPalette.INK, true, -1.0, true)
	draw_circle(c, d * 0.42, bg, true, -1.0, true)
	HudIcons.draw_icon(self, icon, c, d * 0.62, UiPalette.INK, bg)


func _draw_hub(c: Vector2, r: float, u: float, has_tape: bool) -> void:
	var paper := UiPalette.PAPER if has_tape else UiPalette.alpha(UiPalette.PAPER, 0.45)
	draw_circle(c, r, paper, true, -1.0, true)
	draw_arc(c, r, 0, TAU, 24, UiPalette.INK, maxf(1.0, r * 0.14), true)
	draw_circle(c, r * 0.48, Color("#0e0c0b"), true, -1.0, true)
	for k in 6:
		var a := _angle + k * TAU / 6.0
		var dirv := Vector2(cos(a), sin(a))
		draw_line(c + dirv * r * 0.28, c + dirv * r * 0.5, paper, maxf(1.0, r * 0.2), true)
	# A spoke mark so slow spins are visible.
	var sp := Vector2(cos(_angle), sin(_angle))
	draw_line(c + sp * r * 0.62, c + sp * r * 0.92, UiPalette.INK, maxf(1.0, r * 0.18), true)


func _draw_speed(g: HudModel.DeckGeometry, u: float, tape_c: Color) -> void:
	var unavailable := deck.status == DeckStatus.UNAVAILABLE
	var has_speed := deck.speed > 0.0 and not unavailable
	var lcd := g.speed
	HudDraw.panel(self, lcd, UiPalette.INK, UiPalette.INK, 0, u * 0.3)
	draw_rect(lcd.grow(-maxf(1.0, u * 0.08)), UiPalette.alpha(tape_c if not unavailable else UiPalette.MUTED_TEXT, 0.35), false, maxf(1.0, u * 0.06), true)
	var font := UiPalette.font_display()
	var txt := HudModel.format_speed(deck.speed) if has_speed else "--"
	var tr := g.speed_text
	var cap_h := 0.0
	if not slim and tr.size.y > u * 3.2:
		# Small caption above the number.
		cap_h = roundf(u * 0.75)
		var cap := "TAPE SPEED"
		var cfs := HudDraw.fit_size(UiPalette.font_mono(), cap, roundi(u * 0.55), tr.size.x - u * 0.4, 7)
		HudDraw.text_center(self, UiPalette.font_mono(), Rect2(tr.position + Vector2(0, u * 0.18), Vector2(tr.size.x, cap_h)), cap, cfs, UiPalette.alpha(tape_c, 0.85) if not unavailable else UiPalette.MUTED_TEXT)
	var num_r := Rect2(tr.position + Vector2(0, cap_h), tr.size - Vector2(0, cap_h))
	var fs := HudDraw.fit_size(font, txt, roundi(minf(g.speed_font, num_r.size.y * 0.95)), num_r.size.x - u * 0.5, 8)
	var col := tape_c if has_speed else UiPalette.MUTED_TEXT
	var pop := 0.0
	if _pop_t > 0.0:
		var k := 1.0 - _pop_t / 0.32
		pop = sin(k * PI) * 0.35 * (1.0 - k)
	var outline := maxf(2.0, fs * 0.09)
	HudDraw.text_rotated(self, font, num_r.get_center() + Vector2(0, fs * 0.04), txt, fs, col, deg_to_rad(-3.0) * (1.0 + pop * 3.0), outline, 1.0 + pop)
	if slim or g.span_bar.size.x <= 0.0:
		return
	# Span scale (UI-07): one pass of this tape in master bars against one pass at the slowest
	# offered speed - half/double is a half/double-length bar.
	var bar := g.span_bar
	draw_rect(bar, UiPalette.TRACK, true)
	if has_speed:
		var fill := HudModel.span_scale_fill(deck.speed, level_speeds)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), tape_c, true)
		var total := HudModel.span_scale_bars(local_bars, level_speeds, deck.speed)
		var n := clampi(roundi(total), 1, 64)
		for k in range(1, n):
			var x := bar.position.x + bar.size.x * k / n
			draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), UiPalette.alpha(UiPalette.INK, 0.85), maxf(1.0, u * 0.08))
	draw_rect(bar, UiPalette.alpha(UiPalette.PAPER, 0.5), false, 1.0)
	var mono := UiPalette.font_mono()
	var cap_txt := "not offered here" if unavailable else "speed not chosen yet"
	if not has_speed and HudDraw.text_width(mono, cap_txt, 7) > g.span_caption.size.x - 4.0:
		cap_txt = "not offered" if unavailable else "no speed yet"
		if HudDraw.text_width(mono, cap_txt, 7) > g.span_caption.size.x - 4.0:
			cap_txt = "—"
	if has_speed:
		var bars_txt := HudModel.format_bars(deck.span_bars if deck.span_bars > 0.0 else local_bars / deck.speed)
		var unit_word := "bar" if bars_txt == "1" else "bars"
		cap_txt = "1 pass = %s master %s" % [bars_txt, unit_word]
		if HudDraw.text_width(mono, cap_txt, roundi(u * 0.58)) > g.span_caption.size.x - 4.0:
			cap_txt = "= %s master %s" % [bars_txt, unit_word]
		if HudDraw.text_width(mono, cap_txt, roundi(u * 0.5)) > g.span_caption.size.x - 4.0:
			cap_txt = "%s M.BARS" % bars_txt
	var cfs2 := HudDraw.fit_size(mono, cap_txt, roundi(u * 0.58), g.span_caption.size.x - 4.0, 7)
	HudDraw.text_center(self, mono, g.span_caption, cap_txt, cfs2, UiPalette.PAPER_DIM if has_speed else UiPalette.MUTED_TEXT)


func _draw_badges(g: HudModel.DeckGeometry, u: float, tape_c: Color) -> void:
	var rows := HudModel.deck_badges(deck, beat, phase, g.badges.size())
	if slim and rows.size() > 0:
		var life := HudModel.life_badge(deck.life, deck.synced)
		rows = [life if life != null else rows[0]]
	var lamp_on := reduce_flashing or fmod(_time, 0.9) < 0.45
	for k in mini(rows.size(), g.badges.size()):
		var b: HudModel.Badge = rows[k]
		var row: Rect2 = g.badges[k]
		var compact := HudDraw.badge_width(b, row.size.y, false) > row.size.x
		HudDraw.badge(self, row, b, compact, tape_c, lamp_on)


func _draw_flash(g: HudModel.DeckGeometry, u: float, tape_c: Color) -> void:
	if _flash_t <= 0.0 or _flash_len <= 0.0:
		return
	var k := 1.0 - _flash_t / _flash_len # 0 -> 1
	var alpha := 1.0 if k < 0.6 else clampf((1.0 - k) / 0.4, 0.0, 1.0)
	var big := HudModel.flash_is_big(_flash_kind)
	var sc := lerpf(1.25 if big else 1.1, 1.0, clampf(k / 0.35, 0.0, 1.0))
	var bg := tape_c
	var fg := UiPalette.INK
	match _flash_kind:
		StateMarkKind.DEATH:
			bg = UiPalette.STATE_DEAD
		StateMarkKind.DESYNC:
			bg = UiPalette.STATE_DESYNC
		StateMarkKind.RESYNC:
			bg = UiPalette.STATE_GOOD
		ActionKind.HEAVY:
			bg = UiPalette.PAPER
	var txt := HudModel.flash_text(_flash_kind)
	var font := UiPalette.font_display()
	var area := g.flash
	var fs := HudDraw.fit_size(font, txt, roundi(area.size.y * (0.42 if big else 0.34)), area.size.x * 0.8 / sc, 8)
	var tw := HudDraw.text_width(font, txt, fs)
	var c := area.get_center() + Vector2(0, area.size.y * 0.12)
	var box := Rect2(-tw * 0.5 - fs * 0.35, -fs * 0.62, tw + fs * 0.7, fs * 1.24)
	draw_set_transform(c, deg_to_rad(-4.0), Vector2(sc, sc))
	HudDraw.panel(self, box, UiPalette.alpha(bg, alpha), UiPalette.alpha(UiPalette.INK, alpha), maxf(2.0, fs * 0.12), fs * 0.2, maxf(2.0, fs * 0.12), UiPalette.alpha(UiPalette.INK, alpha))
	var asc := font.get_ascent(fs)
	var desc := font.get_descent(fs)
	draw_string(font, Vector2(-tw * 0.5, (asc - desc) * 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.alpha(fg, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)
