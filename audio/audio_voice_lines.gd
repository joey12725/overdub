class_name AudioVoiceLines
extends Node
## Spoken voice (assets/audio/voice/elevenlabs/manifest.json; docs/VOICE-CAST.md section 6): dialogue
## lines by story id, Moxie's barks with their rate limits, the spoken count-in placed on the beat,
## and efforts. Lines and barks play on the Voice bus (the facade ducks the music under them); the
## count-in plays on Ui and efforts on the acting tape's SfxA..D.
##
## Story ids: a line is found by its manifest id ("l04_intro_01"), its story location
## ("levels.04-second-opinion.intro[0]") or, for the dialogue box that only has the text, by speaker
## and exact text. Missing lines return 0 seconds and play nothing (the box shows the text silently).
##
## Timing of the count-in: each word is started so its vowel (manifest `vowelOnset`) is heard on the
## beat, using AudioServer.get_time_to_next_mix() + get_output_latency(); a word is fired on the frame
## that lands it closest to its target (error <= half a frame).

const MANIFEST_PATH := "res://assets/audio/voice/elevenlabs/manifest.json"

## voices setting (docs/VOICE-CAST.md 6.6): everything / only the count-in words / nothing spoken.
const MODE_ON: StringName = &"on"
const MODE_COUNT_ONLY: StringName = &"countin"
const MODE_OFF: StringName = &"off"

## Kinds of speech (for ducking).
const KIND_NONE := 0
const KIND_LINE := 1
const KIND_BARK := 2

## Bark rules (VOICE-CAST 6 dialogue step 4).
const BARK_GAP := 6.0
const BARK_SAME_KEY_GAP := 20.0
const BARK_CHANCE := 0.5
## Barks that may ignore the 6 s gap (death, fail, win).
const BARK_URGENT_KEYS: Array[String] = ["death", "selfDeath", "fail", "win", "lose", "defeat", "victory"]
## A line held at least this long past its audio (the box's own hold; informational).
const LINE_HOLD_PAD := 0.35
const LINE_STOP_FADE := 0.06
## Efforts (VOICE-CAST 6.5): one per tape every 150 ms, attacks on about one swing in three.
const EFFORT_TAPE_GAP := 0.15
const EFFORT_ATTACK_CHANCE := 0.34
const EFFORT_GAIN_DB := -8.0
## Count-in words sit about 6 dB under a line (they peak at -3 dBFS).
const COUNT_GAIN_DB := -6.0
## Silence kept between one count word and the next inside a beat (s).
const COUNT_GAP := 0.04
## Largest speed-up of a count take that is too long for the beat: two semitones.
const COUNT_MAX_RATE := 1.122

var mode: StringName = MODE_ON
var barks_enabled: bool = true
## Errors from loading (empty when the manifest loaded).
var errors: Array[String] = []
## Count of voice plays started (lines, barks, count words, efforts) — for tools and tests.
var started: int = 0
var suppressed_barks: int = 0

var _lines: Dictionary = {}
var _by_location: Dictionary = {}
var _by_text: Dictionary = {}
var _count: Dictionary = {}
var _efforts: Dictionary = {}
var _base := "res://assets/audio/voice/elevenlabs/"
var _streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _line_player: AudioStreamPlayer
var _bark_player: AudioStreamPlayer
var _count_players: Array[AudioStreamPlayer] = []
var _effort_players: Array[AudioStreamPlayer] = []
var _line_fade_from := -1.0
var _line_end := -INF
var _bark_end := -INF
var _last_bark_at := -INF
var _last_bark_id := ""
var _last_by_key: Dictionary = {}
var _effort_last: Array[float] = [-INF, -INF, -INF, -INF]
var _effort_last_file: Dictionary = {}
## Pending count words: [target heard time, stream, gain_db, n, pitch_scale].
var _pending: Array = []
var _count_anchor := -INF
var _count_beat := 0.5
var _count_take: Dictionary = {}


func _init() -> void:
	_rng.seed = 0x0D0B
	load_manifest()


func _ready() -> void:
	_line_player = _make_player("Line", AudioBusSetup.VOICE)
	_bark_player = _make_player("Bark", AudioBusSetup.VOICE)
	for i: int in 3:
		_count_players.append(_make_player("Count%d" % i, AudioBusSetup.UI))
	for i: int in OD.TAPE_COUNT:
		_effort_players.append(_make_player("Effort%d" % i, AudioBusSetup.SFX_PAN[i]))


