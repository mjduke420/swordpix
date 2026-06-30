extends Node2D
## Play scene — top-down grid renderer + HUD + input. Port of client/game.js
## renderMap()/HUD. Rebuilds the whole board on every Net.state_updated, exactly
## like the original's full-redraw model.

const TILE := 48
const GRID := 15

const TILE_SPRITE := {
	".": "ground", "#": "wall", "T": "tree", "~": "water",
	"^": "stalagmite", "*": "rocks", "I": "water", "L": "lava",
	"G": "gears", "Z": "pistons",   # Clockwork Spire decoration / hazard
	"D": "door", "A": "altar",      # interactive: locked hatch / altar
}
# Decoration tiles with transparent sprites — drawn over a ground tile.
const DECOR_TILES := ["T", "^", "*", "G", "Z", "D", "A"]

# Line-of-sight: per-player vision radius (sight helpers live in LOS / los.gd).
const VISION_RADIUS := 4
const DIM := Color(0.34, 0.34, 0.46, 1.0)   # explored-but-not-currently-visible
const SIDE_WIDTH := 340                      # fixed width of the right HUD column
const PARTY_WIDTH := 210                      # fixed width of the left party column

# VFX particle tint per combat-effect / hazard type.
const BOONS := [
	{"id": "vitality", "name": "Vitality", "desc": "+25 max HP"},
	{"id": "power", "name": "Power", "desc": "+6 attack damage"},
	{"id": "precision", "name": "Precision", "desc": "+2 DEX, +1 AC"},
	{"id": "arcane", "name": "Arcane", "desc": "+25 max MP"},
	{"id": "bulwark", "name": "Bulwark", "desc": "+2 Armor Class"},
	{"id": "ferocity", "name": "Ferocity", "desc": "+1 STR & +1 CON"},
]
const VFX_COLORS := {
	"slash": Color("#e2e8f0"), "fireball": Color("#f97316"), "frost": Color("#38bdf8"),
	"shadow": Color("#a855f7"), "whirlwind": Color("#fbbf24"), "heal_aoe": Color("#34d399"),
	"volley": Color("#4ade80"),
	# Per-round biome hazards + traps.
	"drown": Color("#38bdf8"), "hellfire": Color("#ff5530"), "heat": Color("#f59e0b"),
	"rotate": Color("#fb923c"), "trap": Color("#ef4444"),
}
# Hazards whose particles rise (true) vs. fall (false). Default = outward burst.
const VFX_RISE := {"drown": true, "hellfire": true, "heat": true, "frost": false}

const LosScript = preload("res://scripts/los.gd")
var _los = LosScript.new()   # line-of-sight helper instance

var _tex := {}            # name -> Texture2D
var _world: Node2D        # tiles + entities (inside the map SubViewport)
var _torch_layer: Node2D  # torch sprites + fire particles (persistent)
var _torch_nodes := {}    # torch_id -> Node2D (sprite + flame)
var _torch_sig := ""      # signature of current torch set (rebuild when it changes)
var _fx_layer: Node2D     # particle effects (NOT cleared each render)
var _viewport: SubViewport
var _camera: Camera2D
var _round_label: Label
var _turn_bar: HBoxContainer    # initiative order, shown during combat
var _party_box: VBoxContainer   # connected-players roster (left column)
var _party_title: Label
var _party_cards := {}          # pid -> {card, name, sub, hp, mp} (kept across updates)
var _prev_vitals := {}          # pid -> {hp, mp} for detecting damage / mana spend
var _log_box: VBoxContainer
var _log_scroll: ScrollContainer
var _chat_input: LineEdit
var _last_region := -1
var _last_turn_id = null
var _last_phase: String = ""
var _music_state: String = ""   # current background-music state (explore/combat/boss)
var _explored := {}        # Vector2i -> true: tiles ever seen this region
var _fog_region := -1      # region the _explored set belongs to
var _action_row: Container
var _overlay: PanelContainer       # inventory / shop overlay
var _overlay_box: VBoxContainer
var _overlay_backdrop: ColorRect
var _stats_pid := -1
var _dice_layer: CanvasLayer        # transient animated dice (above the HUD)

# Conditional action buttons (toggled by phase / cleared state).
var _btn_attack: Button
var _btn_ability: Button
var _btn_roll: Button
var _btn_end: Button
var _btn_next: Button
var _btn_loot: Button
var _btn_shop: Button
var _btn_bash: Button
var _btn_pick: Button
var _btn_pray: Button
var _btn_hide: Button
var _btn_examine: Button
var _btn_qa: Button
var _btn_nuke: Button
var _btn_boon: Button
var _qa_mode := false

# Button look: shared D&D-styled styleboxes + a golden sheen shader.
var _btn_mat: ShaderMaterial
var _sb_normal: StyleBoxFlat
var _sb_hover: StyleBoxFlat
var _sb_pressed: StyleBoxFlat
var _dot_tex: Texture2D
var _overlay_mode := ""            # "" | "inv" | "shop"


func _ready() -> void:
	_preload_textures()
	_make_dot_texture()
	_make_button_assets()
	_build_ui()
	Net.state_updated.connect(_render)
	Net.log_message.connect(_on_log)
	Net.vfx.connect(_on_vfx)
	Net.dice_rolled.connect(_on_dice)
	if not Net.last_state.is_empty():
		_render(Net.last_state)


## A soft round dot used as the particle sprite (GL-compat CPUParticles2D).
func _make_dot_texture() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var d := Vector2(x - 7.5, y - 7.5).length() / 8.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot_tex = ImageTexture.create_from_image(img)


## Shared button theme: dark panel + gold border + animated golden sheen shader.
func _make_button_assets() -> void:
	_sb_normal = _make_sb("#241f1a", "#b8924a")
	_sb_hover = _make_sb("#332b22", "#ffd86b")
	_sb_pressed = _make_sb("#171310", "#caa84a")
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


func _make_sb(bg: String, border: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bg)
	sb.set_border_width_all(2)
	sb.border_color = Color(border)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(7)
	return sb


func _style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _sb_normal)
	b.add_theme_stylebox_override("hover", _sb_hover)
	b.add_theme_stylebox_override("pressed", _sb_pressed)
	b.add_theme_stylebox_override("focus", _sb_hover)
	b.add_theme_color_override("font_color", Color("#e8d8a0"))
	b.add_theme_color_override("font_hover_color", Color("#fff3c0"))
	b.custom_minimum_size = Vector2(0, 34)
	b.material = _btn_mat


func _preload_textures() -> void:
	var names := ["ground", "wall", "tree", "water", "stalagmite", "rocks", "lava", "gears", "pistons",
		"door", "altar",
		"warrior", "mage", "rogue", "cleric", "ranger",
		"goblin", "orc", "slime", "boss", "chest", "merchant", "potion", "torch"]
	for n in names:
		var path := "res://assets/%s.png" % n
		if ResourceLoader.exists(path):
			_tex[n] = load(path)


