class_name AudioChordInfo
extends RefCounted
## The chord in force at a master beat (director.ts ChordInfo).

## Index into the level progression.
var index: int = 0
## Scale degree of the chord root.
var degree: int = 0
## Pitch class of the chord root.
var root: int = 0
## Pitch classes of the chord, root first.
var pcs: Array[int] = []


static func make(p_index: int, p_degree: int, p_root: int, p_pcs: Array[int]) -> AudioChordInfo:
	var c := AudioChordInfo.new()
	c.index = p_index
	c.degree = p_degree
	c.root = p_root
	c.pcs = p_pcs.duplicate()
	return c
