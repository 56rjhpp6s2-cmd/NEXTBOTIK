# Verification status

## Direct reward hotkeys and applied effects (2026-10-30)

- Reward selection no longer depends on camera aim, ray targeting, proximity or small hand hitboxes: **Q always selects/votes left, E always selects/votes right** while the reward phase is active. The world title, both cards, prompt, vote counts and countdown show the same mapping.
- Reward application now explicitly refreshes movement tuning and the projectile HUD, and re-applies run modifiers after every level transition. The HUD displays the active reward weapon, effective per-projectile damage, projectile count and effective cooldown instead of the unchanged base 20-damage value.
- Bossfight passed **54/54** checks, including actual Q/E input dispatch, exactly-once application, the updated stack display, a real 25-damage projectile after transition, persistent HUD state and a real sprint-speed increase. Combat passed **128/128**, modes/events **76/76**, and two-process Bossfight networking **18/18 host + 22/22 client**.

## Post-boss Reward Keeper (2026-10-29)

- Added the supplied `assets/rewards/reward_keeper.jpg` as an aspect-preserving camera-facing life-sized NPC. The original classroom background is deliberately retained; no transparent cutout is claimed. Configurable left/right palm anchors carry two different rarity-colored reward objects.
- Boss death now enters an explicit seven-state reward/progression machine. Exactly one selection is applied before a collision-validated lever can appear behind the NPC; the old arena exit is suppressed, and both reward and transition calls are idempotent.
- Added 23 data-defined rewards across projectile, new-weapon, movement, defense and special-synergy categories. Weighted Common–Legendary choices filter duplicates and stack caps. Run snapshots preserve active weapon, stacked modifiers and shields across level changes.
- Network protocol **6** adds a 20-second authoritative vote, one changeable ballot per player, majority/tie/no-vote resolution, disconnect cleanup, late-join reward snapshots and one synchronized lever transition. Final loopback results: **18/18 host** and **22/22 client** Bossfight checks; Endless remained **26/26 host** and **42/42 client**.
- Local integration results: **49/49 Bossfight** and **76/76 mode/event** checks. They include both hand paths, real camera targeting, exactly-once application, hidden-before-selection/behind-NPC lever rules, later-cycle persistence, Sandbox manual testing and weapon-profile composition.
- Rendered and inspected `bossfight_reward_selection.png` and `bossfight_reward_lever.png`: the supplied person remains recognizable and undistorted, rewards sit at the raised palms, and the lever is visible behind the NPC only after acquisition.
- The 50-seed procedural regression remains **317/317**, and the project validator passes **17/17** checks. A release Windows export booted cleanly; the freshly extracted friend pack passed **22/22 portable checks**, including the Reward Keeper asset/controller, reward catalog and protocol 6.

## Dust Quarter visual rebuild (2026-10-29)

- Replaced the nearly full open floor and isolated block props with a 305-tile competitive street graph: Amber/Azure courtyards, three-lane mid, market, palace, underpass, outer rotation and connected flanks.
- Added grounded internal and skyline buildings with varied stucco, roofs, parapets, doors, windows, trim, balconies and roof tanks. Market awnings now have four posts; every street/arena lantern has a pole or existing support; signs are wall-mounted or post-mounted.
- Moved decorative planters, cover and barriers away from every possible switch cell. All three deterministic objective sets and the Sun Gate remain navigation-reachable.
- Added aerial and first-person rendered inspection captures: `bossfight_dust_quarter.png` and `bossfight_dust_quarter_street.png`. No unsupported floating props are visible in the final views.
- A Bossfight-specific 36 m batching cell reduced the richer map from 340 initial static batches to **217**; Sun Ring dropped to **72**. Local Bossfight passed **34/34**, map regression **47/47**, and two-process Bossfight networking **12/12 host + 19/19 client**.
- Re-exported and headlessly booted `build/BELOW_ZERO.exe` (101,267,608 bytes), rebuilt `build/BELOW_ZERO_Friends.zip` (81,302,575 bytes), and passed **20/20** checks against a freshly extracted portable pack.

## Bossfight mode and dedicated maps (2026-10-28)

