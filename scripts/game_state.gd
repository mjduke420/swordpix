extends RefCounted
class_name GameState
## Authoritative game state — port of backend/game_state.py.
## Runs ONLY on the server peer. Mutated by net.gd action handlers, then the
## full snapshot from get_state_dict() is broadcast to every client.
## Sections mirror the Python source headers for easy cross-reference.

const MAP_WIDTH := 15
const MAP_HEIGHT := 15
const MAX_LEVEL := 10
const MAX_REGION := 15

# Standard array assigned to stats by class priority (game_state.py:670).
const STANDARD_ARRAY := [15, 14, 13, 12, 10, 8]

# Biome pool (game_state.py:11). First 6 are the campaign biomes; the next 5 are
# reached through Mystic Portals; HellPlane is the chest-triggered excursion.
# "decoration" is the scenery/blocking tile; "hazard" tiles are placed but their
# round-effects remain a later phase.
const BIOME_POOL := {
	"Dreadwood Forest": {
		"floor": "#1a3a1a", "wall": "#2d2d2d", "accent": "#4ade80",
		"monster_suffix": "of the Glade", "decoration": "T"},
	"Charred Wastes": {
		"floor": "#2a1a0a", "wall": "#4a2a0a", "accent": "#f97316",
		"monster_suffix": "of the Flame", "decoration": "T"},
	"Whispering Caves": {
		"floor": "#1e1e2e", "wall": "#313244", "accent": "#cdd6f4",
		"monster_suffix": "of the Echo", "decoration": "^"},
	"Abyssal Depths": {
		"floor": "#0f0a1e", "wall": "#1a0f2e", "accent": "#a78bfa",
		"monster_suffix": "of the Abyss", "decoration": "*"},
	"Crimson Citadel": {
		"floor": "#2a0a0a", "wall": "#4a1a1a", "accent": "#fb7185",
		"monster_suffix": "of the Keep", "decoration": "*"},
	"Frozen Hollow": {
		"floor": "#0c1e3a", "wall": "#1e3a5a", "accent": "#38bdf8",
		"monster_suffix": "of the Frost", "decoration": "*", "hazard": "I"},
	"The Sky-Reaches": {
		"floor": "#e0f2fe", "wall": "#7dd3fc", "accent": "#fde047",
		"monster_suffix": "of the Sky", "decoration": "*", "hazard": "E"},
	"The Sunken Oasis": {
		"floor": "#fef3c7", "wall": "#d97706", "accent": "#10b981",
		"monster_suffix": "of the Dunes", "decoration": "*", "hazard": "H"},
	"The Clockwork Spire": {
		"floor": "#27272a", "wall": "#52525b", "accent": "#fb923c",
		"monster_suffix": "of the Gear", "decoration": "G", "hazard": "Z"},
	"The Fey-Wilds": {
		"floor": "#4a044e", "wall": "#86198f", "accent": "#d946ef",
		"monster_suffix": "of the Wild", "decoration": "T", "hazard": "W"},
	"The Sunless Sea": {
		"floor": "#082f49", "wall": "#0369a1", "accent": "#38bdf8",
		"monster_suffix": "of the Depths", "decoration": "^", "hazard": "U"},
	"HellPlane": {
		"floor": "#3b0a0a", "wall": "#7c1d1d", "accent": "#ff4444",
		"monster_suffix": "of the Hellplane", "decoration": "L"},
}

const PORTAL_BIOMES := ["The Sky-Reaches", "The Sunken Oasis", "The Clockwork Spire", "The Fey-Wilds", "The Sunless Sea"]

# Per-round environmental dangers (game_state.py:1876 _apply_biome_round_effects).
# "every" = rounds between ticks; "kind" drives the effect + its particle.
const BIOME_HAZARDS := {
	"The Sunken Oasis": {"kind": "heat", "every": 3},
	"The Clockwork Spire": {"kind": "rotate", "every": 3},
	"The Sunless Sea": {"kind": "drown", "every": 1},
	"HellPlane": {"kind": "hellfire", "every": 1},
	"Frozen Hollow": {"kind": "frost", "every": 2},
	"The Fey-Wilds": {"kind": "wild", "every": 2},
}

# 15 story chapters across 3 acts (game_state.py:77).
const STORY_BEATS := [
	["The Whispering Woods", "As you enter the ancient forest, strange sounds echo through the trees."],
	["The Goblin Scouting Party", "Goblin scouts have been spotted. Their manic laughter grows louder."],
	["The Gathering Storm", "The air grows heavy. The corruption is spreading faster than anticipated."],
	["The Vanguard", "Elite defenders bar your path. Something is commanding them from the shadows."],
	["The Goblin King's Court", "The Goblin King's fortress looms. Behind those gates, a puppet waits."],
	["The Earth Cracks", "The Goblin King is slain, yet the corruption deepens. The earth itself cracks open..."],
	["Descent into Darkness", "The air grows cold as you delve deeper. Shadows seem to move on their own."],
	["The Bone Wastes", "Skeletal remains litter the ground. An unnatural chill bites at your skin."],
	["The Undead General", "A powerful commander of the dead challenges you. The true enemy reveals itself."],
	["Cathedral of Bone", "A cathedral of bone rises from the abyss. The Lich awaits within..."],
	["The Shattered Reality", "The Lich's dying scream tears reality apart. Through the rift, something peers back..."],
	["Echoes of the Void", "Colors drain from the world. Strange, alien geometry distorts the landscape."],
	["The Vanguard of Nothingness", "Creatures not of this world pour through the rifts. Reality strains."],
	["The Brink of Collapse", "The sky turns pitch black. The world unravels at the seams."],
	["The Void Herald", "This is the end of all things. The Void Herald descends. Fight or be unmade."],
]

const ACT_NAMES := {
	1: "Act I – The Corruption Spreads",
	2: "Act II – Shadows of the Abyss",
	3: "Act III – The Void Awakens",
}

const ACT_TRANSITIONS := {
	5: "⛩️ The ground trembles beneath your feet. A dark gate opens below... The descent begins.",
	10: "✨ Reality shatters like glass! Through the void's maw you plunge into a realm beyond reason...",
	15: "🌟 The Void Herald dissolves into light. The world exhales. But somewhere, a whisper: 'Again...'",
}

# Loot tables (game_state.py:113). Bonuses scale with region + rarity.
const WEAPON_NAMES := ["Iron Sword", "Battle Axe", "War Hammer", "Enchanted Staff", "Shadow Dagger", "Runed Bow"]
const ARMOUR_NAMES := ["Leather Vest", "Chain Mail", "Plate Armor", "Mystic Robes", "Dragon Scale"]
const RARITY_COLORS := {"Common": "#94a3b8", "Rare": "#3b82f6", "Epic": "#a855f7", "Legendary": "#fbbf24"}
const RARITY_BONUS := {"Common": 1, "Rare": 3, "Epic": 8, "Legendary": 15}
const INVENTORY_MAX := 12

const TORCH_LIT_RADIUS := 3   # tiles a torch illuminates around itself

var current_biome := "Dreadwood Forest"
var map: Array = []
var players := {}        # peer_id(int) -> player dict
var monsters := {}       # monster_id(String) -> monster dict
var items := {}          # item_id(String) -> item dict (ground loot / chests)
var npcs := {}           # npc_id(String) -> npc dict (merchant)
var torches := {}        # torch_id(String) -> {id, x, y, radius}
var traps := {}          # trap_id(String) -> {id, x, y, dc, damage, type, is_revealed}
var guilds := {}         # name(String) -> {name, leader(int), members(Dictionary peer->true)}
var player_guilds := {}  # peer_id(int) -> guild name(String)
var chat_history: Array = []

var ready_players := {}      # peer_id -> true (set of players ready to advance)
var phase := "EXPLORATION"   # EXPLORATION | PLAYERS
var round_number := 1
var region_number := 1
var ng_plus := 0
var first_combat_cleared := false

# HellPlane excursion: while inside, _prior_world holds the snapshot to restore.
var in_hellplane := false
var _prior_world = null

# Filled by advance_turn on a round wrap; drained + broadcast by net.gd.
# Each event: {text, color, vfx: {type, x, y}}.
var last_round_events: Array = []

# Initiative system (game_state.py:278). Combat opens in the INITIATIVE phase:
# monsters auto-roll, players must each click to roll; _init_pending tracks who
# still needs to. Once empty, the order is finalized and the phase becomes PLAYERS.
var initiative_queue: Array = []
var current_turn_index := -1
var current_turn_id = null   # int peer_id or String monster_id
var _init_pending := {}      # peer_id -> true (players who still owe an init roll)

var _next_monster_id := 1
var _next_item_id := 1
var _next_torch_id := 1
var _next_trap_id := 1


func _init() -> void:
	map = generate_map(current_biome)


