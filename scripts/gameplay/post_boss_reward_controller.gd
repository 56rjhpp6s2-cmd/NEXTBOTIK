class_name PostBossRewardController
extends Node3D
## Post-boss state machine, world presentation and authoritative vote tally.

enum RewardState {
	BOSS_FIGHT,
	BOSS_DEFEATED,
	REWARD_PREPARATION,
	REWARD_SELECTION,
	REWARD_FINALIZED,
	PROGRESSION_UNLOCKED,
	LEVEL_TRANSITION,
}

const NPC_TEXTURE: Texture2D = preload("res://assets/rewards/reward_keeper.jpg")
const INTERACTION_DISTANCE := 6.5
@export var left_hand_anchor := Vector2(-1.30, 2.20)
@export var right_hand_anchor := Vector2(1.30, 1.82)

var session
var state: RewardState = RewardState.BOSS_FIGHT
var phase_id: int = 0
var phase_level: int = 0
var choices: Array[String] = []
var winner: int = -1
var votes: Dictionary = {}
var vote_time_left: float = 0.0
var focused_choice: int = -1
var npc_position: Vector3 = Vector3.ZERO
var facing_player: Vector3 = Vector3.FORWARD
var lever_position: Vector3 = Vector3.ZERO
var requires_lever: bool = true
var sandbox_test: bool = false
var applied_phases: Dictionary = {}
var suppressed_exits: Array[WorldInteractable] = []

var presentation: Node3D
var npc_sprite: Sprite3D
var reward_roots: Array[Node3D] = []
var reward_models: Array[Node3D] = []
var reward_lights: Array[OmniLight3D] = []
var lever: WorldInteractable
var elapsed := 0.0

func setup(owner_session) -> void:
	session = owner_session
	name = "PostBossRewardController"
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	elapsed += delta
	_update_hand_anchors()
	_animate_rewards(delta)
	if state == RewardState.REWARD_SELECTION and session.network.active:
		vote_time_left = maxf(0.0, vote_time_left - delta)
		session.ui.update_reward_votes(votes, vote_time_left, session.network.local_id())
		if session.is_authority() and vote_time_left <= 0.0:
			_finalize_authoritative(_majority_choice())

func begin_after_boss() -> void:
	if not session.is_authority() or state not in [RewardState.BOSS_FIGHT, RewardState.LEVEL_TRANSITION]:
		return
	if phase_level == session.current_level and state != RewardState.LEVEL_TRANSITION:
		return
	phase_level = session.current_level
	phase_id += 1
	state = RewardState.BOSS_DEFEATED
	session.spawn_timer = INF
	for bot in session.bots:
		bot.enabled = false
	session.ui.toast("BOSS DEFEATED\nTHE REWARD KEEPER IS COMING", 3.0)
	await get_tree().create_timer(0.72, false).timeout
	if not is_instance_valid(session) or session.current_level != phase_level or state != RewardState.BOSS_DEFEATED:
		return
	state = RewardState.REWARD_PREPARATION
	session.pending_respawns.clear()
	# The dead boss has already emitted its death effect; remove any phase minions
	# before interaction so the reward location is genuinely safe.
	session._clear_bots()
	var random := RandomNumberGenerator.new()
	random.seed = int(hash([session.progression_root_seed, phase_level, phase_id, "reward"])) & 0x7fffffff
	var offered: Array[String] = session.game_modes.modifiers.choices(random, 2)
	if offered.size() < 2:
		session.game_modes.modifiers.reset()
		offered = session.game_modes.modifiers.choices(random, 2)
	var data := _make_phase_data(offered)
	if session.network.active:
		session.network.begin_reward_phase(data)
	else:
		start_selection(data)

func begin_sandbox_test() -> void:
	cleanup_world(false)
	sandbox_test = true
	requires_lever = false
	phase_level = session.current_level
	phase_id += 1
	var random := RandomNumberGenerator.new()
	random.seed = int(Time.get_ticks_usec())
	var offered: Array[String] = session.game_modes.modifiers.choices(random, 2)
	if offered.size() < 2:
		session.game_modes.modifiers.reset()
		offered = session.game_modes.modifiers.choices(random, 2)
	var data := _make_phase_data(offered)
	var forward: Vector3 = -session.player.view.camera.global_basis.z
	forward.y = 0.0
	data.position = session.player.global_position + forward.normalized() * 4.2
	data.position.y = session.player.global_position.y
	start_selection(data)

