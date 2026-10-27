class_name ProceduralLayoutGenerator
extends RefCounted
## Deterministic modular-room generator. Rooms are joined at explicit doorway
## cells; unintended side contacts are rejected, so every opening is traceable.

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const ROOM_SCENES: Array[PackedScene] = [
	preload("res://scenes/procedural/small_room.tscn"),
	preload("res://scenes/procedural/large_hall.tscn"),
	preload("res://scenes/procedural/long_corridor.tscn"),
	preload("res://scenes/procedural/l_corridor.tscn"),
	preload("res://scenes/procedural/t_junction.tscn"),
	preload("res://scenes/procedural/four_way.tscn"),
	preload("res://scenes/procedural/storage_room.tscn"),
	preload("res://scenes/procedural/abandoned_office.tscn"),
	preload("res://scenes/procedural/dark_classroom.tscn"),
	preload("res://scenes/procedural/parking_room.tscn"),
	preload("res://scenes/procedural/maintenance_tunnel.tscn"),
	preload("res://scenes/procedural/dead_end.tscn"),
	preload("res://scenes/procedural/special_room.tscn"),
]
const SPAWN_SCENE: PackedScene = preload("res://scenes/procedural/spawn_room.tscn")
const EXIT_SCENE: PackedScene = preload("res://scenes/procedural/exit_room.tscn")

var rng := RandomNumberGenerator.new()
var config: ProceduralGenerationConfig

func generate(seed_value: int, requested_rooms: int, settings: ProceduralGenerationConfig = null, horror_level: int = 4) -> Dictionary:
	config = settings if settings != null else ProceduralGenerationConfig.new()
	var count = clampi(requested_rooms, 4, config.maximum_rooms)
	for retry in range(config.generation_retries):
		var attempt_seed = seed_value + retry * 104729
		var layout = _attempt(attempt_seed, count, horror_level)
		if layout.get("valid", false):
			layout["requested_seed"] = seed_value
			layout["retry"] = retry
			return layout
	var fallback = _fallback(seed_value, count)
	fallback["requested_seed"] = seed_value
	fallback["retry"] = config.generation_retries
	fallback["fallback"] = true
	return fallback

func _attempt(seed_value: int, count: int, horror_level: int) -> Dictionary:
	rng.seed = seed_value
	var occupied: Dictionary = {}
	var rooms: Array = []
	var open_doors: Array = []
	var links: Array = []
	var spawn_definition = _scene_definition(SPAWN_SCENE)
	_commit(_placement(spawn_definition, Vector2i.ZERO, 0, 0), occupied, rooms, open_doors, links, -1)
	var catalog = _catalog(horror_level)
	var guard: int = 0
	while rooms.size() < count - 1 and not open_doors.is_empty() and guard < count * config.placement_attempts * 3:
		guard += 1
		var target_index = rng.randi_range(0, open_doors.size() - 1)
		var target: Dictionary = open_doors[target_index]
		var placed: bool = false
		for attempt in range(config.placement_attempts):
			var definition = _weighted_definition(catalog)
			var turns = rng.randi_range(0, 3)
			var rotated_doors = _rotated_doors(definition.doors, turns)
			var compatible: Array = []
			for door in rotated_doors:
				if int(door.z) == (int(target.dir) + 2) % 4:
					compatible.append(door)
			if compatible.is_empty():
				continue
			var chosen: Vector3i = compatible[rng.randi_range(0, compatible.size() - 1)]
			var target_cell: Vector2i = target.cell
			var candidate_door = Vector2i(chosen.x, chosen.y)
			var origin = target_cell + DIRS[int(target.dir)] - candidate_door
			var candidate = _placement(definition, origin, turns, rooms.size())
			if not _can_place(candidate, occupied, open_doors, target):
				continue
			_commit(candidate, occupied, rooms, open_doors, links, target_index)
			placed = true
			break
		if not placed:
			open_doors.remove_at(target_index)
	if rooms.size() != count - 1 or open_doors.is_empty():
		return {"valid": false, "reason": "ROOM_EXPANSION_EXHAUSTED", "seed": seed_value}
	var distances = _graph_distances(rooms.size(), links, 0)
	var door_order = open_doors.duplicate()
	door_order.sort_custom(func(a, b): return distances.get(a.room, 0) > distances.get(b.room, 0))
	var exit_definition = _scene_definition(EXIT_SCENE)
	var exit_placed: bool = false
	for target in door_order:
		if int(distances.get(target.room, 0)) < mini(config.minimum_exit_graph_distance, maxi(2, count / 3)):
			continue
		var target_index = _find_door(open_doors, target.cell, target.dir)
		if target_index < 0:
			continue
		for turns in range(4):
			for chosen in _rotated_doors(exit_definition.doors, turns):
				if int(chosen.z) != (int(target.dir) + 2) % 4:
					continue
				var origin: Vector2i = target.cell + DIRS[int(target.dir)] - Vector2i(chosen.x, chosen.y)
				var candidate = _placement(exit_definition, origin, turns, rooms.size())
				if _can_place(candidate, occupied, open_doors, target):
					_commit(candidate, occupied, rooms, open_doors, links, target_index)
					exit_placed = true
					break
			if exit_placed:
				break
		if exit_placed:
			break
	if not exit_placed:
		return {"valid": false, "reason": "NO_DISTANT_EXIT", "seed": seed_value}
	return _finalize(seed_value, occupied, rooms, links)

