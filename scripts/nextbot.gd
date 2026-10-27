class_name NextbotEnemy
extends CharacterBody3D
## Sight and hearing feed an explicit pursuit state machine; NavigationAgent handles routes.
enum State { IDLE, WANDER, INVESTIGATE, SEARCH, CHASE, ATTACK, STUNNED, DEAD }
@export var speed: float = 11.4
@export var acceleration: float = 38.0
@export var detection_range: float = 32.0
@export var aggression: float = 1.0
@export var max_health: float = 100.0
@export var respawn_delay: float = 10.0
@export var repath_interval: float = 0.18
@export var search_duration_scale: float = 1.0
@export var chase_speed_cap: float = 22.0
@export var attack_damage: float = 100.0
var combat
var face_variant: int = 0
var custom_face: Texture2D
var face_scale: float = 1.0
var speed_multiplier: float = 1.0
var event_speed_multiplier: float = 1.0
var is_boss: bool = false
var event_spawned: bool = false
var event_tag: String = ""
var angry_observation: bool = false
var stun_remaining: float = 0.0
var boss_minions_summoned: bool = false
var face_base_height: float = 1.45
var boss_ability_timer: float = 5.0
var boss_telegraph: float = 0.0
var boss_dash_remaining: float = 0.0
var network_replica: bool = false
var network_target: int = 1
var state: State = State.IDLE
var agent: NavigationAgent3D
var face: Sprite3D
var audio: AudioStreamPlayer3D
var session
var world: LevelWorld
var player: PlayerController
var last_known: Vector3
var last_seen: float = 100.0
var state_time: float = 0.0
var repath_time: float = 0.0
var sense_time: float = 0.0
var stuck_time: float = 0.0
var last_position: Vector3
var search_steps: int = 0
var desired: Vector3 = Vector3.ZERO
var bot_index: int = 0
var debug_label: Label3D
var enabled: bool = true
var nav_ready: bool = false
var target: Vector3
var rng = RandomNumberGenerator.new()

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.55
	floor_max_angle = deg_to_rad(48.0)
	var collider = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	var body_scale = clampf(face_scale, 0.5, 2.2)
	shape.radius = 0.42 * body_scale
	shape.height = 1.75 * body_scale
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	add_child(collider)
	face = Sprite3D.new()
	face.texture = custom_face if custom_face != null else session.face_for_variant(face_variant)
	face.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	face.pixel_size = 2.7 / float(face.texture.get_height())
	face_base_height = shape.height * 0.83
	face.position.y = face_base_height
	face.shaded = false
	face.double_sided = true
	face.scale = Vector3.ONE * face_scale
	add_child(face)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.6
	agent.radius = 0.5 * body_scale
	agent.height = shape.height
	# RVO must allow the full late-run chase speed; otherwise faster presets are capped.
	agent.max_speed = speed * 1.32 + 1.0
	agent.path_search_max_polygons = world.navigation.polygon_count + 1
	agent.simplify_path = true
	agent.simplify_epsilon = 0.12
	agent.neighbor_distance = maxf(6.0, speed * 0.75)
	agent.time_horizon_agents = 0.7
	agent.time_horizon_obstacles = 0.5
	agent.avoidance_enabled = not network_replica
	agent.avoidance_layers = 1
	agent.avoidance_mask = 1
	agent.avoidance_priority = 0.5 + (bot_index % 5) * 0.05
	agent.velocity_computed.connect(_safe_velocity)
	add_child(agent)
	debug_label = WorldSurface.label(self, "", Vector3(0, 3.3, 0), Color.CYAN, 28)
	debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label.visible = false
	rng.randomize()
	last_position = global_position
	last_known = player.global_position
	audio = Sound.spatial("hum", self, global_position + Vector3.UP, -12.0, true)
	combat = preload("res://scripts/combat/nextbot_combat_controller.gd").new()
	combat.bot = self
	add_child(combat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await world.navigation.wait_ready()
	if is_inside_tree() and not combat.dead and not network_replica:
		nav_ready = true
		_change_state(State.WANDER)

func _physics_process(delta: float) -> void:
	if network_replica or not enabled or not nav_ready or combat.dead or not session.is_running():
		velocity = Vector3.ZERO
		agent.velocity = Vector3.ZERO
		return
	if not session.actor_alive(player):
		player = session.first_alive_player()
		if player == null:
			desired = Vector3.ZERO
			agent.velocity = Vector3.ZERO
			return
		_change_state(State.SEARCH)
	state_time += delta
	if state == State.STUNNED:
		stun_remaining = maxf(0.0, stun_remaining - delta)
		desired = desired.move_toward(Vector3.ZERO, delta * acceleration * 2.0)
		agent.velocity = desired
		face.modulate = Color("8dcfff")
		if stun_remaining <= 0.0:
			face.modulate = Color.WHITE
			_change_state(State.CHASE if is_instance_valid(player) and session.actor_alive(player) else State.WANDER)
		return
	last_seen += delta
	sense_time -= delta
	repath_time -= delta
	if sense_time <= 0.0:
		sense_time = 0.13 + (bot_index % 6) * 0.017
		_sense()
	match state:
		State.IDLE:
			if state_time > 1.2 / aggression:
				_change_state(State.WANDER)
		State.WANDER:
			if agent.is_navigation_finished() or state_time > 16.0:
				_change_state(State.IDLE)
		State.INVESTIGATE:
			if agent.is_navigation_finished() or state_time > 3.0 * search_duration_scale:
				_change_state(State.SEARCH)
		State.CHASE:
			if repath_time <= 0.0:
				repath_time = repath_interval
				var aim = player.global_position if last_seen < 0.4 else last_known
				# Modest prediction rewards sharp changes of direction and line-of-sight breaks.
				if last_seen < 0.4 and global_position.distance_to(aim) > 9.0:
					aim += player.velocity * 0.3
				_set_target(aim)
			if last_seen > 2.6 / aggression or player.hidden or world.refuge_remaining(player.global_position) > 0.0:
				_change_state(State.SEARCH)
		State.SEARCH:
			if agent.is_navigation_finished() or state_time > (4.5 + search_steps * 3.0) * search_duration_scale:
				search_steps += 1
				if search_steps > 3:
					_change_state(State.WANDER)
				else:
					var search_target = last_known + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
					_set_target(NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, search_target))
		State.ATTACK:
			return
		State.STUNNED:
			return
		State.DEAD:
			return
	var distance = global_position.distance_to(player.global_position)
	if distance < 1.25 and absf(global_position.y - player.global_position.y) < 1.4 and not player.hidden and world.refuge_remaining(player.global_position) <= 0.0 and _line_of_sight() and session.game_modes.attacks_enabled():
		_change_state(State.ATTACK)
		session.catch_player(player, self)
		return
	var direction = Vector3.ZERO
	if state != State.IDLE and not agent.is_navigation_finished():
		var next = agent.get_next_path_position()
		direction = (next - global_position)
		direction.y = 0.0
		direction = direction.normalized()
	var boss_phase_multiplier = 1.0
	if is_boss and is_instance_valid(combat.health):
		var health_ratio = combat.health.current_health / combat.health.max_health
		boss_phase_multiplier = 1.45 if health_ratio < 0.2 else (1.25 if health_ratio < 0.5 else 1.0)
		boss_ability_timer -= delta
		if boss_telegraph > 0.0:
			boss_telegraph = maxf(0.0, boss_telegraph - delta)
			boss_phase_multiplier *= 0.22
			face.modulate = Color("ff493d")
			if boss_telegraph <= 0.0:
				boss_dash_remaining = 0.8
				face.modulate = Color.WHITE
		elif boss_dash_remaining > 0.0:
			boss_dash_remaining = maxf(0.0, boss_dash_remaining - delta)
			boss_phase_multiplier *= 1.45
		elif health_ratio < 0.5 and boss_ability_timer <= 0.0:
			boss_telegraph = 0.9
			boss_ability_timer = 7.0
			session.ui.toast("BOSS CHARGE INCOMING\nBREAK LINE OF SIGHT", 1.2)
		if health_ratio < 0.2 and not boss_minions_summoned and session.is_authority():
			boss_minions_summoned = true
			session.spawn_boss_minions(self)
	var observation_multiplier = 1.0
	if angry_observation:
		observation_multiplier = 0.42 if _observed_by_any_player() else 1.32
	var run_speed = speed * speed_multiplier * event_speed_multiplier * boss_phase_multiplier * observation_multiplier * (1.0 + minf(session.survival_time / 360.0, 0.32))
	run_speed = minf(run_speed, chase_speed_cap)
	if state != State.CHASE:
		run_speed *= 0.68 if state == State.SEARCH else 0.43
	desired = desired.move_toward(direction * run_speed, delta * acceleration)
	# Physical collision is the final authority; avoidance only adjusts horizontal velocity.
	agent.velocity = desired
	if direction.length_squared() > 0.1 and global_position.distance_to(last_position) < 0.025:
		stuck_time += delta
	else:
		stuck_time = maxf(0.0, stuck_time - delta * 2.0)
	if stuck_time > 0.7:
		agent.target_position = target
		desired += Vector3(direction.z, 0, -direction.x) * (2.0 if bot_index % 2 == 0 else -2.0)
	if stuck_time > 2.4:
		# Pick a reachable nearby nav point, never teleport toward or onto the player.
		var escape = global_position + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
		_set_target(NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, escape))
		stuck_time = 0.0
	last_position = global_position
	face.position.y = face_base_height + sin(state_time * 6.0) * 0.055
	audio.pitch_scale = 0.85 + minf(0.35, 10.0 / maxf(1.0, distance) * 0.15)
	debug_label.visible = session.debug_ai
	debug_label.text = "%s / %.1fm\nPATH %d / STUCK %.1f" % [State.keys()[state], distance, agent.get_current_navigation_path().size(), stuck_time]
	agent.debug_enabled = session.debug_ai

