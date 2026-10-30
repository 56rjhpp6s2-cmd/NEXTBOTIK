# BELOW / ZERO

A first-person Nextbots horror-action game for Windows, built in Godot 4.5+ with GDScript. Choose **Arcade**, **Endless**, **PNG Mayhem**, **Sandbox** or **Bossfight**, then enter an abandoned underground complex, a gm_construct-style outdoor arena, or Bossfight's dedicated desert district. Endless retains the objective-driven descent and generates a new modular labyrinth from Level 4 onward. Sandbox includes manual spawning plus configurable automatic spawning, batch size, interval and active-enemy limit.

You can fight back by throwing PNG images. Import your own transparent PNGs during a run, switch images with the mouse wheel, aim, and defeat enemies with five standard hits. Both maps retain their movement, chases, objectives, jumpscare and respawn systems.

Cooperative multiplayer supports up to eight players over LAN or Radmin VPN in **Endless and Bossfight**. Select the mode first, then choose **СЕТЬ / RADMIN VPN**: one player hosts and friends join using the host's VPN IP and the same UDP port (default **24577**). See [MULTIPLAYER.md](MULTIPLAYER.md) for Russian setup instructions, shared objectives, individual respawns and network testing.

## Play

Open `project.godot` in your installed Godot 4.5 or newer and press **F5**. Stop an already running game with **F8** before restarting to load new scripts. The renderer is OpenGL Compatibility for broad Windows hardware support. No Python packages are needed to play.

`PLAY.cmd` and `EDITOR.cmd` use the portable Godot executable in `tools/engine` or an installation on PATH. The launcher imports resources before starting and never downloads anything. An optional `GODOT_ENGINE` environment variable can select another installed executable.

To send the game to a friend, use **`build/BELOW_ZERO_Friends.zip`**. It contains the game pack, all bundled Nextbot, Bossfight and Reward Keeper photos, the selected PNG, a portable engine and Russian instructions. Extract the entire archive and run **`BELOW_ZERO/PLAY.cmd`**; no editor installation is needed. Both players should use the same archive. Run **`PACKAGE.cmd`** to rebuild it after changing the project.

Three bundled Nextbot appearances rotate during encounters: the original `assets/nextbot_face.jpg`, `assets/nextbot_faces/elena_finkelshteyn.jpg`, and `assets/nextbot_faces/5402324111498878359.jpg`. Each enemy uses its own photograph for the jumpscare, including over multiplayer.

**`CLEAN_PROJECT.cmd`** removes old download archives, generated test files/logs/captures and temporary package checks. It keeps source, game assets, the working engine, editor import cache and the current friend archive. The unrelated terminal snake files are archived under `extras` before removing their loose copies. Close game/tests/build processes first. Preview with `powershell -NoProfile -File tools/Clean-Project.ps1 -WhatIf`.

The supplied face is detected at `assets/nextbot_face.jpg` and used by both maps and the jumpscare. PNG/WebP/BMP/SVG are also supported. See [assets/README.md](assets/README.md).

## Maps

Use the **КАРТА** selector above **PLAY / ИГРАТЬ** in the main menu, then press Play. The selected map persists between launches. Respawning keeps that map; survival records are separate for each map and difficulty.

- **ПОДЗЕМНЫЙ КОМПЛЕКС**: the original two-floor backrooms, parking, storage and archive complex. Restore the yellow-room, storage and upper pump-control breakers, then reach the north lift.
- **GM CONSTRUCT**: an original recreation inspired by the open grass courtyard, reflecting pool, brick garages, darkroom, white room and accessible rooftop. Two long ramps connect the yard and roof. Restore the darkroom, east-garage and rooftop breakers, then use the control at the south courtyard gate. The shallow pool is walkable for both player and bots. Supplies, lockers and a limited-power refuge are included.

Construct uses original generated geometry and materials; it does not require Garry's Mod or a Source-engine map file. To see newly added menu options in an already running Godot game, stop with **F8** and restart with **F5**.

## Level progression and procedural maps

Levels 1–3 preserve the selected authored map and reset its objectives on each descent. Level 4 replaces it with a deterministic modular labyrinth; every later exit rebuilds a new layout from small rooms, halls, corridors, junctions, offices, classrooms, parking areas, maintenance tunnels, dead ends and rare refuge rooms. Generated layouts are checked for overlap, doorway alignment, graph connectivity and a reachable exit before play resumes. A bounded retry sequence and a guaranteed connected fallback prevent an impossible level.

