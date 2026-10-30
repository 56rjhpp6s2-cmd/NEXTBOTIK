extends RefCounted
## Android/touch layer and LAN discovery integration coverage.

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
	for index in range(count):
		await game.get_tree().process_frame

func run(game) -> void:
	await game.get_tree().physics_frame
	await game.world.navigation.wait_ready()
	check(is_instance_valid(game.mobile_controls), "Mobile test flag installs the Android touch layer")
	check(game.mobile_controls.tracked_buttons.size() >= 9, "Touch HUD exposes movement, combat, interaction and menu buttons")
	game.game_modes.select(GameModeManager.GameplayMode.SANDBOX, false)
	game.start_run()
	await frames(game, 3)
	var controls = game.mobile_controls
	controls._update_joystick(controls.joystick_center + Vector2(75, -75))
	check(Input.get_action_strength("right") > 0.5 and Input.get_action_strength("forward") > 0.5, "Virtual joystick feeds analog movement actions")
	controls._release_movement()
	check(Input.get_action_strength("right") == 0.0 and Input.get_action_strength("forward") == 0.0, "Releasing joystick clears movement actions")
	var old_yaw: float = game.player.rotation.y
	var old_pitch: float = game.player.view.pitch
	game.player.view.look_touch(Vector2(30, -18), game.player)
	check(not is_equal_approx(game.player.rotation.y, old_yaw) and not is_equal_approx(game.player.view.pitch, old_pitch), "Right-side swipe changes yaw and pitch")
	controls._hold_action("throw_png", true)
	check(Input.is_action_pressed("throw_png"), "Touch FIRE holds the existing projectile action")
	controls._hold_action("throw_png", false)
	check(not Input.is_action_pressed("throw_png"), "Touch FIRE releases without a stuck input")
	game.post_boss.begin_sandbox_test()
	await frames(game, 2)
	var left_reward: String = game.post_boss.choices[0]
	controls._reward_left()
	check(game.post_boss.winner == 0 and left_reward in game.game_modes.modifiers.acquired, "Mobile LEFT immediately applies the left reward")
	game.post_boss.begin_sandbox_test()
	await frames(game, 2)
	var right_reward: String = game.post_boss.choices[1]
	controls._use()
	check(game.post_boss.winner == 1 and right_reward in game.game_modes.modifiers.acquired, "Mobile RIGHT/USE immediately applies the right reward")
	var port := 24789
	check(game.network.host(port, "ANDROID HOST") == OK, "Mobile-compatible ENet host starts on UDP")
	game.network_menu._start_discovery_responder()
	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK, "LAN discovery probe binds an ephemeral UDP port")
	probe.set_dest_address("127.0.0.1", port + 1)
	probe.put_packet(game.network_menu.DISCOVERY_MAGIC.to_utf8_buffer())
	var response := ""
	for frame in range(90):
		game.network_menu._poll_discovery()
		if probe.get_available_packet_count() > 0:
			response = probe.get_packet().get_string_from_utf8()
			break
		await game.get_tree().process_frame
	check(response.begins_with(game.network_menu.SERVER_MAGIC + "|%d|" % port), "Windows/Android host answers automatic Wi-Fi/LAN discovery")
	probe.close()
	await game.network.disconnect_session("", false)
	controls._release_all()
	print("MOBILE TEST: %d checks, %d failures" % [checks, failures.size()])
	game.get_tree().quit(0 if failures.is_empty() else 1)
