class_name BossfightWorld
extends "res://scripts/world.gd"
## Original sun-baked arena map for Bossfight. Its routes and visual language
## evoke a compact Mediterranean/desert FPS map without copying Mirage geometry.

var stage_level: int = 1
var stage_seed: int = 1
var arena_mode: bool = false
var objective_cells: Array[Vector3i] = []
var objective_signature: String = ""
var sun: DirectionalLight3D

func configure(level: int, seed_value: int) -> void:
	stage_level = maxi(1, level)
	stage_seed = maxi(1, seed_value)
	arena_mode = stage_level % 4 == 0
	# The richer skyline uses more materials; a slightly larger batching cell
	# keeps the redesigned map's draw-call count bounded.
	set_meta("static_batch_chunk", 36.0)
	safe_cells.clear()
	if arena_mode:
		map_id = "bossfight_arena"
		display_name = "SUN RING / BOSS ARENA"
		objective_destination = "DEFEAT THE BOSS"
		mission_description = "An open circular arena.\nDefeat the boss with PNG projectiles.\nSurvive its charge and final phase."
		escape_message = "The boss falls. A new desert sector opens."
		menu_view_position = Vector3(0, 38, 58)
		menu_view_rotation = Vector3(-0.42, PI, 0)
		spawn_cells = [Vector3i(-5, 0, 0), Vector3i(5, 0, 0), Vector3i(0, 0, -5), Vector3i(0, 0, 5)]
	else:
		map_id = "bossfight_mirage"
		display_name = "DUST QUARTER"
		objective_destination = "SUN GATE"
		mission_description = "A sun-baked district of courtyards and covered passages.\nFind three randomized switches.\nOpen the Sun Gate before the Nextbots find you."
		escape_message = "The Sun Gate opens onto another hostile quarter."
		menu_view_position = Vector3(66, 20, 132)
		menu_view_rotation = Vector3(-0.16, PI, 0)
		spawn_cells = [Vector3i(10, 0, 10), Vector3i(3, 0, 4), Vector3i(18, 0, 18), Vector3i(17, 0, 4)]

func _layout() -> void:
	if arena_mode:
		for x in range(-10, 11):
			for z in range(-10, 11):
				if Vector2(x, z).length() <= 10.25:
					tiles[Vector3i(x, 0, z)] = {"zone": "SUN RING" if Vector2(x, z).length() > 6.5 else "BOSS CIRCLE"}
		return
	# A compact competitive-FPS street graph: two bombsite-like plazas, a
	# three-lane middle, market and palace routes, plus an outer rotation. The
	# unwalkable lots between these routes are filled with real building masses
	# in _props(), so the district reads as a town instead of an empty platform.
	_rect(2, 20, 2, 2, 0, "NORTH RING")
	_rect(2, 20, 20, 20, 0, "SOUTH RING")
	_rect(2, 2, 2, 20, 0, "WEST RING")
	_rect(20, 20, 2, 20, 0, "EAST RING")
	_rect(9, 11, 2, 20, 0, "MID PROMENADE")
	_rect(2, 20, 9, 11, 0, "MID PROMENADE")
	_rect(2, 7, 3, 7, 0, "AMBER COURTYARD")
	_rect(14, 20, 14, 19, 0, "AZURE COURTYARD")
	_rect(14, 20, 3, 6, 0, "MARKET HALL")
	_rect(3, 7, 15, 20, 0, "PALACE WALK")
	_rect(2, 3, 7, 15, 0, "WEST ALLEY")
	_rect(18, 20, 6, 14, 0, "EAST ALLEY")
	_rect(6, 9, 6, 9, 0, "UNDERPASS")
	_rect(7, 9, 13, 17, 0, "RAMPART PASS")
	_rect(11, 14, 14, 16, 0, "CATWALK COURT")

func nav_blocked(_key: Vector3i) -> bool:
	return false

func _is_indoor(zone: String) -> bool:
	return zone in ["MARKET HALL", "PALACE WALK", "UNDERPASS"]

func _zone_wall(zone: String) -> String:
	if zone == "AMBER COURTYARD":
		return "ochre_stucco"
	if zone == "AZURE COURTYARD":
		return "blue_stucco"
	if zone == "MARKET HALL":
		return "rose_stucco"
	if zone == "PALACE WALK":
		return "cream_stucco"
	return "sandstone"

