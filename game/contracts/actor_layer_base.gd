class_name ActorLayerBase
extends RenderLayerBase
## The actor layer: Moxie and her selves, enemies, projectiles, state visuals (recording ghost,
## playback ghost, desynced projection, recovery spark - never confusable).
##
## Implemented by res://actors/actor_layer.gd (`extends ActorLayerBase`, no class_name needed);
## the world view instances it from Facades.ACTOR_LAYER_SCRIPT. See RenderLayerBase for the lifecycle.


## Scene position of a self's body for camera framing and fx anchoring (sim position at floor level
## by default). Implementers may refine it (e.g. chest height).
func self_anchor(tape: int, frame: RenderFrame) -> Vector3:
	if frame == null or frame.snap == null:
		return Vector3.ZERO
	var a := frame.snap.actor(tape)
	return RenderCtx.to_scene(a.x, a.y) if a != null else Vector3.ZERO
