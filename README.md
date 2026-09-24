# Ashfall: Milestone 1 prototype (Godot 4.7)

This is the pre-production prototype from the design doc: **harvest, build and fight on one map**.
You play the Bastion Coalition against a Veil AI. The world is built in code; unit and building
models are small `.amdl` files in `models/`, loaded at runtime, so there is nothing to import.

## Run it
1. Open Godot 4.7 (4.3 or newer should also work) and choose **Import**, then select `project.godot`.
2. Press **F5**. The main scene is `scenes/main.tscn`.

Each match generates a new, mirrored map: one crystal field at each base, forward and flank
fields (the flank fields have a blossom tree), and a contested blue field in the centre.

## What's in M1
| Area | Implemented |
|---|---|
| Economy | Crystal fields regrow, spread slowly and get seeded by blossom trees. Blue crystal is worth about 2×. Harvesters loop between field and refinery on their own and run home when shot. Building a Refinery gives you a free Harvester. |
| Base building | RA2-style sidebar with Base, Defense, Infantry and Vehicles tabs. You pay as it builds. A finished structure waits as READY until you place it. Buildings must go within 4 cells of your base. Power and low power apply (low power halves build speed and defense fire rate). You can sell and repair. |
| Tech tree | Construction Yard → Power Plant → Refinery / Barracks → War Factory, plus the Guard Tower. Prerequisites are shown in the tooltips. |
| Units | Shared: Rifleman, Rocket Trooper, Harvester. Bastion: Pathfinder Mech (scout) and Warden Walker (heavy). Veil: Raider Buggy and Scorpion Tank. |
| Combat | Armor × warhead table (bullet, rocket, cannon against infantry, light, heavy and structure), with the counter chart in each cameo tooltip. Projectiles home in on targets. Idle units acquire targets and retaliate on a leash. Attack-move works. Veterancy has 3 ranks (Veteran, Elite) with HP, damage and rate-of-fire bonuses and chevrons on the health bar. |
| Controls | Box and click select, double-click to select all of a type, control groups, rally points, stop, attack-move, formation spread on move. |
| Camera | Pan with the arrows, screen edge or middle-mouse drag. Zoom with the wheel. Q/E rotate between 4 fixed angles. Click the minimap to jump there, and right-click it to move units. |
| AI | Follows a build order, keeps power up, rebuilds its core structures, replaces harvesters, defends its base and attacks in waves that grow over time. |
| Win/Lose | A side loses when it has no structures and no units left. |

## Controls
| Input | Action |
|---|---|
| LMB / drag | Select / box select (Shift adds) |
| RMB | Move, attack, harvest (harvester on crystal), dock (harvester on refinery), set rally point (factory selected) |
| A then LMB | Attack-move |
| S | Stop |
| Ctrl+1..9 / 1..9 | Set / recall a group (tap twice to jump the camera) |
| H / Space | Jump to home base / to the last alert |
| P / F1 / Esc | Pause / toggle help / cancel mode or deselect |
| M / N | Mute music / skip to next track |
| Sidebar LMB / RMB | Queue or place / cancel with a refund |

## Music
`music/` holds the game's soundtrack. `scripts/music.gd` (autoload "Music") scans that folder on
startup and shuffles through every `.mp3`, `.ogg` and `.wav` file it finds, looping forever. **To
add a track, just drop the audio file into `music/`** -- nothing else to wire up. Press `M` in-game
to mute/unmute and `N` to skip to the next track.

