class_name FxWords
extends RefCounted
## Floating combat readouts: the word list baked into the word atlas and the momentum tiers
## (port of prototype/src/render/fx/words.ts).
##
## Tier words are graded against the momentum of a 1x standing light attack with the current loadout
## (docs/ARCHITECTURE.md "Combat": that blow is tuned to kill a 1-hit enemy), so "HIT!" means "a
## normal blow" no matter which weapon is equipped, and the bigger words show the player that speed
## and approach (MOM-01, MOM-03) are what made the difference.

const WORDS: Array[String] = [
	"TAP",
	"HIT!",
	"SMASH!",
	"CRUSH!!",
	"OVERDUB!!",
	"CLANG",
	"DESYNC",
	"RESYNC",
	"A",
	"B",
	"C",
	"D",
	"KO!",
	"BREAK!",
	"REMEMBERS",
	"PHASE",
	"CLEAR!",
]

const W_TAP := 0
const W_HIT := 1
const W_SMASH := 2
const W_CRUSH := 3
const W_OVERDUB := 4
const W_CLANG := 5
const W_DESYNC := 6
const W_RESYNC := 7
## Tape letters A..D are W_TAPE_A + tape index.
const W_TAPE_A := 8
const W_KO := 12
const W_BREAK := 13
const W_REMEMBERS := 14
const W_PHASE := 15
const W_CLEAR := 16

## Words drawn with trailing speed slashes in the atlas (the "loud" readouts).
const LOUD: Array[int] = [W_SMASH, W_CRUSH, W_OVERDUB, W_KO, W_BREAK, W_CLEAR]

## Lower bounds of each momentum tier as a multiple of the reference (1x standing light) momentum.
const TIER_THRESHOLDS: Array[float] = [0.0, 0.85, 1.6, 2.6, 4.0]


## Momentum tier 0..4 for `power` relative to `reference`.
static func momentum_tier(power: float, reference: float) -> int:
	var ref := reference if reference > 1e-6 else 1.0
	var r := maxf(0.0, power) / ref
	var tier := 0
	for i: int in range(1, TIER_THRESHOLDS.size()):
		if r >= TIER_THRESHOLDS[i]:
			tier = i
	return tier


## Atlas word index for a momentum tier.
static func tier_word(tier: int) -> int:
	return W_TAP + clampi(tier, 0, 4)
