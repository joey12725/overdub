// Additive markers drawn over walls (merge flash, missile reticle, phase shots).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled, shadows_disabled;

#include "res://actors/shaders/actor_flat.gdshaderinc"
