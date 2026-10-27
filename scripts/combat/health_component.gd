class_name HealthComponent
extends Node
## One authoritative health value per actor. Death is latched before signals fire.
signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node, point: Vector3)
signal died(source: Node)
@export var max_health: float = 100.0
@export var regeneration_enabled: bool = false
@export var regeneration_per_second: float = 5.0
var current_health: float = 100.0
var dead: bool = false

func _ready() -> void:
	reset(max_health)

func reset(maximum: float = 100.0) -> void:
	max_health = maxf(1.0, maximum)
	current_health = max_health
	dead = false
	health_changed.emit(current_health, max_health)

func apply_damage(amount: float, source: Node = null, point: Vector3 = Vector3.ZERO) -> float:
	if dead or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var applied = minf(current_health, amount)
	current_health = maxf(0.0, current_health - applied)
	dead = current_health <= 0.0
	health_changed.emit(current_health, max_health)
	damaged.emit(applied, source, point)
	if dead:
		died.emit(source)
	return applied

func _physics_process(delta: float) -> void:
	if regeneration_enabled and not dead and current_health < max_health:
		current_health = minf(max_health, current_health + maxf(0.0, regeneration_per_second) * delta)
		health_changed.emit(current_health, max_health)
