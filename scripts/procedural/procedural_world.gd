class_name ProceduralLevelWorld
extends LevelWorld
## Runtime world assembled from reusable modular room prefabs. It deliberately
## implements LevelWorld's public contract so movement, combat and AI do not
## need procedural-map special cases.

var progression_level: int = 4
var generation_seed: int = 1
var generation_config: ProceduralGenerationConfig
var generation_result: Dictionary = {}
var generated_rooms: Array = []
var generated_room_count: int = 0
var lighting_multiplier: float = 0.8
var generation_validation: String = "NOT_STARTED"
var navigation_status: String = "NOT_BUILT"
var layout_signature: String = ""

func _ready() -> void:
	map_id = "procedural"
	display_name = "BELOW / PROCEDURAL LEVEL %d" % progression_level
	objective_destination = "DESCENT GATE"
	mission_description = "Restore three breakers.\nFind the descent gate.\nThe layout changes below Level 3."
	escape_message = "The gate shuts behind you. The next level is already listening."
	if generation_config == null:
		generation_config = preload("res://resources/procedural_generation.tres")
	lighting_multiplier = generation_config.lighting_for_level(progression_level)
	rng.seed = generation_seed
	var generator = ProceduralLayoutGenerator.new()
	generation_result = generator.generate(generation_seed, generation_config.room_count_for_level(progression_level), generation_config, progression_level)
	generation_validation = "FALLBACK_VALID" if generation_result.get("fallback", false) else str(generation_result.get("reason", "FAILED"))
	generated_rooms = generation_result.get("rooms", [])
	generated_room_count = generated_rooms.size()
	_build_tile_dictionary()
	_build_layout_signature()
	_build_environment()
	for key in tiles:
		_build_tile(key)
	_build_connections()
	_build_props_and_objectives()
	print("PROCEDURAL LEVEL %d: seed %d, %d rooms, %d tiles, %s, %d static render batches" % [progression_level, generation_seed, generated_room_count, tiles.size(), generation_validation, WorldSurface.batch_static(self)])
	navigation = LevelNavigation.new()
	navigation.name = "ProceduralNavigationMesh"
	add_child(navigation)
	navigation_status = "BUILDING"
	navigation.build(tiles, self)
	_build_spawn_and_patrol_points()
	for safe in safe_cells:
		refuge_charge[safe] = 18.0
	Settings.changed.connect(apply_quality)
	apply_quality()

func _build_tile_dictionary() -> void:
	tiles.clear()
	for cell_2d in generation_result.get("tiles", {}):
		var room_id: int = int(generation_result.tiles[cell_2d])
		var room: Dictionary = generated_rooms[room_id]
		var key = Vector3i(cell_2d.x, 0, cell_2d.y)
		tiles[key] = {
			"zone": room.name,
			"room": room_id,
			"room_type": room.type,
			"light_density": room.light_density,
			"prop_style": room.prop_style,
		}
	safe_cells.clear()
	for cell in generation_result.get("safe_cells", []):
		safe_cells.append(Vector3i(cell.x, 0, cell.y))

func _build_layout_signature() -> void:
	var cells: Array = generation_result.get("tiles", {}).keys()
	cells.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	var room_shapes: Array[String] = []
	for room in generated_rooms:
		room_shapes.append("%s:%d" % [room.type, room.rotation])
	layout_signature = str(cells) + "/" + ",".join(room_shapes)

func nav_blocked(_key: Vector3i) -> bool:
	return false