func _tile(key: Vector3i) -> void:
	var p := center(key)
	var zone: String = tiles[key].zone
	var indoor := not arena_mode and _is_indoor(zone)
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var floor_kind := "arena_sand" if arena_mode else ("terracotta" if "COURTYARD" in zone else ("paving" if zone in ["MID PROMENADE", "MARKET HALL"] else "sand"))
	WorldSurface.box(root, Vector3(CELL, 0.3, CELL), Vector3(0, -0.15, 0), floor_kind)
	if indoor:
		WorldSurface.box(root, Vector3(CELL, 0.22, CELL), Vector3(0, 4.15, 0), "dark_wood")
	for direction in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if neighbor(key, direction) != null:
			continue
		var wall_height := 5.4 if arena_mode else 4.8
		var size := Vector3(0.35, wall_height, CELL + 0.12) if direction.x != 0 else Vector3(CELL + 0.12, wall_height, 0.35)
		var at := Vector3(direction.x * CELL / 2.0, wall_height / 2.0, direction.y * CELL / 2.0)
		WorldSurface.box(root, size, at, "arena_wall" if arena_mode else _zone_wall(zone))
		WorldSurface.box(root, Vector3(size.x + 0.04, 0.12, size.z + 0.04), at + Vector3.UP * (wall_height / 2.0 - 0.08), "mosaic", false)
		if not arena_mode:
			# Recessed windows and a stone plinth are attached to boundary walls,
			# never suspended in the middle of a street.
			var panel_size := Vector3(0.05, 0.82, 1.25) if direction.x != 0 else Vector3(1.25, 0.82, 0.05)
			var panel_at := Vector3(direction.x * (CELL / 2.0 + 0.19), 2.65, direction.y * (CELL / 2.0 + 0.19))
			if (key.x * 3 + key.z * 5 + direction.x + direction.y) % 3 != 0:
				WorldSurface.box(root, panel_size, panel_at, "window", false)
			var plinth_size := Vector3(0.42, 0.42, CELL + 0.16) if direction.x != 0 else Vector3(CELL + 0.16, 0.42, 0.42)
			WorldSurface.box(root, plinth_size, Vector3(direction.x * CELL / 2.0, 0.21, direction.y * CELL / 2.0), "stone_trim", false)
	if not arena_mode and "COURTYARD" in zone and (key.x + key.z) % 5 == 0:
		WorldSurface.box(root, Vector3(2.4, 0.025, 2.4), Vector3(0, 0.02, 0), "courtyard_tile", false)

func _obstacle(size: Vector3, at: Vector3, material: String) -> Node3D:
	var body := WorldSurface.box(self, size, at, material)
	nav_obstacles.append(AABB(at - size / 2.0, size))
	return body

