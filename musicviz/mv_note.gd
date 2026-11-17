class_name MVNote
extends RefCounted
## One note a cassette layer plays (director.ts LayerNote), on the master beat clock.

const DRUM_KICK: StringName = &"kick"
const DRUM_RIM: StringName = &"rim"
const DRUM_SNARE: StringName = &"snare"
const DRUM_CLAP: StringName = &"clap"
const DRUM_HAT_CLOSED: StringName = &"hatClosed"
const DRUM_TOM: StringName = &"tom"
const DRUM_HAT_OPEN: StringName = &"hatOpen"
const DRUM_PERC: StringName = &"perc"

## GM-style drum notes (director.ts DRUM_NOTE).
const DRUM_NOTE: Dictionary = {&"kick": 36, &"rim": 37, &"snare": 38, &"clap": 39, &"hatClosed": 42, &"tom": 45, &"hatOpen": 46, &"perc": 56}
## Rough height of each drum for contour visuals (director.ts DRUM_NORM).
const DRUM_NORM: Dictionary = {&"kick": 0.05, &"tom": 0.3, &"snare": 0.45, &"clap": 0.5, &"rim": 0.55, &"perc": 0.65, &"hatClosed": 0.85, &"hatOpen": 0.95}

var track: int = 0
## Master beat of the onset.
var beat: float = 0.0
## Master beats.
var duration: float = 0.25
## MIDI pitch (drums: DRUM_NOTE).
var pitch: int = 60
## 1..127.
var velocity: int = 100
## Drum kind, or &"" for a pitched note.
var drum: StringName = &""
## Pitch normalised into the layer range 0..1.
var norm: float = 0.5
## Local step the note came from.
var step: int = 0
