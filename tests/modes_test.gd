extends RefCounted
## Engine-level coverage for the mode/event/statistics framework.

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
		await game.get_tree().process_frame

func run(game) -> void:
	await game.get_tree().physics_frame
	check(game.ui.mode_choice.item_count == 5, "Main menu exposes all five game modes")
	game._select_game_mode(GameModeManager.GameplayMode.ENDLESS)
	check(game.game_modes.selected == GameModeManager.GameplayMode.ENDLESS, "Endless remains the safe default mode")
	check(game.statistics.data.has("bosses_defeated"), "Persistent statistics schema is loaded")

	# Arcade: short configured round exercises timer, score, results and local board.
	game._select_game_mode(GameModeManager.GameplayMode.ARCADE)
	game.gameplay_config.arcade_round_seconds = 0.70
	game.start_run()
	check(game.game_modes.mode_name() == "ARCADE" and game.game_modes.uses_standard_spawner(), "Arcade starts through the existing run coordinator")
	await game.world.navigation.wait_ready()
	game.spawn_timer = 0.0
	await frames(game, 3)
	check(game.bots.size() > 0, "Arcade automatically spawns its opening Nextbot")
	await game.get_tree().create_timer(0.82).timeout
	await frames(game, 3)
	check(game.mode == game.Mode.RESULT, "Arcade round ends when its survival timer expires")
	check(game.game_modes.session_leaderboard.size() == 1 and game.game_modes.session_leaderboard[0].score > 0, "Arcade records score in the local session leaderboard")
	check(int(game.statistics.value("highest_arcade_score")) > 0, "Arcade personal record persists through statistics manager")

	# Endless policy stays attached to the already-tested authored/procedural path.
	game.return_to_menu()
	game._select_game_mode(GameModeManager.GameplayMode.ENDLESS)
	game.start_run()
	check(game.game_modes.can_advance_level() and game.current_level == 1, "Endless owns level progression from Level 1")
	check(game.game_modes.objective_text().contains("BREAKERS"), "Endless HUD retains the authored objective")
	game._clear_bots()
	game.spawn_timer = 0.0
	await frames(game, 3)
	check(game.bots.size() > 0, "Endless automatically retries and spawns its opening Nextbot")
	for index in range(3):
		await game.get_tree().physics_frame

	# Mayhem: spawn a wave, kill each independent health component, then pick a modifier.
	game.return_to_menu()
	game._select_game_mode(GameModeManager.GameplayMode.PNG_MAYHEM)
	game.start_run()
	await game.world.navigation.wait_ready()
	game.game_modes.mayhem_next_wave_delay = 0.0
	game.game_modes.mayhem_wave_pending = true
	game.world.navigation.synchronized = false
	game.game_modes._tick_mayhem(0.1)
	check(game.game_modes.mayhem_wave == 0 and game.game_modes.mayhem_wave_pending, "Mayhem keeps an expired wave request while navigation is loading")
	game.world.navigation.synchronized = true
	game.game_modes._tick_mayhem(0.1)
	for index in range(3):
		await game.get_tree().physics_frame
	check(game.game_modes.mayhem_wave == 1 and game.bots.size() == game.gameplay_config.mayhem_base_wave_size, "PNG Mayhem spawns its first bounded wave")
	var wave_bots = game.bots.duplicate()
	for bot in wave_bots:
		game.damage_system.apply_hit(bot, 10000.0, game.player, bot.global_position + Vector3.UP, Vector3.FORWARD)
	await frames(game, 3)
	check(game.game_modes.mayhem_waiting_for_upgrade and game.ui.upgrade_screen.visible, "Clearing a Mayhem wave opens three upgrade choices")
	check(game.game_modes.offered_upgrades.size() == 3, "Mayhem upgrade selection is randomized from reusable definitions")
	game.game_modes.choose_upgrade(0)
	check(game.game_modes.modifiers.acquired.size() == 1 and game.player.active, "Selected Mayhem modifier applies and resumes combat")
	game._clear_bots()
	game.game_modes.mayhem_wave = game.gameplay_config.mayhem_boss_interval - 1
	game.game_modes._start_mayhem_wave()
	for index in range(3):
		await game.get_tree().physics_frame
	check(is_instance_valid(game.game_modes.active_boss) and game.game_modes.active_boss.max_health == game.gameplay_config.boss_health, "Configured 10,000 HP boss wave is fightable through normal health")
	check(game.game_modes.active_boss.is_boss and game.game_modes.active_boss.face_scale > 1.0, "Boss has phased controller flags and a larger PNG face")

	# Sandbox: selected PNG face, live stats, AI and invincibility without restarting.
	game.return_to_menu()
	game._select_game_mode(GameModeManager.GameplayMode.SANDBOX)
	game.start_run()
	game.game_modes.sandbox_action("count", 2)
	game.game_modes.sandbox_action("health", 321.0)
	game.game_modes.sandbox_action("ai", false)
	game.game_modes.sandbox_action("spawn")
	for index in range(3):
		await game.get_tree().physics_frame
	check(game.bots.size() == 2, "Sandbox spawns the configured count without a restart")
	check(game.bots[0].max_health == 321.0 and game.bots[0].custom_face == game.png_images.current_texture(), "Sandbox uses live HP and selected custom PNG face")
	check(not game.bots[0].enabled, "Sandbox AI toggle applies to newly spawned Nextbots")
	game.kill_player(game.bots[0])
	check(game.mode == game.Mode.PLAYING and game.player.active, "Sandbox invincibility prevents a lethal catch")
	var original_light = game.world.all_lights[0].light_energy
	game.game_modes.sandbox_action("lighting", 0.5)
	check(game.world.all_lights[0].light_energy < original_light, "Sandbox lighting control updates environmental lights live")
	check(game.ui.sandbox_controls.has("auto_spawn"), "Sandbox tools expose an explicit automatic-spawn control")
	game._clear_bots()
	game.game_modes.sandbox_action("count", 2)
	game.game_modes.sandbox_action("auto_spawn_limit", 3)
	game.game_modes.sandbox_action("auto_spawn_interval", 0.5)
	game.game_modes.sandbox_action("auto_spawn", true)
	game.game_modes.sandbox_spawn_timer = 0.0
	game.game_modes._tick_sandbox(0.1)
	check(game.bots.size() == 2, "Sandbox auto-spawn creates the configured batch")
	game.game_modes.sandbox_spawn_timer = 0.0
	game.game_modes._tick_sandbox(0.1)
	check(game.bots.size() == 3, "Sandbox auto-spawn obeys its active-enemy limit")
	game.game_modes.sandbox_action("auto_spawn", false)
	for index in range(3):
		await game.get_tree().physics_frame
	game.game_modes.sandbox_action("reward")
	await game.get_tree().physics_frame
	check(game.post_boss.state == PostBossRewardController.RewardState.REWARD_SELECTION and game.post_boss.choices.size() == 2, "Sandbox can manually spawn and reset the two-hand reward NPC")
	check(not is_instance_valid(game.post_boss.lever), "Sandbox reward testing never creates a progression lever")
	game.post_boss._finalize_authoritative(1)
	check(game.post_boss.winner == 1 and not is_instance_valid(game.post_boss.lever), "Sandbox can test the right reward without forcing progression")
	game.post_boss.reset_run()

	# Every event can start, advertises one active owner and restores its changes.
	game._clear_bots()
	var baseline_energy = game.world.all_lights[0].light_energy
	for event_name in RandomEventManager.EVENT_NAMES:
		check(game.events.request_event(event_name), "%s accepts a manual Sandbox trigger" % event_name)
		game.events.warning_remaining = 0.0
		game.events.tick(0.01)
		for index in range(3):
			await game.get_tree().physics_frame
		check(game.events.active_event == event_name, "%s starts after its warning" % event_name)
		if event_name == "BLACKOUT":
			check(game.world.all_lights[0].light_energy != baseline_energy, "Blackout changes actual light energy")
		elif event_name == "BLOODMOON":
			check(game.world.env.environment.fog_light_color.r > game.world.env.environment.fog_light_color.g, "Bloodmoon installs red fog")
		elif event_name == "ANGRY NEXTBOT":
			check(not game.events.event_bots.is_empty() and game.events.event_bots[0].angry_observation, "Angry Nextbot uses observation-angle behavior")
		elif event_name == "BOSS INVASION":
			check(is_instance_valid(game.game_modes.active_boss), "Boss Invasion publishes boss HUD target")
		game.events.end_event()
		for index in range(2):
			await game.get_tree().physics_frame
		check(game.events.active_event.is_empty() and game.events.pending_event.is_empty(), "%s cleans up completely" % event_name)
	check(is_equal_approx(game.world.all_lights[0].light_energy, baseline_energy), "Event cleanup restores pre-event lighting")

	# Modifiers are composable data, and the weapon consumes one profile.
	var modifier = GameplayModifierSet.new()
	for upgrade in ["damage", "rapid", "double", "explosive", "freezing", "piercing", "ricochet", "movement", "shield", "critical"]:
		check(modifier.apply(upgrade), "Reusable modifier applies: %s" % upgrade)
	check(modifier.damage_multiplier > 1.0 and modifier.projectile_count == 2 and modifier.explosion_radius > 0.0, "Modifier values compose without weapon conditionals")
	check(modifier.consume_shield() and not modifier.consume_shield(), "Temporary shield is consumed exactly once")
	var rapid_weapon := GameplayModifierSet.new()
	var heavy_weapon := GameplayModifierSet.new()
	var spread_weapon := GameplayModifierSet.new()
	var charged_weapon := GameplayModifierSet.new()
	rapid_weapon.apply("rapid_launcher")
	heavy_weapon.apply("heavy_cannon")
	spread_weapon.apply("spread_blaster")
	charged_weapon.apply("charged_launcher")
	check(rapid_weapon.projectile_profile().cooldown_multiplier < 0.5 and heavy_weapon.projectile_profile().explosion_radius >= 2.8, "Rapid and heavy reward weapons have genuinely different mechanics")
	check(int(spread_weapon.projectile_profile().count) >= 5 and charged_weapon.projectile_profile().weapon == "charged_launcher", "Spread and charged reward weapons publish distinct firing profiles")
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = 8086
	var hand_choices: Array[String] = modifier.choices(reward_rng, 2)
	check(hand_choices.size() == 2 and hand_choices[0] != hand_choices[1], "Weighted reward generation never duplicates both hands")
	game.return_to_menu()
	game._select_game_mode(GameModeManager.GameplayMode.PNG_MAYHEM)
	game.start_run()
	game._clear_bots()
	for upgrade in ["damage", "rapid", "double", "explosive", "freezing", "piercing", "ricochet"]:
		game.game_modes.modifiers.apply(upgrade)
	var profile = game.game_modes.projectile_profile()
	var target_at = game.player.global_position + Vector3(0, 0, 2.0)
	var primary = game._spawn_bot(target_at, {"max_health": 500.0, "respawn_delay": 9999.0, "custom_face": game.face_texture})
	var splash = game._spawn_bot(target_at + Vector3(1.0, 0, 0), {"max_health": 500.0, "respawn_delay": 9999.0, "custom_face": game.face_texture})
	primary.enabled = false
	splash.enabled = false
	await game.get_tree().physics_frame
	await game.get_tree().physics_frame
	await game.get_tree().physics_frame
	var special = game.projectiles.launch(game.png_images.current_texture(), target_at + Vector3.UP * 1.45, Vector3.FORWARD, null, false, profile)
	check(special.damage > game.projectiles.projectile_damage and special.explosion_radius > 0.0 and special.freeze_seconds > 0.0 and special.piercing_remaining > 0 and special.ricochets_remaining > 0, "Weapon consumes the composed special-projectile profile")
	await game.get_tree().physics_frame
	await game.get_tree().physics_frame
	check(primary.get_health_component().current_health < 500.0 and splash.get_health_component().current_health < 500.0, "Explosive PNG applies one swept impact and nearby splash damage")
	check(primary.state == NextbotEnemy.State.STUNNED or splash.state == NextbotEnemy.State.STUNNED, "Freezing PNG applies the reusable stunned AI state")

	game.statistics.add("total_deaths", 2)
	check(game.statistics.save_data(), "Statistics write to isolated local storage")
	var previous_deaths = int(game.statistics.value("total_deaths"))
	game.statistics.data.clear()
	game.statistics.load_data()
	check(int(game.statistics.value("total_deaths")) == previous_deaths, "Statistics survive save/load")
	var corrupt = FileAccess.open(game.statistics.storage_path, FileAccess.WRITE)
	corrupt.store_string("{not valid json")
	corrupt = null
	game.statistics.load_data()
	check(int(game.statistics.value("total_deaths")) == 0 and int(game.statistics.value("highest_endless_level")) == 1, "Corrupted statistics fall back to safe defaults")

	game.return_to_menu()
	for index in range(6):
		await game.get_tree().physics_frame
	print("MODES TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)

