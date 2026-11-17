class_name ThemePalette
extends RefCounted
## Colours for one depth theme (prototype render/layer.ts ThemePalette); the environment, actors and
## fx all draw from the same palette. The world view builds one per level (world/ owns the actual
## per-theme values; the defaults here are the prototype's 'upper' palette) and shares it through
## RenderCtx.palette. Intensities are the prototype's relative values; the world maps them to Godot
## light energy.

## LevelTheme.*
var theme: StringName = LevelTheme.UPPER
## Clear colour / fog.
var background: Color = Color("#221917")
var fog: Color = Color("#2a1f1c")
var floor_color: Color = Color("#dcb9a0")
var floor_alt: Color = Color("#caa58e")
var wall: Color = Color("#b99178")
var wall_top: Color = Color("#eed4b8")
var metal: Color = Color("#8e8178")
var trim: Color = Color("#6b5446")
## Yellow utility / hazard accent.
var hazard: Color = Color("#ffc21a")
var foliage: Color = Color("#93c22c")
## Neon / emissive accents (cyan, magenta, violet).
var neon_a: Color = Color("#4fe6e0")
var neon_b: Color = Color("#ff3d9a")
var neon_c: Color = Color("#c06bff")
var graffiti: Color = Color("#ff3fa4")
## Ink outline colour.
var ink: Color = Color("#1f1412")
## Key light colour and intensity, ambient colour and intensity.
var key_light: Color = Color("#fff0d6")
var key_intensity: float = 2.7
var ambient: Color = Color("#d2d8de")
var ambient_intensity: float = 1.35
## Bloom / glow strength 0..2.
var bloom: float = 0.45
