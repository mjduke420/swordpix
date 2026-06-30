extends Node
## Headless verification of the ported GameState logic (plan verification step).
## Run with the Godot MCP: scene = res://scenes/test.tscn. Prints PASS/FAIL.

const GS = preload("res://scripts/game_state.gd")
const MUSIC = preload("res://scripts/music.gd")
const SETTINGS = preload("res://scripts/settings.gd")

var _pass := 0
var _fail := 0


func _ready() -> void:
	var gs = GS.new()
	_check("map is 15x15", gs.map.size() == 15 and gs.map[0].size() == 15)

	gs.add_player(1, "Alice", "warrior")
	gs.add_player(2, "Bob", "mage")
	_check("two players added", gs.players.size() == 2)
	_check("warrior max_health >= 150", gs.players[1]["max_health"] >= 150)
	_check("warrior STR is 15 (standard array)", gs.players[1]["stats"]["STR"] == 15)
	_check("mage damage dice is 4d4", gs.players[2]["damage_dice"] == "4d4")

	gs.spawn_monster_wave(3)
	_check("spawned monsters", gs.monsters.size() >= 1 and gs.monsters.size() <= 3)

	# Place Alice adjacent to a monster, trigger proximity combat.
	var mid: String = gs.monsters.keys()[0]
	var m: Dictionary = gs.monsters[mid]
	gs.players[1]["x"] = m["x"]
	gs.players[1]["y"] = m["y"] + 1
	var engaged: bool = gs.check_combat_engagement(1)
	_check("proximity opens initiative phase", engaged and gs.phase == "INITIATIVE")
	_check("monsters auto-roll initiative", gs.initiative_queue.size() == gs.monsters.size())
	_check("players await manual init roll", gs._init_pending.size() == gs.players.size())

	# Players must each manually roll; combat begins only once everyone has.
	var r1: Dictionary = gs.roll_initiative(1)
	_check("player 1 rolls initiative", r1.get("success", false) and not r1.get("all_rolled", false))
	_check("init roll carries animated dice", r1.get("dice", {}).get("kind", "") == "initiative")
	var r2: Dictionary = gs.roll_initiative(2)
	_check("final roll finalizes initiative", r2.get("all_rolled", false))
	_check("initiative queue has all combatants", gs.initiative_queue.size() == 2 + gs.monsters.size())
	_check("combat begins after all roll", gs.phase == "PLAYERS")
	_check("current_turn_id assigned", gs.current_turn_id != null)
	_check("double-roll is rejected", not gs.roll_initiative(1).get("success", true))

	# Leveling.
	var before_level: int = gs.players[1]["level"]
	var before_hp: int = gs.players[1]["max_health"]
	gs.grant_xp(gs.players[1], 1000)
	_check("grant_xp levels up", gs.players[1]["level"] > before_level)
	_check("level up raises max_health", gs.players[1]["max_health"] > before_hp)

	# Attack: force Alice's turn with the monster in range.
	gs.current_turn_id = 1
	gs.players[1]["action_used"] = false
	gs.players[1]["x"] = m["x"]
	gs.players[1]["y"] = m["y"] + 1
	m["ac"] = 0  # make hits near-certain so the assertion isn't RNG-flaky
	var max_hp: int = m["max_hp"]
	var res: Dictionary = gs.player_attack(1)
	_check("attack resolves", res.get("success", false))
	_check("attack consumes action", gs.players[1]["action_used"])
	# Retry a few times to absorb the ~1/20 fumble chance.
	var damaged: bool = not gs.monsters.has(mid) or gs.monsters[mid]["hp"] < max_hp
	for _i in range(12):
		if damaged:
			break
		gs.current_turn_id = 1
		gs.players[1]["action_used"] = false
		gs.player_attack(1)
		damaged = not gs.monsters.has(mid) or gs.monsters[mid]["hp"] < max_hp
	_check("attack damaged/killed monster", damaged)

	# Ability (warrior Whirlwind costs 15 mana; warrior has 30).
	gs.current_turn_id = 1
	gs.players[1]["action_used"] = false
	gs.players[1]["mana"] = 30
	var abil: Dictionary = gs.player_ability(1)
	_check("ability resolves", abil.get("success", false))

	# State serialization round-trips the key fields.
	var snap: Dictionary = gs.get_state_dict()
	_check("snapshot has players/monsters/map", snap.has("players") and snap.has("monsters") and snap.has("map"))
	_check("snapshot has region/act/chapter", snap.has("region") and snap.has("act") and snap.has("chapter"))

	# --- World progression (phase 2) ---
	var w = GS.new()
	_check("starts in Dreadwood Forest", w.current_biome == "Dreadwood Forest")
	w.advance_region()
	_check("advance -> region 2", w.region_number == 2)
	w.advance_region()
	w.advance_region()
	_check("region 4 is Charred Wastes", w.region_number == 4 and w.current_biome == "Charred Wastes")

	# Boss regions (5/10/15) spawn exactly one boss.
	w.region_number = 5
	w.spawn_monster_wave()
	_check("region 5 spawns Goblin King boss",
		w.monsters.size() == 1 and w.monsters.values()[0]["is_boss"] and w.monsters.values()[0]["name"] == "Goblin King")
	w.region_number = 10
	w.spawn_monster_wave()
	_check("region 10 spawns Lich", w.monsters.values()[0]["name"] == "Lich of the Abyss")
	w.region_number = 15
	w.spawn_monster_wave()
	_check("region 15 spawns Void Herald", w.monsters.values()[0]["name"] == "Void Herald")

	# Act-appropriate biome at region 10 (act 2 -> Abyssal Depths).
	w.region_number = 10
	_check("act number at region 10 is 2", w.act_number() == 2)

	# NG+ loop: advancing past region 15 wraps to region 1, ng_plus++.
	w.region_number = 15
	w.advance_region()
	_check("region 15 -> NG+ wraps to region 1", w.region_number == 1)
	_check("NG+ increments", w.ng_plus == 1)

	# Chapter story reflects the region.
	w.region_number = 1
	_check("chapter story names region 1 beat", "Whispering Woods" in w.generate_chapter_story())

	# --- Mixed-type id comparison (regression: combat crashed on monster turn) ---
	_check("ids_equal int==int", w.ids_equal(1, 1))
	_check("ids_equal String==String", w.ids_equal("m1", "m1"))
	_check("ids_equal int vs String is false (no crash)", not w.ids_equal(1, "m1"))
	_check("ids_equal vs null is false", not w.ids_equal(1, null))
	# A player acting while it's a monster's turn must be rejected, not crash.
	var c = GS.new()
	c.add_player(1, "Cara", "warrior")
	c.spawn_monster_wave(3)
	c.phase = "PLAYERS"
	c.current_turn_id = c.monsters.keys()[0]  # a String monster id
	_check("attack on monster's turn rejected", not c.player_attack(1).get("success", false))
	_check("move on monster's turn rejected", not c.move_player(1, 1, 0).get("success", false))

	# --- Player sprite flipping ---
	var pf = GS.new()
	pf.add_player(1, "Flippy", "warrior")
	_check("player starts facing right (facing_left is false)", not pf.players[1].get("facing_left", true))
	var flip_x: int = pf.players[1]["x"]
	var flip_y: int = pf.players[1]["y"]
	pf.map[flip_y][flip_x - 1] = "."
	pf.map[flip_y][flip_x + 1] = "."
	pf.phase = "EXPLORATION"
	pf.move_player(1, -1, 0)
	_check("player faces left after moving left", pf.players[1].get("facing_left", false))
	pf.move_player(1, 1, 0)
	_check("player faces right after moving right", not pf.players[1].get("facing_left", true))

	# --- Line of sight ---
	var los = preload("res://scripts/los.gd").new()
	var fm: Array = []
	for yy in range(7):
		var row: Array = []
		for xx in range(7):
			row.append(".")
		fm.append(row)
	var vis: Dictionary = los.compute_visible(fm, 3, 3, 4)
	_check("own tile visible", vis.has(Vector2i(3, 3)))
	_check("open tile within radius visible", vis.has(Vector2i(3, 6)))
	_check("tile beyond radius not visible", not vis.has(Vector2i(3, 3 + 9)))
	# Wall at (3,1) blocks the tile behind it (3,0) but the wall itself is seen.
	fm[1][3] = "#"
	var vis2: Dictionary = los.compute_visible(fm, 3, 3, 4)
	_check("blocker tile itself visible", vis2.has(Vector2i(3, 1)))
	_check("tile behind blocker hidden", not vis2.has(Vector2i(3, 0)))

	# --- Loot / equipment / chests / merchant (phase 3) ---
	var L = GS.new()
	L.add_player(1, "Looter", "warrior")
	L.monsters.clear()
	L.phase = "EXPLORATION"
	var lp2: Dictionary = L.players[1]

	var gi: Dictionary = L._generate_loot_item(1, 1)
	_check("generated loot has a valid type", gi["type"] in ["weapon", "armor", "scroll", "potion", "gold"])

	# Equip armor raises AC; weapon/armor go through requirements check.
	var before_ac: int = lp2["ac"]
	lp2["inventory"].append({"id": "armor1", "name": "Test Plate", "type": "armor", "slot": "armor",
		"color": "#fff", "rarity": "Rare", "atk_bonus": 0, "def_bonus": 5, "requirements": {}})
	var er: Dictionary = L.player_equip(1, "armor1")
	_check("armor equips", er.get("success", false) and lp2["equipment"]["armor"] != null)
	_check("armor raises AC by def_bonus", lp2["ac"] == before_ac + 5)
	lp2["inventory"].append({"id": "armor2", "name": "Heavy Plate", "type": "armor", "slot": "armor",
		"color": "#fff", "rarity": "Epic", "atk_bonus": 0, "def_bonus": 9, "requirements": {"CON": 99}})
	_check("equip blocked by unmet requirement", not L.player_equip(1, "armor2").get("success", false))

	# Chest looting (must be adjacent).
	L.items.clear()
	var chest: Dictionary = L._new_item(lp2["x"] + 1, lp2["y"], "Chest", "chest")
	L.items[chest["id"]] = chest
	var lr: Dictionary = L.loot_chest(1, chest["id"])
	_check("adjacent chest loots", lr.get("success", false) and not L.items.has(chest["id"]))

	# Ground pickup via movement (gold increases, item consumed).
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var gx: int = lp2["x"] + d[0]
		var gy: int = lp2["y"] + d[1]
		if L.is_walkable(gx, gy) and not L.is_entity_at(gx, gy):
			var gold_item: Dictionary = L._new_item(gx, gy, "Gold Pouch", "gold")
			L.items[gold_item["id"]] = gold_item
			var gold_before: int = lp2["gold"]
			var mv: Dictionary = L.move_player(1, d[0], d[1])
			_check("walking onto gold picks it up", mv.get("success", false) and lp2["gold"] > gold_before and not L.items.has(gold_item["id"]))
			break

	# Merchant purchase.
	L.npcs.clear()
	L._spawn_merchant()
	var npc_id: String = L.npcs.keys()[0]
	var npc: Dictionary = L.npcs[npc_id]
	lp2["x"] = npc["x"]
	lp2["y"] = npc["y"]
	lp2["gold"] = 9999
	var br: Dictionary = L.buy_item(1, npc_id, "shop_hp")
	_check("merchant sale succeeds", br.get("success", false))
	_check("snapshot includes items + npcs", L.get_state_dict().has("items") and L.get_state_dict().has("npcs"))

	# --- Torch light sources ---
	L.torches = {}
	L._spawn_torches()
	_check("torches spawn (1-3)", L.torches.size() >= 1 and L.torches.size() <= 3)
	var torch: Dictionary = L.torches.values()[0]
	_check("torch on a walkable tile", L.is_walkable(torch["x"], torch["y"]))
	_check("torch carries a lit radius", torch.get("radius", 0) >= 1)
	_check("snapshot includes torches", L.get_state_dict().has("torches"))

	# Fire-particle API sanity (these setters throw at runtime if a name is wrong).
	var fx := CPUParticles2D.new()
	fx.amount = 16
	fx.lifetime = 0.6
	fx.preprocess = 0.6
	fx.direction = Vector2(0, -1)
	fx.spread = 22.0
	fx.gravity = Vector2(0, -14)
	fx.initial_velocity_min = 16.0
	fx.initial_velocity_max = 38.0
	fx.scale_amount_min = 2.0
	fx.scale_amount_max = 4.0
	fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = 3.5
	var gr := Gradient.new()
	gr.add_point(0.45, Color(1, 0.5, 0, 1))
	fx.color_ramp = gr
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_check("fire particle API valid", fx.amount == 16 and fx.color_ramp != null and cm.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD)
	fx.free()

	# --- Portals & HellPlane ---
	var P = GS.new()
	P.add_player(1, "Wanderer", "warrior")
	_check("biome pool has 12 biomes", P.BIOME_POOL.size() == 12)
	# enter_portal warps to an alt-dimension biome and rebuilds the world.
	var ptext: String = P.enter_portal()
	_check("portal text mentions a biome", ptext.length() > 0)
	_check("entered an alt-dimension biome", P.current_biome in P.PORTAL_BIOMES)
	_check("portal world has monsters", P.monsters.size() >= 1)

	# Stepping on a portal item returns the portal flag from move_player.
	var P2 = GS.new()
	P2.add_player(1, "Stepper", "warrior")
	P2.monsters.clear()
	P2.phase = "EXPLORATION"
	var sp2: Dictionary = P2.players[1]
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var px: int = sp2["x"] + d[0]
		var py: int = sp2["y"] + d[1]
		if P2.is_walkable(px, py) and not P2.is_entity_at(px, py):
			var portal_item: Dictionary = P2._new_item(px, py, "Mystic Portal", "portal", "Rare", "#a855f7")
			P2.items[portal_item["id"]] = portal_item
			var mv: Dictionary = P2.move_player(1, d[0], d[1])
			_check("stepping on portal flags a transition", mv.get("portal", false))
			break

	# HellPlane: enter snapshots the world; return restores it.
	var H = GS.new()
	H.add_player(1, "Diver", "warrior")
	H.region_number = 4
	H.current_biome = "Charred Wastes"
	var prior_region: int = H.region_number
	var htext: String = H.enter_hellplane()
	_check("enter_hellplane text returned", htext.length() > 0)
	_check("now in HellPlane biome", H.current_biome == "HellPlane" and H.in_hellplane)
	_check("HellPlane has a return portal", _has_portal(H))
	var rtext: String = H.return_from_hellplane()
	_check("return text returned", rtext.length() > 0)
	_check("return restores prior biome/region", H.current_biome == "Charred Wastes" and H.region_number == prior_region and not H.in_hellplane)
	_check("snapshot exposes in_hellplane", H.get_state_dict().has("in_hellplane"))

	# --- Guilds ---
	var G = GS.new()
	G.add_player(1, "Lead", "warrior")
	G.add_player(2, "Buddy", "mage")
	_check("create guild succeeds", G.create_guild(1, "Knights").get("success", false))
	_check("creator is in guild", G.player_guilds.get(1) == "Knights" and G.guild_member_count(1) == 1)
	_check("duplicate guild name rejected", not G.create_guild(2, "Knights").get("success", false))
	_check("invite adds member", G.invite_to_guild(1, 2).get("success", false) and G.guild_member_count(1) == 2)
	_check("non-leader cannot invite", not G.invite_to_guild(2, 1).get("success", false))
	_check("damage multiplier scales with members", abs(G._guild_damage_multiplier(1) - 1.05) < 0.001)
	# Shared XP: granting to one guildmate also grants to the other.
	var buddy_xp_before: int = G.players[2]["xp"]
	G.grant_xp(G.players[1], 10)
	_check("guild shares XP", G.players[2]["xp"] > buddy_xp_before)
	_check("state exposes guilds + player_guilds", G.get_state_dict().has("guilds") and G.get_state_dict().has("player_guilds"))
	# Leader leaving promotes the remaining member.
	G.leave_guild(1)
	_check("leader leaving promotes a member", G.guilds["Knights"]["leader"] == 2)
	G.leave_guild(2)
	_check("empty guild is removed", not G.guilds.has("Knights"))

	# --- Interactive map layer (traps / hatches / altars) ---
	var I = GS.new()
	I.add_player(1, "Probe", "warrior")
	I.monsters.clear()
	I.phase = "EXPLORATION"
	var ip: Dictionary = I.players[1]
	I.map[1][1] = "D"
	_check("doors block movement (is_walkable)", not I.is_walkable(1, 1))
	I.map[1][1] = "A"
	_check("altars block movement (is_walkable)", not I.is_walkable(1, 1))
	I.map[1][1] = "."
	_check("floor is walkable", I.is_walkable(1, 1))
	# Bash an adjacent hatch (force the STR check to always pass).
	ip["modifiers"]["STR"] = 20
	I.map[ip["y"]][ip["x"] + 1] = "D"
	var br2: Dictionary = I.player_bash(1)
	_check("bash opens adjacent hatch", br2.get("success", false) and I.map[ip["y"]][ip["x"] + 1] == ".")
	# Pray at an adjacent altar (consumes it).
	I.map[ip["y"]][ip["x"] - 1] = "A"
	var pr: Dictionary = I.player_pray(1)
	_check("pray spends adjacent altar", pr.get("success", false) and I.map[ip["y"]][ip["x"] - 1] == ".")
	_check("pray with no altar fails", not I.player_pray(1).get("success", false))
	# Traps: spawn, hidden by default, revealed after spotting.
	I.traps = {}
	I._spawn_traps(3)
	_check("traps spawn", I.traps.size() >= 1)
	_check("hidden traps not in snapshot", I.get_state_dict()["traps"].is_empty())
	I.traps.values()[0]["is_revealed"] = true
	_check("revealed traps appear in snapshot", I.get_state_dict()["traps"].size() == 1)
	# Stepping on a trap consumes it and reports an event.
	I.traps = {}
	I.monsters = {}   # a bashed hatch may have spawned an ambush — clear it
	for d2 in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var tx: int = ip["x"] + d2[0]
		var ty: int = ip["y"] + d2[1]
		if I.is_walkable(tx, ty) and not I.is_entity_at(tx, ty):
			I.map[ty][tx] = "."
			I.traps["trX"] = {"id": "trX", "x": tx, "y": ty, "dc": 13, "damage": "2d6", "type": "Spike", "is_revealed": true}
			var mv2: Dictionary = I.move_player(1, d2[0], d2[1])
			_check("stepping on a trap springs and consumes it", not I.traps.has("trX") and mv2.get("events", []).size() >= 1)
			break

	# --- Biome round hazards ---
	var hz = GS.new()
	hz.add_player(1, "Hazel", "warrior")
	hz.current_biome = "The Fey-Wilds"
	hz.round_number = 1
	_check("wild magic dormant on off-rounds", hz._apply_biome_round_effects().is_empty())
	hz.players[1]["health"] = 10
	hz.round_number = 2
	var wild_evs = hz._apply_biome_round_effects()
	_check("Fey-Wilds surges every 2nd round", wild_evs.size() == 1)
	_check("wild magic alters party HP", hz.players[1]["health"] != 10)
	hz.current_biome = "The Clockwork Spire"
	hz.players[1]["x"] = 3
	hz.players[1]["y"] = 3
	hz.round_number = 3
	var rot_evs = hz._apply_biome_round_effects()
	_check("Clockwork rotation fires", rot_evs.size() == 1)
	_check("rotation carries player to (11,3)", hz.players[1]["x"] == 11 and hz.players[1]["y"] == 3)
	# --- Hide & Examine actions ---
	var ha = GS.new()
	ha.add_player(1, "Sneak", "rogue")
	ha.add_player(2, "Tank", "warrior")
	_check("rogue can hide", ha.player_hide(1).get("success", false) and ha.players[1]["is_hidden"])
	_check("non-rogue cannot hide", not ha.player_hide(2).get("success", true))
	ha.spawn_monster_wave(1)
	var mid2: String = ha.monsters.keys()[0]
	ha.monsters[mid2]["x"] = ha.players[1]["x"]
	ha.monsters[mid2]["y"] = ha.players[1]["y"] + 1
	var exr = ha.player_examine(1)
	_check("examine reports a nearby monster", exr.get("success", false) and "HP" in exr.get("message", ""))
	ha.monsters[mid2]["x"] = ha.players[1]["x"] + 12
	_check("examine fails with nothing in range", not ha.player_examine(1).get("success", true))
	# --- QA nuke ---
	var qn = GS.new()
	qn.add_player(1, "Dev", "warrior")
	qn.spawn_monster_wave(3)
	qn.phase = "PLAYERS"
	var nuked = qn.qa_nuke()
	_check("qa_nuke clears all monsters", nuked.get("success", false) and qn.monsters.is_empty())
	_check("qa_nuke returns to exploration", qn.phase == "EXPLORATION")
	# --- Level-up boons ---
	var bp = GS.new()
	bp.add_player(1, "Hero", "warrior")
	bp.grant_xp(bp.players[1], 100000)
	_check("level up grants a boon pick", bp.players[1]["boon_picks"] >= 1)
	var hp_before: int = bp.players[1]["max_health"]
	var boon_res = bp.choose_boon(1, "vitality")
	_check("choose_boon succeeds", boon_res.get("success", false))
	_check("vitality raises max HP", bp.players[1]["max_health"] > hp_before)
	_check("boon pick consumed", bp.players[1]["boon_picks"] == 0)
	# --- Boss mechanics ---
	var bo = GS.new()
	for ty in range(6, 11):
		for tx in range(5, 10):
			bo.map[ty][tx] = "."
	bo.add_player(1, "Slayer", "warrior")
	bo.players[1]["x"] = 0
	bo.players[1]["y"] = 0
	var boss := bo._new_monster(7, 8, "Goblin King", "boss", "#b91c1c", 300, 14)
	boss["attack_damage"] = 45
	boss["is_boss"] = true
	boss["hp"] = 100
	bo.monsters[boss["id"]] = boss
	var blogs: Array = []
	bo._boss_turn(boss, bo.players[1], blogs)
	_check("boss enrages at half HP", boss.get("enraged", false))
	_check("boss summons adds at half HP", bo.monsters.size() >= 2)

	# --- Boss add-waves: themed, escalating, capped ---
	var bw = GS.new()
	for ty2 in range(0, 15):
		for tx2 in range(0, 15):
			bw.map[ty2][tx2] = "."
	bw.region_number = 10   # -> Lich of the Abyss
	bw.add_player(1, "Slayer", "warrior")
	bw.players[1]["x"] = 0
	bw.players[1]["y"] = 0
	bw._spawn_boss(1.0)
	var lich: Dictionary = bw.monsters.values()[0]
	_check("boss carries a themed add pool", lich.get("add_theme", {}).get("name", "") == "Risen Skeleton")

	# Above every threshold: no summon yet.
	lich["hp"] = int(lich["max_hp"] * 0.8)
	_check("no summon above 75% HP", not bw._boss_summon_check(lich, []))

	# Cross 75%: themed pack of 2.
	lich["hp"] = int(lich["max_hp"] * 0.7)
	_check("summons on crossing 75% HP", bw._boss_summon_check(lich, []))
	var adds1 := 0
	var themed := true
	for mm in bw.monsters.values():
		if mm.get("is_add", false):
			adds1 += 1
			if mm["name"] != "Risen Skeleton" or mm.get("archetype", "") != "archer":
				themed = false
	_check("75% wave spawns 2 adds", adds1 == 2)
	_check("adds are themed to the boss", themed)
	_check("a threshold fires only once", not bw._boss_summon_check(lich, []))

	# Cross 50%: enrage + a bigger wave.
	lich["hp"] = int(lich["max_hp"] * 0.4)
	var crossed_50: bool = bw._boss_summon_check(lich, [])
	_check("enrages on crossing 50% HP", crossed_50 and lich.get("enraged", false))

	# Cross 25%: more adds, but never above the live-add cap.
	lich["hp"] = int(lich["max_hp"] * 0.1)
	bw._boss_summon_check(lich, [])
	var total_adds := 0
	for mm2 in bw.monsters.values():
		if mm2.get("is_add", false):
			total_adds += 1
	_check("live adds capped at MAX_BOSS_ADDS", total_adds <= bw.MAX_BOSS_ADDS)

	# --- Monster archetypes ---
	var ma = GS.new()
	ma.region_number = 1
	ma.spawn_monster_wave(8)
	var has_arch := true
	for mid_a in ma.monsters:
		if not ma.monsters[mid_a].has("archetype"):
			has_arch = false
	_check("spawned monsters all have an archetype", has_arch)
	var hm = GS.new()
	var healer := hm._new_monster(5, 5, "Acolyte", "slime", "#34d399", 60, 12)
	healer["archetype"] = "healer"
	healer["attack_range"] = 3.5
	hm.monsters[healer["id"]] = healer
	var wounded := hm._new_monster(6, 5, "Orc", "orc", "#ef4444", 100, 12)
	wounded["hp"] = 20
	hm.monsters[wounded["id"]] = wounded
	var hlogs: Array = []
	var did_heal := hm._monster_heal_ally(healer, hlogs)
	_check("healer mends a wounded ally", did_heal and hm.monsters[wounded["id"]]["hp"] > 20)
	# --- Elite affixes ---
	var ea = GS.new()
	var em := ea._new_monster(3, 3, "Orc", "orc", "#ef4444", 100, 12)
	em["attack_damage"] = 20
	ea._apply_elite_affix(em)
	_check("elite affix sets elite flag", em.get("elite", "") != "")
	_check("elite affix prefixes the name", em["name"] != "Orc")

	# --- Lobby phase: blocks movement/combat-trigger until the adventure starts ---
	var lb = GS.new()
	lb.add_player(1, "Lobbier", "warrior")
	lb.phase = "LOBBY"
	_check("LOBBY blocks movement", not lb.move_player(1, 1, 0).get("success", true))
	lb.spawn_monster_wave(1)
	lb.players[1]["x"] = lb.monsters.values()[0]["x"]
	lb.players[1]["y"] = lb.monsters.values()[0]["y"]
	_check("LOBBY blocks combat engagement", not lb.check_combat_engagement(1))

	# --- Late join: a player who connects mid-fight rolls into the running order ---
	var lj = GS.new()
	lj.add_player(1, "Alice", "warrior")
	lj.add_player(2, "Bob", "mage")
	lj.spawn_monster_wave(2)
	var lj_mid: String = lj.monsters.keys()[0]
	lj.players[1]["x"] = lj.monsters[lj_mid]["x"]
	lj.players[1]["y"] = lj.monsters[lj_mid]["y"] + 1
	lj.check_combat_engagement(1)
	lj.roll_initiative(1)
	lj.roll_initiative(2)
	_check("setup: combat running before late join", lj.phase == "PLAYERS")
	var before_turn = lj.current_turn_id
	var before_size: int = lj.initiative_queue.size()
	lj.add_player(3, "Charlie", "rogue")
	lj.mark_late_join_pending(3)
	_check("late joiner is marked awaiting a roll", lj._init_pending.has(3))
	var lj_res: Dictionary = lj.roll_initiative(3)
	_check("late joiner rolls into the fight", lj_res.get("success", false))
	_check("late join doesn't disturb the active turn", lj.ids_equal(lj.current_turn_id, before_turn))
	_check("late joiner is inserted into the order", lj.initiative_queue.size() == before_size + 1)
	_check("late joiner no longer awaits a roll", not lj._init_pending.has(3))
	_check("double-rolling a late joiner is rejected", not lj.roll_initiative(3).get("success", true))

	# --- Music track resolution (swappable drop-in folder) ---
	var mus = MUSIC.new()
	_check("music maps the core states", mus.TRACKS.has("menu") and mus.TRACKS.has("explore") and mus.TRACKS.has("combat") and mus.TRACKS.has("boss"))
	_check("unknown music state resolves to empty (silent)", mus.resolve_track_path("nope") == "")
	mus.free()

	# --- Audio settings: bus split + volume mapping ---
	_check("Music + SFX audio buses exist", AudioServer.get_bus_index("Music") != -1 and AudioServer.get_bus_index("SFX") != -1)
	var st = SETTINGS.new()
	_check("full volume maps to 0 dB", absf(st.db_for(1.0)) < 0.01)
	_check("zero volume maps to silence", st.db_for(0.0) <= -80.0)
	_check("half volume is attenuated but audible", st.db_for(0.5) < 0.0 and st.db_for(0.5) > -80.0)
	st.free()

	print("=== RESULTS: %d passed, %d failed ===" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _has_portal(gs) -> bool:
	for it in gs.items.values():
		if it["type"] == "portal":
			return true
	return false


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)
