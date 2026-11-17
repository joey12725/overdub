extends ODTest
## Save data: round trip, validation and corrupt-save recovery (never fails). Port of
## prototype/tests/game/save.test.ts, plus the file storage under user://.


## Storage whose every operation fails (the prototype's throwing storage).
class HostileStorage:
	extends GameSave.Storage


func _sample() -> SaveData:
	var s := SaveData.new()
	s.version = 1
	s.cleared = ["sandbox"]
	var inv := CampaignData.base_inventory()
	inv.append_array(["reel_lash", "needle_rail", "hush_hood"])
	s.inventory = inv
	var lo := CampaignData.base_loadout()
	lo.melee = "reel_lash"
	lo.ranged = "needle_rail"
	lo.helmet = "hush_hood"
	s.loadout = lo
	s.settings.master = 0.5
	s.settings.music = 0.25
	s.settings.sfx = 1.0
	s.settings.av_offset_ms = -40
	s.settings.screen_shake = false
	s.settings.patterns = true
	return s


func test_a_fresh_save_is_the_baseline_kit_with_nothing_cleared() -> void:
	var s := GameSave.fresh_save()
	assert_eq(s.version, 1)
	assert_eq(s.cleared.size(), 0)
	assert_json_eq(s.loadout.to_dict(), CampaignData.base_loadout().to_dict())
	var inv := s.inventory.duplicate()
	inv.sort()
	var base := CampaignData.base_inventory()
	base.sort()
	assert_eq(inv, base)
	assert_json_eq(s.settings.to_dict(), {"master": 0.8, "music": 0.8, "sfx": 0.8, "avOffsetMs": 0, "screenShake": true, "patterns": false})


func test_round_trips_through_storage_under_a_versioned_key() -> void:
	var store := GameSave.memory_storage()
	assert_true(GameSave.write_save(_sample(), store))
	assert_true(store.data.has(GameSave.SAVE_KEY))
	assert_true(GameSave.SAVE_KEY.ends_with("v1"))
	assert_json_eq(GameSave.load_save(store).to_dict(), _sample().to_dict())


func test_missing_corrupt_or_foreign_data_falls_back_to_a_fresh_save() -> void:
	var fresh := GameSave.fresh_save().to_dict()
	assert_json_eq(GameSave.load_save(GameSave.memory_storage()).to_dict(), fresh)
	for text: String in ["{not json", "null", "[1,2,3]", "42", "\"save\""]:
		var store := GameSave.memory_storage({GameSave.SAVE_KEY: text})
		assert_json_eq(GameSave.load_save(store).to_dict(), fresh, 0.0, text)
	var foreign := _sample().to_dict()
	foreign["version"] = 2
	assert_json_eq(GameSave.load_save(GameSave.memory_storage({GameSave.SAVE_KEY: JSON.stringify(foreign)})).to_dict(), fresh)
	assert_json_eq(GameSave.load_save(null).to_dict(), fresh)


func test_storage_that_fails_never_breaks_loading_or_saving() -> void:
	var hostile := HostileStorage.new()
	assert_json_eq(GameSave.load_save(hostile).to_dict(), GameSave.fresh_save().to_dict())
	assert_false(GameSave.write_save(_sample(), hostile))
	assert_false(GameSave.erase_save(hostile))
	assert_false(GameSave.write_save(_sample(), null))
	assert_false(GameSave.erase_save(null))


func test_repairs_a_damaged_save_field_by_field() -> void:
	var damaged := {
		"version": 1,
		"cleared": ["sandbox", 42, "sandbox", null],
		"inventory": ["reel_lash", "no_such_item", 7],
		"loadout": {"helmet": "hush_hood", "top": "reel_lash", "melee": "reel_lash", "shoes": 12},
		"settings": {"master": 7, "music": -1, "sfx": "loud", "avOffsetMs": 9999, "screenShake": "yes", "patterns": true},
	}
	var v := GameSave.validate_save(damaged)
	var base := CampaignData.base_loadout()
	assert_eq(v.cleared, ["sandbox"])
	assert_has(v.inventory, "reel_lash")
	assert_false(v.inventory.has("no_such_item"))
	for id: String in CampaignData.base_inventory():
		assert_has(v.inventory, id)
	# Not owned → baseline; wrong slot → baseline; owned and right slot → kept.
	assert_eq(v.loadout.helmet, base.helmet)
	assert_eq(v.loadout.top, base.top)
	assert_eq(v.loadout.melee, "reel_lash")
	assert_eq(v.loadout.shoes, base.shoes)
	assert_json_eq(v.settings.to_dict(), {"master": 1, "music": 0, "sfx": 0.8, "avOffsetMs": 300, "screenShake": true, "patterns": true})


