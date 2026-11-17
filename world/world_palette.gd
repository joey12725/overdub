class_name WorldPalette
extends ThemePalette
## Theme palettes for the descent (WORLD-04: warmer at the top, more metallic / neon / cold going
## down), ported from prototype render/palettes.ts, plus the Godot lighting values the world view
## applies (sun, ambient, glow, fog, post grade). Every layer draws from the same palette through
## RenderCtx.palette, so a level reads as one picture.
##
## Upper: the user rejected a purple lighting cast on the warm board (chapter 18 "Upper layers").
## Graffiti stays pink / purple, but key, ambient and fill are warm or neutral there.
## Lower: darker, but the playable floor stays a mid value so selves, enemy tells and sparks read.

const FINISH_STONE: StringName = &"stone"
const FINISH_MIXED: StringName = &"mixed"
const FINISH_METAL: StringName = &"metal"

## Masonry / stone tint used for ruins and cliff faces.
var stone: Color = Color("#b7906c")
## Cliff face colour at the top of the skirt and at its deepest point (fades into the background).
var cliff: Color = Color("#9a7356")
var cliff_deep: Color = Color("#2a1f1c")
## Mortar / grout and dark recesses.
var grout: Color = Color("#5d4334")
## Orange rust / wear.
var rust: Color = Color("#d8742a")
## Second graffiti hue (the boards pair pink with purple).
var graffiti_alt: Color = Color("#a65ee0")
## Warm practical source (lamps; the "occasional warm orange source" of the lower board).
var warm: Color = Color("#ffb45a")
## Glow used for rune inscriptions on this theme.
var rune: Color = Color("#ffd27a")
## The theme's signature accent (core: the time machine's chronal glow).
var accent: Color = Color("#ff3d9a")
## Ground bounce colour (lower hemisphere of the ambient).
var bounce: Color = Color("#7a6656")
## Secondary fill from the opposite side of the key.
var fill: Color = Color("#ffe2bc")
var fill_intensity: float = 0.35
## Ambient motes: colour and density factor 0..1.
var mote: Color = Color("#fff0c8")
var mote_density: float = 0.6
## Floor finish: stone paints masonry slabs, metal paints inscribed plates.
var floor_finish: StringName = FINISH_STONE
## Fraction of tiles that get ambient overgrowth.
var overgrowth: float = 0.22

# ── Godot lighting (not in the prototype palette; tuned against docs/reference R03 / R04) ──
## DirectionalLight3D energy of the key.
var sun_energy: float = 1.55
## Ambient light energy (colour = ambient).
var ambient_energy: float = 0.62
## Shadow floor colour of the toon shader (ToonKit.theme_shadow_tint).
var shadow_tint: Color = Color(0.36, 0.30, 0.30, 1.0)
## WorldEnvironment glow intensity and HDR threshold.
var glow_intensity: float = 0.55
var glow_threshold: float = 1.0
## Depth fog toward the background colour below the diorama (0 = off).
var fog_density: float = 0.0
## Post grade: multiply, shadow lift, contrast, saturation, base vignette.
var grade_gain: Color = Color(1.03, 1.0, 0.95)
var grade_lift: Color = Color(0.02, 0.012, 0.0)
var contrast: float = 1.04
var saturation: float = 1.06
var vignette_base: float = 0.26
## Practical light energy multiplier (lamps, neon).
var practical_energy: float = 1.0


## Palette for a theme; unknown themes fall back to 'upper' so a bad level still renders.
static func for_theme(t: StringName) -> WorldPalette:
	match t:
		LevelTheme.MID:
			return _mid()
		LevelTheme.LOWER:
			return _lower()
		LevelTheme.CORE:
			return _core()
	return _upper()


