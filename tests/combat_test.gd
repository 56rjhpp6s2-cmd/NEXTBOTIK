extends RefCounted
## Exercises the real weapon, continuous physics queries, enemies, library and UI.
var failures: Array[String] = []
var checks: int = 0
var confirmed_hits: int = 0
var created_files: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func frames(game, count: int) -> void:
	for frame in range(count):
		await game.get_tree().physics_frame

func _confirmed(_target: Node, _amount: float, _lethal: bool) -> void:
	confirmed_hits += 1

func _aim(game, point: Vector3) -> void:
	var direction = point - game.player.view.camera.global_position
	game.player.rotation.y = atan2(-direction.x, -direction.z)
	game.player.view.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	game.player.view.rotation.x = game.player.view.pitch
	game.player.view.camera.rotation = Vector3.ZERO

func run(game) -> void:
	if Settings.level_index != 1:
		game._select_map(1)
	await game.world.navigation.wait_ready()
	Settings.unlimited_png_ammo = true
	game.start_run()
	game.spawn_timer = 9999
	game.player.reset_at(Vector3(60, 0.1, 84))
	await frames(game, 15)
	var weapon = game.projectiles
	var images = game.png_images
	game.damage_system.hit_confirmed.connect(_confirmed)
	check(images.entries.size() >= 3, "Bundled PNGs are available immediately")
	check(images.directory.contains(".godot"), "Tests isolate user projectile storage")
	check(weapon.projectile_damage == 20 and weapon.projectile_speed == 35, "Weapon defaults: 20 HP and 35 m/s")
	check(weapon.maximum_range == 100 and is_equal_approx(weapon.throw_cooldown, 0.3), "Weapon defaults: 100 m range and 0.3 second cooldown")
	check(weapon.unlimited_ammo, "Ammunition is unlimited by default")
	images.select_filename("BZ_anomaly.png")
	var texture: Texture2D = images.current_texture()
	check(texture != null and texture.get_image().get_pixel(0, 0).a < 0.01, "Actual PNG texture retains transparency")
	for action in ["throw_png", "aim_png", "reload_png", "next_png", "previous_png", "png_library", "reward_left", "interact"]:
		check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "Combat input bound: " + action)
	var old_index: int = images.selected_index
	var wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	weapon._unhandled_input(wheel)
	check(images.selected_index != old_index, "Mouse wheel selects the next PNG")
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	weapon._unhandled_input(wheel)
	check(images.selected_index == old_index, "Mouse wheel selects the previous PNG")
	Input.action_press("aim_png")
	await frames(game, 12)
	check(game.player.view.aiming and game.player.view.camera.fov < 73, "Right mouse aims and narrows FOV")
	check(is_equal_approx(game.player.view.sensitivity_multiplier, 0.65), "Aiming lowers mouse sensitivity")
	Input.action_release("aim_png")
	await frames(game, 15)
	check(not game.player.view.aiming and game.player.view.camera.fov > 73, "Releasing aim restores normal view")
	var bot = game._spawn_bot(Vector3(60, 0.1, 96), {"respawn_delay": 1.0})
	var other = game._spawn_bot(Vector3(66, 0.1, 96), {"max_health": 160.0, "respawn_delay": 0.25})
	await frames(game, 8)
	bot.enabled = false
	other.enabled = false
	check(bot.face.texture == game.face_textures[1] and other.face.texture == game.face_textures[2], "Bundled enemy photos rotate independently in one run")
	check(bot.combat.health.current_health == 100 and bot.combat.health.max_health == 100, "Nextbot begins with 100/100 HP")
	check(other.combat.health.current_health == 160, "Individual Nextbot maximum HP is configurable")
	check(not bot.combat.health.regeneration_enabled, "Health regeneration is disabled by default")
	check(bot.combat.bar_root.visible and bot.combat.health_label.text == "100/100", "World health bar displays exact starting HP")
	for hit_index in range(5):
		_aim(game, bot.global_position + Vector3.UP * 1.2)
		weapon.cooldown_remaining = 0.0
		var hp_before: float = bot.combat.health.current_health
		var shot = weapon.fire()
		check(shot != null, "PNG throw %d launches" % (hit_index + 1))
		if shot == null:
			break
		check(shot.visual.texture == images.current_texture() and shot.visual.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "Throw %d uses the selected billboard PNG" % (hit_index + 1))
		if hit_index == 0:
			check(weapon.fire() == null, "Cooldown rejects a second immediate throw")
			check(weapon.animation != null and weapon.animation.is_running(), "Throw plays a viewmodel animation")
		for frame in range(60):
			await game.get_tree().physics_frame
			if bot.combat.health.current_health < hp_before:
				break
		check(bot.combat.health.current_health == hp_before - 20.0, "Hit %d deals exactly 20 HP" % (hit_index + 1))
		check(other.combat.health.current_health == 160, "Hit %d leaves another bot's health unchanged" % (hit_index + 1))
		check(weapon.hit_time > 0.0, "Hit %d produces a hitmarker" % (hit_index + 1))
		if hit_index == 0:
			check(bot.combat.displayed_ratio > 0.8 and bot.combat.displayed_ratio <= 1.0, "Health bar smoothly animates instead of snapping")
			check(bot.face.modulate.g < 0.9, "Damaged Nextbot flashes red")
			check(bot.combat.knockback.length() > 0.1, "Hit applies knockback")
			check(bot.state == NextbotEnemy.State.CHASE, "A damaged living bot remains in pursuit state")
			check(not game.damage_system.get_children().is_empty(), "Hit spawns damage numbers and particles")
		if hit_index == 1:
			check(bot.combat.health_label.text == "60/100", "Health label updates to 60/100")
			await frames(game, 35)
			check(bot.combat.health.current_health == 60, "Damaged health does not regenerate")
		if hit_index == 2:
			check(bot.combat.bar_material.albedo_color == bot.combat.YELLOW, "Health bar turns yellow below 60 percent")
		if hit_index == 3:
			check(bot.combat.bar_material.albedo_color == bot.combat.RED, "Health bar turns red below 25 percent")
	check(bot.combat.health.dead and bot.state == NextbotEnemy.State.DEAD, "Five hits kill a 100 HP Nextbot")
	check(not bot.enabled and not bot.agent.avoidance_enabled and bot.collision_layer == 0, "Death disables AI, navigation avoidance and collision")
	check(not bot.combat.bar_root.visible, "Death hides the enemy health bar")
	check(game.kill_count == 1 and confirmed_hits == 5, "Five impacts award exactly one kill")
	check(game.pending_respawns.size() == 1 and not game.bots.has(bot), "Killed enemy schedules one delayed replacement")
	if not bot.combat.health.dead or game.pending_respawns.is_empty():
		print("COMBAT TEST: %d checks, %d failures" % [checks, failures.size()])
		game.get_tree().quit(1)
		return
	bot.global_position = game.player.global_position + Vector3(0, 0, 0.3)
	var extra = game.damage_system.apply_hit(bot, 20, game.player, bot.global_position, Vector3.FORWARD)
	await frames(game, 2)
	check(extra == 0 and game.kill_count == 1, "A dead enemy cannot take duplicate damage or award another kill")
	check(game.combat_hud.kills_label.text == "KILLS  1", "Combat HUD displays the awarded kill")
	check(game.is_running() and game.player.active, "A touching dead Nextbot cannot kill the player")
	var remaining: float = game.pending_respawns[0].remaining
	game.pause_run()
	await frames(game, 12)
	check(is_equal_approx(game.pending_respawns[0].remaining, remaining), "Enemy respawn delay freezes while paused")
	game.resume_run()
	await frames(game, 70)
	var replacement
	for candidate in game.bots:
		if candidate != other:
			replacement = candidate
	check(is_instance_valid(replacement) and replacement.combat.health.current_health == 100, "Nextbot respawns after its delay with full HP")
	check(is_instance_valid(replacement) and replacement.face.texture == game.face_textures[1], "Respawned Nextbot retains its own photo")
	check(game.pending_respawns.is_empty() and game.kill_count == 1, "Respawn does not award a kill or create duplicate tickets")
	game.damage_system.apply_hit(other, 160.0, game.player, other.global_position + Vector3.UP, Vector3.BACK)
	await frames(game, 22)
	var custom_replacement
	for candidate in game.bots:
		if candidate != replacement and candidate.max_health == 160.0:
			custom_replacement = candidate
	check(is_instance_valid(custom_replacement) and custom_replacement.combat.health.current_health == 160, "Respawning preserves an individual bot's custom maximum HP")
	check(game.kill_count == 2, "Independent enemy deaths each award one kill")
	game._clear_bots()
	await frames(game, 2)
	await _test_collision(game)
	await _test_live_reaction(game)
	await _test_library(game)
	await _test_reload_and_lifecycle(game)
	for kind in ["png_throw", "png_hit", "png_wall", "png_reload", "png_death"]:
		check(Sound.clips.has(kind) and Sound.clips[kind].data.size() > 100, "Combat sound generated: " + kind)
	var master_before: float = Settings.master
	var sfx_before: float = Settings.sfx
	Settings.master = 0.0
	Settings.sfx = 0.0
	Sound.apply_settings()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "Combat audio respects master and sound-effects mute")
	Settings.master = master_before
	Settings.sfx = sfx_before
	Sound.apply_settings()
	_cleanup_files(images)
	print("COMBAT TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)

func _test_collision(game) -> void:
	var weapon = game.projectiles
	game.player.reset_at(Vector3(60, 0.1, 84))
	var bot = game._spawn_bot(Vector3(60, 0.1, 96), {"max_health": 200.0})
	await frames(game, 8)
	bot.enabled = false
	_aim(game, bot.global_position + Vector3.UP * 1.2)
	weapon.projectile_speed = 5000.0
	weapon.cooldown_remaining = 0
	var fast = weapon.fire()
	await frames(game, 3)
	check(bot.combat.health.current_health == 180, "Swept collision hits a target at 5000 m/s without tunneling")
	check(not is_instance_valid(fast), "An impacted projectile is cleaned up")
	var wall = WorldSurface.box(game.world, Vector3(4, 3, 0.025), Vector3(60, 1.5, 90), "metal")
	await frames(game, 3)
	weapon.cooldown_remaining = 0
	var blocked = weapon.fire()
	await frames(game, 3)
	check(bot.combat.health.current_health == 180, "A 2.5 cm wall blocks high-speed damage to enemies behind it")
	check(not is_instance_valid(blocked), "Wall impact removes the projectile")
	wall.queue_free()
	await frames(game, 2)
	_aim(game, bot.global_position + Vector3.UP * 2.5)
	weapon.cooldown_remaining = 0
	weapon.fire()
	await frames(game, 3)
	check(bot.combat.health.current_health == 160, "Visible forehead above the AI capsule can be hit")
	weapon.projectile_speed = 35
	var duplicate = weapon.launch(game.png_images.current_texture(), game.player.view.camera.global_position, Vector3.BACK)
	duplicate.set_physics_process(false)
	var hit = {"collider": bot, "position": bot.global_position + Vector3.UP, "normal": Vector3.FORWARD}
	duplicate._impact(hit)
	duplicate._impact(hit)
	check(bot.combat.health.current_health == 140, "A repeated collision callback applies damage only once")
	var short_lived = weapon.launch(game.png_images.current_texture(), Vector3(60, 12, 84), Vector3.UP)
	short_lived.lifetime = 0.05
	await frames(game, 6)
	check(not is_instance_valid(short_lived), "Configurable lifetime cleans up missed projectiles")
	var ranged = weapon.launch(game.png_images.current_texture(), Vector3(60, 12, 84), Vector3.UP)
	ranged.maximum_range = 1.0
	await frames(game, 5)
	check(not is_instance_valid(ranged), "Maximum travel distance cleans up projectiles")
	check(game.is_running(), "Projectiles never damage their firing player")
	game._clear_bots()
	await frames(game, 2)

func _test_live_reaction(game) -> void:
	game.player.reset_at(Vector3(60, 0.1, 84))
	var bot = game._spawn_bot(Vector3(60, 0.1, 100))
	await frames(game, 10)
	var before = bot.global_position.distance_to(game.player.global_position)
	game.damage_system.apply_hit(bot, 20, game.player, bot.global_position + Vector3.UP * 1.4, Vector3.BACK)
	await frames(game, 35)
	check(bot.enabled and bot.state == NextbotEnemy.State.CHASE and bot.combat.health.current_health == 80, "A wounded live Nextbot stays active at 80 HP")
	check(bot.global_position.distance_to(game.player.global_position) < before - 1.0, "Wounded Nextbot physically continues chasing after knockback")
	game._clear_bots()
	await frames(game, 2)

func _test_library(game) -> void:
	var images = game.png_images
	var folder = ProjectSettings.globalize_path("res://").path_join(".godot/combat_fixtures")
	DirAccess.make_dir_recursive_absolute(folder)
	var path = folder.path_join("мой PNG с прозрачностью.png")
	var image = Image.create(32, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(5, 15):
		for x in range(8, 24):
			image.set_pixel(x, y, Color(0.9, 0.2, 0.4, 0.7))
	image.save_png(path)
	var before: int = images.entries.size()
	var result: Dictionary = images.import_png(path)
	check(result.ok and FileAccess.file_exists(result.get("path", "")), "A custom PNG is copied into the projectile directory")
	if result.ok:
		created_files.append(result.path)
		check(FileAccess.get_file_as_bytes(path) == FileAccess.get_file_as_bytes(result.path), "Import preserves original PNG bytes")
	check(images.entries.size() == before + 1, "Imported PNG appears immediately without restart")
	check(images.current_entry().filename.begins_with("мой PNG"), "Imported Unicode filename is selected immediately")
	var selected_image = images.current_texture().get_image()
	check(selected_image.get_pixel(0, 0).a < 0.01 and selected_image.get_pixel(16, 10).a > 0.6, "Imported PNG retains both transparent and translucent pixels")
	var second: Dictionary = images.import_png(path)
	check(second.ok and second.path != result.path, "Duplicate import chooses a unique filename instead of overwriting")
	if second.ok:
		created_files.append(second.path)
	var jpg_path = folder.path_join("JPEG картинка.JPG")
	var rgb = image.duplicate()
	rgb.convert(Image.FORMAT_RGB8)
	rgb.save_jpg(jpg_path, 0.9)
	var original_jpg = FileAccess.get_file_as_bytes(jpg_path)
	var jpeg_result: Dictionary = images.import_png(jpg_path)
	check(jpeg_result.ok and jpeg_result.get("converted", false), "JPG import converts a copy to PNG")
	if jpeg_result.ok:
		created_files.append(jpeg_result.path)
		check(FileAccess.get_file_as_bytes(jpeg_result.path).slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]), "Converted JPEG is an actual PNG, not a renamed file")
		check(images.current_entry().filename.get_extension() == "png" and images.current_entry().dimensions == Vector2i(32, 20), "Converted JPG is selected immediately with its original dimensions")
	check(FileAccess.get_file_as_bytes(jpg_path) == original_jpg, "JPEG import leaves the source file unchanged")
	var jpeg_path = folder.path_join("JPEG картинка.jpeg")
	DirAccess.copy_absolute(jpg_path, jpeg_path)
	var long_extension: Dictionary = images.import_png(jpeg_path)
	check(long_extension.ok, "JPEG extension and uppercase JPG are both supported")
	if long_extension.ok:
		created_files.append(long_extension.path)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--import-fixture="):
			var fixture_path = argument.trim_prefix("--import-fixture=")
			var source_hash = FileAccess.get_sha256(fixture_path)
			var fixture: Dictionary = images.import_png(fixture_path)
			check(fixture.ok, "Provided user image imports successfully: " + fixture_path.get_file())
			if fixture.ok:
				created_files.append(fixture.path)
				check(images.current_texture() != null and images.current_entry().filename.get_extension() == "png", "Provided user image is ready as a PNG projectile")
			check(FileAccess.get_sha256(fixture_path) == source_hash, "Provided user image is not modified")
	var invalid_path = folder.path_join("invalid.png")
	var invalid_file = FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_string("This is not an image.")
	invalid_file.close()
	var invalid: Dictionary = images.import_png(invalid_path)
	check(not invalid.ok, "Invalid PNG import returns an error without crashing")
	var truncated = folder.path_join("truncated.png")
	var partial = FileAccess.open(truncated, FileAccess.WRITE)
	partial.store_buffer(FileAccess.get_file_as_bytes(path).slice(0, 50))
	partial.close()
	check(not images.import_png(truncated).ok, "Truncated PNG is rejected safely")
	var external_added = images.directory.path_join("combat_external_added.png")
	DirAccess.copy_absolute(path, ProjectSettings.globalize_path(external_added))
	created_files.append(external_added)
	images._process(3.1)
	var found: bool = false
	for entry in images.entries:
		found = found or entry.filename == "combat_external_added.png"
	check(found, "Automatic refresh discovers files added directly to the folder")
	var timer_before: float = game.survival_time
	var library_key = InputEventAction.new()
	library_key.action = "png_library"
	library_key.pressed = true
	game._unhandled_input(library_key)
	await frames(game, 8)
	check(game.combat_hud.gallery.visible and game.get_tree().paused, "PNG gallery pauses gameplay and releases the mouse")
	check(is_equal_approx(game.survival_time, timer_before), "Survival timer freezes while choosing PNGs")
	var picker: FileDialog = game.combat_hud.file_picker
	check(picker.access == FileDialog.ACCESS_FILESYSTEM and picker.file_mode == FileDialog.FILE_MODE_OPEN_FILE and picker.use_native_dialog, "Import PNG uses the native filesystem PNG picker")
	check(picker.filters[0].contains("*.jpg") and picker.filters[0].contains("*.jpeg"), "Default file-picker filter includes JPG and JPEG")
	var paths_before: Array = []
	for entry in images.entries:
		paths_before.append(entry.path)
	picker.file_selected.emit(path)
	for entry in images.entries:
		if not paths_before.has(entry.path):
			created_files.append(entry.path)
	check(game.combat_hud.preview.texture != null and game.combat_hud.details.text.contains("мой PNG"), "File-picker selection updates gallery preview immediately")
	game.combat_hud.size_slider.value = 1.25
	game.combat_hud.close_library()
	check(game.is_running() and not game.get_tree().paused, "Closing the gallery resumes the same run")
	var sized = game.projectiles.launch(images.current_texture(), Vector3(60, 12, 84), Vector3.UP)
	var rendered_size = sized.visual.pixel_size * maxi(sized.texture.get_width(), sized.texture.get_height())
	check(is_equal_approx(rendered_size, 1.25), "Custom projectile size changes the 3D PNG size")
	sized.expire()
	game.pause_run()
	game.combat_hud.open_library()
	game.combat_hud.close_library()
	check(game.mode == game.Mode.PAUSED and game.get_tree().paused, "Gallery opened from pause returns to pause")
	game.resume_run()
	images.select(0)
	game.combat_hud._item_selected(1)
	check(images.selected_index == 1 and game.combat_hud.icon.texture == images.current_entry().preview, "Image selection updates the combat HUD icon")

