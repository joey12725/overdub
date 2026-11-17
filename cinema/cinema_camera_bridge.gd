class_name CinemaCameraBridge
extends RefCounted
## Pure maths that turns a CinemaFrame into numbers the isometric camera understands (docs/
## CINEMATIC.md "Integration"). It deliberately knows nothing about WorldIsoCamera's internals: the
## world / camera owner calls pose() and copies the result into its own state, so the cinema
## module never reaches into world/.
##
##     var pose := CinemaCameraBridge.pose(cf, cam.aspect(), cam.fit_size())
##     # inside WorldIsoCamera.update(), CINEMATIC branch:
##     #   size = pose.view_size; tx = pose.target.x; tz = pose.target.y; target_yaw = ISO_YAW + pose.yaw_offset
##     #   if pose.snap: view_size = size; target_x = tx; target_z = tz   (a hard cut: no damping)
##
## Span -> view size: a floor disc of diameter `span` tiles seen by an orthographic camera at the
## isometric pitch is `span` wide on screen and `span * sin(pitch)` tall, and a standing figure adds
## about FIGURE_HEIGHT * cos(pitch) above its feet. The band must hold both: view_size =
## max(span * sin(pitch) + FIGURE_HEIGHT * cos(pitch), span / aspect).

## atan(1 / sqrt 2), the isometric pitch (same as WorldIsoCamera.ISO_PITCH).
const ISO_PITCH := 0.6154797086703873
## World units a self stands above the floor (Moxie is ~1.7 units with hair).
const FIGURE_HEIGHT := 1.8
## Never closer than this many units of vertical view (same as WorldIsoCamera.MIN_VIEW_SIZE).
const MIN_VIEW_SIZE := 5.5


## What the camera should do this frame.
class Pose:
	extends RefCounted
	## Floor look-at point, sim axes (scene X = x, Z = y).
	var target: Vector2 = Vector2.ZERO
	## Visible world units from the bottom to the top of the usable band.
	var view_size: float = 16.0
	## Added to the isometric yaw, radians.
	var yaw_offset: float = 0.0
	## True on the first frame of a hard cut: set the camera directly, no damping.
	var snap: bool = false
	## Per split pane (same order as CinemaFrame.panes): the view size that fits that pane's span
	## in the pane's own aspect ratio, and its look-at point.
	var pane_view_sizes: PackedFloat32Array = PackedFloat32Array()
	var pane_targets: PackedVector2Array = PackedVector2Array()


## View size (vertical world units of the band) that shows a floor disc of `span` tiles.
static func view_size(span: float, aspect: float, pitch: float = ISO_PITCH) -> float:
	var a := maxf(0.1, aspect)
	var tall := span * sin(pitch) + FIGURE_HEIGHT * cos(pitch)
	return maxf(MIN_VIEW_SIZE, maxf(tall, span / a))


## The camera pose for a CinemaFrame. `fit_size` is the view size that fits the whole level (the
## camera's own fit_size()); WIDE frames use it, and no frame is wider than 1.05 x fit. A null frame (no plan) is "fit the level, look at `fallback_target`".
## The target is the frame's own (the planner already centres wide shots between the selves and
## the level centre); clamp it to the level with the camera's clamp_target() as usual.
static func pose(cf: CinemaFrame, aspect: float, fit_size: float, fallback_target: Vector2 = Vector2.ZERO) -> Pose:
	var p := Pose.new()
	if cf == null or cf.shot == null:
		p.view_size = fit_size
		p.target = fallback_target
		return p
	var tight := minf(view_size(cf.span, aspect), fit_size * 1.05)
	var w := clampf(cf.wide, 0.0, 1.0)
	p.view_size = lerpf(tight, fit_size, w)
	p.target = cf.target
	p.yaw_offset = cf.yaw_offset
	p.snap = cf.cut
	for pane: CinemaTypes.Pane in cf.panes:
		var pa := aspect * maxf(0.05, pane.rect.size.x) / maxf(0.05, pane.rect.size.y)
		p.pane_view_sizes.append(minf(view_size(pane.span, pa), fit_size * 1.05))
		p.pane_targets.append(pane.focus)
	return p
