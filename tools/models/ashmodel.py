"""Tiny modelling kit that writes Ashfall .amdl model files.

Coordinates are Godot's: Y up, the model faces +Z, 1.0 = one map cell.
A model is a set of parts (rigid pieces with a pivot, e.g. a turret or a leg).
Every triangle belongs to a material slot ("body", "team", "glow"...). The game
maps slots to faction/team materials at runtime (see scripts/mesh_factory.gd).

Faces are flat shaded (Tiberian Sun voxel look) and get baked ambient occlusion
in the vertex colour.

.amdl layout:
    b"AMDL" u32 version u32 json_len  json  u32 raw_size  zlib(raw)
    json = {"meta": {...}, "parts": [{"name", "parent", "pivot", "surfaces":
            [{"slot", "count", "offset"}]}]}
    raw  = for each surface: positions f32[3n], normals f32[3n], colors f32[4n]
"""
import json
import math
import struct
import zlib

import numpy as np
import trimesh

SLOTS = ["body", "panel", "dark", "metal", "team", "glow", "glass", "lamp",
         "tib", "concrete", "hazard", "red"]


# ------------------------------------------------------------------ transforms
def rot_matrix(rot):
    """rot = (rx, ry, rz) in degrees, applied X then Y then Z."""
    rx, ry, rz = [math.radians(a) for a in rot]
    m = trimesh.transformations.euler_matrix(rx, ry, rz, "sxyz")
    return m


def place(mesh, at=(0, 0, 0), rot=None, scale=None):
    mesh = mesh.copy()
    if scale is not None:
        mesh.apply_scale(scale)
    if rot is not None:
        mesh.apply_transform(rot_matrix(rot))
    mesh.apply_translation(at)
    return mesh


# ------------------------------------------------------------------ primitives
def box(size, at=(0, 0, 0), rot=None, bevel=0.0):
    sx, sy, sz = size
    if bevel <= 0.0:
        m = trimesh.creation.box(extents=(sx, sy, sz))
    else:
        b = min(bevel, sx * 0.45, sy * 0.45, sz * 0.45)
        pts = []
        for x in (-1, 1):
            for y in (-1, 1):
                for z in (-1, 1):
                    hx, hy, hz = sx / 2, sy / 2, sz / 2
                    pts += [(x * (hx - b), y * hy, z * (hz - b)),
                            (x * hx, y * (hy - b), z * (hz - b)),
                            (x * (hx - b), y * (hy - b), z * hz)]
        m = trimesh.convex.convex_hull(np.array(pts))
    return place(m, at, rot)


def hull(points, at=(0, 0, 0), rot=None):
    return place(trimesh.convex.convex_hull(np.array(points, dtype=float)), at, rot)


def taper_box(bottom, top, height, at=(0, 0, 0), rot=None, top_offset=(0, 0)):
    """Box whose bottom is bottom=(sx, sz) and top is top=(sx, sz)."""
    bx, bz = bottom[0] / 2, bottom[1] / 2
    tx, tz = top[0] / 2, top[1] / 2
    ox, oz = top_offset
    pts = [(x * bx, 0, z * bz) for x in (-1, 1) for z in (-1, 1)]
    pts += [(x * tx + ox, height, z * tz + oz) for x in (-1, 1) for z in (-1, 1)]
    return hull(pts, at, rot)


def cyl(r, h, at=(0, 0, 0), axis="y", seg=12, r2=None, rot=None):
    """Cylinder/frustum centred on `at`. r = bottom radius, r2 = top radius."""
    r2 = r if r2 is None else r2
    pts = []
    for i in range(seg):
        a = 2 * math.pi * (i + 0.5) / seg
        c, s = math.cos(a), math.sin(a)
        pts.append((c * r, -h / 2, s * r))
        pts.append((c * r2, h / 2, s * r2))
    m = trimesh.convex.convex_hull(np.array(pts))
    if axis == "x":
        m.apply_transform(rot_matrix((0, 0, -90)))
    elif axis == "z":
        m.apply_transform(rot_matrix((90, 0, 0)))
    return place(m, at, rot)


def sphere(r, at=(0, 0, 0), sub=1, scale=None):
    m = trimesh.creation.icosphere(subdivisions=sub, radius=r)
    return place(m, at, scale=scale)


def extrude_profile(profile, width, at=(0, 0, 0), rot=None):
    """Extrude a 2D side profile given as (z, y) points along X (centred)."""
    from shapely.geometry import Polygon
    poly = Polygon([(p[0], p[1]) for p in profile])
    if not poly.exterior.is_ccw:
        poly = Polygon(list(poly.exterior.coords)[::-1])
    m = trimesh.creation.extrude_polygon(poly, width)
    # polygon (u, v) -> (z, y), extrusion w -> x
    t = np.array([[0, 0, 1, -width / 2],
                  [0, 1, 0, 0],
                  [1, 0, 0, 0],
                  [0, 0, 0, 1]], dtype=float)
    m.apply_transform(t)
    if m.volume < 0:
        m.invert()
    return place(m, at, rot)


