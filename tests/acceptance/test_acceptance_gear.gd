extends ODTest
## Acceptance: equipment and the art handoff (docs/requirements.txt chapter 21: TEST-33, TEST-34;
## Revision 2: APP-TEST-01..03). Gear goes through the shipped campaign (game/campaign.gd equip ->
## resolved_loadout) and catalogue (data/gear.json); outcomes through the shipped core / GameSession.

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")


func _cat() -> ContentData.GearCatalogue:
	var errors: Array[String] = []
	var c := ContentData.load_gear(errors)
	assert_true(c != null, "data/gear.json loads: %s" % [errors])
	return c


## A campaign whose inventory holds every catalogue item (everything has been found).
func _campaign(cat: ContentData.GearCatalogue) -> GameCampaign:
	var errors: Array[String] = []
	var levels := ContentData.load_campaign(errors)
	var save := GameSave.fresh_save(cat)
	var inv: Array[String] = []
	for it: GearItem in cat.items:
		inv.append(it.id)
	save.inventory = inv
	return GameCampaign.new(levels, save, cat)


func _wins(level: LevelDef, tapes: Array[ODTape], lo: ResolvedLoadout) -> bool:
	var res := K.resolve(level, tapes, lo)
	return res != null and res.outcome.win


# ───────────────────────────── TEST-33 ─────────────────────────────


## TEST-33 - Change gear between levels.
## Expected: "Available equipment can be recombined without skill-point reallocation."
func test_TEST33_owned_gear_recombines_freely_between_levels_with_no_points_to_reallocate() -> void:
	var cat := _cat()
	if cat == null:
		return
	var c := _campaign(cat)
	# Every owned item can be put in its slot, in any combination, any number of times.
	var refused: Array[String] = []
	for pass_i: int in 2:
		for slot: StringName in OD.GEAR_SLOTS:
			for it: GearItem in cat.items_in_slot(slot):
				if not c.equip(slot, it.id):
					refused.append(it.id)
				elif c.save.loadout.get_slot(slot) != it.id:
					refused.append(it.id + " (not applied)")
	assert_eq(refused, [], K.say("TEST-33", "equipment that could not be recombined"))
	# A combination's result depends only on what is worn, never on the order or history of swaps
	# (nothing is spent, so nothing needs reallocating).
	var target := Loadout.make("click_visor", "razor_mesh", "snap_trackies", "spring_soles", "amp_sledge", "needle_rail")
	for slot: StringName in OD.GEAR_SLOTS:
		c.equip(slot, target.get_slot(slot))
	var via_history := c.resolved_loadout().to_dict()
	var fresh := _campaign(cat)
	for slot: StringName in OD.GEAR_SLOTS:
		fresh.equip(slot, target.get_slot(slot))
	assert_json_eq(via_history, fresh.resolved_loadout().to_dict(), 0.0, K.say("TEST-33", "same gear, same character, whatever was worn before"))
	# There is no skill-point or budget concept anywhere in the save or the items.
	var save_keys := c.save.to_dict().keys()
	save_keys.sort()
	assert_eq(save_keys, ["cleared", "inventory", "loadout", "settings", "version"], K.say("TEST-33", "save fields"))
	for it: GearItem in cat.items:
		var d := it.to_dict()
		for k: String in d.keys():
			assert_false(k.to_lower().contains("point") or k.to_lower().contains("cost") or k.to_lower().contains("level"), K.say("TEST-33", "%s has a '%s' field" % [it.id, k]))
	# Between levels only: while an attempt runs the loadout is locked, after it gear is free again.
	var lv := c.levels[0] if not c.levels.is_empty() else null
	if lv != null:
		assert_true(c.begin_level(lv.id))
		assert_false(c.equip(GearSlot.HELMET, "scrap_cap"), K.say("TEST-33", "gear is locked during an attempt (GEAR-03)"))
		c.end_level()
		assert_true(c.equip(GearSlot.HELMET, "scrap_cap"), K.say("TEST-33", "and free again between levels"))
		# The next level is played with the recombined loadout.
		var s := K.new_session(lv, c.resolved_loadout())
		assert_true(s != null and s.loadout.loadout.equals(c.save.loadout), K.say("TEST-33", "the session uses the chosen gear"))


# ───────────────────────────── TEST-34 ─────────────────────────────


