extends ODTest
## The project skeleton: constants, the type port's JSON round trips, the data files and the
## module facade bases. Run with `bash tools/gd test skeleton`.

## serializeTape() output of the prototype for a fixed 3-tick tape (generated with vite-node from
## prototype/src/core/tape.ts), proving byte compatibility of ODTape.to_dict / from_dict.
const PROTOTYPE_TAPE_JSON := '{"v":1,"index":2,"speed":2,"endMode":"reverse","ticks":3,"pos":"AABgQAAAsEBmZmZAZmauQKRwbUDNzKxAVVV1QJqZqUA=","facing":"AAAAAM3MzD0AACDA2w9JQA==","anim":"AAEDCw==","events":[[1,1,0.75,3.6,5.45,1.25,-0.5],[2,5,-1,3.71,5.4,0,0]]}'


# ───────────────────────────── helpers ─────────────────────────────

## Drop keys whose value is a JSON "empty" (0, false, "", [], {}), recursively. The port's to_dict()
## omits optional fields at their absent-default (startFacing: 0, bossRecall: false...), so original
## JSON and round-tripped JSON are compared after stripping both.
func _strip(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			var x: Variant = _strip(v[k])
			if not _is_empty_json(x):
				out[k] = x
		return out
	if v is Array:
		var out: Array = []
		for x: Variant in v:
			out.append(_strip(x))
		return out
	return v


func _is_empty_json(v: Variant) -> bool:
	if v is bool:
		return not v
	if v is int or v is float:
		return float(v) == 0.0
	if v is String or v is StringName:
		return String(v).is_empty()
	if v is Array:
		return (v as Array).is_empty()
	if v is Dictionary:
		return (v as Dictionary).is_empty()
	return v == null


## to_dict -> JSON text -> parse -> from_dict -> to_dict must reproduce the first to_dict exactly.
func _json_cycle(d: Dictionary) -> Dictionary:
	return JSON.parse_string(ODJson.stringify(d))


# ───────────────────────────── constants ─────────────────────────────

func test_constants_match_prototype() -> void:
	assert_eq(OD.SUB_HZ, 240)
	assert_eq(OD.LOCAL_HZ, 60)
	assert_eq(OD.BEATS_PER_BAR, 4)
	assert_eq(OD.FRAME_SUBS, 4)
	assert_eq(OD.TAPE_COUNT, 4)
	assert_eq(OD.ALL_SPEEDS, [0.5, 1.0, 2.0, 4.0])
	assert_eq(OD.TAPE_COLORS, ["#ff4d6d", "#ffd23f", "#3ec5ff", "#7dff6b"])
	assert_eq(OD.TAPE_NAMES, ["A", "B", "C", "D"])
	assert_eq(OD.tape_color(2), Color("#3ec5ff"))
	assert_eq(OD.tape_letter(3), "D")
	assert_eq(OD.GEAR_SLOTS, ["helmet", "top", "pants", "shoes", "melee", "ranged"])
	assert_eq(OD.GEAR_SLOTS, GearSlot.ALL)
	assert_eq(OD.ANIM_STATES, AnimState.ALL)
	assert_eq(OD.ANIM_STATES.size(), 12)
	assert_eq(OD.ANIM_STATES[3], AnimState.LIGHT_ACTIVE)
	assert_eq(String(AnimState.LIGHT_ACTIVE), "lightActive")


func test_time_03_subs_per_local_tick_every_speed() -> void:
	var expected := {0.5: 8, 1.0: 4, 2.0: 2, 4.0: 1}
	for s: float in OD.ALL_SPEEDS:
		assert_eq(OD.subs_per_local_tick(s), expected[s], "speed %s" % s)
		assert_true(OD.is_speed(s))
	assert_false(OD.is_speed(3.0))
	assert_false(OD.is_speed(0.0))


func test_enum_names_round_trip() -> void:
	assert_eq(OD.END_MODE_NAMES, ["stop", "repeat", "reverse"])
	for m: int in OD.ALL_END_MODES:
		assert_eq(OD.end_mode_from_name(OD.end_mode_name(m)), m)
	assert_eq(OD.end_mode_from_name("bounce"), -1)
	assert_eq(OD.end_mode_name(-1), "")
	assert_eq(OD.LIFE_STATE_NAMES, ["alive", "recGhost", "ghost"])
	assert_eq(OD.life_state_from_name("recGhost"), OD.LifeState.REC_GHOST)
	assert_eq(OD.life_state_name(OD.LifeState.GHOST), "ghost")


func test_vocabularies_match_prototype_unions() -> void:
	assert_eq(ActionKind.ALL, ["light", "heavy", "dodge", "ranged", "interact", "ability"])
	assert_eq(AbilityId.ALL.size(), 10)
	assert_has(AbilityId.ALL, &"manualDesync")
	assert_eq(RangedArchetype.SELF, ["missile", "pierce", "phase", "arc", "burst"])
	assert_has(RangedArchetype.ALL, &"bolt")
	assert_has(RangedArchetype.ALL, &"shock")
	assert_eq(EnemyType.ALL, ["grunt", "stalker", "turret", "shielder", "brute", "drone", "boss"])
	assert_eq(EnemyStateName.ALL, ["asleep", "idle", "move", "telegraph", "attack", "stagger", "dead"])
	assert_eq(EntityKind.ALL.size(), 9)
	assert_eq(DecorType.ALL.size(), 18)
	assert_eq(String(DecorType.TIME_MACHINE), "timeMachine")
	assert_eq(MechKind.ALL.size(), 7)
	assert_eq(SimEventType.ALL.size(), 29)
	assert_eq(String(SimEventType.PROJECTILE_HIT), "projectileHit")
	assert_eq(SessionPhase.ALL.size(), 8)
	assert_eq(DeckStatus.ALL.size(), 6)
	assert_eq(SessionAction.ALL.size(), 12)
	assert_eq(String(SessionAction.CONTINUE), "continue")
	assert_eq(FailReason.ALL, ["objective", "noSurvivor"])
	assert_eq(LevelTheme.ALL, ["upper", "mid", "lower", "core"])
	assert_eq(ObjectiveType.ALL, ["eliminate", "reach", "activate", "boss", "signal"])
	assert_eq(ViewMode.ALL, ["record", "review", "cinematic", "idle"])
	assert_eq(UiScreen.ALL.size(), 8)
	assert_eq(UiIntentType.ALL.size(), 10)
	assert_true(SimEventType.has(&"tapeWrap"))
	assert_false(SimEventType.has(&"tape_wrap"))


func test_json_stringify_round_trips_doubles() -> void:
	var values: Array[float] = [PI, 0.1, 1e-7, 1.5e-12, 123456789.123, -2.5, 3.5999999046325684, 0.30000000000000004, 8.0]
	for f: float in values:
		var back: Variant = JSON.parse_string(ODJson.format_float(f))
		assert_true(back is float and back == f, "%s -> %s" % [String.num(f, 17), ODJson.format_float(f)])
	var data := {"b": [PI, {"x": 0.1, "n": null, "t": true}], "a": "q\"uote", "i": 3, "e": [], "o": {}}
	var text := ODJson.stringify(data, "  ")
	assert_has(text, "3.1415926535897931")
	assert_true(text.find("\"b\"") < text.find("\"a\""), "insertion order kept")
	assert_json_eq(JSON.parse_string(text), data)
	assert_json_eq(JSON.parse_string(ODJson.stringify(data)), data)
	assert_eq(ODJson.stringify(PackedFloat32Array([0.5, 2.0])), "[0.5,2.0]")


# ───────────────────────────── tape & input ─────────────────────────────

func test_player_input_round_trip() -> void:
	var i := PlayerInput.make(0.5, -1.0, 2.25)
	i.heavy = true
	i.ability = true
	var back := PlayerInput.from_dict(_json_cycle(i.to_dict()))
	assert_json_eq(back.to_dict(), i.to_dict())
	assert_true(back.heavy and back.ability and not back.light)
	var c := i.copy()
	c.clear()
	assert_eq(c.move_x, 0.0)
	assert_false(c.heavy)
	assert_eq(c.aim, 2.25)
	assert_true(i.heavy, "copy is independent")


func test_tape_event_round_trip() -> void:
	var e := TapeEvent.make(7, ActionKind.RANGED, 1.5, 3.25, 4.0, -0.5, 2.0)
	assert_json_eq(TapeEvent.from_dict(_json_cycle(e.to_dict())).to_dict(), e.to_dict())
	assert_eq(e.to_tuple(), [7, 3, 1.5, 3.25, 4.0, -0.5, 2.0])
	assert_true(TapeEvent.from_tuple(e.to_tuple()).equals(e))
	var errors: Array[String] = []
	assert_eq(TapeEvent.from_tuple([1, 9, 0, 0, 0, 0, 0], errors), null)
	assert_has(errors[0], "bad action kind")


func test_tape_phase_round_trip() -> void:
	var p := TapePhase.make(12.5, -1, 2, false)
	var back := TapePhase.from_dict(_json_cycle(p.to_dict()))
	assert_true(back.equals(p))
	assert_true(p.copy().equals(p))


func test_tape_reads_prototype_serialized_tape() -> void:
	var errors: Array[String] = []
	var t := ODTape.from_dict(JSON.parse_string(PROTOTYPE_TAPE_JSON), errors)
	if not assert_true(t != null, "parse failed: %s" % [errors]):
		return
	assert_eq(t.index, 2)
	assert_eq(t.speed, 2.0)
	assert_eq(t.end_mode, OD.EndMode.REVERSE)
	assert_eq(t.ticks, 3)
	# Float32 values exactly as the prototype's Float32Array holds them.
	assert_eq(t.pos, [3.5, 5.5, 3.5999999046325684, 5.449999809265137, 3.7100000381469727, 5.400000095367432, 3.8333332538604736, 5.300000190734863])
	assert_eq(t.facing, [0.0, 0.10000000149011612, -2.5, 3.1415927410125732])
	assert_eq(t.anim, [0, 1, 3, 11])
	assert_eq(t.events.size(), 2)
	assert_eq(t.events[0].kind, ActionKind.HEAVY)
	assert_eq(t.events[1].kind, ActionKind.ABILITY)
	assert_eq(t.events[0].vx, 1.25)


func test_tape_writes_prototype_serialized_tape() -> void:
	var t := ODTape.create(2, 2.0, OD.EndMode.REVERSE, 3)
	var pos: Array[float] = [3.5, 5.5, 3.6, 5.45, 3.71, 5.4, 3.8333333, 5.3]
	for k in pos.size():
		t.pos[k] = pos[k]
	t.facing = PackedFloat32Array([0.0, 0.1, -2.5, PI])
	t.anim = PackedByteArray([0, 1, 3, 11])
	t.events.append(TapeEvent.make(1, ActionKind.HEAVY, 0.75, 3.6, 5.45, 1.25, -0.5))
	t.events.append(TapeEvent.make(2, ActionKind.ABILITY, -1.0, 3.71, 5.4, 0.0, 0.0))
	assert_json_eq(t.to_dict(), JSON.parse_string(PROTOTYPE_TAPE_JSON))


func test_tape_round_trip_and_copy() -> void:
	var t := ODTape.create(1, 0.5, OD.EndMode.REPEAT, 120)
	for k in t.ticks + 1:
		t.pos[k * 2] = 1.0 + k * 0.013
		t.pos[k * 2 + 1] = 2.0 - k * 0.007
		t.facing[k] = sin(k * 0.1)
		t.anim[k] = k % OD.ANIM_STATES.size()
	t.events.append(TapeEvent.make(30, ActionKind.DODGE, 0.3, 1.39, 1.79, 4.0, 0.0))
	var back := ODTape.from_dict(_json_cycle(t.to_dict()))
	if not assert_true(back != null):
		return
	assert_eq(back.pos, t.pos)
	assert_eq(back.facing, t.facing)
	assert_eq(back.anim, t.anim)
	assert_json_eq(back.to_dict(), t.to_dict())
	var c := t.copy()
	c.pos[0] = 99.0
	c.events[0].tick = 31
	assert_eq(t.pos[0], 1.0, "copy() is deep (pos)")
	assert_eq(t.events[0].tick, 30, "copy() is deep (events)")


func test_tape_rejects_malformed_input() -> void:
	var good: Dictionary = JSON.parse_string(PROTOTYPE_TAPE_JSON)
	var cases := {
		"unsupported version": {"v": 2},
		"bad ticks": {"ticks": 1.5},
		"array lengths": {"ticks": 4},
		"bad character": {"anim": "AA*DCw=="},
		"multiple of 4": {"anim": "AAEDC"},
		"bad endMode": {"endMode": "bounce"},
		"bad action kind": {"events": [[1, 6, 0, 0, 0, 0, 0]]},
	}
	for want: String in cases:
		var d := good.duplicate(true)
		d.merge(cases[want], true)
		var errors: Array[String] = []
		assert_eq(ODTape.from_dict(d, errors), null, want)
		assert_true(errors.size() > 0 and errors[0].contains(want), "%s: got %s" % [want, errors])


# ───────────────────────────── equipment ─────────────────────────────

func test_stat_mods_identity_keys_and_round_trip() -> void:
	var m := StatMods.new()
	assert_eq(StatMods.keys().size(), 16)
	assert_eq(m.to_dict(), {})
	assert_eq(m.to_dict(true).size(), 16)
	assert_eq(m.get_stat("interactRadiusAdd"), 0.0)
	assert_eq(m.get_stat("moveSpeed"), 1.0)
	assert_true(StatMods.is_additive("interactRadiusAdd"))
	assert_false(StatMods.is_additive("damage"))
	m.set_stat("moveSpeed", 0.92)
	m.set_stat("interactRadiusAdd", 0.75)
	assert_eq(m.move_speed, 0.92)
	assert_eq(m.to_dict(), {"moveSpeed": 0.92, "interactRadiusAdd": 0.75})
	var back := StatMods.from_dict(_json_cycle(m.to_dict(true)))
	assert_json_eq(back.to_dict(true), m.to_dict(true))
	assert_eq(m.copy().interact_radius_add, 0.75)


func test_weapon_defs_round_trip() -> void:
	var r := RangedWeaponDef.new()
	r.archetype = RangedArchetype.ARC
	r.max_range = 7.0
	r.has_min_range = true
	r.min_range = 3.0
	var d := r.to_dict()
	assert_true(d.has("range") and d.has("minRange") and not d.has("radius"))
	var back := RangedWeaponDef.from_dict(_json_cycle(d))
	assert_true(back.has_min_range and not back.has_radius)
	assert_json_eq(back.to_dict(), d)
	var m := MeleeWeaponDef.new()
	m.light.windup = 6.0
	m.heavy.impact = 1.8
	m.style = MeleeStyle.WHIP
	var mb := MeleeWeaponDef.from_dict(_json_cycle(m.to_dict()))
	assert_json_eq(mb.to_dict(), m.to_dict())
	var mc := m.copy()
	mc.light.windup = 9.0
	assert_eq(m.light.windup, 6.0, "copy() is deep")


func test_loadout_and_resolved_loadout() -> void:
	var l := Loadout.make("a", "b", "c", "d", "e", "f")
	assert_eq(l.get_slot(GearSlot.SHOES), "d")
	l.set_slot(GearSlot.MELEE, "reel_lash")
	assert_eq(l.melee, "reel_lash")
	assert_eq(l.ids(), ["a", "b", "c", "d", "reel_lash", "f"])
	assert_true(Loadout.from_dict(_json_cycle(l.to_dict())).equals(l))
	var r := ResolvedLoadout.new()
	r.loadout = l
	r.abilities = [AbilityId.PARRY]
	r.looks[GearSlot.TOP] = GearLook.from_dict({"color": "#25212b", "variant": "bomber"})
	var back := ResolvedLoadout.from_dict(_json_cycle(r.to_dict()))
	assert_json_eq(back.to_dict(), r.to_dict())
	assert_true(back.has_ability(AbilityId.PARRY))
	assert_eq(back.looks[GearSlot.TOP].variant, "bomber")
	assert_eq(back.looks[GearSlot.TOP].color_or(Color.BLACK), Color("#25212b"))


func test_save_data_round_trip() -> void:
	var s := SaveData.new()
	s.cleared = ["sandbox"]
	s.inventory = ["scrap_cap", "reel_lash"]
	s.loadout = Loadout.make("scrap_cap", "lined_bomber", "olive_cargos", "beater_hightops", "reel_lash", "mixtape_rocket")
	s.settings.av_offset_ms = -40
	s.settings.patterns = true
	var back := SaveData.from_dict(_json_cycle(s.to_dict()))
	assert_json_eq(back.to_dict(), s.to_dict())
	assert_eq(back.version, 1)
	# Defaults are the prototype's DEFAULT_SETTINGS.
	var fresh := SaveSettings.new()
	assert_eq(fresh.to_dict(), {"master": 0.8, "music": 0.8, "sfx": 0.8, "avOffsetMs": 0, "screenShake": true, "patterns": false})
	assert_true(fresh.set_by_key("avOffsetMs", 12.6))
	assert_eq(fresh.av_offset_ms, 13)
	assert_true(fresh.set_by_key("screenShake", false))
	assert_false(fresh.set_by_key("screenShake", 1.0))
	assert_false(fresh.set_by_key("volume", 1.0))
	assert_eq(fresh.get_by_key("screenShake"), false)
	# A foreign / partial save keeps defaults where fields are missing.
	var partial := SaveData.from_dict({"version": 1, "settings": {"sfx": 0.25}})
	assert_eq(partial.settings.sfx, 0.25)
	assert_eq(partial.settings.music, 0.8)


# ───────────────────────────── level data ─────────────────────────────

func test_signal_expr_every_op_round_trips() -> void:
	var cases: Array = [
		{"sig": "lever"},
		{"not": {"sig": "plate"}},
		{"and": [{"sig": "a"}, {"const": true}]},
		{"or": []},
		{"xor": [{"sig": "a"}, {"not": {"sig": "b"}}]},
		{"const": false},
		{"beat": {"every": 4, "from": 0, "to": 2}},
	]
	for c: Dictionary in cases:
		var errors: Array[String] = []
		var e := SignalExpr.from_dict(c, errors)
		if not assert_true(e != null, "%s: %s" % [c, errors]):
			continue
		assert_json_eq(e.to_dict(), c)
		assert_json_eq(e.copy().to_dict(), c)
	var bad: Array[String] = []
	assert_eq(SignalExpr.from_dict({"nand": []}, bad), null)
	assert_eq(SignalExpr.from_dict({"xor": [{"sig": "a"}]}, bad), null)
	assert_eq(bad.size(), 2)
	var built := SignalExpr.of_and([SignalExpr.of_sig("x"), SignalExpr.of_not(SignalExpr.of_beat(2.0, 0.0, 1.0))])
	assert_eq(built.op, SignalExpr.Op.AND)
	assert_json_eq(built.to_dict(), {"and": [{"sig": "x"}, {"not": {"beat": {"every": 2, "from": 0, "to": 1}}}]})


func test_every_entity_kind_round_trips() -> void:
	var cases: Array = [
		{"kind": "enemy", "id": "b", "type": "boss", "x": 4.5, "y": 2.5, "facing": 1.5, "hp": 30, "beat": {"every": 2, "offset": 1}, "arc": 3.0, "wakeWhen": {"sig": "door"}},
		{"kind": "enemy", "id": "g", "type": "grunt", "x": 1.5, "y": 1.5},
		{"kind": "door", "id": "gate", "cells": [{"c": 5, "r": 3}, {"c": 5, "r": 4}], "openWhen": {"sig": "lever"}},
		{"kind": "switch", "id": "lever", "x": 3.5, "y": 1.5, "initial": true},
		{"kind": "plate", "id": "p", "c": 1, "r": 8, "heavy": true},
		{"kind": "breakable", "id": "w", "c": 5, "r": 7, "threshold": 3},
		{"kind": "laser", "id": "beam", "from": {"x": 6.5, "y": 6.5}, "to": {"x": 12.5, "y": 6.5}, "onWhen": {"not": {"sig": "plate"}}},
		{"kind": "core", "id": "c1", "x": 2.5, "y": 2.5, "threshold": 2},
		{"kind": "core", "id": "c2", "x": 3.5, "y": 2.5},
		{"kind": "exit", "id": "exit", "c": 10, "r": 1, "w": 2, "h": 3},
		{"kind": "decor", "type": "graffiti", "x": 7.5, "y": 0.6, "rot": 2, "variant": "MOX"},
	]
	for c: Dictionary in cases:
		var errors: Array[String] = []
		var e := LevelDef.entity_from_dict(_json_cycle(c), errors)
		if not assert_true(e != null and errors.is_empty(), "%s: %s" % [c, errors]):
			continue
		assert_eq(e.kind, StringName(c["kind"]))
		assert_json_eq(e.to_dict(), c)
		assert_json_eq(e.copy().to_dict(), c)
	var en := LevelDef.entity_from_dict(cases[1]) as EnemyDef
	assert_false(en.has_hp or en.has_beat or en.has_arc)
	assert_eq(en.wake_when, null)
	var core2 := LevelDef.entity_from_dict(cases[8]) as CoreDef
	assert_false(core2.has_threshold)
	var errors2: Array[String] = []
	assert_eq(LevelDef.entity_from_dict({"kind": "teleporter"}, errors2), null)
	assert_has(errors2[0], "unknown entity kind")


func test_objective_and_music_round_trip() -> void:
	var o := {"type": "signal", "targets": ["a", "b"], "when": {"sig": "x"}, "text": "Do it"}
	assert_json_eq(ObjectiveDef.from_dict(_json_cycle(o)).to_dict(), o)
	var m := {"root": 9, "scale": "Dorian", "progression": [0, 3, 0, 4], "chordBars": 2, "tracks": [
		{"role": "bass", "formula": "fibonacci", "params": {"m": 7}},
		{"role": "drums", "formula": "groove", "params": {"genre": 2, "voice": 0, "density": 1}, "genre": "Boom bap"},
		{"role": "melody", "formula": "lissajous"},
		{"role": "chord", "formula": "voicelead", "params": {"voices": 4}},
	]}
	assert_json_eq(LevelMusicDef.from_dict(_json_cycle(m)).to_dict(), m)


# ───────────────────────────── sim output ─────────────────────────────

func test_snapshots_round_trip() -> void:
	var f := FrameSnapshot.new()
	f.sub = 400
	f.beat = 3.333
	var a := ActorSnap.new()
	a.tape = 1
	a.live = true
	a.anim = AnimState.HEAVY_WINDUP
	a.life = OD.LifeState.REC_GHOST
	a.synced = false
	a.has_spark = true
	a.spark = Vector2(2.5, 3.5)
	a.phase = TapePhase.make(80.5, -1, 1, false)
	f.actors.append(a)
	var e := EnemySnap.new()
	e.id = "boss"
	e.type = EnemyType.BOSS
	e.hp = 20
	e.max_hp = 30
	e.state = EnemyStateName.TELEGRAPH
	e.target = 0
	e.boss_phase = 2
	e.boss_recall = true
	e.boss_recall_tape = 3
	e.has_boss_recall_at = true
	e.boss_recall_at = Vector2(4.0, 5.0)
	f.enemies.append(e)
	var s := EnemySnap.new()
	s.id = "s1"
	s.type = EnemyType.SHIELDER
	s.has_shield = true
	s.shield = false
	f.enemies.append(s)
	var p1 := ProjectileSnap.new()
	p1.id = 3
	p1.owner_tape = 2
	p1.archetype = RangedArchetype.MISSILE
	p1.target_id = "boss"
	var p2 := ProjectileSnap.new()
	p2.id = 4
	p2.owner_enemy = "t1"
	f.projectiles.append(p1)
	f.projectiles.append(p2)
	var m := MechSnap.new()
	m.id = "gate"
	m.has_t = true
	m.t = 0.5
	f.mechs.append(m)
	f.objective.progress = 0.5
	f.objective.survivors = 2
	var d := f.to_dict()
	assert_json_eq(d["projectiles"][0]["owner"], {"tape": 2})
	assert_json_eq(d["projectiles"][1]["owner"], {"enemy": "t1"})
	assert_eq(d["enemies"][1]["shield"], false, "an explicit shield:false survives")
	assert_false(d["enemies"][1].has("target"), "target -1 is omitted")
	assert_eq(d["actors"][0]["life"], "recGhost")
	var back := FrameSnapshot.from_dict(_json_cycle(d))
	assert_json_eq(back.to_dict(), d)
	assert_json_eq(f.copy().to_dict(), d)
	assert_eq(back.actor(1).spark, Vector2(2.5, 3.5))
	assert_eq(back.enemy("boss").boss_recall_tape, 3)
	assert_eq(back.mech("gate").t, 0.5)
	assert_false(back.projectiles[1].is_self_owned())


func test_events_outcome_resolution_round_trip() -> void:
	var ev := SimEvent.make(12, SimEventType.HIT, 1.0, 2.0).with_tape(0).with_id("g1").with_dir(0.0).with_power(1.8).with_detail("heavy")
	var plain := SimEvent.make(13, SimEventType.STEP, 1.0, 2.0)
	assert_eq(plain.to_dict(), {"sub": 13, "type": "step", "x": 1.0, "y": 2.0})
	assert_true(ev.to_dict().has("dir"), "dir 0 is kept when set")
	var o := Outcome.new()
	o.objective_complete = true
	o.survivors = [0, 2]
	o.reason = FailReason.NO_SURVIVOR
	o.notes = ["Tape A died at beat 9"]
	var r := Resolution.new()
	r.outcome = o
	r.events = [ev, plain]
	r.frames = [FrameSnapshot.new(), FrameSnapshot.new()]
	r.frames[1].sub = 4
	r.horizon_subs = 8
	var d := r.to_dict()
	var back := Resolution.from_dict(_json_cycle(d))
	assert_json_eq(back.to_dict(), d)
	assert_json_eq(r.copy().to_dict(), d)
	assert_eq(back.frame_at_sub(5).sub, 4)
	assert_eq(back.frame_at_sub(-3).sub, 0)
	assert_eq(back.events[0].power, 1.8)


func test_boss_memory_and_sim_config_round_trip() -> void:
	var bm := BossMemory.new()
	var ob := BossObservation.new()
	ob.tape = 1
	ob.speed = 2.0
	ob.samples = [BossSample.make(0.0, 3.5, 5.5), BossSample.make(0.5, 3.6, 5.4)]
	ob.has_actions = true
	ob.actions = [BossMemoryAction.make(1.25, 3.6, 5.4, ActionKind.HEAVY)]
	bm.observed.append(ob)
	var ob2 := BossObservation.new()
	bm.observed.append(ob2)
	var bd := bm.to_dict()
	assert_false(bd["observed"][1].has("actions"), "absent actions stay absent")
	assert_json_eq(BossMemory.from_dict(_json_cycle(bd)).to_dict(), bd)
	var cfg := SimConfig.new()
	cfg.level = LevelDef.from_dict({"id": "t", "map": ["###", "#.#", "###"], "start": {"x": 1.5, "y": 1.5}, "speeds": [1], "endModes": ["stop"]})
	cfg.tapes = [ODTape.create(0, 1.0, OD.EndMode.STOP, 2)]
	cfg.live = LiveTake.make(1, 0.5, OD.EndMode.REVERSE)
	cfg.boss_memory = bm
	var cd := cfg.to_dict()
	var errors: Array[String] = []
	var back := SimConfig.from_dict(_json_cycle(cd), errors)
	if not assert_true(back != null, str(errors)):
		return
	assert_json_eq(back.to_dict(), cd)
	assert_eq(back.live.end_mode, OD.EndMode.REVERSE)
	assert_eq(cfg.without_live().live, null)
	assert_json_eq(cfg.deep_copy().to_dict(), cd)


func test_session_view_defaults() -> void:
	var v := SessionView.new()
	assert_eq(v.decks.size(), OD.TAPE_COUNT)
	assert_eq(v.decks[3].index, 3)
	assert_eq(v.active, -1)
	assert_eq(v.decks[0].speed, 0.0, "no speed = 0.0")
	assert_eq(v.decks[0].end_mode, -1)
	v.objective = ObjectiveView.make(ObjectiveSnap.new(), "Break the wall")
	var c := v.copy()
	assert_eq(c.objective.text, "Break the wall")
	assert_eq(c.decks.size(), OD.TAPE_COUNT)


# ───────────────────────────── data files ─────────────────────────────

func test_gear_file_loads_cleanly() -> void:
	var errors: Array[String] = []
	var cat := ContentData.load_gear(errors)
	if not assert_true(cat != null and errors.is_empty(), str(errors)):
		return
	assert_eq(cat.items.size(), 37)
	assert_eq(cat.items[0].id, "scrap_cap", "catalogue order is kept")
	assert_eq(cat.base_loadout.to_dict(), {"helmet": "scrap_cap", "top": "lined_bomber", "pants": "olive_cargos", "shoes": "beater_hightops", "melee": "splice_blade", "ranged": "mixtape_rocket"})
	assert_eq(cat.base_inventory().size(), 6)
	for slot: StringName in GearSlot.ALL:
		assert_true(cat.items_in_slot(slot).size() >= 5, "slot %s" % slot)
	for it: GearItem in cat.items:
		assert_eq(it.melee != null, it.slot == GearSlot.MELEE, "%s melee def" % it.id)
		assert_eq(it.ranged != null, it.slot == GearSlot.RANGED, "%s ranged def" % it.id)
		assert_false(it.name.is_empty() or it.effect.is_empty() or it.lore.is_empty(), it.id)
		for a: StringName in it.abilities:
			assert_true(AbilityId.has(a), "%s ability %s" % [it.id, a])
		if it.ranged != null:
			assert_true(RangedArchetype.SELF.has(it.ranged.archetype), it.id)
	var blade := cat.get_item("splice_blade")
	assert_eq(blade.melee.light.impact, 1.0)
	assert_eq(blade.melee.heavy.windup, 16.0)
	var arc := cat.get_item("bass_drop")
	assert_true(arc.ranged.lobbed and arc.ranged.has_min_range)
	assert_eq(arc.ranged.min_range, 3.0)
	assert_eq(cat.get_item("rabbit_ears").mods.spark_speed, 1.4)
	assert_eq(cat.get_item("nope"), null)
	# Every item writes back exactly what the file holds.
	var raw: Dictionary = load_json(ContentData.GEAR_PATH)
	var i := 0
	for it: GearItem in cat.items:
		assert_json_eq(it.to_dict(), raw["items"][i], 0.0, it.id)
		assert_json_eq(it.copy().to_dict(), raw["items"][i], 0.0, it.id + " copy")
		i += 1


func test_sandbox_level_loads_cleanly() -> void:
	var errors: Array[String] = []
	var level := ContentData.load_level("sandbox", errors)
	if not assert_true(level != null and errors.is_empty(), str(errors)):
		return
	assert_eq(level.id, "sandbox")
	assert_eq(level.bpm, 120.0)
	assert_eq(level.bars, 8)
	assert_eq(level.horizon_bars, 16)
	assert_eq(level.max_tapes, 4)
	assert_eq(level.speeds, OD.ALL_SPEEDS)
	assert_eq(level.end_modes, OD.ALL_END_MODES)
	assert_eq(level.theme, LevelTheme.UPPER)
	assert_eq(level.map.size(), 10)
	assert_eq(level.map[0], "##############")
	assert_eq(level.start, Vector2(3.5, 5.5))
	assert_eq(level.entities.size(), 16)
	assert_eq(level.entities_of(EntityKind.ENEMY).size(), 3)
	assert_eq(level.entities_of(EntityKind.DECOR).size(), 8)
	var door := level.entities_of(EntityKind.DOOR)[0] as DoorDef
	assert_eq(door.cells, [Vector2i(5, 3)])
	assert_eq(door.open_when.op, SignalExpr.Op.SIG)
	assert_eq(door.open_when.sig, "lever")
	var laser := level.entities_of(EntityKind.LASER)[0] as LaserDef
	assert_eq(laser.on_when.op, SignalExpr.Op.NOT)
	var turret := level.entities_of(EntityKind.ENEMY)[2] as EnemyDef
	assert_eq(turret.type, EnemyType.TURRET)
	assert_true(turret.has_beat)
	assert_eq(turret.beat_every, 2)
	assert_near(turret.facing, PI, 1e-12)
	assert_eq(level.objective.type, ObjectiveType.ELIMINATE)
	assert_eq(level.music.tracks.size(), 4)
	assert_eq(level.music.tracks[1].genre, "Boom bap")
	assert_eq(level.music.tracks[2].params["phase"], 0.25)
	assert_eq(level.hints[1].left(10), "Try 2x on ")
	assert_eq(level.loot, ["reel_lash", "needle_rail", "spring_soles", "hush_hood"])
	# Round trip against the file (to_dict omits optional fields at their absent-default).
	var raw: Dictionary = load_json("res://data/levels/sandbox.json")
	assert_json_eq(_strip(level.to_dict()), _strip(raw))
	assert_json_eq(_strip(level.copy().to_dict()), _strip(raw))
	assert_json_eq(LevelDef.from_dict(_json_cycle(level.to_dict())).to_dict(), level.to_dict())
	# Every loot id exists in the catalogue.
	var cat := ContentData.load_gear()
	for id: String in level.loot:
		assert_true(cat.has_item(id), "loot %s" % id)


func test_level_index_and_bad_ids() -> void:
	var ids := ContentData.list_level_ids(true)
	assert_has(ids, "sandbox")
	var campaign := ContentData.load_campaign()
	assert_true(campaign.size() >= 1)
	for i in range(1, campaign.size()):
		assert_true(campaign[i - 1].index <= campaign[i].index, "campaign sorted by index")
	var errors: Array[String] = []
	assert_eq(ContentData.load_level("../project", errors), null)
	assert_eq(ContentData.load_level("no_such_level", errors), null)
	assert_eq(errors.size(), 2)


# ───────────────────────────── contracts ─────────────────────────────

func test_contract_data_classes() -> void:
	var i := UiIntent.setting("avOffsetMs", 20.0)
	assert_eq(i.type, UiIntentType.SETTING)
	assert_eq(i.describe(), "setting:avOffsetMs=20.0")
	assert_eq(UiIntent.session(SessionAction.COMMIT).describe(), "session:commit")
	assert_eq(UiIntent.equip(GearSlot.MELEE, "reel_lash").describe(), "equip:melee=reel_lash")
	var pulse := MusicPulse.new()
	assert_eq(pulse.levels.size(), OD.TAPE_COUNT)
	assert_eq(pulse.copy().pitches.size(), OD.TAPE_COUNT)
	var frame := RenderFrame.new()
	assert_eq(frame.mode, ViewMode.IDLE)
	assert_eq(frame.active, -1)
	assert_eq(ButtonPrompt.make("A", ButtonPrompt.STYLE_FACE_A).style, &"face-a")
	# Scene mapping: sim (x, y) -> scene (X, Z); a +Z-facing model turned by heading_to_yaw faces dir.
	assert_eq(RenderCtx.to_scene(2.0, 3.0, 1.0), Vector3(2.0, 1.0, 3.0))
	assert_eq(RenderCtx.to_sim(Vector3(2.0, 1.0, 3.0)), Vector2(2.0, 3.0))
	for dir: float in [0.0, 0.7, PI * 0.5, -2.0, PI]:
		var fwd := Basis(Vector3.UP, RenderCtx.heading_to_yaw(dir)) * Vector3(0, 0, 1)
		assert_vec_near(fwd, Vector3(cos(dir), 0.0, sin(dir)), 1e-6, "heading %s" % dir)


func test_facade_bases_are_safe_defaults() -> void:
	var audio := AudioBase.new()
	audio.unlock()
	audio.set_transport(1.0, 1.0, true)
	assert_eq(audio.pulse().beat, 0.0)
	audio.free()
	var hud := HudBase.new()
	hud.update_hud(SessionView.new(), MusicPulse.new())
	hud.free()
	var ui := UiBase.new()
	var got: Array[UiIntent] = []
	ui.intent.connect(func(x: UiIntent) -> void: got.append(x))
	ui.emit_intent(UiIntent.simple(UiIntentType.OPEN_LOADOUT))
	assert_eq(got.size(), 1)
	assert_eq(got[0].type, UiIntentType.OPEN_LOADOUT)
	ui.free()
	var view := WorldViewBase.new()
	tree().root.add_child(view)
	# Layers come from their fixed paths, or the do-nothing bases while those files do not exist.
	if not Facades.is_provided(Facades.ACTOR_LAYER_SCRIPT) and not Facades.is_provided(Facades.FX_LAYER_SCRIPT):
		view.attach_layers()
		assert_true(view.actor_layer is ActorLayerBase and view.fx_layer is FxLayerBase)
		var ctx := view.new_ctx(LevelDef.new(), ResolvedLoadout.new())
		view._load_layers(ctx)
		var frame := RenderFrame.new()
		frame.snap = FrameSnapshot.new()
		view._update_layers(frame)
		assert_eq(ctx.view, view)
		assert_eq(view.get_node(^"LevelRoot"), ctx.root)
	else:
		assert_true(true, "layer files exist; their owners test them")
	assert_eq(view.screen_up_in_world(), Vector2(0.0, -1.0))
	view.queue_free()
	await tree().process_frame


func test_facade_loader_instances_scripts_by_path() -> void:
	var good := "user://od_skeleton_probe_layer.gd"
	var wrong := "user://od_skeleton_probe_wrong.gd"
	var f := FileAccess.open(good, FileAccess.WRITE)
	f.store_string("extends ActorLayerBase\n\nvar probe: int = 7\n")
	f.close()
	f = FileAccess.open(wrong, FileAccess.WRITE)
	f.store_string("extends Node3D\n")
	f.close()
	var n := Facades._instance_script(good)
	assert_true(n is ActorLayerBase, "a script extending the base is instanced")
	assert_eq(n.get("probe"), 7)
	n.free()
	var w := Facades._instance_script(wrong)
	assert_true(w is Node3D and not (w is RenderLayerBase))
	expect_engine_errors()
	Facades._reject(w, wrong, "ActorLayerBase")
	assert_eq(Facades._instance_script("user://does_not_exist.gd"), null)
	DirAccess.remove_absolute(good)
	DirAccess.remove_absolute(wrong)
