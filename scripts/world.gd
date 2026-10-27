class_name LevelWorld
extends Node3D
## Hand-authored interconnected tile plan with two real ramp connections.
const CELL: float = 6.0
const WALL_HEIGHT: float = 3.8
var tiles: Dictionary = {}
var spawns: Array[Vector3] = []
var patrol_points: Array[Vector3] = []
var interactables: Array[Node3D] = []
var flickers: Array = []
var safe_cells: Array[Vector3i] = [Vector3i(1, 0, 9), Vector3i(17, 0, 5)]
var refuge_charge: Dictionary = {}
var navigation: LevelNavigation
var rng = RandomNumberGenerator.new()
var elapsed: float = 0.0
var env: WorldEnvironment
var all_lights: Array[OmniLight3D] = []
var nav_obstacles: Array[AABB] = []
var session
var map_id: String = "complex"
var display_name: String = "UNDERGROUND COMPLEX"
var objective_destination: String = "NORTH SERVICE LIFT"
var mission_description: String = "Restore three breakers.\nReach the north service lift.\nSurvive what follows you."
var escape_message: String = "The lift doors close. Something is still down there."
var menu_view_position: Vector3 = Vector3(54, 7.7, 54)
var menu_view_rotation: Vector3 = Vector3(0, 0.5, 0)
var spawn_cells: Array[Vector3i] = [Vector3i(2, 0, 9), Vector3i(17, 0, 6), Vector3i(8, 0, 17), Vector3i(9, 1, 3)]

func _ready() -> void:
	rng.seed = 4413
	_layout()
	_environment()
	for key in tiles:
		_tile(key)
	_props()
	_story()
	print("LEVEL: ", tiles.size(), " tiles, ", WorldSurface.batch_static(self), " static render batches")
	navigation = LevelNavigation.new()
	navigation.name = "ConnectedNavigationMesh"
	add_child(navigation)
	navigation.build(tiles, self)
	for cell in spawn_cells:
		spawns.append(center(cell) + Vector3.UP * 0.1)
	for key in tiles:
		if not is_safe_cell(key) and not nav_blocked(key) and not tiles[key].get("ramp", false):
			if navigation_clear(AABB(center(key) + Vector3(-0.4, 0.3, -0.4), Vector3(0.8, 1.1, 0.8))):
				patrol_points.append(center(key))
	for safe in safe_cells:
		refuge_charge[safe] = 18.0
	Settings.changed.connect(apply_quality)
	apply_quality()

func _rect(x0: int, x1: int, z0: int, z1: int, floor_index: int, zone: String) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			tiles[Vector3i(x, floor_index, z)] = {"zone": zone}

func _layout() -> void:
	_rect(1, 17, 9, 9, 0, "TRANSIT SPINE")
	_rect(1, 17, 17, 17, 0, "SERVICE RING")
	_rect(1, 1, 1, 17, 0, "WEST MAINTENANCE")
	_rect(17, 17, 1, 17, 0, "EAST MAINTENANCE")
	_rect(1, 17, 1, 1, 0, "NORTH TRANSIT")
	_rect(9, 9, 1, 17, 0, "CENTRAL SPINE")
	# Backrooms: long sight lines crossed by shorter escape routes.
	_rect(2, 7, 3, 3, 0, "THE YELLOW ROOMS")
	_rect(2, 7, 7, 7, 0, "THE YELLOW ROOMS")
	_rect(3, 3, 2, 8, 0, "THE YELLOW ROOMS")
	_rect(7, 7, 2, 9, 0, "THE YELLOW ROOMS")
	_rect(4, 6, 5, 5, 0, "THE YELLOW ROOMS")
	_rect(5, 5, 3, 7, 0, "THE YELLOW ROOMS")
	_rect(10, 16, 3, 3, 0, "STORAGE / C")
	_rect(11, 11, 4, 7, 0, "STORAGE / C")
	_rect(12, 15, 5, 7, 0, "STORAGE / C")
	_rect(15, 17, 5, 5, 0, "REFUGE / 02")
	_rect(13, 13, 1, 3, 0, "STORAGE / C")
	_rect(10, 16, 10, 16, 0, "PARKING / B2")
	# Large ventilation shafts break up parking without trapping navigation agents.
	for x in [11, 14]:
		for z in [11, 14]:
			tiles.erase(Vector3i(x, 0, z))
	_rect(2, 8, 15, 16, 0, "LOADING BAY")
	_rect(5, 7, 11, 14, 0, "VENTILATION")
	_rect(7, 9, 12, 12, 0, "VENTILATION")
	_rect(3, 5, 14, 14, 0, "WEST STAIRWELL")
	_rect(2, 4, 10, 10, 0, "WEST MAINTENANCE")
	# Upper floor, two loops connected to the lower parking/loading area.
	_rect(3, 15, 3, 3, 1, "UPPER CONCOURSE")
	_rect(3, 15, 9, 9, 1, "UPPER CONCOURSE")
	_rect(3, 3, 3, 9, 1, "WEST STAIRWELL")
	_rect(15, 15, 3, 9, 1, "EAST STAIRWELL")
	_rect(9, 9, 3, 9, 1, "ARCHIVE HALL")
	_rect(4, 8, 5, 7, 1, "RECORDS / 1986")
	_rect(6, 6, 3, 9, 1, "RECORDS / 1986")
	_rect(10, 14, 5, 7, 1, "PUMP CONTROL")
	_rect(12, 12, 3, 9, 1, "PUMP CONTROL")
	for x in [3, 15]:
		for z in range(10, 14):
			tiles[Vector3i(x, 0, z)] = {"zone": "WEST STAIRWELL" if x == 3 else "EAST STAIRWELL", "ramp": true}

