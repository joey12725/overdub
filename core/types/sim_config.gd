class_name SimConfig
extends RefCounted
## Everything a simulation run needs (types.ts SimConfig).

var level: LevelDef = LevelDef.new()
var loadout: ResolvedLoadout = ResolvedLoadout.new()
## Tapes to play back (already recorded).
var tapes: Array[ODTape] = []
## Present when a new take is being recorded: the live self is driven by step_local_tick.
## null for authoritative playback, where every tape (including a just-recorded one) is fixed.
var live: LiveTake = null
## The outside-the-loop boss's memory; null = none.
var boss_memory: BossMemory = null


static func make(p_level: LevelDef, p_loadout: ResolvedLoadout, p_tapes: Array[ODTape], p_live: LiveTake = null, p_boss_memory: BossMemory = null) -> SimConfig:
	var c := SimConfig.new()
	c.level = p_level
	c.loadout = p_loadout
	c.tapes = p_tapes
	c.live = p_live
	c.boss_memory = p_boss_memory
	return c


## Shallow copy: same level/loadout/tape objects, new tapes array (the prototype's `{ ...config }`).
## Use without_live() for resolveEncounter's Omit<SimConfig, 'live'>.
func copy() -> SimConfig:
	return SimConfig.make(level, loadout, tapes.duplicate(), live, boss_memory)


## Copy with `live` cleared (authoritative playback config).
func without_live() -> SimConfig:
	return SimConfig.make(level, loadout, tapes.duplicate(), null, boss_memory)


## Deep copy of every part.
func deep_copy() -> SimConfig:
	var t: Array[ODTape] = []
	for x: ODTape in tapes:
		t.append(x.copy())
	return SimConfig.make(level.copy(), loadout.copy(), t, live.copy() if live != null else null, boss_memory.copy() if boss_memory != null else null)


## Returns null and appends to `errors` when a tape is malformed.
static func from_dict(d: Dictionary, errors: Array[String] = []) -> SimConfig:
	var c := SimConfig.new()
	c.level = LevelDef.from_dict(ODJson.dict(d, "level"), errors)
	c.loadout = ResolvedLoadout.from_dict(ODJson.dict(d, "loadout"))
	for v: Variant in ODJson.array(d, "tapes"):
		var t := ODTape.from_dict(v, errors)
		if t == null:
			return null
		c.tapes.append(t)
	if d.get("live") is Dictionary:
		c.live = LiveTake.from_dict(d["live"])
	if d.get("bossMemory") is Dictionary:
		c.boss_memory = BossMemory.from_dict(d["bossMemory"])
	return c


## Tapes are written in SerializedTape form (ODTape.to_dict).
func to_dict() -> Dictionary:
	var t: Array = []
	for x: ODTape in tapes:
		t.append(x.to_dict())
	var out := {"level": level.to_dict(), "loadout": loadout.to_dict(), "tapes": t}
	if live != null:
		out["live"] = live.to_dict()
	if boss_memory != null:
		out["bossMemory"] = boss_memory.to_dict()
	return out
