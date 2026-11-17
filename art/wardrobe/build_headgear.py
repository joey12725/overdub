"""
OVERDUB wardrobe — the six headgear models (Blender 4.5).

    blender --background --threads 8 --python art/wardrobe/build_headgear.py -- [id ...] [--no-preview]

Writes assets/models/wardrobe/<id>.glb (one mesh "Headgear", origin = the Head bone joint, Godot
space: +Y up, +Z = Moxie's front) and preview stills under art/previews/wardrobe/.

Every piece is designed to sit WITH the yellow headphones (APPAREL-01): nothing enters the volume
of the ear cups or of the band over the top of the head, and nothing covers the pigtails.
Concept targets: docs/reference/generated/wardrobe/<id>.png.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hlib as L  # noqa: E402
import spec  # noqa: E402

ROOT = L.ROOT
OUT = os.path.join(ROOT, "assets", "models", "wardrobe")
PREV = os.path.join(ROOT, "art", "previews", "wardrobe")
# The fit mannequin: the Moxie model currently in the game. HEAD_BONE is its head joint.
MANNEQUIN = os.path.join(ROOT, *spec.HEAD["model"].split("/"))
HEAD_BONE = spec.HEAD["bone"]

hp, hn = L.head_pt, L.head_n
G = L.HAIR  # how far outside the skull the gear rides (hair thickness)


def rad(a):
    return math.radians(a)


def arc_band(az0, az1, el, width, thick, grow, mat, n=18, el1=None, taper=None):
    """A strap hugging the head from azimuth az0 to az1 at elevation el (el1 at the far end)."""
    def fn(u, v):
        az = az0 + (az1 - az0) * u
        e = el + ((el1 - el) * u if el1 is not None else 0.0)
        w = width * (taper(u) if taper else 1.0)
        p = hp(az, e, grow)
        return p + Vector((0, (v - 0.5) * w, 0))
    return L.surf(fn, n, 1, thick, mat, "band")


# ════════════════════════════════════ SCRAP CAP ════════════════════════════════════
def scrap_cap():
    """A beat-up five-panel cap with the whole back cut away: front crown + brim, ending in front
    of the headphone band, side tabs tucking under the ear cups."""
    parts = []
    g = G + 0.004
    A = 78.0           # half-angle of the crown
    E0, E1 = 22.0, 74.0  # elevation range: brow line up to just in front of the band

    def crown(u, v):
        az = -A + 2 * A * u
        # the crown's back edge sweeps forward toward the sides (five-panel cut)
        top = E1 - 20.0 * abs(az / A) ** 2.2
        el = E0 + (top - E0) * v
        return hp(az, el, g + 0.012 * math.sin(math.pi * v))
    parts.append(L.surf(crown, 16, 6, 0.007, "helmet", "crown"))
    # panel seams
    for az in (-46.0, -15.5, 15.5, 46.0):
        top = E1 - 20.0 * abs(az / A) ** 2.2
        pts = [hp(az, E0 + (top - E0) * t / 6, g + 0.012 * math.sin(math.pi * t / 6) + 0.008) for t in range(7)]
        parts.append(L.ribbon(pts, 0.006, 0.003, "helmet_trim", up=hn(az, 45)))
    # sweat band along the brow edge
    parts.append(arc_band(-A, A, E0, 0.016, 0.006, g + 0.004, "helmet_trim", n=16))
    # raw cut edge along the back of the crown (frayed tape binding)
    pts = []
    for i in range(17):
        az = -A + 2 * A * i / 16
        top = E1 - 20.0 * abs(az / A) ** 2.2
        pts.append(hp(az, top, g + 0.008))
    parts.append(L.tube(pts, 0.006, "helmet_accent2", n=6, up=(0, 1, 0)))

    # brim: short, stiff, flipped slightly up
    base_el = E0
    tilt = rad(8.0)

    def brim(u, v):
        az = -52.0 + 104.0 * u
        root = hp(az, base_el, g + 0.004)
        reach = 0.082 * (1.0 - 0.45 * (2 * u - 1) ** 2)
        out = Vector((math.sin(rad(az)) * 0.55, 0, math.cos(rad(az)))).normalized()
        d = v * reach
        return root + out * d * math.cos(tilt) + Vector((0, d * math.sin(tilt) + 0.012 * v * v, 0))
    b = L.surf(brim, 12, 4, 0.008, "helmet", "brim")
    parts.append(b)
    # brim edge piping
    pts = [brim(i / 12, 1.0) + Vector((0, 0.004, 0)) for i in range(13)]
    parts.append(L.tube(pts, 0.0045, "helmet_trim", n=6, up=(0, 1, 0)))
    # pink tape strip across the brim and a safety pin
    pts = [brim(0.72, t / 4) + Vector((0, 0.0095, 0)) for t in range(5)]
    parts.append(L.ribbon(pts, 0.02, 0.002, "helmet_accent2", up=(0, 1, 0)))
    pin = [brim(0.2, 0.35) + Vector((0, 0.011, 0)), brim(0.34, 0.7) + Vector((0, 0.011, 0))]
    parts.append(L.tube(pin, 0.0022, "helmet_metal", n=5, up=(0, 1, 0)))
    parts.append(L.sphere(0.005, pin[0], "helmet_metal", n=6))

    # yellow triangle patch on the front panel (her headphone mark)
    c = hp(0, 43, g + 0.021)
    n = hn(0, 43)
    tri = L.prism([(-0.026, -0.02), (0.026, -0.02), (0.0, 0.026)], 0.005, mat="helmet_accent", normal="Z", bev=0.0012)
    tri2 = L.prism([(-0.012, -0.011), (0.012, -0.011), (0.0, 0.011)], 0.007, mat="helmet_trim", normal="Z")
    parts += L.orient_all([tri, tri2], c, n)
    # stitches around the patch
    for (dx, dy) in ((-0.03, -0.024), (0.03, -0.024), (0.0, 0.034)):
        s = L.box((0.006, 0.0025, 0.004), mat="helmet_paper")
        L.orient(s, c + Vector((dx, dy, 0)), n)
        parts.append(s)
    # top button stub where the panels meet
    parts.append(L.cyl(0.009, 0.006, hp(0, E1 - 1, g + 0.012), "Y", "helmet_trim", n=8))
    # side tabs that tuck under the ear cups + adjuster buckle
    for s in (1, -1):
        parts.append(arc_band(s * A, s * 100.0, E0 + 4, 0.022, 0.005, g + 0.002, "helmet", n=4, el1=6.0,
                              taper=lambda u: 1.0 - 0.35 * u))
        bk = L.box((0.004, 0.016, 0.012), mat="helmet_metal", bev=0.001)
        L.orient(bk, hp(s * 86.0, E0 - 2, g + 0.006), hn(s * 86.0, E0 - 2))
        parts.append(bk)
    return parts


# ════════════════════════════════════ HUSH HOOD ════════════════════════════════════
def hush_hood():
    """A hood quilted from speaker foam, worn pushed back: a padded roll around the back of the
    neck and a quilted cowl lip rising behind the head, below the pigtails."""
    parts = []
    # the bunched roll: a fat horseshoe around the neck, open at the front
    N = 27
    path, scale = [], []
    for i in range(N + 1):
        t = i / N
        az = 62.0 + (360.0 - 124.0) * t           # 62 deg (front-left) round the back to 298
        a = rad(az)
        r = 0.108 + 0.02 * math.sin(math.pi * t)  # wider at the back
        y = -0.058 + 0.03 * math.sin(math.pi * t) - 0.04 * (1 - math.sin(math.pi * t)) ** 2
        path.append((r * math.sin(a), y, 0.0 + r * math.cos(a) - 0.012))
        # quilted segments: pinch at every seam
        k = 0.8 + 0.2 * abs(math.sin(math.pi * t * 9.0))
        scale.append(k * (0.6 + 0.4 * math.sin(math.pi * t) ** 0.5))
    roll = L.tube(path, 0.054, "helmet", n=8, up=(0, 1, 0), scale=scale)
    parts.append(roll)
    # seam stitches between the quilted segments
    for k in range(1, 9):
        t = k / 9.0
        i = int(round(t * N))
        p = Vector(path[i])
        t0 = (Vector(path[min(i + 1, N)]) - Vector(path[max(i - 1, 0)])).normalized()
        r = 0.054 * scale[i] + 0.002
        ringp = []
        side = t0.cross(Vector((0, 1, 0))).normalized()
        up = side.cross(t0).normalized()
        for j in range(9):
            a = 2 * math.pi * j / 8
            ringp.append(p + side * (r * math.cos(a)) + up * (r * math.sin(a)))
        parts.append(L.tube(ringp, 0.004, "helmet_accent", n=3, up=tuple(t0)))

    # the cowl lip: a quilted shell standing behind the head
    def cowl(u, v):
        az = 180.0 - 74.0 + 148.0 * u
        a = rad(az)
        edge = math.sin(math.pi * u)
        r = 0.128 + 0.034 * v + 0.012 * math.sin(math.pi * v)
        y = -0.03 + (0.165 * edge ** 0.7 + 0.015) * v
        puff = 0.008 * abs(math.sin(math.pi * u * 5.0)) * math.sin(math.pi * v)
        return Vector(((r + puff) * math.sin(a), y, (r + puff) * math.cos(a) - 0.012))
    parts.append(L.surf(cowl, 16, 4, 0.02, "helmet", "cowl"))
    # rim piping along the top edge of the cowl
    pts = [cowl(i / 20, 1.0) + Vector((0, 0.004, 0)) for i in range(21)]
    parts.append(L.tube(pts, 0.011, "helmet_trim", n=6, up=(0, 1, 0)))
    # quilting stitch lines down the cowl (yellow thread)
    for k in range(1, 5):
        u = k / 5.0
        a = rad(180.0 - 74.0 + 148.0 * u)
        out = Vector((math.sin(a), 0, math.cos(a)))
        pts = [cowl(u, v / 5) - out * 0.003 for v in range(6)]
        parts.append(L.tube(pts, 0.003, "helmet_accent", n=4, up=(0, 1, 0)))
    # egg-crate foam studs showing on the inside face (the lining)
    for row, v in enumerate((0.35, 0.65)):
        for k in range(6):
            u = (k + 0.5 + 0.5 * (row % 2)) / 6.5
            if u >= 0.97:
                continue
            a = rad(180.0 - 74.0 + 148.0 * u)
            inn = Vector((-math.sin(a), 0, -math.cos(a)))
            p = cowl(u, v) + inn * 0.004
            st = L.lathe([(0, 0), (0.011, 0), (0.004, 0.012), (0, 0.013)], axis="Z", mat="helmet_dark", n=4)
            L.orient(st, p, inn)
            parts.append(st)
    # drawcords with glowing toggles hanging from the front ends of the roll
    for s in (1, -1):
        p0 = Vector(path[0 if s > 0 else N])
        cord = [p0 + Vector((0, 0.0, 0.01)), p0 + Vector((s * 0.008, -0.03, 0.035)),
                p0 + Vector((s * 0.004, -0.075, 0.045)), p0 + Vector((0, -0.11, 0.043))]
        parts.append(L.tube(L.smooth_path(cord, 3), 0.004, "helmet_trim", n=5, up=(1, 0, 0)))
        parts.append(L.cyl(0.009, 0.022, cord[-1] + Vector((0, -0.012, 0)), "Y", "helmet_glow", n=8, bev=0.002))
        parts.append(L.cyl(0.011, 0.007, cord[-1] + Vector((0, 0.003, 0)), "Y", "helmet_dark", n=8))
        # end cap of the roll
        parts.append(L.sphere(0.033, p0, "helmet_trim", n=8, scale=(1, 1, 0.8)))
    return parts


# ════════════════════════════════════ FEEDBACK CROWN ════════════════════════════════════
def tweeter(r=0.024):
    """A small blown tweeter facing +Z: basket, torn cone, glowing dust cap, magnet behind."""
    p = []
    p.append(L.lathe([(0, -0.004), (r, -0.004), (r * 1.08, 0.0), (r * 1.08, 0.006), (r * 0.93, 0.006),
                      (r * 0.93, 0.002), (0, 0.002)], axis="Z", mat="helmet", n=9))
    p.append(L.lathe([(0, -0.006), (r * 0.3, -0.006), (r * 0.88, 0.005), (r * 0.8, 0.005), (0, -0.003)],
                     axis="Z", mat="helmet_dark", n=9))
    p.append(L.sphere(r * 0.34, (0, 0, -0.002), "helmet_glow", n=6, scale=(1, 1, 0.7)))
    p.append(L.cyl(r * 0.62, 0.012, (0, 0, -0.011), "Z", "helmet_steel", n=8))
    p.append(L.cyl(r * 0.4, 0.006, (0, 0, -0.019), "Z", "helmet_dark", n=8))
    # torn flap of cone
    p.append(L.prism([(0, 0), (r * 0.55, r * 0.2), (r * 0.5, r * 0.62)], 0.0018, loc=(r * 0.1, r * 0.1, 0.007),
                     normal="Z", mat="helmet_dark", rot=(18, -14, 0)))
    return p


def feedback_crown():
    """A tiara of five blown tweeters across the brow, in front of the headphone band."""
    parts = []
    g = G + 0.006
    EL = 38.0
    A = 74.0
    parts.append(arc_band(-A, A, EL, 0.024, 0.007, g, "helmet", n=18))
    parts.append(arc_band(-A, A, EL, 0.007, 0.004, g + 0.006, "helmet_accent", n=18))
    # temple end plates
    for s in (1, -1):
        e = L.box((0.006, 0.034, 0.022), mat="helmet_steel", bev=0.002)
        L.orient(e, hp(s * (A + 2), EL, g + 0.002), hn(s * (A + 2), EL))
        parts.append(e)
    # five tweeters as the crown points, tallest in the middle
    spots = [(-58.0, 0.030, 0.019), (-30.0, 0.050, 0.023), (0.0, 0.074, 0.028), (30.0, 0.050, 0.023), (58.0, 0.030, 0.019)]
    centres = []
    for az, rise, r in spots:
        base = hp(az, EL, g + 0.006)
        n = hn(az, EL)
        n = Vector((n.x, 0.25, n.z)).normalized()
        c = base + Vector((0, rise, 0)) + n * 0.012
        centres.append(c)
        # stalk
        parts.append(L.tube([base + Vector((0, 0.006, 0)), base + Vector((0, rise * 0.55, 0)) + n * 0.004,
                             c - n * 0.016], 0.0045, "helmet_steel", n=6, up=(1, 0, 0)))
        parts.append(L.box((0.016, 0.012, 0.01), base + Vector((0, 0.008, 0)) + n * 0.002, mat="helmet_dark", bev=0.002,
                           rot=(0, az, 0)))
        parts += L.orient_all(tweeter(r), c, n)
    # speaker wire looping between the magnets
    for a, b in zip(centres[:-1], centres[1:]):
        mid = (a + b) * 0.5 + Vector((0, -0.026, 0))
        back = hn(0, 0) * -0.0
        pa = a - Vector((0, 0.004, 0)) - (a - Vector(L.HEAD_C)).normalized() * 0.014
        pb = b - Vector((0, 0.004, 0)) - (b - Vector(L.HEAD_C)).normalized() * 0.014
        mid = mid - (mid - Vector(L.HEAD_C)).normalized() * 0.004 + back
        parts.append(L.tube(L.smooth_path([pa, mid, pb], 3), 0.0032, "helmet_accent", n=4, up=(0, 1, 0)))
    # battery clip at her left temple with a little squeal light
    az = 66.0
    p = hp(az, EL - 2, g + 0.016)
    n = hn(az, EL - 2)
    bat = L.box((0.03, 0.022, 0.016), mat="helmet_dark", bev=0.003)
    cap = L.box((0.008, 0.016, 0.012), (0.019, 0, 0), mat="helmet_copper", bev=0.002)
    led = L.sphere(0.005, (-0.008, 0.012, 0.004), "helmet_glow", n=6)
    parts += L.orient_all([bat, cap, led], p, n)
    return parts


# ════════════════════════════════════ CLICK-TRACK VISOR ════════════════════════════════════
def click_visor():
    """A chunky yellow sun-visor on the brow under the headphone band, with a metronome pendulum
    salvaged from a drum machine and four beat lights."""
    parts = []
    g = G + 0.006
    EL = 30.0
    A = 80.0
    parts.append(arc_band(-A, A, EL, 0.034, 0.008, g, "helmet_dark", n=18, taper=lambda u: 1.0 - 0.3 * abs(2 * u - 1) ** 2))
    parts.append(arc_band(-A, A, EL + 7.5, 0.007, 0.006, g + 0.004, "helmet", n=18))

    # the shade peak: amber, curved, tipped down over the eyes
    tilt = rad(-14.0)

    def peak(u, v):
        az = -62.0 + 124.0 * u
        root = hp(az, EL - 5.0, g + 0.006)
        reach = 0.096 * (1.0 - 0.5 * abs(2 * u - 1) ** 2.4)
        out = Vector((math.sin(rad(az)) * 0.5, 0, math.cos(rad(az)))).normalized()
        d = v * reach
        return root + out * d * math.cos(tilt) + Vector((0, d * math.sin(tilt) - 0.02 * v * v, 0))
    parts.append(L.surf(peak, 14, 4, 0.007, "helmet_lens", "peak"))
    pts = [peak(i / 14, 1.0) + Vector((0, 0.003, 0)) for i in range(15)]
    parts.append(L.tube(pts, 0.005, "helmet", n=6, up=(0, 1, 0)))
    # yellow hinge housing where the peak meets the band
    parts.append(arc_band(-64.0, 64.0, EL - 4.5, 0.014, 0.012, g + 0.004, "helmet", n=14))

    # four beat lights across the band
    for az in (-42.0, -27.0, 27.0, 42.0):
        p = hp(az, EL + 1, g + 0.009)
        n = hn(az, EL + 1)
        led = L.box((0.016, 0.011, 0.005), mat="helmet_glow", bev=0.0015)
        bez = L.box((0.021, 0.016, 0.003), (0, 0, -0.002), mat="helmet_steel", bev=0.001)
        parts += L.orient_all([led, bez], p, n)

    # the metronome: a little pyramid case at the centre of the brow, pendulum swung to one side
    c = hp(0, EL + 2, g + 0.012)
    n = Vector((0, 0.12, 1)).normalized()
    case = L.prism([(-0.024, -0.018), (0.024, -0.018), (0.012, 0.05), (-0.012, 0.05)], 0.02, normal="Z",
                   mat="helmet", bev=0.003)
    face = L.prism([(-0.014, -0.01), (0.014, -0.01), (0.007, 0.04), (-0.007, 0.04)], 0.004, loc=(0, 0, 0.011),
                   normal="Z", mat="helmet_paper")
    marks = [L.box((0.01 - 0.001 * k, 0.0016, 0.002), (0, -0.004 + 0.008 * k, 0.0135), mat="helmet_dark") for k in range(5)]
    foot = L.box((0.056, 0.008, 0.026), (0, -0.02, 0), mat="helmet_dark", bev=0.002)
    piv = (0, -0.008, 0.016)
    ang = rad(-24.0)
    tip = (piv[0] + 0.1 * math.sin(ang), piv[1] + 0.1 * math.cos(ang), piv[2])
    arm = L.tube([piv, tip], 0.0026, "helmet_metal", n=5, up=(0, 0, 1))
    wpos = (piv[0] + 0.066 * math.sin(ang), piv[1] + 0.066 * math.cos(ang), piv[2])
    weight = L.box((0.014, 0.013, 0.007), wpos, rot=(0, 0, 24.0), mat="helmet_accent2", bev=0.002)
    hub = L.cyl(0.005, 0.006, piv, "Z", "helmet_steel", n=8)
    tipb = L.sphere(0.0045, tip, "helmet_glow", n=6)
    key = L.cyl(0.006, 0.008, (0.03, 0.0, 0.0), "X", "helmet_steel", n=6)
    parts += L.orient_all([case, face, marks, foot, arm, weight, hub, tipb, key], c, n)
    return parts


# ════════════════════════════════════ PRISM GOGGLES ════════════════════════════════════
def prism_goggles():
    """Welding-style goggles pushed up on the forehead: two faceted mirror lenses, riveted rims,
    side vents, and an elastic strap that runs back under the ear cups."""
    parts = []
    g = G + 0.004
    EL = 40.0
    R = 0.037
    for s in (1, -1):
        az = s * 27.0
        n = hn(az, EL)
        n = Vector((n.x, n.y + 0.12, n.z)).normalized()
        c = hp(az, EL, g + 0.022)
        eye = []
        # barrel
        eye.append(L.lathe([(R * 0.86, -0.02), (R * 1.04, -0.02), (R * 1.04, 0.004), (R * 1.14, 0.006), (R * 1.14, 0.014),
                            (R * 0.9, 0.014), (R * 0.9, 0.004), (R * 0.86, 0.004)], axis="Z", mat="helmet_dark", n=14, closed=True))
        eye.append(L.ring(R * 1.14, 0.0, (0, 0, 0.0145), "Z", "helmet_steel", n=14, flat=(0.004, 0.0015)))
        # faceted mirror lens: a shallow six-sided pyramid of glass
        eye.append(L.lathe([(0, 0.016), (R * 0.5, 0.0125), (R * 0.9, 0.006), (R * 0.9, 0.0), (0, 0.0)], axis="Z",
                           mat="helmet_glow", n=6))
        eye.append(L.lathe([(0, 0.0175), (R * 0.2, 0.0165), (0, 0.0155)], axis="Z", mat="helmet_paper", n=6))
        # rivets
        for k in range(6):
            a = math.pi / 6 + k * math.pi / 3
            eye.append(L.sphere(0.0038, (R * 1.14 * math.cos(a), R * 1.14 * math.sin(a), 0.0155), "helmet_metal", n=5))
        # side vent on the outer side
        vx = s * R * 1.12
        eye.append(L.box((0.012, 0.026, 0.02), (vx, 0, -0.006), mat="helmet", bev=0.002))
        for k in (-1, 0, 1):
            eye.append(L.box((0.004, 0.004, 0.016), (vx + s * 0.005, k * 0.008, -0.006), mat="helmet_dark"))
        # foam gasket against the forehead
        eye.append(L.ring(R * 0.96, 0.007, (0, 0, -0.021), "Z", "helmet_trim", n=12, m=6))
        parts += L.orient_all(eye, c, n)
    # nose bridge
    a = hp(-9.0, EL, g + 0.02)
    b = hp(9.0, EL, g + 0.02)
    parts.append(L.tube([a, (a + b) * 0.5 + Vector((0, 0.006, 0.006)), b], 0.006, "helmet_steel", n=6, up=(0, 1, 0)))
    parts.append(L.box((0.012, 0.012, 0.008), (a + b) * 0.5 + Vector((0, 0.006, 0.01)), mat="helmet", bev=0.002))
    # elastic strap back to under the cups, striped
    for s in (1, -1):
        parts.append(arc_band(s * 50.0, s * 104.0, EL - 2, 0.026, 0.005, g + 0.002, "helmet_trim", n=7, el1=10.0))
        parts.append(arc_band(s * 50.0, s * 104.0, EL - 2, 0.008, 0.003, g + 0.006, "helmet", n=7, el1=10.0))
        bk = L.box((0.006, 0.03, 0.014), mat="helmet_metal", bev=0.0015)
        L.orient(bk, hp(s * 54.0, EL - 2.5, g + 0.007), hn(s * 54.0, EL - 2.5))
        parts.append(bk)
    return parts


# ════════════════════════════════════ RABBIT-EAR AERIALS ════════════════════════════════════
def rabbit_ears():
    """Two telescoping TV aerials zip-tied to the outside of the headphone ear cups, in a wide V."""
    parts = []
    cx, cy, cz = L.CUP_C
    for s in (1, -1):
        side = []
        base = Vector((s * (cx + 0.017), cy + 0.03, cz - 0.006))
        d = Vector((s * 0.42, 0.9, -0.1)).normalized()
        # mounting plate strapped to the cup + swivel
        side.append(L.box((0.012, 0.05, 0.034), base + Vector((-s * 0.004, -0.012, 0)), mat="helmet_dark", bev=0.003))
        side.append(L.sphere(0.0125, base + Vector((s * 0.004, 0.014, 0)), "helmet_steel", n=8))
        side.append(L.cyl(0.0085, 0.02, base + Vector((s * 0.004, 0.014, 0)), "Z", "helmet_dark", n=8, bev=0.001))
        # zip ties round the plate, tails sticking out
        for k, yy in enumerate((-0.026, -0.004)):
            side.append(L.box((0.016, 0.006, 0.04), base + Vector((-s * 0.003, yy, 0)), mat="helmet_trim"))
            side.append(L.box((0.004, 0.004, 0.022), base + Vector((s * 0.006, yy, 0.028)), rot=(-30 + 50 * k, 0, 0), mat="helmet_trim"))
        # three telescoping segments
        p = base + Vector((s * 0.004, 0.014, 0)) + d * 0.008
        for i, (ln, r) in enumerate(((0.125, 0.0115), (0.115, 0.0085), (0.105, 0.006))):
            q = p + d * ln
            side.append(L.tube([p, q], r, "helmet", n=7, up=(0, 0, 1)))
            # collar at each joint
            side.append(L.tube([q - d * 0.006, q + d * 0.004], r * 1.35, "helmet_steel", n=7, up=(0, 0, 1)))
            p = q
        side.append(L.sphere(0.018, p + d * 0.012, "helmet_glow", n=8))
        # a strip of pink tape flagging the second joint
        j = base + Vector((s * 0.004, 0.014, 0)) + d * (0.008 + 0.125 + 0.03)
        side.append(L.box((0.03, 0.014, 0.002), j + Vector((s * 0.012, 0, 0.004)), rot=(0, 0, -s * 25), mat="helmet_accent2"))
        parts += side
    # coax wire: curls off her left aerial's base and drapes behind the head to the right one
    a = Vector((cx + 0.02, cy + 0.02, cz - 0.02))
    b = Vector((-(cx + 0.02), cy + 0.02, cz - 0.02))
    pts = [a]
    for k in range(1, 12):
        t = k / 12
        az = 90.0 + 180.0 * t
        q = hp(az, -4.0 - 16.0 * math.sin(math.pi * t), G + 0.03)
        pts.append(q)
    pts.append(b)
    parts.append(L.tube(L.smooth_path(pts, 2), 0.0038, "helmet_dark", n=5, up=(0, 1, 0)))
    # coil where the wire leaves the left base
    coil = L.helix(0.009, 0.0, 0.03, 3.0, axis="Y", steps=8)
    coil = [Vector(c) + a + Vector((0.006, -0.03, -0.004)) for c in coil]
    parts.append(L.tube(coil, 0.003, "helmet_dark", n=4, up=(0, 1, 0)))
    return parts


BUILDERS = {
    "scrap_cap": (scrap_cap, {"helmet_glow": "#ffd23f"}),
    "hush_hood": (hush_hood, {"helmet_glow": "#5ff6ff", "helmet_dark": "#30333d", "helmet_trim": "#2f323c"}),
    "feedback_crown": (feedback_crown, {"helmet_glow": "#ff8fd0"}),
    "click_visor": (click_visor, {"helmet_glow": "#5ff6ff", "helmet_lens": "#ff9d1e"}),
    "prism_goggles": (prism_goggles, {"helmet_glow": "#9ff0ff", "helmet": "#3a4f66"}),
    "rabbit_ears": (rabbit_ears, {"helmet_glow": "#ff5a6e"}),
}


# ───────────────────────────── preview ─────────────────────────────
def load_mannequin():
    """The current Moxie model, moved so its head joint is at the origin, in Godot axes."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=MANNEQUIN)
    new = [o for o in bpy.data.objects if o not in before]
    fix = Matrix.Translation(Vector((-HEAD_BONE[0], -HEAD_BONE[1], -HEAD_BONE[2]))) @ Matrix.Rotation(-math.pi / 2, 4, "X")
    for o in new:
        # the importer leaves the first animation applied: go back to the rest pose
        if o.animation_data is not None:
            o.animation_data_clear()
        if o.type == "ARMATURE":
            for pb in o.pose.bones:
                pb.matrix_basis = Matrix.Identity(4)
        if o.parent is None:
            o.matrix_world = fix @ o.matrix_world
    bpy.context.view_layer.update()
    return new