func height_at(key: Vector3i, z_world: float) -> float:
	if tiles[key].get("ramp", false):
		return clampf((13.5 * CELL - z_world) * 0.25, 0.0, 6.0)
	return float(key.y) * 6.0

func center(key: Vector3i) -> Vector3:
	return Vector3(key.x * CELL, height_at(key, key.z * CELL), key.z * CELL)

func neighbor(key: Vector3i, offset: Vector2i):
	var edge_z = key.z * CELL + offset.y * CELL / 2.0
	var expected = height_at(key, edge_z)
	for floor_index in [0, 1]:
		var other = Vector3i(key.x + offset.x, floor_index, key.z + offset.y)
		if tiles.has(other) and absf(height_at(other, edge_z) - expected) < 0.1:
			# Ramps may only connect at their ends, never across a stepped side edge.
			if offset.x != 0 and (tiles[key].get("ramp", false) or tiles[other].get("ramp", false)):
				continue
			return other
	return null

func connected(key: Vector3i, offset: Vector2i) -> bool:
	var other = neighbor(key, offset)
	return other != null and not nav_blocked(other)

func nav_blocked(key: Vector3i) -> bool:
	return key.y == 0 and key.x == 5 and key.z in [14, 15]

func is_safe_cell(key: Vector3i) -> bool:
	return key in safe_cells

func _tile(key: Vector3i) -> void:
	var p = center(key)
	var ramp: bool = tiles[key].get("ramp", false)
	var yellow: bool = tiles[key].zone == "THE YELLOW ROOMS"
	var floor_kind = "carpet" if yellow else "floor"
	var wall_kind = "yellow" if yellow else "concrete"
	var tile_root = Node3D.new()
	tile_root.position = p
	if ramp:
		tile_root.rotation.x = atan(0.25)
	add_child(tile_root)
	WorldSurface.box(tile_root, Vector3(CELL, 0.3, CELL * (sqrt(1.0625) if ramp else 1.0)), Vector3(0, -0.15, 0), floor_kind)
	WorldSurface.box(tile_root, Vector3(CELL, 0.2, CELL * (sqrt(1.0625) if ramp else 1.0)), Vector3(0, WALL_HEIGHT + 0.1, 0), "ceiling")
	for direction in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if neighbor(key, direction) != null:
			continue
		var size = Vector3(0.3, WALL_HEIGHT, CELL + 0.1) if direction.x != 0 else Vector3(CELL + 0.1, WALL_HEIGHT, 0.3)
		var wall_at = Vector3(direction.x * CELL / 2.0, WALL_HEIGHT / 2.0, direction.y * CELL / 2.0)
		WorldSurface.box(tile_root, size, wall_at, wall_kind)
		# Wall footings, numbered service panels and a continuous low stripe.
		WorldSurface.box(tile_root, Vector3(size.x + 0.03, 0.14, size.z + 0.03), wall_at - Vector3.UP * 1.55, "metal", false)
		if not yellow:
			WorldSurface.box(tile_root, Vector3(size.x + 0.04, 0.06, size.z + 0.04), wall_at - Vector3.UP * 0.6, "safe" if key.y == 1 else "stripe", false)
	if ramp:
		# Tread markings and rails keep stairs legible; continuous collision is smooth.
		for n in range(8):
			WorldSurface.box(tile_root, Vector3(5.5, 0.012, 0.04), Vector3(0, 0.012, -2.65 + n * 0.77), "stripe", false)
		for side in [-1, 1]:
			WorldSurface.box(tile_root, Vector3(0.07, 0.08, 6.1), Vector3(side * 2.6, 1.0, 0), "metal", false)
	if (key.x + key.z * 2 + key.y) % 4 == 0 or is_safe_cell(key):
		_light(p, is_safe_cell(key), ramp or (key.x + key.z) % 7 == 0)
	if key.x == 9 and key.z % 4 == 1:
		WorldSurface.box(tile_root, Vector3(0.06, 0.02, 2.0), Vector3(0, 0.015, 0), "stripe", false)
	if is_safe_cell(key):
		WorldSurface.box(tile_root, Vector3(4.8, 0.025, 4.8), Vector3(0, 0.02, 0), "safe", false)
		WorldSurface.label(self, "POWERED REFUGE\n18 SECONDS OF SILENCE", p + Vector3(0, 2.5, 2.7), Color("85e6c5"), 31)