- Added Bossfight as the fifth mode, now playable locally and in authoritative ENet co-op. Levels 1–3 use the original Dust Quarter desert-FPS layout and deterministically reroll three switches from ten validated locations; Level 4 uses the separate 333-tile open Sun Ring. The cycle repeats indefinitely.
- The first boss has exactly **4,000 HP** and every later boss gains **500 HP**. After each victory, regular Nextbots gain health, speed and active-population pressure. Boss defeat automatically advances to the following three-level sector cycle.
- Preserved the supplied boss photographs byte-for-byte. SHA-256: idle `0a739ce5013dd47ef585793a2dda8bbf4e899821a4bc47c2c64ae8c5ba90bbc8`; attack `2076b12f8193b8f1034cead1379f8c24339b14e90595dba53e011bee4bd59eba`. The state machine switches to the attacking photograph during charge/direct attack and therefore uses it for a successful boss catch.
- New full-cycle suite: **34 Bossfight checks** cover all three switch levels, objective navigation, randomized positions, automatic boss spawn, 4,000 HP, real `ATTACK`-state image switching, victory transition, stronger Level 5 enemies, repeated Level 8 arena and the 4,500-HP second boss.
- Network protocol **5** carries the selected mode and boss replica metadata. The host owns Bossfight AI, combat, switches and transitions; clients reconstruct the same seeded map and receive the boss flag, scale, HP, target state and attack-face state. Boss catches also send the dedicated aggressive jumpscare identity.
- Dedicated two-process loopback results: **12 Bossfight host / 19 Bossfight client** checks passed. They cover mode handshake, equal seeds/switch signatures on Levels 1–3, guest interaction, synchronized transitions, Sun Ring, 4,000 HP, idle/attack photos, boss HUD binding, authoritative damage, boss death and synchronized Level 5. The existing Endless regression also remained green at **26 host / 42 client** checks.
- Full local results after the online layer: **17 static**, **30 smoke**, **47 map**, **22 movement**, **317 procedural**, **70 mode/event**, **34 Bossfight**, **126 combat**, and **78 spawn** checks passed — **724 Godot checks** plus static validation, zero functional failures.
- Re-exported and headlessly booted `build/BELOW_ZERO.exe` (101,262,424 bytes), then rebuilt `build/BELOW_ZERO_Friends.zip` (81,297,344 bytes). The extracted friend pack passed **20 portable checks**, including both boss photographs and protocol 5.
- Rendered and inspected `bossfight_dust_quarter.png`, `bossfight_arena_idle.png` and `bossfight_arena_attack.png` using the regular OpenGL/ANGLE renderer. The two boss states, arena cover, HUD and warm environment render without missing assets.
- Exported and headlessly booted `build/BELOW_ZERO.exe` (101,260,296 bytes). Rebuilt `build/BELOW_ZERO_Friends.zip` (81,295,251 bytes); its pack log confirms both boss textures and `bossfight_world.gd` are embedded.

## Third bundled Nextbot face (2026-10-28)

- Copied `5402324111498878359.jpg` unchanged into `assets/nextbot_faces/`; source and bundled copy share SHA-256 `528395702258bc3c963bc48e5ffa4ebbb82e33f67359b51f7c01f6aafc3a9ba8`.
- Added it as the third deterministic face variant. Normal spawning rotates through all three bundled photos, each enemy retains its assigned face when respawned, and the same variant drives its billboard and jumpscare.
- Local results after the change: **16 static**, **30 smoke**, **47 map**, **22 movement**, **317 procedural**, **70 mode/event**, **126 combat**, and **78 spawn** checks passed with no failures. The ENet regression explicitly used the new face for snapshot replication and the client jumpscare; **26 host** and **42 client** checks passed.
- Re-exported and headlessly booted `build/BELOW_ZERO.exe` (99,165,976 bytes). Its startup log confirms all three face resources load from the packed build.
- Rebuilt `build/BELOW_ZERO_Friends.zip` (79,245,156 bytes); the pack export log confirms the imported third-face texture is embedded in its PCK.

## Spawn reliability and mode-aware levers (2026-10-27)

