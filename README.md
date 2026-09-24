# Ashfall: Milestone 1 prototype (Godot 4.7)

This is the pre-production prototype from the design doc: **harvest, build and fight on one map**.
You play the Bastion Coalition against a Veil AI. Everything is built in code from primitive meshes,
so there are no assets to import.

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
| Sidebar LMB / RMB | Queue or place / cancel with a refund |

## Project layout
```
data/rules.json        all balance data (units, weapons, warheads, crystal, economy)
scripts/g.gd           autoload "G": rules, players, entity registry, spawning, placement
scripts/map_grid.gd    map generation, AStarGrid2D pathing, crystal growth, ground and crystal visuals
scripts/entity.gd      shared health, armor, weapon and veterancy
scripts/unit.gd        movement and orders;  harvester.gd  harvest state machine
scripts/structure.gd   footprint, power, defense turret, repair and sell
scripts/player_state.gd credits, power, production queues
scripts/ai_controller.gd skirmish AI
scripts/input_controller.gd selection and orders;  rts_camera.gd  camera
scripts/hud.gd, overlay.gd, minimap.gd  UI
scripts/mesh_factory.gd placeholder models (swap for real art using the same metadata contract)
scripts/fx.gd, projectile.gd  effects
```
**Tweaking balance:** edit `data/rules.json`. To add a unit, add an entry that references a `model`
key from `mesh_factory.gd`. It shows up in the sidebar automatically.

**Exporting:** add `*.json` to *Export → Resources → Filters to export non-resource files*,
otherwise `rules.json` is left out of the build.

## Known limits (deliberately deferred)
- No fog of war or shroud, and no air or naval units yet.
- Flat terrain. High-ground bonuses come later.
- The simulation isn't deterministic yet, so there's no multiplayer. It needs a fixed-point lockstep layer.
- Units only push each other apart (they don't use RVO avoidance). Large blobs can jostle in chokepoints.
- No audio yet.
- Placeholder art: every model is built from primitive meshes.
