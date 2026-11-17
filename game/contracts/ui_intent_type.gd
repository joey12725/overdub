class_name UiIntentType
extends RefCounted
## UiIntent.type (contracts.ts UiIntent union discriminator).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## UiIntent.action holds a SessionAction.
const SESSION: StringName = &"session"
const OPEN_CAMPAIGN: StringName = &"openCampaign"
const OPEN_LOADOUT: StringName = &"openLoadout"
const OPEN_SETTINGS: StringName = &"openSettings"
const OPEN_TITLE: StringName = &"openTitle"
## UiIntent.id holds the level id.
const PLAY_LEVEL: StringName = &"playLevel"
## UiIntent.slot + UiIntent.id.
const EQUIP: StringName = &"equip"
## UiIntent.key (SaveSettings key, prototype spelling) + UiIntent.value (float or bool).
const SETTING: StringName = &"setting"
const RESUME: StringName = &"resume"
const ERASE_SAVE: StringName = &"eraseSave"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	SESSION,
	OPEN_CAMPAIGN,
	OPEN_LOADOUT,
	OPEN_SETTINGS,
	OPEN_TITLE,
	PLAY_LEVEL,
	EQUIP,
	SETTING,
	RESUME,
	ERASE_SAVE,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
