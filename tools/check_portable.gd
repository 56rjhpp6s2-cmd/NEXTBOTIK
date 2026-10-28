extends SceneTree
## Run against an extracted pack with --portable-test; uses isolated test preferences.
var checks: int = 0
var failures: int = 0
var game
var settings

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var restarted = "--restart-probe" in OS.get_cmdline_user_args()
	settings = root.get_node("Settings")
	var sound = root.get_node("Sound")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await game.world.navigation.wait_ready()
	var images = game.png_images
	check(game.face_texture.resource_path == "res://assets/nextbot_face.jpg", "Pack uses the current enemy face")
	check(game.face_textures.size() == 3 and game.face_textures[1].get_width() > 900 and game.face_textures[2].get_height() > 900, "Pack loads all three bundled Nextbot faces")
	check(game.player.sprint_speed > 10.0 and game.player.has_method("_start_slide") and game.player.has_method("_can_stand"), "Pack includes the advanced movement controller")
	var has_stamina := false
	for property in game.player.get_property_list():
		if property.name == "stamina":
			has_stamina = true
	for control in game.ui.hud.get_children():
		if control is ProgressBar:
			has_stamina = true
	check(not has_stamina, "Pack has no stamina property or HUD gauge")
	check(sound.clips.has("slide") and sound.clips.has("wind") and sound.clips["wind"].data.size() > 100, "Pack contains generated movement sounds")
	check(game.ui.toggles.has("auto_bunnyhop") and game.ui.sliders.has("head_bob_intensity"), "Pack contains movement settings")
	check(images.current_entry().filename == ("BZ_star.png" if restarted else "Без имени.png"), "Correct PNG is selected after fresh start or restart")
	check(is_equal_approx(settings.projectile_size, 1.3), "Current projectile size is the fresh-install default")
	var seed = images.directory.path_join("Без имени.png")
	var original = "res://assets/projectiles/Без имени.png"
	check(ResourceLoader.exists(original), "Original PNG resource is included in the pack")
	check(FileAccess.get_sha256(seed) == "38811007ae70b305730a38133e2272e09d0e164545e58891812f459ca329fe6d", "Seeded PNG is byte-identical to the user's original")
	check(images.entries.size() == 4, "Fresh portable library contains all four current PNGs")
	images.select_filename("Без имени.png")
	var expected = Image.new()
	expected.load_png_from_buffer(FileAccess.get_file_as_bytes(seed))
	var actual = images.current_texture().get_image()
	actual.clear_mipmaps()
	actual.convert(Image.FORMAT_RGBA8)
	expected.convert(Image.FORMAT_RGBA8)
	check(actual.get_data() == expected.get_data(), "Throw texture preserves the original pixels")
	if not restarted:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(seed))
		images.refresh()
		check(FileAccess.file_exists(seed) and images.current_entry().filename == "Без имени.png", "Missing bundled PNG restores automatically without changing selection")
		var readonly = load("res://scripts/combat/png_image_loader.gd").new()
		readonly.refresh()
		check(readonly.entries.size() == 4 and readonly.current_entry().filename == "Без имени.png" and readonly.current_texture() != null, "Bundled PNGs remain usable with no writable image directory")
		readonly.free()
	game.start_run()
	game.spawn_timer = 9999
	await physics_frame
	var first_bot = game._spawn_bot(game.world.spawns[0] + Vector3(6, 0, 6))
	var second_bot = game._spawn_bot(game.world.spawns[0] + Vector3(12, 0, 6))
	var third_bot = game._spawn_bot(game.world.spawns[0] + Vector3(18, 0, 6))
	check(is_equal_approx(first_bot.speed, 11.4) and first_bot.agent.max_speed > first_bot.speed * 1.32, "Packed Nextbots use the faster chase and avoidance speed")
	check(first_bot.face.texture == game.face_textures[1] and second_bot.face.texture == game.face_textures[2] and third_bot.face.texture == game.face_texture, "Packed game rotates through both added photos and the original appearance")
	var shot = game.projectiles.fire()
	check(shot != null and shot.visual.texture != null, "Packed game starts and throws the bundled PNG")
	images.select_filename("BZ_star.png")
	var config = ConfigFile.new()
	check(config.load(settings.storage_path) == OK and config.get_value("settings", "selected_png", "") == "BZ_star.png", "PNG choice is saved immediately")
	print("PORTABLE TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