## Two-column layout: a bordered map box on the left (its own SubViewport with a
## player-following camera) and a fixed-width column of panels on the right, so
## the HUD never overlaps the play area.
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 10)
	root.add_theme_constant_override("margin_right", 10)
	root.add_theme_constant_override("margin_top", 10)
	root.add_theme_constant_override("margin_bottom", 10)
	layer.add_child(root)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	root.add_child(cols)

	_build_party_panel(cols)
	_build_map_panel(cols)
	_build_side_panel(cols)
	_build_overlay(layer)

	# Dedicated top layer for transient animated dice (drawn above everything).
	_dice_layer = CanvasLayer.new()
	_dice_layer.layer = 10
	add_child(_dice_layer)


## Left column: the connected-players roster (name, level/class, HP/MP).
func _build_party_panel(parent: Control) -> void:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(PARTY_WIDTH, 0)
	parent.add_child(box)
	var vb := VBoxContainer.new()
	box.add_child(vb)
	_party_title = Label.new()
	_party_title.text = "Party"
	_party_title.add_theme_font_size_override("font_size", 16)
	vb.add_child(_party_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_party_box = VBoxContainer.new()
	_party_box.custom_minimum_size = Vector2(PARTY_WIDTH - 24, 0)
	_party_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_party_box)


func _build_map_panel(parent: Control) -> void:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)

	var vb := VBoxContainer.new()
	box.add_child(vb)
	var title := Label.new()
	title.text = "  World Map"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)

	# Turn-order strip — a fixed-height bar that's always present (so the
	# viewport never resizes), populated with the initiative order in combat.
	var turn_panel := PanelContainer.new()
	turn_panel.custom_minimum_size = Vector2(0, 32)
	vb.add_child(turn_panel)
	_turn_bar = HBoxContainer.new()
	_turn_bar.add_theme_constant_override("separation", 8)
	_turn_bar.clip_contents = true
	turn_panel.add_child(_turn_bar)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(svc)

	_viewport = SubViewport.new()
	_viewport.handle_input_locally = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	svc.add_child(_viewport)

	_world = Node2D.new()
	_viewport.add_child(_world)
	_torch_layer = Node2D.new()   # torches + their fire particles (rebuilt only when torches change)
	_viewport.add_child(_torch_layer)
	_fx_layer = Node2D.new()   # particles live here so _render's clear doesn't kill them
	_viewport.add_child(_fx_layer)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(1.6, 1.6)
	_camera.position = Vector2(GRID * TILE / 2.0, GRID * TILE / 2.0)
	_viewport.add_child(_camera)
	_camera.make_current()


func _build_side_panel(parent: Control) -> void:
	# Fixed-width column: it never expands and its labels clip, so combat text
	# ("YOUR TURN" / "waiting…") can never reflow the layout or the map viewport.
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	col.size_flags_horizontal = Control.SIZE_FILL
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	# Top bar: round / region label (whose-turn is shown by the turn-order bar).
	var top := PanelContainer.new()
	col.add_child(top)
	_round_label = Label.new()
	_round_label.add_theme_font_size_override("font_size", 14)
	_round_label.clip_text = true
	top.add_child(_round_label)

	# (Local player stats live in the left Party list now — no duplicate panel.)

	# Action buttons (2-column grid). Combat actions and Next Region are toggled
	# in _update_hud based on phase / whether the area is cleared.
	_action_row = GridContainer.new()
	_action_row.columns = 2
	col.add_child(_action_row)
	_btn_attack = _add_action("Attack", {"type": "attack"}, "#fb923c")
	_btn_ability = _add_action("Ability", {"type": "ability"}, "#c084fc")
	_add_action("Heal", {"type": "heal"}, "#f87171")
	_add_action("Mana", {"type": "mana"}, "#60a5fa")
	_btn_roll = _add_action("Roll Init", {"type": "roll_initiative"}, "#fbbf24")
	_btn_next = _add_action("Next Region", {"type": "ready"}, "#4ade80")
	_add_button("Inv", _toggle_inventory, "#d8b98a")
	_add_button("Guild", _toggle_guild, "#a5b4fc")
	_btn_loot = _add_button("Loot", _do_loot, "#fcd34d")
	_btn_shop = _add_button("Shop", _toggle_shop, "#34d399")
	_btn_bash = _add_button("Bash", func(): Net.send_action({"type": "bash"}), "#f59e0b")
	_btn_pick = _add_button("Pick", func(): Net.send_action({"type": "pick"}), "#2dd4bf")
	_btn_pray = _add_button("Pray", func(): Net.send_action({"type": "pray"}), "#fde68a")
	_btn_hide = _add_button("Hide", func(): Net.send_action({"type": "hide"}), "#94a3b8")
	_btn_examine = _add_button("Examine", func(): Net.send_action({"type": "examine"}), "#67e8f9")
	_btn_end = _add_button("End Turn", func(): Net.send_action({"type": "end_turn"}), "#cbd5e1")
	_btn_qa = _add_button("QA", _toggle_qa, "#e879f9")
	_btn_nuke = _add_button("Nuke", func(): Net.send_action({"type": "qa_nuke"}), "#f87171")
	_btn_boon = _add_button("Boon", _open_boon, "#facc15")
	_add_button("Settings", _open_settings, "#cbd5e1")

	# Chat / log box (fills remaining height) — gold outline like the buttons.
	var chat := PanelContainer.new()
	chat.add_theme_stylebox_override("panel", _make_sb("#15120d", "#8a6d2f"))
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(chat)
	var cvb := VBoxContainer.new()
	chat.add_child(cvb)
	var chat_title := Label.new()
	chat_title.text = "Global Chat"
	chat_title.add_theme_font_size_override("font_size", 15)
	cvb.add_child(chat_title)
	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.custom_minimum_size = Vector2(300, 240)
	cvb.add_child(_log_scroll)
	_log_box = VBoxContainer.new()
	_log_box.custom_minimum_size = Vector2(300, 0)
	_log_scroll.add_child(_log_box)
	var input_row := HBoxContainer.new()
	cvb.add_child(input_row)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Say something..."
	_chat_input.max_length = 100
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(_on_chat_submitted)
	input_row.add_child(_chat_input)
	var send_btn := Button.new()
	send_btn.text = "Send"
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.pressed.connect(func(): _on_chat_submitted(_chat_input.text))
	input_row.add_child(send_btn)


func _build_overlay(layer: CanvasLayer) -> void:
	_overlay_backdrop = ColorRect.new()
	_overlay_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_backdrop.color = Color(0, 0, 0, 0.45)
	_overlay_backdrop.visible = false
	_overlay_backdrop.gui_input.connect(_on_backdrop_input)
	layer.add_child(_overlay_backdrop)
	_overlay = PanelContainer.new()
	_overlay.add_theme_stylebox_override("panel", _make_sb("#15120d", "#8a6d2f"))
	_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_overlay.position = Vector2(-220, -200)
	_overlay.custom_minimum_size = Vector2(440, 400)
	_overlay.visible = false
	layer.add_child(_overlay)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 380)
	_overlay.add_child(scroll)
	_overlay_box = VBoxContainer.new()
	_overlay_box.custom_minimum_size = Vector2(400, 0)
	scroll.add_child(_overlay_box)


