extends SceneTree
## Loads the voice manifest through VoiceBank and checks every listed stream imports and matches
## the manifest (rate, mono, length). Exits non-zero on any failure.
##   bash tools/gd script res://art/voice/check_voice_bank.gd


func _init() -> void:
	var fails := 0
	var vb := VoiceBank.new()
	if not vb.load_manifest():
		printerr("manifest did not load")
		quit(1)
		return
	var checked := 0
	for kind: String in ["count", "effort"]:
		for id: String in vb.ids(kind):
			var s := vb.stream(id)
			var wav := s as AudioStreamWAV
			if wav == null:
				printerr("not a WAV stream: ", id)
				fails += 1
				continue
			checked += 1
			if wav.mix_rate != 44100 or wav.stereo or wav.format != AudioStreamWAV.FORMAT_16_BITS:
				printerr("format: ", id, " rate ", wav.mix_rate, " stereo ", wav.stereo, " fmt ", wav.format)
				fails += 1
			if absf(wav.get_length() - vb.duration_sec(id)) > 0.002:
				printerr("length: ", id, " ", wav.get_length(), " vs ", vb.duration_sec(id))
				fails += 1
			if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
				printerr("loops: ", id)
				fails += 1
	for style: StringName in [VoiceBank.STYLE_NORMAL, VoiceBank.STYLE_WHISPER, VoiceBank.STYLE_SHOUT]:
		vb.begin_count(style)
		var line := ""
		for n: int in [5, 6, 7, 8]:
			var id := vb.count_id(n)
			if id == "" or vb.stream(id) == null:
				printerr("no count take: ", style, " ", n)
				fails += 1
			line += "%s(onset %.3f, %+.1f dB) " % [id, vb.onset_sec(id), vb.gain_db(id)]
		print(style, ": ", line)
	vb.begin_count(VoiceBank.STYLE_NORMAL)
	for midi: int in [48, 60, 61, 71, 127]:
		for n: int in [5, 6, 7, 8]:
			var id := vb.count_id(n, midi)
			if not id.ends_with(".p%d" % (55 + posmod(midi - 55, 12))) or vb.stream(id) == null:
				printerr("pitched lookup: ", midi, " ", n, " -> ", id)
				fails += 1
	if vb.count_id(4) != "" or vb.count_id(9, 60) != "":
		printerr("out-of-range count should be empty")
		fails += 1
	for kind: StringName in [VoiceBank.EFFORT_ATTACK_LIGHT, VoiceBank.EFFORT_ATTACK_HEAVY, VoiceBank.EFFORT_DODGE,
			VoiceBank.EFFORT_HIT, VoiceBank.EFFORT_DEATH, VoiceBank.EFFORT_LAUGH, VoiceBank.EFFORT_HM, VoiceBank.EFFORT_SIGH]:
		var a := vb.effort_id(kind)
		var b := vb.effort_id(kind)
		if a == "" or vb.stream(a) == null:
			printerr("no effort: ", kind)
			fails += 1
		if kind == VoiceBank.EFFORT_ATTACK_LIGHT and a == b:
			printerr("effort repeated: ", kind)
			fails += 1
	if vb.bark_stream("countIn", 0) != null:
		printerr("bark audio is not expected to exist yet")
		fails += 1
	print("voice bank: %d streams checked, %d failures" % [checked, fails])
	quit(1 if fails > 0 else 0)