func _build_tile(key: Vector3i) -> void:
	var data: Dictionary = tiles[key]
	var p = center(key)
	var style: String = str(data.prop_style)
	var floor_kind = "carpet" if style in ["office", "classroom"] else ("paving" if style == "parking" else "floor")
	var wall_kind = "yellow" if style == "classroom" else ("brick" if style == "office" else "concrete")
	var tile_root = Node3D.new()
	tile_root.position = p
	add_child(tile_root)
	WorldSurface.box(tile_root, Vector3(CELL, 0.3, CELL), Vector3(0, -0.15, 0), floor_kind)
	WorldSurface.box(tile_root, Vector3(CELL, 0.2, CELL), Vector3(0, WALL_HEIGHT + 0.1, 0), "ceiling")
	for direction in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if neighbor(key, direction) != null:
			continue
		var size = Vector3(0.3, WALL_HEIGHT, CELL + 0.1) if direction.x != 0 else Vector3(CELL + 0.1, WALL_HEIGHT, 0.3)
		var wall_at = Vector3(direction.x * CELL / 2.0, WALL_HEIGHT / 2.0, direction.y * CELL / 2.0)
		WorldSurface.box(tile_root, size, wall_at, wall_kind)
		WorldSurface.box(tile_root, Vector3(size.x + 0.03, 0.14, size.z + 0.03), wall_at - Vector3.UP * 1.55, "metal", false)
		WorldSurface.box(tile_root, Vector3(size.x + 0.04, 0.05, size.z + 0.04), wall_at - Vector3.UP * 0.65, "red" if progression_level >= 7 else "stripe", false)
	var forced_light = key in safe_cells or data.room_type in ["spawn_room", "exit_room"]
	var candidate_light = posmod(key.x * 17 + key.z * 31 + int(generation_seed), 4) == 0
	var functioning_chance = clampf(0.10 + float(data.light_density) * lighting_multiplier, 0.08, 1.0)
	if forced_light or (candidate_light and rng.randf() < functioning_chance):
		_add_procedural_light(p, forced_light, data.room_type == "exit_room")
	if style == "parking":
		WorldSurface.box(tile_root, Vector3(0.08, 0.014, 4.2), Vector3(2.1, 0.012, 0), "white", false)
	elif style == "maintenance":
		WorldSurface.box(tile_root, Vector3(0.14, 0.14, 5.7), Vector3(-2.25, 3.45, 0), "rust", false)

func _add_procedural_light(at: Vector3, forced: bool, emergency: bool) -> void:
	var kind = "green" if forced and not emergency else ("emergency" if emergency else "glow")
	WorldSurface.box(self, Vector3(1.35, 0.1, 0.38), at + Vector3(0, 3.68, 0), kind, false)
	var light = OmniLight3D.new()
	light.position = at + Vector3(0, 3.15, 0)
	light.light_color = Color("7de0c2") if forced and not emergency else (Color("ef6b58") if emergency else Color("d2d8b8"))
	light.omni_range = 9.5 if not forced else 11.5
	light.light_energy = maxf(0.42, (1.45 if not forced else 1.75) * maxf(lighting_multiplier, 0.28) * Settings.brightness)
	light.omni_attenuation = 1.3
	add_child(light)
	all_lights.append(light)
	var flicker_chance = 0.12 + (1.0 - lighting_multiplier) * 0.44
	if not forced and rng.randf() < flicker_chance:
		flickers.append({"light": light, "phase": rng.randf() * 20.0, "energy": light.light_energy})

func _build_connections() -> void:
	for link in generation_result.get("links", []):
		var a = Vector3(link.a_cell.x * CELL, 0.0, link.a_cell.y * CELL)
		var b = Vector3(link.b_cell.x * CELL, 0.0, link.b_cell.y * CELL)
		var midpoint = (a + b) * 0.5
		var along_x = not is_equal_approx(a.x, b.x)
		var post_size = Vector3(0.35, 3.25, 0.55) if along_x else Vector3(0.55, 3.25, 0.35)
		var side_axis = Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
		for side in [-1.0, 1.0]:
			WorldSurface.box(self, post_size, midpoint + side_axis * 2.7 + Vector3.UP * 1.62, "metal", false)
		var lintel_size = Vector3(0.35, 0.35, 5.75) if along_x else Vector3(5.75, 0.35, 0.35)
		WorldSurface.box(self, lintel_size, midpoint + Vector3.UP * 3.55, "metal", false)