# ============================================================
#  Rendering (mirrors renderMap full rebuild)
# ============================================================
func _render(state: Dictionary) -> void:
	var phase_now: String = state.get("phase", "")
	if phase_now == "INITIATIVE" and _last_phase != "INITIATIVE":
		_show_combat_banner()
	_last_phase = phase_now
	_update_music(state, phase_now)
	for c in _world.get_children():
		c.queue_free()
	var map: Array = state.get("map", [])

	# Fog of war: vision is computed from the LOCAL player's position. Reset the
	# explored memory when the region changes.
	var region: int = state.get("region", -1)
	if region != _fog_region:
		_fog_region = region
		_explored = {}
	var lp: Dictionary = state.get("players", {}).get(Net.local_id, {})
	var have_fog: bool = not lp.is_empty()
	var vis_set := {}
	if have_fog:
		vis_set = _los.compute_visible(map, lp["x"], lp["y"], VISION_RADIUS)
		# A torch you can see casts its own pool of light, revealing tiles around it.
		for t in state.get("torches", {}).values():
			if vis_set.has(Vector2i(t["x"], t["y"])):
				for cell in _los.compute_visible(map, t["x"], t["y"], int(t.get("radius", 3))):
					vis_set[cell] = true
		for cell in vis_set:
			_explored[cell] = true
		# Keep the camera centred on the local player.
		_camera.position = Vector2(lp["x"] * TILE + TILE / 2.0, lp["y"] * TILE + TILE / 2.0)

	# A pale wash of the biome's accent colour gives each biome its own ground hue.
	var ground_tint := Color(state.get("biome", {}).get("accent", "#ffffff")).lerp(Color.WHITE, 0.62)
	var safe_tint := Color("#34d399").lerp(Color.WHITE, 0.45)   # Sunless Sea air-bubble islands
	var sunless: bool = state.get("biome", {}).get("name", "") == "The Sunless Sea"

	# Tiles: bright if visible, dim if explored, hidden if never seen.
	for y in range(map.size()):
		for x in range(map[y].size()):
			var cell := Vector2i(x, y)
			var is_vis: bool = (not have_fog) or vis_set.has(cell)
			if not is_vis and not _explored.has(cell):
				continue
			var ch: String = map[y][x]
			# Decorations have transparent backgrounds — lay tinted ground beneath.
			if ch in DECOR_TILES:
				var g := _add_sprite("ground", x, y, 1.0)
				g.modulate = DIM if not is_vis else ground_tint
			# In the Sunless Sea, open floor is drowning water; 'B' tiles are safe.
			var base_name: String = TILE_SPRITE.get(ch, "ground")
			if sunless and ch == ".":
				base_name = "water"
			elif ch == "B":
				base_name = "ground"
			var spr := _add_sprite(base_name, x, y, 1.0)
			if not is_vis:
				spr.modulate = DIM
			elif ch == "B":
				spr.modulate = safe_tint
			elif base_name == "ground":
				spr.modulate = ground_tint
			# Pitfalls have no sprite — draw a dark hole over the ground.
			if ch == "P":
				_add_dot(x, y, Color(0.03, 0.03, 0.05, 0.92) if is_vis else DIM, 0.82)

	# Ground loot / chests — only when currently visible.
	for it in state.get("items", {}).values():
		if have_fog and not vis_set.has(Vector2i(it["x"], it["y"])):
			continue
		if it["type"] == "chest":
			_add_sprite("chest", it["x"], it["y"], 0.7)
		elif it["type"] == "potion":
			_add_sprite("potion", it["x"], it["y"], 0.55)
		elif it["type"] == "portal":
			_add_portal(it["x"], it["y"])
		else:
			_add_marker(it["x"], it["y"], Color(it.get("color", "#ffffff")))

	# Revealed traps (only spotted ones are sent) — red warning marker.
	for tr in state.get("traps", {}).values():
		if have_fog and not vis_set.has(Vector2i(tr["x"], tr["y"])):
			continue
		_add_marker(tr["x"], tr["y"], Color("#ef4444"))

	# Merchant / NPCs — the wandering merchant only appears during exploration.
	if state.get("phase", "") == "EXPLORATION":
		for n in state.get("npcs", {}).values():
			if have_fog and not vis_set.has(Vector2i(n["x"], n["y"])):
				continue
			_add_sprite(n.get("sprite", "merchant"), n["x"], n["y"], 0.85)
			_add_name(n, false)

	# Monsters hide in the fog — only drawn when their tile is currently visible.
	for m in state.get("monsters", {}).values():
		if have_fog and not vis_set.has(Vector2i(m["x"], m["y"])):
			continue
		var is_boss: bool = m.get("is_boss", false)
		var sp := _add_sprite(m.get("sprite", "goblin"), m["x"], m["y"], 1.05 if is_boss else 0.82)
		if is_boss:
			sp.modulate = Color(m.get("color", "#ffffff"))
		elif m.get("elite", "") != "":
			sp.modulate = Color("#fcd34d")
		_add_hp_bar(m)
		_add_status_badges(m)
		if is_boss or m.get("elite", "") != "":
			_add_name(m, false)

	# Party members are always shown.
	for pid in state.get("players", {}):
		var p: Dictionary = state["players"][pid]
		var spr := _add_sprite(p.get("sprite", "warrior"), p["x"], p["y"], 0.86)
		spr.flip_h = p.get("facing_left", false)
		_add_name(p, pid == Net.local_id)
		_add_status_badges(p)

	_update_torches(state, vis_set, have_fog)
	_update_hud(state)
	_update_turn_bar(state)
	_update_party(state)
	_maybe_announce_region(state)
	if _overlay_mode != "":
		_refresh_overlay(state)

	# Combat turn chime for the local player. current_turn_id is int (player) or
	# String (monster); the typeof guard short-circuits so we never compare across
	# types (which GDScript throws on).
	var ct = state.get("current_turn_id", null)
	if state.get("phase", "") != "PLAYERS":
		_last_turn_id = null
	else:
		var changed: bool = typeof(ct) != typeof(_last_turn_id) or ct != _last_turn_id
		if changed:
			_last_turn_id = ct
			if typeof(ct) == TYPE_INT and ct == Net.local_id:
				Audio.play("chime")


## Small diamond marker for non-sprite ground loot (weapons/armor/gold/scroll).
func _add_marker(gx: int, gy: int, color: Color) -> void:
	var r := ColorRect.new()
	r.color = color
	r.size = Vector2(TILE * 0.34, TILE * 0.34)
	r.rotation = PI / 4.0
	r.position = Vector2(gx * TILE + TILE * 0.5, gy * TILE + TILE * 0.5)
	_world.add_child(r)


## Soft round dot overlay (used for pitfall holes).
func _add_dot(gx: int, gy: int, color: Color, scale_factor: float) -> void:
	var s := Sprite2D.new()
	s.texture = _dot_tex
	s.modulate = color
	var px: float = TILE * scale_factor / float(_dot_tex.get_width())
	s.scale = Vector2(px, px)
	s.position = Vector2(gx * TILE + TILE * 0.5, gy * TILE + TILE * 0.5)
	_world.add_child(s)


