extends RefCounted
## Verifies the three built-in school items and their exclusive face weaknesses.
const ThrowableItems = preload("res://scripts/combat/throwable_item_registry.gd")

var checks: int = 0
var failures: Array[String] = []
var game

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func frames(count: int) -> void:
	for frame in range(count):
		await game.get_tree().physics_frame

func run(root) -> void:
	game = root
	if Settings.level_index != 1:
		game._select_map(1)
	await game.world.navigation.wait_ready()
	game.start_run()
	game.spawn_timer = 9999
	game.player.reset_at(Vector3(60, 0.1, 84))
	await frames(6)

	var images = game.png_images
	var expected := {
		"BZ_test_tube.png": ThrowableItems.TEST_TUBE,
		"BZ_literature_book.png": ThrowableItems.LITERATURE_BOOK,
		"BZ_constitution.png": ThrowableItems.CONSTITUTION,
	}
	for filename in expected:
		images.select_filename(filename)
		var entry: Dictionary = images.current_entry()
		check(entry.filename == filename, "%s is seeded into the projectile library" % filename)
		check(images.current_item_kind() == expected[filename], "%s retains its gameplay item type" % filename)
		check(images.current_texture() != null and images.current_texture().get_image().get_pixel(0, 0).a < 0.01, "%s keeps a transparent background" % filename)

	var black_white = game._spawn_bot(Vector3(54, 0.1, 96), {"face_variant": 0, "respawn_delay": 9999.0})
	var elena = game._spawn_bot(Vector3(60, 0.1, 96), {"face_variant": 1, "respawn_delay": 9999.0})
	var kogan = game._spawn_bot(Vector3(66, 0.1, 96), {"face_variant": 2, "respawn_delay": 9999.0})
	await frames(5)
	for bot in [black_white, elena, kogan]:
		bot.enabled = false

	check(ThrowableItems.required_kind(black_white) == ThrowableItems.CONSTITUTION, "Black-and-white Nextbot requires the Constitution")
	check(ThrowableItems.required_kind(elena) == ThrowableItems.TEST_TUBE, "Elena Finkelshteyn requires the test tube")
	check(ThrowableItems.required_kind(kogan) == ThrowableItems.LITERATURE_BOOK, "Pink-background Kogan requires the literature textbook")

	_hit(elena, ThrowableItems.LITERATURE_BOOK, 100.0)
	_hit(kogan, ThrowableItems.CONSTITUTION, 100.0)
	_hit(black_white, ThrowableItems.TEST_TUBE, 100.0)
	await frames(2)
	check(elena.combat.health.current_health == 100.0, "Wrong textbook cannot damage Elena")
	check(kogan.combat.health.current_health == 100.0, "Wrong Constitution cannot damage Kogan")
	check(black_white.combat.health.current_health == 100.0, "Wrong test tube cannot damage the black-and-white Nextbot")

	_hit(elena, ThrowableItems.TEST_TUBE, 100.0)
	_hit(kogan, ThrowableItems.LITERATURE_BOOK, 100.0)
	_hit(black_white, ThrowableItems.CONSTITUTION, 100.0)
	await frames(2)
	check(elena.combat.health.dead, "Test tube kills Elena Finkelshteyn")
	check(kogan.combat.health.dead, "Literature textbook kills pink-background Kogan")
	check(black_white.combat.health.dead, "Constitution kills the black-and-white Nextbot")
	check(game.kill_count == 3, "Three matching items award exactly three kills")

	var custom = game._spawn_bot(Vector3(60, 0.1, 102), {"custom_face": game.face_textures[1], "face_variant": 1})
	await frames(2)
	check(ThrowableItems.can_damage(custom, ThrowableItems.STANDARD), "Sandbox custom faces remain vulnerable to ordinary PNGs")
	game.return_to_menu()
	print("THROWABLE ITEMS TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)

func _hit(bot: NextbotEnemy, item_kind: String, damage: float) -> void:
	var projectile = game.projectiles.launch(game.png_images.current_texture(), bot.global_position - Vector3.FORWARD, Vector3.FORWARD, game.player, false, {}, 1.0, item_kind)
	projectile.damage = damage
	projectile.set_physics_process(false)
	projectile._impact({"collider": bot, "position": bot.global_position + Vector3.UP, "normal": Vector3.BACK})
