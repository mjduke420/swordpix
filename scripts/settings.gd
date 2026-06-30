extends Node
## Settings — Autoload for user audio preferences (music / SFX volume + mute).
## Applies the saved volumes to the "Music" and "SFX" audio buses on startup and
## persists changes to user://settings.cfg. These are USER preferences, not game
## state, so they DO persist across runs (unlike the deliberately save-less game).
##
## `build_panel()` returns a ready-made controls widget that both the main menu
## and the in-game settings overlay embed, so there is a single implementation.

const PATH := "user://settings.cfg"

var music_volume := 0.8   # 0.0 .. 1.0 (linear)
var sfx_volume := 0.9     # 0.0 .. 1.0 (linear)
var muted := false


func _ready() -> void:
	load_settings()
	_apply_all()


# ============================================================
#  Public setters (live-apply + persist)
# ============================================================
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_bus("Music", music_volume)
	save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_bus("SFX", sfx_volume)
	save_settings()


func set_muted(m: bool) -> void:
	muted = m
	var idx := AudioServer.get_bus_index("Master")
	if idx != -1:
		AudioServer.set_bus_mute(idx, muted)
	save_settings()


## Linear 0..1 volume -> decibels for a bus (<=0 is true silence). Pure/testable.
func db_for(v: float) -> float:
	return -80.0 if v <= 0.0 else linear_to_db(clampf(v, 0.0, 1.0))


# ============================================================
#  Shared settings widget (embedded by menu + in-game overlay)
# ============================================================
func build_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_slider_row("Music", music_volume, set_music_volume))
	box.add_child(_slider_row("SFX", sfx_volume, set_sfx_volume))
	var mute := CheckBox.new()
	mute.text = "Mute all"
	mute.button_pressed = muted
	mute.focus_mode = Control.FOCUS_NONE   # don't let WASD/ui-nav steal movement keys
	mute.toggled.connect(set_muted)
	box.add_child(mute)
	return box


func _slider_row(label: String, value: float, setter: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(54, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(170, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(setter)
	row.add_child(s)
	return row


# ============================================================
#  Internals
# ============================================================
func _apply_all() -> void:
	_apply_bus("Music", music_volume)
	_apply_bus("SFX", sfx_volume)
	var idx := AudioServer.get_bus_index("Master")
	if idx != -1:
		AudioServer.set_bus_mute(idx, muted)


func _apply_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, db_for(v))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	muted = bool(cfg.get_value("audio", "muted", muted))
