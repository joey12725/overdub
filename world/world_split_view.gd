class_name WorldSplitView
extends CanvasLayer
## Cinematic split-screen (docs/CINEMATIC.md "Integration" step 8): when a CinemaFrame carries panes,
## each pane is drawn from its own orthographic camera at the isometric angle, sharing the main view's
## World3D, in its screen rect, bordered in the pane colour, opening with `split_t`. Sits below the fx
## overlay (letterbox, layer -5) and the post grade (-1), above the 3D view.
##
## Each pane is a SubViewport that renders the whole scene again, so panes exist only while a split
## shot is on screen (at most CinemaGrammar's four) and are freed when it ends.

const LAYER := -8
const BORDER_PX := 4.0
## Gap between panes in pixels (the main view shows through as a thin dark seam).
const GAP_PX := 6.0


class Pane:
	extends RefCounted
	var vp: SubViewport
	var cam: Camera3D
	var rig: WorldIsoCamera
	var frame: ColorRect
	var view: TextureRect


var _panes: Array[Pane] = []
var _root: Control = null
## Panes drawn last frame (diagnostics / tests / tools).
var shown: int = 0


func _init() -> void:
	name = "SplitView"
	layer = LAYER
	_root = Control.new()
	_root.name = "Panes"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	visible = false


## Show the panes of `cf` (or hide them when it has none). `main` is the main view's camera rig
## (bounds, yaw, viewport); `pose` carries the per-pane view sizes and targets.
func sync(cf: CinemaFrame, pose: CinemaCameraBridge.Pose, main: WorldIsoCamera, world: World3D, msaa: Viewport.MSAA) -> void:
	var n := cf.panes.size() if cf != null and cf.split_t > 0.01 else 0
	if n == 0:
		if visible:
			clear()
		return
	visible = true
	while _panes.size() < n:
		_panes.append(_make_pane(world, msaa))
	while _panes.size() > n:
		_free_pane(_panes.pop_back())
	var vp_size := Vector2(main.vp_w, main.vp_h)
	var band_h := main.usable_height()
	var t := clampf(cf.split_t, 0.0, 1.0)
	var ease := t * t * (3.0 - 2.0 * t)
	for i: int in n:
		var pane := cf.panes[i]
		var p := _panes[i]
		# Pane rect in pixels within the usable band (above the HUD), opening from its centre.
		var r := Rect2(pane.rect.position * Vector2(vp_size.x, band_h), pane.rect.size * Vector2(vp_size.x, band_h))
		r = r.grow(-GAP_PX * 0.5)
		var full := r
		r.size *= Vector2(1.0, lerpf(0.15, 1.0, ease))
		r.position = full.get_center() - r.size * 0.5
		p.frame.position = r.position - Vector2(BORDER_PX, BORDER_PX)
		p.frame.size = r.size + Vector2(BORDER_PX, BORDER_PX) * 2.0
		p.frame.color = Color(pane.color.r, pane.color.g, pane.color.b, ease)
		p.view.position = r.position
		p.view.size = r.size
		p.view.modulate = Color(1, 1, 1, ease)
		var px := Vector2i(maxi(16, int(full.size.x)), maxi(16, int(full.size.y)))
		if p.vp.size != px:
			p.vp.size = px
		var rig := p.rig
		rig.b_min_x = main.b_min_x
		rig.b_max_x = main.b_max_x
		rig.b_min_z = main.b_min_z
		rig.b_max_z = main.b_max_z
		rig.b_min_y = main.b_min_y
		rig.b_max_y = main.b_max_y
		rig.set_viewport(px.x, px.y)
		rig.set_bottom_inset(0.0)
		rig.yaw = main.yaw
		rig.pitch = main.pitch
		var size := pose.pane_view_sizes[i] if i < pose.pane_view_sizes.size() else main.view_size
		var target := pose.pane_targets[i] if i < pose.pane_targets.size() else pane.focus
		rig.view_size = size
		var c := rig.clamp_target(target.x, target.y, size, 1.5)
		rig.target_x = c.x
		rig.target_z = c.y
		rig.apply_to(p.cam)
	shown = n


func clear() -> void:
	for p: Pane in _panes:
		_free_pane(p)
	_panes.clear()
	visible = false
	shown = 0


func _make_pane(world: World3D, msaa: Viewport.MSAA) -> Pane:
	var p := Pane.new()
	p.vp = SubViewport.new()
	p.vp.name = "PaneViewport"
	p.vp.world_3d = world
	p.vp.msaa_3d = msaa
	p.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	p.vp.size = Vector2i(320, 180)
	p.cam = Camera3D.new()
	p.cam.name = "PaneCamera"
	p.vp.add_child(p.cam)
	p.cam.current = true
	add_child(p.vp)
	p.rig = WorldIsoCamera.new()
	p.frame = ColorRect.new()
	p.frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(p.frame)
	p.view = TextureRect.new()
	p.view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.view.stretch_mode = TextureRect.STRETCH_SCALE
	p.view.texture = p.vp.get_texture()
	_root.add_child(p.view)
	return p


func _free_pane(p: Pane) -> void:
	for n: Node in [p.view, p.frame, p.vp]:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
