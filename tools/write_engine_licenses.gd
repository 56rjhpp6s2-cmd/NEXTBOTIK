extends SceneTree

func _initialize() -> void:
	var destination = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--license-output="):
			destination = argument.trim_prefix("--license-output=")
	var file = FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string("GODOT ENGINE\n\n" + Engine.get_license_text())
	file.store_string("\n\nTHIRD PARTY COPYRIGHTS\n\n" + JSON.stringify(Engine.get_copyright_info(), "\t"))
	for name in Engine.get_license_info():
		file.store_string("\n\n" + name + "\n\n" + Engine.get_license_info()[name])
	file.close()
	quit()
