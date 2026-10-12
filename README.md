# Collider (working title)

Linear boomer shooter, Godot 4.5 (Compatibility renderer).

## Grid kit rules
- Cell = 2m x 4m x 2m. GridMap `cell_size = (2,4,2)`, `cell_center_y = false`.
- Every piece lives strictly inside its cell. Walls are solid blocks; detail is cut
  *into* them (recesses), never stuck out, so neighbours never overlap.
- Wall features (light, vent, console, lamp, pipes, hazard, cables, rust) sit on the
  +Z face. Rotate the cell to aim them at the room.
- Floor cells carry their own floor + ceiling.
- Ship trims (angled wall/ceiling chamfers, kick plates, corner caps) are generated
  automatically from the grid by `scripts/level.gd` — never painted.
- Light/door cells become real lights/doors at runtime (`scripts/level.gd`).

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
- Level trims/lights/doors are baked into the scene (Level inspector button "Bake"),
  nothing is generated at runtime.

## Dev tooling
- `-- --capture`  screenshot every Marker3D in group "shots"
- `-- --playtest` bot plays the level (walk in, aim, fire), captures key moments to shots/play_*.png + play_log.txt
- `-- --vmcheck`  fire once and capture the viewmodel frames
- `python3 tools/gen_sprites.py` regenerates enemy sprite sheets
