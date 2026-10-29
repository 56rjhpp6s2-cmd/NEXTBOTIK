class_name GameplayModifierSet
extends RefCounted
## Data-driven run rewards. Combat and movement consume the calculated fields;
## adding a reward normally only requires another definition and one effect entry.

const RARITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary"]
const RARITY_WEIGHTS := {"common": 42.0, "uncommon": 29.0, "rare": 17.0, "epic": 9.0, "legendary": 3.0}
const RARITY_COLORS := {
	"common": Color("aab2b6"), "uncommon": Color("73dc8c"), "rare": Color("62a9ff"),
	"epic": Color("c37aff"), "legendary": Color("ffd15c"),
}

const DEFINITIONS := {
	"damage": {"title": "HEAVY PNG", "rarity": "common", "category": "PNG UPGRADE", "description": "+25% projectile damage", "stats": "Damage  +25%", "max_stacks": 5},
	"rapid": {"title": "QUICK HANDS", "rarity": "common", "category": "PNG UPGRADE", "description": "Throw PNGs 15% faster", "stats": "Cooldown  -15%", "max_stacks": 4},
	"velocity": {"title": "FIBER LINK", "rarity": "common", "category": "PNG UPGRADE", "description": "Faster, longer-range PNGs", "stats": "Velocity  +18%  /  Range  +10%", "max_stacks": 3},
	"movement": {"title": "OVERCLOCK", "rarity": "common", "category": "MOVEMENT", "description": "Move faster in every stance", "stats": "Movement speed  +6%", "max_stacks": 4},
	"air_control": {"title": "AIR ROUTER", "rarity": "uncommon", "category": "MOVEMENT", "description": "Stronger Quake-style air strafing", "stats": "Air acceleration  +18%", "max_stacks": 3},
	"slide": {"title": "TEFLON KNEES", "rarity": "uncommon", "category": "MOVEMENT", "description": "Slides keep momentum for longer", "stats": "Slide friction  -18%", "max_stacks": 3},
	"jump": {"title": "SPRING LOADED", "rarity": "uncommon", "category": "MOVEMENT", "description": "Jump and wall-jump higher", "stats": "Jump velocity  +8%", "max_stacks": 3},
	"critical": {"title": "CRITICAL FORMAT", "rarity": "uncommon", "category": "PNG UPGRADE", "description": "Chance to deal double damage", "stats": "Critical chance  +10%", "max_stacks": 4},
	"hitbox": {"title": "WIDE FORMAT", "rarity": "uncommon", "category": "PNG UPGRADE", "description": "Larger projectile collision volume", "stats": "Projectile hitbox  +20%", "max_stacks": 3},
	"double": {"title": "DUPLICATE FILE", "rarity": "rare", "category": "PNG UPGRADE", "description": "Throw one additional PNG", "stats": "Projectiles  +1", "max_stacks": 3},
	"freezing": {"title": "FROZEN FRAME", "rarity": "rare", "category": "PNG UPGRADE", "description": "Hits briefly stun Nextbots", "stats": "Stun  +0.7 seconds", "max_stacks": 4},
	"piercing": {"title": "LOSSLESS", "rarity": "rare", "category": "PNG UPGRADE", "description": "PNG passes through another enemy", "stats": "Piercing targets  +1", "max_stacks": 3},
	"ricochet": {"title": "BOUNCE BUFFER", "rarity": "rare", "category": "PNG UPGRADE", "description": "PNG ricochets from one wall", "stats": "Wall ricochets  +1", "max_stacks": 3},
	"shield": {"title": "FIREWALL", "rarity": "rare", "category": "DEFENSE", "description": "Blocks one otherwise lethal catch", "stats": "Lethal-hit shields  +1", "max_stacks": 3},
	"explosive": {"title": "CORRUPTED PNG", "rarity": "epic", "category": "PNG UPGRADE", "description": "Hits damage nearby Nextbots", "stats": "Explosion radius  +1.8 m", "max_stacks": 3},
	"fifth_shot": {"title": "FIFTH ELEMENT", "rarity": "epic", "category": "SPECIAL", "description": "Every fifth projectile hits brutally hard", "stats": "Every fifth PNG  x2.5 damage", "max_stacks": 1},
	"slide_damage": {"title": "DRIVE-BY", "rarity": "epic", "category": "SPECIAL", "description": "Projectiles thrown while sliding are empowered", "stats": "Sliding damage  +65%", "max_stacks": 1},
	"air_critical": {"title": "AERIAL CACHE", "rarity": "epic", "category": "SPECIAL", "description": "Fast airborne throws gain critical chance", "stats": "Airborne critical chance  +30%", "max_stacks": 1},
	"death_burst": {"title": "CHAIN REACTION", "rarity": "legendary", "category": "SPECIAL", "description": "Defeated Nextbots burst and damage nearby enemies", "stats": "Death burst  3.8 m / 45 damage", "max_stacks": 1},
	"rapid_launcher": {"title": "PNG MINIGUN", "rarity": "rare", "category": "NEW WEAPON", "description": "Automatic rapid fire with lighter projectiles", "stats": "Damage  12  /  Cooldown  0.10 s", "max_stacks": 1, "weapon": true},
	"spread_blaster": {"title": "SPREADSHOT.EXE", "rarity": "rare", "category": "NEW WEAPON", "description": "A close-range fan of five PNG fragments", "stats": "5 pellets  /  45% damage each", "max_stacks": 1, "weapon": true},
	"heavy_cannon": {"title": "MEME HOWITZER", "rarity": "epic", "category": "NEW WEAPON", "description": "Slow heavy PNG with a built-in blast", "stats": "Damage  x3  /  2.8 m blast  /  0.95 s", "max_stacks": 1, "weapon": true},
	"charged_launcher": {"title": "CHARGEPOSTER", "rarity": "legendary", "category": "NEW WEAPON", "description": "Hold fire, then release a charged PNG", "stats": "Charge up to x3 damage  /  0.25-1.2 s", "max_stacks": 1, "weapon": true},
}

