extends Node
## ENet listen-server cooperative session. Gameplay authority stays on peer 1.
signal status_changed(message: String)
const PROTOCOL: int = 5
const MAX_PLAYERS: int = 8
const RemoteActor = preload("res://scripts/network/remote_player.gd")
const NetworkImages = preload("res://scripts/network/network_images.gd")
var session
var active: bool = false
var connected: bool = false
var game_running: bool = false
var loading: bool = false
var port: int = 24577
var epoch: int = 0
var peers: Dictionary = {}
var avatars: Dictionary = {}
var replicas: Dictionary = {}
var bot_targets: Dictionary = {}
var shots: Dictionary = {}
var predicted: Dictionary = {}
var ended_shots: Dictionary = {}
var images = NetworkImages.new()
var announced_images: Dictionary = {}
var selected_art: String = ""
var sequence: int = 0
var shot_id: int = 0
var send_time: float = 0.0
var connect_time: float = 0.0
var original_map: int = 0
var original_difficulty: int = 1
var original_game_mode: int = GameModeManager.GameplayMode.ENDLESS
var received_snapshots: int = 0
var received_hits: int = 0
var received_shots: int = 0
var closing: bool = false
var transition_acks: Dictionary = {}
var transition_level: int = 1
var transition_seed: int = 0
var transitioning: bool = false

func _ready() -> void:
	name = "NetworkSession"
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	multiplayer.peer_disconnected.connect(_peer_left)
	session.damage_system.hit_applied.connect(_on_damage)
	session.png_images.image_selected.connect(_image_changed)

func is_host() -> bool:
	return active and _transport_connected() and multiplayer.is_server()

func _transport_connected() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func local_id() -> int:
	return multiplayer.get_unique_id() if active and connected and _transport_connected() else 1

func host(listen_port: int = 24577, player_name: String = "PLAYER") -> Error:
	if active:
		return ERR_ALREADY_IN_USE
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(listen_port, MAX_PLAYERS - 1, 3)
	if error != OK:
		status_changed.emit("Не удалось создать UDP-сервер: %s. Попробуйте другой порт." % error_string(error))
		return error
	_remember_settings()
	port = listen_port
	multiplayer.multiplayer_peer = peer
	active = true
	connected = true
	epoch = int(Time.get_unix_time_from_system())
	session.start_run(true)
	peers[1] = _new_peer(1, player_name, session.player.global_position)
	peers[1].ready = true
	game_running = true
	session.projectiles.unlimited_ammo = true
	session.network_menu.panel.visible = false
	_prepare_art()
	status_changed.emit("Сервер создан. Подключайтесь по IP хоста из Radmin VPN, UDP %d." % port)
	return OK

func join(address: String, listen_port: int = 24577, player_name: String = "PLAYER") -> Error:
	if active:
		return ERR_ALREADY_IN_USE
	if not address.is_valid_ip_address():
		status_changed.emit("Введите IP хоста из Radmin VPN, без кавычек и номера порта.")
		return ERR_INVALID_PARAMETER
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, listen_port, 3)
	if error != OK:
		status_changed.emit("Не удалось начать подключение: " + error_string(error))
		return error
	_remember_settings()
	Settings.network_name = player_name.strip_edges().left(20)
	port = listen_port
	multiplayer.multiplayer_peer = peer
	active = true
	connected = false
	connect_time = 0.0
	status_changed.emit("Подключение к %s:%d…" % [address, port])
	return OK

func _remember_settings() -> void:
	original_map = Settings.level_index
	original_difficulty = Settings.difficulty
	original_game_mode = int(session.game_modes.selected)

func disconnect_session(reason: String = "", return_to_menu: bool = true) -> void:
	if closing:
		return
	closing = true
	var was_active = active
	var was_connected = connected
	if active and connected and _transport_connected():
		if is_host():
			_shutdown.rpc()
		else:
			_goodbye.rpc_id(1)
	active = false
	connected = false
	game_running = false
	loading = false
	if was_active:
		session.player.active = false
		if return_to_menu:
			session.mode = session.Mode.MENU
	if was_active and was_connected:
		await get_tree().process_frame
		await get_tree().process_frame
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for actor in avatars.values():
		if is_instance_valid(actor):
			actor.queue_free()
	avatars.clear()
	peers.clear()
	replicas.clear()
	bot_targets.clear()
	shots.clear()
	predicted.clear()
	ended_shots.clear()
	announced_images.clear()
	images = NetworkImages.new()
	selected_art = ""
	send_time = 0.0
	closing = false
	if was_active and return_to_menu:
		session.return_to_menu()
		Settings.difficulty = original_difficulty
		session.game_modes.select(original_game_mode, false)
		if Settings.level_index != original_map:
			session._select_map(original_map)
		session.ui.set_mode_description(session.game_modes)
		Settings.save()
		session.ui.show_screen("menu")
	if not reason.is_empty():
		status_changed.emit(reason)
		if is_instance_valid(session.network_menu):
			session.network_menu.open()

