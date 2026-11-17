/**
 * Moving the live self's body from outside its controller (belts and bumpers; docs/TRAPS.md).
 *
 * PlayerController (player.ts) is the only place live player physics happens and it keeps its
 * position private. A belt or a bumper is the world moving the body between two of its ticks, so
 * the kernel sets the position directly, before the controller's next step: the controller then
 * runs its normal physics from the new place (its velocity is untouched, so a belt adds no swing
 * momentum) and the tape records the result as ordinary movement.
 *
 * PORTING NOTE: this reaches the controller's two private fields because player.ts is owned by
 * another engineer. The clean form is a public `PlayerController.displace(x, y)` that does exactly
 * the two assignments below; the GDScript port should add that method instead.
 */
import type { PlayerController } from '../player';

export function displaceController(ctl: PlayerController, x: number, y: number): void {
  const body = ctl as unknown as { x: number; y: number };
  body.x = Math.fround(x);
  body.y = Math.fround(y);
}
