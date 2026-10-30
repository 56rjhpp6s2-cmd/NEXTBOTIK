# Nextbots overhaul progress

This file is the durable implementation checklist for the master overhaul. Checked items are implemented in the repository; verification state is called out separately.

## Audit

- [x] Identified Godot 4.5 / GDScript architecture, programmatic scene/UI construction, autoloads and Windows exports.
- [x] Inventoried authored/procedural worlds, navigation, player movement, AI, combat, PNG library, UI, networking, audio and existing tests.
- [x] Preserved the existing controller, world contract, combat stack, ENet protocol and CI workflows.
- [x] Baseline static suite: 15 checks passed on 2026-10-27.
- [x] Godot integration: 30 smoke, 47 map, 126 combat, 22 movement, 317 procedural and 70 mode checks passed on 2026-10-27.
- [x] Two-process ENet regression: 26 host and 42 client checks passed.
- [x] Windows executable exported and booted from `build/BELOW_ZERO.exe` (generated artifact remains gitignored).

## Existing foundations retained

- [x] Acceleration movement, sprint, crouch, slide/slide-jump, bunny hop, air strafe, wall jump and camera polish.
- [x] Custom PNG import/library, previews, persistence, billboard projectiles and swept collision.
- [x] Reusable enemy health, HP bars, damage feedback, death and delayed respawn.
- [x] Navigation pursuit, LOS, sound response, last-known-position search and stuck recovery.
- [x] Deterministic modular generation from Endless level 4, 50-seed test coverage, navigation validation and safe fallback.
- [x] Progressive darkness, fog, flashlight, safe rooms and capped speed/room curves.
- [x] Death/jumpscare/results and ENet co-op foundations.

## Current milestone — mode and replayability framework

- [x] Central gameplay-mode/event tuning resource.
- [x] Corruption-tolerant local statistics store.
- [x] Reusable Mayhem modifier model.
- [x] Five selectable, playable game-mode loops and mode-specific HUD/results, including the dedicated Bossfight progression cycle.
- [x] Reversible random-event manager and all seven event types.
- [x] Phased boss support, charge telegraph, minions and boss HUD.
- [x] Live Sandbox controls and selected-PNG custom enemy spawning.
- [x] Reliable automatic spawning in Arcade, Endless and Mayhem; configurable Sandbox auto-spawn toggle, interval, batch and cap.
- [x] Original Dust Quarter objective map, randomized switches, Sun Ring arena, escalating 4,000 + 500 HP bosses and two-state supplied boss artwork.
- [x] Rebuilt Dust Quarter visual/layout pass: grounded skyline buildings and props, supported market/lights, distinct lanes and courtyards, façade detail and bounded 36 m static batching.
- [x] Authoritative Bossfight co-op: mode/seed handoff, shared switches, synchronized level cycle, boss HP/art/attacks and post-victory transition for up to eight players.
- [x] Reusable explosive, freezing, piercing, ricochet, critical and multishot projectile modifiers.
- [x] Mandatory post-boss Reward Keeper using the supplied raised-hand photograph, two calibrated hand anchors, rarity presentation and direct Q-left / E-right selection.
- [x] Data-defined 23-reward pool with weighted rarity, stack/dependency filtering, run persistence and four mechanically distinct PNG weapons.
- [x] Protocol-6 authoritative two-choice multiplayer vote with changeable ballots, tie/no-vote handling, late-join snapshots and exactly-once group reward application.
- [x] Collision-validated progression lever behind the NPC, hidden until rewards finalize and latched against duplicate transitions; lever-free Mayhem/Sandbox cleanup paths.
- [x] Static and Godot engine tests for the new architecture.

## Remaining master-task work after this milestone

- [ ] Vaulting and ledge mantling with authored collision tests.
- [ ] Persistent named custom-Nextbot editor profiles and chase-music selection.
- [ ] Dedicated handcrafted third level (the existing project currently contains two authored maps).
- [ ] Rich event objectives/power-panel placement and additional special-enemy art/audio content.
- [ ] Multiplayer authority/synchronization for Arcade, PNG Mayhem, Sandbox and random events (Endless and Bossfight are online).
- [ ] Manual native file-dialog, audio mix, controller-feel and rendered UI review.
- [ ] Sustained representative-load frame-time benchmark on a mid-range Windows PC.
- [ ] Godot integration, restart/leak, Windows export and CI verification after all overhaul phases.