## A glowing purple portal disc (additive halo + bright core).
func _add_portal(gx: int, gy: int) -> void:
	var center := Vector2(gx * TILE + TILE * 0.5, gy * TILE + TILE * 0.5)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var halo := Sprite2D.new()
	halo.texture = _dot_tex
	halo.modulate = Color(0.66, 0.33, 0.95, 0.55)
	var hs: float = TILE * 1.2 / float(_dot_tex.get_width())
	halo.scale = Vector2(hs, hs)
	halo.position = center
	halo.material = add_mat
	_world.add_child(halo)
	var core := Sprite2D.new()
	core.texture = _dot_tex
	core.modulate = Color(0.85, 0.6, 1.0, 0.9)
	var cs: float = TILE * 0.55 / float(_dot_tex.get_width())
	core.scale = Vector2(cs, cs)
	core.position = center
	_world.add_child(core)


# ============================================================
#  Torch light sources (persistent — rebuilt only when torches change)
# ============================================================
func _update_torches(state: Dictionary, vis_set: Dictionary, have_fog: bool) -> void:
	var torches: Dictionary = state.get("torches", {})
	# Rebuild the torch nodes only when the torch set changes (region advance).
	var sig := ""
	for t in torches.values():
		sig += "%s:%d,%d;" % [t["id"], t["x"], t["y"]]
	if sig != _torch_sig:
		_torch_sig = sig
		for c in _torch_layer.get_children():
			c.queue_free()
		_torch_nodes = {}
		for t in torches.values():
			_torch_nodes[t["id"]] = _make_torch_node(t["x"], t["y"])

	# Each frame: a torch glows + burns only while currently lit; dim if explored.
	for t in torches.values():
		var node: Node2D = _torch_nodes.get(t["id"])
		if node == null:
			continue
		var cell := Vector2i(t["x"], t["y"])
		var lit: bool = (not have_fog) or vis_set.has(cell)
		var seen: bool = lit or _explored.has(cell)
		node.visible = seen
		node.modulate = Color.WHITE if lit else DIM
		var flame: CPUParticles2D = node.get_meta("flame")
		flame.emitting = lit
		node.get_meta("glow").visible = lit


func _make_torch_node(tx: int, ty: int) -> Node2D:
	var node := Node2D.new()
	node.position = Vector2(tx * TILE + TILE / 2.0, ty * TILE + TILE / 2.0)

	# Warm additive glow halo.
	var glow := Sprite2D.new()
	glow.texture = _dot_tex
	glow.modulate = Color(1.0, 0.6, 0.25, 0.32)
	var gscale: float = TILE * 3.0 / float(_dot_tex.get_width())
	glow.scale = Vector2(gscale, gscale)
	var gmat := CanvasItemMaterial.new()
	gmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gmat
	node.add_child(glow)
	node.set_meta("glow", glow)

	# Torch sprite.
	var spr := Sprite2D.new()
	spr.texture = _tex.get("torch")
	if spr.texture != null:
		var s: float = TILE * 0.62 / float(spr.texture.get_width())
		spr.scale = Vector2(s, s)
	node.add_child(spr)

	# Fire particles rising from the flame.
	var flame := _make_fire()
	flame.position = Vector2(0, -TILE * 0.22)
	node.add_child(flame)
	node.set_meta("flame", flame)

	_torch_layer.add_child(node)
	return node


func _make_fire() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _dot_tex
	p.amount = 16
	p.lifetime = 0.6
	p.preprocess = 0.6
	p.direction = Vector2(0, -1)
	p.spread = 22.0
	p.gravity = Vector2(0, -14)
	p.initial_velocity_min = 16.0
	p.initial_velocity_max = 38.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.5, 1.0))     # bright yellow core
	grad.set_color(1, Color(0.7, 0.12, 0.05, 0.0))    # fade to transparent red
	grad.add_point(0.45, Color(1.0, 0.55, 0.12, 0.9)) # orange mid
	p.color_ramp = grad
	return p


func _add_sprite(tex_name: String, gx: int, gy: int, scale_factor: float) -> Sprite2D:
	var s := Sprite2D.new()
	var tex: Texture2D = _tex.get(tex_name, _tex.get("ground"))
	if tex == null:
		return s
	s.texture = tex
	var px: float = TILE / float(tex.get_width()) * scale_factor
	s.scale = Vector2(px, px)
	s.position = Vector2(gx * TILE + TILE / 2.0, gy * TILE + TILE / 2.0)
	_world.add_child(s)
	return s


## Maps an entity's status_effects (+ stealth) to a string of emoji badges.
func _status_badges(entity: Dictionary) -> String:
	if entity.get("is_hidden", false) or not entity.get("status_effects", []).is_empty():
		return "!"
	return ""


## Human-readable list of an entity's active conditions for the details overlay.
func _status_text(entity: Dictionary) -> String:
	var parts := PackedStringArray()
	if entity.get("is_hidden", false):
		parts.append("Hidden")
	for eff in entity.get("status_effects", []):
		var t: String = str(eff.get("type", "")).capitalize()
		var dur: int = int(eff.get("duration", 0))
		parts.append("%s (%d)" % [t, dur] if dur > 0 else t)
	if parts.is_empty():
		return "None"
	return ", ".join(parts)


