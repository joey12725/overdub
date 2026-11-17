class_name WorldIsoCamera
extends RefCounted
## Isometric orthographic camera and its framing logic (port of prototype render/camera.ts).
##
## ART-01: the presentation is isometric. The camera looks down at the true isometric pitch
## (atan(1/sqrt 2) ~ 35.26 deg) from yaw 45 deg, i.e. it sits on the +X / +Z side of what it frames,
## so map row 0 is at the back and tile (0, 0) is the top corner of the diamond.
##
## Framing (chapter 16 leaves "show whole level vs follow" open): record mode shows the whole level
## when it fits at a readable tile size (pushed in a little on the live self, RECORD_PUSH_IN, moving
## only as far as it takes to keep her in the middle of the view) and otherwise follows the active
## self inside soft bounds.
## Review frames the action, cinematic drifts and pushes in on focus requests (CINE-03) and widens
## for the whole room every 16 beats, idle sways a few degrees behind menus.
##
## HUD inset: the bottom `bottom_inset` viewport pixels belong to the HUD. All framing happens in
## the usable band above it (the level is fitted and centred there); the projection maths below
## accounts for the shift exactly.
##
## Pure maths: apply_to(camera) copies the result onto a Camera3D. Viewport coordinates are the
## root viewport's visible-rect coordinates (the same space as InputEventMouse.position).

const ISO_YAW := PI / 4.0
## atan(1 / sqrt(2)).
const ISO_PITCH := 0.6154797086703873
## Distance from the look-at point; any value works for an orthographic camera as long as near/far
## bracket the level.
const CAMERA_DISTANCE := 120.0
const NEAR := 1.0
const FAR := CAMERA_DISTANCE * 2.5
## Smallest on-screen size of one world unit (viewport px) in record mode before we switch to following.
const MIN_PX_PER_UNIT := 42.0
## Never zoom closer than this many world units of vertical view.
const MIN_VIEW_SIZE := 5.5
## Share of the whole-level view size used while setting up and recording (smaller = closer).
const RECORD_PUSH_IN := 0.74

var yaw: float = ISO_YAW
var pitch: float = ISO_PITCH
## Visible world units from the bottom to the top of the usable band (viewport minus HUD inset).
var view_size: float = 16.0
## Look-at point on the floor plane (scene X, Z); appears at the centre of the usable band.
var target_x: float = 0.0
var target_z: float = 0.0

var vp_w: float = 1600.0
var vp_h: float = 900.0
## Viewport pixels at the bottom reserved for the HUD.
var bottom_inset: float = 0.0

## Level bounds (scene units).
var b_min_x: float = 0.0
var b_min_z: float = 0.0
var b_max_x: float = 1.0
var b_max_z: float = 1.0
var b_max_y: float = 0.0
var b_min_y: float = 0.0

var trauma: float = 0.0
var shake_x: float = 0.0
var shake_y: float = 0.0

var _focus_sum_x: float = 0.0
var _focus_sum_y: float = 0.0
var _focus_sum_w: float = 0.0
var focus_x: float = 0.0
var focus_y: float = 0.0
var focus_w: float = 0.0
var push_in: float = 0.0

# Basis, refreshed by _basis().
var _right := Vector3.RIGHT
var _up := Vector3.UP
var _fwd := Vector3.FORWARD
# Screen-basis extents of the level box, refreshed by _extents().
var _e_min_r: float = 0.0
var _e_max_r: float = 0.0
var _e_min_u: float = 0.0
var _e_max_u: float = 0.0


## Inputs to update(); the world view fills one per frame (scratch, reused).
class Framing:
	extends RefCounted
	var mode: StringName = ViewMode.IDLE
	## Wall-clock seconds since last update.
	var dt: float = 0.0
	## Accumulated wall-clock seconds (drives drift / sway).
	var time: float = 0.0
	## Master beat (cinematic wide-shot rhythm).
	var beat: float = 0.0
	## Position of the self under live control (sim axes), valid when has_follow.
	var follow := Vector2.ZERO
	var has_follow: bool = false
	## Centre of the selves that matter right now (alive ones), valid when has_crowd.
	var crowd := Vector2.ZERO
	var has_crowd: bool = false
	## Cinematic director output (CINEMATIC mode only; docs/CINEMATIC.md). When set, it drives the
	## framing (target, zoom, yaw, hard cuts) and layers' focus requests are ignored.
	var cinema: CinemaFrame = null


