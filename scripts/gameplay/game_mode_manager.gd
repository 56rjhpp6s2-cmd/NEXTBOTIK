class_name GameModeManager
extends Node
## Rules and scoring for the local modes. The run coordinator still owns
## world transitions, actors and screens; this node only defines mode policy.

enum GameplayMode { ARCADE, ENDLESS, PNG_MAYHEM, SANDBOX, BOSSFIGHT }

const NAMES := ["ARCADE", "ENDLESS", "PNG MAYHEM", "SANDBOX", "BOSSFIGHT"]
const DESCRIPTIONS := [
	"Survive a five-minute pursuit. Speed, slides and close escapes build score.",
	"Descend forever. Procedural rooms, darkness and aggression begin at Level 4.",
	"Clear escalating combat waves, choose reusable PNG upgrades and defeat bosses.",
	"A live Nextbot playground. Spawn, tune, relight and regenerate without restarting.",
	"Find three randomized switches across a desert district, then defeat a boss every fourth level.",
]
const BOSSFIGHT_IDLE_FACE: Texture2D = preload("res://assets/bosses/bossfight_idle.jpg")
const BOSSFIGHT_ATTACK_FACE: Texture2D = preload("res://assets/bosses/bossfight_attack.jpg")

var session
var config: GameplayConfig
var statistics: StatisticsManager
var modifiers := GameplayModifierSet.new()
var selected: GameplayMode = GameplayMode.ENDLESS
var arcade_round: int = 0
var arcade_time_left: float = 300.0
var arcade_score: float = 0.0
var arcade_multiplier: float = 1.0
var arcade_close_escape_cooldown: float = 0.0
var session_leaderboard: Array[Dictionary] = []
var mayhem_wave: int = 0
var mayhem_wave_kills: int = 0
var mayhem_wave_target: int = 0
var mayhem_total_score: int = 0
var mayhem_multiplier: float = 1.0
var mayhem_waiting_for_upgrade: bool = false
var mayhem_next_wave_delay: float = 0.0
var mayhem_wave_pending: bool = false
var bossfight_boss_pending: bool = false
var offered_upgrades: Array[String] = []
var active_boss: NextbotEnemy
var ending: bool = false
var rng := RandomNumberGenerator.new()
var base_walk_speed: float = 0.0
var base_sprint_speed: float = 0.0
var base_air_acceleration: float = 0.0
var base_slide_friction: float = 0.0
var base_jump_velocity: float = 0.0
var sandbox := {
	"speed": 11.4,
	"health": 100.0,
	"damage": 100.0,
	"aggression": 1.0,
	"detection": 34.0,
	"size": 1.0,
	"count": 1,
	"attacks": true,
	"ai": true,
	"invincible": true,
	"lighting": 1.0,
	"auto_spawn": false,
	"auto_spawn_interval": 4.0,
	"auto_spawn_limit": 12,
}
var sandbox_spawn_timer: float = 0.0
var sandbox_light_energy: Dictionary = {}
var sandbox_ambient_energy: float = -1.0

func setup(owner_session, tuning: GameplayConfig, stats: StatisticsManager) -> void:
	session = owner_session
	config = tuning
	statistics = stats
	selected = clampi(Settings.selected_game_mode, 0, 4)
	rng.randomize()
	base_walk_speed = session.player.walk_speed
	base_sprint_speed = session.player.sprint_speed
	base_air_acceleration = session.player.air_acceleration
	base_slide_friction = session.player.slide_friction
	base_jump_velocity = session.player.jump_velocity
	sandbox.auto_spawn_interval = config.sandbox_auto_spawn_interval
	sandbox.auto_spawn_limit = config.sandbox_auto_spawn_limit

func select(index: int, persist: bool = true) -> void:
	selected = clampi(index, 0, 4)
	if persist:
		Settings.selected_game_mode = int(selected)
		Settings.save()

func mode_name() -> String:
	return NAMES[int(selected)]

func description() -> String:
	return DESCRIPTIONS[int(selected)]

func before_start() -> void:
	# Local Arcade rotates authored maps between rounds. Network sessions retain
	# the host-selected authored map and currently use Endless rules.
	if selected == GameplayMode.ARCADE and arcade_round > 0 and not session.network.active:
		Settings.level_index = (Settings.level_index + 1) % 2
		session._load_world(Settings.level_index)
		session.ui.set_map_description(session.world)