Default room counts are 15 / 20 / 25 / 30 / 35 on Levels 4–8, then rise more slowly to a 55-room cap. Lighting falls from 0.80x on Level 4 to a playable 0.10x minimum on Level 10+, while functioning lights become rarer, fog and flicker increase and safe lighting remains around the entry, exits and refuges. Nextbot speed uses 1.10x through 1.70x multipliers on Levels 4–10, then approaches a configurable 2.00x ceiling with diminishing returns; the physical chase speed remains capped below the player's practical movement ceiling. Detection, search persistence, repathing and population pressure also rise.

The HUD displays the current level, and the deepest reached level is saved. F3 includes the generation seed, room count, light/speed multipliers, navigation state and validation result. In a debug build, enable F3 and press **F6** to regenerate the current procedural level with a new reproducible seed. Generation and progression tuning lives in `resources/procedural_generation.tres` and is independent from the selected Explorer/Relentless/Nightmare difficulty.

## Bossfight mode

Bossfight uses its own original **Dust Quarter** map: a sun-baked competitive-FPS district with two distinct courtyards, a three-lane middle, supported market stalls, palace and underpass routes, outer rotations, arches and multiple chase loops. A full surrounding skyline now uses grounded buildings with roofs, parapets, doors, windows, balconies and attached signage; street lamps have posts and courtyard props sit on the ground. It is visually inspired by desert Counter-Strike maps without copying Mirage geometry or assets. On each of the first three levels, three switches are selected from ten valid locations; activate all three and reach the Sun Gate. The same authored layout returns with new switch positions on the following level.

Every fourth level loads the separate **Sun Ring**, a large open circular arena with spaced pillars that provide fair cover from the boss's telegraphed charge. The first boss has **4,000 HP**. Each later boss gains **500 HP**, while ordinary Nextbots gain health, speed and population pressure after every victory.

Defeating a boss now starts a mandatory post-boss reward encounter. The photographed **Reward Keeper** appears once with a different data-driven weapon or upgrade above each raised hand. Press **Q for the left reward** or **E for the right reward**; aiming at the item and approaching the NPC are not required. The selected reward is applied immediately and persists for the current run. Only then does a dedicated progression lever appear behind the Keeper. Pulling that lever starts the next three-sector cycle. The normal arena exit stays disabled throughout selection, so the reward cannot be skipped.

The pool includes weighted Common through Legendary projectile, movement, defense and synergy upgrades plus genuinely different PNG Minigun, Meme Howitzer, Spreadshot and charged Chargeposter weapons. Maxed, duplicate and invalid choices are filtered. PNG Mayhem uses the same system after boss waves without creating a progression lever; Sandbox exposes a manual **SPAWN / RESET REWARD KEEPER** test button.

The supplied `assets/bosses/bossfight_idle.jpg` is the boss's normal billboard. During its charge and direct attack it switches to `bossfight_attack.jpg`; that aggressive image is also active when the boss catches the player. Both source photographs are bundled unchanged.

Bossfight is fully cooperative: the host synchronizes the selected mode, level seed, randomized switches and every transition. On Sun Ring levels the host owns boss AI and damage; guests receive the same 4,000 + 500 HP scaling, boss bar and idle/attack photographs. After victory every eligible player votes for the left or right hand during a 20-second server-authoritative vote. Votes can be changed; majority wins, and ties or no votes resolve through authoritative random selection. Everyone receives the same reward, then the shared lever unlocks and performs one synchronized transition. Late join receives the current reward phase, vote state, run modifiers, Bossfight level and seed. All players must use the same current build because this data is part of network protocol 6.

## Controls

