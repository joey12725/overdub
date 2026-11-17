class_name MenuArt
extends RefCounted
## Procedural menu artwork (prototype ui/menus/art.ts): the OVERDUB cassette logotype, Moxie's
## loadout silhouette, the time machine, small icons and cassettes. Everything is drawn in code from
## the Moxie palette (CHAR-05..09, R01): yellow headphones and Walkman as the key colour,
## ink/charcoal, olive cargo pants, pink graffiti accents. Painters draw in their own view-box units;
## MenuArtView scales them into a Control. Never instantiated.

const Y := MenuStyle.YELLOW
const INK := MenuStyle.INK
const INK_SOFT := MenuStyle.INK_SOFT
const PAPER := MenuStyle.PAPER
const PAPER_DIM := MenuStyle.PAPER_DIM
const PINK := MenuStyle.PINK
const VIOLET := MenuStyle.VIOLET
const CYAN := MenuStyle.CYAN

const LOGO_BOX := Vector2(820, 300)
const DOLL_BOX := Vector2(240, 440)
const TM_BOX := Vector2(64, 64)
const ICON_BOX := Vector2(24, 24)
const CASSETTE_BOX := Vector2(40, 26)


# ───────────────────────────── logo ─────────────────────────────

## OVERDUB logotype: the word printed on a cassette label, the shell tilted like a sticker slapped on
## a wall. The reels turn so the title screen reads as "tape is running".
static func paint_logo(ci: CanvasItem, t: float, view: MenuArtView) -> void:
	var tilt := Transform2D(deg_to_rad(-3.5), Vector2.ZERO)
	var pivot := Vector2(410, 150)
	var m := view.base * Transform2D(0.0, pivot) * tilt * Transform2D(0.0, -pivot)
	ci.draw_set_transform_matrix(m)

	# Drop shadow, offset like a screen-printed sticker; then the shell.
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(52, 34, 730, 246), 28), PINK)
	var shell := MenuVector.rounded_rect(Rect2(40, 22, 730, 246), 28)
	ci.draw_colored_polygon(shell, INK)
	_outline(ci, shell, Y, 6)
	for p: Vector2 in [Vector2(70, 50), Vector2(740, 50), Vector2(70, 240), Vector2(740, 240)]:
		ci.draw_circle(p, 7, INK_SOFT)
		ci.draw_arc(p, 7, 0, TAU, 16, PAPER_DIM, 2, true)

	# Label: diagonal yellow hatch, ink header band.
	var label_rect := Rect2(88, 42, 634, 138)
	var label := MenuVector.rounded_rect(label_rect, 12)
	ci.draw_colored_polygon(label, Y)
	var x := label_rect.position.x - label_rect.size.y
	while x < label_rect.end.x:
		var stripe := PackedVector2Array([
			Vector2(x, label_rect.end.y), Vector2(x + 4, label_rect.end.y),
			Vector2(x + 4 + label_rect.size.y, label_rect.position.y), Vector2(x + label_rect.size.y, label_rect.position.y)])
		MenuVector.fill_clipped(ci, stripe, label, MenuStyle.YELLOW_DEEP)
		x += 10.0
	MenuVector.fill_clipped(ci, MenuVector.rounded_rect(Rect2(88, 42, 634, 26), 12), label, INK)
	ci.draw_rect(Rect2(88, 56, 634, 12), INK)
	_outline(ci, label, INK, 4)
	ci.draw_string(MenuStyle.mono_font(), Vector2(106, 61), "SIDE A", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Y)
	for i in OD.TAPE_COUNT:
		ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(560 + i * 36, 49, 30, 12), 2), MenuStyle.tape(i))

	# Wordmark: pink offset print, then ink, stretched across the label like the SVG's textLength
	# (horizontal scale only, so the cap height stays inside the label under the header band).
	var font := MenuStyle.display_font()
	var fs := 96
	var tw := font.get_string_size("OVERDUB", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var sx := 590.0 / maxf(tw, 1.0)
	var word := m * Transform2D(0.0, Vector2(sx, 1.0), 0.0, Vector2(410, 0))
	ci.draw_set_transform_matrix(word)
	ci.draw_string(font, Vector2(-tw * 0.5 + 6.0 / sx, 166), "OVERDUB", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PINK)
	ci.draw_string(font, Vector2(-tw * 0.5, 161), "OVERDUB", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	ci.draw_set_transform_matrix(m)

	# Tape window with the wound tape behind the reels.
	var window := MenuVector.rounded_rect(Rect2(258, 190, 304, 72), 36)
	ci.draw_colored_polygon(window, INK_SOFT)
	var clip := MenuVector.rounded_rect(Rect2(265, 196, 290, 60), 30)
	# The take winds from the left spool to the right one as the title idles.
	var wind := 0.5 + 0.5 * sin(t * 0.25)
	MenuVector.fill_clipped(ci, MenuVector.ellipse(Vector2(320, 226), 30 + 14 * wind, 30 + 14 * wind), clip, Color("#4a2f22"))
	MenuVector.fill_clipped(ci, MenuVector.ellipse(Vector2(500, 226), 44 - 14 * wind, 44 - 14 * wind), clip, Color("#4a2f22"))
	_outline(ci, window, PAPER, 4)
	reel(ci, Vector2(320, 226), 24, t * 2.4)
	reel(ci, Vector2(500, 226), 24, t * 2.4 + 0.7)

	MenuVector.stroke(ci, "M220 268 L250 236 L570 236 L600 268 Z", Color(PAPER_DIM, 0.55), 3)
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(120, 200, 104, 10), 5), Y)
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(120, 218, 70, 10), 5), PINK)
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(596, 200, 104, 10), 5), Y)
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(630, 218, 70, 10), 5), VIOLET)
	ci.draw_set_transform_matrix(view.base)