func start_run() -> void:
	ending = false
	mayhem_waiting_for_upgrade = false
	offered_upgrades.clear()
	modifiers.reset()
	session.player.walk_speed = base_walk_speed
	session.player.sprint_speed = base_sprint_speed
	session.player.air_acceleration = base_air_acceleration
	session.player.slide_friction = base_slide_friction
	session.player.jump_velocity = base_jump_velocity
	match selected:
		GameplayMode.ARCADE:
			arcade_round += 1
			arcade_time_left = config.arcade_round_seconds
			arcade_score = 0.0
			arcade_multiplier = 1.0
			arcade_close_escape_cooldown = 0.0
			session.spawn_timer = 0.75
		GameplayMode.ENDLESS:
			# The old nine-second delay made a healthy run look empty or broken.
			session.spawn_timer = minf(session.spawn_timer, 2.0)
		GameplayMode.PNG_MAYHEM:
			mayhem_wave = 0
			mayhem_total_score = 0
			mayhem_multiplier = 1.0
			mayhem_next_wave_delay = 0.8
			mayhem_wave_pending = true
			session.projectiles.unlimited_ammo = true
		GameplayMode.SANDBOX:
			session.spawn_timer = INF
			sandbox_spawn_timer = 0.25
			_capture_sandbox_lighting()
			apply_sandbox_lighting()
		GameplayMode.BOSSFIGHT:
			bossfight_level_ready()

func finish_run() -> void:
	_restore_player_tuning()
	if statistics.dirty:
		statistics.save_data()

func tick(delta: float) -> void:
	statistics.tick_playtime(delta)
	match selected:
		GameplayMode.ARCADE:
			_tick_arcade(delta)
		GameplayMode.PNG_MAYHEM:
			_tick_mayhem(delta)
		GameplayMode.SANDBOX:
			_tick_sandbox(delta)
		GameplayMode.BOSSFIGHT:
			_tick_bossfight()

func _tick_arcade(delta: float) -> void:
	if ending:
		return
	arcade_time_left = maxf(0.0, arcade_time_left - delta)
	arcade_close_escape_cooldown = maxf(0.0, arcade_close_escape_cooldown - delta)
	var speed = Vector2(session.player.velocity.x, session.player.velocity.z).length()
	var movement_bonus = maxf(0.0, speed - config.arcade_speed_bonus_threshold) * 0.65
	if session.player.sliding:
		movement_bonus += 3.0
	if not session.player.is_on_floor() and speed > config.arcade_speed_bonus_threshold:
		movement_bonus += 1.5
	arcade_score += delta * (config.arcade_survival_score_per_second + movement_bonus) * arcade_multiplier
	if arcade_close_escape_cooldown <= 0.0:
		for bot in session.bots:
			if bot.state == NextbotEnemy.State.CHASE and bot.global_position.distance_to(session.player.global_position) <= config.arcade_close_escape_distance:
				arcade_score += 125.0 * arcade_multiplier
				arcade_multiplier = minf(5.0, arcade_multiplier + 0.15)
				arcade_close_escape_cooldown = 2.5
				break
	if arcade_time_left <= 0.0:
		ending = true
		session.finish_arcade_round.call_deferred()

func _tick_mayhem(delta: float) -> void:
	if ending or mayhem_waiting_for_upgrade:
		return
	if not mayhem_wave_pending:
		return
	mayhem_next_wave_delay = maxf(0.0, mayhem_next_wave_delay - delta)
	# Keep retrying after the timer expires. Previously, reaching zero before the
	# asynchronous NavigationMesh was ready permanently suppressed the wave.
	if mayhem_next_wave_delay <= 0.0 and session.world.navigation.synchronized:
		mayhem_wave_pending = false
		_start_mayhem_wave()