func _catalog(horror_level: int) -> Array:
	var result: Array = []
	for scene in ROOM_SCENES:
		var definition = _scene_definition(scene)
		if definition.type == "dead_end":
			definition.weight = float(definition.weight) * (1.0 + minf(1.4, float(horror_level - 4) * 0.10))
		elif definition.type == "dark_classroom":
			definition.weight = float(definition.weight) * (1.0 + minf(1.0, float(horror_level - 4) * 0.08))
		var rare_chance = config.rare_room_chance * maxf(0.35, 1.0 - float(horror_level - 4) * 0.05)
		if definition.rare and rng.randf() > rare_chance:
			continue
		result.append(definition)
	return result

func _scene_definition(scene: PackedScene) -> Dictionary:
	var node: ProceduralRoomDefinition = scene.instantiate()
	var result = node.definition()
	node.free()
	return result

func _weighted_definition(catalog: Array) -> Dictionary:
	var total: float = 0.0
	for definition in catalog:
		total += float(definition.weight)
	var roll = rng.randf() * total
	for definition in catalog:
		roll -= float(definition.weight)
		if roll <= 0.0:
			return definition
	return catalog.back()

func _placement(definition: Dictionary, origin: Vector2i, turns: int, id: int) -> Dictionary:
	var tiles: Array[Vector2i] = []
	for tile in definition.tiles:
		tiles.append(origin + _rotate(tile, turns))
	var doors: Array = []
	for door in _rotated_doors(definition.doors, turns):
		doors.append({"cell": origin + Vector2i(door.x, door.y), "dir": int(door.z), "room": id})
	var markers: Array[Vector2i] = []
	for marker in definition.markers:
		markers.append(origin + _rotate(marker, turns))
	return {
		"id": id,
		"type": definition.type,
		"name": definition.name,
		"origin": origin,
		"rotation": turns,
		"tiles": tiles,
		"doors": doors,
		"markers": markers,
		"light_density": definition.light_density,
		"prop_style": definition.prop_style,
		"safe": definition.safe,
	}

