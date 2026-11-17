class_name MusicVizHub
extends Node
## The music you can see (MUSIC-12, chapter 15 "Visualizations", chapter 18 "Musical architecture").
## One per loaded level. Owns the shared music model (MVMusic: the level's four cassette layers
## evaluated with the Harmonograph port), the visualiser canvases (created on demand, shared by every
## mount that asks for the same kind) and their reduced-rate, round-robin redraw. Decoration only:
## nothing here collides or feeds back into gameplay.
##
##   var hub := MusicVizHub.new(); parent.add_child(hub)
##   hub.load_level(level)                                   # once per level
##   hub.use_audio_director(audio.director())                # notes = the audio's notes
##   hub.set_tracks(tracks)                                  # wherever audio.set_tracks is called
##   hub.update_from_frame(frame)                            # every rendered frame
##   hub.mount_screen(wave_screen_model)                     # any time after load
##   hub.mount_frieze(root, a, b, 0.55, 0.42, facing)
##   hub.mount_signature(root, centre, 1.4, 0.6)
##   hub.mount_hologram(root, base, layer)
##   (or hub.update(master_beat, tracks, dt) without set_tracks)
##
## See docs/MUSICVIZ.md.

const KIND_STACK_SCREEN: StringName = &"stack_screen"
const KIND_FRIEZE: StringName = &"frieze"
const KIND_EPICYCLE: StringName = &"epicycle"
const KIND_EPICYCLE_WAVE: StringName = &"epicycle_wave"
const KIND_SIGILS: StringName = &"sigils"
const KIND_SIGIL: StringName = &"sigil"
const KIND_CONSTELLATION: StringName = &"constellation"
const KIND_RUNES: StringName = &"runes"
const KIND_RUNE_ROW: StringName = &"rune_row"

## Redraw rates (per second) per kind at high quality; low quality halves them.
const RATES: Dictionary = {
	&"stack_screen": 20.0, &"frieze": 16.0, &"epicycle": 20.0, &"epicycle_wave": 20.0,
	&"sigils": 12.0, &"sigil": 12.0, &"constellation": 12.0, &"runes": 15.0, &"rune_row": 15.0,
}
## Rune glyph sheet picked up automatically when present (white glyphs on transparent, a grid of
## GLYPH_SHEET_GRID cells, read left to right, top to bottom). Procedural runes otherwise.
const GLYPH_SHEET_PATH := "res://assets/textures/decals/rune_glyphs.png"
const GLYPH_SHEET_GRID := Vector2i(8, 4)
const GLYPH_ATLAS_PATH := "res://assets/textures/decals/runes/rune_glyphs_atlas.png"
const GLYPH_ATLAS_GRID := Vector2i(8, 5)
## How far ahead (master beats) note prefetching runs (beyond every drawer's look-ahead).
const PREFETCH_BEATS := 8.0

## The shared music model (null before load_level).
var music: MVMusic = null
var style: MVStyle = MVStyle.dark()
## At most this many canvases redraw in one frame (spreads the cost).
var max_redraws_per_frame: int = 2
var low_quality: bool = false
## Optional rune glyph sheet for the rune sequencers (see MVRuneSequencer).
var glyph_sheet: Texture2D = null
var glyph_grid: Vector2i = Vector2i(8, 4)
## CPU microseconds of the last update() (model + scheduling, excluding the deferred _draw calls).
var last_update_usec: int = 0
## Current overall strength of the mounted visualisers (set_intensity).
var intensity: float = 1.0

var _canvases: Dictionary = {}
## Mounted materials: [ShaderMaterial, energy, is_hologram] (re-themed on level load).
var _mounted: Array = []
var _sheet_checked: bool = false
var _tracks: Array = []
var _director: Object = null
var _order: Array[String] = []
var _rr: int = 0


## Loads a level's music (LevelDef.music, bpm, horizon) and theme. Existing canvases are kept and
## re-pointed at the new model.
func load_level(level: LevelDef) -> void:
	load_music(level.music, level.bpm, level.horizon_bars, level.theme)


