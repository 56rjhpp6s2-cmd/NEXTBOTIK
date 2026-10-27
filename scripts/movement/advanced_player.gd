extends CharacterBody3D
## Fast, acceleration-based first-person locomotion. Tuning is exposed in the Inspector.
signal footsteps(at: Vector3, loudness: float)

@export_group("Ground")
@export var walk_speed := 6.7
@export var sprint_speed := 11.8
@export var crouch_speed := 3.2
@export var ground_acceleration := 58.0
@export var ground_friction := 20.0
@export_group("Air")
@export var air_acceleration := 17.0
@export var air_speed_cap := 8.5
@export var air_control := 3.5
@export var gravity := 22.0
@export var jump_velocity := 7.4
@export var coyote_time := 0.10
@export var jump_buffer_time := 0.12
@export var momentum_retention := 1.0
@export_group("Slide")
@export var slide_start_speed := 7.0
@export var slide_boost := 1.5
@export var slide_friction := 3.2
@export var slide_steering := 5.5
@export var slide_min_duration := 0.32
@export var slide_max_duration := 1.55
@export var slide_slope_force := 22.0
@export var maximum_practical_velocity := 22.0
@export_group("Parkour")
@export var enable_wall_jump := true
@export var wall_jump_push := 5.0
@export var wall_jump_cooldown := 0.4

var view: HorrorCamera
var capsule: CollisionShape3D
var active := false
var network_alive := true
var sprinting := false
var crouching := false
var sliding := false
var hidden := false
var step_distance := 0.0
var session
var standing_shape: CapsuleShape3D
var crouch_shape: CapsuleShape3D
var obstacle: NavigationObstacle3D
var wind_player: AudioStreamPlayer
var slide_time := 0.0
var jump_buffer := 0.0
var floor_grace := 0.0
var wall_jump_wait := 0.0
var crouch_toggled := false
var sprint_toggled := false
var previous_crouch := false
var previous_sprint := false
var previous_jump := false
var previous_slide_crouch := false
var last_floor_normal := Vector3.UP

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(48.0)
	standing_shape = CapsuleShape3D.new()
	standing_shape.radius = 0.32
	standing_shape.height = 1.8
	crouch_shape = CapsuleShape3D.new()
	crouch_shape.radius = 0.32
	crouch_shape.height = 1.1
	capsule = CollisionShape3D.new()
	capsule.shape = standing_shape
	capsule.position.y = 0.9
	add_child(capsule)
	view = HorrorCamera.new()
	view.name = "View"
	add_child(view)
	obstacle = NavigationObstacle3D.new()
	obstacle.radius = 0.38
	obstacle.height = 1.8
	obstacle.avoidance_layers = 2
	add_child(obstacle)
	wind_player = AudioStreamPlayer.new()
	wind_player.stream = Sound.clips["wind"]
	wind_player.bus = "SFX"
	wind_player.volume_db = -80.0
	add_child(wind_player)
	wind_player.play()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		view.look(event, self)
	if event.is_action_pressed("flashlight"):
		view.toggle_flashlight()
	if event.is_action_pressed("speedometer"):
		Settings.show_speedometer = not Settings.show_speedometer
		Settings.save()

func _can_stand() -> bool:
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 0.9)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _set_crouch(value: bool) -> void:
	crouching = value
	capsule.shape = crouch_shape if value else standing_shape
	capsule.position.y = 0.55 if value else 0.9

func _update_buttons() -> void:
	var crouch_down = Input.is_action_pressed("crouch")
	var sprint_down = Input.is_action_pressed("sprint")
	var jump_down = Input.is_action_pressed("jump")
	if Settings.toggle_crouch and crouch_down and not previous_crouch:
		crouch_toggled = not crouch_toggled
	if Settings.toggle_sprint and sprint_down and not previous_sprint:
		sprint_toggled = not sprint_toggled
	if jump_down and not previous_jump:
		jump_buffer = jump_buffer_time
	previous_crouch = crouch_down
	previous_sprint = sprint_down
	previous_jump = jump_down

func _want_crouch() -> bool:
	return crouch_toggled if Settings.toggle_crouch else Input.is_action_pressed("crouch")

func _want_sprint() -> bool:
	return sprint_toggled if Settings.toggle_sprint else Input.is_action_pressed("sprint")

func _start_slide(horizontal: Vector3) -> void:
	sliding = true
	slide_time = 0.0
	_set_crouch(true)
	horizontal = (horizontal + horizontal.normalized() * slide_boost).limit_length(maximum_practical_velocity)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	Sound.one_shot("slide", -14.0, randf_range(0.92, 1.08))

func _jump(wall_normal: Vector3 = Vector3.ZERO) -> void:
	if crouching and not sliding:
		return
	if sliding:
		if not _can_stand():
			return
		sliding = false
		_set_crouch(false)
	var horizontal = FPSMovementMotor.horizontal(velocity) * momentum_retention
	if wall_normal != Vector3.ZERO:
		horizontal += wall_normal * wall_jump_push
		wall_jump_wait = wall_jump_cooldown
	floor_grace = 0.0
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = jump_velocity
	jump_buffer = 0.0
	Sound.one_shot("jump", -16.0)
	view.on_jump()

