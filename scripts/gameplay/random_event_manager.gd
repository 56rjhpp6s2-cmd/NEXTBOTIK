class_name RandomEventManager
extends Node
## Single-active-event scheduler. Every mutation is snapshotted and restored by
## end_event(), including manual Sandbox events and level transitions.

const EVENT_NAMES := ["BLACKOUT", "BLOODMOON", "OUTBREAK", "ANGRY NEXTBOT", "NEXTBOT SWARM", "TOTAL DARKNESS", "BOSS INVASION"]
const WARNINGS := {
	"BLACKOUT": "POWER GRID FAILURE IMMINENT",
	"BLOODMOON": "RED WEATHER FRONT DETECTED",
	"OUTBREAK": "CONTAINMENT BREACH",
	"ANGRY NEXTBOT": "DO NOT LOOK AWAY",
	"NEXTBOT SWARM": "MULTIPLE CONTACTS APPROACHING",
	"TOTAL DARKNESS": "ALL LIGHT WILL BE LOST",
	"BOSS INVASION": "MASSIVE ANOMALY DETECTED",
}

var session
var config: GameplayConfig
var active_event: String = ""
var pending_event: String = ""
var warning_remaining: float = 0.0
var remaining: float = 0.0
var cooldown: float = 45.0
var objective_remaining: int = 0
var event_bots: Array[NextbotEnemy] = []
var light_snapshot: Dictionary = {}
var ambient_snapshot: float = -1.0
var background_snapshot: Color
var fog_color_snapshot: Color
var fog_density_snapshot: float = -1.0
var rng := RandomNumberGenerator.new()

func setup(owner_session, tuning: GameplayConfig) -> void:
	session = owner_session
	config = tuning
	rng.randomize()
	cooldown = config.first_event_delay

func tick(delta: float) -> void:
	if not session.is_running() or session.transition_in_progress:
		return
	if not pending_event.is_empty():
		warning_remaining -= delta
		if warning_remaining <= 0.0:
			_start_event(pending_event)
			pending_event = ""
		return
	if not active_event.is_empty():
		remaining -= delta
		if objective_remaining <= 0 and active_event in ["OUTBREAK", "ANGRY NEXTBOT", "NEXTBOT SWARM", "BOSS INVASION"]:
			end_event()
		elif remaining <= 0.0:
			end_event()
		return
	if session.game_modes.selected not in [GameModeManager.GameplayMode.ARCADE, GameModeManager.GameplayMode.ENDLESS]:
		return
	cooldown -= delta
	if cooldown <= 0.0:
		request_random_event()

func request_random_event(manual: bool = false) -> bool:
	if not active_event.is_empty() or not pending_event.is_empty() or session.transition_in_progress:
		return false
	var candidates = EVENT_NAMES.duplicate()
	# Boss invasions remain uncommon during automatic selection.
	var roll = rng.randi_range(0, candidates.size() + (3 if not manual else 0) - 1)
	var selected = candidates[mini(roll, candidates.size() - 1)]
	pending_event = selected
	warning_remaining = config.event_warning_seconds
	session.ui.toast("EVENT WARNING\n%s" % WARNINGS[selected], config.event_warning_seconds)
	return true

func request_event(event_name: String) -> bool:
	var normalized = event_name.to_upper()
	if normalized not in EVENT_NAMES or not active_event.is_empty() or not pending_event.is_empty():
		return false
	pending_event = normalized
	warning_remaining = config.event_warning_seconds
	session.ui.toast("EVENT WARNING\n%s" % WARNINGS[normalized], config.event_warning_seconds)
	return true

func _start_event(event_name: String) -> void:
	active_event = event_name
	remaining = config.event_duration
	objective_remaining = 1
	event_bots.clear()
	_snapshot_environment()
	match active_event:
		"BLACKOUT":
			objective_remaining = 2
			_apply_blackout(false)
			session.ui.toast("BLACKOUT\nRESTORE TWO BREAKERS OR SURVIVE", 5.0)
		"BLOODMOON":
			objective_remaining = 999
			_apply_bloodmoon()
			session.ui.toast("BLOODMOON\nNEXTBOTS +20% SPEED", 5.0)
		"OUTBREAK":
			_spawn_group(mini(config.event_enemy_budget, 7), 65.0, 1.12, "outbreak")
			objective_remaining = event_bots.size()
			session.ui.toast("OUTBREAK\nELIMINATE %d INFECTED" % objective_remaining, 5.0)
		"ANGRY NEXTBOT":
			var angry = _spawn_event_bot({"max_health": 450.0, "speed_multiplier": 1.75, "face_scale": 1.25, "angry": true, "event_tag": "angry"})
			objective_remaining = 1 if angry != null else 0
			session.ui.toast("ANGRY NEXTBOT\nWATCH IT TO SLOW IT", 5.0)
		"NEXTBOT SWARM":
			_spawn_group(config.event_enemy_budget, 35.0, 0.92, "swarm")
			objective_remaining = event_bots.size()
			session.ui.toast("NEXTBOT SWARM\nWEAK INDIVIDUALLY / MOVE", 5.0)
		"TOTAL DARKNESS":
			objective_remaining = 999
			remaining = minf(28.0, config.event_duration)
			_apply_blackout(true)
			session.ui.toast("TOTAL DARKNESS\nFLASHLIGHTS ONLY", 5.0)
		"BOSS INVASION":
			var boss = _spawn_event_bot({"max_health": config.boss_health, "speed_multiplier": 1.1, "face_scale": 1.85, "boss": true, "event_tag": "boss"})
			objective_remaining = 1 if boss != null else 0
			session.game_modes.active_boss = boss
			session.ui.toast("BOSS INVASION\nDEFEAT IT OR SURVIVE", 5.0)
	# Breakers are progression levers in Endless but also power switches for
	# Blackout; re-evaluate their visibility/interactability for this mode.
	session.refresh_interactable_policy()

