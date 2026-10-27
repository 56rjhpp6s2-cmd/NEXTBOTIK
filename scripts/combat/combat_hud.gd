class_name CombatHUD
extends CanvasLayer
## HUD and paused PNG library. Native import never requires restarting a run.
const ACCENT = Color("93decc")
var session
var weapon
var images
var root: Control
var hud: Control
var gallery: Control
var image_list: ItemList
var preview: TextureRect
var details: Label
var status: Label
var size_label: Label
var size_slider: HSlider
var ammo_toggle: CheckButton
var icon: TextureRect
var image_name: Label
var ammo_label: Label
var kills_label: Label
var target_label: Label
var file_picker: FileDialog
var return_to_game: bool = true
var rebuilding: bool = false
var opened_from_menu: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = session.ui.root.theme
	add_child(root)
	_build_hud()
	_build_gallery()
	file_picker = FileDialog.new()
	file_picker.access = FileDialog.ACCESS_FILESYSTEM
	file_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_picker.filters = PackedStringArray(["*.png,*.jpg,*.jpeg ; PNG and JPEG images", "*.png ; PNG images", "*.jpg,*.jpeg ; JPEG images"])
	file_picker.use_native_dialog = true
	file_picker.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	file_picker.file_selected.connect(_on_file_selected)
	add_child(file_picker)
	images.library_changed.connect(_rebuild_list)
	images.image_selected.connect(_selected)
	images.notice.connect(_notice)
	_rebuild_list()
	gallery.visible = false
	hud.visible = false

