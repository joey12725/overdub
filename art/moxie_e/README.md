# Moxie — candidate E (model sheets -> image-to-3D -> Blender)

Route: generate orthographic model sheets with the image model, turn them into geometry with a multi-view
image-to-3D model, then register, re-texture from the sheets, rig and animate in Blender.

## Deliverables

| Path | What |
|---|---|
| `assets/models/candidates/e/moxie.glb` | 71,998 triangles, 1.59 units tall, faces +Z, origin on the floor between the feet, node `Rig` > `Skeleton3D` (27 bones), one mesh `Moxie`, two materials `body` and `head` with a 2k albedo each (embedded; Godot extracts them as `moxie_moxie_body.png` / `moxie_moxie_head.png`), nine animations |
| `assets/models/candidates/e/moxie_body.png`, `moxie_head.png` | the baked albedos (same pixels as the embedded ones; the Blender file reads these) |
| `assets/models/candidates/e/moxie_head_grin.png` | alternate head albedo with her grin — swap it onto the `head` material for an expression change (there are no blend shapes) |
| `assets/models/candidates/e/LICENSES.md` | terms of everything used. **Read the Hunyuan row: outputs may not be distributed in the EU, UK or South Korea.** |
| `assets/anim/candidates/e/moxie_anims.res` | `AnimationLibrary`: loops `idle` 2.5 s, `run` 0.933 s, `stopped` 1.667 s; one-shots of exactly 1.0 s `light`, `heavy`, `dodge`, `ranged`, `interact`, `death`. Track paths `Rig/Skeleton3D:<Bone>`, humanoid bones only. |
| `art/moxie_e/moxie.blend` | mesh + export skeleton `Rig` (clips on muted NLA tracks) + Rigify control rig `MoxieControl` (hidden) + text block `moxie_control_rig.py` |
| `tools/moxie_e_check.gd` | `bash tools/gd shot res://tools/moxie_e_check.gd` — loads the glb, verifies the humanoid mapping / hierarchy / rest orientations / size / facing / clip contract, plays every clip, writes screenshots to `art/previews/moxie_e/godot/`. Adapted from candidate A's check so the candidates are judged alike. Last run: `RESULT OK`. |
| `art/previews/moxie_e/` | `turnaround.png`, `face.png`, `face_overlay.png` + `face_check.json`, `toon_iso.png` (Godot, game toon + outline shader, ortho yaw 45 pitch 35), `thumb.png` (160 px), `tpose.png`, `deform_tests.png`, `anim_<clip>.png` + `anim_all.png`, `candidates.png` (raw generator outputs), `godot/` (engine screenshots, clip strips) |
| `docs/reference/generated/` | the model sheets, with their own README |

## What was tried for the 3D step

Online, without an account (Hugging Face Spaces through `gradio_client`, scripts in `gen/`):
`tencent/Hunyuan3D-2mv`, `tencent/Hunyuan3D-2`, `tencent/Hunyuan3D-2.1`, `VAST-AI/TripoSG` — all answer the API but
refuse to run: "You have exceeded your ZeroGPU runs limit / quota (0 s left)" for anonymous callers from this
address. `jainarham/trellis-3d-api`: "Expired ZeroGPU proxy token". `trellis-community/TRELLIS`: read timeout.
`stabilityai/stable-fast-3d`: upstream exception. `microsoft/TRELLIS`: space in CONFIG_ERROR. `microsoft/TRELLIS.2`,
`Stable-X/Hi3DGen`, `TencentARC/InstantMesh` are ZeroGPU spaces under the same exhausted quota and were not run.
No Hugging Face token was used (the brief said "without an account").

What worked: the same multi-view model run **locally**. `gen/fetch_mv.py` downloads the Hunyuan3D-2mv shape
checkpoint (4.9 GB, sha256 verified) to `C:\Users\joeya\.t3\tools\gen-local\models\hunyuan3d-dit-v2-mv`;
`gen/gen3d_mv.py` runs it on the RTX 3080 with the ComfyUI portable Python (read-only) and the `hy3dgen` checkout
another artist left in `gen-local` (peak 5.6 GB VRAM, 70-130 s per mesh, shape only — its texture stage is not
installed, and is not needed). Three generations are used:

