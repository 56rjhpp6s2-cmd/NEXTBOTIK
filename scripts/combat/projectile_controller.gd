class_name ProjectileController
extends Node
## Player weapon: input, cooldown, aim, viewmodel, ammunition and projectile ownership.
signal projectile_launched(projectile: Node3D)
signal state_changed
const ProjectileScript = preload("res://scripts/combat/png_projectile.gd")
@export var projectile_damage: float = 20.0
@export var projectile_speed: float = 35.0
@export var throw_cooldown: float = 0.3
@export var maximum_range: float = 100.0
@export var projectile_lifetime: float = 4.0
@export var unlimited_ammo: bool = true
@export var magazine_size: int = 12
@export var reload_duration: float = 0.8
var player: PlayerController
var session
var images
var damage_system
var projectiles: Array[Node3D] = []
var cooldown_remaining: float = 0.0
var reload_remaining: float = 0.0
var ammo: int = 12
var run_id: int = 0
var held_image: Sprite3D
var animation: Tween
var require_release: bool = false
var aimed_enemy: Node3D
var last_hit_enemy: Node3D
var target_scan: float = 0.0
var hit_time: float = 0.0
var hit_lethal: bool = false
var charging: bool = false
var charge_elapsed: float = 0.0
var shot_serial: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	held_image = Sprite3D.new()
	held_image.shaded = false
	held_image.no_depth_test = true
	held_image.render_priority = 100
	held_image.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	held_image.position = Vector3(0.28, -0.23, -0.52)
	player.view.camera.add_child(held_image)
	images.image_selected.connect(_on_image_selected)
	damage_system.hit_confirmed.connect(_on_hit_confirmed)
	_on_image_selected(images.current_entry())

func _can_use() -> bool:
	if not session.is_local_playing() or player.hidden:
		return false
	if is_instance_valid(session.post_boss) and session.post_boss.state in [
		PostBossRewardController.RewardState.BOSS_DEFEATED,
		PostBossRewardController.RewardState.REWARD_PREPARATION,
		PostBossRewardController.RewardState.REWARD_SELECTION,
		PostBossRewardController.RewardState.REWARD_FINALIZED,
		PostBossRewardController.RewardState.PROGRESSION_UNLOCKED,
	]:
		return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not _can_use():
		return
	if event.is_action_pressed("reload_png"):
		reload()
	elif event.is_action_pressed("next_png"):
		images.cycle(1)
	elif event.is_action_pressed("previous_png"):
		images.cycle(-1)

func _physics_process(delta: float) -> void:
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	hit_time = maxf(0.0, hit_time - delta)
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			ammo = magazine_size
			state_changed.emit()
	var usable = _can_use()
	held_image.visible = usable and held_image.texture != null
	player.view.aiming = usable and Input.is_action_pressed("aim_png") and reload_remaining <= 0.0
	player.view.sensitivity_multiplier = 0.65 if player.view.aiming else 1.0
	if not usable:
		clear_aim()
		return
	if animation == null or not animation.is_running():
		var at = Vector3(0.14, -0.13, -0.55) if player.view.aiming else Vector3(0.28, -0.23, -0.52)
		held_image.position = held_image.position.lerp(at, 1.0 - exp(-delta * 16.0))
	var current_profile: Dictionary = session.game_modes.projectile_profile() if is_instance_valid(session.game_modes) else {}
	var charged_weapon := str(current_profile.get("weapon", "png_thrower")) == "charged_launcher"
	if require_release:
		if not Input.is_action_pressed("throw_png"):
			require_release = false
	elif charged_weapon:
		if Input.is_action_pressed("throw_png") and cooldown_remaining <= 0.0 and reload_remaining <= 0.0:
			charging = true
			charge_elapsed = minf(1.2, charge_elapsed + delta)
		elif charging:
			var power := clampf(charge_elapsed / 1.2, 0.2, 1.0)
			charging = false
			charge_elapsed = 0.0
			fire(power)
	elif Input.is_action_pressed("throw_png"):
		fire()
	target_scan -= delta
	if target_scan <= 0.0:
		target_scan = 0.08
		_scan_target()

