# 11 — The Archivist

Lower ruins, 90 bpm, C# Phrygian. 4 cassettes, 6-bar takes, 6-bar (24-beat) horizon, speeds 0.5 / 1 / 2 / 4,
stop / repeat / reverse. Objective: `boss` (160 hp). Files: `data/levels/11-the-archivist.json`,
`data/levels/solutions/11-the-archivist.json`.

## The idea

The Archivist cannot be hurt from the front or by whoever it is watching, and after the first take
it stops watching you: it acts on its file of every committed tape. It strikes where a tape stood
still for two beats and where a tape swung, on the beat it happened. One memory occupies it for
three beats (two to wind up, one to recover), it works through them strictly one at a time, earliest
beat first, lower cassette first on a tie, and while it is busy with a memory **that cassette holds
its attention**, alive or not.

So its memory is a blind spot you can author. Tape A is recorded to be read: a swing at nothing, in
the south-west nook, every three beats. From then on the Archivist spends the whole fight facing the
nook, punishing a self who died there on beat 2, and it never has a free slot to act on anyone else.
Everything the player was afraid of (standing on a plate, swinging from one spot) becomes safe behind
that one habit. The room keeps 3 against the music's 4: a dart launcher ticks across the hall every
three beats and the wall beside it is tagged "3/4".

## Intended solution (stored; wins in the prototype and replayed in Godot)

| Take | Speed, mode | What it does | When |
|---|---|---|---|
| A, the habit | 4x repeat | Into the nook behind the south-west pillar; one light swing at the air on beat 2 and one on beat 5 of a 6-beat loop. | nook 0.3; swings 2, 5, 8 … 23 |
| B, the doorstop | 1x stop | Stands on the call plate (east hall), which holds the stacks gate (west aisle). | plate 2.66, gate 2.77 |
| C, first blade | 2x repeat | Waits at the gate, round into the stacks behind the desk, 28 light cuts at its back; the tape wraps at beat 12 and C does it again. | first hit 5.03 |
| D, second blade | 2x repeat | The same, beside C. | first hit 5.3 |

Combined run: A is struck dead in the nook on beat 2 (by its own file) and it does not matter. The
Archivist recalls tape A at beats 0, 3, 6 … 21, without a gap; no base attack and no other memory
ever starts. Phase 2 at beat 8.3, phase 3 at 11.8, dead at beat 20.0 of 24. Survivors B, C, D.

## Naive plans (each run through the real session; outcomes as the game reports them)

| Plan | Result | Why, in the game's words |
|---|---|---|
| One tape hits it from the hall | FAIL, 160/160 | Cleaved on beat 4 ("struck by boss archivist"); a lone self always holds its eye. |
| Hold the door, hit the back (A plate, B and C blades, D bait in front), no habit | FAIL, 160/160 | "Tape A died at beat 4: struck by boss … (remembering Tape A)" on the plate, gate closes; B and C die at beat 7 to its memory of B's first swing. |
| Right selves, wrong order: blade committed before the habit | FAIL, 160/160 | The blade is the lower cassette, so it wins the tie: the Archivist turns to the stacks and kills both blades on beat 5 ("remembering Tape B"). |
| Habit recorded last | FAIL, 160/160 | The take being recorded is never on file: no memory of it, nothing looks away. |
| Right selves, wrong rhythm: habit once a bar (every 4 beats) | FAIL, 160/160 | One free beat per bar is enough: C's swing is filed into it, C and D die on beat 5 ("remembering Tape C"). |
| Habit, plate, one blade (2x repeat) | FAIL, 48 left | Not enough hands. Best three-tape line found (2x holder, reverse blade): 52 left. |
| Habit, plate, two blades on `stop` | FAIL, 48 left | A 2x tape is over after 12 beats; the fight is 24. |
| One 4x blade | FAIL, 144 left | Every 4x hit staggers it out of the memory; it turns on the blade. |

## Alternatives that win (tested)

- Blades on `reverse` instead of `repeat` (no walk back in): dead at beat 15.1.
- Two 4x repeat blades: dead at beat 11.3. Each hit wakes it, but it can only watch one of them.
- Plate first, habit second: the habit's beat-2 slot still shadows the plate-holder's dwell.
- The habit as a 1x `stop` tape with eight swings by hand (2, 5, 8 … 23).

Left open, untested: a holder who paces in front of it and never stands or swings (nothing to file),
and a habit tape that survives by leaving the nook before each landing.

## What it teaches

Commit order is a weapon; a dead tape's choreography still shapes the run; "one at a time" systems
can be saturated. Level 12 leans on the same trust in a take that dies on its own.

## Numbers relied on (`level.ts probe`, 90 bpm = 40 ticks per beat)

- Memory strike: telegraph 2 beats, recovery 1, radius 1.25 + body 0.3, walls give no shelter. A dwell
  is 3 whole-beat samples within 0.75 tiles; a swing is filed on the nearest whole beat (so the
  habit has half a beat of tolerance either way). The schedule needs landings exactly 3 beats apart.
- Back arc: push direction within 90° of its facing. The nook gives 43° (C) and 0° (D).
- 2x standing light: momentum 2, 2 damage, every 20 ticks (4 per beat). Hits of momentum 4 or more
  stagger it and cancel the memory it is winding up; a phase change during a wind-up does too.
- Blade reach 1.3 + its radius 0.9 = 2.2 from its centre; the hall side of the desk is 2.4 away.
- One 2x repeat blade deals 112 in this layout; 160 hp needs two. The stored run has 4 beats spare.
- Dart lane (row 8): the stored takes cross it more than a beat clear of any dart, every loop
  (loops are 6 and 12 beats, the launcher's period is 3).

## What the Godot presentation must get right

- A memory wind-up must be drawn in the remembered cassette's colour, at the remembered spot, and
  must look different from a reaction to a live self. It is the whole lesson (hint on tape 2).
- The Archivist visibly turns its back to the stacks while it recalls the nook; its facing has to
  read from the isometric camera.
- The health bar and the three phases; the clang of armour versus a real hit.
- The plate and the gate share a signal colour: they are a hall apart.
- The dart must sound on its 3-beat grid against the 4/4 drums (the drum track is a 3:4 polymeter).
- The west aisle (column 1, rows 3 to 5) sits behind a tall wall for the camera; nothing is required
  there except walking through. Blades work north of the open desk bay, which is not hidden.

## Known gaps

- `validate` notes that the 24-beat horizon cuts a 0.5x tape off half-way. That is deliberate: the
  fight is short so that end modes matter.
- The plan language has no loop, so each blade's 28 cuts are 28 lines in the solution.
