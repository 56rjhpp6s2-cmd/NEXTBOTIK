# Verification status

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
