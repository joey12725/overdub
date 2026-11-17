# Licences — Moxie candidate E

| What | Source | Terms | How it is used |
|---|---|---|---|
| Model sheets (`docs/reference/generated/`) | Generated with gpt-image-2.6-sunburst through the project's image proxy (`tools/img`), from the creator's own concept art (R01/R02) | Output of the project's own image-model account; the creator's art | Inputs to the 3D generation, source of every texel of the albedo |
| Shape model **Hunyuan3D-2mv** (`hunyuan3d-dit-v2-mv`, fp16) | Tencent, https://huggingface.co/tencent/Hunyuan3D-2mv — downloaded to `C:\Users\joeya\.t3\tools\gen-local\models\hunyuan3d-dit-v2-mv` (not in the repo), run locally on the RTX 3080 | **Tencent Hunyuan 3D 2.0 Community License** (text read from the local checkout's `LICENSE`). Section 6(d): "Tencent claims no rights in Outputs You generate." **But section 5(c): "You must not use, reproduce, modify, distribute, or display the Tencent Hunyuan 3D 2.0 Works, Output or results ... outside the Territory", and the Territory is the world excluding the European Union, the United Kingdom and South Korea.** Section 5(b) forbids using Outputs to improve other AI models; an acceptable-use policy applies. **SHIPPING RISK: as written, a game that contains this mesh may not be distributed in the EU, UK or South Korea. The creator must decide on this before candidate E ships** (see "If the licence is a blocker" below). | Generated the raw body and head meshes (`art/moxie_e/gen/raw/*.glb`). Only the resulting geometry is in the repo, cleaned, decimated and re-textured. |
| Hunyuan3D-2 inference code (`hy3dgen`) | Tencent, https://github.com/Tencent/Hunyuan3D-2 — a checkout another artist placed at `C:\Users\joeya\.t3\tools\gen-local\Hunyuan3D-2` | Same Tencent Hunyuan 3D 2.0 Community License | Run only; nothing copied into the repo |
| DINOv2 image encoder (inside the checkpoint) | Meta | Apache-2.0 | Part of the shape model |
| **Universal Animation Library** (`art/moxie_e/dl/ual/UAL1_Standard.glb`) | Quaternius, https://quaternius.com/packs/universalanimationlibrary.html | **CC0 1.0** (public domain), licence text in `art/moxie_e/dl/ual/License.txt` | Source motion for the nine clips in `assets/anim/candidates/e/moxie_anims.res` (retargeted, time-normalised). The mannequin mesh is not used. |
| Godot `SkeletonProfileHumanoid` reference pose (`art/moxie_e/godot_humanoid_profile.json`) | Dumped from Godot 4.4.1 by candidate A | MIT (Godot Engine) | Bone names, hierarchy and rest orientations of the skeleton |
| Blender 4.5, Rigify add-on | Blender Foundation | GPL (tools; output is unencumbered) | Mesh processing, rig, control rig |
| ComfyUI portable Python (torch 2.4.1+cu124) | Already on the machine | Used read-only as an interpreter; nothing installed | Runs the shape model |

Online image-to-3D services were tried first and produced nothing (anonymous GPU quota exhausted) — see
`art/moxie_e/README.md`. No file from any online 3D service is in this candidate.

## If the licence is a blocker

The Hunyuan-generated geometry is the only encumbered part. Everything else in this candidate carries over to a mesh
from another source: the model sheets, the sheet-projection texture baker (`art/moxie_e/s3_texture.py`), the rig
builder with exact Godot humanoid rest orientations (`s4_rig.py`), the retarget and clip builder (`s6_anim.py`), the
control rig (`s8_control.py`) and the Godot check. Options: (a) regenerate the shape with a generator whose terms allow
worldwide distribution of outputs (the pipeline takes any mesh registered to the sheets: replace
`art/moxie_e/gen/raw/*.glb` and re-run steps 1-8), or (b) restrict distribution to the licence's Territory.