func _build_props_and_objectives() -> void:
	var reserved: Dictionary = {}
	var breaker_index: int = 1
	for cell in generation_result.breaker_cells:
		var key = Vector3i(cell.x, 0, cell.y)
		reserved[key] = true
		_add_item("breaker", key, Vector3(2.15, 1.1, 0), "%02d / RELAY" % breaker_index)
		breaker_index += 1
	var exit_cell: Vector2i = generation_result.exit_cell
	var exit_key = Vector3i(exit_cell.x, 0, exit_cell.y)
	reserved[exit_key] = true
	_add_item("exit", exit_key, Vector3(0, 1.2, 0), "DESCENT GATE")
	WorldSurface.label(self, "DESCENT / LEVEL %02d\nPOWER REQUIRED" % (progression_level + 1), center(exit_key) + Vector3(0, 2.9, 0), Color("d77f68"), 30)
	var ordinary_rooms: Array = []
	for room in generated_rooms:
		if room.type not in ["spawn_room", "exit_room"]:
			ordinary_rooms.append(room)
	var batteries = mini(5, ordinary_rooms.size())
	for index in range(batteries):
		var room: Dictionary = ordinary_rooms[(index * 7 + 2) % ordinary_rooms.size()]
		var key_2d: Vector2i = room.markers[0] if not room.markers.is_empty() else room.tiles[0]
		var key = Vector3i(key_2d.x, 0, key_2d.y)
		if not reserved.has(key):
			_add_item("battery", key, Vector3(-1.8, 0.6, 1.7), "BATTERY")
	var lockers: int = 0
	for room in ordinary_rooms:
		if lockers >= 4:
			break
		if room.type in ["storage_room", "abandoned_office", "dark_classroom", "dead_end"]:
			var cell_2d: Vector2i = room.tiles[0]
			var key = Vector3i(cell_2d.x, 0, cell_2d.y)
			if not reserved.has(key):
				_add_item("hide", key, Vector3(-2.15, 0, -1.7), "LOCKER")
				lockers += 1
	for room in ordinary_rooms:
		if rng.randf() > 0.28 or room.tiles.is_empty():
			continue
		var cell_2d: Vector2i = room.tiles.back()
		var key = Vector3i(cell_2d.x, 0, cell_2d.y)
		if reserved.has(key) or key in safe_cells:
			continue
		var p = center(key) + Vector3(2.25, 0.55, 1.8)
		var size = Vector3(0.75, 1.1, 1.25)
		WorldSurface.box(self, size, p, "rust" if room.prop_style in ["storage", "maintenance"] else "metal")
		nav_obstacles.append(AABB(p - size * 0.5, size))
	for safe in safe_cells:
		WorldSurface.box(self, Vector3(4.7, 0.025, 4.7), center(safe) + Vector3.UP * 0.02, "safe", false)
		WorldSurface.label(self, "EMERGENCY REFUGE\n18 SECONDS", center(safe) + Vector3(0, 2.65, 2.65), Color("85e6c5"), 28)

func _build_spawn_and_patrol_points() -> void:
	spawns.clear()
	patrol_points.clear()
	var spawn_room: Dictionary = generated_rooms[0]
	for marker in spawn_room.markers:
		spawns.append(Vector3(marker.x * CELL, 0.1, marker.y * CELL))
	if spawns.is_empty():
		var fallback: Vector2i = generation_result.spawn_cell
		spawns.append(Vector3(fallback.x * CELL, 0.1, fallback.y * CELL))
	for key in tiles:
		if key in safe_cells:
			continue
		if navigation_clear(AABB(center(key) + Vector3(-0.4, 0.3, -0.4), Vector3(0.8, 1.1, 0.8))):
			patrol_points.append(center(key))

func _build_environment() -> void:
	env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("05080b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("687c80")
	environment.ambient_light_energy = maxf(0.025, 0.30 * lighting_multiplier * Settings.brightness)
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("0b171b")
	environment.fog_density = 0.010 + (1.0 - lighting_multiplier) * 0.022
	environment.fog_height = 0.0
	environment.fog_height_density = 0.0
	env.environment = environment
	add_child(env)

func apply_quality() -> void:
	if not is_inside_tree() or env == null:
		return
	env.environment.ambient_light_energy = maxf(0.025, 0.30 * lighting_multiplier * Settings.brightness)
	var shadow_stride = maxi(2, roundi(8.0 - (1.0 - lighting_multiplier) * 5.0))
	for index in range(all_lights.size()):
		all_lights[index].shadow_enabled = Settings.quality == 2 and index % shadow_stride == 0
	env.environment.fog_enabled = Settings.quality > 0
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][Settings.quality]

func mark_navigation_ready(success: bool) -> void:
	navigation_status = "READY" if success else "FAILED"
	if not success:
		generation_validation = "NAVIGATION_FAILED"

func validate_navigation() -> bool:
	if spawns.is_empty() or navigation == null or not navigation.synchronized:
		return false
	var exit_item: WorldInteractable
	for item in interactables:
		if item.kind == "exit":
			exit_item = item
			break
	if exit_item == null:
		return false
	var destination = center(exit_item.cell)
	var path = navigation.path_between(spawns[0], destination)
	var valid = path.size() > 1 and path[path.size() - 1].distance_to(destination) < 2.0
	if valid and generation_result.get("fallback", false):
		generation_validation = "FALLBACK_NAV_VALID"
	elif valid:
		generation_validation = "VALID"
	return valid

func hud_location(at: Vector3) -> String:
	var key = Vector3i(roundi(at.x / CELL), 0, roundi(at.z / CELL))
	return "L%02d / %s" % [progression_level, str(tiles.get(key, {"zone": "BETWEEN ROOMS"}).zone)]