- body: front + left + back A-pose sheets -> `gen/raw/body_flb.glb`
- head with hair and headphones: head front + left + back -> `gen/raw/head_full_s11.glb`
- clean face: the hair-pulled-back head sheets, front + left -> `gen/raw/head_bare_s11.glb`

The first pass of this candidate (before the reboot) had fallen back to an inflated-silhouette relief; that is
deleted and nothing of it ships.

## Pipeline (run in this order; every step is re-runnable)

```
PY=C:/Users/joeya/.t3/tools/venv-gen/Scripts/python.exe          (numpy, scipy, PIL, trimesh)
BL="C:/Users/joeya/.t3/tools/blender-4.5.16-windows-x64/blender.exe" --background --threads 6 --python
$PY -I s1_align.py      register the three raw meshes to the sheets (silhouette fit), lay the clean face into the hair head
$BL s2_mesh.py          cut head/body at the choker, drop floaters, decimate (44k body + 28k head), UV unwrap
$PY -I s3_texture.py    bake both 2k albedos by projecting the sheets (add --grin for the grin head)
$BL s4_rig.py           joints from sheet landmarks, bone-heat weights, A-pose -> exact T-pose, Godot-profile skeleton
$BL s5_deform.py        T-pose sheet + weight test poses
$BL s6_anim.py          retarget the UAL clips, contact sheets, save moxie.blend, export moxie.glb
$BL s8_control.py       Rigify control rig into moxie.blend
$BL s7_previews.py      turnaround / face / iso renders + head renders in the head sheets' pixel frame
$PY -I s7_measure.py    face check against the sheet, preview tiling
$PY -I s9_finalize.py   publish the sheets, candidates.png
bash tools/gd script res://art/moxie_e/godot/build_anim_lib.gd     glb animations -> moxie_anims.res
bash tools/gd shot   res://tools/moxie_e_check.gd
```
`s1` needs the raw meshes (`gen/raw/`); its outputs `work/*.ply` are deleted to save space and come back when it runs.

## How the head was built and checked (the creator's "face shape is not there yet")

- A dedicated head sheet was drawn at 3.26x the body-sheet scale, plus a variant with the headphones removed and the
  hair pulled flat, registered pixel-for-pixel with it. The head is its own generation at octree 384 (about 1.4 mm
  cells, against 5 mm on the body), and the face comes from the hair-pulled-back generation: `s1_align.py` turns that
  clean face into a depth map and lays the hair head's face region onto it, leaving any hair strand that stands more
  than about 5 mm proud of the skin alone. Result: the sheet's short round cranium, wide cheekbones, small pointed chin
  and tiny nose are real geometry under the fringe, not a smeared average.
- Checks (numbers from the last run):
  - clean-face mesh against the hair-pulled-back sheet, silhouette IoU: 0.973 front, 0.871 side;
  - head rendered orthographically in the head sheet's own pixel frame (`face_overlay.png`), landmarks measured with
    PIL (`face_check.json`), as a share of head height (crown to chin, 590 px):
    iris centres 0.07 % and 0.12 % off, eye spacing -0.34 %; profile nose tip 0.53 %, chin 0.54 %, profile curve
    brow to under-chin RMS 0.59 %; the brow point is 2.2 % off (it sits under the fringe, where sheet and mesh hair differ);
  - whole head silhouette (hair included) IoU 0.80 front: the generated pigtails do not follow the drawn spikes one for one.
- Two caveats on those numbers. The iris agreement in the front view is partly by construction: the eyes are painted
  from that same sheet. The profile numbers are the honest geometric ones. And `face_check.json` contains a
  "side iris" error of 11 %: that is not a placement error but the absence of a profile eye — see "What falls short".

## Texture

Every texel is sampled from the sheets (front / back / left / right for the body; head front / back / left and the
mirrored left for her right side), visibility-tested against the mesh, blended by facing^4. The sheets' outer ink line
is removed before projection (the game draws its own outline). 28 % of texels are seen by no sheet (tops, undersides,
inner arms and legs, under the jacket) and take the colour of the nearest painted texel in 3D.

## Rig

