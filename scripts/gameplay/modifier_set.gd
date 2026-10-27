class_name GameplayModifierSet
extends RefCounted
## Composable Mayhem upgrades. Weapon/enemy code consumes these values without
## knowing which upgrade produced them.

const DEFINITIONS := {
	"damage": {"title": "HEAVY PNG", "description": "+35% projectile damage"},
	"rapid": {"title": "QUICK HANDS", "description": "-20% throw cooldown"},
	"double": {"title": "DUPLICATE FILE", "description": "+1 projectile per throw"},
	"explosive": {"title": "CORRUPTED PNG", "description": "+1.8 m explosion radius"},
	"freezing": {"title": "FROZEN FRAME", "description": "+0.8 s stun"},
	"piercing": {"title": "LOSSLESS", "description": "+1 enemy pierced"},
	"ricochet": {"title": "BOUNCE BUFFER", "description": "+1 wall ricochet"},
	"movement": {"title": "OVERCLOCK", "description": "+6% movement speed"},
	"shield": {"title": "FIREWALL", "description": "+1 lethal-hit shield"},
	"critical": {"title": "CRITICAL FORMAT", "description": "+10% critical chance"},
}

var damage_multiplier: float = 1.0
var cooldown_multiplier: float = 1.0
var projectile_count: int = 1
var explosion_radius: float = 0.0
var freeze_seconds: float = 0.0
var piercing: int = 0
var ricochets: int = 0
var movement_multiplier: float = 1.0
var shields: int = 0
var critical_chance: float = 0.0
var acquired: Array[String] = []

func reset() -> void:
	damage_multiplier = 1.0
	cooldown_multiplier = 1.0
	projectile_count = 1
	explosion_radius = 0.0
	freeze_seconds = 0.0
	piercing = 0
	ricochets = 0
	movement_multiplier = 1.0
	shields = 0
	critical_chance = 0.0
	acquired.clear()

func apply(upgrade: String) -> bool:
	if not DEFINITIONS.has(upgrade):
		return false
	acquired.append(upgrade)
	match upgrade:
		"damage": damage_multiplier *= 1.35
		"rapid": cooldown_multiplier = maxf(0.35, cooldown_multiplier * 0.8)
		"double": projectile_count = mini(4, projectile_count + 1)
		"explosive": explosion_radius = minf(5.0, explosion_radius + 1.8)
		"freezing": freeze_seconds = minf(3.0, freeze_seconds + 0.8)
		"piercing": piercing = mini(4, piercing + 1)
		"ricochet": ricochets = mini(4, ricochets + 1)
		"movement": movement_multiplier = minf(1.30, movement_multiplier * 1.06)
		"shield": shields = mini(3, shields + 1)
		"critical": critical_chance = minf(0.5, critical_chance + 0.1)
	return true

func consume_shield() -> bool:
	if shields <= 0:
		return false
	shields -= 1
	return true

func choices(rng: RandomNumberGenerator, count: int = 3) -> Array[String]:
	var available: Array[String] = []
	for key in DEFINITIONS:
		available.append(key)
	for index in range(available.size() - 1, 0, -1):
		var swap = rng.randi_range(0, index)
		var value = available[index]
		available[index] = available[swap]
		available[swap] = value
	return available.slice(0, mini(count, available.size()))