- Root cause fixed: `LevelNavigation.synchronized` was only flipped true inside `wait_ready()`, which only the Endless level-transition path awaited. A freshly loaded Arcade/Mayhem/Sandbox/Endless world (startup, map select, round rollover, mode switch) left the flag false forever, so the standard spawner, Mayhem wave logic and Sandbox auto-spawn all gate on it and never fired. `Navigation.build()` now starts a background `wait_ready()` via `_ensure_synchronized()` so the flag is honest for every caller, with a null-tree guard so a world freed mid-poll returns cleanly. Verified with a fresh-world probe: 5 Arcade launches and 5 Mayhem launches each synchronise and spawn without any explicit `await wait_ready()`.
- Mode-aware lever policy added: `WorldInteractable.active` plus `LevelWorld.apply_interactable_policy()` hide progression breakers and the exit outside Endless. `main.gd` `refresh_interactable_policy()` is the single source of truth, wired into `start_run`, `_transition_to_level`, `return_to_menu`, the world's own deferred `_ready()`, and event start/end. Breakers re-appear while the Blackout event needs them and hide again when it ends, in every mode. Endless keeps three active breakers and a working exit; Arcade, Mayhem and Sandbox hide both.
- Robust spawning: `_spawn_bot()` now validates world/player, picks a navigable, collision-cleared patrol point far from the player via `_find_safe_spawn_point()`, logs the actual failure reason, and returns null on failure instead of planting an enemy on the player or in a wall. Callers in Mayhem waves, Sandbox batches, boss minions and level transitions handle null safely. Mayhem only commits a wave once at least one enemy spawned, so a transient spawn failure retries instead of stalling the run.
- Debug: F7 force-spawns a Nextbot (gated on F3 AI debug + debug build) and toasts the result; the AI debug HUD now lists the F7 binding. `push_warning` reports skipped spawns with mode, navigation status, patrol point count and bot/cap counts.
- New `tests/spawn_test.gd`: 78 checks covering 5 Arcade launches, Arcade round rollover, 5 Mayhem launches, 3 consecutive cleared Mayhem waves, 10-batch Sandbox manual spawn + remove + respawn, Endless breakers/exit, 3 mode-switch cycles, no over-spawn beyond the cap, and the Blackout breaker-visibility exception. Added to `tools/Launch.ps1` as the `spawn` suite.
- Final local results: **30 smoke**, **47 map**, **22 movement**, **317 procedural**, **70 mode/event**, **126 combat**, **78 spawn** checks, **690 total**, **0 failures**. The engine's pre-existing root-certificate startup message and occasional shutdown ObjectDB/RID warning remain; every suite exits successfully with no GDScript errors.

## Four-mode and event framework (2026-10-27)

- Added selectable Arcade, Endless, PNG Mayhem and Sandbox policies without replacing the existing run, movement, combat, navigation or ENet systems. Arcade has timed scoring and a session leaderboard; Mayhem has bounded waves, composable upgrades and boss waves; Sandbox applies live spawn/AI/combat/lighting settings and uses the selected PNG as an enemy face.
- Added versioned local statistics with corrupted-file fallback, all seven mutually exclusive timed events with reversible environment/enemy cleanup, observed/unobserved Angry Nextbot behavior, and phased 10,000-HP bosses with a charge warning and low-health minions.
- Added composable damage, cooldown, multishot, explosion, freeze/stun, piercing, ricochet, movement, shield and critical modifiers. Default combat values and ENet projectile behavior remain unchanged.
- Verified **15 static**, **30 smoke**, **47 map**, **126 combat**, **22 movement**, **317 procedural**, **70 mode/event**, and **26 host / 42 client** loopback checks. The mode suite also validates automatic Arcade/Endless spawns, navigation-delayed Mayhem waves, capped Sandbox auto-spawn, special projectile splash/freeze, all event cleanup paths, live Sandbox changes, statistics save/load and corrupted-save recovery.
- Exported `build/BELOW_ZERO.exe` (98,466,528 bytes) after the spawn fixes and booted it headlessly. The generated build is gitignored. The sandbox still reports its known Windows certificate-store/editor-settings warnings; forced engine shutdowns can report the pre-existing generic ObjectDB warning. No test suite reported a GDScript/runtime failure.

## Procedural progression and progressive horror (2026-10-26)

- Levels 1–3 retain the selected authored map. Level 4+ uses deterministic modular `PackedScene` rooms with bounded placement retries, explicit aligned doorways, overlap/connectivity checks, a distant exit and a guaranteed connected fallback. The live world additionally validates a NavigationServer path from spawn to the exit before enabling AI.
- Level transitions disable input and enemies, clear projectiles/effects/respawn tickets, fade to black, replace the world, wait for navigation, place actors at valid spawns, stage enemies disabled, fade in and only then resume play. Highest level, brightness and all previous settings persist. F3 reports seed/rooms/light/speed/navigation/validation; debug F6 regenerates.
- ENet protocol **4** synchronizes level transitions and deterministic seeds. The host waits for client map/navigation acknowledgements before resetting actors and resuming the shared world. Late join reproduces the current procedural level.
- Final local results: **15 static**, **30 smoke**, **47 map**, **126 combat**, **22 movement**, **317 procedural** checks, plus **26 host / 42 client** checks across two real ENet processes. The procedural suite validates 50 deterministic maps and then exercises real navigation, replacement cleanup, safe spawning and PNG damage on Level 4/5. The engine's pre-existing root-certificate message and occasional shutdown ObjectDB/RID warning remain; every suite exits successfully with no GDScript errors.

