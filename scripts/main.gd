extends Node3D
## Run coordinator. Owns progression; movement, rendering, AI, audio and UI stay separate.
enum Mode { MENU, PLAYING, PAUSED, DYING, RESULT, TRANSITION }
const EXTRA_FACE_PATHS := [
	"res://assets/nextbot_faces/elena_finkelshteyn.jpg",
	"res://assets/nextbot_faces/5402324111498878359.jpg",
]
const MobileControlsScript = preload("res://scripts/mobile_controls.gd")
var mode: Mode = Mode.MENU
var world: LevelWorld
var player: PlayerController
var ui: GameInterface
var bots: Array[NextbotEnemy] = []
var menu_camera: Camera3D
var face_texture: Texture2D
var face_textures: Array[Texture2D] = []
var survival_time: float = 0.0
var breakers: int = 0
var chased: bool = false
var threat: float = 0.0
var spawn_timer: float = 9.0
var ambient_timer: float = 18.0
var debug_ai: bool = false
var interaction_prompt: String = ""
var focused_item: WorldInteractable
var hide_remaining: float = 0.0
var hide_cooldown: float = 0.0
var hidden_light: bool = false
var run_difficulty: int = 1
var new_record: bool = false
var intro_time: float = 0.0
var hide_return_position: Vector3
var hide_return_yaw: float = 0.0
var test_runner
var run_map_index: int = 0
var png_images
var projectiles
var damage_system
var combat_hud
var kill_count: int = 0
var next_bot_id: int = 0
var defeated_bots: Array[NextbotEnemy] = []
var pending_respawns: Array[Dictionary] = []
var network
var network_menu
var rng = RandomNumberGenerator.new()
var current_level: int = 1
var current_generation_seed: int = 0
var progression_root_seed: int = 1
var regeneration_serial: int = 0
var transition_in_progress: bool = false
var progression_config: ProceduralGenerationConfig = preload("res://resources/procedural_generation.tres")
var gameplay_config: GameplayConfig = preload("res://resources/gameplay_config.tres")
var statistics: StatisticsManager
var game_modes: GameModeManager
var events: RandomEventManager
var post_boss: PostBossRewardController
var mobile_controls

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	rng.randomize()
	_load_face()
	_load_extra_faces()
	if "--capture-construct" in OS.get_cmdline_user_args():
		Settings.level_index = 1
	_load_world(Settings.level_index)
	player = PlayerController.new()
	player.name = "Player"
	player.session = self
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.position = world.spawns[0]
	player.footsteps.connect(_footstep)
	menu_camera = Camera3D.new()
	menu_camera.position = world.menu_view_position
	menu_camera.rotation = world.menu_view_rotation
	menu_camera.fov = 72
	add_child(menu_camera)
	menu_camera.make_current()
	ui = GameInterface.new()
	add_child(ui)
	ui.action_requested.connect(_action)
	ui.map_selected.connect(_select_map)
	ui.set_map_description(world)
	_setup_combat()
	_setup_network()
	_setup_gameplay()
	_setup_mobile_controls()
	Sound.set_enabled(true)
	if "--net-test-host" in OS.get_cmdline_user_args() or "--net-test-client" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/network_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--bossfight-net-test-host" in OS.get_cmdline_user_args() or "--bossfight-net-test-client" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/bossfight_network_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--modes-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/modes_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--bossfight-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/bossfight_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--mobile-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/mobile_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--throwables-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/throwables_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--movement-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/movement_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--combat-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/combat_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--map-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/maps_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--procedural-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/procedural_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--spawn-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/spawn_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--smoke-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/smoke_test.gd").new()
		test_runner.run.call_deferred(self)
	elif "--play" in OS.get_cmdline_user_args():
		start_run()
	if "--capture-menu" in OS.get_cmdline_user_args():
		_capture.call_deferred("menu")
	if "--capture-construct" in OS.get_cmdline_user_args():
		_capture_construct.call_deferred()
	if "--capture-combat" in OS.get_cmdline_user_args():
		_capture_combat.call_deferred()
	if "--capture-bossfight" in OS.get_cmdline_user_args():
		_capture_bossfight.call_deferred()
	if "--capture-network" in OS.get_cmdline_user_args():
		network_menu.open()
		_capture_network.call_deferred()

func _setup_mobile_controls() -> void:
	if not MobileControlsScript.enabled_for_platform():
		return
	mobile_controls = MobileControlsScript.new()
	mobile_controls.name = "MobileControls"
	mobile_controls.session = self
	add_child(mobile_controls)

func _setup_gameplay() -> void:
	statistics = StatisticsManager.new()
	statistics.name = "StatisticsManager"
	add_child(statistics)
	game_modes = GameModeManager.new()
	game_modes.name = "GameModeManager"
	add_child(game_modes)
	game_modes.setup(self, gameplay_config, statistics)
	events = RandomEventManager.new()
	events.name = "RandomEventManager"
	add_child(events)
	events.setup(self, gameplay_config)
	post_boss = PostBossRewardController.new()
	post_boss.setup(self)
	add_child(post_boss)
	ui.mode_selected.connect(_select_game_mode)
	ui.upgrade_selected.connect(game_modes.choose_upgrade)
	ui.sandbox_action.connect(game_modes.sandbox_action)
	ui.set_mode_description(game_modes)

func _setup_network() -> void:
	network = preload("res://scripts/network/network_session.gd").new()
	network.session = self
	network.name = "NetworkSession"
	add_child(network)
	network_menu = preload("res://scripts/network/network_menu.gd").new()
	network_menu.session = self
	network_menu.net = network
	add_child(network_menu)

func prepare_network_world(map_index: int, difficulty_index: int, progression_level: int = 1, seed_value: int = 0, gameplay_mode: int = GameModeManager.GameplayMode.ENDLESS) -> void:
	projectiles.clear_projectiles()
	damage_system.clear_effects()
	_clear_bots()
	game_modes.select(gameplay_mode, false)
	var map_changed = Settings.level_index != map_index
	if map_changed:
		Settings.level_index = map_index
	if game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT:
		_load_bossfight_world(progression_level, seed_value)
	elif progression_level >= 4:
		_load_procedural_world(progression_level, seed_value)
	elif map_changed or world is ProceduralLevelWorld or world is BossfightWorld:
		_load_world(map_index)
	Settings.difficulty = clampi(difficulty_index, 0, 2)
	ui.set_map_description(world)
	ui.set_mode_description(game_modes)