@rpc("authority", "call_remote", "reliable", 0)
func _shutdown() -> void:
	if active:
		disconnect_session("Хост завершил сервер.")

@rpc("any_peer", "call_remote", "reliable", 0)
func _goodbye() -> void:
	if is_host():
		var id = multiplayer.get_remote_sender_id()
		_peer_left(id)

func _connected() -> void:
	if not active:
		return
	connected = true
	status_changed.emit("Соединение установлено. Загрузка карты хоста…")
	_hello.rpc_id(1, PROTOCOL, Settings.network_name)

func _connection_failed() -> void:
	if active:
		disconnect_session("Хост не отвечает. Проверьте IP, порт, Radmin VPN и разрешение игры в брандмауэре.")

func _server_disconnected() -> void:
	if active:
		disconnect_session("Хост отключился. Соединение закрыто.")

func _peer_left(id: int) -> void:
	if not active:
		return
	if avatars.has(id):
		var actor = avatars[id]
		session.projectiles.clear_owned_projectiles(actor)
		actor.queue_free()
		avatars.erase(id)
	peers.erase(id)
	if is_host():
		_peer_removed.rpc(epoch, id)

@rpc("authority", "call_remote", "reliable", 0)
func _peer_removed(round_id: int, id: int) -> void:
	if not active or round_id != epoch:
		return
	_peer_left(id)

func _new_peer(id: int, player_name: String, at: Vector3) -> Dictionary:
	return {"id": id, "name": player_name.strip_edges().left(20), "p": at, "v": Vector3.ZERO, "yaw": PI, "pitch": 0.0, "alive": true, "ready": false, "hidden": false, "hide_left": 0.0, "hide_cooldown": 0.0, "hide_item": -1, "light": true, "battery": 100.0, "crouch": false, "kills": 0, "next_fire": 0.0, "last_seq": 0, "last_pose": Time.get_ticks_msec(), "last_step": 0.0, "art": ""}

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(version: int, player_name: String) -> void:
	if not is_host():
		return
	var id = multiplayer.get_remote_sender_id()
	if id <= 1 or peers.has(id):
		return
	if version != PROTOCOL or peers.size() >= MAX_PLAYERS:
		_refused.rpc_id(id, "Несовместимая версия игры или сервер заполнен.")
		return
	var state = _new_peer(id, player_name, _choose_spawn())
	state.alive = false
	peers[id] = state
	_ensure_avatar(id, state)
	var data = _snapshot()
	data["map"] = session.run_map_index
	data["difficulty"] = session.run_difficulty
	_welcome.rpc_id(id, epoch, data)
	for key in images.buffers:
		_art.rpc_id(id, key, images.buffers[key])

@rpc("authority", "call_remote", "reliable", 0)
func _refused(message: String) -> void:
	disconnect_session(message)

@rpc("authority", "call_remote", "reliable", 0)
func _welcome(round_id: int, data: Dictionary) -> void:
	if not active or is_host():
		return
	epoch = round_id
	loading = true
	game_running = false
	session.prepare_network_world(int(data.map), int(data.difficulty), int(data.get("level", 1)), int(data.get("seed", 0)), int(data.get("mode", GameModeManager.GameplayMode.ENDLESS)))
	session.start_run(true, int(data.get("level", 1)), int(data.get("seed", 0)))
	session.player.active = false
	session.player.network_alive = false
	game_running = true
	_apply_snapshot(data)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await session.world.navigation.wait_ready()
	if active:
		_client_ready.rpc_id(1, epoch)

@rpc("any_peer", "call_remote", "reliable", 0)
func _client_ready(round_id: int) -> void:
	if not is_host() or round_id != epoch:
		return
	var id = multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	peers[id].ready = true
	_spawn_peer(id)
	if not game_running:
		_round_finished.rpc_id(id, epoch)

func _spawn_peer(id: int) -> void:
	if not peers.has(id):
		return
	var state = peers[id]
	state.p = _choose_spawn()
	state.v = Vector3.ZERO
	state.alive = true
	state.hidden = false
	state.hide_left = 0.0
	state.hide_cooldown = 0.0
	state.hide_item = -1
	state.light = true
	state.battery = 100.0
	state.last_pose = Time.get_ticks_msec()
	_apply_actor(id, state, "spawn")
	_actor.rpc(epoch, id, state, "spawn")

func _choose_spawn() -> Vector3:
	var best = session.world.spawns[0]
	var best_score: float = -1.0
	for point in session.world.spawns:
		var score: float = 200.0
		for bot in session.bots:
			score = minf(score, point.distance_to(bot.global_position))
		for state in peers.values():
			if state.alive and state.ready:
				score = minf(score, point.distance_to(state.p))
		if score > best_score:
			best = point
			best_score = score
	return best

func actor_for(id: int) -> PlayerController:
	if id == local_id():
		return session.player
	return avatars.get(id)