func load_music(def: LevelMusicDef, bpm: float, horizon_bars: int, theme: StringName) -> void:
	music = MVMusic.make(def, bpm, horizon_bars)
	if _director != null and is_instance_valid(_director):
		MVAudioNotes.install(music, _director)
	style = MVStyle.for_theme(theme)
	for e: Array in _mounted:
		MVMount.apply_theme(e[0], style, e[1], e[2])
	for k: String in _order:
		var c: MVCanvas = _canvases[k]
		c.viz.style = style
		c.viz.set_music(music)
		c.due = 0.0


## The canvas for a visualiser kind (created on first request). `p_layer` selects the cassette for
## per-layer kinds (epicycle, epicycle_wave, sigil, rune_row).
func canvas(kind: StringName, p_layer: int = -1) -> MVCanvas:
	var key := "%s|%d" % [kind, p_layer]
	if _canvases.has(key):
		return _canvases[key]
	var v: MVViz = null
	match kind:
		KIND_STACK_SCREEN:
			v = MVStackStrip.screen_preset()
		KIND_FRIEZE:
			v = MVStackStrip.frieze_preset()
		KIND_EPICYCLE:
			v = MVEpicycleHologram.preset(maxi(0, p_layer), MVEpicycleHologram.MODE_ROSETTE)
		KIND_EPICYCLE_WAVE:
			v = MVEpicycleHologram.preset(maxi(0, p_layer), MVEpicycleHologram.MODE_WAVE)
		KIND_SIGILS:
			v = MVShapeSigil.preset_atlas()
		KIND_SIGIL:
			v = MVShapeSigil.preset_single(maxi(0, p_layer))
		KIND_CONSTELLATION:
			v = MVConstellation.preset()
		KIND_RUNES:
			v = MVRuneSequencer.preset(-1)
		KIND_RUNE_ROW:
			v = MVRuneSequencer.preset(maxi(0, p_layer))
		_:
			push_error("MusicVizHub: unknown visualiser kind '%s'" % kind)
			return null
	if v is MVRuneSequencer and glyph_sheet == null and not _sheet_checked:
		_sheet_checked = true
		if ResourceLoader.exists(GLYPH_SHEET_PATH):
			glyph_sheet = load(GLYPH_SHEET_PATH) as Texture2D
			glyph_grid = GLYPH_SHEET_GRID
		elif ResourceLoader.exists(GLYPH_ATLAS_PATH):
			# The painted 40-glyph atlas (assets/textures/README.md): 8 columns x 5 rows of 128 px.
			glyph_sheet = load(GLYPH_ATLAS_PATH) as Texture2D
			glyph_grid = GLYPH_ATLAS_GRID
	if v is MVRuneSequencer and glyph_sheet != null:
		(v as MVRuneSequencer).glyph_sheet = glyph_sheet
		(v as MVRuneSequencer).sheet_grid = glyph_grid
	if low_quality:
		v.size = (v.size * 0.5).round()
	v.style = style
	var c := MVCanvas.make(v, _rate(kind))
	c.name = "MV_%s_%d" % [kind, p_layer]
	add_child(c)
	if music != null:
		v.set_music(music)
	_canvases[key] = c
	_order.append(key)
	return c


func texture(kind: StringName, p_layer: int = -1) -> Texture2D:
	var c := canvas(kind, p_layer)
	return c.texture() if c != null else null


func _rate(kind: StringName) -> float:
	var r: float = RATES.get(kind, 15.0)
	return r * (0.5 if low_quality else 1.0)


## Overall strength (0..1) of every mounted visualiser (the shaders' `intensity`). MUSIC-13: the
## flourishes belong to the cinematic replay; while recording, readability comes first, so the
## game dims them (suggested: RECORD 0.55, REVIEW 0.8, IDLE / CINEMATIC 1.0).
func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)
	for e: Array in _mounted:
		(e[0] as ShaderMaterial).set_shader_parameter(&"intensity", intensity)


## The intensity suggested for a ViewMode (see set_intensity).
static func intensity_for_mode(mode: StringName) -> float:
	match mode:
		ViewMode.RECORD:
			return 0.55
		ViewMode.REVIEW:
			return 0.8
	return 1.0


func set_quality(low: bool) -> void:
	low_quality = low
	for k: String in _order:
		var c: MVCanvas = _canvases[k]
		c.hz = _rate(StringName(k.get_slice("|", 0)))