var damage_multiplier := 1.0
var cooldown_multiplier := 1.0
var projectile_count := 1
var explosion_radius := 0.0
var freeze_seconds := 0.0
var piercing := 0
var ricochets := 0
var movement_multiplier := 1.0
var air_acceleration_multiplier := 1.0
var slide_friction_multiplier := 1.0
var jump_multiplier := 1.0
var shields := 0
var critical_chance := 0.0
var velocity_multiplier := 1.0
var range_multiplier := 1.0
var hitbox_multiplier := 1.0
var fifth_shot_multiplier := 1.0
var sliding_damage_multiplier := 1.0
var airborne_critical_bonus := 0.0
var death_explosion_radius := 0.0
var active_weapon := "png_thrower"
var acquired: Array[String] = []
var stacks: Dictionary = {}

func reset() -> void:
	damage_multiplier = 1.0
	cooldown_multiplier = 1.0
	projectile_count = 1
	explosion_radius = 0.0
	freeze_seconds = 0.0
	piercing = 0
	ricochets = 0
	movement_multiplier = 1.0
	air_acceleration_multiplier = 1.0
	slide_friction_multiplier = 1.0
	jump_multiplier = 1.0
	shields = 0
	critical_chance = 0.0
	velocity_multiplier = 1.0
	range_multiplier = 1.0
	hitbox_multiplier = 1.0
	fifth_shot_multiplier = 1.0
	sliding_damage_multiplier = 1.0
	airborne_critical_bonus = 0.0
	death_explosion_radius = 0.0
	active_weapon = "png_thrower"
	acquired.clear()
	stacks.clear()

func stack_count(reward: String) -> int:
	return int(stacks.get(reward, 0))

func can_offer(reward: String) -> bool:
	if not DEFINITIONS.has(reward):
		return false
	var definition: Dictionary = DEFINITIONS[reward]
	if stack_count(reward) >= int(definition.get("max_stacks", 1)):
		return false
	return not (bool(definition.get("weapon", false)) and active_weapon == reward)