## Entity ids are mixed-type: player ids are ints (peer ids), monster ids are
## Strings. GDScript throws on `int == String`, so compare ids through here.
## The `and` short-circuits, so the `==` only runs when the types already match.
func ids_equal(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


func biome() -> Dictionary:
	return BIOME_POOL[current_biome]


func act_number() -> int:
	return (region_number - 1) / 5 + 1


# ============================================================
#  Map generation (game_state.py:214)
# ============================================================
func generate_map(biome_name: String) -> Array:
	var info: Dictionary = BIOME_POOL.get(biome_name, BIOME_POOL["Dreadwood Forest"])
	var decor: String = info["decoration"]
	var hazard: String = info.get("hazard", "#")
	var game_map: Array = []
	for y in range(MAP_HEIGHT):
		var row: Array = []
		for x in range(MAP_WIDTH):
			if x == 0 or y == 0 or x == MAP_WIDTH - 1 or y == MAP_HEIGHT - 1:
				row.append("#")
			else:
				var r := randf()
				if r < 0.10:
					row.append(decor)
				elif r < 0.15:
					row.append("~")
				elif r < 0.18:
					row.append(hazard)   # biome hazard tile (ice / edge / pistons / ...)
				elif r < 0.20:
					row.append(["A", "D", "P"][randi() % 3])   # altar / locked hatch / pitfall
				elif r < 0.22:
					row.append("#")
				else:
					row.append(".")
		game_map.append(row)
	# Clear a 5x5 center for spawns.
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cx: int = MAP_WIDTH / 2 + dx
			var cy: int = MAP_HEIGHT / 2 + dy
			if cx > 0 and cx < MAP_WIDTH - 1 and cy > 0 and cy < MAP_HEIGHT - 1:
				game_map[cy][cx] = "."

	# The Sunless Sea drowns you off the safe air-bubble tiles ('B'); scatter some,
	# and make the central spawn a safe pocket.
	if biome_name == "The Sunless Sea":
		for y in range(1, MAP_HEIGHT - 1):
			for x in range(1, MAP_WIDTH - 1):
				if game_map[y][x] == "." and randf() < 0.18:
					game_map[y][x] = "B"
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				game_map[MAP_HEIGHT / 2 + dy][MAP_WIDTH / 2 + dx] = "B"
	return game_map


func is_walkable(x: int, y: int) -> bool:
	if y < 0 or y >= MAP_HEIGHT or x < 0 or x >= MAP_WIDTH:
		return false
	var tile: String = map[y][x]
	# Doors block until bashed/picked; altars are handled in move_player so monsters
	# can't path onto them either — treat both as solid here.
	return not (tile in ["#", "~", "^", "*", "D", "A"])


func is_entity_at(x: int, y: int) -> bool:
	for p in players.values():
		if p["x"] == x and p["y"] == y:
			return true
	for m in monsters.values():
		if m["x"] == x and m["y"] == y:
			return true
	# Chests block the tile (looted from adjacent); ground loot does not.
	for it in items.values():
		if it["type"] == "chest" and it["x"] == x and it["y"] == y:
			return true
	for n in npcs.values():
		if n["x"] == x and n["y"] == y:
			return true
	return false


# ============================================================
#  Chat / log
# ============================================================
func add_chat_message(author: String, text: String, color := "#ffffff") -> Dictionary:
	var message := {"author": author, "text": text, "color": color}
	chat_history.append(message)
	if chat_history.size() > 50:
		chat_history.pop_front()
	return message


# ============================================================
#  Guilds — in-memory, in-session (game_state.py:369)
# ============================================================
func create_guild(peer_id: int, guild_name: String) -> Dictionary:
	var name := guild_name.strip_edges().substr(0, 20)
	if name == "":
		return {"success": false, "message": "Guild name required."}
	if guilds.has(name):
		return {"success": false, "message": "Guild '%s' already exists." % name}
	if player_guilds.has(peer_id):
		return {"success": false, "message": "You are already in a guild."}
	if not players.has(peer_id):
		return {"success": false, "message": "Unknown player."}
	guilds[name] = {"name": name, "leader": peer_id, "members": {peer_id: true}}
	player_guilds[peer_id] = name
	return {"success": true, "message": "Guild '%s' founded." % name, "color": "#a78bfa"}


func invite_to_guild(leader_id: int, target_id: int) -> Dictionary:
	var gname = player_guilds.get(leader_id)
	if gname == null:
		return {"success": false, "message": "You are not in a guild."}
	var guild: Dictionary = guilds.get(gname, {})
	if guild.is_empty() or guild["leader"] != leader_id:
		return {"success": false, "message": "Only the guild leader can invite."}
	if not players.has(target_id):
		return {"success": false, "message": "Unknown target player."}
	if player_guilds.has(target_id):
		return {"success": false, "message": "Target is already in a guild."}
	guild["members"][target_id] = true
	player_guilds[target_id] = gname
	return {"success": true, "message": "%s joined '%s'." % [players[target_id].get("name", "Unknown"), gname], "color": "#a78bfa"}


func leave_guild(peer_id: int) -> Dictionary:
	var gname = player_guilds.get(peer_id)
	if gname == null:
		return {"success": false, "message": "You are not in a guild."}
	var guild: Dictionary = guilds.get(gname, {})
	if not guild.is_empty():
		guild["members"].erase(peer_id)
		if guild["members"].is_empty():
			guilds.erase(gname)
		elif guild["leader"] == peer_id:
			guild["leader"] = guild["members"].keys()[0]   # promote a remaining member
	player_guilds.erase(peer_id)
	return {"success": true, "message": "You left '%s'." % gname, "color": "#a78bfa"}


func guild_member_count(peer_id: int) -> int:
	var gname = player_guilds.get(peer_id)
	if gname == null or not guilds.has(gname):
		return 0
	return guilds[gname]["members"].size()


func _guild_damage_multiplier(peer_id: int) -> float:
	return 1.0 + 0.05 * max(0, guild_member_count(peer_id) - 1)


## Find the peer id that owns a player dict (by reference identity).
func _peer_for_player(p: Dictionary) -> int:
	for pid in players:
		if is_same(players[pid], p):
			return pid
	return -1


# ============================================================
#  XP / leveling (game_state.py:492)
# ============================================================
func xp_to_next(level: int) -> int:
	return 50 + level * 30


func grant_xp(p: Dictionary, xp: int, _internal := false):
	var new_level = null
	if p.get("level", 1) < MAX_LEVEL:
		p["xp"] = p.get("xp", 0) + xp
		var needed := xp_to_next(p.get("level", 1))
		if p["xp"] >= needed:
			p["xp"] -= needed
			p["level"] = p.get("level", 1) + 1
			p["max_health"] += 20
			p["max_mana"] = p.get("max_mana", 30) + 10
			p["attack_damage"] += 5
			p["health"] = p["max_health"]
			p["mana"] = p["max_mana"]
			p["boon_picks"] = p.get("boon_picks", 0) + 1
			new_level = p["level"]

	# Guild shared-XP fan-out — only on the original (non-internal) call so we
	# don't recurse between guildmates.
	if not _internal:
		var origin := _peer_for_player(p)
		if origin != -1:
			var gname = player_guilds.get(origin)
			if gname != null and guilds.has(gname):
				for member_id in guilds[gname]["members"]:
					if member_id != origin and players.has(member_id):
						grant_xp(players[member_id], xp, true)
	return new_level


# ============================================================
#  Status effects (game_state.py:443)
# ============================================================
func has_status_effect(entity: Dictionary, type: String) -> bool:
	for e in entity.get("status_effects", []):
		if e["type"] == type:
			return true
	return false


func apply_status_effect(entity: Dictionary, status_type: String, duration: int, value := 0) -> void:
	var effects: Array = entity.get("status_effects", [])
	for eff in effects:
		if eff["type"] == status_type:
			eff["duration"] = max(eff["duration"], duration)
			return
	effects.append({"type": status_type, "duration": duration, "value": value})
	entity["status_effects"] = effects


## Returns [damage_taken, stunned].
func process_status_effects(entity: Dictionary) -> Array:
	var dmg := 0
	var stunned := false
	var remaining: Array = []
	for eff in entity.get("status_effects", []):
		var etype: String = eff["type"]
		if etype == "poison":
			dmg = eff.get("value", 5)
			if entity.has("hp"):
				entity["hp"] -= dmg
			else:
				entity["health"] -= dmg
		elif etype == "stun":
			stunned = true
		eff["duration"] -= 1
		if eff["duration"] > 0:
			remaining.append(eff)
	entity["status_effects"] = remaining
	return [dmg, stunned]


# ============================================================
#  Player management (game_state.py:626)
# ============================================================
func add_player(peer_id: int, pname: String, class_key: String) -> void:
	var cc: Dictionary = Classes.get_class_data(class_key)
	while true:
		var x: int = clampi(MAP_WIDTH / 2 + randi_range(-2, 2), 1, MAP_WIDTH - 2)
		var y: int = clampi(MAP_HEIGHT / 2 + randi_range(-2, 2), 1, MAP_HEIGHT - 2)
		if map[y][x] == "." and not is_entity_at(x, y):
			var p := {
				"name": pname, "x": x, "y": y,
				"class": cc["name"], "class_key": class_key,
				"color": cc["color"], "symbol": cc["symbol"], "sprite": cc["sprite"],
				"health": cc["max_health"], "max_health": cc["max_health"],
				"mana": cc["max_mana"], "max_mana": cc["max_mana"],
				"weapon": cc["weapon"], "attack_range": cc["attack_range"],
				"attack_damage": cc["attack_damage"], "damage_dice": cc["damage_dice"],
				"ability_name": cc["ability_name"], "ability_cost": cc["ability_cost"],
				"ability_range": cc["ability_range"], "action_type": cc["action_type"],
				"score": 0, "gold": 0, "level": 1, "xp": 0, "boon_picks": 0,
				"health_potions": 1, "mana_potions": 1,
				"inventory": [], "equipment": {"weapon": null, "armor": null},
				"moves_left": 5, "action_used": false, "bonus_action_used": false,
				"ended_turn": false, "is_hidden": false, "facing_left": false,
				"status_effects": [], "stats": {}, "modifiers": {},
			}
			# Assign standard array by class stat priority.
			var priority: Array = cc["stat_priority"]
			for i in range(priority.size()):
				var stat: String = priority[i]
				p["stats"][stat] = STANDARD_ARRAY[i]
				p["modifiers"][stat] = (STANDARD_ARRAY[i] - 10) / 2
			# Derived AC + CON bulk (game_state.py:692).
			p["ac"] = 10 + p["modifiers"]["DEX"]
			p["max_health"] += p["modifiers"]["CON"] * 5
			p["health"] = p["max_health"]
			players[peer_id] = p
			return


func remove_player(peer_id: int) -> void:
	if player_guilds.has(peer_id):
		leave_guild(peer_id)
	players.erase(peer_id)
	ready_players.erase(peer_id)
	# If they bowed out mid-roll, don't stall the INITIATIVE phase waiting on them.
	if _init_pending.has(peer_id):
		_init_pending.erase(peer_id)
		if phase == "INITIATIVE" and _init_pending.is_empty():
			_finalize_initiative()


# ============================================================
#  Movement (game_state.py:714)
# ============================================================
## Returns {success: bool, msg: String}.
func move_player(peer_id: int, dx: int, dy: int) -> Dictionary:
	if not (phase in ["PLAYERS", "EXPLORATION"]):
		return {"success": false, "msg": "Not your phase!"}
	if not players.has(peer_id):
		return {"success": false, "msg": ""}
	if phase == "PLAYERS" and not ids_equal(peer_id, current_turn_id):
		return {"success": false, "msg": "Not your turn!"}
	var p: Dictionary = players[peer_id]
	if p["ended_turn"] and phase == "PLAYERS":
		return {"success": false, "msg": "You ended your turn."}
	if p["moves_left"] <= 0 and phase == "PLAYERS":
		return {"success": false, "msg": "Out of moves for this round."}

	var nx: int = p["x"] + dx
	var ny: int = p["y"] + dy
	if not (nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT):
		return {"success": false, "msg": ""}
	# Doors / altars block, but with a helpful hint instead of a silent bonk.
	if map[ny][nx] == "D":
		return {"success": false, "msg": "A locked hatch blocks your path. Use 🔨 Bash or 🗝️ Pick."}
	if map[ny][nx] == "A":
		return {"success": false, "msg": "A sacred Altar blocks your path. 🙏 Pray to it."}
	if not is_walkable(nx, ny) or is_entity_at(nx, ny):
		return {"success": false, "msg": ""}

	# Ice tiles slide the player along until they leave the ice.
	if map[ny][nx] == "I":
		while nx + dx > 0 and nx + dx < MAP_WIDTH - 1 and ny + dy > 0 and ny + dy < MAP_HEIGHT - 1 \
				and map[ny + dy][nx + dx] == "I" and not is_entity_at(nx + dx, ny + dy):
			nx += dx
			ny += dy

	p["x"] = nx
	p["y"] = ny
	if dx < 0:
		p["facing_left"] = true
	elif dx > 0:
		p["facing_left"] = false
	if phase == "PLAYERS":
		p["moves_left"] -= 1

	var evs: Array = []
	_ranger_perception(p, evs)
	_apply_tile_effects(p, evs)
	_trigger_trap(p, evs)

	# Stepping onto a portal triggers a dimension transition (handled in net.gd).
	if _portal_at(p["x"], p["y"]):
		return {"success": true, "msg": "", "portal": true, "events": evs}

	var msg := ""
	var picked := _pickup_ground_items(p)
	if picked != "":
		msg = "%s picked up %s!" % [p["name"], picked]
	if check_combat_engagement(peer_id) and msg == "":
		msg = "%s engages the enemy!" % p["name"]
	return {"success": true, "msg": msg, "events": evs}


## Ranger passively spots hidden traps near the tile they moved to.
func _ranger_perception(p: Dictionary, evs: Array) -> void:
	if p.get("class", "") != "Ranger":
		return
	for tid in traps:
		var t: Dictionary = traps[tid]
		if t["is_revealed"]:
			continue
		if abs(t["x"] - p["x"]) <= 2 and abs(t["y"] - p["y"]) <= 2:
			if Dice.saving_throw(p["modifiers"], "WIS", t["dc"])["success"]:
				t["is_revealed"] = true
				evs.append({"text": "%s spots a hidden trap nearby!" % p["name"], "color": "#fb7185"})


## Step-on hazard tiles: lava burn, pitfall, sky edge (game_state.py:759).
func _apply_tile_effects(p: Dictionary, evs: Array) -> void:
	match map[p["y"]][p["x"]]:
		"L":
			_env_damage(p, 10)
			evs.append(_hazard_event("%s is burned by lava! -10 HP" % p["name"], "#f97316", "hellfire", p["x"], p["y"]))
		"P":
			if Dice.saving_throw(p["modifiers"], "DEX", 15)["success"]:
				evs.append({"text": "%s nimbly dodges a pitfall!" % p["name"], "color": "#4ade80"})
			else:
				p["health"] -= 20
				p["x"] = MAP_WIDTH / 2
				p["y"] = MAP_HEIGHT / 2
				if p["health"] <= 0:
					p["health"] = p["max_health"]
				evs.append({"text": "%s fell into a pit! -20 HP, dragged back to start." % p["name"], "color": "#475569"})
		"E":
			if Dice.saving_throw(p["modifiers"], "DEX", 12)["success"]:
				evs.append({"text": "%s balances on the crumbling edge." % p["name"], "color": "#4ade80"})
			else:
				_env_damage(p, 15)
				evs.append({"text": "%s slips on the edge! -15 HP" % p["name"], "color": "#475569"})


## Spring a trap on the tile the player landed on (game_state.py:781).
func _trigger_trap(p: Dictionary, evs: Array) -> void:
	var hit := ""
	for tid in traps:
		var t: Dictionary = traps[tid]
		if t["x"] == p["x"] and t["y"] == p["y"]:
			var sv := Dice.saving_throw(p["modifiers"], "DEX", t["dc"])
			if sv["success"]:
				evs.append({"text": "TRAP! %s rolls %d+%d vs DC %d: SAVED!" % [p["name"], sv["roll"], sv["mod"], t["dc"]], "color": "#4ade80"})
			else:
				var dmg := Dice.roll(t["damage"])
				_env_damage(p, dmg)
				evs.append(_hazard_event("TRAP! %s takes %d damage!" % [p["name"], dmg], "#ef4444", "trap", p["x"], p["y"]))
			hit = tid
			break
	if hit != "":
		traps.erase(hit)


# ============================================================
#  Interactive objects — traps, hatches, altars (game_state.py:580 / 1135)
# ============================================================
func _spawn_traps(count: int) -> void:
	for _i in range(count):
		for _attempt in range(50):
			var tx := randi_range(1, MAP_WIDTH - 2)
			var ty := randi_range(1, MAP_HEIGHT - 2)
			if map[ty][tx] == "." and not is_entity_at(tx, ty):
				var id := "tr%d" % _next_trap_id
				_next_trap_id += 1
				traps[id] = {"id": id, "x": tx, "y": ty, "dc": 10 + region_number / 2,
					"damage": "2d6", "type": "Spike", "is_revealed": false}
				break


## Spawn one region-scaled monster from a hatch (game_state.py:580).
func _spawn_hatch_monster(x: int, y: int) -> Dictionary:
	var act := (region_number - 1) / 5 + 1
	var ng_mult := 1.0 + ng_plus * 0.25
	var base_hp := {"Goblin": 40 + (act - 1) * 30, "Orc": 80 + (act - 1) * 40, "Slime": 30 + (act - 1) * 25}
	var base_atk := 15 + (act - 1) * 10
	var suffix: String = biome()["monster_suffix"]
	var accent: String = biome()["accent"]
	var monster_ac := 10 + (region_number / 2)
	var r := randf()
	var m: Dictionary
	if r < 0.5:
		m = _new_monster(x, y, "Goblin %s" % suffix, "goblin", accent, int(base_hp["Goblin"] * ng_mult), monster_ac)
	elif r < 0.8:
		m = _new_monster(x, y, "Orc %s" % suffix, "orc", accent, int(base_hp["Orc"] * ng_mult), monster_ac + 2)
	else:
		m = _new_monster(x, y, "Slime %s" % suffix, "slime", accent, int(base_hp["Slime"] * ng_mult), monster_ac - 2)
	m["attack_damage"] = int(base_atk * ng_mult)
	monsters[m["id"]] = m
	return m


## Open a hatch tile: 60% loot, 40% ambush monster (game_state.py:612).
func _open_hatch(x: int, y: int) -> Dictionary:
	map[y][x] = "."   # the door becomes walkable floor regardless of contents
	if randf() < 0.60:
		var item := _generate_loot_item(x, y)
		items[item["id"]] = item
		return {"kind": "loot", "name": item["name"], "color": "#fbbf24"}
	var m := _spawn_hatch_monster(x, y)
	return {"kind": "monster", "name": m["name"], "color": "#ef4444"}


## /bash — STR check to force an adjacent hatch (game_state.py:1154).
func player_bash(peer_id: int) -> Dictionary:
	return _force_hatch(peer_id, "STR", "bashed open the hatch")


## /pick — DEX check to pick an adjacent hatch lock (game_state.py:1171).
func player_pick(peer_id: int) -> Dictionary:
	return _force_hatch(peer_id, "DEX", "picked the hatch lock")


func _force_hatch(peer_id: int, stat: String, verb: String) -> Dictionary:
	if not players.has(peer_id):
		return {"success": false}
	var p: Dictionary = players[peer_id]
	var d := _adjacent_tile(p, "D")
	if d.x < 0:
		return {"success": false, "message": "No hatch nearby."}
	var sv := Dice.saving_throw(p["modifiers"], stat, 13)
	if not sv["success"]:
		return {"success": false, "message": "The hatch resists. (Roll: %d+%d vs DC 13)" % [sv["roll"], sv["mod"]]}
	var reveal := _open_hatch(d.x, d.y)
	var tail := "Inside: %s!" % reveal["name"] if reveal["kind"] == "loot" else "A %s lunges out!" % reveal["name"]
	return {"success": true, "message": "%s %s! (Roll: %d+%d) %s" % [p["name"], verb, sv["roll"], sv["mod"], tail], "color": reveal["color"]}


## /pray — spend an adjacent altar for a heal or a permanent +2 stat (game_state.py:1135).
func player_pray(peer_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"success": false}
	var p: Dictionary = players[peer_id]
	var a := _adjacent_tile(p, "A")
	if a.x < 0:
		return {"success": false, "message": "No Altar nearby."}
	map[a.y][a.x] = "."   # spend the altar
	if randf() < 0.30:
		p["health"] = p["max_health"]
		return {"success": true, "message": "%s is fully healed by the gods!" % p["name"], "color": "#4ade80"}
	var stat: String = ["STR", "DEX", "CON", "INT", "WIS"][randi() % 5]
	p["stats"][stat] += 2
	p["modifiers"][stat] = (p["stats"][stat] - 10) / 2
	return {"success": true, "message": "The gods grant %s a permanent +2 %s!" % [p["name"], stat], "color": "#fbbf24"}


## Rogue melts into shadows: monsters skip hidden players and won't trigger combat by
## proximity. Cleared at the start of the rogue's next turn.
func player_hide(peer_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"success": false}
	var p: Dictionary = players[peer_id]
	if p.get("class_key", "") != "rogue":
		return {"success": false, "message": "Only a Rogue can melt into the shadows.", "color": "#ef4444"}
	if p.get("is_hidden", false):
		return {"success": false, "message": "%s is already hidden." % p["name"], "color": "#94a3b8"}
	if phase == "PLAYERS":
		if current_turn_id != peer_id:
			return {"success": false, "message": "Not your turn.", "color": "#ef4444"}
		if p.get("bonus_action_used", false):
			return {"success": false, "message": "Bonus action already used.", "color": "#ef4444"}
		p["bonus_action_used"] = true
	p["is_hidden"] = true
	return {"success": true, "message": "%s melts into the shadows." % p["name"], "color": "#a78bfa"}


## Examine the nearest creature within sight to reveal its vitals.
func player_examine(peer_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"success": false}
	var p: Dictionary = players[peer_id]
	var target = null
	var best := 9999.0
	for m in monsters.values():
		var d: float = Vector2(p["x"], p["y"]).distance_to(Vector2(m["x"], m["y"]))
		if d <= 5.0 and d < best:
			best = d
			target = m
	if target == null:
		return {"success": false, "message": "No creature close enough to examine.", "color": "#ef4444"}
	return {"success": true, "message": "%s: HP %d/%d, AC %d, ATK %d" % [target["name"], int(target["hp"]), int(target["max_hp"]), int(target.get("ac", 10)), int(target.get("attack_damage", 0))], "color": "#38bdf8"}


const BOON_POOL := [
	{"id": "vitality", "name": "Vitality", "desc": "+25 max HP"},
	{"id": "power", "name": "Power", "desc": "+6 attack damage"},
	{"id": "precision", "name": "Precision", "desc": "+2 DEX, +1 AC"},
	{"id": "arcane", "name": "Arcane", "desc": "+25 max MP"},
	{"id": "bulwark", "name": "Bulwark", "desc": "+2 Armor Class"},
	{"id": "ferocity", "name": "Ferocity", "desc": "+1 STR & +1 CON"},
]


## Apply a chosen level-up boon (permanent for the run). Consumes one pick.
func choose_boon(peer_id: int, boon_id: String) -> Dictionary:
	if not players.has(peer_id):
		return {"success": false}
	var p: Dictionary = players[peer_id]
	if p.get("boon_picks", 0) <= 0:
		return {"success": false, "message": "No boon to choose right now.", "color": "#ef4444"}
	var label := ""
	match boon_id:
		"vitality":
			p["max_health"] += 25
			p["health"] = p["max_health"]
			label = "Vitality"
		"power":
			p["attack_damage"] += 6
			label = "Power"
		"precision":
			p["stats"]["DEX"] += 2
			p["modifiers"]["DEX"] = (p["stats"]["DEX"] - 10) / 2
			p["ac"] = p.get("ac", 10) + 1
			label = "Precision"
		"arcane":
			p["max_mana"] = p.get("max_mana", 30) + 25
			p["mana"] = p["max_mana"]
			label = "Arcane"
		"bulwark":
			p["ac"] = p.get("ac", 10) + 2
			label = "Bulwark"
		"ferocity":
			p["stats"]["STR"] += 1
			p["stats"]["CON"] += 1
			p["modifiers"]["STR"] = (p["stats"]["STR"] - 10) / 2
			p["modifiers"]["CON"] = (p["stats"]["CON"] - 10) / 2
			label = "Ferocity"
		_:
			return {"success": false, "message": "Unknown boon.", "color": "#ef4444"}
	p["boon_picks"] = p.get("boon_picks", 0) - 1
	return {"success": true, "message": "%s embraces %s!" % [p["name"], label], "color": "#fbbf24"}


## QA helper: vaporize every enemy and drop back to exploration.
func qa_nuke() -> Dictionary:
	var n: int = monsters.size()
	monsters.clear()
	initiative_queue.clear()
	_init_pending.clear()
	current_turn_id = null
	current_turn_index = -1
	if phase != "EXPLORATION":
		phase = "EXPLORATION"
		first_combat_cleared = true
	return {"success": true, "message": "QA: %d enemies vaporized." % n, "color": "#f43f5e"}


## Position of an adjacent (incl. diagonal) tile matching `ch`, or (-1,-1).
func _adjacent_tile(p: Dictionary, ch: String) -> Vector2i:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var tx: int = p["x"] + dx
			var ty: int = p["y"] + dy
			if tx >= 0 and tx < MAP_WIDTH and ty >= 0 and ty < MAP_HEIGHT and map[ty][tx] == ch:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


func _portal_at(x: int, y: int) -> bool:
	for it in items.values():
		if it["type"] == "portal" and it["x"] == x and it["y"] == y:
			return true
	return false


## Trigger combat if within 1.5 tiles of a monster in EXPLORATION (game_state.py:844).
func check_combat_engagement(peer_id: int) -> bool:
	if phase != "EXPLORATION" or monsters.is_empty():
		return false
	var p: Dictionary = players.get(peer_id, {})
	if p.is_empty() or p.get("is_hidden", false):
		return false
	for m in monsters.values():
		if Vector2(p["x"], p["y"]).distance_to(Vector2(m["x"], m["y"])) <= 1.5:
			begin_initiative()
			return true
	return false


# ============================================================
#  Turn management (game_state.py:861)
# ============================================================
func end_turn(peer_id: int) -> bool:
	if players.has(peer_id) and phase == "PLAYERS":
		players[peer_id]["ended_turn"] = true
		return true
	return false


## Open combat: monsters auto-roll initiative; players must each roll manually.
func begin_initiative() -> void:
	phase = "INITIATIVE"
	initiative_queue = []
	current_turn_index = -1
	current_turn_id = null
	_init_pending = {}
	for mid in monsters:
		var m: Dictionary = monsters[mid]
		var r: int = Dice.d20() + m["modifiers"].get("DEX", 0)
		initiative_queue.append({"id": mid, "type": "monster", "roll": r, "name": m["name"]})
	for pid in players:
		_init_pending[pid] = true
	# Edge case: no players to roll (e.g. all hidden/gone) — finalize immediately.
	if _init_pending.is_empty():
		_finalize_initiative()


## A player rolls their d20 + DEX for initiative. Finalizes once everyone's in.
func roll_initiative(peer_id: int) -> Dictionary:
	if phase != "INITIATIVE":
		return {"success": false, "message": "It is not time to roll initiative."}
	if not _init_pending.has(peer_id):
		return {"success": false, "message": "You have already rolled."}
	var p: Dictionary = players[peer_id]
	var raw := Dice.d20()
	var mod: int = p["modifiers"].get("DEX", 0)
	var total := raw + mod
	initiative_queue.append({"id": peer_id, "type": "player", "roll": total, "name": p["name"]})
	_init_pending.erase(peer_id)
	var all_rolled: bool = _init_pending.is_empty()
	if all_rolled:
		_finalize_initiative()
	var sign_str := "+" if mod >= 0 else ""
	return {
		"success": true,
		"message": "%s rolls initiative: %d %s%d = %d" % [p["name"], raw, sign_str, mod, total],
		"dice": {"roll": raw, "mod": mod, "total": total, "name": p["name"], "kind": "initiative"},
		"all_rolled": all_rolled,
	}


## Sort the rolled queue and hand the first turn out — combat proper begins.
func _finalize_initiative() -> void:
	initiative_queue.sort_custom(func(a, b): return a["roll"] > b["roll"])
	current_turn_index = 0
	phase = "PLAYERS"
	if not initiative_queue.is_empty():
		current_turn_id = initiative_queue[0]["id"]
		_start_entity_turn(current_turn_id)
	else:
		current_turn_id = null


func _start_entity_turn(entity_id) -> void:
	if players.has(entity_id):
		var p: Dictionary = players[entity_id]
		p["moves_left"] = 5
		p["action_used"] = false
		p["bonus_action_used"] = false
		p["ended_turn"] = false
		p["is_hidden"] = false
	elif monsters.has(entity_id):
		var m: Dictionary = monsters[entity_id]
		m["moves_left"] = 5
		m["action_used"] = false
		m["bonus_action_used"] = false


func advance_turn(_depth := 0):
	if initiative_queue.is_empty() or _depth > initiative_queue.size() + 1:
		current_turn_id = null
		return null
	current_turn_index = (current_turn_index + 1) % initiative_queue.size()
	if current_turn_index == 0:
		round_number += 1
		last_round_events = _apply_biome_round_effects()
	current_turn_id = initiative_queue[current_turn_index]["id"]
	if not players.has(current_turn_id) and not monsters.has(current_turn_id):
		return advance_turn(_depth + 1)
	_start_entity_turn(current_turn_id)
	return current_turn_id


# ============================================================
#  Player attack (game_state.py:990)
# ============================================================
func player_attack(peer_id: int) -> Dictionary:
	if not ids_equal(peer_id, current_turn_id):
		return {"success": false, "message": "It is not your turn!"}
	var p: Dictionary = players[peer_id]
	if p.get("action_used", false):
		return {"success": false, "message": "Already used your action this turn."}

	var px: int = p["x"]
	var py: int = p["y"]
	var atk_range: float = p["attack_range"]
	var target_id = null
	var min_dist := 9999.0
	for mid in monsters:
		var mm: Dictionary = monsters[mid]
		var dist := Vector2(mm["x"], mm["y"]).distance_to(Vector2(px, py))
		if dist <= atk_range and dist < min_dist:
			min_dist = dist
			target_id = mid
	if target_id == null:
		return {"success": false, "message": "No target in range."}

	var m: Dictionary = monsters[target_id]
	p["action_used"] = true
	var disadvantage := has_status_effect(p, "blinded") or has_status_effect(p, "frightened")
	var roll := Dice.roll("1d20", false, disadvantage)
	var atk_bonus: int = p["modifiers"].get("STR", 0)
	if p["class"] in ["Rogue", "Ranger"]:
		atk_bonus = p["modifiers"].get("DEX", 0)
	var eq_weapon = p.get("equipment", {}).get("weapon")
	if eq_weapon != null:
		atk_bonus += eq_weapon.get("atk_bonus", 0)
	var prof: int = (p["level"] / 4) + 2
	var hit_score := roll + atk_bonus + prof
	var is_crit := roll == 20
	var is_fumble := roll == 1
	var hit: bool = (hit_score >= m["ac"] or is_crit) and not is_fumble
	var dice_info := {"roll": roll, "mod": atk_bonus + prof, "target_ac": m["ac"], "type": "d20"}

	if not hit:
		var fumble_text := "CRITICAL FAIL! " if is_fumble else ""
		return {
			"success": true, "color": "#94a3b8", "dice": dice_info,
			"message": "%s%s rolls %d+%d vs AC %d: MISS!" % [fumble_text, p["name"], roll, dice_info["mod"], m["ac"]],
		}

	var damage := Dice.roll(p.get("damage_dice", "1d8"))
	if is_crit:
		damage *= 2
	damage = int(damage * _guild_damage_multiplier(peer_id))   # guild bonus
	m["hp"] -= damage
	var is_dead: bool = m["hp"] <= 0
	var fx_type := "slash"
	if p["class"] == "Mage":
		fx_type = "fireball"
	elif p["class"] == "Rogue":
		fx_type = "shadow"
	var crit_text := "CRITICAL HIT! " if is_crit else ""
	var msg := "%s%s rolls %d+%d vs AC %d: HIT! deals %d dmg!" % [crit_text, p["name"], roll, dice_info["mod"], m["ac"], damage]
	if is_dead:
		msg += " %s is slain!" % m["name"]
		grant_xp(p, 20 + region_number * 5)
		_drop_loot(m["x"], m["y"])
		monsters.erase(target_id)
	return {
		"success": true, "message": msg,
		"color": "#fbbf24" if is_crit else p["color"],
		"dice": dice_info, "effect": {"type": fx_type, "x": m["x"], "y": m["y"], "amount": damage},
	}


# ============================================================
#  Player ability (game_state.py:1188) — class signatures
# ============================================================
func player_ability(peer_id: int) -> Dictionary:
	if not ids_equal(peer_id, current_turn_id):
		return {"success": false, "message": "It is not your turn!"}
	var p: Dictionary = players[peer_id]
	var is_bonus: bool = p["action_type"] == "bonus"
	if is_bonus and p.get("bonus_action_used", false):
		return {"success": false, "message": "Already used your bonus action."}
	if not is_bonus and p.get("action_used", false):
		return {"success": false, "message": "Already used your main action."}
	var cost: int = p["ability_cost"]
	if p["mana"] < cost:
		return {"success": false, "message": "Not enough mana! Need %d, have %d." % [cost, p["mana"]]}

	p["mana"] -= cost
	if is_bonus:
		p["bonus_action_used"] = true
	else:
		p["action_used"] = true

	var px: int = p["x"]
	var py: int = p["y"]
	var abl_range: float = p["ability_range"]
	var base_dmg: int = int(p["attack_damage"] * _guild_damage_multiplier(peer_id))   # guild bonus
	var ability: String = p["ability_name"]
	var parts: Array = []
	var fx = null

	match ability:
		"Whirlwind":
			for mid in monsters.keys():
				var m: Dictionary = monsters[mid]
				if Vector2(m["x"], m["y"]).distance_to(Vector2(px, py)) <= abl_range:
					_damage_monster(p, mid, base_dmg, parts)
			fx = {"type": "whirlwind", "x": px, "y": py}
		"Frost Nova":
			for mid in monsters.keys():
				var m: Dictionary = monsters[mid]
				if Vector2(m["x"], m["y"]).distance_to(Vector2(px, py)) <= abl_range:
					apply_status_effect(m, "stun", 1)
					_damage_monster(p, mid, int(base_dmg * 1.2), parts)
			fx = {"type": "frost", "x": px, "y": py}
		"Shadow Step":
			var target_mid = _nearest_monster(px, py, abl_range)
			if target_mid != null:
				var m: Dictionary = monsters[target_mid]
				for off in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var tx: int = m["x"] + off.x
					var ty: int = m["y"] + off.y
					if is_walkable(tx, ty) and not is_entity_at(tx, ty):
						p["x"] = tx
						p["y"] = ty
						break
				_damage_monster(p, target_mid, int(base_dmg * 2.5), parts, "Backstabs %s for %d")
				fx = {"type": "shadow", "x": m["x"], "y": m["y"]}
		"Holy Resonance":
			var heal := base_dmg + 30
			for p2 in players.values():
				if Vector2(p2["x"], p2["y"]).distance_to(Vector2(px, py)) <= abl_range:
					p2["health"] = min(p2["max_health"], p2["health"] + heal)
					parts.append("%s healed %d" % [p2["name"], heal])
			fx = {"type": "heal_aoe", "x": px, "y": py}
		"Volley":
			for mid in monsters.keys():
				var m: Dictionary = monsters[mid]
				if Vector2(m["x"], m["y"]).distance_to(Vector2(px, py)) <= abl_range:
					_damage_monster(p, mid, int(base_dmg * 0.8), parts)
			fx = {"type": "volley", "x": px, "y": py}

	if parts.is_empty():
		parts.append("No targets hit")
	return {
		"success": true,
		"message": "%s uses %s! %s." % [p["name"], ability, ", ".join(parts)],
		"color": p["color"], "effect": fx,
	}


func _nearest_monster(px: int, py: int, max_range: float):
	var target = null
	var min_d := 9999.0
	for mid in monsters:
		var m: Dictionary = monsters[mid]
		var d := Vector2(m["x"], m["y"]).distance_to(Vector2(px, py))
		if d <= max_range and d < min_d:
			min_d = d
			target = mid
	return target


func _damage_monster(p: Dictionary, mid: String, dmg: int, parts: Array, fmt := "%s takes %d") -> void:
	var m: Dictionary = monsters[mid]
	m["hp"] -= dmg
	parts.append(fmt % [m["name"], dmg])
	if m["hp"] <= 0:
		grant_xp(p, 20 + region_number * 5)
		_drop_loot(m["x"], m["y"])
		monsters.erase(mid)


# ============================================================
#  Potions (game_state.py:1356)
# ============================================================
func player_heal(peer_id: int) -> Dictionary:
	var p: Dictionary = players.get(peer_id, {})
	if p.is_empty():
		return {"success": false}
	if p.get("health_potions", 0) <= 0:
		return {"success": false, "message": "No health potions!"}
	p["health_potions"] -= 1
	p["health"] = min(p["max_health"], p["health"] + 50)
	return {"success": true, "message": "%s drinks a Health Potion! +50 HP." % p["name"], "color": "#10b981"}


func player_mana(peer_id: int) -> Dictionary:
	var p: Dictionary = players.get(peer_id, {})
	if p.is_empty():
		return {"success": false}
	if p.get("mana_potions", 0) <= 0:
		return {"success": false, "message": "No mana potions!"}
	p["mana_potions"] -= 1
	p["mana"] = min(p["max_mana"], p["mana"] + 40)
	return {"success": true, "message": "%s drinks a Mana Potion! +40 MP." % p["name"], "color": "#3b82f6"}


# ============================================================
#  Monster spawning (game_state.py:1451)
# ============================================================
func spawn_monster_wave(num := 3) -> void:
	monsters.clear()
	var act := (region_number - 1) / 5 + 1
	var ng_mult := 1.0 + ng_plus * 0.25

	# Boss regions: every 5th region spawns a single act boss (game_state.py:1461).
	if region_number > 0 and region_number % 5 == 0:
		_spawn_boss(ng_mult)
		return

	var base_hp := {
		"Goblin": 40 + (act - 1) * 30,
		"Orc": 80 + (act - 1) * 40,
		"Slime": 30 + (act - 1) * 25,
	}
	var base_atk := 15 + (act - 1) * 10
	var suffix: String = biome()["monster_suffix"]
	var accent: String = biome()["accent"]
	for _i in range(num):
		for _attempt in range(50):
			var x := randi_range(1, MAP_WIDTH - 2)
			var y := randi_range(1, MAP_HEIGHT - 2)
			if (map[y][x] == "." or map[y][x] == "T") and not is_entity_at(x, y):
				var monster_ac := 10 + (region_number / 2)
				var r := randf()
				var m: Dictionary
				if r < 0.30:
					m = _new_monster(x, y, "Goblin %s" % suffix, "goblin", accent, int(base_hp["Goblin"] * ng_mult), monster_ac)
					m["archetype"] = "skirmisher"
				elif r < 0.48:
					m = _new_monster(x, y, "Orc %s" % suffix, "orc", accent, int(base_hp["Orc"] * ng_mult), monster_ac + 2)
					m["archetype"] = "brute"
				elif r < 0.64:
					m = _new_monster(x, y, "Skeleton Archer %s" % suffix, "goblin", accent, int(base_hp["Goblin"] * ng_mult), monster_ac)
					m["archetype"] = "archer"
					m["attack_range"] = 5.0
				elif r < 0.78:
					m = _new_monster(x, y, "Cultist %s" % suffix, "slime", accent, int(base_hp["Slime"] * ng_mult), monster_ac)
					m["archetype"] = "caster"
					m["attack_range"] = 4.5
				elif r < 0.90:
					m = _new_monster(x, y, "Acolyte %s" % suffix, "slime", accent, int(base_hp["Slime"] * ng_mult), monster_ac)
					m["archetype"] = "healer"
					m["attack_range"] = 3.5
				else:
					m = _new_monster(x, y, "Ghoul %s" % suffix, "orc", accent, int(base_hp["Orc"] * ng_mult), monster_ac)
					m["archetype"] = "lurker"
				m["attack_damage"] = int(base_atk * ng_mult)
				if randf() < 0.18 + region_number * 0.01:
					_apply_elite_affix(m)
				monsters[m["id"]] = m
				break


const ELITE_AFFIXES := ["Veteran", "Savage", "Vampiric", "Venomous", "Dire", "Frenzied"]


## Promote a monster to an elite with one 5e-flavored affix: stat mods + a name prefix.
func _apply_elite_affix(m: Dictionary) -> void:
	var affix: String = ELITE_AFFIXES[randi() % ELITE_AFFIXES.size()]
	m["elite"] = affix
	m["name"] = "%s %s" % [affix, m["name"]]
	match affix:
		"Veteran":
			m["max_hp"] = int(m["max_hp"] * 1.6)
			m["ac"] += 2
		"Savage":
			m["attack_damage"] = int(m["attack_damage"] * 1.6)
			m["max_hp"] = int(m["max_hp"] * 1.2)
		"Vampiric":
			m["max_hp"] = int(m["max_hp"] * 1.4)
		"Venomous":
			m["max_hp"] = int(m["max_hp"] * 1.3)
		"Dire":
			m["max_hp"] = int(m["max_hp"] * 2.0)
			m["attack_damage"] = int(m["attack_damage"] * 1.1)
		"Frenzied":
			m["attack_damage"] = int(m["attack_damage"] * 1.35)
			m["max_hp"] = int(m["max_hp"] * 1.35)
	m["hp"] = m["max_hp"]


func _new_monster(x: int, y: int, mname: String, sprite: String, color: String, hp: int, ac: int) -> Dictionary:
	var id := "m%d" % _next_monster_id
	_next_monster_id += 1
	var stats := {"STR": 12, "DEX": 10, "CON": 12, "INT": 8, "WIS": 10, "CHA": 8}
	var modifiers := {}
	for s in stats:
		modifiers[s] = (stats[s] - 10) / 2
	return {
		"id": id, "x": x, "y": y, "name": mname, "sprite": sprite, "color": color,
		"hp": hp, "max_hp": hp, "attack_damage": 15, "ac": ac, "is_boss": false,
		"status_effects": [], "stats": stats, "modifiers": modifiers,
		"action_used": false, "bonus_action_used": false, "moves_left": 5,
		"archetype": "brute", "attack_range": 1.5,
	}


## One act boss at map center (game_state.py:1461). region 5 / 10 / 15.
func _spawn_boss(ng_mult: float) -> void:
	var cx: int = MAP_WIDTH / 2
	var cy: int = MAP_HEIGHT / 2
	var r5 := region_number == 5 or region_number % 15 == 5
	var r10 := region_number == 10 or region_number % 15 == 10
	var m: Dictionary
	if r5:
		m = _new_monster(cx, cy, "Goblin King", "boss", "#b91c1c", int(300 * ng_mult), 14)
		m["attack_damage"] = int(45 * ng_mult)
	elif r10:
		m = _new_monster(cx, cy, "Lich of the Abyss", "boss", "#4f46e5", int(600 * ng_mult), 16)
		m["attack_damage"] = int(60 * ng_mult)
	else:
		m = _new_monster(cx, cy, "Void Herald", "boss", "#a855f7", int(1000 * ng_mult), 18)
		m["attack_damage"] = int(85 * ng_mult)
	m["is_boss"] = true
	m["add_theme"] = _boss_add_theme(m["name"])
	m["summons_fired"] = []
	monsters[m["id"]] = m


## The themed minions a boss summons (matches the wave archetype system).
func _boss_add_theme(boss_name: String) -> Dictionary:
	match boss_name:
		"Lich of the Abyss":
			return {"name": "Risen Skeleton", "sprite": "goblin", "color": "#6366f1", "archetype": "archer", "range": 5.0}
		"Void Herald":
			return {"name": "Void Spawn", "sprite": "slime", "color": "#a855f7", "archetype": "caster", "range": 4.5}
		_:
			return {"name": "Goblin Runt", "sprite": "goblin", "color": "#b91c1c", "archetype": "skirmisher", "range": 1.5}


# ============================================================
#  Monster AI turn (game_state.py:1515)
# ============================================================
func execute_monster_turn(mid: String) -> Array:
	if not ids_equal(mid, current_turn_id) or not monsters.has(mid):
		return []
	var m: Dictionary = monsters[mid]
	var logs: Array = []

	var sresult := process_status_effects(m)
	var stunned: bool = sresult[1]
	if stunned or m["hp"] <= 0:
		if m["hp"] <= 0:
			monsters.erase(mid)
		return logs

	var closest_p = _closest_visible_player(m)
	if closest_p == null:
		return logs
	var rng: float = m.get("attack_range", 1.5)
	if m.get("archetype", "") == "healer" and not m["action_used"]:
		if _monster_heal_ally(m, logs):
			m["action_used"] = true
			return logs

	# Move toward target.
	while m["moves_left"] > 0:
		var dist := Vector2(closest_p["x"], closest_p["y"]).distance_to(Vector2(m["x"], m["y"]))
		if dist <= rng:
			break
		var dx := signi(closest_p["x"] - m["x"])
		var dy := signi(closest_p["y"] - m["y"])
		if is_walkable(m["x"] + dx, m["y"] + dy) and not is_entity_at(m["x"] + dx, m["y"] + dy):
			m["x"] += dx
			m["y"] += dy
			m["moves_left"] -= 1
		else:
			break

	# Attack if adjacent.
	if Vector2(closest_p["x"], closest_p["y"]).distance_to(Vector2(m["x"], m["y"])) <= rng and not m["action_used"]:
		_monster_special_or_attack(m, closest_p, logs)
		m["action_used"] = true
	return logs


func _closest_visible_player(m: Dictionary):
	var closest = null
	var min_dist := 9999.0
	for p in players.values():
		if p.get("is_hidden", false):
			continue
		var dist := Vector2(p["x"], p["y"]).distance_to(Vector2(m["x"], m["y"]))
		if dist < min_dist:
			min_dist = dist
			closest = p
	return closest


func _monster_special_or_attack(m: Dictionary, target: Dictionary, logs: Array) -> void:
	if m.get("is_boss", false):
		_boss_turn(m, target, logs)
		return
	var p_ac: int = target.get("ac", 10)
	var arch: String = m.get("archetype", "brute")
	if arch == "caster" and randf() < 0.5:
		var svc := Dice.saving_throw(target["modifiers"], "CON", 12)
		if not svc["success"]:
			apply_status_effect(target, "stun", 1)
			logs.append({"text": "%s casts Hold! %s is held!" % [m["name"], target["name"]], "color": "#818cf8"})
			return
	if arch == "lurker" and randf() < 0.4:
		apply_status_effect(target, "poison", 2, 6)
		logs.append({"text": "%s's claws poison %s!" % [m["name"], target["name"]], "color": "#84cc16"})
		return
	if randf() < 0.25 and "Goblin" in m["name"]:
		var sv := Dice.saving_throw(target["modifiers"], "DEX", 12)
		if not sv["success"]:
			apply_status_effect(target, "blinded", 2)
			logs.append({"text": "%s throws Pocket Sand! %s is BLINDED!" % [m["name"], target["name"]], "color": "#64748b"})
		else:
			logs.append({"text": "%s tries Pocket Sand, but %s dodges!" % [m["name"], target["name"]], "color": "#94a3b8"})
		return
	if randf() < 0.25 and "Orc" in m["name"]:
		var sv := Dice.saving_throw(target["modifiers"], "WIS", 12)
		if not sv["success"]:
			apply_status_effect(target, "frightened", 2)
			logs.append({"text": "%s lets out a Roar! %s is FRIGHTENED!" % [m["name"], target["name"]], "color": "#ec4899"})
		else:
			logs.append({"text": "%s roars, but %s stands firm!" % [m["name"], target["name"]], "color": "#94a3b8"})
		return
	_perform_monster_attack(m, target, p_ac, logs)


## Healer archetype: mend the most-wounded ally monster within range (5e Cure Wounds).
func _monster_heal_ally(healer: Dictionary, logs: Array) -> bool:
	var best = null
	var worst_frac := 1.0
	for mid in monsters:
		var ally: Dictionary = monsters[mid]
		if ally["id"] == healer["id"]:
			continue
		var frac: float = float(ally["hp"]) / float(ally["max_hp"])
		if frac < worst_frac and Vector2(ally["x"], ally["y"]).distance_to(Vector2(healer["x"], healer["y"])) <= healer.get("attack_range", 3.5):
			worst_frac = frac
			best = ally
	if best == null or worst_frac >= 0.95:
		return false
	var heal: int = int(best["max_hp"] * 0.25)
	best["hp"] = min(best["max_hp"], best["hp"] + heal)
	logs.append({"text": "%s mends %s (+%d)!" % [healer["name"], best["name"], heal], "color": "#34d399", "effect": {"type": "heal_aoe", "x": best["x"], "y": best["y"], "amount": heal, "heal": true}})
	return true


func _perform_monster_attack(m: Dictionary, target: Dictionary, p_ac: int, logs: Array) -> void:
	var roll := Dice.d20()
	var hit := (roll >= p_ac or roll == 20) and roll != 1
	if hit:
		var damage: int = max(5, m["attack_damage"] + randi_range(-5, 5))
		target["health"] -= damage
		var elite: String = m.get("elite", "")
		if elite == "Vampiric":
			m["hp"] = min(m["max_hp"], m["hp"] + int(damage / 2))
		elif elite == "Venomous":
			apply_status_effect(target, "poison", 2, 6)
		logs.append({
			"text": "%s rolls %d vs AC %d: HIT! deals %d dmg!" % [m["name"], roll, p_ac, damage],
			"color": "#ef4444", "dice": {"roll": roll, "target_ac": p_ac, "type": "d20"},
			"effect": {"type": "slash", "x": target["x"], "y": target["y"], "amount": damage},
		})
		if target["health"] <= 0:
			logs.append({"text": "%s was defeated!" % target["name"], "color": "#ff0000"})
			target["health"] = target["max_health"]
			target["x"] = MAP_WIDTH / 2
			target["y"] = MAP_HEIGHT / 2
	else:
		logs.append({"text": "%s rolls %d vs AC %d: MISS!" % [m["name"], roll, p_ac], "color": "#94a3b8"})


## Boss signature turn: summon a themed add-wave when crossing an HP threshold
## (which consumes the turn), else a chance at an AoE cleave.
func _boss_turn(m: Dictionary, target: Dictionary, logs: Array) -> void:
	if _boss_summon_check(m, logs):
		return
	if randf() < 0.4:
		var hit_any := false
		for pid in players:
			var pl: Dictionary = players[pid]
			if Vector2(pl["x"], pl["y"]).distance_to(Vector2(m["x"], m["y"])) <= 2.5:
				var dmg: int = m["attack_damage"]
				pl["health"] -= dmg
				logs.append({"text": "%s cleaves! %s takes %d dmg!" % [m["name"], pl["name"], dmg], "color": "#ef4444", "effect": {"type": "whirlwind", "x": pl["x"], "y": pl["y"], "amount": dmg}})
				if pl["health"] <= 0:
					pl["health"] = pl["max_health"]
					pl["x"] = MAP_WIDTH / 2
					pl["y"] = MAP_HEIGHT / 2
				hit_any = true
		if hit_any:
			return
	_perform_monster_attack(m, target, target.get("ac", 10), logs)


## Boss add-waves: at 75% / 50% / 25% HP the boss summons an escalating, themed
## pack (and enrages once at <=50%). Returns true if anything was summoned this
## turn (so the caller can spend the turn on it). Fires every newly-crossed
## threshold in one call, bounded by the live-add cap, so a burst-down boss still
## reacts. Each threshold fires at most once (tracked in `summons_fired`).
const BOSS_SUMMON_THRESHOLDS := [0.75, 0.5, 0.25]
const MAX_BOSS_ADDS := 6


func _boss_summon_check(m: Dictionary, logs: Array) -> bool:
	var max_hp: int = max(1, int(m["max_hp"]))
	var hp_frac: float = float(m["hp"]) / float(max_hp)
	var fired: Array = m.get("summons_fired", [])
	var did_summon := false
	var enraged_now := false
	for i in range(BOSS_SUMMON_THRESHOLDS.size()):
		var t: float = BOSS_SUMMON_THRESHOLDS[i]
		if hp_frac > t or fired.has(t):
			continue
		fired.append(t)
		if t <= 0.5 and not m.get("enraged", false):
			m["enraged"] = true
			m["attack_damage"] = int(m["attack_damage"] * 1.5)
			enraged_now = true
		if _summon_adds(m, 2 + i) > 0:
			did_summon = true
	m["summons_fired"] = fired
	if did_summon:
		var verb: String = "ENRAGES and summons reinforcements" if enraged_now else "summons reinforcements"
		logs.append({"text": "%s %s!" % [m["name"], verb], "color": "#f43f5e", "effect": {"type": "shadow", "x": m["x"], "y": m["y"]}})
	return did_summon


## Spawn up to `count` themed minions on free tiles around a boss (respecting the
## live-add cap); they join initiative. Returns how many actually spawned.
func _summon_adds(boss: Dictionary, count: int) -> int:
	var theme: Dictionary = boss.get("add_theme", {})
	var live_adds := 0
	for mm in monsters.values():
		if mm.get("is_add", false):
			live_adds += 1
	var made := 0
	for _i in count:
		if live_adds + made >= MAX_BOSS_ADDS:
			break
		var pos := _adjacent_free_tile(boss)
		if pos.x < 0:
			continue
		var add := _new_monster(pos.x, pos.y, theme.get("name", "%s's Thrall" % boss["name"]), theme.get("sprite", "goblin"), theme.get("color", "#7f1d1d"), 40 + region_number * 3, 12)
		add["attack_damage"] = 12 + region_number
		add["archetype"] = theme.get("archetype", "skirmisher")
		add["attack_range"] = theme.get("range", 1.5)
		add["is_add"] = true
		monsters[add["id"]] = add
		initiative_queue.append({"id": add["id"], "type": "monster", "roll": 10, "name": add["name"]})
		made += 1
	return made


## First walkable, unoccupied tile adjacent to an entity, or (-1,-1).
func _adjacent_free_tile(e: Dictionary) -> Vector2i:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var tx: int = e["x"] + dx
			var ty: int = e["y"] + dy
			if is_walkable(tx, ty) and not is_entity_at(tx, ty):
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


# ============================================================
#  Region / story progression (game_state.py:1617)
# ============================================================
func generate_chapter_story() -> String:
	var idx := (region_number - 1) % 15
	var beat: Array = STORY_BEATS[idx]
	var prefix := ""
	if ng_plus > 0:
		prefix = "[Cycle %d] " % (ng_plus + 1)
	return "%s%s — %s" % [prefix, beat[0], beat[1]]


## Advance to the next region (or loop to NG+ after region 15). Regenerates the
## map for the act-appropriate biome and spawns a fresh wave. Returns dramatic
## transition text. (game_state.py:1626)
func advance_region() -> String:
	var old_region := region_number
	var dramatic := ""

	if region_number >= MAX_REGION:
		ng_plus += 1
		region_number = 1
		dramatic = ("🌟 VICTORY! The Void Herald is vanquished!\n"
			+ "But the whisper returns... 'Again.'\n"
			+ "⚔️ NEW GAME+ Cycle %d begins. Monsters grow stronger (+%d%%).\n" % [ng_plus + 1, ng_plus * 25]
			+ "Your strength carries forward. The corruption stirs anew...")
	else:
		region_number += 1
		var act_name: String = ACT_NAMES.get(act_number(), "The Journey Continues")
		var idx := (region_number - 1) % 15
		var transition: String = ACT_TRANSITIONS.get(old_region, "")
		var head := "⚔️ %s\nRegion %d: %s" % [act_name, region_number, STORY_BEATS[idx][0]]
		if transition != "":
			dramatic = "%s\n%s\n%s" % [head, transition, STORY_BEATS[idx][1]]
		else:
			dramatic = "%s\n%s" % [head, STORY_BEATS[idx][1]]

	# Act-based biome selection (game_state.py:1660).
	var act := act_number()
	if act == 1:
		current_biome = "Dreadwood Forest" if region_number < 4 else "Charred Wastes"
	elif act == 2:
		current_biome = "Whispering Caves" if region_number < 9 else "Abyssal Depths"
	else:
		current_biome = "Crimson Citadel" if region_number < 14 else "Frozen Hollow"

	first_combat_cleared = false
	map = generate_map(current_biome)
	round_number = 1
	phase = "EXPLORATION"
	initiative_queue = []
	current_turn_index = -1
	current_turn_id = null
	ready_players = {}
	items = {}
	npcs = {}
	torches = {}
	traps = {}
	_reposition_players()
	spawn_monster_wave(randi_range(3, 5))
	spawn_chests(randi_range(1, 3))
	_spawn_merchant()
	_spawn_torches()
	_spawn_traps(randi_range(2, 4))
	return dramatic


func _reposition_players() -> void:
	for pid in players:
		for _attempt in range(50):
			var x: int = clampi(MAP_WIDTH / 2 + randi_range(-3, 3), 1, MAP_WIDTH - 2)
			var y: int = clampi(MAP_HEIGHT / 2 + randi_range(-3, 3), 1, MAP_HEIGHT - 2)
			if map[y][x] == "." and not is_entity_at(x, y):
				var p: Dictionary = players[pid]
				p["x"] = x
				p["y"] = y
				p["moves_left"] = 5
				p["ended_turn"] = false
				p["action_used"] = false
				p["bonus_action_used"] = false
				break


# ============================================================
#  Loot, items & equipment (game_state.py:534)
# ============================================================
func _new_item(x: int, y: int, name: String, type: String, rarity := "Common", color := "#94a3b8") -> Dictionary:
	var id := "i%d" % _next_item_id
	_next_item_id += 1
	return {
		"id": id, "x": x, "y": y, "name": name, "type": type, "rarity": rarity,
		"color": color, "slot": "", "atk_bonus": 0, "def_bonus": 0, "requirements": {},
	}


## Weighted rarity + stat generation, scaling with region (game_state.py:535).
func _generate_loot_item(x: int, y: int) -> Dictionary:
	var bonus_base: int = max(1, region_number / 2)
	var rr := randf()
	var rarity := "Common"
	if rr >= 0.90:
		rarity = "Legendary"
	elif rr >= 0.70:
		rarity = "Epic"
	elif rr >= 0.40:
		rarity = "Rare"
	var total: int = bonus_base + RARITY_BONUS[rarity]
	var color: String = RARITY_COLORS[rarity]

	var rt := randf()
	var item: Dictionary
	if rt < 0.45:
		item = _new_item(x, y, "%s %s" % [rarity, WEAPON_NAMES[randi() % WEAPON_NAMES.size()]], "weapon", rarity, color)
		item["atk_bonus"] = total
		item["slot"] = "weapon"
		if total > 8:
			item["requirements"] = {("STR" if randf() > 0.5 else "DEX"): 10 + total / 2}
	elif rt < 0.80:
		item = _new_item(x, y, "%s %s" % [rarity, ARMOUR_NAMES[randi() % ARMOUR_NAMES.size()]], "armor", rarity, color)
		item["def_bonus"] = total
		item["slot"] = "armor"
		if total > 8:
			item["requirements"] = {"CON": 10 + total / 2}
	elif rt < 0.85:
		item = _new_item(x, y, "Scroll of Fireball", "scroll", rarity, "#f97316")
	elif rt < 0.94:
		item = _new_item(x, y, "Health Potion", "potion", rarity, "#ef4444")
	elif rt < 0.98:
		item = _new_item(x, y, "Gold Pouch", "gold", rarity, "#ffd700")
	else:
		# Mystic Portal — step on it to be whisked to an alt-dimension biome.
		item = _new_item(x, y, "Mystic Portal", "portal", rarity, "#a855f7")
	return item


## 80% chance to drop loot on a tile (game_state.py:571).
func _drop_loot(x: int, y: int) -> void:
	if randf() > 0.80:
		return
	var item := _generate_loot_item(x, y)
	items[item["id"]] = item


## Pick up non-chest items the player stepped on. Returns a summary string.
func _pickup_ground_items(p: Dictionary) -> String:
	var picked: Array = []
	for iid in items.keys():
		var it: Dictionary = items[iid]
		if it["x"] != p["x"] or it["y"] != p["y"] or it["type"] == "chest":
			continue
		match it["type"]:
			"potion":
				if "Health" in it["name"]:
					p["health_potions"] += 1
					picked.append("a Health Potion")
				else:
					p["mana_potions"] += 1
					picked.append("a Mana Potion")
			"gold":
				var val := randi_range(20, 60) + region_number * 10
				p["gold"] += val
				p["score"] += val
				picked.append("%d gold" % val)
			"weapon", "armor", "scroll":
				if p["inventory"].size() < INVENTORY_MAX:
					p["inventory"].append(_to_inv_entry(it))
					picked.append(it["name"])
		items.erase(iid)
	return ", ".join(picked)


func _to_inv_entry(it: Dictionary) -> Dictionary:
	return {
		"id": it["id"], "name": it["name"], "type": it["type"], "slot": it.get("slot", ""),
		"color": it.get("color", "#fff"), "rarity": it.get("rarity", "Common"),
		"atk_bonus": it.get("atk_bonus", 0), "def_bonus": it.get("def_bonus", 0),
		"requirements": it.get("requirements", {}),
	}


func _recompute_ac(p: Dictionary) -> void:
	p["ac"] = 10 + p["modifiers"].get("DEX", 0)
	var armor = p.get("equipment", {}).get("armor")
	if armor != null:
		p["ac"] += armor.get("def_bonus", 0)


## Equip an inventory item, or unequip an equipped one (game_state.py:1305).
func player_equip(peer_id: int, item_id: String) -> Dictionary:
	if not players.has(peer_id):
		return {"success": false}
	var p: Dictionary = players[peer_id]
	var inv: Array = p["inventory"]
	var eq: Dictionary = p["equipment"]

	# Already equipped? Unequip it back to inventory.
	for slot_name in ["weapon", "armor"]:
		var cur = eq.get(slot_name)
		if cur != null and cur["id"] == item_id:
			inv.append(cur)
			eq[slot_name] = null
			_recompute_ac(p)
			return {"success": true, "message": "Unequipped %s." % cur["name"], "color": "#fbbf24"}

	# Find in inventory.
	var idx := -1
	for i in range(inv.size()):
		if inv[i]["id"] == item_id:
			idx = i
			break
	if idx == -1:
		return {"success": false, "message": "Item not found."}
	var target: Dictionary = inv[idx]
	for stat in target.get("requirements", {}):
		if p["stats"].get(stat, 0) < target["requirements"][stat]:
			return {"success": false, "message": "Requires %d %s!" % [target["requirements"][stat], stat]}

	inv.remove_at(idx)
	var slot: String = target.get("slot", "weapon")
	var old = eq.get(slot)
	if old != null:
		inv.append(old)
	eq[slot] = target
	_recompute_ac(p)
	return {"success": true, "message": "Equipped %s!" % target["name"], "color": "#34d399"}


## Use a consumable from the inventory (potion or fireball scroll).
func inventory_use(peer_id: int, item_id: String) -> Dictionary:
	if not players.has(peer_id):
		return {"success": false}
	var p: Dictionary = players[peer_id]
	var inv: Array = p["inventory"]
	var idx := -1
	for i in range(inv.size()):
		if inv[i]["id"] == item_id:
			idx = i
			break
	if idx == -1:
		return {"success": false, "message": "Item not found."}
	var target: Dictionary = inv[idx]
	if target["type"] == "potion":
		inv.remove_at(idx)
		return player_heal(peer_id) if "Health" in target["name"] else player_mana(peer_id)
	if target["type"] == "scroll" and "Fireball" in target["name"]:
		inv.remove_at(idx)
		var dmg := 100
		for mid in monsters.keys():
			var m: Dictionary = monsters[mid]
			if Vector2(m["x"], m["y"]).distance_to(Vector2(p["x"], p["y"])) <= 4.0:
				m["hp"] -= dmg
				if m["hp"] <= 0:
					grant_xp(p, 50)
					_drop_loot(m["x"], m["y"])
					monsters.erase(mid)
		return {"success": true, "message": "%s unleashes a Fireball scroll! 100 dmg to nearby enemies." % p["name"], "color": "#f97316"}
	return {"success": false, "message": "This item cannot be used."}


# ============================================================
#  Chests & merchant (game_state.py:1419 / 1729)
# ============================================================
func spawn_chests(count: int) -> void:
	for _i in range(count):
		for _attempt in range(50):
			var cx := randi_range(1, MAP_WIDTH - 2)
			var cy := randi_range(1, MAP_HEIGHT - 2)
			if map[cy][cx] == "." and not is_entity_at(cx, cy):
				var chest := _new_item(cx, cy, "Chest", "chest", "Common", "#fbbf24")
				items[chest["id"]] = chest
				break


## Open an adjacent chest (game_state.py:495). Random gold/potion reward.
func loot_chest(peer_id: int, item_id: String) -> Dictionary:
	if not players.has(peer_id) or not items.has(item_id):
		return {"success": false}
	var p: Dictionary = players[peer_id]
	var chest: Dictionary = items[item_id]
	if chest["type"] != "chest":
		return {"success": false}
	if Vector2(p["x"], p["y"]).distance_to(Vector2(chest["x"], chest["y"])) > 1.5:
		return {"success": false, "message": "You are too far away to open that chest."}
	items.erase(item_id)
	var r := randf()
	if r < 0.2:
		p["health_potions"] += 1
		return {"success": true, "message": "%s opened a chest: a Health Potion!" % p["name"], "color": "#10b981"}
	elif r < 0.4:
		p["mana_potions"] += 1
		return {"success": true, "message": "%s opened a chest: a Mana Potion!" % p["name"], "color": "#3b82f6"}
	var val := randi_range(50, 200)
	p["gold"] += val
	p["score"] += val
	return {"success": true, "message": "%s opened a chest: %d gold!" % [p["name"], val], "color": "#ffd700"}


func _spawn_merchant() -> void:
	for _attempt in range(50):
		var mx := randi_range(2, MAP_WIDTH - 3)
		var my := randi_range(2, MAP_HEIGHT - 3)
		if map[my][mx] == "." and not is_entity_at(mx, my):
			var bonus: int = max(1, region_number)
			var npc := {
				"id": "n%d" % _next_item_id, "x": mx, "y": my, "name": "Merchant", "sprite": "merchant",
				"inventory": [
					{"id": "shop_hp", "name": "Health Potion", "price": 30, "type": "potion", "color": "#ef4444"},
					{"id": "shop_mp", "name": "Mana Potion", "price": 25, "type": "potion", "color": "#3b82f6"},
					{"id": "shop_wpn", "name": "Fine Sword +%d" % bonus, "price": 80 + bonus * 20, "type": "weapon", "slot": "weapon", "atk_bonus": bonus, "color": "#fbbf24"},
					{"id": "shop_arm", "name": "Sturdy Shield +%d" % bonus, "price": 70 + bonus * 15, "type": "armor", "slot": "armor", "def_bonus": bonus, "color": "#34d399"},
				],
			}
			_next_item_id += 1
			npcs[npc["id"]] = npc
			break


## Place 1-3 stationary torches on walkable, empty tiles (game_state.py:423).
## Torches are light sources only — they don't block movement.
func _spawn_torches(count_min := 1, count_max := 3) -> void:
	var count := randi_range(count_min, count_max)
	for _i in range(count):
		for _attempt in range(50):
			var x := randi_range(1, MAP_WIDTH - 2)
			var y := randi_range(1, MAP_HEIGHT - 2)
			if map[y][x] != "." or is_entity_at(x, y):
				continue
			if _torch_at(x, y):
				continue
			var id := "t%d" % _next_torch_id
			_next_torch_id += 1
			torches[id] = {"id": id, "x": x, "y": y, "radius": TORCH_LIT_RADIUS}
			break


func _torch_at(x: int, y: int) -> bool:
	for t in torches.values():
		if t["x"] == x and t["y"] == y:
			return true
	return false


# ============================================================
#  Portals & HellPlane (game_state.py:1749)
# ============================================================
## Cluster every player near the map centre and reset their turn flags.
func _cluster_players() -> void:
	var i := 0
	for pid in players:
		var p: Dictionary = players[pid]
		p["x"] = clampi(MAP_WIDTH / 2 + (i % 3) - 1, 1, MAP_WIDTH - 2)
		p["y"] = clampi(MAP_HEIGHT / 2 + (i / 3) - 1, 1, MAP_HEIGHT - 2)
		p["ended_turn"] = false
		p["action_used"] = false
		p["bonus_action_used"] = false
		p["moves_left"] = 5
		i += 1


## Step on a Mystic Portal -> warp the whole party to a random alt-dimension biome.
func enter_portal() -> String:
	current_biome = PORTAL_BIOMES[randi() % PORTAL_BIOMES.size()]
	map = generate_map(current_biome)
	monsters = {}
	items = {}
	npcs = {}
	torches = {}
	phase = "EXPLORATION"
	first_combat_cleared = false
	ready_players = {}
	initiative_queue = []
	current_turn_index = -1
	current_turn_id = null
	_cluster_players()
	spawn_monster_wave(randi_range(3, 5))
	_spawn_torches()
	return "✨ The party was sucked into a Mystic Portal!\nWelcome to %s." % current_biome


## Snapshot the current world and drop the party into HellPlane (chest-triggered).
func enter_hellplane() -> String:
	if in_hellplane:
		return ""
	_prior_world = {
		"map": map, "monsters": monsters, "items": items, "npcs": npcs, "torches": torches,
		"region_number": region_number, "current_biome": current_biome, "phase": phase,
		"initiative_queue": initiative_queue.duplicate(), "current_turn_index": current_turn_index,
		"current_turn_id": current_turn_id, "first_combat_cleared": first_combat_cleared,
		"player_positions": {},
	}
	for pid in players:
		_prior_world["player_positions"][pid] = [players[pid]["x"], players[pid]["y"]]

	current_biome = "HellPlane"
	map = generate_map("HellPlane")
	monsters = {}
	items = {}
	npcs = {}
	torches = {}
	phase = "EXPLORATION"
	first_combat_cleared = false
	initiative_queue = []
	current_turn_index = -1
	current_turn_id = null
	_cluster_players()
	spawn_monster_wave(randi_range(3, 5))
	_spawn_torches()
	_spawn_return_portal()
	in_hellplane = true
	return "🔥 The chest spits flame!\nYou are pulled into the HellPlane..."


## Step on the return portal -> restore the snapshotted world.
func return_from_hellplane() -> String:
	if not in_hellplane or _prior_world == null:
		return ""
	var pw: Dictionary = _prior_world
	map = pw["map"]
	monsters = pw["monsters"]
	items = pw["items"]
	npcs = pw["npcs"]
	torches = pw["torches"]
	region_number = pw["region_number"]
	current_biome = pw["current_biome"]
	phase = pw["phase"]
	initiative_queue = pw["initiative_queue"]
	current_turn_index = pw["current_turn_index"]
	current_turn_id = pw["current_turn_id"]
	first_combat_cleared = pw["first_combat_cleared"]
	for pid in pw["player_positions"]:
		if players.has(pid):
			players[pid]["x"] = pw["player_positions"][pid][0]
			players[pid]["y"] = pw["player_positions"][pid][1]
	_prior_world = null
	in_hellplane = false
	return "✨ The HellPlane fades behind you.\nYou return to your quest."


func _spawn_return_portal() -> void:
	for _attempt in range(50):
		var x := randi_range(2, MAP_WIDTH - 3)
		var y := randi_range(2, MAP_HEIGHT - 3)
		if map[y][x] == "." and not is_entity_at(x, y) and not _portal_at(x, y):
			var portal := _new_item(x, y, "Return Portal", "portal", "Epic", "#a855f7")
			items[portal["id"]] = portal
			return


# ============================================================
#  Per-round biome dangers (game_state.py:1876)
# ============================================================
## Applies the current biome's round hazard. Returns a list of events for the
## client to narrate + spawn particles: {text, color, vfx:{type, x, y}}.
func _apply_biome_round_effects() -> Array:
	var events: Array = []
	var hz = BIOME_HAZARDS.get(current_biome)
	if hz == null or round_number % hz["every"] != 0:
		return events
	match hz["kind"]:
		"drown":
			for pid in players:
				var p: Dictionary = players[pid]
				if map[p["y"]][p["x"]] != "B":
					_env_damage(p, 10)
					events.append(_hazard_event("%s is drowning! -10 HP" % p["name"], "#0ea5e9", "drown", p["x"], p["y"]))
		"hellfire":
			for pid in players:
				var p: Dictionary = players[pid]
				_env_damage(p, 8)
				events.append(_hazard_event("Hellfire scorches %s! -8 HP" % p["name"], "#ef4444", "hellfire", p["x"], p["y"]))
		"heat":
			for pid in players:
				var p: Dictionary = players[pid]
				if not Dice.saving_throw(p["modifiers"], "CON", 12)["success"]:
					apply_status_effect(p, "exhaustion", 3, 5)
					_env_damage(p, 6)
					events.append(_hazard_event("Heat wave! %s wilts. -6 HP, Exhaustion" % p["name"], "#f59e0b", "heat", p["x"], p["y"]))
		"frost":
			for pid in players:
				var p: Dictionary = players[pid]
				if not Dice.saving_throw(p["modifiers"], "CON", 12)["success"]:
					_env_damage(p, 6)
					if randf() < 0.25:
						apply_status_effect(p, "stun", 1)
					events.append(_hazard_event("Bitter cold bites %s! -6 HP" % p["name"], "#7dd3fc", "frost", p["x"], p["y"]))
		"rotate":
			_rotate_map()
			events.append(_hazard_event("The Clockwork Spire grinds and shifts!", "#fb923c", "rotate", MAP_WIDTH / 2, MAP_HEIGHT / 2))
		"wild":
			if randf() < 0.5:
				for pid in players:
					var p: Dictionary = players[pid]
					p["health"] = min(p["max_health"], p["health"] + 6)
				events.append(_hazard_event("Wild magic mends the party! +6 HP", "#d946ef", "wild", MAP_WIDTH / 2, MAP_HEIGHT / 2))
			else:
				for pid in players:
					var p: Dictionary = players[pid]
					_env_damage(p, 5)
				events.append(_hazard_event("Fey thorns lash the party! -5 HP", "#d946ef", "wild", MAP_WIDTH / 2, MAP_HEIGHT / 2))
	return events


func _hazard_event(text: String, color: String, vfx_type: String, x: int, y: int) -> Dictionary:
	return {"text": text, "color": color, "vfx": {"type": vfx_type, "x": x, "y": y}}


## Apply environmental damage; revive at map centre on defeat (like combat death).
func _env_damage(p: Dictionary, amount: int) -> void:
	p["health"] -= amount
	if p["health"] <= 0:
		p["health"] = p["max_health"]
		p["x"] = MAP_WIDTH / 2
		p["y"] = MAP_HEIGHT / 2


## Rotate the interior of the map 90° and carry entities with it (game_state.py:1895).
func _rotate_map() -> void:
	var new_map: Array = []
	for row in map:
		new_map.append(row.duplicate())
	for y in range(1, MAP_HEIGHT - 1):
		for x in range(1, MAP_WIDTH - 1):
			var nx := 7 - (y - 7)
			var ny := 7 + (x - 7)
			new_map[ny][nx] = map[y][x]
	map = new_map
	for p in players.values():
		if p["x"] >= 1 and p["x"] < MAP_WIDTH - 1 and p["y"] >= 1 and p["y"] < MAP_HEIGHT - 1:
			var px: int = p["x"]
			var py: int = p["y"]
			p["x"] = 7 - (py - 7)
			p["y"] = 7 + (px - 7)
	for m in monsters.values():
		if m["x"] >= 1 and m["x"] < MAP_WIDTH - 1 and m["y"] >= 1 and m["y"] < MAP_HEIGHT - 1:
			var mx: int = m["x"]
			var my: int = m["y"]
			m["x"] = 7 - (my - 7)
			m["y"] = 7 + (mx - 7)


func buy_item(peer_id: int, npc_id: String, shop_item_id: String) -> Dictionary:
	if not players.has(peer_id) or not npcs.has(npc_id):
		return {"success": false}
	var p: Dictionary = players[peer_id]
	var npc: Dictionary = npcs[npc_id]
	if Vector2(p["x"], p["y"]).distance_to(Vector2(npc["x"], npc["y"])) > 1.5:
		return {"success": false, "message": "No merchant in reach."}
	for itm in npc["inventory"]:
		if itm["id"] != shop_item_id:
			continue
		if p["gold"] < itm["price"]:
			return {"success": false, "message": "Not enough gold!"}
		p["gold"] -= itm["price"]
		if itm["type"] == "potion":
			if "Health" in itm["name"]:
				p["health_potions"] += 1
			else:
				p["mana_potions"] += 1
		elif p["inventory"].size() < INVENTORY_MAX:
			var entry := _new_item(0, 0, itm["name"], itm["type"], "Rare", itm["color"])
			entry["slot"] = itm.get("slot", "")
			entry["atk_bonus"] = itm.get("atk_bonus", 0)
			entry["def_bonus"] = itm.get("def_bonus", 0)
			p["inventory"].append(_to_inv_entry(entry))
		return {"success": true, "message": "Bought %s for %d gold!" % [itm["name"], itm["price"]], "color": "#fbbf24"}
	return {"success": false, "message": "Item not available."}


# ============================================================
#  State serialization (game_state.py:1940)
# ============================================================
func get_state_dict() -> Dictionary:
	return {
		"map": map,
		"phase": phase,
		"round": round_number,
		"region": region_number,
		"act": act_number(),
		"act_name": ACT_NAMES.get(act_number(), ""),
		"chapter": generate_chapter_story(),
		"ng_plus": ng_plus,
		"ready_count": ready_players.size(),
		"current_turn_id": current_turn_id,
		"initiative_queue": initiative_queue,
		"awaiting_init": _init_pending.keys(),
		"players": players,
		"monsters": monsters,
		"items": items,
		"npcs": npcs,
		"torches": torches,
		"traps": _revealed_traps(),
		"guilds": _guilds_for_state(),
		"player_guilds": player_guilds,
		"in_hellplane": in_hellplane,
		"biome": {"name": current_biome, "accent": biome()["accent"], "floor": biome()["floor"], "wall": biome()["wall"]},
	}


## Only revealed traps are sent to clients (hidden ones stay secret).
func _revealed_traps() -> Dictionary:
	var out := {}
	for tid in traps:
		if traps[tid]["is_revealed"]:
			out[tid] = traps[tid]
	return out


## Guild members are stored as a set; serialize as a plain array for clients.
func _guilds_for_state() -> Dictionary:
	var out := {}
	for gname in guilds:
		var g: Dictionary = guilds[gname]
		out[gname] = {"name": g["name"], "leader": g["leader"], "members": g["members"].keys()}
	return out
