class_name WidgetProjector
extends RefCounted
## Sim point -> screen point for the world-anchored widgets (gauge, badges, off-screen chevrons).
##
## Uses the world's Camera3D (RenderCtx.camera / the world view's camera) with the scene convention
## sim (x, y) -> scene (X = x, Z = y), Y up (RenderCtx.to_scene). The result is in the camera
## viewport's coordinates; `canvas_offset` is added for an overlay whose origin is not the viewport's
## (normally zero: the UI CanvasLayer shares the root viewport). A custom `project_fn`
## (func(sim: Vector2, h: float) -> Vector2) replaces the camera, for tests and screenshots.

var camera: Camera3D = null
var canvas_offset: Vector2 = Vector2.ZERO
var project_fn: Callable = Callable()


static func for_camera(cam: Camera3D) -> WidgetProjector:
	var p := WidgetProjector.new()
	p.camera = cam
	return p


static func for_callable(fn: Callable) -> WidgetProjector:
	var p := WidgetProjector.new()
	p.project_fn = fn
	return p


func valid() -> bool:
	return project_fn.is_valid() or (camera != null and is_instance_valid(camera) and camera.is_inside_tree())


## Screen position of sim point `sim` at height `h` above the floor.
func to_screen(sim: Vector2, h: float = 0.0) -> Vector2:
	if project_fn.is_valid():
		return project_fn.call(sim, h)
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return Vector2(-1e6, -1e6)
	return camera.unproject_position(RenderCtx.to_scene(sim.x, sim.y, h)) + canvas_offset


## True when the point is behind a perspective camera (never for orthographic or custom projections).
func is_behind(sim: Vector2, h: float = 0.0) -> bool:
	if project_fn.is_valid() or camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return false
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return false
	return camera.is_position_behind(RenderCtx.to_scene(sim.x, sim.y, h))


## Screen pixels per world unit near `sim` (for sizing world-anchored stickers).
func px_per_unit(sim: Vector2) -> float:
	var a := to_screen(sim, 0.0)
	var b := to_screen(sim, 1.0)
	return maxf(1.0, a.distance_to(b))
