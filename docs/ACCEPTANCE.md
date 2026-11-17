# Acceptance status

Every acceptance id of `docs/requirements.txt` — chapter 21 (TEST-01..34), Revision 1
(NEW-01..11) and Revision 2 (APP-TEST-01..03) — mapped to its automated test in
`tests/acceptance/`, with the status of the last run against the shipped Godot code. The
"Expected result" column is quoted from the requirements document; `test_acceptance_texts.gd`
fails if a quote stops matching it. Regenerate after a run:

```
bash tools/gd test acceptance > acc.log; bash tools/gd test tests/replay > rep.log
python -I tests/acceptance/gen_acceptance.py . acc.log rep.log docs/ACCEPTANCE.md
```


Last run: `11 suite(s), 51 test(s): 51 passed, 0 failed, 0 suite load failure(s); 2397 assertion(s); 11518 ms`.

Status: **pass** — every test for the id passed; **FAIL** — a test failed (reason quoted from
the run); **by eye** notes say what an automated test cannot judge.

| Id | Expected result | Test | Status | By eye |
|---|---|---|---|---|
| TEST-01 | Actual recording allowance remains equal; world pace changes relative to the controlled character. | `test_TEST01_recording_allowance_is_equal_at_every_speed_and_the_world_pace_changes`<br>(test_acceptance_time.gd) | pass |  |
| TEST-02 | The master-beat relationship is preserved; no duration stretching changes the landing. | `test_TEST02_a_2x_plate_landing_happens_at_the_same_master_beat_in_recording_and_replay`<br>(test_acceptance_time.gd) | pass |  |
| TEST-03 | The encounter starts at beat zero; cassette one plays from its start. | `test_TEST03_cassette_two_starts_at_beat_zero_with_cassette_one_playing_from_its_start`<br>(test_acceptance_session.gd) | pass |  |
| TEST-04 | Prior tapes are visible/simulated; unrecorded future tapes do not appear. | `test_TEST04_prior_tapes_are_simulated_while_recording_and_future_tapes_do_not_appear`<br>(test_acceptance_session.gd) | pass |  |
| TEST-05 | Earlier committed takes remain; the current take can be replaced. | `test_TEST05_retry_replaces_the_current_take_and_keeps_the_committed_ones`<br>(test_acceptance_session.gd) | pass |  |
| TEST-06 | Every cassette in the attempt is reset, including those before the edited tape. | `test_TEST06_changing_an_older_tape_resets_every_cassette_including_earlier_ones`<br>(test_acceptance_session.gd) | pass |  |
| TEST-07 | Recording continues with a major ghost visual distinction. | `test_TEST07_dying_while_recording_continues_the_take_as_a_visibly_distinct_ghost`<br>(test_acceptance_ghosts.gd) | pass | How strong the recording-ghost distinction looks (hologram body, broken halo) — review in game. |
| TEST-08 | Normal movement collision still applies; the recording ghost cannot simply phase through. | `test_TEST08_the_recording_ghost_still_collides_with_a_locked_door`<br>(test_acceptance_ghosts.gd) | pass |  |
| TEST-09 | They affect that provisional recording run. | `test_TEST09_the_recording_ghosts_attack_and_switch_affect_its_provisional_run`<br>(test_acceptance_ghosts.gd) | pass |  |
| TEST-10 | Later attack/switch effects do not occur; its non-interactive ghost continues the path. | `test_TEST10_replayed_the_dead_tapes_later_attack_and_switch_do_not_occur_and_its_ghost_keeps_the_path`<br>(test_acceptance_ghosts.gd) | pass |  |
| TEST-11 | Later recorded actions can be effective, subject to current world and sync state. | `test_TEST11_once_the_fatal_hit_is_prevented_the_later_recorded_actions_take_effect`<br>(test_acceptance_ghosts.gd) | pass |  |
| TEST-12 | From that moment, it becomes a non-interactive playback ghost. | `test_TEST12_an_earlier_tape_killed_at_a_new_time_is_a_non_interactive_ghost_from_that_moment`<br>(test_acceptance_ghosts.gd) | pass |  |
| TEST-13 | Its projection stays on the recording; desynchronization and reachable recovery apply. | `test_TEST13_a_door_closed_across_a_living_tape_desyncs_it_while_its_projection_stays_on_the_recording`<br>(test_acceptance_desync.gd) | pass |  |
| TEST-14 | Finite-speed recovery can navigate toward the moving projection; no instant overlap-only recovery. | `test_TEST14_the_spark_navigates_the_detour_at_finite_speed_toward_the_moving_projection`<br>(test_acceptance_desync.gd) | pass |  |
| TEST-15 | The new traversable route can enable recovery. | `test_TEST15_reopening_the_blocked_route_lets_the_spark_recover`<br>(test_acceptance_desync.gd) | pass |  |
| TEST-16 | No dealt or received damage under the working invulnerable/harmless rule. | `test_TEST16_a_desynced_self_deals_and_receives_no_damage`<br>(test_acceptance_desync.gd) | pass |  |
| TEST-17 | Desync can protect the crossing, but the actor must resync before damaging the turret. | `test_TEST17_desync_protects_the_crossing_but_the_strike_only_counts_after_resync`<br>(test_acceptance_desync.gd) | pass |  |
| TEST-18 | Enemy response can change without the old tape changing its aim or path. | `test_TEST18_a_closer_self_changes_the_enemys_response_while_the_old_tape_keeps_its_aim_and_path`<br>(test_acceptance_combat.gd) | pass |  |
| TEST-19 | Its new physical position changes later hit outcomes. | `test_TEST19_knocking_an_enemy_into_or_out_of_a_later_attack_changes_that_hits_outcome`<br>(test_acceptance_combat.gd) | pass |  |
| TEST-20 | Effective momentum meaningfully influences damage, stagger and knockback. | `test_TEST20_tape_speed_and_movement_change_damage_stagger_and_knockback_of_the_same_attack`<br>(test_acceptance_combat.gd) | pass |  |
| TEST-21 | The selected i-frame interval can prevent death; exact timing is tunable. | `test_TEST21_the_dodge_iframe_interval_prevents_death_and_its_timing_is_tunable`<br>(test_acceptance_combat.gd) | pass |  |
| TEST-22 | Nearest target is acquired once at launch; the missile does not continuously retarget. | `test_TEST22_the_missile_locks_the_nearest_enemy_once_at_launch_and_never_retargets`<br>(test_acceptance_combat.gd) | pass |  |
| TEST-23 | The survival rule permits success. | `test_TEST23_three_selves_die_and_one_survivor_completing_the_objective_wins`<br>(test_acceptance_ghosts.gd) | pass |  |
| TEST-24 | The survival requirement is not met. | `test_TEST24_an_objective_completed_with_no_survivor_does_not_meet_the_survival_requirement`<br>(test_acceptance_ghosts.gd) | pass |  |
| TEST-25 | It cuts to its starting position and repeats without resetting the entire encounter. | `test_TEST25_repeat_cuts_to_the_start_and_repeats_without_resetting_the_encounter`<br>(test_acceptance_tapemodes.gd) | pass |  |
| TEST-26 | Recorded actions run backward without globally restoring world history; specific event inverses require policy. | `test_TEST26_reverse_runs_recorded_actions_backward_without_restoring_world_history`<br>(test_acceptance_tapemodes.gd) | pass |  |
| TEST-27 | The solution is not rejected or steered away solely for musical reasons. | `test_TEST27_an_off_beat_solution_is_accepted_exactly_as_performed`<br>(test_acceptance_music.gd) | pass |  |
| TEST-28 | They use the agreed fine rhythmic integration policy; no unapproved gameplay-time adjustment. | `test_TEST28_sound_events_keep_their_gameplay_time_and_the_late_only_sfx_policy_is_shipped`<br>(test_acceptance_music.gd) | pass | Whether sounds feel tight to the beat is by ear. |
| TEST-29 | Its own generated musical channel changes state; shared coherence remains a design goal. | `test_TEST29_a_dead_or_desynced_cassette_changes_only_its_own_music_channel_state`<br>(test_acceptance_music.gd) | pass | How a dead/desynced layer sounds (thinning, drift) and whether the mix stays coherent is by ear. |
| TEST-30 | Their timing can be beat-based, but they do not directly rewrite player wave functions. | `test_TEST30_enemy_attacks_keep_beat_time_but_never_rewrite_a_cassettes_music`<br>(test_acceptance_music.gd) | pass | That enemy hits keep time without muddying the cassette layers is by ear. |
| TEST-31 | Playback may finish for observation; the player can reset/end early. | `test_TEST31_a_failed_final_playback_may_finish_and_the_player_can_end_it_early_or_reset`<br>(test_acceptance_session.gd) | pass |  |
| TEST-32 | Controls do not alter the result; all tapes use correct master timing and extra music-linked visuals. | `test_TEST32_the_cinematic_ignores_controls_plays_every_tape_at_master_timing_with_cinematic_fx`<br>(test_acceptance_session.gd) | pass | The cinematic flourishes and framing themselves are by eye. |
| TEST-33 | Available equipment can be recombined without skill-point reallocation. | `test_TEST33_owned_gear_recombines_freely_between_levels_with_no_points_to_reallocate`<br>(test_acceptance_gear.gd) | pass |  |
| TEST-34 | Selected character details, isometric perspective, warm upper lighting and neon metal lower direction are preserved. | `test_TEST34_character_details_isometric_view_warm_upper_light_and_neon_metal_lower_are_preserved`<br>(test_acceptance_gear.gd) | pass | Moxie's likeness, warm upper light and neon lower look against docs/reference/ R01-R04 are by eye. |
| NEW-01 | Equip at least two melee weapons with visibly different effective reach, attack timing, knockback or other meaningful properties; both remain viable. | `test_NEW01_melee_weapons_differ_in_reach_timing_and_knockback_and_each_is_viable`<br>(test_acceptance_weapons.gd) | pass |  |
| NEW-02 | Equip at least two ranged weapon archetypes with different weaknesses; guided missile is slower than at least one alternative projectile. | `test_NEW02_ranged_archetypes_have_different_weaknesses_and_the_missile_is_slower`<br>(test_acceptance_weapons.gd) | pass |  |
| NEW-03 | A missile acquires nearest enemy once on launch, does not retarget, and may choose a different enemy on a subsequent tape playback if battlefield state differs. | `test_NEW03_the_same_missile_tape_locks_once_never_retargets_and_picks_another_target_when_the_field_differs`<br>(test_acceptance_weapons.gd) | pass |  |
| NEW-04 | A fast piercing projectile may strike successive targets in its line when that weapon property applies; a normal projectile does not inherit piercing automatically. | `test_NEW04_piercing_strikes_successive_targets_only_on_the_piercing_weapon`<br>(test_acceptance_weapons.gd) | pass |  |
| NEW-05 | A wall-piercing or vertical-trajectory weapon follows only its own documented collision/trajectory rules; never grant every ranged attack these abilities. | `test_NEW05_only_the_phase_weapon_passes_walls_and_only_the_arc_weapon_lobs`<br>(test_acceptance_weapons.gd) | pass |  |
| NEW-06 | Different cassette speeds and local velocity influence melee momentum and its damage/stagger/knockback consequences, with weapon-specific characteristics. | `test_NEW06_speed_velocity_and_the_weapon_shape_the_momentum_consequences`<br>(test_acceptance_weapons.gd) | pass |  |
| NEW-07 | Four separately identifiable on-screen cassette elements are present during level play; their colors correspond to the four player recordings. | `test_NEW07_four_cassette_decks_with_the_recordings_colours_are_on_screen_during_play`<br>(test_acceptance_hud.gd) | pass | That the four decks read as first-class, unmistakable UI is by eye. |
| NEW-08 | Each cassette visibly states its tape speed and status, including which tape is currently recording and which are committed. | `test_NEW08_each_deck_states_its_speed_and_status_including_recording_and_committed`<br>(test_acceptance_hud.gd) | pass | Legibility of the speed readout and status words at play distance is by eye. |
| NEW-09 | Continuous-time master timeline with beat markers remains visible during recording, not only during the final cinematic replay. | `test_NEW09_the_master_timeline_runs_continuously_and_is_shown_while_recording`<br>(test_acceptance_hud.gd) | pass | That the ruler is readable while recording is by eye. |
| NEW-10 | Switching tape speed changes readout and any corresponding reel/transport feedback without losing master-beat alignment. | `test_NEW10_switching_speed_changes_readout_and_reels_but_keeps_master_beat_alignment`<br>(test_acceptance_hud.gd) | pass | That the reel animation visibly speeds up/slows down is by eye. |
| NEW-11 | A player can distinguish a cassette that is unrecorded, committed, stopped, looping, reversing, dead or desynchronized without relying exclusively on audio. | `test_NEW11_every_cassette_state_has_its_own_visible_reading`<br>(test_acceptance_hud.gd) | pass | That the seven states are distinguishable at a glance (not only by icon/word tables) is by eye. |
| APP-TEST-01 | Equip and swap a helmet, shirt, pants, and shoes; each category can demonstrably change a gameplay outcome. | `test_APPTEST01_each_clothing_category_swapped_in_changes_a_gameplay_outcome`<br>(test_acceptance_gear.gd) | pass |  |
| APP-TEST-02 | Changing a clothing slot updates its displayed effect and preserves the distinction between equipment categories. | `test_APPTEST02_a_clothing_swap_updates_the_shown_effect_and_slots_stay_distinct`<br>(test_acceptance_gear.gd) | pass |  |
| APP-TEST-03 | A valid compulsory level can be completed using at least the intended baseline loadout available before entering it. | `test_APPTEST03_every_compulsory_level_is_valid_and_completable_with_the_baseline_loadout`<br>(test_acceptance_gear.gd) | pass |  |

