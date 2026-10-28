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
		menu_view_position = Vector3(65, 24, 132)
		menu_view_rotation = Vector3(-0.2, -2.72, 0)
		spawn_cells = [Vector3i(10, 0, 11), Vector3i(3, 0, 4), Vector3i(19, 0, 19), Vector3i(17, 0, 4)]

func _layout() -> void:
	if arena_mode:
		for x in range(-10, 11):
			for z in range(-10, 11):
				if Vector2(x, z).length() <= 10.25:
					tiles[Vector3i(x, 0, z)] = {"zone": "SUN RING" if Vector2(x, z).length() > 6.5 else "BOSS CIRCLE"}
		return
	# Four looping flanks surround a broad central route. Covered passages and
	# open sites create readable choices for both parkour and navigation AI.
	_rect(2, 20, 10, 12, 0, "MID PROMENADE")
	_rect(9, 12, 2, 20, 0, "CENTRAL ARCHES")
	_rect(2, 8, 3, 8, 0, "AMBER COURTYARD")
	_rect(13, 20, 14, 20, 0, "AZURE COURTYARD")
	_rect(2, 5, 7, 15, 0, "WEST ALLEY")
	_rect(16, 20, 6, 15, 0, "EAST ALLEY")
	_rect(4, 10, 18, 20, 0, "PALACE WALK")
	_rect(12, 18, 2, 5, 0, "MARKET HALL")
	_rect(2, 20, 2, 3, 0, "NORTH RING")
	_rect(2, 20, 19, 20, 0, "SOUTH RING")
	_rect(2, 3, 2, 20, 0, "WEST RING")
	_rect(19, 20, 2, 20, 0, "EAST RING")
	_rect(6, 9, 6, 7, 0, "UNDERPASS")
	_rect(12, 16, 6, 8, 0, "APARTMENTS")
	_rect(6, 8, 13, 17, 0, "RAMPART PASS")
	_rect(13, 15, 11, 15, 0, "CATWALK COURT")

func nav_blocked(_key: Vector3i) -> bool:
	return false

func _is_indoor(zone: String) -> bool:
	return zone in ["MARKET HALL", "PALACE WALK", "UNDERPASS", "APARTMENTS"]

func _tile(key: Vector3i) -> void:
	var p := center(key)
	var zone: String = tiles[key].zone
	var indoor := not arena_mode and _is_indoor(zone)
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var floor_kind := "arena_sand" if arena_mode else ("terracotta" if "COURTYARD" in zone else "sand")
	WorldSurface.box(root, Vector3(CELL, 0.3, CELL), Vector3(0, -0.15, 0), floor_kind)
	if indoor:
		WorldSurface.box(root, Vector3(CELL, 0.2, CELL), Vector3(0, 4.15, 0), "plaster")
	for direction in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if neighbor(key, direction) != null:
			continue
		var wall_height := 5.4 if arena_mode else 4.8
		var size := Vector3(0.35, wall_height, CELL + 0.12) if direction.x != 0 else Vector3(CELL + 0.12, wall_height, 0.35)
		var at := Vector3(direction.x * CELL / 2.0, wall_height / 2.0, direction.y * CELL / 2.0)
		WorldSurface.box(root, size, at, "arena_wall" if arena_mode else ("plaster" if indoor else "sandstone"))
		WorldSurface.box(root, Vector3(size.x + 0.04, 0.12, size.z + 0.04), at + Vector3.UP * (wall_height / 2.0 - 0.08), "mosaic", false)
	if not arena_mode and (key.x * 2 + key.z) % 9 == 0:
		_add_lantern(p + Vector3.UP * (3.5 if indoor else 2.8), indoor)
	if not arena_mode and "COURTYARD" in zone and (key.x + key.z) % 5 == 0:
		WorldSurface.box(root, Vector3(2.4, 0.025, 2.4), Vector3(0, 0.02, 0), "mosaic", false)

func _obstacle(size: Vector3, at: Vector3, material: String) -> Node3D:
	var body := WorldSurface.box(self, size, at, material)
	nav_obstacles.append(AABB(at - size / 2.0, size))
	return body

