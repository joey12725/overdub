class_name AudioVoiceEngine
extends Node
## Plays AudioTriggers through a pool of AudioStreamPlayers (sample playback with pitch_scale from
## the nearest sample), with per-group polyphony, note releases, chokes and cancellation.
##
## Timing. Godot starts a player at the next audio mix, not at an arbitrary time, so a voice
## asked to sound at heard-time T is started a little early and seeks into the silent pad every
## sample file begins with (AudioSampleBank.pad):
##
##     mix   = now + AudioServer.get_time_to_next_mix()      when the player starts consuming
##     delay = T - mix - AudioServer.get_output_latency()    how far after that it should be heard
##     from  = pad - delay * pitch_scale                     the attack lands `delay` after the mix
##
## A voice fires on the first frame where `delay` fits inside the pad, so attacks land within a
## sample of T as long as frames come at least every `pad / pitch_scale` seconds (~75 ms). If a
## frame hitch makes a voice late it starts at its attack immediately (never skipping it). The
## remaining error is the accuracy of get_time_to_next_mix() itself, plus at most one mix buffer
## when a play() call races the mix boundary; see last_error / max_error.

const POLY_LAYER := 24
const POLY_SEND := 10
const POLY_SFX := 28
const POLY_UI := 10
## Ceiling for a sustained (looping) voice that was given no length.
const MAX_SUSTAIN := 8.0
## Release used when sounding music is choked (seek, pause, take restart).
const CHOKE_RELEASE := 0.03
## Margin kept inside the pad so float error never seeks before the start of the file.
const FIRE_MARGIN := 0.004
## A one-shot that is this late (s) is no longer worth playing.
const MAX_LATE := 0.25

var bank: AudioSampleBank
## When false the engine plans and times everything but starts no players (tests, headless use
## without the sample library).
var output_enabled: bool = true

var fired: int = 0
var late: int = 0
var stolen: int = 0
var dropped: int = 0
## Predicted heard time minus target for the last fired voice (s); positive = late.
var last_error: float = 0.0
## Largest |error| of an on-time voice since reset_stats() (s).
var max_error: float = 0.0
## Largest lateness of a late voice since reset_stats() (s).
var max_late: float = 0.0
## The same, for music notes only (scheduled voices with an id); SFX and UI sounds asked for "now"
## are necessarily heard one mix plus the output latency later and are counted above only.
var music_fired: int = 0
var music_late: int = 0
var music_max_late: float = 0.0
var music_max_error: float = 0.0
## The first late music voices since reset_stats(): [target time, lateness, family, now at fire].
var late_log: Array = []
## When true, every music voice is measured once just after its attack: Godot's own playback
## position (get_playback_position() + get_time_since_last_mix() - get_output_latency(), the sync
## method of the Godot docs) gives when the attack is heard, compared with its target time.
var measure: bool = false
var measured: int = 0
var measured_sum: float = 0.0
var measured_sq: float = 0.0
var measured_max: float = 0.0

var _free: Array[AudioStreamPlayer] = []
var _pending: Array[_Voice] = []
var _active: Array[_Voice] = []
var _group_count: Dictionary = {}
var _group_limit: Dictionary = {}


class _Voice:
	extends RefCounted
	var id: int = 0
	var group: StringName = &""
	var bus: StringName = &""
	var family: StringName = &""
	var pick: AudioSampleBank.Pick
	## Target heard time (s, listening clock).
	var time: float = 0.0
	## Seconds held before release (<= 0 = play out).
	var dur: float = 0.0
	var release: float = 0.05
	var gain: float = 1.0
	var player: AudioStreamPlayer
	## Heard start time actually achieved (predicted).
	var heard: float = 0.0
	## Wall time the release fade starts / the voice can be recycled.
	var release_wall: float = INF
	var end_wall: float = INF
	var fade: float = 1.0
	var measured: bool = false


func _init(p_bank: AudioSampleBank = null) -> void:
	bank = p_bank
	for i: int in OD.TAPE_COUNT:
		_group_limit[_layer_group(i)] = POLY_LAYER
		_group_limit[_send_group(i)] = POLY_SEND
	_group_limit[&"sfx"] = POLY_SFX
	_group_limit[&"ui"] = POLY_UI


func _ready() -> void:
	var total := 0
	for g: StringName in _group_limit:
		total += int(_group_limit[g])
	for i: int in total:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_free.append(p)


static func _layer_group(i: int) -> StringName:
	return StringName("layer%d" % i)


static func _send_group(i: int) -> StringName:
	return StringName("send%d" % i)


