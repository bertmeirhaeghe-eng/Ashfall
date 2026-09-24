"""Procedural Tiberian Sun-style models for units and buildings without an STL.

References: TS GDI light infantry / disc thrower, Nod attack buggy and tick tank,
GDI and Nod construction yard, power plant, refinery, barracks / Hand of Nod,
war factory and guard towers. Faceted, chunky shapes with bevelled armour,
team-coloured panels and glowing lights.
"""
import math

import numpy as np

from ashmodel import (Model, box, cyl, extrude_profile, hull, ngon_prism, sphere,
                      taper_box)


def crystal(r, h, at, lean=(0.0, 0.0)):
    """A pointed tiberium-style crystal."""
    x, y, z = at
    pts = []
    for i in range(6):
        a = i * math.pi / 3 + 0.3
        pts.append((x + math.cos(a) * r, y, z + math.sin(a) * r))
        pts.append((x + math.cos(a) * r * 0.8 + lean[0] * h * 0.4, y + h * 0.7, z + math.sin(a) * r * 0.8 + lean[1] * h * 0.4))
    pts.append((x + lean[0] * h, y + h, z + lean[1] * h))
    return hull(pts)


MODELS = {}


def model(fn):
    MODELS[fn.__name__] = fn
    return fn


# ------------------------------------------------------------------ helpers
def strut(p0, p1, r, seg=6):
    """Cylinder between two points."""
    import trimesh
    p0, p1 = np.array(p0, float), np.array(p1, float)
    return trimesh.creation.cylinder(radius=r, segment=[p0, p1], sections=seg)


def bar(p0, p1, w, h):
    """Rectangular beam between two points (w across, h up)."""
    p0, p1 = np.array(p0, float), np.array(p1, float)
    d = p1 - p0
    L = np.linalg.norm(d)
    f = d / L
    up = np.array([0.0, 1.0, 0.0])
    side = np.cross(up, f)
    if np.linalg.norm(side) < 1e-6:
        side = np.array([1.0, 0, 0])
    side /= np.linalg.norm(side)
    upv = np.cross(f, side)
    pts = []
    for e in (p0, p1):
        for sx in (-1, 1):
            for sy in (-1, 1):
                pts.append(e + side * sx * w / 2 + upv * sy * h / 2)
    return hull(pts)


def slab(md, w, d, h=0.12, slot="concrete", inset=0.05):
    md.add(box((w - inset * 2, h, d - inset * 2), (0, h / 2, 0), bevel=h * 0.45), slot)
    return h


def stripes(md, p0, p1, n, size, slot_a="hazard", slot_b="dark"):
    """n alternating blocks along the line p0 -> p1."""
    p0, p1 = np.array(p0, float), np.array(p1, float)
    for i in range(n):
        c = p0 + (p1 - p0) * (i + 0.5) / n
        md.add(box(size, c), slot_a if i % 2 == 0 else slot_b)


def lamp(md, at, r=0.035, slot="lamp", part="body"):
    md.add(box((r * 2, r * 1.2, r * 2), at, bevel=r * 0.4), slot, part)


def wheel(md, at, r, w, part="body", hub=True, seg=10):
    md.add(cyl(r, w, at, axis="x", seg=seg), "dark", part)
    if hub:
        x, y, z = at
        s = 1 if x > 0 else -1
        md.add(cyl(r * 0.45, w * 0.3, (x + s * w * 0.5, y, z), axis="x", seg=6), "metal", part)


def spike(at, r, h, lean=(0.0, 0.0), sides=4):
    x, y, z = at
    pts = [(x + math.cos(a) * r, y, z + math.sin(a) * r) for a in np.linspace(0, 2 * math.pi, sides, endpoint=False) + math.pi / sides]
    pts.append((x + lean[0], y + h, z + lean[1]))
    return hull(pts)


# ------------------------------------------------------------------ infantry
def _infantry(name, veil, rocket):
    md = Model(name)
    body = "dark" if veil else "body"
    # boots and legs, slightly apart (combat stance)
    for s in (-1, 1):
        md.add(box((0.055, 0.035, 0.085), (s * 0.042, 0.018, 0.012), bevel=0.01), "dark")
        md.add(taper_box((0.05, 0.055), (0.06, 0.065), 0.2, (s * 0.042, 0.03, 0)), body)
        md.add(box((0.05, 0.03, 0.02), (s * 0.042, 0.13, 0.03), bevel=0.006), "panel")  # knee pad
    md.add(box((0.14, 0.05, 0.08), (0, 0.255, 0), bevel=0.012), body)  # hips
    # torso and armour vest
    md.add(taper_box((0.13, 0.085), (0.17, 0.095), 0.15, (0, 0.27, 0)), body)
    md.add(taper_box((0.145, 0.03), (0.175, 0.03), 0.11, (0, 0.285, 0.035)), "team" if not veil else "panel")
    md.add(box((0.12, 0.13, 0.06), (0, 0.35, -0.07), bevel=0.012), "panel" if not veil else "dark")  # backpack
    if not veil:
        md.add(box((0.1, 0.02, 0.05), (0, 0.42, -0.07), bevel=0.008), "dark")  # radio pack lid
    # shoulders and arms reaching forward to the weapon
    for s in (-1, 1):
        md.add(box((0.055, 0.04, 0.07), (s * 0.1, 0.405, 0), bevel=0.012), "team" if veil else "panel")
    arm_r = 0.02
    if rocket:
        md.add(strut((0.1, 0.4, 0), (0.07, 0.42, 0.08), arm_r, 5), body)
        md.add(strut((-0.1, 0.4, 0), (-0.02, 0.34, 0.1), arm_r, 5), body)
    else:
        md.add(strut((0.1, 0.4, 0), (0.05, 0.33, 0.1), arm_r, 5), body)
        md.add(strut((-0.1, 0.4, 0), (0.0, 0.34, 0.16), arm_r, 5), body)
    # head
    md.add(sphere(0.04, (0, 0.455, 0.005), sub=1, scale=(1, 1.1, 1)), "panel" if not veil else "dark")
    if veil:
        # Nod: hood, gas mask and red eye lenses
        md.add(hull([(x * 0.05, 0.43, z) for x in (-1, 1) for z in (-0.05, 0.03)] + [(0, 0.515, -0.01)]), "dark")
        md.add(box((0.05, 0.03, 0.03), (0, 0.44, 0.04), bevel=0.008), "metal")
        for s in (-1, 1):
            md.add(box((0.018, 0.014, 0.01), (s * 0.017, 0.463, 0.042)), "red")
    else:
        # GDI: rounded helmet with visor
        md.add(hull([(math.cos(a) * 0.05, 0.45, math.sin(a) * 0.052) for a in np.linspace(0, 2 * math.pi, 10, endpoint=False)]
                    + [(0, 0.51, -0.005)]), "body")
        md.add(box((0.07, 0.016, 0.012), (0, 0.458, 0.043)), "glass")
    if rocket:
        # shoulder-fired launcher
        md.add(cyl(0.034, 0.34, (0.075, 0.44, 0.03), axis="z", seg=8), "panel" if not veil else "metal")
        md.add(cyl(0.04, 0.05, (0.075, 0.44, 0.2), axis="z", seg=8), "dark")
        md.add(cyl(0.028, 0.03, (0.075, 0.44, -0.15), axis="z", seg=8), "hazard")
        md.add(box((0.02, 0.05, 0.04), (0.075, 0.4, 0.05)), "dark")  # grip
        md.add(box((0.03, 0.03, 0.05), (0.035, 0.47, 0.06)), "glass")  # sight
        md.meta["muzzle_height"] = 0.44
    else:
        md.add(box((0.028, 0.045, 0.2), (0.02, 0.35, 0.1)), "dark")
        md.add(box((0.018, 0.018, 0.1), (0.02, 0.36, 0.24)), "metal")
        md.add(box((0.02, 0.05, 0.02), (0.02, 0.315, 0.12)), "dark")  # magazine
        md.meta["muzzle_height"] = 0.36
    return md