func _props() -> void:
	if arena_mode:
		_build_arena_props()
		return
	# Fill the non-walkable lots and the horizon with grounded buildings. Their
	# roofs, parapets and windows make the map readable from both street and air.
	_building(Vector2(12, 6), Vector3(27, 0, 48), 7.2, "ochre_stucco", "PALM HOUSE")
	_building(Vector2(18, 12), Vector3(30, 0, 78), 8.6, "cream_stucco", "RAMPART")
	_building(Vector2(30, 12), Vector3(87, 0, 45), 9.8, "rose_stucco", "MARKET LOFTS")
	_building(Vector2(24, 12), Vector3(75, 0, 75), 7.8, "blue_stucco", "MID APARTMENTS")
	_building(Vector2(12, 18), Vector3(75, 0, 108), 10.4, "cream_stucco", "PALACE ANNEX")
	for entry in [
		[Vector2(18, 14), Vector3(24, 0, -1), 8.0, "ochre_stucco"],
		[Vector2(30, 14), Vector3(60, 0, -1), 11.0, "cream_stucco"],
		[Vector2(20, 14), Vector3(102, 0, -1), 8.8, "rose_stucco"],
		[Vector2(24, 14), Vector3(24, 0, 133), 9.5, "blue_stucco"],
		[Vector2(34, 14), Vector3(66, 0, 133), 12.0, "cream_stucco"],
		[Vector2(20, 14), Vector3(108, 0, 133), 8.5, "ochre_stucco"],
		[Vector2(14, 26), Vector3(-1, 0, 30), 9.0, "rose_stucco"],
		[Vector2(14, 30), Vector3(-1, 0, 72), 11.5, "cream_stucco"],
		[Vector2(14, 22), Vector3(-1, 0, 108), 7.5, "ochre_stucco"],
		[Vector2(14, 24), Vector3(133, 0, 30), 10.0, "blue_stucco"],
		[Vector2(14, 32), Vector3(133, 0, 70), 12.5, "cream_stucco"],
		[Vector2(14, 24), Vector3(133, 0, 108), 8.0, "rose_stucco"],
	]:
		_building(entry[0], entry[1], entry[2], entry[3])

	# Amber court: a low fountain and grounded planters preserve a fast loop.
	_obstacle(Vector3(4.6, 0.75, 4.6), Vector3(30, 0.375, 30), "courtyard_tile")
	WorldSurface.box(self, Vector3(2.4, 0.22, 2.4), Vector3(30, 0.86, 30), "water", false)
	for at in [Vector3(21, 0, 21), Vector3(39, 0, 21), Vector3(21, 0, 39), Vector3(39, 0, 39)]:
		_planter(at)

	# Market cloth is held by four visible posts; nothing floats unsupported.
	for at in [Vector3(90, 0, 24), Vector3(102, 0, 24), Vector3(114, 0, 24)]:
		_market_stall(at)

	# A central arch frames mid while leaving a wide slide/bunny-hop gap.
	for side in [-1.0, 1.0]:
		_obstacle(Vector3(0.85, 4.8, 0.85), Vector3(60 + side * 3.0, 2.4, 72), "stone_trim")
	WorldSurface.box(self, Vector3(6.85, 0.85, 0.85), Vector3(60, 4.38, 72), "stone_trim")

	# Fair low cover in B and along the outer rotations.
	for at in [Vector3(94, 1.0, 96), Vector3(106, 1.0, 102), Vector3(111, 1.0, 90), Vector3(60, 1.0, 108)]:
		_crate(at)
	for at in [Vector3(18, 0.55, 72), Vector3(114, 0.55, 66), Vector3(60, 0.55, 18)]:
		_obstacle(Vector3(5.4, 1.1, 0.8), at, "stone_trim")

	for at in [Vector3(18, 0, 18), Vector3(42, 0, 60), Vector3(60, 0, 42), Vector3(108, 0, 36), Vector3(114, 0, 78), Vector3(96, 0, 108), Vector3(42, 0, 114), Vector3(18, 0, 96)]:
		_street_lamp(at)

	var candidates := [
		{"cell": Vector3i(3, 0, 4), "offset": Vector3(-2.3, 1.1, 0)},
		{"cell": Vector3i(7, 0, 7), "offset": Vector3(0, 1.1, -2.3)},
		{"cell": Vector3i(3, 0, 13), "offset": Vector3(-2.3, 1.1, 0)},
		{"cell": Vector3i(6, 0, 17), "offset": Vector3(2.3, 1.1, 0)},
		{"cell": Vector3i(10, 0, 20), "offset": Vector3(0, 1.1, 2.3)},
		{"cell": Vector3i(16, 0, 4), "offset": Vector3(0, 1.1, -2.3)},
		{"cell": Vector3i(17, 0, 4), "offset": Vector3(2.3, 1.1, 0)},
		{"cell": Vector3i(19, 0, 10), "offset": Vector3(2.3, 1.1, 0)},
		{"cell": Vector3i(15, 0, 16), "offset": Vector3(0, 1.1, 2.3)},
		{"cell": Vector3i(19, 0, 18), "offset": Vector3(2.3, 1.1, 0)},
	]
	var order: Array[int] = []
	for index in range(candidates.size()):
		order.append(index)
	var objective_rng := RandomNumberGenerator.new()
	objective_rng.seed = stage_seed
	for i in range(order.size() - 1, 0, -1):
		var j := objective_rng.randi_range(0, i)
		var temporary := order[i]
		order[i] = order[j]
		order[j] = temporary
	objective_cells.clear()
	for index in range(3):
		var entry: Dictionary = candidates[order[index]]
		var cell: Vector3i = entry.cell
		objective_cells.append(cell)
		_add_item("breaker", cell, entry.offset, "SWITCH %02d / %s" % [index + 1, str(tiles[cell].zone)])
	objective_signature = ":".join(objective_cells.map(func(cell): return "%d,%d" % [cell.x, cell.z]))
	_add_item("exit", Vector3i(20, 0, 10), Vector3(2.3, 1.2, 0), "SUN GATE")
	for cell in [Vector3i(3, 0, 10), Vector3i(10, 0, 3), Vector3i(19, 0, 15), Vector3i(7, 0, 20)]:
		_add_item("battery", cell, Vector3(0, 0.6, 0), "BATTERY")
	for cell in [Vector3i(7, 0, 8), Vector3i(19, 0, 8)]:
		_add_item("hide", cell, Vector3(0, 0, 0), "LOCKER")

