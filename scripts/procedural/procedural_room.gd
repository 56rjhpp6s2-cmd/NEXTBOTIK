class_name ProceduralRoomDefinition
extends Node3D
## Metadata-only modular room prefab used by ProceduralLayoutGenerator.
## Vector3i doorway entries store local tile x/z in x/y and direction in z:
## 0 north, 1 east, 2 south, 3 west.

@export var room_type: String = "small_room"
@export var display_name: String = "SMALL ROOM"
@export var dimensions: Vector2i = Vector2i.ONE
@export var tile_cells: Array[Vector2i] = [Vector2i.ZERO]
@export var doorway_cells: Array[Vector3i] = []
@export var spawn_marker_cells: Array[Vector2i] = []
@export_range(0.0, 1.0, 0.01) var light_density: float = 0.45
@export_range(0.0, 4.0, 0.05) var selection_weight: float = 1.0
@export var prop_style: String = "concrete"
@export var safe_room: bool = false
@export var rare: bool = false

func definition() -> Dictionary:
	return {
		"type": room_type,
		"name": display_name,
		"dimensions": dimensions,
		"tiles": tile_cells.duplicate(),
		"doors": doorway_cells.duplicate(),
		"markers": spawn_marker_cells.duplicate(),
		"light_density": light_density,
		"weight": selection_weight,
		"prop_style": prop_style,
		"safe": safe_room,
		"rare": rare,
	}