@model
def rifleman():
    return _infantry("rifleman", False, False)


@model
def rifleman_veil():
    return _infantry("rifleman_veil", True, False)


@model
def rocket_trooper():
    return _infantry("rocket_trooper", False, True)


@model
def rocket_trooper_veil():
    return _infantry("rocket_trooper_veil", True, True)


# ------------------------------------------------------------------ vehicles
@model
def buggy():
    """Veil Raider = TS Nod attack buggy: open frame, big tyres, rear MG."""
    md = Model("buggy")
    # chassis: low wedge
    md.add(extrude_profile([(-0.4, 0.12), (0.36, 0.12), (0.46, 0.18), (0.4, 0.24), (0.1, 0.27), (-0.1, 0.3), (-0.42, 0.29)], 0.32), "body")
    md.add(extrude_profile([(0.12, 0.24), (0.42, 0.22), (0.46, 0.18), (0.36, 0.14), (0.12, 0.14)], 0.36), "panel")  # nose
    md.add(box((0.3, 0.02, 0.12), (0, 0.235, 0.3)), "team")  # hood stripe
    # fenders over the wheels
    for s in (-1, 1):
        for z in (-0.25, 0.26):
            md.add(hull([(s * 0.18, 0.2, z - 0.15), (s * 0.18, 0.2, z + 0.15), (s * 0.34, 0.25, z - 0.1),
                         (s * 0.34, 0.25, z + 0.1), (s * 0.34, 0.2, z - 0.15), (s * 0.34, 0.2, z + 0.15),
                         (s * 0.18, 0.27, z - 0.1), (s * 0.18, 0.27, z + 0.1)]), "team" if z > 0 else "body")
            wheel(md, (s * 0.27, 0.12, z), 0.12, 0.1, seg=12)
        # side exhausts
        md.add(cyl(0.02, 0.22, (s * 0.2, 0.2, -0.12), axis="z", seg=6), "metal")
    # cockpit tub, seat and windscreen
    md.add(box((0.24, 0.08, 0.2), (0, 0.28, 0.08), bevel=0.02), "dark")
    md.add(box((0.1, 0.12, 0.04), (0.05, 0.34, 0.01)), "dark")
    md.add(hull([(-0.12, 0.3, 0.2), (0.12, 0.3, 0.2), (-0.11, 0.39, 0.16), (0.11, 0.39, 0.16),
                 (-0.12, 0.3, 0.19), (0.12, 0.3, 0.19)]), "glass")
    # roll cage
    for s in (-1, 1):
        md.add(strut((s * 0.13, 0.3, 0.17), (s * 0.12, 0.44, 0.05), 0.012), "metal")
        md.add(strut((s * 0.12, 0.44, 0.05), (s * 0.14, 0.3, -0.14), 0.012), "metal")
    md.add(strut((-0.12, 0.44, 0.05), (0.12, 0.44, 0.05), 0.012), "metal")
    # headlights and tail lights
    for s in (-1, 1):
        lamp(md, (s * 0.12, 0.2, 0.44), 0.02)
        lamp(md, (s * 0.14, 0.26, -0.42), 0.015, "red")
    # rear gun mount
    t = md.part("turret", (0, 0.33, -0.2))
    md.add(cyl(0.07, 0.04, (0, 0.33, -0.2), seg=8), "dark", t)
    md.add(box((0.1, 0.08, 0.14), (0, 0.39, -0.2), bevel=0.015), "panel", t)
    md.add(box((0.14, 0.07, 0.02), (0, 0.4, -0.12)), "team", t)  # gun shield
    for s in (-1, 1):
        md.add(cyl(0.012, 0.3, (s * 0.025, 0.4, 0.0), axis="z", seg=6), "metal", t)
    md.add(box((0.06, 0.05, 0.08), (0, 0.37, -0.28)), "dark", t)  # ammo box
    md.meta.update({"turret": t, "muzzle_height": 0.42})
    return md


