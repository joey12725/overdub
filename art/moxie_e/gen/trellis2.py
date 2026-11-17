import sys, os, shutil, time
from gradio_client import Client, handle_file
tag, img, res = sys.argv[1], sys.argv[2], sys.argv[3]
c = Client('jainarham/trellis-3d-api', verbose=False)
print('status:', c.predict(api_name='/check_status'))
t = time.time()
r = c.predict(image=handle_file(img), seed=7, randomize_seed=False, resolution=res,
              decimation_target=300000, texture_size=2048, api_name='/handle_image_to_3d')
print('took', time.time() - t); print(r)
os.makedirs('raw', exist_ok=True)
for i, x in enumerate(r[:2]):
    if isinstance(x, str) and os.path.exists(x):
        shutil.copy(x, f'raw/{tag}_{i}{os.path.splitext(x)[1]}'); print('saved', i, os.path.getsize(x))