func _label(parent: Node, text: String, at: Vector2, dimensions: Vector2, font_size: int = 20, color: Color = Color("dce6df")) -> Label:
	var label = Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, at: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _texture(parent: Node, at: Vector2, dimensions: Vector2) -> TextureRect:
	var image = TextureRect.new()
	image.position = at
	image.size = dimensions
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	var crosshair = preload("res://scripts/combat/combat_crosshair.gd").new()
	crosshair.weapon = weapon
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(crosshair)
	icon = _texture(hud, Vector2(48, 650), Vector2(64, 64))
	image_name = _label(hud, "", Vector2(130, 650), Vector2(310, 30), 21, ACCENT)
	image_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ammo_label = _label(hud, "PNG  ∞", Vector2(130, 685), Vector2(350, 28), 18)
	_button(hud, "Import PNG", Vector2(48, 725), Vector2(160, 40), import_pressed)
	_button(hud, "PNG LIBRARY [TAB]", Vector2(220, 725), Vector2(230, 40), open_library)
	_label(hud, "LMB THROW  /  RMB AIM  /  R RELOAD  /  WHEEL SELECT", Vector2(48, 777), Vector2(550, 25), 14, Color("94aaa9"))
	kills_label = _label(hud, "KILLS  0", Vector2(1330, 82), Vector2(220, 35), 20, ACCENT)
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	target_label = _label(hud, "", Vector2(550, 488), Vector2(500, 40), 19, ACCENT)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_gallery() -> void:
	gallery = Control.new()
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(gallery)
	var background = ColorRect.new()
	background.color = Color(0.012, 0.023, 0.03, 0.98)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gallery.add_child(background)
	_label(gallery, "PNG ARSENAL", Vector2(210, 95), Vector2(1000, 65), 44, ACCENT)
	_label(gallery, "PNG / JPG / JPEG. JPEGs are converted to PNG on import.", Vector2(212, 163), Vector2(1000, 35), 21)
	_button(gallery, "Import PNG", Vector2(210, 215), Vector2(250, 55), import_pressed)
	_button(gallery, "REFRESH LIST", Vector2(480, 215), Vector2(250, 55), _refresh_pressed)
	_button(gallery, "USE PNG / RETURN", Vector2(1030, 215), Vector2(360, 55), close_library)
	image_list = ItemList.new()
	image_list.position = Vector2(210, 295)
	image_list.size = Vector2(560, 400)
	image_list.fixed_icon_size = Vector2i(64, 64)
	image_list.icon_mode = ItemList.ICON_MODE_LEFT
	image_list.add_theme_font_size_override("font_size", 22)
	image_list.item_selected.connect(_item_selected)
	gallery.add_child(image_list)
	var checker = _texture(gallery, Vector2(890, 295), Vector2(330, 250))
	checker.stretch_mode = TextureRect.STRETCH_SCALE
	checker.texture = _checkerboard()
	preview = _texture(gallery, Vector2(900, 305), Vector2(310, 230))
	details = _label(gallery, "", Vector2(820, 560), Vector2(570, 55), 21)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size_label = _label(gallery, "", Vector2(820, 625), Vector2(560, 30), 20, ACCENT)
	size_slider = HSlider.new()
	size_slider.position = Vector2(820, 660)
	size_slider.size = Vector2(420, 25)
	size_slider.min_value = 0.2
	size_slider.max_value = 2.5
	size_slider.step = 0.05
	size_slider.value = Settings.projectile_size
	size_slider.value_changed.connect(_size_changed)
	gallery.add_child(size_slider)
	_size_changed(Settings.projectile_size)
	ammo_toggle = CheckButton.new()
	ammo_toggle.text = "Unlimited ammunition"
	ammo_toggle.position = Vector2(820, 700)
	ammo_toggle.button_pressed = Settings.unlimited_png_ammo
	ammo_toggle.toggled.connect(_ammo_changed)
	gallery.add_child(ammo_toggle)
	status = _label(gallery, "", Vector2(210, 720), Vector2(560, 70), 18, Color("a6b7b5"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(gallery, "TAB / ESC RETURN   •   PNGs refresh automatically every 3 seconds", Vector2(210, 825), Vector2(1180, 35), 17, Color("8a9d9f"))

func _checkerboard() -> Texture2D:
	var image = Image.create(32, 24, false, Image.FORMAT_RGB8)
	for y in range(24):
		for x in range(32):
			var light = (x / 4 + y / 4) % 2 == 0
			image.set_pixel(x, y, Color("26363b") if light else Color("15262c"))
	return ImageTexture.create_from_image(image)

func _process(_delta: float) -> void:
	hud.visible = session.is_running() and session.ui.hud.visible and not gallery.visible
	kills_label.text = "KILLS  %d" % session.kill_count
	var damage = ceili(weapon.projectile_damage)
	ammo_label.text = "RELOADING PNG…" if weapon.reload_remaining > 0.0 else ("PNG  ∞  /  %d DAMAGE" % damage if weapon.unlimited_ammo else "PNG  %d / %d  /  %d DAMAGE" % [weapon.ammo, weapon.magazine_size, damage])
	target_label.text = ""
	var target = weapon.aimed_enemy
	if not is_instance_valid(target) and weapon.hit_time > 0:
		target = weapon.last_hit_enemy
	if is_instance_valid(target):
		var health = target.get_health_component()
		target_label.text = "ELIMINATED" if health.dead else "NEXTBOT  %d / %d HP" % [ceili(health.current_health), ceili(health.max_health)]

func open_library() -> void:
	if gallery.visible or session.mode not in [session.Mode.PLAYING, session.Mode.PAUSED]:
		return
	return_to_game = session.is_local_playing()
	if return_to_game:
		session.pause_run()
	session.ui.pause_screen.visible = false
	weapon.suspend_input()
	gallery.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	images.refresh()
	_rebuild_list()
	size_slider.value = Settings.projectile_size
	ammo_toggle.button_pressed = weapon.unlimited_ammo
	ammo_toggle.disabled = session.network.active
	image_list.grab_focus()

func open_library_from_menu() -> void:
	if gallery.visible or session.mode != session.Mode.MENU:
		return
	opened_from_menu = true
	return_to_game = false
	session.ui.menu.visible = false
	weapon.suspend_input()
	gallery.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	images.refresh()
	_rebuild_list()
	size_slider.value = Settings.projectile_size
	ammo_toggle.button_pressed = Settings.unlimited_png_ammo
	ammo_toggle.disabled = false
	image_list.grab_focus()

func close_library() -> void:
	if not gallery.visible:
		return
	dismiss()
	Settings.save()
	weapon.require_release = true
	if opened_from_menu:
		opened_from_menu = false
		session.ui.show_screen("menu")
		return
	if return_to_game and session.mode == session.Mode.PAUSED:
		session.resume_run()
	elif session.mode == session.Mode.PAUSED:
		session.ui.show_screen("pause")

func dismiss() -> void:
	gallery.visible = false
	if is_instance_valid(file_picker):
		file_picker.hide()

func import_pressed() -> void:
	if not gallery.visible:
		open_library()
	if not gallery.visible:
		return
	file_picker.popup_centered_ratio(0.75)

func _on_file_selected(path: String) -> void:
	var result: Dictionary = images.import_png(path)
	status.text = result.message
	status.add_theme_color_override("font_color", ACCENT if result.ok else Color("f2947b"))
	if result.ok:
		_rebuild_list()

func _refresh_pressed() -> void:
	images.refresh(true)
	_rebuild_list()
	status.text = "%d PNGs ready. Folder: %s" % [images.entries.size(), ProjectSettings.globalize_path(images.directory)]
	if not images.errors.is_empty():
		status.text = "Skipped: " + images.errors[0]

func _rebuild_list() -> void:
	if not is_instance_valid(image_list):
		return
	rebuilding = true
	image_list.clear()
	for entry in images.entries:
		image_list.add_item(entry.name, entry.preview)
	if not images.entries.is_empty():
		image_list.select(images.selected_index)
		_selected(images.current_entry())
	if not images.errors.is_empty():
		status.text = "Skipped: " + images.errors[0]
	else:
		status.text = "%d PNGs ready.\nFolder: %s" % [images.entries.size(), ProjectSettings.globalize_path(images.directory)]
	rebuilding = false

func _item_selected(index: int) -> void:
	if not rebuilding:
		images.select(index)

func _selected(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	icon.texture = entry.preview
	preview.texture = images.current_texture()
	image_name.text = entry.name
	image_name.tooltip_text = entry.filename
	details.text = "%s\n%d × %d pixels / transparency preserved" % [entry.filename, entry.dimensions.x, entry.dimensions.y]
	if image_list.item_count > images.selected_index:
		image_list.select(images.selected_index)

func _size_changed(value: float) -> void:
	Settings.projectile_size = clampf(value, 0.2, 2.5)
	size_label.text = "PROJECTILE SIZE  /  %.2f m" % Settings.projectile_size

func _ammo_changed(enabled: bool) -> void:
	if session.network.active:
		return
	Settings.unlimited_png_ammo = enabled
	weapon.unlimited_ammo = enabled
	weapon.ammo = weapon.magazine_size

func _notice(message: String) -> void:
	status.text = message
