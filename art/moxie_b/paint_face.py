"""Paints Moxie's skin/face albedo (system python + PIL):  python -I paint_face.py
Reads _stage/landmarks.json (written by s02_body.py), writes tex/moxie_skin.png (2048x2048).

The face front is UV-mapped by a planar front projection (see FACE_SPAN / uv_of in s03_face.py):
    u = 0.5 + x / FACE_SPAN,  v = 0.5 + (z - zc) / FACE_SPAN,  zc = z_eye - 0.02
so everything here is drawn in metres on the face plane (x = her left, z = up) exactly as seen from the front.
Everything that is not the face front samples the plain skin colour in the bottom-left corner.
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mb_eye import outline

HERE = os.path.dirname(os.path.abspath(__file__))
L = json.load(open(os.path.join(HERE, "_stage", "landmarks.json")))
FACE_SPAN = 0.27
SS = 2                      # supersampling
N = 2048 * SS
ZC = L["z_eye"] - 0.02

SKIN = (201, 136, 92)
SKIN_SH = (160, 96, 66)
LINE = (74, 34, 24)
LASH = (30, 17, 14)
BROW = (40, 24, 19)
SCLERA = (250, 245, 238)
SCLERA_SH = (190, 172, 176)
IRIS_RIM = (72, 34, 12)
IRIS = (196, 112, 22)
IRIS_LO = (250, 190, 52)
PUPIL = (36, 16, 8)
TEETH = (253, 249, 242)
BLUSH = (226, 104, 84)
PAINT_W = (246, 238, 222)
PAINT_R = (214, 52, 70)


def px(x, z):
    return ((0.5 + x / FACE_SPAN) * N, (0.5 - (z - ZC) / FACE_SPAN) * N)


def mm(v):
    return v / FACE_SPAN * N


img = Image.new("RGB", (N, N), SKIN)


def poly_mask(pts):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).polygon([px(*p) for p in pts], fill=255)
    return m


def ell_mask(cx, cz, rx, rz, rot=0.0):
    pts = []
    for i in range(96):
        t = 2 * math.pi * i / 96
        a, b = rx * math.cos(t), rz * math.sin(t)
        pts.append((cx + a * math.cos(rot) - b * math.sin(rot), cz + a * math.sin(rot) + b * math.cos(rot)))
    return poly_mask(pts)


def fill(mask, color, alpha=1.0):
    global img
    if alpha < 1.0:
        mask = mask.point(lambda v: int(v * alpha))
    img.paste(Image.new("RGB", (N, N), color), (0, 0), mask)


def stroke(pts, width_fn, color):
    """Variable-width stroke through pts (metres); width_fn(t in 0..1) -> width in metres."""
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    n = len(pts)
    left, right = [], []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        tx, tz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(tx, tz) or 1e-9
        nx, nz = -tz / ln, tx / ln
        w = width_fn(i / (n - 1)) * 0.5
        left.append((p[0] + nx * w, p[1] + nz * w))
        right.append((p[0] - nx * w, p[1] - nz * w))
    d.polygon([px(*q) for q in left + right[::-1]], fill=255)
    fill(m, color)


def soft(mask, radius_m):
    return mask.filter(ImageFilter.GaussianBlur(mm(radius_m)))


W, HU, HL, TILT = L["eye_w"], L["eye_hu"], L["eye_hl"], L["tilt"]


def eye_pt(sign, c, theta, grow=0.0):
    a, b = outline(theta, W, HU, HL, TILT)
    if grow:
        # offset along the outward normal (finite difference)
        a2, b2 = outline(theta + 0.01, W, HU, HL, TILT)
        tx, tz = a2 - a, b2 - b
        ln = math.hypot(tx, tz) or 1e-9
        a += tz / ln * grow
        b += -tx / ln * grow
    return (c[0] + sign * a, c[2] + b)


def paint_eye(sign, c):
    lid = [eye_pt(sign, c, 2 * math.pi * i / 160) for i in range(160)]
    lid_big = [eye_pt(sign, c, 2 * math.pi * i / 160, grow=0.0012) for i in range(160)]
    M = poly_mask(lid_big)
    fill(M, SCLERA)
    # shadow cast by the upper lid
    sh = ImageChops.subtract(M, ImageChops.offset(M, 0, int(mm(0.0075))))
    fill(sh, SCLERA_SH)
    # iris
    icx = c[0] - sign * 0.0012
    icz = c[2] + 0.0030
    rz = 0.5 * (HU + HL)
    rx = 0.84 * rz
    k = rz / 0.0152
    iris = ImageChops.multiply(ell_mask(icx, icz, rx, rz), M)
    fill(iris, IRIS_RIM)
    fill(ImageChops.multiply(ell_mask(icx, icz, rx * 0.86, rz * 0.86), M), IRIS)
    lo = ImageChops.multiply(ImageChops.multiply(ell_mask(icx, icz - rz * 0.42, rx * 0.74, rz * 0.5), ell_mask(icx, icz, rx * 0.86, rz * 0.86)), M)
    fill(lo, IRIS_LO)
    # upper iris shadow
    top = ImageChops.multiply(iris, ImageChops.subtract(M, ImageChops.offset(M, 0, int(mm(0.0125)))))
    fill(top, IRIS_RIM, 0.8)
    fill(ImageChops.multiply(ell_mask(icx, icz + 0.001, rx * 0.40, rz * 0.46), M), PUPIL)
    # radial flecks in the iris
    for i in range(14):
        t = math.pi * (1.08 + 0.84 * i / 13)
        p0 = (icx + math.cos(t) * rx * 0.48, icz + math.sin(t) * rz * 0.5)
        p1 = (icx + math.cos(t) * rx * 0.80, icz + math.sin(t) * rz * 0.82)
        stroke([p0, p1], lambda q: 0.0005, (224, 150, 36))
    # highlights (same image side on both eyes)
    fill(ImageChops.multiply(ell_mask(icx - 0.0050 * k, icz + 0.0062 * k, 0.0034 * k, 0.0042 * k, 0.5), M), (255, 255, 255))
    fill(ImageChops.multiply(ell_mask(icx + 0.0046 * k, icz - 0.0062 * k, 0.0015 * k, 0.0019 * k), M), (255, 246, 214))
    # lower lid line (outer half) and inner-corner tick
    stroke([eye_pt(sign, c, -math.pi * (0.04 + 0.52 * i / 30), grow=0.0002) for i in range(31)],
           lambda q: 0.0014 * (1 - q) + 0.0004, LINE)
    # upper lash band: thick over the outer two thirds, tapering to the inner corner, with a wing
    outer = [eye_pt(sign, c, -0.20 + (math.pi + 0.30) * i / 80, grow=0.0006 + 0.0034 * (1 - (i / 80) ** 1.6) + (0.001 if i < 8 else 0)) for i in range(81)]
    inner = [eye_pt(sign, c, -0.20 + (math.pi + 0.30) * i / 80, grow=-0.0016) for i in range(81)]
    fill(poly_mask(outer + inner[::-1]), LASH)
    oc = eye_pt(sign, c, 0.0)
    wing = [eye_pt(sign, c, 0.30, grow=0.003), (oc[0] + sign * 0.0085, oc[1] + 0.0062), eye_pt(sign, c, -0.22, grow=0.0006), eye_pt(sign, c, 0.05, grow=-0.001)]
    fill(poly_mask(wing), LASH)
    for th, ln_ in ((0.42, 0.0052), (0.62, 0.0042)):
        b0 = eye_pt(sign, c, th - 0.07, grow=0.003)
        b1 = eye_pt(sign, c, th + 0.07, grow=0.003)
        tip = eye_pt(sign, c, th - 0.16, grow=0.003 + ln_)
        fill(poly_mask([b0, b1, tip]), LASH)
    # lid crease
    stroke([eye_pt(sign, c, math.pi * (0.22 + 0.5 * i / 30), grow=0.0062) for i in range(31)],
           lambda q: 0.0009 * math.sin(math.pi * q) + 0.0002, (150, 88, 60))
    # brow: confident, rising outward, thick inner end
    pts = []
    for i in range(41):
        q = i / 40
        a = -0.024 + 0.054 * q
        z = c[2] + HU + 0.0075 + 0.0075 * q - 0.004 * (q - 0.55) ** 2 * 4 + 0.002 * math.sin(q * math.pi)
        pts.append((c[0] + sign * a, z))
    stroke(pts, lambda q: 0.0066 * (1 - q) ** 0.7 + 0.0010 if q > 0.06 else 0.0040 + q * 0.04, BROW)


# ---- soft shading first (under the line work)
zc_e = L["z_eye"]
for sign in (1, -1):
    fill(soft(ell_mask(sign * 0.045, zc_e - 0.030, 0.019, 0.010), 0.006), BLUSH, 0.42)
# blush hatch lines
for sign in (1, -1):
    for j in range(3):
        x0 = sign * (0.036 + j * 0.006)
        stroke([(x0, zc_e - 0.032), (x0 + 0.0035, zc_e - 0.0265)], lambda q: 0.0007, (188, 84, 66))
# under-chin / jaw soft shadow so the face reads round even unlit
fill(soft(ell_mask(0, L["z_chin"] - 0.012, 0.07, 0.016), 0.006), SKIN_SH, 0.5)

paint_eye(1, L["eye_c_l"])
paint_eye(-1, L["eye_c_r"])

# ---- nose: a small tick and a nostril dot
zn = L["z_nose"]
stroke([(0.0035, zn + 0.004), (0.0052, zn - 0.001), (0.0020, zn - 0.0035)], lambda q: 0.0011 * math.sin(math.pi * q) + 0.0004, (150, 84, 56))
fill(soft(ell_mask(-0.002, zn - 0.006, 0.006, 0.0022), 0.0012), SKIN_SH, 0.55)

# ---- mouth: cocky open grin, raised on her left
zm = L["z_mouth"] + 0.003
top = []
bot = []
for i in range(61):
    q = i / 60
    x = -0.0215 + 0.045 * q
    lift = 0.0005 + 0.0050 * q ** 1.6
    top.append((x, zm + lift - 0.0022 * math.sin(math.pi * q)))
    bot.append((x, zm + lift - 0.0022 * math.sin(math.pi * q) - 0.0135 * math.sin(math.pi * q) ** 0.75))
mouth = poly_mask(top + bot[::-1])
fill(mouth, TEETH)
# dark gap at the bottom of the open mouth and a tooth line
gap = ImageChops.multiply(mouth, ImageChops.invert(ImageChops.offset(mouth, 0, -int(mm(0.0034)))))
fill(gap, (120, 44, 40))
stroke(top, lambda q: 0.0013, LINE)
stroke(bot, lambda q: 0.0011, LINE)
stroke([top[0], (top[0][0] - 0.0028, top[0][1] + 0.0012)], lambda q: 0.0012 * (1 - q) + 0.0003, LINE)
stroke([top[-1], (top[-1][0] + 0.0034, top[-1][1] + 0.0028)], lambda q: 0.0013 * (1 - q) + 0.0003, LINE)
# tooth separators (subtle)
for q in (0.3, 0.5, 0.7):
    i = int(q * 60)
    stroke([(top[i][0], top[i][1] - 0.0006), (top[i][0] + 0.0003, bot[i][1] + 0.0036)], lambda t: 0.00035, (214, 200, 190))
# lower lip shadow
stroke([(-0.006 + 0.014 * i / 20, zm - 0.0185 - 0.0012 * math.sin(math.pi * i / 20)) for i in range(21)], lambda q: 0.0011 * math.sin(math.pi * q) + 0.0002, (160, 92, 64))

# ---- face paint: two cream bars on her right cheek, a red double tick on her left
for k, (dx, dz) in enumerate(((0.0, 0.0), (0.0040, -0.0068))):
    cx, cz = -0.047 + dx, zc_e - 0.0305 + dz
    rot = math.radians(28)
    hw_, hh = 0.0078, 0.0021
    pts = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        a, b = sx * hw_, sz * hh
        pts.append((cx + a * math.cos(rot) - b * math.sin(rot), cz + a * math.sin(rot) + b * math.cos(rot)))
    fill(poly_mask(pts), PAINT_W)
for k in range(2):
    cx, cz = 0.049 + k * 0.0052, zc_e - 0.0325 - k * 0.0006
    stroke([(cx - 0.0026, cz - 0.0042), (cx + 0.0026, cz + 0.0042)], lambda q: 0.0022, PAINT_R)

# plain skin swatch for every non-face polygon (bottom-left corner)
ImageDraw.Draw(img).rectangle([0, N - int(N * 0.08), int(N * 0.08), N], fill=SKIN)

out = img.resize((2048, 2048), Image.LANCZOS)
os.makedirs(os.path.join(HERE, "tex"), exist_ok=True)
out.save(os.path.join(HERE, "tex", "moxie_skin.png"))
print("wrote tex/moxie_skin.png")
