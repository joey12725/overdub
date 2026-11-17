class_name ResultsModel
extends RefCounted
## Data for the results screen (contracts.ts ResultsModel).

var level: LevelDef = null
var outcome: Outcome = null
var tapes_used: int = 0
var loot: Array[GearItem] = []
var has_next: bool = false
## Id of the next level on the path; "" = absent. When present, "Next level" emits a playLevel intent
## with this id; when absent it emits session 'continue' (back to the path, focused on the next level).
var next_id: String = ""