| Input | Action |
|---|---|
| WASD / mouse | Move / look |
| Shift | Sprint without a stamina limit |
| Ctrl | Crouch; press during a sprint to slide under obstacles |
| Space | Jump, including out of a slide; optional hold-to-bunny-hop in Settings |
| A / D in the air | Air strafe to carry speed through turns |
| F4 | Show or hide the speedometer |
| F2 | Open or close live Sandbox controls while playing Sandbox |
| Q during reward selection | Immediately choose/vote for the left-hand reward |
| E during reward selection | Immediately choose/vote for the right-hand reward |
| E otherwise | Interact; restore breakers, pull levers, use lifts and gates |
| F | Toggle flashlight |
| Left mouse (hold or click) | Throw selected PNG |
| Right mouse (hold) | Aim |
| R | Reload / refresh PNGs |
| Mouse wheel | Previous / next PNG |
| Tab | Open PNG library; pauses single-player only |
| Escape | Pause / resume |
| F3 | AI states, current navigation paths and performance overlay |
| F6 | Regenerate the current procedural level (debug build with F3 enabled) |

Momentum builds through sprinting, sliding and well-timed jumps. Sliding downhill gains speed, while uphill slides slow down. The movement settings offer hold/toggle crouch and sprint, automatic bunny hopping, adjustable head bob and landing shake, dynamic FOV and camera tilt. The movement parameters are exposed on the player controller for tuning.

## PNG combat and importing

Open the PNG library with **Tab**, then click **Import PNG** and choose an image. It is copied to `user://projectiles/` and selected immediately. The library includes a transparent preview, selection list, size slider and an unlimited-ammunition toggle. It also refreshes the directory automatically every three seconds. You can import from the PNG option in the pause menu too.

The file picker accepts **PNG, JPG and JPEG**. JPEG images are converted to PNG copies automatically; their original files stay unchanged. JPEG backgrounds are retained.

The current **Без имени.png** is also bundled under `assets/projectiles/` and selected on a fresh installation, with a 1.3 m projectile size. Its bytes are preserved. The three original PNGs remain available; a missing bundled copy restores automatically, and selection changes are saved immediately. Images and the enemy face travel with the game pack rather than relying on the creator's Windows profile.

Default throws deal **20 damage**, travel at **35 m/s**, have a **0.3-second cooldown** and a **100-meter maximum range**. Ammunition is unlimited by default. A 100-HP Nextbot dies in five hits; health bars, damage numbers, hitmarkers and kill counts show the result. Dead enemies cannot attack and respawn after ten seconds by default. If unlimited ammunition is disabled, the magazine holds 12 PNGs and R reloads from unlimited reserves.

See [COMBAT.md](COMBAT.md) for image limits, configuration, component APIs and testing.

## Survive

Breakers are in the yellow rooms, storage C and the upper pump control room. The lift is at the north end of the central spine. Printed signs and sector names help you learn the layout. Two stairwells link the levels so a pursuit always has a looping route.

Enemies see along clear sight lines, hear movement and investigate restored breakers. Sprinting is loud; crouching with the flashlight off reduces detection range. After losing you, they search the last known location. A locker gives 12 seconds of concealment, but cannot fool an enemy watching you enter. It requires an eight-second recovery between uses. Refuge rooms protect you for 18 seconds of stored power, then slowly recharge while empty. Neither is permanent shelter.

The first bot enters after nine seconds. More arrive every 55 seconds, up to the difficulty cap. Base pursuit speeds are 9.0, 11.4 and 13.6 m/s on Explorer, Relentless and Nightmare; they increase as a run continues. Flashlight charge lasts approximately four minutes, and scattered batteries restore 45%. All audio, including the jumpscare, respects the volume controls.

Settings include sensitivity, brightness/minimum visibility, separate master/music/SFX volumes, resolution, fullscreen, three graphics levels, three difficulty levels, reduced flashing and movement/camera preferences. Preferences, selected map, deepest level and a best survival record for each map/difficulty persist in Godot's `user://below_zero.cfg` (normally `%APPDATA%/Godot/app_userdata/BELOW - ZERO/`; the exact application folder is chosen by Godot).

## Project structure

