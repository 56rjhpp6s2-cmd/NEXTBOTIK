extends Control
var weapon

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if weapon == null:
		return
	var center = size / 2.0
	var aiming: bool = weapon.player.view.aiming
	var gap: float = (3.0 if aiming else 7.0) + weapon.cooldown_remaining * 13.0
	var ink = Color(0.86, 0.95, 0.91, 0.85)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + direction * gap, center + direction * (gap + 6.0), Color(0, 0, 0, 0.8), 3.5, true)
		draw_line(center + direction * gap, center + direction * (gap + 6.0), ink, 1.5, true)
	draw_circle(center, 1.3, ink)
	if weapon.hit_time > 0.0:
		var tint = Color("f78b79") if weapon.hit_lethal else Color("dcfff1")
		tint.a = clampf(weapon.hit_time / 0.12, 0.0, 1.0)
		for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(center + direction * 5.0, center + direction * 12.0, tint, 2.0, true)