@model
def tank():
    """Veil Scorpion = TS Nod tick tank style: low, angular, long gun."""
    md = Model("tank")
    for s in (-1, 1):
        x = s * 0.3
        md.add(extrude_profile([(-0.44, 0.02), (0.44, 0.02), (0.52, 0.1), (0.46, 0.18), (-0.47, 0.18), (-0.52, 0.09)], 0.17, (x, 0, 0)), "dark")
        for z in np.linspace(-0.36, 0.36, 5):
            md.add(cyl(0.065, 0.02, (s * 0.395, 0.09, z), axis="x", seg=8), "metal")
        # track guard
        md.add(hull([(x - 0.1, 0.19, -0.5), (x + 0.1, 0.19, -0.5), (x - 0.1, 0.19, 0.46), (x + 0.1, 0.19, 0.46),
                     (x - 0.09, 0.22, -0.48), (x + 0.1, 0.21, -0.48), (x - 0.09, 0.22, 0.4), (x + 0.1, 0.21, 0.4)]), "panel")
        md.add(box((0.04, 0.012, 0.5), (x + s * 0.05, 0.222, -0.02)), "team")
    # hull with a steep front glacis
    md.add(extrude_profile([(-0.46, 0.1), (0.36, 0.1), (0.5, 0.17), (0.3, 0.3), (-0.4, 0.3), (-0.48, 0.22)], 0.46), "body")
    md.add(hull([(-0.2, 0.3, 0.3), (0.2, 0.3, 0.3), (-0.23, 0.2, 0.44), (0.23, 0.2, 0.44),
                 (-0.2, 0.29, 0.31), (0.2, 0.29, 0.31)]), "panel")
    # driver hatch, engine deck
    md.add(box((0.1, 0.03, 0.08), (-0.12, 0.31, 0.25), bevel=0.01), "dark")
    lamp(md, (-0.12, 0.33, 0.29), 0.012, "glass")
    for z in (-0.28, -0.34, -0.4):
        md.add(box((0.32, 0.015, 0.03), (0, 0.305, z)), "dark")
    for s in (-1, 1):
        lamp(md, (s * 0.17, 0.24, 0.44), 0.018)
        lamp(md, (s * 0.18, 0.25, -0.46), 0.015, "red")
    # hexagonal turret
    t = md.part("turret", (0, 0.3, -0.04))
    pts = []
    for (x, z) in [(-0.17, -0.22), (0.17, -0.22), (0.22, -0.02), (0.13, 0.19), (-0.13, 0.19), (-0.22, -0.02)]:
        pts += [(x, 0.3, z - 0.04), (x * 0.78, 0.44, z * 0.8 - 0.04)]
    md.add(hull(pts), "body", t)
    md.add(hull([(x * 0.7, 0.441, z * 0.72 - 0.05) for (x, z) in [(-0.17, -0.22), (0.17, -0.22), (0.22, -0.02), (0.13, 0.19), (-0.13, 0.19), (-0.22, -0.02)]]
                + [(x * 0.62, 0.455, z * 0.62 - 0.05) for (x, z) in [(-0.17, -0.22), (0.17, -0.22), (0.13, 0.19), (-0.13, 0.19)]]), "team", t)
    md.add(box((0.1, 0.1, 0.1), (0, 0.37, 0.18)), "panel", t)  # mantlet
    md.add(cyl(0.03, 0.52, (0, 0.375, 0.47), axis="z", seg=8), "metal", t)
    md.add(cyl(0.042, 0.08, (0, 0.375, 0.72), axis="z", seg=8), "dark", t)  # muzzle brake
    md.add(cyl(0.05, 0.03, (0.07, 0.46, -0.1), seg=8), "dark", t)  # hatch
    md.add(strut((-0.14, 0.44, -0.2), (-0.15, 0.72, -0.24), 0.005, 4), "dark", t)  # antenna
    md.add(box((0.3, 0.07, 0.09), (0, 0.35, -0.29), bevel=0.01), "dark", t)  # bustle rack
    md.meta.update({"turret": t, "muzzle_height": 0.38})
    return md


# ------------------------------------------------------------------ Bastion (GDI) buildings
def _vents(md, x0, x1, y, z, n, slot="dark", depth=0.03, h=0.012):
    for i in range(n):
        x = x0 + (x1 - x0) * i / max(1, n - 1)
        md.add(box((0.02, h, depth), (x, y, z)), slot)


@model
def construction_yard():
    md = Model("construction_yard")
    b = slab(md, 3.0, 3.0)
    # raised front pad with hazard edge
    md.add(box((2.5, 0.05, 1.0), (0, b + 0.025, 0.85)), "concrete")
    stripes(md, (-1.2, b + 0.06, 1.33), (1.2, b + 0.06, 1.33), 12, (0.2, 0.02, 0.05))
    # main hall with a slanted glazed front
    md.add(extrude_profile([(-1.35, b), (0.3, b), (0.3, b + 0.35), (0.0, b + 0.9), (-1.35, b + 0.9)], 2.3), "body")
    md.add(extrude_profile([(0.29, b + 0.36), (0.31, b + 0.36), (0.01, b + 0.9), (-0.01, b + 0.9)], 2.0), "glass")
    md.add(extrude_profile([(-1.25, b + 0.9), (-0.05, b + 0.9), (-0.15, b + 1.02), (-1.15, b + 1.02)], 2.1), "panel")
    md.add(box((2.34, 0.06, 0.08), (0, b + 0.92, -0.02)), "team")
    md.add(box((2.34, 0.08, 0.06), (0, b + 0.32, 0.31)), "team")
    # doors under the glass
    for x in (-0.7, 0.0, 0.7):
        md.add(box((0.4, 0.28, 0.03), (x, b + 0.14, 0.31)), "dark")
        stripes(md, (x - 0.2, b + 0.3, 0.32), (x + 0.2, b + 0.3, 0.32), 5, (0.08, 0.02, 0.02))
    # corner towers at the back
    for s in (-1, 1):
        md.add(ngon_prism(0.32, 1.25, 8, (s * 1.05, b, -1.0)), "panel")
        md.add(ngon_prism(0.34, 0.08, 8, (s * 1.05, b + 1.25, -1.0)), "team")
        md.add(ngon_prism(0.24, 0.12, 8, (s * 1.05, b + 1.33, -1.0), r2=0.14), "body")
        lamp(md, (s * 1.05, b + 1.48, -1.0), 0.04)
        for y in (0.3, 0.7):
            md.add(box((0.12, 0.08, 0.03), (s * 1.05, b + y, -0.67)), "glass")
    # roof: radar dish and vents
    md.add(cyl(0.05, 0.25, (-0.5, b + 1.14, -0.6), seg=6), "metal")
    md.add(cyl(0.28, 0.04, (-0.5, b + 1.3, -0.6), seg=12, r2=0.2, rot=(25, 0, 0)), "metal")
    for z in (-0.9, -0.5):
        _vents(md, 0.25, 0.75, b + 1.03, z, 6, depth=0.25)
    # the crane: turntable, mast and boom over the pad
    cx, cz = 0.95, 0.7
    md.add(cyl(0.26, 0.12, (cx, b + 0.11, cz), seg=10), "dark")
    md.add(taper_box((0.26, 0.26), (0.18, 0.18), 1.35, (cx, b + 0.17, cz)), "hazard")
    for y in (0.45, 0.85, 1.2):
        md.add(box((0.24 - y * 0.05, 0.05, 0.24 - y * 0.05), (cx, b + y, cz)), "dark")
    top = (cx, b + 1.6, cz)
    md.add(box((0.3, 0.2, 0.3), top, bevel=0.03), "body")
    md.add(box((0.14, 0.1, 0.02), (cx, b + 1.62, cz + 0.16)), "glass")
    tip = (-0.55, b + 1.72, 0.9)
    md.add(bar((cx + 0.35, b + 1.68, cz - 0.1), tip, 0.12, 0.12), "hazard")
    md.add(box((0.3, 0.22, 0.26), (cx + 0.42, b + 1.6, cz - 0.12), bevel=0.03), "dark")  # counterweight
    md.add(strut((tip[0] + 0.05, tip[1], tip[2]), (tip[0] + 0.05, b + 0.75, tip[2]), 0.012, 4), "dark")
    md.add(box((0.16, 0.12, 0.16), (tip[0] + 0.05, b + 0.7, tip[2]), bevel=0.02), "hazard")
    lamp(md, (tip[0], tip[1] + 0.08, tip[2]), 0.03, "red")
    for s in (-1, 1):
        lamp(md, (s * 1.3, b + 0.1, 1.3), 0.04)
    return md


