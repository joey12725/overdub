# 05 — Dead Air

`data/levels/05-dead-air.json` · mid · 120 bpm · 8-bar takes, 8-bar horizon · 3 tapes · 0.5x / 1x / 2x · stop

## The idea

Death is not the end of a take (Scenarios C, D, L). The room has four jobs and three cassettes:

1. stand on the west floor key,
2. stand on the east floor key (both down opens the gate),
3. go through the gate and stand on the mute pad (the only thing that turns the laser grid off),
4. walk past the lasers, break the booth wall, throw the ON AIR switch.

Both keys are in the sentry's sights; it shoots the nearest self it can see once every two bars (fires on
beat 4 of bars 1, 3, 5 …, one beat of telegraph). The laser grid cannot be rolled through. So job 4 has
to be done by a key-holder, and in her own take the lasers are still on. The only way to record it is to
die first and walk it as a ghost. A later take then removes what killed her, and the ghost route becomes
real. The "aha": the self that dies is the only one who can record her whole job alone, so she goes first.

## Intended solution (stored; all three survive)

| Tape | Speed | Beat | What happens |
|---|---|---|---|
| A | 1x | 3.8 | on the west key |
| | | 11 → 12.08 | sentry fires; bolt lands: A dies (local second six) |
| | | 12.5 → 18.4 | ghost walks through the live grid |
| | | 20.00 | heavy breaks the booth wall (second ten; momentum 1.8, needs 1.6) |
| | | 24.00 | throws the switch (second twelve). Review: none of it counted |
| B | 1x | 4.8 | on the east key: gate opens at 4.9. In this take the bolt goes to B (nearer), and A, alive, burns in the grid at 16.3 |
| C | 2x | 4.9 | through the gate |
| | | 6.17 | heavy kills the sentry from behind (deadline: its shot on beat 11) |
| | | 7.30 | on the mute pad: grid off (deadline: A reaches it at 16.3) |

Final run: nobody is shot, A crosses where the grid was, wall at 20, switch at 24. Slack: 4.8 beats on
the kill, 9 beats on the pad, 0.2 momentum on the wall. `mutate`: all 24 variants win. Replays in Godot.

## Naive plans (all run; outcomes from `level.ts run`)

- **One tape does everything.** Rolling the grid: dies in it from every start point (22 positions swept,
  plus a zig-zag along the wall and a pocket hop). Rocketing the sentry first changes nothing: the grid
  stays on. A's take alone is this plan: dead at 12.08, switch thrown by a ghost, objective not complete.
- **Wrong order: the gate-runner first.** The gate never opens in her take, so her tape is a self standing
  at a door. Fails; the cause is visible (nobody was on the keys yet).
- **Nobody dies in her own take.** A holds the key, steps off before the shot and waits at the grid alive.
  Everyone survives, the grid drops at 7.3, and nobody ever walks through: no tape recorded that route.
- **Runner at 0.5x.** Running heavy on the booth wall: momentum 1.35, needs 1.6. Clang.
- **Runner on the near key, slow helper.** If C ignores the sentry, the bolt takes whoever is nearer. With
  the runner on the east key she dies at 11.72 and stays dead.

## Alternatives left open

- **Sacrifice (Scenario L):** runner on the far key, B on the near key, C at 1x or 0.5x goes straight to
  the pad. B is shot at 11.72 and stays dead; A is untouched. WIN, survivors A and C.
- **Rocket (level 04's tool):** B fires the mixtape rocket from her key; sentry dead at 6.9. C can stroll.
- Any speed for the holders works if the plan accounts for the sentry; 2x holders are seen on beat 2.

## What it teaches for later

Ghost takes as a planning tool, recording order as part of the plan, enemy aim that moves when a self is
added (Scenario D: A's death moves from "shot at 12.08" to "burned at 16.3" between takes 1 and 2), and
that a dead tape is acceptable (07 builds on "not interactive but still moving" with desync).

## Tuning relied on

Sentry `every 8, offset 3`, telegraph 1 beat, bolt 3 tiles/beat; west key 4.24 tiles from it (flight 1.08
beats), east key 3.16. Roll: about 1.9 tiles of i-frames, 2.6 total; the grid's lethal band is 2.6 tiles
with 0.4-tile pockets closed by the two lengthwise beams. Gate needs both keys; keys are 6+ tiles from it.

## Presentation must get right

- The deck must say DEAD and keep rolling; the ghost must visibly pass through beams.
- Review must show A's switch throw as a non-event (dim / struck through), not silently drop it.
- Death marks on the ruler must move between takes (12.08 → 16.3 → gone).
- Accents: both keys and the gate one colour; mute pad and all five beams another.
- The sentry's telegraph must show whom it is aiming at.
- The booth sits behind a pit, not a tall wall, so the switch and the cracked wall are visible.

## Known gaps

- `dead:<enemy>` signals validate but are never set by either kernel, so the grid is wired to the pad,
  not to the sentry's death.
- Level `index` is 5 (file prefix), as briefed; the campaign test wants 0-based numbering and fails for
  all twelve levels.