- Bones: `Hips, Spine, Chest, UpperChest, Neck, Head, Left/Right Shoulder, UpperArm, LowerArm, Hand, UpperLeg,
  LowerLeg, Foot, Toes` with Godot `SkeletonProfileHumanoid` names, hierarchy and **rest orientations identical to the
  profile's reference pose** (the check reports 0.000 degrees worst deviation), so a library already retargeted to the
  Godot humanoid profile plays on her without rest fixing. Secondary bones: `PigtailL1/L2`, `PigtailR1/R2` (children of
  `Head`), `JacketBack` (child of `UpperChest`) — not touched by the clips, free for spring-bone motion.
- Rest is an exact T-pose for the arms (left arm direction (1, 0, 0)); the legs keep the sheet's slight stance
  (5 degrees out). No transforms on any node.
- Skin: bone heat on a watertight voxel proxy, transferred to the mesh, smoothed, 4 influences. The head part is
  weighted procedurally (Head, Neck under the chin, pigtail chains).
- Attachments as in `docs/GODOT-PORT.md`: weapon on `RightHand`, wrist device on `LeftLowerArm`.
- Control rig: in `moxie.blend`, open the text block `moxie_control_rig.py`, run it, call `control(True)`; animate
  `MoxieControl` (IK/FK arms and legs, spine, head); `bake("clip")` writes the result onto `Rig`.

## Animations

Quaternius Universal Animation Library (CC0), retargeted in `s6_anim.py` by world-space rotation deltas (limbs are
aimed where the source limbs point, hips scaled by leg length 0.894), baked at 30 fps:
`idle` Idle_Loop, `run` Jog_Fwd_Loop, `stopped` Sword_Idle, `light` Sword_Attack, `heavy` Punch_Cross, `dodge` Roll,
`ranged` Pistol_Shoot, `interact` Interact, `death` Death01. For `light` and `heavy` the hit (the span where the right
hand moves fastest) is time-warped onto 40-60 % of the second. `dodge` and the loops are made in-place.

## What falls short (against R01)

- **Licence**: the geometry is an output of Hunyuan3D-2mv; its licence forbids distributing outputs in the EU, UK and
  South Korea. This alone may rule the candidate out. See `LICENSES.md`.
- **No fingers rigged.** The hands are generated mitten-like shapes with finger grooves; the profile's finger bones are
  absent (they are optional), so finger animation is ignored and the hands stay open.
- **The jacket is fused to the body.** It is one skin with the torso and arms, so with the arms up or in the T-pose it
  stretches into a web under the arms and across the back (`tpose.png`, `deform_tests.png` "overhead"). It reads well
  with the arms below shoulder height, which is where the game clips keep them most of the time.
- **Belt gear, straps and cables are fused relief**, not separate dangling parts; they deform with the hips and thighs.
- **Exact side view of the face**: the eye is painted from the front, as on most anime models, so in a strict profile
  there is no drawn profile eye and the cheek shows a faint projection seam. Front and three-quarter views (the game
  camera) hold up; a profile close-up in a cutscene would not.
- **Texture is a projection, not a paint job**: the sheet's cel shading and highlights are baked into the albedo (fine
  for an unlit/toon look, wrong under strong directional light); surfaces no sheet sees are filled by neighbours
  (inner thighs, tops of the shoulders and boots, the crown of the hair), and hair tips came out a paler orange than
  the sheet. The headphone cups show fragments of a second triangle mark from behind. There is a visible join at the
  neck inside the choker, and the choker ring sits a little low.
- **No material hooks**: materials are `body` and `head`; there are no `top` / `pants` / `shoes` tint materials and no
  `*_glow` emissive parts (the wrist screens and the vial are just albedo). Wardrobe tinting would need the atlas split.
- **No blend shapes**; expressions are texture swaps (neutral, grin).
- **Topology is decimated marching-cubes triangles**, not animation-friendly quads with edge loops. 72k triangles.
- **Silhouette**: body IoU against the sheets is 0.88 front / 0.80 side; the pigtails are fuller and less spiky than drawn.
- **Clips are library motion**, not Moxie's own acting: `heavy` is a punch, `ranged` is a pistol shot stretched from
  0.63 s to 1 s, `stopped` is a sword-ready stance. Feet can slide a little (leg proportions differ from the mannequin).
- Not done: a top-down sheet (would fix most of the unpainted tops), per-part separation for wardrobe swaps.
