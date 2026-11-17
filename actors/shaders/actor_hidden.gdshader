// A surface that is not drawn (a part of the model replaced by an attachment, e.g. the wrist device
// under a worn ranged weapon). Discarding keeps the mesh's surface layout intact.
shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled;

void fragment() {
	discard;
}
