extends "res://scripts/world.gd"
## Original gm_construct-style arena: grass, pool, brick garages, darkroom and roof.
var sun: DirectionalLight3D

func _init() -> void:
	map_id = "construct"
	display_name = "GM CONSTRUCT"
	objective_destination = "COURTYARD GATE"
	mission_description = "Open yard. Garages. Dark rooms.\nRestore three power breakers.\nEscape through the south gate."
	escape_message = "The courtyard gate opens. You escape the construction site."
	menu_view_position = Vector3(66, 15, 119)
	menu_view_rotation = Vector3(-0.15, 0.08, 0)
	safe_cells = [Vector3i(19, 0, 3)]
	spawn_cells = [Vector3i(9, 0, 12), Vector3i(17, 0, 18), Vector3i(6, 0, 7), Vector3i(9, 1, 6)]

func _layout() -> void:
	_rect(1, 19, 8, 21, 0, "CONCRETE COURTYARD")
	_rect(4, 16, 10, 18, 0, "CENTRAL LAWN")
	_rect(6, 9, 15, 17, 0, "SHALLOW POOL")
	_rect(1, 19, 1, 3, 0, "REAR SERVICE HALL")
	_rect(1, 3, 4, 7, 0, "THE DARK ROOM")
	_rect(5, 7, 4, 7, 0, "WEST GARAGE")
	_rect(9, 11, 4, 7, 0, "MAIN GARAGE")
	_rect(13, 15, 4, 7, 0, "EAST GARAGE")
	_rect(17, 19, 4, 7, 0, "WHITE CHAMBER")
	_rect(1, 19, 1, 9, 1, "ROOFTOP")
	for x in [3, 15]:
		for z in range(10, 14):
			tiles[Vector3i(x, 0, z)] = {"zone": "WEST ROOF RAMP" if x == 3 else "EAST ROOF RAMP", "ramp": true}

func nav_blocked(_key: Vector3i) -> bool:
	return false

func _outdoors(key: Vector3i) -> bool:
	return key.y == 1 or key.z >= 8 or tiles[key].get("ramp", false)

func _tile(key: Vector3i) -> void:
	var p = center(key)
	var ramp: bool = tiles[key].get("ramp", false)
	var outdoors = _outdoors(key)
	var zone: String = tiles[key].zone
	var tile_root = Node3D.new()
	tile_root.position = p
	if ramp:
		tile_root.rotation.x = atan(0.25)
	add_child(tile_root)
	var floor_kind = "grass" if zone == "CENTRAL LAWN" else "paving"
	if zone == "THE DARK ROOM":
		floor_kind = "dark"
	elif zone == "WHITE CHAMBER":
		floor_kind = "white"
	if zone == "SHALLOW POOL":
		floor_kind = "pool_tile"
	WorldSurface.box(tile_root, Vector3(CELL, 0.3, CELL * (sqrt(1.0625) if ramp else 1.0)), Vector3(0, -0.15, 0), floor_kind)
	if not outdoors:
		WorldSurface.box(tile_root, Vector3(CELL, 0.2, CELL), Vector3(0, 3.9, 0), "dark" if zone == "THE DARK ROOM" else "concrete")
	for direction in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if neighbor(key, direction) != null:
			continue
		var wall_height: float = 1.15 if outdoors else 5.7
		var size = Vector3(0.3, wall_height, CELL + 0.1) if direction.x != 0 else Vector3(CELL + 0.1, wall_height, 0.3)
		var at = Vector3(direction.x * CELL / 2.0, wall_height / 2.0, direction.y * CELL / 2.0)
		var kind = "retaining" if outdoors else ("white" if zone == "WHITE CHAMBER" else "brick")
		if zone == "THE DARK ROOM":
			kind = "dark"
		WorldSurface.box(tile_root, size, at, kind)
		WorldSurface.box(tile_root, Vector3(size.x + 0.04, 0.09, size.z + 0.04), at + Vector3.UP * (wall_height / 2.0 - 0.04), "white", false)
	if ramp:
		for n in range(8):
			WorldSurface.box(tile_root, Vector3(5.5, 0.012, 0.045), Vector3(0, 0.015, -2.65 + n * 0.77), "stripe", false)
	if not outdoors and (key.x + key.z) % 4 == 0:
		if zone == "THE DARK ROOM":
			_light(p, false, true)
		else:
			_light(p, is_safe_cell(key), false)
	if is_safe_cell(key):
		WorldSurface.box(tile_root, Vector3(4.8, 0.025, 4.8), Vector3(0, 0.02, 0), "safe", false)
		_light(p, true, false)
		WorldSurface.label(self, "REFUGE / 18 SEC", p + Vector3(0, 2.8, 2.6), Color("85e6c5"), 34)

