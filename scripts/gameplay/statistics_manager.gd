class_name StatisticsManager
extends Node
## Versioned, local-only statistics. Invalid or partial files fall back safely.

const VERSION: int = 1
const DEFAULTS := {
	"total_playtime": 0.0,
	"total_deaths": 0,
	"total_nextbot_kills": 0,
	"best_survival_time": 0.0,
	"highest_endless_level": 1,
	"highest_arcade_score": 0,
	"total_png_projectiles_thrown": 0,
	"successful_projectile_hits": 0,
	"best_completed_wave": 0,
	"bosses_defeated": 0,
}

var data: Dictionary = DEFAULTS.duplicate(true)
var storage_path: String = "user://below_zero_statistics.json"
var dirty: bool = false
var flush_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Settings.automated_run():
		storage_path = ProjectSettings.globalize_path("res://").path_join(".godot/test_%s_statistics.json" % Settings.automated_tag())
	load_data()

func load_data() -> void:
	data = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(storage_path):
		return
	var file = FileAccess.open(storage_path, FileAccess.READ)
	if file == null:
		push_warning("Statistics file could not be opened; defaults are active.")
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("Statistics file is invalid; defaults are active.")
		return
	var parsed = json.data
	if not (parsed is Dictionary) or int(parsed.get("version", -1)) != VERSION or not (parsed.get("statistics", null) is Dictionary):
		push_warning("Statistics file is invalid; defaults are active.")
		return
	var stored: Dictionary = parsed.statistics
	for key in DEFAULTS:
		var value = stored.get(key, DEFAULTS[key])
		if value is int or value is float:
			data[key] = maxf(0.0, float(value)) if DEFAULTS[key] is float else maxi(0, int(value))

func save_data() -> bool:
	var file = FileAccess.open(storage_path, FileAccess.WRITE)
	if file == null:
		push_warning("Statistics could not be saved: %s" % storage_path)
		return false
	file.store_string(JSON.stringify({"version": VERSION, "statistics": data}, "\t"))
	dirty = false
	flush_time = 0.0
	return true

func add(key: String, amount: float = 1.0) -> void:
	if not data.has(key) or not is_finite(amount):
		return
	if DEFAULTS[key] is int:
		data[key] = maxi(0, int(data[key]) + roundi(amount))
	else:
		data[key] = maxf(0.0, float(data[key]) + amount)
	dirty = true

func record_maximum(key: String, value: float) -> bool:
	if not data.has(key) or not is_finite(value) or value <= float(data[key]):
		return false
	data[key] = int(value) if DEFAULTS[key] is int else value
	dirty = true
	return true

func value(key: String):
	return data.get(key, DEFAULTS.get(key, 0))

func tick_playtime(delta: float) -> void:
	add("total_playtime", maxf(0.0, delta))
	flush_time += delta
	if flush_time >= 30.0:
		save_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if dirty:
			save_data()

