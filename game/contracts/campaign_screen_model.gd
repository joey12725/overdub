class_name CampaignScreenModel
extends RefCounted
## Data for the campaign path screen (contracts.ts CampaignScreenModel).

## Every level in campaign order.
var levels: Array[CampaignLevelEntry] = []
## Index (into `levels`) of the next uncleared level.
var current: int = 0
