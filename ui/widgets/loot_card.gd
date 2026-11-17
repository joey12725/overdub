class_name WidgetLootCard
extends Control
## One found item as a sticker card (GEAR-02, APPAREL-02/03): icon, slot, name, effect line and a
## NEW stamp. Used by WidgetLootReveal; usable on its own (set_item, then size it).
##
## Icon: res://assets/ui/icons/gear/<item id>.png when it exists, else a drawn glyph for the slot.

const ICON_DIR := "res://assets/ui/icons/gear/"

const SLOT_COLOR: Dictionary[StringName, Color] = {
	GearSlot.HELMET: Color("#ffd23f"),
	GearSlot.TOP: Color("#ff4fa3"),
	GearSlot.PANTS: Color("#9bbf4a"),
	GearSlot.SHOES: Color("#4ff3ff"),
	GearSlot.MELEE: Color("#ff7a2f"),
	GearSlot.RANGED: Color("#a25bff"),
}

const SLOT_NAME: Dictionary[StringName, String] = {
	GearSlot.HELMET: "HEADGEAR",
	GearSlot.TOP: "TOP",
	GearSlot.PANTS: "PANTS",
	GearSlot.SHOES: "SHOES",
	GearSlot.MELEE: "MELEE",
	GearSlot.RANGED: "RANGED",
}

var item: GearItem = null
var is_new: bool = true
## 0..1 progress of the NEW stamp (0 = not stamped yet).
var stamp: float = 1.0
var _icon: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_item(p_item: GearItem, p_is_new: bool) -> void:
	item = p_item
	is_new = p_is_new
	_icon = icon_for(p_item)
	queue_redraw()


## The item's icon texture, or null when none is on disk.
static func icon_for(p_item: GearItem) -> Texture2D:
	if p_item == null or p_item.id == "":
		return null
	var path := ICON_DIR + p_item.id + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func slot_color(slot: StringName) -> Color:
	return SLOT_COLOR.get(slot, UiPalette.PAPER)


func _draw() -> void:
	if item == null:
		return
	var u := size.x / 13.0
	var r := Rect2(Vector2.ZERO, size)
	var accent := slot_color(item.slot)
	# Paper sticker with a thick ink border, a die-cut white rim and a hard shadow.
	WidgetDraw.panel(self, r.grow(u * 0.35), Color.WHITE, UiPalette.INK, maxf(2.0, u * 0.22), u * 1.0, u * 0.45)
	WidgetDraw.panel(self, r, UiPalette.PAPER, UiPalette.INK, maxf(1.5, u * 0.12), u * 0.75)
	# Icon well.
	var well := Rect2(Vector2(u * 0.7, u * 0.7), Vector2(size.x - u * 1.4, size.y * 0.46))
	WidgetDraw.panel(self, well, UiPalette.alpha(accent, 0.28), UiPalette.alpha(UiPalette.INK, 0.6), 1.5, u * 0.5)
	if _icon != null:
		var side := minf(well.size.x, well.size.y) * 0.96
		draw_texture_rect(_icon, Rect2(well.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)), false)
	else:
		draw_slot_glyph(self, item.slot, well.get_center(), minf(well.size.x, well.size.y) * 0.62, accent)
	# Slot chip.
	var mono := UiPalette.font_mono()
	var display := UiPalette.font_display()
	var ui := UiPalette.font_ui()
	var slot_txt: String = SLOT_NAME.get(item.slot, String(item.slot).to_upper())
	var cs := int(u * 0.62)
	var cw := WidgetDraw.text_width(mono, slot_txt, cs) + u * 0.9
	var chip := Rect2(Vector2(u * 0.7, well.end.y + u * 0.5), Vector2(cw, u * 1.05))
	WidgetDraw.panel(self, chip, accent, UiPalette.INK, 1.5, u * 0.3)
	WidgetDraw.text(self, mono, chip.position + Vector2(u * 0.45, chip.size.y * 0.5 + cs * 0.36), slot_txt, cs, UiPalette.INK)
	# Name (shrinks to fit).
	var ns := int(u * 1.05)
	while ns > 8 and WidgetDraw.text_width(display, item.name.to_upper(), ns) > size.x - u * 1.4:
		ns -= 1
	var ny := chip.end.y + u * 1.35
	WidgetDraw.text(self, display, Vector2(u * 0.7, ny), item.name.to_upper(), ns, UiPalette.INK)
	# Effect line, wrapped.
	var es := int(u * 0.62)
	draw_multiline_string(ui, Vector2(u * 0.7, ny + u * 1.0), item.effect, HORIZONTAL_ALIGNMENT_LEFT, size.x - u * 1.4, es, 5, UiPalette.INK_SOFT)
	# NEW stamp, top-right, rotated.
	if is_new and stamp > 0.0:
		var k := clampf(stamp, 0.0, 1.0)
		var sc := lerpf(2.2, 1.0, ease(k, 0.4))
		var c := Vector2(size.x - u * 1.2, u * 1.0)
		draw_set_transform(c, -0.22, Vector2(sc, sc))
		var sw := u * 3.4
		var sh := u * 1.45
		WidgetDraw.panel(self, Rect2(Vector2(-sw * 0.5, -sh * 0.5), Vector2(sw, sh)), UiPalette.alpha(UiPalette.GRAFFITI_PINK, k), UiPalette.alpha(UiPalette.INK, k), maxf(2.0, u * 0.16), u * 0.3)
		WidgetDraw.text_centered(self, display, Vector2.ZERO, "NEW", int(u * 0.95), UiPalette.alpha(Color.WHITE, k), u * 0.2)
		draw_set_transform(Vector2.ZERO)


