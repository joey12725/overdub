"""Chunky high-top boots: two-tone sole, toe box, dark heel counter, tongue, loose yellow laces."""
import math

import bmesh
import numpy as np

from mc_util import (V, Mesh, catmull, circle_profile, loft, norm, rbox, shade_auto, sweep,
                     to_object, torus)

FOOT_X = 0.100
FOOT_Y = 0.020


def _boot_ring(z, yf, yb, hw, n=28, power=2.6):
    yc = FOOT_Y + (yf + yb) / 2
    ly = (yb - yf) / 2
    pts = []
    e = 2.0 / power
    for k in range(n):
        a = 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        pts.append((FOOT_X + hw * np.sign(c) * abs(c) ** e, yc + ly * np.sign(s) * abs(s) ** e, z))
    return pts


SLICES = [  # z, y_front, y_back, half width
    (0.000, -0.166, 0.080, 0.050), (0.007, -0.176, 0.088, 0.057), (0.020, -0.178, 0.089, 0.058),
    (0.036, -0.176, 0.088, 0.057), (0.042, -0.170, 0.084, 0.0535), (0.052, -0.170, 0.083, 0.0525),
    (0.072, -0.167, 0.084, 0.0525), (0.090, -0.156, 0.085, 0.0515), (0.102, -0.134, 0.085, 0.0505),
    (0.114, -0.100, 0.084, 0.0495), (0.132, -0.068, 0.083, 0.0485), (0.156, -0.048, 0.081, 0.0480),
    (0.190, -0.038, 0.080, 0.0485), (0.226, -0.035, 0.082, 0.0505)]


def build_boots():
    m = Mesh()
    rings = np.array([_boot_ring(*s) for s in SLICES])
    for side in (1, -1):
        rr = rings * V(side, 1, 1)
        n = rr.shape[1]
        for i in range(len(SLICES) - 1):
            z = 0.5 * (SLICES[i][0] + SLICES[i + 1][0])
            for k in range(n):
                a, b = k, (k + 1) % n
                quad = np.array([rr[i][a], rr[i][b], rr[i + 1][b], rr[i + 1][a]])
                c = quad.mean(axis=0)
                yl = c[1] - FOOT_Y
                if z < 0.010:
                    mat = "shoes_dark"
                elif z < 0.040:
                    mat = "shoes_sole"
                elif yl > 0.045 and z < 0.085:
                    mat = "shoes_accent" if z < 0.066 else "shoes_dark"
                elif yl > 0.040:
                    mat = "shoes_dark"
                elif z > 0.19:
                    mat = "shoes_dark"
                elif abs(c[0] * side - FOOT_X) > 0.040 and -0.10 < yl < 0.0 and z < 0.11:
                    mat = "shoes_dark"
                else:
                    mat = "shoes_main"
                m.add(quad, [(0, 1, 2, 3)], mat)
        cap = rr[0]
        cen = cap.mean(axis=0)
        m.add(np.vstack([cap, cen[None, :]]), [(n, (k + 1) % n, k) for k in range(n)], "shoes_dark")
        cx = side * FOOT_X
        # tongue up the instep
        line = np.array([(-0.126, 0.100), (-0.098, 0.119), (-0.070, 0.142), (-0.052, 0.170),
                         (-0.044, 0.205), (-0.046, 0.238)])
        line = catmull(line, 12)
        trings = []
        for (yl, z) in line:
            row = []
            for dx in (-0.021, -0.011, 0.0, 0.011, 0.021):
                k = 1 - (dx / 0.021) ** 2
                row.append((cx + dx, FOOT_Y + yl - 0.004 - 0.006 * k, z + 0.003 * k))
            trings.append(row)
        loft(np.array(trings), "shoes_main", m, closed=False)
        tz = line[8]
        m.add(np.array([(cx - 0.011, FOOT_Y + tz[0] - 0.0135, tz[1] - 0.012),
                        (cx + 0.011, FOOT_Y + tz[0] - 0.0135, tz[1] - 0.012),
                        (cx, FOOT_Y + tz[0] - 0.0155, tz[1] + 0.012)]), [(0, 1, 2), (0, 2, 1)],
              "shoes_accent")
        # laces
        eL, eR = [], []
        for i in (2, 4, 6, 8, 10):
            yl, z = line[i]
            eL.append(V(cx - 0.024, FOOT_Y + yl - 0.005, z + 0.001))
            eR.append(V(cx + 0.024, FOOT_Y + yl - 0.005, z + 0.001))
        prof = circle_profile(5)
        for i in range(len(eL) - 1):
            for a, b2 in ((eL[i], eR[i + 1]), (eR[i], eL[i + 1])):
                mid = (a + b2) / 2 + V(0, -0.008, 0.004)
                sweep(catmull(np.array([a, mid, b2]), 5), prof, 0.0030, V(0, 0, 1), "lace", m)
        sweep(catmull(np.array([eL[0], (eL[0] + eR[0]) / 2 + V(0, -0.007, 0.002), eR[0]]), 7), prof,
              0.0030, V(0, 0, 1), "lace", m)
        top = (eL[-1] + eR[-1]) / 2 + V(0, -0.010, 0.004)
        for sg in (1, -1):
            loop = np.array([top, top + V(sg * 0.030, -0.012, 0.018), top + V(sg * 0.050, -0.016, 0.004),
                             top + V(sg * 0.030, -0.012, -0.012), top])
            sweep(catmull(loop, 10), prof, 0.0030, V(0, -1, 0), "lace", m)
            end = np.array([top, top + V(sg * 0.014, -0.016, -0.022), top + V(sg * 0.030, -0.020, -0.052),
                            top + V(sg * 0.036, -0.014, -0.074)])
            sweep(catmull(end, 6), prof, 0.0030, V(0, -1, 0), "lace", m)
        for p in eL + eR:
            torus(p + V(0, -0.001, 0), norm(V(0, -0.8, 0.6)), 0.0042, 0.0014, "metal", m, n=6, m=3)
        # padded collar and heel pull tab
        ctr = V(cx, FOOT_Y + 0.0235, 0.228)
        rc = []
        prof8 = circle_profile(8, 0.009, 0.008)
        top_ring = np.array(_boot_ring(0.228, -0.035, 0.082, 0.0505, n=24, power=2.2)) * V(side, 1, 1)
        for k in range(24):
            p = top_ring[k]
            out = norm(V(p[0] - ctr[0], p[1] - ctr[1], 0))
            rc.append([p + V(0, 0, 1) * px + out * py for px, py in prof8])
        rc.append(rc[0])
        loft(np.array(rc), "shoes_dark", m)
        tab = np.array([(cx, FOOT_Y + 0.083, 0.205), (cx, FOOT_Y + 0.096, 0.222),
                        (cx, FOOT_Y + 0.094, 0.246), (cx, FOOT_Y + 0.082, 0.240)])
        sweep(catmull(tab, 8), circle_profile(6, 1.0, 0.25), 0.008, V(1, 0, 0), "shoes_accent", m)
    ob = to_object("Boots", m, merge=0.0002)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    shade_auto(ob, 48)
    return ob