func _start_mayhem_wave() -> void:
	mayhem_wave_pending = false
	var next_wave := mayhem_wave + 1
	var boss_wave := next_wave % config.mayhem_boss_interval == 0
	var desired := 1 if boss_wave else mini(config.mayhem_maximum_wave_size, config.mayhem_base_wave_size + (next_wave - 1) * config.mayhem_wave_growth)
	var spawned := 0
	if boss_wave:
		active_boss = session._spawn_bot(Vector3.INF, {
			"max_health": config.boss_health,
			"respawn_delay": 9999.0,
			"speed_multiplier": 1.08 + next_wave * 0.01,
			"face_scale": 1.8,
			"boss": true,
		})
		if active_boss != null:
			spawned = 1
		session.ui.toast("BOSS WAVE %02d\n10,000 HP / WATCH ITS PHASES" % next_wave, 5.0)
	else:
		var health_scale = 1.0 + float(next_wave - 1) * config.mayhem_health_growth
		var speed_scale = 1.0 + minf(0.55, float(next_wave - 1) * config.mayhem_speed_growth)
		for index in range(desired):
			if session._spawn_bot(Vector3.INF, {"max_health": 100.0 * health_scale, "respawn_delay": 9999.0, "speed_multiplier": speed_scale}) != null:
				spawned += 1
		session.ui.toast("WAVE %02d\n%d NEXTBOTS" % [next_wave, spawned], 3.0)
	if spawned == 0:
		# Navigation/prop blocked every candidate; retry the wave next tick
		# instead of committing an empty wave that would instantly "clear".
		push_warning("MAYHEM: wave %d could not spawn any enemies; retrying" % next_wave)
		mayhem_wave_pending = true
		return
	mayhem_wave = next_wave
	mayhem_wave_kills = 0
	# Count only successful spawns so the wave can never stall waiting for a
	# kill that a failed spawn would have prevented.
	mayhem_wave_target = spawned

func enemy_defeated(bot: NextbotEnemy) -> void:
	statistics.add("total_nextbot_kills")
	if bot.is_boss:
		statistics.add("bosses_defeated")
		active_boss = null
	match selected:
		GameplayMode.ARCADE:
			arcade_score += 250.0 * arcade_multiplier
			arcade_multiplier = minf(5.0, arcade_multiplier + 0.25)
		GameplayMode.ENDLESS:
			if bot.is_boss:
				session.post_boss.begin_after_boss.call_deferred()
		GameplayMode.PNG_MAYHEM:
			mayhem_wave_kills += 1
			mayhem_total_score += roundi(100.0 * mayhem_multiplier * (10.0 if bot.is_boss else 1.0))
			mayhem_multiplier = minf(8.0, mayhem_multiplier + 0.1)
			if mayhem_wave_kills >= mayhem_wave_target:
				statistics.record_maximum("best_completed_wave", mayhem_wave)
				if bot.is_boss:
					mayhem_waiting_for_upgrade = true
					session.post_boss.begin_after_boss.call_deferred()
				else:
					_show_upgrades.call_deferred()
		GameplayMode.BOSSFIGHT:
			if bot.is_boss and is_bossfight_boss_level():
				bossfight_boss_pending = false
				active_boss = null
				session.ui.toast("BOSS DEFEATED\nCHOOSE YOUR REWARD", 4.0)
				session.post_boss.begin_after_boss.call_deferred()

func _show_upgrades() -> void:
	if ending or selected != GameplayMode.PNG_MAYHEM:
		return
	mayhem_waiting_for_upgrade = true
	session.player.active = false
	session.projectiles.suspend_input()
	offered_upgrades = modifiers.choices(rng)
	session.ui.show_upgrades(offered_upgrades, GameplayModifierSet.DEFINITIONS)

func choose_upgrade(index: int) -> void:
	if not mayhem_waiting_for_upgrade or index < 0 or index >= offered_upgrades.size():
		return
	var upgrade = offered_upgrades[index]
	if not modifiers.apply(upgrade):
		return
	_apply_player_tuning()
	mayhem_waiting_for_upgrade = false
	session.ui.show_screen("game")
	session.player.active = true
	session.projectiles.require_release = true
	mayhem_next_wave_delay = 1.0
	mayhem_wave_pending = true
	session.ui.toast("UPGRADE INSTALLED\n%s" % GameplayModifierSet.DEFINITIONS[upgrade].title, 2.5)

func _apply_player_tuning() -> void:
	session.player.walk_speed = base_walk_speed * modifiers.movement_multiplier
	session.player.sprint_speed = base_sprint_speed * modifiers.movement_multiplier
	session.player.air_acceleration = base_air_acceleration * modifiers.air_acceleration_multiplier
	session.player.slide_friction = base_slide_friction * modifiers.slide_friction_multiplier
	session.player.jump_velocity = base_jump_velocity * modifiers.jump_multiplier

