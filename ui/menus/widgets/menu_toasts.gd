class_name MenuToasts
extends VBoxContainer
## Toast stack (prototype ui/index.ts toast): top-right, newest at the bottom, at most TOAST_MAX;
## each stays TOAST_SECONDS then fades out. Tones: UiBase.TONE_INFO / TONE_GOOD / TONE_WARN.

const TOAST_SECONDS := 3.2
const FADE_SECONDS := 0.26
const TOAST_MAX := 4
const WIDTH := 380.0


func _init() -> void:
	name = "Toasts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size.x = WIDTH


func push(text: String, tone: StringName = UiBase.TONE_INFO) -> PanelContainer:
	var accent := MenuStyle.YELLOW
	match tone:
		UiBase.TONE_GOOD:
			accent = MenuStyle.GOOD
		UiBase.TONE_WARN:
			accent = MenuStyle.WARN
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The generated toast (assets/ui/art/ui/toast.png: hazard-striped cap, inked body), a fixed-height
	# 3-slice drawn at half size; the flat box remains the fallback.
	var art := UiArt.nine("toast", 0.5)
	var sb: StyleBox = null
	if art != null:
		art.content_margin_left = art.texture_margin_left + 12
		art.content_margin_right = 16
		art.content_margin_top = 9
		art.content_margin_bottom = 11
		if tone == UiBase.TONE_GOOD:
			art.modulate_color = Color(0.82, 1.0, 0.86)
		sb = art
	else:
		var flat := MenuStyle.box(Color(MenuStyle.INK, 0.92), Color(accent, 0.8), 0, MenuStyle.RADIUS_SM, Color(0, 0, 0, 0.4), Vector2(4, 4))
		flat.border_width_left = 6
		MenuStyle.pad(flat, 16, 10)
		flat.content_margin_left = 18
		sb = flat
	p.add_theme_stylebox_override("panel", sb)
	var l := MenuStyle.label(text, MenuStyle.ui_bold_font(), 16, MenuStyle.PAPER, true)
	l.custom_minimum_size.x = WIDTH - 40
	p.add_child(l)
	p.set_meta(&"tone", tone)
	add_child(p)
	while get_child_count() > TOAST_MAX:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	p.modulate = Color(1, 1, 1, 0)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.14)
	tw.tween_interval(TOAST_SECONDS)
	tw.tween_property(p, "modulate:a", 0.0, FADE_SECONDS)
	tw.tween_callback(p.queue_free)
	return p


var _scale: float = 1.0


func set_text_scale(sc: float) -> void:
	_scale = clampf(sc, 0.75, 2.0)
	custom_minimum_size.x = WIDTH * minf(_scale, 1.3)


func texts() -> Array[String]:
	var out: Array[String] = []
	for c in get_children():
		if c.is_queued_for_deletion():
			continue
		var l := c.get_child(0) as Label
		if l != null:
			out.append(l.text)
	return out


func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
