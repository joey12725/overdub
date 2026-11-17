class_name HudBase
extends Control
## The in-level HUD (prototype ui/hud Hud): four cassette decks, the master beat ruler with one lane
## per cassette, objective, count-in, phase banner and decision prompts (UI-01..07, NEW-07..11).
## Implemented by the root script of res://ui/hud/hud.tscn (`extends HudBase`). UiBase instances it
## (Facades.instance_hud()) and forwards the calls below; the HUD never mutates game state, it
## emits clicks on its own controls through `action`.

## A clickable HUD control (record, commit, retry...) was pressed. UiBase turns it into a session intent.
signal action(session_action: StringName)

const DEVICE_KEYBOARD: StringName = &"keyboard"
const DEVICE_GAMEPAD: StringName = &"gamepad"


## Refresh from the session view and the music pulse (called every frame while playing).
func update_hud(_view: SessionView, _pulse: MusicPulse) -> void:
	pass


## Flash a deck when its self performs an action / dies / desyncs (kind: ActionKind.* or
## StateMarkKind.*).
func deck_event(_tape: int, _kind: StringName) -> void:
	pass


## DEVICE_KEYBOARD / DEVICE_GAMEPAD: which button prompts to show.
func set_device(_device: StringName) -> void:
	pass


## Button prompts for the current device: SessionAction.* (or ActionKind.* for gameplay buttons)
## -> ButtonPrompt.
func set_bindings(_prompts: Dictionary[StringName, ButtonPrompt]) -> void:
	pass


## 0..1 progress of a hold-to-confirm (reset all) currently being held; 0 when none.
func set_hold_progress(_progress: float) -> void:
	pass


## Colour-blind cassette patterns (SaveSettings.patterns).
func set_patterns(_enabled: bool) -> void:
	pass
