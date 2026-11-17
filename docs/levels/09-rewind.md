# 09 — Rewind

Lower levels, 120 bpm, F minor (0 3 0 4, two bars a chord), the composer's block from
`data/music/09-rewind.json`: a bass that reads the same backwards under a triangle lead. Four
cassettes, all speeds, stop / repeat / reverse. Takes of 4 bars,
horizon 8 bars (32 beats). The creator's Scenario H: a fast tape opens a door outbound and moves the
switch back on its reverse pass, so the access window closes at a planned time.
Files: `data/levels/09-rewind.json`, `data/levels/solutions/09-rewind.json`.

## The idea

```
######....#.........#
#sMM>>....#.........#   valve (s), ram (M, 2 tiles), outfeed belt (>, 2 tiles), start at (8.5, 2.5)
#=====....#.........#
####...===#.........#
#ee+......G.........F   lift (e), shutter (+, opens when the pilot is lit), gate (G, open while valve), burner (F)
#===......#.........#
#.........#.========#
#.........#....g..o.#   stoker (grunt, wakes with the valve), pilot core (needs 3.2)
```

One machine on an 8-beat cycle. The burner fires west down row 5 on beats 7.5–8.5 of every 8
(so the level opens with flame splashing against the shut gate). The gate is the only shield for
the lift, which sits in the lane. The valve opens the gate, and its bay is only usable in the calm
at the start of a cycle: the ram is up on beats 0.5–2 and 5.5–7.5, and from beat 2 the belt
(30 tiles/s) throws any live body back out. So a live self can open the valve early and can never
walk back to close it. A 4x tape is 4 beats long: reversed, it is back in the bay on beats 6–7,
walking over a belt that cannot move a recording (MOM-06), and has the gate shut 0.6 beat before
the fire. The fire is symmetric about beat 8, so "left just after the fire" mirrors to "returns
just before the next one" without any counting.

## Intended solution (3 tapes, wins at the horizon; `mutate`: all 24 win)

| Beat | A, 4x reverse | B, 2x stop | C, 1x stop |
|---|---|---|---|
| 0–1.3 | to the bay mouth, in at 0.75, valve ON at 1.27 (gate opens 1.42) | to the gate | to the south of the hub, off the lane |
| 1.3–4 | out by 1.8 (ram slams at 2), idles; tape turns at 4 | through the gate at 1.73, kills the stoker at 3.65 | waits |
| 4–7 | walks back in over the running belt, valve OFF at 6.73 (gate shut 6.88) | 2x heavy on the pilot at 5.58 (3.6 against 3.2); stays in the kiln, off the lane | shutter opens 5.73; walks into the lift |
| 7.5–8.5 | fire; the gate takes it | | in the lift at 8.1, shielded |

A keeps cycling (ON 9.27, OFF 14.73, …) so every later fire also meets a shut gate; C is in the
lift at beat 32.

## Naive plans, run with the tools

| Plan | Result |
|---|---|
| A at 4x, stop | FAIL — gate never closes, "C died at beat 7.49: burned by flame jet burner". |
| A at 4x, repeat | FAIL — second pass reaches the bay at beat 5: ram down, "A's interact does nothing: desynced"; the valve stays on until 9.28 and C burns at 7.49. Repeat redoes, it does not undo. |
| A at 2x, reverse | FAIL — too slow for the calm: valve on at 1.8, A is under the ram at 2.0 and dies; gate stays open, C burns. |
| One 4x tape does everything | FAIL — valve, stoker, and the tape ends on the way to the pilot (4 of 14 steps never reached). |
| X opens (4x stop), Y walks in at beat 5.6 to close, with a dodge | FAIL — Y is held off by the belt ("way blocked"), the rider burns at 7.49. |
| A 2x self stays at the valve to close it later | FAIL — crushed by the ram at beat 2; rider burns. |
| B at 1x | FAIL — struck by the stoker at beat 6; a 1x swing tops out at 2.7 against the pilot's 3.2 anyway. |
| Two tapes: B lights the pilot and runs for the lift herself | FAIL — back at the gate at 7.18, it shut at 6.88; burned in the lane at 7.49. |
| Three forward tapes: X opens and sprints for the pilot, Y closes late in the same calm | FAIL — X reaches the gate 0.1 beat after it shuts: "desynced at beat 2.01 (blocked by door gate)". |

## Alternative that wins

Four forward tapes, no reverse: X (4x) opens at 0.81, Y (4x) closes at 1.85 and is crushed in the
bay, B (4x, waiting at the gate) slips through inside that one-beat window and lights the pilot,
C rides. It needs three fast selves threaded through one calm and spends every cassette; reverse
does it with three and no timing. Not found: any win with fewer than three tapes.

## Teaches for later

Reverse as "undo in mirrored time" (11 and 12 lean on it), that repeat and reverse meet the world
at different beats, that a recording ignores belts, and doors as flame shields.

## Numbers relied on (`level.ts probe 09`)

4x run: 8.8 tiles per beat. In-bay round trip at 4x: 0.75 → 1.8 (ram cells left by about 1.55,
slam at 2.0; mirrored exit from the ram cells about 7.0, slam at 7.5). Gate closes 0.62 beat before
the fire. Door travel 0.15 beat. Pilot 3.2: 2x heavy 3.6 yes, 2x running light 3.0 no, 1x best 2.7.
Godot replay: `bash tools/gd script res://tools/bot.gd -- 09-rewind` wins identically.

## Presentation must-haves

- Burner, ram and belt are one machine: same accent, and the ram slam and burner ignition at 7.5
  must land together. The beat-0 flame against the shut gate is the level's first lesson; do not
  cut it from the intro.
- Valve and gate share a signal colour; pilot and shutter share another.
- The belt needs strong outward chevrons and must visibly stop during the calm. A playback self
  walking against it should show the cassette-colour ghost trail from `docs/TRAPS.md`.
- The ram is two side-by-side stampers from the north wall (`dir: "s"`, cells listed west to east).
- The bay's south side and the lift's south side are low barriers so both read from the camera.