func _building(footprint: Vector2, at: Vector3, height: float, wall_kind: String, title: String = "") -> void:
	WorldSurface.box(self, Vector3(footprint.x, height, footprint.y), Vector3(at.x, height / 2.0, at.z), wall_kind)
	WorldSurface.box(self, Vector3(footprint.x + 0.35, 0.24, footprint.y + 0.35), Vector3(at.x, height + 0.12, at.z), "roof_tile", false)
	var parapet_y := height + 0.48
	WorldSurface.box(self, Vector3(footprint.x + 0.5, 0.72, 0.36), Vector3(at.x, parapet_y, at.z - footprint.y / 2.0), "stone_trim", false)
	WorldSurface.box(self, Vector3(footprint.x + 0.5, 0.72, 0.36), Vector3(at.x, parapet_y, at.z + footprint.y / 2.0), "stone_trim", false)
	WorldSurface.box(self, Vector3(0.36, 0.72, footprint.y + 0.5), Vector3(at.x - footprint.x / 2.0, parapet_y, at.z), "stone_trim", false)
	WorldSurface.box(self, Vector3(0.36, 0.72, footprint.y + 0.5), Vector3(at.x + footprint.x / 2.0, parapet_y, at.z), "stone_trim", false)
	# Window rows and a grounded door on the street-facing facade.
	var window_count := clampi(floori(footprint.x / 6.0), 1, 5)
	for index in range(window_count):
		var fraction := (float(index) + 1.0) / (float(window_count) + 1.0)
		var x := at.x - footprint.x / 2.0 + footprint.x * fraction
		for y in [2.6, 5.5]:
			if y < height - 0.8:
				WorldSurface.box(self, Vector3(1.25, 0.82, 0.06), Vector3(x, y, at.z + footprint.y / 2.0 + 0.04), "window", false)
				WorldSurface.box(self, Vector3(1.25, 0.82, 0.06), Vector3(x, y, at.z - footprint.y / 2.0 - 0.04), "window", false)
	var side_window_count := clampi(floori(footprint.y / 6.0), 1, 5)
	for index in range(side_window_count):
		var fraction := (float(index) + 1.0) / (float(side_window_count) + 1.0)
		var z := at.z - footprint.y / 2.0 + footprint.y * fraction
		for y in [2.6, 5.5]:
			if y < height - 0.8:
				WorldSurface.box(self, Vector3(0.06, 0.82, 1.25), Vector3(at.x + footprint.x / 2.0 + 0.04, y, z), "window", false)
				WorldSurface.box(self, Vector3(0.06, 0.82, 1.25), Vector3(at.x - footprint.x / 2.0 - 0.04, y, z), "window", false)
	# Continuous trim bands break up large walls at first-person height.
	WorldSurface.box(self, Vector3(footprint.x + 0.12, 0.14, 0.1), Vector3(at.x, 4.25, at.z + footprint.y / 2.0 + 0.06), "stone_trim", false)
	WorldSurface.box(self, Vector3(footprint.x + 0.12, 0.14, 0.1), Vector3(at.x, 4.25, at.z - footprint.y / 2.0 - 0.06), "stone_trim", false)
	WorldSurface.box(self, Vector3(0.1, 0.14, footprint.y + 0.12), Vector3(at.x + footprint.x / 2.0 + 0.06, 4.25, at.z), "stone_trim", false)
	WorldSurface.box(self, Vector3(0.1, 0.14, footprint.y + 0.12), Vector3(at.x - footprint.x / 2.0 - 0.06, 4.25, at.z), "stone_trim", false)
	if height >= 8.5 and footprint.x >= 16.0:
		WorldSurface.box(self, Vector3(minf(8.0, footprint.x * 0.45), 0.16, 1.15), Vector3(at.x, 4.45, at.z + footprint.y / 2.0 + 0.55), "dark_wood", false)
	WorldSurface.box(self, Vector3(1.25, 2.25, 0.08), Vector3(at.x, 1.125, at.z + footprint.y / 2.0 + 0.05), "dark_wood", false)
	if not title.is_empty():
		WorldSurface.box(self, Vector3(minf(footprint.x - 1.0, 10.0), 0.9, 0.1), Vector3(at.x, 3.7, at.z + footprint.y / 2.0 + 0.08), "sign_back", false)
		WorldSurface.label(self, title, Vector3(at.x, 3.7, at.z + footprint.y / 2.0 + 0.15), Color("f6dfaf"), 22)
	# Water tanks sit directly on the roof instead of floating above it.
	if height >= 9.0:
		WorldSurface.box(self, Vector3(2.4, 1.2, 2.4), Vector3(at.x + footprint.x * 0.2, height + 0.72, at.z), "mosaic", false)

