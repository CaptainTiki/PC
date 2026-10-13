# Collider (working title)

Linear boomer shooter, Godot 4.5 (Compatibility renderer).

## Grid kit: three GridMaps on one grid
| Grid | Cell | Library | Holds |
|---|---|---|---|
| `Grid` (structure) | 2x4x2 | kit/structure.meshlib.res | wall faces, floors (+ `_open` no-ceiling variants), void / catwalk, stairs, doors, glass wall, crawl ducts + octagon shafts (auto-joining, with wall mouths) |
| `Trim` | 2x2x2 | kit/trim.meshlib.res | floor slot y=2f: gutter, gutter_glow, band_floor · ceiling slot y=2f+1: chamfer, chamfer_light(_broken/_off), band_ceil |
| `Props` | 2x4x2 | kit/props.meshlib.res | runs that tile: tray, pipes_vertical, beam, beam_cross, pillar · railings (edge masks) · cover · console_desk |

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
- Multi-floor: floor f sits at cell y=f in Grid/Props (4m apart) and y=2f / 2f+1 in Trim.
- Devices are free-placed scenes (scenes/props/): ladder, elevator (+ call_post),
  breaker, explosive (canister), vent_cover. `*_off` pieces are the unpowered twins
  that `Level.power_on()` swaps back to lit.

## Pipeline
    tools/rebuild_and_shoot.sh [level]   # textures -> kit -> level -> screenshots
- `tools/gen_textures.py`  procedural seamless 64px tile atlas + emission atlas
- `tools/build_kit.gd`     builds the three mesh libraries + device meshes
- `tools/build_level.gd`   ASCII map (`levels/*.txt`) -> GridMap scene
- Capture: run a level with `-- --capture` to render every Marker3D in group `shots`.

## ASCII legend
Full legend in the header of `tools/build_level.gd`. Walls `#` plain, `!` lit chamfer,
`?` broken light, `%` glowing gutter, features `C H W U L V K R P O`, `g` glass;
floors `. , = _ *`; air `^` (no floor), `v` (air + ceiling light), `c` catwalk;
`/` stairs, `l` ladder, `Q` elevator; tubes `d` duct (crouch), `m` shaft;
props `o - + t p n j`; clutter `x X b`; `D` door, `k` breaker, `@` start,
`e` Drifter, `s` Skitter, `h` health, `a` cells, `E` exit.

Floor 0 is the map at the top; `[floor 1]`, `[floor 2]`… follow. Sections:
`[stairs] stair c r n|e|s|w [floor]`, `[power] zone c0 r0 c1 r1` (breakers power
zones in reading order), `[damage] zone …`, `[shots] shot name c r yaw pitch [floor]`.
Railings, ceiling removal under open air, duct/shaft mouths, vent covers and
elevator call buttons are all placed automatically.

Doors and switches: `[locks] lock c r f jammed|inside|lockdown|seal` locks a door (both
halves of a double door); `r` (door release, on the nearest wall) and `y` (lockdown
console) are switches, wired with `[links] link c r f to c r f ...`. Locks live in
`Level.door_locks`, so re-baking keeps them; locked doors are walls to the flow field.
`lock c r f oneway n|e|s|w` opens only from that side (then stays open as a shortcut);
`lock c r f keycard [id]` opens once you carry that keycard (`q` places a crew keycard).
Ledges: `w` is a walkway 1.8 m up along a cell's walls (joins round corners), `z` the
same with a crate to jump up from, and `i` a crawl duct whose floor is 1.8 m up, so its
mouth is a vent at ledge height (shoot the cover, crouch in).
Climbing: `u` is a climb cell under a ceiling grate `G` on the floor above (crate, a
ledge 2 m up on the wall, a short ladder through the grate). `G` alone is a hatch with
a shootable grate you can drop through. `~` is open air with no railing (a collapsed
floor you fall through).
Door states: open = cyan lamp, no power = dark, jammed = amber + sparks, locked from the
inside = red, lockdown = magenta pulse, pressure seal = white. Look at a locked door to
see why it's shut.

Room templates: `[rooms] room <template> c r n|e|s|w [floor] [variant]` stamps
`rooms/<template>.txt` with its door `D` on c,r facing that way. Each template has
`[variant]` blocks (rolled per room when not named); `$` rolls loot (health / cells /
nothing) and `&` maybe a skitter, per placed room. Loot ends up as normal nodes, so
it's editable in Godot after the build. Templates: `cabin` (single, double, trashed,
lit), `closet` (shelves, mop).