## Project layout
```
data/rules.json        all balance data (units, weapons, warheads, crystal, economy)
music/                  soundtrack -- drop .mp3/.ogg/.wav files here to add more
scripts/g.gd           autoload "G": rules, players, entity registry, spawning, placement
scripts/music.gd       autoload "Music": scans music/ and shuffle-plays the soundtrack
scripts/map_grid.gd    map generation, AStarGrid2D pathing, crystal growth, ground and crystal visuals
scripts/entity.gd      shared health, armor, weapon and veterancy
scripts/unit.gd        movement and orders;  harvester.gd  harvest state machine
scripts/structure.gd   footprint, power, defense turret, repair and sell
scripts/player_state.gd credits, power, production queues
scripts/ai_controller.gd skirmish AI
scripts/input_controller.gd selection and orders;  rts_camera.gd  camera
scripts/hud.gd, overlay.gd, minimap.gd  UI
scripts/mesh_factory.gd loads models/*.amdl, maps material slots to faction palette / team colour
models/*.amdl          generated models (see "Art" below)
tools/models/          model pipeline: STL sources, procedural models, preview renderer
scripts/fx.gd, projectile.gd  effects
```
**Tweaking balance:** edit `data/rules.json`. To add a unit, add an entry that references a `model`
key (a file in `models/`). It shows up in the sidebar automatically.

**Exporting:** the presets already export `*.json` and `*.amdl` as non-resource files. If you make a
new preset, add both to *Export → Resources → Filters to export non-resource files*.

## Art (Tiberian Sun look)
Models are flat-shaded and faceted like TS voxels, with baked ambient occlusion, a weathered grime
texture, glowing lights and team-colour panels that recolour per player (like TS palette remaps).
Bastion uses GDI khaki-grey with gold trim; the Veil uses Nod gunmetal black with red.

| Model | Source |
|---|---|
| Harvester | `CC2_harvester.STL` (TS GDI harvester), with glowing cargo windows that fill as it harvests |
| Warden Walker | `SK_VH_Titan_Reborn.stl` (GDI Titan), split into legs and a rotating upper body |
| Pathfinder Mech | `SK_VH_Wolverine_Reborn.stl` (GDI Wolverine), split into legs and a rotating upper body |
| Rifleman, Rocket Trooper | procedural: GDI helmeted infantry, or Nod hooded gas-mask troops for the Veil |
| Raider Buggy, Scorpion Tank | procedural: Nod attack buggy, Nod tick-tank-style light tank |
| Buildings | procedural, one GDI-style and one Nod-style (`*_veil`) version each. The Veil barracks is a Hand of Nod-style temple |
| Terrain props | procedural tiberium crystal clusters, faceted boulders, blossom tree |

**Terrain and mood** (`scripts/map_grid.gd`, `shaders/`, `main.gd`): a heightmap with rolling hills, flattened
base plateaus and rock cells that rise into streaked cliffs. `terrain.gdshader` paints ochre dirt, dark scrub
patches, dust flats with cracks, cliff rock and tiberium-stained soil. `tiberium.gdshader` gives the crystals
glowing tips, a fresnel rim and a slow pulse. Lighting is a low amber dusk sun with a cold fill, dusty haze,
filmic grading, drifting ash and embers, and a vignette.

Rebuild after editing `tools/models/procedural.py` or `build_models.py`:
```
pip install -r tools/models/requirements.txt
python3 tools/models/build_models.py              # or: ... build_models.py walker tank
xvfb-run godot --rendering-driver opengl3 --path . --script tools/models/preview.gd -- sheet.png
```
To add a model, write a function in `procedural.py` (or an STL import in `build_models.py`) and
reference its name as `model` in `rules.json`. A `<model>_veil` version is picked automatically for
the Veil. Material slots are `body panel dark metal team glow glass lamp red tib concrete hazard`.

## Known limits (deliberately deferred)
- No fog of war or shroud, and no air or naval units yet.
- Height is visual only: units follow hills and cliffs block movement, but there are no high-ground bonuses yet.
- The simulation isn't deterministic yet, so there's no multiplayer. It needs a fixed-point lockstep layer.
- Units only push each other apart (they don't use RVO avoidance). Large blobs can jostle in chokepoints.
- Music only -- no sound effects yet.
- Units have simple procedural animation only (leg swing, turret aim, bobbing); no skeletal rigs.