func reset_stats() -> void:
	fired = 0
	late = 0
	stolen = 0
	dropped = 0
	last_error = 0.0
	max_error = 0.0
	max_late = 0.0
	music_fired = 0
	music_late = 0
	music_max_late = 0.0
	music_max_error = 0.0
	late_log.clear()
	measured = 0
	measured_sum = 0.0
	measured_sq = 0.0
	measured_max = 0.0


func pending_count() -> int:
	return _pending.size()


func active_count() -> int:
	return _active.size()


## Queues triggers whose offsets are relative to `base_time` (heard time). `id` > 0 lets music
## notes be cancelled; SFX use 0.
func schedule(triggers: Array[AudioTrigger], base_time: float, id: int = 0) -> void:
	if bank == null:
		return
	for t: AudioTrigger in triggers:
		var fam := bank.family(t.family)
		if fam == null:
			dropped += 1
			continue
		var bus: StringName
		var group: StringName
		match t.dest:
			AudioTrigger.DEST_LAYER:
				var ch := clampi(t.channel, 0, OD.TAPE_COUNT - 1)
				bus = AudioBusSetup.LAYERS[ch]
				group = _layer_group(ch)
			AudioTrigger.DEST_UI:
				bus = AudioBusSetup.UI
				group = &"ui"
			_:
				bus = AudioBusSetup.SFX_PAN[t.channel] if t.channel >= 0 and t.channel < OD.TAPE_COUNT else AudioBusSetup.SFX
				group = &"sfx"
		var v := _make_voice(t, fam, base_time, id, bus, group)
		if v == null:
			continue
		_insert_pending(v)
		if t.dest == AudioTrigger.DEST_LAYER and t.send > 0.0:
			var ch2 := clampi(t.channel, 0, OD.TAPE_COUNT - 1)
			var s := _make_voice(t, fam, base_time, id, AudioBusSetup.SENDS[ch2], _send_group(ch2))
			if s != null:
				s.gain = t.gain * t.send
				# The send copy uses the same sample and pitch so the reverb hears the same note.
				s.pick = v.pick
				_insert_pending(s)


func _make_voice(t: AudioTrigger, fam: AudioSampleBank.Family, base_time: float, id: int, bus: StringName, group: StringName) -> _Voice:
	var pick := bank.pick(t.family, t.pitch)
	if pick == null or pick.sample == null:
		dropped += 1
		return null
	var v := _Voice.new()
	v.id = id
	v.group = group
	v.bus = bus
	v.family = t.family
	v.pick = pick
	v.time = base_time + t.offset
	v.dur = t.dur
	if v.dur <= 0.0 and fam.loop:
		v.dur = MAX_SUSTAIN
	v.release = t.release if t.release > 0.0 else fam.release
	v.gain = clampf(t.gain, 0.0, 2.0)
	return v


func _insert_pending(v: _Voice) -> void:
	# Keep pending sorted by time (binary insertion; stable for equal times).
	var lo := 0
	var hi := _pending.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if _pending[mid].time <= v.time:
			lo = mid + 1
		else:
			hi = mid
	_pending.insert(lo, v)


## Drops not-yet-audible voices of a music note (scheduler cancellation).
func cancel(id: int, now: float) -> void:
	if id <= 0:
		return
	var kept: Array[_Voice] = []
	for v: _Voice in _pending:
		if v.id != id:
			kept.append(v)
	_pending = kept
	for v: _Voice in _active.duplicate():
		if v.id == id and v.heard > now:
			_retire(v)


## Quickly releases every sounding music voice (layers and their sends).
func choke_music(now: float) -> void:
	for v: _Voice in _active:
		if String(v.group).begins_with("layer") or String(v.group).begins_with("send"):
			if v.release_wall > now:
				v.release_wall = now
				v.release = minf(v.release, CHOKE_RELEASE)


## Stops everything (level change, dispose). Pending voices are dropped, sounding ones fade fast.
func stop_all(now: float) -> void:
	_pending.clear()
	for v: _Voice in _active:
		if v.release_wall > now:
			v.release_wall = now
			v.release = minf(v.release, 0.02)


