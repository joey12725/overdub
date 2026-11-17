# 08 — Loop Pedal

Lower theme · 120 bpm · 4-bar takes (8 s) · horizon 8 bars · 3 cassettes · 0.5x / 1x / 2x / 4x · stop, repeat.
Files: `data/levels/08-loop-pedal.json`, `data/levels/solutions/08-loop-pedal.json`.
Traps used: conveyor, two sets of spikes, one relay (as a latch). All implemented and proven.

## The idea

Scenario G as a machine. Tape speed is tape length (4x one bar, 2x two, 1x four, 0.5x all eight)
and strength. The room needs something strong for the whole run and something patient for the
whole run: fast + repeat, and slow. Three selves, three shapes in time: one stays, one lasts, one
comes round again.

```
#<<<<<H<<<H<<<H<<<H<<#   <  conveyor "line", runs west while the drive plate is held; scanner beam along it
#==WW=p==============#   H  four sleeping shielders ("cans"), 4 tiles apart = one every two bars
#....=:..#####.......#   W  bay under the press (spikes): down only in beats 4–8 of every 8
#.====...#####.......#   p  booth with a dead-man plate, behind a hatch (:) that locks when the line runs
#.=...@..wwwww....p..#   w  teeth (spikes): down two beats, up two        p (18,5) drive plate
#.=......#####.......#   =  railings: the bay is reached the long way round (west side)
#........#####.......#   fault relay (lamp at 5.5, 2.5): line running + empty booth = press shut for good
```

## Intended solution (3 cassettes; stored, wins at beat 30.2)

| Tape | Does | Why this speed / end mode |
|---|---|---|
| A — S, 0.5x, stop | Into the booth (in by beat 3.2), stays. Knocks each can as it passes: beats 5.8, 13.8, 21.8, 29.8 | A knock needs no strength; only a half-speed tape is still awake for can 4, and it never leaves the plate |
| B — T, 4x, stop | Through the teeth in their first down-window, waits beside the drive plate, steps on at 3.5 (after S is in). Line starts, hatch locks | Only 2x/4x gets through the teeth; a 4x tape ends at beat 4, so this is nearly its last beat |
| C — F, 2x, **repeat** | Each two-bar pass: round the railings to the bay mark (3.3), in when the press lifts (4.2), heavy at 6.2 just after the knock, out by 6.9 | Loop length = press cycle = can spacing. 3.6 momentum kills a 2-hp can in one hit |

Slack: knock → hit 0.4 beat inside a 1-beat shield window; F enters the bay 0.4 after the press
lifts and leaves 1.1 before it drops; S is in the booth 0.33 before the line starts; T is on the
plate 0.47 before its tape ends. `mutate`: all 24 variants win.

## Naive plans (each run)

| Plan | Result |
|---|---|
| One tape (the striker alone) | FAIL — nothing moves, nothing pops |
| Striker 2x on **stop** | FAIL — kills can 1, then stands still: cans 2–4 standing |
| Striker **4x** on repeat (the new speed) | FAIL — "skewered by spikes press" at 1.7: a one-bar loop comes round while the press is shut. Waiting does not help; pass 1 is always inside beats 0–4 |
| Courier first, straight to the plate | FAIL — line runs at 1.31 with the booth empty: fault at 2.0, press shut, striker skewered at 4.3 |
| Booth self at 1x, stop | FAIL — knocks cans 1 and 2, tape over at 16: cans 3, 4 standing |
| Booth self on a 2x loop | FAIL — it blinks out of the booth at beat 8: fault, press shut |
| Courier at 1x (or 0.5x) | FAIL — "skewered by spikes teeth" |
| Speeds swapped (0.5x hits, 2x loop knocks) | FAIL — "too little momentum for any damage (0.90)" four times |
| Two 2x loopers in the bay, booth empty | FAIL — fault as the line starts |
| Striker on a 4x loop hitting from inside the booth | FAIL — locked out from pass 2; its spark needs 4.8 beats to go round by the belt, longer than the loop |

## Alternatives that win (run, not stored)

- Courier at 2x instead of 4x (crosses the teeth in the same window; twice the time to wait for S).
- Striker on a 2x loop working from **inside the booth**: from pass 2 the hatch is locked, it
  desyncs, and its spark goes round the railings, across the bay and along the belt (sparks ignore
  beams and spikes) to re-form in the booth at phase 4.9, in time for the hit at 6.2. It skips the
  press but needs level 07's lesson and still needs the two-bar loop. Left open on purpose; say if
  you want it closed (seven more tiles of railing would do it).

Not proven: a 1x-loop striker (two cans per pass, two knocks and two lights each). My one attempt
overstayed in the bay and was skewered; it should be possible.

## What it teaches for later

A loop meets the room as it is now, not as it was (the 4x death, the fault). Pick the tape whose
length matches the machine. Slow tapes are for jobs that need time, not force. Machines can be
chained (plate → belt + hatch; relay → spikes): levels 09 and 10 build on that.

## Numbers relied on

Belt 1 tile/s = 0.5 tile/beat; cans 4 tiles apart. Blade reach 1.3 + shielder radius 0.35: from
the booth (6.5, 2.5) a can is in reach for x 5.2–7.8, from the bay (4.5, 2.6) for x 3.2–5.7.
Shield stays down 1 beat after a knock. 0.5x light 0.5 momentum (pops, 0 damage); 2x heavy 3.6
(3 damage); 2x light is exactly 2.00 = the can's 2 hp, so the solution uses the heavy. Teeth: 5
tiles; 4x crosses in 0.55 beat, 2x in 1.1, 1x in 2.2 (window 2). Spark 7.5 tiles/s.

## Presentation must get right

- The press must show its cycle before anyone walks under it (warn ramp, and a visibly different
  "fault: locked shut" state with the relay lamp on).
- Drive plate, belt chevrons and hatch share one accent colour; booth plate, fault lamp and press
  share another.
- Railings (`=`) are low: they must not hide the bay or the belt. Cans are dormant shielders; the
  knock (shield pop) needs a clear flash so the striker can time off it.
- A mark on the belt where the booth's and the bay's reach overlap (x ≈ 5.2–5.7) would help.

## Known gaps

- Human execution: at 0.5x one real second is four master beats. S has to walk straight into the
  booth (three tiles), and each knock has to land within about ±0.15 s of the same point in the
  two-bar cycle, because F's swing repeats exactly. Playable on the beat, but it is the tightest
  input in the level. A 2x courier is the forgiving choice if S was slow.
- A 2x light kills a can with no margin (2.00 momentum for 2 hp); if the Godot port rounds
  differently a player's light could fail where the table says it works.