func _light(p: Vector3, safe: bool, faulty: bool) -> void:
	WorldSurface.box(self, Vector3(1.5, 0.11, 0.4), p + Vector3(0, 3.68, 0), "green" if safe else ("emergency" if faulty else "glow"), false)
	var light = OmniLight3D.new()
	light.position = p + Vector3(0, 3.2, 0)
	light.light_color = Color("80dcc7") if safe else (Color("ec7561") if faulty else Color("d8ddb9"))
	light.omni_range = 10.5
	light.light_energy = 1.9 if safe else 1.5
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	add_child(light)
	all_lights.append(light)
	if faulty:
		flickers.append({"light": light, "phase": rng.randf() * 20.0, "energy": light.light_energy})

func _props() -> void:
	# Wall props get navigation clearance when the mesh is built below.
	for key in tiles:
		if tiles[key].get("ramp", false) or is_safe_cell(key):
			continue
		var p = center(key)
		if rng.randf() < 0.3 and neighbor(key, Vector2i(1, 0)) == null:
			var rack = WorldSurface.box(self, Vector3(0.65, 2.1, 2.2), p + Vector3(2.55, 1.05, 0), "metal")
			nav_obstacles.append(AABB(p + Vector3(2.225, 0, -1.1), Vector3(0.65, 2.1, 2.2)))
			for shelf in [0.4, 1.0, 1.6]:
				WorldSurface.box(rack, Vector3(0.69, 0.06, 2.3), Vector3(0, shelf - 1.05, 0), "rust", false)
		elif rng.randf() < 0.22 and neighbor(key, Vector2i(-1, 0)) == null:
			WorldSurface.box(self, Vector3(0.6, 1.25, 1.8), p + Vector3(-2.55, 0.625, 0), "rust")
			nav_obstacles.append(AABB(p + Vector3(-2.85, 0, -0.9), Vector3(0.6, 1.25, 1.8)))
		if (key.x * 3 + key.z) % 8 == 0:
			WorldSurface.box(self, Vector3(0.16, 0.16, 6.0), p + Vector3(-2.3, 3.5, 0), "rust", false)
	# Parking ventilation cores and lane markings.
	for x in [11, 14]:
		for z in [11, 14]:
			WorldSurface.box(self, Vector3(5.8, 3.8, 5.8), Vector3(x * CELL, 1.9, z * CELL), "concrete")
			WorldSurface.box(self, Vector3(5.84, 0.35, 5.84), Vector3(x * CELL, 1.2, z * CELL), "stripe", false)
	for x in range(10, 17):
		for z in [10, 13, 16]:
			WorldSurface.box(self, Vector3(0.09, 0.014, 3.8), Vector3(x * CELL + 2.3, 0.012, z * CELL), "white", false)
	# Crouch-only shortcut between ventilation and the loading bay.
	for z in [14, 15]:
		var key = Vector3i(5, 0, z)
		WorldSurface.box(self, Vector3(6, 2.1, 0.4), center(key) + Vector3(0, 2.75, 0), "metal")
	# Interactive objects: fixed locations make spatial learning rewarding.
	_add_item("breaker", Vector3i(5, 0, 5), Vector3(-2.3, 1.1, 0), "01 / SIGNAL")
	_add_item("breaker", Vector3i(13, 0, 7), Vector3(0, 1.1, 2.3), "02 / VENTILATION")
	_add_item("breaker", Vector3i(12, 1, 6), Vector3(-2.3, 1.1, 0), "03 / PUMP CONTROL")
	_add_item("exit", Vector3i(9, 0, 1), Vector3(0, 1.2, -2.3), "SERVICE LIFT")
	for key in [Vector3i(7, 0, 7), Vector3i(17, 0, 9), Vector3i(7, 0, 15), Vector3i(6, 1, 5), Vector3i(15, 1, 3)]:
		_add_item("battery", key, Vector3(2.0, 0.6, 0), "BATTERY")
	for key in [Vector3i(11, 0, 6), Vector3i(5, 0, 16), Vector3i(8, 1, 6), Vector3i(1, 0, 13)]:
		_add_item("hide", key, Vector3(-2.2, 0.0, 0), "LOCKER")

