"""Paints the cargo-pants albedo (system python + PIL):  python -I paint_pants.py  ->  tex/moxie_pants.png

UV layout (see s05_outfit.py): left half of the image = her left leg, right half = her right leg.
Inside a half, u_local 0 = inner seam, 0.25 = front, 0.5 = outer seam, 0.75 = back; v = (z - 0.15) / 0.80.
"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
N = 2048
rnd = random.Random(5)
BASE = (112, 100, 60)
DARK = (88, 78, 46)
LIGHT = (130, 118, 74)
YEL = (242, 182, 31)
SEAM = (70, 66, 38)


def P(side, ul, z):
    """side 'L' / 'R', u_local 0..1, z in metres -> pixel."""
    u = ul * 0.5 + (0.0 if side == 'L' else 0.5)
    v = (z - 0.15) / 0.80
    return (u * N, (1 - v) * N)


img = Image.new("RGB", (N, N), BASE)
# cloth mottling
for col, cnt, rad, alpha in ((DARK, 70, 90, 70), (LIGHT, 70, 80, 60), (DARK, 160, 26, 40)):
    lay = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(lay)
    for _ in range(cnt):
        cx, cy = rnd.uniform(0, N), rnd.uniform(0, N)
        rx, ry = rnd.uniform(0.4, 1.0) * rad, rnd.uniform(0.8, 2.2) * rad
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=alpha)
    lay = lay.filter(ImageFilter.GaussianBlur(rad * 0.45))
    img.paste(Image.new("RGB", (N, N), col), (0, 0), lay)
d = ImageDraw.Draw(img)


def line(side, pts, width_m, col):
    px = [P(side, a, b) for a, b in pts]
    w = max(1, int(width_m / 0.80 * N))
    d.line(px, fill=col, width=w, joint="curve")


def band(side, pts, half_z, col):
    """Thick poly-band: pts are (u_local, z) centre points; thickness measured in z."""
    top = [P(side, a, b + half_z) for a, b in pts]
    bot = [P(side, a, b - half_z) for a, b in pts]
    d.polygon(top + bot[::-1], fill=col)


for side in "LR":
    # seams: outer and inner, double-stitched
    for ul in (0.5, 0.004, 0.996):
        line(side, [(ul, 0.15), (ul, 0.95)], 0.0035, SEAM)
        for o in (-0.012, 0.012):
            for k in range(0, 100):
                z0 = 0.16 + k * 0.008
                line(side, [(ul + o, z0), (ul + o, z0 + 0.004)], 0.0016, LIGHT)
    # grime towards the cuff
    lay = Image.new("L", (N, N), 0)
    ImageDraw.Draw(lay).rectangle([P(side, 0, 0.27)[0], P(side, 0, 0.27)[1], P(side, 1, 0.15)[0], P(side, 1, 0.15)[1]], fill=90)
    lay = lay.filter(ImageFilter.GaussianBlur(40))
    img.paste(Image.new("RGB", (N, N), (70, 64, 40)), (0, 0), lay)
    d = ImageDraw.Draw(img)
    # back pocket stitching
    x0, x1, z0, z1 = 0.66, 0.86, 0.775, 0.865
    for (a, b) in (((x0, z0), (x1, z0)), ((x1, z0), (x1, z1)), ((x1, z1), (x0, z1)), ((x0, z1), (x0, z0))):
        line(side, [a, b], 0.003, SEAM)

# yellow zig-zag on her right leg (front / outer), plus a yellow cuff stripe
zig = [(0.47, 0.545), (0.215, 0.475), (0.435, 0.415), (0.195, 0.345), (0.415, 0.285), (0.22, 0.245)]
for i in range(len(zig) - 1):
    a, b = zig[i], zig[i + 1]
    band('R', [a, b], 0.030, YEL)
band('R', [(0.06, 0.212), (0.47, 0.212)], 0.011, YEL)
# a smaller accent tick on her left thigh
band('L', [(0.40, 0.70), (0.47, 0.675)], 0.008, YEL)
band('L', [(0.40, 0.672), (0.47, 0.647)], 0.008, YEL)

# knee patch round the left-knee tear and frayed threads round both tears
patch = [P('L', 0.16, 0.565), P('L', 0.39, 0.565), P('L', 0.39, 0.45), P('L', 0.16, 0.45)]
d.polygon(patch, fill=(92, 86, 50))
for i in range(4):
    a, b = patch[i], patch[(i + 1) % 4]
    for k in range(24):
        t0, t1 = k / 24, (k + 0.55) / 24
        d.line([(a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0), (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)], fill=LIGHT, width=4)
for side, ul, zc in (('L', 0.269, 0.505), ('R', 0.341, 0.335)):
    c = P(side, ul, zc)
    for k in range(90):
        a = rnd.uniform(0, 2 * math.pi)
        r0 = rnd.uniform(30, 60)
        r1 = r0 + rnd.uniform(14, 46)
        d.line([(c[0] + math.cos(a) * r0 * 1.5, c[1] + math.sin(a) * r0), (c[0] + math.cos(a + 0.2) * r1 * 1.5, c[1] + math.sin(a + 0.2) * r1)],
               fill=(150, 143, 96), width=3)

# fine weave: faint vertical streaks
st = Image.new("L", (N, 1), 0)
sp = st.load()
for i in range(N):
    sp[i, 0] = rnd.randint(0, 7)
st = st.resize((N, N))
img = ImageChops.subtract(img, Image.merge("RGB", (st, st, st)).filter(ImageFilter.GaussianBlur(1)))
os.makedirs(os.path.join(HERE, "tex"), exist_ok=True)
img.save(os.path.join(HERE, "tex", "moxie_pants.png"))
print("wrote tex/moxie_pants.png")