func network_spawn_local(state: Dictionary) -> void:
	get_tree().paused = false
	mode = Mode.PLAYING
	player.reset_at(state.p)
	player.rotation.y = float(state.yaw)
	projectiles.reset_run(true)
	projectiles.unlimited_ammo = true
	combat_hud.dismiss()
	kill_count = int(state.kills)
	ui.result_button.disabled = false
	ui.overlay.material.set_shader_parameter("darkness", 0.0)
	ui.show_screen("game")

func apply_network_actor(state: Dictionary) -> void:
	player.global_position = state.p
	player.rotation.y = state.yaw
	player.hidden = state.hidden
	player.view.flashlight_on = state.light
	player.view.battery = state.battery
	hide_remaining = state.hide_left
	ui.overlay.material.set_shader_parameter("darkness", 0.55 if player.hidden else 0.0)
	if player.hidden:
		projectiles.suspend_input()

func network_death_local(bot_id: int, face_variant: int = -1, bossfight_boss: bool = false) -> void:
	if mode in [Mode.DYING, Mode.RESULT]:
		return
	mode = Mode.DYING
	player.active = false
	player.network_alive = false
	player.velocity = Vector3.ZERO
	player.hidden = false
	projectiles.clear_owned_projectiles(player)
	projectiles.suspend_input()
	combat_hud.dismiss()
	ui.overlay.material.set_shader_parameter("darkness", 0.0)
	_record_run()
	var death_time = survival_time
	Sound.jumpscare()
	var scare_face: Texture2D = GameModeManager.BOSSFIGHT_ATTACK_FACE if bossfight_boss else (face_for_variant(face_variant) if face_variant >= 0 else _face_for_bot_id(bot_id))
	await ui.play_jumpscare(scare_face)
	if mode != Mode.DYING or not network.active:
		return
	mode = Mode.RESULT
	ui.show_result(false, death_time, Settings.best_for_map(run_map_index, run_difficulty), new_record, world.escape_message, kill_count)

func show_network_victory() -> void:
	mode = Mode.RESULT
	player.active = false
	projectiles.clear_projectiles()
	projectiles.suspend_input()
	combat_hud.dismiss()
	_record_run()
	ui.show_result(true, survival_time, Settings.best_for_map(run_map_index, run_difficulty), new_record, world.escape_message, kill_count)
	if not network.is_host():
		ui.result_button.disabled = true
		ui.result_button.text = "ОЖИДАНИЕ НОВОГО ЗАБЕГА ОТ ХОСТА"

func target_players() -> Array[PlayerController]:
	var result: Array[PlayerController] = []
	if is_instance_valid(player):
		result.append(player)
	if is_instance_valid(network) and network.active:
		for actor in network.avatars.values():
			if is_instance_valid(actor):
				result.append(actor)
	return result

func actor_alive(actor) -> bool:
	if not is_instance_valid(actor):
		return false
	return actor.network_alive if is_instance_valid(network) and network.active else actor.active

func first_alive_player() -> PlayerController:
	for actor in target_players():
		if actor_alive(actor):
			return actor
	return null

func catch_player(actor: PlayerController, bot: NextbotEnemy) -> void:
	if is_instance_valid(network) and network.active:
		if network.is_host():
			network.catch_peer(network.peer_for(actor), bot.bot_index)
	elif actor == player:
		kill_player(bot)

func is_authority() -> bool:
	return not is_instance_valid(network) or not network.active or network.is_host()

func is_local_playing() -> bool:
	return mode == Mode.PLAYING and is_instance_valid(player) and player.active

func _setup_combat() -> void:
	png_images = preload("res://scripts/combat/png_image_loader.gd").new()
	add_child(png_images)
	damage_system = preload("res://scripts/combat/damage_system.gd").new()
	damage_system.session = self
	add_child(damage_system)
	projectiles = preload("res://scripts/combat/projectile_controller.gd").new()
	projectiles.player = player
	projectiles.session = self
	projectiles.images = png_images
	projectiles.damage_system = damage_system
	player.add_child(projectiles)
	combat_hud = preload("res://scripts/combat/combat_hud.gd").new()
	combat_hud.session = self
	combat_hud.weapon = projectiles
	combat_hud.images = png_images
	add_child(combat_hud)

func _capture_combat() -> void:
	if Settings.level_index != 1:
		_select_map(1)
	await world.navigation.wait_ready()
	start_run()
	spawn_timer = 9999
	player.reset_at(Vector3(60, 0.1, 84))
	player.rotation.y = PI
	var bot = _spawn_bot(Vector3(60, 0.1, 95))
	await get_tree().physics_frame
	await get_tree().physics_frame
	bot.enabled = false
	damage_system.apply_hit(bot, 40.0, player, bot.global_position + Vector3.UP * 1.5, Vector3.FORWARD)
	await get_tree().create_timer(0.3).timeout
	projectiles.fire()
	await get_tree().create_timer(0.1).timeout
	await _capture("combat")
	combat_hud.open_library()
	await _capture("png_library")
	get_tree().quit()

func _capture_construct() -> void:
	ui.root.visible = false
	menu_camera.look_at(Vector3(60, 2, 48))
	await get_tree().create_timer(1.0).timeout
	await _capture("construct")
	get_tree().quit()