## Draw the status badges above an entity's map token.
func _add_status_badges(entity: Dictionary) -> void:
	var txt := _status_badges(entity)
	if txt == "":
		return
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color("#fbbf24"))
	l.position = Vector2(entity["x"] * TILE, entity["y"] * TILE - 26)
	l.size = Vector2(TILE, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world.add_child(l)


func _add_hp_bar(m: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.size = Vector2(TILE * 0.8, 5)
	bg.position = Vector2(m["x"] * TILE + TILE * 0.1, m["y"] * TILE + 2)
	_world.add_child(bg)
	var frac: float = clampf(float(m["hp"]) / float(m["max_hp"]), 0.0, 1.0)
	var fg := ColorRect.new()
	fg.color = Color("#ef4444")
	fg.size = Vector2(TILE * 0.8 * frac, 5)
	fg.position = bg.position
	_world.add_child(fg)


func _add_name(p: Dictionary, is_local: bool) -> void:
	var l := Label.new()
	l.text = p["name"]
	l.add_theme_font_size_override("font_size", 11)
	l.modulate = Color("#ffd24a") if is_local else Color("#e2e8f0")
	l.position = Vector2(p["x"] * TILE, p["y"] * TILE - 14)
	l.size = Vector2(TILE, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world.add_child(l)


## Spawn a one-shot particle burst for a combat effect or biome hazard.
## A quick bright core that pops and fades — sells the impact of a hit.
func _spawn_impact_flash(pos: Vector2, col: Color) -> void:
	var f := CPUParticles2D.new()
	f.texture = _dot_tex
	f.position = pos
	f.one_shot = true
	f.amount = 10
	f.explosiveness = 1.0
	f.lifetime = 0.28
	f.spread = 180.0
	f.initial_velocity_min = 0.0
	f.initial_velocity_max = 40.0
	f.scale_amount_min = 4.0
	f.scale_amount_max = 7.0
	f.color = col.lerp(Color.WHITE, 0.6)
	f.emitting = true
	_fx_layer.add_child(f)
	get_tree().create_timer(0.7).timeout.connect(f.queue_free)



## A combat damage (or heal) number that floats up over a token and fades.
func _spawn_damage_number(effect: Dictionary) -> void:
	var amount: int = int(effect.get("amount", 0))
	if amount == 0:
		return
	var is_heal: bool = effect.get("heal", false)
	var lbl := Label.new()
	lbl.text = ("+%d" % amount) if is_heal else ("-%d" % amount)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color("#4ade80") if is_heal else Color("#fca5a5"))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(effect["x"] * TILE, effect["y"] * TILE - 8)
	lbl.size = Vector2(TILE, 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.z_index = 50
	_fx_layer.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 34.0, 0.9)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.set_parallel(false)
	tw.tween_callback(lbl.queue_free)


func _on_vfx(effect: Dictionary) -> void:
	if not effect.has("x"):
		return
	var type: String = effect.get("type", "slash")
	Audio.play(type)   # no-ops for hazard types without a matching SFX
	if effect.has("amount"):
		_spawn_damage_number(effect)
	var col: Color = VFX_COLORS.get(type, Color.WHITE)
	var p := CPUParticles2D.new()
	p.texture = _dot_tex
	p.position = Vector2(effect["x"] * TILE + TILE / 2.0, effect["y"] * TILE + TILE / 2.0)
	p.one_shot = true
	p.lifetime = 0.7
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = col
	if VFX_RISE.has(type):
		# Hazard column: drift up (fire/heat/bubbles) or settle down (frost).
		var rising: bool = VFX_RISE[type]
		p.amount = 22
		p.explosiveness = 0.5
		p.spread = 28.0
		p.direction = Vector2(0, -1 if rising else 1)
		p.initial_velocity_min = 30.0
		p.initial_velocity_max = 80.0
		p.gravity = Vector2(0, -40 if rising else 50)
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = TILE * 0.4
		p.lifetime = 0.9
	else:
		# Outward burst (combat hits, gear sparks) — snappy, with a hot core flash.
		p.amount = 46
		p.explosiveness = 1.0
		p.spread = 180.0
		p.direction = Vector2(0, -1)
		p.initial_velocity_min = 90.0
		p.initial_velocity_max = 240.0
		p.damping_min = 40.0
		p.damping_max = 110.0
		p.gravity = Vector2(0, 60)
		p.lifetime = 0.5
		_spawn_impact_flash(p.position, col)
	p.emitting = true
	_fx_layer.add_child(p)
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


## Animated d20: a die tumbles through random faces, lands on the rolled value,
## then shows the total. Triggered by initiative rolls (push_dice from the server).
func _on_dice(dice: Dictionary) -> void:
	if dice.get("kind", "") != "initiative":
		if dice.has("target_ac"):
			_show_combat_die(dice)
		return   # other d20s stay chat-only
	var roll: int = int(dice.get("roll", 1))
	var mod: int = int(dice.get("mod", 0))
	var total: int = int(dice.get("total", roll + mod))
	var who: String = str(dice.get("name", ""))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	_dice_layer.add_child(box)

	var face := Panel.new()
	face.custom_minimum_size = Vector2(120, 120)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1e293b")
	sb.border_color = Color("#fbbf24")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	face.add_theme_stylebox_override("panel", sb)
	box.add_child(face)

	var num := Label.new()
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", 56)
	num.add_theme_color_override("font_color", Color("#fde68a"))
	num.text = str(roll)
	face.add_child(num)

	var caption := Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color("#e2e8f0"))
	caption.text = "%s rolls initiative" % who
	box.add_child(caption)

	# Tumble (~0.6s of random faces), settle on the roll, reveal the total, fade.
	var sign_str := "+" if mod >= 0 else ""
	var tw := create_tween()
	tw.tween_method(func(_t: float): num.text = str(randi_range(1, 20)), 0.0, 1.0, 0.6)
	tw.tween_callback(func():
		num.text = str(roll)
		num.add_theme_color_override("font_color", Color("#fbbf24") if roll < 20 else Color("#4ade80"))
		caption.text = "%s:  %d %s%d = %d" % [who, roll, sign_str, mod, total])
	tw.tween_interval(1.1)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(box.queue_free)


func _show_combat_die(dice: Dictionary) -> void:
	var roll: int = int(dice.get("roll", 1))
	var mod: int = int(dice.get("mod", 0))
	var ac: int = int(dice.get("target_ac", 0))
	var total: int = roll + mod
	var crit: bool = roll >= 20
	var fumble: bool = roll <= 1
	var hit: bool = total >= ac
	var result_color: Color = Color("#4ade80") if crit else (Color("#f87171") if fumble else (Color("#86efac") if hit else Color("#fca5a5")))
	var result_text: String = "CRIT!" if crit else ("FUMBLE!" if fumble else (("HIT  %d vs %d" % [total, ac]) if hit else ("MISS  %d vs %d" % [total, ac])))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	_dice_layer.add_child(box)
	var face := Panel.new()
	face.custom_minimum_size = Vector2(84, 84)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1e293b")
	sb.border_color = Color("#fbbf24")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	face.add_theme_stylebox_override("panel", sb)
	box.add_child(face)
	var num := Label.new()
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", 40)
	num.add_theme_color_override("font_color", Color("#fde68a"))
	num.text = str(roll)
	face.add_child(num)
	var cap := Label.new()
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 14)
	cap.add_theme_color_override("font_color", Color("#e2e8f0"))
	box.add_child(cap)
	var tw := create_tween()
	tw.tween_method(func(_t: float): num.text = str(randi_range(1, 20)), 0.0, 1.0, 0.35)
	tw.tween_callback(func():
		num.text = str(roll)
		num.add_theme_color_override("font_color", result_color)
		sb.border_color = result_color
		cap.text = result_text
		cap.add_theme_color_override("font_color", result_color))
	tw.tween_interval(0.6)
	tw.tween_property(box, "modulate:a", 0.0, 0.35)
	tw.tween_callback(box.queue_free)


