extends RefCounted
## Fifty-seed structural validation plus an in-engine navigation/transition pass.

var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func run(game) -> void:
	print("PROCEDURAL TEST: starting fifty deterministic layouts")
	var config: ProceduralGenerationConfig = preload("res://resources/procedural_generation.tres")
	var generator = ProceduralLayoutGenerator.new()
	var signatures: Dictionary = {}
	var loop_layouts: int = 0
	var seen_types: Dictionary = {}
	for index in range(50):
		var level = 4 + index % 9
		var seed_value = 810013 + index * 7919
		var expected = config.room_count_for_level(level)
		var layout = generator.generate(seed_value, expected, config, level)
		check(layout.valid, "Seed %d produces a valid layout" % seed_value)
		check(int(layout.room_count) == expected, "Seed %d reaches its configured room count" % seed_value)
		check(layout.distances.size() == layout.rooms.size(), "Seed %d has one connected room graph" % seed_value)
		check(int(layout.exit_graph_distance) >= mini(config.minimum_exit_graph_distance, maxi(2, expected / 3)), "Seed %d puts the exit far from spawn" % seed_value)
		var tile_total: int = 0
		for room in layout.rooms:
			tile_total += room.tiles.size()
			seen_types[room.type] = true
		if layout.links.size() >= layout.rooms.size():
			loop_layouts += 1
		check(tile_total == layout.tiles.size(), "Seed %d has no overlapping room tiles" % seed_value)
		var aligned: bool = true
		for link in layout.links:
			aligned = aligned and link.a_cell.distance_squared_to(link.b_cell) == 1
		check(aligned, "Seed %d aligns every connected doorway" % seed_value)
		var cells: Array = layout.tiles.keys()
		cells.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
		var signature = str(cells) + str(layout.rooms.map(func(room): return room.type))
		signatures[signature] = true
	check(signatures.size() >= 48, "Different deterministic seeds create different layouts")
	check(loop_layouts >= 1, "Generated room graphs occasionally contain loops")
	check(seen_types.has("dead_end") and seen_types.has("rare_special"), "Room selection includes dead ends and rare special rooms")
	check(is_equal_approx(config.lighting_for_level(4), 0.8) and is_equal_approx(config.lighting_for_level(10), 0.1), "Lighting progression follows configured Level 4 and Level 10 targets")
	check(is_equal_approx(config.speed_for_level(4), 1.1) and is_equal_approx(config.speed_for_level(10), 1.7) and config.speed_for_level(30) <= config.nextbot_speed_cap_multiplier, "Nextbot scaling uses early targets and a late cap")
	game.start_run()
	game.spawn_timer = 9999.0
	await game.world.navigation.wait_ready()
	var authored_world = game.world
	var level_two_ok: bool = await game._transition_to_level(2, 0, false, true)
	check(level_two_ok and game.world == authored_world and game.current_level == 2, "Level 2 preserves the selected authored map")
	var level_three_ok: bool = await game._transition_to_level(3, 0, false, true)
	check(level_three_ok and game.world == authored_world and game.current_level == 3, "Level 3 preserves the selected authored map")
	var transition_ok: bool = await game._transition_to_level(4, 424242, false, true)
	check(transition_ok and game.world is ProceduralLevelWorld, "Level 4 transition installs a procedural world after navigation synchronization")
	check(game.current_level == 4 and game.current_generation_seed == 424242, "Transition exposes the current level and deterministic seed")
	check(game.world.generated_room_count == config.room_count_for_level(4), "Level 4 builds fifteen modular rooms")
	check(game.world.generation_validation == "VALID" and game.world.navigation_status == "READY", "Generated world reports successful layout and navigation validation")
	var exit_item: WorldInteractable
	for item in game.world.interactables:
		if item.kind == "exit":
			exit_item = item
			break
	var path = game.world.navigation.path_between(game.player.global_position, game.world.center(exit_item.cell))
	check(path.size() > 1 and path[path.size() - 1].distance_to(game.world.center(exit_item.cell)) < 2.0, "Navigation reaches the procedural exit across room boundaries")
	for frame in range(12):
		await game.get_tree().physics_frame
	check(game.player.is_on_floor(), "Procedural spawn is above solid floor and outside walls")
	var first_layout = game.world
	var second_ok: bool = await game._transition_to_level(5, 525252, false, true)
	await game.get_tree().process_frame
	check(second_ok and game.world != first_layout and game.world.generated_room_count == config.room_count_for_level(5), "Level 5 cleans up and replaces the previous procedural map")
	check(not game.projectiles.projectiles.size() and game.mode == game.Mode.PLAYING and game.player.active, "Transition clears projectiles and restores player control only after loading")
	var test_bot = game._spawn_bot(game.world.far_point(game.player.global_position, 24.0))
	await game.get_tree().physics_frame
	var before: float = test_bot.combat.health.current_health
	game.damage_system.apply_hit(test_bot, 20.0, game.player, test_bot.global_position + Vector3.UP, Vector3.FORWARD)
	check(test_bot.combat.health.current_health == before - 20.0, "PNG damage pipeline remains active on generated maps")
	check(Settings.highest_level >= 5, "Highest reached level is persisted")
	game._clear_bots()
	game.return_to_menu()
	await game.get_tree().process_frame
	await game.get_tree().process_frame
	print("PROCEDURAL TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)
