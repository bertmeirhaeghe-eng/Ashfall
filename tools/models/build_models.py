"""Builds every Ashfall model into res://models/*.amdl.

    pip install -r tools/models/requirements.txt
    python3 tools/models/build_models.py            # all models
    python3 tools/models/build_models.py walker     # just some

Units with an STL source (tools/models/stl) are converted: oriented, scaled,
split into animated parts and painted into material slots. Environment art
(houses, trees...) comes from found FBX/OBJ assets, converted and pruned to a
poly budget in tools/models/src/environment (see the README there) and
painted the same way. The rest is modelled procedurally in procedural.py in a
Tiberian Sun style.
"""
import os
import sys

import numpy as np
import trimesh

import procedural
from ashmodel import Model, load_env, load_stl, split_components, submesh

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "models"))
STL = os.path.join(HERE, "stl")
ENV = os.path.join(HERE, "src", "environment")


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


# ----------------------------------------------------- environment art (OBJ)
def _roof_paint(model, mesh, part, height, roof_frac=0.65, up=0.5, found_frac=0.05):
    """Heuristic paint for a merged building mesh with no named sub-parts:
    a dark foundation strip, plain walls, and an upward-facing roof."""
    tri = mesh.triangles
    cen = tri.mean(1)
    nrm = mesh.face_normals
    slot = np.full(len(tri), "body", dtype=object)
    slot[cen[:, 1] < found_frac * height] = "dark"
    slot[(cen[:, 1] > roof_frac * height) & (nrm[:, 1] > up)] = "panel"
    for s in set(slot):
        sm = submesh(mesh, slot == s)
        if sm is not None:
            model.add(sm, s, part)


def _flat_cap(x0, x1, z0, z1, y):
    """An upward-facing rectangle, for capping a roof that doesn't fully
    close over its interior (seen from the game's overhead camera)."""
    m = trimesh.Trimesh(vertices=[[x0, y, z0], [x1, y, z0], [x1, y, z1], [x0, y, z1]],
                         faces=[[0, 1, 2], [0, 2, 3]], process=False)
    if m.face_normals[0][1] < 0:
        m.invert()
    return m


def house():
    """Farmhouse decor building (data/rules.json "house"), from a found FBX
    asset converted and pruned in tools/models/src/environment/house.obj."""
    parts = load_env(os.path.join(ENV, "house.obj"), height=1.5)
    slot_of = {"fundametnts": "dark", "windows": "glass", "window_roof": "glass",
               "door": "dark", "barrels": "metal", "wall_barrels": "metal",
               "lamp_exterior": "lamp", "roof": "panel", "ridge": "panel", "chimneys": "panel"}
    md = Model("house")
    for name, mesh in parts.items():
        md.add(mesh, slot_of.get(name, "body"), "body")
    # safety net: an eave-height cap under the roof, so an unnoticed gap in
    # this complex, multi-wing roof can't show through to open sky
    all_v = np.concatenate([m.vertices for m in parts.values()])
    eave_y = parts["roof"].bounds[0][1]
    md.add(_flat_cap(all_v[:, 0].min(), all_v[:, 0].max(), all_v[:, 2].min(), all_v[:, 2].max(), eave_y),
           "dark", "body")
    return md


def church():
    """Collapsed Church decor building (data/rules.json "church"). The source
    file's two material groups don't line up with any useful part split (both
    span the full footprint), so paint the merged shell geometrically instead."""
    parts = load_env(os.path.join(ENV, "church.obj"), height=2.4)
    md = Model("church")
    shell = trimesh.util.concatenate([parts["detail"], parts["walls_roof"]])
    _roof_paint(md, shell, "body", 2.4, roof_frac=0.6)
    return md


def cottage():
    """Small cottage decor building, a shorter neighbour to house()."""
    parts = load_env(os.path.join(ENV, "cottage.obj"), height=1.3)
    md = Model("cottage")
    _roof_paint(md, parts["body"], "body", 1.3, roof_frac=0.55)
    return md


def _canopy_hull(mesh):
    """The source canopy is hundreds of individual disconnected leaf cards;
    decimating that (as for a normal surface) drops whole cards and leaves a
    moth-eaten, gappy silhouette. A convex hull instead gives one solid,
    faceted low-poly crown, in keeping with this project's flat-shaded style
    (see ashmodel.hull(), used the same way throughout procedural.py)."""
    return trimesh.convex.convex_hull(mesh.vertices)


def tree():
    """Generic forest tree: trunk + canopy parts, drawn as two colour-tinted
    MultiMeshes by map_grid.gd's forest scatter (map_grid.gd _build_forest)."""
    parts = load_env(os.path.join(ENV, "tree.obj"), height=2.1)
    md = Model("tree")
    md.add(parts["trunk"], "body", md.part("trunk", (0, 0, 0)))
    md.add(_canopy_hull(parts["canopy"]), "body", md.part("canopy", (0, 0, 0)))
    return md


def mapletree():
    """Ornamental specimen maple, placed individually like blossom_tree
    rather than mass-scattered (its source keeps more branch detail)."""
    parts = load_env(os.path.join(ENV, "mapletree.obj"), height=2.6)
    md = Model("mapletree")
    md.add(parts["trunk"], "dark", "body")
    md.add(_canopy_hull(parts["canopy"]), "foliage", "body")
    return md


MODELS = {
    "harvester": harvester,
    "walker": walker,
    "scout_mech": scout_mech,
    "house": house,
    "church": church,
    "cottage": cottage,
    "tree": tree,
    "mapletree": mapletree,
}
MODELS.update(procedural.MODELS)


def main(names):
    os.makedirs(OUT, exist_ok=True)
    for name in names or MODELS:
        md = MODELS[name]()
        md.write(os.path.join(OUT, name + ".amdl"))


if __name__ == "__main__":
    main(sys.argv[1:])
