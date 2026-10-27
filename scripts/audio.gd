extends Node
## Original synthesized PCM sounds. No downloads, missing files, or licensing dependencies.
var clips: Dictionary = {}
var ambience: AudioStreamPlayer
var chase: AudioStreamPlayer
var sting: AudioStreamPlayer
var intensity: float = 0.0
var target_intensity: float = 0.0
var enabled: bool = false
var rng = RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 803441
	for bus_name in ["Music", "SFX"]:
		var index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	for kind in ["ambient", "chase", "step", "jump", "land", "slide", "wind", "scream", "scare", "hum", "click", "breaker", "battery", "png_throw", "png_hit", "png_wall", "png_reload", "png_death"]:
		clips[kind] = _synthesize(kind)
	ambience = _player("ambient", "Music", -15.0)
	chase = _player("chase", "Music", -50.0)
	sting = _player("scare", "SFX", -4.0)
	Settings.changed.connect(apply_settings)
	apply_settings()

func _player(kind: String, bus_name: String, db: float) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.stream = clips[kind]
	p.bus = bus_name
	p.volume_db = db
	add_child(p)
	return p

func apply_settings() -> void:
	for pair in [["Master", Settings.master], ["Music", Settings.music], ["SFX", Settings.sfx]]:
		var index = AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, pair[1])))
		AudioServer.set_bus_mute(index, pair[1] <= 0.001)

func _process(delta: float) -> void:
	intensity = move_toward(intensity, target_intensity if enabled else 0.0, delta * 0.65)
	chase.volume_db = lerpf(-48.0, -9.0, intensity)
	chase.pitch_scale = lerpf(0.92, 1.13, intensity)
	if enabled:
		if not ambience.playing:
			ambience.play()
		if not chase.playing:
			chase.play()

func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		ambience.stop()
		chase.stop()

func one_shot(kind: String, db: float = -5.0, pitch: float = 1.0) -> void:
	var p = _player(kind, "SFX", db)
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	p.play()

func spatial(kind: String, parent: Node3D, where: Vector3, db: float = -5.0, loop: bool = false) -> AudioStreamPlayer3D:
	var p = AudioStreamPlayer3D.new()
	p.stream = clips[kind]
	p.bus = "SFX"
	p.volume_db = db
	p.unit_size = 7.0
	p.max_distance = 65.0
	parent.add_child(p)
	p.global_position = where
	if not loop:
		p.finished.connect(p.queue_free)
	p.play()
	return p

func jumpscare() -> void:
	sting.play()

func _synthesize(kind: String) -> AudioStreamWAV:
	var rate = 22050
	var duration: float = {"ambient": 8.0, "chase": 4.0, "step": 0.19, "jump": 0.22, "land": 0.25, "slide": 0.65, "wind": 2.0, "scream": 2.4, "scare": 1.1, "hum": 3.0, "click": 0.07, "breaker": 0.7, "battery": 0.35, "png_throw": 0.2, "png_hit": 0.16, "png_wall": 0.1, "png_reload": 0.65, "png_death": 0.75}[kind]
	var count = int(rate * duration)
	var data = PackedByteArray()
	data.resize(count * 2)
	var filtered: float = 0.0
	for i in range(count):
		var t = float(i) / rate
		var phase = t / duration
		var noise = rng.randf_range(-1.0, 1.0)
		filtered = filtered * 0.91 + noise * 0.09
		var sample: float = 0.0
		match kind:
			"ambient":
				sample = 0.22 * sin(TAU * 43.0 * t) + 0.12 * sin(TAU * 61.0 * t) + filtered * 0.4 + 0.06 * sin(TAU * 109.0 * t) * sin(TAU * 0.25 * t)
			"chase":
				var beat = fmod(t, 0.5)
				var kick = sin(TAU * (46.0 * beat + 2.0 * (1.0 - exp(-beat * 30.0)))) * exp(-beat * 15.0)
				var pulse = exp(-fmod(t, 0.25) * 32.0)
				sample = kick * 0.7 + pulse * sin(TAU * 146.0 * t) * 0.2 + filtered * 0.16 + sin(TAU * 55.0 * t) * 0.15
			"step", "land", "jump":
				sample = (filtered * 2.5 + sin(TAU * 72.0 * t) * 0.35) * exp(-phase * 12.0) * sin(minf(1.0, phase * 40.0) * PI / 2.0)
			"slide":
				sample = (filtered * 2.7 + sin(TAU * 56.0 * t) * 0.12) * sin(minf(1.0, phase * 28.0) * PI * 0.5) * pow(1.0 - phase, 0.8)
			"wind":
				sample = filtered * 0.95 + sin(TAU * 72.0 * t) * 0.018
			"scream":
				var pitch = 360.0 * t + 80.0 * sin(t * 3.0) + 4.0 * sin(t * 30.0)
				sample = (sin(TAU * pitch) * 0.35 + sin(TAU * pitch * 1.49) * 0.2 + filtered * 0.5) * pow(sin(PI * phase), 2.0)
			"scare":
				sample = (noise * 0.4 + sin(TAU * (180.0 * t + 95.0 * t * t)) * 0.35 + sin(TAU * 63.0 * t) * 0.3) * minf(1.0, phase * 120.0) * pow(1.0 - phase, 1.3)
			"hum":
				sample = sin(TAU * 74.0 * t) * 0.3 + sin(TAU * 111.0 * t) * 0.16 + filtered * 0.4
			"click":
				sample = noise * exp(-phase * 25.0) * 0.6
			"breaker":
				sample = (noise * exp(-phase * 13.0) + sin(TAU * 110.0 * t) * exp(-phase * 4.0)) * 0.6
			"battery":
				sample = sin(TAU * (640.0 if phase < 0.5 else 880.0) * t) * sin(PI * phase) * 0.3
			"png_throw":
				sample = (filtered * 2.4 + sin(TAU * (240.0 * t - 380.0 * t * t)) * 0.2) * sin(PI * phase) * (1.0 - phase)
			"png_hit":
				sample = (noise * 0.35 + sin(TAU * 190.0 * t) * 0.45 + sin(TAU * 970.0 * t) * 0.2) * exp(-phase * 8.0)
			"png_wall":
				sample = (filtered * 1.7 + sin(TAU * 115.0 * t) * 0.3) * exp(-phase * 11.0)
			"png_reload":
				var click_phase = fmod(t, 0.2)
				sample = (noise * 0.4 + sin(TAU * 720.0 * t) * 0.2) * exp(-click_phase * 90.0) * (1.0 - phase * 0.4)
			"png_death":
				sample = (sin(TAU * (125.0 * t - 55.0 * t * t)) * 0.5 + filtered * 1.2 + sin(TAU * 330.0 * t) * 0.2) * pow(1.0 - phase, 2.0)
		var integer = int(clampf(sample, -0.95, 0.95) * 32767.0)
		data.encode_s16(i * 2, integer)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if kind in ["ambient", "chase", "hum", "wind"]:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	return stream