func _capture_bossfight() -> void:
	game_modes.select(GameModeManager.GameplayMode.BOSSFIGHT)
	start_run(false, 1, 13001)
	spawn_timer = 9999.0
	await world.navigation.wait_ready()
	_clear_bots()
	ui.root.visible = false
	menu_camera.global_position = Vector3(66, 32, 132)
	menu_camera.look_at(Vector3(66, 0, 62))
	menu_camera.make_current()
	await get_tree().create_timer(0.8).timeout
	await _capture("bossfight_dust_quarter")
	player.reset_at(Vector3(66, 0.1, 114))
	player.view.camera.make_current()
	_look_at_point(Vector3(66, 2.0, 63))
	await get_tree().create_timer(0.35).timeout
	await _capture("bossfight_dust_quarter_street")
	ui.root.visible = true
	await _transition_to_level(4, 44004, false)
	for frame in range(240):
		if is_instance_valid(game_modes.active_boss):
			break
		await get_tree().physics_frame
	var boss := game_modes.active_boss
	if is_instance_valid(boss):
		boss.enabled = false
		boss.global_position = Vector3(0, 0.1, 0)
	player.reset_at(Vector3(0, 0.1, 18))
	player.view.camera.make_current()
	_look_at_point(Vector3(0, 2.0, 0))
	await get_tree().create_timer(0.5).timeout
	await _capture("bossfight_arena_idle")
	if is_instance_valid(boss):
		boss._change_state(NextbotEnemy.State.ATTACK)
	await get_tree().process_frame
	await _capture("bossfight_arena_attack")
	if is_instance_valid(boss):
		boss.combat.health.apply_damage(boss.combat.health.current_health, player, boss.global_position)
	for frame in range(180):
		if post_boss.state == PostBossRewardController.RewardState.REWARD_SELECTION:
			break
		await get_tree().physics_frame
	player.reset_at(Vector3(0, 0.1, 5.2))
	_look_at_point(post_boss.npc_position + Vector3.UP * 1.45)
	await get_tree().create_timer(0.4).timeout
	await _capture("bossfight_reward_selection")
	post_boss._finalize_authoritative(0)
	player.reset_at(Vector3(4.2, 0.1, 3.8))
	_look_at_point(post_boss.npc_position + Vector3.UP * 1.15)
	await get_tree().create_timer(0.5).timeout
	await _capture("bossfight_reward_lever")
	get_tree().quit()

func _look_at_point(point: Vector3) -> void:
	var direction := point - player.view.camera.global_position
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.view.pitch = -atan2(direction.y, Vector2(direction.x, direction.z).length())
	player.view.rotation.x = player.view.pitch

func _capture_network() -> void:
	await _capture("network_menu")
	get_tree().quit()

func _load_world(index: int) -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = load("res://scripts/construct_world.gd").new() if index == 1 else LevelWorld.new()
	world.name = "Construct" if index == 1 else "UndergroundComplex"
	world.session = self
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

func _load_procedural_world(level: int, seed_value: int) -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	var generated = ProceduralLevelWorld.new()
	generated.progression_level = level
	generated.generation_seed = seed_value
	generated.generation_config = progression_config
	generated.name = "ProceduralLevel%d" % level
	generated.session = self
	generated.process_mode = Node.PROCESS_MODE_PAUSABLE
	world = generated
	add_child(world)

func _load_bossfight_world(level: int, seed_value: int) -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	var battlefield := BossfightWorld.new()
	battlefield.configure(level, seed_value)
	battlefield.name = "BossArena" if battlefield.arena_mode else "DustQuarter"
	battlefield.session = self
	battlefield.process_mode = Node.PROCESS_MODE_PAUSABLE
	world = battlefield
	add_child(world)

func _select_map(index: int) -> void:
	if mode != Mode.MENU or index == Settings.level_index or (is_instance_valid(network) and network.active):
		return
	Settings.level_index = index
	Settings.save()
	projectiles.clear_projectiles()
	damage_system.clear_effects()
	_load_world(index)
	player.active = false
	player.position = world.spawns[0]
	menu_camera.position = world.menu_view_position
	menu_camera.rotation = world.menu_view_rotation
	ui.set_map_description(world)
	ui.show_screen("menu")

func _load_face() -> void:
	# Imported textures support exported PCKs; direct images support newly dropped files.
	for extension in ["png", "jpg", "jpeg", "webp", "bmp", "svg"]:
		var path = "res://assets/nextbot_face." + extension
		if ResourceLoader.exists(path):
			var resource = load(path)
			if resource is Texture2D:
				face_texture = resource
				print("NEXTBOT FACE: using original image ", path)
				return
		if FileAccess.file_exists(path):
			var image = Image.load_from_file(ProjectSettings.globalize_path(path))
			if image != null and not image.is_empty():
				face_texture = ImageTexture.create_from_image(image)
				print("NEXTBOT FACE: using original image ", path)
				return
	face_texture = preload("res://assets/fallback_face.svg")
	print("NEXTBOT FACE: supplied image missing; using original project fallback. See assets/README.md.")

func _load_extra_faces() -> void:
	face_textures.clear()
	face_textures.append(face_texture)
	for path in EXTRA_FACE_PATHS:
		var texture := _load_extra_face(path)
		if texture != null:
			face_textures.append(texture)
			print("NEXTBOT FACE: added image ", face_textures.size(), " ", path)
		else:
			push_warning("Bundled Nextbot face is missing: " + path)

func _load_extra_face(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var resource = load(path)
		if resource is Texture2D:
			return resource
	if FileAccess.file_exists(path):
		var image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)
	return null

func face_for_variant(index: int) -> Texture2D:
	return face_textures[posmod(index, face_textures.size())] if not face_textures.is_empty() else face_texture

