// Normal-blended effect sprites: ink splashes, debris, dust (see fx_sprite.gdshaderinc).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform, blend_mix, shadows_disabled, fog_disabled;

#define FX_ADDITIVE 0.0
#define FX_GAIN 1.0
#include "res://fx/shaders/fx_sprite.gdshaderinc"