func peer_for(actor) -> int:
	if not is_instance_valid(actor):
		return 0
	if actor == session.player:
		return local_id()
	if is_instance_valid(actor) and actor.has_meta("peer_id"):
		return int(actor.get_meta("peer_id"))
	return 0

func _ensure_avatar(id: int, state: Dictionary) -> void:
	if id == local_id():
		return
	if not avatars.has(id):
		var actor = RemoteActor.new()
		actor.peer_id = id
		actor.player_name = str(state.name)
		actor.session = session
		actor.name = "RemotePlayer%d" % id
		actor.set_meta("peer_id", id)
		actor.process_mode = Node.PROCESS_MODE_PAUSABLE
		session.add_child(actor)
		avatars[id] = actor
	avatars[id].apply_pose(state)

@rpc("authority", "call_remote", "reliable", 0)
func _actor(round_id: int, id: int, state: Dictionary, event: String) -> void:
	if not active or round_id != epoch:
		return
	peers[id] = state
	_apply_actor(id, state, event)

func _apply_actor(id: int, state: Dictionary, event: String) -> void:
	if id != local_id():
		_ensure_avatar(id, state)
		avatars[id].apply_pose(state, event in ["spawn", "hide", "unhide"])
		return
	if event == "spawn":
		loading = false
		session.network_spawn_local(state)
		session.network_menu.panel.visible = false
		_prepare_art()
	elif event in ["hide", "unhide", "correction"]:
		session.apply_network_actor(state)

func _collect_pose() -> Dictionary:
	var p = session.player
	return {"p": p.global_position, "v": p.velocity, "yaw": p.rotation.y, "pitch": p.view.pitch, "crouch": p.crouching, "light": p.view.flashlight_on, "art": selected_art}

func _process(delta: float) -> void:
	if not active:
		return
	if not connected:
		connect_time += delta
		if connect_time > 12.0:
			_connection_failed()
		return
	if not game_running:
		return
	if is_host():
		_tick_players(delta)
	else:
		for id in bot_targets:
			if replicas.has(id) and is_instance_valid(replicas[id]) and not replicas[id].combat.dead:
				var bot = replicas[id]
				bot.global_position = bot.global_position.lerp(bot_targets[id], 1.0 - exp(-delta * 18.0))
				bot.face.position.y = 1.45 + sin(Time.get_ticks_msec() * 0.006) * 0.055
	send_time += delta
	if send_time >= 0.05:
		send_time = 0.0
		if is_host():
			_accept_pose(1, _collect_pose())
			if multiplayer.get_peers().size() > 0:
				# Shots use reliable events; only late join needs their full list.
				_world_state.rpc(epoch, var_to_bytes(_snapshot(false)).compress(FileAccess.COMPRESSION_DEFLATE))
		elif not loading:
			_pose.rpc_id(1, epoch, _collect_pose())

func _tick_players(delta: float) -> void:
	for id in peers:
		var state = peers[id]
		state.hide_cooldown = maxf(0.0, state.hide_cooldown - delta)
		if not state.ready or not state.alive:
			continue
		if state.light and not state.hidden:
			state.battery = maxf(0.0, state.battery - 0.38 * delta)
		if state.hidden:
			state.hide_left -= delta
			if state.hide_left <= 0.0:
				_unhide(id)
		if state.p.y < -8.0:
			catch_peer(id, -1)
		if id == 1:
			session.player.view.battery = state.battery
			session.hide_remaining = state.hide_left

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _pose(round_id: int, data: Dictionary) -> void:
	if is_host() and round_id == epoch:
		_accept_pose(multiplayer.get_remote_sender_id(), data)

func _accept_pose(id: int, data: Dictionary) -> void:
	if not peers.has(id) or not peers[id].ready or not peers[id].alive:
		return
	var p = data.get("p", Vector3.INF)
	var v = data.get("v", Vector3.INF)
	var coordinate_limit = 4096.0 if session.world is ProceduralLevelWorld else 256.0
	if not p is Vector3 or not v is Vector3 or not p.is_finite() or not v.is_finite() or absf(p.x) > coordinate_limit or absf(p.z) > coordinate_limit or p.y < -30 or p.y > 50:
		return
	if not is_finite(float(data.get("yaw", INF))) or not is_finite(float(data.get("pitch", INF))):
		return
	var state = peers[id]
	var now = Time.get_ticks_msec()
	var elapsed = clampf(float(now - state.last_pose) / 1000.0, 0.01, 0.5)
	if id != 1 and not state.hidden and state.p.distance_to(p) > 28.0 * elapsed + 1.5:
		_actor.rpc_id(id, epoch, id, state, "correction")
		return
	state.last_pose = now
	if not state.hidden:
		state.p = p
		state.v = v.limit_length(26)
		state.light = bool(data.get("light", true))
	state.yaw = wrapf(float(data.yaw), -PI, PI)
	state.pitch = clampf(float(data.pitch), -1.48, 1.48)
	state.crouch = bool(data.get("crouch", false))
	if images.textures.has(str(data.get("art", ""))):
		state.art = str(data.art)
	if id != 1:
		_ensure_avatar(id, state)

