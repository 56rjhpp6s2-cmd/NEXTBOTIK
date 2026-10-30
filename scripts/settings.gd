extends Node
## Persistent preferences, input setup, and per-difficulty records.
signal changed

const SAVE_PATH = "user://below_zero.cfg"
const RESOLUTIONS = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var sensitivity: float = 0.11
var master: float = 0.8
var music: float = 0.55
var sfx: float = 0.8
var fullscreen: bool = false
var resolution: int = 0
var quality: int = 1
var difficulty: int = 1
var best: Array = [0.0, 0.0, 0.0]
var reduced_flashes: bool = false
var level_index: int = 0
var construct_best: Array = [0.0, 0.0, 0.0]
var storage_path: String = SAVE_PATH
const DEFAULT_PNG: String = "Без имени.png"
var selected_png: String = DEFAULT_PNG
var projectile_size: float = 1.3
var unlimited_png_ammo: bool = true
var network_name: String = "PLAYER"
var network_address: String = "127.0.0.1"
var network_port: int = 24577
var toggle_crouch: bool = false
var toggle_sprint: bool = false
var auto_bunnyhop: bool = false
var camera_shake_intensity: float = 0.7
var head_bob_intensity: float = 0.7
var dynamic_fov: bool = true
var camera_tilt: bool = true
var show_speedometer: bool = false
var brightness: float = 1.0
var highest_level: int = 1
var selected_game_mode: int = 1
const PERSISTED = ["sensitivity", "master", "music", "sfx", "fullscreen", "resolution", "quality", "difficulty", "best", "reduced_flashes", "level_index", "construct_best", "selected_png", "projectile_size", "unlimited_png_ammo", "network_name", "network_address", "network_port", "toggle_crouch", "toggle_sprint", "auto_bunnyhop", "camera_shake_intensity", "head_bob_intensity", "dynamic_fov", "camera_tilt", "show_speedometer", "brightness", "highest_level", "selected_game_mode"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if automated_run():
		storage_path = ProjectSettings.globalize_path("res://").path_join(".godot/test_%s_settings.cfg" % automated_tag())
	var config = ConfigFile.new()
	if config.load(storage_path) == OK:
		for key in PERSISTED:
			set(key, config.get_value("settings", key, get(key)))
	sensitivity = clampf(sensitivity, 0.02, 0.35)
	resolution = clampi(resolution, 0, RESOLUTIONS.size() - 1)
	quality = clampi(quality, 0, 2)
	difficulty = clampi(difficulty, 0, 2)
	level_index = clampi(level_index, 0, 1)
	projectile_size = clampf(projectile_size, 0.2, 2.5)
	camera_shake_intensity = clampf(camera_shake_intensity, 0.0, 1.0)
	head_bob_intensity = clampf(head_bob_intensity, 0.0, 1.0)
	brightness = clampf(brightness, 0.65, 1.35)
	highest_level = maxi(1, highest_level)
	selected_game_mode = clampi(selected_game_mode, 0, 4)
	if best.size() != 3:
		best = [0.0, 0.0, 0.0]
	if construct_best.size() != 3:
		construct_best = [0.0, 0.0, 0.0]
	_bind("forward", KEY_W)
	_bind("back", KEY_S)
	_bind("left", KEY_A)
	_bind("right", KEY_D)
	_bind("sprint", KEY_SHIFT)
	_bind("crouch", KEY_CTRL)
	_bind("jump", KEY_SPACE)
	_bind("speedometer", KEY_F4)
	_bind("reward_left", KEY_Q)
	_bind("interact", KEY_E)
	_bind("flashlight", KEY_F)
	_bind("pause", KEY_ESCAPE)
	_bind("debug_ai", KEY_F3)
	_bind("debug_regenerate", KEY_F6)
	_bind("debug_spawn", KEY_F7)
	_bind("reload_png", KEY_R)
	_bind("png_library", KEY_TAB)
	_bind("sandbox_tools", KEY_F2)
	_bind_mouse("throw_png", MOUSE_BUTTON_LEFT)
	_bind_mouse("aim_png", MOUSE_BUTTON_RIGHT)
	_bind_mouse("next_png", MOUSE_BUTTON_WHEEL_DOWN)
	_bind_mouse("previous_png", MOUSE_BUTTON_WHEEL_UP)
	apply_display()

func automated_run() -> bool:
	return not automated_tag().is_empty()

func automated_tag() -> String:
	for flag in ["--smoke-test", "--map-test", "--combat-test", "--movement-test", "--procedural-test", "--modes-test", "--bossfight-test", "--mobile-test", "--throwables-test", "--capture-construct", "--capture-combat", "--capture-bossfight", "--net-test-host", "--net-test-client", "--capture-network", "--portable-test"]:
		if flag in OS.get_cmdline_user_args():
			return flag.trim_prefix("--")
	return ""

func _bind_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var event = InputEventMouseButton.new()
		event.button_index = button
		InputMap.action_add_event(action, event)

func _bind(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var event = InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)

func apply_display() -> void:
	if OS.has_feature("mobile"):
		changed.emit()
		return
	if DisplayServer.get_name() != "headless" and "--capture-construct" not in OS.get_cmdline_user_args() and "--capture-combat" not in OS.get_cmdline_user_args() and "--capture-network" not in OS.get_cmdline_user_args() and "--capture-network-client" not in OS.get_cmdline_user_args():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		if not fullscreen:
			DisplayServer.window_set_size(RESOLUTIONS[resolution])
			var screen = DisplayServer.screen_get_usable_rect()
			DisplayServer.window_set_position(screen.position + (screen.size - RESOLUTIONS[resolution]) / 2)
	changed.emit()

func save() -> void:
	var config = ConfigFile.new()
	for key in PERSISTED:
		config.set_value("settings", key, get(key))
	config.save(storage_path)
	changed.emit()

func record(seconds: float) -> bool:
	return record_for_map(level_index, difficulty, seconds)

func difficulty_name() -> String:
	return ["EXPLORER", "RELENTLESS", "NIGHTMARE"][difficulty]

func best_for_map(map_index: int, difficulty_index: int) -> float:
	return float(best[difficulty_index] if map_index == 0 else construct_best[difficulty_index])

func record_for_map(map_index: int, difficulty_index: int, seconds: float) -> bool:
	if seconds <= best_for_map(map_index, difficulty_index):
		return false
	if map_index == 0:
		best[difficulty_index] = seconds
	else:
		construct_best[difficulty_index] = seconds
	save()
	return true

func record_level(level: int) -> bool:
	if level <= highest_level:
		return false
	highest_level = level
	save()
	return true

static func time_text(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