func _restore_player_tuning() -> void:
	if is_instance_valid(session) and is_instance_valid(session.player):
		session.player.walk_speed = base_walk_speed
		session.player.sprint_speed = base_sprint_speed
		session.player.air_acceleration = base_air_acceleration
		session.player.slide_friction = base_slide_friction
		session.player.jump_velocity = base_jump_velocity

func should_respawn_enemy(bot: NextbotEnemy) -> bool:
	if bot.is_boss or bot.event_spawned:
		return false
	if selected == GameplayMode.BOSSFIGHT:
		return not is_bossfight_boss_level()
	return selected in [GameplayMode.ARCADE, GameplayMode.ENDLESS]

func uses_standard_spawner() -> bool:
	return selected in [GameplayMode.ARCADE, GameplayMode.ENDLESS] or (selected == GameplayMode.BOSSFIGHT and not is_bossfight_boss_level())

func maximum_active_bots(default_value: int) -> int:
	if selected == GameplayMode.ARCADE:
		var pressure = int((config.arcade_round_seconds - arcade_time_left) / 60.0)
		return mini(config.arcade_maximum_nextbots, config.arcade_starting_nextbots + pressure)
	if selected == GameplayMode.BOSSFIGHT:
		return 1 if is_bossfight_boss_level() else mini(config.bossfight_maximum_nextbots, config.bossfight_starting_nextbots + bossfight_difficulty_tier())
	return default_value

func desired_active_bots(default_value: int) -> int:
	if selected == GameplayMode.ARCADE:
		var elapsed_minutes = int((config.arcade_round_seconds - arcade_time_left) / 60.0)
		return mini(config.arcade_maximum_nextbots, config.arcade_starting_nextbots + elapsed_minutes)
	if selected == GameplayMode.BOSSFIGHT:
		return 1 if is_bossfight_boss_level() else mini(config.bossfight_maximum_nextbots, config.bossfight_starting_nextbots + bossfight_difficulty_tier())
	return default_value

func can_advance_level() -> bool:
	return selected == GameplayMode.ENDLESS or (selected == GameplayMode.BOSSFIGHT and not is_bossfight_boss_level())

func attacks_enabled() -> bool:
	return bool(sandbox.attacks) if selected == GameplayMode.SANDBOX else true

func player_invincible() -> bool:
	return bool(sandbox.invincible) if selected == GameplayMode.SANDBOX else false

func consume_shield() -> bool:
	return modifiers.consume_shield()

func projectile_profile() -> Dictionary:
	return modifiers.projectile_profile()

func apply_run_reward(reward: String) -> bool:
	if not modifiers.apply(reward):
		return false
	_apply_player_tuning()
	if is_instance_valid(session.projectiles):
		session.projectiles.require_release = true
		session.projectiles.state_changed.emit()
	return true

func reapply_run_rewards() -> void:
	# The Player node persists between maps, but this makes level loading and
	# future controller resets unable to silently discard movement rewards.
	_apply_player_tuning()
	if is_instance_valid(session.projectiles):
		session.projectiles.state_changed.emit()

func restore_run_rewards(data: Dictionary) -> void:
	modifiers.restore(data)
	_apply_player_tuning()

func post_reward_without_lever() -> void:
	if selected == GameplayMode.PNG_MAYHEM:
		mayhem_waiting_for_upgrade = false
		mayhem_next_wave_delay = 1.0
		mayhem_wave_pending = true

func arcade_finished() -> Dictionary:
	var result = {"round": arcade_round, "score": roundi(arcade_score), "survival": config.arcade_round_seconds}
	session_leaderboard.append(result)
	session_leaderboard.sort_custom(func(a, b): return a.score > b.score)
	if session_leaderboard.size() > 8:
		session_leaderboard.resize(8)
	statistics.record_maximum("highest_arcade_score", arcade_score)
	statistics.record_maximum("best_survival_time", config.arcade_round_seconds)
	return result

