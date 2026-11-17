# Moxie - candidate C (from-scratch, Python-driven Blender build)

Everything here is generated: there is no hand-edited mesh. `moxie.blend` is the working file
(export skeleton `Rig`, skinned mesh `Moxie`, the nine game clips, and the Rigify control rig
`MoxieControl`); `assets/models/candidates/c/moxie.glb` and
`assets/anim/candidates/c/moxie_anims.res` are what the game loads.

## Rebuild

```
bash art/moxie_c/rebuild.sh                               # model -> clips -> control rig -> glb -> previews
bash tools/gd script res://art/moxie_c/gd_build_anims.gd  # glb clips -> assets/anim/candidates/c/moxie_anims.res
bash tools/gd shot   res://tools/moxie_c_check.gd         # humanoid-profile check + toon-shader screenshots
```

`rebuild.sh` runs one Blender at a time with `--threads 6` and waits while `tools/mem` is above 85.
The animation source must be present at
`art/moxie_c/_dl/ual/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb`
(Quaternius, CC0 - https://quaternius.itch.io/universal-animation-library).

Single steps while iterating:

```
bash art/moxie_c/run.sh [--parts head,hair,body,hands,cloth,gear] [--shots turn,face,...] [--toon]
bash art/moxie_c/rs.sh <shot> [pose] [--toon]     # render a shot of the built model (poses.py)
MC_NOWARP=1 bash art/moxie_c/run.sh --parts head --shots hc --toon && python -I art/moxie_c/ref_compare.py
bash art/moxie_c/rs.sh sheet sheet --toon && python -I art/moxie_c/body_compare.py
```

## Pipeline

| Stage | Files | What it does |
|---|---|---|
| Reference tracing | `ref/head_bald_front_side.png`, `ref_measure.py` | Orthographic front + profile head sheet (hair removed) generated from the concept art with `tools/img`; silhouettes and landmarks are traced numerically into `ref/head_profile_raw.json`. |
| Head | `mc_headshape.py`, `mc_facedef.py`, `mc_head.py` | The head is an implicit surface whose every horizontal slice is a pair of super-ellipses sized by the traced curves (front half-width, profile front, profile back), so its front and side silhouettes ARE the sheet's; cheeks, eye sockets, nose, ears and neck are blended on. A quad cage (cube-sphere) is projected on it, eye and mouth openings are cut with concentric loops and rims, then subdivided and re-projected. Eyes are inset plates with painted irises, lashes are geometry, teeth sit behind the grin. |
| Textures | `mc_paint.py` -> `tex/` | Face (brows, lid creases, blush, cheek marks), eyes and the pants (zig-zag, seams, wear) are painted procedurally with PIL from the same layout numbers the modeller uses. Flat-colour parts share three small palette textures (`mc_finish.py`). |
| Hair | `mc_hair.py` | Scalp shell + tapered strand clumps swept along splines on the head surface: bangs, side locks, sections swept into two ties, two big pigtail balls of crescent locks, a tuft on the crown. |
| Body, hands | `mc_body.py`, `mc_hand.py` | Quad cages projected onto sculpted signed-distance bodies; loops at shoulders, elbows, knuckles; five articulated fingers. |
| Clothing | `mc_cloth.py`, `mc_jacket.py`, `mc_boots.py` | Separate thick meshes with modelled folds: cargo pants ballooning over rolled mid-shin cuffs, crop top + trim, chest strap, gloves, off-the-shoulder jacket (collar rolled out to the yellow lining, sagging pushed-up sleeves), chunky boots with laces. |
| Gear | `mc_gear.py`, `mc_kit.py` | Bevelled hard-surface parts: headphones with the triangle, choker, Walkman + cable, belt kit, hanging gadgets, wrist devices, straps. |
| Skeleton + skin | `mc_rig.py`, `godot_humanoid_ref.json`, `gd_refpose.gd` | Armature `Rig` with Godot `SkeletonProfileHumanoid` names / hierarchy, bone rolls taken from Godot's reference pose, T-pose rest, identity object transform; 13 secondary bones (pigtails x6, jacket x3, straps x4). Skin weights are analytic functions of rest position per garment (max 4 influences). |
| Proportion pass | `mc_proportion.py` | Parts are built in a roomy "build space"; one smooth warp then takes mesh and skeleton to the proportions measured from `docs/reference/generated/moxie_front.png` (upper body x0.80, head x0.775 and lifted, legs lengthened, boots enlarged). Weights travel with the vertices. |
| Clips | `mc_anim.py`, `mc_contact.py` | World-space retarget of Quaternius UAL clips onto `Rig`, resampled at 30 fps; one-shots exactly 1.0 s; `light`/`heavy` re-timed so the wind-up is 0-40 %, the strike 40-60 %, recovery 60-100 % (`heavy` adds a deeper coil layer). |
| Control rig | `mc_ctrl.py`, `mc_ctrl_test.py` | Rigify metarig fitted to the export joints and generated as `MoxieControl` (IK/FK limbs, spine, fingers). Each export bone has a muted Copy Transforms to an `EXP-` helper; the text block `moxie_tools.py` in the .blend has `control_rig(True)` to animate on the controls and `bake_to_export(name)` to bake a clip onto `Rig`. |
| Export | `mc_export.py`, `gd_build_anims.gd` | glTF with only `Rig` + `Moxie`; Godot script builds the `AnimationLibrary` (humanoid-profile bones only, no scale tracks, loops flagged). |
| Checks | `ref_compare.py`, `body_compare.py`, `tools/moxie_c_check.gd` | Numeric head and body comparison against the sheets with 50 % overlays; Godot-side skeleton / contract check. |

## Clip sources (all from `UAL1_Standard.glb`, CC0)

| Game clip | UAL action | Treatment |
|---|---|---|
| idle (loop 2.0 s) | Idle_Loop | resampled |
| run (loop 0.6 s) | Jog_Fwd_Loop | resampled |
| stopped (loop 1.0 s) | Sword_Idle | held first frame |
| light (1.0 s) | Sword_Attack | strike window found from weapon-hand speed, re-timed 40/20/40 |
| heavy (1.0 s) | Sword_Attack | same + extra torso coil / hip drop layer |
| dodge (1.0 s) | Roll | resampled |
| ranged (1.0 s) | Pistol_Shoot | resampled |
| interact (1.0 s) | Interact | resampled |
| death (1.0 s) | Death01 | resampled |

## Measured against the sheets (see `art/previews/moxie_c/head_check.txt`, `body_check.txt`)

Head (units of head height): cranium width 0.748 sheet / 0.752 model; eye line 0.597 / 0.597; eye
spacing 0.172 / 0.172; eye opening 0.171 x 0.098 / 0.169 x 0.104; jaw width at the mouth line
0.491 / 0.484; silhouette error at 19 heights <= 1 % of head height except the ear rows
(the sheet's ears stick out further; they sit under the headphones) and the nose tip (2 %).

Body (metres, soles at 0): crown 1.580 / 1.586, chin 1.414 / 1.420, shoulder line 1.309 / 1.327,
navel 1.103 / 1.075, waistband 1.045 / 1.025, crotch 0.890 / 0.894, cuff 0.315 / 0.312, boot top
0.247 / 0.246; bare shoulder width 0.293 / 0.298; waist 0.150 / 0.142; 9.5 / 9.6 heads tall.

## Contract facts

1 unit = 1 m, Y up, faces +Z in Godot, origin on the floor between the feet; skull crown 1.59 m,
hair tips 1.72 m; 83.9k triangles; one skinned mesh, 14 surfaces: `skin, skin_face, eye, hair_dark,
hair, pants_olive, pants_cuff, pants_dark, top_light, screen_glow, vial_glow, gear, jacket, shoes`
(tint hooks `top*`, `pants*`, `shoes*`; emissive `*_glow`).