func _spawn_group(count: int, health: float, speed_scale: float, tag: String) -> void:
	for index in range(count):
		_spawn_event_bot({"max_health": health, "speed_multiplier": speed_scale, "event_tag": tag, "respawn_delay": 9999.0})

func _spawn_event_bot(stats: Dictionary) -> NextbotEnemy:
	if session.bots.size() >= config.event_enemy_budget + session.game_modes.maximum_active_bots(5):
		return null
	stats["event_spawned"] = true
	stats["respawn_delay"] = 9999.0
	var bot: NextbotEnemy = session._spawn_bot(Vector3.INF, stats)
	if bot == null:
		return null
	event_bots.append(bot)
	return bot

func enemy_spawned(bot: NextbotEnemy) -> void:
	if active_event == "BLOODMOON":
		bot.event_speed_multiplier = 1.2

func enemy_defeated(bot: NextbotEnemy) -> void:
	if bot in event_bots:
		event_bots.erase(bot)
		objective_remaining = maxi(0, objective_remaining - 1)
	if bot == session.game_modes.active_boss:
		session.game_modes.active_boss = null

func breaker_activated() -> void:
	if active_event == "BLACKOUT":
		objective_remaining = maxi(0, objective_remaining - 1)
		if objective_remaining <= 0:
			session.ui.toast("POWER RESTORED", 3.0)
			end_event()

func _snapshot_environment() -> void:
	light_snapshot.clear()
	for light in session.world.all_lights:
		if is_instance_valid(light):
			light_snapshot[light.get_instance_id()] = {"energy": light.light_energy, "color": light.light_color}
	if is_instance_valid(session.world.env):
		var environment = session.world.env.environment
		ambient_snapshot = environment.ambient_light_energy
		background_snapshot = environment.background_color
		fog_color_snapshot = environment.fog_light_color
		fog_density_snapshot = environment.fog_density

func _apply_blackout(total: bool) -> void:
	for index in range(session.world.all_lights.size()):
		var light = session.world.all_lights[index]
		if not is_instance_valid(light):
			continue
		if not total and index % 9 == 0:
			light.light_energy = maxf(0.25, light.light_energy * 0.35)
			light.light_color = Color("ef5548")
		else:
			light.light_energy = 0.0 if total else light.light_energy * 0.025
	if is_instance_valid(session.world.env):
		session.world.env.environment.ambient_light_energy = 0.008 if total else 0.018
		session.world.env.environment.fog_density = maxf(session.world.env.environment.fog_density, 0.035 if total else 0.025)

func _apply_bloodmoon() -> void:
	if is_instance_valid(session.world.env):
		var environment = session.world.env.environment
		environment.background_color = Color("210305")
		environment.fog_light_color = Color("6f080b")
		environment.fog_density = maxf(environment.fog_density, 0.026)
	for light in session.world.all_lights:
		if is_instance_valid(light):
			light.light_color = light.light_color.lerp(Color("ff1e24"), 0.72)
	for bot in session.bots:
		bot.event_speed_multiplier = 1.2
	Sound.target_intensity = maxf(Sound.target_intensity, 0.75)

func end_event() -> void:
	if active_event.is_empty() and pending_event.is_empty():
		return
	var active_lights: Array = session.world.all_lights if is_instance_valid(session.world) else []
	for light in active_lights:
		if is_instance_valid(light) and light_snapshot.has(light.get_instance_id()):
			var saved: Dictionary = light_snapshot[light.get_instance_id()]
			light.light_energy = saved.energy
			light.light_color = saved.color
	if is_instance_valid(session.world) and is_instance_valid(session.world.env) and ambient_snapshot >= 0.0:
		var environment = session.world.env.environment
		environment.ambient_light_energy = ambient_snapshot
		environment.background_color = background_snapshot
		environment.fog_light_color = fog_color_snapshot
		environment.fog_density = fog_density_snapshot
	for bot in session.bots:
		bot.event_speed_multiplier = 1.0
	for bot in event_bots.duplicate():
		if is_instance_valid(bot):
			bot.enabled = false
			bot.queue_free()
	event_bots.clear()
	if is_instance_valid(session.game_modes.active_boss) and session.game_modes.active_boss.event_spawned:
		session.game_modes.active_boss = null
	active_event = ""
	pending_event = ""
	remaining = 0.0
	objective_remaining = 0
	light_snapshot.clear()
	ambient_snapshot = -1.0
	cooldown = rng.randf_range(config.event_cooldown_min, config.event_cooldown_max)
	# Blackout just ended: hide its breakers again in non-Endless modes.
	session.refresh_interactable_policy()

func warning_text() -> String:
	if not pending_event.is_empty():
		return "WARNING / %s / %d" % [pending_event, ceili(warning_remaining)]
	if active_event.is_empty():
		return ""
	var objective = ""
	if active_event in ["BLACKOUT", "OUTBREAK", "ANGRY NEXTBOT", "NEXTBOT SWARM", "BOSS INVASION"]:
		objective = " / OBJECTIVE %d" % objective_remaining
	return "%s / %02d SEC%s" % [active_event, ceili(remaining), objective]