func mode_status() -> String:
	match selected:
		GameplayMode.ARCADE:
			return "ROUND %02d  /  SCORE %06d  /  x%.1f" % [arcade_round, roundi(arcade_score), arcade_multiplier]
		GameplayMode.ENDLESS:
			return "LEVEL %02d  /  BEST %02d" % [session.current_level, Settings.highest_level]
		GameplayMode.PNG_MAYHEM:
			return "WAVE %02d  /  KILLS %d/%d  /  SCORE %06d" % [mayhem_wave, mayhem_wave_kills, mayhem_wave_target, mayhem_total_score]
		GameplayMode.SANDBOX:
			return "SANDBOX  /  %d ACTIVE  /  F2 TOOLS" % session.bots.size()
		GameplayMode.BOSSFIGHT:
			return "BOSSFIGHT  /  LEVEL %02d  /  CYCLE %02d" % [session.current_level, bossfight_cycle_number()]
	return ""

func objective_text() -> String:
	match selected:
		GameplayMode.ARCADE: return "SURVIVE UNTIL EXTRACTION  /  KEEP MOVING"
		GameplayMode.ENDLESS: return "BREAKERS  %d / 3  ->  %s" % [session.breakers, session.world.objective_destination if session.breakers == 3 else "RESTORE POWER"]
		GameplayMode.PNG_MAYHEM: return "CLEAR THE WAVE  /  THROW PNGs"
		GameplayMode.SANDBOX: return "AUTO %s  /  %d ACTIVE  /  F2 LIVE CONTROLS" % ["ON" if bool(sandbox.auto_spawn) else "OFF", session.bots.size()]
		GameplayMode.BOSSFIGHT:
			if is_instance_valid(session.post_boss):
				if session.post_boss.state == PostBossRewardController.RewardState.REWARD_SELECTION:
					return "CHOOSE A REWARD  /  LEFT HAND OR RIGHT HAND"
				if session.post_boss.state == PostBossRewardController.RewardState.PROGRESSION_UNLOCKED:
					return "PULL THE LEVER BEHIND THE REWARD KEEPER"
			if is_bossfight_boss_level():
				return "DEFEAT THE BOSS  /  %d HP" % bossfight_boss_health()
			return "SWITCHES %d / 3  ->  %s" % [session.breakers, session.world.objective_destination if session.breakers == 3 else "SEARCH THE DISTRICT"]
	return ""

func timer_seconds() -> float:
	return arcade_time_left if selected == GameplayMode.ARCADE else session.survival_time

func is_bossfight_boss_level() -> bool:
	return selected == GameplayMode.BOSSFIGHT and session.current_level % 4 == 0

func bossfight_cycle_number() -> int:
	return floori(float(maxi(1, session.current_level) - 1) / 4.0) + 1

func bossfight_difficulty_tier() -> int:
	return floori(float(maxi(1, session.current_level) - 1) / 4.0)

func bossfight_boss_health() -> float:
	var boss_number := maxi(1, floori(float(session.current_level) / 4.0))
	return config.bossfight_base_boss_health + float(boss_number - 1) * config.bossfight_boss_health_growth

func nextbot_speed_multiplier(default_value: float) -> float:
	if selected != GameplayMode.BOSSFIGHT:
		return default_value
	return minf(config.bossfight_enemy_speed_cap, 1.0 + float(bossfight_difficulty_tier()) * config.bossfight_enemy_speed_growth)

func enemy_pressure(default_value: float) -> float:
	if selected != GameplayMode.BOSSFIGHT:
		return default_value
	return float(bossfight_difficulty_tier()) * 2.0

func default_enemy_health(default_value: float = 100.0) -> float:
	if selected != GameplayMode.BOSSFIGHT or is_bossfight_boss_level():
		return default_value
	return default_value + float(bossfight_difficulty_tier()) * config.bossfight_enemy_health_growth

func bossfight_level_ready() -> void:
	if selected != GameplayMode.BOSSFIGHT:
		return
	active_boss = null
	bossfight_boss_pending = is_bossfight_boss_level()
	session.spawn_timer = INF if bossfight_boss_pending else 0.9
	if bossfight_boss_pending:
		session.ui.toast("BOSS CYCLE %02d\n%d HP / ATTACK FACE MEANS DANGER" % [bossfight_cycle_number(), roundi(bossfight_boss_health())], 5.0)