## A cassette reel: paper hub ring, six ink spokes, yellow centre.
static func reel(ci: CanvasItem, c: Vector2, r: float, angle: float) -> void:
	ci.draw_circle(c, r, PAPER)
	ci.draw_arc(c, r, 0, TAU, 32, INK, 4, true)
	ci.draw_circle(c, r * 0.42, INK)
	for k in 6:
		var a := angle + k * TAU / 6.0
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * r * 0.42, c + d * r * 0.86, INK, 4, true)
	ci.draw_circle(c, r * 0.16, Y)


static func _outline(ci: CanvasItem, poly: PackedVector2Array, col: Color, width: float) -> void:
	var pts := poly.duplicate()
	pts.append(poly[0])
	ci.draw_polyline(pts, col, width, true)


# ───────────────────────────── loadout doll ─────────────────────────────

## Doll pin positions (fraction of the doll's view box) per slot, matching the prototype layout.
const DOLL_PINS: Dictionary[StringName, Vector2] = {
	&"helmet": Vector2(0.50, 0.11),
	&"top": Vector2(0.50, 0.33),
	&"pants": Vector2(0.50, 0.62),
	&"shoes": Vector2(0.50, 0.90),
	&"melee": Vector2(0.09, 0.38),
	&"ranged": Vector2(0.92, 0.56),
}

const HAIR := Color("#2b1d17")
const SKIN := Color("#d9a07a")
const SKIN_SHADE := Color("#c98a62")
const OLIVE := Color("#6b6a3a")
const OLIVE_DARK := Color("#585731")


## Stylised Moxie for the loadout paper doll. Each equipment slot is its own group so the active slot
## can be highlighted (APPAREL-03: slots plainly identified). Base look follows R01: yellow
## headphones, dark pigtails, light crop top, dark jacket with yellow lining, olive low-rise cargo
## pants, belt Walkman, chunky high-tops. view.slot = active slot; view.time drives the halo pulse.
static func paint_doll(ci: CanvasItem, t: float, view: MenuArtView) -> void:
	_doll_base(ci)
	var order: Array[StringName] = [GearSlot.PANTS, GearSlot.SHOES, GearSlot.TOP, GearSlot.HELMET, GearSlot.MELEE, GearSlot.RANGED]
	var active := view.slot
	for s in order:
		if s == active:
			# A pulsing yellow/pink halo marks the slot being browsed.
			var glow := 0.65 + 0.35 * sin(t * 4.0)
			_doll_part(ci, s, Color(PINK, 0.9), 13.0)
			_doll_part(ci, s, Color(Y, glow), 8.0)
		_doll_part(ci, s, Color.TRANSPARENT, 0.0)


