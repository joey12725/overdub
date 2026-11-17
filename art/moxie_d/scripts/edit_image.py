"""Image-edit helper: redraw reference art (pose / view changes) through a public HF Space.
usage: edit_image.py <space> <out.png> <prompt> <seed> <w> <h> <img> [img...]
spaces: Qwen/Qwen-Image-Edit-2509 (multi-image), Qwen/Qwen-Image-Edit, black-forest-labs/FLUX.1-Kontext-Dev"""
import sys, shutil
from gradio_client import Client, handle_file
space, out, prompt, seed, w, h = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
imgs = sys.argv[7:]
c = Client(space, verbose=False)
if "Kontext" in space:
    r = c.predict(input_image=handle_file(imgs[0]), prompt=prompt, seed=seed, randomize_seed=False, guidance_scale=2.5, steps=28, api_name="/infer")
    path = r[0]["path"] if isinstance(r[0], dict) else r[0]
elif "2509" in space:
    r = c.predict(images=[{"image": handle_file(i), "caption": None} for i in imgs], prompt=prompt, seed=seed, randomize_seed=False,
                  true_guidance_scale=4.0, num_inference_steps=40, height=h, width=w, rewrite_prompt=False, api_name="/infer")
    path = r[0][0]["image"]
    path = path["path"] if isinstance(path, dict) else path
else:
    raise SystemExit("see api first")
shutil.copy(path, out); print("saved", out)