@model
def power_plant():
    md = Model("power_plant")
    b = slab(md, 2.0, 2.0)
    md.add(box((1.7, 0.45, 1.4), (0, b + 0.225, -0.15), bevel=0.06), "body")
    md.add(box((1.72, 0.06, 1.42), (0, b + 0.42, -0.15)), "team")
    # twin turbine stacks
    for s in (-1, 1):
        x = s * 0.42
        md.add(cyl(0.36, 0.95, (x, b + 0.92, -0.2), seg=14, r2=0.3), "panel")
        for y in (0.6, 0.9, 1.2):
            md.add(cyl(0.375 - (y - 0.45) * 0.06, 0.04, (x, b + y, -0.2), seg=14), "dark")
        md.add(cyl(0.32, 0.06, (x, b + 1.42, -0.2), seg=14), "body")
        md.add(cyl(0.25, 0.02, (x, b + 1.455, -0.2), seg=14), "glow")
        for a in range(0, 180, 45):
            md.add(box((0.5, 0.02, 0.04), (x, b + 1.47, -0.2), rot=(0, a, 0)), "metal")
        md.add(cyl(0.05, 0.06, (x, b + 1.48, -0.2), seg=8), "dark")
        # coolant pipes
        md.add(strut((x, b + 0.55, 0.12), (x, b + 0.55, 0.62), 0.05), "metal")
        md.add(strut((x, b + 0.55, 0.62), (x, b + 0.15, 0.62), 0.05), "metal")
    # front transformer bank with insulators
    md.add(box((1.2, 0.28, 0.3), (0, b + 0.14, 0.72), bevel=0.03), "panel")
    for x in np.linspace(-0.45, 0.45, 4):
        for k in range(3):
            md.add(cyl(0.045 - k * 0.005, 0.04, (x, b + 0.31 + k * 0.05, 0.72), seg=8), "glass")
        lamp(md, (x, b + 0.47, 0.72), 0.018, "glow")
    stripes(md, (-0.6, b + 0.29, 0.875), (0.6, b + 0.29, 0.875), 8, (0.15, 0.03, 0.02))
    md.add(box((0.4, 0.14, 0.02), (0.55, b + 0.26, 0.56)), "glass")
    return md


@model
def refinery():
    md = Model("refinery")
    b = slab(md, 3.0, 3.0)
    # processing hall on the west half
    md.add(extrude_profile([(-1.35, b), (1.2, b), (1.2, b + 0.7), (0.9, b + 0.95), (-1.35, b + 0.95)], 1.6, (-0.55, 0, 0)), "body")
    md.add(box((1.64, 0.07, 0.07), (-0.55, b + 0.72, 1.22)), "team")
    md.add(box((1.4, 0.2, 0.02), (-0.55, b + 0.45, 1.21)), "glass")
    md.add(box((1.2, 0.1, 2.0), (-0.55, b + 1.0, -0.2), bevel=0.03), "panel")
    for z in (-0.9, -0.3, 0.3):
        md.add(cyl(0.12, 0.25, (-0.9, b + 1.15, z), seg=8, r2=0.09), "metal")
    # tiberium silos flanking the dock
    for z in (-0.95, 0.95):
        md.add(cyl(0.34, 1.1, (0.95, b + 0.55, z), seg=14), "panel")
        md.add(cyl(0.36, 0.08, (0.95, b + 0.3, z), seg=14), "team")
        md.add(cyl(0.3, 0.14, (0.95, b + 1.17, z), seg=14, r2=0.16), "body")
        md.add(cyl(0.05, 0.1, (0.95, b + 1.28, z), seg=6), "metal")
        for a in (0, 90, 180, 270):
            ang = math.radians(a + 30)
            md.add(box((0.05, 0.6, 0.04), (0.95 + math.cos(ang) * 0.33, b + 0.72, z + math.sin(ang) * 0.33), rot=(0, -a - 30, 0)), "tib")
        md.add(strut((0.62, b + 0.9, z), (0.25, b + 0.9, z * 0.8), 0.05), "metal")
    # unloading bay: harvester docks on the east edge (cell just outside)
    md.add(box((1.1, 0.04, 0.9), (0.9, b + 0.02, 0)), "dark")
    stripes(md, (1.44, b + 0.05, -0.45), (1.44, b + 0.05, 0.45), 8, (0.05, 0.02, 0.1))
    md.add(hull([(0.25, b, -0.45), (0.25, b, 0.45), (0.25, b + 0.6, -0.4), (0.25, b + 0.6, 0.4),
                 (0.7, b + 0.55, -0.35), (0.7, b + 0.55, 0.35), (0.7, b + 0.45, -0.35), (0.7, b + 0.45, 0.35)]), "panel")
    md.add(box((0.05, 0.22, 0.6), (0.25, b + 0.2, 0)), "tib")
    md.add(bar((0.7, b + 0.5, 0), (1.3, b + 0.62, 0), 0.25, 0.08), "hazard")  # intake arm
    md.add(box((0.2, 0.08, 0.35), (1.35, b + 0.55, 0), bevel=0.02), "dark")
    lamp(md, (1.4, b + 0.66, 0), 0.03, "tib")
    for z in (-0.45, 0.45):
        lamp(md, (1.4, b + 0.06, z), 0.035)
    return md


