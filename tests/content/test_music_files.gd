extends ODTest
## The composer's music files (data/music/<id>.json, docs/MUSIC.md) load through ContentData /
## CampaignData with the extras the audio layer reads (state maps, SFX pitch sets, layers, the menu
## bed), and agree with the level files and with the prototype's loader
## (prototype/src/content/musicFiles.ts, prototype/tests/content/music.test.ts).


func test_every_campaign_level_and_the_menu_have_a_music_file() -> void:
	for id: String in ContentData.list_level_ids():
		var errors: Array[String] = []
		var f := ContentData.load_music_file(id, errors)
		if not assert_true(f != null, "%s: %s" % [id, "; ".join(errors)]):
			continue
		assert_eq(f.id, id)
		assert_eq(f.music.tracks.size(), 4, "%s: four cassette layers" % id)
		assert_eq(f.layers.size(), 4, "%s: a layer description per cassette" % id)
		for k in 4:
			assert_eq(ODJson.string(f.layers[k], "role"), String(f.music.tracks[k].role), "%s: layer %d describes cassette %d" % [id, k + 1, k + 1])
	var menu := CampaignData.menu_music()
	if assert_true(menu != null, "data/music/menu.json loads"):
		var bed: Array = ODJson.array(menu.bed, "tracks")
		assert_eq(bed.size(), 4, "the menu bed gives a state per cassette")
		assert_eq(menu.bpm, 72.0, "the menu bed runs at 72 bpm (docs/MUSIC.md)")


func test_state_maps_and_sfx_pitch_sets_are_carried_for_the_audio_layer() -> void:
	for id: String in ContentData.list_level_ids():
		var f := CampaignData.music_file(id)
		if not assert_true(f != null, id):
			continue
		for state: String in ["dead", "desynced", "reversing", "stopped"]:
			assert_true(f.state_map(state) != null, "%s: stateMaps.%s (OPEN-22)" % [id, state])
		assert_eq(ODJson.array(f.state_maps, "order"), ["dead", "desynced", "reversing", "stopped"], "%s: maps apply in the documented order" % id)
		assert_false(ODJson.dict(f.sfx, "classes").is_empty(), "%s: sfx.classes (MUSIC-05)" % id)
		assert_false(ODJson.string(f.sfx, "palette").is_empty(), "%s: sfx.palette" % id)
		assert_false(ODJson.dict(f.sfx, "latency").is_empty(), "%s: sfx.latency (OPEN-23)" % id)
		var some_class: String = ODJson.dict(f.sfx, "classes").keys()[0]
		assert_false(f.sfx_class(some_class).is_empty(), "%s: sfx_class() reads a class" % id)


func test_the_level_file_plays_the_composers_music_and_the_level_keeps_its_tempo() -> void:
	for lv: LevelDef in CampaignData.levels():
		var f := CampaignData.music_file(lv.id)
		if not assert_true(f != null, lv.id):
			continue
		assert_eq(f.bpm, lv.bpm, "%s: bpm belongs to the level; the piece was composed at it" % lv.id)
		assert_eq(lv.music.to_dict(), f.music.to_dict(), "%s: run python -I art/music/merge.py --write" % lv.id)
		# The block the Godot loader parses is the raw block the prototype imports, field for field.
		var raw: Variant = ODJson.read_file("res://data/music/%s.json" % lv.id)
		assert_eq(f.music.to_dict(), ODJson.dict(raw, "music"), "%s: LevelMusicDef carries every field of the composer's block" % lv.id)


func test_malformed_ids_and_missing_files_are_reported_not_loaded() -> void:
	var errors: Array[String] = []
	assert_true(ContentData.load_music_file("../gear", errors) == null)
	assert_true(ContentData.load_music_file("no-such-piece", errors) == null)
	assert_eq(errors.size(), 2, str(errors))