func _safe_velocity(safe: Vector3) -> void:
	if not enabled or combat.dead or not session.is_running():
		return
	velocity.x = safe.x + combat.knockback.x
	velocity.z = safe.z + combat.knockback.z
	if not is_on_floor():
		velocity.y -= 22.0 * get_physics_process_delta_time()
	else:
		velocity.y = -0.5
	move_and_slide()

func _sense() -> void:
	if combat.dead or network_replica:
		return
	var best: PlayerController = null
	var best_distance: float = INF
	for candidate in session.target_players():
		if not session.actor_alive(candidate) or candidate.hidden or world.refuge_remaining(candidate.global_position) > 0.0:
			continue
		var distance = global_position.distance_to(candidate.global_position)
		var range_scale: float = 0.58 if candidate.crouching and not candidate.view.flashlight_on else 1.0
		if distance < detection_range * range_scale and distance < best_distance and _line_of_sight(candidate):
			best = candidate
			best_distance = distance
	if best != null:
		player = best
		last_known = player.global_position
		last_seen = 0.0
		if state != State.CHASE:
			_change_state(State.CHASE)

func _line_of_sight(candidate: PlayerController = null) -> bool:
	if candidate == null:
		candidate = player
	if not is_instance_valid(candidate):
		return false
	var ray = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, candidate.global_position + Vector3.UP * 1.0, 1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func hear(at: Vector3, loudness: float, source: PlayerController = null) -> void:
	if network_replica or not enabled or state == State.CHASE or (is_instance_valid(source) and source.hidden) or world.refuge_remaining(at) > 0.0:
		return
	if global_position.distance_to(at) < 22.0 * loudness * aggression:
		if is_instance_valid(source):
			player = source
		last_known = at
		_change_state(State.INVESTIGATE)