static func _doll_base(ci: CanvasItem) -> void:
	MenuVector.fill(ci, "M78 58 C52 44 38 76 46 104 C50 118 40 128 34 138 C58 132 70 112 72 92 Z", HAIR)
	MenuVector.fill(ci, "M162 58 C188 44 202 76 194 104 C190 118 200 128 206 138 C182 132 170 112 168 92 Z", HAIR)
	ci.draw_rect(Rect2(110, 98, 20, 22), SKIN_SHADE)
	ci.draw_colored_polygon(MenuVector.ellipse(Vector2(120, 74), 30, 34), SKIN)
	MenuVector.fill(ci, "M90 70 C88 40 108 30 122 32 C142 32 156 46 150 72 C142 58 132 52 124 50 C118 60 104 64 90 70 Z", HAIR)
	MenuVector.stroke(ci, "M104 86 l8 2 M128 88 l8 -2", INK, 3, true)
	MenuVector.stroke(ci, "M112 98 q8 5 16 0", INK, 2.5, true)
	MenuVector.stroke(ci, "M97 82 l6 6 M97 88 l5 4", PINK, 2, true)
	# Arms (skin) and fingerless gloves; wrist device glow.
	MenuVector.stroke(ci, "M70 128 C56 160 52 196 56 226", SKIN_SHADE, 16, true)
	MenuVector.stroke(ci, "M170 128 C184 160 188 196 184 226", SKIN_SHADE, 16, true)
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(47, 214, 20, 18), 5), INK)
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(173, 214, 20, 18), 5), INK)
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(50, 198, 16, 9), 2), Color(MenuStyle.CYAN, 0.85))
	# Midriff, belt, Walkman and its cable; the hanging strap.
	MenuVector.fill(ci, "M94 168 L146 168 L148 196 L92 196 Z", SKIN)
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(86, 194, 68, 11), 3), INK)
	var walkman := MenuVector.rounded_rect(Rect2(132, 190, 22, 18), 3)
	ci.draw_colored_polygon(walkman, Y)
	_outline(ci, walkman, INK, 2)
	ci.draw_circle(Vector2(139, 199), 3, INK)
	ci.draw_circle(Vector2(147, 199), 3, INK)
	MenuVector.stroke(ci, "M143 190 C150 160 146 120 136 104", Y, 2)
	MenuVector.stroke(ci, "M100 205 l-6 46", Color("#d6336c"), 6, true)


## Draw one slot's part. halo_w > 0 draws only a halo outline of that width in halo_col.
static func _doll_part(ci: CanvasItem, slot: StringName, halo_col: Color, halo_w: float) -> void:
	var halo := halo_w > 0.0
	match slot:
		GearSlot.HELMET:
			_doll_stroke(ci, "M86 70 C84 26 156 26 154 70", Y, 7, halo, halo_col, halo_w)
			_doll_poly(ci, MenuVector.rounded_rect(Rect2(78, 58, 18, 32), 8), Y, INK, 3, halo, halo_col, halo_w)
			_doll_poly(ci, MenuVector.rounded_rect(Rect2(144, 58, 18, 32), 8), Y, INK, 3, halo, halo_col, halo_w)
			if not halo:
				MenuVector.fill(ci, "M150 68 l6 10 l-12 0 z", INK)
		GearSlot.TOP:
			_doll_path(ci, "M96 120 L144 120 L150 170 L90 170 Z", PAPER, INK, 3, halo, halo_col, halo_w)
			if not halo:
				MenuVector.stroke(ci, "M100 122 L142 168", INK_SOFT, 6)
			_doll_path(ci, "M96 118 C78 118 64 126 60 150 L56 196 L76 196 L84 150 L98 170 Z", INK_SOFT, INK, 3, halo, halo_col, halo_w)
			_doll_path(ci, "M144 118 C162 118 176 126 180 150 L184 196 L164 196 L156 150 L142 170 Z", INK_SOFT, INK, 3, halo, halo_col, halo_w)
			if not halo:
				MenuVector.stroke(ci, "M90 128 L98 168", Y, 4)
				MenuVector.stroke(ci, "M150 128 L142 168", Y, 4)
				MenuVector.fill(ci, "M64 150 l10 -6 l2 10 z", Y)
		GearSlot.PANTS:
			_doll_path(ci, "M88 204 L152 204 L168 352 L128 356 L120 262 L112 356 L72 352 Z", OLIVE, INK, 3, halo, halo_col, halo_w)
			if not halo:
				MenuVector.stroke(ci, "M78 300 l14 -14 l0 14 l14 -14", Y, 6)
				MenuVector.shape(ci, "M140 240 l10 0 l0 22 l-10 0 z", OLIVE_DARK, INK, 2)
				MenuVector.stroke(ci, "M72 344 L112 348 M128 348 L168 344", OLIVE_DARK, 8)
		GearSlot.SHOES:
			_doll_path(ci, "M70 356 L112 358 L114 392 L120 404 L60 404 L62 384 Z", PAPER_DIM, INK, 3, halo, halo_col, halo_w)
			_doll_path(ci, "M128 358 L170 356 L178 384 L180 404 L120 404 L126 392 Z", PAPER_DIM, INK, 3, halo, halo_col, halo_w)
			if not halo:
				ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(58, 398, 64, 10), 4), INK_SOFT)
				ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(118, 398, 64, 10), 4), INK_SOFT)
				MenuVector.stroke(ci, "M76 366 l24 8 M76 376 l24 -8 M140 374 l24 -8 M140 366 l24 8", Y, 3)
		GearSlot.MELEE:
			var pivot := Vector2(24, 230)
			_doll_poly(ci, MenuVector.rotated_rect(Rect2(18, 120, 12, 110), -14, pivot), Color("#9aa3b5"), INK, 3, halo, halo_col, halo_w)
			_doll_poly(ci, MenuVector.rotated_rect(Rect2(36, 206, 22, 34), -14, pivot), INK, INK, 0, halo, halo_col, halo_w)
			if not halo:
				var tip := Transform2D(deg_to_rad(-14), Vector2.ZERO)
				ci.draw_line(pivot + tip.basis_xform(Vector2(24, 130) - pivot), pivot + tip.basis_xform(Vector2(30, 118) - pivot), PINK, 3, true)
		GearSlot.RANGED:
			_doll_poly(ci, MenuVector.rounded_rect(Rect2(184, 226, 44, 18), 5), INK_SOFT, INK, 3, halo, halo_col, halo_w)
			_doll_poly(ci, MenuVector.rounded_rect(Rect2(190, 242, 12, 20), 3), INK, INK, 0, halo, halo_col, halo_w)
			if not halo:
				ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(222, 230, 12, 10), 2), Color("#3ec5ff"))
				ci.draw_circle(Vector2(200, 235), 3, Y)