func fire(charge_power: float = 1.0) -> Node3D:
	if not _can_use() or cooldown_remaining > 0.0 or reload_remaining > 0.0:
		return null
	if not unlimited_ammo and ammo <= 0:
		reload()
		return null
	var texture: Texture2D = images.current_texture()
	if texture == null:
		return null
	var profile: Dictionary = session.game_modes.projectile_profile() if is_instance_valid(session.game_modes) else {}
	cooldown_remaining = maxf(0.01, throw_cooldown * float(profile.get("cooldown_multiplier", 1.0)))
	if not unlimited_ammo:
		ammo -= 1
	var projectile: Node3D
	var count = maxi(1, int(profile.get("count", 1)))
	for index in range(count):
		shot_serial += 1
		var shot_profile := profile.duplicate()
		if shot_serial % 5 == 0:
			shot_profile["trigger_damage_multiplier"] = float(profile.get("fifth_shot_multiplier", 1.0))
		if player.sliding:
			shot_profile["trigger_damage_multiplier"] = float(shot_profile.get("trigger_damage_multiplier", 1.0)) * float(profile.get("sliding_damage_multiplier", 1.0))
		if not player.is_on_floor() and Vector2(player.velocity.x, player.velocity.z).length() > 7.0:
			shot_profile["critical_chance"] = float(profile.get("critical_chance", 0.0)) + float(profile.get("airborne_critical_bonus", 0.0))
		var center = (float(count) - 1.0) * 0.5
		var direction = (-player.view.camera.global_basis.z + player.view.camera.global_basis.x * (float(index) - center) * float(profile.get("spread", 0.035))).normalized()
		if is_instance_valid(session.network) and session.network.active:
			projectile = session.network.throw_local(texture, player.view.camera.global_position, direction, charge_power)
		else:
			projectile = launch(texture, player.view.camera.global_position, direction, null, false, shot_profile, charge_power)
		if is_instance_valid(session.statistics):
			session.statistics.add("total_png_projectiles_thrown")
	_play_throw()
	Sound.one_shot("png_throw", -13.0, randf_range(0.94, 1.08))
	if not session.network.active:
		for bot in session.bots:
			bot.hear(player.global_position, 0.7)
	state_changed.emit()
	return projectile

func launch(texture: Texture2D, origin: Vector3, direction: Vector3, owner_actor: Node3D = null, visual_only: bool = false, profile: Dictionary = {}, charge_power: float = 1.0) -> Node3D:
	var projectile = ProjectileScript.new()
	projectile.shooter = owner_actor if owner_actor != null else player
	projectile.visual_only = visual_only
	projectile.session = session
	projectile.damage_system = damage_system
	projectile.run_id = run_id
	projectile.texture = texture
	projectile.damage = projectile_damage * float(profile.get("damage_multiplier", 1.0)) * float(profile.get("trigger_damage_multiplier", 1.0))
	if str(profile.get("weapon", "png_thrower")) == "charged_launcher":
		projectile.damage *= lerpf(0.7, 3.0, clampf(charge_power, 0.2, 1.0))
	if randf() < float(profile.get("critical_chance", 0.0)):
		projectile.damage *= 2.0
		projectile.critical = true
	projectile.speed = projectile_speed * float(profile.get("velocity_multiplier", 1.0))
	projectile.maximum_range = maximum_range * float(profile.get("range_multiplier", 1.0))
	projectile.lifetime = projectile_lifetime
	projectile.image_size = Settings.projectile_size * float(profile.get("size_multiplier", 1.0))
	projectile.collision_radius = clampf(projectile.image_size * 0.12 * float(profile.get("hitbox_multiplier", 1.0)), 0.06, 0.38)
	projectile.explosion_radius = float(profile.get("explosion_radius", 0.0))
	projectile.freeze_seconds = float(profile.get("freeze_seconds", 0.0))
	projectile.piercing_remaining = int(profile.get("piercing", 0))
	projectile.ricochets_remaining = int(profile.get("ricochets", 0))
	projectile.velocity = direction.normalized() * projectile.speed
	projectile.position = origin
	session.add_child(projectile)
	projectiles.append(projectile)
	projectile.tree_exiting.connect(_forget_projectile.bind(projectile))
	projectile_launched.emit(projectile)
	return projectile

