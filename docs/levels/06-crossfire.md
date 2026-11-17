# 06 — Crossfire

`data/levels/06-crossfire.json` · mid · 100 bpm · 8-bar takes, 8-bar horizon · 3 tapes · 0.5x / 1x / 2x · stop

## The idea

Knockback as a tool (Scenario E), and the stalker's rule. The amp is behind a three-tile shutter that is
open only while something stands on the socket. The socket lies on a laser rail: selves die there, robots
do not. So the key is a robot, and the only way to put it there is to hit it.

- The stalker sleeps in its dock until the panic-room hatch locks, then hunts the **farthest** self. The
  self behind the hatch is unreachable, so it parks on the nearest tile to her: on the rail, one tile
  short of the socket, in the sentry's line.
- Any 1x or 2x swing kills a stalker. A **0.5x standing heavy** does no damage and shoves it 1.1 tiles:
  onto the socket, staggered for a beat.
- The sentry fires down the rail at any self it can see, once a bar. The only place to swing from is in
  its sights, and the only cover is the stalker.

Three jobs, three speeds: bait (1x), broom (0.5x), runner (2x, the amp needs momentum 3).

## Intended solution (stored; all three survive)

| Tape | Speed | Beat | What happens |
|---|---|---|---|
| A bait | 1x | 1.84 | on the latch; hatch shut at 1.97; stalker wakes, parked on the rail by 5.3 |
| B broom | 0.5x | 1.8 | waits south of the row, out of the sentry's sight |
| | | 6.3 | steps out just after the sentry's look on beat 6 |
| | | 10.56 | heavy lands: stalker slides onto the socket (10.70 – 11.85) |
| | | 10 → 11 | sentry has seen her: telegraph, fires at her |
| | | 12.66 | the bolt hits the stalker, back between them: killed by its colleague |
| C runner | 2x | 10.82 | shutter opens; through three door tiles |
| | | 12.04 | 2x heavy wakes the amp (shutter shut again at 11.97) |

Slack: C is clear of the shutter about 0.35 beat before it shuts; B wins leaving cover at any beat from 5.3
to 7.5 (stored: 6.3; at 7.5 the stalker is shot while still on the socket), fails at 8.0 to 9.0, and wins
again from 9.7 on the sentry's next cycle; the bat lands 2.1 beats before the bolt. `mutate`: all 24 variants win. Replays in Godot.

## Naive plans (all run)

- **One tape.** The bait alone locks herself in; nothing else can happen. A self rolling onto the socket
  herself dies there and holds the shutter for at most 0.27 beat: the runner cannot get through three
  tiles, with or without a run-up (12 timings tried).
- **Broom at 1x.** Same plan, wrong speed: "B KILLS stalker" at 8.42. No key, no shutter.
- **Broom dawdles in the sentry's sights.** Seen on beat 6, swings on beat 9: the bolt kills the parked
  stalker at 8.66 before she uses it. The crossfire happens, at the wrong time.
- **Runner recorded first.** Her tape is a self standing at a shut door. Fails.
- **Runner at 1x.** Reaches the amp; heavy 1.8, needs 3.
- **No bait.** The stalker never wakes; the broom stands in the row unshielded and is shot at 13.51.
- **Light bat.** Stagger too short: socket held 0.37 beat, the runner is caught by the shutter.

## Alternatives left open

- **Reactive broom:** walk straight in and swing the moment the stalker parks (bat at 5.61, amp at 7.10,
  stalker shot at 8.66). WIN. Faster than the stored line; needs the player to react instead of count.
- A second bat after the stalker walks back reopens the shutter, if the sentry has not fired yet.
- The bait can be any speed; she only has to reach the latch.

## What it teaches for later

Enemies as moving parts of a machine (plates, bolt-stoppers); tape speed as a force dial, not only a
clock; the stalker's targeting, which 07 and 10 reuse; standing behind an enemy to redirect a shot.

## Tuning relied on

At 100 bpm: stalker 2.16 tiles/beat, mass 0.8, poise 1.5; 0.5x heavy standing: momentum 0.9, damage 0,
knockback 1.125 tiles, stagger 0.6 s (1 beat). Sentry `every 4, offset 3`: looks on beats 2, 6, 10, fires
on 3, 7, 11; bolt 3.6 tiles/beat, 1.66 beats to the parked stalker. Stalker commits once within 2.5 tiles
of its quarry and otherwise re-chooses on bar lines. Shutter is three tiles so only a held socket opens it.

## Presentation must get right

- The stalker must visibly ignore the selves it runs past, and visibly fixate through the hatch wall.
- A 0-damage hit needs its own look and sound (a shove, not a clang of failure).
- Socket and shutter one accent colour; latch, hatch and dock another.
- The rail must read as lethal to Moxie and harmless to robots (the stalker stands in it for five beats).
- The row north of the rail is a low barrier and the south side is a pit, so nothing hides the socket,
  the shutter or the amp. The latch tile is west of a tall wall: the bait needs the x-ray silhouette.
- The sentry's telegraph must show its target; the kill should get the camera.

## Known gaps

- Stalker re-pick edge: if a bar line falls while it is between x = 6.5 and 7.0 on the row, a self at the
  shutter is momentarily the farthest and it turns on her. About a quarter-beat window; the stored
  solution is 1.3 beats clear of it.
- The objective is only the amp. I wanted "and the stalker is dead", but `dead:<enemy>` signals validate
  and are never set by either kernel. The kill still happens in every winning line I found.
- "Into an earlier self's swing" is not used; the level covers the plate and the turret lane.
- Level `index` is 6 (file prefix), as briefed; the campaign test wants 0-based numbering.
