extends RefCounted
## Integration checks executed by the actual engine, not mocks.
## godot --headless --path . -- --smoke-test
var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)

func run(game) -> void:
	if Settings.level_index != 0:
		game._select_map(0)
	await game.get_tree().physics_frame
	await game.get_tree().physics_frame
	await game.world.navigation.wait_ready()
	check(game.face_texture != null, "Face texture loads")
	check(game.ui.menu.visible, "Main menu is visible")
	check(game.world.tiles.size() > 200, "Full complex has more than 200 walkable tiles")
	check(game.world.navigation.polygon_count > 500, "NavigationMesh contains connected surfaces")
	var map = game.get_world_3d().navigation_map
	NavigationServer3D.map_force_update(map)
	var a = Vector3(3 * 6, 0, 14 * 6)
	var b = Vector3(3 * 6, 6, 9 * 6)
	var route = game.world.navigation.path_between(a, b)
	if "--nav-probe" in OS.get_cmdline_user_args():
		print("WEST ROUTE: ", route)
		print("NAV ITERATION: ", NavigationServer3D.map_get_iteration_id(map))
		for cell in [Vector3i(3, 0, 10), Vector3i(3, 0, 11), Vector3i(3, 0, 12), Vector3i(3, 0, 13)]:
			var p = game.world.center(cell)
			print("RAMP ", cell, " wanted ", p, " actual ", NavigationServer3D.map_get_closest_point(map, p))
	check(route.size() >= 2 and route[route.size() - 1].distance_to(b) < 1, "West staircase connects both floors")
	var east_route = game.world.navigation.path_between(Vector3(15 * 6, 0, 14 * 6), Vector3(15 * 6, 6, 9 * 6))
	if "--nav-probe" in OS.get_cmdline_user_args():
		print("EAST ROUTE: ", east_route)
	check(east_route.size() >= 2 and east_route[east_route.size() - 1].y > 5, "East staircase connects both floors")
	var reachable: int = 0
	for item in game.world.interactables:
		if item.kind == "breaker" or item.kind == "exit":
			var path = game.world.navigation.path_between(a, game.world.center(item.cell))
			if path.size() > 1 and (path[path.size() - 1] + Vector3.UP * 1.62).distance_to(item.global_position) < 3.1:
				reachable += 1
	check(reachable == 4, "All three breakers and exit are reachable")
	for kind in ["ambient", "chase", "step", "scare", "hum", "scream"]:
		check(Sound.clips.has(kind) and Sound.clips[kind].data.size() > 100, "PCM audio generated: " + kind)
	game.start_run()
	check(game.is_running() and game.player.active, "Play starts an active run")
	game.spawn_timer = 999
	game.player.reset_at(Vector3(9 * 6, 0.1, 9 * 6))
	for i in range(30):
		await game.get_tree().physics_frame
	check(game.player.is_on_floor(), "Player lands on map collision")
	var start = game.player.global_position
	Input.action_press("forward")
	for i in range(30):
		await game.get_tree().physics_frame
	Input.action_release("forward")
	check(game.player.global_position.distance_to(start) > 1.0, "WASD moves the first-person player")
	var look = InputEventMouseMotion.new()
	look.relative = Vector2(100, 20)
	game.player.view.look(look, game.player)
	check(absf(game.player.view.pitch) > 0.01, "Mouse input rotates camera")
	Input.action_press("forward")
	Input.action_press("sprint")
	for i in range(30):
		await game.get_tree().physics_frame
	Input.action_release("forward")
	Input.action_release("sprint")
	check(game.player.sprinting, "Sprint works without stamina")
	game.player.reset_at(Vector3(9 * 6, 0.1, 9 * 6))
	var bot = game._spawn_bot(Vector3(9 * 6, 0.1, 7 * 6))
	for i in range(30):
		await game.get_tree().physics_frame
	check(bot.speed > game.player.walk_speed and bot.agent.max_speed > bot.speed * 1.32, "Nextbot pursuit outruns walking and avoidance allows late-run speed")
	check(bot.state == NextbotEnemy.State.CHASE, "Nextbot detects player down corridor")
	check(game.face_textures.size() == 3 and bot.face.texture == game.face_textures[1] and bot.face.billboard != 0, "All three faces load and the first Nextbot displays its camera-facing photo")
	var initial_distance = bot.global_position.distance_to(game.player.global_position)
	for i in range(22):
		await game.get_tree().physics_frame
	check(bot.global_position.distance_to(game.player.global_position) < initial_distance - 1, "Navigation agent pursues player")
	game.pause_run()
	check(game.get_tree().paused and game.ui.pause_screen.visible, "Pause freezes run and opens pause menu")
	game.ui.open_settings("pause")
	check(game.ui.settings_screen.visible and game.ui.choices.size() == 3, "Settings controls are available")
	game.ui.apply_settings()
	game.resume_run()
	check(not game.get_tree().paused and game.player.active, "Resume restores play")
	bot.global_position = game.player.global_position + Vector3(0, 0, 0.65)
	for i in range(12):
		await game.get_tree().physics_frame
	check(game.mode == game.Mode.DYING and game.ui.jumpscare_screen.visible, "Contact triggers death and jumpscare")
	check(game.ui.scare_image.texture == bot.face.texture, "Jumpscare uses the catching Nextbot's own photo")
	await game.get_tree().create_timer(1.4).timeout
	check(game.ui.result_screen.visible, "Jumpscare fades into death screen")
	game.start_run()
	check(game.player.active and game.bots.is_empty() and game.breakers == 0, "Respawn resets the run")
	game.breakers = 3
	game._win_run()
	check(game.ui.result_title.text == "SURFACE REACHED", "Lift escape shows victory")
	print("SMOKE TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)
