# Collider (working title)

Linear boomer shooter, Godot 4.5 (Compatibility renderer).

## Grid kit: three GridMaps on one grid
| Grid | Cell | Library | Holds |
|---|---|---|---|
| `Grid` (structure) | 2x4x2 | kit/structure.meshlib.res | wall faces, floors, doors |
| `Trim` | 2x2x2 | kit/trim.meshlib.res | slot y=0: floor trim (gutter, gutter_glow) · slot y=1: ceiling trim (chamfer, chamfer_light, chamfer_light_broken) |
| `Props` | 2x4x2 | kit/props.meshlib.res | runs that tile: tray (end/straight/corner/T/cross), pipes_vertical, beam, beam_cross, pillar |

- Every piece lives strictly inside its cell.
- Wall faces sit 0.75m back from the room-side cell edge (local z = +0.25). The trim
  profile (gutter -> kick, chamfer) lands on floor/ceiling height at the edge.
  Without trim a wall still closes with a hard 90 degree edge.
- Wall and trim pieces exist for every combination of open sides + inside corners:
  `<name>`, `<name>_corner_in`, `<name>_corner_out`, `<name>_auto_<sides>_<corners>`.
  Lit/broken chamfers and feature walls are straight-only.
- Rooms are separated by at least one wall cell; wall cells with no open neighbour stay empty.
- Crates and other one-off clutter are free-placed scenes (scenes/props/).
- Lights and doors become real nodes via the Level "Bake" button.

## Pipeline
    tools/rebuild_and_shoot.sh [level]   # textures -> kit -> level -> screenshots
- `tools/gen_textures.py`  procedural seamless 64px tile atlas + emission atlas
- `tools/build_kit.gd`     builds `kit/kit.meshlib.res` (20 pieces)
- `tools/build_level.gd`   ASCII map (`levels/*.txt`) -> GridMap scene
- Capture: run a level with `-- --capture` to render every Marker3D in group `shots`.

## ASCII legend
See the header of `tools/build_level.gd`. Walls `#` plain, `!` lit chamfer, `?` broken
light, `%` glowing gutter, features `C H W U L V K R P O`; floors `. , = _ *`;
props `o - + t p`; clutter `x X`; `D` door, `@` start, `e` Drifter, `s` Skitter,
`h` health, `a` cells, `E` exit. After the map: `[damage]` zones (dim/flickering
lights, patchy trim) and `[shots]` screenshot markers.

## Levels
- `levels/wing01` — Collider control wing (main scene). Arrival bay -> control room ->
  cargo bay -> damaged corridor -> pipe gallery -> airlock -> breach chamber (exit).
  23 anomalies; bot clears it in ~55s at 80 hull.

## Gameplay (vertical slice core)
- Controls: WASD move, mouse look, LMB fire, F flashlight, Esc release mouse.
- `Player` (scenes/actors/player.tscn) — reads `PlayerInput` intent only; damage via `take_hit()`.
- `Weapon` + `WeaponData` (data/scattergun.tres) — hitscan pellets, tracers, impact FX.
- `Enemy` + `EnemyData` — flat billboard sprites (art/sprites); `take_hit()` chokepoint.
  - Drifter (data/drifter.tres): flies, keeps range, fires slow orbs.
  - Skitter (data/skitter.tres): ground pack melee, lunges, alerts nearby allies.
  - Out of sight, enemies follow the Level's grid flow field (round corners, through doors).
- Pickups: health +25, cells +15 (scenes/props/pickup_*.tscn). Exit: scenes/props/exit.tscn.
- Level map chars: `@` player start, `e` Drifter spawn.
- Lights/doors are baked into the scene (Level inspector button "Bake"),
  nothing is generated at runtime.

## Dev tooling
- `-- --capture`  screenshot every Marker3D in group "shots"
- `-- --playtest` bot plays the level (walk in, aim, fire), captures key moments to shots/play_*.png + play_log.txt
- `-- --vmcheck`  fire once and capture the viewmodel frames
- `-- --topdown`  orthographic plan of the level from straight above -> shots/<level>_topdown.png
- `-- --flashcheck` every shot marker with the flashlight off and on
- `python3 tools/gen_sprites.py` regenerates enemy sprite sheets
