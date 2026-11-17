import sys, os, shutil, json, time
from gradio_client import Client, handle_file
tag = sys.argv[1]; left_key = sys.argv[2]; right_key = sys.argv[3]
steps = int(sys.argv[4]) if len(sys.argv) > 4 else 30
octree = int(sys.argv[5]) if len(sys.argv) > 5 else 384
space = sys.argv[6] if len(sys.argv) > 6 else 'tencent/Hunyuan3D-2mv'
api = sys.argv[7] if len(sys.argv) > 7 else '/shape_generation'
I = os.path.join(os.path.dirname(__file__), 'inputs')
f = lambda n: handle_file(os.path.join(I, n + '.png')) if n != 'none' else None
c = Client(space, verbose=False)
t = time.time()
r = c.predict(caption=None, image=None, mv_image_front=f('front'), mv_image_back=f('back'),
              mv_image_left=f(left_key), mv_image_right=f(right_key), steps=steps, guidance_scale=5.0, seed=1234,
              octree_resolution=octree, check_box_rembg=False, num_chunks=8000, randomize_seed=False, api_name=api)
print('took', time.time() - t); print(r)
os.makedirs('raw', exist_ok=True)
files = [x for x in r if isinstance(x, (str, dict))][:2]
for i, x in enumerate(files):
    p = x['value'] if isinstance(x, dict) and 'value' in x else (x.get('path') if isinstance(x, dict) else x)
    if p and os.path.exists(str(p)):
        ext = os.path.splitext(p)[1]
        shutil.copy(p, f'raw/{tag}_{i}{ext}'); print('saved', f'raw/{tag}_{i}{ext}', os.path.getsize(p))
