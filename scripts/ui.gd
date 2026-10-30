class_name GameInterface
extends CanvasLayer
signal action_requested(action: String)
signal map_selected(index: int)
signal mode_selected(index: int)
signal upgrade_selected(index: int)
signal sandbox_action(action: String, value)
const INK = Color("dce6df")
const MUTED = Color("8a9d9f")
const ACCENT = Color("93decc")
var root: Control
var menu: Control
var hud: Control
var pause_screen: Control
var settings_screen: Control
var result_screen: Control
var jumpscare_screen: Control
var settings_return: String = "menu"
var timer_label: Label
var zone_label: Label
var warning_label: Label
var prompt_label: Label
var objective_label: Label
var movement_label: Label
var battery_label: Label
var toast_label: Label
var debug_label: Label
var result_title: Label
var result_body: Label
var result_button: Button
var scare_image: TextureRect
var fade: ColorRect
var overlay: ColorRect
var toast_time: float = 0.0
var menu_best: Label
var sliders: Dictionary = {}
var choices: Dictionary = {}
var toggles: Dictionary = {}
var settings_preview: bool = false
var map_choice: OptionButton
var mission_label: Label
var speed_label: Label
var level_label: Label
var transition_screen: Control
var transition_black: ColorRect
var transition_label: Label
var mode_choice: OptionButton
var mode_description: Label
var statistics_screen: Control
var statistics_body: Label
var upgrade_screen: Control
var upgrade_buttons: Array[Button] = []
var sandbox_screen: Control
var sandbox_controls: Dictionary = {}
var boss_label: Label
var reward_panel: Control
var reward_title: Label
var reward_vote_label: Label
var reward_cards: Array[PanelContainer] = []
var reward_texts: Array[Label] = []
var reward_ids: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_theme()
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay_material = ShaderMaterial.new()
	overlay_material.shader = preload("res://scripts/overlay.gdshader")
	overlay.material = overlay_material
	root.add_child(overlay)
	_build_menu()
	_build_hud()
	_build_pause()
	_build_settings()
	_build_result()
	_build_jumpscare()
	_build_transition()
	_build_statistics()
	_build_upgrades()
	_build_sandbox()
	show_screen("menu")

func _theme() -> void:
	var theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	theme.default_font = font
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_focus_color", "Button", ACCENT)
	for type in ["normal", "hover", "pressed", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.045, 0.075, 0.085, 0.96) if type == "normal" else Color(0.1, 0.19, 0.2, 0.98)
		style.border_color = Color("334449") if type == "normal" else ACCENT
		style.set_border_width_all(1)
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 15
		style.content_margin_bottom = 15
		theme.set_stylebox(type, "Button", style)
		theme.set_stylebox(type, "OptionButton", style)
	root.theme = theme

func _screen(darken: float = 0.0) -> Control:
	var c = Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	if darken > 0.0:
		var bg = ColorRect.new()
		bg.color = Color(0.013, 0.025, 0.032, darken)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.add_child(bg)
	return c

func _label(parent: Node, text: String, size: int = 22, color: Color = INK) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _at(control: Control, at: Vector2, dimensions: Vector2 = Vector2.ZERO) -> Control:
	control.position = at
	if dimensions != Vector2.ZERO:
		control.size = dimensions
	return control

func _button(parent: Node, text: String, action: String) -> Button:
	var b = Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(360, 58)
	b.pressed.connect(_on_button_pressed.bind(action))
	parent.add_child(b)
	return b

func _on_button_pressed(action: String) -> void:
	Sound.one_shot("click", -13.0)
	action_requested.emit(action)

func _vbox(parent: Node, at: Vector2, width: float, separation: int = 12) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.position = at
	v.size.x = width
	v.add_theme_constant_override("separation", separation)
	parent.add_child(v)
	return v