func _make_phase_data(offered: Array[String]) -> Dictionary:
	requires_lever = session.game_modes.selected in [GameModeManager.GameplayMode.BOSSFIGHT, GameModeManager.GameplayMode.ENDLESS]
	sandbox_test = session.game_modes.selected == GameModeManager.GameplayMode.SANDBOX
	var at := _safe_reward_position()
	var toward: Vector3 = session.player.global_position - at
	toward.y = 0.0
	if toward.length_squared() < 0.1:
		toward = Vector3.FORWARD
	return {
		"phase": phase_id,
		"level": phase_level,
		"choices": offered,
		"position": at,
		"facing": toward.normalized(),
		"timer": session.gameplay_config.reward_vote_seconds,
		"requires_lever": requires_lever,
		"sandbox": sandbox_test,
	}

func _safe_reward_position() -> Vector3:
	if session.world is BossfightWorld and session.world.arena_mode:
		return Vector3(0, 0.08, 0)
	var desired: Vector3 = session.player.global_position + (-session.player.view.camera.global_basis.z * 4.0)
	desired.y = session.player.global_position.y
	if session.world.navigation.synchronized:
		var closest := NavigationServer3D.map_get_closest_point(session.get_world_3d().navigation_map, desired)
		if closest.is_finite():
			return closest + Vector3.UP * 0.08
	return session.world.spawns[0]

func start_selection(data: Dictionary) -> void:
	var incoming_phase := int(data.get("phase", 0))
	if incoming_phase < phase_id or int(data.get("level", session.current_level)) != session.current_level:
		return
	cleanup_world(false)
	phase_id = incoming_phase
	phase_level = int(data.get("level", session.current_level))
	choices.assign(data.get("choices", []))
	if choices.size() != 2 or choices[0] == choices[1]:
		push_error("Reward phase requires two distinct choices")
		return
	npc_position = data.get("position", Vector3.ZERO)
	facing_player = data.get("facing", Vector3.FORWARD)
	vote_time_left = maxf(0.0, float(data.get("timer", session.gameplay_config.reward_vote_seconds)))
	requires_lever = bool(data.get("requires_lever", true))
	sandbox_test = bool(data.get("sandbox", false))
	winner = -1
	votes.clear()
	state = RewardState.REWARD_SELECTION
	_suppress_normal_exits()
	_build_presentation()
	session.ui.show_reward_phase(choices, session.network.active, vote_time_left)
	session.ui.toast("CHOOSE A REWARD\n[Q] LEFT HAND   /   [E] RIGHT HAND", 5.0)

func update_focus(camera: Camera3D) -> String:
	focused_choice = -1
	if state != RewardState.REWARD_SELECTION or not is_instance_valid(presentation):
		return ""
	# The photographed hands are wide apart, but the interaction cone is generous
	# so controller users and players with camera shake never need pixel aiming.
	var best := 0.74
	for index in range(reward_roots.size()):
		var offset := reward_roots[index].global_position - camera.global_position
		if offset.length() > INTERACTION_DISTANCE:
			continue
		var score := offset.normalized().dot(-camera.global_basis.z)
		if score > best:
			best = score
			focused_choice = index
	_update_highlight()
	return "[Q] LEFT: %s    /    [E] RIGHT: %s" % [GameplayModifierSet.DEFINITIONS[choices[0]].title, GameplayModifierSet.DEFINITIONS[choices[1]].title]

func select_choice(choice: int) -> bool:
	if state != RewardState.REWARD_SELECTION or choice not in [0, 1]:
		return false
	focused_choice = choice
	_update_highlight()
	if session.network.active:
		session.network.request_reward_vote(choice)
	else:
		_finalize_authoritative(choice)
	return true

func interact_focused() -> bool:
	if focused_choice < 0:
		return false
	return select_choice(focused_choice)

func register_vote(peer_id: int, choice: int) -> void:
	if state != RewardState.REWARD_SELECTION or choice not in [0, 1]:
		return
	votes[peer_id] = choice
	if session.network.active and session.network.is_host():
		session.network.broadcast_reward_votes(phase_id, votes, vote_time_left)

func remove_vote(peer_id: int) -> void:
	if votes.erase(peer_id) and session.network.active and session.network.is_host():
		session.network.broadcast_reward_votes(phase_id, votes, vote_time_left)

func sync_votes(incoming_phase: int, incoming_votes: Dictionary, time_left: float) -> void:
	if incoming_phase != phase_id or state != RewardState.REWARD_SELECTION:
		return
	votes = incoming_votes.duplicate()
	vote_time_left = maxf(0.0, time_left)
	session.ui.update_reward_votes(votes, vote_time_left, session.network.local_id() if session.network.active else 1)

