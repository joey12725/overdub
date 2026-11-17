class_name WidgetThresholdBadges
extends Control
## World-anchored, screen-aligned badges (Scenario K, HEALTH-02, MOM-01):
##   - breakables and cores: the force a single hit needs, as diamond pips matching the momentum
##     gauge's segments (one pip = WidgetMath.PIP_MOMENTUM). While a take is being recorded the pips
##     fill up to what the live self's heaviest swing could reach at this tape speed (running fully
##     into it); a met requirement shows a tick, an unreachable one names the tape speed that would
##     do it ("2×") - so "faster tape hits harder" reads straight off the wall.
##   - multi-hit enemies (max hp >= 2, not the boss): hit-point pips over the head, with a shield
##     icon while a shielder's shield is up.
##
## API (see docs/WIDGETS.md):
##   setup(level, loadout)                    per level
##   update_badges(snap, view, projector)     per frame
## Full-rect, mouse-transparent overlay.

## Badges with more slots than this draw one pip and a number.
const MAX_PIPS := 8

var level: LevelDef = null
var loadout: ResolvedLoadout = null

## Prepared draw list: [kind, screen pos, Dictionary of fields].
var _badges: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_level: LevelDef, p_loadout: ResolvedLoadout) -> void:
	level = p_level
	loadout = p_loadout
	_badges.clear()
	queue_redraw()


func update_badges(snap: FrameSnapshot, view: SessionView, projector: WidgetProjector) -> void:
	_badges = build_badges(level, loadout, snap, view, projector, size)
	queue_redraw()