func _add_item(kind: String, key: Vector3i, offset: Vector3, title: String) -> void:
	var item = preload("res://scripts/interactable.gd").new()
	item.kind = kind
	item.cell = key
	item.set_meta("dynamic_geometry", true)
	item.title = title
	item.position = center(key) + offset
	add_child(item)
	interactables.append(item)
	if kind == "hide":
		nav_obstacles.append(AABB(item.position + Vector3(-0.525, 0, -0.55), Vector3(1.05, 2.35, 1.1)))
	elif kind in ["breaker", "exit"]:
		nav_obstacles.append(AABB(item.position - Vector3(0.325, 0.5, 0.25), Vector3(0.65, 1.0, 0.5)))

func navigation_clear(bounds: AABB) -> bool:
	for obstacle in nav_obstacles:
		# Clearance is horizontal; a roof may sit directly on a solid support below.
		var expanded = AABB(obstacle.position - Vector3(0.47, 0, 0.47), obstacle.size + Vector3(0.94, 0, 0.94))
		if bounds.intersects(expanded):
			return false
	return true

func _story() -> void:
	var signs = [
		[Vector3i(9, 0, 9), "← REFUGE 01     PARKING B2 →\n↑ STORAGE     LOADING BAY ↓"],
		[Vector3i(3, 0, 14), "STAIR A / UPPER ARCHIVES\nKEEP MOVING"],
		[Vector3i(15, 0, 14), "STAIR B / PUMP CONTROL\nNO PERSONNEL BEYOND THIS POINT"],
		[Vector3i(9, 1, 3), "LEVEL −1 / ARCHIVE\nTHEY FOLLOW THE SOUND"],
		[Vector3i(1, 0, 3), "DO NOT TRUST THE QUIET"],
		[Vector3i(13, 0, 3), "RESTORE ALL THREE BREAKERS\nTHEN RETURN TO THE NORTH LIFT"],
		[Vector3i(9, 0, 17), "SECTOR 06\nEVACUATION SUSPENDED  /  17.11.86"]
	]
	for entry in signs:
		WorldSurface.label(self, entry[1], center(entry[0]) + Vector3(0, 2.7, -2.55), Color("c2c5ab"), 30)

func _environment() -> void:
	env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("0b1319")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("829797")
	e.ambient_light_energy = 0.34
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color("132328")
	e.fog_density = 0.012
	e.fog_height = 0.0
	e.fog_height_density = 0.0
	env.environment = e
	add_child(env)

func apply_quality() -> void:
	if not is_inside_tree():
		return
	for i in range(all_lights.size()):
		all_lights[i].shadow_enabled = Settings.quality == 2 and i % 7 == 0
	env.environment.fog_enabled = Settings.quality > 0
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][Settings.quality]

func _process(delta: float) -> void:
	elapsed += delta
	for entry in flickers:
		var wave = sin(elapsed * 9.0 + entry.phase) * sin(elapsed * 17.3 + entry.phase)
		entry.light.light_energy = entry.energy * (0.35 if wave > 0.52 and not Settings.reduced_flashes else 1.0)
	for key in refuge_charge:
		if session != null and is_instance_valid(session.player) and session.is_running():
			if not session.is_authority():
				continue
			var occupied: bool = false
			for actor in session.target_players():
				if session.actor_alive(actor) and actor.global_position.distance_to(center(key)) < 2.7:
					occupied = true
			if occupied:
				refuge_charge[key] = maxf(0.0, refuge_charge[key] - delta)
			else:
				refuge_charge[key] = minf(18.0, refuge_charge[key] + delta * 0.1)

func refuge_remaining(at: Vector3) -> float:
	for key in refuge_charge:
		if at.distance_to(center(key)) < 2.7:
			return refuge_charge[key]
	return -1.0

func zone_at(at: Vector3) -> String:
	var key = Vector3i(roundi(at.x / CELL), 1 if at.y > 4.8 else 0, roundi(at.z / CELL))
	return tiles.get(key, {"zone": "STAIRWELL"}).zone

func hud_location(at: Vector3) -> String:
	return "B%d / %s" % [1 if at.y > 4.8 else 2, zone_at(at)]

func far_point(origin: Vector3, min_distance: float = 32.0) -> Vector3:
	var candidates: Array[Vector3] = []
	for p in patrol_points:
		if p.distance_to(origin) >= min_distance:
			candidates.append(p)
	return candidates[rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else patrol_points[0]

func reset_items() -> void:
	for item in interactables:
		item.reset()
	for key in refuge_charge:
		refuge_charge[key] = 18.0