## Stamina removed (2026-10-25)

- Sprinting and jumping no longer spend stamina or enter an exhausted state. The HUD no longer draws a stamina gauge. Multiplayer poses and snapshots no longer carry stamina; the network protocol version is now 3 so older builds cannot join a changed movement rule set.
- After the change: **15 static**, **30 smoke**, **47 map**, **126 combat**, **22 movement**, and **65 two-process network checks** passed. The movement suite holds sprint for over seven seconds to catch the old exhaustion behavior. The rebuilt friend archive passed **16 portable restart checks** and contains no stamina property or HUD gauge.

## Faster Nextbots (2026-10-25)

- Chase speeds are now 9.0 / 11.4 / 13.6 m/s across the three difficulties, with quicker acceleration. Navigation avoidance permits the full late-run speed, and chase paths recalculate every 0.18 seconds for tighter turns.
- The Construct test now requires a bot to close over four meters during its timed pursuit interval. The local suites passed: **15 static**, **30 smoke**, **47 map**, **126 combat**, **20 movement** and **65 two-process network** checks. The rebuilt friend archive passed **15 portable restart checks**, including its new bot speed.

## Advanced movement update (2026-10-25)

- Replaced fixed target velocity with configurable ground/air acceleration, friction and momentum retention. Added sprint slide with slope force, slide jump, buffered/coyote jumps, air strafing, optional held-space bunny hopping, a fresh-press wall jump and a practical horizontal speed limit. Crouch uses a lower capsule and a standing-clearance query.
- Added smoother camera height/FOV/bob/tilt/landing feedback, generated slide/wind sounds, a speedometer, and persistent movement preferences. The ENet shot-origin allowance was adjusted for fast sidesteps; wall clearance checks still apply.
- Final local checks: **15 static**, **29 smoke**, **47 map**, **126 combat**, **20 movement**, and **65 two-process network checks** passed. The movement suite checks physical sliding, slide jumping, air control, held-space bunny hops, blocked standing, toggle crouch, and physical wall jumping.
- Rebuilt `build/BELOW_ZERO_Friends.zip`; its extracted PCK passed **14 portable restart checks**, including the advanced controller, movement sounds and settings. Two physical PCs with Radmin VPN, manual controller feel, and sustained frame-rate testing remain untested here.
- The environment's automatic approval review rejected recursive deletion of the extracted `build/.portable-movement-test` verification directory because that action would require a sandbox approval that is disabled. The distributed ZIP contains no test directory.

Updated 2026-10-25 after adding ENet cooperative multiplayer alongside PNG combat. Tests used the installed Godot 4.5 stable engine in Downloads.

## Added Nextbot photograph

- The supplied `5399833567338111357.jpg` was copied unchanged to `assets/nextbot_faces/elena_finkelshteyn.jpg`; both SHA-256 digests are `05d1f97ab2741a06b081e028e8de083f00949753f979ab0802ef82a92d1fc3f6`.
- First enemy in a round uses the added photo; the next uses the original. Each respawn retains its photo. Both maps use the same spawner. The photo variant is sent in network snapshots and in the reliable death event, so a client receives the correct jumpscare even before its next world update.
- After the change: **15 static**, **29 smoke**, **47 map**, **126 combat**, and **65 two-process network checks** passed. The relevant suites test alternation, preserving the image on respawn, the single-player jumpscare, client synchronization and the network jumpscare.
- The friend archive was rebuilt and its new PCK loaded in an isolated directory: **13 portable checks passed**, including loading both photos and spawning enemies with each. The archive is approximately 74.3 MiB. The original face, selected PNG and all previous gameplay systems remain included.

## Portable PNG library and friend package

