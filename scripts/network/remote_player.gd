extends "res://scripts/player.gd"
## Visual/network actor with the same targeting interface as the local controller.
var peer_id: int = 0
var player_name: String = "PLAYER"
var target_position: Vector3
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var body_visual: Node3D
var name_tag: Label3D
var initialized: bool = false

func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	capsule = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	capsule.shape = shape
	capsule.position.y = 0.9
	add_child(capsule)
	view = HorrorCamera.new()
	add_child(view)
	view.camera.current = false
	view.flashlight.shadow_enabled = false
	view.flashlight.spot_range = 20.0
	body_visual = Node3D.new()
	add_child(body_visual)
	var tint: Color = [Color("7edfc8"), Color("e7a971"), Color("8bb4ed"), Color("d69ae8"), Color("d8d873"), Color("ee9292")][posmod(peer_id, 6)]
	var material = StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.8
	var torso = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.28
	mesh.height = 1.35
	torso.mesh = mesh
	torso.material_override = material
	torso.position.y = 0.8
	body_visual.add_child(torso)
	var head = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	head.mesh = sphere
	head.material_override = material
	head.position.y = 1.62
	body_visual.add_child(head)
	WorldSurface.box(body_visual, Vector3(0.29, 0.08, 0.07), Vector3(0, 1.64, -0.21), "dark", false)
	name_tag = WorldSurface.label(self, player_name, Vector3(0, 2.15, 0), tint, 31)
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	target_position = global_position
	active = true

func _unhandled_input(_event: InputEvent) -> void:
	return

func apply_pose(data: Dictionary, snap: bool = false) -> void:
	target_position = data.get("p", global_position)
	target_yaw = data.get("yaw", 0.0)
	target_pitch = data.get("pitch", 0.0)
	velocity = data.get("v", Vector3.ZERO)
	network_alive = data.get("alive", true)
	active = network_alive
	hidden = data.get("hidden", false)
	crouching = data.get("crouch", false)
	view.battery = data.get("battery", 100.0)
	view.flashlight_on = data.get("light", true)
	if snap or not initialized or global_position.distance_to(target_position) > 8.0:
		global_position = target_position
		rotation.y = target_yaw
	initialized = true

func _physics_process(delta: float) -> void:
	if not initialized:
		return
	global_position = global_position.lerp(target_position, 1.0 - exp(-delta * 18.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-delta * 18.0))
	view.rotation.x = target_pitch
	view.position.y = 0.92 if crouching else 1.62
	body_visual.scale.y = 0.64 if crouching else 1.0
	body_visual.visible = network_alive and not hidden
	name_tag.visible = network_alive and not hidden
	collision_layer = 8 if network_alive and not hidden else 0
	view.flashlight.visible = network_alive and not hidden and view.flashlight_on and view.battery > 0
	view.flashlight.shadow_enabled = false
