extends RefCounted
## Full-cycle integration coverage for the dedicated Bossfight mode and maps.
var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func frames(game, count: int) -> void:
	for index in range(count):
		await game.get_tree().physics_frame

func wait_for_level(game, level: int) -> bool:
	for frame in range(900):
		if game.current_level == level and game.mode == game.Mode.PLAYING and not game.transition_in_progress:
			return true
		await game.get_tree().physics_frame
	return false

func wait_for_boss(game) -> NextbotEnemy:
	for frame in range(600):
		if is_instance_valid(game.game_modes.active_boss):
			return game.game_modes.active_boss
		await game.get_tree().physics_frame
	return null

func stage_objectives(game) -> Array[WorldInteractable]:
	var result: Array[WorldInteractable] = []
	for item in game.world.interactables:
		if item.kind in ["breaker", "exit"]:
			result.append(item)
	return result

func validate_stage(game, expected_level: int) -> String:
	check(game.world is BossfightWorld and not game.world.arena_mode, "Bossfight Level %d uses the dedicated Dust Quarter map" % expected_level)
	check(game.world.map_id == "bossfight_mirage" and game.world.tiles.size() > 260, "Dust Quarter is a large authored desert layout")
	var objectives := stage_objectives(game)
	check(objectives.size() == 4, "Level %d has three randomized switches and one exit" % expected_level)
	var reachable := 0
	var origin: Vector3 = game.world.spawns[0]
	for item in objectives:
		var path: PackedVector3Array = game.world.navigation.path_between(origin, game.world.center(item.cell))
		if path.size() > 1 and path[path.size() - 1].distance_to(game.world.center(item.cell)) < 0.3:
			reachable += 1
	check(reachable == objectives.size(), "Every Level %d objective is reachable through navigation" % expected_level)
	return game.world.objective_signature

func complete_stage(game, next_level: int) -> bool:
	game.spawn_timer = 9999.0
	game._clear_bots()
	for item in game.world.interactables:
		if item.kind == "breaker":
			game.focused_item = item
			game._interact()
	check(game.breakers == 3, "All three randomized switches activate")
	for item in game.world.interactables:
		if item.kind == "exit":
			game.focused_item = item
			game._interact()
			break
	var arrived := await wait_for_level(game, next_level)
	check(arrived, "Sun Gate advances to Level %d" % next_level)
	if arrived:
		game.spawn_timer = 9999.0
		for bot in game.bots:
			bot.enabled = false
	return arrived

func run(game) -> void:
	await frames(game, 2)
	check(game.ui.mode_choice.item_count == 5, "Main menu exposes Bossfight as the fifth mode")
	game._select_game_mode(GameModeManager.GameplayMode.BOSSFIGHT)
	check(game.ui.map_choice.disabled, "Authored-map selector is disabled because Bossfight owns its maps")
	game.start_run(false, 1, 13001)
	game.progression_root_seed = 424242
	game.spawn_timer = 9999.0
	await game.world.navigation.wait_ready()
	var signatures: Array[String] = []
	signatures.append(validate_stage(game, 1))
	if not await complete_stage(game, 2):
		await finish(game)
		return
	await game.world.navigation.wait_ready()
	signatures.append(validate_stage(game, 2))
	if not await complete_stage(game, 3):
		await finish(game)
		return
	await game.world.navigation.wait_ready()
	signatures.append(validate_stage(game, 3))
	check(signatures[0] != signatures[1] and signatures[1] != signatures[2], "Switch positions are rerolled between the three desert levels")
	if not await complete_stage(game, 4):
		await finish(game)
		return
	await game.world.navigation.wait_ready()
	check(game.world is BossfightWorld and game.world.arena_mode and game.world.map_id == "bossfight_arena", "Level 4 replaces the district with the open Sun Ring arena")
	check(game.world.tiles.size() > 300 and stage_objectives(game).is_empty(), "Boss arena is large, open and has no switch objective")
	var boss := await wait_for_boss(game)
	check(is_instance_valid(boss), "Level 4 automatically spawns its boss")
	if not is_instance_valid(boss):
		await finish(game)
		return
	boss.enabled = false
	check(boss.max_health == 4000.0 and boss.combat.health.current_health == 4000.0, "First Bossfight boss starts with exactly 4000 HP")
	check(boss.face.texture == GameModeManager.BOSSFIGHT_IDLE_FACE and boss.attack_face == GameModeManager.BOSSFIGHT_ATTACK_FACE, "Boss uses the supplied calm and attacking photographs")
	boss._change_state(NextbotEnemy.State.ATTACK)
	check(boss.face.texture == GameModeManager.BOSSFIGHT_ATTACK_FACE, "Boss switches to the aggressive photograph while attacking")
	boss._change_state(NextbotEnemy.State.CHASE)
	check(boss.face.texture == GameModeManager.BOSSFIGHT_IDLE_FACE, "Boss restores its normal photograph outside an attack")
	boss.combat.health.apply_damage(4000.0, game.player, boss.global_position)
	check(await wait_for_level(game, 5), "Defeating the boss automatically opens the next three-level cycle")
	await game.world.navigation.wait_ready()
	game.spawn_timer = 9999.0
	check(game.game_modes.bossfight_difficulty_tier() == 1 and game.world is BossfightWorld and not game.world.arena_mode, "Level 5 returns to Dust Quarter at difficulty tier 1")
	game._clear_bots()
	var stronger: NextbotEnemy = game._spawn_bot(game.world.patrol_points[0])
	await frames(game, 3)
	if is_instance_valid(stronger):
		stronger.enabled = false
	check(is_instance_valid(stronger) and stronger.max_health == 125.0, "Ordinary Nextbots gain health after a boss victory")
	check(is_instance_valid(stronger) and stronger.speed > [9.0, 11.4, 13.6][game.run_difficulty], "Ordinary Nextbots gain speed after a boss victory")
	await game._transition_to_level(8, game._seed_for_level(8), false)
	var second_boss := await wait_for_boss(game)
	check(game.world is BossfightWorld and game.world.arena_mode, "The arena repeats on Level 8")
	check(is_instance_valid(second_boss) and second_boss.max_health == 4500.0, "Second boss gains the configured 500 HP")
	if is_instance_valid(second_boss):
		second_boss.enabled = false
	await finish(game)

func finish(game) -> void:
	game._clear_bots()
	await frames(game, 3)
	print("BOSSFIGHT TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)