func _forget_projectile(projectile: Node3D) -> void:
	projectiles.erase(projectile)

func reload() -> bool:
	if not _can_use() or reload_remaining > 0.0:
		return false
	images.refresh(true)
	reload_remaining = maxf(0.05, reload_duration)
	clear_aim()
	if animation != null:
		animation.kill()
	animation = create_tween()
	animation.tween_property(held_image, "position:y", -0.65, reload_duration * 0.35)
	animation.tween_property(held_image, "position:y", -0.23, reload_duration * 0.65)
	Sound.one_shot("png_reload", -13.0)
	state_changed.emit()
	return true

func _play_throw() -> void:
	if animation != null:
		animation.kill()
	animation = create_tween()
	animation.tween_property(held_image, "position", Vector3(0.11, -0.12, -0.4), 0.055)
	animation.tween_property(held_image, "position", Vector3(0.33, -0.42, -0.47), 0.075)
	animation.tween_property(held_image, "position", Vector3(0.28, -0.23, -0.52), 0.14)
	if not Settings.reduced_flashes:
		player.view.shake = maxf(player.view.shake, 0.06)

func _on_image_selected(_entry: Dictionary) -> void:
	if not is_instance_valid(held_image):
		return
	held_image.texture = images.current_texture()
	if held_image.texture != null:
		held_image.pixel_size = 0.24 / maxi(held_image.texture.get_width(), held_image.texture.get_height())
	state_changed.emit()

func _on_hit_confirmed(target: Node, _amount: float, lethal: bool) -> void:
	last_hit_enemy = target
	hit_time = 0.25
	hit_lethal = lethal
	if is_instance_valid(session.statistics):
		session.statistics.add("successful_projectile_hits")

func _scan_target() -> void:
	aimed_enemy = null
	var camera = player.view.camera
	var ray = PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * maximum_range, 1 | 4, [player.get_rid()])
	ray.collide_with_areas = true
	var hit = player.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var target = damage_system.receiver_for(hit.collider)
		if is_instance_valid(target) and target.has_method("get_health_component") and not target.get_health_component().dead:
			aimed_enemy = target

func clear_aim() -> void:
	player.view.aiming = false
	player.view.sensitivity_multiplier = 1.0

func suspend_input() -> void:
	clear_aim()
	require_release = true
	held_image.visible = false
	charging = false
	charge_elapsed = 0.0

func reset_run(keep_others: bool = false) -> void:
	if keep_others:
		clear_owned_projectiles(player)
	else:
		clear_projectiles()
	run_id += 1
	clear_aim()
	cooldown_remaining = 0.0
	reload_remaining = 0.0
	ammo = magazine_size
	unlimited_ammo = Settings.unlimited_png_ammo
	if is_instance_valid(session.network) and session.network.active:
		unlimited_ammo = true
	hit_time = 0.0
	aimed_enemy = null
	last_hit_enemy = null
	require_release = true
	charging = false
	charge_elapsed = 0.0
	shot_serial = 0
	if animation != null:
		animation.kill()
	held_image.position = Vector3(0.28, -0.23, -0.52)
	state_changed.emit()

func clear_projectiles() -> void:
	for projectile in projectiles.duplicate():
		if is_instance_valid(projectile):
			projectile.expire()
	projectiles.clear()

func clear_owned_projectiles(actor: Node3D) -> void:
	for projectile in projectiles.duplicate():
		if is_instance_valid(projectile) and projectile.shooter == actor:
			projectile.expire()
