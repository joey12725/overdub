class_name CinemaFrame
extends RefCounted
## What the camera / fx owners apply for one rendered frame of the cinematic (CinemaDirector
## output). Floor points are sim axes (x, y); the scene maps them to (X = x, Z = y).

## Index into CinemaPlan.shots, -1 when there is no plan.
var shot_index: int = -1
var shot: CinemaShot = null
## Floor point the camera looks at (sim axes).
var target: Vector2 = Vector2.ZERO
## Floor diameter in tiles that must be visible (see docs/CINEMATIC.md for the view-size formula).
var span: float = 12.0
## 0..1 blend toward "fit the whole level" (1 for WIDE shots).
var wide: float = 0.0
## Yaw offset from the isometric yaw, radians (orbit moves).
var yaw_offset: float = 0.0
## Letterbox bar height, fraction of the screen height per bar.
var letterbox: float = CinemaGrammar.LETTERBOX_BASE
## 0..1 time-ripple strength (peaks on the shot's key beat).
var ripple: float = 0.0
## CinemaGrammar.EMPHASIS_* of the current shot.
var emphasis: StringName = CinemaGrammar.EMPHASIS_NONE
## Split-screen panes (copies with `focus` set to this frame's target per pane); empty = one view.
var panes: Array[CinemaTypes.Pane] = []
## 0..1 how far the split layout has opened (eases in and out at the shot's edges).
var split_t: float = 0.0
## Selves / entities to highlight this frame, with `strength` 0..1.
var callouts: Array[CinemaTypes.Callout] = []
## True on the first frame of a shot that begins with a hard cut: snap, do not damp.
var cut: bool = false
## Flourish cues whose beat was crossed since the previous advance() (empty from sample()).
var cues: Array[CinemaTypes.Cue] = []
## 0..1 progress through the shot.
var progress: float = 0.0