## The badges to draw this frame, as dictionaries (also used by tests):
##   {kind: &"breakable"|&"core"|&"enemy", id, pos: Vector2 (screen), need: float, slots: int,
##    reach: float (pips the live heavy can fill; -1 = no live self), met: bool, min_speed: float,
##    hp: int, max_hp: int, shield: bool, tape: int}
static func build_badges(p_level: LevelDef, p_loadout: ResolvedLoadout, snap: FrameSnapshot, view: SessionView, projector: WidgetProjector, screen: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if projector == null or not projector.valid():
		return out
	var live: ActorSnap = null
	if snap != null and view != null and view.phase == SessionPhase.RECORDING:
		for a: ActorSnap in snap.actors:
			if a.live and a.life != OD.LifeState.GHOST:
				live = a
				break
	var speed := 1.0
	if live != null and live.tape < view.decks.size() and view.decks[live.tape].speed > 0.0:
		speed = view.decks[live.tape].speed
	var reach := -1.0
	if live != null and p_loadout != null:
		var p := WidgetMath.preview_swing(p_loadout, ActionKind.HEAVY, speed, 0.0, 0.0, 0.0)
		reach = p.full
	var speeds: Array[float] = []
	if view != null and not view.speeds.is_empty():
		speeds = view.speeds
	elif p_level != null:
		speeds = p_level.speeds
	var bounds := Rect2(Vector2(-60, -60), screen + Vector2(120, 120))
	if p_level != null:
		for e: EntityDef in p_level.entities_of(EntityKind.BREAKABLE):
			var b := e as BreakableDef
			if WidgetMath._mech_on(snap, b.id):
				continue
			var pos := projector.to_screen(Vector2(b.c + 0.5, b.r + 0.5), WidgetMath.BREAKABLE_BADGE_HEIGHT)
			if not bounds.has_point(pos):
				continue
			out.append(_force_badge(WidgetMath.KIND_BREAKABLE, b.id, pos, WidgetMath.breakable_threshold(b), reach, p_loadout, speeds, live))
		for e: EntityDef in p_level.entities_of(EntityKind.CORE):
			var co := e as CoreDef
			if WidgetMath._mech_on(snap, co.id):
				continue
			var pos := projector.to_screen(Vector2(co.x, co.y), WidgetMath.CORE_BADGE_HEIGHT)
			if not bounds.has_point(pos):
				continue
			out.append(_force_badge(WidgetMath.KIND_CORE, co.id, pos, WidgetMath.core_threshold(co), reach, p_loadout, speeds, live))
	if snap != null:
		for en: EnemySnap in snap.enemies:
			if not en.alive or en.type == EnemyType.BOSS or en.max_hp < 2:
				continue
			var h: float = WidgetMath.HEAD_HEIGHT.get(en.type, 1.5)
			var pos := projector.to_screen(Vector2(en.x, en.y), h)
			if not bounds.has_point(pos):
				continue
			out.append({
				"kind": WidgetMath.KIND_ENEMY, "id": en.id, "pos": pos, "hp": en.hp, "max_hp": en.max_hp,
				"shield": en.has_shield and en.shield, "type": en.type,
			})
	return out


static func _force_badge(kind: StringName, id: String, pos: Vector2, need: float, reach: float, p_loadout: ResolvedLoadout, speeds: Array[float], live: ActorSnap) -> Dictionary:
	var met := reach >= 0.0 and WidgetMath.meets(reach, need)
	return {
		"kind": kind, "id": id, "pos": pos, "need": need, "slots": WidgetMath.pip_slots(need),
		"reach": (WidgetMath.force_pips(reach) if reach >= 0.0 else -1.0), "met": met,
		"min_speed": (WidgetMath.min_speed_for(p_loadout, need, speeds) if reach >= 0.0 and not met else 0.0),
		"tape": (live.tape if live != null else -1),
	}


func _draw() -> void:
	var u := WidgetDraw.unit(self)
	for b: Dictionary in _badges:
		if b["kind"] == WidgetMath.KIND_ENEMY:
			_draw_enemy(b, u)
		else:
			_draw_force(b, u)


func _draw_force(b: Dictionary, u: float) -> void:
	var pos: Vector2 = b["pos"]
	var slots: int = b["slots"]
	var need: float = b["need"]
	var reach: float = b["reach"]
	var tape: int = b["tape"]
	var met: bool = b["met"]
	var pip := u * 0.78
	var compact := slots > MAX_PIPS
	var shown_slots := 1 if compact else slots
	var display := UiPalette.font_display()
	var mono := UiPalette.font_mono()
	var num := WidgetMath.fmt(need)
	var ns := int(u * 0.8)
	var pips_w := shown_slots * pip + (shown_slots - 1) * pip * 0.35
	var num_w := WidgetDraw.text_width(mono, num, ns)
	var icon_w := u * 1.2
	var w := icon_w + pips_w + u * 0.45 + num_w + u * 0.9
	var status := ""
	var status_icon := &""
	var status_col := UiPalette.PAPER
	if reach >= 0.0:
		if met:
			status_icon = WidgetDraw.ICON_CHECK
			status_col = UiPalette.STATE_GOOD
		elif float(b["min_speed"]) > 0.0:
			status = WidgetMath.speed_label(float(b["min_speed"]))
			status_col = UiPalette.STATE_WARN
		else:
			status_icon = WidgetDraw.ICON_CROSS
			status_col = UiPalette.THREAT
	var ss := int(u * 0.7)
	var status_w := 0.0
	if status != "":
		status_w = WidgetDraw.text_width(display, status, ss) + u * 0.8
	elif status_icon != &"":
		status_w = u * 1.2
	w += status_w
	var h := u * 1.45
	var box := Rect2(pos - Vector2(w * 0.5, h), Vector2(w, h))
	var edge := status_col if reach >= 0.0 else UiPalette.PAPER_DIM
	WidgetDraw.panel(self, box, UiPalette.PANEL, UiPalette.INK, maxf(1.5, u * 0.12), u * 0.3, u * 0.12)
	draw_rect(Rect2(box.position + Vector2(u * 0.3, box.size.y - maxf(2.0, u * 0.14) - u * 0.12), Vector2(box.size.x - u * 0.6, maxf(2.0, u * 0.14))), UiPalette.alpha(edge, 0.9))
	# Pointer to the object.
	var tri := PackedVector2Array([pos + Vector2(-u * 0.35, -1), pos + Vector2(u * 0.35, -1), pos + Vector2(0, u * 0.45)])
	draw_colored_polygon(tri, UiPalette.INK)
	var x := box.position.x + u * 0.25
	var cy := box.position.y + h * 0.48
	var icon_id := WidgetDraw.ICON_BREAKABLE if b["kind"] == WidgetMath.KIND_BREAKABLE else WidgetDraw.ICON_CORE
	WidgetDraw.icon(self, icon_id, Vector2(x + icon_w * 0.45, cy), u * 0.95, UiPalette.PAPER)
	x += icon_w
	var fill_col := UiPalette.tape(tape) if tape >= 0 else UiPalette.PAPER
	var filled := 0.0
	if reach >= 0.0:
		filled = minf(reach, WidgetMath.force_pips(need)) if not compact else (1.0 if met else 0.0)
	# Empty slots: the requirement itself (partial last slot shows a fractional threshold).
	WidgetDraw.pips(self, Vector2(x + pips_w * 0.5, cy), shown_slots, filled, pip, fill_col, UiPalette.MUTED)
	x += pips_w + u * 0.45
	WidgetDraw.text(self, mono, Vector2(x, cy + ns * 0.36), num, ns, UiPalette.PAPER)
	x += num_w + u * 0.5
	if status != "":
		WidgetDraw.text(self, display, Vector2(x, cy + ss * 0.36), status, ss, status_col)
	elif status_icon != &"":
		WidgetDraw.icon(self, status_icon, Vector2(x + u * 0.35, cy), u * 0.85, status_col)
	if compact:
		WidgetDraw.text(self, mono, Vector2(box.position.x + icon_w + pip * 1.2, cy + u * 0.25), "×", int(u * 0.5), UiPalette.PAPER_DIM)


func _draw_enemy(b: Dictionary, u: float) -> void:
	var pos: Vector2 = b["pos"]
	var hp: int = b["hp"]
	var max_hp: int = b["max_hp"]
	var pip := u * 0.72
	# One pip per hit point up to MAX_PIPS; a tougher enemy (a 150 hp brute) gets a bar and a number,
	# never a row of pips wider than the screen.
	var bar := max_hp > MAX_PIPS
	var mono := UiPalette.font_mono()
	var ns := int(u * 0.72)
	var num := "%d/%d" % [maxi(0, hp), max_hp]
	var bar_w := u * 4.2
	var w := (bar_w + u * 0.4 + WidgetDraw.text_width(mono, num, ns)) if bar else (max_hp * pip + (max_hp - 1) * pip * 0.3)
	var extra := u * 1.0 if b["shield"] else 0.0
	var box := Rect2(Vector2(pos.x - (w + extra) * 0.5 - u * 0.35, pos.y - u * 1.1), Vector2(w + extra + u * 0.7, u * 1.1))
	WidgetDraw.panel(self, box, UiPalette.alpha(UiPalette.INK, 0.8), UiPalette.INK, 1.5, u * 0.3)
	var cy := box.get_center().y
	if bar:
		var r := Rect2(Vector2(box.position.x + u * 0.35, cy - u * 0.22), Vector2(bar_w, u * 0.44))
		draw_rect(r, UiPalette.MUTED)
		draw_rect(Rect2(r.position, Vector2(bar_w * clampf(float(hp) / float(max_hp), 0.0, 1.0), r.size.y)), UiPalette.THREAT)
		draw_rect(r, UiPalette.INK, false, maxf(1.0, u * 0.08))
		WidgetDraw.text(self, mono, Vector2(r.end.x + u * 0.4, cy + ns * 0.36), num, ns, UiPalette.PAPER)
	else:
		WidgetDraw.pips(self, Vector2(box.position.x + u * 0.35 + w * 0.5, cy), max_hp, float(hp), pip, UiPalette.THREAT, UiPalette.MUTED, pip * 0.3)
	if b["shield"]:
		WidgetDraw.icon(self, WidgetDraw.ICON_SHIELD, Vector2(box.end.x - u * 0.75, cy), u * 0.9, UiPalette.NEON_CYAN)
