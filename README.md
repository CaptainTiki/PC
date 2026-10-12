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
props `o - + t p`; clutter `x X`; `D` door, `@` start, `e` Drifter.

## Gameplay (vertical slice core)
- Controls: WASD move, mouse look, LMB fire, Esc release mouse.
- `Player` (scenes/actors/player.tscn) — reads `PlayerInput` intent only; damage via `take_hit()`.
- `Weapon` + `WeaponData` (data/scattergun.tres) — hitscan pellets, tracers, impact FX.
- `Enemy` + `EnemyData` (data/drifter.tres) — flat billboard sprite (art/sprites), floats,
  keeps range, fires slow `Projectile` orbs; `take_hit()` chokepoint; shard burst on death.
- Level map chars: `@` player start, `e` Drifter spawn.
- Lights/doors are baked into the scene (Level inspector button "Bake"),
  nothing is generated at runtime.

## Dev tooling
- `-- --capture`  screenshot every Marker3D in group "shots"
- `-- --playtest` bot plays the level (walk in, aim, fire), captures key moments to shots/play_*.png + play_log.txt
- `-- --vmcheck`  fire once and capture the viewmodel frames
- `python3 tools/gen_sprites.py` regenerates enemy sprite sheets
