class_name PNGImageLoader
extends Node
## Live PNG library. Originals are copied unchanged; previews/textures are bounded.
signal library_changed
signal image_selected(entry: Dictionary)
signal notice(message: String)
const DEFAULTS = {
	"BZ_anomaly.png": "res://assets/projectiles/anomaly.png",
	"BZ_warning.png": "res://assets/projectiles/warning.png",
	"BZ_star.png": "res://assets/projectiles/star.png",
	"Без имени.png": "res://assets/projectiles/Без имени.png"
}
const MAX_BYTES: int = 67108864
const MAX_PIXELS: int = 67108864
var directory: String = "user://projectiles"
var entries: Array[Dictionary] = []
var errors: Array[String] = []
var selected_index: int = 0
var selected_path: String = ""
var cache: Dictionary = {}
var texture_cache: Dictionary = {}
var scan_time: float = 0.0
var directory_ready: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Settings.automated_run():
		directory = ProjectSettings.globalize_path("res://").path_join(".godot/test_projectiles_%s" % Settings.automated_tag())
	directory_ready = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK
	refresh()

func _seed_defaults() -> void:
	if not directory_ready:
		return
	for filename in DEFAULTS:
		var path: String = DEFAULTS[filename]
		var destination = directory.path_join(filename)
		if FileAccess.file_exists(destination):
			continue
		# Source projects copy bytes; exported packs decode their imported textures.
		if FileAccess.file_exists(path):
			var file = FileAccess.open(destination, FileAccess.WRITE)
			if file != null:
				file.store_buffer(FileAccess.get_file_as_bytes(path))
				file.close()
				continue
		var texture = load(path) as Texture2D
		if texture != null:
			texture.get_image().save_png(destination)

func _process(delta: float) -> void:
	scan_time += delta
	if scan_time >= 3.0:
		scan_time = 0.0
		refresh()

func refresh(force: bool = false) -> void:
	_seed_defaults()
	var previous_path = selected_path
	var previous_signature = _signature()
	var previous_errors = ";".join(errors)
	var next_entries: Array[Dictionary] = []
	errors.clear()
	var present: Dictionary = {}
	if directory_ready:
		var files = DirAccess.get_files_at(directory)
		files.sort()
		for filename in files:
			if filename.get_extension().to_lower() != "png":
				continue
			var path = directory.path_join(filename)
			present[path] = true
			var signature = str(FileAccess.get_modified_time(path)) + ":" + str(_file_length(path))
			if force or not cache.has(path) or cache[path].signature != signature:
				texture_cache.erase(path)
				var decoded = _decode(path)
				if decoded.image == null:
					cache[path] = {"signature": signature, "error": decoded.error}
				else:
					var image: Image = decoded.image
					var dimensions = image.get_size()
					_fit(image, 256)
					cache[path] = {"signature": signature, "error": "", "entry": {"path": path, "name": filename.get_basename(), "filename": filename, "dimensions": dimensions, "preview": ImageTexture.create_from_image(image)}}
			if not cache[path].error.is_empty():
				errors.append(filename + ": " + cache[path].error)
			else:
				next_entries.append(cache[path].entry)
	for path in cache.keys():
		if not present.has(path):
			cache.erase(path)
			texture_cache.erase(path)
	# Bundled images remain available even if a user copy is missing or unreadable.
	for filename in DEFAULTS:
		var found: bool = false
		for entry in next_entries:
			if entry.filename == filename:
				found = true
				break
		if not found:
			var path: String = DEFAULTS[filename]
			var texture = load(path) as Texture2D
			if texture != null:
				next_entries.append({"path": path, "name": filename.get_basename(), "filename": filename, "dimensions": Vector2i(texture.get_width(), texture.get_height()), "preview": texture})
	entries = next_entries
	selected_index = 0
	for i in range(entries.size()):
		if entries[i].filename == Settings.DEFAULT_PNG:
			selected_index = i
	for i in range(entries.size()):
		if entries[i].path == previous_path or entries[i].filename == Settings.selected_png:
			selected_index = i
	selected_path = entries[selected_index].path if not entries.is_empty() else ""
	if force or previous_signature != _signature() or previous_errors != ";".join(errors):
		library_changed.emit()
		if not entries.is_empty():
			select(selected_index)

func _signature() -> String:
	var result = ""
	for entry in entries:
		result += entry.path + str(cache.get(entry.path, {}).get("signature", "bundled")) + ";"
	return result

func current_entry() -> Dictionary:
	return entries[selected_index] if not entries.is_empty() else {}

func select(index: int) -> void:
	if entries.is_empty():
		return
	selected_index = posmod(index, entries.size())
	selected_path = entries[selected_index].path
	if Settings.selected_png != entries[selected_index].filename:
		Settings.selected_png = entries[selected_index].filename
		Settings.save()
	image_selected.emit(current_entry())

func select_filename(filename: String) -> void:
	for i in range(entries.size()):
		if entries[i].filename == filename:
			select(i)
			return

func cycle(direction: int) -> void:
	select(selected_index + direction)

func current_texture() -> Texture2D:
	if entries.is_empty():
		return null
	var entry = current_entry()
	if entry.path.begins_with("res://assets/"):
		return load(entry.path) as Texture2D
	if texture_cache.has(entry.path):
		return texture_cache[entry.path]
	var decoded = _decode(entry.path)
	if decoded.image == null:
		notice.emit(decoded.error)
		return entry.preview
	var image: Image = decoded.image
	_fit(image, 2048)
	image.generate_mipmaps()
	var texture = ImageTexture.create_from_image(image)
	if texture_cache.size() >= 4:
		texture_cache.erase(texture_cache.keys()[0])
	texture_cache[entry.path] = texture
	return texture

