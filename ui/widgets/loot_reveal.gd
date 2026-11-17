class_name WidgetLootReveal
extends Control
## The results-screen loot moment (GEAR-02 "upgrades are physical equipment", APPAREL-02 "found as
## loot"): a kit chest drops in, rattles and opens in a SubViewport, and each found item pops out as a
## sticker card (icon, slot, name, effect line, NEW stamp). Then a prompt: equip now or later.
##
## Chest: res://assets/models/kit/chest__upper.glb (upper / mid themes) or chest__lower.glb (lower /
## core), whose `Lid` object is hinged on its origin and opens by rotating about local X (negative
## opens; kit manifest note). Without the model a drawn chest stands in.
##
## API (see docs/WIDGETS.md):
##   show_loot(items, theme := LevelTheme.UPPER, owned_before := [])   start the reveal
##   skip()            jump to the end of the reveal (prompt showing)
##   seek(t)           jump to time t seconds into the reveal (screenshots, tests)
##   signal choice_made(equip_now: bool, item_ids: PackedStringArray)   once, on a button/ui action
##   signal reveal_finished()                                            when the prompt appears
## Accept (ui_accept) skips the reveal, then picks EQUIP NOW; cancel (ui_cancel) picks LATER.
## Equipping is not done here: the menus/game decide what "equip now" means (e.g. open the loadout
## screen focused on these items, or equip each into its slot).

signal choice_made(equip_now: bool, item_ids: PackedStringArray)
signal reveal_finished()

const CHEST_UPPER := "res://assets/models/kit/chest__upper.glb"
const CHEST_LOWER := "res://assets/models/kit/chest__lower.glb"
const LID_OPEN_DEG := -110.0

const T_DROP := 0.55
const T_RATTLE := 1.05
const T_OPEN := 1.45
const CARD_GAP := 0.42
const CARD_FLIGHT := 0.5
const STAMP_DELAY := 0.15

var items: Array[GearItem] = []
var new_flags: Array[bool] = []
var level_theme: StringName = LevelTheme.UPPER
var t: float = 0.0
var playing: bool = false
var finished: bool = false
var chose: bool = false

var _vp_container: SubViewportContainer = null
var _vp: SubViewport = null
var _chest_root: Node3D = null
var _lid: Node3D = null
var _lid_rest: Basis = Basis()
var _has_model: bool = false
var _cards: Array[WidgetLootCard] = []
var _prompt: Control = null
var _btn_now: Button = null
var _btn_later: Button = null
var _caption: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var th := UiPalette.theme()
	if th != null:
		theme = th
	_build()
	resized.connect(_relayout)