func _snapshot(include_shots: bool = true) -> Dictionary:
	var actors: Array = []
	for state in peers.values():
		var visible_state: Dictionary = {}
		for key in ["id", "name", "p", "v", "yaw", "pitch", "alive", "ready", "hidden", "hide_left", "light", "battery", "crouch", "kills"]:
			visible_state[key] = state[key]
		actors.append(visible_state)
	var enemies: Array = []
	for bot in session.bots:
		if is_instance_valid(bot) and not bot.combat.dead:
			enemies.append({"id": bot.bot_index, "p": bot.global_position, "hp": bot.combat.health.current_health, "max": bot.max_health, "face": bot.face_variant, "state": int(bot.state), "target": peer_for(bot.player), "boss": bot.is_boss, "scale": bot.face_scale, "attack": bot.attack_visual_active})
	var projectiles: Array = []
	if include_shots:
		for projectile in shots.values():
			if is_instance_valid(projectile) and not projectile.spent:
				projectiles.append(_shot_data(projectile))
	var used: Array = []
	for i in range(session.world.interactables.size()):
		if session.world.interactables[i].used:
			used.append(i)
	return {"time": session.survival_time, "breakers": session.breakers, "level": session.current_level, "seed": session.current_generation_seed, "mode": int(session.game_modes.selected), "players": actors, "bots": enemies, "shots": projectiles, "used": used, "refuges": session.world.refuge_charge.duplicate(), "running": game_running}

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _world_state(round_id: int, packet: PackedByteArray) -> void:
	if active and not is_host() and round_id == epoch and game_running:
		if packet.size() > 32768:
			return
		var bytes = packet.decompress_dynamic(65536, FileAccess.COMPRESSION_DEFLATE)
		if bytes.size() < 4:
			return
		var data = bytes_to_var(bytes)
		if not data is Dictionary:
			return
		received_snapshots += 1
		_apply_snapshot(data)

func _apply_snapshot(data: Dictionary) -> void:
	if not data.has("time"):
		return
	session.survival_time = float(data.time)
	session.breakers = int(data.breakers)
	session.world.refuge_charge = data.refuges
	for state in data.players:
		var id = int(state.id)
		peers[id] = state
		if id != local_id():
			_ensure_avatar(id, state)
		else:
			session.kill_count = int(state.kills)
			session.player.view.battery = float(state.battery)
			session.hide_remaining = float(state.hide_left)
	for index in data.used:
		if int(index) >= 0 and int(index) < session.world.interactables.size():
			var item = session.world.interactables[int(index)]
			if not item.used:
				item.activate()
	var present: Dictionary = {}
	for state in data.bots:
		var id = int(state.id)
		present[id] = true
		if not replicas.has(id) or not is_instance_valid(replicas[id]):
			var boss := bool(state.get("boss", false))
			var stats := {"max_health": float(state.max), "network_id": id, "face_variant": int(state.face), "boss": boss, "face_scale": float(state.get("scale", 1.0))}
			if boss and session.game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT:
				stats["custom_face"] = GameModeManager.BOSSFIGHT_IDLE_FACE
				stats["attack_face"] = GameModeManager.BOSSFIGHT_ATTACK_FACE
			var bot = session._spawn_bot(state.p, stats)
			replicas[id] = bot
		var enemy = replicas[id]
		bot_targets[id] = state.p
		enemy.state = int(state.state)
		enemy.network_target = int(state.target)
		enemy.combat.sync_network_health(float(state.hp), float(state.max))
		enemy._set_attack_visual(bool(state.get("attack", false)))
		if enemy.is_boss:
			session.game_modes.active_boss = enemy
	for id in replicas.keys():
		if not present.has(id):
			var enemy = replicas[id]
			if enemy == session.game_modes.active_boss:
				session.game_modes.active_boss = null
			if is_instance_valid(enemy) and not enemy.combat.dead:
				enemy.combat.sync_network_health(0.0, enemy.max_health)
			replicas.erase(id)
			bot_targets.erase(id)
	for state in data.shots:
		_spawn_visual_shot(state)

func _image_changed(_entry: Dictionary) -> void:
	if active and connected and game_running:
		_prepare_art()

func _prepare_art() -> String:
	var texture: Texture2D = session.png_images.current_texture()
	if texture == null:
		return ""
	var encoded = images.encode(texture)
	if encoded.is_empty():
		return ""
	selected_art = encoded.key
	if not announced_images.has(selected_art):
		announced_images[selected_art] = true
		if is_host():
			_art.rpc(selected_art, encoded.bytes)
		else:
			_upload_art.rpc_id(1, epoch, selected_art, encoded.bytes)
	return selected_art

@rpc("any_peer", "call_remote", "reliable", 0)
func _upload_art(round_id: int, key: String, bytes: PackedByteArray) -> void:
	if not is_host() or round_id != epoch or not peers.has(multiplayer.get_remote_sender_id()):
		return
	if images.accept(key, bytes):
		_art.rpc(key, bytes)

