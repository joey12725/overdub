class_name HGChord
extends RefCounted
## The chord in force at a beat (engine `chordAt` result).

## Scale degree of the chord (0-based).
var degree: int = 0
## Pitch class of the chord root.
var root: int = 0
## Pitch classes, root first, without duplicates; inside the scale unless the state's `escape` is on.
var pcs: Array[int] = []
## Display name, e.g. "Am7".
var name: String = ""


func has_pc(pc: int) -> bool:
	return pcs.has(pc)


func to_dict() -> Dictionary:
	var ps: Array = []
	for p: int in pcs:
		ps.append(p)
	return {"degree": degree, "root": root, "pcs": ps, "name": name}