func _obstacle_box(size: Vector3, at: Vector3, kind: String) -> Node3D:
	var body = WorldSurface.box(self, size, at, kind)
	nav_obstacles.append(AABB(at - size / 2.0, size))
	return body

func _props() -> void:
	# Four solid brick piers split the facade into five large walk-through bays.
	for x in [4, 8, 12, 16]:
		_obstacle_box(Vector3(6, 5.7, 24), Vector3(x * CELL, 2.85, 33), "brick")
	for x in [2, 6, 10, 14, 18]:
		WorldSurface.box(self, Vector3(18, 1.9, 0.55), Vector3(x * CELL, 4.75, 45), "brick")
		WorldSurface.box(self, Vector3(18, 0.16, 0.7), Vector3(x * CELL, 3.82, 45), "metal", false)
		WorldSurface.label(self, "%02d / %s" % [x / 4 + 1, "DARKROOM" if x == 2 else ("WHITE ROOM" if x == 18 else "GARAGE")], Vector3(x * CELL, 4.8, 45.4), Color("ddd9c5"), 36)
	# The retaining walls and blue sky make the arena feel open yet enclosed.
	WorldSurface.box(self, Vector3(1, 24, 127), Vector3(2.5, 12, 66), "retaining")
	WorldSurface.box(self, Vector3(1, 24, 127), Vector3(117.5, 12, 66), "retaining")
	WorldSurface.box(self, Vector3(116, 24, 1), Vector3(60, 12, 2.5), "retaining")
	WorldSurface.box(self, Vector3(116, 24, 1), Vector3(60, 12, 129.5), "retaining")
	for x in [2.5, 117.5]:
		WorldSurface.box(self, Vector3(1.3, 0.25, 127), Vector3(x, 24.1, 66), "grass", false)
	# Reflecting pool is ankle-deep: both player and bots can cross it.
	var water = WorldSurface.box(self, Vector3(23.8, 0.025, 17.8), Vector3(45, 0.03, 96), "water", false)
	water.name = "ShallowReflectingPool"
	for x in [33.2, 56.8]:
		WorldSurface.box(self, Vector3(0.16, 0.035, 18), Vector3(x, 0.045, 96), "white", false)
	for z in [87.2, 104.8]:
		WorldSurface.box(self, Vector3(24, 0.035, 0.16), Vector3(45, 0.045, z), "white", false)
	# Scattered crates, low barriers and rooftop equipment break sight lines.
	for at in [Vector3(73, 1.2, 75), Vector3(81, 1.2, 78), Vector3(44, 1.2, 65), Vector3(96, 1.2, 110)]:
		var crate = _obstacle_box(Vector3(2.8, 2.4, 2.8), at, "rust")
		for height in [-0.8, 0.8]:
			WorldSurface.box(crate, Vector3(2.86, 0.08, 2.86), Vector3(0, height, 0), "metal", false)
	for at in [Vector3(30, 0.55, 115), Vector3(83, 0.55, 91), Vector3(60, 0.55, 66)]:
		_obstacle_box(Vector3(8, 1.1, 0.8), at, "concrete")
	for at in [Vector3(27, 7.2, 24), Vector3(66, 7.2, 36), Vector3(95, 7.2, 19)]:
		var vent = _obstacle_box(Vector3(4, 2.4, 5), at, "metal")
		for n in range(7):
			WorldSurface.box(vent, Vector3(4.04, 0.07, 5.04), Vector3(0, -0.8 + n * 0.25, 0), "dark", false)
	for x in [6, 10, 14]:
		# Service benches in the garages leave broad paths on either side.
		_obstacle_box(Vector3(4, 1.1, 1.2), Vector3(x * CELL, 0.55, 29), "metal")
	for at in [Vector3(9, 0, 79), Vector3(111, 0, 79), Vector3(9, 0, 115), Vector3(111, 0, 115)]:
		_tree(at)
	# Working objectives, hiding spots and supplies on both elevations.
	_add_item("breaker", Vector3i(2, 0, 4), Vector3(-2.3, 1.1, 0), "01 / DARKROOM")
	_add_item("breaker", Vector3i(14, 0, 4), Vector3(2.3, 1.1, 0), "02 / GARAGE POWER")
	_add_item("breaker", Vector3i(18, 1, 2), Vector3(0, 1.1, -1.0), "03 / ROOF RELAY")
	_add_item("exit", Vector3i(10, 0, 21), Vector3(0, 1.2, 2.3), "COURTYARD GATE")
	for key in [Vector3i(6, 0, 6), Vector3i(18, 0, 6), Vector3i(2, 0, 20), Vector3i(4, 1, 5), Vector3i(16, 1, 8)]:
		_add_item("battery", key, Vector3(1.8, 0.6, 0), "BATTERY")
	for key in [Vector3i(2, 0, 2), Vector3i(18, 0, 2), Vector3i(10, 0, 2)]:
		_add_item("hide", key, Vector3(-2.1, 0, 0), "LOCKER")
	# The extraction gate is visual; its control uses the normal win interaction.
	WorldSurface.box(self, Vector3(9, 3.5, 0.12), Vector3(60, 1.75, 128.8), "metal", false)
	for x in range(56, 65, 2):
		WorldSurface.box(self, Vector3(0.08, 3.5, 0.2), Vector3(x, 1.75, 128.6), "stripe", false)