func _build_menu() -> void:
	menu = _screen(0.45)
	_at(_label(menu, "ANOMALY DIVISION  /  INCIDENT 086", 19, ACCENT), Vector2(90, 80))
	_at(_label(menu, "BELOW", 112), Vector2(82, 130))
	_at(_label(menu, "/ ZERO", 112, ACCENT), Vector2(82, 245))
	_at(_label(menu, "THERE IS NO QUIET WAY OUT.", 21, MUTED), Vector2(92, 390))
	var buttons = _vbox(menu, Vector2(92, 430), 440)
	mode_choice = OptionButton.new()
	mode_choice.custom_minimum_size = Vector2(440, 58)
	for title in ["MODE: ARCADE", "MODE: ENDLESS", "MODE: PNG MAYHEM", "MODE: SANDBOX", "MODE: BOSSFIGHT"]:
		mode_choice.add_item(title)
	mode_choice.select(Settings.selected_game_mode)
	mode_choice.item_selected.connect(_on_mode_selected)
	buttons.add_child(mode_choice)
	map_choice = OptionButton.new()
	map_choice.custom_minimum_size = Vector2(440, 58)
	map_choice.add_item("КАРТА: ПОДЗЕМНЫЙ КОМПЛЕКС")
	map_choice.add_item("КАРТА: GM CONSTRUCT")
	map_choice.select(Settings.level_index)
	map_choice.item_selected.connect(_on_map_selected)
	buttons.add_child(map_choice)
	_button(buttons, "PLAY / ИГРАТЬ     →", "play")
	_button(buttons, "СЕТЬ / RADMIN VPN", "network")
	_button(buttons, "SETTINGS", "settings")
	_button(buttons, "QUIT", "quit")
	buttons.add_theme_constant_override("separation", 8)
	for control in buttons.get_children():
		control.custom_minimum_size.y = 48
	var library_buttons = _vbox(menu, Vector2(545, 488), 400, 12)
	_button(library_buttons, "NEXTBOT EDITOR / SANDBOX", "nextbot_editor")
	_button(library_buttons, "PNG PROJECTILE LIBRARY", "png_library_menu")
	_button(library_buttons, "STATISTICS", "statistics")
	mode_description = _label(menu, "", 18, MUTED)
	_at(mode_description, Vector2(545, 700), Vector2(430, 110))
	mode_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_best = _label(menu, "", 18, MUTED)
	_at(menu_best, Vector2(94, 805))
	var info = _vbox(menu, Vector2(1080, 500), 420, 14)
	_label(info, "YOUR ASSIGNMENT", 18, ACCENT)
	mission_label = _label(info, "", 24)
	_label(info, "WASD  MOVE    SHIFT  SPRINT\nCTRL  SLIDE / CROUCH    SPACE  JUMP\nF  FLASHLIGHT    E  INTERACT\nF4  SPEEDOMETER    ESC  PAUSE", 17, MUTED)
	_at(_label(menu, "B2 / SUBSURFACE OPERATIONS", 17, MUTED), Vector2(92, 837))
	_at(_label(menu, "HEADPHONES RECOMMENDED  •  SUDDEN SOUNDS & FLASHING LIGHTS", 15, MUTED), Vector2(870, 841))

func _on_map_selected(index: int) -> void:
	Sound.one_shot("click", -13.0)
	map_selected.emit(index)

func _on_mode_selected(index: int) -> void:
	Sound.one_shot("click", -13.0)
	mode_selected.emit(index)

func set_mode_description(manager) -> void:
	if not is_instance_valid(mode_choice):
		return
	mode_choice.select(int(manager.selected))
	mode_description.text = manager.description()
	var dedicated_map: bool = int(manager.selected) == GameModeManager.GameplayMode.BOSSFIGHT
	map_choice.disabled = dedicated_map
	map_choice.tooltip_text = "BOSSFIGHT uses its own Dust Quarter map and Sun Ring arena." if dedicated_map else ""
	if dedicated_map:
		mission_label.text = "Three randomized switches per sector.\nEvery fourth level is a boss arena.\nBoss HP begins at 4000 and rises by 500."
	elif is_instance_valid(get_parent()) and is_instance_valid(get_parent().world):
		mission_label.text = get_parent().world.mission_description

func set_map_description(world) -> void:
	map_choice.select(Settings.level_index)
	mission_label.text = world.mission_description

