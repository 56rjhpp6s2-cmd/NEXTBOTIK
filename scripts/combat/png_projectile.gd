class_name PNGProjectile
extends Node3D
## A camera-facing image with a continuous swept volume, not a frame-only overlap.
@export var damage: float = 20.0
@export var speed: float = 35.0
@export var maximum_range: float = 100.0
@export var lifetime: float = 4.0
var shooter: Node3D
var damage_system
var session
var run_id: int = 0
var velocity: Vector3 = Vector3.ZERO
var previous_position: Vector3
var travelled: float = 0.0
var age: float = 0.0
var spent: bool = false
var visual_only: bool = false
var visual: Sprite3D
var texture: Texture2D
var image_size: float = 0.75
var collision_radius: float = 0.09
var shape = SphereShape3D.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	visual = Sprite3D.new()
	visual.texture = texture
	visual.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	visual.shaded = false
	visual.double_sided = true
	visual.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	visual.pixel_size = image_size / maxi(texture.get_width(), texture.get_height())
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	shape.radius = collision_radius
	previous_position = global_position

func _physics_process(delta: float) -> void:
	if spent:
		return
	if not is_instance_valid(session) or not session.is_running() or (run_id != session.projectiles.run_id and not session.network.active):
		expire()
		return
	var remaining_life = maxf(0.0, lifetime - age)
	var remaining_range = maxf(0.0, maximum_range - travelled)
	var distance = minf(velocity.length() * minf(delta, remaining_life), remaining_range)
	age += delta
	if distance <= 0.00001:
		expire()
		return
	previous_position = global_position
	var motion = velocity.normalized() * distance
	var hit = _sweep(previous_position, motion)
	if not hit.is_empty():
		global_position = hit.position
		_impact(hit)
		return
	global_position += motion
	travelled += distance
	if age >= lifetime or travelled >= maximum_range - 0.0001:
		expire()

func _sweep(origin: Vector3, motion: Vector3) -> Dictionary:
	var space = get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		excluded.append(shooter.get_rid())
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = 1 | 4
	query.collide_with_areas = true
	query.exclude = excluded
	query.margin = 0.01
	# cast_motion ignores initial overlaps, so handle those explicitly.
	var overlaps = space.intersect_shape(query, 1)
	if not overlaps.is_empty():
		return {"collider": overlaps[0].collider, "position": origin, "normal": -motion.normalized()}
	var ray = PhysicsRayQueryParameters3D.create(origin, origin + motion, 1 | 4, excluded)
	ray.collide_with_areas = true
	var ray_hit = space.intersect_ray(ray)
	query.motion = motion
	var fractions = space.cast_motion(query)
	if fractions.size() == 2 and fractions[0] < 1.0:
		var safe_distance = motion.length() * fractions[0]
		if not ray_hit.is_empty() and origin.distance_to(ray_hit.position) <= safe_distance:
			return ray_hit
		var overlap_fraction = minf(1.0, fractions[1] + 0.025 / maxf(motion.length(), 0.001))
		query.transform.origin = origin + motion * overlap_fraction
		query.motion = Vector3.ZERO
		var rest = space.get_rest_info(query)
		if not rest.is_empty():
			return {"collider": instance_from_id(rest.collider_id), "position": origin + motion * fractions[0], "normal": rest.normal}
		var contacts = space.intersect_shape(query, 1)
		if not contacts.is_empty():
			return {"collider": contacts[0].collider, "position": origin + motion * fractions[0], "normal": -motion.normalized()}
		if not ray_hit.is_empty():
			return ray_hit
		# Conservatively stop even when the backend cannot report a contact body.
		return {"collider": null, "position": origin + motion * fractions[0], "normal": -motion.normalized()}
	return ray_hit

func _impact(hit: Dictionary) -> void:
	if spent:
		return
	spent = true
	set_physics_process(false)
	visual.visible = false
	if visual_only:
		session.network.projectile_finished(self)
		queue_free()
		return
	var applied: float = damage_system.apply_hit(hit.get("collider"), damage, shooter, hit.position, velocity.normalized())
	if applied <= 0.0:
		damage_system.impact(hit.position)
		Sound.spatial("png_wall", damage_system, hit.position, -18.0)
	if session.network.active:
		session.network.projectile_finished(self, 2 if applied > 0 else 1, hit.position)
	queue_free()

func expire() -> void:
	if spent:
		return
	spent = true
	if is_instance_valid(session) and is_instance_valid(session.network) and session.network.active:
		session.network.projectile_finished(self)
	set_physics_process(false)
	if is_instance_valid(visual):
		visual.visible = false
	queue_free()
