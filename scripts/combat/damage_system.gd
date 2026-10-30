class_name DamageSystem
extends Node3D
## Shared damage routing and short-lived world effects, independent of enemy AI.
signal hit_confirmed(target: Node, amount: float, lethal: bool)
signal hit_applied(target: Node, amount: float, lethal: bool, source: Node, point: Vector3)
var session

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func apply_hit(target: Object, amount: float, source: Node, point: Vector3, direction: Vector3) -> float:
	target = receiver_for(target)
	if not session.is_authority():
		return 0.0
	if not is_instance_valid(target) or target == source or not session.is_running():
		return 0.0
	if not target.has_method("receive_png_hit"):
		return 0.0
	if is_instance_valid(session.network) and session.network.active:
		var core = target.global_position + Vector3.UP * clampf(point.y - target.global_position.y, 0.3, 2.6)
		var visibility = PhysicsRayQueryParameters3D.create(point, core, 1)
		if not session.get_world_3d().direct_space_state.intersect_ray(visibility).is_empty():
			return 0.0
	var applied: float = target.receive_png_hit(amount, source, point, direction)
	if applied > 0.0:
		var lethal: bool = target.get_health_component().dead
		if source == session.player:
			hit_confirmed.emit(target, applied, lethal)
		hit_applied.emit(target, applied, lethal, source, point)
	return applied

func receiver_for(collider: Object) -> Object:
	if is_instance_valid(collider) and collider is Node and collider.has_meta("png_receiver"):
		return collider.get_meta("png_receiver")
	return collider

func impact(point: Vector3, enemy_hit: bool = false, damage: float = 0.0) -> void:
	_particles(point, Color("ff9a88") if enemy_hit else Color("9bdccc"), 10, 0.24, 0.08)
	if enemy_hit:
		var number = Label3D.new()
		number.text = "−%d" % roundi(damage)
		number.font_size = 58
		number.pixel_size = 0.008
		number.modulate = Color("ffb19a")
		number.outline_modulate = Color("12181d")
		number.outline_size = 10
		number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(number)
		number.global_position = point + Vector3(randf_range(-0.15, 0.15), 0.25, 0)
		var tween = number.create_tween()
		tween.tween_property(number, "position:y", number.position.y + 0.85, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(number, "modulate:a", 0.0, 0.4).set_delay(0.25)
		tween.tween_callback(number.queue_free)

func immune_impact(point: Vector3, message: String) -> void:
	_particles(point, Color("ffd66b"), 14, 0.3, 0.11)
	Sound.spatial("png_wall", self, point, -14.0)
	var label := Label3D.new()
	label.text = message
	label.font_size = 34
	label.pixel_size = 0.006
	label.modulate = Color("ffd66b")
	label.outline_modulate = Color("12181d")
	label.outline_size = 9
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.global_position = point + Vector3.UP * 0.35
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y + 0.7, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.35)
	tween.tween_callback(label.queue_free)
	if is_instance_valid(session.ui):
		session.ui.toast(message, 1.6)

func death_effect(point: Vector3) -> void:
	_particles(point, Color("b5f1df"), 34, 0.65, 0.55)

func _particles(point: Vector3, tint: Color, count: int, duration: float, radius: float) -> void:
	var particles = CPUParticles3D.new()
	particles.emitting = false
	particles.amount = count
	particles.lifetime = duration
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius
	particles.direction = Vector3.UP
	particles.spread = 160.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 4.5
	particles.gravity = Vector3(0, -5, 0)
	particles.color = tint
	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE * 0.055
	particles.mesh = mesh
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	particles.material_override = material
	add_child(particles)
	particles.global_position = point
	particles.finished.connect(particles.queue_free)
	particles.emitting = true

func clear_effects() -> void:
	for child in get_children():
		child.queue_free()
