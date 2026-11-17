# 07 — Out of Phase

Mid theme · 80 bpm · 4-bar takes (12 s) · horizon 8 bars · 3 cassettes · 0.5x / 1x / 2x · stop, repeat.
Files: `data/levels/07-out-of-phase.json`, `data/levels/solutions/07-out-of-phase.json`.

## The idea

Scenario J, taught so the player finds it: a recording that walks into a shut door **desyncs**. Its
projection carries on without a body, so a lethal lane cannot touch it — but it has no hands until
its spark catches up, and a spark needs an open door (Scenario I's "reopened route").

```
#p.@##      T......#     p  damper plate: shuts BOTH gates while held     @ start
#...##      ...s...#     :  gate1 (5,3) and gate2 (13,9), same signal, same colour
#....:~~~~~~.......#     ~  cutting beam along each catwalk (void either side), off once the mains is cut
#...##      .......#     T  armoured sentry behind each beam (120° arc: its rear is safe)
################.###     s  vault key (switch) on the island: opens the vault door +
#....#.      ##....#     o  the mains (core): the objective
#.o..+.~~~~~~:.....#
#....#T      ##....#
```

One route, two lanes: west room → gate1 → catwalk 1 → island (pull the key) → down to gate2 →
catwalk 2 → vault → mains. The key is what makes one long desync useless: the self has to be
solid on the island, then out of phase again.

## Intended solution (2 cassettes; stored, wins at beat 13.96)

| Beat | Tape A — striker, 1x, stop (recorded first) | Tape B — doorman, 2x, **repeat** |
|---|---|---|
| 0.3 | | on the plate: both gates shut |
| 0.9 | walks into gate1: **desyncs**, projection crosses beam 1 | |
| 3.1 | projection nearly across | steps off: gates open, spark runs the catwalk |
| 5.1 | spark catches A at the key (A has been standing there since 4.2) | |
| 5.6 | pulls the key: vault opens | |
| 7.1 | leaves the island (waited so that it meets gate2 two bars after gate1) | |
| 8.0–8.3 | | **tape loops**: back on the plate, gates shut |
| 9.5 | walks into gate2: desyncs, crosses beam 2 | |
| 11.1 | | steps off again (same loop) |
| 13.2 / 13.6 | spark arrives / heavy on the mains | |

A's own take is a ghost route (level 05): beam 1 kills it at beat 1.4 and it records the rest as a
ghost. The "aha" comes in take 2, standing on the plate and watching the old self walk through fire.
Slack: every dependency has ≥ 0.36 beat (gate shut 0.57 before A arrives; resync 0.5 before the key;
second closure 1.2 before A; release ≥ 1.0 after the minimum; resync 0.45 before the swing; 2 beats
of tape left). `mutate`: all 20 variants win.

## Naive plans (each run; outcome as the game reports it)

| Plan | Result |
|---|---|
| One tape walks the route | FAIL — "Tape A died at beat 1.36: burned by laser beam1" |
| One 2x tape, dodging down the catwalk | FAIL — burned at beat 0.77; the beam is lengthwise, i-frames run out |
| Doorman stands on the plate for good | FAIL — "A's interact does nothing: desynced … ended the run desynced". Spark stuck at gate1 |
| Doorman steps off too early (beat 1.2) | FAIL — A resyncs on the catwalk and burns at 2.04 |
| Doorman at 2x on **stop** (one closure) | FAIL — key pulled, then A walks through open gate2: burned by beam2 at 9.96 |
| Doorman recorded **first**, striker second | FAIL — a live take cannot desync: it waits for the gate, then burns at 3.76 |
| Striker at 2x (doorman by hand at 1x) | FAIL — the spark (7.5 tiles/s) is slower than a 2x self (9); it arrives at 8.45, after the tape ended at 8 |
| Doorman at 0.5x, one closure | FAIL — same as the one-closure case |

## Alternatives that win (run, not stored)

- 1x doorman on **stop** doing both closures by hand (on, off at 3, on at 8, off at 11).
- Three cassettes, no repeat: 2x doorman once + a 1x second doorman for gate2.
- Three cassettes, one long closure: A never waits at the key (its ghost pulls it in its own take),
  a second striker crosses with it and really pulls the key, the doorman holds until beat 5.2.
  Released at 4.4 instead, A resyncs on catwalk 2 and burns — the release rule again.

Repeat is therefore the economical line, not the only one: that is the "gentle" introduction.

## What it teaches for later

Desync is a tool, with a price (no agency) and a rule (the spark is faster than a 1x self, slower
than a 2x self, and needs a route). A loop comes round whether you are ready or not: plan the
striker's waits to the doorman's bar line. Level 08 uses both.

## Numbers relied on

1x run 4.5 tiles/s (3.38 tiles/beat here); spark 7.5 tiles/s; door travel ≈ 0.1 beat; catwalk 6
beam tiles (lethal x 6.2–11.8). Release rule: gate must stay shut ≥ 0.4 × crossing time after the
self enters (≈ 0.7 beat), so the spark cannot catch it on the beam. Core threshold 1; the solution
uses a standing 1x heavy (1.8).

## Presentation must get right

- Desynced A must read at once: projection ghosted in cassette colour, spark bright and visibly
  **waiting at the shut gate**, then racing when it opens. This is the whole lesson.
- Both gates and the plate share one accent colour; key and vault share another.
- The beams should look like they belong to the sentries (emitter housing beside each one) and die
  when the mains is cut. Sentries are armoured (hp 99): no health bar, a clang on hit.
- The sentries can see into the west room and the south-east room only through an open gate, along
  rows 3 and 9. The plate, the start and the key are outside those cones.

## Known gaps

- The sentries never fire in the intended run; they punish loitering in the gate mouths and stand
  in for Scenario J's turret. The beam, not the bolt, is what makes the lane lethal: a turret lane
  alone can be dashed by a 2x self (one-beat telegraph) and rocketed from safety (1 hp, baseline
  rocket), so it could not carry the puzzle.
- No detour route for the spark (Scenario I's other half); only the reopened door.