func _majority_choice() -> int:
	var counts := [0, 0]
	for choice in votes.values():
		if int(choice) in [0, 1]:
			counts[int(choice)] += 1
	if counts[0] > counts[1]:
		return 0
	if counts[1] > counts[0]:
		return 1
	var random := RandomNumberGenerator.new()
	random.seed = int(hash([session.progression_root_seed, phase_id, votes.size(), "tie"])) & 0x7fffffff
	return random.randi_range(0, 1)

func _finalize_authoritative(choice: int) -> void:
	if state != RewardState.REWARD_SELECTION or choice not in [0, 1]:
		return
	if session.network.active:
		if not session.network.is_host():
			return
		session.network.finalize_reward_phase(phase_id, choice, choices[choice])
	else:
		finalize_selection(phase_id, choice, choices[choice])

func finalize_selection(incoming_phase: int, choice: int, reward: String) -> void:
	if incoming_phase != phase_id or state != RewardState.REWARD_SELECTION or choice not in [0, 1] or choices[choice] != reward:
		return
	winner = choice
	state = RewardState.REWARD_FINALIZED
	if not applied_phases.has(phase_id):
		if session.game_modes.apply_run_reward(reward):
			applied_phases[phase_id] = true
		else:
			push_error("Reward could not be applied exactly once: " + reward)
	var losing := 1 - choice
	if losing < reward_roots.size() and is_instance_valid(reward_roots[losing]):
		var lose_tween := create_tween().set_parallel(true)
		lose_tween.tween_property(reward_roots[losing], "scale", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_BACK)
	if choice < reward_roots.size() and is_instance_valid(reward_roots[choice]):
		var win_tween := create_tween()
		win_tween.tween_property(reward_roots[choice], "scale", Vector3.ONE * 1.35, 0.18).set_trans(Tween.TRANS_BACK)
		win_tween.tween_property(reward_roots[choice], "scale", Vector3.ONE, 0.25)
	Sound.one_shot("battery", -6.0, 1.3)
	var definition: Dictionary = GameplayModifierSet.DEFINITIONS[reward]
	session.ui.finalize_reward(choice, reward, requires_lever)
	session.ui.toast("REWARD APPLIED\n%s\n%s" % [definition.title, definition.stats], 4.0)
	if requires_lever:
		_spawn_progression_lever()
		state = RewardState.PROGRESSION_UNLOCKED
	else:
		state = RewardState.REWARD_FINALIZED
		_finish_nonprogression_reward.call_deferred(phase_id)

func _finish_nonprogression_reward(finalized_phase: int) -> void:
	# Sandbox and Mayhem do not use a progression lever. Keep the acquisition
	# pose briefly, then remove the encounter and restore the normal weapon flow.
	await get_tree().create_timer(1.2, false).timeout
	if finalized_phase != phase_id or state != RewardState.REWARD_FINALIZED or requires_lever:
		return
	cleanup_world(false)
	state = RewardState.BOSS_FIGHT
	session.game_modes.post_reward_without_lever()

