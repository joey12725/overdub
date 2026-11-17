# 01 — Soft Open

Upper ruins, 90 bpm, F major pentatonic (lo-fi groove). One cassette, 1x, stop. 8 bars (21 s).
Files: `data/levels/01-soft-open.json`, `data/levels/solutions/01-soft-open.json`.

## The idea

Move, light attack, the deck and the beat ruler, and nothing else. One grunt walks at Moxie the
moment the count-in ends; behind a low wall two more are visibly asleep; the only gap in that wall
is boarded with rotten planks. The room is one straight line east to west, so there is nowhere to
go but forward and nothing to do but swing.

```
#,,....=.....,,#      @  start, facing west
#,G....=.......#      G  g1 (east room): awake, walks at you from beat 0
#......=.......#      %  planks: break to any hit (threshold 1)
#...G..%G.....@#      G  g2, g3 (west room): asleep until the planks break
#......=.......#      =  low wall: you see and shoot over it, cannot walk through
```

## Intended solution (one take, wins at beat 7.7 of 32)

| Beat | Tape A |
|---|---|
| 0–1.3 | Step forward; g1 walks into reach; a light swing kills it (blade reach 1.3 beats its 0.9). |
| 1.6–2.8 | Walk to the planks, light swing: they break, g2 and g3 wake. |
| 3.2–5.4 | Step back from the gap; g2 arrives first (it sleeps three tiles closer); light. |
| 7.7 | g3 arrives two beats later through the same one-tile gap; light. Objective complete. |

The small "smart" moment: the gap is one tile wide and the sleepers are at different distances, so
a player who simply holds the gap fights them one at a time.

## What a first-timer tries, and what happens (all run with the tools)

| Plan | Result |
|---|---|
| Stand still (does not realise the take has started) | FAIL — "Tape A died at beat 4: struck by grunt g1". Four beats of warning; the strike lands on the beat. |
| Run round g1 to the planks and break them | FAIL — "struck by grunt g1" at beat 2, in the back, while swinging at the planks. Teaches: enemies follow. |
| Heavy swings only | WIN at beat 9.2 (alternative). |
| Blade for g1, then rockets over the low wall | Partial: the rocket kills sleeping g2 without the planks ever breaking; my second test shot missed g3, so I did not prove this line to a win. It is deliberately left open. |

## Teaches for later

- Enemies act on the beat grid; the ruler is the thing to watch (everything from 03 depends on it).
- Cracked things break when hit. Level 02 immediately complicates this ("not hard enough").
- "Asleep until something happens" as a visible, readable state.

## Numbers relied on (`level.ts probe 01`)

Run 3 tiles per beat; a light swing lands 6 ticks after the press and commits half a beat; blade
reach 1.3 plus the target's radius; a grunt walks 1.47 tiles per beat, reaches 0.9 and strikes on
even beats after a half-beat telegraph. g2 arrives 2.4 beats after the planks break, g3 about 2.2
beats after g2. `mutate`: all 12 variants win.

## Presentation must-haves (Godot)

- Flow is east to west on purpose: with the camera in the south-east, Moxie is never behind
  anything. The divider must render as a LOW wall so both sleepers are visible from the start.
- Sleeping grunts need an unmistakable asleep pose and a visible start when the planks go. The
  planks must look flimsy (boards, not masonry): level 02's cracked walls are the tough version of
  the same visual family.
- Count-in, then the ruler's even beats flash when a grunt telegraphs.
- Decor is all against the outer walls; nothing stands on the centre row.

## Known issue (not mine to fix)

The version on disk before the reboot used `dead:g1` to open a gate and wake the pair. The
validator and the README accept `dead:<enemy>` signals, but the prototype kernel never sets them
(`mechanisms.ts` only publishes switches, plates, breakables, cores, exits, doors and lasers), so
the gate never opened and the level could not be won. The planks replace it and teach more.