func _show_combat_banner() -> void:
	Audio.play("chime")
	var banner := PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.position = Vector2(-260, -60)
	banner.custom_minimum_size = Vector2(520, 0)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#3b0a0a")
	sb.border_color = Color("#ff4444")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	banner.add_theme_stylebox_override("panel", sb)
	_dice_layer.add_child(banner)
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color("#fca5a5"))
	lbl.text = "COMBAT! Roll for Initiative!"
	banner.add_child(lbl)
	banner.modulate = Color(1, 1, 1, 0)
	banner.scale = Vector2(0.8, 0.8)
	banner.pivot_offset = Vector2(260, 40)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	tw.tween_property(banner, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(2.2)
	tw.tween_property(banner, "modulate:a", 0.0, 0.5)
	tw.tween_callback(banner.queue_free)


func _add_button(text: String, cb: Callable, color := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE   # don't let WASD (ui_*) navigate buttons
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b)
	_tint_button(b, color)
	b.pressed.connect(cb)
	_action_row.add_child(b)
	return b


func _add_action(text: String, action: Dictionary, color := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE   # don't let WASD (ui_*) navigate buttons
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b)
	_tint_button(b, color)
	b.pressed.connect(func(): Net.send_action(action))
	_action_row.add_child(b)
	return b


## Override a button's text color to signal its function (heal=red, mana=blue, …).
func _tint_button(b: Button, color: String) -> void:
	if color == "":
		return
	var c := Color(color)
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", c.lightened(0.3))
	b.add_theme_color_override("font_pressed_color", c.darkened(0.1))
	b.add_theme_color_override("font_focus_color", c)


## Pick the background-music state from the game state and switch only on change
## (boss music when a boss is on the field mid-fight, combat otherwise, else explore).
func _update_music(state: Dictionary, phase: String) -> void:
	var want := "explore"
	if phase == "PLAYERS" or phase == "INITIATIVE":
		want = "combat"
		for m in state.get("monsters", {}).values():
			if m.get("is_boss", false):
				want = "boss"
				break
	if want != _music_state:
		_music_state = want
		Music.play_state(want)


func _update_hud(state: Dictionary) -> void:
	var region: int = state.get("region", 1)
	var biome_name: String = state.get("biome", {}).get("name", "")
	var phase: String = state.get("phase", "")
	var combat: bool = phase == "PLAYERS"
	var exploration: bool = phase == "EXPLORATION"
	var rolling: bool = phase == "INITIATIVE"
	var cleared: bool = exploration and state.get("monsters", {}).is_empty()
	var phase_label: String = "Combat" if combat else ("Roll Initiative" if rolling else "Exploration")
	_round_label.text = "Round %d  —  Region %d: %s  (%s)" % [state.get("round", 1), region, biome_name, phase_label]

	# Roll Init only while initiative is open and you personally still owe a roll;
	# combat actions only during combat; exploration actions only out of it.
	var must_roll: bool = rolling and (Net.local_id in state.get("awaiting_init", []))
	_btn_attack.visible = combat
	_btn_ability.visible = combat
	_btn_roll.visible = must_roll
	_btn_end.visible = combat
	_btn_loot.visible = exploration
	_btn_shop.visible = exploration
	_btn_bash.visible = exploration
	_btn_pick.visible = exploration
	_btn_pray.visible = exploration
	_btn_hide.visible = (Net.local_player().get("class_key", "") == "rogue") and (combat or exploration)
	_btn_examine.visible = not state.get("monsters", {}).is_empty()
	_btn_qa.visible = true
	_btn_nuke.visible = _qa_mode
	_btn_boon.visible = Net.local_player().get("boon_picks", 0) > 0
	_btn_next.visible = cleared


## Initiative order strip along the top of the map, shown during combat.
func _update_turn_bar(state: Dictionary) -> void:
	for c in _turn_bar.get_children():
		c.queue_free()
	# Bar stays present (fixed height) in all phases so the viewport never resizes.
	var phase: String = state.get("phase", "")
	if phase != "PLAYERS":
		var hint := Label.new()
		if phase == "INITIATIVE":
			var waiting: int = state.get("awaiting_init", []).size()
			hint.text = "  Roll for initiative!  (%d still to roll)" % waiting
			hint.modulate = Color("#fbbf24")
		else:
			hint.text = "  Initiative order shows here during combat"
			hint.modulate = Color("#64748b")
		hint.add_theme_font_size_override("font_size", 12)
		_turn_bar.add_child(hint)
		return
	var ct = state.get("current_turn_id", null)
	for entry in state.get("initiative_queue", []):
		var is_current: bool = typeof(entry["id"]) == typeof(ct) and entry["id"] == ct
		var is_player: bool = entry.get("type", "") == "player"
		var lbl := Label.new()
		var nm := _short_name(str(entry.get("name", "?")))
		lbl.text = ("> " + nm) if is_current else nm
		lbl.add_theme_font_size_override("font_size", 13)
		if is_current:
			lbl.modulate = Color("#fbbf24")
		elif is_player:
			lbl.modulate = Color("#7dd3fc")
		else:
			lbl.modulate = Color("#f87171")
		_turn_bar.add_child(lbl)


## Shorten combatant names for the turn bar ("Goblin of the Glade" -> "Goblin").
func _short_name(full: String) -> String:
	return full.split(" of ")[0]


## Roster of all connected players (left column). Cards are kept across updates
## (not rebuilt) so a bar can flash when its player loses HP or spends mana.
func _update_party(state: Dictionary) -> void:
	var players: Dictionary = state.get("players", {})
	_party_title.text = "Party (%d/%d)" % [players.size(), 10]
	var ct = state.get("current_turn_id", null)

	# Drop cards for players who left.
	for pid in _party_cards.keys():
		if not players.has(pid):
			_party_cards[pid]["card"].queue_free()
			_party_cards.erase(pid)
			_prev_vitals.erase(pid)
	# Build cards for new players (no flash on first appearance).
	for pid in players:
		if not _party_cards.has(pid):
			_party_cards[pid] = _build_party_card()
			_party_cards[pid]["card"].gui_input.connect(_on_party_card_input.bind(pid))
			_prev_vitals[pid] = {"hp": int(players[pid].get("health", 0)), "mp": int(players[pid].get("mana", 0))}
	# Refresh every card in place.
	var pguilds: Dictionary = state.get("player_guilds", {})
	for pid in players:
		_update_party_card(pid, players[pid], ct, str(pguilds.get(pid, "")))


func _build_party_card() -> Dictionary:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_sb("#1d1813", "#5a4a2a"))
	card.material = _btn_mat
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 2)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cv)
	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(name_lbl)
	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", 11)
	sub.modulate = Color("#94a3b8")
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(sub)
	var st := Label.new()
	st.add_theme_font_size_override("font_size", 11)
	st.add_theme_color_override("font_color", Color("#fbbf24"))
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(st)
	var hp := _party_bar(cv, "#ef4444")
	var mp := _party_bar(cv, "#3b82f6")
	_party_box.add_child(card)
	return {"card": card, "name": name_lbl, "sub": sub, "status": st, "hp": hp, "mp": mp}


func _update_party_card(pid, p: Dictionary, ct, guild_name: String) -> void:
	var refs: Dictionary = _party_cards[pid]
	var is_local: bool = pid == Net.local_id
	var is_turn: bool = typeof(ct) == typeof(pid) and ct == pid
	var name_lbl: Label = refs["name"]
	name_lbl.text = "%s%s" % ["> " if is_turn else "", p.get("name", "?")]
	if is_turn:
		name_lbl.modulate = Color("#fbbf24")
	elif is_local:
		name_lbl.modulate = Color("#ffd24a")
	else:
		name_lbl.modulate = Color("#e2e8f0")
	var tag := "  <%s>" % guild_name if guild_name != "" else ""
	refs["sub"].text = "Lv %d %s%s" % [p.get("level", 1), p.get("class", ""), tag]
	refs["status"].text = _status_badges(p)

	var hp := int(p.get("health", 0))
	var mp := int(p.get("mana", 0))
	_set_party_bar(refs["hp"], hp, int(p.get("max_health", 1)))
	_set_party_bar(refs["mp"], mp, int(p.get("max_mana", 1)))

	# Flash the bar when its value dropped (damage taken / mana spent).
	var prev: Dictionary = _prev_vitals.get(pid, {"hp": hp, "mp": mp})
	if hp < prev["hp"]:
		_flash_bar(refs["hp"])
	if mp < prev["mp"]:
		_flash_bar(refs["mp"])
	_prev_vitals[pid] = {"hp": hp, "mp": mp}