func _face_for_bot_id(bot_id: int) -> Texture2D:
	for bot in bots + defeated_bots:
		if is_instance_valid(bot) and bot.bot_index == bot_id:
			return bot.face.texture
	if is_instance_valid(network) and network.replicas.has(bot_id) and is_instance_valid(network.replicas[bot_id]):
		return network.replicas[bot_id].face.texture
	return face_for_variant(bot_id + 1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_action("quit")
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == Mode.PLAYING and not Settings.automated_run():
		pause_run()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(network_menu) and network_menu.panel.visible:
		if event.is_action_pressed("pause"):
			network_menu.close()
		return
	if is_instance_valid(combat_hud) and combat_hud.gallery.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("png_library"):
			combat_hud.close_library()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("png_library") and mode in [Mode.PLAYING, Mode.PAUSED] and not ui.settings_screen.visible:
		combat_hud.open_library()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("sandbox_tools") and mode in [Mode.PLAYING, Mode.PAUSED] and game_modes.selected == GameModeManager.GameplayMode.SANDBOX:
		ui.toggle_sandbox_tools()
		player.active = not ui.sandbox_screen.visible
		if player.active:
			projectiles.require_release = true
		get_viewport().set_input_as_handled()
		return
	if is_local_playing() and post_boss.state == PostBossRewardController.RewardState.REWARD_SELECTION:
		if event.is_action_pressed("reward_left"):
			post_boss.select_choice(0)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("interact"):
			post_boss.select_choice(1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause"):
		if ui.settings_screen.visible:
			_action("apply_settings")
		elif mode == Mode.PLAYING:
			pause_run()
		elif mode == Mode.PAUSED:
			resume_run()
	if event.is_action_pressed("interact") and is_local_playing():
		_interact()
	if event.is_action_pressed("debug_ai"):
		debug_ai = not debug_ai
	if event.is_action_pressed("debug_regenerate") and debug_ai and current_level >= 4 and OS.is_debug_build() and not transition_in_progress and (not is_instance_valid(network) or not network.active):
		regeneration_serial += 1
		_transition_to_level(current_level, _seed_for_level(current_level, regeneration_serial))
	if event.is_action_pressed("debug_spawn") and debug_ai and is_local_playing() and OS.is_debug_build() and is_authority():
		var forced = _spawn_bot()
		if forced != null:
			ui.toast("DEBUG: forced Nextbot spawn -> %d total" % bots.size(), 3.0)
		else:
			ui.toast("DEBUG: forced spawn failed (nav=%s patrol=%d)" % [world.navigation.synchronized, world.patrol_points.size()], 3.0)

func _action(action: String) -> void:
	match action:
		"play", "restart": start_run()
		"resume": resume_run()
		"settings": ui.open_settings("menu")
		"settings_pause": ui.open_settings("pause")
		"png_library": combat_hud.open_library()
		"png_library_menu": combat_hud.open_library_from_menu()
		"network":
			# Cooperative sessions support the established Endless rules and the
			# dedicated Bossfight cycle. Other local-only modes fall back safely.
			if game_modes.selected not in [GameModeManager.GameplayMode.ENDLESS, GameModeManager.GameplayMode.BOSSFIGHT]:
				game_modes.select(GameModeManager.GameplayMode.ENDLESS)
			ui.set_mode_description(game_modes)
			network_menu.open()
		"statistics": ui.show_statistics(statistics)
		"menu_screen":
			ui.show_screen("menu")
			ui.set_mode_description(game_modes)
		"nextbot_editor":
			game_modes.select(GameModeManager.GameplayMode.SANDBOX)
			ui.set_mode_description(game_modes)
			start_run()
			ui.toggle_sandbox_tools()
			player.active = false
		"sandbox_spawn": game_modes.sandbox_action("spawn")
		"sandbox_reward": game_modes.sandbox_action("reward")
		"sandbox_remove": game_modes.sandbox_action("remove")
		"sandbox_event": game_modes.sandbox_action("event")
		"sandbox_regenerate":
			ui.show_screen("game")
			game_modes.sandbox_action("regenerate")
		"sandbox_reset": game_modes.sandbox_action("reset")
		"sandbox_close":
			ui.show_screen("game")
			player.active = true
			projectiles.require_release = true
		"apply_settings":
			ui.apply_settings()
			ui.show_screen(ui.settings_return)
		"menu": return_to_menu()
		"quit":
			if mode == Mode.PLAYING or mode == Mode.PAUSED:
				_record_run()
			Settings.save()
			statistics.save_data()
			if network.active:
				await network.disconnect_session("", false)
			get_tree().quit()

func is_running() -> bool:
	if is_instance_valid(network) and network.active:
		return network.game_running
	return mode == Mode.PLAYING

func start_run(force_new: bool = false, starting_level: int = 1, seed_value: int = 0) -> void:
	if is_instance_valid(network) and network.active and not force_new:
		network.respawn_local()
		return
	get_tree().paused = false
	events.end_event()
	post_boss.reset_run()
	game_modes.before_start()
	_clear_bots()
	var progression_mode := game_modes.selected in [GameModeManager.GameplayMode.ENDLESS, GameModeManager.GameplayMode.BOSSFIGHT]
	current_level = maxi(1, starting_level) if progression_mode else 1
	current_generation_seed = 0
	regeneration_serial = 0
	progression_root_seed = int(rng.randi()) & 0x7fffffff
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--proc-seed="):
			progression_root_seed = int(argument.trim_prefix("--proc-seed=")) & 0x7fffffff
	if game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT:
		current_generation_seed = seed_value if seed_value != 0 else _seed_for_level(current_level)
		if not world is BossfightWorld or world.stage_level != current_level or world.stage_seed != current_generation_seed:
			_load_bossfight_world(current_level, current_generation_seed)
	elif current_level >= 4:
		current_generation_seed = seed_value
		if not world is ProceduralLevelWorld or world.generation_seed != current_generation_seed or world.progression_level != current_level:
			_load_procedural_world(current_level, current_generation_seed)
	elif world is ProceduralLevelWorld or world is BossfightWorld:
		_load_world(Settings.level_index)
	world.reset_items()
	refresh_interactable_policy()
	survival_time = 0.0
	breakers = 0
	threat = 0.0
	chased = false
	spawn_timer = 9.0
	ambient_timer = rng.randf_range(16, 26)
	intro_time = 0.0
	hide_remaining = 0.0
	hide_cooldown = 0.0
	run_difficulty = Settings.difficulty
	run_map_index = Settings.level_index
	new_record = false
	kill_count = 0
	next_bot_id = 0
	ui.overlay.material.set_shader_parameter("darkness", 0.0)
	mode = Mode.PLAYING
	player.reset_at(world.spawns[rng.randi_range(0, world.spawns.size() - 1)])
	projectiles.reset_run()
	damage_system.clear_effects()
	combat_hud.dismiss()
	ui.result_button.disabled = false
	ui.show_screen("game")
	game_modes.start_run()
	ui.toast("%s / %s\n%s\nE INTERACT  /  F FLASHLIGHT  /  TAB PNG LIBRARY" % [game_modes.mode_name(), world.display_name, game_modes.objective_text()], 7.0)
	Sound.target_intensity = 0.0
	Sound.set_enabled(true)

func pause_run() -> void:
	if not is_local_playing():
		return
	mode = Mode.PAUSED
	projectiles.suspend_input()
	ui.show_screen("pause")
	Sound.target_intensity = 0.0
	if network.active:
		player.active = false
		ui.toast("СЕТЕВАЯ ИГРА ПРОДОЛЖАЕТСЯ", 3.0)
	else:
		get_tree().paused = true

func resume_run() -> void:
	get_tree().paused = false
	mode = Mode.PLAYING
	player.active = true
	ui.show_screen("game")

func return_to_menu() -> void:
	if is_instance_valid(network) and network.active:
		network.disconnect_session()
		return
	if mode in [Mode.PLAYING, Mode.PAUSED]:
		_record_run()
	get_tree().paused = false
	events.end_event()
	post_boss.reset_run()
	game_modes.finish_run()
	mode = Mode.MENU
	_clear_bots()
	projectiles.clear_projectiles()
	projectiles.suspend_input()
	damage_system.clear_effects()
	combat_hud.dismiss()
	player.active = false
	player.hidden = false
	transition_in_progress = false
	current_level = 1
	current_generation_seed = 0
	if world is ProceduralLevelWorld or world is BossfightWorld:
		_load_world(Settings.level_index)
		player.position = world.spawns[0]
		menu_camera.position = world.menu_view_position
		menu_camera.rotation = world.menu_view_rotation
		ui.set_map_description(world)
	refresh_interactable_policy()
	menu_camera.make_current()
	Sound.target_intensity = 0.0
	ui.overlay.material.set_shader_parameter("danger", 0.0)
	ui.overlay.material.set_shader_parameter("darkness", 0.0)
	ui.show_screen("menu")
	ui.set_mode_description(game_modes)

func _clear_bots() -> void:
	pending_respawns.clear()
	for bot in bots + defeated_bots:
		if is_instance_valid(bot):
			bot.enabled = false
			bot.queue_free()
	bots.clear()
	defeated_bots.clear()

func enemy_defeated(bot: NextbotEnemy, source: Node) -> void:
	if not is_running() or not is_authority() or not bots.has(bot):
		return
	bots.erase(bot)
	defeated_bots.append(bot)
	events.enemy_defeated(bot)
	game_modes.enemy_defeated(bot)
	if game_modes.modifiers.death_explosion_radius > 0.0:
		_trigger_reward_death_burst.call_deferred(bot.global_position, bot, source)
	if network.active:
		network.award_kill(source)
	elif source == player:
		kill_count += 1
	if game_modes.should_respawn_enemy(bot):
		pending_respawns.append({"remaining": maxf(0.05, bot.respawn_delay), "stats": {"max_health": bot.max_health, "respawn_delay": bot.respawn_delay, "face_variant": bot.face_variant}})

func _trigger_reward_death_burst(at: Vector3, defeated: NextbotEnemy, source: Node) -> void:
	if not is_running() or not is_authority():
		return
	damage_system.impact(at + Vector3.UP, false)
	for other in bots.duplicate():
		if other == defeated or not is_instance_valid(other) or other.combat.dead or other.global_position.distance_to(at) > game_modes.modifiers.death_explosion_radius:
			continue
		var direction: Vector3 = (other.global_position - at).normalized()
		damage_system.apply_hit(other, 45.0, source, other.global_position + Vector3.UP, direction)

func _forget_enemy(bot: NextbotEnemy) -> void:
	bots.erase(bot)
	defeated_bots.erase(bot)

func _update_enemy_respawns(delta: float) -> void:
	for i in range(pending_respawns.size() - 1, -1, -1):
		pending_respawns[i].remaining -= delta
		if pending_respawns[i].remaining <= 0.0:
			var stats = pending_respawns[i].stats
			pending_respawns.remove_at(i)
			_spawn_bot(Vector3.INF, stats)

func _process(delta: float) -> void:
	if mode == Mode.MENU:
		menu_camera.rotation.y += delta * 0.028
	if not is_running():
		return
	survival_time += delta
	intro_time += delta
	if not is_authority():
		_update_threat(delta)
		_update_interaction()
		ui.update_hud(self)
		return
	hide_cooldown = maxf(0.0, hide_cooldown - delta)
	spawn_timer -= delta
	ambient_timer -= delta
	_update_enemy_respawns(delta)
	var max_bots: int = maximum_active_bots()
	var desired_count = mini(max_bots, 1 + int(survival_time / 55.0) + (1 if run_difficulty == 2 else 0))
	desired_count = game_modes.desired_active_bots(desired_count)
	if game_modes.uses_standard_spawner() and spawn_timer <= 0.0 and world.navigation.synchronized and bots.size() + pending_respawns.size() < desired_count:
		_spawn_bot()
		spawn_timer = 5.0
		if bots.size() == 1:
			ui.toast("SOMETHING HAS ENTERED THE COMPLEX.", 4.0)
	elif game_modes.uses_standard_spawner() and spawn_timer <= 0.0 and not world.navigation.synchronized:
		# Navigation is built asynchronously. Keep the request armed instead of
		# losing the initial spawn while a newly selected map is still loading.
		spawn_timer = 0.0
	if ambient_timer <= 0.0:
		var horror_pressure = maxf(0.0, float(current_level - 3))
		ambient_timer = rng.randf_range(maxf(10.0, 23.0 - horror_pressure * 0.55), maxf(18.0, 41.0 - horror_pressure * 0.9))
		Sound.spatial("scream", world, world.far_point(player.global_position, 18.0) + Vector3.UP * 1.5, -13.0)
	if player.hidden and not network.active:
		hide_remaining -= delta
		if hide_remaining <= 0:
			_leave_hiding()
			ui.toast("YOU CANNOT HOLD YOUR BREATH ANY LONGER.", 3.0)
	_update_threat(delta)
	_update_interaction()
	game_modes.tick(delta)
	events.tick(delta)
	ui.update_hud(self)

func _spawn_bot(at: Vector3 = Vector3.INF, stats: Dictionary = {}) -> NextbotEnemy:
	if not is_instance_valid(world) or not is_instance_valid(player):
		push_warning("SPAWN SKIPPED: world/player invalid (mode=%s)" % game_modes.mode_name())
		return null
	var point = at
	if point == Vector3.INF:
		# Automatic placement: validate navigation readiness, pick a patrol
		# point that is both far from the player and collision-cleared, and
		# never silently fall back onto the player's tile. Returning null lets
		# the caller (standard spawner, Mayhem waves, Sandbox batches) retry
		# safely instead of planting an enemy inside a wall or on the player.
		point = _find_safe_spawn_point()
		if point == Vector3.INF:
			push_warning("SPAWN FAILED: no valid spawn point (mode=%s nav=%s patrol=%d bots=%d/%d)" % [game_modes.mode_name(), world.navigation.synchronized, world.patrol_points.size(), bots.size(), maximum_active_bots()])
			return null
	var bot = NextbotEnemy.new()
	bot.session = self
	bot.process_mode = Node.PROCESS_MODE_PAUSABLE
	bot.world = world
	bot.player = player
	var level_speed = nextbot_speed_multiplier()
	var level_pressure = game_modes.enemy_pressure(maxf(0.0, float(current_level - 3)))
	bot.speed = [9.0, 11.4, 13.6][run_difficulty] * level_speed
	bot.detection_range = [26.0, 34.0, 43.0][run_difficulty] * (1.0 + minf(0.45, level_pressure * 0.035))
	bot.aggression = [0.8, 1.0, 1.25][run_difficulty] * (1.0 + minf(0.50, level_pressure * 0.04))
	bot.repath_interval = maxf(0.105, 0.18 - level_pressure * 0.004)
	bot.search_duration_scale = 1.0 + minf(0.65, level_pressure * 0.045)
	bot.chase_speed_cap = 21.2
	bot.max_health = maxf(1.0, stats.get("max_health", game_modes.default_enemy_health()))
	bot.respawn_delay = maxf(0.05, stats.get("respawn_delay", 10.0))
	bot.speed_multiplier = maxf(0.1, stats.get("speed_multiplier", 1.0))
	if stats.has("speed_override"):
		bot.speed = maxf(0.0, float(stats.speed_override))
	bot.detection_range = maxf(0.0, float(stats.get("detection_range", bot.detection_range)))
	bot.aggression = maxf(0.05, float(stats.get("aggression", bot.aggression)))
	bot.attack_damage = maxf(0.0, float(stats.get("attack_damage", 100.0)))
	bot.face_scale = clampf(float(stats.get("face_scale", 1.0)), 0.25, 3.0)
	bot.custom_face = stats.get("custom_face", null)
	bot.attack_face = stats.get("attack_face", null)
	bot.is_boss = bool(stats.get("boss", false))
	bot.event_spawned = bool(stats.get("event_spawned", false))
	bot.event_tag = str(stats.get("event_tag", ""))
	bot.angry_observation = bool(stats.get("angry", false))
	bot.bot_index = int(stats.get("network_id", next_bot_id))
	bot.face_variant = int(stats.get("face_variant", bot.bot_index + 1))
	next_bot_id = maxi(next_bot_id + 1, bot.bot_index + 1)
	bot.network_replica = not is_authority()
	bot.position = point + Vector3.UP * 0.06
	bot.name = "Nextbot%d" % bot.bot_index
	add_child(bot)
	bot.tree_exiting.connect(_forget_enemy.bind(bot))
	bots.append(bot)
	events.enemy_spawned(bot)
	if debug_ai:
		print("SPAWN OK: mode=%s bot=%d at=%s bots=%d/%d nav=%s" % [game_modes.mode_name(), bot.bot_index, str(point), bots.size(), maximum_active_bots(), world.navigation.synchronized])
	return bot

# Picks a navigable, collision-cleared patrol point away from the player for
# automatic enemy placement. Returns Vector3.INF only when the map has no
# usable spawn surface at all (e.g. navigation still building); callers must
# treat that as a retry signal, never as a successful spawn.
func _find_safe_spawn_point() -> Vector3:
	if not world.navigation.synchronized:
		return Vector3.INF
	if world.patrol_points.is_empty():
		return Vector3.INF
	var clearance := AABB(Vector3.ZERO, Vector3(1.0, 1.8, 1.0))
	var far: Array[Vector3] = []
	for p in world.patrol_points:
		if p.distance_to(player.global_position) < 40.0:
			continue
		clearance.position = p + Vector3(-0.5, 0.3, -0.5)
		if world.navigation_clear(clearance):
			far.append(p)
	if not far.is_empty():
		return far[rng.randi_range(0, far.size() - 1)]
	for p in world.patrol_points:
		clearance.position = p + Vector3(-0.5, 0.3, -0.5)
		if world.navigation_clear(clearance):
			return p
	# Last resort: any patrol point beats spawning on the player, but only if
	# nothing better exists; the standard spawner will retry next frame.
	return world.patrol_points[rng.randi_range(0, world.patrol_points.size() - 1)]

func _update_threat(delta: float) -> void:
	chased = false
	var target_threat: float = 0.0
	for bot in bots:
		var targeting_local = bot.player == player if is_authority() else bot.network_target == network.local_id()
		if bot.state == NextbotEnemy.State.CHASE and targeting_local and actor_alive(player):
			chased = true
			var distance = bot.global_position.distance_to(player.global_position)
			target_threat = maxf(target_threat, clampf(1.0 - distance / 45.0, 0.25, 1.0))
	threat = move_toward(threat, target_threat, delta * 1.8)
	Sound.target_intensity = threat

func _update_interaction() -> void:
	focused_item = null
	interaction_prompt = ""
	if player.hidden:
		return
	var best_score: float = -1.0
	var eye = player.view.camera.global_position
	var forward = -player.view.camera.global_basis.z
	var reward_prompt := post_boss.update_focus(player.view.camera)
	if not reward_prompt.is_empty():
		interaction_prompt = reward_prompt
		return
	for item in world.interactables:
		if item.used or not item.active:
			continue
		var aim = item.global_position + (Vector3.UP * 1.2 if item.kind == "hide" else Vector3.ZERO)
		var offset = aim - eye
		if offset.length() > 3.1:
			continue
		var score = offset.normalized().dot(forward)
		if score < 0.72 or score <= best_score:
			continue
		# A surface hit at the object itself is fine; a wall before it is not.
		var ray = PhysicsRayQueryParameters3D.create(eye, aim, 1)
		var hit = get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and eye.distance_to(hit.position) + 0.7 < offset.length():
			continue
		focused_item = item
		best_score = score
	if focused_item != null:
		interaction_prompt = focused_item.prompt(breakers)

func _interact() -> void:
	if post_boss.interact_focused():
		return
	if network.active:
		network.request_interact(-1 if player.hidden or focused_item == null else world.interactables.find(focused_item))
		return
	if player.hidden:
		_leave_hiding()
		return
	if focused_item == null:
		return
	match focused_item.kind:
		"battery":
			if player.view.battery > 98.0:
				ui.toast("FLASHLIGHT BATTERY IS FULL.", 2.0)
				return
			player.view.battery = minf(100.0, player.view.battery + 45.0)
			focused_item.activate()
			Sound.one_shot("battery", -12.0)
			ui.toast("BATTERY REPLACED  /  +45%", 2.5)
		"breaker":
			focused_item.activate()
			breakers += 1
			events.breaker_activated()
			Sound.spatial("breaker", world, focused_item.global_position)
			var objective_kind := "SWITCHES ACTIVATED" if game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT else "BREAKERS RESTORED"
			ui.toast("%d / 3 %s\n%s" % [breakers, objective_kind, world.objective_destination + " IS NOW ONLINE" if breakers == 3 else "THE NOISE WILL DRAW THEM HERE"], 4.0)
			for bot in bots:
				bot.hear(player.global_position, 4.0)
			spawn_timer = minf(spawn_timer, 3.0)
		"exit":
			if not game_modes.can_advance_level():
				ui.toast("THIS EXIT IS INACTIVE IN %s." % game_modes.mode_name(), 2.0)
			elif breakers == 3:
				advance_level()
			else:
				ui.toast("ACTIVATE ALL THREE SWITCHES FIRST." if game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT else "RESTORE ALL THREE BREAKERS FIRST.", 2.0)
		"progression_lever":
			post_boss.try_activate_lever()
		"hide":
			if hide_cooldown > 0:
				ui.toast("CATCH YOUR BREATH BEFORE HIDING AGAIN.", 2.0)
				return
			for bot in bots:
				if bot.state == NextbotEnemy.State.CHASE and bot.global_position.distance_to(player.global_position) < 18.0 and bot._line_of_sight():
					ui.toast("IT SAW YOU. BREAK LINE OF SIGHT FIRST.", 2.5)
					return
			player.hidden = true
			hide_return_position = player.global_position
			hide_return_yaw = player.rotation.y
			player.global_position = focused_item.global_position + Vector3.UP * 0.1
			player.rotation.y = 0.0
			hidden_light = player.view.flashlight_on
			player.view.flashlight_on = false
			hide_remaining = 12.0
			ui.overlay.material.set_shader_parameter("darkness", 0.55)
			Sound.one_shot("click", -10.0)

func _leave_hiding() -> void:
	player.hidden = false
	player.global_position = hide_return_position
	player.rotation.y = hide_return_yaw
	player.view.flashlight_on = hidden_light
	hide_cooldown = 8.0
	ui.overlay.material.set_shader_parameter("darkness", 0.0)
	Sound.one_shot("click", -10.0)

func _footstep(at: Vector3, loudness: float) -> void:
	if network.active:
		network.on_step(loudness)
		return
	for bot in bots:
		bot.hear(at, loudness)

func kill_player(bot) -> void:
	if is_instance_valid(network) and network.active:
		if player.network_alive:
			network.report_fall()
		return
	if not is_running():
		return
	if game_modes.player_invincible():
		ui.toast("SANDBOX INVINCIBILITY ABSORBED THE HIT.", 1.5)
		return
	if game_modes.consume_shield():
		ui.toast("FIREWALL SHIELD CONSUMED.", 1.5)
		return
	mode = Mode.DYING
	events.end_event()
	player.active = false
	player.velocity = Vector3.ZERO
	projectiles.clear_projectiles()
	projectiles.suspend_input()
	pending_respawns.clear()
	combat_hud.dismiss()
	Sound.target_intensity = 0.0
	for enemy in bots:
		enemy.enabled = false
	_record_run()
	statistics.add("total_deaths")
	statistics.record_maximum("best_survival_time", survival_time)
	Sound.jumpscare()
	var texture = bot.face.texture if bot != null else face_texture
	await ui.play_jumpscare(texture)
	if mode != Mode.DYING:
		return
	mode = Mode.RESULT
	ui.show_result(false, survival_time, Settings.best_for_map(run_map_index, run_difficulty), new_record, world.escape_message, kill_count)

func _win_run() -> void:
	mode = Mode.RESULT
	events.end_event()
	player.active = false
	projectiles.clear_projectiles()
	projectiles.suspend_input()
	pending_respawns.clear()
	combat_hud.dismiss()
	for bot in bots:
		bot.enabled = false
	Sound.target_intensity = 0.0
	Sound.one_shot("battery", -5.0, 0.65)
	_record_run()
	ui.show_result(true, survival_time, Settings.best_for_map(run_map_index, run_difficulty), new_record, world.escape_message, kill_count)

func nextbot_speed_multiplier() -> float:
	return game_modes.nextbot_speed_multiplier(progression_config.speed_for_level(current_level))

func maximum_active_bots() -> int:
	var base: int = [2, 4, 5][run_difficulty]
	var level_bonus: int = maxi(0, floori(float(current_level - 3) / 2.0))
	return game_modes.maximum_active_bots(mini(progression_config.maximum_nextbots, base + level_bonus))

## Centralised mode-aware lever policy. Breakers and the exit are progression
## objects that belong to Endless; other modes hide them so they cannot block
## round/wave/sandbox play. Breakers re-appear while a Blackout event needs them.
func refresh_interactable_policy() -> void:
	if not is_instance_valid(world) or not is_instance_valid(game_modes) or not is_instance_valid(events):
		return
	var endless := game_modes.selected == GameModeManager.GameplayMode.ENDLESS
	var bossfight_stage := game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT and not game_modes.is_bossfight_boss_level()
	var needs_breakers := endless or bossfight_stage or events.active_event == "BLACKOUT"
	world.apply_interactable_policy(needs_breakers, endless or bossfight_stage)

func _seed_for_level(level: int, salt: int = 0) -> int:
	var value = int(hash([progression_root_seed, level, salt])) & 0x7fffffff
	return value if value != 0 else level * 7919 + salt + 1

func advance_level() -> void:
	if transition_in_progress or mode != Mode.PLAYING:
		return
	if is_instance_valid(network) and network.active:
		if network.is_host():
			network.advance_level()
		return
	_transition_to_level(current_level + 1, _seed_for_level(current_level + 1), not Settings.automated_run())

func _transition_to_level(next_level: int, seed_value: int, animate: bool = true, finish_locally: bool = true) -> bool:
	if transition_in_progress:
		return false
	transition_in_progress = true
	post_boss.begin_level_transition()
	events.end_event()
	mode = Mode.TRANSITION
	player.active = false
	player.hidden = false
	player.velocity = Vector3.ZERO
	projectiles.clear_projectiles()
	projectiles.suspend_input()
	damage_system.clear_effects()
	pending_respawns.clear()
	for bot in bots:
		bot.enabled = false
	_clear_bots()
	Sound.target_intensity = 0.0
	if animate:
		var transition_title := "DESCENDING"
		if game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT:
			transition_title = "BOSS ARENA" if next_level % 4 == 0 else "NEXT DESERT SECTOR"
		await ui.fade_to_black("%s\nLEVEL %02d" % [transition_title, next_level])
	current_level = maxi(1, next_level)
	current_generation_seed = seed_value if current_level >= 4 or game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT else 0
	var previous_layout_signature = world.layout_signature if world is ProceduralLevelWorld else ""
	if game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT:
		_load_bossfight_world(current_level, current_generation_seed)
	elif current_level >= 4:
		_load_procedural_world(current_level, current_generation_seed)
		if not previous_layout_signature.is_empty() and world.layout_signature == previous_layout_signature:
			current_generation_seed = (current_generation_seed + 65537) & 0x7fffffff
			_load_procedural_world(current_level, current_generation_seed)
	else:
		if world is ProceduralLevelWorld:
			_load_world(run_map_index)
		world.reset_items()
		refresh_interactable_policy()
	breakers = 0
	threat = 0.0
	chased = false
	spawn_timer = maxf(5.0, 10.0 - float(current_level) * 0.35)
	ambient_timer = rng.randf_range(14.0, 24.0)
	hide_remaining = 0.0
	hide_cooldown = 0.0
	focused_item = null
	interaction_prompt = ""
	await get_tree().physics_frame
	var navigation_ready: bool = await world.navigation.wait_ready()
	if world is ProceduralLevelWorld:
		navigation_ready = navigation_ready and world.validate_navigation()
		if not navigation_ready:
			# A layout can be topologically valid while a backend navigation sync
			# fails. Rebuild once under black using another reproducible seed.
			current_generation_seed = (current_generation_seed + 13007) & 0x7fffffff
			_load_procedural_world(current_level, current_generation_seed)
			await get_tree().physics_frame
			navigation_ready = await world.navigation.wait_ready()
			navigation_ready = navigation_ready and world.validate_navigation()
		world.mark_navigation_ready(navigation_ready)
	if not navigation_ready:
		push_error("Navigation failed to synchronize for level %d seed %d" % [current_level, current_generation_seed])
	player.reset_at(world.spawns[rng.randi_range(0, world.spawns.size() - 1)])
	player.active = false
	projectiles.reset_run(is_instance_valid(network) and network.active)
	combat_hud.dismiss()
	ui.show_screen("game")
	if game_modes.selected == GameModeManager.GameplayMode.ENDLESS:
		Settings.record_level(current_level)
		statistics.record_maximum("highest_endless_level", current_level)
	if finish_locally:
		await complete_level_transition(true, animate)
	return navigation_ready

func complete_level_transition(spawn_enemies: bool = true, animate: bool = true) -> void:
	var staged_bots: Array[NextbotEnemy] = []
	if spawn_enemies and is_authority() and world.navigation.synchronized and game_modes.uses_standard_spawner():
		var initial_count: int = mini(maximum_active_bots(), 1 + floori(float(maxi(0, current_level - 4)) / 3.0))
		for index in range(initial_count):
			var bot = _spawn_bot()
			if bot != null:
				bot.enabled = false
				staged_bots.append(bot)
	if animate:
		await ui.fade_from_black()
	mode = Mode.PLAYING
	player.active = true
	player.network_alive = true
	post_boss.level_ready()
	game_modes.reapply_run_rewards()
	if game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT:
		game_modes.bossfight_level_ready()
	for bot in staged_bots:
		if is_instance_valid(bot):
			bot.enabled = true
	transition_in_progress = false
	if game_modes.selected == GameModeManager.GameplayMode.SANDBOX:
		game_modes._capture_sandbox_lighting()
		game_modes.apply_sandbox_lighting()
	if game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT:
		ui.toast("%s %02d\n%s" % ["BOSS ARENA" if game_modes.is_bossfight_boss_level() else "DESERT SECTOR", current_level, game_modes.objective_text()], 4.0)
	else:
		ui.toast("LEVEL %02d\nTHE WAY BACK IS GONE." % current_level, 4.0)

func _record_run() -> void:
	# Settings may be edited while paused; records always belong to the run difficulty.
	new_record = Settings.record_for_map(run_map_index, run_difficulty, survival_time) or new_record
	statistics.record_maximum("best_survival_time", survival_time)

func _select_game_mode(index: int) -> void:
	if mode != Mode.MENU or network.active:
		return
	game_modes.select(index)
	ui.set_mode_description(game_modes)

func finish_arcade_round() -> void:
	if mode != Mode.PLAYING or game_modes.selected != GameModeManager.GameplayMode.ARCADE:
		return
	mode = Mode.RESULT
	events.end_event()
	player.active = false
	projectiles.clear_projectiles()
	projectiles.suspend_input()
	pending_respawns.clear()
	for bot in bots:
		bot.enabled = false
	var result = game_modes.arcade_finished()
	statistics.save_data()
	ui.show_arcade_result(result, game_modes.session_leaderboard)

func spawn_boss_minions(boss: NextbotEnemy) -> void:
	if not is_authority() or not is_instance_valid(boss):
		return
	ui.toast("BOSS PHASE 3\nMINIONS INBOUND", 3.0)
	for index in range(3):
		var minion = _spawn_bot(Vector3.INF, {"max_health": 45.0, "speed_multiplier": 1.15, "respawn_delay": 9999.0, "event_spawned": boss.event_spawned, "event_tag": boss.event_tag})
		if minion != null and boss.event_spawned:
			events.event_bots.append(minion)

func _capture(label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var folder = ProjectSettings.globalize_path("res://tests/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	image.save_png(folder.path_join(label + ".png"))