func _rotated_doors(doors: Array, turns: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for door in doors:
		var cell = _rotate(Vector2i(door.x, door.y), turns)
		result.append(Vector3i(cell.x, cell.y, (int(door.z) + turns) % 4))
	return result

func _rotate(value: Vector2i, turns: int) -> Vector2i:
	var result = value
	for step in range(posmod(turns, 4)):
		result = Vector2i(-result.y, result.x)
	return result

func _can_place(candidate: Dictionary, occupied: Dictionary, open_doors: Array, target: Dictionary) -> bool:
	var candidate_cells: Dictionary = {}
	var candidate_doors: Dictionary = {}
	for cell in candidate.tiles:
		if occupied.has(cell):
			return false
		candidate_cells[cell] = true
	for door in candidate.doors:
		candidate_doors[_door_key(door.cell, door.dir)] = true
	var intended_cell: Vector2i = target.cell + DIRS[int(target.dir)]
	for cell in candidate.tiles:
		for direction in range(4):
			var other = cell + DIRS[direction]
			if not occupied.has(other):
				continue
			var intended = cell == intended_cell and other == target.cell and direction == (int(target.dir) + 2) % 4
			var loop_door = candidate_doors.has(_door_key(cell, direction)) and _find_door(open_doors, other, (direction + 2) % 4) >= 0
			if not intended and not loop_door:
				return false
	return true

func _commit(candidate: Dictionary, occupied: Dictionary, rooms: Array, open_doors: Array, links: Array, target_index: int) -> void:
	var existing_doors = open_doors.duplicate()
	var connected_candidate: Dictionary = {}
	for door in candidate.doors:
		var other_cell: Vector2i = door.cell + DIRS[int(door.dir)]
		var other_index = _find_door(existing_doors, other_cell, (int(door.dir) + 2) % 4)
		if other_index >= 0:
			var other: Dictionary = existing_doors[other_index]
			links.append({"a": int(other.room), "b": int(candidate.id), "a_cell": other.cell, "b_cell": door.cell})
			connected_candidate[_door_key(door.cell, door.dir)] = true
	for cell in candidate.tiles:
		occupied[cell] = candidate.id
	rooms.append(candidate)
	# Remove every existing doorway consumed by the new room, not just the one
	# selected for expansion; this is how incidental valid loops are retained.
	for index in range(open_doors.size() - 1, -1, -1):
		var old: Dictionary = open_doors[index]
		for door in candidate.doors:
			if old.cell + DIRS[int(old.dir)] == door.cell and int(door.dir) == (int(old.dir) + 2) % 4:
				open_doors.remove_at(index)
				break
	for door in candidate.doors:
		if not connected_candidate.has(_door_key(door.cell, door.dir)):
			open_doors.append(door)

func _find_door(doors: Array, cell: Vector2i, direction: int) -> int:
	for index in range(doors.size()):
		if doors[index].cell == cell and int(doors[index].dir) == direction:
			return index
	return -1

func _door_key(cell: Vector2i, direction: int) -> String:
	return "%d,%d/%d" % [cell.x, cell.y, direction]

func _graph_distances(room_count: int, links: Array, start: int) -> Dictionary:
	var adjacent: Array = []
	adjacent.resize(room_count)
	for index in range(room_count):
		adjacent[index] = []
	for link in links:
		if int(link.a) < room_count and int(link.b) < room_count:
			adjacent[int(link.a)].append(int(link.b))
			adjacent[int(link.b)].append(int(link.a))
	var distances: Dictionary = {start: 0}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current = queue.pop_front()
		for other in adjacent[current]:
			if not distances.has(other):
				distances[other] = int(distances[current]) + 1
				queue.append(other)
	return distances

func _finalize(seed_value: int, occupied: Dictionary, rooms: Array, links: Array) -> Dictionary:
	var distances = _graph_distances(rooms.size(), links, 0)
	if distances.size() != rooms.size():
		return {"valid": false, "reason": "DISCONNECTED_ROOM_GRAPH", "seed": seed_value}
	var tile_seen: Dictionary = {}
	var start_cell: Vector2i = _room_marker(rooms[0])
	var queue: Array[Vector2i] = [start_cell]
	tile_seen[start_cell] = true
	while not queue.is_empty():
		var current = queue.pop_front()
		for direction in DIRS:
			var other = current + direction
			if occupied.has(other) and not tile_seen.has(other):
				tile_seen[other] = true
				queue.append(other)
	if tile_seen.size() != occupied.size():
		return {"valid": false, "reason": "DISCONNECTED_TILES", "seed": seed_value}
	var exit_id = rooms.size() - 1
	var ordered: Array = []
	for room in rooms:
		if int(room.id) not in [0, exit_id]:
			ordered.append(room)
	ordered.sort_custom(func(a, b): return distances.get(a.id, 0) < distances.get(b.id, 0))
	if ordered.size() < 3:
		return {"valid": false, "reason": "NOT_ENOUGH_OBJECTIVE_ROOMS", "seed": seed_value}
	var breaker_rooms: Array = []
	for ratio in [0.38, 0.68, 0.92]:
		var index = clampi(roundi((ordered.size() - 1) * ratio), 0, ordered.size() - 1)
		while breaker_rooms.has(ordered[index]) and index > 0:
			index -= 1
		breaker_rooms.append(ordered[index])
	var breaker_cells: Array[Vector2i] = []
	for room in breaker_rooms:
		breaker_cells.append(_room_marker(room))
	var safe_cells: Array[Vector2i] = []
	for room in rooms:
		if room.safe:
			safe_cells.append(_room_marker(room))
	if safe_cells.is_empty() and ordered.size() > 2:
		safe_cells.append(_room_marker(ordered[ordered.size() / 2]))
	return {
		"valid": true,
		"reason": "VALID",
		"seed": seed_value,
		"fallback": false,
		"rooms": rooms,
		"room_count": rooms.size(),
		"tiles": occupied,
		"links": links,
		"distances": distances,
		"spawn_cell": _room_marker(rooms[0]),
		"exit_cell": _room_marker(rooms[exit_id]),
		"exit_graph_distance": int(distances.get(exit_id, 0)),
		"breaker_cells": breaker_cells,
		"safe_cells": safe_cells,
	}

func _room_marker(room: Dictionary) -> Vector2i:
	if not room.markers.is_empty():
		return room.markers[0]
	return room.tiles[room.tiles.size() / 2]

func _fallback(seed_value: int, count: int) -> Dictionary:
	# Guaranteed connected, non-overlapping chain. It is intentionally simple,
	# but still uses room records and explicit aligned doorway links.
	var occupied: Dictionary = {}
	var rooms: Array = []
	var links: Array = []
	for index in range(count):
		var cells: Array[Vector2i] = []
		var start_x = index * 3
		for x in range(start_x, start_x + 3):
			cells.append(Vector2i(x, 0))
			occupied[Vector2i(x, 0)] = index
		var room_type = "spawn_room" if index == 0 else ("exit_room" if index == count - 1 else "maintenance_tunnel")
		rooms.append({"id": index, "type": room_type, "name": room_type.to_upper(), "origin": Vector2i(start_x, 0), "rotation": 1, "tiles": cells, "doors": [], "markers": [Vector2i(start_x + 1, 0)], "light_density": 0.35, "prop_style": "concrete", "safe": index == count / 2})
		if index > 0:
			links.append({"a": index - 1, "b": index, "a_cell": Vector2i(start_x - 1, 0), "b_cell": Vector2i(start_x, 0)})
	return _finalize(seed_value, occupied, rooms, links)
