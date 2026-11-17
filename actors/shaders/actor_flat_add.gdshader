// Flat markers, additive, depth-tested (glows, shock rings). See actor_flat.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

#include "res://actors/shaders/actor_flat.gdshaderinc"
