class_name AudioBase
extends Node
## The audio facade (contracts.ts IAudio). Implemented by the root script of
## res://audio/audio.tscn (`extends AudioBase`); the game instances it through
## Facades.instance_audio() and adds it to the tree. Every method has a silent default so the game
## runs before audio exists; pulse() then returns safe defaults.

## ui() kinds.
const UI_MOVE: StringName = &"move"
const UI_SELECT: StringName = &"select"
const UI_BACK: StringName = &"back"
const UI_COMMIT: StringName = &"commit"
const UI_RETRY: StringName = &"retry"
const UI_RESET: StringName = &"reset"
const UI_WIN: StringName = &"win"
const UI_FAIL: StringName = &"fail"
const UI_LOOT: StringName = &"loot"
const UI_SPEED: StringName = &"speed"
const UI_KINDS: Array[StringName] = [UI_MOVE, UI_SELECT, UI_BACK, UI_COMMIT, UI_RETRY, UI_RESET, UI_WIN, UI_FAIL, UI_LOOT, UI_SPEED]

## set_mode() modes. Cinematic opens the mix up (wider, brighter) without changing the notes.
const MODE_MENU: StringName = &"menu"
const MODE_RECORD: StringName = &"record"
const MODE_REVIEW: StringName = &"review"
const MODE_CINEMATIC: StringName = &"cinematic"

var _silent_pulse: MusicPulse = MusicPulse.new()


## Start audio output. (The prototype needed a user gesture to resume the AudioContext; in Godot this
## may simply start the streams.)
func unlock() -> void:
	pass


## Load a level's key, progression and four cassette functions.
func load_level(_level: LevelDef) -> void:
	pass


## Called every frame. Tells the music where the master timeline is and how fast it is moving
## relative to wall time (`rate` = master seconds per wall second; 0 pauses the music). The audio
## layer schedules notes slightly ahead from this.
func set_transport(_master_beat: float, _rate: float, _playing: bool) -> void:
	pass


## Exactly OD.TAPE_COUNT entries, index = tape.
func set_tracks(_tracks: Array[TrackAudioState]) -> void:
	pass


## Gameplay sounds. Played roughly quantised to a sixteenth-note grid (MUSIC-05), late only, and
## pitched from the current chord; never delays or alters gameplay (MUSIC-07).
func on_events(_events: Array[SimEvent]) -> void:
	pass


## Count-in tick: n is 5, 6, 7 or 8 ("five, six, seven, eight").
func count_in(_n: int) -> void:
	pass


## UI feedback blips (UI_*).
func ui(_kind: StringName) -> void:
	pass


## MODE_*.
func set_mode(_mode: StringName) -> void:
	pass


## Linear 0..1 volumes.
func set_volumes(_master: float, _music: float, _sfx: float) -> void:
	pass


## Live music analysis for visuals and the HUD. Must be cheap (called every frame).
func pulse() -> MusicPulse:
	return _silent_pulse


## Stop everything and free voices. The node itself is freed by its owner.
func dispose() -> void:
	pass

# ── Voice (docs/VOICE-CAST.md section 6). Additive; every default is silent. ──

## voices setting values for set_voice_options().
const VOICES_ON: StringName = &"on"
const VOICES_COUNT_ONLY: StringName = &"countin"
const VOICES_OFF: StringName = &"off"


## Voices `on` / `countin` (only Moxie's count-in words) / `off`; barks on or off; Voice fader 0..1.
func set_voice_options(_voices: StringName, _barks: bool, _voice_volume: float) -> void:
	pass


## Speaks a dialogue line by story id: a manifest id ("l04_intro_01"), a story location
## ("levels.04-second-opinion.intro[0]") or, with `who`, the exact line text. Returns its length in
## seconds (0 = no audio; show the text silently). Hold the box for at least that + 0.35 s.
func play_line(_key: String, _who: String = "", _radio: bool = false) -> float:
	return 0.0


## Length of a line's audio without playing it (0 = none).
func line_duration(_key: String, _who: String = "", _radio: bool = false) -> float:
	return 0.0


## Stops the current line with a short fade (early advance, skip).
func stop_line() -> void:
	pass


## A bark for the dialogue system's bark key; obeys the bark rate limits. Returns seconds played (0 =
## suppressed or no audio).
func play_bark(_key: String, _event_key: String, _who: String = "moxie") -> float:
	return 0.0


## The take was abandoned during the count-in: drop the count words already queued.
func cancel_count_in() -> void:
	pass


## Optional: wire a DialogueLayer (res://ui/dialogue/dialogue_layer.tscn) so its lines and barks are
## spoken. Safe to call with null.
func connect_dialogue(_layer: Node) -> void:
	pass
