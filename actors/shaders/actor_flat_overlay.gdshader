// Flat markers drawn over walls (live chevron, tether, target pips): alpha-blended, no depth test.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled, shadows_disabled;

#include "res://actors/shaders/actor_flat.gdshaderinc"