def setup_render(w, h):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.object_outline_color = (0.03, 0.02, 0.03)
    sh.show_shadows = False
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.show_specular_highlight = False
    sc.display.render_aa = "16"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.03, 0.028, 0.035)
    sh.background_type = "WORLD"


def shoot(path, yaw, pitch, target=(0, 0.16, 0), scale=0.62):
    sc = bpy.context.scene
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cd = bpy.data.cameras.new("PreviewCam")
        cam = bpy.data.objects.new("PreviewCam", cd)
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
    cam.data.clip_start, cam.data.clip_end = 0.01, 50
    y, p = rad(yaw), rad(pitch)
    z = Vector((math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)))
    x = Vector((0, 1, 0)).cross(z).normalized()
    u = z.cross(x).normalized()
    pos = Vector(target) + z * 5
    cam.matrix_world = Matrix(((x.x, u.x, z.x, pos.x), (x.y, u.y, z.y, pos.y), (x.z, u.z, z.z, pos.z), (0, 0, 0, 1)))
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


VIEWS = [("iso", 45, 35), ("isoback", 225, 35), ("front", 0, 4), ("side", 90, 4)]


def build(ident, previews=True):
    fn, over = BUILDERS[ident]
    h = spec.HEADGEAR[ident]
    ov = dict(over)
    main = ov.pop("helmet", h["color"])
    L.reset(main, **ov)
    obj = L.join(fn(), "Headgear")
    lo, hi = L.bounds([obj])
    print("BUILT %s tris=%d min=(%.3f %.3f %.3f) max=(%.3f %.3f %.3f) mats=%s" % (
        ident, L.tris(obj), lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, [m.name for m in obj.data.materials]))
    L.export_glb(os.path.join(OUT, ident + ".glb"), [obj])
    if previews:
        load_mannequin()
        setup_render(640, 640)
        for name, yaw, pitch in VIEWS:
            shoot(os.path.join(PREV, "%s_%s.png" % (ident, name)), yaw, pitch)
        # how it reads at something like game scale
        shoot(os.path.join(PREV, "%s_body.png" % ident), 45, 35, target=(0, -0.45, 0), scale=2.3)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    previews = "--no-preview" not in argv
    ids = [a for a in argv if not a.startswith("--")] or list(BUILDERS)
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    for i in ids:
        build(i, previews)


if __name__ == "__main__":
    main()