static func _upper() -> WorldPalette:
	var p := WorldPalette.new()
	p.theme = LevelTheme.UPPER
	p.background = Color("#221917")
	p.fog = Color("#2a1f1c")
	p.floor_color = Color("#dcb9a0")
	p.floor_alt = Color("#caa58e")
	p.wall = Color("#b99178")
	p.wall_top = Color("#eed4b8")
	p.metal = Color("#8e8178")
	p.trim = Color("#6b5446")
	p.hazard = Color("#ffc21a")
	p.foliage = Color("#93c22c")
	p.neon_a = Color("#4fe6e0")
	p.neon_b = Color("#ff3d9a")
	p.neon_c = Color("#c06bff")
	p.graffiti = Color("#ff3fa4")
	p.ink = Color("#1f1412")
	p.key_light = Color("#fff0d6")
	p.key_intensity = 2.7
	# Neutral sky fill: sunlit faces stay warm, shadows go neutral rather than orange (never purple).
	p.ambient = Color("#d2d8de")
	p.ambient_intensity = 1.35
	p.bloom = 0.45
	p.stone = Color("#b7906c")
	p.cliff = Color("#9a7356")
	p.cliff_deep = Color("#2a1f1c")
	p.grout = Color("#5d4334")
	p.rust = Color("#d8742a")
	p.graffiti_alt = Color("#a65ee0")
	p.warm = Color("#ffb45a")
	p.rune = Color("#ffd27a")
	p.accent = Color("#ff3d9a")
	p.bounce = Color("#7a6656")
	p.fill = Color("#ffe2bc")
	p.fill_intensity = 0.35
	p.mote = Color("#fff0c8")
	p.mote_density = 0.6
	p.floor_finish = FINISH_STONE
	p.overgrowth = 0.22
	p.sun_energy = 1.55
	p.ambient_energy = 0.62
	p.shadow_tint = Color(0.40, 0.33, 0.30, 1.0)
	p.glow_intensity = 0.5
	p.grade_gain = Color(1.04, 1.0, 0.94)
	p.grade_lift = Color(0.025, 0.015, 0.0)
	p.contrast = 1.04
	p.saturation = 1.08
	p.vignette_base = 0.26
	p.practical_energy = 0.8
	return p


static func _mid() -> WorldPalette:
	var p := WorldPalette.new()
	p.theme = LevelTheme.MID
	p.background = Color("#17151d")
	p.fog = Color("#1c1a22")
	p.floor_color = Color("#a49a90")
	p.floor_alt = Color("#8e857e")
	p.wall = Color("#857a72")
	p.wall_top = Color("#b0a598")
	p.metal = Color("#707784")
	p.trim = Color("#474b56")
	p.hazard = Color("#ffb81c")
	p.foliage = Color("#76ad3c")
	p.neon_a = Color("#2fe6ff")
	p.neon_b = Color("#ff3fb4")
	p.neon_c = Color("#9b5cff")
	p.graffiti = Color("#ff4fae")
	p.ink = Color("#121018")
	p.key_light = Color("#f4e6d2")
	p.key_intensity = 2.3
	p.ambient = Color("#a9b0c4")
	p.ambient_intensity = 1.15
	p.bloom = 0.7
	p.stone = Color("#8f8378")
	p.cliff = Color("#6b6470")
	p.cliff_deep = Color("#17151d")
	p.grout = Color("#3b3a42")
	p.rust = Color("#c8662a")
	p.graffiti_alt = Color("#a65ee0")
	p.warm = Color("#ffa04a")
	p.rune = Color("#4ff0ff")
	p.accent = Color("#2fe6ff")
	p.bounce = Color("#4a4656")
	p.fill = Color("#8fc8ff")
	p.fill_intensity = 0.55
	p.mote = Color("#bfe8ff")
	p.mote_density = 0.45
	p.floor_finish = FINISH_MIXED
	p.overgrowth = 0.1
	p.sun_energy = 1.35
	p.ambient_energy = 0.62
	p.shadow_tint = Color(0.30, 0.30, 0.38, 1.0)
	p.glow_intensity = 0.7
	p.grade_gain = Color(0.99, 1.0, 1.03)
	p.grade_lift = Color(0.01, 0.012, 0.025)
	p.contrast = 1.06
	p.saturation = 1.06
	p.vignette_base = 0.32
	p.practical_energy = 1.0
	return p