@model
def barracks():
    md = Model("barracks")
    b = slab(md, 2.0, 2.0)
    md.add(taper_box((1.5, 1.2), (1.2, 0.95), 0.55, (0, b, -0.15)), "body")
    md.add(taper_box((1.22, 0.97), (1.1, 0.85), 0.07, (0, b + 0.55, -0.15)), "team")
    md.add(taper_box((0.7, 0.55), (0.55, 0.42), 0.3, (-0.15, b + 0.62, -0.25)), "panel")
    md.add(box((0.5, 0.06, 0.02), (-0.15, b + 0.8, 0.02)), "glass")
    # door with an awning
    md.add(box((0.4, 0.34, 0.1), (0.25, b + 0.17, 0.43)), "dark")
    md.add(hull([(0.0, b + 0.36, 0.38), (0.5, b + 0.36, 0.38), (0.0, b + 0.4, 0.55), (0.5, b + 0.4, 0.55),
                 (0.0, b + 0.42, 0.38), (0.5, b + 0.42, 0.38)]), "panel")
    lamp(md, (0.25, b + 0.47, 0.43), 0.03)
    for x in (-0.45, -0.2):
        md.add(box((0.14, 0.08, 0.02), (x, b + 0.35, 0.47)), "glass")
    # sandbag walls
    for (x, z, ry, n) in [(-0.55, 0.78, 0, 4), (0.75, 0.55, 90, 3), (-0.85, 0.2, 90, 3)]:
        for k in range(n):
            off = (k - (n - 1) / 2) * 0.16
            px, pz = (x + off, z) if ry == 0 else (x, z + off)
            for lvl in range(2):
                md.add(box((0.15, 0.07, 0.09), (px + (0.04 if lvl else 0), b + 0.035 + lvl * 0.065, pz), rot=(0, ry, 0), bevel=0.025), "concrete")
    # flag pole and antenna
    md.add(strut((0.75, b, -0.75), (0.75, b + 1.1, -0.75), 0.02), "metal")
    md.add(box((0.02, 0.18, 0.3), (0.75, b + 0.98, -0.6)), "team")
    md.add(strut((-0.3, b + 0.92, -0.35), (-0.3, b + 1.3, -0.35), 0.012), "dark")
    lamp(md, (-0.3, b + 1.31, -0.35), 0.02, "red")
    return md


@model
def war_factory():
    md = Model("war_factory")
    b = slab(md, 3.0, 3.0)
    prof = [(-1.35, b), (1.0, b), (1.0, b + 0.95), (0.7, b + 1.25), (-1.0, b + 1.25), (-1.35, b + 1.0)]
    md.add(extrude_profile(prof, 2.5), "body")
    # roof ribs and team stripes
    for x in np.linspace(-1.1, 1.1, 5):
        md.add(extrude_profile([(-1.38, b + 0.95), (1.03, b + 0.95), (1.03, b + 0.98), (0.71, b + 1.29), (-1.01, b + 1.29), (-1.38, b + 1.03)], 0.08, (x, 0, 0)), "panel")
    md.add(box((2.54, 0.06, 0.08), (0, b + 1.27, 0.68)), "team")
    md.add(box((2.54, 0.06, 0.08), (0, b + 1.27, -0.98)), "team")
    # the big door
    md.add(box((1.4, 0.88, 0.06), (0, b + 0.44, 1.01)), "dark")
    for y in np.linspace(0.08, 0.8, 7):
        md.add(box((1.3, 0.035, 0.03), (0, b + y, 1.045)), "panel")
    stripes(md, (-0.72, b + 0.93, 1.04), (0.72, b + 0.93, 1.04), 9, (0.16, 0.08, 0.05))
    for s in (-1, 1):
        md.add(box((0.12, 0.95, 0.12), (s * 0.76, b + 0.47, 1.03)), "panel")
        lamp(md, (s * 0.76, b + 1.0, 1.1), 0.04)
        md.add(box((0.35, 0.2, 0.02), (s * 1.05, b + 0.55, 1.01)), "glass")
    # apron with guide stripes
    md.add(box((1.5, 0.03, 0.4), (0, b + 0.015, 1.2)), "dark")
    for s in (-1, 1):
        stripes(md, (s * 0.7, b + 0.04, 1.02), (s * 0.7, b + 0.04, 1.42), 4, (0.06, 0.02, 0.1))
    # rooftop gantry and exhaust stacks
    for s in (-1, 1):
        md.add(box((0.08, 0.5, 0.08), (s * 0.9, b + 1.5, -0.4)), "hazard")
    md.add(box((1.9, 0.1, 0.12), (0, b + 1.75, -0.4)), "hazard")
    md.add(box((0.2, 0.14, 0.2), (0.3, b + 1.66, -0.4), bevel=0.02), "dark")
    for x in (-0.8, -0.5):
        md.add(cyl(0.08, 0.45, (x, b + 1.45, -1.05), seg=8), "metal")
        md.add(cyl(0.09, 0.05, (x, b + 1.68, -1.05), seg=8), "dark")
    return md


@model
def guard_tower():
    md = Model("guard_tower")
    md.add(ngon_prism(0.47, 0.14, 8, (0, 0, 0), r2=0.44), "concrete")
    md.add(ngon_prism(0.3, 0.8, 6, (0, 0.14, 0), r2=0.23), "body")
    for y in (0.3, 0.6):
        md.add(ngon_prism(0.305 - y * 0.09, 0.05, 6, (0, 0.14 + y, 0)), "panel")
    md.add(box((0.05, 0.12, 0.04), (0, 0.55, 0.27)), "glass")
    md.add(ngon_prism(0.3, 0.08, 6, (0, 0.94, 0), r2=0.32), "team")
    t = md.part("turret", (0, 1.02, 0))
    md.add(hull([(x, 1.02, z) for x in (-0.2, 0.2) for z in (-0.2, 0.16)] + [(x, 1.2, z) for x in (-0.15, 0.15) for z in (-0.16, 0.08)]), "body", t)
    md.add(hull([(x, 1.201, z) for x in (-0.14, 0.14) for z in (-0.15, 0.07)] + [(x, 1.215, z) for x in (-0.1, 0.1) for z in (-0.1, 0.03)]), "team", t)
    md.add(box((0.14, 0.1, 0.1), (0, 1.1, 0.19)), "panel", t)
    for s in (-1, 1):
        md.add(cyl(0.025, 0.42, (s * 0.04, 1.1, 0.4), axis="z", seg=8), "metal", t)
    md.add(box((0.1, 0.04, 0.02), (0, 1.16, 0.17)), "glass", t)
    lamp(md, (-0.12, 1.24, -0.12), 0.025, "red", t)
    md.meta.update({"turret": t, "muzzle_height": 1.1})
    return md