func _party_bar(parent: Control, color: String) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#171310")
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(color)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.set_meta("fill", fill)
	bar.set_meta("base", Color(color))
	parent.add_child(bar)
	return bar


func _set_party_bar(bar: ProgressBar, value: int, maxv: int) -> void:
	bar.max_value = max(1, maxv)
	bar.value = clampi(value, 0, maxv)


## Quick flash: blow the fill to white, then tween it back to its base colour.
func _flash_bar(bar: ProgressBar) -> void:
	var fill: StyleBoxFlat = bar.get_meta("fill")
	var base: Color = bar.get_meta("base")
	fill.bg_color = Color(1, 1, 1)
	var tw := create_tween()
	tw.tween_property(fill, "bg_color", base, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Announce the opening chapter once on join. Subsequent region advances are
## narrated by the server's dramatic transition text (see net.gd _do_ready).
func _maybe_announce_region(state: Dictionary) -> void:
	var region: int = state.get("region", -1)
	var first := _last_region == -1
	_last_region = region
	if not first:
		return
	var act_name: String = state.get("act_name", "")
	var chapter: String = state.get("chapter", "")
	if act_name != "":
		_on_log({"author": "Chapter", "text": act_name, "color": "#a78bfa"})
	if chapter != "":
		_on_log({"author": "Storyteller", "text": chapter, "color": "#c084fc"})


# ============================================================
#  Inventory / shop overlay
# ============================================================
func _toggle_qa() -> void:
	_qa_mode = not _qa_mode
	if not Net.last_state.is_empty():
		_update_hud(Net.last_state)


func _toggle_inventory() -> void:
	if _overlay_mode == "inv":
		_close_overlay()
	else:
		_overlay_mode = "inv"
		_overlay.visible = true
		_refresh_overlay(Net.last_state)


func _toggle_shop() -> void:
	if _overlay_mode == "shop":
		_close_overlay()
	else:
		_overlay_mode = "shop"
		_overlay.visible = true
		_refresh_overlay(Net.last_state)


func _toggle_guild() -> void:
	if _overlay_mode == "guild":
		_close_overlay()
	else:
		_overlay_mode = "guild"
		_overlay.visible = true
		_refresh_overlay(Net.last_state)


func _close_overlay() -> void:
	_overlay_mode = ""
	_overlay.visible = false
	_overlay_backdrop.visible = false


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_overlay()


func _on_party_card_input(event: InputEvent, pid) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_show_player_stats(pid)


func _show_player_stats(pid) -> void:
	_overlay_mode = "stats"
	_stats_pid = pid
	_overlay.visible = true
	_refresh_overlay(Net.last_state)


func _open_boon() -> void:
	_overlay_mode = "boon"
	_overlay.visible = true
	_refresh_overlay(Net.last_state)


func _open_settings() -> void:
	_overlay_mode = "settings"
	_overlay.visible = true
	_refresh_overlay(Net.last_state)


func _build_settings(_state: Dictionary) -> void:
	_overlay_box.add_child(_heading("⚙ Settings"))
	_overlay_box.add_child(Settings.build_panel())


func _build_boon_overlay(_state: Dictionary) -> void:
	_overlay_box.add_child(_heading("⭐ Choose a Boon"))
	for boon in BOONS:
		var row := HBoxContainer.new()
		var b := Button.new()
		b.text = boon["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 0)
		var bid: String = boon["id"]
		b.pressed.connect(func():
			Net.send_action({"type": "pick_boon", "boon": bid})
			_close_overlay())
		row.add_child(b)
		var d := Label.new()
		d.text = boon["desc"]
		d.modulate = Color("#cbd5e1")
		row.add_child(d)
		_overlay_box.add_child(row)


func _build_player_stats(state: Dictionary) -> void:
	var p: Dictionary = state.get("players", {}).get(_stats_pid, {})
	if p.is_empty():
		_overlay_box.add_child(_heading("Player has left"))
		return
	_overlay_box.add_child(_heading(str(p.get("name", "?"))))
	_overlay_box.add_child(_stat_line("Class", "Lv %d %s" % [int(p.get("level", 1)), str(p.get("class", ""))]))
	_overlay_box.add_child(_stat_line("HP", "%d / %d" % [int(p.get("health", 0)), int(p.get("max_health", 0))]))
	_overlay_box.add_child(_stat_line("MP", "%d / %d" % [int(p.get("mana", 0)), int(p.get("max_mana", 0))]))
	_overlay_box.add_child(_stat_line("Armor Class", str(int(p.get("ac", 10)))))
	_overlay_box.add_child(_stat_line("Status", _status_text(p)))
	var mods: Dictionary = p.get("modifiers", {})
	for stat_name in p.get("stats", {}):
		var score: int = int(p["stats"][stat_name])
		var modifier: int = int(mods.get(stat_name, 0))
		var sign_str: String = "+" if modifier >= 0 else ""
		var mod_color: String = "#4ade80" if modifier > 0 else ("#f87171" if modifier < 0 else "#cbd5e1")
		_overlay_box.add_child(_stat_line(str(stat_name), "%d  (%s%d)" % [score, sign_str, modifier], mod_color))
	_overlay_box.add_child(_stat_line("Weapon", str(p.get("weapon", "-"))))
	_overlay_box.add_child(_stat_line("Damage", str(p.get("damage_dice", "-"))))
	_overlay_box.add_child(_stat_line("Ability", str(p.get("ability_name", "-"))))
	_overlay_box.add_child(_stat_line("Gold", str(int(p.get("gold", 0)))))
	_overlay_box.add_child(_stat_line("XP", str(int(p.get("xp", 0)))))


func _stat_line(label: String, value: String, value_color := "#f1f5f9") -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.modulate = Color("#94a3b8")
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.modulate = Color(value_color)
	row.add_child(v)
	return row


func _do_loot() -> void:

	var lp: Dictionary = Net.local_player()
	if lp.is_empty():
		return
	for it in Net.last_state.get("items", {}).values():
		if it["type"] == "chest" and Vector2(it["x"], it["y"]).distance_to(Vector2(lp["x"], lp["y"])) <= 1.5:
			Net.send_action({"type": "loot", "item_id": it["id"]})
			return
	_on_log({"author": "System", "text": "No chest within reach.", "color": "#ef4444"})


func _refresh_overlay(state: Dictionary) -> void:
	_overlay_backdrop.visible = true
	for c in _overlay_box.get_children():
		c.queue_free()
	var close := Button.new()
	close.text = "✕ Close"
	close.pressed.connect(_close_overlay)
	_overlay_box.add_child(close)
	if _overlay_mode == "inv":
		_build_inventory(state)
	elif _overlay_mode == "shop":
		_build_shop(state)
	elif _overlay_mode == "guild":
		_build_guild(state)
	elif _overlay_mode == "stats":
		_build_player_stats(state)
	elif _overlay_mode == "boon":
		_build_boon_overlay(state)
	elif _overlay_mode == "settings":
		_build_settings(state)


func _build_inventory(state: Dictionary) -> void:
	var p: Dictionary = state.get("players", {}).get(Net.local_id, {})
	if p.is_empty():
		return
	_overlay_box.add_child(_heading("🎒 Inventory"))
	for slot in ["weapon", "armor"]:
		var eq = p.get("equipment", {}).get(slot)
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s: %s" % [slot.capitalize(), (eq["name"] if eq != null else "—")]
		lbl.custom_minimum_size = Vector2(280, 0)
		row.add_child(lbl)
		if eq != null:
			row.add_child(_item_button("Unequip", {"type": "equip", "item_id": eq["id"]}))
		_overlay_box.add_child(row)

	var inv: Array = p.get("inventory", [])
	_overlay_box.add_child(_heading("Backpack (%d/%d)" % [inv.size(), 12]))
	for item in inv:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = _item_label(item)
		lbl.modulate = Color(item.get("color", "#ffffff"))
		lbl.custom_minimum_size = Vector2(280, 0)
		row.add_child(lbl)
		if item["type"] in ["weapon", "armor"]:
			row.add_child(_item_button("Equip", {"type": "equip", "item_id": item["id"]}))
		elif item["type"] in ["potion", "scroll"]:
			row.add_child(_item_button("Use", {"type": "use", "item_id": item["id"]}))
		_overlay_box.add_child(row)


func _build_shop(state: Dictionary) -> void:
	var p: Dictionary = state.get("players", {}).get(Net.local_id, {})
	if p.is_empty():
		return
	var merchant = null
	for n in state.get("npcs", {}).values():
		if Vector2(n["x"], n["y"]).distance_to(Vector2(p["x"], p["y"])) <= 1.5:
			merchant = n
			break
	if merchant == null:
		_overlay_box.add_child(_heading("No merchant nearby"))
		var hint := Label.new()
		hint.text = "Stand next to the merchant, then open the shop."
		_overlay_box.add_child(hint)
		return
	_overlay_box.add_child(_heading("🛒 Merchant  (your gold: %d)" % p.get("gold", 0)))
	for itm in merchant["inventory"]:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s — %d g" % [itm["name"], itm["price"]]
		lbl.modulate = Color(itm.get("color", "#ffffff"))
		lbl.custom_minimum_size = Vector2(280, 0)
		row.add_child(lbl)
		row.add_child(_item_button("Buy", {"type": "buy", "npc_id": merchant["id"], "shop_item_id": itm["id"]}))
		_overlay_box.add_child(row)


func _build_guild(state: Dictionary) -> void:
	var players: Dictionary = state.get("players", {})
	var pguilds: Dictionary = state.get("player_guilds", {})
	var guilds: Dictionary = state.get("guilds", {})
	_overlay_box.add_child(_heading("🛡️ Guild"))

	var my_guild = pguilds.get(Net.local_id)
	if my_guild == null:
		var blurb := Label.new()
		blurb.text = "Form a guild to share XP and gain +5% damage per member."
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(380, 0)
		_overlay_box.add_child(blurb)
		var name_edit := LineEdit.new()
		name_edit.placeholder_text = "Guild name"
		name_edit.max_length = 20
		_overlay_box.add_child(name_edit)
		var create := Button.new()
		create.text = "Create Guild"
		create.pressed.connect(func(): Net.send_action({"type": "guild_create", "name": name_edit.text}))
		_overlay_box.add_child(create)
		return

	var guild: Dictionary = guilds.get(my_guild, {})
	var is_leader: bool = guild.get("leader", -1) == Net.local_id
	_overlay_box.add_child(_heading("« %s »" % my_guild))
	var members: Array = guild.get("members", [])
	for mid in members:
		var nm: String = players.get(mid, {}).get("name", "Unknown")
		var tag := "  (leader)" if guild.get("leader", -1) == mid else ""
		var ml := Label.new()
		ml.text = "• %s%s" % [nm, tag]
		ml.modulate = Color("#a78bfa")
		_overlay_box.add_child(ml)

	if is_leader:
		var inv_hdr := Label.new()
		inv_hdr.text = "Invite:"
		inv_hdr.modulate = Color("#cbd5e1")
		_overlay_box.add_child(inv_hdr)
		var any := false
		for opid in players:
			if opid == Net.local_id or pguilds.has(opid):
				continue
			any = true
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = players[opid].get("name", "?")
			lbl.custom_minimum_size = Vector2(280, 0)
			row.add_child(lbl)
			row.add_child(_item_button("Invite", {"type": "guild_invite", "target_id": opid}))
			_overlay_box.add_child(row)
		if not any:
			var none := Label.new()
			none.text = "  (no unguilded players nearby)"
			none.modulate = Color("#64748b")
			_overlay_box.add_child(none)

	var leave := Button.new()
	leave.text = "Leave Guild"
	leave.pressed.connect(func(): Net.send_action({"type": "guild_leave"}))
	_overlay_box.add_child(leave)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = _strip_icons(text)
	l.add_theme_font_size_override("font_size", 16)
	return l


## Drop emoji / symbol glyphs the web export's font can't render (shown as boxes):
## arrows + misc symbols + dingbats + geometric (0x2190-0x2BFF), the emoji planes
## (>=0x1F000), and the variation-selector / ZWJ joiners.
func _strip_icons(s: String) -> String:
	var out := ""
	for ch in s:
		var c := ch.unicode_at(0)
		if c == 0xFE0F or c == 0x200D:
			continue
		if c >= 0x2190 and c <= 0x2BFF:
			continue
		if c >= 0x1F000:
			continue
		out += ch
	return out.replace("  ", " ")


func _item_label(item: Dictionary) -> String:
	var bonus := ""
	if int(item.get("atk_bonus", 0)) > 0:
		bonus = "  (+%d ATK)" % int(item["atk_bonus"])
	elif int(item.get("def_bonus", 0)) > 0:
		bonus = "  (+%d DEF)" % int(item["def_bonus"])
	return "%s%s" % [item["name"], bonus]


func _item_button(text: String, action: Dictionary) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Net.send_action(action))
	return b


# ============================================================
#  Log + input
# ============================================================
func _on_chat_submitted(text: String) -> void:
	var msg: String = text.strip_edges()
	if msg == "":
		return
	Net.send_action({"type": "chat", "text": msg})
	_chat_input.clear()


func _on_log(msg: Dictionary) -> void:
	var l := Label.new()
	l.text = _strip_icons("[%s] %s" % [msg.get("author", ""), msg.get("text", "")])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(290, 0)
	l.modulate = Color(msg.get("color", "#ffffff"))
	_log_box.add_child(l)
	while _log_box.get_child_count() > 40:
		var first := _log_box.get_child(0)
		_log_box.remove_child(first)
		first.queue_free()
	await get_tree().process_frame
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	var dx := 0
	var dy := 0
	if event.is_action("ui_up"):
		dy = -1
	elif event.is_action("ui_down"):
		dy = 1
	elif event.is_action("ui_left"):
		dx = -1
	elif event.is_action("ui_right"):
		dx = 1
	else:
		return
	Net.send_action({"type": "move", "dx": dx, "dy": dy})
