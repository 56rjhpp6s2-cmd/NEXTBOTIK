extends SceneTree
## Regenerates the transparent PNG throwables from their editable SVG sources.

const FILES := ["test_tube", "literature_book", "constitution"]

func _initialize() -> void:
	for stem in FILES:
		var source := "res:/" + "/assets/projectiles/%s.svg" % stem
		var target := "res:/" + "/assets/projectiles/%s.png" % stem
		var image := Image.new()
		var error := image.load_svg_from_buffer(FileAccess.get_file_as_bytes(source), 1.0)
		if error != OK or image.is_empty():
			push_error("Could not render %s: %s" % [source, error_string(error)])
			quit(1)
			return
		error = image.save_png(ProjectSettings.globalize_path(target))
		if error != OK:
			push_error("Could not save %s: %s" % [target, error_string(error)])
			quit(1)
			return
		print("Rendered ", target, " (", image.get_width(), "x", image.get_height(), ")")
	quit(0)