func _build_hud() -> void:
	hud = _screen()
	level_label = _label(hud, "LEVEL 01", 20, ACCENT)
	_at(level_label, Vector2(665, 34), Vector2(270, 36))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_label = _label(hud, "", 18, MUTED)
	_at(zone_label, Vector2(48, 36))
	objective_label = _label(hud, "BREAKERS  0 / 3  →  NORTH LIFT", 18)
	_at(objective_label, Vector2(48, 68))
	timer_label = _label(hud, "00:00", 32)
	_at(timer_label, Vector2(1405, 32), Vector2(145, 45))
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	warning_label = _label(hud, "", 22, Color("ef927c"))
	_at(warning_label, Vector2(400, 105), Vector2(800, 40))
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label = _label(hud, "", 21)
	_at(prompt_label, Vector2(350, 550), Vector2(900, 50))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	movement_label = _label(hud, "", 17, MUTED)
	_at(movement_label, Vector2(48, 825))
	speed_label = _label(hud, "", 17, ACCENT)
	_at(speed_label, Vector2(690, 825), Vector2(220, 38))
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battery_label = _label(hud, "", 17, MUTED)
	_at(battery_label, Vector2(1280, 825), Vector2(270, 40))
	battery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toast_label = _label(hud, "", 23, ACCENT)
	_at(toast_label, Vector2(300, 715), Vector2(1000, 80))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	debug_label = _label(hud, "", 16, Color.CYAN)
	_at(debug_label, Vector2(48, 125))
	boss_label = _label(hud, "", 23, Color("ef7568"))
	_at(boss_label, Vector2(400, 150), Vector2(800, 44))
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_reward_hud()

func _build_reward_hud() -> void:
	reward_panel = Control.new()
	reward_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reward_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(reward_panel)
	reward_title = _label(reward_panel, "POST-BOSS REWARD  /  CHOOSE ONE", 27, ACCENT)
	_at(reward_title, Vector2(430, 210), Vector2(740, 44))
	reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index in range(2):
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_at(card, Vector2(55 if index == 0 else 1145, 300), Vector2(400, 205))
		reward_panel.add_child(card)
		var label := _label(card, "REWARD", 20)
		label.custom_minimum_size = Vector2(370, 180)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward_cards.append(card)
		reward_texts.append(label)
	reward_vote_label = _label(reward_panel, "", 22, Color("ffe4a3"))
	_at(reward_vote_label, Vector2(500, 620), Vector2(600, 75))
	reward_vote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_panel.visible = false

func _build_pause() -> void:
	pause_screen = _screen(0.88)
	var v = _vbox(pause_screen, Vector2(575, 220), 450, 18)
	_label(v, "SIGNAL PAUSED", 44)
	_label(v, "Take a breath. The complex can wait.", 19, MUTED)
	_button(v, "RESUME", "resume")
	_button(v, "SETTINGS", "settings_pause")
	_button(v, "PNG PROJECTILES / IMPORT", "png_library")
	_button(v, "RETURN TO MENU", "menu")
	_button(v, "QUIT", "quit")

