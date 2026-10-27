class_name ProceduralGenerationConfig
extends Resource
## Map complexity is deliberately independent from the selected AI difficulty.

@export_group("Room count")
@export_range(4, 80, 1) var level_four_rooms: int = 15
@export_range(0, 20, 1) var rooms_per_level: int = 5
@export_range(4, 100, 1) var maximum_rooms: int = 55
@export_range(0, 10, 1) var late_level_room_step: int = 3

@export_group("Generation limits")
@export_range(1, 32, 1) var generation_retries: int = 12
@export_range(4, 128, 1) var placement_attempts: int = 42
@export_range(2, 30, 1) var minimum_exit_graph_distance: int = 5
@export_range(0.0, 0.5, 0.01) var rare_room_chance: float = 0.09

@export_group("Progression caps")
@export_range(1.0, 3.0, 0.01) var nextbot_speed_cap_multiplier: float = 2.0
@export_range(1, 12, 1) var maximum_nextbots: int = 8
@export_range(0.05, 0.5, 0.01) var minimum_lighting: float = 0.10

func room_count_for_level(level: int) -> int:
	if level <= 4:
		return mini(level_four_rooms, maximum_rooms)
	if level <= 8:
		return mini(level_four_rooms + (level - 4) * rooms_per_level, maximum_rooms)
	return mini(level_four_rooms + 4 * rooms_per_level + (level - 8) * late_level_room_step, maximum_rooms)

func lighting_for_level(level: int) -> float:
	var authored = 1.0
	var table = {4: 0.80, 5: 0.65, 6: 0.50, 7: 0.35, 8: 0.25, 9: 0.15}
	if level <= 3:
		return authored
	return maxf(minimum_lighting, float(table.get(level, minimum_lighting)))

func speed_for_level(level: int) -> float:
	if level <= 3:
		return 1.0
	if level <= 10:
		return 1.0 + float(level - 3) * 0.10
	# Diminishing returns approach the configurable cap without an endless
	# exponential arms race against the player's finite movement speed.
	var extra = (nextbot_speed_cap_multiplier - 1.7) * (1.0 - exp(-float(level - 10) * 0.18))
	return minf(nextbot_speed_cap_multiplier, 1.7 + extra)
