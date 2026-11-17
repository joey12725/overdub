"""Image-to-3D through public Hugging Face Spaces (no account / token).
usage: gen3d.py <service> <out_stem> --front f.png [--back b.png --left l.png --right r.png] [--seed N] [--shape-only]
services: hy2 | hy2mv | hy21 | trellis2 | triposg | instantmesh | sf3d | hi3dgen
Outputs go to art/moxie_d/gen/<out_stem>*.glb"""
import sys, shutil, argparse, os, json, time
from gradio_client import Client, handle_file
ap = argparse.ArgumentParser()
ap.add_argument("service"); ap.add_argument("stem")
ap.add_argument("--front"); ap.add_argument("--back"); ap.add_argument("--left"); ap.add_argument("--right")
ap.add_argument("--seed", type=int, default=1234); ap.add_argument("--shape-only", action="store_true")
ap.add_argument("--steps", type=int, default=30); ap.add_argument("--octree", type=int, default=384)
a = ap.parse_args()
OUT = os.path.join(os.path.dirname(__file__), "..", "gen")
def hf(p): return handle_file(p) if p else None
def keep(src, suffix):
    if not src: return
    if isinstance(src, dict): src = src.get("path") or src.get("value")
    ext = os.path.splitext(src)[1] or ".glb"
    dst = os.path.join(OUT, a.stem + suffix + ext); shutil.copy(src, dst); print("saved", os.path.normpath(dst), os.path.getsize(dst))
SPACES = {"hy2": "tencent/Hunyuan3D-2", "hy2mv": "tencent/Hunyuan3D-2mv", "hy21": "tencent/Hunyuan3D-2.1", "trellis2": "microsoft/TRELLIS.2",
          "triposg": "VAST-AI/TripoSG", "instantmesh": "TencentARC/InstantMesh", "sf3d": "stabilityai/stable-fast-3d", "hi3dgen": "Stable-X/Hi3DGen"}
c = Client(SPACES[a.service], verbose=False)
t0 = time.time()
if a.service in ("hy2", "hy2mv", "hy21"):
    kw = dict(steps=a.steps, guidance_scale=5.0, seed=a.seed, octree_resolution=a.octree, check_box_rembg=True, num_chunks=8000, randomize_seed=False)
    if a.service == "hy2mv": kw.update(image=None, mv_image_front=hf(a.front), mv_image_back=hf(a.back), mv_image_left=hf(a.left), mv_image_right=hf(a.right))
    else: kw.update(image=hf(a.front), mv_image_front=None, mv_image_back=None, mv_image_left=None, mv_image_right=None)
    if a.service != "hy21": kw["caption"] = None
    if a.shape_only:
        r = c.predict(api_name="/shape_generation", **kw); keep(r[0], "_shape"); print(r[2])
    else:
        r = c.predict(api_name="/generation_all", **kw); keep(r[0], "_shape"); keep(r[1], "_tex"); print(r[3])
elif a.service == "trellis2":
    c.predict(api_name="/start_session")
    im = c.predict(input=hf(a.front), api_name="/preprocess_image")
    c.predict(image=handle_file(im["path"] if isinstance(im, dict) else im), seed=a.seed, resolution="1024", api_name="/image_to_3d")
    r = c.predict(decimation_target=300000, texture_size=2048, api_name="/extract_glb"); keep(r[1] or r[0], "_tex")
elif a.service == "sf3d":
    r = c.predict(hf(a.front), 0.85, "none", 0, 1024, api_name="/run_button"); print(r); keep(r[0] if not isinstance(r, str) else r, "_tex")
else:
    c.view_api(); raise SystemExit("endpoint wiring needed")
print("elapsed %.0fs" % (time.time() - t0))
