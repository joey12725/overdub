class_name ActorOptions
extends RefCounted
## Player-facing readability options the actor layer honours (docs/ACCESSIBILITY.md sections 5.2 and
## 6): which measured cassette colour set is in use, high-contrast outlines, colour-blind patterns
## and "reduce flashing". Static, because the render contract (RenderCtx) carries only the screen
## shake switch: the game calls ActorOptions.apply_settings(save.settings) whenever settings load or
## change, and the actor layer reads the values at load_level() and every frame.
##
## apply_settings() reads fields by name and ignores the ones SaveSettings does not have yet, so it
## is safe to call today and picks the new fields up when they land (cassette_palette,
## high_contrast, reduce_flashing; `patterns` exists already).

## AccessKit.SET_DEFAULT / SET_HIGH_CONTRAST / SET_LEGACY.
static var cassette_set: String = AccessKit.SET_DEFAULT
static var high_contrast: bool = false
static var patterns: bool = false
static var reduce_flashing: bool = false


static func apply_settings(settings: Object) -> void:
	if settings == null:
		return
	var v: Variant = settings.get(&"cassette_palette")
	if v is String or v is StringName:
		cassette_set = String(v) if AccessKit.set_ids().has(String(v)) else AccessKit.SET_DEFAULT
	v = settings.get(&"high_contrast")
	if v is bool:
		high_contrast = v
	v = settings.get(&"patterns")
	if v is bool:
		patterns = v
	v = settings.get(&"reduce_flashing")
	if v is bool:
		reduce_flashing = v
	# One set of cassette colours everywhere: the HUD, effects and music displays read OD.tape_color.
	OD.set_tape_palette(tape_colors())


## The four cassette colours of the active set (AccessKit; OD.tape_color if the data is unreadable).
static func tape_colors() -> PackedColorArray:
	var out := PackedColorArray()
	var set := AccessKit.colors(cassette_set)
	for i: int in OD.TAPE_COUNT:
		out.append(set[i] if i < set.size() else OD.TAPE_COLORS_RGB[i])
	return out


## Largest alpha a whole-body flash may reach (a struck boss is a large area; ACCESSIBILITY A13).
static func body_flash_max() -> float:
	return 0.0 if reduce_flashing else 1.0


## Strength of the chromatic split / flicker treatments (photosensitivity `chromatic_split_max`).
static func split_scale() -> float:
	return float(AccessKit.flash_limits(reduce_flashing).get("chromatic_split_max", 1.0))
