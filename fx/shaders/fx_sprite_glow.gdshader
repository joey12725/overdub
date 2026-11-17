// Additive effect sprites: sparks, rings, flashes (see fx_sprite.gdshaderinc).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform, blend_add, shadows_disabled, fog_disabled;

#define FX_ADDITIVE 1.0
#define FX_GAIN 1.35
#include "res://fx/shaders/fx_sprite.gdshaderinc"