func _test_reload_and_lifecycle(game) -> void:
	var weapon = game.projectiles
	game.player.reset_at(Vector3(60, 0.1, 84))
	_aim(game, Vector3(60, 20, 90))
	weapon.unlimited_ammo = false
	weapon.ammo = 2
	weapon.cooldown_remaining = 0
	weapon.reload_remaining = 0
	weapon.require_release = false
	Input.action_press("throw_png")
	await frames(game, 2)
	Input.action_release("throw_png")
	check(weapon.ammo == 1 and not weapon.projectiles.is_empty(), "Left mouse input launches a real projectile")
	weapon.cooldown_remaining = 0
	weapon.fire()
	check(weapon.ammo == 0, "Optional finite magazine consumes ammunition")
	weapon.cooldown_remaining = 0
	check(weapon.fire() == null and weapon.reload_remaining > 0, "Empty magazine initiates reloading")
	check(weapon.fire() == null, "Reload blocks throwing until complete")
	await frames(game, 55)
	check(weapon.ammo == weapon.magazine_size and weapon.reload_remaining == 0, "Reload refills the magazine")
	weapon.unlimited_ammo = true
	var reload_event = InputEventAction.new()
	reload_event.action = "reload_png"
	reload_event.pressed = true
	weapon._unhandled_input(reload_event)
	check(weapon.reload_remaining > 0, "R reloads/refreshes PNGs with unlimited ammunition too")
	await frames(game, 55)
	var still = weapon.launch(game.png_images.current_texture(), Vector3(60, 12, 84), Vector3.UP)
	var before = still.global_position
	game.pause_run()
	await frames(game, 6)
	check(is_instance_valid(still) and still.global_position == before, "Paused projectiles do not move or hit")
	check(weapon.fire() == null, "Pause prevents new throws")
	game.resume_run()
	game.kill_player(null)
	await frames(game, 2)
	check(weapon.projectiles.is_empty() and not game.combat_hud.hud.visible, "Player death cleans up projectiles and combat HUD")
	await game.get_tree().create_timer(1.2).timeout
	check(game.ui.result_title.text == "РОССИЯ ПУТИН ПОБЕДА", "Existing jumpscare/death presentation remains intact")
	Settings.unlimited_png_ammo = true
	game.start_run()
	game.spawn_timer = 9999
	check(game.kill_count == 0 and game.pending_respawns.is_empty() and weapon.unlimited_ammo, "Respawn resets kills, enemy tickets, ammunition and projectiles")
	var old_world = game.world
	game.return_to_menu()
	game._select_map(0)
	await game.world.navigation.wait_ready()
	game.start_run()
	game.spawn_timer = 9999
	var underground = game._spawn_bot(Vector3(54, 0.1, 42))
	await frames(game, 4)
	game.damage_system.apply_hit(underground, 20, game.player, underground.global_position + Vector3.UP, Vector3.FORWARD)
	check(game.world != old_world and underground.combat.health.current_health == 80, "Combat works on the original underground map too")
	game.return_to_menu()
	check(weapon.projectiles.is_empty() and game.bots.is_empty() and game.pending_respawns.is_empty(), "Returning to menu clears all combat actors and delayed spawns")
	check(weapon.fire() == null, "Menu cannot fire projectiles into the level")

func _cleanup_files(images) -> void:
	var root_path = ProjectSettings.globalize_path(images.directory).simplify_path()
	for path in created_files:
		var absolute = ProjectSettings.globalize_path(path).simplify_path()
		if absolute.begins_with(root_path + "/"):
			DirAccess.remove_absolute(absolute)
	images.refresh(true)