func test_erase_removes_the_stored_save() -> void:
	var store := GameSave.memory_storage()
	GameSave.write_save(_sample(), store)
	assert_true(GameSave.erase_save(store))
	assert_json_eq(GameSave.load_save(store).to_dict(), GameSave.fresh_save().to_dict())


func test_file_storage_writes_json_under_user_and_survives_a_reload() -> void:
	var dir := "user://test_save_%d" % Time.get_ticks_usec()
	var store := GameSave.FileStorage.new(dir)
	assert_true(store.get_item(GameSave.SAVE_KEY) == null)
	assert_true(GameSave.write_save(_sample(), store))
	var path := store.path_for(GameSave.SAVE_KEY)
	assert_true(FileAccess.file_exists(path), path)
	assert_false(FileAccess.file_exists(path + ".tmp"), "no temporary file left behind")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary and int(parsed["version"]) == 1)
	# A second write replaces the first atomically.
	var s2 := _sample()
	s2.cleared.append("tutorial")
	assert_true(GameSave.write_save(s2, store))
	var again := GameSave.FileStorage.new(dir)
	assert_json_eq(GameSave.load_save(again).to_dict(), s2.to_dict())
	assert_true(GameSave.erase_save(again))
	assert_false(FileAccess.file_exists(path))
	assert_true(GameSave.erase_save(again), "erasing nothing succeeds")
	DirAccess.remove_absolute(dir)


func test_an_older_save_migrates_the_new_fields_default_and_untouched_saves_keep_the_old_format() -> void:
	# A save written before the story, Field Guide and accessibility options existed.
	var old := {
		"version": 1, "cleared": ["sandbox"], "inventory": [], "loadout": {},
		"settings": {"master": 0.5, "music": 0.8, "sfx": 0.8, "avOffsetMs": 0, "screenShake": false, "patterns": false},
	}
	var v := GameSave.validate_save(old)
	assert_eq(v.seen.size(), 0)
	assert_eq(v.codex.size(), 0)
	assert_false(v.settings.reduce_flashing)
	assert_eq(v.settings.cassette_palette, "default")
	assert_eq(v.settings.hold_mode, "hold")
	assert_true(v.settings.voices and v.settings.barks and v.settings.coach_marks)
	assert_eq(v.settings.quality, "auto")
	assert_false(v.settings.screen_shake, "the old shake switch is kept")
	# Untouched new fields are not written: the file is still the prototype's shape.
	var d := v.to_dict()
	assert_false(d.has("seen") or d.has("codex"))
	assert_eq((d["settings"] as Dictionary).keys().size(), 6)


func test_seen_flags_codex_pages_and_new_settings_round_trip_and_are_repaired() -> void:
	var s := _sample()
	s.seen = ["story.01-soft-open.intro", "coach.record", "chapter.01-soft-open"]
	s.codex = ["grunt", "breakable"]
	s.settings.reduce_flashing = true
	s.settings.cassette_palette = "high_contrast"
	s.settings.shake_scale = 0.4
	s.settings.text_scale = 1.3
	s.settings.hold_mode = "press"
	s.settings.voices = false
	s.settings.barks = false
	s.settings.coach_marks = false
	s.settings.text_speed = 2.5
	s.settings.voice_volume = 0.5
	s.settings.quality = "low"
	var store := GameSave.memory_storage()
	assert_true(GameSave.write_save(s, store))
	var back := GameSave.load_save(store)
	assert_eq(back.seen, ["chapter.01-soft-open", "coach.record", "story.01-soft-open.intro"], "sorted")
	assert_eq(back.codex, ["breakable", "grunt"])
	assert_json_eq(back.settings.to_dict(), s.settings.to_dict())
	# Damaged values fall back field by field.
	var damaged := s.to_dict()
	damaged["seen"] = ["a", 3, "a", null, "b"]
	damaged["codex"] = "grunt"
	var st: Dictionary = damaged["settings"]
	st["cassettePalette"] = "rainbow"
	st["shakeScale"] = 9.0
	st["textSpeed"] = "fast"
	st["voices"] = "no"
	st["voiceVolume"] = 4.0
	st["quality"] = 3
	var v := GameSave.validate_save(damaged)
	assert_eq(v.seen, ["a", "b"])
	assert_eq(v.codex.size(), 0)
	assert_eq(v.settings.cassette_palette, "default")
	assert_eq(v.settings.shake_scale, 1.0, "clamped into 0..1")
	assert_eq(v.settings.text_speed, 1.0)
	assert_true(v.settings.voices)
	assert_eq(v.settings.voice_volume, 1.0)
	assert_eq(v.settings.quality, "auto")
	assert_true(v.settings.reduce_flashing, "valid fields survive")