func _make_player(n: String, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	p.bus = bus
	add_child(p)
	return p


func load_manifest() -> bool:
	errors.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		errors.append("missing " + MANIFEST_PATH)
		return false
	var parse: Array[String] = []
	var d: Variant = ODJson.read_file(MANIFEST_PATH, parse)
	if not (d is Dictionary):
		errors.append("bad voice manifest: %s" % ", ".join(parse))
		return false
	_base = ODJson.string(d, "base", _base)
	_lines = ODJson.dict(d, "lines")
	_by_location = ODJson.dict(d, "byLocation")
	_count = ODJson.dict(d, "countIn")
	_efforts = ODJson.dict(d, "efforts")
	_by_text.clear()
	for id: Variant in _lines:
		var l: Dictionary = _lines[id]
		_by_text[_text_key(str(l.get("character", "")), str(l.get("text", "")))] = str(id)
	return true


static func _text_key(who: String, text: String) -> String:
	return who.to_lower().strip_edges() + "|" + text.strip_edges()


## Manifest id for an id, a story location or (who, text); "" when unknown.
func resolve(key: String, who: String = "") -> String:
	if _lines.has(key):
		return key
	if _by_location.has(key):
		return str(_by_location[key])
	var tk := _text_key(who, key)
	if who != "" and _by_text.has(tk):
		return str(_by_text[tk])
	# The box may name Tolliver "tolliver"; the manifest uses "tolly".
	if who.to_lower() == "tolliver" and _by_text.has(_text_key("tolly", key)):
		return str(_by_text[_text_key("tolly", key)])
	return ""


func has_line(key: String, who: String = "") -> bool:
	return resolve(key, who) != ""


## Seconds of audio for a line (0 when it has none). With `radio`, Tolliver's comms take.
func line_duration(key: String, who: String = "", radio: bool = false) -> float:
	var id := resolve(key, who)
	if id == "":
		return 0.0
	var l: Dictionary = _lines[id]
	if radio and l.get("radio") is Dictionary:
		return float((l["radio"] as Dictionary).get("duration", 0.0))
	return float(l.get("duration", 0.0))


func _line_file(id: String, radio: bool) -> String:
	var l: Dictionary = _lines[id]
	if radio and l.get("radio") is Dictionary:
		return str((l["radio"] as Dictionary).get("file", ""))
	return str(l.get("file", ""))


func _stream(rel: String) -> AudioStream:
	if rel == "":
		return null
	if _streams.has(rel):
		return _streams[rel]
	var path := _base + rel
	var st: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	_streams[rel] = st
	return st


## Plays a dialogue line; returns its duration (0 = nothing played: unknown id or voices not on).
## Hold the text box for at least duration + LINE_HOLD_PAD. A new line replaces the current one.
func play_line(key: String, who: String = "", radio: bool = false, now: float = NAN) -> float:
	if mode != MODE_ON:
		return 0.0
	var id := resolve(key, who)
	if id == "":
		return 0.0
	var st := _stream(_line_file(id, radio))
	if st == null:
		return 0.0
	var t := _now() if is_nan(now) else now
	# Never over a bark: the line wins.
	_stop_player(_bark_player)
	_bark_end = -INF
	if _line_player != null:
		_line_player.stream = st
		_line_player.volume_db = 0.0
		_line_player.play()
	_line_fade_from = -1.0
	var dur := line_duration(id, "", radio)
	_line_end = t + dur
	started += 1
	return dur


## Stops the current line with a short fade (early advance / skip).
func stop_line(now: float = NAN) -> void:
	var t := _now() if is_nan(now) else now
	if _line_end > t:
		_line_fade_from = t
		_line_end = t + LINE_STOP_FADE


## A bark for `event_key` (the dialogue system's bark key: "idle", "selfDeath", "bossRecall"...):
## plays only if barks and voices are on, no line is playing, the rate limits allow it and the
## coin says so (about half of eligible events). Returns the duration played (0 = suppressed).
## `force` skips the coin (the caller already decided this bark is shown).
func play_bark(key: String, event_key: String, who: String = "moxie", force: bool = false, now: float = NAN) -> float:
	var t := _now() if is_nan(now) else now
	if not bark_allowed(event_key, t):
		suppressed_barks += 1
		return 0.0
	var id := resolve(key, who)
	if id == "" or id == _last_bark_id:
		suppressed_barks += 1
		return 0.0
	if not force and _rng.randf() >= BARK_CHANCE:
		suppressed_barks += 1
		return 0.0
	var st := _stream(_line_file(id, false))
	if st == null:
		return 0.0
	if _bark_player != null:
		_bark_player.stream = st
		_bark_player.volume_db = 0.0
		_bark_player.play()
	var dur := line_duration(id)
	_bark_end = t + dur
	_last_bark_at = t
	_last_bark_id = id
	_last_by_key[event_key] = t
	started += 1
	return dur


## The rate limits alone (VOICE-CAST 6, dialogue step 4).
func bark_allowed(event_key: String, now: float) -> bool:
	if mode != MODE_ON or not barks_enabled:
		return false
	if _line_end > now or _bark_end > now:
		return false
	var urgent := BARK_URGENT_KEYS.has(event_key)
	if not urgent and now - _last_bark_at < BARK_GAP:
		return false
	if now - float(_last_by_key.get(event_key, -INF)) < BARK_SAME_KEY_GAP:
		return false
	return true


## Which speech is sounding now (KIND_*), for ducking.
func speaking(now: float) -> int:
	if _line_end > now:
		return KIND_LINE
	if _bark_end > now:
		return KIND_BARK
	return KIND_NONE


# ───────────────────────────── count-in ─────────────────────────────

const _COUNT_WORDS: Dictionary = {5: "five", 6: "six", 7: "seven", 8: "eight"}


## The take used for a count-in at `bpm`: {intensity, take, files: {n: entry}, longest, rate}. One
## take for all four words. `longest` is the tightest word of the take as it will be played: from its
## vowel (on the beat) to its end, plus the lead-in of the word that follows (which starts its own
## vowelOnset before the next beat). A take fits when that leaves COUNT_GAP of silence inside a beat.
##
## Among the takes that fit as recorded, the longest-spoken one. When none fits (the words are 346 to
## 381 ms: at 150 bpm a beat is 400 ms) the take that needs the least help is played slightly fast
## (`rate` > 1, the players' pitch_scale) so the words stay apart; `files` then carries the durations
## and vowel onsets as played, so the vowels still land on the beat. The speed-up is capped at
## COUNT_MAX_RATE (VOICE-CAST 6.4: beyond about two semitones the voice changes); above the campaign
## tempos the words simply run closer together. `called` for the boss floor and the finale.
func count_take(bpm: float, called: bool) -> Dictionary:
	var beat := 60.0 / maxf(20.0, bpm)
	var room := beat - COUNT_GAP
	var intensity := "called" if called else "spoken"
	var best: Dictionary = {}
	var best_len := -1.0
	var shortest: Dictionary = {}
	var shortest_len := INF
	for take: int in [1, 2, 3]:
		var files := {}
		for n: int in _COUNT_WORDS:
			var e := _count_entry(_COUNT_WORDS[n], intensity, take)
			if e.is_empty():
				break
			files[n] = e
		if files.size() != _COUNT_WORDS.size():
			continue
		var longest := 0.0
		for n: int in files:
			var e: Dictionary = files[n]
			# The last word is followed by the take's downbeat, not by another word.
			var lead_in := float((files[n + 1] as Dictionary).get("vowelOnset", 0.0)) if files.has(n + 1) else 0.0
			longest = maxf(longest, float(e.get("duration", 0.0)) - float(e.get("vowelOnset", 0.0)) + lead_in)
		var cand := {"intensity": intensity, "take": take, "files": files, "longest": longest, "rate": 1.0}
		if longest < shortest_len:
			shortest_len = longest
			shortest = cand
		if longest <= room and longest > best_len:
			best_len = longest
			best = cand
	if not best.is_empty() or shortest.is_empty():
		return best
	# Nothing fits as recorded: play the shortest take just fast enough (every time in it scales).
	var rate := clampf(shortest_len / maxf(0.05, room - 0.001), 1.0, COUNT_MAX_RATE)
	var fitted := {}
	for n: int in shortest["files"]:
		var e: Dictionary = (shortest["files"][n] as Dictionary).duplicate()
		e["duration"] = float(e.get("duration", 0.0)) / rate
		e["vowelOnset"] = float(e.get("vowelOnset", 0.0)) / rate
		fitted[n] = e
	shortest["files"] = fitted
	shortest["longest"] = shortest_len / rate
	shortest["rate"] = rate
	return shortest


func _count_entry(word: String, intensity: String, take: int) -> Dictionary:
	var w: Variant = _count.get(word)
	if not (w is Dictionary):
		return {}
	var list: Variant = (w as Dictionary).get(intensity)
	if not (list is Array):
		return {}
	for e: Variant in list:
		if e is Dictionary and int((e as Dictionary).get("take", 0)) == take:
			var st := _stream(str((e as Dictionary).get("file", "")))
			return e if st != null else {}
	return {}


## True when a recorded word exists for count n (else the synthesised count plays).
func has_count_word(n: int, bpm: float, called: bool) -> bool:
	if mode == MODE_OFF:
		return false
	var take := count_take(bpm, called)
	return not take.is_empty() and (take["files"] as Dictionary).has(n)


## Count-in word n (5..8). On n = 5 the take is chosen and all four words are queued on the beat
## grid starting now; later calls only re-anchor if the queue was lost. Returns true when Moxie
## speaks it (false: fall back to the synthesised word).
func count_in(n: int, bpm: float, called: bool, now: float) -> bool:
	if mode == MODE_OFF or not _COUNT_WORDS.has(n):
		return false
	if n == 5 or _count_take.is_empty() or now - _count_anchor > 6.0 * _count_beat:
		_count_take = count_take(bpm, called)
		if _count_take.is_empty():
			return false
		_count_beat = 60.0 / maxf(20.0, bpm)
		_count_anchor = now - float(n - 5) * _count_beat
		_pending.clear()
		var files: Dictionary = _count_take["files"]
		var rate := float(_count_take.get("rate", 1.0))
		for k: int in range(n, 9):
			var e: Dictionary = files[k]
			var target := _count_anchor + float(k - 5) * _count_beat
			# The word starts vowelOnset early so the vowel is on the beat.
			_pending.append([target - float(e.get("vowelOnset", 0.0)), _stream(str(e["file"])), COUNT_GAIN_DB, k, rate])
	return true


## Drops queued count words (the take was abandoned during the count-in).
func cancel_count_in() -> void:
	_pending.clear()
	_count_take = {}
	for p: AudioStreamPlayer in _count_players:
		_stop_player(p)


func pending_count_words() -> int:
	return _pending.size()


# ───────────────────────────── efforts ─────────────────────────────

## An effort for a self's event (VOICE-CAST 6.5). `group`: attack_light, attack_heavy, dodge, hit,
## death, laugh, hm. Attack efforts play on about one swing in three.
func effort(group: String, tape: int, now: float) -> bool:
	if mode != MODE_ON or tape < 0 or tape >= OD.TAPE_COUNT:
		return false
	if now - _effort_last[tape] < EFFORT_TAPE_GAP:
		return false
	if group.begins_with("attack") and _rng.randf() >= EFFORT_ATTACK_CHANCE:
		return false
	var list: Variant = _efforts.get(group)
	if not (list is Array) or (list as Array).is_empty():
		return false
	var arr: Array = list
	var i := _rng.randi_range(0, arr.size() - 1)
	if arr.size() > 1 and str((arr[i] as Dictionary).get("file", "")) == str(_effort_last_file.get(group, "")):
		i = (i + 1) % arr.size()
	var file := str((arr[i] as Dictionary).get("file", ""))
	var st := _stream(file)
	if st == null:
		return false
	_effort_last_file[group] = file
	_effort_last[tape] = now
	if _effort_players.size() > tape:
		var p := _effort_players[tape]
		p.stream = st
		p.volume_db = EFFORT_GAIN_DB
		p.pitch_scale = 1.0 + _rng.randf_range(-0.03, 0.03)
		p.play()
	started += 1
	return true


# ───────────────────────────── per frame ─────────────────────────────

func process(now: float) -> void:
	if _line_fade_from >= 0.0 and _line_player != null:
		var k := clampf((now - _line_fade_from) / LINE_STOP_FADE, 0.0, 1.0)
		_line_player.volume_db = linear_to_db(maxf(1e-4, 1.0 - k))
		if k >= 1.0:
			_stop_player(_line_player)
			_line_fade_from = -1.0
	if _pending.is_empty():
		return
	var ahead := 0.0
	if is_inside_tree():
		ahead = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	var frame := clampf(get_process_delta_time() if is_inside_tree() else 0.016, 0.004, 0.05)
	while not _pending.is_empty():
		var w: Array = _pending[0]
		var start: float = w[0]
		# Fire on the frame that lands the start closest to its target (heard = now + ahead).
		if start - (now + ahead) > frame * 0.5:
			break
		_pending.remove_at(0)
		if now + ahead - start > 0.25:
			continue
		var p := _free_count_player()
		if p != null and w[1] != null:
			p.stream = w[1]
			p.volume_db = float(w[2])
			p.pitch_scale = float(w[4])
			p.play()
			started += 1


func _free_count_player() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _count_players:
		if not p.playing:
			return p
	return _count_players[0] if not _count_players.is_empty() else null


## Everything silent at once (dispose, level change).
func stop_all() -> void:
	_pending.clear()
	_line_end = -INF
	_bark_end = -INF
	_line_fade_from = -1.0
	for p: AudioStreamPlayer in [_line_player, _bark_player]:
		_stop_player(p)
	for p: AudioStreamPlayer in _count_players:
		_stop_player(p)


static func _stop_player(p: AudioStreamPlayer) -> void:
	if p != null and p.playing:
		p.stop()


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0