## Call every frame. `now` is the listening clock; mix timing comes from the AudioServer.
func process(now: float) -> void:
	var mix := now + AudioServer.get_time_to_next_mix()
	var lat := AudioServer.get_output_latency()
	var pad := bank.pad if bank != null else 0.1
	# Fire.
	while not _pending.is_empty():
		var v: _Voice = _pending[0]
		var ps := v.pick.pitch_scale
		var delay := v.time - mix - lat
		if delay > pad / maxf(1.0, ps) - FIRE_MARGIN:
			break
		_pending.remove_at(0)
		if delay < -MAX_LATE and v.dur <= 0.0:
			dropped += 1
			continue
		_fire(v, now, mix, lat, pad, delay)
	# Release and recycle.
	var i := 0
	while i < _active.size():
		var v: _Voice = _active[i]
		if measure and not v.measured and v.id > 0 and v.player != null and now >= v.heard + 0.02:
			_measure(v, now, lat, pad)
		if now >= v.release_wall:
			var k := (now - v.release_wall) / maxf(0.005, v.release)
			if k >= 1.0:
				_retire(v)
				continue
			v.fade = exp(-6.9 * k)
			if v.player != null:
				v.player.volume_db = linear_to_db(maxf(1e-5, v.gain * v.fade))
		if now >= v.end_wall:
			_retire(v)
			continue
		i += 1


func _fire(v: _Voice, now: float, mix: float, lat: float, pad: float, delay: float) -> void:
	var ps := v.pick.pitch_scale
	var from := pad - delay * ps
	if from > pad:
		from = pad
	if from < 0.0:
		from = 0.0
	v.heard = mix + lat + (pad - from) / ps
	var err := v.heard - v.time
	last_error = err
	if err > 0.002:
		late += 1
		max_late = maxf(max_late, err)
	else:
		max_error = maxf(max_error, absf(err))
	fired += 1
	if v.id > 0:
		music_fired += 1
		if err > 0.002:
			music_late += 1
			music_max_late = maxf(music_max_late, err)
			if late_log.size() < 64:
				late_log.append([v.time, err, v.family, now])
		else:
			music_max_error = maxf(music_max_error, absf(err))
	var length := float(v.pick.sample.frames) / float(bank.sample_rate) if bank != null else 1.0
	var natural := (length - from) / ps
	if v.dur > 0.0:
		v.release_wall = v.heard + v.dur - lat
	v.end_wall = v.heard - lat + natural + 0.02
	if v.family != &"" and bank.family(v.family).loop:
		v.end_wall = INF
	if not output_enabled or v.pick.sample.stream == null:
		v.player = null
		_track(v)
		return
	var p := _take_player(v.group, now)
	if p == null:
		dropped += 1
		return
	v.player = p
	p.stream = v.pick.sample.stream
	p.bus = v.bus
	p.pitch_scale = ps
	p.volume_db = linear_to_db(maxf(1e-5, v.gain))
	p.play(from)
	_track(v)


func _measure(v: _Voice, now: float, lat: float, pad: float) -> void:
	v.measured = true
	if now > v.heard + 0.4 or not v.player.playing:
		return
	var ps := v.pick.pitch_scale
	var heard_pos := v.player.get_playback_position() + (AudioServer.get_time_since_last_mix() - lat) * ps
	if heard_pos <= pad:
		return
	var err := (now - (heard_pos - pad) / ps) - v.time
	measured += 1
	measured_sum += err
	measured_sq += err * err
	measured_max = maxf(measured_max, absf(err))


## [mean, sd, max |error|] of the measured music attacks (seconds).
func measured_stats() -> Array[float]:
	if measured == 0:
		return [0.0, 0.0, 0.0]
	var mean := measured_sum / measured
	return [mean, sqrt(maxf(0.0, measured_sq / measured - mean * mean)), measured_max]


func _track(v: _Voice) -> void:
	_active.append(v)
	_group_count[v.group] = int(_group_count.get(v.group, 0)) + 1


func _take_player(group: StringName, now: float) -> AudioStreamPlayer:
	var limit: int = _group_limit.get(group, 16)
	if int(_group_count.get(group, 0)) >= limit:
		_steal(group, now)
	if _free.is_empty():
		_steal(&"", now)
	if _free.is_empty():
		return null
	return _free.pop_back()


## Frees the voice that matters least: already releasing first, then the oldest.
func _steal(group: StringName, now: float) -> void:
	var best: _Voice = null
	for v: _Voice in _active:
		if group != &"" and v.group != group:
			continue
		if best == null:
			best = v
			continue
		var v_rel := now >= v.release_wall
		var b_rel := now >= best.release_wall
		if (v_rel and not b_rel) or (v_rel == b_rel and v.heard < best.heard):
			best = v
	if best != null:
		stolen += 1
		_retire(best)


func _retire(v: _Voice) -> void:
	var idx := _active.find(v)
	if idx >= 0:
		_active.remove_at(idx)
		_group_count[v.group] = maxi(0, int(_group_count.get(v.group, 1)) - 1)
	if v.player != null:
		v.player.stop()
		_free.append(v.player)
		v.player = null