func _build_settings() -> void:
	settings_screen = _screen(0.97)
	_at(_label(settings_screen, "SYSTEM CONFIGURATION", 38), Vector2(230, 55))
	var scroll = ScrollContainer.new()
	_at(scroll, Vector2(230, 130), Vector2(1140, 610))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_screen.add_child(scroll)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 23)
	scroll.add_child(v)
	_slider(v, "Mouse sensitivity", "sensitivity", 0.02, 0.35, 0.01)
	_slider(v, "Master volume", "master", 0.0, 1.0, 0.01)
	_slider(v, "Chase music & ambience", "music", 0.0, 1.0, 0.01)
	_slider(v, "Sound effects", "sfx", 0.0, 1.0, 0.01)
	_slider(v, "Brightness / minimum visibility", "brightness", 0.65, 1.35, 0.05)
	_choice(v, "Resolution", "resolution", ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440"])
	_choice(v, "Graphics", "quality", ["LOW  /  no shadows", "MEDIUM  /  flashlight shadows", "HIGH  /  selected environment shadows"])
	_choice(v, "Nextbot difficulty", "difficulty", ["EXPLORER  /  slower pursuit", "RELENTLESS  /  intended experience", "NIGHTMARE  /  faster, more sensitive"])
	_toggle(v, "Fullscreen", "fullscreen")
	_toggle(v, "Reduce flashing lights & jumpscare shake", "reduced_flashes")
	_slider(v, "Landing shake", "camera_shake_intensity", 0.0, 1.0, 0.05)
	_slider(v, "Head bob", "head_bob_intensity", 0.0, 1.0, 0.05)
	_toggle(v, "Toggle crouch", "toggle_crouch")
	_toggle(v, "Toggle sprint", "toggle_sprint")
	_toggle(v, "Hold Space for auto bunny hop", "auto_bunnyhop")
	_toggle(v, "Dynamic field of view", "dynamic_fov")
	_toggle(v, "Camera strafe tilt", "camera_tilt")
	_toggle(v, "Show speedometer (F4)", "show_speedometer")
	_at(_button(settings_screen, "APPLY & RETURN", "apply_settings"), Vector2(230, 785), Vector2(360, 60))
	_at(_label(settings_screen, "Difficulty changes take effect on the next run.\nVolume and sensitivity preview immediately.", 18, MUTED), Vector2(650, 788))

func _row(parent: Node, title: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.custom_minimum_size.y = 48
	row.add_theme_constant_override("separation", 30)
	parent.add_child(row)
	var label = _label(row, title, 21)
	label.custom_minimum_size.x = 470
	return row

func _slider(parent: Node, title: String, key: String, minimum: float, maximum: float, step: float) -> void:
	var row = _row(parent, title)
	var slider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size.x = 400
	row.add_child(slider)
	var value_label = _label(row, "", 19, ACCENT)
	value_label.custom_minimum_size.x = 80
	slider.value_changed.connect(_on_slider_changed.bind(key, value_label))
	_on_slider_changed(slider.value, key, value_label)
	sliders[key] = slider

func _on_slider_changed(value: float, key: String, value_label: Label) -> void:
	value_label.text = "%.2f" % value if key == "sensitivity" else "%d%%" % roundi(value * 100.0)
	if settings_preview:
		Settings.set(key, value)
		Sound.apply_settings()

func _choice(parent: Node, title: String, key: String, items: Array) -> void:
	var row = _row(parent, title)
	var choice = OptionButton.new()
	choice.custom_minimum_size.x = 560
	for item in items:
		choice.add_item(item)
	row.add_child(choice)
	choices[key] = choice

func _toggle(parent: Node, title: String, key: String) -> void:
	var row = _row(parent, title)
	var toggle = CheckButton.new()
	toggle.text = "ENABLED"
	row.add_child(toggle)
	toggles[key] = toggle

func _build_result() -> void:
	result_screen = _screen(0.97)
	var v = _vbox(result_screen, Vector2(430, 210), 740, 22)
	_label(v, "ANOMALY DIVISION / FIELD REPORT", 19, ACCENT)
	result_title = _label(v, "РОССИЯ ПУТИН ПОБЕДА", 48)
	result_body = _label(v, "", 25, MUTED)
	result_button = _button(v, "RESPAWN    →", "restart")
	_button(v, "RETURN TO MENU", "menu")

func _build_jumpscare() -> void:
	jumpscare_screen = _screen(1.0)
	scare_image = TextureRect.new()
	scare_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scare_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scare_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scare_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jumpscare_screen.add_child(scare_image)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	jumpscare_screen.add_child(fade)

func _build_transition() -> void:
	transition_screen = Control.new()
	transition_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(transition_screen)
	transition_black = ColorRect.new()
	transition_black.color = Color(0, 0, 0, 0)
	transition_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_screen.add_child(transition_black)
	transition_label = _label(transition_screen, "", 32, ACCENT)
	transition_label.position = Vector2(300, 400)
	transition_label.size = Vector2(1000, 100)
	transition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transition_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	transition_screen.visible = false

func _build_statistics() -> void:
	statistics_screen = _screen(0.97)
	var v = _vbox(statistics_screen, Vector2(350, 105), 900, 18)
	_label(v, "LOCAL STATISTICS", 46, ACCENT)
	statistics_body = _label(v, "", 24)
	statistics_body.custom_minimum_size = Vector2(900, 520)
	_button(v, "RETURN TO MENU", "menu_screen")

func _build_upgrades() -> void:
	upgrade_screen = _screen(0.93)
	_at(_label(upgrade_screen, "WAVE CLEARED", 54, ACCENT), Vector2(510, 135))
	_at(_label(upgrade_screen, "Choose one reusable modifier", 22, MUTED), Vector2(570, 205))
	var v = _vbox(upgrade_screen, Vector2(445, 285), 710, 18)
	for index in range(3):
		var button = Button.new()
		button.text = "UPGRADE"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(710, 105)
		button.pressed.connect(_upgrade_pressed.bind(index))
		v.add_child(button)
		upgrade_buttons.append(button)

func _upgrade_pressed(index: int) -> void:
	upgrade_selected.emit(index)

func _build_sandbox() -> void:
	sandbox_screen = _screen(0.82)
	_at(_label(sandbox_screen, "SANDBOX NEXTBOT LAB", 42, ACCENT), Vector2(160, 55))
	_at(_label(sandbox_screen, "Changes apply live. Spawn uses the selected PNG face.", 19, MUTED), Vector2(165, 110))
	var left = _vbox(sandbox_screen, Vector2(165, 165), 580, 12)
	_sandbox_slider(left, "Speed", "speed", 0.0, 30.0, 0.1, 11.4)
	_sandbox_slider(left, "Maximum HP", "health", 1.0, 10000.0, 1.0, 100.0)
	_sandbox_slider(left, "Attack damage", "damage", 0.0, 200.0, 1.0, 100.0)
	_sandbox_slider(left, "Aggression", "aggression", 0.05, 3.0, 0.05, 1.0)
	_sandbox_slider(left, "Detection range", "detection", 0.0, 100.0, 1.0, 34.0)
	_sandbox_slider(left, "Nextbot size", "size", 0.25, 3.0, 0.05, 1.0)
	_sandbox_slider(left, "Spawn count", "count", 1.0, 12.0, 1.0, 1.0)
	_sandbox_slider(left, "Auto-spawn interval", "auto_spawn_interval", 0.5, 20.0, 0.5, 4.0)
	_sandbox_slider(left, "Auto-spawn limit", "auto_spawn_limit", 1.0, 32.0, 1.0, 12.0)
	_sandbox_slider(left, "Lighting", "lighting", 0.05, 2.0, 0.05, 1.0)
	var right = _vbox(sandbox_screen, Vector2(860, 170), 520, 12)
	_sandbox_toggle(right, "AI enabled", "ai", true)
	_sandbox_toggle(right, "Enemy attacks", "attacks", true)
	_sandbox_toggle(right, "Player invincible", "invincible", true)
	_sandbox_toggle(right, "AUTO SPAWN NEXTBOTS", "auto_spawn", false)
	_button(right, "SPAWN SELECTED PNG NEXTBOT", "sandbox_spawn")
	_button(right, "SPAWN / RESET REWARD KEEPER", "sandbox_reward")
	_button(right, "REMOVE ALL NEXTBOTS", "sandbox_remove")
	_button(right, "TRIGGER RANDOM EVENT", "sandbox_event")
	_button(right, "REGENERATE PROCEDURAL MAP", "sandbox_regenerate")
	_button(right, "RESET SANDBOX", "sandbox_reset")
	_button(right, "RETURN TO PLAY [F2]", "sandbox_close")

func _sandbox_slider(parent: Node, title: String, key: String, minimum: float, maximum: float, step: float, initial: float) -> void:
	var row = _row(parent, title)
	row.get_child(0).custom_minimum_size.x = 220
	var slider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size.x = 250
	row.add_child(slider)
	var value_label = _label(row, "", 17, ACCENT)
	value_label.custom_minimum_size.x = 90
	slider.value_changed.connect(_sandbox_slider_changed.bind(key, step, value_label))
	_sandbox_slider_changed(initial, key, step, value_label)
	sandbox_controls[key] = slider

func _sandbox_slider_changed(value: float, key: String, step: float, value_label: Label) -> void:
	value_label.text = "%d" % roundi(value) if step >= 1.0 else "%.2f" % value
	sandbox_action.emit(key, roundi(value) if key == "count" else value)

func _sandbox_toggle(parent: Node, title: String, key: String, initial: bool) -> void:
	var toggle = CheckButton.new()
	toggle.text = title
	toggle.button_pressed = initial
	toggle.custom_minimum_size = Vector2(500, 46)
	toggle.toggled.connect(_sandbox_toggle_changed.bind(key))
	parent.add_child(toggle)
	sandbox_controls[key] = toggle

func _sandbox_toggle_changed(value: bool, key: String) -> void:
	sandbox_action.emit(key, value)

func show_screen(which: String) -> void:
	menu.visible = which == "menu"
	hud.visible = which == "game"
	pause_screen.visible = which == "pause"
	settings_screen.visible = which == "settings"
	result_screen.visible = which == "result"
	jumpscare_screen.visible = which == "jumpscare"
	statistics_screen.visible = which == "statistics"
	upgrade_screen.visible = which == "upgrades"
	sandbox_screen.visible = which == "sandbox"
	if which == "menu":
		menu_best.text = "%s  /  BEST SURVIVAL %s  /  DEEPEST LEVEL %02d" % [Settings.difficulty_name(), Settings.time_text(Settings.best_for_map(Settings.level_index, Settings.difficulty)), Settings.highest_level]
		_focus_first(menu)
	elif which == "pause":
		_focus_first(pause_screen)
	elif which == "result":
		_focus_first(result_screen)
	elif which == "statistics":
		_focus_first(statistics_screen)
	elif which == "upgrades":
		_focus_first(upgrade_screen)
	elif which == "sandbox":
		_focus_first(sandbox_screen)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if which == "game" else Input.MOUSE_MODE_VISIBLE

func _focus_first(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.grab_focus()
			return
		_focus_first(child)

func open_settings(return_screen: String) -> void:
	settings_return = return_screen
	settings_preview = false
	for key in sliders:
		sliders[key].value = Settings.get(key)
	for key in choices:
		choices[key].select(Settings.get(key))
	for key in toggles:
		toggles[key].button_pressed = Settings.get(key)
	settings_preview = true
	show_screen("settings")

func apply_settings() -> void:
	for key in choices:
		Settings.set(key, choices[key].selected)
	for key in toggles:
		Settings.set(key, toggles[key].button_pressed)
	Settings.apply_display()
	Settings.save()
	settings_preview = false

func update_hud(session) -> void:
	var p = session.player
	level_label.text = session.game_modes.mode_status()
	timer_label.text = Settings.time_text(session.game_modes.timer_seconds())
	zone_label.text = session.world.hud_location(p.global_position)
	objective_label.text = "BREAKERS  %d / 3  →  %s" % [session.breakers, session.world.objective_destination if session.breakers == 3 else "RESTORE POWER"]
	objective_label.text = session.game_modes.objective_text()
	movement_label.text = "SLIDING" if p.sliding else ("SPRINTING" if p.sprinting else ("CROUCHED / QUIET" if p.crouching else ""))
	speed_label.visible = Settings.show_speedometer
	speed_label.text = "%.1f m/s" % Vector2(p.velocity.x, p.velocity.z).length()
	battery_label.text = "LIGHT %s  /  %d%%" % ["ON" if p.view.flashlight_on else "OFF", ceili(p.view.battery)]
	var refuge = session.world.refuge_remaining(p.global_position)
	var event_warning = session.events.warning_text()
	if not event_warning.is_empty():
		warning_label.text = event_warning
	elif p.hidden:
		warning_label.text = "HOLD YOUR BREATH"
	elif refuge > 0:
		warning_label.text = "REFUGE POWER  /  %02d SEC" % ceili(refuge)
	elif refuge == 0:
		warning_label.text = "REFUGE DEPLETED  /  MOVE"
	else:
		warning_label.text = "RUN. IT HAS SEEN YOU." if session.chased else ""
	prompt_label.text = "[E] LEAVE LOCKER  /  %d SECONDS" % ceili(session.hide_remaining) if p.hidden else session.interaction_prompt
	boss_label.text = ""
	if is_instance_valid(session.game_modes.active_boss) and not session.game_modes.active_boss.combat.dead:
		var boss_health = session.game_modes.active_boss.get_health_component()
		boss_label.text = "BOSS  %d / %d HP" % [ceili(boss_health.current_health), ceili(boss_health.max_health)]
	if is_instance_valid(session.post_boss) and session.post_boss.state == PostBossRewardController.RewardState.REWARD_SELECTION and session.network.active:
		update_reward_votes(session.post_boss.votes, session.post_boss.vote_time_left, session.network.local_id())
	overlay.material.set_shader_parameter("danger", clampf(session.threat, 0, 1))
	debug_label.visible = session.debug_ai
	if session.debug_ai:
		var seed_text = str(session.current_generation_seed) if session.current_level >= 4 else "AUTHORED"
		var procedural = session.world is ProceduralLevelWorld
		var room_count = session.world.generated_room_count if procedural else 0
		var light_scale = session.world.lighting_multiplier if procedural else 1.0
		var validation = session.world.generation_validation if procedural else "AUTHORED"
		var nav_state = session.world.navigation_status if procedural else ("READY" if session.world.navigation.synchronized else "BUILDING")
		debug_label.text = "F3 / AI DEBUG  |  F6 REGENERATE  |  F7 FORCE SPAWN\nLEVEL %02d  |  SEED %s  |  ROOMS %d\nLIGHT %.2fx  |  BOT SPEED %.2fx\nNAV %s  |  VALIDATION %s\nFPS %d  |  BOTS %d  |  NAV POLYGONS %d\nPOSITION %s  |  THREAT %.2f" % [session.current_level, seed_text, room_count, light_scale, session.nextbot_speed_multiplier(), nav_state, validation, Engine.get_frames_per_second(), session.bots.size(), session.world.navigation.polygon_count, str(p.global_position.snapped(Vector3.ONE * 0.1)), session.threat]

func fade_to_black(message: String, duration: float = 0.65) -> void:
	transition_screen.visible = true
	transition_screen.move_to_front()
	transition_label.text = message
	transition_label.modulate.a = 0.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(transition_black, "color:a", 1.0, duration)
	tween.tween_property(transition_label, "modulate:a", 1.0, duration * 0.75)
	await tween.finished

func fade_from_black(duration: float = 0.75) -> void:
	await get_tree().create_timer(0.12, true).timeout
	var tween = create_tween().set_parallel(true)
	tween.tween_property(transition_black, "color:a", 0.0, duration)
	tween.tween_property(transition_label, "modulate:a", 0.0, duration * 0.55)
	await tween.finished
	transition_screen.visible = false

func toast(message: String, duration: float = 4.0) -> void:
	toast_label.text = message
	toast_time = duration
	toast_label.modulate.a = 1.0

func _process(delta: float) -> void:
	if toast_time > 0.0 and not get_tree().paused:
		toast_time -= delta
		toast_label.modulate.a = clampf(toast_time, 0, 1)

func show_result(won: bool, seconds: float, best_time: float, new_record: bool, escape_text: String = "The lift doors close. Something is still down there.", kills: int = 0) -> void:
	result_title.text = "SURFACE REACHED" if won else "РОССИЯ ПУТИН ПОБЕДА"
	result_title.add_theme_font_size_override("font_size", 64 if won else 48)
	result_title.add_theme_color_override("font_color", ACCENT if won else Color("ed9b86"))
	result_body.text = "%s\nSURVIVED  %s     /     BEST  %s\n%s" % [escape_text if won else "You were not alone down there.", Settings.time_text(seconds), Settings.time_text(best_time), "NEW SURVIVAL RECORD" if new_record else "Learn the loops. Break line of sight. Keep moving."]
	result_body.text += "\nPNG KILLS  %d" % kills
	result_button.text = "ENTER AGAIN    →" if won else "RESPAWN    →"
	show_screen("result")

func show_arcade_result(result: Dictionary, leaderboard: Array[Dictionary]) -> void:
	result_title.text = "ROUND SURVIVED"
	result_title.add_theme_font_size_override("font_size", 58)
	result_title.add_theme_color_override("font_color", ACCENT)
	result_body.text = "ROUND %02d  /  SCORE %06d\nSURVIVED  %s\n\nSESSION LEADERBOARD" % [result.round, result.score, Settings.time_text(result.survival)]
	for index in range(mini(5, leaderboard.size())):
		result_body.text += "\n%d.  %06d  /  ROUND %02d" % [index + 1, leaderboard[index].score, leaderboard[index].round]
	result_button.text = "NEXT MAP / ROUND    ->"
	show_screen("result")

func show_upgrades(upgrades: Array[String], definitions: Dictionary) -> void:
	for index in range(upgrade_buttons.size()):
		var key = upgrades[index]
		upgrade_buttons[index].text = "%s\n%s" % [definitions[key].title, definitions[key].description]
	show_screen("upgrades")

func show_reward_phase(rewards: Array[String], multiplayer_vote: bool, time_left: float) -> void:
	reward_ids = rewards.duplicate()
	reward_panel.visible = rewards.size() == 2
	reward_title.text = "POST-BOSS VOTE  /  [Q] LEFT  OR  [E] RIGHT" if multiplayer_vote else "POST-BOSS REWARD  /  [Q] LEFT  OR  [E] RIGHT"
	for index in range(mini(2, rewards.size())):
		_update_reward_card_text(index, rewards[index])
		_set_reward_card_style(index, GameplayModifierSet.rarity_color(rewards[index]), false)
	update_reward_votes({}, time_left, 1)

func _update_reward_card_text(index: int, reward: String) -> void:
	if index < 0 or index >= reward_texts.size() or not GameplayModifierSet.DEFINITIONS.has(reward):
		return
	var definition: Dictionary = GameplayModifierSet.DEFINITIONS[reward]
	var rarity := str(definition.rarity).to_upper()
	var current_stack: int = get_parent().game_modes.modifiers.stack_count(reward)
	var maximum_stack := int(definition.get("max_stacks", 1))
	var hotkey := "Q" if index == 0 else "E"
	reward_texts[index].text = "[%s]  %s HAND\n%s\n%s  /  %s\n\n%s\n%s\nCURRENT STACK  %d / %d" % [hotkey, "LEFT" if index == 0 else "RIGHT", definition.title, rarity, definition.category, definition.description, definition.stats, current_stack, maximum_stack]

func _set_reward_card_style(index: int, color: Color, focused: bool) -> void:
	if index < 0 or index >= reward_cards.size():
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r * 0.08, color.g * 0.08, color.b * 0.08, 0.90)
	style.border_color = color.lightened(0.22) if focused else color.darkened(0.18)
	style.set_border_width_all(4 if focused else 2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	reward_cards[index].add_theme_stylebox_override("panel", style)
	reward_texts[index].add_theme_color_override("font_color", color.lightened(0.18))

func focus_reward(index: int) -> void:
	for card_index in range(mini(2, reward_ids.size())):
		_set_reward_card_style(card_index, GameplayModifierSet.rarity_color(reward_ids[card_index]), card_index == index)

func update_reward_votes(votes: Dictionary, time_left: float, local_id: int) -> void:
	if not reward_panel.visible:
		return
	var counts := [0, 0]
	for choice in votes.values():
		if int(choice) in [0, 1]:
			counts[int(choice)] += 1
	if votes.is_empty() and not get_parent().network.active:
		reward_vote_label.text = "PRESS [Q] FOR LEFT   /   PRESS [E] FOR RIGHT"
	else:
		var mine := int(votes.get(local_id, -1))
		var vote_text := "LEFT" if mine == 0 else ("RIGHT" if mine == 1 else "NONE")
		reward_vote_label.text = "[Q] LEFT  %d VOTES    /    [E] RIGHT  %d VOTES\n%02d SEC    /    YOUR VOTE: %s" % [counts[0], counts[1], ceili(time_left), vote_text]

func finalize_reward(choice: int, reward: String, lever_required: bool = true) -> void:
	if not reward_panel.visible or choice not in [0, 1]:
		return
	var definition: Dictionary = GameplayModifierSet.DEFINITIONS[reward]
	reward_title.text = "ACQUIRED  /  %s" % definition.title
	_update_reward_card_text(choice, reward)
	reward_cards[1 - choice].modulate = Color(1, 1, 1, 0.18)
	reward_cards[choice].modulate = Color.WHITE
	reward_vote_label.text = "PROGRESSION UNLOCKED  /  LEVER BEHIND THE KEEPER" if lever_required else "REWARD INSTALLED"

func hide_reward_phase() -> void:
	if not is_instance_valid(reward_panel):
		return
	reward_panel.visible = false
	reward_ids.clear()
	for card in reward_cards:
		card.modulate = Color.WHITE

func show_statistics(statistics) -> void:
	var d: Dictionary = statistics.data
	statistics_body.text = "TOTAL PLAYTIME             %s\nTOTAL DEATHS               %d\nNEXTBOT KILLS              %d\nBEST SURVIVAL              %s\nHIGHEST ENDLESS LEVEL      %02d\nHIGHEST ARCADE SCORE       %06d\nPNG PROJECTILES THROWN     %d\nSUCCESSFUL PNG HITS        %d\nBEST COMPLETED WAVE        %02d\nBOSSES DEFEATED            %d" % [Settings.time_text(d.total_playtime), d.total_deaths, d.total_nextbot_kills, Settings.time_text(d.best_survival_time), d.highest_endless_level, d.highest_arcade_score, d.total_png_projectiles_thrown, d.successful_projectile_hits, d.best_completed_wave, d.bosses_defeated]
	show_screen("statistics")

func toggle_sandbox_tools() -> void:
	if sandbox_screen.visible:
		show_screen("game")
	else:
		show_screen("sandbox")

func play_jumpscare(texture: Texture2D) -> void:
	scare_image.texture = texture
	scare_image.position = Vector2.ZERO
	scare_image.modulate = Color.WHITE
	fade.color.a = 0.0
	show_screen("jumpscare")
	var tween = create_tween()
	if not Settings.reduced_flashes:
		for i in range(7):
			tween.tween_property(scare_image, "position", Vector2(randf_range(-32, 32), randf_range(-22, 22)), 0.045)
	else:
		tween.tween_interval(0.315)
	tween.tween_interval(0.25)
	tween.tween_property(fade, "color:a", 1.0, 0.4)
	await tween.finished