## Advances every visualiser to master `master_beat` with the four cassettes' TrackAudioState (the
## same array the game sends to AudioBase.set_tracks; missing / null entries = absent) and redraws
## the canvases that are due (at most max_redraws_per_frame, round-robin).
func update(master_beat: float, tracks: Array, dt: float) -> void:
	if music == null:
		return
	var t0 := Time.get_ticks_usec()
	music.update(master_beat, tracks)
	var n := _order.size()
	for k: String in _order:
		(_canvases[k] as MVCanvas).due -= dt
	var drawn := 0
	for j: int in n:
		if drawn >= max_redraws_per_frame:
			break
		var key := _order[(_rr + j) % n]
		var c: MVCanvas = _canvases[key]
		if c.due <= 0.0:
			c.redraw()
			c.due = maxf(c.due + 1.0 / maxf(1.0, c.hz), 0.25 / maxf(1.0, c.hz))
			drawn += 1
	if n > 0:
		_rr = (_rr + maxi(1, drawn)) % n
	# Compile the notes of one upcoming bar per frame ahead of the strips' look-ahead, so a bar
	# entering view never costs a compile in the middle of a redraw.
	music.prefetch(master_beat + PREFETCH_BEATS)
	last_update_usec = Time.get_ticks_usec() - t0


## Reads notes from the audio module's director (audio.director(), an AudioDirector) instead of
## compiling them again: the drawn notes are then the heard notes, and the per-bar compile cost is
## paid once. Call after audio.load_level(level) (each level makes a new director); it is re-applied
## on every later load_level of this hub. Returns false when the director cannot be used (the hub
## then keeps its own compiler, which is a faithful port of the same director).
func use_audio_director(director: Object) -> bool:
	_director = director
	if music == null:
		return director != null and MVAudioNotes.make(director) != null
	return MVAudioNotes.install(music, director)


## Remembers the four cassettes' states (same array and timing as AudioBase.set_tracks: call it
## wherever the game calls audio.set_tracks). update_from_frame() then uses them every frame.
func set_tracks(tracks: Array) -> void:
	_tracks = tracks.duplicate()


## update() from a RenderFrame (master beat = frame.music.beat, wall dt = frame.dt) with the states
## last given to set_tracks() (or `tracks` when passed).
func update_from_frame(frame: RenderFrame, tracks: Array = []) -> void:
	if frame == null or frame.music == null:
		return
	update(frame.music.beat, tracks if not tracks.is_empty() else _tracks, frame.dt)


## Redraws every canvas now (e.g. right after a level load, or for screenshots).
func redraw_all() -> void:
	for k: String in _order:
		(_canvases[k] as MVCanvas).redraw()


## CPU microseconds of the most recent _draw of every canvas (sum).
func draw_cost_usec() -> int:
	var s := 0
	for k: String in _order:
		s += (_canvases[k] as MVCanvas).viz.cost_usec
	return s


## Estimated CPU microseconds per rendered frame at `fps`: the last update() plus, per canvas, its
## average draw cost times its redraws per frame. This is what the decoration budget (< 1 ms) is
## measured against.
func frame_cost_usec(fps: float = 60.0) -> float:
	var s := float(last_update_usec)
	for k: String in _order:
		var c: MVCanvas = _canvases[k]
		s += maxf(0.0, c.viz.avg_cost_usec) * minf(c.hz, fps) / fps
	return s


## Per-canvas cost lines ("kind|layer: avg us x hz -> us/frame") for logs.
func cost_report(fps: float = 60.0) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _order:
		var c: MVCanvas = _canvases[k]
		var avg := maxf(0.0, c.viz.avg_cost_usec)
		out.append("%s: %.0f us x %.0f Hz -> %.1f us/frame" % [k, avg, c.hz, avg * minf(c.hz, fps) / fps])
	return out


func canvas_count() -> int:
	return _order.size()


func dispose() -> void:
	for k: String in _order:
		var c: MVCanvas = _canvases[k]
		if is_instance_valid(c):
			c.queue_free()
	_canvases.clear()
	_order.clear()
	_mounted.clear()
	music = null


# ───────────────────────────── mounting ─────────────────────────────
# Energies are the dark-depths values; on warm levels MVMount.apply_theme caps them so the drawing
# reads as ink and colour on pale stone instead of blowing out.

