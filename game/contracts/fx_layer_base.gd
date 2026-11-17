class_name FxLayerBase
extends RenderLayerBase
## The fx layer: particles, hit sparks, music-linked visuals (owns ctx.music_reactive modulation),
## screen treatments through ctx.post, shake/focus requests through ctx.shake()/ctx.focus(), and
## cinematic flourishes.
##
## Implemented by res://fx/fx_layer.gd (`extends FxLayerBase`, no class_name needed); the world view
## instances it from Facades.FX_LAYER_SCRIPT. See RenderLayerBase for the lifecycle.
