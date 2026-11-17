# 03 — Hold the Door

Upper ruins · 2 cassettes · 0.5x / 1x / 2x · stop · 120 bpm · takes of 4 bars (8 s), horizon 8 bars ·
D Lydian, boom bap · loot: needle_rail, hush_hood

## The idea

The first overdub (Scenario B). A pressure plate holds a gate open only while somebody stands on it,
and the plate is the long way round a collapsed floor: about 28 tiles from the start, while the gate
is three tiles in front of it. Nobody can do both jobs, so one self holds and one self passes.

The second half of the idea is tape length. Every take is the same eight seconds for the player, but
a 2x tape is over at master beat 8, a 1x tape at beat 16 and a 0.5x tape at beat 32. The holder
needs to get to the plate early; the runner needs a tape that is **still running** when the gate
finally opens. The two selves want opposite speeds, and the player works that out from one failure.

```
 0  ####################     @  start, facing the gate      +  gate, open while the plate is held
 1  #..................#     p  plate (18,7)                G  grunts, asleep until the plate is pressed
 2  #..................#     e  stairs (exit), 4 x 3 tiles  (blank) the collapsed floor: no way across
 3  #..              ..#
 4  #..              ..#
 5  #..              ..#
 6  #..              ..#
 7  #..              .p#
 8  #......#############
 9  #......#..G....eeee#
10  #...@..+.......eeee#
11  #......#...G...eeee#
12  ####################
```

## Intended solution (stored in `data/levels/solutions/03-hold-the-door.json`)

| Master beat | Tape A — 2x, the holder | Tape B — 1x, the runner |
|---|---|---|
| 0 | runs west, north, east and south round the pit | walks three tiles to the gate and waits |
| 0 – 6 | (seen from B's take: A tears round the pit at double speed) | watches herself do it |
| 6.2 | steps on the plate; gate opens at 6.3; grunts wake | |
| 7.9 / 8.6 | tape ran out at 8.0: she stands on the plate for good | cuts down g1, then g2, just inside the gate |
| 12.9 | | stands on the stairs (tape ends at 16) |
| 32 | horizon: B is alive on the exit — win | |

The moment that has to land is beats 0 to 6 of take B: the player stands at a shut gate with nothing
to do except watch their own earlier run going round the pit, and the gate opens because of it.

## What a first-time player tries, and what it teaches

All of these were run with the level tools; outcomes are the game's own.

| Plan | Result | The lesson, in the game's terms |
|---|---|---|
| One tape does everything (any speed): plate, then back to the gate | FAIL. The gate shuts the moment she steps off; at 2x the tape ends on the plate at beat 8, at 0.5x she only reaches it at beat 24.7 | A plate works only while someone stands on it. It takes two. |
| Runner first, holder second | FAIL. Tape A was recorded pushing at a shut gate; when B opens it, A is still standing there and the grunts kill her at beat 12 | A tape replays what you did, not what you meant. Record the support first. |
| Both at 2x (fresh from level 02) | FAIL. Gate opens at 6.3; B kills both grunts by 7.8 and her tape ends at 8.0, 1.6 tiles inside the gate and 6.4 short of the stairs | Fast tapes run out sooner. |
| Both at 2x, B sprints past the grunts and rolls | FAIL. B freezes on the stairs at x = 15.4; both grunts walk up and kill her at beat 12 | A stopped self is a sitting duck. |
| Both at 2x, B cuts both grunts on the run and rolls | FAIL. Tape ends at x = 13.2, 1.8 tiles short | |
| Both at 1x | FAIL. Gate opens at 12.5; B kills both grunts and the tape ends at x = 8.6 | The holder was too slow, not the runner. |
| Holder 0.5x, runner 1x | FAIL. Plate pressed at beat 23.2, eight beats after B's tape ended | The slow tape belongs to whoever has to wait. |
| Holder 2x, runner 0.5x, light swings | FAIL. "too little momentum for any damage (0.50)" twice, both grunts strike at beat 12 | Level 02 in reverse: a slow tape hits soft. |

## Alternatives left open (all win)

- Holder 2x, runner 1x, two rockets from the doorstep instead of the blade (grunts dead at 8.1 and 10.2; she is on the stairs as her tape ends at 16, with almost no slack).
- Holder 2x, runner 0.5x: rocket g1 from the gate, step back three tiles while it reloads, rocket g2
  (dead at 13.1), walk to the stairs by beat 25.3. Slow and safe.
- Holder 1x, runner 0.5x, same rockets: on the stairs at beat 31.5 of 32. With a running heavy
  (momentum 1.35 at 0.5x) on g2 instead of the second rocket: beat 27.7.

## Known hole (not fixed)

Rolling is about 1.5 times faster than running (2.4 tiles in 14 ticks, again after 36). If the
holder chains rolls round the pit (plate at beat 5.05 instead of 6.18) **and** the runner hugs the
gate, cuts both grunts on the run and rolls, both tapes at 2x win with half a beat to spare. A
rolling holder with a careful runner still fails at both 2x (stops at x = 10.1) and 1x (x = 14.5,
half a tile short). I could not close this by tuning: the margin that makes the intended plan
comfortable is the same margin a 1.5x mover eats. Fixes outside my files: a gate that takes time to
open (a `relay` with a delay, which the Godot core does not have yet), or a smaller travel gain
for the roll.

## What it sets up

- 04: the old self is a collaborator standing next to you, not a ghost to watch.
- 05: a self whose tape has stopped can be killed where it stands (both 2x failures show it).
- 07 / 08: tape length on the master clock, before repeat makes a short tape useful again.

## Numbers relied on (`level.ts probe 03`)

- Run 4.5 tiles per local second; 2.05 / 4.29 tiles per master beat at 1x / 2x.
- Holder's route 28 tiles: plate at beat 6.18 (2x), 12.35 (1x), 24.7 (0.5x). At 2x she has 1.8
  beats (0.9 s) to spare, at 1x 3.6 beats.
- Runner needs 3.3 s of her own time after the gate opens (two grunts, 8.5 tiles). At 2x she has
  0.8 s, at 1x behind a 2x holder 4.8 s, at 1x behind a 1x holder 1.8 s.
- Grunt: 1.1 tiles per beat, strikes on even beats, 1 hp; a 0.5x light is 0.5 momentum = no damage.
- Robustness: `mutate` passes all 20 variants (±2 ticks, ±0.08 tiles). Godot replay matches.

## What the presentation must get right

- The pit must read as impassable at a glance and the plate must be visible across it from the
  start. Plate and gate share one accent colour (signal `plate`); a cable decor runs from the plate.
- The gate should visibly snap shut when the plate is released: take 1 has to show the player that
  stepping off closes it.
- The frozen "tape ran out" pose has to be unmistakable (deck reels stopped, self greyed or
  flagged), because two of the failures are "your tape ended here".
- The sleeping grunts must be visible through the cut-away chamber wall from the start position, so
  the player knows what opening the gate lets out.
- At 2x the review of take 1 is short; the grunts' walk toward the holder never arrives (37 tiles),
  so nothing dramatic happens there. That is fine: the failure note is "nobody reached the stairs".