@rpc("authority", "call_remote", "reliable", 0)
func _art(key: String, bytes: PackedByteArray) -> void:
	if active and not is_host():
		if images.accept(key, bytes):
			for projectile in shots.values():
				if is_instance_valid(projectile) and projectile.get_meta("net_art", "") == key:
					projectile.texture = images.textures[key]
					projectile.visual.texture = projectile.texture
					projectile.visual.pixel_size = projectile.image_size / maxi(projectile.texture.get_width(), projectile.texture.get_height())

func throw_local(texture: Texture2D, origin: Vector3, direction: Vector3) -> Node3D:
	var key = _prepare_art()
	if key.is_empty():
		return null
	sequence += 1
	if is_host():
		return _server_fire(1, sequence, key, origin, direction, Settings.projectile_size)
	var projectile = session.projectiles.launch(texture, origin, direction, session.player, true)
	projectile.set_meta("net_seq", sequence)
	predicted[sequence] = projectile
	_fire.rpc_id(1, epoch, sequence, key, origin, direction, Settings.projectile_size)
	return projectile

@rpc("any_peer", "call_remote", "reliable", 0)
func _fire(round_id: int, seq: int, key: String, origin: Vector3, direction: Vector3, size: float) -> void:
	if is_host() and round_id == epoch:
		_server_fire(multiplayer.get_remote_sender_id(), seq, key, origin, direction, size)

func _server_fire(id: int, seq: int, key: String, origin: Vector3, direction: Vector3, size: float) -> Node3D:
	if not game_running or not peers.has(id):
		return null
	var state = peers[id]
	var now = Time.get_ticks_msec() / 1000.0
	if not state.ready or not state.alive or state.hidden or seq <= state.last_seq or now < state.next_fire - 0.045 or not images.textures.has(key) or not direction.is_finite() or direction.length() < 0.5 or not origin.is_finite() or not is_finite(size):
		if id != 1:
			_reject_shot.rpc_id(id, seq)
		return null
	state.last_seq = seq
	state.next_fire = now + 0.3
	var expected = state.p + Vector3.UP * (0.92 if state.crouch else 1.62)
	# A fast sidestep can outrun the last unreliable pose packet. Keep shots at
	# their camera origin within a small lag allowance, after a wall-clearance ray.
	if expected.distance_to(origin) > 3.5:
		origin = expected
	else:
		var ray = PhysicsRayQueryParameters3D.create(expected, origin, 1)
		if not session.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			origin = expected
	var actor = actor_for(id)
	if not is_instance_valid(actor):
		return null
	var projectile = session.projectiles.launch(images.textures[key], origin, direction, actor)
	projectile.damage = 20.0
	projectile.velocity = direction.normalized() * 35.0
	projectile.maximum_range = 100.0
	projectile.image_size = clampf(size, 0.2, 2.5)
	projectile.collision_radius = clampf(size * 0.12, 0.06, 0.22)
	projectile.shape.radius = projectile.collision_radius
	projectile.visual.pixel_size = projectile.image_size / maxi(projectile.texture.get_width(), projectile.texture.get_height())
	shot_id += 1
	projectile.set_meta("net_id", shot_id)
	projectile.set_meta("net_owner", id)
	projectile.set_meta("net_art", key)
	projectile.set_meta("net_seq", seq)
	shots[shot_id] = projectile
	_spawn_shot.rpc(epoch, _shot_data(projectile))
	if id != local_id():
		Sound.spatial("png_throw", session.damage_system, origin, -13.0)
	for bot in session.bots:
		bot.hear(origin, 0.7, actor)
	return projectile

func _shot_data(projectile) -> Dictionary:
	return {"id": int(projectile.get_meta("net_id")), "owner": int(projectile.get_meta("net_owner")), "art": str(projectile.get_meta("net_art")), "seq": int(projectile.get_meta("net_seq")), "p": projectile.global_position, "v": projectile.velocity, "size": projectile.image_size, "age": projectile.age}

@rpc("authority", "call_remote", "reliable", 0)
func _reject_shot(seq: int) -> void:
	if predicted.has(seq):
		if is_instance_valid(predicted[seq]):
			predicted[seq].expire()
		predicted.erase(seq)

@rpc("authority", "call_remote", "reliable", 0)
func _spawn_shot(round_id: int, data: Dictionary) -> void:
	if active and not is_host() and round_id == epoch:
		received_shots += 1
		_spawn_visual_shot(data)
		if int(data.owner) != local_id():
			Sound.spatial("png_throw", session.damage_system, data.p, -13.0)

