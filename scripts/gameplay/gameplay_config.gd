class_name GameplayConfig
extends Resource
## Central tuning for the mode/event layer. Existing movement and procedural
## resources remain authoritative for their own systems.

@export_group("Arcade")
@export_range(30.0, 900.0, 1.0) var arcade_round_seconds: float = 300.0
@export_range(1, 12, 1) var arcade_starting_nextbots: int = 2
@export_range(1, 16, 1) var arcade_maximum_nextbots: int = 7
@export var arcade_survival_score_per_second: float = 10.0
@export var arcade_speed_bonus_threshold: float = 9.0
@export var arcade_close_escape_distance: float = 5.0

@export_group("PNG Mayhem")
@export_range(1, 20, 1) var mayhem_base_wave_size: int = 3
@export_range(1, 8, 1) var mayhem_wave_growth: int = 1
@export_range(1, 40, 1) var mayhem_maximum_wave_size: int = 18
@export_range(2, 10, 1) var mayhem_boss_interval: int = 5
@export var mayhem_health_growth: float = 0.16
@export var mayhem_speed_growth: float = 0.035
@export var boss_health: float = 10000.0

@export_group("Bossfight")
@export var bossfight_base_boss_health: float = 4000.0
@export var bossfight_boss_health_growth: float = 500.0
@export var bossfight_enemy_health_growth: float = 25.0
@export_range(0.0, 0.25, 0.005) var bossfight_enemy_speed_growth: float = 0.08
@export_range(1.0, 3.0, 0.05) var bossfight_enemy_speed_cap: float = 1.65
@export_range(1, 12, 1) var bossfight_starting_nextbots: int = 2
@export_range(1, 16, 1) var bossfight_maximum_nextbots: int = 8

@export_group("Sandbox")
@export_range(0.5, 30.0, 0.5) var sandbox_auto_spawn_interval: float = 4.0
@export_range(1, 32, 1) var sandbox_auto_spawn_limit: int = 12

@export_group("Events")
@export_range(10.0, 600.0, 1.0) var first_event_delay: float = 45.0
@export_range(10.0, 900.0, 1.0) var event_cooldown_min: float = 75.0
@export_range(10.0, 900.0, 1.0) var event_cooldown_max: float = 130.0
@export_range(5.0, 180.0, 1.0) var event_duration: float = 38.0
@export_range(0.5, 10.0, 0.1) var event_warning_seconds: float = 3.0
@export_range(1, 24, 1) var event_enemy_budget: int = 10

