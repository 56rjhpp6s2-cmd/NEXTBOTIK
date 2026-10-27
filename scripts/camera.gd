class_name HorrorCamera
extends Node3D
## Mouse view, view-height easing, bob, sprint FOV, recoil and flashlight.
var camera: Camera3D
var flashlight: SpotLight3D
var pitch: float = 0.0
var bob_phase: float = 0.0
var shake: float = 0.0
var battery: float = 100.0
var flashlight_on: bool = true
var sensitivity_multiplier: float = 1.0
var aiming: bool = false
var vertical_feedback: float = 0.0
var vertical_feedback_speed: float = 0.0
var strafe_tilt: float = 0.0

func _ready() -> void:
	position.y = 1.62
	camera = Camera3D.new()
	camera.near = 0.06
	camera.far = 135.0
	camera.fov = 79.0
	add_child(camera)
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.18, -0.12, -0.1)
	flashlight.light_color = Color("d7e7dc")
	flashlight.light_energy = 3.3
	flashlight.spot_range = 27.0
	flashlight.spot_angle = 31.0
	flashlight.spot_angle_attenuation = 0.7
	camera.add_child(flashlight)
	Settings.changed.connect(_quality)
	_quality()

func _quality() -> void:
	flashlight.shadow_enabled = Settings.quality > 0

func look(event: InputEventMouseMotion, body: Node3D) -> void:
	var amount = Settings.sensitivity * sensitivity_multiplier * PI / 180.0
	body.rotate_y(-event.relative.x * amount)
	pitch = clampf(pitch - event.relative.y * amount, -1.48, 1.48)
	rotation.x = pitch

func tick(delta: float, speed: float, grounded: bool, sprinting: bool, crouching: bool, active: bool, sliding: bool = false, strafe: float = 0.0) -> void:
	var target_height = 0.70 if sliding else (0.92 if crouching else 1.62)
	position.y = lerpf(position.y, target_height, 1.0 - exp(-delta * (17.0 if sliding else 13.0)))
	if grounded and speed > 0.5 and active:
		bob_phase += delta * (13.0 if sprinting else 9.0) * clampf(speed / 8.0, 0.55, 1.7)
	var bob = sin(bob_phase) * minf(speed / 7.0, 1.0) * 0.028 * Settings.head_bob_intensity if grounded and not sliding else 0.0
	vertical_feedback_speed += (-vertical_feedback * 85.0 - vertical_feedback_speed * 15.0) * delta
	vertical_feedback += vertical_feedback_speed * delta
	camera.position = camera.position.lerp(Vector3(cos(bob_phase * 0.5) * 0.014 * Settings.head_bob_intensity, bob + vertical_feedback, 0), 1.0 - exp(-delta * 15.0))
	var target_fov: float = 64.0 if aiming else (79.0 + clampf((speed - 5.0) * 0.95, 0.0, 12.0) if Settings.dynamic_fov else 79.0)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 8.0))
	shake = move_toward(shake, 0.0, delta * 2.0)
	strafe_tilt = lerpf(strafe_tilt, -strafe * minf(1.0, speed / 10.0) * 0.026 if Settings.camera_tilt and grounded else 0.0, 1.0 - exp(-delta * 9.0))
	camera.rotation.z = strafe_tilt + sin(Time.get_ticks_msec() * 0.08) * shake * 0.035 * Settings.camera_shake_intensity
	if active and flashlight_on:
		battery = maxf(0.0, battery - delta * 0.38)
	flashlight.visible = flashlight_on and battery > 0.0
	flashlight.light_energy = 3.3 * (0.55 + 0.45 * clampf(battery / 8.0, 0.0, 1.0))

func on_jump() -> void:
	vertical_feedback_speed += 0.7 * Settings.camera_shake_intensity

func on_land(fall_speed: float) -> void:
	vertical_feedback_speed -= clampf(fall_speed * 0.16, 0.55, 2.2) * Settings.camera_shake_intensity
	shake = maxf(shake, clampf((fall_speed - 6.0) * 0.055, 0.0, 0.28))

func toggle_flashlight() -> void:
	flashlight_on = not flashlight_on
	Sound.one_shot("click", -15.0)

func reset_view() -> void:
	aiming = false
	sensitivity_multiplier = 1.0
	pitch = 0.0
	rotation = Vector3.ZERO
	battery = 100.0
	flashlight_on = true
	vertical_feedback = 0.0
	vertical_feedback_speed = 0.0
	strafe_tilt = 0.0
	shake = 0.0
