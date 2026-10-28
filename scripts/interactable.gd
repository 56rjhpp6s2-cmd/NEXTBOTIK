class_name WorldInteractable
extends Node3D
var kind: String = "battery"
var title: String = ""
var used: bool = false
var active: bool = true
var cell: Vector3i
var indicator: Node3D
var light: OmniLight3D

func _ready() -> void:
	match kind:
		"breaker", "exit":
			WorldSurface.box(self, Vector3(0.65, 1.0, 0.5), Vector3.ZERO, "metal")
			indicator = WorldSurface.box(self, Vector3(0.4, 0.12, 0.53), Vector3(0, 0.2, 0), "emergency", false)
			WorldSurface.label(self, title, Vector3(0, 0.85, 0), Color("dce3cb"), 23)
		"battery":
			indicator = WorldSurface.box(self, Vector3(0.22, 0.35, 0.22), Vector3.ZERO, "green", false)
		"hide":
			WorldSurface.box(self, Vector3(1.05, 2.35, 0.08), Vector3(0, 1.175, 0.46), "metal")
			WorldSurface.box(self, Vector3(1.05, 2.35, 0.05), Vector3(0, 1.175, -0.5), "metal")
			for side in [-1, 1]:
				WorldSurface.box(self, Vector3(0.08, 2.35, 1.0), Vector3(side * 0.485, 1.175, 0), "metal")
			for shelf in [0.04, 2.31]:
				WorldSurface.box(self, Vector3(1.05, 0.08, 1.0), Vector3(0, shelf, 0), "metal")
			WorldSurface.box(self, Vector3(0.04, 0.25, 0.05), Vector3(0.3, 1.2, -0.53), "stripe", false)
			for n in range(4):
				WorldSurface.box(self, Vector3(0.65, 0.025, 0.02), Vector3(0, 1.8 + n * 0.07, -0.51), "dark", false)
	if kind != "hide":
		light = OmniLight3D.new()
		light.light_color = Color("7ad8bd") if kind == "battery" else Color("f17658")
		light.light_energy = 0.45
		light.omni_range = 2.4
		light.position.y = 0.5
		add_child(light)

func prompt(breakers: int) -> String:
	if used:
		return ""
	match kind:
		"breaker": return "[E] RESTORE " + title
		"battery": return "[E] TAKE BATTERY  +45%"
		"hide": return "[E] HIDE IN LOCKER"
		"exit":
			var is_gate := title in ["DESCENT GATE", "SUN GATE"]
			var action = "ENTER NEXT SECTOR" if title == "SUN GATE" else ("DESCEND THROUGH GATE" if is_gate else "CALL SERVICE LIFT")
			var offline = "GATE OFFLINE" if is_gate else "LIFT OFFLINE"
			return "[E] " + action if breakers == 3 else "%s  /  %d OF 3 BREAKERS" % [offline, breakers]
	return ""

func activate() -> void:
	used = true
	if kind == "battery":
		visible = false
	elif kind == "breaker":
		for child in indicator.get_children():
			if child is MeshInstance3D:
				child.material_override = WorldSurface.material("green")
		light.light_color = Color("7ad8bd")

func reset() -> void:
	used = false
	visible = active
	if kind == "breaker":
		for child in indicator.get_children():
			if child is MeshInstance3D:
				child.material_override = WorldSurface.material("emergency")
		light.light_color = Color("f17658")