func _tick_bossfight() -> void:
	if not bossfight_boss_pending or not is_bossfight_boss_level() or not session.world.navigation.synchronized:
		return
	var boss_number := maxi(1, floori(float(session.current_level) / 4.0))
	active_boss = session._spawn_bot(Vector3.INF, {
		"max_health": bossfight_boss_health(),
		"respawn_delay": 9999.0,
		"speed_multiplier": minf(1.38, 1.04 + float(boss_number - 1) * 0.045),
		"face_scale": 2.05,
		"boss": true,
		"custom_face": BOSSFIGHT_IDLE_FACE,
		"attack_face": BOSSFIGHT_ATTACK_FACE,
	})
	if active_boss == null:
		return
	bossfight_boss_pending = false
	session.ui.toast("BOSS %02d ENTERS THE SUN RING\n%d HP" % [boss_number, roundi(bossfight_boss_health())], 4.0)

func sandbox_action(action: String, value = null) -> void:
	if selected != GameplayMode.SANDBOX:
		return
	if sandbox.has(action) and value != null:
		sandbox[action] = value
		if action == "lighting":
			apply_sandbox_lighting()
		elif action == "ai":
			for bot in session.bots:
				bot.enabled = bool(value)
		elif action == "auto_spawn":
			sandbox_spawn_timer = 0.15
			session.ui.toast("SANDBOX AUTO SPAWN  /  %s" % ("ON" if bool(value) else "OFF"), 2.0)
		return
	match action:
		"spawn":
			_spawn_sandbox_batch(int(sandbox.count))
		"remove":
			session.events.end_event()
			session._clear_bots()
		"event":
			session.events.request_random_event(true)
		"reward":
			session.post_boss.begin_sandbox_test()
		"regenerate":
			session.regeneration_serial += 1
			session._transition_to_level(4, session._seed_for_level(4, session.regeneration_serial))
		"reset":
			session.events.end_event()
			session._clear_bots()
			sandbox = {"speed": 11.4, "health": 100.0, "damage": 100.0, "aggression": 1.0, "detection": 34.0, "size": 1.0, "count": 1, "attacks": true, "ai": true, "invincible": true, "lighting": 1.0, "auto_spawn": false, "auto_spawn_interval": config.sandbox_auto_spawn_interval, "auto_spawn_limit": config.sandbox_auto_spawn_limit}
			sandbox_spawn_timer = 0.0
			apply_sandbox_lighting()

func _tick_sandbox(delta: float) -> void:
	if not bool(sandbox.auto_spawn) or not session.world.navigation.synchronized:
		return
	sandbox_spawn_timer = maxf(0.0, sandbox_spawn_timer - delta)
	if sandbox_spawn_timer > 0.0:
		return
	var available = maxi(0, int(sandbox.auto_spawn_limit) - session.bots.size())
	if available > 0:
		_spawn_sandbox_batch(mini(int(sandbox.count), available))
	sandbox_spawn_timer = maxf(0.5, float(sandbox.auto_spawn_interval))

func _spawn_sandbox_batch(amount: int) -> void:
	for index in range(maxi(0, amount)):
		var bot = session._spawn_bot(Vector3.INF, {
			"max_health": float(sandbox.health),
			"speed_override": float(sandbox.speed),
			"aggression": float(sandbox.aggression),
			"detection_range": float(sandbox.detection),
			"attack_damage": float(sandbox.damage),
			"face_scale": float(sandbox.size),
			"custom_face": session.png_images.current_texture(),
			"respawn_delay": 9999.0,
		})
		if bot != null:
			bot.enabled = bool(sandbox.ai)

func _capture_sandbox_lighting() -> void:
	sandbox_light_energy.clear()
	for light in session.world.all_lights:
		if is_instance_valid(light):
			sandbox_light_energy[light.get_instance_id()] = light.light_energy
	if is_instance_valid(session.world.env):
		sandbox_ambient_energy = session.world.env.environment.ambient_light_energy

func apply_sandbox_lighting() -> void:
	if selected != GameplayMode.SANDBOX:
		return
	var scale = clampf(float(sandbox.lighting), 0.05, 2.0)
	for light in session.world.all_lights:
		if is_instance_valid(light):
			var base = float(sandbox_light_energy.get(light.get_instance_id(), light.light_energy))
			light.light_energy = base * scale
	if is_instance_valid(session.world.env) and sandbox_ambient_energy >= 0.0:
		session.world.env.environment.ambient_light_energy = maxf(0.01, sandbox_ambient_energy * scale)

