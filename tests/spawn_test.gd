extends RefCounted
## Spawning + lever-policy regression coverage for the original four modes;
## Bossfight progression and spawning have a dedicated integration suite.
## Exercises fresh-world navigation synchronization (no explicit wait_ready),
## wave integrity, manual Sandbox spawning, mode switching and the
## mode-aware breaker/exit policy including the Blackout exception.

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

func _count_active(interactables: Array, kind: String) -> int:
	var total: int = 0
	for item in interactables:
		if item.kind == kind and item.active:
			total += 1
	return total

func _any_active(interactables: Array, kind: String) -> bool:
	for item in interactables:
		if item.kind == kind and item.active:
			return true
	return false

func run(game) -> void:
	# --- Arcade: 5 fresh launches must each synchronise navigation and spawn. ---
	for attempt in range(5):
		game._select_game_mode(GameModeManager.GameplayMode.ARCADE)
		game.gameplay_config.arcade_round_seconds = 30.0
		game.start_run()
		game.spawn_timer = 0.0
		for frame in range(60):
			await game.get_tree().physics_frame
			if game.bots.size() > 0:
				break
		check(game.world.navigation.synchronized, "Arcade launch %d synchronises navigation" % (attempt + 1))
		check(game.bots.size() > 0, "Arcade launch %d spawns its opening Nextbot" % (attempt + 1))
		check(not _any_active(game.world.interactables, "breaker"), "Arcade launch %d hides progression breakers" % (attempt + 1))
		check(not _any_active(game.world.interactables, "exit"), "Arcade launch %d hides the exit switch" % (attempt + 1))
		await frames(game, 8)
		for bot in game.bots:
			check(bot.is_on_floor(), "Arcade launch %d Nextbot stands on solid floor (not inside geometry)" % (attempt + 1))
			break
		game.return_to_menu()
		await frames(game, 2)

	# --- Arcade round rollover: a second round on a rotated map still spawns. ---
	game.game_modes.arcade_round = 0
	game._select_game_mode(GameModeManager.GameplayMode.ARCADE)
	game.gameplay_config.arcade_round_seconds = 0.4
	game.start_run()
	await frames(game, 3)
	var round_before: int = game.game_modes.arcade_round
	check(round_before >= 1, "Arcade round is active before rollover (round=%d)" % round_before)
	game.gameplay_config.arcade_round_seconds = 0.4
	await frames(game, 40)
	check(game.game_modes.arcade_round > round_before or game.mode == game.Mode.RESULT, "Arcade rolls into a new round via the timer")
	game.gameplay_config.arcade_round_seconds = 300.0
	game._clear_bots()
	game.return_to_menu()
	await frames(game, 2)

	# --- PNG Mayhem: 5 fresh launches each begin a bounded wave. ---
	for attempt in range(5):
		game._select_game_mode(GameModeManager.GameplayMode.PNG_MAYHEM)
		game.start_run()
		for frame in range(60):
			await game.get_tree().physics_frame
			if game.game_modes.mayhem_wave > 0:
				break
		check(game.world.navigation.synchronized, "Mayhem launch %d synchronises navigation" % (attempt + 1))
		check(game.game_modes.mayhem_wave > 0 and game.bots.size() > 0, "Mayhem launch %d begins wave %d with enemies" % [(attempt + 1), game.game_modes.mayhem_wave])
		check(not _any_active(game.world.interactables, "breaker"), "Mayhem launch %d hides progression breakers" % (attempt + 1))
		check(not _any_active(game.world.interactables, "exit"), "Mayhem launch %d hides the exit switch" % (attempt + 1))
		game.return_to_menu()
		await frames(game, 2)

	# --- Mayhem: clear three consecutive waves by killing every enemy. ---
	game._select_game_mode(GameModeManager.GameplayMode.PNG_MAYHEM)
	game.start_run()
	var waves_cleared: int = 0
	for wave in range(3):
		for frame in range(120):
			await game.get_tree().physics_frame
			if game.game_modes.mayhem_wave > wave:
				break
		while game.bots.size() > 0 and not game.game_modes.mayhem_waiting_for_upgrade:
			# Kill every enemy in the current wave; the next wave must start.
			for bot in game.bots.duplicate():
				if is_instance_valid(bot):
					game.damage_system.apply_hit(bot, 100000.0, game.player, bot.global_position + Vector3.UP, Vector3.FORWARD)
			await frames(game, 6)
		# Either an upgrade screen (non-boss waves) or the boss wave just cleared.
		if game.game_modes.mayhem_waiting_for_upgrade:
			game.game_modes.choose_upgrade(0)
			await frames(game, 4)
		waves_cleared += 1
	check(waves_cleared >= 3, "Mayhem clears three consecutive waves without stalling (cleared %d)" % waves_cleared)
	check(game.game_modes.mayhem_wave >= 3, "Mayhem reaches at least wave 3 after three clears (wave=%d)" % game.game_modes.mayhem_wave)
	game._clear_bots()
	game.return_to_menu()
	await frames(game, 2)

	# --- Sandbox: manual spawn of 10 Nextbots, remove them, then spawn again. ---
	game._select_game_mode(GameModeManager.GameplayMode.SANDBOX)
	game.start_run()
	game.game_modes.sandbox_action("ai", false)
	game.game_modes.sandbox_action("count", 10)
	game.game_modes.sandbox_action("spawn")
	await frames(game, 6)
	check(game.bots.size() == 10, "Sandbox manual spawn creates ten Nextbots in one batch (got %d)" % game.bots.size())
	for bot in game.bots:
		# Sandbox bots with AI disabled don't run move_and_slide, so verify
		# the spawn is clear of walls (not inside geometry) instead of floor.
		var spawn_clear = game.world.navigation_clear(AABB(bot.global_position + Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.8, 1.0)))
		check(spawn_clear, "Sandbox Nextbot spawns in a collision-cleared position (not inside geometry)")
		check(not bot.enabled, "Sandbox AI toggle keeps the ten manual Nextbots disabled")
		break
	check(not _any_active(game.world.interactables, "breaker") and not _any_active(game.world.interactables, "exit"), "Sandbox hides progression levers")
	game.game_modes.sandbox_action("remove")
	await frames(game, 3)
	check(game.bots.is_empty(), "Sandbox remove clears all ten manual Nextbots")
	game.game_modes.sandbox_action("count", 10)
	game.game_modes.sandbox_action("spawn")
	await frames(game, 8)
	check(game.bots.size() == 10, "Sandbox respawns ten Nextbots after a full remove (got %d)" % game.bots.size())
	game._clear_bots()
	game.return_to_menu()
	await frames(game, 2)

	# --- Endless: original behaviour preserved; breakers + exit active. ---
	game._select_game_mode(GameModeManager.GameplayMode.ENDLESS)
	game.start_run()
	game.spawn_timer = 0.0
	await frames(game, 40)
	check(game.world.navigation.synchronized, "Endless synchronises navigation")
	check(game.bots.size() > 0, "Endless spawns its opening Nextbot")
	check(_count_active(game.world.interactables, "breaker") == 3, "Endless keeps three breakers active for progression (got %d)" % _count_active(game.world.interactables, "breaker"))
	check(_any_active(game.world.interactables, "exit"), "Endless keeps the exit switch active")
	game._clear_bots()
	game.return_to_menu()
	await frames(game, 2)

	# --- Mode switching loop: no mode must break enemy spawning afterwards. ---
	for cycle in range(3):
		for mode in [GameModeManager.GameplayMode.ARCADE, GameModeManager.GameplayMode.PNG_MAYHEM, GameModeManager.GameplayMode.SANDBOX, GameModeManager.GameplayMode.ENDLESS]:
			game._select_game_mode(mode)
			game.start_run()
			game.spawn_timer = 0.0
			await frames(game, 20)
			if mode == GameModeManager.GameplayMode.SANDBOX:
				game.game_modes.sandbox_action("count", 2)
				game.game_modes.sandbox_action("spawn")
				await frames(game, 6)
				check(game.bots.size() == 2, "Mode-switch cycle %d Sandbox spawns after switching from other modes" % (cycle + 1))
			else:
				check(game.world.navigation.synchronized, "Mode-switch cycle %d keeps navigation synchronised on %s" % [(cycle + 1), game.game_modes.mode_name()])
			game.return_to_menu()
			await frames(game, 2)

	# --- No duplicate enemies from overlapping spawn timers: stay under the cap. ---
	game._select_game_mode(GameModeManager.GameplayMode.ENDLESS)
	game.start_run()
	game.spawn_timer = 0.0
	await frames(game, 30)
	check(game.bots.size() <= game.maximum_active_bots(), "No duplicate over-spawn beyond the mode cap (bots=%d cap=%d)" % [game.bots.size(), game.maximum_active_bots()])
	game._clear_bots()
	game.return_to_menu()
	await frames(game, 3)

	# --- Blackout re-enables breakers even in non-Endless modes, then hides them again. ---
	game._select_game_mode(GameModeManager.GameplayMode.ARCADE)
	game.start_run()
	var breakers_before = _count_active(game.world.interactables, "breaker")
	check(breakers_before == 0, "Arcade starts with no active progression breakers (got %d)" % breakers_before)
	game.events.request_event("BLACKOUT")
	check(game.events.pending_event == "BLACKOUT", "Blackout event request is accepted")
	game.events.warning_remaining = 0.0
	game.events.tick(0.01)
	await frames(game, 4)
	check(game.events.active_event == "BLACKOUT", "Blackout becomes the active event")
	check(_count_active(game.world.interactables, "breaker") == 3, "Blackout re-enables the three breaker switches (got %d)" % _count_active(game.world.interactables, "breaker"))
	game.events.end_event()
	await frames(game, 3)
	check(game.events.active_event.is_empty(), "Blackout ends cleanly")
	check(_count_active(game.world.interactables, "breaker") == 0, "Breakers hide again after Blackout ends in Arcade (got %d)" % _count_active(game.world.interactables, "breaker"))
	game.return_to_menu()
	await frames(game, 3)

	print("SPAWN TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)
