"""Pose helpers that work in armature space, independent of bone rolls."""
import bpy, math
from mathutils import Vector, Matrix, Quaternion


def _update():
    bpy.context.view_layer.update()


def aim(pb, direction):
    """Rotate pose bone pb (about its head) so it points along `direction` (armature space)."""
    _update()
    cur = (pb.tail - pb.head).normalized()
    q = cur.rotation_difference(Vector(direction).normalized())
    h = pb.head.copy()
    pb.matrix = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ pb.matrix
    _update()


def turn(pb, axis, degrees):
    """Rotate pose bone pb about its head around an armature-space axis."""
    _update()
    h = pb.head.copy()
    r = Matrix.Rotation(math.radians(degrees), 4, Vector(axis).normalized())
    pb.matrix = Matrix.Translation(h) @ r @ Matrix.Translation(-h) @ pb.matrix
    _update()


def twist(pb, degrees):
    """Rotate pose bone about its own length."""
    _update()
    turn(pb, (pb.tail - pb.head), degrees)


def reset(rig):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    _update()


SIDES = (("Left", 1.0), ("Right", -1.0))
FINGERS = ("Index", "Middle", "Ring", "Little")


def curl_fingers(rig, side, amount):
    """amount 0..1 -> fist. Fingers curl about the hand's across axis."""
    pbs = rig.pose.bones
    hand = pbs[side + "Hand"]
    _update()
    hd = (hand.tail - hand.head).normalized()
    # palm normal: use index->little direction to build the across axis
    a = pbs[side + "IndexProximal"].head
    b = pbs[side + "LittleProximal"].head
    across = (b - a).normalized()
    for f in FINGERS:
        for seg, ang in (("Proximal", 75), ("Intermediate", 95), ("Distal", 60)):
            turn(pbs[side + f + seg], across, ang * amount * (1 if side == "Left" else 1))
    palm_n = hd.cross(across).normalized()
    turn(pbs[side + "ThumbMetacarpal"], hd, -35 * amount * (1 if side == "Left" else -1))
    for seg, ang in (("ThumbProximal", 35), ("ThumbDistal", 55)):
        turn(pbs[side + seg], palm_n, ang * amount * (1 if side == "Left" else -1))
