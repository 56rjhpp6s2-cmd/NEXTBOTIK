# PNG projectile combat

The combat system is integrated into both existing maps. Movement, flashlight, hiding, objectives, chases, jumpscare and the custom death message remain available.

## Play and import

- Left mouse: throw. Holding it repeats throws at the cooldown rate.
- Right mouse: aim with a narrower FOV and lower mouse sensitivity.
- R: reload/re-grip the PNG and refresh the available files. It works with unlimited ammunition too.
- Mouse wheel: select another image.
- Tab: pause the run and open the PNG library. Choose **Import PNG**, pick a file, preview it and return to play. The pause menu also has a PNG library/import button.

The library creates `user://projectiles/` at first launch and seeds three original transparent PNGs plus the current `Без имени.png`. The latter is bundled byte for byte and is the default selection, with a 1.3 m size. Missing bundled files are restored on refresh; bundled resources also work when the image directory is not writable. Selection changes save immediately. The UI shows the resolved folder path. PNG files placed there directly are detected within three seconds; **Refresh List** or R rescans immediately. Imports are available without restarting. A duplicate filename gets a numeric suffix instead of replacing the existing file. Original PNG files are copied byte for byte.

**Import PNG also accepts JPG/JPEG**, including uppercase extensions. A JPEG is decoded and saved as a real PNG copy in the projectiles directory; its source file is left unchanged. The converted image is selected immediately. Conversion does not remove the background or create transparency that was absent from the JPEG.

PNG transparency and aspect ratio are retained. The size slider sets the image's longest side in meters (0.2–2.5 m). Gallery previews use a checkerboard so alpha is visible. Decode errors and invalid/truncated files produce a message instead of crashing. To bound memory, a file may be at most 64 MB, 16,384 pixels on either axis and 64 megapixels total. Render textures are reduced to at most 2048 pixels on their longest side; previews to 256. Original imported files are never resized or rewritten. Four full render textures are cached; previews are cached separately.

## Defaults and enemy reactions

| Setting | Default |
|---|---|
| Projectile damage | 20 HP |
| Projectile speed | 35 m/s |
| Throw cooldown | 0.3 s |
| Maximum range | 100 m |
| Maximum lifetime | 4 s; range may expire first |
| Ammunition | Unlimited |
| Optional finite magazine | 12, unlimited reserves |
| Reload duration | 0.8 s |
| Nextbot health | 100/100 HP |
| Nextbot respawn delay | 10 s |
| Health regeneration | Disabled |

An enemy loses exactly 20 HP per normal hit. Its billboard health bar animates toward the new value and shows exact HP. Green is used at 60% and above, yellow below 60%, red below 25%. A hit flashes the enemy red, applies collision-aware knockback and produces a spatial sound, particles, floating damage and a hitmarker. A living enemy continues pursuing the player.

At zero HP, the AI and attack state stop immediately, collision/hurtboxes and navigation avoidance are disabled, the health bar hides, and the face falls/shrinks/fades with a particle and sound effect. The kill is counted once. A replacement spawns far from the player after the configured delay with full health; custom maximum HP is preserved. Delayed replacements count against the encounter population so a kill is not immediately replaced by the difficulty director. Timers and projectiles freeze on pause. Death, restarting, changing maps and returning to menu clear old projectiles and pending replacements.

## Architecture

All components are in `scripts/combat/`:

| Component | Responsibility |
|---|---|
| `ProjectileController` | Input, cooldown, aim, reload/ammo, held-image animation, active projectiles |
| `PNGProjectile` | Billboard image, velocity, swept-sphere and segment queries, impact latch, range/lifetime cleanup |
| `PNGImageLoader` | User directory, PNG validation, original-file import, live refresh, previews and bounded texture cache |
| `HealthComponent` | Per-actor maximum/current HP, damage signals, a latched death signal, optional regeneration |
| `DamageSystem` | Damage receiver resolution, hit confirmation, numbers and CPU particle effects |
| `NextbotCombatController` | Health bar, camera-aligned face hurtbox, hit reactions, knockback and death presentation |
| `CombatHUD` | Crosshair, PNG icon/name, ammo, target HP, kills, gallery, preview and native file picker |

The AI collision capsule stays sized for the existing corridors. A thin hurtbox follows the camera-facing face so the visible forehead above that capsule can also be hit. Both area and body hits resolve to the same health component. Each projectile latches its impact before applying damage, preventing two contacts from damaging twice. Continuous sweeps handle initial overlaps and movement between physics frames; the firing player's RID is excluded. World collision blocks damage to targets behind it.

Weapon configuration is exported on `ProjectileController`. Enemy HP and respawn delay are exported on `NextbotEnemy`, or supplied per spawn:

```gdscript
var tougher_bot = _spawn_bot(Vector3(60, 0.1, 96), {
    "max_health": 160.0,
    "respawn_delay": 15.0,
})
```

`HealthComponent.apply_damage(amount, source, world_hit_position)` returns applied damage, ignores invalid/nonpositive damage and emits `health_changed`, `damaged`, and one `died` signal. PNGs route through `DamageSystem.apply_hit()` and the enemy's `receive_png_hit()` method, so feedback and kill ownership stay consistent.

Combat audio is synthesized by the existing sound manager and uses the existing master and SFX buses. No audio downloads or packages are required.

## Tests

```powershell
godot --headless --path . --log-file ./tests/engine-combat.log -- --combat-test
godot --headless --path . --log-file ./tests/engine-smoke.log -- --smoke-test
godot --headless --path . --log-file ./tests/engine-maps.log -- --map-test
python tests/validate_project.py
```

The combat suite exercises the real physics engine, including a 5000 m/s shot and a 2.5 cm wall, five standard hits, dead-enemy contact, delayed replacement, independent/custom HP, actual left-mouse input, aim, wheel selection, reload, alpha-preserving imports with Unicode filenames, JPG/JPEG-to-PNG conversion, corrupt images, native-picker selection callbacks, gallery pause, cleanup, and both maps. Each suite uses separate `.godot/test_*` settings and PNG storage. Normal user images/settings are not touched. Optional `--import-fixture=<image path>` adds an import regression using a specific external image; it verifies the source hash is unchanged.

For a graphics capture, run `godot --path . -- --capture-combat` without `--headless`. It captures the combat HUD and gallery. Results and environment limitations are recorded in `tests/VERIFICATION.md`.