func _build() -> void:
	_vp_container = SubViewportContainer.new()
	_vp_container.stretch = true
	_vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vp_container)
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp_container.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.7, 0.8)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.4
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.8)
	key.light_energy = 1.15
	key.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(28.0), 0.0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.75, 0.55, 1.0)
	rim.light_energy = 0.9
	rim.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(200.0), 0.0)
	_vp.add_child(rim)
	var glow := OmniLight3D.new()
	glow.name = "LootGlow"
	glow.light_color = Color(1.0, 0.85, 0.4)
	glow.light_energy = 0.0
	glow.omni_range = 2.5
	glow.position = Vector3(0, 0.45, 0.0)
	_vp.add_child(glow)
	var cam := Camera3D.new()
	cam.fov = 28.0
	cam.position = Vector3(0.0, 1.25, 2.6)
	_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.32, 0), Vector3.UP)
	cam.current = true
	_chest_root = Node3D.new()
	_vp.add_child(_chest_root)

	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	_prompt = HBoxContainer.new()
	(_prompt as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("separation", 24)
	add_child(_prompt)
	_btn_now = Button.new()
	_btn_now.text = "EQUIP NOW"
	_btn_now.pressed.connect(func() -> void: _choose(true))
	_prompt.add_child(_btn_now)
	_btn_later = Button.new()
	_btn_later.text = "LATER"
	_btn_later.pressed.connect(func() -> void: _choose(false))
	_prompt.add_child(_btn_later)
	_prompt.visible = false


func _load_chest() -> void:
	for c: Node in _chest_root.get_children():
		c.queue_free()
	_lid = null
	_has_model = false
	var path := CHEST_LOWER if (level_theme == LevelTheme.LOWER or level_theme == LevelTheme.CORE) else CHEST_UPPER
	if not ResourceLoader.exists(path):
		path = CHEST_UPPER if ResourceLoader.exists(CHEST_UPPER) else ""
	if path == "":
		return
	var ps := load(path) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return
	_chest_root.add_child(inst)
	_lid = inst.find_child("Lid", true, false) as Node3D
	if _lid != null:
		_lid_rest = _lid.transform.basis
	_has_model = true


## Start the reveal for `p_items`. `owned_before` = gear ids the player had before this level; an
## item is NEW unless its id is in it (pass [] to stamp everything NEW).
func show_loot(p_items: Array[GearItem], p_theme: StringName = LevelTheme.UPPER, owned_before: Array = []) -> void:
	items = p_items.duplicate()
	level_theme = p_theme
	new_flags.clear()
	for it: GearItem in items:
		new_flags.append(not owned_before.has(it.id))
	for c: WidgetLootCard in _cards:
		c.queue_free()
	_cards.clear()
	for i: int in items.size():
		var card := WidgetLootCard.new()
		card.set_item(items[i], new_flags[i])
		card.visible = false
		add_child(card)
		_cards.append(card)
	move_child(_prompt, get_child_count() - 1)
	_load_chest()
	t = 0.0
	playing = true
	finished = false
	chose = false
	_prompt.visible = false
	if items.is_empty():
		_btn_now.visible = false
		_btn_later.text = "CONTINUE"
	else:
		_btn_now.visible = true
		_btn_later.text = "LATER"
	_relayout()
	_apply(t)


## Total length of the reveal, seconds.
func duration() -> float:
	if items.is_empty():
		return T_OPEN + 0.4
	return T_OPEN + 0.15 + CARD_GAP * (items.size() - 1) + CARD_FLIGHT + STAMP_DELAY + 0.35


func skip() -> void:
	seek(duration())


func seek(p_t: float) -> void:
	t = clampf(p_t, 0.0, duration())
	_apply(t)


func _process(delta: float) -> void:
	if playing and not finished:
		t = minf(t + delta, duration())
		_apply(t)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not playing or chose:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if not finished:
			skip()
		elif items.is_empty():
			_choose(false)
		else:
			_choose(true)
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not finished:
			skip()
		else:
			_choose(false)


func _choose(equip_now: bool) -> void:
	if chose:
		return
	chose = true
	# The found items either way: "later" callers may still want to highlight them as new.
	var ids := PackedStringArray()
	for it: GearItem in items:
		ids.append(it.id)
	choice_made.emit(equip_now, ids)


# ───────────────────────────── layout and animation ─────────────────────────────

func _u() -> float:
	return WidgetDraw.unit(self)


func _chest_rect() -> Rect2:
	var u := _u()
	var w := minf(u * 26.0, size.x * 0.5)
	var h := w * 0.72
	var top := size.y * 0.06
	return Rect2(Vector2((size.x - w) * 0.5, top), Vector2(w, h))


## Screen point where cards emerge (the chest's mouth).
func _mouth() -> Vector2:
	var r := _chest_rect()
	return Vector2(r.get_center().x, r.position.y + r.size.y * 0.5)


func _card_size() -> Vector2:
	var u := _u()
	var n := maxi(1, items.size())
	var w := minf(u * 13.0, (size.x - u * 4.0) / n - u * 1.6)
	return Vector2(w, w * 1.38)


func _card_slot(i: int) -> Vector2:
	var u := _u()
	var cs := _card_size()
	var n := items.size()
	var gap := u * 1.6
	var total := n * cs.x + (n - 1) * gap
	var x := (size.x - total) * 0.5 + i * (cs.x + gap)
	var y := _chest_rect().end.y + u * 1.4
	return Vector2(x, y)


func _relayout() -> void:
	if _vp_container == null:
		return
	var cr := _chest_rect()
	_vp_container.position = cr.position
	_vp_container.size = cr.size
	var u := _u()
	_caption.add_theme_font_override("font", UiPalette.font_display())
	_caption.add_theme_font_size_override("font_size", int(u * 1.5))
	_caption.add_theme_color_override("font_color", UiPalette.PAPER)
	_caption.add_theme_color_override("font_outline_color", UiPalette.INK)
	_caption.add_theme_constant_override("outline_size", int(u * 0.35))
	_caption.position = Vector2(0, cr.end.y - u * 2.4)
	_caption.size = Vector2(size.x, u * 2.0)
	var cs := _card_size()
	for c: WidgetLootCard in _cards:
		c.size = cs
		c.pivot_offset = cs * 0.5
	_prompt.position = Vector2(0, minf(size.y - u * 5.0, _card_slot(0).y + cs.y + u * 2.2))
	_prompt.size = Vector2(size.x, u * 3.0)
	for b: Button in [_btn_now, _btn_later]:
		b.custom_minimum_size = Vector2(u * 11.0, u * 2.6)
		b.add_theme_font_override("font", UiPalette.font_display())
		b.add_theme_font_size_override("font_size", int(u * 1.0))
	_apply(t)


static func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var k := x - 1.0
	return 1.0 + c3 * k * k * k + c1 * k * k


## Lid opening 0..1 at reveal time `p_t` (exposed for tests).
func lid_open(p_t: float) -> float:
	if p_t <= T_RATTLE:
		return 0.0
	return clampf(_ease_out_back(clampf((p_t - T_RATTLE) / (T_OPEN - T_RATTLE), 0.0, 1.0)), 0.0, 1.15)


## Card i's flight progress 0..1 at time `p_t`.
func card_progress(i: int, p_t: float) -> float:
	var start := T_OPEN + 0.15 + CARD_GAP * i
	return clampf((p_t - start) / CARD_FLIGHT, 0.0, 1.0)


func _apply(p_t: float) -> void:
	if _chest_root == null:
		return
	# Chest: drop in with a bounce, rattle, then open.
	var drop := clampf(p_t / T_DROP, 0.0, 1.0)
	var y := (1.0 - _ease_out_back(drop)) * 1.2
	var rattle := 0.0
	if p_t > T_DROP and p_t < T_RATTLE:
		var k := (p_t - T_DROP) / (T_RATTLE - T_DROP)
		rattle = sin(k * TAU * 3.0) * 0.07 * (1.0 - k)
	_chest_root.position = Vector3(0, y, 0)
	_chest_root.rotation = Vector3(0, deg_to_rad(-18.0), rattle)
	var open := lid_open(p_t)
	if _lid != null:
		_lid.transform.basis = _lid_rest * Basis(Vector3.RIGHT, deg_to_rad(LID_OPEN_DEG) * open)
	var glow := _vp.get_node_or_null("LootGlow") as OmniLight3D
	if glow != null:
		glow.light_energy = 1.2 * clampf(open, 0.0, 1.0)
	_vp_container.modulate.a = clampf(drop * 3.0, 0.0, 1.0)
	# Cards.
	var mouth := _mouth()
	var cs := _card_size()
	for i: int in _cards.size():
		var card := _cards[i]
		var k := card_progress(i, p_t)
		card.visible = k > 0.0
		if k <= 0.0:
			continue
		var target := _card_slot(i)
		var from := mouth - cs * 0.5
		var e := _ease_out_back(k)
		var arc := -sin(k * PI) * _u() * 6.0
		card.position = from.lerp(target, e) + Vector2(0, arc)
		var sc := lerpf(0.15, 1.0, e)
		card.scale = Vector2(sc, sc)
		var tilt := (-0.06 if i % 2 == 0 else 0.05)
		card.rotation = lerpf(0.9 * (1 if i % 2 == 0 else -1), tilt, e)
		card.stamp = clampf((p_t - (T_OPEN + 0.15 + CARD_GAP * i + CARD_FLIGHT + STAMP_DELAY)) / 0.18, 0.0, 1.0)
		card.queue_redraw()
	# Caption and prompt.
	if items.is_empty():
		_caption.text = "NOTHING NEW IN THIS ONE" if p_t >= T_OPEN else ""
	else:
		_caption.text = ""
	var done := p_t >= duration() - 1e-6
	_prompt.visible = done
	if done and not finished:
		finished = true
		if _btn_now.visible:
			_btn_now.grab_focus.call_deferred()
		else:
			_btn_later.grab_focus.call_deferred()
		reveal_finished.emit()
	queue_redraw()


func _draw() -> void:
	var u := _u()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.04, 0.05, 0.9))
	var open := clampf(lid_open(t), 0.0, 1.0)
	var mouth := _mouth()
	# Light burst behind the chest once it opens: rays in the slot colours of what is inside.
	# (A burst too small to see is skipped: a sub-pixel triangle cannot be triangulated.)
	if open > 0.03:
		var n := 14
		var rad := u * 22.0 * open
		for k: int in n:
			var a0 := TAU * k / n + t * 0.25
			var a1 := a0 + TAU / n * 0.45
			var col := UiPalette.MOXIE_YELLOW
			if not items.is_empty():
				col = WidgetLootCard.slot_color(items[k % items.size()].slot)
			var pts := PackedVector2Array([mouth, mouth + Vector2.from_angle(a0) * rad, mouth + Vector2.from_angle(a1) * rad])
			draw_colored_polygon(pts, UiPalette.alpha(col, 0.16 * open))
		draw_circle(mouth, u * 4.0 * open, UiPalette.alpha(UiPalette.MOXIE_YELLOW, 0.25 * open))
	if not _has_model:
		_draw_fallback_chest(u, open)
	# Header.
	var display := UiPalette.font_display()
	var head := "LOOT" if not items.is_empty() else "NO LOOT"
	var hs := int(u * 1.8)
	WidgetDraw.text(self, display, Vector2(u * 2.0, u * 3.2), head, hs, UiPalette.MOXIE_YELLOW, u * 0.35)
	if not items.is_empty():
		var sub := "%d piece%s of gear found" % [items.size(), "" if items.size() == 1 else "s"]
		WidgetDraw.text(self, UiPalette.font_ui(), Vector2(u * 2.0, u * 4.6), sub, int(u * 0.9), UiPalette.PAPER_DIM)
	if finished and not items.is_empty() and _prompt != null:
		var hint := "Gear swaps freely between levels on the loadout screen."
		WidgetDraw.text_centered(self, UiPalette.font_ui(), Vector2(size.x * 0.5, _prompt.position.y + _prompt.size.y + u * 0.9), hint, int(u * 0.75), UiPalette.PAPER_DIM)