- The current `Без имени.png` is bundled unchanged (SHA-256 `38811007ae70b305730a38133e2272e09d0e164545e58891812f459ca329fe6d`). Fresh installations select it with the existing 1.3 m size. Immediate selection persistence, automatic recovery of missing bundled copies and a read-only-directory fallback are implemented.
- **14 static checks**, **28 smoke**, **47 map**, **124 combat**, and **62 two-process ENet checks** passed after the library change. The static suite checks for machine-specific absolute paths in game scripts and launch/build tools.
- `build/BELOW_ZERO_Friends.zip` was built using the existing Godot executable without downloads or export templates. It contains a PCK, portable runtime, launcher, instructions and licenses. No test fixtures, user configuration or source-machine profile files are packaged.
- The archive was extracted to a different directory containing spaces and Cyrillic characters. A separate process loaded its PCK from a fresh empty working directory: **11 portable checks passed**. Another process then verified reopening and persisted selection: **9 checks passed**. Tests verified current face, current PNG, exact seeded-file hash, pixel equality, all four images, restoration, fallback and a real throw in the packed game.
- `tools/check_portable.gd` is an external test probe, not a game dependency. It uses `--portable-test` for isolated settings; `--restart-probe` checks the following process. The normal package starts through its own `PLAY.cmd`.
- Cleanup commands were rejected by this environment's approval policy, including deletion of a temporary probe directory and the obsolete engine ZIP. They remain in the development workspace. `CLEAN_PROJECT.cmd` / `tools/Clean-Project.ps1` provide scoped cleanup for the user to run; that cleanup has not been executed here. The distributed ZIP is already free of those artifacts.

- `python tests/validate_project.py`: **12 checks passed**. Resource references, nested combat GDScript structure, SVGs, actual RGBA PNG files and both layouts checked.
- `--headless --path . --log-file ./tests/engine-smoke-combat.log -- --smoke-test`: **28 checks passed** after combat integration. Underground stairs, objectives, collision/movement/look/stamina, face texture, audio buffers, pursuit, pause/settings, jumpscare/death, respawn and victory remain functional.
- `--headless --path . --log-file ./tests/engine-maps-combat.log -- --map-test`: **47 checks passed** after combat integration. Both maps, eight spawns, objectives, physical ramp traversal, pursuit, gate completion, custom death message, respawn, separate records and persistence.
- `--headless --path . --log-file ./tests/engine-combat.log -- --combat-test --import-fixture=<provided JPEG>`: **127 checks passed** (124 general checks plus three using the supplied external JPEG). Real left-mouse throws; RMB aim, wheel selection and reload; exact 20 HP damage; five-hit death; colors, smooth bar reduction and 60/100 text; independent and custom HP; no regeneration; knockback with continuing pursuit; dead-enemy contact safety; one kill per enemy; configured respawn and full/custom HP restoration; pause; actual PNG alpha; byte-identical PNG import; JPG/JPEG conversion; duplicate-name handling; invalid/truncated PNG rejection; live folder refresh; gallery/picker callback and preview; size changes; finite/unlimited ammo; lifecycle cleanup and both maps.
- The provided `Без имени.jpg` was confirmed as a valid 180×168 JPEG, imported successfully as an immediately usable PNG projectile, and its source SHA-256 was unchanged. JPEG conversion creates an opaque PNG; it does not remove the background.
- Continuous collision was exercised at **5000 m/s**, including a **2.5 cm wall** shielding a target. A visible-forehead hit above the movement capsule was also verified. Repeating the same impact callback still applies damage only once.
- An OpenGL render of Construct was captured and inspected at `tests/captures/construct.png` using Intel Iris Plus Graphics 650. The sandbox blocks Godot's user-directory shader cache, so capture used a temporary shader-cache override, removed after the capture. Normal project shader-cache settings are unchanged.
- Combat HUD/health bar/flying PNG and the paused PNG library were rendered and inspected at `tests/captures/combat.png` and `tests/captures/png_library.png`. The temporary capture override was removed. Normal game rendering configuration is unchanged.
- Both maps load the supplied `assets/nextbot_face.jpg`. The image pixels were not edited.

Navigation now uses matching mesh/map cell settings, waits for asynchronous synchronization and allows searches across the full polygon mesh. Tests query reachable interaction approaches instead of the inside of a solid breaker box.

## Multiplayer verification