static func _damp(from: float, to: float, rate: float, dt: float) -> float:
	return to + (from - to) * exp(-rate * dt)


## Wrap an angle difference into (-PI, PI].
static func _angle_delta(a: float, b: float) -> float:
	var d := fmod(b - a, TAU)
	if d > PI:
		d -= TAU
	if d <= -PI:
		d += TAU
	return d


func _init() -> void:
	_basis()


# ───────────────────────────── configuration ─────────────────────────────

## Viewport size in viewport pixels.
func set_viewport(w: float, h: float) -> void:
	vp_w = maxf(1.0, w)
	vp_h = maxf(1.0, h)


## Pixels at the bottom of the viewport covered by the HUD (clamped to 60% of the height).
func set_bottom_inset(px: float) -> void:
	bottom_inset = clampf(px, 0.0, vp_h * 0.6)


## Height of the usable band above the HUD, in viewport pixels.
func usable_height() -> float:
	return maxf(1.0, vp_h - clampf(bottom_inset, 0.0, vp_h * 0.6))


## Aspect ratio of the usable band.
func aspect() -> float:
	return vp_w / usable_height()


## Level bounds in scene units (an AABB; X = sim x, Z = sim y).
func set_bounds(b: AABB) -> void:
	b_min_x = b.position.x
	b_min_y = b.position.y
	b_min_z = b.position.z
	b_max_x = b.end.x
	b_max_y = b.end.y
	b_max_z = b.end.z


## Called on level load: centre on the level and start zoomed out so the first frames ease in to
## the fitted framing.
func introduce() -> void:
	yaw = ISO_YAW
	pitch = ISO_PITCH
	var fit := fit_size()
	var c := level_centre()
	target_x = c.x
	target_z = c.y
	view_size = fit * 1.55
	trauma = 0.0
	shake_x = 0.0
	shake_y = 0.0
	focus_w = 0.0
	push_in = 0.0
	_focus_sum_w = 0.0
	_focus_sum_x = 0.0
	_focus_sum_y = 0.0


## Jump straight to the framing update() is heading for (no easing); used by tools and tests.
func settle(f: Framing) -> void:
	var g := Framing.new()
	g.mode = f.mode
	g.time = f.time
	g.beat = f.beat
	g.follow = f.follow
	g.has_follow = f.has_follow
	g.crowd = f.crowd
	g.has_crowd = f.has_crowd
	g.dt = 0.1
	for i: int in range(200):
		update(g)
	trauma = 0.0
	shake_x = 0.0
	shake_y = 0.0


## Camera shake request, magnitude 0..1 (trauma model: shake grows with trauma squared).
func add_trauma(magnitude: float) -> void:
	if not (magnitude > 0.0):
		return
	trauma = minf(1.0, trauma + magnitude)


## Weighted focus request for this frame (sim axes). Consumed by the next update().
func request_focus(x: float, y: float, weight: float) -> void:
	if not (weight > 0.0) or not is_finite(x) or not is_finite(y):
		return
	_focus_sum_x += x * weight
	_focus_sum_y += y * weight
	_focus_sum_w += weight


# ───────────────────────────── basis helpers ─────────────────────────────

func _basis() -> void:
	var cp := cos(pitch)
	var sp := sin(pitch)
	_fwd = Vector3(-sin(yaw) * cp, -sp, -cos(yaw) * cp)
	_right = Vector3(cos(yaw), 0.0, -sin(yaw))
	_up = _right.cross(_fwd).normalized()


## Camera right / up / forward (unit, world space) for the current yaw and pitch.
func right_vector() -> Vector3:
	_basis()
	return _right


func up_vector() -> Vector3:
	_basis()
	return _up


func forward_vector() -> Vector3:
	_basis()
	return _fwd


func _extents() -> void:
	_basis()
	var mn_r := INF
	var mx_r := -INF
	var mn_u := INF
	var mx_u := -INF
	for i: int in range(8):
		var x := b_max_x if (i & 1) != 0 else b_min_x
		# The deep cliff fades into the background; frame its upper half.
		var y := b_max_y if (i & 2) != 0 else b_min_y * 0.35
		var z := b_max_z if (i & 4) != 0 else b_min_z
		var p := Vector3(x, y, z)
		var rr := p.dot(_right)
		var uu := p.dot(_up)
		mn_r = minf(mn_r, rr)
		mx_r = maxf(mx_r, rr)
		mn_u = minf(mn_u, uu)
		mx_u = maxf(mx_u, uu)
	_e_min_r = mn_r
	_e_max_r = mx_r
	_e_min_u = mn_u
	_e_max_u = mx_u


