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
var discovery_button: Button
var discovery_responder: PacketPeerUDP
var discovery_searcher: PacketPeerUDP
var discovery_deadline := 0.0
const DISCOVERY_MAGIC := "BELOW_ZERO_DISCOVER_V1"
const SERVER_MAGIC := "BELOW_ZERO_SERVER_V1"

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
	var mobile := OS.has_feature("mobile") or "--mobile-test" in OS.get_cmdline_user_args()
	_label(panel, "ОНЛАЙН / WI-FI / LAN" if mobile else "СЕТЬ / LAN / RADMIN VPN", Vector2(300, 100), Vector2(1000, 65), 43)
	_label(panel, "На телефоне найдите хост в одной Wi-Fi сети или введите обычный IP." if mobile else "Один создаёт сервер. Остальные вводят LAN, публичный или VPN IP.", Vector2(300, 175), Vector2(1050, 45), 23)
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
	address_input.placeholder_text = "LAN / публичный / VPN IP"
	panel.add_child(address_input)
	_label(panel, "ПОРТ UDP", Vector2(300, 415), Vector2(280, 45), 21)
	port_input = SpinBox.new()
	port_input.position = Vector2(610, 410)
	port_input.size = Vector2(250, 50)
	port_input.min_value = 1024
	port_input.max_value = 65534
	port_input.value = Settings.network_port
	panel.add_child(port_input)
	status_label = _label(panel, "Карта и сложность берутся у хоста. До 8 игроков. Без PvP.", Vector2(300, 490), Vector2(1000, 85), 21)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("СОЗДАТЬ СЕРВЕР", Vector2(300, 610), Vector2(430, 65), _host)
	_button("ПОДКЛЮЧИТЬСЯ", Vector2(780, 610), Vector2(430, 65), _join)
	discovery_button = _button("НАЙТИ ХОСТ В WI-FI / LAN", Vector2(780, 700), Vector2(430, 60), _discover)
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

func _button(text: String, at: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.pressed.connect(callback)
	panel.add_child(button)
	return button

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
	if net.host(Settings.network_port, Settings.network_name) == OK:
		_start_discovery_responder()

func _join() -> void:
	_save_fields()
	net.join(Settings.network_address, Settings.network_port, Settings.network_name)

func _start_discovery_responder() -> void:
	_stop_discovery_responder()
	discovery_responder = PacketPeerUDP.new()
	var error := discovery_responder.bind(net.port + 1)
	if error != OK:
		discovery_responder = null
		return
	discovery_responder.set_broadcast_enabled(true)

func _stop_discovery_responder() -> void:
	if discovery_responder != null:
		discovery_responder.close()
	discovery_responder = null

func _discover() -> void:
	if net.active:
		set_status("Сначала отключитесь от текущей сетевой игры.")
		return
	if discovery_searcher != null:
		discovery_searcher.close()
	discovery_searcher = PacketPeerUDP.new()
	var error := discovery_searcher.bind(0)
	if error != OK:
		set_status("Не удалось открыть поиск LAN: %s" % error_string(error))
		discovery_searcher = null
		return
	discovery_searcher.set_broadcast_enabled(true)
	discovery_searcher.set_dest_address("255.255.255.255", int(port_input.value) + 1)
	discovery_searcher.put_packet(DISCOVERY_MAGIC.to_utf8_buffer())
	discovery_deadline = Time.get_ticks_msec() / 1000.0 + 3.0
	set_status("Ищем хост в текущей Wi-Fi / LAN сети…")

func _poll_discovery() -> void:
	if discovery_responder != null:
		while discovery_responder.get_available_packet_count() > 0:
			var packet := discovery_responder.get_packet().get_string_from_utf8()
			var sender_ip := discovery_responder.get_packet_ip()
			var sender_port := discovery_responder.get_packet_port()
			if packet == DISCOVERY_MAGIC:
				discovery_responder.set_dest_address(sender_ip, sender_port)
				var response := "%s|%d|%s" % [SERVER_MAGIC, net.port, session.game_modes.mode_name()]
				discovery_responder.put_packet(response.to_utf8_buffer())
	if discovery_searcher == null:
		return
	while discovery_searcher.get_available_packet_count() > 0:
		var response := discovery_searcher.get_packet().get_string_from_utf8()
		var sender_ip := discovery_searcher.get_packet_ip()
		var fields := response.split("|")
		if fields.size() >= 3 and fields[0] == SERVER_MAGIC:
			address_input.text = sender_ip
			port_input.value = int(fields[1])
			set_status("Найден %s: %s:%d. Подключаемся…" % [fields[2], sender_ip, int(fields[1])])
			discovery_searcher.close()
			discovery_searcher = null
			_join.call_deferred()
			return
	if Time.get_ticks_msec() / 1000.0 >= discovery_deadline:
		discovery_searcher.close()
		discovery_searcher = null
		set_status("Хост в LAN не найден. Проверьте одну Wi-Fi сеть или введите IP вручную.")

func _process(_delta: float) -> void:
	if net.is_host() and discovery_responder == null:
		_start_discovery_responder()
	elif not net.active and discovery_responder != null:
		_stop_discovery_responder()
	_poll_discovery()
	network_label.visible = net.active and not panel.visible and session.mode in [session.Mode.PLAYING, session.Mode.PAUSED]
	if net.active:
		network_label.text = "%s  •  %d / 8 ИГРОКОВ  •  UDP %d\nМЕНЮ НЕ ОСТАНАВЛИВАЕТ ИГРУ" % ["ХОСТ" if net.is_host() else "СЕТЕВАЯ ИГРА", net.peers.size(), net.port]

func _exit_tree() -> void:
	_stop_discovery_responder()
	if discovery_searcher != null:
		discovery_searcher.close()
