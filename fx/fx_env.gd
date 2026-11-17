class_name FxEnv
extends RefCounted
## Level-scoped inputs FxDirector needs (no nodes): built by the fx layer from the RenderCtx.

var palette: ThemePalette = ThemePalette.new()
var level: LevelDef = LevelDef.new()
## Momentum of a 1x standing light attack with the current loadout (tier reference).
var ref_momentum: float = 1.0
## Melee reach in tiles and arc in degrees, so swing arcs match the real hit volume.
var melee_reach: float = 1.2
var melee_arc_deg: float = 120.0
## WorldViewBase.QUALITY_LOW / QUALITY_HIGH.
var quality: StringName = &"high"
## Accessibility: reduce flashing (docs/ACCESSIBILITY.md photosensitivity limits, "reduced").
var reduce_flashing: bool = false
## The world mounted the music visualisers (RenderCtx.musicviz_mounted): fx ambient leaves the
## structural music visuals to them.
var musicviz_mounted: bool = false


## Env for a RenderCtx (palette, level and the loadout's melee numbers).
static func from_ctx(ctx: RenderCtx) -> FxEnv:
	var e := FxEnv.new()
	if ctx.palette != null:
		e.palette = ctx.palette
	if ctx.level != null:
		e.level = ctx.level
	e.quality = ctx.quality
	e.reduce_flashing = ctx.reduce_flashing
	e.musicviz_mounted = ctx.musicviz_mounted
	if ctx.loadout != null:
		var lo := ctx.loadout
		var ref := lo.melee.light.impact * (lo.mods.melee_impact if lo.mods != null else 1.0)
		e.ref_momentum = ref if ref > 0.0 else 1.0
		e.melee_reach = lo.melee.reach
		e.melee_arc_deg = lo.melee.arc_deg
	return e
