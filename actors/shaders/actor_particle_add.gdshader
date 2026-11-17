// Soft particles, additive (glows, sparks, hologram bits). See actor_particle.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

#include "res://actors/shaders/actor_particle.gdshaderinc"