# ------------------------------------------------------------------ Veil (Nod) buildings
# Angular black structures, red trim, spikes and red lamps.
def _pyramid(md, bottom, top, h, at, slot="body"):
    md.add(taper_box(bottom, top, h, at), slot)


def _spikes(md, pts, r=0.05, h=0.45, slot="panel"):
    for (x, y, z) in pts:
        md.add(spike((x, y, z), r, h, (0, 0), 4), slot)


@model
def construction_yard_veil():
    md = Model("construction_yard_veil")
    b = slab(md, 3.0, 3.0)
    md.add(ngon_prism(1.35, 0.1, 8, (0, b, -0.1), r2=1.3), "concrete")
    # stepped pyramid core
    _pyramid(md, (2.1, 1.8), (1.6, 1.3), 0.5, (0, b + 0.1, -0.35))
    _pyramid(md, (1.62, 1.32), (1.1, 0.8), 0.45, (0, b + 0.6, -0.35), "panel")
    _pyramid(md, (1.12, 0.82), (0.2, 0.2), 0.55, (0, b + 1.05, -0.35))
    md.add(box((1.64, 0.05, 1.34), (0, b + 0.62, -0.35)), "hazard")
    md.add(box((1.14, 0.05, 0.84), (0, b + 1.07, -0.35)), "team")
    md.add(spike((0, b + 1.55, -0.35), 0.08, 0.5), "dark")
    lamp(md, (0, b + 2.07, -0.35), 0.035, "red")
    # glowing slit windows on the front slope
    for x in (-0.5, -0.25, 0.25, 0.5):
        md.add(box((0.1, 0.08, 0.03), (x, b + 0.4, 0.57), rot=(-10, 0, 0)), "red")
    md.add(box((0.5, 0.35, 0.06), (0, b + 0.28, 0.56)), "dark")  # gate
    # angular crane arm
    cx, cz = -1.0, 0.8
    md.add(ngon_prism(0.22, 0.14, 6, (cx, b, cz)), "dark")
    md.add(bar((cx, b + 0.1, cz), (cx + 0.15, b + 1.3, cz - 0.1), 0.16, 0.16), "hazard")
    tip = (0.7, b + 1.55, 0.85)
    md.add(bar((cx - 0.2, b + 1.25, cz - 0.15), tip, 0.1, 0.14), "body")
    md.add(box((0.26, 0.2, 0.22), (cx - 0.25, b + 1.25, cz - 0.15), bevel=0.03), "dark")
    md.add(strut(tip, (tip[0], b + 0.6, tip[2]), 0.012, 4), "dark")
    md.add(spike((tip[0], b + 0.45, tip[2]), 0.09, 0.18), "hazard")
    lamp(md, (tip[0], tip[1] + 0.07, tip[2]), 0.03, "red")
    _spikes(md, [(s * 1.25, b, -1.25) for s in (-1, 1)] + [(1.25, b, 1.2)], 0.09, 0.7)
    for s in (-1, 1):
        lamp(md, (s * 1.3, b + 0.05, 1.3), 0.035, "red")
    return md


@model
def power_plant_veil():
    md = Model("power_plant_veil")
    b = slab(md, 2.0, 2.0)
    _pyramid(md, (1.7, 1.7), (1.0, 1.0), 0.55, (0, b, 0))
    md.add(box((1.04, 0.05, 1.04), (0, b + 0.56, 0)), "hazard")
    # central energy core with fins
    md.add(ngon_prism(0.3, 0.6, 6, (0, b + 0.55, 0), r2=0.22), "panel")
    md.add(ngon_prism(0.24, 0.35, 6, (0, b + 1.15, 0), r2=0.12), "glow")
    md.add(spike((0, b + 1.5, 0), 0.1, 0.35), "dark")
    for a in range(0, 360, 90):
        r = math.radians(a + 45)
        x, z = math.cos(r), math.sin(r)
        md.add(hull([(x * 0.2, b + 0.55, z * 0.2), (x * 0.62, b + 0.55, z * 0.62), (x * 0.2, b + 1.35, z * 0.2),
                     (x * 0.2 + z * 0.03, b + 0.55, z * 0.2 - x * 0.03), (x * 0.2 - z * 0.03, b + 0.55, z * 0.2 + x * 0.03)]), "body")
        md.add(cyl(0.1, 0.4, (x * 0.72, b + 0.2 + 0.2, z * 0.72), seg=6), "dark")
        md.add(cyl(0.07, 0.08, (x * 0.72, b + 0.64, z * 0.72), seg=6), "red")
    for x in (-0.3, 0.0, 0.3):
        md.add(box((0.12, 0.04, 0.03), (x, b + 0.2, 0.8), rot=(-40, 0, 0)), "team")
    return md


