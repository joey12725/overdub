// OVERDUB cel-shaded material with alpha scissor and both faces (foliage cards, vines).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

#define OD_CUTOUT
#include "res://shaders/toon_body.gdshaderinc"
