extends Node
## Audio — Autoload for dynamic sound synthesis and playback.
## Generates game SFX dynamically in memory (16-bit PCM) to avoid external assets.

const SAMPLE_RATE := 44100
var _sfx := {}


func _ready() -> void:
	# Generate all sound effects on startup.
	_sfx["chime"] = _create_wav(_generate_chime())
	_sfx["slash"] = _create_wav(_generate_slash())
	_sfx["fireball"] = _create_wav(_generate_fireball())
	_sfx["shadow"] = _create_wav(_generate_shadow())
	_sfx["whirlwind"] = _create_wav(_generate_whirlwind())
	_sfx["frost"] = _create_wav(_generate_frost())
	_sfx["volley"] = _create_wav(_generate_volley())
	_sfx["heal_aoe"] = _create_wav(_generate_heal_aoe())


## Play a sound by name. Instantiates a player, plays it, and auto-cleans up.
func play(sfx_name: String) -> void:
	var stream = _sfx.get(sfx_name)
	if stream == null:
		return
	
	var player := AudioStreamPlayer.new()
	# Route to the dedicated "SFX" bus (volume-controlled in Settings) if present.
	if AudioServer.get_bus_index("SFX") != -1:
		player.bus = "SFX"
	add_child(player)
	player.stream = stream
	player.finished.connect(player.queue_free)
	player.play()


func _create_wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


# ============================================================
#  SFX PCM Generation (16-bit signed, little-endian)
# ============================================================

func _generate_chime() -> PackedByteArray:
	var duration := 0.55
	var num_samples := int(SAMPLE_RATE * duration)
	var arr := PackedByteArray()
	arr.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t := float(i) / SAMPLE_RATE
		var val := 0.0
		if t < 0.14:
			# Note 1: E5 (659.25 Hz)
			var env := exp(-12.0 * t)
			val = sin(2.0 * PI * 659.25 * t) * env * 0.25
		else:
			# Note 2: A5 (880.00 Hz)
			var t2 := t - 0.14
			var env := exp(-7.0 * t2)
			val = sin(2.0 * PI * 880.00 * t2) * env * 0.35
			
		var int_val := int(clampf(val, -1.0, 1.0) * 32767.0)
		arr[i * 2] = int_val & 0xFF
		arr[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	return arr


func _generate_slash() -> PackedByteArray:
	var duration := 0.12
	var num_samples := int(SAMPLE_RATE * duration)
	var arr := PackedByteArray()
	arr.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		# Quick pitch sweep from 1400Hz down to 200Hz
		var freq := 1400.0 - 1200.0 * progress
		var sine := sin(2.0 * PI * freq * t)
		var noise := randf_range(-1.0, 1.0)
		var val := (sine * 0.35 + noise * 0.65) * (1.0 - progress) * 0.28
		
		var int_val := int(clampf(val, -1.0, 1.0) * 32767.0)
		arr[i * 2] = int_val & 0xFF
		arr[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	return arr


func _generate_fireball() -> PackedByteArray:
	var duration := 0.38
	var num_samples := int(SAMPLE_RATE * duration)
	var arr := PackedByteArray()
	arr.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		# Deep explosion sweep from 180Hz down to 45Hz
		var freq := 180.0 - 135.0 * progress
		var sine := sin(2.0 * PI * freq * t)
		var noise := randf_range(-1.0, 1.0)
		var val := (sine * 0.25 + noise * 0.75) * exp(-6.5 * t) * 0.32
		
		var int_val := int(clampf(val, -1.0, 1.0) * 32767.0)
		arr[i * 2] = int_val & 0xFF
		arr[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	return arr


func _generate_shadow() -> PackedByteArray:
	var duration := 0.26
	var num_samples := int(SAMPLE_RATE * duration)
	var arr := PackedByteArray()
	arr.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		# Ascending pitch from 400Hz to 1100Hz with a pulsing LFO
		var freq := 400.0 + 700.0 * progress
		var lfo := sin(2.0 * PI * 16.0 * t) * 0.25 + 0.75
		var sine := sin(2.0 * PI * freq * t) * lfo
		var val := sine * (1.0 - progress) * 0.25
		
		var int_val := int(clampf(val, -1.0, 1.0) * 32767.0)
		arr[i * 2] = int_val & 0xFF
		arr[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	return arr


func _generate_whirlwind() -> PackedByteArray:
	var duration := 0.28
	var num_samples := int(SAMPLE_RATE * duration)
	var arr := PackedByteArray()
	arr.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		# Sweeping spin frequency modulated by LFO
		var freq := 550.0 + 250.0 * sin(2.0 * PI * 7.5 * t)
		var sine := sin(2.0 * PI * freq * t)
		var noise := randf_range(-1.0, 1.0)
		var val := (sine * 0.4 + noise * 0.6) * (1.0 - progress) * 0.26
		
		var int_val := int(clampf(val, -1.0, 1.0) * 32767.0)
		arr[i * 2] = int_val & 0xFF
		arr[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	return arr


func _generate_frost() -> PackedByteArray:
	var duration := 0.24
	var num_samples := int(SAMPLE_RATE * duration)
	var arr := PackedByteArray()
	arr.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		# Crackling static with a high pitch sweep
		var freq := 2100.0 - 900.0 * progress
		var sine := sin(2.0 * PI * freq * t)
		var crackle := 1.0 if randf() < 0.26 else 0.0
		var val := (sine * 0.5 + crackle * 0.5) * (1.0 - progress) * 0.22
		
		var int_val := int(clampf(val, -1.0, 1.0) * 32767.0)
		arr[i * 2] = int_val & 0xFF
		arr[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	return arr


func _generate_volley() -> PackedByteArray:
	var duration := 0.20
	var num_samples := int(SAMPLE_RATE * duration)
	var arr := PackedByteArray()
	arr.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		# Clean pitch whistle sweep down from 2400Hz to 900Hz
		var freq := 2400.0 - 1500.0 * progress
		var val := sin(2.0 * PI * freq * t) * (1.0 - progress) * 0.25
		
		var int_val := int(clampf(val, -1.0, 1.0) * 32767.0)
		arr[i * 2] = int_val & 0xFF
		arr[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	return arr


func _generate_heal_aoe() -> PackedByteArray:
	var duration := 0.42
	var num_samples := int(SAMPLE_RATE * duration)
	var arr := PackedByteArray()
	arr.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		# Sparkly vibrato sweep upwards
		var vibrato := sin(2.0 * PI * 22.0 * t) * 35.0
		var freq := 450.0 + 1350.0 * progress + vibrato
		var val := sin(2.0 * PI * freq * t) * exp(-4.5 * t) * 0.26
		
		var int_val := int(clampf(val, -1.0, 1.0) * 32767.0)
		arr[i * 2] = int_val & 0xFF
		arr[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	return arr