func _spawn_visual_shot(data: Dictionary) -> void:
	var id = int(data.id)
	if ended_shots.has(id):
		return
	if shots.has(id) and is_instance_valid(shots[id]):
		return
	var projectile
	if int(data.owner) == local_id() and predicted.has(int(data.seq)):
		projectile = predicted[int(data.seq)]
		predicted.erase(int(data.seq))
		if not is_instance_valid(projectile):
			ended_shots[id] = true
			return
	else:
		var texture: Texture2D = images.textures.get(str(data.art), session.png_images.current_texture())
		projectile = session.projectiles.launch(texture, data.p, data.v.normalized(), actor_for(int(data.owner)), true)
		projectile.velocity = data.v
		projectile.age = float(data.age)
	projectile.image_size = float(data.size)
	projectile.visual.pixel_size = projectile.image_size / maxi(projectile.texture.get_width(), projectile.texture.get_height())
	projectile.set_meta("net_id", id)
	projectile.set_meta("net_owner", int(data.owner))
	projectile.set_meta("net_art", str(data.art))
	shots[id] = projectile

func projectile_finished(projectile: Node3D, kind: int = 0, point: Vector3 = Vector3.ZERO) -> void:
	if not active or not projectile.has_meta("net_id"):
		return
	var id = int(projectile.get_meta("net_id"))
	shots.erase(id)
	ended_shots[id] = true
	if ended_shots.size() > 512:
		ended_shots.erase(ended_shots.keys()[0])
	if is_host():
		_end_shot.rpc(epoch, id, point, kind)

@rpc("authority", "call_remote", "reliable", 0)
func _end_shot(round_id: int, id: int, point: Vector3, kind: int) -> void:
	if not active or round_id != epoch:
		return
	ended_shots[id] = true
	if shots.has(id) and is_instance_valid(shots[id]):
		shots[id].expire()
	shots.erase(id)
	if kind == 1:
		session.damage_system.impact(point)
		Sound.spatial("png_wall", session.damage_system, point, -18.0)

func _on_damage(target: Node, amount: float, lethal: bool, source: Node, point: Vector3) -> void:
	if is_host():
		var owner_id = peer_for(source)
		_enemy_hit.rpc(epoch, target.bot_index, target.combat.health.current_health, target.max_health, amount, point, owner_id, lethal)

@rpc("authority", "call_remote", "reliable", 0)
func _enemy_hit(round_id: int, id: int, hp: float, maximum: float, amount: float, point: Vector3, owner_id: int, lethal: bool) -> void:
	if not active or round_id != epoch:
		return
	var bot: Node = null
	if replicas.has(id) and is_instance_valid(replicas[id]):
		bot = replicas[id]
		bot.combat.network_hit(hp, maximum, amount, point)
	if owner_id == local_id():
		session.projectiles._on_hit_confirmed(bot, amount, lethal)
		received_hits += 1

func award_kill(source: Node) -> void:
	var id = peer_for(source)
	if peers.has(id):
		peers[id].kills += 1
		if id == local_id():
			session.kill_count = peers[id].kills

func catch_peer(id: int, bot_id: int) -> void:
	if not is_host() or not peers.has(id) or not peers[id].alive:
		return
	var state = peers[id]
	state.alive = false
	state.hidden = false
	state.hide_item = -1
	state.death_time = Time.get_ticks_msec() / 1000.0
	var actor = actor_for(id)
	if is_instance_valid(actor):
		actor.network_alive = false
		actor.active = false
		session.projectiles.clear_owned_projectiles(actor)
		if id != local_id():
			avatars[id].apply_pose(state, true)
	if id == local_id():
		session.network_death_local(bot_id)
	else:
		var face_variant: int = -1
		var bossfight_boss := false
		for bot in session.bots:
			if is_instance_valid(bot) and bot.bot_index == bot_id:
				face_variant = bot.face_variant
				bossfight_boss = bot.is_boss and session.game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT
				break
		_caught.rpc_id(id, epoch, bot_id, face_variant, bossfight_boss)

@rpc("authority", "call_remote", "reliable", 0)
func _caught(round_id: int, bot_id: int, face_variant: int, bossfight_boss: bool) -> void:
	if active and round_id == epoch:
		session.network_death_local(bot_id, face_variant, bossfight_boss)

func respawn_local() -> void:
	if not active:
		return
	if not game_running:
		if is_host():
			restart_round()
		return
	if is_host():
		if peers.has(1) and not peers[1].alive:
			_spawn_peer(1)
	else:
		_respawn.rpc_id(1, epoch)

@rpc("any_peer", "call_remote", "reliable", 0)
func _respawn(round_id: int) -> void:
	var id = multiplayer.get_remote_sender_id()
	if is_host() and round_id == epoch and peers.has(id) and not peers[id].alive and Time.get_ticks_msec() / 1000.0 - peers[id].get("death_time", 0.0) > 0.8:
		_spawn_peer(id)

func report_fall() -> void:
	if is_host():
		catch_peer(1, -1)
	else:
		_fall.rpc_id(1, epoch)

@rpc("any_peer", "call_remote", "reliable", 0)
func _fall(round_id: int) -> void:
	var id = multiplayer.get_remote_sender_id()
	if is_host() and round_id == epoch and peers.has(id) and peers[id].p.y < -5:
		catch_peer(id, -1)

