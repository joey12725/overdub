class_name RenderFrame
extends RefCounted
## Per-frame presentation inputs that are not part of the simulation (contracts.ts RenderFrame).
## Built by the game every rendered frame and passed to WorldViewBase.render(), which hands it to
## every RenderLayerBase.update().

## Snapshot to draw.
var snap: FrameSnapshot = null
## Previous snapshot, for interpolation; may be the same object as `snap`.
var prev: FrameSnapshot = null
## 0..1 interpolation factor from prev to snap.
var alpha: float = 1.0
## Wall-clock seconds since the last render call.
var dt: float = 0.0
## ViewMode.*
var mode: StringName = ViewMode.IDLE
## Events that happened since the last render call (hit sparks, shakes, flashes).
var events: Array[SimEvent] = []
## How fast master time passes relative to wall time (drives world-speed visual treatment).
var world_rate: float = 1.0
## Live music analysis for music-linked visuals (runes, panels, flourishes).
var music: MusicPulse = MusicPulse.new()
## Which cassette is under live control (gets the camera + highlight); -1 = none.
var active: int = -1
## Cinematic director output for this frame (docs/CINEMATIC.md), or null. The game may fill it; when
## it is null in CINEMATIC mode the world view advances its own director (WorldView.set_cinema_plan)
## and stores the result here before the layers update, so the fx layer reads the same frame.
var cinema: CinemaFrame = null