- `scripts/main.gd`: run lifecycle, progression, objectives and interaction.
- `scripts/player.gd`, `scripts/movement/` and `camera.gd`: momentum physics, stance, camera and flashlight.
- `scripts/nextbot.gd`: Idle / Wander / Search / Chase / Attack, hearing, visibility and avoidance.
- `scripts/world.gd`, `surface.gd`, `navigation.gd`: authored map plan, shared materials, collision, render batching and connected NavigationMesh.
- `scripts/construct_world.gd`: outdoor Construct map, daylight, grass, pool, garages, darkroom and roof routes, using the shared gameplay and navigation systems.
- `scripts/bossfight_world.gd`: Dust Quarter, randomized switch placement and the circular Sun Ring boss arena.
- `scripts/procedural/`, `scenes/procedural/`: deterministic room placement, reusable room prefabs, procedural world rendering, validation and progression configuration.
- `scripts/interactable.gd`: breakers, batteries, lockers, lifts and the post-reward progression lever.
- `scripts/audio.gd`: generated PCM, spatial effects, audio buses and adaptive chase score.
- `scripts/ui.gd`, `overlay.gdshader`: main menu, settings, HUD, pause, jumpscare and results.
- `scripts/settings.gd`: persistence and Windows display configuration.
- `scripts/combat/`: PNG image loading/import, projectile controller, swept projectile collisions, reusable health/damage, Nextbot reactions and combat HUD/library.
- `scripts/network/`: ENet host/join, server authority, player avatars, interpolated world snapshots, custom PNG exchange and network menu.
- `scripts/gameplay/`: five mode policies, post-boss state machine, reusable reward definitions, local statistics and reversible random events.
- `resources/gameplay_config.tres`: central Arcade, Mayhem, boss and event tuning.

Map geometry and its navigation surfaces are created deterministically from the same tile layout. Stair ramps share edge vertices with the floors. Bot clearance is inset at walls, physical props sit outside navigation clearance, and low player-only shortcuts are excluded from the bot mesh. Static boxes are batched by material in 24-meter chunks to reduce draw calls while preserving frustum culling. Quality settings limit shadows and multisampling.

## Verification

Current engine results and remaining rendering/audio checks are recorded in [tests/VERIFICATION.md](tests/VERIFICATION.md).

Run **TEST.cmd**, or:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . -- --smoke-test
godot --headless --path . -- --map-test
godot --headless --path . -- --combat-test
godot --headless --path . -- --movement-test
godot --headless --path . -- --procedural-test
godot --headless --path . -- --modes-test
godot --headless --path . -- --bossfight-test
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Test-Network.ps1 -Bossfight
```

The engine integration suite checks navigation across both stairwells, reachability of all objectives, collision, movement, mouse look, unlimited sprint, bot detection and pursuit, billboard texture, audio buffers, pause/settings, contact death, jumpscare transition, respawn and victory. It exits nonzero on failure.

The map suite checks both maps, menu selection and persistence, all spawn collisions, objective reachability, physical player and bot traversal onto the Construct roof, courtyard pursuit, gate completion, death text and respawning. The combat suite checks real PNG throws, exact damage, five-hit kills, independent HP, collision at high speed, walls, health bars, delayed respawn, import/selection, transparency, reload, aiming, pause and cleanup. The modes suite checks Arcade timing/score, Endless policy, Mayhem waves/upgrades/bosses, Sandbox controls, every random event, special projectiles and statistics recovery. Automated runs isolate settings and PNG files under `.godot/test_*` so they do not modify your normal preferences, images or records. If restricted filesystem access prevents Godot from opening its usual log, add `--log-file ./tests/engine-test.log`.

The independent static checks need only Python 3:

```powershell
python tests/validate_project.py
```

For a rendered capture: `godot --path . -- --capture-menu`. It writes `tests/captures/menu.png`. Use a regular renderer, not `--headless`.

`godot --path . -- --capture-combat` renders the combat HUD and paused image library to `tests/captures/combat.png` and `tests/captures/png_library.png`.

For a standalone Windows executable, install the matching Godot export templates through **Editor → Manage Export Templates**, create `build`, and use **Project → Export → Windows Desktop → Export Project**. The included preset embeds game resources into `build/BELOW_ZERO.exe`. With templates installed, the equivalent command is `godot --headless --path . --export-release "Windows Desktop" build/BELOW_ZERO.exe`.

## Assets and license

Project code, fallback artwork and synthesized audio are original and distributed under the MIT license in `LICENSE`. Godot is a separate MIT-licensed engine; its license and third-party notices are available from [Godot's license page](https://godotengine.org/license/). Engine binaries are downloaded from the [official Godot release](https://github.com/godotengine/godot-builds/releases/tag/4.5.1-stable). Use an image you have permission to include when replacing the fallback.
