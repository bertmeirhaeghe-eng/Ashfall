"""Builds every Ashfall model into res://models/*.amdl.

    pip install -r tools/models/requirements.txt
    python3 tools/models/build_models.py            # all models
    python3 tools/models/build_models.py walker     # just some

Units with an STL source (tools/models/stl) are converted: oriented, scaled,
split into animated parts and painted into material slots. The rest are
modelled procedurally in procedural.py in a Tiberian Sun style.
"""
import os
import sys

import numpy as np

import procedural
from ashmodel import Model, load_stl, split_components, submesh

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "models"))
STL = os.path.join(HERE, "stl")


def comp_info(c):
    mn, mx = c.bounds
    return mn, mx, (mn + mx) / 2


def paint(model, mesh, part, height, team_above=0.62, team_up=0.55, dark_below=0.0,
          team_mask=None, dark_mask=None):
    """Split one mesh into material slots by face position and orientation."""
    tri = mesh.triangles
    cen = tri.mean(1)
    nrm = mesh.face_normals
    slot = np.full(len(tri), "body", dtype=object)
    if dark_below > 0:
        slot[cen[:, 1] < dark_below * height] = "dark"
    team = (nrm[:, 1] > team_up) & (cen[:, 1] > team_above * height)
    if team_mask is not None:
        team &= team_mask(cen, nrm)
    slot[team] = "team"
    if dark_mask is not None:
        slot[dark_mask(cen, nrm)] = "dark"
    for s in set(slot):
        sm = submesh(mesh, slot == s)
        if sm is not None:
            model.add(sm, s, part)


def add_components(model, comps, part, height, **kw):
    for c in comps:
        c = c.copy()
        paint(model, c, part, height, **kw)


# --------------------------------------------------------------- STL units
def harvester():
    """GDI harvester (CC2_harvester.STL): Warden-sized tiberium truck."""
    L = 1.5
    m = load_stl(os.path.join(STL, "harvester.stl"), "+x", length=L)
    H = m.bounds[1][1]
    md = Model("harvester")
    comps = split_components(m)
    for c in comps:
        mn, mx, ce = comp_info(c)
        if mx[1] < 0.5 * H and abs(ce[0]) > 0.12:
            md.add(c, "dark")  # wheels and running gear
        elif mn[2] > 0.3 * L and mx[1] < 0.5 * H:
            md.add(c, "metal")  # front scoop
        else:
            paint(md, c, "body", H, team_above=0.8, team_up=0.8)
    # glowing tiberium gauge windows on the hopper sides; they fill with cargo
    # glowing tiberium gauge windows on the hopper walls; they fill with cargo
    y0, y1 = 0.58 * H, 0.74 * H
    origins = np.array([[1.0, (y0 + y1) / 2, -0.4], [-1.0, (y0 + y1) / 2, -0.4]])
    hits, _, _ = m.ray.intersects_location(origins, np.array([[-1.0, 0, 0], [1.0, 0, 0]]), multiple_hits=False)
    hx = float(np.max(np.abs(hits[:, 0]))) if len(hits) else 0.18
    bin_part = md.part("bin", (0, y0, -0.27 * L))
    for sx in (-1, 1):
        md.add(procedural.box((0.01, y1 - y0, 0.33 * L), (sx * (hx + 0.006), (y0 + y1) / 2, -0.27 * L)), "tib", bin_part)
    md.meta.update({"bin": "bin", "muzzle_height": 0.6})
    return md


def _walker(name, src, forward, height, is_leg, swing, muzzle, team_above):
    m = load_stl(os.path.join(STL, src), forward, height=height)
    comps = split_components(m)
    legs = [c for c in comps if is_leg(*comp_info(c))]
    upper = [c for c in comps if not is_leg(*comp_info(c))]
    # centre the model on its legs, not on the bounding box (guns stick out)
    lmn = np.min([c.bounds[0] for c in legs], 0)
    lmx = np.max([c.bounds[1] for c in legs], 0)
    shift = -(lmn + lmx) / 2
    shift[1] = 0
    for c in comps:
        c.apply_translation(shift)
    hip_y = max(c.bounds[1][1] for c in legs) * 0.96
    md = Model(name)
    turret = md.part("turret", (0, hip_y, 0))
    add_components(md, upper, turret, height, team_above=team_above, team_up=0.6)
    names = []
    for side in (-1, 1):
        side_legs = [c for c in legs if np.sign(c.bounds.mean(0)[0]) == side]
        cx = float(np.mean([c.bounds.mean(0)[0] for c in side_legs]))
        pname = md.part("leg_%s" % ("r" if side < 0 else "l"), (cx, hip_y, 0))
        names.append(pname)
        for c in side_legs:
            mn, mx, ce = comp_info(c)
            md.add(c, "dark" if mx[1] < 0.07 * height else "panel", pname)
    md.meta.update({"turret": "turret", "legs": names, "leg_swing": swing, "muzzle_height": muzzle})
    return md


def walker():
    """Warden Walker = GDI Titan (SK_VH_Titan_Reborn.stl)."""
    return _walker("walker", "titan.stl", "-y", 1.45,
                   lambda mn, mx, ce: mx[1] < 0.53 * 1.45 and not (abs(ce[0] - 0.02) < 0.08 and mn[1] > 0.4 * 1.45),
                   0.3, 0.86, 0.8)


def scout_mech():
    """Pathfinder Mech = GDI Wolverine (SK_VH_Wolverine_Reborn.stl)."""
    H = 0.95
    return _walker("scout_mech", "wolverine.stl", "-x", H,
                   lambda mn, mx, ce: mx[1] < 0.37 * H and np.max(np.abs([mn[0], mx[0]])) < 0.27 * H,
                   0.35, 0.42, 0.85)


MODELS = {
    "harvester": harvester,
    "walker": walker,
    "scout_mech": scout_mech,
}
MODELS.update(procedural.MODELS)


def main(names):
    os.makedirs(OUT, exist_ok=True)
    for name in names or MODELS:
        md = MODELS[name]()
        md.write(os.path.join(OUT, name + ".amdl"))


if __name__ == "__main__":
    main(sys.argv[1:])
