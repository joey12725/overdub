class_name Facades
extends RefCounted
## Fixed locations of the module implementations, and loaders that instance them (docs/GODOT-PORT.md
## "Module facades"). Each implementer provides exactly the file listed; the game instances it with
## the matching instance_*() call without any other coordination. While a file does not exist yet,
## the loader returns the do-nothing base class so the game still runs.

## Root node's script extends WorldViewBase.
const WORLD_VIEW_SCENE := "res://world/world_view.tscn"
## Script extends ActorLayerBase (instanced by WorldViewBase.attach_layers()).
const ACTOR_LAYER_SCRIPT := "res://actors/actor_layer.gd"
## Script extends FxLayerBase (instanced by WorldViewBase.attach_layers()).
const FX_LAYER_SCRIPT := "res://fx/fx_layer.gd"
## Root node's script extends AudioBase.
const AUDIO_SCENE := "res://audio/audio.tscn"
## Root node's script extends UiBase.
const UI_ROOT_SCENE := "res://ui/ui_root.tscn"
## Root node's script extends HudBase (instanced by UiBase.attach_hud()).
const HUD_SCENE := "res://ui/hud/hud.tscn"


static func instance_world_view() -> WorldViewBase:
	var n := _instance_scene(WORLD_VIEW_SCENE)
	if n is WorldViewBase:
		return n
	_reject(n, WORLD_VIEW_SCENE, "WorldViewBase")
	return WorldViewBase.new()


static func instance_audio() -> AudioBase:
	var n := _instance_scene(AUDIO_SCENE)
	if n is AudioBase:
		return n
	_reject(n, AUDIO_SCENE, "AudioBase")
	return AudioBase.new()


static func instance_ui() -> UiBase:
	var n := _instance_scene(UI_ROOT_SCENE)
	if n is UiBase:
		return n
	_reject(n, UI_ROOT_SCENE, "UiBase")
	return UiBase.new()


static func instance_hud() -> HudBase:
	var n := _instance_scene(HUD_SCENE)
	if n is HudBase:
		return n
	_reject(n, HUD_SCENE, "HudBase")
	return HudBase.new()


static func instance_actor_layer() -> ActorLayerBase:
	var n := _instance_script(ACTOR_LAYER_SCRIPT)
	if n is ActorLayerBase:
		return n
	_reject(n, ACTOR_LAYER_SCRIPT, "ActorLayerBase")
	return ActorLayerBase.new()


static func instance_fx_layer() -> FxLayerBase:
	var n := _instance_script(FX_LAYER_SCRIPT)
	if n is FxLayerBase:
		return n
	_reject(n, FX_LAYER_SCRIPT, "FxLayerBase")
	return FxLayerBase.new()


## True when the implementation file exists (for diagnostics / tests).
static func is_provided(path: String) -> bool:
	return ResourceLoader.exists(path)


static func _instance_scene(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Facades: %s is not a scene" % path)
		return null
	return scene.instantiate()


static func _instance_script(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		push_error("Facades: %s failed to load" % path)
		return null
	var o: Variant = script.new()
	if o is Node:
		return o
	if o is Object and not (o is RefCounted):
		(o as Object).free()
	return null


## A file that exists but has the wrong base class is an error (missing files are expected early on).
static func _reject(n: Node, path: String, base: String) -> void:
	if n != null:
		push_error("Facades: %s must extend %s; using the do-nothing base" % [path, base])
		n.free()