func _tree(at: Vector3) -> void:
	_obstacle_box(Vector3(0.6, 3.3, 0.6), at + Vector3.UP * 1.65, "rust")
	var leaves = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 2.1
	sphere.height = 4.8
	sphere.radial_segments = 12
	sphere.rings = 6
	leaves.mesh = sphere
	leaves.material_override = WorldSurface.material("grass")
	leaves.position = at + Vector3.UP * 4.7
	add_child(leaves)

func _story() -> void:
	WorldSurface.box(self, Vector3(15, 2.8, 0.12), Vector3(61, 8.1, 57.1), "metal", false)
	WorldSurface.label(self, "GM CONSTRUCT", Vector3(61, 8.4, 57.3), Color("d7e4e2"), 100)
	WorldSurface.label(self, "ORIGINAL RECREATION / NEXTBOT TEST SITE", Vector3(61, 7, 57.3), Color("a9c2c8"), 31)
	WorldSurface.label(self, "THREE BREAKERS → SOUTH GATE", Vector3(60, 3.4, 128.5), Color("a5dfc9"), 44).rotation.y = PI
	WorldSurface.label(self, "← DARKROOM / GARAGES / WHITE ROOM →", Vector3(61, 2.8, 46), Color("c9d5d1"), 37)
	for x in [3, 15]:
		WorldSurface.label(self, "ROOF ACCESS ↑", Vector3(x * CELL, 2.8, 86), Color("bcd1d4"), 33)
	WorldSurface.label(self, "DON'T STOP IN THE DARK", Vector3(12, 2.2, 21.4), Color("cf9a84"), 28)

func _environment() -> void:
	env = WorldEnvironment.new()
	var e = Environment.new()
	var sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("5886b3")
	sky_material.sky_horizon_color = Color("b3ccd7")
	sky_material.ground_bottom_color = Color("5c6864")
	sky_material.ground_horizon_color = Color("a5bbc5")
	sky_material.sun_angle_max = 8.0
	sky.sky_material = sky_material
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("abbfd1")
	e.ambient_light_energy = 0.48
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color("a0b8c5")
	e.fog_density = 0.0018
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54, -32, 0)
	sun.light_color = Color("fff3d4")
	sun.light_energy = 1.0
	sun.directional_shadow_max_distance = 125.0
	add_child(sun)

func apply_quality() -> void:
	super.apply_quality()
	if is_instance_valid(sun):
		sun.shadow_enabled = Settings.quality > 0

func hud_location(at: Vector3) -> String:
	return "CONSTRUCT / %s" % zone_at(at)