## Usable-band view size that fits the whole level with a margin.
func fit_size(margin: float = 1.05) -> float:
	_extents()
	var w := _e_max_r - _e_min_r
	var h := _e_max_u - _e_min_u
	return maxf(MIN_VIEW_SIZE, maxf(h, w / aspect()) * margin)


## View size at which one world unit is MIN_PX_PER_UNIT viewport pixels tall.
func readable_size() -> float:
	return maxf(MIN_VIEW_SIZE, usable_height() / MIN_PX_PER_UNIT)


## Floor point (scene X, Z as x, y) whose projection is at screen-basis coordinates (r, u).
func _floor_point_for(r: float, u: float) -> Vector2:
	var a := _right.x
	var b := _right.z
	var c := _up.x
	var d := _up.z
	var det := a * d - b * c
	if absf(det) < 1e-9:
		return Vector2(target_x, target_z)
	return Vector2((r * d - b * u) / det, (a * u - c * r) / det)


## Floor point that centres the level's projected bounding box on screen.
func level_centre() -> Vector2:
	_extents()
	return _floor_point_for((_e_min_r + _e_max_r) * 0.5, (_e_min_u + _e_max_u) * 0.5)


## Clamp a desired look-at point so the view stays inside the level's projected extents plus a
## soft margin; on an axis where the view is wider than the level, centre that axis.
func clamp_target(x: float, z: float, size: float, margin: float) -> Vector2:
	_extents()
	var half_h := size * 0.5
	var half_w := size * aspect() * 0.5
	var r := x * _right.x + z * _right.z
	var u := x * _up.x + z * _up.z
	var lo_r := _e_min_r + half_w - margin
	var hi_r := _e_max_r - half_w + margin
	var lo_u := _e_min_u + half_h - margin
	var hi_u := _e_max_u - half_h + margin
	r = (_e_min_r + _e_max_r) * 0.5 if lo_r > hi_r else clampf(r, lo_r, hi_r)
	u = (_e_min_u + _e_max_u) * 0.5 if lo_u > hi_u else clampf(u, lo_u, hi_u)
	return _floor_point_for(r, u)


## Look-at point nearest (cx, cz) that keeps the subject (sx, sz) inside the middle of a view of
## `size`: within KEEP_SIDE of the half-width, KEEP_DOWN of the half-height below the centre and
## KEEP_UP above it (less room at the top, where the HUD's banners sit).
const KEEP_SIDE := 0.55
const KEEP_DOWN := 0.5
const KEEP_UP := 0.3


func _keep_in_view(sx: float, sz: float, cx: float, cz: float, size: float) -> Vector2:
	_basis()
	var half_w := size * aspect() * 0.5
	var half_h := size * 0.5
	var cr := cx * _right.x + cz * _right.z
	var cu := cx * _up.x + cz * _up.z
	var dr := (sx * _right.x + sz * _right.z) - cr
	var du := (sx * _up.x + sz * _up.z) - cu
	var r := cr + dr - clampf(dr, -half_w * KEEP_SIDE, half_w * KEEP_SIDE)
	var u := cu + du - clampf(du, -half_h * KEEP_DOWN, half_h * KEEP_UP)
	return _floor_point_for(r, u)


# ───────────────────────────── per-frame framing ─────────────────────────────

