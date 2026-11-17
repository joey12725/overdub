"""Probe candidate Hugging Face Spaces: is each one up, and what is its API?"""
import sys, json
from gradio_client import Client
spaces = sys.argv[1:] or [
 "tencent/Hunyuan3D-2", "tencent/Hunyuan3D-2mv", "tencent/Hunyuan3D-2.1", "tencent/Hunyuan3D-2mini-Turbo",
 "trellis-community/TRELLIS", "microsoft/TRELLIS", "microsoft/TRELLIS.2", "VAST-AI/TripoSG", "TencentARC/InstantMesh",
 "stabilityai/stable-fast-3d", "VAST-AI/TripoSR", "Stable-X/Hi3DGen", "wushuang98/Direct3D-S2-v1.0-demo",
 "VAST-AI/MV-Adapter-Img2Texture", "VAST-AI/UniRig", "Qwen/Qwen-Image-Edit", "Qwen/Qwen-Image-Edit-2509",
 "black-forest-labs/FLUX.1-Kontext-Dev", "multimodalart/Qwen-Image-Edit-Fast", "linoyts/Qwen-Image-Edit-Angles",
]
for s in spaces:
    try:
        c = Client(s, verbose=False)
        api = c.view_api(return_format="dict")
        eps = list(api.get("named_endpoints", {}).keys())
        print("OK  ", s, eps)
    except Exception as e:
        print("FAIL", s, type(e).__name__, str(e)[:150])
