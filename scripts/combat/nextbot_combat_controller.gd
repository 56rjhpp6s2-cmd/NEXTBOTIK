class_name NextbotCombatController
extends Node3D
## Health and reactions are kept out of the enemy's pathfinding/state machine.
const HealthScript = preload("res://scripts/combat/health_component.gd")
const GREEN = Color("83dfab")
const YELLOW = Color("ffd866")
const RED = Color("f05f55")
var bot
var health
var bar_root: Node3D
var bar_fill: MeshInstance3D
var bar_material: StandardMaterial3D
var health_label: Label3D
var displayed_ratio: float = 1.0
var knockback: Vector3 = Vector3.ZERO
var flash: Tween
var dead: bool = false
var hurtbox: Area3D

func _ready() -> void:
	health = HealthScript.new()
	health.max_health = bot.max_health
	add_child(health)
	_build_hurtbox()
	_build_bar()
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_on_health_changed(health.current_health, health.max_health)

func _build_hurtbox() -> void:
	# A thin, camera-aligned rectangle covers the visible face above the AI capsule.
	hurtbox = Area3D.new()
	hurtbox.position.y = bot.face_base_height
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.set_meta("png_receiver", bot)
	var collision = CollisionShape3D.new()
	var shape: Shape3D
	if is_instance_valid(bot.session.network) and bot.session.network.active:
		var cylinder = CylinderShape3D.new()
		cylinder.radius = clampf(1.35 * bot.face.texture.get_width() / bot.face.texture.get_height(), 0.42, 1.35)
		cylinder.height = 2.7
		shape = cylinder
	else:
		var rectangle = BoxShape3D.new()
		rectangle.size = Vector3(2.7 * bot.face.texture.get_width() / bot.face.texture.get_height(), 2.7, 0.12) * bot.face_scale
		shape = rectangle
	collision.shape = shape
	hurtbox.add_child(collision)
	add_child(hurtbox)

func _build_bar() -> void:
	bar_root = Node3D.new()
	bar_root.position.y = bot.face_base_height + 1.57 * bot.face_scale
	bar_root.scale = Vector3.ONE * clampf(bot.face_scale, 1.0, 1.8)
	add_child(bar_root)
	var background = MeshInstance3D.new()
	var background_mesh = QuadMesh.new()
	background_mesh.size = Vector2(1.9, 0.15)
	background.mesh = background_mesh
	var background_material = StandardMaterial3D.new()
	background_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	background_material.albedo_color = Color("17252a")
	background.material_override = background_material
	background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar_root.add_child(background)
	bar_fill = MeshInstance3D.new()
	var fill_mesh = QuadMesh.new()
	fill_mesh.size = Vector2(1.84, 0.095)
	bar_fill.mesh = fill_mesh
	bar_fill.position.z = 0.01
	bar_material = StandardMaterial3D.new()
	bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_fill.material_override = bar_material
	bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar_root.add_child(bar_fill)
	health_label = Label3D.new()
	health_label.position = Vector3(0, 0.2, 0.02)
	health_label.font_size = 32
	health_label.pixel_size = 0.007
	health_label.outline_size = 6
	bar_root.add_child(health_label)

func _process(delta: float) -> void:
	if dead:
		return
	var camera = get_viewport().get_camera_3d()
	if camera != null and bar_root.global_position.distance_squared_to(camera.global_position) > 0.001:
		var direction = (camera.global_position - bar_root.global_position).normalized()
		if absf(direction.dot(Vector3.UP)) < 0.995:
			bar_root.look_at(camera.global_position, Vector3.UP, true)
	displayed_ratio = lerpf(displayed_ratio, health.current_health / health.max_health, 1.0 - exp(-delta * 12.0))
	bar_fill.mesh.size = Vector2(maxf(0.001, 1.84 * displayed_ratio), 0.095)
	bar_fill.position.x = (displayed_ratio - 1.0) * 1.84 / 2.0

func _physics_process(delta: float) -> void:
	knockback = knockback.move_toward(Vector3.ZERO, delta * 13.0)
	if not dead and is_instance_valid(bot.player) and not bot.session.network.active:
		hurtbox.global_basis = bot.player.view.camera.global_basis

func receive_hit(amount: float, source: Node, point: Vector3, direction: Vector3) -> float:
	if dead or not bot.session.is_running() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var push = Vector3(direction.x, 0, direction.z).normalized()
	knockback = push * 2.5
	return health.apply_damage(amount, source, point)

func _on_health_changed(current: float, maximum: float) -> void:
	health_label.text = "%d/%d" % [ceili(current), ceili(maximum)]
	var ratio = current / maximum
	bar_material.albedo_color = RED if ratio < 0.25 else (YELLOW if ratio < 0.6 else GREEN)

func _on_damaged(amount: float, source: Node, point: Vector3) -> void:
	if flash != null:
		flash.kill()
	bot.face.modulate = Color(1.0, 0.18, 0.18, 1.0)
	flash = create_tween()
	flash.tween_property(bot.face, "modulate", Color.WHITE, 0.17)
	Sound.spatial("png_hit", bot.session.damage_system, point, -9.0, false)
	bot.session.damage_system.impact(point, true, amount)
	if is_instance_valid(source) and source is Node3D and not health.dead and not bot.network_replica:
		if source is PlayerController:
			bot.player = source
		bot.last_known = source.global_position
		bot.last_seen = 0.0
		bot._change_state(bot.State.CHASE)

func _on_died(source: Node) -> void:
	if dead:
		return
	dead = true
	knockback = Vector3.ZERO
	bot.enabled = false
	bot.state = bot.State.DEAD
	bot.velocity = Vector3.ZERO
	bot.desired = Vector3.ZERO
	bot.collision_layer = 0
	bot.collision_mask = 0
	hurtbox.collision_layer = 0
	bot.agent.velocity = Vector3.ZERO
	bot.agent.avoidance_enabled = false
	bot.debug_label.visible = false
	bar_root.visible = false
	bot.audio.stop()
	if flash != null:
		flash.kill()
	Sound.spatial("png_death", bot.session.damage_system, bot.global_position + Vector3.UP, -7.0)
	bot.session.damage_system.death_effect(bot.global_position + Vector3.UP * 1.3)
	if not bot.network_replica:
		bot.session.enemy_defeated(bot, source)
	var tween = create_tween()
	tween.tween_property(bot.face, "position:y", 0.45, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(bot.face, "scale", Vector3.ONE * 0.6, 0.65)
	tween.parallel().tween_property(bot.face, "modulate:a", 0.0, 0.5).set_delay(0.15)
	tween.tween_callback(bot.queue_free)

func sync_network_health(current: float, maximum: float) -> void:
	if dead:
		return
	health.max_health = maximum
	health.current_health = minf(health.current_health, clampf(current, 0, maximum))
	health.dead = current <= 0
	_on_health_changed(health.current_health, maximum)
	if health.dead:
		_on_died(null)

func network_hit(current: float, maximum: float, amount: float, point: Vector3) -> void:
	if dead:
		return
	_on_damaged(amount, null, point)
	sync_network_health(current, maximum)