func update(f: Framing) -> void:
	var dt := clampf(f.dt, 0.0, 0.1)
	var t := f.time

	# Focus requests from layers this frame.
	if _focus_sum_w > 0.0:
		var fx := _focus_sum_x / _focus_sum_w
		var fy := _focus_sum_y / _focus_sum_w
		if focus_w < 0.02:
			focus_x = fx
			focus_y = fy
		else:
			focus_x = _damp(focus_x, fx, 4.0, dt)
			focus_y = _damp(focus_y, fy, 4.0, dt)
	focus_w = _damp(focus_w, minf(1.0, _focus_sum_w), 6.0 if _focus_sum_w > focus_w else 0.9, dt)
	_focus_sum_x = 0.0
	_focus_sum_y = 0.0
	_focus_sum_w = 0.0

	var directed := f.mode == ViewMode.CINEMATIC and f.cinema != null and f.cinema.shot != null
	if directed:
		_update_directed(f, dt)
	else:
		_update_framing(f, dt, t)

	# Shake: trauma^2 keeps small hits subtle and big hits punchy; smooth pseudo-noise.
	trauma = maxf(0.0, trauma - dt * 1.7)
	var amp := trauma * trauma * 0.045 * view_size
	shake_x = amp * (sin(t * 47.3) * 0.6 + sin(t * 89.1 + 1.7) * 0.4)
	shake_y = amp * (sin(t * 53.9 + 0.6) * 0.6 + sin(t * 77.7 + 2.9) * 0.4)


## CINEMATIC with a director plan (docs/CINEMATIC.md "Integration" step 4): the director's pose sets
## the zoom, look-at point and yaw; a hard cut (on the beat) snaps with no damping, and within a shot
## the camera follows quickly because the director already eases.
func _update_directed(f: Framing, dt: float) -> void:
	var pose := CinemaCameraBridge.pose(f.cinema, aspect(), fit_size())
	var size := maxf(MIN_VIEW_SIZE, pose.view_size)
	var target_yaw := ISO_YAW + pose.yaw_offset
	if pose.snap:
		yaw = target_yaw
		view_size = size
		var p0 := clamp_target(pose.target.x, pose.target.y, size, 1.5)
		target_x = p0.x
		target_z = p0.y
		push_in = 0.0
		return
	yaw += _angle_delta(yaw, target_yaw) * (1.0 - exp(-6.0 * dt))
	view_size = _damp(view_size, size, 6.0, dt)
	# Clamp with the size actually shown this frame, so the target never pushes the view off the level.
	var p := clamp_target(pose.target.x, pose.target.y, view_size, 1.5)
	target_x = _damp(target_x, p.x, 6.0, dt)
	target_z = _damp(target_z, p.y, 6.0, dt)


func _update_framing(f: Framing, dt: float, t: float) -> void:
	var target_yaw := ISO_YAW
	if f.mode == ViewMode.IDLE:
		target_yaw = ISO_YAW + deg_to_rad(5.0) * sin(t * 0.12)
	elif f.mode == ViewMode.CINEMATIC:
		target_yaw = ISO_YAW + deg_to_rad(3.5) * sin(t * 0.09)
	yaw += _angle_delta(yaw, target_yaw) * (1.0 - exp(-2.2 * dt))

	var fit := fit_size()
	var readable := readable_size()
	var centre := level_centre()
	var cx := centre.x
	var cz := centre.y
	var size: float
	var tx := cx
	var tz := cz
	var size_rate := 2.4
	var move_rate := 3.2

	if f.mode == ViewMode.RECORD or f.mode == ViewMode.REVIEW:
		var has_subject := f.has_follow or f.has_crowd
		var subj := f.follow if f.has_follow else (f.crowd if f.has_crowd else Vector2(cx, cz))
		var sx := subj.x
		var sy := subj.y
		if f.mode == ViewMode.REVIEW and focus_w > 0.05:
			# Review frames the action, so layers' focus requests pull the view a little.
			var k := minf(0.6, focus_w * 0.6)
			sx += (focus_x - sx) * k
			sy += (focus_y - sy) * k
			has_subject = true
		if fit <= readable:
			# Whole level fits at a readable size: hold it still and centred (readability first).
			size = fit
			if f.mode == ViewMode.RECORD and f.has_follow:
				# While setting up and recording, push in on the live Moxie so she reads as a character
				# rather than a marker. The view leaves the level centre only as far as it takes to keep
				# her inside its middle (so as much of the room as possible stays in view and the camera
				# rests while she works in the middle of it); review returns to the fit.
				size = maxf(MIN_VIEW_SIZE, fit * RECORD_PUSH_IN)
				var pr := _keep_in_view(sx, sy, cx, cz, size)
				pr = clamp_target(pr.x, pr.y, size, size * 0.12)
				tx = pr.x
				tz = pr.y
				move_rate = 2.6
		else:
			size = readable
			if has_subject:
				var p := clamp_target(sx, sy, size, 1.0)
				tx = p.x
				tz = p.y
			move_rate = 2.6
	elif f.mode == ViewMode.CINEMATIC:
		var base := minf(fit, readable * 1.35)
		# Every 16 beats, widen for the whole-room picture for three beats so the causal chain stays
		# legible (CINE-03 spectacle must not hide how the solution works).
		var cycle := fposmod(f.beat, 16.0)
		var wide := cycle >= 13.0
		var want_push := 0.0 if wide else minf(1.0, focus_w) * 0.85
		push_in = _damp(push_in, want_push, 1.6 if want_push > push_in else 0.8, dt)
		size = maxf(MIN_VIEW_SIZE, base * (1.0 - 0.4 * push_in))
		var sx := cx
		var sy := cz
		if focus_w > 0.02:
			sx = focus_x
			sy = focus_y
		elif f.has_crowd:
			sx = f.crowd.x
			sy = f.crowd.y
		var k := 0.25 + 0.65 * push_in if base >= fit * 0.999 else 0.85
		var drift_r := sin(t * 0.13) * 0.06 * size
		var drift_u := cos(t * 0.11) * 0.035 * size
		var px := cx + (sx - cx) * k + _right.x * drift_r + _up.x * drift_u
		var pz := cz + (sy - cz) * k + _right.z * drift_r + _up.z * drift_u
		var p := clamp_target(px, pz, size, 1.5)
		tx = p.x
		tz = p.y
		size_rate = 1.4
		move_rate = 1.6
	else:
		size = fit * 1.08
		size_rate = 1.2
		move_rate = 1.2

	view_size = _damp(view_size, size, size_rate, dt)
	target_x = _damp(target_x, tx, move_rate, dt)
	target_z = _damp(target_z, tz, move_rate, dt)


