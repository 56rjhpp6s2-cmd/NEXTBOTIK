class_name WorldSurface
extends RefCounted
## Shared materials with a generated concrete texture; reused by every tile.
static var cache: Dictionary = {}

static func material(kind: String) -> StandardMaterial3D:
	if cache.has(kind):
		return cache[kind]
	var m = StandardMaterial3D.new()
	var colors = {"concrete": Color("737d7b"), "floor": Color("424d4e"), "ceiling": Color("343c3c"), "yellow": Color("aaa17c"), "carpet": Color("696c4f"), "metal": Color("34454c"), "rust": Color("6b4937"), "dark": Color("141c21"), "stripe": Color("c69c46"), "red": Color("9b3634"), "safe": Color("255b58"), "white": Color("c9d7cc"), "grass": Color("698b49"), "paving": Color("8f8a79"), "brick": Color("a17762"), "pool_tile": Color("729a9f"), "retaining": Color("87928d"), "sand": Color("b99561"), "arena_sand": Color("ad714d"), "sandstone": Color("bd955d"), "arena_wall": Color("743e3b"), "plaster": Color("d8cbae"), "terracotta": Color("92503e"), "mosaic": Color("438c91"), "awning": Color("8f3543"), "wood": Color("62442f"), "dark_wood": Color("382a25"), "ochre_stucco": Color("b87842"), "blue_stucco": Color("527f89"), "rose_stucco": Color("9b5d58"), "cream_stucco": Color("c7b389"), "stone_trim": Color("8f7655"), "courtyard_tile": Color("4e8d8a"), "roof_tile": Color("577b78"), "foliage": Color("4d7045"), "window": Color("263c43"), "sign_back": Color("4a352c")}
	m.albedo_color = colors.get(kind, Color.GRAY)
	m.roughness = 0.87
	if kind in ["metal", "rust", "dark", "window"]:
		m.metallic = 0.5
		m.roughness = 0.55
	if kind in ["concrete", "floor", "yellow", "carpet", "ceiling", "grass", "paving", "pool_tile", "retaining", "sand", "arena_sand", "sandstone", "arena_wall", "plaster", "terracotta", "wood", "dark_wood", "ochre_stucco", "blue_stucco", "rose_stucco", "cream_stucco", "stone_trim", "courtyard_tile", "roof_tile", "foliage"]:
		var subtle_texture := kind in ["sandstone", "ochre_stucco", "blue_stucco", "rose_stucco", "cream_stucco", "stone_trim"]
		var noise = FastNoiseLite.new()
		noise.seed = 52
		noise.frequency = 0.12 if subtle_texture else 0.065
		var tex = NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.noise = noise
		if kind in ["grass", "paving", "pool_tile", "retaining", "sand", "arena_sand", "sandstone", "arena_wall", "plaster", "terracotta", "wood", "dark_wood", "ochre_stucco", "blue_stucco", "rose_stucco", "cream_stucco", "stone_trim", "courtyard_tile", "roof_tile", "foliage"]:
			var ramp = Gradient.new()
			ramp.colors = PackedColorArray([Color(0.84, 0.84, 0.84), Color(0.99, 0.99, 0.99)]) if subtle_texture else PackedColorArray([Color(0.7, 0.7, 0.7), Color(0.97, 0.97, 0.97)])
			tex.color_ramp = ramp
		m.albedo_texture = tex
		m.uv1_scale = Vector3(2, 2, 2)
	if kind == "brick":
		var image = Image.create(128, 128, false, Image.FORMAT_RGB8)
		for y in range(128):
			for x in range(128):
				var mortar = y % 16 < 2 or (x + (16 if (y / 16) % 2 == 0 else 0)) % 32 < 2
				var shade = 0.45 if mortar else 0.82 + sin(x * 7.0 + y * 13.0) * 0.12
				image.set_pixel(x, y, Color(shade, shade, shade))
		m.albedo_texture = ImageTexture.create_from_image(image)
		m.uv1_scale = Vector3(3, 3, 3)
	if kind == "water":
		m.albedo_color = Color(0.24, 0.5, 0.58, 0.65)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.16
		m.metallic = 0.25
	if kind in ["glow", "emergency", "green"]:
		m.albedo_color = {"glow": Color("d8edc2"), "emergency": Color("f65640"), "green": Color("78e0c3")}[kind]
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 2.5
	cache[kind] = m
	return m

static func box(parent: Node3D, size: Vector3, at: Vector3, kind: String, solid: bool = true) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.position = at
	parent.add_child(root)
	var visual = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material(kind)
	root.add_child(visual)
	if solid:
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		root.add_child(collision)
	return root

static func label(parent: Node3D, text: String, at: Vector3, color: Color = Color("b4d5c6"), size: int = 48) -> Label3D:
	var sign_label = Label3D.new()
	sign_label.text = text
	sign_label.position = at
	sign_label.font_size = size
	sign_label.pixel_size = 0.009
	sign_label.modulate = color
	sign_label.outline_size = 3
	sign_label.no_depth_test = false
	parent.add_child(sign_label)
	return sign_label

static func batch_static(root: Node3D) -> int:
	var groups: Dictionary = {}
	var chunk_size := float(root.get_meta("static_batch_chunk", 24.0))
	_collect_meshes(root, groups, chunk_size)
	var unit = BoxMesh.new()
	unit.size = Vector3.ONE
	for key in groups:
		var entry = groups[key]
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = unit
		multimesh.instance_count = entry.meshes.size()
		var instance = MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = entry.material
		root.add_child(instance)
		for i in range(entry.meshes.size()):
			var visual = entry.meshes[i]
			var transform = root.global_transform.affine_inverse() * visual.global_transform
			transform.basis = transform.basis.scaled_local(visual.mesh.size)
			multimesh.set_instance_transform(i, transform)
			visual.queue_free()
	return groups.size()

static func _collect_meshes(node: Node, groups: Dictionary, chunk_size: float = 24.0) -> void:
	if node.get_meta("dynamic_geometry", false):
		return
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			var chunk = (child.global_position / chunk_size).floor()
			var key = str(chunk) + "/" + str(child.material_override.get_instance_id())
			if not groups.has(key):
				groups[key] = {"material": child.material_override, "meshes": []}
			groups[key].meshes.append(child)
		else:
			_collect_meshes(child, groups, chunk_size)
