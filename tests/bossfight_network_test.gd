extends RefCounted
## Two-process Bossfight regression: mode/seed handoff, shared switches,
## synchronized transitions, the two-state boss and post-boss scaling.
var failures: Array[String] = []
var checks: int = 0
var folder: String
var run_id: String = "default"
var test_port: int = 24631
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

func write_state(role: String, stage: String, extra: Dictionary = {}) -> void:
	var data := extra.duplicate()
	data["stage"] = stage
	var file := FileAccess.open(folder.path_join(run_id + "_bossfight_" + role + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func read_state(role: String) -> Dictionary:
	var file := FileAccess.open(folder.path_join(run_id + "_bossfight_" + role + ".json"), FileAccess.READ)
	if file == null:
		return {}
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) != OK or not json.data is Dictionary:
		return {}
	return json.data

func wait_stage(role: String, expected: String, limit: int = 1800) -> Dictionary:
	for frame in range(limit):
		var data := read_state(role)
		if data.get("stage", "") == expected:
			return data
		await game.get_tree().physics_frame
	check(false, "Timed out waiting for %s/%s" % [role, expected])
	return {}

func run(root) -> void:
	game = root
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--net-run="):
			run_id = argument.trim_prefix("--net-run=").validate_filename()
		elif argument.begins_with("--net-port="):
			test_port = int(argument.trim_prefix("--net-port="))
	folder = ProjectSettings.globalize_path("res://").path_join(".godot/network_tests")
	DirAccess.make_dir_recursive_absolute(folder)
	if "--bossfight-net-test-host" in OS.get_cmdline_user_args():
		await host_test()
	else:
		await client_test()

func teleport(id: int, at: Vector3) -> void:
	var state = game.network.peers[id]
	state.p = at
	state.v = Vector3.ZERO
	state.yaw = PI
	state.last_pose = Time.get_ticks_msec()
	game.network._apply_actor(id, state, "correction")
	game.network._actor.rpc(game.network.epoch, id, state, "correction")
	if id == 1:
		game.player.global_position = at

func wait_level(level: int, limit: int = 1800) -> bool:
	for frame in range(limit):
		if game.network.game_running and not game.network.transitioning and game.current_level == level:
			return true
		await game.get_tree().physics_frame
	return false

func disable_stage_enemies() -> void:
	game.spawn_timer = INF
	game._clear_bots()

func complete_stage() -> void:
	disable_stage_enemies()
	for index in range(game.world.interactables.size()):
		var item = game.world.interactables[index]
		if item.kind == "breaker" and not item.used:
			teleport(1, game.world.center(item.cell) + Vector3.UP * 0.1)
			game.network._server_interact(1, index)
	check(game.breakers == 3, "Host activates all three shared Bossfight switches on Level %d" % game.current_level)
	for index in range(game.world.interactables.size()):
		var item = game.world.interactables[index]
		if item.kind == "exit":
			teleport(1, game.world.center(item.cell) + Vector3.UP * 0.1)
			game.network._server_interact(1, index)
			return
	check(false, "Bossfight stage exposes a network exit")

func host_test() -> void:
	game.game_modes.select(GameModeManager.GameplayMode.BOSSFIGHT, false)
	var error: Error = game.network.host(test_port, "BOSS HOST")
	check(error == OK, "Bossfight host opens an ENet server")
	if error != OK:
		finish("HOST")
		return
	disable_stage_enemies()
	var client_id := 0
	for frame in range(1800):
		for peer_id in game.network.peers:
			if peer_id != 1 and game.network.peers[peer_id].ready:
				client_id = peer_id
		if client_id > 1:
			break
		await game.get_tree().physics_frame
	check(client_id > 1, "Bossfight client completes the protocol-5 handshake")
	if client_id == 0:
		finish("HOST")
		return
	check(game.game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT and game.world is BossfightWorld, "Host retains Bossfight instead of being forced into Endless")
	write_state("host", "stage1", {"seed": game.current_generation_seed, "signature": game.world.objective_signature})
	await wait_stage("client", "stage1_seen")
	var first_switch := -1
	for index in range(game.world.interactables.size()):
		if game.world.interactables[index].kind == "breaker":
			first_switch = index
			break
	teleport(client_id, game.world.center(game.world.interactables[first_switch].cell) + Vector3.UP * 0.1)
	write_state("host", "interact", {"item": first_switch})
	await wait_stage("client", "interacted")
	check(game.breakers == 1 and game.world.interactables[first_switch].used, "Guest can activate a randomized Bossfight switch")
	complete_stage()
	check(await wait_level(2), "All peers advance to Bossfight Level 2")
	disable_stage_enemies()
	write_state("host", "level2", {"seed": game.current_generation_seed, "signature": game.world.objective_signature})
	await wait_stage("client", "level2_seen")
	complete_stage()
	check(await wait_level(3), "All peers advance to Bossfight Level 3")
	disable_stage_enemies()
	write_state("host", "level3", {"seed": game.current_generation_seed, "signature": game.world.objective_signature})
	await wait_stage("client", "level3_seen")
	complete_stage()
	check(await wait_level(4), "All peers enter the shared Sun Ring on Level 4")
	var boss: NextbotEnemy
	for frame in range(600):
		if is_instance_valid(game.game_modes.active_boss):
			boss = game.game_modes.active_boss
			break
		await game.get_tree().physics_frame
	check(is_instance_valid(boss) and boss.max_health == 4000.0, "Authority spawns the first 4,000-HP boss")
	if not is_instance_valid(boss):
		finish("HOST")
		return
	boss.enabled = false
	write_state("host", "boss", {"id": boss.bot_index})
	await wait_stage("client", "boss_seen")
	boss._set_attack_visual(true)
	await frames(10)
	write_state("host", "attack")
	await wait_stage("client", "attack_seen")
	boss._set_attack_visual(false)
	game.damage_system.apply_hit(boss, 20.0, game.player, boss.global_position + Vector3.UP, Vector3.BACK)
	await frames(10)
	write_state("host", "damage", {"hp": boss.combat.health.current_health})
	await wait_stage("client", "damage_seen")
	game.damage_system.apply_hit(boss, boss.combat.health.current_health, game.player, boss.global_position + Vector3.UP, Vector3.BACK)
	check(await wait_level(5), "Boss death advances the entire session to the next three-stage cycle")
	disable_stage_enemies()
	write_state("host", "level5", {"seed": game.current_generation_seed, "signature": game.world.objective_signature})
	await wait_stage("client", "level5_seen")
	await game.network.disconnect_session("", false)
	await frames(8)
	finish("HOST")

func client_test() -> void:
	# The host is already listening before it publishes stage1; retry connection
	# startup briefly to avoid depending on process launch order.
	await frames(20)
	check(game.network.join("127.0.0.1", test_port, "BOSS CLIENT") == OK, "Bossfight guest begins loopback connection")
	for frame in range(1800):
		if game.network.game_running and not game.network.loading and game.player.active:
			break
		await game.get_tree().physics_frame
	var stage := await wait_stage("host", "stage1")
	check(game.game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT, "Host-selected Bossfight mode is synchronized to the guest")
	check(game.world is BossfightWorld and game.current_level == 1, "Guest builds Dust Quarter Level 1")
	check(game.current_generation_seed == int(stage.seed) and game.world.objective_signature == str(stage.signature), "Level 1 seed and randomized switch layout match the host")
	write_state("client", "stage1_seen")
	stage = await wait_stage("host", "interact")
	game.network.request_interact(int(stage.item))
	for frame in range(300):
		if game.breakers == 1:
			break
		await game.get_tree().physics_frame
	check(game.breakers == 1, "Guest receives authoritative shared-switch state")
	write_state("client", "interacted")
	stage = await wait_stage("host", "level2")
	check(await wait_level(2), "Guest resumes on Bossfight Level 2")
	check(game.current_generation_seed == int(stage.seed) and game.world.objective_signature == str(stage.signature), "Level 2 rerolled switches are deterministic on both peers")
	write_state("client", "level2_seen")
	stage = await wait_stage("host", "level3")
	check(await wait_level(3), "Guest resumes on Bossfight Level 3")
	check(game.current_generation_seed == int(stage.seed) and game.world.objective_signature == str(stage.signature), "Level 3 switch layout matches the authority")
	write_state("client", "level3_seen")
	stage = await wait_stage("host", "boss")
	check(await wait_level(4), "Guest loads the dedicated Sun Ring arena")
	var boss_id := int(stage.id)
	for frame in range(600):
		if game.network.replicas.has(boss_id):
			break
		await game.get_tree().physics_frame
	var boss = game.network.replicas.get(boss_id)
	check(is_instance_valid(boss) and boss.is_boss and boss.max_health == 4000.0, "Guest receives the 4,000-HP boss replica")
	check(is_instance_valid(boss) and boss.face.texture == GameModeManager.BOSSFIGHT_IDLE_FACE, "Guest boss uses the supplied idle photograph")
	check(game.game_modes.active_boss == boss, "Guest HUD is bound to the replicated boss health")
	write_state("client", "boss_seen")
	await wait_stage("host", "attack")
	await frames(12)
	check(is_instance_valid(boss) and boss.attack_visual_active and boss.face.texture == GameModeManager.BOSSFIGHT_ATTACK_FACE, "Boss attack photograph is synchronized to the guest")
	write_state("client", "attack_seen")
	stage = await wait_stage("host", "damage")
	await frames(12)
	check(is_instance_valid(boss) and boss.combat.health.current_health == float(stage.hp) and float(stage.hp) == 3980.0, "Boss damage and HP bar are authoritative on the guest")
	write_state("client", "damage_seen")
	stage = await wait_stage("host", "level5")
	check(await wait_level(5), "Guest continues online after the boss into Level 5")
	check(game.game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT and game.world is BossfightWorld, "Bossfight mode remains active after the online boss transition")
	check(game.current_generation_seed == int(stage.seed) and game.world.objective_signature == str(stage.signature), "Post-boss Level 5 seed and objectives match the host")
	write_state("client", "level5_seen")
	for frame in range(300):
		if not game.network.active:
			break
		await game.get_tree().physics_frame
	check(not game.network.active, "Host shutdown closes the Bossfight session cleanly")
	finish("CLIENT")

func finish(role: String) -> void:
	print("BOSSFIGHT NETWORK %s TEST: %d checks, %d failures" % [role, checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)
