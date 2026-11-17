class_name CoachAnchors
extends RefCounted
## Resolves a coach-mark anchor (docs/ONBOARDING.md "Anchors") to a rectangle in a target
## CanvasItem's local coordinates. HUD anchors are found on the HUD; world anchors are positioned
## from the FrameSnapshot / LevelDef (CoachWorld) and projected by a Callable the game supplies.
## Full contract for the HUD and game engineers: docs/DIALOGUE.md "Anchors".
##
## HUD anchors and their group names (subject / active already substituted):
##   deck:<n>          deck_<n>             deck.<part>       deck_<part>  (speed endMode reels status)
##   ruler             ruler                ruler.playhead    ruler_playhead
##   ruler.lane:<n>    ruler_lane_<n>       objective         objective
##   countin           count_in             prompt:<action>   prompt_<action>
## Lookup order, first hit wins:
##   1. hud_root.anchor_rect(anchor: String, subject: Dictionary) -> Rect2   (ONBOARDING.md's hook;
##      `anchor` with subject/active resolved, e.g. "deck:2"; hud_root-local; empty rect = no)
##   2. hud_root.coach_anchor_rect(group_name: StringName) -> Rect2           (hud_root-local)
##   3. the first visible CanvasItem in the group (Control: its rect; Node2D: a small box at it)
##   4. fallbacks on today's HUD node names (DeckA..D + HudDeck.geometry(), Ruler + body_rect(),
##      Objective, CountIn, the enabled click zone of a visible HudPanel for prompt_<action>)
## World anchors: world:self, world:self:<n|subject>, world:spark:<n|subject>,
## world:entity:<id|subject>, world:nearest:<kind>, world:event. The sim point (tiles) goes to
## world_to_screen.call(Vector2(x, y)) which must return a Vector2 in viewport 2D coordinates
## (Camera3D.unproject_position of RenderCtx.to_scene) or null when off screen.

const WORLD_BOX_U := 1.4

var hud_root: Node = null
var world_to_screen: Callable = Callable()
var unit: float = 14.0


class Resolved:
	extends RefCounted
	var ok: bool = false
	var rect: Rect2 = Rect2()
	## "hud" | "world" | "none"
	var kind: String = "none"
	## The HUD group name or world form the anchor resolved to (for tests / debugging).
	var name: String = ""
	## A tape the anchor is about (deck / lane / self anchors), else -1: the label's edge colour.
	var tape: int = -1


## Resolve `anchor` into `space`-local coordinates. `ctx` supplies the live tape and world state;
## `subject` the mark's bound subject (may be null).
func resolve(anchor: String, space: CanvasItem, ctx: CoachContext = null, subject: CoachConditions.Binding = null) -> Resolved:
	var out := Resolved.new()
	if anchor == "" or anchor == "none":
		return out
	var live := ctx.live_tape() if ctx != null else -1
	if anchor.begins_with("world:"):
		return _world(anchor.substr(6), space, ctx, subject, live)
	var group := group_name(anchor, live, subject)
	if group == "":
		return out
	out = _hud(anchor, group, space, subject, live)
	out.name = group
	if group.begins_with("deck_") and group.substr(5).is_valid_int():
		out.tape = group.substr(5).to_int()
	elif group.begins_with("ruler_lane_"):
		out.tape = group.substr(11).to_int()
	elif group.begins_with("deck_") or group.begins_with("ruler"):
		out.tape = live
	return out


## Spec anchor -> HUD group name ("" when it cannot be resolved, e.g. a subject with no tape).
static func group_name(anchor: String, live: int, subject: CoachConditions.Binding) -> String:
	var a := anchor
	if a.contains(":subject"):
		if subject == null or not subject.has or subject.tape < 0:
			return ""
		a = a.replace(":subject", ":%d" % subject.tape)
	if a.contains(":active"):
		a = a.replace(":active", ":%d" % maxi(live, 0))
	if a.begins_with("deck:"):
		return "deck_" + a.substr(5)
	if a.begins_with("deck."):
		return "deck_" + a.substr(5)
	if a == "ruler.playhead":
		return "ruler_playhead"
	if a.begins_with("ruler.lane:"):
		return "ruler_lane_" + a.substr(11)
	if a == "countin":
		return "count_in"
	if a.begins_with("prompt:"):
		return "prompt_" + a.substr(7)
	return a


