// Translucent twin of actor_body, double-sided (open sheets such as a face plane or hair cards, from materials imported as double-sided). See actor_body_fx.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always;

#include "res://actors/shaders/actor_body.gdshaderinc"
#include "res://actors/shaders/actor_body_fx.gdshaderinc"

void fragment() {
	od_body_fx(NORMAL, INV_VIEW_MATRIX, ALBEDO, ALPHA);
}
