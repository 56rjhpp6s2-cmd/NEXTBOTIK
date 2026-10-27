extends RefCounted
## Engine-level checks for momentum, stance clearance, slide and air control.
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func frames(game, count: int) -> void:
	for i in range(count):
		await game.get_tree().physics_frame

func run(game) -> void:
	var free_speed = FPSMovementMotor.accelerate(Vector3(0, 0, -12), Vector3.RIGHT, 8.5, 17.0, 1.0 / 60.0)
	check(free_speed.z == -12.0 and free_speed.x > 0.0, "Air steering adds sideways speed without erasing forward momentum")
	var one_step = FPSMovementMotor.accelerate(Vector3.ZERO, Vector3.RIGHT, 8.5, 17.0, 1.0 / 30.0)
	var two_steps = FPSMovementMotor.accelerate(FPSMovementMotor.accelerate(Vector3.ZERO, Vector3.RIGHT, 8.5, 17.0, 1.0 / 60.0), Vector3.RIGHT, 8.5, 17.0, 1.0 / 60.0)
	check(one_step.distance_to(two_steps) < 0.0001, "Acceleration is frame-rate independent")
	check(Sound.clips["slide"].data.size() > 100 and Sound.clips["wind"].data.size() > 100, "Movement audio exists without external files")
	check(game.ui.toggles.has("auto_bunnyhop") and game.ui.toggles.has("toggle_crouch") and game.ui.sliders.has("head_bob_intensity"), "Movement preferences are exposed in settings")
	game._select_map(1)
	await game.world.navigation.wait_ready()
	game.start_run()
	game.spawn_timer = 9999.0
	game._clear_bots()
	var p = game.player
	p.reset_at(Vector3(60, 0.1, 84))
	p.rotation.y = 0.0
	await frames(game, 30)
	check(p.is_on_floor(), "Movement test begins on Construct collision")
	Input.action_press("forward")
	Input.action_press("sprint")
	await frames(game, 70)
	var run_speed = FPSMovementMotor.horizontal(p.velocity).length()
	check(p.sprinting and run_speed > 10.5 and run_speed <= p.sprint_speed + 0.2, "Sprint accelerates smoothly to its configured speed")
	check(p.view.camera.fov > 79.0, "Sprint expands field of view")
	var endurance_wall = StaticBody3D.new()
	endurance_wall.collision_layer = 1
	var endurance_collision = CollisionShape3D.new()
	var endurance_box = BoxShape3D.new()
	endurance_box.size = Vector3(4.0, 3.0, 0.2)
	endurance_collision.shape = endurance_box
	endurance_wall.add_child(endurance_collision)
	game.add_child(endurance_wall)
	endurance_wall.global_position = p.global_position + Vector3(0, 1.5, -1.2)
	await frames(game, 440)
	check(p.sprinting and p.is_on_floor(), "Holding sprint for over seven seconds never causes exhaustion")
	var stamina_hud_found := false
	for control in game.ui.hud.get_children():
		if control is ProgressBar:
			stamina_hud_found = true
	check(not stamina_hud_found, "HUD no longer shows a stamina gauge")
	endurance_wall.queue_free()
	Input.action_release("forward")
	Input.action_release("sprint")
	p.reset_at(Vector3(60, 0.1, 84))
	p.rotation.y = 0.0
	await frames(game, 25)
	Input.action_press("forward")
	Input.action_press("sprint")
	await frames(game, 70)
	Input.action_press("crouch")
	await frames(game, 3)
	check(p.sliding and p.crouching and p.capsule.shape == p.crouch_shape, "Ctrl while sprinting enters slide with low collision capsule")
	check(FPSMovementMotor.horizontal(p.velocity).length() >= run_speed * 0.9, "Slide keeps run momentum")
	await frames(game, 8)
	check(p.view.position.y < 1.4, "Camera lowers smoothly during slide")
	Input.action_release("crouch")
	Input.action_press("jump")
	await frames(game, 1)
	var slide_jump_speed = FPSMovementMotor.horizontal(p.velocity).length()
	check(p.velocity.y > 4.0 and not p.sliding and slide_jump_speed > 9.0, "Slide jump carries speed into the air")
	Input.action_release("forward")
	Input.action_release("sprint")
	Input.action_press("right")
	await frames(game, 13)
	check(p.velocity.x > 1.0 and FPSMovementMotor.horizontal(p.velocity).length() <= p.maximum_practical_velocity + 0.01, "Air strafe changes direction under the speed ceiling")
	Input.action_release("jump")
	Input.action_release("right")
	p.reset_at(Vector3(60, 0.1, 84))
	p.rotation.y = 0.0
	await frames(game, 25)
	Settings.auto_bunnyhop = true
	Input.action_press("jump")
	var jump_count := 0
	var previous_y := 0.0
	for i in range(110):
		await game.get_tree().physics_frame
		if p.velocity.y > 5.5 and previous_y <= 5.5:
			jump_count += 1
		previous_y = p.velocity.y
	Input.action_release("jump")
	Settings.auto_bunnyhop = false
	check(jump_count >= 2, "Holding Space repeats a bunny hop after landing when enabled")
	p.reset_at(Vector3(60, 0.1, 84))
	await frames(game, 25)
	Input.action_press("crouch")
	await frames(game, 3)
	var ceiling = StaticBody3D.new()
	ceiling.collision_layer = 1
	ceiling.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(3.0, 0.24, 3.0)
	shape.shape = box
	ceiling.add_child(shape)
	game.add_child(ceiling)
	ceiling.global_position = p.global_position + Vector3.UP * 1.54
	await frames(game, 2)
	Input.action_release("crouch")
	await frames(game, 4)
	check(p.crouching and not p._can_stand(), "Low ceiling blocks standing while crouched")
	ceiling.queue_free()
	await frames(game, 4)
	check(not p.crouching and p.capsule.shape == p.standing_shape, "Player stands when headroom returns")
	Settings.toggle_crouch = true
	Input.action_press("crouch")
	await frames(game, 2)
	Input.action_release("crouch")
	await frames(game, 2)
	check(p.crouching, "Toggle crouch stays active after releasing Ctrl")
	Input.action_press("crouch")
	await frames(game, 2)
	Input.action_release("crouch")
	await frames(game, 2)
	check(not p.crouching, "Second Ctrl press cancels toggle crouch")
	Settings.toggle_crouch = false
	check(p.wind_player.bus == "SFX" and p.wind_player.playing, "Speed-based wind respects the SFX volume bus")
	p.reset_at(Vector3(60, 0.1, 84))
	p.rotation.y = 0.0
	var wall = StaticBody3D.new()
	wall.collision_layer = 1
	var wall_collision = CollisionShape3D.new()
	var wall_box = BoxShape3D.new()
	wall_box.size = Vector3(4.0, 2.8, 0.2)
	wall_collision.shape = wall_box
	wall.add_child(wall_collision)
	game.add_child(wall)
	wall.global_position = Vector3(60, 1.4, 82)
	await frames(game, 25)
	Input.action_press("forward")
	Input.action_press("jump")
	var touched_wall := false
	for i in range(55):
		await game.get_tree().physics_frame
		if p.is_on_wall() and not p.is_on_floor():
			touched_wall = true
			break
	check(touched_wall, "Airborne player physically reaches a solid wall")
	if touched_wall:
		Input.action_release("jump")
		await frames(game, 2)
		Input.action_press("jump")
		await frames(game, 1)
		check(p.velocity.y > 5.0 and p.velocity.z > 0.0 and p.wall_jump_wait > 0.0, "Fresh jump press pushes player upward and away from wall")
	Input.action_release("jump")
	Input.action_release("forward")
	wall.queue_free()
	print("MOVEMENT TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)