func _hud(spec: String, group: String, space: CanvasItem, subject: CoachConditions.Binding, live: int) -> Resolved:
	var out := Resolved.new()
	if hud_root == null:
		return out
	var ci := hud_root as CanvasItem
	# 1. ONBOARDING.md hook
	if ci != null and hud_root.has_method("anchor_rect"):
		var resolved_spec := spec.replace(":subject", ":%d" % (subject.tape if subject != null else -1)).replace(":active", ":%d" % maxi(live, 0))
		var r: Variant = hud_root.call("anchor_rect", resolved_spec, _subject_dict(subject))
		if r is Rect2 and (r as Rect2).has_area():
			return _ok(_to_space(ci, r, space))
	# 2. group-name hook
	if ci != null and hud_root.has_method("coach_anchor_rect"):
		var r2: Variant = hud_root.call("coach_anchor_rect", StringName(group))
		if r2 is Rect2 and (r2 as Rect2).has_area():
			return _ok(_to_space(ci, r2, space))
	# 3. groups
	if hud_root.is_inside_tree():
		for n: Node in hud_root.get_tree().get_nodes_in_group(StringName(group)):
			if n is Control and (n as Control).is_visible_in_tree():
				var c := n as Control
				return _ok(_to_space(c, Rect2(Vector2.ZERO, c.size), space))
			if n is Node2D and (n as Node2D).is_visible_in_tree():
				var h := unit
				return _ok(_to_space(n as CanvasItem, Rect2(Vector2(-h, -h), Vector2(h, h) * 2.0), space))
	# 4. fallbacks against the current HUD
	var fb: Variant = _fallback(group, live)
	if fb is Array:
		return _ok(_to_space(fb[0], fb[1], space))
	# 5. node path
	var node := hud_root.get_node_or_null(NodePath(group))
	if node is Control and (node as Control).is_visible_in_tree():
		var c := node as Control
		return _ok(_to_space(c, Rect2(Vector2.ZERO, c.size), space))
	return out


static func _subject_dict(s: CoachConditions.Binding) -> Dictionary:
	if s == null or not s.has:
		return {}
	var d := {"kind": s.kind, "tape": s.tape, "id": s.id}
	if s.has_pos:
		d["x"] = s.pos.x
		d["y"] = s.pos.y
	return d


## [CanvasItem, local Rect2] or null.
func _fallback(group: String, live: int) -> Variant:
	var names := {"ruler": "Ruler", "objective": "Objective", "count_in": "CountIn", "banner": "Banner",
		"setup": "Setup", "decision": "Decision", "briefing": "Briefing"}
	if names.has(group):
		var c := _find_control(str(names[group]))
		if c == null:
			return null
		if group == "ruler" and c.has_method("body_rect"):
			var br: Variant = c.call("body_rect")
			if br is Rect2 and (br as Rect2).has_area():
				return [c, br]
		return [c, Rect2(Vector2.ZERO, c.size)]
	if group.begins_with("deck_"):
		var rest := group.substr(5)
		var idx := rest.to_int() if rest.is_valid_int() else clampi(live, 0, 3)
		if idx < 0 or idx >= OD.TAPE_NAMES.size():
			return null
		var c := _find_control("Deck" + OD.TAPE_NAMES[idx])
		if c == null:
			return null
		if rest == "speed" and c.has_method("geometry"):
			var g: Variant = c.call("geometry")
			if g != null and "speed" in g and (g.speed as Rect2).has_area():
				return [c, g.speed]
		return [c, Rect2(Vector2.ZERO, c.size)]
	if group.begins_with("ruler_"):
		var r := _find_control("Ruler")
		if r == null:
			return null
		var body := Rect2(Vector2.ZERO, r.size)
		if r.has_method("body_rect"):
			var br: Variant = r.call("body_rect")
			if br is Rect2 and (br as Rect2).has_area():
				body = br
		if group.begins_with("ruler_lane_") and "unit" in r and "slim" in r:
			var i := group.substr(11).to_int()
			var g := HudModel.ruler_geometry(body.size.x, body.size.y, float(r.get("unit")), bool(r.get("slim")))
			if i >= 0 and i < g.lane_y.size() and g.lane_h > 0.0:
				return [r, Rect2(body.position + Vector2(g.track_x, g.lane_y[i]), Vector2(g.track_w, g.lane_h))]
		if group == "ruler_playhead" and "view" in r and "unit" in r and "slim" in r:
			var v: Variant = r.get("view")
			var g := HudModel.ruler_geometry(body.size.x, body.size.y, float(r.get("unit")), bool(r.get("slim")))
			if v is SessionView and (v as SessionView).horizon_beats > 0.0:
				var f := clampf((v as SessionView).beat / (v as SessionView).horizon_beats, 0.0, 1.0)
				var x := body.position.x + g.track_x + g.track_w * f
				return [r, Rect2(Vector2(x - 2.0, body.position.y), Vector2(4.0, body.size.y))]
		return [r, body]
	if group.begins_with("prompt_"):
		return _find_zone(hud_root, group.substr(7))
	return null