func _surface(tex: Texture2D, energy: float, backdrop: Color = Color(0, 0, 0, 0), uv_rect: Rect2 = Rect2(0, 0, 1, 1), disc: bool = false) -> ShaderMaterial:
	var m := MVMount.surface_material(tex, energy, backdrop, uv_rect, disc)
	MVMount.apply_theme(m, style, energy, false)
	m.set_shader_parameter(&"intensity", intensity)
	_mounted.append([m, energy, false])
	return m


func _hologram(tex: Texture2D, energy: float) -> ShaderMaterial:
	var m := MVMount.hologram_material(tex, energy)
	MVMount.apply_theme(m, style, energy, true)
	m.set_shader_parameter(&"intensity", intensity)
	_mounted.append([m, energy, true])
	return m


## Draws the four-lane Stack strip on a prop's "Screen" surface (wave_screen). Returns the screen
## mesh, or null when the model has none.
func mount_screen(model_root: Node, energy: float = 1.6) -> MeshInstance3D:
	if MVMount.find_screen(model_root) == null:
		return null
	return MVMount.on_screen(model_root, _surface(texture(KIND_STACK_SCREEN), energy, MVMount.SCREEN_GLASS))


## A long Stack frieze along a wall face from floor point a to b, from height y0 for `height`.
func mount_frieze(parent: Node3D, a: Vector3, b: Vector3, y0: float, height: float, facing: Vector3, energy: float = 1.7) -> MeshInstance3D:
	return MVMount.wall_quad(parent, a, b, y0, height, facing, _surface(texture(KIND_FRIEZE), energy))


## A rune sequencer strip along a wall (p_layer -1: four rows, one per cassette).
func mount_runes(parent: Node3D, a: Vector3, b: Vector3, y0: float, height: float, facing: Vector3, p_layer: int = -1, energy: float = 1.7) -> MeshInstance3D:
	var kind := KIND_RUNES if p_layer < 0 else KIND_RUNE_ROW
	return MVMount.wall_quad(parent, a, b, y0, height, facing, _surface(texture(kind, p_layer), energy))


## One cassette's Shape sigil as a floor inscription of `radius` at floor point `centre`.
func mount_sigil(parent: Node3D, centre: Vector3, radius: float, p_layer: int, energy: float = 1.6) -> MeshInstance3D:
	var c := canvas(KIND_SIGILS)
	var cell := (c.viz as MVShapeSigil).cell_rect(p_layer)
	return MVMount.floor_disc(parent, centre, radius, _surface(c.texture(), energy, Color(0, 0, 0, 0), cell, true))


## The level signature: the four sigils in a row centred on floor point `centre`, `spacing` apart
## along `axis` (default +X), each of `radius`.
func mount_signature(parent: Node3D, centre: Vector3, spacing: float, radius: float, axis: Vector3 = Vector3.RIGHT) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var ax := Vector3(axis.x, 0.0, axis.z).normalized()
	for i: int in OD.TAPE_COUNT:
		out.append(mount_sigil(parent, centre + ax * spacing * (float(i) - 1.5), radius, i))
	return out


## A rune sequencer strip inlaid in the floor from floor point a to b, `width` across (p_layer -1:
## four rows, one per cassette, aspect about 4 : 1).
func mount_floor_runes(parent: Node3D, a: Vector3, b: Vector3, width: float, p_layer: int = -1, energy: float = 1.6) -> MeshInstance3D:
	var kind := KIND_RUNES if p_layer < 0 else KIND_RUNE_ROW
	return MVMount.floor_strip(parent, a, b, width, _surface(texture(kind, p_layer), energy))


## The epicycle hologram of cassette `p_layer` standing at floor point `base`.
func mount_hologram(parent: Node3D, base: Vector3, p_layer: int, size: float = 1.6, lift: float = 0.35, energy: float = 2.2) -> MeshInstance3D:
	return MVMount.hologram(parent, base, size, size, _hologram(texture(KIND_EPICYCLE, p_layer), energy), lift)


## The constellation helix as a hologram at floor point `base`.
func mount_constellation(parent: Node3D, base: Vector3, size: float = 1.6, lift: float = 0.35, energy: float = 2.0) -> MeshInstance3D:
	return MVMount.hologram(parent, base, size, size, _hologram(texture(KIND_CONSTELLATION), energy), lift)