static func _doll_path(ci: CanvasItem, d: String, fill_col: Color, line: Color, w: float, halo: bool, halo_col: Color, halo_w: float) -> void:
	if halo:
		MenuVector.stroke(ci, d, halo_col, halo_w + w)
	else:
		MenuVector.shape(ci, d, fill_col, line, w)


static func _doll_stroke(ci: CanvasItem, d: String, col: Color, w: float, halo: bool, halo_col: Color, halo_w: float) -> void:
	if halo:
		MenuVector.stroke(ci, d, halo_col, w + halo_w, true)
	else:
		MenuVector.stroke(ci, d, col, w, true)


static func _doll_poly(ci: CanvasItem, poly: PackedVector2Array, fill_col: Color, line: Color, w: float, halo: bool, halo_col: Color, halo_w: float) -> void:
	if halo:
		_outline(ci, poly, halo_col, halo_w + w)
		return
	ci.draw_colored_polygon(poly, fill_col)
	if w > 0.0:
		_outline(ci, poly, line, w)


# ───────────────────────────── time machine ─────────────────────────────

## The time machine at the bottom of the descent (WORLD-05): a ringed gate with turning clock hands.
static func paint_time_machine(ci: CanvasItem, t: float, _view: MenuArtView) -> void:
	var c := Vector2(32, 32)
	ci.draw_circle(c, 29, Color(VIOLET, 0.18))
	ci.draw_arc(c, 27, 0, TAU, 48, VIOLET, 4, true)
	ci.draw_circle(c, 20, INK)
	MenuVector.dashed_circle(ci, c, 20, CYAN, 3, 4, 3, -t * 0.4)
	var a1 := t * TAU / 6.0
	var a2 := t * TAU / 24.0
	ci.draw_line(c, c + Vector2(0, -14).rotated(a1), Y, 3, true)
	ci.draw_line(c, c + Vector2(10, 4).rotated(a2), PINK, 3, true)
	ci.draw_circle(c, 3, Y)
	var x := 8.0
	while x < 56.0:
		ci.draw_line(Vector2(x, 54), Vector2(minf(x + 6, 56), 54), Y, 3)
		x += 10.0


# ───────────────────────────── icons ─────────────────────────────

## Padlock for locked levels. view.tint = colour.
static func paint_lock(ci: CanvasItem, _t: float, view: MenuArtView) -> void:
	var col := view.tint
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(5, 10, 14, 11), 2), col)
	ci.draw_arc(Vector2(12, 7), 4, PI, TAU, 12, col, 2.4, true)
	ci.draw_line(Vector2(8, 7), Vector2(8, 10.5), col, 2.4)
	ci.draw_line(Vector2(16, 7), Vector2(16, 10.5), col, 2.4)
	ci.draw_circle(Vector2(12, 15), 1.6, INK)


