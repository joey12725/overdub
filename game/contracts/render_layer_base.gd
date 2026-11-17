class_name RenderLayerBase
extends Node3D
## A layer that draws into the world view's scene (prototype render/layer.ts RenderLayer). The world
## view instances the actor layer and the fx layer from their fixed script paths (Facades), adds
## them as children of itself, and drives them:
##   load_level(ctx)        after the environment of a new level is built (ctx.root is fresh)
##   update(frame, ctx)     every rendered frame, after the camera moved
##   dispose()              before the level is torn down / the view is freed
## Override all three. The defaults do nothing, so a missing layer never breaks the view.


## Build per-level objects (add them under this node or under ctx.root).
func load_level(_ctx: RenderCtx) -> void:
	pass


## Draw one frame.
func update(_frame: RenderFrame, _ctx: RenderCtx) -> void:
	pass


## Free per-level objects. The default frees every child of this node.
func dispose() -> void:
	for c: Node in get_children():
		c.queue_free()