func _find_control(n: String) -> Control:
	var node := hud_root.find_child(n, true, false)
	if node is Control and (node as Control).is_visible_in_tree():
		return node as Control
	return null


func _find_zone(root: Node, action: String) -> Variant:
	for ch: Node in root.get_children():
		if ch is Control and (ch as Control).is_visible_in_tree() and ch.has_method("zones"):
			var zs: Variant = ch.call("zones")
			if zs is Array:
				for z: Variant in zs:
					if z is Array and (z as Array).size() >= 4 and str(z[1]) == action and z[3] == true:
						return [ch, z[0]]
		var deeper: Variant = _find_zone(ch, action)
		if deeper != null:
			return deeper
	return null


## World anchor forms (after "world:").
func _world(form: String, space: CanvasItem, ctx: CoachContext, subject: CoachConditions.Binding, live: int) -> Resolved:
	var out := Resolved.new()
	out.name = "world:" + form
	if ctx == null or not world_to_screen.is_valid():
		return out
	var p := Vector2.INF
	var tape := -1
	var parts := form.split(":")
	var what := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	if arg == "subject":
		if subject == null or not subject.has:
			return out
	match what:
		"self":
			tape = live if arg == "" else (subject.tape if arg == "subject" else arg.to_int())
			p = CoachWorld.self_pos(ctx, tape)
		"spark":
			tape = subject.tape if arg == "subject" else arg.to_int()
			p = CoachWorld.spark_pos(ctx, tape)
		"entity":
			var id := subject.id if arg == "subject" else form.substr(7)
			p = CoachWorld.entity_pos(ctx, id)
			if p == Vector2.INF and arg == "subject" and subject.has_pos:
				p = subject.pos
		"nearest":
			var a := CoachWorld.self_pos(ctx, live)
			if a != Vector2.INF:
				p = CoachWorld.nearest(ctx, arg, a)
		"event":
			if subject != null and subject.has_pos:
				p = subject.pos
				tape = subject.tape
	if p == Vector2.INF:
		return out
	var sp: Variant = world_to_screen.call(p)
	if not (sp is Vector2):
		return out
	var local: Vector2 = space.get_global_transform_with_canvas().affine_inverse() * (sp as Vector2)
	var h := unit * WORLD_BOX_U
	out.ok = true
	out.kind = "world"
	out.tape = tape
	out.rect = Rect2(local - Vector2(h, h), Vector2(h, h) * 2.0)
	return out


func _ok(r: Rect2) -> Resolved:
	var out := Resolved.new()
	out.ok = true
	out.kind = "hud"
	out.rect = r
	return out


## A rect local to `from` -> local to `space`, through viewport coordinates.
static func _to_space(from: CanvasItem, r: Rect2, space: CanvasItem) -> Rect2:
	var xf := space.get_global_transform_with_canvas().affine_inverse() * from.get_global_transform_with_canvas()
	var a := xf * r.position
	var b := xf * r.end
	return Rect2(a.min(b), (b - a).abs())
