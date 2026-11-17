class_name UiBase
extends Control
## The UI facade (contracts.ts IUi): menus, the in-level HUD and toasts, drawn above the 3D view.
## Implemented by the root script of res://ui/ui_root.tscn (`extends UiBase`); the game instances it
## through Facades.instance_ui() and adds it to the tree (on a CanvasLayer above the world).
##
## The UI never mutates game state: every player choice leaves through the `intent` signal and the
## game layer decides. This base already instances the HUD (attach_hud(), call it in _ready) and
## forwards the HUD calls to it; menu implementers override the menu methods.

## Emits player intents from clicks / menu keys.
signal intent(i: UiIntent)

## toast() tones.
const TONE_INFO: StringName = &"info"
const TONE_GOOD: StringName = &"good"
const TONE_WARN: StringName = &"warn"

## navigate() directions.
const NAV_UP: StringName = &"up"
const NAV_DOWN: StringName = &"down"
const NAV_LEFT: StringName = &"left"
const NAV_RIGHT: StringName = &"right"
const NAV_ACCEPT: StringName = &"accept"
const NAV_BACK: StringName = &"back"

## set_device() devices (same values as HudBase.DEVICE_*).
const DEVICE_KEYBOARD: StringName = &"keyboard"
const DEVICE_GAMEPAD: StringName = &"gamepad"

## The HUD instance (null until attach_hud()).
var hud: HudBase = null
## Current screen (UiScreen.*).
var screen: StringName = UiScreen.TITLE


# ───────────────────────────── menus (override) ─────────────────────────────

## UiScreen.*. The base shows the HUD on 'play' and 'pause' (it stays readable under the pause
## overlay) and hides it otherwise; overrides call super.
func show_screen(s: StringName) -> void:
	screen = s
	if hud != null:
		hud.visible = s == UiScreen.PLAY or s == UiScreen.PAUSE


func set_campaign(_model: CampaignScreenModel) -> void:
	pass


func set_loadout(_model: LoadoutScreenModel) -> void:
	pass


func set_results(_model: ResultsModel) -> void:
	pass


## The base forwards `patterns` to the HUD; overrides call super.
func set_settings(settings: SaveSettings) -> void:
	if hud != null:
		hud.set_patterns(settings.patterns)


## Short toast ("Tape B desynced", "New gear: ..."). tone: TONE_*.
func toast(_text: String, _tone: StringName = TONE_INFO) -> void:
	pass


## Menu navigation from keyboard / gamepad when a menu screen is up (NAV_*). Ignored on 'play'.
func navigate(_dir: StringName) -> void:
	pass


# ───────────────────────────── HUD (forwarded by the base) ─────────────────────────────

## In-level HUD update (called every frame while a level is up).
func update_hud(view: SessionView, pulse: MusicPulse) -> void:
	if hud != null and (screen == UiScreen.PLAY or screen == UiScreen.PAUSE):
		hud.update_hud(view, pulse)


## Flash a deck when its self performs an action / dies / desyncs (ActionKind.* or StateMarkKind.*).
func deck_event(tape: int, kind: StringName) -> void:
	if hud != null:
		hud.deck_event(tape, kind)


## Which device the player is using, so the HUD and menus show matching prompts. Overrides that also
## restyle menus call super.
func set_device(device: StringName) -> void:
	if hud != null:
		hud.set_device(device)


## Button prompts for the current device (SessionAction.* / ActionKind.* -> ButtonPrompt).
func set_bindings(prompts: Dictionary[StringName, ButtonPrompt]) -> void:
	if hud != null:
		hud.set_bindings(prompts)


## 0..1 progress of the hold-to-confirm (reset all) being held; 0 when none.
func set_hold_progress(progress: float) -> void:
	if hud != null:
		hud.set_hold_progress(progress)


# ───────────────────────────── plumbing (provided) ─────────────────────────────

## Instance the HUD from Facades.HUD_SCENE (a do-nothing HudBase if it does not exist yet), add it
## as the first child (below menus and toasts), and route its clicks out as session intents.
func attach_hud() -> void:
	if hud != null:
		return
	hud = Facades.instance_hud()
	hud.name = "Hud"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.visible = screen == UiScreen.PLAY or screen == UiScreen.PAUSE
	add_child(hud)
	move_child(hud, 0)
	hud.action.connect(func(a: StringName) -> void: emit_intent(UiIntent.session(a)))


## Emit an intent (convenience for implementers).
func emit_intent(i: UiIntent) -> void:
	intent.emit(i)


## Release timers / tweens; the node itself is freed by its owner.
func dispose() -> void:
	pass