func _glb_json(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20:
		return {}
	var json_len := bytes.decode_u32(12)
	var text := bytes.slice(20, 20 + json_len).get_string_from_utf8()
	var d: Variant = JSON.parse_string(text)
	return d if d is Dictionary else {}


func _material_color(glb: Dictionary, name: String) -> Variant:
	for m: Variant in glb.get("materials", []):
		if m is Dictionary and m.get("name") == name:
			var f: Array = (m as Dictionary).get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
			return Color(f[0], f[1], f[2]).linear_to_srgb()
	return null


func _material_color_ci(glb: Dictionary, lower_name: String) -> Variant:
	for m: Variant in glb.get("materials", []):
		if m is Dictionary and String(m.get("name", "")).to_lower() == lower_name:
			var f: Array = (m as Dictionary).get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
			return Color(f[0], f[1], f[2]).linear_to_srgb()
	return null


func _material_names(glb: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for m: Variant in glb.get("materials", []):
		names.append(String((m as Dictionary).get("name", "")).to_lower())
	return names


## True when every material of the model is textured (the parts are painted, not separate materials).
func _is_painted_model(glb: Dictionary) -> bool:
	var mats: Array = glb.get("materials", [])
	if mats.is_empty():
		return false
	for m: Variant in mats:
		var pbr: Dictionary = (m as Dictionary).get("pbrMetallicRoughness", {})
		if not pbr.has("baseColorTexture"):
			return false
	return true


## Share of a texture (sampled on a 256 x 256 grid) that is Moxie yellow; -1 when unreadable.
func _yellow_share(path: String) -> float:
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or img.is_empty():
		return -1.0
	var hit := 0
	var w := img.get_width()
	var h := img.get_height()
	for gy: int in 256:
		for gx: int in 256:
			var c := img.get_pixel(gx * w / 256, gy * h / 256)
			if c.h > 0.08 and c.h < 0.19 and c.s > 0.6 and c.v > 0.7:
				hit += 1
	return hit / 65536.0


## The painted model: clothes are the outfit zones measured from the body texture
## (tools/moxie_regions.py -> assets/models/moxie_regions.json, the data the wardrobe recolours),
## the yellow headphones are a real share of the head texture, the hair is the pigtail bones
## (checked by the caller). The painted walkman and wrist device have no data of their own: they
## are reviewed by eye (docs/ACCEPTANCE.md).
func _check_parts_of_painted_model(names: Array[String]) -> void:
	assert_true(names.has("body") and names.has("head"), K.say("TEST-34", "painted Moxie has body and head materials (got %s)" % [names]))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/moxie_regions.json"))
	var zones: Dictionary = (parsed as Dictionary).get("zones", {}) if parsed is Dictionary else {}
	for part: String in ["top", "jacket", "pants", "shoes"]:
		var z: Variant = zones.get(part)
		var texels := int((z as Dictionary).get("texels", 0)) if z is Dictionary else 0
		assert_true(texels > 0, K.say("TEST-34", "Moxie lost her '%s' (no such zone in the body texture)" % part))
	var yellow := _yellow_share("res://assets/models/moxie_head.png")
	assert_true(yellow > 0.02, K.say("TEST-34", "the headphones are yellow (%.1f%% of the head texture is Moxie yellow)" % (yellow * 100.0)))


## A model with one material per part: each signature part is matched by a family of name stems
## (any one material in the family counts), and the yellowest headphone material is yellow.
func _check_parts_by_material(glb: Dictionary) -> void:
	var names: Array[String] = _material_names(glb)
	var families := {
		"headphones": ["headphone", "hp_"], "walkman": ["walkman", "cassette_player"],
		"top": ["top"], "jacket": ["jacket"], "pants": ["pants"], "shoes": ["shoe"],
		"hair": ["hair"], "wrist_device": ["wrist", "device"],
	}
	for part: String in families:
		var hit := false
		for n: String in names:
			for stem: String in families[part]:
				hit = hit or n.begins_with(stem)
		assert_true(hit, K.say("TEST-34", "Moxie lost her '%s' (materials %s)" % [part, names]))
	# The headphones are Moxie yellow: the yellowest headphone material is yellow.
	var best_hp: Variant = null
	for n: String in names:
		if n.begins_with("headphone") or n.begins_with("hp_"):
			var c0: Variant = _material_color_ci(glb, n)
			if c0 != null and (best_hp == null or absf((c0 as Color).h - 0.14) < absf((best_hp as Color).h - 0.14)) and (c0 as Color).s > 0.3:
				best_hp = c0
	if assert_true(best_hp != null, K.say("TEST-34", "a coloured headphone material")):
		var c: Color = best_hp
		assert_true(c.h > 0.08 and c.h < 0.19 and c.s > 0.6 and c.v > 0.7, K.say("TEST-34", "the headphones are yellow (got %s, hue %.2f)" % [c.to_html(false), c.h]))


## TEST-34 - Review art handoff.
## Expected: "Selected character details, isometric perspective, warm upper lighting and neon metal
## lower direction are preserved." Logic-level guards of the data that carries each one; the look
## itself is by eye (docs/ACCEPTANCE.md lists what to review against docs/reference/).
func test_TEST34_character_details_isometric_view_warm_upper_light_and_neon_metal_lower_are_preserved() -> void:
	# Selected character details: Moxie's model keeps the signature parts.
	var glb := _glb_json("res://assets/models/moxie.glb")
	if not assert_false(glb.is_empty(), K.say("TEST-34", "assets/models/moxie.glb readable")):
		return
	# docs/GODOT-PORT.md (Moxie): material names are discovered at load, not fixed, so each
	# signature part is matched by a family of name stems (any one material in the family counts).
	var names: Array[String] = []
	for m: Variant in glb.get("materials", []):
		names.append(String((m as Dictionary).get("name", "")).to_lower())
	# A model with one material per part carries its signature parts in the material names; the
	# shipping model (docs/GODOT-PORT.md, assets/LICENSES.md) is painted instead: one body and one
	# head texture, so the parts are looked for where they now live.
	if _is_painted_model(glb):
		_check_parts_of_painted_model(names)
	else:
		_check_parts_by_material(glb)
	var nodes := {}
	for n: Variant in glb.get("nodes", []):
		nodes[(n as Dictionary).get("name", "")] = true
	var pigtails := 0
	for n: String in nodes:
		if n.to_lower().begins_with("pigtail"):
			pigtails += 1
	assert_true(pigtails >= 2, K.say("TEST-34", "the scrappy pigtails"))
	# The rig keeps the SkeletonProfileHumanoid names the animation library retargets onto.
	assert_true(nodes.has("Rig"), K.say("TEST-34", "skeleton named Rig"))
	for bone: String in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]:
		assert_true(nodes.has(bone), K.say("TEST-34", "humanoid bone %s" % bone))
	# Isometric perspective: orthographic camera at yaw 45 degrees and the true-isometric pitch.
	assert_near(WorldIsoCamera.ISO_YAW, PI / 4.0, 1e-9, K.say("TEST-34", "isometric yaw"))
	assert_near(rad_to_deg(WorldIsoCamera.ISO_PITCH), 35.26, 0.5, K.say("TEST-34", "isometric pitch"))
	var cam_src := FileAccess.get_file_as_string("res://world/world_camera.gd")
	assert_true(cam_src.contains("PROJECTION_ORTHOGONAL"), K.say("TEST-34", "orthographic projection"))
	# Warm upper lighting, never a purple cast: key and fill are warm, ambient neutral-or-warm.
	var up := WorldPalette.for_theme(LevelTheme.UPPER)
	for pair: Array in [["key_light", up.key_light], ["fill", up.fill]]:
		var col: Color = pair[1]
		assert_true(col.r >= col.b and col.r >= col.g * 0.95, K.say("TEST-34", "upper %s is warm (%s)" % [pair[0], col.to_html(false)]))
	for pair: Array in [["key_light", up.key_light], ["ambient", up.ambient], ["fill", up.fill]]:
		var col2: Color = pair[1]
		var purple := col2.s > 0.12 and col2.h > 0.70 and col2.h < 0.92
		assert_false(purple, K.say("TEST-34", "upper %s has the rejected purple cast (%s)" % [pair[0], col2.to_html(false)]))
	assert_eq(up.floor_finish, WorldPalette.FINISH_STONE, K.say("TEST-34", "upper floors are stone"))
	# Neon metal lower direction: metal floors, darker ground, saturated magenta / cyan neon.
	var low := WorldPalette.for_theme(LevelTheme.LOWER)
	assert_eq(low.floor_finish, WorldPalette.FINISH_METAL, K.say("TEST-34", "lower floors are metal"))
	assert_true(low.floor_color.v < up.floor_color.v, K.say("TEST-34", "lower is darker than upper"))
	var neon := [low.neon_a, low.neon_b, low.neon_c]
	var magenta := false
	var cyan := false
	for n: Color in neon:
		magenta = magenta or (n.s > 0.5 and (n.h > 0.8 or n.h < 0.02))
		cyan = cyan or (n.s > 0.5 and n.h > 0.45 and n.h < 0.58)
	assert_true(magenta and cyan, K.say("TEST-34", "lower neon keeps magenta and cyan (%s)" % [neon]))
	# Not a side-view platformer: the reference art the review is made against is in the repo.
	for ref: String in ["R01-moxie-concept.png", "R02-moxie-sheet.png", "R03-upper-environment.png", "R04-lower-environment.png"]:
		assert_true(FileAccess.file_exists("res://docs/reference/" + ref), "reference %s present" % ref)


# ───────────────────────────── APP-TEST-01 ─────────────────────────────


## APP-TEST-01: Equip and swap a helmet, shirt, pants, and shoes; each category can demonstrably
## change a gameplay outcome. Each clothing slot gets one scenario whose WIN/LOSS flips when that
## slot's item is swapped in through the campaign's equip, and flips back when swapped out.
func test_APPTEST01_each_clothing_category_swapped_in_changes_a_gameplay_outcome() -> void:
	var cat := _cat()
	if cat == null:
		return
	var results := {}
	# Helmet - hush_hood (lowProfile): a turret at the edge of its reach no longer sees the self.
	var lp := K.golden_run("ability-low-profile-control")
	if lp.resolution != null:
		var seen_alive := func(lo: ResolvedLoadout) -> bool:
			var r := K.resolve(lp.level, lp.tapes, lo)
			return r.outcome.survivors.size() > 0
		results["helmet/hush_hood"] = _flip(cat, GearSlot.HELMET, "hush_hood", seen_alive)
	# Top - patchcord_hoodie (interact radius +0.75): a switch just beyond the baseline reach.
	var base_r := PlayerController.interact_radius(LoadoutRules.resolve_loadout(cat.base_loadout, cat))
	var ents: Array[EntityDef] = [S.switch_def("sw", 6.0 + base_r + 0.35, 5.5)]
	var sw_level := TestLevels.make_level({"speeds": [1.0], "bars": 1, "start": Vector2(6.0, 5.5), "entities": ents, "objective": S.objective(ObjectiveType.SIGNAL, "Flip the switch", [], SignalExpr.of_sig("sw"))})
	var sw_tape := S.path_tape(0, 1.0, 120, [[0, 6.0, 5.5]], [[10, ActionKind.INTERACT, 0.0]])
	var sw_tapes: Array[ODTape] = [sw_tape]
	var flips_switch := func(lo: ResolvedLoadout) -> bool: return _wins(sw_level, sw_tapes, lo)
	results["top/patchcord_hoodie"] = _flip(cat, GearSlot.TOP, "patchcord_hoodie", flips_switch)
	# Pants - parachute_pants (dodge i-frames x1.3): a dodge a little early survives the bolt.
	var dg := K.golden_run("dodge-too-early-dies")
	if dg.resolution != null:
		var still: Array[ODTape] = [S.path_tape(0, 1.0, 240, [[0, 5.0, 5.5]])]
		var death := K.first_event(K.resolve(dg.level, still, LoadoutRules.resolve_loadout(cat.base_loadout, cat)).events, SimEventType.SELF_DEATH, 0)
		if assert_true(death != null, "the undodged bolt kills"):
			var t := death.sub / 4 - 12
			var dodge_tape := S.path_tape(0, 1.0, 240, [[0, 5.0, 5.5]], [[t, ActionKind.DODGE, 0.0]])
			var dodge_tapes: Array[ODTape] = [dodge_tape]
			var survives := func(lo: ResolvedLoadout) -> bool:
				var r := K.resolve(dg.level, dodge_tapes, lo)
				return r.outcome.survivors.size() > 0
			results["pants/parachute_pants"] = _flip(cat, GearSlot.PANTS, "parachute_pants", survives)
	# Shoes - anvil_platforms (heavyStep): the heavy plate holds only under heavy steps.
	var hs := K.golden_run("ability-heavy-step")
	if hs.level != null:
		var plate_level := hs.level.copy()
		plate_level.objective = S.objective(ObjectiveType.SIGNAL, "Hold the heavy plate", [], SignalExpr.of_sig("p1"))
		var holds_plate := func(lo: ResolvedLoadout) -> bool: return _wins(plate_level, hs.tapes, lo)
		results["shoes/anvil_platforms"] = _flip(cat, GearSlot.SHOES, "anvil_platforms", holds_plate)
	for slot: String in ["helmet", "top", "pants", "shoes"]:
		var found := false
		for k: String in results:
			if k.begins_with(slot + "/"):
				found = true
				assert_eq(results[k], "flips", K.say("APP-TEST-01", "%s: %s" % [k, results[k]]))
		assert_true(found, K.say("APP-TEST-01", "no scenario ran for the %s slot" % slot))


## "flips" when the outcome is false with the baseline, true with `id` equipped through the campaign,
## and false again after swapping back; otherwise a description of what happened.
func _flip(cat: ContentData.GearCatalogue, slot: StringName, id: String, outcome: Callable) -> String:
	var c := _campaign(cat)
	var base := bool(outcome.call(c.resolved_loadout()))
	if not c.equip(slot, id):
		return "equip refused"
	var with_item := bool(outcome.call(c.resolved_loadout()))
	c.equip(slot, cat.base_loadout.get_slot(slot))
	var back := bool(outcome.call(c.resolved_loadout()))
	if not base and with_item and not back:
		return "flips"
	return "baseline %s, with %s %s, swapped back %s" % [base, id, with_item, back]


# ───────────────────────────── APP-TEST-02 ─────────────────────────────


## APP-TEST-02: Changing a clothing slot updates its displayed effect and preserves the distinction
## between equipment categories.
func test_APPTEST02_a_clothing_swap_updates_the_shown_effect_and_slots_stay_distinct() -> void:
	var cat := _cat()
	if cat == null:
		return
	var c := _campaign(cat)
	var base_summary := c.loadout_model().summary
	for slot: StringName in [GearSlot.HELMET, GearSlot.TOP, GearSlot.PANTS, GearSlot.SHOES]:
		for it: GearItem in cat.items_in_slot(slot):
			if it.id == cat.base_loadout.get_slot(slot):
				continue
			assert_false(it.effect.strip_edges().is_empty(), K.say("APP-TEST-02", "%s states its effect" % it.id))
			assert_true(c.equip(slot, it.id))
			var m := c.loadout_model()
			assert_ne(m.summary, base_summary, K.say("APP-TEST-02", "equipping %s changes the displayed effect" % it.id))
			# Only that slot changed: the other categories keep their items.
			for other: StringName in OD.GEAR_SLOTS:
				if other != slot:
					assert_eq(m.loadout.get_slot(other), cat.base_loadout.get_slot(other), K.say("APP-TEST-02", "%s changed %s" % [it.id, other]))
			assert_true(c.equip(slot, cat.base_loadout.get_slot(slot)))
			assert_eq(c.loadout_model().summary, base_summary, K.say("APP-TEST-02", "swapping back restores the shown effect"))
	# Categories stay distinct: an item never fits another slot, each slot has its own label, and
	# the loadout screen groups the inventory by slot.
	for it: GearItem in cat.items:
		for slot: StringName in OD.GEAR_SLOTS:
			if slot != it.slot:
				assert_false(c.equip(slot, it.id), K.say("APP-TEST-02", "%s accepted in the %s slot" % [it.id, slot]))
	var labels := {}
	for slot: StringName in OD.GEAR_SLOTS:
		labels[LoadoutRules.SLOT_LABEL[slot]] = slot
	assert_eq(labels.size(), OD.GEAR_SLOTS.size(), K.say("APP-TEST-02", "slot labels: %s" % [labels.keys()]))
	var m2 := c.loadout_model()
	for it: GearItem in m2.inventory:
		assert_true(it.slot in OD.GEAR_SLOTS)


# ───────────────────────────── APP-TEST-03 ─────────────────────────────


## Decode a level solution's open-loop inputs (data/levels/solutions/<id>.json "generated.inputs":
## per take {ticks, runs: [[count, moveX, moveY, aim, buttonBits], ...]}, bit i = ActionKind.ALL[i]).
## APP-TEST-03: A valid compulsory level can be completed using at least the intended baseline
## loadout available before entering it. Every campaign level is validated and then played through
## GameSession, with the baseline loadout, from its recorded solution.
func test_APPTEST03_every_compulsory_level_is_valid_and_completable_with_the_baseline_loadout() -> void:
	var cat := _cat()
	var errors: Array[String] = []
	var levels := ContentData.load_campaign(errors)
	if cat == null or not assert_false(levels.is_empty(), "campaign loads: %s" % [errors]):
		return
	var base := LoadoutRules.resolve_loadout(GameSave.fresh_save(cat).loadout, cat)
	for lv: LevelDef in levels:
		var problems: Array[String] = []
		for p: String in LevelValidator.validate_level(lv):
			if LevelValidator.is_problem(p):
				problems.append(p)
		assert_eq(problems, [] as Array[String], K.say("APP-TEST-03", "%s is a valid level" % lv.id))
		var path := "res://data/levels/solutions/%s.json" % lv.id
		var sol: Variant = ODJson.read_file(path, errors) if FileAccess.file_exists(path) else null
		if not assert_true(sol is Dictionary, K.say("APP-TEST-03", "%s has no recorded solution (%s) to prove it completable" % [lv.id, path])):
			continue
		var takes: Array = ODJson.array(sol, "takes")
		var gen := ODJson.dict(sol, "generated")
		# Each take's recorded controller input (data/levels/solutions/README.md, takes[k].inputs),
		# decoded by the shipped bot's TickScript reader.
		var inputs: Array = []
		for k0: int in takes.size():
			var bt := GameBot.take_from_dict(takes[k0], "%s.takes[%d]" % [lv.id, k0], errors) if takes[k0] is Dictionary else null
			if not assert_true(bt != null and bt.controller is GameBot.TickScript, K.say("APP-TEST-03", "%s take %d has recorded inputs (%s)" % [lv.id, k0 + 1, errors])):
				inputs = []
				break
			inputs.append(bt.controller)
		if inputs.is_empty():
			continue
		var sol_lo := Loadout.from_dict(ODJson.dict(gen, "loadout"))
		assert_true(sol_lo.equals(cat.base_loadout), K.say("APP-TEST-03", "%s's solution uses the baseline loadout" % lv.id))
		var s := K.new_session(lv, base)
		if not assert_true(s != null):
			continue
		var ok := true
		for k: int in inputs.size():
			var take: Dictionary = takes[k] if k < takes.size() else {}
			K.set_speed(s, ODJson.num(take, "speed", 1.0))
			var want := OD.end_mode_from_name(ODJson.string(take, "endMode", "stop"))
			var guard := 0
			while s.end_mode != want and guard < 4:
				s.act(SessionAction.CYCLE_END_MODE)
				guard += 1
			if not s.act(SessionAction.RECORD):
				ok = false
				break
			K.advance_until_phase_changes(s, 10.0)
			var feed: GameBot.TickScript = inputs[k]
			var t := 0
			while s.phase == SessionPhase.RECORDING:
				s.tick_local(feed.input(t))
				t += 1
			if s.phase == SessionPhase.CINEMATIC:
				break
			K.advance_until_phase_changes(s)
			if k < inputs.size() - 1 and not s.act(SessionAction.COMMIT):
				ok = false
				break
		assert_true(ok, "%s: the solution's takes could be recorded" % lv.id)
		assert_eq(s.phase, SessionPhase.CINEMATIC, K.say("APP-TEST-03", "%s completed with the baseline loadout (outcome %s)" % [lv.id, ReplayVerifier.outcome_key(s.resolution.outcome) if s.resolution != null else "none"]))
	# The sandbox's prototype-recorded bot solution also completes on the port.
	var g := K.golden_run("sandbox-bot-solo")
	if g.resolution != null:
		assert_true(g.resolution.outcome.win, K.say("APP-TEST-03", "the sandbox bot solution (baseline loadout) wins on the port"))