func request_interact(item_index: int) -> void:
	if is_host():
		_server_interact(1, item_index)
	else:
		_interact.rpc_id(1, epoch, item_index)

@rpc("any_peer", "call_remote", "reliable", 0)
func _interact(round_id: int, item_index: int) -> void:
	if is_host() and round_id == epoch:
		_server_interact(multiplayer.get_remote_sender_id(), item_index)

func _server_interact(id: int, item_index: int) -> void:
	if not game_running or not peers.has(id) or not peers[id].ready or not peers[id].alive:
		return
	var state = peers[id]
	if state.hidden:
		_unhide(id)
		return
	if item_index < 0 or item_index >= session.world.interactables.size():
		return
	var item = session.world.interactables[item_index]
	var eye = state.p + Vector3.UP * (0.92 if state.crouch else 1.62)
	var aim = item.global_position + (Vector3.UP * 1.2 if item.kind == "hide" else Vector3.ZERO)
	if item.used or eye.distance_to(aim) > 3.4:
		return
	var ray = PhysicsRayQueryParameters3D.create(eye, aim, 1)
	var hit = session.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and eye.distance_to(hit.position) + 0.7 < eye.distance_to(aim):
		return
	if item.kind == "breaker":
		item.activate()
		session.breakers += 1
		for bot in session.bots:
			bot.hear(state.p, 4.0, actor_for(id))
		_item.rpc(epoch, item_index, session.breakers)
		var objective_name := "SWITCHES ACTIVATED" if session.game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT else "BREAKERS RESTORED"
		session.ui.toast("%d / 3 %s" % [session.breakers, objective_name], 3.0)
		Sound.spatial("breaker", session.damage_system, item.global_position)
	elif item.kind == "battery" and state.battery < 98.0:
		state.battery = minf(100, state.battery + 45)
		item.activate()
		_apply_actor(id, state, "correction")
		_actor.rpc(epoch, id, state, "correction")
		_item.rpc(epoch, item_index, session.breakers)
	elif item.kind == "exit" and session.breakers == 3 and session.game_modes.can_advance_level():
		advance_level()
	elif item.kind == "hide" and state.hide_cooldown <= 0:
		for other in peers.values():
			if other.hidden and other.hide_item == item_index:
				return
		for bot in session.bots:
			if bot.state == NextbotEnemy.State.CHASE and bot.global_position.distance_to(state.p) < 18 and bot._line_of_sight(actor_for(id)):
				return
		state.return_p = state.p
		state.return_yaw = state.yaw
		state.return_light = state.light
		state.p = item.global_position + Vector3.UP * 0.1
		state.hidden = true
		state.hide_left = 12.0
		state.hide_item = item_index
		state.light = false
		_apply_actor(id, state, "hide")
		_actor.rpc(epoch, id, state, "hide")

func _unhide(id: int) -> void:
	var state = peers[id]
	state.p = state.get("return_p", state.p)
	state.yaw = state.get("return_yaw", state.yaw)
	state.light = state.get("return_light", true)
	state.hidden = false
	state.hide_left = 0.0
	state.hide_cooldown = 8.0
	state.hide_item = -1
	_apply_actor(id, state, "unhide")
	_actor.rpc(epoch, id, state, "unhide")

@rpc("authority", "call_remote", "reliable", 0)
func _item(round_id: int, index: int, count: int) -> void:
	if not active or round_id != epoch or index < 0 or index >= session.world.interactables.size():
		return
	var item = session.world.interactables[index]
	if not item.used:
		item.activate()
		Sound.spatial("breaker" if item.kind == "breaker" else "battery", session.damage_system, item.global_position, -12.0)
	session.breakers = count
	if item.kind == "breaker":
		var objective_name := "SWITCHES ACTIVATED" if session.game_modes.selected == GameModeManager.GameplayMode.BOSSFIGHT else "BREAKERS RESTORED"
		session.ui.toast("%d / 3 %s" % [count, objective_name], 3.0)

func on_step(loudness: float) -> void:
	if is_host():
		_server_step(1, loudness)
	else:
		_step_request.rpc_id(1, epoch, loudness)

@rpc("any_peer", "call_remote", "unreliable", 1)
func _step_request(round_id: int, loudness: float) -> void:
	if is_host() and round_id == epoch:
		_server_step(multiplayer.get_remote_sender_id(), loudness)

func _server_step(id: int, loudness: float) -> void:
	if not peers.has(id) or not peers[id].alive or peers[id].hidden:
		return
	var state = peers[id]
	var now = Time.get_ticks_msec() / 1000.0
	if now - state.last_step < 0.15:
		return
	state.last_step = now
	for bot in session.bots:
		bot.hear(state.p, clampf(loudness, 0.2, 1.0), actor_for(id))
	if id != 1:
		Sound.spatial("step", session.damage_system, state.p, -13.0)
	_step.rpc(epoch, id, state.p, loudness)