func import_png(source_path: String) -> Dictionary:
	if not directory_ready:
		return {"ok": false, "message": "Cannot write to the projectiles folder."}
	var decoded = _decode_import(source_path)
	if decoded.image == null:
		return {"ok": false, "message": decoded.error}
	var stem = source_path.get_file().get_basename().validate_filename()
	if stem.is_empty():
		stem = "projectile"
	var destination = directory.path_join(stem + ".png")
	var source_absolute = ProjectSettings.globalize_path(source_path).simplify_path()
	if source_absolute.to_lower() != ProjectSettings.globalize_path(destination).simplify_path().to_lower():
		var suffix: int = 2
		while FileAccess.file_exists(destination):
			destination = directory.path_join(stem + "_%d.png" % suffix)
			suffix += 1
		var error: Error = OK
		if decoded.get("converted", false):
			var image: Image = decoded.image
			error = image.save_png(destination)
		else:
			error = DirAccess.copy_absolute(source_absolute, ProjectSettings.globalize_path(destination))
		if error != OK:
			return {"ok": false, "message": "Could not save PNG: " + error_string(error)}
	refresh(true)
	select_filename(destination.get_file())
	Settings.save()
	return {"ok": true, "path": destination, "converted": decoded.get("converted", false), "message": ("Converted JPEG to PNG: " if decoded.get("converted", false) else "Ready to throw: ") + destination.get_file()}

func _decode_import(path: String) -> Dictionary:
	var extension = path.get_extension().to_lower()
	if extension == "png":
		return _decode(path)
	if extension not in ["jpg", "jpeg"]:
		return {"image": null, "error": "Choose a PNG, JPG, or JPEG image."}
	var length = _file_length(path)
	if length < 4 or length > MAX_BYTES:
		return {"image": null, "error": "JPEG is unreadable or larger than 64 MB."}
	var bytes = FileAccess.get_file_as_bytes(path)
	var dimensions = _jpeg_dimensions(bytes)
	if dimensions.x < 1 or dimensions.y < 1:
		return {"image": null, "error": "This file is not a valid JPEG."}
	if dimensions.x > 16384 or dimensions.y > 16384 or dimensions.x * dimensions.y > MAX_PIXELS:
		return {"image": null, "error": "JPEG dimensions exceed the safe image-memory limit."}
	var image = Image.new()
	if image.load_jpg_from_buffer(bytes) != OK or image.is_empty():
		return {"image": null, "error": "JPEG could not be decoded."}
	return {"image": image, "error": "", "converted": true}

func _jpeg_dimensions(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 4 or bytes[0] != 0xff or bytes[1] != 0xd8:
		return Vector2i.ZERO
	var offset: int = 2
	while offset + 1 < bytes.size():
		if bytes[offset] != 0xff:
			return Vector2i.ZERO
		while offset < bytes.size() and bytes[offset] == 0xff:
			offset += 1
		if offset >= bytes.size():
			return Vector2i.ZERO
		var marker = bytes[offset]
		offset += 1
		if marker == 0xda or marker == 0xd9:
			return Vector2i.ZERO
		if marker == 0x01 or marker == 0xd8 or (marker >= 0xd0 and marker <= 0xd7):
			continue
		if offset + 2 > bytes.size():
			return Vector2i.ZERO
		var segment_length = (int(bytes[offset]) << 8) | int(bytes[offset + 1])
		if segment_length < 2 or offset + segment_length > bytes.size():
			return Vector2i.ZERO
		if marker in [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]:
			if segment_length < 8:
				return Vector2i.ZERO
			var height = (int(bytes[offset + 3]) << 8) | int(bytes[offset + 4])
			var width = (int(bytes[offset + 5]) << 8) | int(bytes[offset + 6])
			return Vector2i(width, height)
		offset += segment_length
	return Vector2i.ZERO

func _decode(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "png":
		return {"image": null, "error": "Choose a PNG file."}
	var length = _file_length(path)
	if length < 45 or length > MAX_BYTES:
		return {"image": null, "error": "PNG is unreadable or larger than 64 MB."}
	var bytes = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 33 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return {"image": null, "error": "This file is not a valid PNG."}
	if bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return {"image": null, "error": "PNG header is invalid."}
	var width = _u32(bytes, 16)
	var height = _u32(bytes, 20)
	if width < 1 or height < 1 or width > 16384 or height > 16384 or width * height > MAX_PIXELS:
		return {"image": null, "error": "PNG dimensions exceed the safe image-memory limit."}
	var offset: int = 8
	var complete: bool = false
	while offset + 12 <= bytes.size():
		var chunk_length = _u32(bytes, offset)
		if chunk_length < 0 or offset + chunk_length + 12 > bytes.size():
			break
		if bytes.slice(offset + 4, offset + 8).get_string_from_ascii() == "IEND":
			complete = chunk_length == 0
			break
		offset += chunk_length + 12
	if not complete:
		return {"image": null, "error": "PNG data is truncated."}
	var image = Image.new()
	var error = image.load_png_from_buffer(bytes)
	if error != OK or image.is_empty():
		return {"image": null, "error": "PNG could not be decoded."}
	return {"image": image, "error": ""}

func _file_length(path: String) -> int:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length = file.get_length()
	file.close()
	return length

func _u32(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])

func _fit(image: Image, maximum: int) -> void:
	var largest = maxi(image.get_width(), image.get_height())
	if largest > maximum:
		var scale = float(maximum) / largest
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
