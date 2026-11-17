class_name WorldViewBase
extends Node3D
## The 3D world facade (contracts.ts IRenderer). Implemented by the root script of
## res://world/world_view.tscn (`extends WorldViewBase`); the game instances that scene through
## Facades.instance_world_view() and adds it to the tree.
##
## Responsibilities of the implementer: build the level from the kit, own the camera, lighting and
## WorldEnvironment, and drive the two layers. This base already does the layer plumbing: call
## attach_layers() once (e.g. in _ready), _load_layers(ctx) at the end of load_level(), and
## _update_layers(frame) inside render(); override the virtuals below.
##
## Sim (x, y) maps to scene (X = x, Z = y), Y up, 1 tile = 1 unit (see RenderCtx).

const QUALITY_LOW: StringName = &"low"
const QUALITY_HIGH: StringName = &"high"

## Emitted after a level finished building (environment and layers).
signal level_loaded(level: LevelDef)

## Context shared with the layers; rebuilt by load_level().
var ctx: RenderCtx = null
var actor_layer: ActorLayerBase = null
var fx_layer: FxLayerBase = null
var quality: StringName = QUALITY_HIGH
var screen_shake_enabled: bool = true


# ───────────────────────────── facade (override) ─────────────────────────────

## Build the scene for a level (tiles, props, lighting by theme). Disposes the previous level.
## Implementers build the environment, fill `ctx` (new_ctx() gives one with the common fields set),
## then call _load_layers(ctx) and emit level_loaded.
func load_level(_level: LevelDef, _loadout: ResolvedLoadout) -> void:
	pass


## Draw one frame. Implementers move the camera and update the environment, then call
## _update_layers(frame).
func render(_frame: RenderFrame) -> void:
	pass


## World-space direction (unit vector, sim axes) that screen-up maps to; lets the input layer turn
## WASD / stick into camera-relative movement.
func screen_up_in_world() -> Vector2:
	return Vector2(0.0, -1.0)


## Convert a viewport position (pixels) to a point on the floor plane, in sim axes.
func screen_to_world(_screen_pos: Vector2) -> Vector2:
	return Vector2.ZERO


## QUALITY_LOW / QUALITY_HIGH.
func set_quality(q: StringName) -> void:
	quality = q
	if ctx != null:
		ctx.quality = q


## Honour SaveSettings.screen_shake; RenderCtx.shake() requests are ignored when off.
func set_screen_shake(enabled: bool) -> void:
	screen_shake_enabled = enabled
	if ctx != null:
		ctx.screen_shake_enabled = enabled


## Tear down the current level (layers first). Override to free the environment too; call super.
func dispose() -> void:
	if actor_layer != null:
		actor_layer.dispose()
	if fx_layer != null:
		fx_layer.dispose()


# ───────────────────────────── hooks the layers call (via RenderCtx) ─────────────────────────────

## Camera shake request, magnitude 0..1 (already filtered by the screen-shake setting).
func request_shake(_magnitude: float) -> void:
	pass


## Nudge the camera focus toward a sim-space point with a weight (cinematic framing).
func request_focus(_x: float, _y: float, _weight: float) -> void:
	pass


## Height of the top surface at a sim point (wall top, barrier top, 0 on floor).
func surface_height(_x: float, _y: float) -> float:
	return 0.0


# ───────────────────────────── layer plumbing (provided) ─────────────────────────────

## Instance the actor and fx layers from their fixed script paths and add them as children. A layer
## whose script does not exist yet is replaced by a do-nothing base layer. Safe to call twice.
func attach_layers() -> void:
	if actor_layer == null:
		actor_layer = Facades.instance_actor_layer()
		actor_layer.name = "ActorLayer"
		add_child(actor_layer)
	if fx_layer == null:
		fx_layer = Facades.instance_fx_layer()
		fx_layer.name = "FxLayer"
		add_child(fx_layer)


## A RenderCtx with view, level, loadout, quality, shake setting and a fresh `root` (a child Node3D
## named "LevelRoot", replacing the previous one) filled in. Implementers set camera, palette,
## bounds, music_reactive, toon material/ramp and post before passing it on.
func new_ctx(level: LevelDef, loadout: ResolvedLoadout) -> RenderCtx:
	var old := get_node_or_null(^"LevelRoot")
	if old != null:
		remove_child(old)
		old.queue_free()
	var root := Node3D.new()
	root.name = "LevelRoot"
	add_child(root)
	var c := RenderCtx.new()
	c.view = self
	c.level = level
	c.loadout = loadout
	c.root = root
	c.quality = quality
	c.screen_shake_enabled = screen_shake_enabled
	return c


## Store ctx and run load_level on both layers (actors first, then fx).
func _load_layers(c: RenderCtx) -> void:
	ctx = c
	attach_layers()
	actor_layer.load_level(c)
	fx_layer.load_level(c)


## Run update on both layers (actors first, then fx).
func _update_layers(frame: RenderFrame) -> void:
	if ctx == null:
		return
	if actor_layer != null:
		actor_layer.update(frame, ctx)
	if fx_layer != null:
		fx_layer.update(frame, ctx)
