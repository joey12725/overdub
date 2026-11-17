extends FxLayerBase
## Effects, music-linked visuals and the cinematic layer (CINE-03, MUSIC-12, MUSIC-13; port of
## prototype/src/render/fx/index.ts). Instanced by WorldViewBase.attach_layers() from
## Facades.FX_LAYER_SCRIPT.
##
##   FxDirector        CPU: events -> pooled sprites / readouts, world-speed and cinematic state
##   FxSpriteRenderer  two MultiMeshes (additive glow, normal-blended ink) of analytic shapes
##   FxWordRenderer    hand-inked readouts from the FxWordAtlas
##   FxRibbonRenderer  per-tape cinematic ribbons
##   FxAmbient         sigils, contour strips, epicycles, rune overlays driven by RenderFrame.music
##   FxMusicDrive      pulses ctx.music_reactive (rune grooves, neon, screens, core)
##   FxOverlay         letterbox, world-speed tint / lines, sweep, flashes, impact lines, glitch tear
##
## Camera shake goes through ctx.shake() (proportional to the blow, scaled by mode), cinematic focus
## through ctx.focus(), chromatic split / saturation / vignette through ctx.post. Nothing here
## touches simulation state or gameplay time: the impact "freeze" holds only this layer's sprites.

## The director for the current level (null before load_level); exposed for tools and tests.
var director: FxDirector = null
var glow: FxSpriteRenderer = null
var ink: FxSpriteRenderer = null
var words: FxWordRenderer = null
var ribbons: FxRibbonRenderer = null
var ambient: FxAmbient = null
var overlay: FxOverlay = null
var atlas: FxWordAtlas = null
## Surfaces driven last frame (diagnostics / tests).
var reactive_driven: int = 0

var _ctx: RenderCtx = null
var _quality: StringName = &"high"


func load_level(ctx: RenderCtx) -> void:
	_teardown()
	_ctx = ctx
	_quality = ctx.quality
	var env := FxEnv.from_ctx(ctx)
	director = FxDirector.new(env)

	ink = FxSpriteRenderer.new()
	ink.setup(director.ink.capacity, false, 4)
	add_child(ink)
	glow = FxSpriteRenderer.new()
	glow.setup(director.glow.capacity, true, 6)
	add_child(glow)

	ribbons = FxRibbonRenderer.new()
	add_child(ribbons)
	ribbons.transform = Transform3D.IDENTITY

	ambient = FxAmbient.new()
	ambient.name = "FxAmbient"
	# World-space like the sprites: everything fx draws uses scene coordinates directly.
	ambient.top_level = true
	add_child(ambient)
	ambient.build(ctx)

	if atlas == null:
		atlas = FxWordAtlas.new()
		add_child(atlas)
		atlas.paint()
	words = FxWordRenderer.new()
	words.setup(director.text.capacity, atlas, env.palette.ink)
	add_child(words)

	overlay = FxOverlay.new()
	overlay.set_ink(env.palette.ink)
	add_child(overlay)

	FxMusicDrive.reset(ctx.music_reactive)


func update(frame: RenderFrame, ctx: RenderCtx) -> void:
	var d := director
	if d == null or frame == null:
		return
	if ctx.quality != _quality:
		_quality = ctx.quality
		d.set_quality(ctx.quality)
	var dt := clampf(frame.dt, 0.0, 0.1)
	d.env.reduce_flashing = ctx.reduce_flashing

	d.update(frame)

	if d.shake_out > 0.001:
		ctx.shake(d.shake_out)
	# A director plan frames the cinematic itself; focus requests would fight it (docs/CINEMATIC.md).
	if frame.mode == ViewMode.CINEMATIC and d.focus_w > 0.0 and frame.cinema == null:
		ctx.focus(d.focus_x, d.focus_y, d.focus_w)

	glow.sync(d.glow)
	ink.sync(d.ink)
	words.sync(d.text)
	ribbons.sync(d.ribbons, dt)
	overlay.sync(d.screen, ctx.camera)

	var prof := d.profile()
	ambient.update(frame.music, prof.ambient, dt, ctx.camera)
	# Reduce flashing: neon and emissive beat pulses swing at most ~15 % (docs/ACCESSIBILITY.md).
	reactive_driven = FxMusicDrive.apply(ctx.music_reactive, frame.music, prof.ambient * (FxMusicDrive.REDUCED_FLASH_SCALE if ctx.reduce_flashing else 1.0))
	_drive_post(ctx.post, frame.mode)


## Post controls: chromatic is a kick (the world view decays it), saturation / vignette are held.
func _drive_post(post: PostControls, mode: StringName) -> void:
	if post == null:
		return
	var d := director
	if d.screen.chromatic > post.chromatic:
		post.chromatic = d.screen.chromatic
	# A slowed world (recording a fast tape) cools and slightly desaturates; a sped-up world warms
	# and saturates a touch. Faint on purpose: readability first.
	var ws := d.world_speed
	var sat := 1.0 - 0.1 * maxf(0.0, -ws) + 0.05 * maxf(0.0, ws)
	if mode == ViewMode.CINEMATIC:
		sat += 0.06
	post.saturation = sat
	post.vignette = 1.0 + 3.0 * d.screen.letterbox


func dispose() -> void:
	_teardown()
	if atlas != null:
		atlas.queue_free()
		atlas = null


func _teardown() -> void:
	if _ctx != null:
		FxMusicDrive.reset(_ctx.music_reactive)
		if _ctx.post != null:
			_ctx.post.saturation = 1.0
			_ctx.post.vignette = 1.0
	for c: Node in get_children():
		if c == atlas:
			continue
		remove_child(c)
		c.queue_free()
	director = null
	glow = null
	ink = null
	words = null
	ribbons = null
	ambient = null
	overlay = null
	_ctx = null