@model
def refinery_veil():
    md = Model("refinery_veil")
    b = slab(md, 3.0, 3.0)
    # angular processing hall
    md.add(extrude_profile([(-1.35, b), (1.2, b), (1.2, b + 0.35), (0.7, b + 0.95), (-1.0, b + 0.95), (-1.35, b + 0.6)], 1.6, (-0.55, 0, 0)), "body")
    md.add(extrude_profile([(0.77, b + 0.88), (0.8, b + 0.85), (0.72, b + 0.97), (0.69, b + 0.97)], 1.62, (-0.55, 0, 0)), "hazard")
    md.add(extrude_profile([(1.19, b + 0.36), (1.22, b + 0.36), (1.16, b + 0.45), (1.13, b + 0.45)], 1.62, (-0.55, 0, 0)), "hazard")
    md.add(box((1.64, 0.05, 0.25), (-0.55, b + 0.97, 0.55)), "team")
    md.add(box((1.64, 0.05, 0.12), (-0.55, b + 0.97, -0.95)), "team")
    for x in (-1.0, -0.55, -0.1):
        md.add(box((0.2, 0.08, 0.03), (x, b + 0.2, 1.21)), "red")
    md.add(spike((-0.55, b + 0.97, -0.15), 0.12, 0.6), "panel")
    # hexagonal tiberium tanks
    for z in (-0.95, 0.95):
        md.add(ngon_prism(0.34, 0.95, 6, (0.95, b, z), r2=0.3), "panel")
        md.add(ngon_prism(0.3, 0.3, 6, (0.95, b + 0.95, z), r2=0.08), "body")
        md.add(ngon_prism(0.345, 0.06, 6, (0.95, b + 0.8, z)), "team")
        for a in (0, 120, 240):
            ang = math.radians(a + 60)
            md.add(box((0.06, 0.5, 0.04), (0.95 + math.cos(ang) * 0.3, b + 0.45, z + math.sin(ang) * 0.3), rot=(0, -a - 60, 0)), "tib")
        md.add(strut((0.65, b + 0.7, z), (0.25, b + 0.7, z * 0.8), 0.045), "metal")
    # unloading bay on the east edge
    md.add(box((1.1, 0.04, 0.9), (0.9, b + 0.02, 0)), "dark")
    stripes(md, (1.44, b + 0.05, -0.45), (1.44, b + 0.05, 0.45), 8, (0.05, 0.02, 0.1))
    md.add(hull([(0.25, b, -0.45), (0.25, b, 0.45), (0.25, b + 0.65, -0.3), (0.25, b + 0.65, 0.3), (0.75, b + 0.35, -0.3), (0.75, b + 0.35, 0.3), (0.75, b, -0.4), (0.75, b, 0.4)]), "panel")
    md.add(box((0.05, 0.2, 0.5), (0.5, b + 0.25, 0), rot=(0, 0, 30)), "tib")
    md.add(bar((0.6, b + 0.5, 0), (1.3, b + 0.62, 0), 0.22, 0.08), "hazard")
    md.add(spike((1.33, b + 0.45, 0), 0.1, 0.12), "dark")
    for z in (-0.45, 0.45):
        lamp(md, (1.4, b + 0.06, z), 0.035, "red")
    return md


@model
def barracks_veil():
    """The Hand: a stepped temple with a giant raised hand."""
    md = Model("barracks_veil")
    b = slab(md, 2.0, 2.0)
    _pyramid(md, (1.7, 1.5), (1.3, 1.1), 0.35, (0, b, -0.1))
    md.add(box((1.32, 0.04, 1.12), (0, b + 0.35, -0.1)), "hazard")
    _pyramid(md, (1.0, 0.8), (0.7, 0.55), 0.25, (0, b + 0.37, -0.15), "panel")
    md.add(box((0.3, 0.26, 0.05), (0, b + 0.13, 0.63)), "dark")  # doorway
    for s in (-1, 1):
        lamp(md, (s * 0.22, b + 0.3, 0.64), 0.025, "red")
    # the hand, palm facing forward
    hand_start = sum(len(p["meshes"]) for p in md.parts.values())
    hb = b + 0.62
    wrist = (0, hb, -0.15)
    md.add(taper_box((0.28, 0.22), (0.32, 0.2), 0.25, wrist), "body")
    md.add(taper_box((0.3, 0.24), (0.3, 0.24), 0.06, (0, hb + 0.05, -0.15)), "team")  # cuff
    md.add(box((0.4, 0.38, 0.14), (0, hb + 0.44, -0.15), bevel=0.03), "body")  # palm
    for i, x in enumerate((-0.15, -0.05, 0.05, 0.15)):
        ln = [0.26, 0.3, 0.28, 0.22][i]
        y0 = hb + 0.63
        md.add(box((0.085, ln * 0.55, 0.11), (x, y0 + ln * 0.27, -0.15), bevel=0.02), "body")
        md.add(box((0.08, ln * 0.5, 0.1), (x, y0 + ln * 0.8, -0.13), rot=(12, 0, 0), bevel=0.02), "body")
    md.add(box((0.09, 0.22, 0.1), (-0.25, hb + 0.4, -0.12), rot=(0, 0, 35), bevel=0.02), "body")  # thumb
    md.add(box((0.1, 0.1, 0.02), (0, hb + 0.46, -0.075)), "red")  # palm sigil
    for m, _ in md.parts["body"]["meshes"][hand_start:]:
        m.apply_translation((0, -hb, 0.15))
        m.apply_scale(1.45)
        m.apply_translation((0, hb, -0.15))
    _spikes(md, [(s * 0.75, b, sz) for s in (-1, 1) for sz in (-0.75, 0.55)], 0.06, 0.45)
    return md


@model
def war_factory_veil():
    md = Model("war_factory_veil")
    b = slab(md, 3.0, 3.0)
    prof = [(-1.35, b), (1.0, b), (1.0, b + 0.5), (0.6, b + 1.2), (-0.9, b + 1.2), (-1.35, b + 0.7)]
    md.add(extrude_profile(prof, 2.5), "body")
    md.add(extrude_profile([(0.99, b + 0.51), (1.02, b + 0.51), (0.97, b + 0.6), (0.94, b + 0.6)], 2.52), "hazard")
    md.add(box((2.52, 0.05, 0.22), (0, b + 1.22, 0.45)), "team")
    md.add(box((1.2, 0.05, 1.2), (0, b + 1.2, -0.2)), "panel")
    for x in (-0.9, 0.9):
        md.add(taper_box((0.5, 1.6), (0.3, 1.3), 0.35, (x, b + 1.2, -0.15)), "panel")
        md.add(spike((x, b + 1.55, -0.15), 0.1, 0.4), "dark")
    # angled door frame
    md.add(box((1.4, 0.85, 0.06), (0, b + 0.42, 1.01)), "dark")
    for y in np.linspace(0.08, 0.78, 6):
        md.add(box((1.3, 0.04, 0.03), (0, b + y, 1.045)), "panel")
    md.add(hull([(-0.85, b, 1.0), (-0.7, b, 1.0), (-0.85, b + 1.0, 1.0), (-0.7, b + 0.9, 1.0), (-0.85, b, 1.12), (-0.7, b, 1.12), (-0.85, b + 0.95, 1.08), (-0.7, b + 0.85, 1.08)]), "hazard")
    md.add(hull([(0.85, b, 1.0), (0.7, b, 1.0), (0.85, b + 1.0, 1.0), (0.7, b + 0.9, 1.0), (0.85, b, 1.12), (0.7, b, 1.12), (0.85, b + 0.95, 1.08), (0.7, b + 0.85, 1.08)]), "hazard")
    for s in (-1, 1):
        lamp(md, (s * 0.78, b + 1.0, 1.08), 0.035, "red")
    md.add(box((1.5, 0.03, 0.4), (0, b + 0.015, 1.2)), "dark")
    for s in (-1, 1):
        stripes(md, (s * 0.7, b + 0.04, 1.02), (s * 0.7, b + 0.04, 1.42), 4, (0.06, 0.02, 0.1))
    _spikes(md, [(s * 1.25, b, -1.25) for s in (-1, 1)], 0.08, 0.6)
    return md


