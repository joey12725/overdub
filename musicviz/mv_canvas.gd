class_name MVCanvas
extends SubViewport
## A visualiser's render target: a transparent 2D SubViewport holding one MVViz drawer, re-rendered
## only when the hub asks (UPDATE_ONCE) at a reduced rate. texture() is applied to props, walls,
## floors and holograms (see MVMount). The texture holds PREMULTIPLIED colour (Godot's 2D blend into
## a transparent target), which the musicviz shaders expect.

var viz: MVViz = null
## Redraws per second (decoration: 12-30 is plenty).
var hz: float = 20.0
## Wall-clock seconds until the next redraw is due.
var due: float = 0.0


static func make(p_viz: MVViz, p_hz: float = 20.0) -> MVCanvas:
	var c := MVCanvas.new()
	c.viz = p_viz
	c.hz = p_hz
	c.size = Vector2i(p_viz.size)
	c.transparent_bg = true
	c.disable_3d = true
	c.gui_disable_input = true
	c.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	c.render_target_update_mode = SubViewport.UPDATE_ONCE
	c.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	c.add_child(p_viz)
	return c


## The live texture of this canvas (a ViewportTexture).
func texture() -> Texture2D:
	return get_texture()


## Draws the visualiser now and renders the target once.
func redraw() -> void:
	if viz != null:
		viz.refresh()
	render_target_update_mode = SubViewport.UPDATE_ONCE
