extends RefCounted
## Real-engine regressions for map selection, collision, navigation and objectives.
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
	await game.get_tree().physics_frame
	check(game.ui.map_choice.item_count == 2, "Main menu lists two playable maps")
	for index in [0, 1]:
		game.return_to_menu()
		game.ui.map_choice.item_selected.emit(index)
		await game.get_tree().physics_frame
		await game.get_tree().physics_frame
		await game.world.navigation.wait_ready()
		var world = game.world
		check(world.map_id == ("complex" if index == 0 else "construct"), "Map selection loads correct world %d" % index)
		check(game.ui.map_choice.selected == index, "Menu selection matches active map %d" % index)
		check(world.spawns.size() >= 4, "Map %d has multiple spawn points" % index)
		var origin = world.spawns[0]
		var nav = game.get_world_3d().navigation_map
		check(NavigationServer3D.map_get_closest_point_owner(nav, origin) == world.navigation.get_rid(), "Map %d navigation is synchronized" % index)
		var reachable = 0
		for item in world.interactables:
			if item.kind not in ["breaker", "exit"]:
				continue
			var path = world.navigation.path_between(origin, world.center(item.cell))
			var approach_ok = path.size() > 1 and (path[path.size() - 1] + Vector3.UP * 1.62).distance_to(item.global_position) <= 3.1
			check(approach_ok, "Map %d objective reachable: %s" % [index, item.title])
			if not approach_ok:
				print("OBJECTIVE PATH: ", item.title, " goal ", world.center(item.cell), " length ", path.size(), " end ", path[path.size() - 1] if not path.is_empty() else Vector3.INF)
			if approach_ok:
				reachable += 1
		check(reachable == 4, "Map %d has all three breakers and an accessible exit" % index)
		for x in [3, 15]:
			var goal = Vector3(x * 6, 6, 9 * 6)
			var path = world.navigation.path_between(Vector3(x * 6, 0, 14 * 6), goal)
			check(path.size() > 2 and path[path.size() - 1].distance_to(goal) < 0.2, "Map %d ramp %d joins both floors" % [index, x])
		game.start_run()
		game.spawn_timer = 9999
		for spawn in world.spawns:
			game.player.reset_at(spawn)
			for frame in range(18):
				await game.get_tree().physics_frame
			check(game.player.is_on_floor(), "Map %d spawn has solid ground: %s" % [index, str(spawn)])
		if index == 1:
			await _test_construct(game)
		else:
			game.return_to_menu()
	# Switching back must restore the original world and keep records separate.
	game.ui.map_choice.item_selected.emit(0)
	await game.get_tree().physics_frame
	await game.world.navigation.wait_ready()
	check(game.world.map_id == "complex", "Returning to underground rebuilds original level")
	Settings.best = [11.0, 22.0, 33.0]
	Settings.construct_best = [44.0, 55.0, 66.0]
	check(Settings.best_for_map(0, 1) == 22.0 and Settings.best_for_map(1, 1) == 55.0, "Survival records are separate for both maps")
	Settings.save()
	var config = ConfigFile.new()
	check(config.load(Settings.storage_path) == OK and config.get_value("settings", "level_index", -1) == 0, "Map preference persists in settings")
	print("MAP TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)

func _test_construct(game) -> void:
	var world = game.world
	check(world.tiles.size() > 450, "Construct includes a large yard and full rooftop")
	check(world.sun != null and world.sun.light_energy > 0, "Construct has daylight and sky")
	check(world.has_node("ShallowReflectingPool"), "Construct contains the walkable reflecting pool")
	check(world.zone_at(Vector3(12, 0, 30)) == "THE DARK ROOM", "Construct includes the darkroom")
	check(world.zone_at(Vector3(108, 0, 30)) == "WHITE CHAMBER", "Construct includes the white chamber")
	game.player.reset_at(Vector3(60, 0.1, 84))
	var bot = game._spawn_bot(Vector3(60, 0.1, 100))
	for frame in range(35):
		await game.get_tree().physics_frame
	check(bot.state == NextbotEnemy.State.CHASE, "Nextbot sees player in Construct courtyard")
	var distance = bot.global_position.distance_to(game.player.global_position)
	for frame in range(35):
		await game.get_tree().physics_frame
	check(bot.global_position.distance_to(game.player.global_position) < distance - 4, "Fast Nextbot closes distance across Construct lawn")
	game._clear_bots()
	await game.get_tree().physics_frame
	# Physical ramp traversal exercises more than a NavigationMesh query.
	game.player.reset_at(Vector3(18, 0.1, 84))
	game.player.rotation.y = 0
	Input.action_press("forward")
	Input.action_press("sprint")
	for frame in range(245):
		await game.get_tree().physics_frame
	Input.action_release("forward")
	Input.action_release("sprint")
	check(game.player.global_position.y > 5.8, "Player can run up Construct ramp onto rooftop")
	game.player.reset_at(Vector3(60, 0.1, 84))
	var ascending = game._spawn_bot(Vector3(18, 0.1, 84))
	await game.get_tree().physics_frame
	await game.get_tree().physics_frame
	ascending.detection_range = 0.0
	ascending.state = NextbotEnemy.State.SEARCH
	ascending.state_time = 0.0
	ascending.search_steps = 100
	ascending.speed = 9.0
	ascending._set_target(Vector3(18, 6, 52))
	for frame in range(430):
		await game.get_tree().physics_frame
	check(ascending.global_position.y > 5.5, "Nextbot physically follows ramp onto Construct rooftop")
	game._clear_bots()
	await game.get_tree().physics_frame
	for item in world.interactables:
		if item.kind == "breaker":
			game.focused_item = item
			game._interact()
	check(game.breakers == 3, "All three Construct breakers activate")
	for item in world.interactables:
		if item.kind == "exit":
			game.focused_item = item
			game._interact()
	for frame in range(120):
		await game.get_tree().process_frame
		if game.current_level == 2 and game.mode == game.Mode.PLAYING:
			break
	check(game.current_level == 2 and game.mode == game.Mode.PLAYING and game.world == world, "Construct gate advances to authored Level 2")
	game.start_run()
	game.spawn_timer = 9999
	game.kill_player(null)
	await game.get_tree().create_timer(1.3).timeout
	check(game.ui.result_title.text == "РОССИЯ ПУТИН ПОБЕДА", "Custom death text remains on Construct")
	game.start_run()
	check(game.world == world and game.breakers == 0 and game.player.active, "Construct respawn keeps the selected map and resets objectives")
	game.return_to_menu()