## A drawn chest for when the kit model is missing.
func _draw_fallback_chest(u: float, open: float) -> void:
	var cr := _chest_rect()
	var drop := clampf(t / T_DROP, 0.0, 1.0)
	var c := cr.get_center() + Vector2(0, (1.0 - _ease_out_back(drop)) * -u * 10.0)
	var w := cr.size.x * 0.5
	var h := w * 0.5
	var body := Rect2(c + Vector2(-w * 0.5, 0), Vector2(w, h))
	WidgetDraw.panel(self, body, Color("#8a5a2b"), UiPalette.INK, u * 0.25, u * 0.4, u * 0.3)
	draw_rect(Rect2(body.position + Vector2(0, h * 0.2), Vector2(w, h * 0.16)), UiPalette.MOXIE_YELLOW)
	draw_rect(Rect2(body.get_center() - Vector2(u * 0.6, u * 0.5), Vector2(u * 1.2, u * 1.3)), Color("#c9a24a"))
	# Lid hinged at the back: draw it rotated up about its back edge.
	var hinge := body.position + Vector2(w * 0.5, 0)
	draw_set_transform(hinge, 0.0, Vector2(1.0, lerpf(1.0, -0.55, clampf(open, 0.0, 1.0))))
	WidgetDraw.panel(self, Rect2(Vector2(-w * 0.52, -h * 0.55), Vector2(w * 1.04, h * 0.55)), Color("#a06a32"), UiPalette.INK, u * 0.25, u * 0.6)
	draw_rect(Rect2(Vector2(-w * 0.52, -h * 0.32), Vector2(w * 1.04, h * 0.12)), UiPalette.MOXIE_YELLOW)
	draw_set_transform(Vector2.ZERO)