func _planter(at: Vector3) -> void:
	_obstacle(Vector3(1.8, 0.65, 1.8), at + Vector3.UP * 0.325, "stone_trim")
	WorldSurface.box(self, Vector3(0.38, 2.6, 0.38), at + Vector3.UP * 1.95, "wood", false)
	WorldSurface.box(self, Vector3(1.8, 1.25, 1.8), at + Vector3.UP * 3.0, "foliage", false)
	WorldSurface.box(self, Vector3(1.25, 0.9, 1.25), at + Vector3(0.55, 3.45, 0), "foliage", false)

func _market_stall(at: Vector3) -> void:
	for x in [-2.8, 2.8]:
		for z in [-1.7, 1.7]:
			WorldSurface.box(self, Vector3(0.13, 2.9, 0.13), at + Vector3(x, 1.45, z), "dark_wood", false)
	WorldSurface.box(self, Vector3(6.0, 0.16, 3.8), at + Vector3.UP * 2.9, "awning", false)
	WorldSurface.box(self, Vector3(4.6, 0.9, 1.1), at + Vector3(0, 0.45, 0), "wood", false)

func _crate(at: Vector3) -> void:
	var crate := _obstacle(Vector3(2.4, 2.0, 2.4), at, "wood")
	WorldSurface.box(crate, Vector3(2.46, 0.08, 2.46), Vector3(0, 1.04, 0), "metal", false)

func _street_lamp(at: Vector3) -> void:
	_obstacle(Vector3(0.34, 0.28, 0.34), at + Vector3.UP * 0.14, "stone_trim")
	WorldSurface.box(self, Vector3(0.14, 3.2, 0.14), at + Vector3.UP * 1.74, "metal", false)
	_add_lantern(at + Vector3.UP * 3.42, true, Color("ffd49a"))

func _build_arena_props() -> void:
	# Eight spaced pillars make boss charges avoidable without turning the arena
	# into a maze. The centre remains completely open for projectile combat.
	for at in [Vector3(24, 2.4, 0), Vector3(-24, 2.4, 0), Vector3(0, 2.4, 24), Vector3(0, 2.4, -24), Vector3(18, 2.4, 18), Vector3(-18, 2.4, 18), Vector3(18, 2.4, -18), Vector3(-18, 2.4, -18)]:
		_obstacle(Vector3(2.6, 4.8, 2.6), at, "arena_wall")
		WorldSurface.box(self, Vector3(3.4, 0.2, 3.4), at + Vector3.UP * 2.45, "mosaic", false)
	for angle_index in range(12):
		var angle := TAU * float(angle_index) / 12.0
		var at := Vector3(cos(angle) * 48.0, 3.2, sin(angle) * 48.0)
		_add_lantern(at, false, Color("ff854f"))
	WorldSurface.box(self, Vector3(18, 0.08, 18), Vector3(0, 0.04, 0), "mosaic", false)
	WorldSurface.label(self, "SUN RING", Vector3(0, 0.16, 0), Color("6f352a"), 92).rotation_degrees.x = -90