func _build_presentation() -> void:
	presentation = Node3D.new()
	presentation.name = "RewardKeeperEncounter"
	presentation.position = npc_position
	add_child(presentation)
	var frame := MeshInstance3D.new()
	var frame_mesh := QuadMesh.new()
	frame_mesh.size = Vector2(3.18, 2.66)
	frame.mesh = frame_mesh
	frame.position = Vector3(0, 1.35, 0.035)
	var frame_material := StandardMaterial3D.new()
	frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frame_material.albedo_color = Color(0.18, 0.82, 0.71, 0.28)
	frame_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	frame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	frame.material_override = frame_material
	presentation.add_child(frame)
	npc_sprite = Sprite3D.new()
	npc_sprite.name = "ReferencePhotoNPC"
	npc_sprite.texture = NPC_TEXTURE
	npc_sprite.position = Vector3(0, 1.35, 0)
	npc_sprite.pixel_size = 2.55 / float(NPC_TEXTURE.get_height())
	npc_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	npc_sprite.shaded = false
	npc_sprite.double_sided = true
	npc_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	presentation.add_child(npc_sprite)
	var title := Label3D.new()
	title.text = "THE REWARD KEEPER\n[Q] LEFT   /   [E] RIGHT"
	title.position = Vector3(0, 3.06, 0)
	title.font_size = 34
	title.pixel_size = 0.007
	title.outline_size = 10
	title.modulate = Color("d8fff2")
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	presentation.add_child(title)
	var spawn_light := OmniLight3D.new()
	spawn_light.position = Vector3(0, 1.5, 0.4)
	spawn_light.light_color = Color("7dffe0")
	spawn_light.light_energy = 0.45
	spawn_light.omni_range = 1.8
	spawn_light.shadow_enabled = false
	presentation.add_child(spawn_light)
	reward_roots.clear()
	reward_models.clear()
	reward_lights.clear()
	for index in range(2):
		_build_reward_visual(index)
	presentation.scale = Vector3.ONE * 0.02
	var tween := create_tween()
	tween.tween_property(presentation, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(spawn_light, "light_energy", 0.05, 0.9)

func _build_reward_visual(index: int) -> void:
	var reward := choices[index]
	var definition: Dictionary = GameplayModifierSet.DEFINITIONS[reward]
	var color := GameplayModifierSet.rarity_color(reward)
	var root := Node3D.new()
	root.name = "LeftHandReward" if index == 0 else "RightHandReward"
	presentation.add_child(root)
	reward_roots.append(root)
	var card := MeshInstance3D.new()
	var card_mesh := BoxMesh.new()
	card_mesh.size = Vector3(0.72, 0.72, 0.12)
	card.mesh = card_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color.darkened(0.38)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.25
	card.material_override = material
	root.add_child(card)
	var model := Node3D.new()
	root.add_child(model)
	reward_models.append(model)
	_build_category_model(model, str(definition.category), color)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.28
	light.omni_range = 1.25
	light.shadow_enabled = false
	root.add_child(light)
	reward_lights.append(light)

func _build_category_model(parent: Node3D, category: String, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color.lightened(0.25)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.8
	if category == "NEW WEAPON":
		var barrel := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.08
		cylinder.bottom_radius = 0.12
		cylinder.height = 0.62
		barrel.mesh = cylinder
		barrel.rotation.z = PI / 2.0
		barrel.material_override = material
		parent.add_child(barrel)
		WorldSurface.box(parent, Vector3(0.25, 0.24, 0.22), Vector3(-0.18, -0.12, 0), "metal", false)
	elif category == "MOVEMENT":
		WorldSurface.box(parent, Vector3(0.15, 0.52, 0.14), Vector3(0, -0.02, 0), "glow", false).rotation.z = -0.75
		WorldSurface.box(parent, Vector3(0.34, 0.14, 0.14), Vector3(0.15, 0.14, 0), "glow", false).rotation.z = 0.55
	elif category == "DEFENSE":
		var shield := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		shield.mesh = sphere
		shield.scale.z = 0.32
		shield.material_override = material
		parent.add_child(shield)
	else:
		var gem := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.42, 0.48, 0.2)
		gem.mesh = prism
		gem.material_override = material
		parent.add_child(gem)

func _update_hand_anchors() -> void:
	if not is_instance_valid(presentation) or reward_roots.size() != 2:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	for index in range(2):
		if not is_instance_valid(reward_roots[index]):
			continue
		var anchor := left_hand_anchor if index == 0 else right_hand_anchor
		reward_roots[index].global_position = npc_position + right * anchor.x + Vector3.UP * (anchor.y + sin(elapsed * 2.4 + index) * 0.07)
		reward_roots[index].look_at(camera.global_position, Vector3.UP, true)

func _animate_rewards(delta: float) -> void:
	for index in range(reward_models.size()):
		if is_instance_valid(reward_models[index]):
			reward_models[index].rotate_y(delta * (1.35 if index == 0 else -1.35))

func _update_highlight() -> void:
	for index in range(reward_roots.size()):
		if not is_instance_valid(reward_roots[index]):
			continue
		var target := Vector3.ONE * (1.18 if index == focused_choice else 1.0)
		reward_roots[index].scale = reward_roots[index].scale.lerp(target, 0.22)
		if index < reward_lights.size():
			reward_lights[index].light_energy = 0.75 if index == focused_choice else 0.28
	session.ui.focus_reward(focused_choice)

func _suppress_normal_exits() -> void:
	suppressed_exits.clear()
	for item in session.world.interactables:
		if item.kind == "exit" and item.active:
			item.active = false
			item.visible = false
			suppressed_exits.append(item)

func _spawn_progression_lever() -> void:
	if is_instance_valid(lever):
		return
	var behind := -facing_player.normalized()
	var candidates := [npc_position + behind * 3.0, npc_position + behind * 3.0 + Vector3(-behind.z, 0, behind.x) * 1.6, npc_position + behind * 3.0 - Vector3(-behind.z, 0, behind.x) * 1.6]
	var chosen: Vector3 = candidates[0]
	for candidate in candidates:
		var bounds := AABB(candidate + Vector3(-0.6, 0.0, -0.6), Vector3(1.2, 2.2, 1.2))
		if session.world.navigation_clear(bounds):
			chosen = candidate
			break
	lever_position = chosen + Vector3.UP * 1.0
	lever = preload("res://scripts/interactable.gd").new()
	lever.kind = "progression_lever"
	lever.title = "NEXT CYCLE"
	lever.position = lever_position
	lever.set_meta("dynamic_geometry", true)
	session.world.add_child(lever)
	session.world.interactables.append(lever)
	lever.scale = Vector3.ONE * 0.02
	var tween := create_tween()
	tween.tween_property(lever, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sound.spatial("breaker", session.world, lever.global_position, -8.0)
	session.ui.toast("PROGRESSION UNLOCKED\nTHE LEVER IS BEHIND THE KEEPER", 4.0)

func try_activate_lever() -> bool:
	if state != RewardState.PROGRESSION_UNLOCKED or not is_instance_valid(lever) or lever.used:
		return false
	lever.activate()
	state = RewardState.LEVEL_TRANSITION
	session.ui.hide_reward_phase()
	Sound.spatial("breaker", session.world, lever.global_position, -5.0)
	session.advance_level()
	return true

func post_boss_snapshot() -> Dictionary:
	return {
		"state": int(state), "phase": phase_id, "level": phase_level, "choices": choices.duplicate(),
		"winner": winner, "votes": votes.duplicate(), "timer": vote_time_left,
		"position": npc_position, "facing": facing_player, "requires_lever": requires_lever,
		"sandbox": sandbox_test, "modifiers": session.game_modes.modifiers.snapshot(),
	}

func apply_network_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		return
	session.game_modes.restore_run_rewards(data.get("modifiers", {}))
	var incoming_state := int(data.get("state", RewardState.BOSS_FIGHT))
	if incoming_state in [RewardState.REWARD_SELECTION, RewardState.REWARD_FINALIZED, RewardState.PROGRESSION_UNLOCKED]:
		var start_data := {
			"phase": int(data.get("phase", 0)), "level": int(data.get("level", session.current_level)),
			"choices": data.get("choices", []), "position": data.get("position", Vector3.ZERO),
			"facing": data.get("facing", Vector3.FORWARD), "timer": float(data.get("timer", 0.0)),
			"requires_lever": bool(data.get("requires_lever", true)), "sandbox": bool(data.get("sandbox", false)),
		}
		if phase_id != int(start_data.phase) or not is_instance_valid(presentation):
			start_selection(start_data)
		sync_votes(phase_id, data.get("votes", {}), float(data.get("timer", 0.0)))
		if incoming_state >= RewardState.REWARD_FINALIZED and state == RewardState.REWARD_SELECTION:
			var selected := int(data.get("winner", -1))
			if selected in [0, 1]:
				# The modifier snapshot was restored above, so latch this phase before
				# finalization to avoid granting the late joiner a duplicate stack.
				applied_phases[phase_id] = true
				finalize_selection(phase_id, selected, choices[selected])

func begin_level_transition() -> void:
	state = RewardState.LEVEL_TRANSITION
	cleanup_world(false)

func level_ready() -> void:
	cleanup_world(false)
	state = RewardState.BOSS_FIGHT
	phase_level = 0

func reset_run() -> void:
	cleanup_world(true)
	state = RewardState.BOSS_FIGHT
	phase_id = 0
	phase_level = 0
	applied_phases.clear()
	sandbox_test = false

func cleanup_world(restore_exits: bool = false) -> void:
	focused_choice = -1
	if restore_exits:
		for item in suppressed_exits:
			if is_instance_valid(item) and not item.used:
				item.active = true
				item.visible = true
	suppressed_exits.clear()
	if is_instance_valid(lever):
		if is_instance_valid(session.world):
			session.world.interactables.erase(lever)
		lever.queue_free()
	lever = null
	if is_instance_valid(presentation):
		presentation.queue_free()
	presentation = null
	npc_sprite = null
	reward_roots.clear()
	reward_models.clear()
	reward_lights.clear()
	choices.clear()
	votes.clear()
	winner = -1
	session.ui.hide_reward_phase()
