class_name FxColors
extends RefCounted
## Effect colours that are not part of the theme palette (prototype render/fx/colors.ts). Authored
## sRGB values; the fx shaders convert to linear where the 3D renderer expects it.

const WHITE := Color(1.0, 1.0, 1.0)
## "Not enough momentum": a dull, cold grey so a clang never reads as a real hit.
const CLANG := Color("#8f969e")
const CLANG_WORD := Color("#b9c0c8")
const DUST := Color("#cfc3ad")
const ENEMY := Color("#ff3d5a")
## Fallback for boss recall when the remembered tape is unknown.
const RECALL := Color("#b26bff")
const SLOW_WORLD := Color("#7cc8ff")
const FAST_WORLD := Color("#ffb066")
const TIER0_WORD := Color("#d8d8d8")


## Cassette identity colour (UI-02); `fallback` when tape is not 0..3.
static func tape(t: int, fallback: Color = WHITE) -> Color:
	return OD.tape_color(t) if t >= 0 and t < OD.TAPE_COUNT else fallback