- `tools/Test-Network.ps1 -EnginePath <installed Godot console executable>`: **24 host checks and 38 client checks passed**, using two independent headless processes communicating through actual ENet/UDP on `127.0.0.1`. Latest logs: `engine-net-host.log`, `engine-net-client.log`. No GDScript, transport or MTU errors remained; the sandbox certificate-store startup message remains unrelated to ENet.
- Verified real handshake, host map/difficulty, independent cameras and local movement, remote avatar creation, AI targeting a remote player, online pause without stopping simulation, custom PNG upload with alpha, exact 20-HP reductions, five network throws killing an enemy, correct per-player kills/hit confirmations, host-originated projectile replication and damage, full-HP enemy respawn, shared breaker state, local jumpscare/death/respawn, continued play during host death, AI retargeting after a victim dies, shared extraction, late join after extraction, host-only restart, authoritative difficulty on restart, reconnect into a damaged enemy/completed objective, stale avatar cleanup and graceful server shutdown.
- Single-player regressions after integration: **28 smoke, 47 map and 124 combat checks passed**, with **12 static checks**. Logs: `engine-smoke-network.log`, `engine-map-network.log`, `engine-combat-network.log`.
- A rendered ENet client also completed the then-current 51-check network suite. Inspected `captures/network_menu.png` and `captures/network_play.png`: Russian host/join menu, second player's body/name, original enemy image, HP, custom held PNG and network HUD display correctly. The temporary sandbox shader-cache override was removed afterward.
- Not tested here: two physical computers using Radmin VPN and their Windows firewall settings, an eight-player stress session, internet latency/packet-loss performance or manual audio listening. Eight is the configured player cap. See [MULTIPLAYER.md](../MULTIPLAYER.md) for setup and the two-process test command.

Automated suites use separate `.godot/test_<suite>_settings.cfg` and `.godot/test_projectiles_<suite>` directories. They do not modify normal user PNG files, settings or records. The test only deletes imported copies that it created in its isolated directory.

Remaining limitations: no sustained frame-rate benchmark or listening test. The native file dialog's configuration and file-selection callback were automated; the OS picker was not manually operated. The sandbox reports a root-certificate-store access error at startup and sometimes an ObjectDB cleanup warning on exit; all gameplay suites exit successfully with no GDScript errors. The earlier launcher download fallback issue is outside this combat change; use the installed Godot editor and F5.

## Android build and mobile online verification (2026-10-30)

- Godot 4.5.1 exported `build/BELOW_ZERO_Android.apk` successfully through the reproducible `tools/Build-Android.ps1` entry point. The latest debug APK is 33,017,208 bytes, package `com.nextbotik.belowzero`, version `1.2.0` / code `3`, target SDK 35 and ARM64-only.
- Android SDK `aapt2` confirmed the launcher activity and the network/Wi-Fi/vibration permissions. `apksigner verify --verbose` confirmed APK Signature Scheme v2 and v3 with one RSA-2048 debug signer.
- The mobile integration suite passed **12/12** checks: touch HUD creation, analog joystick input/release, touch look, projectile press/release, direct left/right post-boss reward selection, ENet hosting and automatic UDP Wi-Fi/LAN discovery response.
- The static suite passed **17/17** checks. The two-process Endless ENet regression passed **26/26 host** and **42/42 client** checks; Bossfight passed **18/18 host** and **22/22 client** checks after the mobile discovery/menu changes.
- No Android device or emulator was connected (`adb devices` returned no devices), so physical-device installation, rendered touch ergonomics, Android system file picker behavior and device performance remain manual checks. The test APK is debug-signed and is not a Google Play release artifact.

## Face-specific throwable items (2026-10-30)

- Added transparent test-tube, literature-textbook and Constitution projectiles to the persistent PNG library. Their editable SVG sources and generated 512×512 PNGs are bundled in desktop, friend-package and Android exports.
- Ordinary photographed enemies now reject the wrong projectile with zero damage and a readable requirement message. Elena Finkelshteyn accepts the test tube, pink-background Kogan accepts the literature textbook, and the original black-and-white face accepts the Constitution. Matching hits retain the normal 20 HP damage. Bosses and custom Sandbox faces remain compatible with arbitrary PNGs.
- Dedicated item regression: **20/20** checks. Full combat: **129/129**. Modes: **76/76**. Bossfight: **54/54**. Static validation: **17/17**. Two-process Endless networking: **26/26 host + 42/42 client**; Bossfight: **18/18 host + 22/22 client**.
- Network protocol is now **7** so the authoritative host receives the typed throwable with every shot. The Windows release executable booted successfully; Android APK Signature Schemes v2/v3 verified; the friend archive was rebuilt with the current PCK and instructions.
- Final generated artifacts: Windows EXE SHA-256 `606E38DBE8812FBD0FA19418BA175846E0EBADC30D08F1A70A5EF229D1F598DC`; Android APK `FEC45FA3041BE68B818C9C0D62C0D03D470D7EBF49C3B1B366962C9377878149`; friend ZIP `198F48CCE3C029BEC1A0A4007435AE2D42845D7627C3E8A00851815E387D9394`.
