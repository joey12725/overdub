class_name UiIntent
extends RefCounted
## A player intent emitted by the UI (contracts.ts UiIntent union). The game layer owns all state
## changes; the UI only emits these through UiBase's `intent` signal.
##
## `type` (UiIntentType.*) says which other fields are meaningful:
##   session      action (SessionAction.*)
##   playLevel    id (level id)
##   equip        slot (GearSlot.*), id (item id)
##   setting      key (SaveSettings key in prototype spelling, e.g. "avOffsetMs"), value (float or bool)
##   openCampaign / openLoadout / openSettings / openTitle / resume / eraseSave   nothing else

var type: StringName = &""
var action: StringName = &""
var id: String = ""
var slot: StringName = &""
var key: String = ""
## float for volume / offset settings, bool for toggles.
var value: Variant = null


static func session(p_action: StringName) -> UiIntent:
	var i := UiIntent.new()
	i.type = UiIntentType.SESSION
	i.action = p_action
	return i


## For the payload-free intents (openCampaign, openLoadout, openSettings, openTitle, resume, eraseSave).
static func simple(p_type: StringName) -> UiIntent:
	var i := UiIntent.new()
	i.type = p_type
	return i


static func play_level(p_id: String) -> UiIntent:
	var i := UiIntent.new()
	i.type = UiIntentType.PLAY_LEVEL
	i.id = p_id
	return i


static func equip(p_slot: StringName, p_id: String) -> UiIntent:
	var i := UiIntent.new()
	i.type = UiIntentType.EQUIP
	i.slot = p_slot
	i.id = p_id
	return i


static func setting(p_key: String, p_value: Variant) -> UiIntent:
	var i := UiIntent.new()
	i.type = UiIntentType.SETTING
	i.key = p_key
	i.value = p_value
	return i


## Debug text ("session:commit", "equip:melee=reel_lash").
func describe() -> String:
	match type:
		UiIntentType.SESSION:
			return "session:%s" % action
		UiIntentType.PLAY_LEVEL:
			return "playLevel:%s" % id
		UiIntentType.EQUIP:
			return "equip:%s=%s" % [slot, id]
		UiIntentType.SETTING:
			return "setting:%s=%s" % [key, value]
	return String(type)
