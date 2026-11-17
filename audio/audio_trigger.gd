class_name AudioTrigger
extends RefCounted
## One sample voice to start: which sample family, at what pitch, when, how loud, for how long and
## on which bus. Produced by AudioCues (pure), consumed by AudioVoiceEngine.

## Logical destinations. AudioVoiceEngine maps them to real buses (AudioBusSetup).
const DEST_LAYER: int = 0
const DEST_SFX: int = 1
const DEST_UI: int = 2

## Sample family name (assets/audio/manifest.json).
var family: StringName = &""
## MIDI pitch; < 0 for unpitched families (played at their recorded pitch).
var pitch: float = -1.0
## Seconds after the cue's base time.
var offset: float = 0.0
## Linear amplitude (a family's loudest sample peaks at about this level).
var gain: float = 1.0
## Seconds until the note is released; <= 0 lets the sample play out.
var dur: float = 0.0
## Release fade in seconds (0 = the family default).
var release: float = 0.0
## DEST_*.
var dest: int = DEST_SFX
## Layer index (DEST_LAYER) or tape for SFX panning (-1 = centre).
var channel: int = -1
## Reverb send level for layer voices (0 = dry only).
var send: float = 0.0


static func make(p_family: StringName, p_pitch: float, p_gain: float, p_offset: float = 0.0, p_dur: float = 0.0, p_release: float = 0.0) -> AudioTrigger:
	var t := AudioTrigger.new()
	t.family = p_family
	t.pitch = p_pitch
	t.gain = p_gain
	t.offset = p_offset
	t.dur = p_dur
	t.release = p_release
	return t