static func _lower() -> WorldPalette:
	var p := WorldPalette.new()
	p.theme = LevelTheme.LOWER
	p.background = Color("#0d0912")
	p.fog = Color("#0e0a14")
	# The playable floor stays a mid value so selves, enemy tells and sparks read against it
	# (chapter 18 "Lower layers": darkness must not make the floor unreadable).
	p.floor_color = Color("#7a6884")
	p.floor_alt = Color("#6b5a75")
	p.wall = Color("#463a4f")
	p.wall_top = Color("#7a6684")
	p.metal = Color("#5e5066")
	p.trim = Color("#2b2132")
	p.hazard = Color("#ffb020")
	p.foliage = Color("#568f4c")
	p.neon_a = Color("#3ff0ff")
	p.neon_b = Color("#ff2fa0")
	p.neon_c = Color("#c040ff")
	p.graffiti = Color("#ff3fa4")
	p.ink = Color("#0a0610")
	p.key_light = Color("#cdc2f0")
	p.key_intensity = 2.2
	p.ambient = Color("#7e6ca6")
	p.ambient_intensity = 1.2
	p.bloom = 1.0
	p.stone = Color("#5b5060")
	p.cliff = Color("#3a2f42")
	p.cliff_deep = Color("#0d0912")
	p.grout = Color("#1e1724")
	p.rust = Color("#d06a28")
	p.graffiti_alt = Color("#b04dff")
	p.warm = Color("#ff8a2a")
	p.rune = Color("#ff3fd0")
	p.accent = Color("#ff2fa0")
	p.bounce = Color("#2a1a38")
	p.fill = Color("#ff4fc0")
	p.fill_intensity = 0.7
	p.mote = Color("#ff9cf0")
	p.mote_density = 0.5
	p.floor_finish = FINISH_METAL
	p.overgrowth = 0.05
	p.sun_energy = 1.1
	p.ambient_energy = 0.55
	p.shadow_tint = Color(0.30, 0.22, 0.40, 1.0)
	p.glow_intensity = 0.95
	p.grade_gain = Color(0.98, 0.96, 1.04)
	p.grade_lift = Color(0.02, 0.0, 0.035)
	p.contrast = 1.08
	p.saturation = 1.1
	p.vignette_base = 0.4
	p.practical_energy = 1.3
	return p


static func _core() -> WorldPalette:
	var p := WorldPalette.new()
	p.theme = LevelTheme.CORE
	p.background = Color("#06050c")
	p.fog = Color("#07060d")
	p.floor_color = Color("#58566f")
	p.floor_alt = Color("#4c4a62")
	p.wall = Color("#34324c")
	p.wall_top = Color("#5e5c80")
	p.metal = Color("#4c4a66")
	p.trim = Color("#1d1b2c")
	p.hazard = Color("#ffc23a")
	p.foliage = Color("#3f7a6a")
	p.neon_a = Color("#3ff0ff")
	p.neon_b = Color("#ff2fa0")
	p.neon_c = Color("#8a4dff")
	p.graffiti = Color("#ff3fa4")
	p.ink = Color("#05040a")
	p.key_light = Color("#bfc8ff")
	p.key_intensity = 1.7
	p.ambient = Color("#6a6aa0")
	p.ambient_intensity = 1.15
	p.bloom = 1.2
	p.stone = Color("#47455a")
	p.cliff = Color("#29273c")
	p.cliff_deep = Color("#06050c")
	p.grout = Color("#14121f")
	p.rust = Color("#c0602a")
	p.graffiti_alt = Color("#9a5cff")
	p.warm = Color("#ff9a3a")
	# The time-machine depth gets its own chronal amber so it reads apart from the lower neon.
	p.rune = Color("#ffb347")
	p.accent = Color("#ffb347")
	p.bounce = Color("#1c1830")
	p.fill = Color("#5fe8ff")
	p.fill_intensity = 0.75
	p.mote = Color("#ffd59a")
	p.mote_density = 0.7
	p.floor_finish = FINISH_METAL
	p.overgrowth = 0.02
	p.sun_energy = 0.95
	p.ambient_energy = 0.58
	p.shadow_tint = Color(0.26, 0.26, 0.42, 1.0)
	p.glow_intensity = 1.05
	p.grade_gain = Color(0.98, 0.98, 1.04)
	p.grade_lift = Color(0.015, 0.01, 0.04)
	p.contrast = 1.08
	p.saturation = 1.08
	p.vignette_base = 0.44
	p.practical_energy = 1.4
	return p


## Linear blend of two colours (prototype mixColor), clamped t.
static func mix_color(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))


## Multiply a colour's channels by f (prototype scaleColor), clamped to 0..1, alpha kept.
static func scale_color(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


## Hue (degrees), saturation and lightness (prototype hsl()).
static func hsl(c: Color) -> Vector3:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var l := (mx + mn) * 0.5
	if mx == mn:
		return Vector3(0.0, 0.0, l)
	var d := mx - mn
	var s := d / (2.0 - mx - mn) if l > 0.5 else d / (mx + mn)
	var h: float
	if mx == c.r:
		h = (c.g - c.b) / d + (6.0 if c.g < c.b else 0.0)
	elif mx == c.g:
		h = (c.b - c.r) / d + 2.0
	else:
		h = (c.r - c.g) / d + 4.0
	return Vector3(h * 60.0, s, l)
