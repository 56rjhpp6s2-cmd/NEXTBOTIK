extends RefCounted
## Two actual Godot processes, one ENet server and one client, using loopback UDP.
var failures: Array[String] = []
var checks: int = 0
var folder: String
var run_id: String = "default"
var test_port: int = 24621
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
	var data = extra.duplicate()
	data["stage"] = stage
	var file = FileAccess.open(folder.path_join(run_id + "_" + role + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func read_state(role: String) -> Dictionary:
	var file = FileAccess.open(folder.path_join(run_id + "_" + role + ".json"), FileAccess.READ)
	if file == null:
		return {}
	var content = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(content) != OK or not json.data is Dictionary:
		return {}
	return json.data

func wait_stage(role: String, expected: String, limit: int = 1500) -> Dictionary:
	for frame in range(limit):
		var data = read_state(role)
		if data.get("stage", "") == expected:
			return data
		await game.get_tree().physics_frame
	check(false, "Timed out waiting for " + role + "/" + expected)
	return {}

func run(root) -> void:
	game = root
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--net-run="):
			run_id = argument.trim_prefix("--net-run=").validate_filename()
		if argument.begins_with("--net-port="):
			test_port = int(argument.trim_prefix("--net-port="))
	folder = ProjectSettings.globalize_path("res://").path_join(".godot/network_tests")
	DirAccess.make_dir_recursive_absolute(folder)
	if "--net-test-host" in OS.get_cmdline_user_args():
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

func host_test() -> void:
	if Settings.level_index != 1:
		game._select_map(1)
	await game.world.navigation.wait_ready()
	var error: Error = game.network.host(test_port, "HOST TEST")
	check(error == OK, "ENet server opens UDP port")
	if error != OK:
		finish("HOST")
		return
	game.spawn_timer = 9999
	teleport(1, Vector3(70, 0.1, 106))
	write_state("host", "ready", {"port": test_port})
	var id: int = 0
	for frame in range(1500):
		for peer_id in game.network.peers:
			if peer_id != 1 and game.network.peers[peer_id].ready:
				id = peer_id
		if id > 1:
			break
		await game.get_tree().physics_frame
	check(id > 1, "Client completes real network handshake")
	if id == 0:
		finish("HOST")
		return
	check(game.network.avatars.has(id), "Server creates a visible remote player")
	teleport(id, Vector3(60, 0.1, 84))
	var bot = game._spawn_bot(Vector3(60, 0.1, 96), {"respawn_delay": 0.6})
	await frames(6)
	check(bot.face.texture == game.face_textures[1], "Server spawns the added face as its first enemy")
	bot.enabled = false
	bot._sense()
	check(bot.player == game.network.avatars[id] and bot.state == NextbotEnemy.State.CHASE, "Host AI detects the remote player rather than only the host")
	write_state("host", "shoot", {"bot": bot.bot_index})
	var shot_result = await wait_stage("client", "shot_done")
	check(not is_instance_valid(bot) or bot.combat.health.dead, "Client's five network PNGs kill server enemy")
	check(game.network.peers[id].kills == 1, "Server awards the kill to the correct client")
	check(game.kill_count == 0, "Client kill does not increase host score")
	check(game.projectiles.hit_time == 0, "Host does not receive the client's hitmarker")
	var key = str(shot_result.get("art", ""))
	check(game.network.images.textures.has(key), "Custom PNG is uploaded to server")
	if game.network.images.textures.has(key):
		check(game.network.images.textures[key].get_image().get_pixel(0, 0).a < 0.01, "Network PNG upload preserves transparency")
	await frames(50)
	check(game.bots.size() == 1 and game.bots[0].combat.health.current_health == 100, "Server respawns a killed network enemy with full HP")
	game._clear_bots()
	await frames(3)
	var host_target = game._spawn_bot(Vector3(70, 0.1, 96))
	await frames(6)
	host_target.enabled = false
	write_state("host", "host_shot_prepare", {"bot": host_target.bot_index})
	await wait_stage("client", "host_shot_ready")
	var direction = host_target.global_position + Vector3.UP * 1.4 - game.player.view.camera.global_position
	game.player.rotation.y = atan2(-direction.x, -direction.z)
	game.player.view.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	game.player.view.rotation.x = game.player.view.pitch
	check(game.projectiles.fire() != null, "Host can throw its own network PNG")
	await frames(30)
	check(host_target.combat.health.current_health == 80, "Host projectile deals exactly 20 HP on server")
	write_state("host", "host_shot_done")
	await wait_stage("client", "host_shot_seen")
	game._clear_bots()
	await frames(3)
	var breaker_index: int = 0
	var breaker = game.world.interactables[breaker_index]
	teleport(id, game.world.center(breaker.cell) + Vector3.UP * 0.1)
	write_state("host", "interact", {"item": breaker_index})
	await wait_stage("client", "interacted")
	check(game.breakers == 1 and breaker.used, "Client interaction activates a shared server breaker")
	teleport(id, Vector3(60, 0.1, 84))
	await frames(8)
	var catcher = game._spawn_bot(Vector3(60, 0.1, 84.4), {"face_variant": 1})
	write_state("host", "death", {"face": catcher.face_variant})
	await wait_stage("client", "respawned")
	check(game.network.peers[id].alive and game.network.avatars[id].network_alive, "Client can respawn independently after a bot catch")
	check(game.is_local_playing() and game.network.game_running, "Client death does not stop host or world")
	check(game.breakers == 1, "Individual respawn preserves shared objectives")
	await frames(8)
	check(is_instance_valid(catcher) and catcher.state != NextbotEnemy.State.ATTACK and game.actor_alive(catcher.player), "A bot resumes hunting living players after its victim dies")
	game._clear_bots()
	await frames(3)
	game.network.catch_peer(1, -1)
	write_state("host", "host_dead")
	await wait_stage("client", "host_death_observed")
	check(game.network.game_running and game.mode == game.Mode.RESULT, "Host death keeps the server simulation running")
	game.start_run()
	await frames(5)
	check(game.player.active and game.network.peers[1].alive, "Host can respawn without restarting session")
	for index in range(game.world.interactables.size()):
		var item = game.world.interactables[index]
		if item.kind == "breaker" and not item.used:
			teleport(1, game.world.center(item.cell) + Vector3.UP * 0.1)
			game.network._server_interact(1, index)
	check(game.breakers == 3, "All peers share the same three restored breakers")
	for index in range(game.world.interactables.size()):
		var item = game.world.interactables[index]
		if item.kind == "exit":
			teleport(1, game.world.center(item.cell) + Vector3.UP * 0.1)
			game.network._server_interact(1, index)
	for frame in range(900):
		if game.network.game_running and not game.network.transitioning and game.current_level == 2:
			break
		await game.get_tree().physics_frame
	write_state("host", "victory")
	await wait_stage("client", "victory_seen")
	check(game.network.game_running and game.current_level == 2 and game.mode == game.Mode.PLAYING, "Shared extraction advances every peer to authored Level 2")
	write_state("host", "victory_rejoin")
	await wait_stage("client", "victory_rejoined")
	game.network.restart_round()
	game.spawn_timer = 9999
	await wait_stage("client", "restarted")
	check(game.network.game_running and game.breakers == 0 and game.current_level == 1, "Host restarts a fresh shared progression")
	var existing = game._spawn_bot(Vector3(66, 0.1, 96), {"max_health": 140.0})
	await frames(6)
	existing.enabled = false
	game.damage_system.apply_hit(existing, 20, game.player, existing.global_position + Vector3.UP, Vector3.BACK)
	teleport(1, game.world.center(breaker.cell) + Vector3.UP * 0.1)
	game.network._server_interact(1, breaker_index)
	write_state("host", "rejoin", {"bot": existing.bot_index, "hp": 120})
	await wait_stage("client", "rejoined")
	check(game.network.peers.size() == 2 and game.network.avatars.size() == 1, "Reconnect replaces the old player without ghosts")
	game._clear_bots()
	for next_level in [2, 3, 4]:
		await game.network.advance_level()
		await frames(5)
	check(game.current_level == 4 and game.world is ProceduralLevelWorld and game.world.navigation_status == "READY", "Host reaches synchronized procedural Level 4")
	write_state("host", "procedural_synced", {"seed": game.current_generation_seed, "rooms": game.world.generated_room_count})
	await wait_stage("client", "procedural_seen")
	write_state("host", "closing")
	await game.network.disconnect_session("", false)
	await frames(10)
	finish("HOST")

func client_test() -> void:
	var ready = await wait_stage("host", "ready")
	if ready.is_empty():
		finish("CLIENT")
		return
	check(game.network.join("127.0.0.1", test_port, "CLIENT TEST") == OK, "ENet client begins loopback connection")
	for frame in range(1500):
		if game.network.active and game.network.game_running and not game.network.loading and game.player.active:
			break
		await game.get_tree().physics_frame
	check(game.network.game_running and not game.network.loading, "Client loads host's selected map and enters game")
	check(game.world.map_id == "construct" and game.network.local_id() != 1, "Client uses host map and its own peer identity")
	check(game.network.avatars.has(1), "Client sees host avatar")
	check(game.player.view.camera.current, "Remote avatars do not steal local camera")
	var stage = await wait_stage("host", "shoot")
	var bot_id = int(stage.get("bot", -1))
	for frame in range(180):
		if game.network.replicas.has(bot_id) and game.player.global_position.distance_to(Vector3(60, 0, 84)) < 1:
			break
		await game.get_tree().physics_frame
	check(game.network.replicas.has(bot_id), "Server Nextbot appears on client")
	check(game.network.replicas.has(bot_id) and game.network.replicas[bot_id].face.texture == game.face_textures[1], "Client sees the same added photo as the host")
	var before_move: Vector3 = game.player.global_position
	Input.action_press("right")
	await frames(12)
	Input.action_release("right")
	await frames(10)
	check(game.player.global_position.distance_to(before_move) > 0.2, "Client retains responsive local movement")
	game.pause_run()
	var paused_time: float = game.survival_time
	await frames(10)
	check(not game.get_tree().paused and game.survival_time > paused_time and not game.player.active and game.player.network_alive, "Online pause stops local input while shared world keeps running")
	game.resume_run()
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(8, 24):
		for x in range(8, 24):
			image.set_pixel(x, y, Color("ed5ca5"))
	var custom_path = game.png_images.directory.path_join("network_test_custom.png")
	image.save_png(custom_path)
	game.png_images.refresh(true)
	game.png_images.select_filename("network_test_custom.png")
	await frames(6)
	var key = game.network.selected_art
	for hit in range(5):
		var direction = Vector3(60, 1.4, 96) - game.player.view.camera.global_position
		game.player.rotation.y = atan2(-direction.x, -direction.z)
		game.player.view.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		game.player.view.rotation.x = game.player.view.pitch
		if hit == 0 and "--capture-network-client" in OS.get_cmdline_user_args():
			await game._capture("network_play")
		var shot = game.projectiles.fire()
		check(shot != null, "Client fires network projectile %d" % (hit + 1))
		await frames(28)
		if hit < 4:
			check(game.network.replicas.has(bot_id) and game.network.replicas[bot_id].combat.health.current_health == 100 - (hit + 1) * 20, "Authoritative hit %d subtracts exactly 20 HP on client" % (hit + 1))
	check(game.network.received_hits >= 5, "Client receives authoritative hit confirmations")
	await frames(5)
	check(game.kill_count == 1, "Client kill counter matches authoritative score")
	check(game.network.received_snapshots > 10, "World snapshots update continuously")
	write_state("client", "shot_done", {"art": key})
	stage = await wait_stage("host", "host_shot_prepare")
	var host_target_id = int(stage.get("bot", -1))
	for frame in range(120):
		if game.network.replicas.has(host_target_id):
			break
		await game.get_tree().physics_frame
	write_state("client", "host_shot_ready")
	await wait_stage("host", "host_shot_done")
	await frames(8)
	check(game.network.received_shots >= 6, "Client receives host's visible projectile event")
	check(game.network.replicas.has(host_target_id) and game.network.replicas[host_target_id].combat.health.current_health == 80, "Client sees host's exact 20 HP damage")
	check(game.kill_count == 1, "Host's nonlethal hit preserves client's own score")
	write_state("client", "host_shot_seen")
	stage = await wait_stage("host", "interact")
	await frames(10)
	game.network.request_interact(int(stage.item))
	for frame in range(180):
		if game.breakers == 1:
			break
		await game.get_tree().physics_frame
	check(game.breakers == 1 and game.world.interactables[int(stage.item)].used, "Shared breaker state returns to client")
	write_state("client", "interacted")
	var death_stage = await wait_stage("host", "death")
	for frame in range(300):
		if game.mode == game.Mode.RESULT:
			break
		await game.get_tree().physics_frame
	check(game.mode == game.Mode.RESULT and game.ui.result_title.text == "РОССИЯ ПУТИН ПОБЕДА", "Client bot catch shows local jumpscare and custom death screen")
	check(game.ui.scare_image.texture == game.face_for_variant(int(death_stage.face)), "Client jumpscare displays the catching enemy's synced photo")
	game.start_run()
	for frame in range(180):
		if game.is_local_playing():
			break
		await game.get_tree().physics_frame
	check(game.is_local_playing() and game.breakers == 1, "Client respawns without resetting world or objectives")
	write_state("client", "respawned")
	await wait_stage("host", "host_dead")
	await frames(80)
	var time_before: float = game.survival_time
	await frames(20)
	check(game.is_local_playing() and game.survival_time > time_before, "Client keeps playing while host is on death screen")
	check(game.network.peers.has(1) and not game.network.peers[1].alive, "Host's dead state is replicated")
	write_state("client", "host_death_observed")
	await wait_stage("host", "victory")
	for frame in range(300):
		if game.network.game_running and not game.network.transitioning and game.current_level == 2:
			break
		await game.get_tree().physics_frame
	check(game.current_level == 2 and game.mode == game.Mode.PLAYING, "Shared extraction loads authored Level 2 on client")
	var old_epoch: int = game.network.epoch
	var expected_difficulty: int = game.run_difficulty
	write_state("client", "victory_seen")
	await wait_stage("host", "victory_rejoin")
	await game.network.disconnect_session()
	await frames(5)
	game.network.join("127.0.0.1", test_port, "CLIENT VICTORY JOIN")
	for frame in range(600):
		if game.network.active and game.network.game_running and not game.network.loading and game.current_level == 2:
			break
		await game.get_tree().physics_frame
	check(game.network.game_running and game.current_level == 2 and game.mode == game.Mode.PLAYING, "Joining mid-progression reproduces the host's current level")
	Settings.difficulty = (expected_difficulty + 1) % 3
	write_state("client", "victory_rejoined")
	for frame in range(300):
		if game.network.epoch > old_epoch and game.is_local_playing():
			break
		await game.get_tree().physics_frame
	check(game.network.epoch > old_epoch and game.breakers == 0 and game.kill_count == 0 and game.current_level == 1, "New shared progression resets client objectives, level and scores")
	check(game.run_difficulty == expected_difficulty, "New round uses host difficulty even if guest changed preferences")
	write_state("client", "restarted")
	stage = await wait_stage("host", "rejoin")
	await game.network.disconnect_session()
	await frames(5)
	check(game.mode == game.Mode.MENU and not game.network.active, "Leaving a server restores standalone menu")
	game.network.join("127.0.0.1", test_port, "CLIENT REJOIN")
	for frame in range(600):
		if game.network.game_running and not game.network.loading and game.player.active:
			break
		await game.get_tree().physics_frame
	await frames(15)
	check(game.network.game_running and game.breakers == 1, "Late join receives already completed objective state")
	check(game.network.replicas.has(int(stage.bot)) and game.network.replicas[int(stage.bot)].combat.health.current_health == 120, "Late join receives existing enemy's damaged HP")
	check(game.network.avatars.size() == 1, "Rejoin has one remote host and no stale avatars")
	write_state("client", "rejoined")
	var procedural_stage = await wait_stage("host", "procedural_synced")
	for frame in range(600):
		if game.network.game_running and not game.network.transitioning and game.current_level == 4:
			break
		await game.get_tree().physics_frame
	check(game.world is ProceduralLevelWorld and game.current_level == 4, "Client installs the synchronized procedural Level 4 world")
	check(game.current_generation_seed == int(procedural_stage.seed) and game.world.generated_room_count == int(procedural_stage.rooms), "Client procedural seed and room count match the host")
	check(game.world.navigation_status == "READY", "Client enables play only after procedural navigation is ready")
	write_state("client", "procedural_seen")
	await wait_stage("host", "closing")
	for frame in range(300):
		if not game.network.active:
			break
		await game.get_tree().physics_frame
	await frames(6)
	check(not game.network.active and game.mode == game.Mode.MENU, "Host shutdown returns client to menu cleanly")
	finish("CLIENT")

func finish(role: String) -> void:
	print("NETWORK %s TEST: %d checks, %d failures" % [role, checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)
