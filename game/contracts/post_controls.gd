class_name PostControls
extends RefCounted
## Screen treatments the fx layer may drive (prototype render/layer.ts PostControls). `chromatic` and
## `flash` are kicks: the world view decays them toward 0 every frame, so a layer sets them on an
## event and forgets. `saturation` and `vignette` are held values the fx layer owns. All are no-ops
## on 'low' quality.

## Chromatic split amount 0..1 (use sparingly).
var chromatic: float = 0.0
## Full-screen flash 0..1 toward flash_color.
var flash: float = 0.0
var flash_color: Color = Color.WHITE
## 1 = as rendered, 0 = greyscale, > 1 more saturated.
var saturation: float = 1.0
## Vignette strength multiplier (1 = the theme's default).
var vignette: float = 1.0
