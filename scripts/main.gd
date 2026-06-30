extends Control
## Main menu — pixel-art logo, name/class entry, Host / Join. Builds its UI in
## code with a styled card + animated backdrop; switches to game.tscn on entry.

const GAME_SCENE := "res://scenes/game.tscn"

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _class_picker: OptionButton
var _status: Label
var _btn_mat: ShaderMaterial


func _ready() -> void:
	# Dedicated-server mode (Docker / headless): host the game with no menu and no
	# host player, then stop — clients connect over WebSocket from a browser.
	if _is_server_mode():
		Net.start_dedicated_server()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_make_button_material()
	_build_background()
	_build_ui()
	Net.entered_game.connect(_on_entered_game)
	Net.connection_failed.connect(func(): _set_status("Connection failed.", "#ef4444"))
	Net.server_disconnected.connect(func(): _set_status("Disconnected from host.", "#ef4444"))
	Music.play_state("menu")


# ============================================================
#  Backdrop + styling
# ============================================================
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 c = UV - 0.5;
	float d = length(c);
	float vig = smoothstep(1.0, 0.15, d);
	float pulse = 0.5 + 0.5 * sin(TIME * 0.4);
	vec3 base = vec3(0.035, 0.045, 0.07);
	vec3 glow = vec3(0.13, 0.10, 0.05) * vig * (0.55 + 0.45 * pulse);
	COLOR = vec4(base + glow, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	add_child(bg)


func _make_button_material() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	float s = sin((UV.x + UV.y) * 5.0 - TIME * 2.0) * 0.5 + 0.5;
	s = smoothstep(0.78, 1.0, s) * 0.20;
	COLOR.rgb += vec3(1.0, 0.85, 0.45) * s * COLOR.a;
}
"""
	_btn_mat = ShaderMaterial.new()
	_btn_mat.shader = sh


func _sb(bg: String, border: String, width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bg)
	sb.set_border_width_all(width)
	sb.border_color = Color(border)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	return sb


# ============================================================
#  Layout
# ============================================================
func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(620, 100)
	box.add_child(logo)

	var subtitle := Label.new()
	subtitle.text = "Multiplayer turn-based dungeon crawler"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color("#9aa7bd")
	box.add_child(subtitle)

	# Form card.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sb("#15120d", "#8a6d2f", 2))
	box.add_child(card)
	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(380, 0)
	form.add_theme_constant_override("separation", 8)
	card.add_child(form)

	form.add_child(_labeled("Name"))
	_name_edit = _make_edit("Hero")
	_name_edit.max_length = 15
	form.add_child(_name_edit)

	form.add_child(_labeled("Class"))
	_class_picker = OptionButton.new()
	_class_picker.add_theme_stylebox_override("normal", _sb("#241f1a", "#b8924a"))
	for key in Classes.CLASS_KEYS:
		var cc: Dictionary = Classes.CLASS_DATA[key]
		_class_picker.add_item("%s — %s" % [cc["name"], cc["description"]])
	form.add_child(_class_picker)

	var host_btn := _make_button("Host Game", _on_host)
	form.add_child(host_btn)
	var host_sep := HSeparator.new()
	form.add_child(host_sep)
	var ip_label := _labeled("Host IP (to join)")
	form.add_child(ip_label)
	_ip_edit = _make_edit("127.0.0.1")
	form.add_child(_ip_edit)
	var join_btn := _make_button("Join Game", _on_join)
	form.add_child(join_btn)
	form.add_child(HSeparator.new())

	# In a browser the server is the Docker host: there's nothing to "host" locally
	# and the address is derived from the page, so hide hosting + manual IP entry.
	if OS.has_feature("web"):
		host_btn.visible = false
		host_sep.visible = false
		ip_label.visible = false
		_ip_edit.visible = false
		join_btn.text = "Play"
	form.add_child(_labeled("Audio"))
	form.add_child(Settings.build_panel())

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)


func _labeled(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color("#cbd5e1")
	return l


func _make_edit(value: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.add_theme_stylebox_override("normal", _sb("#0f0d0a", "#5a4a2a", 1))
	e.add_theme_stylebox_override("focus", _sb("#161208", "#caa84a", 1))
	return e


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", _sb("#241f1a", "#b8924a"))
	b.add_theme_stylebox_override("hover", _sb("#332b22", "#ffd86b"))
	b.add_theme_stylebox_override("pressed", _sb("#171310", "#caa84a"))
	b.add_theme_color_override("font_color", Color("#e8d8a0"))
	b.add_theme_color_override("font_hover_color", Color("#fff3c0"))
	b.material = _btn_mat
	b.pressed.connect(cb)
	return b


func _selected_class() -> String:
	return Classes.CLASS_KEYS[_class_picker.selected]


func _on_host() -> void:
	_set_status("Starting host...", "#fbbf24")
	if not Net.host_game(_name_edit.text, _selected_class()):
		_set_status("Failed to start host (port in use?).", "#ef4444")


func _on_join() -> void:
	_set_status("Connecting...", "#fbbf24")
	var target: String = _web_server_url() if OS.has_feature("web") else _ip_edit.text
	if not Net.join_game(target, _name_edit.text, _selected_class()):
		_set_status("Could not start client.", "#ef4444")


## True when launched as a dedicated server: the `dedicated_server` feature (an
## exported server build) or a `--server` command-line flag (running from source).
func _is_server_mode() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	return "--server" in OS.get_cmdline_args() or "--server" in OS.get_cmdline_user_args()


## On web, the game server lives behind the same origin via the Caddy proxy at
## /ws — derive ws(s)://<host>/ws from the page so no manual address is needed.
func _web_server_url() -> String:
	var host := str(JavaScriptBridge.eval("location.host", true))
	var proto := str(JavaScriptBridge.eval("location.protocol", true))
	var scheme := "wss" if proto == "https:" else "ws"
	return "%s://%s/ws" % [scheme, host]


func _on_entered_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _set_status(text: String, color: String) -> void:
	_status.text = text
	_status.modulate = Color(color)