func _physics_process(delta: float) -> void:
	if not active or hidden:
		velocity = Vector3.ZERO
		sprinting = false
		sliding = false
		wind_player.volume_db = -80.0
		view.tick(delta, 0.0, true, false, crouching, active)
		return
	var was_on_floor = is_on_floor()
	var downward_speed = maxf(0.0, -velocity.y)
	_update_buttons()
	jump_buffer = maxf(0.0, jump_buffer - delta)
	wall_jump_wait = maxf(0.0, wall_jump_wait - delta)
	floor_grace = coyote_time if was_on_floor else maxf(0.0, floor_grace - delta)
	if was_on_floor:
		last_floor_normal = get_floor_normal()
	var input = Input.get_vector("left", "right", "forward", "back")
	var wish = (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var horizontal = FPSMovementMotor.horizontal(velocity)
	var wants_crouch = _want_crouch()
	var sprint_requested = _want_sprint() and input.length() > 0.1 and not view.aiming
	if was_on_floor and not sliding and wants_crouch and not previous_slide_crouch and sprint_requested and horizontal.length() >= slide_start_speed:
		_start_slide(horizontal)
		horizontal = FPSMovementMotor.horizontal(velocity)
	previous_slide_crouch = wants_crouch
	if sliding:
		slide_time += delta
		if (not wants_crouch and slide_time >= slide_min_duration) or slide_time >= slide_max_duration or horizontal.length() < crouch_speed:
			sliding = false
	_set_crouch(sliding or wants_crouch or (crouching and not _can_stand()))
	sprinting = sprint_requested and not crouching and not sliding
	var jump_now = jump_buffer > 0.0 or (Settings.auto_bunnyhop and Input.is_action_pressed("jump"))
	if jump_now and (was_on_floor or floor_grace > 0.0) and (not crouching or sliding):
		_jump()
	elif jump_buffer > 0.0 and enable_wall_jump and not was_on_floor and is_on_wall() and wall_jump_wait <= 0.0:
		_jump(get_wall_normal())
	horizontal = FPSMovementMotor.horizontal(velocity)
	var on_ground = was_on_floor and velocity.y <= 0.0
	if on_ground:
		if sliding:
			var downhill = Vector3.DOWN.slide(last_floor_normal)
			downhill.y = 0.0
			horizontal += downhill * slide_slope_force * delta
			horizontal = FPSMovementMotor.friction(horizontal, slide_friction, delta)
			horizontal = FPSMovementMotor.accelerate(horizontal, wish, maxf(horizontal.length(), sprint_speed), slide_steering, delta)
		else:
			if not jump_now:
				horizontal = FPSMovementMotor.friction(horizontal, ground_friction, delta)
			var target_speed = crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)
			horizontal = FPSMovementMotor.accelerate(horizontal, wish, target_speed, ground_acceleration, delta)
	else:
		horizontal = FPSMovementMotor.accelerate(horizontal, wish, air_speed_cap, air_acceleration, delta)
		if wish != Vector3.ZERO and horizontal.length() > 0.1:
			var angle = horizontal.signed_angle_to(wish, Vector3.UP)
			var turned = horizontal.rotated(Vector3.UP, clampf(angle, -air_control * delta / horizontal.length(), air_control * delta / horizontal.length()))
			horizontal = horizontal.lerp(turned, minf(1.0, delta * 8.0))
	horizontal = horizontal.limit_length(maximum_practical_velocity)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not on_ground:
		velocity.y -= gravity * delta
	move_and_slide()
	var speed = FPSMovementMotor.horizontal(velocity).length()
	if not was_on_floor and is_on_floor():
		Sound.one_shot("land", -17.0 if downward_speed < 8.0 else -12.0)
		view.on_land(downward_speed)
	if is_on_floor() and speed > 0.5 and not sliding:
		step_distance += speed * delta
		if step_distance > (2.5 if sprinting else 2.0):
			step_distance = 0.0
			Sound.one_shot("step", -27.0 if crouching else (-10.0 if sprinting else -17.0), randf_range(0.84, 1.18))
			footsteps.emit(global_position, 0.2 if crouching else (1.0 if sprinting else 0.5))
	wind_player.volume_db = lerpf(wind_player.volume_db, lerpf(-75.0, -25.0, clampf((speed - 8.0) / 12.0, 0.0, 1.0)), 1.0 - exp(-delta * 4.0))
	view.tick(delta, speed, is_on_floor(), sprinting, crouching, true, sliding, input.x)
	if global_position.y < -8.0 and session != null:
		session.kill_player(null)

func reset_at(at: Vector3) -> void:
	network_alive = true
	global_position = at
	rotation.y = PI
	velocity = Vector3.ZERO
	sliding = false
	_set_crouch(false)
	hidden = false
	step_distance = 0.0
	slide_time = 0.0
	jump_buffer = 0.0
	floor_grace = 0.0
	wall_jump_wait = 0.0
	crouch_toggled = false
	sprint_toggled = false
	previous_crouch = false
	previous_sprint = false
	previous_jump = false
	previous_slide_crouch = false
	wind_player.volume_db = -80.0
	view.reset_view()
	view.camera.make_current()
	active = true
