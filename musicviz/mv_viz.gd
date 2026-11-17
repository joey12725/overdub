class_name MVViz
extends Node2D
## Base of every music visualiser drawer: a Node2D that paints into its canvas (normally the
## SubViewport of an MVCanvas) from the shared MVMusic at its current beat. Subclasses override
## _paint(). Visual only — never a collider, never read by gameplay (MUSIC-12, chapter 18).
##
## Retained static layer: a subclass whose drawing has parts that only change now and then (rings,
## the settled sigil figure, rune etching, a full reconstructed curve) returns a key describing
## those parts from _static_key() and draws them in _paint_static(ci). They live on a child canvas
## item drawn behind this one and are re-recorded only when the key changes, so each redraw pays
## only for what moves. Godot keeps a canvas item's draw commands until it is redrawn.

## Shared music model (set by the hub / canvas).
var music: MVMusic = null
var style: MVStyle = MVStyle.dark()
## Canvas size in pixels.
var size: Vector2 = Vector2(512, 256)
## Cassette layer this drawer shows; -1 = all four.
var layer: int = -1
## Fill the canvas with style.screen_bg first (screens); off for decals and holograms.
var backdrop: bool = false
## CPU microseconds the last _draw took (plus a static re-record, if one happened since).
var cost_usec: int = 0
## Running average of cost_usec over recent redraws (what the budget counts).
var avg_cost_usec: float = -1.0

var _static: _StaticLayer = null
var _recorded_key: String = ""
var _static_spent: int = 0


class _StaticLayer:
	extends Node2D
	var viz: MVViz = null

	func _draw() -> void:
		if viz == null or viz.music == null:
			return
		var t0 := Time.get_ticks_usec()
		if viz.backdrop:
			draw_rect(Rect2(Vector2.ZERO, viz.size), viz.style.screen_bg)
		viz._paint_static(self)
		viz._static_spent += Time.get_ticks_usec() - t0


func _ready() -> void:
	_static = _StaticLayer.new()
	_static.viz = self
	_static.show_behind_parent = true
	_static.name = "Static"
	add_child(_static)


func _draw() -> void:
	if music == null:
		return
	var t0 := Time.get_ticks_usec()
	if backdrop and _static == null:
		draw_rect(Rect2(Vector2.ZERO, size), style.screen_bg)
	_paint()
	cost_usec = Time.get_ticks_usec() - t0 + _static_spent
	_static_spent = 0
	avg_cost_usec = float(cost_usec) if avg_cost_usec < 0.0 else lerpf(avg_cost_usec, float(cost_usec), 0.15)


## Re-records the static layer if its key changed and queues this drawer (called by MVCanvas).
func refresh() -> void:
	if music != null and _static != null:
		var k := _static_key()
		if k != _recorded_key:
			_recorded_key = k
			_static.queue_redraw()
	queue_redraw()


## Forces the static layer to re-record on the next refresh.
func invalidate_static() -> void:
	_recorded_key = "#invalid#"


## Draw the moving parts of the visualiser (override).
func _paint() -> void:
	pass


## Key of the static layer's content (override; "" = nothing static besides the backdrop).
func _static_key() -> String:
	return ""


## Draw the static parts on `ci` (override; called only when _static_key() changed).
func _paint_static(_ci: CanvasItem) -> void:
	pass


## Called when the music model changes (override to rebuild caches).
func music_changed() -> void:
	pass


func set_music(m: MVMusic) -> void:
	music = m
	music_changed()
	invalidate_static()
	refresh()


## Layers this drawer shows.
func shown_layers() -> Array[int]:
	var out: Array[int] = []
	if layer >= 0:
		out.append(layer)
	else:
		for i: int in OD.TAPE_COUNT:
			out.append(i)
	return out


## Whether layer `i`'s drawing is in a steady state (no drift, no resync flash, not mid-fade), so
## its colour, width, glow and alpha are constant and its still parts can live on the static layer.
func settled(i: int) -> bool:
	var t := music.tracks[i]
	if not t.present:
		return true
	return t.drift <= 0.0 and t.snap_flash <= 0.0 and (t.dead_mix <= 0.0 or t.dead_mix >= 1.0)


## A short key of layer `i`'s steady drawing state (for _static_key()).
func state_key(i: int) -> String:
	var t := music.tracks[i]
	if not t.present:
		return "-"
	return "%d%d" % [1 if t.dead_mix >= 1.0 else 0, 1 if settled(i) else 0]
