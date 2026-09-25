# Environment art sources

Multi-object, Y-up OBJ files loaded by `build_models.py` (via `ashmodel.load_env`)
to build `models/house.amdl`, `church.amdl`, `cottage.amdl`, `tree.amdl` and
`mapletree.amdl`. Each `o <name>` object in a file becomes one named part/slot
in the built model (see the functions in `build_models.py`). `load_env` also
runs `trimesh.repair.fix_normals` on every part: these are converted assets
built from many small, independently authored pieces, and a piece with
inward-facing winding turns invisible from outside once Godot backface-culls
it.

Converted from found FBX assets (a church, a cottage, a farmhouse, a tree and
a maple tree pack) and pruned to a poly budget comparable to this project's
other decor structures:

- `church.obj`, `tree.obj`: exported from the source FBX with
  `assimp export <src>.fbx <name>.obj`, then decimated per part with
  `trimesh.Trimesh.simplify_quadric_decimation`.
- `cottage.obj`: exported with `assimp export` but kept at its original
  4281 tris, *not* decimated. It's ~500 small disjoint (unwelded) boards and
  panels rather than one connected surface, and quadric decimation collapses
  whole panels away on meshes like that (confirmed by rendering before/after:
  entire walls turned invisible), leaving a building with gaping holes.
- `house.obj`: the source FBX was an old (FBX 6.1, Blender 2.70) ASCII file
  that neither `trimesh` nor `assimp` can read. Its per-part `Vertices` /
  `PolygonVertexIndex` blocks and `Lcl Translation/Rotation/Scaling` were
  parsed directly and fan-triangulated, then decimated the same way as
  church/tree (this source's parts stayed properly connected, so decimation
  is safe here). Its part names (`roof`, `windows`, `door`,
  `lamp_exterior`...) come straight from the source file and drive the slot
  painting in `build_models.py`'s `house()`.
- `mapletree.obj`: its trunk is a many-hundred-piece branch network that
  quadric decimation can't collapse (each twig is its own disconnected
  segment); it's pruned instead by dropping the thinnest branches and keeping
  the largest (thickest, nearest-the-trunk) components up to a face budget.

Before touching the decimation budget for any of these again, render before
and after (e.g. with `trimesh`/`pyrender` offscreen, or just load it in
Godot) rather than trusting the triangle count alone — a mesh can lose most
of its visible surface while "successfully" hitting its target count.

Re-running the conversion (e.g. to swap in a different asset) doesn't need
either tool at build time: only `build_models.py`'s existing dependencies
(`trimesh`, `numpy`) are needed to load these already-converted `.obj` files.
