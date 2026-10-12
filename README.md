# Collider (working title)

Linear boomer shooter, Godot 4.5 (Compatibility renderer).

## Grid kit rules
- Cell = 2m x 4m x 2m. GridMap `cell_size = (2,4,2)`, `cell_center_y = false`.
- Every piece lives strictly inside its cell.
- Walls are single-sided profile pieces: gutter grating -> kick -> face -> chamfer.
  The face sits 0.75m back from the room-side edge; the profile lands on floor and
  ceiling height at the edge, so it meets any floor cell. Hidden faces are never drawn.
- Wall pieces exist for every combination of open sides + inside corners
  (`wall`, `wall_corner_in`, `wall_corner_out`, `wall_auto_<sides>_<corners>`).
  The ASCII builder picks the right one and rotation automatically.
- Feature walls (light, vent, console, lamp, pipes, window, hazard, cables, rust,
  bulkhead) are straight pieces facing +Z.
- Rooms are separated by at least one wall cell; wall cells with no open neighbour
  are left empty.
- Floor cells carry their own floor + ceiling. Doors sit in the wall line.
- Light/door cells get real lights/doors via the Level "Bake" button.

## Pipeline
    tools/rebuild_and_shoot.sh [level]   # textures -> kit -> level -> screenshots
- `tools/gen_textures.py`  procedural seamless 64px tile atlas + emission atlas
- `tools/build_kit.gd`     builds `kit/kit.meshlib.res` (20 pieces)
- `tools/build_level.gd`   ASCII map (`levels/*.txt`) -> GridMap scene
- Capture: run a level with `-- --capture` to render every Marker3D in group `shots`.

## ASCII legend
Walls: `#` wall `C` bulkhead `O` window `H` hazard `W` cables `U` rust `L` light `V` vent `K` console `R` red lamp `P` pipes
Floors: `.` concrete `,` metal `=` grate `_` yellow line `*` ceiling light `-` beam `o` pillar `x` crate `X` crate stack `D` door (two side-by-side `DD` = sliding double door) `@` player start

Layout rule of thumb: corridors at least 2 cells (4m) wide; glowing grate is an accent, not a floor.

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
