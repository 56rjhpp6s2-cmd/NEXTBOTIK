extends CanvasLayer
var session
var net
var root: Control
var panel: Control
var status_label: Label
var name_input: LineEdit
var address_input: LineEdit
var port_input: SpinBox
var network_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = session.ui.root.theme
	add_child(root)
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)
	var bg = ColorRect.new()
	bg.color = Color(0.012, 0.023, 0.03, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(bg)
	_label(panel, "СЕТЬ / RADMIN VPN", Vector2(300, 100), Vector2(1000, 65), 43)
	_label(panel, "Один создаёт сервер. Остальные вводят его IP из Radmin VPN.", Vector2(300, 175), Vector2(1050, 45), 23)
	_label(panel, "ИМЯ ИГРОКА", Vector2(300, 255), Vector2(280, 45), 21)
	name_input = LineEdit.new()
	name_input.position = Vector2(610, 250)
	name_input.size = Vector2(600, 50)
	name_input.max_length = 20
	name_input.text = Settings.network_name
	panel.add_child(name_input)
	_label(panel, "IP ХОСТА", Vector2(300, 335), Vector2(280, 45), 21)
	address_input = LineEdit.new()
	address_input.position = Vector2(610, 330)
	address_input.size = Vector2(600, 50)
	address_input.text = Settings.network_address
	address_input.placeholder_text = "IP из Radmin VPN или 127.0.0.1"
	panel.add_child(address_input)
	_label(panel, "ПОРТ UDP", Vector2(300, 415), Vector2(280, 45), 21)
	port_input = SpinBox.new()
	port_input.position = Vector2(610, 410)
	port_input.size = Vector2(250, 50)
	port_input.min_value = 1024
	port_input.max_value = 65535
	port_input.value = Settings.network_port
	panel.add_child(port_input)
	status_label = _label(panel, "Карта и сложность берутся у хоста. До 8 игроков. Без PvP.", Vector2(300, 490), Vector2(1000, 85), 21)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("СОЗДАТЬ СЕРВЕР", Vector2(300, 610), Vector2(430, 65), _host)
	_button("ПОДКЛЮЧИТЬСЯ", Vector2(780, 610), Vector2(430, 65), _join)
	_button("НАЗАД", Vector2(300, 700), Vector2(430, 60), close)
	_label(panel, "В сетевой игре меню и выбор PNG не останавливают остальных игроков.", Vector2(300, 805), Vector2(1100, 45), 19)
	network_label = _label(root, "", Vector2(490, 34), Vector2(660, 55), 17)
	network_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.visible = false
	net.status_changed.connect(set_status)

func _label(parent: Node, text: String, at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("a4dccd"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(text: String, at: Vector2, dimensions: Vector2, callback: Callable) -> void:
	var button = Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.pressed.connect(callback)
	panel.add_child(button)

func open() -> void:
	panel.visible = true
	status_label.text = "%s ONLINE • Host controls the shared map, seed and difficulty • Up to 8 players" % session.game_modes.mode_name()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	name_input.grab_focus()

func close() -> void:
	if net.active and not net.game_running:
		net.disconnect_session()
	panel.visible = false

func set_status(message: String) -> void:
	status_label.text = message

func _save_fields() -> void:
	Settings.network_name = name_input.text.strip_edges().left(20)
	if Settings.network_name.is_empty():
		Settings.network_name = "PLAYER"
	Settings.network_address = address_input.text.strip_edges()
	Settings.network_port = int(port_input.value)
	Settings.save()

func _host() -> void:
	_save_fields()
	net.host(Settings.network_port, Settings.network_name)

func _join() -> void:
	_save_fields()
	net.join(Settings.network_address, Settings.network_port, Settings.network_name)

func _process(_delta: float) -> void:
	network_label.visible = net.active and not panel.visible and session.mode in [session.Mode.PLAYING, session.Mode.PAUSED]
	if net.active:
		network_label.text = "%s  •  %d / 8 ИГРОКОВ  •  UDP %d\nМЕНЮ НЕ ОСТАНАВЛИВАЕТ ИГРУ" % ["ХОСТ" if net.is_host() else "СЕТЕВАЯ ИГРА", net.peers.size(), net.port]
