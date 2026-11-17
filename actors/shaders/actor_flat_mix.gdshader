// Flat markers, alpha-blended, depth-tested (floor rings, telegraphs). See actor_flat.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://actors/shaders/actor_flat.gdshaderinc"
