// OVERDUB cel-shaded lit material. Uniforms: shaders/README.md. Build it with ToonKit.toon().
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/toon_body.gdshaderinc"