func _add_lantern(at: Vector3, indoor: bool, color: Color = Color("ffd38b")) -> void:
	if not indoor:
		var post_height := maxf(0.3, at.y - 0.35)
		WorldSurface.box(self, Vector3(0.14, post_height, 0.14), Vector3(at.x, post_height / 2.0, at.z), "metal", false)
		WorldSurface.box(self, Vector3(0.6, 0.16, 0.6), Vector3(at.x, 0.08, at.z), "stone_trim", false)
	WorldSurface.box(self, Vector3(0.45, 0.7, 0.45), at, "glow", false)
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = 1.1 if indoor else 0.72
	light.omni_range = 8.0 if indoor else 10.0
	light.shadow_enabled = false
	add_child(light)
	all_lights.append(light)

func _story() -> void:
	if arena_mode:
		WorldSurface.label(self, "BOSS CYCLE %02d\nBREAK THE FACE / SURVIVE THE CHARGE" % (stage_level / 4), Vector3(0, 5.8, -59), Color("ffd08a"), 44)
		return
	# Every sign has a wall or posts behind it; these replace the old labels that
	# visibly hovered over the level when viewed from a distance.
	WorldSurface.box(self, Vector3(22.0, 1.45, 0.12), Vector3(60, 3.45, 9.18), "sign_back", false)
	WorldSurface.label(self, "DUST QUARTER", Vector3(60, 3.45, 9.26), Color("ffe0a6"), 68)
	WorldSurface.box(self, Vector3(0.12, 1.3, 12.0), Vector3(123.18, 3.25, 60), "sign_back", false)
	var gate_label := WorldSurface.label(self, "SUN GATE  /  3 SWITCHES", Vector3(123.26, 3.25, 60), Color("8ce3dc"), 30)
	gate_label.rotation.y = -PI / 2.0
	_signpost(Vector3(60, 0, 63), "← AMBER COURT     MARKET ↑     AZURE COURT →")

func _signpost(at: Vector3, text: String) -> void:
	for x in [-2.6, 2.6]:
		WorldSurface.box(self, Vector3(0.12, 2.4, 0.12), at + Vector3(x, 1.2, 0), "dark_wood", false)
	WorldSurface.box(self, Vector3(6.2, 1.05, 0.14), at + Vector3.UP * 2.15, "sign_back", false)
	WorldSurface.label(self, text, at + Vector3(0, 2.15, 0.09), Color("f4d3a0"), 20)

func _environment() -> void:
	env = WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("315f86") if not arena_mode else Color("512e42")
	sky_material.sky_horizon_color = Color("91b6c5") if not arena_mode else Color("e0795d")
	sky_material.ground_bottom_color = Color("65442f")
	sky_material.ground_horizon_color = Color("91b6c5") if not arena_mode else Color("b98255")
	sky_material.sun_angle_max = 6.0
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d6ad7c") if not arena_mode else Color("d8967f")
	environment.ambient_light_energy = 0.20 if not arena_mode else 0.34
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("bd8c60") if not arena_mode else Color("9f554e")
	environment.fog_density = 0.0008 if not arena_mode else 0.0028
	env.environment = environment
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28 if not arena_mode else 24, 0)
	sun.light_color = Color("fff0c6") if not arena_mode else Color("ffb17d")
	sun.light_energy = 0.58 if not arena_mode else 0.78
	sun.directional_shadow_max_distance = 135.0
	add_child(sun)

func apply_quality() -> void:
	super.apply_quality()
	if is_instance_valid(sun):
		sun.shadow_enabled = Settings.quality > 0

func hud_location(at: Vector3) -> String:
	return ("SUN RING / " if arena_mode else "DUST QUARTER / ") + zone_at(at)