def extrude_plan(outline, height, at=(0, 0, 0), rot=None):
    """Extrude a floor plan given as (x, z) points upward by `height`."""
    from shapely.geometry import Polygon
    poly = Polygon([(p[0], p[1]) for p in outline])
    m = trimesh.creation.extrude_polygon(poly, height)
    # (u, v, w) -> (x, w, v): maps v to z, w to y
    t = np.array([[1, 0, 0, 0],
                  [0, 0, 1, 0],
                  [0, 1, 0, 0],
                  [0, 0, 0, 1]], dtype=float)
    m.apply_transform(t)
    if m.volume < 0:
        m.invert()
    return place(m, at, rot)


def ngon_prism(r, h, sides, at=(0, 0, 0), r2=None, rot=None, phase=0.5):
    r2 = r if r2 is None else r2
    pts = []
    for i in range(sides):
        a = 2 * math.pi * (i + phase) / sides
        pts.append((math.cos(a) * r, 0, math.sin(a) * r))
        pts.append((math.cos(a) * r2, h, math.sin(a) * r2))
    return hull(pts, at, rot)


# ------------------------------------------------------------------ model
class Model:
    def __init__(self, name):
        self.name = name
        self.parts = {"body": {"parent": None, "pivot": (0.0, 0.0, 0.0), "meshes": []}}
        self.order = ["body"]
        self.meta = {}

    def part(self, name, pivot, parent="body"):
        self.parts[name] = {"parent": parent, "pivot": tuple(float(v) for v in pivot), "meshes": []}
        self.order.append(name)
        return name

    def add(self, mesh, slot="body", part="body"):
        assert slot in SLOTS, slot
        if isinstance(mesh, (list, tuple)):
            for m in mesh:
                self.add(m, slot, part)
            return
        self.parts[part]["meshes"].append((mesh, slot))

    def mirror_add(self, mesh, slot="body", part="body"):
        """Add mesh and its mirror across the X=0 plane."""
        self.add(mesh, slot, part)
        mm = mesh.copy()
        mm.apply_transform(np.diag([-1.0, 1, 1, 1]))
        mm.invert()
        self.add(mm, slot, part)

    # ---------------------------------------------------------- baking
    def bounds(self):
        vs = [m.vertices for p in self.parts.values() for m, _ in p["meshes"]]
        v = np.concatenate(vs)
        return v.min(0), v.max(0)

    def _all_triangles(self):
        tris, owners = [], []
        for pname in self.order:
            for i, (m, slot) in enumerate(self.parts[pname]["meshes"]):
                tris.append(m.triangles)
                owners += [(pname, i)] * len(m.faces)
        return np.concatenate(tris), owners

    def bake_ao(self, rays=32, reach=None, strength=0.75, ground=True):
        tris, owners = self._all_triangles()
        mn, mx = self.bounds()
        size = float(np.max(mx - mn))
        reach = reach if reach is not None else max(0.25, size * 0.35)
        verts = tris.reshape(-1, 3)
        faces = np.arange(len(verts)).reshape(-1, 3)
        scene = trimesh.Trimesh(verts, faces, process=False)
        normals = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
        ln = np.linalg.norm(normals, axis=1)
        ln[ln == 0] = 1
        normals /= ln[:, None]
        centers = tris.mean(1)
        rng = np.random.default_rng(7)
        n = len(tris)
        # cosine-weighted hemisphere directions around each normal
        u1 = rng.random((n, rays))
        u2 = rng.random((n, rays))
        r = np.sqrt(u1)
        th = 2 * np.pi * u2
        local = np.stack([r * np.cos(th), r * np.sin(th), np.sqrt(1 - u1)], -1)
        # build tangent frames
        up = np.where(np.abs(normals[:, 1:2]) < 0.9, [[0, 1, 0]], [[1, 0, 0]])
        t1 = np.cross(up, normals)
        t1 /= np.linalg.norm(t1, axis=1)[:, None]
        t2 = np.cross(normals, t1)
        dirs = (local[..., 0:1] * t1[:, None] + local[..., 1:2] * t2[:, None]
                + local[..., 2:3] * normals[:, None])
        origins = np.repeat(centers + normals * 1e-3 * max(size, 1.0), rays, 0)
        d = dirs.reshape(-1, 3)
        hit = np.zeros(len(d), dtype=bool)
        try:
            locs, idx_ray, _ = scene.ray.intersects_location(origins, d, multiple_hits=False)
            if len(idx_ray):
                dist = np.linalg.norm(locs - origins[idx_ray], axis=1)
                close = dist < reach
                hit[idx_ray[close]] = True
        except Exception as e:  # pragma: no cover
            print("  AO ray cast failed:", e)
        if ground:
            with np.errstate(divide="ignore", invalid="ignore"):
                tg = -origins[:, 1] / d[:, 1]
            hit |= (d[:, 1] < 0) & (tg < reach) & (tg > 0)
        occl = hit.reshape(n, rays).mean(1)
        ao = 1.0 - strength * occl
        # store per mesh
        k = 0
        self._ao = {}
        for pname in self.order:
            for i, (m, _) in enumerate(self.parts[pname]["meshes"]):
                self._ao[(pname, i)] = ao[k:k + len(m.faces)]
                k += len(m.faces)

    def write(self, path, ao=True, **ao_kw):
        if ao:
            self.bake_ao(**ao_kw)
        parts_json = []
        raw = bytearray()
        abs_pivot = {}
        for pname in self.order:
            abs_pivot[pname] = np.array(self.parts[pname]["pivot"])
        for pname in self.order:
            p = self.parts[pname]
            parent = p["parent"]
            local_pivot = abs_pivot[pname] - (abs_pivot[parent] if parent else 0)
            by_slot = {}
            for i, (m, slot) in enumerate(p["meshes"]):
                t = m.triangles - abs_pivot[pname]
                nrm = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
                ln = np.linalg.norm(nrm, axis=1)
                keep = ln > 1e-12
                t, nrm, ln = t[keep], nrm[keep], ln[keep]
                nrm /= ln[:, None]
                a = self._ao[(pname, i)][keep] if ao else np.ones(len(t))
                by_slot.setdefault(slot, []).append((t, nrm, a))
            surfaces = []
            for slot in SLOTS:
                if slot not in by_slot:
                    continue
                t = np.concatenate([x[0] for x in by_slot[slot]])
                nrm = np.concatenate([x[1] for x in by_slot[slot]])
                a = np.concatenate([x[2] for x in by_slot[slot]])
                # Godot's front faces are clockwise: flip our CCW winding
                t = t[:, [0, 2, 1]]
                pos = t.reshape(-1, 3).astype(np.float32)
                nv = np.repeat(nrm, 3, 0).astype(np.float32)
                av = np.repeat(a, 3).astype(np.float32)
                col = np.stack([av, av, av, np.ones_like(av)], 1).astype(np.float32)
                surfaces.append({"slot": slot, "count": int(len(pos)), "offset": len(raw)})
                raw += pos.tobytes() + nv.tobytes() + col.tobytes()
            parts_json.append({"name": pname, "parent": parent,
                               "pivot": [round(float(v), 5) for v in local_pivot],
                               "surfaces": surfaces})
        mn, mx = self.bounds()
        meta = dict(self.meta)
        meta.setdefault("aabb", [[round(float(v), 4) for v in mn], [round(float(v), 4) for v in mx]])
        js = json.dumps({"meta": meta, "parts": parts_json}, separators=(",", ":")).encode()
        blob = zlib.compress(bytes(raw), 9)
        with open(path, "wb") as f:
            f.write(b"AMDL" + struct.pack("<II", 1, len(js)) + js + struct.pack("<I", len(raw)) + blob)
        ntri = sum(s["count"] for pj in parts_json for s in pj["surfaces"]) // 3
        print(f"  {self.name}: {ntri} tris, {len(blob) // 1024} KB -> {path}")