# ───────────────────────────── camera transform and projections ─────────────────────────────

## World units per viewport pixel at the current zoom.
func world_per_pixel() -> float:
	return view_size / usable_height()


## Vertical size of the whole viewport in world units (Camera3D.size with KEEP_HEIGHT).
func camera_size() -> float:
	return world_per_pixel() * vp_h


## Point on the camera's view axis (its "eye" for an orthographic projection), including shake and
## the HUD-inset shift.
func eye() -> Vector3:
	_basis()
	var wpp := world_per_pixel()
	# The target shows at the centre of the usable band, inset/2 px above the viewport centre, so the
	# view axis passes inset/2 px below the target.
	var inset_shift := clampf(bottom_inset, 0.0, vp_h * 0.6) * 0.5 * wpp
	var t := Vector3(target_x, 0.0, target_z) + _right * shake_x + _up * (shake_y - inset_shift)
	return t - _fwd * CAMERA_DISTANCE


## Camera3D global transform (looks along -Z local = _fwd).
func transform() -> Transform3D:
	_basis()
	return Transform3D(Basis(_right, _up, -_fwd), eye())


## Copy transform and projection onto a Camera3D (orthographic, keep height).
func apply_to(cam: Camera3D) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = camera_size()
	cam.near = NEAR
	cam.far = FAR
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	if cam.is_inside_tree():
		cam.global_transform = transform()
	else:
		cam.transform = transform()


## Sim-axes unit direction that "up on screen" maps to on the floor: the camera's up vector
## projected onto the floor plane.
func screen_up_in_world() -> Vector2:
	_basis()
	var v := Vector2(_up.x, _up.z)
	if v.length() < 1e-9:
		return Vector2(0.0, -1.0)
	return v.normalized()


## Viewport position (pixels) -> point on the floor plane (Y = 0), sim axes.
func screen_to_world(p: Vector2) -> Vector2:
	_basis()
	var wpp := world_per_pixel()
	var origin := eye() + _right * ((p.x - vp_w * 0.5) * wpp) + _up * ((vp_h * 0.5 - p.y) * wpp)
	if absf(_fwd.y) < 1e-9:
		return Vector2(origin.x, origin.z)
	var k := -origin.y / _fwd.y
	return Vector2(origin.x + _fwd.x * k, origin.z + _fwd.z * k)


## Scene point -> viewport position (pixels).
func world_to_screen(p: Vector3) -> Vector2:
	_basis()
	var wpp := world_per_pixel()
	var d := p - eye()
	return Vector2(vp_w * 0.5 + d.dot(_right) / wpp, vp_h * 0.5 - d.dot(_up) / wpp)
