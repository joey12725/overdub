# Square RGBA inputs for the image-to-3D services (generic file names: nothing project-specific leaves the machine)
import os, sys
from PIL import Image
G = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'docs', 'reference', 'generated', 'cut'))
out = os.path.join(os.path.dirname(__file__), 'inputs'); os.makedirs(out, exist_ok=True)
for n in ['front', 'back', 'left', 'right', 'threequarter']:
    im = Image.open(os.path.join(G, f'moxie_{n}.png'))
    sq = Image.new('RGBA', (1536, 1536), (0, 0, 0, 0))
    sq.alpha_composite(im, ((1536 - im.width) // 2, 0))
    sq = sq.crop((0, 40, 1536, 1536)).resize((1024, 998))
    c = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0)); c.alpha_composite(sq, (0, 13))
    c.save(os.path.join(out, f'{n}.png'))
    w = Image.new('RGB', (1024, 1024), (255, 255, 255)); w.paste(c, mask=c.split()[3]); w.save(os.path.join(out, f'{n}_white.png'))
