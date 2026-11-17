"""Local image-to-3D with Tencent Hunyuan3D-2 (shape model hunyuan3d-dit-v2-0, fp16) on the RTX 3080.
Run with a Python that has torch+CUDA (the ComfyUI portable interpreter is used read-only; nothing is installed into it):
  <python_embeded>/python.exe gen3d_local.py <rgba.png> <out.glb> [--seed 1234] [--steps 50] [--octree 384] [--guidance 5.0]
Memory-lean loader: weights are read straight to the GPU and assigned into empty modules, so system RAM stays low."""
import sys, os, types, argparse, time
GL = os.environ.get("GEN_LOCAL", r"C:\Users\joeya\.t3\tools\gen-local")
sys.path[:0] = [os.path.join(GL, "extras"), os.path.join(GL, "Hunyuan3D-2")]
sys.modules.setdefault("pymeshlab", types.ModuleType("pymeshlab"))  # only used by optional post-processors
sys.modules["pymeshlab"].MeshSet = object
ap = argparse.ArgumentParser()
ap.add_argument("image"); ap.add_argument("out")
ap.add_argument("--seed", type=int, default=1234); ap.add_argument("--steps", type=int, default=50)
ap.add_argument("--octree", type=int, default=384); ap.add_argument("--guidance", type=float, default=5.0)
ap.add_argument("--chunks", type=int, default=8000)
a = ap.parse_args()
import torch, yaml, safetensors.torch
from PIL import Image
from accelerate import init_empty_weights
from hy3dgen.shapegen.pipelines import Hunyuan3DDiTFlowMatchingPipeline, instantiate_from_config
t0 = time.time()
mdir = os.path.join(GL, "models", "hunyuan3d-dit-v2-0")
config = yaml.safe_load(open(os.path.join(mdir, "config.yaml")))
flat = safetensors.torch.load_file(os.path.join(mdir, "model.fp16.safetensors"), device="cuda")
ckpt = {}
for k, v in flat.items():
    n = k.split(".")[0]; ckpt.setdefault(n, {})[k[len(n) + 1:]] = v
del flat
def lean(cfg, sd):
    with init_empty_weights(): m = instantiate_from_config(cfg)
    missing, unexpected = m.load_state_dict(sd, strict=False, assign=True)
    assert not missing, missing[:5]
    return m
model = lean(config["model"], ckpt["model"])
conditioner = lean(config["conditioner"], ckpt["conditioner"])
vae = instantiate_from_config(config["vae"]); vae.load_state_dict({k: v.cpu() for k, v in ckpt["vae"].items()}, strict=False)
del ckpt
pipe = Hunyuan3DDiTFlowMatchingPipeline(vae=vae, model=model, scheduler=instantiate_from_config(config["scheduler"]), conditioner=conditioner,
                                        image_processor=instantiate_from_config(config["image_processor"]), device="cuda", dtype=torch.float16)
print("loaded in %.0fs, VRAM %.1f GB" % (time.time() - t0, torch.cuda.memory_allocated() / 2**30))
img = Image.open(a.image).convert("RGBA")
mesh = pipe(image=img, num_inference_steps=a.steps, guidance_scale=a.guidance, octree_resolution=a.octree, num_chunks=a.chunks,
            generator=torch.Generator("cuda").manual_seed(a.seed), output_type="trimesh")[0]
mesh.export(a.out)
print("saved", a.out, "verts", len(mesh.vertices), "faces", len(mesh.faces), "total %.0fs" % (time.time() - t0), "peak VRAM %.1f GB" % (torch.cuda.max_memory_allocated() / 2**30))
