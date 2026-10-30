class_name MobileControls
extends CanvasLayer
## Touch-first controls used by Android builds. Gameplay still consumes the
## existing InputMap actions, so desktop and network authority stay unchanged.

var session
var root: Control
var joystick_base: Panel
var joystick_knob: Panel
var left_reward_button: Button
var use_button: Button
var tracked_buttons: Array[Button] = []
var joystick_touch := -1
var look_touch := -1
var joystick_center := Vector2(185, 700)
var joystick_radius := 105.0
var actions_held: Dictionary = {}

static func enabled_for_platform() -> bool:
	return OS.has_feature("mobile") or "--mobile-test" in OS.get_cmdline_user_args()

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	joystick_base = _disc(Vector2(65, 580), Vector2(240, 240), Color(0.03, 0.08, 0.09, 0.48), 120)
	joystick_knob = _disc(Vector2(130, 645), Vector2(110, 110), Color(0.42, 0.92, 0.79, 0.68), 55)
	_action_button("FIRE", Vector2(1390, 445), Vector2(155, 115), "throw_png")
	_action_button("AIM", Vector2(1215, 500), Vector2(145, 100), "aim_png")
	_action_button("JUMP", Vector2(1385, 590), Vector2(160, 110), "jump")
	_action_button("SLIDE", Vector2(1195, 650), Vector2(155, 105), "crouch")
	_action_button("SPRINT", Vector2(1015, 720), Vector2(165, 100), "sprint")
	use_button = _tap_button("USE", Vector2(1385, 730), Vector2(160, 105), _use)
	left_reward_button = _tap_button("LEFT", Vector2(1015, 575), Vector2(165, 110), _reward_left)
	_tap_button("LIGHT", Vector2(1215, 365), Vector2(145, 90), _flashlight)
	_tap_button("PNG", Vector2(1080, 25), Vector2(140, 70), _library)
	_tap_button("II", Vector2(1450, 25), Vector2(95, 70), _pause)
	left_reward_button.visible = false
	_reset_joystick()

func _disc(at: Vector2, size: Vector2, color: Color, radius: int) -> Panel:
	var panel := Panel.new()
	panel.position = at
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = Color(0.55, 0.95, 0.84, 0.55)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	return panel

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(18)
	style.border_color = Color(0.55, 0.95, 0.84, 0.72)
	style.set_border_width_all(2)
	return style

func _base_button(text: String, at: Vector2, size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.02, 0.07, 0.08, 0.64)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.20, 0.72, 0.59, 0.82)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.05, 0.18, 0.18, 0.72)))
	root.add_child(button)
	tracked_buttons.append(button)
	return button

func _action_button(text: String, at: Vector2, size: Vector2, action: String) -> Button:
	var button := _base_button(text, at, size)
	button.button_down.connect(_hold_action.bind(action, true))
	button.button_up.connect(_hold_action.bind(action, false))
	return button

func _tap_button(text: String, at: Vector2, size: Vector2, callback: Callable) -> Button:
	var button := _base_button(text, at, size)
	button.pressed.connect(callback)
	return button

func _hold_action(action: String, down: bool) -> void:
	if down:
		actions_held[action] = true
		Input.action_press(action)
	else:
		actions_held.erase(action)
		Input.action_release(action)

func _input(event: InputEvent) -> void:
	if not root.visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if touch.position.distance_to(joystick_center) <= joystick_radius * 1.45 and joystick_touch < 0:
				joystick_touch = touch.index
				_update_joystick(touch.position)
			elif look_touch < 0 and touch.position.x > 480.0 and not _over_button(touch.position):
				look_touch = touch.index
		else:
			if touch.index == joystick_touch:
				joystick_touch = -1
				_release_movement()
				_reset_joystick()
			elif touch.index == look_touch:
				look_touch = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == joystick_touch:
			_update_joystick(drag.position)
		elif drag.index == look_touch and is_instance_valid(session.player):
			session.player.view.look_touch(drag.relative, session.player)

func _over_button(point: Vector2) -> bool:
	for button in tracked_buttons:
		if button.visible and button.get_global_rect().has_point(point):
			return true
	return false

func _update_joystick(point: Vector2) -> void:
	var offset := (point - joystick_center).limit_length(joystick_radius)
	var axis := offset / joystick_radius
	joystick_knob.position = joystick_center + offset - joystick_knob.size * 0.5
	_set_axis_action("left", maxf(0.0, -axis.x))
	_set_axis_action("right", maxf(0.0, axis.x))
	_set_axis_action("forward", maxf(0.0, -axis.y))
	_set_axis_action("back", maxf(0.0, axis.y))

func _set_axis_action(action: String, strength: float) -> void:
	if strength > 0.06:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

func _release_movement() -> void:
	for action in ["left", "right", "forward", "back"]:
		Input.action_release(action)

func _reset_joystick() -> void:
	if is_instance_valid(joystick_knob):
		joystick_knob.position = joystick_center - joystick_knob.size * 0.5

func _use() -> void:
	if not session.is_local_playing():
		return
	if session.post_boss.state == PostBossRewardController.RewardState.REWARD_SELECTION:
		session.post_boss.select_choice(1)
	else:
		session._interact()

func _reward_left() -> void:
	if session.is_local_playing():
		session.post_boss.select_choice(0)

func _flashlight() -> void:
	if session.is_local_playing():
		session.player.view.toggle_flashlight()

func _library() -> void:
	if session.mode in [session.Mode.PLAYING, session.Mode.PAUSED]:
		session.combat_hud.open_library()

func _pause() -> void:
	if session.mode == session.Mode.PLAYING:
		session.pause_run()
	elif session.mode == session.Mode.PAUSED:
		session.resume_run()

func _process(_delta: float) -> void:
	var should_show: bool = session.mode == session.Mode.PLAYING and session.ui.hud.visible and not session.combat_hud.gallery.visible
	if root.visible and not should_show:
		_release_all()
	root.visible = should_show
	if not should_show:
		return
	var choosing: bool = session.post_boss.state == PostBossRewardController.RewardState.REWARD_SELECTION
	left_reward_button.visible = choosing
	use_button.text = "RIGHT" if choosing else "USE"

func _release_all() -> void:
	_release_movement()
	for action in actions_held.keys():
		Input.action_release(str(action))
	actions_held.clear()
	joystick_touch = -1
	look_touch = -1
	_reset_joystick()

func _exit_tree() -> void:
	_release_all()