## Levels
- `levels/wing01` — Collider control wing (main scene). Arrival bay -> control room ->
  cargo bay -> damaged corridor -> pipe gallery -> airlock -> breach chamber (exit).
  23 anomalies; bot clears it in ~50s.
- `levels/deck02` — kit showcase / level 2 draft (two floors). Start room -> corridor
  (or the crawl duct) -> unpowered double-height atrium with catwalks and stairs ->
  control room with a glass wall over the atrium and the breaker -> back down through
  the now-unlocked door -> lower hall -> ladder or elevator to the mezzanine ->
  maintenance shaft -> exit. 20 anomalies; bot clears it in ~70s.

- `levels/deck03` — Habitation ring greybox (three floors, ~70 enemies). Corridor A ->
  command room seen through glass (seal release inside) reached via storeroom A
  (crate -> ledge -> high vent -> hidden riser ladder) and the west maintenance deck
  -> junction (Transit needs the crew keycard) -> Corridor C / commons -> gym locker
  hatch down to the F0 pump/power rooms (breaker) -> storeroom B ladder up and a crawl
  over Corridor B into the room above the security post -> drop in for the keycard and
  the lockdown console -> stairs to the gallery -> Corridor D's collapsed floor drops
  you into Corridor C past the cave-in -> transit lift. Generated from the scratchpad
  `deck03.py`; `--deckcheck` walks all three chains.
- `levels/chain_test` — mini chain (pass 2): command room behind glass with a one-way
  door and the seal release; reached from the storeroom (crate -> ledge -> high vent ->
  crouch duct -> hidden riser ladder), across maintenance above, then down through a
  grate. Keycard door
  past the seal.
- `levels/kit03_test` — door and detour test map (pass 1 of deck03): jammed corridor with
  the duct/riser/ladder detour through maintenance, a security post locked from the
  inside reached by a duct from the rec room, a lockdown shutter, a pressure seal, and
  template cabins/closet.

## Gameplay (vertical slice core)
- Controls: WASD move, mouse look, LMB fire, Space jump, E use, C / Ctrl crouch (hold), F flashlight, Esc release mouse.
- Use: look at a usable thing (anything with `interact()` / `prompt()`) within 2.6m; the HUD shows `[E] prompt`.
- Ladders: push forward to climb, back to descend (or forward while looking down).
- `Player` (scenes/actors/player.tscn) — reads `PlayerInput` intent only; damage via `take_hit()`.
- `Weapon` + `WeaponData` (data/scattergun.tres) — hitscan pellets, tracers, impact FX.
- `Enemy` + `EnemyData` — flat billboard sprites (art/sprites); `take_hit()` chokepoint.
  - Drifter (data/drifter.tres): flies, keeps range, fires slow orbs.
  - Skitter (data/skitter.tres): ground pack melee, lunges, alerts nearby allies.
  - Out of sight, enemies follow the Level's grid flow field (round corners, through
    doors, up and down stairs; they don't use ladders, ducts or elevators). Fliers
    hover above whatever floor is under them.
- Pickups: health +25, cells +15 (scenes/props/pickup_*.tscn). Exit: scenes/props/exit.tscn.
- Level map chars: `@` player start, `e` Drifter spawn.
- Lights/doors are baked into the scene (Level inspector button "Bake"),
  nothing is generated at runtime.

## Dev tooling
- `-- --capture`  screenshot every Marker3D in group "shots"
- `-- --playtest` bot plays the level (walk in, aim, fire), captures key moments to shots/play_*.png + play_log.txt
- `-- --vmcheck`  fire once and capture the viewmodel frames
- `-- --topdown`  orthographic plan from straight above -> shots/<level>_topdown.png (one per floor: `_topdown_f<N>.png`)
- `-- --capture --power` same shots with every power zone switched on (`<level>_pw_*.png`)
- `-- --peek c f r yaw pitch [open] ...` drop the player at grid cells (flashlight on, enemies gone) and capture shots/peek_<n>.png; `open` opens every door for that shot
- `-- --deckcheck` scripted walk of deck03's three chains with teleports between steps (28 checks, shots/deck_*.png)
- `-- --chaincheck` scripted run of the mini chain in chain_test: one-way door, seal, crate jump + ledge ladder through a grate, shaft, grate drop, release, keycard
- `-- --doorcheck` scripted checks in kit03_test: every door state, the switches, and the duct -> riser -> ladder -> maintenance -> closet detour
- `-- --mechcheck` scripted checks in deck02: explosive chain, vent cover + crouch through the duct, ladder, elevator call/ride, breaker
- `-- --flashcheck` every shot marker with the flashlight off and on
- `python3 tools/gen_sprites.py` regenerates enemy sprite sheets
