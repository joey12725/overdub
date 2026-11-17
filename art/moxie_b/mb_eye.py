"""Eye outline shared by the mesh stage (eyelid loop) and the texture painter. Pure python."""
import math


def outline(theta, W, HU, HL, TILT):
    """Eye outline in eye-plane coords (lateral + = away from the nose, up +).
    theta runs from the outer corner (0) over the upper lid to the inner corner (pi); negative = lower lid."""
    c, s_ = math.cos(theta), math.sin(theta)
    a = W * math.copysign(abs(c) ** 0.9, c)
    if s_ >= 0:
        b = HU * (abs(s_) ** 0.92) * (1.0 + 0.16 * c)
    else:
        b = -HL * (abs(s_) ** 1.0) * (1.0 - 0.10 * c)
    return a * math.cos(TILT) - b * math.sin(TILT), a * math.sin(TILT) + b * math.cos(TILT)