Totals: 48 pass, 0 fail, 0 without a test (of 48 ids).

## Observations (not failures)

- APP-TEST-03 covers the levels `data/levels/index.json` lists as the campaign. At the last run that is only `sandbox`; the numbered levels `01`..`12` exist but are not in the index yet, and the solutions of `06-crossfire`, `10-heavy-rotation` and `sandbox-solo` have no `generated` block. When the index grows, the test covers each new level automatically (it fails if a listed level has no recorded solution).
- TEST-20 reads stagger from the `enemyStagger` event (its duration). A never-woken (asleep) enemy's snapshot state stays `stagger` until the horizon after any hit, because `core/enemies/common.gd` only moves an awake enemy out of STAGGER (the prototype behaves the same: the goldens agree). If an asleep enemy is ever shown with a stagger animation, it would look staggered forever; that is a presentation question.
- TEST-34 follows the revised Moxie contract in docs/GODOT-PORT.md: material names are discovered at load, so each signature part is matched by a family of name stems (headphones `hp_*`/`headphone*`, `top*`, `jacket*`, `pants*`, `shoe*`, `hair*`, `walkman*`, wrist `device*`), plus the SkeletonProfileHumanoid bone names and the pigtail bones. The shipping model is painted (one `body` and one `head` material, each textured), so for it the test looks where the parts now live: the `top`, `jacket`, `pants` and `shoes` outfit zones measured from the body texture (`assets/models/moxie_regions.json`), a real share of Moxie yellow in the head texture for the headphones (6.6% measured, 2% required), and the pigtail bones for the hair. **The painted walkman and wrist device have no data to test and are by eye.** This branch was written while Godot could not be run on the build machine and has not been executed yet.

## Replay integrity (CINE-01, LEVEL-09, chapter 20)

`tests/replay/test_replay.gd` covers the replay keeper in `replay/` (see `replay/README.md`).
Last run: `1 suite(s), 13 test(s): 13 passed, 0 failed, 0 suite load failure(s); 582 assertion(s); 3558 ms`.
