class_name RenderCtx
extends RefCounted
## What the world view shares with the layers that draw into its scene (prototype render/layer.ts
## RenderCtx). Built by WorldViewBase.load_level() after the environment exists, then passed to every
## RenderLayerBase.load_level() and update().
##
## Scene convention: 1 tile = 1 unit. Sim (x, y) maps to scene (X = x, Z = y); scene Y is up. The
## floor's top surface is at Y = 0. Use RenderCtx.to_scene() / to_sim() rather than hand-mapping.

## The world view that owns this context.
var view: WorldViewBase = null
var camera: Camera3D = null
var palette: ThemePalette = ThemePalette.new()
var level: LevelDef = null
var loadout: ResolvedLoadout = null
## Node layers add their per-level objects under (freed by the world view on level change).
## Each layer also gets its own child node: it is a Node3D itself.
var root: Node3D = null
## Shared toon material / ramp for actors and fx (null until the shaders exist; layers fall back to
## their own materials).
var toon_material: ShaderMaterial = null
var toon_ramp: Texture2D = null
## QUALITY_LOW / QUALITY_HIGH (WorldViewBase constants).
var quality: StringName = &"high"
## Every music-reactive surface the environment built (owned by the fx layer after load).
var music_reactive: Array[MusicReactive] = []
## Post-processing controls the fx layer may drive.
var post: PostControls = PostControls.new()
## Level extents in scene units (X = sim x, Z = sim y, Y up).
var bounds: AABB = AABB()
## Wall-clock seconds since the world view was created (shared animation clock).
var time: float = 0.0
## Whether the player allows screen shake (SaveSettings.screen_shake); shake() is ignored when off.
var screen_shake_enabled: bool = true
## Accessibility (docs/ACCESSIBILITY.md): reduce flashing (no large-area flashes, capped chromatic
## kicks, calmer pulses) and the screen-shake scale (0 off, 0.4 reduced, 1 full; the world view applies it).
var reduce_flashing: bool = false
var shake_scale: float = 1.0
## True when the world view mounted the music visualisers (musicviz/: wave-screen strips, frieze,
## floor sigils, rune strips, holograms); the fx layer then leaves those structural visuals to them
## and only pulses the world's reactive surfaces, so the two never draw the same thing twice.
var musicviz_mounted: bool = false


## Ask the world view for camera shake (magnitude 0..1). Ignored when the setting is off.
func shake(magnitude: float) -> void:
	if view != null and screen_shake_enabled:
		view.request_shake(magnitude)


## Ask the world view to nudge the camera focus toward a sim-space point with a weight (cinematic framing).
func focus(x: float, y: float, weight: float) -> void:
	if view != null:
		view.request_focus(x, y, weight)


## Height of the top surface at a sim point (wall top, barrier top, 0 on floor); for fx placement.
func surface_height(x: float, y: float) -> float:
	return view.surface_height(x, y) if view != null else 0.0


## Sim point (x, y) at height h -> scene position.
static func to_scene(x: float, y: float, h: float = 0.0) -> Vector3:
	return Vector3(x, h, y)


## Scene position -> sim point.
static func to_sim(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Sim heading (radians, atan2(y, x) in sim axes) -> rotation about scene Y for a node whose rest
## pose faces +Z (the asset contract). Sim +x maps to scene +X, sim +y to scene +Z.
static func heading_to_yaw(dir: float) -> float:
	return PI * 0.5 - dir
