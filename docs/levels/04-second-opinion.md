# 04 — Second Opinion

Upper ruins · 2 cassettes · 0.5x / 1x / 2x · stop · 100 bpm · takes of 4 bars (9.6 s), horizon 8 bars ·
E Dorian, funk · loot: speaker_knuckles, patchcord_hoodie, kneepad_joggers

## The idea

Two hits in one moment (Scenario A). The bouncer is a shielder: a hit from a self only drops its
shield for one master beat, and only a **different** self can use that beat. One tape, at any speed
and any momentum, can never hurt it. The room is two halves joined by a one-tile doorway, so
whichever self it is walking at, the bouncer comes through the same tile at the same time
(beat 4.6): that is where two selves can be sure to find it together.

The second half of the idea is the order inside the moment. The first hit only opens; the second is
the one that counts, and the bouncer has 2 hp, so the closer has to bring 2 momentum (level 02).
A grunt comes through the doorway first (beat 3.2) and is the reason the rocket matters: the rocket
locks the nearest enemy at launch, which is the grunt until somebody removes it (Scenario F).

```
0  ################     @  start (2.5, 4.5)
1  #......#.......#     G  grunt g1: reaches the doorway at beat 3
2  #......#..G....#     H  bouncer (shielder, 2 hp): reaches the doorway at beat 4.6,
3  #......#.......#        bashes on beats 0, 4, 8 … after a 0.75-beat wind-up
4  #.@.........H..#
5  #......#.......#
6  #......#.......#
7  #......#.......#
8  ################
```

## Discovering it alone

Take 1 is alone by construction. Measured lone takes: at 1x, two lights, a running heavy (2.7) and
the rocket; at 2x, lights (2.0), a running heavy (5.4) and the rocket. Every one reports
"does nothing: shield", and the run fails with "Still standing: shielder bouncer". The bouncer walks
1.08 tiles a beat and bashes once every four, so the player has about nine beats to try everything
and can back away from it. The tape 2 hint then states the rule in one line.

## Intended solution (stored in `data/levels/solutions/04-second-opinion.json`)

| Master beat | Tape A — 1x, the opener | Tape B — 2x, the closer |
|---|---|---|
| 0 – 1.2 | walks to (5.2, 4.5), two tiles short of the doorway | stands beside her at (5.0, 5.6), a step further from the doorway |
| 3.17 | light: kills the grunt as it comes through | |
| 4.61 | light: "does nothing: shield" — the shield is down until 5.61 | |
| 5.19 | backs off north-west | standing heavy, momentum 3.6: lands, 3 damage, bouncer dead |

Slack: B lands 0.58 beats after the tap and 0.42 before the window closes. `mutate` passes all 20
variants. The Godot replay gives the same outcome (objective at beat 5.19).

## What a first-time player tries, and what it teaches

| Plan | Result | The lesson |
|---|---|---|
| One tape, hit harder (1x or 2x, heavy, running heavy, rocket) | FAIL, shield every time | Momentum is not the answer here; a second self is. |
| Both at 1x, a standing light each | FAIL. B's light lands for 1 of 2 hp, the shield is back, B is bashed at beat 12 | The closer must hit for 2: fast tape or a run-up. |
| Closer first: B's 2x heavy at 4.36, A's light at 4.61 | FAIL. The heavy opens the shield, the light lands for 1 | The second hit is the one that counts. Open soft, close hard. |
| B a beat late (6.19) | FAIL, "does nothing: shield" | The window is one beat. |
| B runs ahead through the doorway | FAIL. The grunt kills B at beat 2; A's first swing hits air because the grunt went for B | Enemies go for whoever is nearest. Do not pull them off your old self's swing. |

## Alternatives left open (all win)

- Both at 1x: A taps, B answers with a **running** heavy (momentum 2.64) at 5.28.
- B at 2x with a standing light (momentum 2.0, exactly 2 damage) at 5.19.
- A at 0.5x: her light does no damage (0.5) but still opens the shield (4.33); B at 2x kills the
  grunt first, then closes at 5.26.
- **Target manipulation (Scenario F).** Tape A only fires the rocket east at beat 2.6 and walks
  away: alone it takes the grunt (3.03) and the run fails. On tape B (2x), kill the grunt at 2.18,
  before the launch: the same rocket now locks the bouncer, opens its shield at 3.58, and B's heavy
  lands at 3.88. If B swings before the rocket arrives the roles swap and the rocket lands for 1:
  a failure.

## What it sets up

- 05: A's lone take often ends with her bashed at beat 12; with B there she lives. Survival is
  recomputed every run.
- 06: the bouncer's path is predictable because of the doorway; later levels move enemies on purpose.
- 10 / 11: opener and closer roles, and rockets whose target depends on what other tapes did.

## Numbers relied on (`level.ts probe 04`)

- 100 bpm: 36 ticks a beat; a self runs 2.7 tiles a beat at 1x.
- Shielder 2 hp, 1.08 tiles a beat, shield window 1 master beat (`SHIELDER_WINDOW_BEATS`), bash
  every 4 beats, needs its target within 0.9 tiles at the start of the wind-up.
- Blade reach 1.3 + target radius 0.35. Light lands 6 ticks after the press, heavy 16 (0.22 beats
  at 2x). Momentum: light 1.0 / 2.0 at 1x / 2x, standing heavy 1.8 / 3.6, running heavy 2.7 / 5.4.
- Rocket: 1.8 tiles a beat, momentum 1.5, locks the nearest living enemy once at launch.
- A 2x tape ends at beat 8, 2.8 beats after the kill.

## What the presentation must get right

- The shield needs three readable states: up, just hit (down, with the one-beat window draining
  visibly), and snapping back up. The clang on a blocked hit has to look different from a hit that
  lacked momentum.
- The 2 hp must be visible, so that "it took one and the shield came back" reads as progress.
- On tape B the player has to see A's swing coming: the windup of a recorded self should be as
  legible as an enemy telegraph.
- The rocket's lock should be drawn at launch (a line or reticle on the target) so that the changed
  target in the Scenario F line is noticed.
- Nothing stands in the fight zone (columns 4 to 7, rows 3 to 6); decor is against the walls.

## Honest notes

- This level is short and its intended solution is easy to execute once the rule is understood;
  the thinking is in the rule, the order of the two hits and which self gets the fast tape.
- The doorway makes the two-self timing forgiving. In an open room the bouncer's path would depend
  on which self is nearer, which is the harder version of this puzzle and is left for level 06.