@rpc("authority", "call_remote", "unreliable", 1)
func _step(round_id: int, id: int, at: Vector3, loudness: float) -> void:
	if active and round_id == epoch and id != local_id():
		Sound.spatial("step", session.damage_system, at, -20.0 if loudness < 0.5 else -13.0)

func finish_round() -> void:
	if not is_host() or not game_running:
		return
	game_running = false
	_round_finished.rpc(epoch)
	session.show_network_victory()

func advance_level() -> void:
	if not is_host() or not game_running or transitioning:
		return
	transitioning = true
	game_running = false
	transition_level = session.current_level + 1
	transition_seed = session._seed_for_level(transition_level)
	transition_acks.clear()
	transition_acks[1] = false
	_level_transition.rpc(epoch, transition_level, transition_seed)
	var host_ready: bool = await session._transition_to_level(transition_level, transition_seed, true, false)
	transition_acks[1] = host_ready
	var deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and not _all_transition_ready():
		await get_tree().process_frame
	# Reset every authoritative actor only after the new navigation map exists.
	for state in peers.values():
		state.alive = false
		state.ready = false
	for id in peers:
		var state = peers[id]
		state.p = _choose_spawn()
		state.v = Vector3.ZERO
		state.yaw = PI
		state.pitch = 0.0
		state.alive = true
		state.ready = true
		state.hidden = false
		state.hide_left = 0.0
		state.hide_cooldown = 0.0
		state.hide_item = -1
		state.light = true
		state.last_pose = Time.get_ticks_msec()
		if id == 1:
			session.player.reset_at(state.p)
			session.player.active = false
		else:
			_ensure_avatar(id, state)
			avatars[id].apply_pose(state, true)
	await session.complete_level_transition(true, true)
	game_running = true
	transitioning = false
	_level_resume.rpc(epoch, _snapshot())

func _all_transition_ready() -> bool:
	for id in peers:
		if not transition_acks.get(id, false):
			return false
	return true

@rpc("authority", "call_remote", "reliable", 0)
func _level_transition(round_id: int, level: int, seed_value: int) -> void:
	if not active or is_host() or round_id != epoch or transitioning:
		return
	transitioning = true
	loading = true
	game_running = false
	for enemy in replicas.values():
		if is_instance_valid(enemy):
			enemy.enabled = false
	replicas.clear()
	bot_targets.clear()
	shots.clear()
	predicted.clear()
	ended_shots.clear()
	var ready: bool = await session._transition_to_level(level, seed_value, true, false)
	if active and round_id == epoch:
		_level_ready.rpc_id(1, epoch, level, seed_value, ready)

@rpc("any_peer", "call_remote", "reliable", 0)
func _level_ready(round_id: int, level: int, seed_value: int, ready: bool) -> void:
	if not is_host() or not transitioning or round_id != epoch or level != transition_level or seed_value != transition_seed:
		return
	var id = multiplayer.get_remote_sender_id()
	if peers.has(id):
		transition_acks[id] = ready

@rpc("authority", "call_remote", "reliable", 0)
func _level_resume(round_id: int, data: Dictionary) -> void:
	if not active or is_host() or round_id != epoch or not transitioning:
		return
	_apply_snapshot(data)
	for state in data.players:
		if int(state.id) == local_id():
			session.player.reset_at(state.p)
			session.player.active = false
			break
	await session.complete_level_transition(false, true)
	game_running = true
	loading = false
	transitioning = false

@rpc("authority", "call_remote", "reliable", 0)
func _round_finished(round_id: int) -> void:
	if active and round_id == epoch:
		game_running = false
		session.show_network_victory()

func restart_round() -> void:
	if not is_host():
		return
	epoch += 1
	shots.clear()
	ended_shots.clear()
	predicted.clear()
	replicas.clear()
	bot_targets.clear()
	game_running = false
	session.start_run(true)
	for id in peers:
		var old = peers[id]
		peers[id] = _new_peer(id, old.name, _choose_spawn())
		peers[id].ready = true
	game_running = true
	_restart.rpc(epoch, session.run_map_index, session.run_difficulty, _snapshot())
	_spawn_peer(1)

@rpc("authority", "call_remote", "reliable", 0)
func _restart(round_id: int, map_index: int, difficulty_index: int, data: Dictionary) -> void:
	if not active:
		return
	epoch = round_id
	game_running = false
	shots.clear()
	ended_shots.clear()
	predicted.clear()
	replicas.clear()
	bot_targets.clear()
	session.prepare_network_world(map_index, difficulty_index, int(data.get("level", 1)), int(data.get("seed", 0)), int(data.get("mode", GameModeManager.GameplayMode.ENDLESS)))
	session.start_run(true, int(data.get("level", 1)), int(data.get("seed", 0)))
	game_running = true
	_apply_snapshot(data)
	if peers.has(local_id()):
		session.network_spawn_local(peers[local_id()])