func apply(reward: String) -> bool:
	if not can_offer(reward):
		return false
	acquired.append(reward)
	stacks[reward] = stack_count(reward) + 1
	match reward:
		"damage": damage_multiplier *= 1.25
		"rapid": cooldown_multiplier = maxf(0.42, cooldown_multiplier * 0.85)
		"velocity":
			velocity_multiplier = minf(1.65, velocity_multiplier * 1.18)
			range_multiplier = minf(1.45, range_multiplier * 1.10)
		"double": projectile_count = mini(4, projectile_count + 1)
		"explosive": explosion_radius = minf(5.0, explosion_radius + 1.8)
		"freezing": freeze_seconds = minf(3.0, freeze_seconds + 0.7)
		"piercing": piercing = mini(4, piercing + 1)
		"ricochet": ricochets = mini(4, ricochets + 1)
		"movement": movement_multiplier = minf(1.28, movement_multiplier * 1.06)
		"air_control": air_acceleration_multiplier = minf(1.6, air_acceleration_multiplier * 1.18)
		"slide": slide_friction_multiplier = maxf(0.5, slide_friction_multiplier * 0.82)
		"jump": jump_multiplier = minf(1.25, jump_multiplier * 1.08)
		"shield": shields = mini(3, shields + 1)
		"critical": critical_chance = minf(0.5, critical_chance + 0.1)
		"hitbox": hitbox_multiplier = minf(1.7, hitbox_multiplier * 1.2)
		"fifth_shot": fifth_shot_multiplier = 2.5
		"slide_damage": sliding_damage_multiplier = 1.65
		"air_critical": airborne_critical_bonus = 0.3
		"death_burst": death_explosion_radius = 3.8
		"rapid_launcher", "spread_blaster", "heavy_cannon", "charged_launcher": active_weapon = reward
	return true

func consume_shield() -> bool:
	if shields <= 0:
		return false
	shields -= 1
	return true

func projectile_profile() -> Dictionary:
	var profile := {
		"damage_multiplier": damage_multiplier, "cooldown_multiplier": cooldown_multiplier,
		"count": projectile_count, "explosion_radius": explosion_radius, "freeze_seconds": freeze_seconds,
		"piercing": piercing, "ricochets": ricochets, "critical_chance": critical_chance,
		"velocity_multiplier": velocity_multiplier, "range_multiplier": range_multiplier,
		"hitbox_multiplier": hitbox_multiplier, "fifth_shot_multiplier": fifth_shot_multiplier,
		"sliding_damage_multiplier": sliding_damage_multiplier, "airborne_critical_bonus": airborne_critical_bonus,
		"weapon": active_weapon, "spread": 0.035, "size_multiplier": 1.0,
	}
	match active_weapon:
		"rapid_launcher":
			profile.damage_multiplier *= 0.6
			profile.cooldown_multiplier *= 0.34
			profile.velocity_multiplier *= 1.18
		"spread_blaster":
			profile.damage_multiplier *= 0.45
			profile.cooldown_multiplier *= 1.75
			profile.count = 5 + maxi(0, int(profile.count) - 1)
			profile.spread = 0.095
		"heavy_cannon":
			profile.damage_multiplier *= 3.0
			profile.cooldown_multiplier *= 3.17
			profile.velocity_multiplier *= 0.78
			profile.explosion_radius = maxf(2.8, float(profile.explosion_radius))
			profile.size_multiplier = 1.55
		"charged_launcher":
			profile.cooldown_multiplier *= 1.8
			profile.size_multiplier = 1.25
	return profile

func choices(random: RandomNumberGenerator, count: int = 3) -> Array[String]:
	var pool: Array[String] = []
	for key in DEFINITIONS:
		if can_offer(key):
			pool.append(key)
	var result: Array[String] = []
	while result.size() < count and not pool.is_empty():
		var total := 0.0
		for key in pool:
			total += float(RARITY_WEIGHTS.get(str(DEFINITIONS[key].rarity), 1.0))
		var roll := random.randf() * total
		var chosen := pool[0]
		for key in pool:
			roll -= float(RARITY_WEIGHTS.get(str(DEFINITIONS[key].rarity), 1.0))
			if roll <= 0.0:
				chosen = key
				break
		result.append(chosen)
		pool.erase(chosen)
	return result

func snapshot() -> Dictionary:
	return {"acquired": acquired.duplicate(), "shields": shields}

func restore(data: Dictionary) -> void:
	reset()
	for reward in data.get("acquired", []):
		apply(str(reward))
	shields = clampi(int(data.get("shields", shields)), 0, 3)

static func rarity_color(reward: String) -> Color:
	if not DEFINITIONS.has(reward):
		return Color.WHITE
	return RARITY_COLORS.get(str(DEFINITIONS[reward].rarity), Color.WHITE)