@model
def guard_tower_veil():
    md = Model("guard_tower_veil")
    md.add(ngon_prism(0.47, 0.12, 4, (0, 0, 0), r2=0.44, phase=0.0), "concrete")
    md.add(taper_box((0.6, 0.6), (0.3, 0.3), 0.85, (0, 0.12, 0)), "body")
    md.add(box((0.34, 0.05, 0.34), (0, 0.9, 0)), "hazard")
    for s in (-1, 1):
        md.add(box((0.04, 0.2, 0.03), (s * 0.1, 0.45, 0.24), rot=(-18, 0, 0)), "red")
    t = md.part("turret", (0, 0.95, 0))
    md.add(hull([(0, 0.95, 0.24), (-0.18, 0.95, -0.12), (0.18, 0.95, -0.12), (0, 1.15, 0.12), (-0.12, 1.15, -0.1), (0.12, 1.15, -0.1)]), "body", t)
    md.add(hull([(0, 1.151, 0.1), (-0.1, 1.151, -0.08), (0.1, 1.151, -0.08), (0, 1.2, -0.02)]), "team", t)
    md.add(cyl(0.03, 0.4, (0, 1.06, 0.38), axis="z", seg=6), "metal", t)
    md.add(cyl(0.045, 0.06, (0, 1.06, 0.58), axis="z", seg=6), "red", t)
    md.meta.update({"turret": t, "muzzle_height": 1.06})
    return md


# ------------------------------------------------------------------ terrain props
@model
def tiberium():
    """A tiberium crystal cluster (one surface; the map tints green or blue)."""
    md = Model("tiberium")
    rng = np.random.default_rng(3)
    spec = [(0, 0, 0.1, 0.62, (0.0, 0.0)), (0.12, 0.05, 0.07, 0.4, (0.35, 0.1)), (-0.1, 0.08, 0.075, 0.45, (-0.3, 0.2)),
            (0.02, -0.12, 0.06, 0.34, (0.05, -0.4)), (-0.13, -0.08, 0.05, 0.28, (-0.35, -0.3)), (0.14, -0.1, 0.05, 0.25, (0.4, -0.35))]
    for (x, z, r, h, lean) in spec:
        r *= 1 + rng.uniform(-0.1, 0.1)
        md.add(crystal(r, h, (x, -0.02, z), lean), "tib")
    return md


@model
def rock():
    """A faceted boulder filling about one cell."""
    md = Model("rock")
    rng = np.random.default_rng(11)
    pts = []
    for _ in range(26):
        a = rng.uniform(0, 2 * math.pi)
        y = rng.uniform(0, 1)
        r = (0.55 - 0.25 * y * y) * rng.uniform(0.8, 1.05)
        pts.append((math.cos(a) * r, y * 0.9 - 0.05, math.sin(a) * r * 0.9))
    md.add(hull(pts), "body")
    for (x, z, s) in [(0.42, 0.25, 0.22), (-0.35, -0.38, 0.18), (-0.45, 0.3, 0.15)]:
        sub = [(x + math.cos(a) * s * rng.uniform(0.7, 1.1), rng.uniform(-0.05, s * 1.2), z + math.sin(a) * s * rng.uniform(0.7, 1.1))
               for a in rng.uniform(0, 2 * math.pi, 10)]
        md.add(hull(sub), "body")
    return md


@model
def blossom_tree():
    """Tiberium blossom tree: twisted veined trunk with glowing seed pods."""
    md = Model("blossom_tree")
    # flared trunk from stacked twisted rings
    rings = []
    for k in range(7):
        y = k * 0.26
        r = 0.36 * (1 - k / 8) ** 1.4 + 0.06
        rings.append((y, r, k * 0.35))
    for (y0, r0, a0), (y1, r1, a1) in zip(rings, rings[1:]):
        pts = [(math.cos(a0 + i * 1.047) * r0, y0, math.sin(a0 + i * 1.047) * r0) for i in range(6)]
        pts += [(math.cos(a1 + i * 1.047) * r1, y1, math.sin(a1 + i * 1.047) * r1) for i in range(6)]
        md.add(hull(pts), "dark")
    # roots and green veins
    for i in range(5):
        a = i * 2 * math.pi / 5 + 0.3
        md.add(bar((math.cos(a) * 0.2, 0.2, math.sin(a) * 0.2), (math.cos(a) * 0.62, -0.02, math.sin(a) * 0.62), 0.1, 0.08), "dark")
        md.add(bar((math.cos(a) * 0.3, 0.02, math.sin(a) * 0.3), (math.cos(a + 0.4) * 0.12, 1.1, math.sin(a + 0.4) * 0.12), 0.03, 0.03), "tib")
    # canopy of drooping branches with pods
    for i in range(6):
        a = i * math.pi / 3
        tip = (math.cos(a) * 0.62, 1.35 + (i % 2) * 0.12, math.sin(a) * 0.62)
        md.add(bar((0, 1.6, 0), tip, 0.07, 0.06), "dark")
        md.add(sphere(0.15 + (i % 2) * 0.04, (tip[0], tip[1] - 0.12, tip[2]), sub=1, scale=(1, 1.25, 1)), "tib")
    md.add(sphere(0.2, (0, 1.72, 0), sub=1, scale=(1, 1.3, 1)), "tib")
    return md
