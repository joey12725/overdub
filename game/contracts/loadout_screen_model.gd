class_name LoadoutScreenModel
extends RefCounted
## Data for the loadout screen (contracts.ts LoadoutScreenModel).

## Owned items, catalogue order.
var inventory: Array[GearItem] = []
var loadout: Loadout = Loadout.new()
## Player-readable summary lines of the combined effects.
var summary: Array[String] = []
## Item ids picked up since the screen was last opened.
var fresh: Array[String] = []