## Check for cleared levels.
static func paint_check(ci: CanvasItem, _t: float, view: MenuArtView) -> void:
	var pts := PackedVector2Array([Vector2(4, 12.5), Vector2(9, 17.5), Vector2(20, 6)])
	ci.draw_polyline(pts, view.tint, 3.2, true)
	for p in pts:
		ci.draw_circle(p, 1.6, view.tint)


## Crate for loot counts.
static func paint_crate(ci: CanvasItem, _t: float, view: MenuArtView) -> void:
	var col := view.tint
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(3, 7, 18, 13), 2), col)
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(3, 4, 18, 5), 1.5), Color(col, 0.75))
	ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(10, 9, 4, 4), 1), INK)


# ───────────────────────────── cassettes ─────────────────────────────

## A small cassette in a tape's identity colour. view.tape = 0..3, view.on = offered/used,
## view.patterns = colour-blind pattern overlay (A stripes, B dots, C zigzag, D solid bar), the same
## code the HUD decks use.
static func paint_cassette(ci: CanvasItem, _t: float, view: MenuArtView) -> void:
	var body_rect := Rect2(1, 1, 38, 24)
	var body := MenuVector.rounded_rect(body_rect, 4)
	var col := MenuStyle.tape(view.tape)
	if view.on:
		ci.draw_colored_polygon(body, col)
		if view.patterns:
			_pattern(ci, view.tape, body, body_rect)
		ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(5, 4, 30, 7), 2), Color(PAPER, 0.85))
		ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(10, 14, 20, 8), 4), INK)
		ci.draw_circle(Vector2(15, 18), 2.6, PAPER)
		ci.draw_circle(Vector2(25, 18), 2.6, PAPER)
		_outline(ci, body, INK, 1.5)
	else:
		ci.draw_colored_polygon(body, Color(INK, 0.55))
		_outline(ci, body, Color(PAPER_DIM, 0.45), 1.5)
		ci.draw_colored_polygon(MenuVector.rounded_rect(Rect2(10, 14, 20, 8), 4), Color(PAPER_DIM, 0.2))


static func _pattern(ci: CanvasItem, tape: int, body: PackedVector2Array, r: Rect2) -> void:
	var ink := Color(INK, 0.45)
	# The same four patterns as the HUD (AccessKit), so a tape reads the same on every screen.
	if UiArt.draw_pattern(ci, r.grow(-1.0), tape, ink, 12.0):
		return
	match tape:
		0:
			var x := r.position.x - r.size.y
			while x < r.end.x:
				MenuVector.fill_clipped(ci, PackedVector2Array([
					Vector2(x, r.end.y), Vector2(x + 2.5, r.end.y),
					Vector2(x + 2.5 + r.size.y, r.position.y), Vector2(x + r.size.y, r.position.y)]), body, ink)
				x += 6.0
		1:
			for yy in range(int(r.position.y) + 4, int(r.end.y), 5):
				for xx in range(int(r.position.x) + 4, int(r.end.x), 5):
					ci.draw_circle(Vector2(xx, yy), 1.1, ink)
		2:
			var pts := PackedVector2Array()
			var xx := r.position.x + 2
			var up := true
			while xx <= r.end.x - 2:
				pts.append(Vector2(xx, r.position.y + (4.0 if up else 10.0)))
				up = not up
				xx += 4.0
			ci.draw_polyline(pts, ink, 1.6, true)
		3:
			ci.draw_rect(Rect2(r.position.x + 2, r.end.y - 6, r.size.x - 4, 3), ink)


# ───────────────────────────── slider grabber ─────────────────────────────

static var _grabbers: Dictionary[bool, Texture2D] = {}


## A little reel used as the slider knob.
static func slider_grabber(highlight: bool) -> Texture2D:
	if _grabbers.has(highlight):
		return _grabbers[highlight]
	var size := 24
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var ring := MenuStyle.PINK if highlight else MenuStyle.YELLOW
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var col := Color(0, 0, 0, 0)
			if d <= 11.5:
				col = MenuStyle.INK
			if d <= 9.5:
				col = ring
			if d <= 4.0:
				col = MenuStyle.INK
			if d <= 1.8:
				col = MenuStyle.PAPER
			# Soft edge.
			var edge := clampf(11.5 - d + 0.5, 0.0, 1.0)
			col.a *= edge
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_grabbers[highlight] = tex
	return tex