## Simple slot glyphs used when an item has no icon art yet.
static func draw_slot_glyph(ci: CanvasItem, slot: StringName, c: Vector2, size: float, color: Color) -> void:
	var s := size / 24.0
	var o := c - Vector2(12, 12) * s
	var ink := UiPalette.INK
	var w := maxf(2.0, 2.2 * s)
	match slot:
		GearSlot.HELMET:
			ci.draw_arc(o + Vector2(12, 14) * s, 8.5 * s, PI, TAU, 24, ink, w * 2.2, true)
			ci.draw_arc(o + Vector2(12, 14) * s, 8.5 * s, PI, TAU, 24, color, w, true)
			for x: float in [3.5, 20.5]:
				var cup := Rect2(o + Vector2(x - 2.8, 11.5) * s, Vector2(5.6, 8) * s)
				WidgetDraw.panel(ci, cup, color, ink, w * 0.8, 2.0 * s)
		GearSlot.TOP:
			var pts := PackedVector2Array([Vector2(8, 3), Vector2(16, 3), Vector2(22, 8), Vector2(19, 11), Vector2(17, 9), Vector2(17, 21), Vector2(7, 21), Vector2(7, 9), Vector2(5, 11), Vector2(2, 8)])
			_poly(ci, o, s, pts, color, ink, w)
		GearSlot.PANTS:
			var pts := PackedVector2Array([Vector2(6, 3), Vector2(18, 3), Vector2(20, 21), Vector2(14, 21), Vector2(12, 10), Vector2(10, 21), Vector2(4, 21)])
			_poly(ci, o, s, pts, color, ink, w)
		GearSlot.SHOES:
			var pts := PackedVector2Array([Vector2(3, 9), Vector2(10, 9), Vector2(13, 13), Vector2(21, 15), Vector2(21, 20), Vector2(3, 20)])
			_poly(ci, o, s, pts, color, ink, w)
		GearSlot.MELEE:
			var pts := PackedVector2Array([Vector2(19, 2), Vector2(22, 5), Vector2(9, 18), Vector2(6, 15)])
			_poly(ci, o, s, pts, color, ink, w)
			ci.draw_line(o + Vector2(4, 13) * s, o + Vector2(11, 20) * s, ink, w * 1.6)
			ci.draw_line(o + Vector2(7.5, 16.5) * s, o + Vector2(3, 21) * s, ink, w * 1.8)
		GearSlot.RANGED:
			var body := Rect2(o + Vector2(3, 6) * s, Vector2(18, 12) * s)
			WidgetDraw.panel(ci, body, color, ink, w, 2.0 * s)
			for x: float in [8.5, 15.5]:
				ci.draw_circle(o + Vector2(x, 11) * s, 2.6 * s, ink)
		_:
			ci.draw_circle(c, size * 0.4, color)


static func _poly(ci: CanvasItem, o: Vector2, s: float, src: PackedVector2Array, fill: Color, ink: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in src:
		pts.append(o + p * s)
	ci.draw_colored_polygon(pts, fill)
	var rim := pts.duplicate()
	rim.append(pts[0])
	ci.draw_polyline(rim, ink, w, true)