func _props() -> void:
	if arena_mode:
		_build_arena_props()
		return
	# Low cover preserves long movement lines while providing fair ways to break
	# sight during a chase. Every obstacle is included in the generated navmesh.
	for at in [Vector3(31, 1.0, 30), Vector3(43, 1.0, 38), Vector3(91, 1.0, 102), Vector3(106, 1.0, 92), Vector3(69, 1.0, 67)]:
		var crate := _obstacle(Vector3(2.4, 2.0, 2.4), at, "wood")
		WorldSurface.box(crate, Vector3(2.46, 0.08, 2.46), Vector3(0, 0.7, 0), "metal", false)
	for at in [Vector3(48, 0.55, 66), Vector3(78, 0.55, 66), Vector3(18, 0.55, 72), Vector3(114, 0.55, 54)]:
		_obstacle(Vector3(7.0, 1.1, 0.8), at, "sandstone")
	# Dense building masses split the broad district into a central lane and two
	# flanks. Wide gaps around every block keep several chase loops available.
	for entry in [
		{"size": Vector3(13, 5.4, 23), "at": Vector3(36, 2.7, 66), "name": "WEST KASBAH"},
		{"size": Vector3(13, 5.4, 23), "at": Vector3(96, 2.7, 66), "name": "EAST KASBAH"},
		{"size": Vector3(11, 6.8, 13), "at": Vector3(66, 3.4, 96), "name": "PALACE TOWER"},
	]:
		var building := _obstacle(entry.size, entry.at, "plaster")
		WorldSurface.box(building, Vector3(entry.size.x + 0.35, 0.18, entry.size.z + 0.35), Vector3(0, entry.size.y / 2.0 + 0.08, 0), "mosaic", false)
		WorldSurface.label(self, entry.name, entry.at + Vector3(0, entry.size.y / 2.0 + 0.7, entry.size.z / 2.0 + 0.2), Color("76513c"), 25)
	# Paired columns and lintels suggest open arches while leaving a broad gap for
	# wall jumps, slides and Nextbot navigation.
	for arch_center in [Vector3(60, 0, 48), Vector3(72, 0, 84), Vector3(54, 0, 108)]:
		for side in [-1.0, 1.0]:
			_obstacle(Vector3(0.8, 4.5, 0.8), arch_center + Vector3(side * 3.0, 2.25, 0), "sandstone")
		WorldSurface.box(self, Vector3(6.8, 0.8, 0.8), arch_center + Vector3(0, 4.1, 0), "sandstone")
	# A central tiled well and market awnings establish the warm FPS-map identity.
	_obstacle(Vector3(4.2, 1.2, 4.2), Vector3(63, 0.6, 66), "mosaic")
	for x in [76.0, 88.0, 100.0]:
		WorldSurface.box(self, Vector3(7.5, 0.12, 4.4), Vector3(x, 3.1, 18), "awning", false)
	for at in [Vector3(18, 2.8, 27), Vector3(108, 2.8, 99), Vector3(60, 2.8, 116)]:
		WorldSurface.box(self, Vector3(0.7, 5.6, 0.7), at, "sandstone")

	var candidates := [
		{"cell": Vector3i(3, 0, 4), "offset": Vector3(-2.3, 1.1, 0)},
		{"cell": Vector3i(7, 0, 7), "offset": Vector3(0, 1.1, -2.3)},
		{"cell": Vector3i(4, 0, 13), "offset": Vector3(-2.3, 1.1, 0)},
		{"cell": Vector3i(7, 0, 16), "offset": Vector3(2.3, 1.1, 0)},
		{"cell": Vector3i(8, 0, 19), "offset": Vector3(0, 1.1, 2.3)},
		{"cell": Vector3i(13, 0, 7), "offset": Vector3(0, 1.1, -2.3)},
		{"cell": Vector3i(17, 0, 4), "offset": Vector3(2.3, 1.1, 0)},
		{"cell": Vector3i(18, 0, 10), "offset": Vector3(2.3, 1.1, 0)},
		{"cell": Vector3i(15, 0, 16), "offset": Vector3(0, 1.1, 2.3)},
		{"cell": Vector3i(19, 0, 19), "offset": Vector3(2.3, 1.1, 0)},
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
	_add_item("exit", Vector3i(20, 0, 11), Vector3(2.3, 1.2, 0), "SUN GATE")
	for cell in [Vector3i(3, 0, 11), Vector3i(10, 0, 3), Vector3i(19, 0, 15), Vector3i(8, 0, 20)]:
		_add_item("battery", cell, Vector3(0, 0.6, 0), "BATTERY")
	for cell in [Vector3i(5, 0, 8), Vector3i(16, 0, 8)]:
		_add_item("hide", cell, Vector3(0, 0, 0), "LOCKER")

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
	WorldSurface.label(self, "DUST QUARTER", Vector3(63, 6.2, 12), Color("ffe0a6"), 84)
	WorldSurface.label(self, "THREE SWITCHES  →  SUN GATE", Vector3(116.5, 3.2, 66), Color("8ce3dc"), 38).rotation.y = -PI / 2.0
	WorldSurface.label(self, "AMBER COURT  ←     MID     →  AZURE COURT", Vector3(66, 3.2, 61), Color("f4d3a0"), 31)
	WorldSurface.label(self, "MARKET / APARTMENTS", Vector3(90, 3.2, 31), Color("e7c58d"), 29)

func _environment() -> void:
	env = WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("426e9e") if not arena_mode else Color("512e42")
	sky_material.sky_horizon_color = Color("e9c78e") if not arena_mode else Color("e0795d")
	sky_material.ground_bottom_color = Color("8f6944")
	sky_material.ground_horizon_color = Color("d0aa72")
	sky_material.sun_angle_max = 6.0
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d7c09c") if not arena_mode else Color("d8967f")
	environment.ambient_light_energy = 0.27 if not arena_mode else 0.34
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("d6b47e") if not arena_mode else Color("9f554e")
	environment.fog_density = 0.0015 if not arena_mode else 0.0028
	env.environment = environment
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28 if not arena_mode else 24, 0)
	sun.light_color = Color("fff0c6") if not arena_mode else Color("ffb17d")
	sun.light_energy = 0.68 if not arena_mode else 0.78
	sun.directional_shadow_max_distance = 135.0
	add_child(sun)

func apply_quality() -> void:
	super.apply_quality()
	if is_instance_valid(sun):
		sun.shadow_enabled = Settings.quality > 0

func hud_location(at: Vector3) -> String:
	return ("SUN RING / " if arena_mode else "DUST QUARTER / ") + zone_at(at)