func apply_stun(seconds: float) -> void:
	if combat.dead or seconds <= 0.0:
		return
	stun_remaining = maxf(stun_remaining, seconds)
	_change_state(State.STUNNED)

func _observed_by_any_player() -> bool:
	for candidate in session.target_players():
		if not session.actor_alive(candidate):
			continue
		var eye = candidate.view.camera.global_position
		var offset = global_position + Vector3.UP * 1.2 - eye
		if offset.length_squared() < 0.01:
			return true
		var forward = -candidate.view.camera.global_basis.z
		if forward.dot(offset.normalized()) < 0.78:
			continue
		var ray = PhysicsRayQueryParameters3D.create(eye, global_position + Vector3.UP * 1.2, 1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			return true
	return false

func _set_target(at: Vector3) -> void:
	target = at
	agent.target_position = at

func _change_state(next: State) -> void:
	if combat != null and combat.dead and next != State.DEAD:
		return
	state = next
	state_time = 0.0
	match state:
		State.WANDER:
			_set_target(world.patrol_points[rng.randi_range(0, world.patrol_points.size() - 1)])
		State.SEARCH:
			search_steps = 0
			_set_target(last_known)
		State.CHASE:
			repath_time = 0.0

func receive_png_hit(amount: float, source: Node, point: Vector3, direction: Vector3) -> float:
	return combat.receive_hit(amount, source, point, direction)

func get_health_component() -> Node:
	return combat.health
