// Soft additive particles drawn over everything: the recovery spark and its comet trail
// (DESYNC-06: small, bright and never hidden by walls).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled, shadows_disabled;

#include "res://actors/shaders/actor_particle.gdshaderinc"