# ------------------------------------------------------------------ STL import
def load_stl(path, forward, height=None, length=None, width=None, drop=None):
    """Load a Z-up STL and convert it to Godot space, facing +Z.

    forward: STL axis the model faces, e.g. "+x" or "-y".
    Scale so the model is `height` tall, or `length` long (along forward),
    or `width` wide. Returns a trimesh with its lowest point on y=0, centred in XZ.
    """
    m = trimesh.load(path, process=False)
    m.merge_vertices()
    if drop:
        m = drop(m)
    ax = {"x": 0, "y": 1, "z": 2}[forward[1]]
    f = np.zeros(3)
    f[ax] = 1.0 if forward[0] == "+" else -1.0
    up = np.array([0.0, 0.0, 1.0])
    left = np.cross(up, f)
    rot = np.eye(4)
    rot[0, :3] = left
    rot[1, :3] = up
    rot[2, :3] = f
    m.apply_transform(rot)
    mn, mx = m.bounds
    ext = mx - mn
    if height:
        s = height / ext[1]
    elif length:
        s = length / ext[2]
    else:
        s = width / ext[0]
    m.apply_scale(s)
    mn, mx = m.bounds
    m.apply_translation([-(mn[0] + mx[0]) / 2, -mn[1], -(mn[2] + mx[2]) / 2])
    return m


def split_components(mesh):
    return mesh.split(only_watertight=False)


def submesh(mesh, face_mask):
    idx = np.nonzero(face_mask)[0]
    if len(idx) == 0:
        return None
    return mesh.submesh([idx], append=True, repair=False)
