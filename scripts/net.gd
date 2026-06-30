extends Node
## Net — autoload. Multiplayer transport + authoritative action routing.
## Port of backend/server.py: the server peer owns a GameState, clients send
## action dicts via request_action.rpc_id(1, ...), the server mutates state and
## broadcasts the full snapshot via apply_state.rpc(...). Mirrors the original's
## broadcast() / get_state_dict() model exactly.

signal state_updated(state: Dictionary)   # any client got a fresh snapshot
signal log_message(msg: Dictionary)        # {author, text, color}
signal dice_rolled(dice: Dictionary)
signal vfx(effect: Dictionary)             # combat effect to play (slash, fireball, ...)
signal entered_game                        # local peer is in and has first state
signal connection_failed
signal server_disconnected

const PORT := 8765
const MAX_PLAYERS := 10
const GameStateScript = preload("res://scripts/game_state.gd")

var gs = null                     # server-only authoritative state (GameState)
var last_state := {}              # latest snapshot (all peers)
var local_id := 0
var _pending_join := {}           # client: name/class to send on connect
var _cycle_running := false
var _entered := false


# ============================================================
#  Connection setup
# ============================================================
func host_game(pname: String, class_key: String) -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		push_error("Failed to host: %s" % err)
		return false
	multiplayer.multiplayer_peer = peer
	local_id = multiplayer.get_unique_id()   # 1 for the server
	_entered = false

	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	gs = GameStateScript.new()
	gs.phase = "LOBBY"
	# The host is also a player, waiting in the lobby like anyone else.
	gs.add_player(local_id, pname, class_key)
	_enter_once()
	_broadcast_state()
	return true


## Dedicated headless server: hosts the game WITHOUT the server being a player
## (for Docker / browser play). Clients join purely as remote peers into the
## lobby; whoever's there can start the run via the "start_game" action, alone
## or with the group — the exact same authoritative path as a listen-server,
## minus a host player on peer 1.
func start_dedicated_server() -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		push_error("Failed to start dedicated server: %s" % err)
		return false
	multiplayer.multiplayer_peer = peer
	local_id = multiplayer.get_unique_id()   # 1
	_entered = false
	multiplayer.peer_connected.connect(func(pid): print("[server] peer %d connected" % pid))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	gs = GameStateScript.new()
	gs.phase = "LOBBY"
	print("godot-rpg dedicated server listening on ws port %d" % PORT)
	return true


func join_game(ip: String, pname: String, class_key: String) -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	var url := ip.strip_edges()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		if url.contains(":"):
			url = "ws://" + url
		else:
			var is_domain = false
			for c in url:
				if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'):
					is_domain = true
					break
			if is_domain:
				url = "ws://" + url
			else:
				url = "ws://" + url + ":" + str(PORT)
	
	var err := peer.create_client(url)
	if err != OK:
		push_error("Failed to join: %s" % err)
		return false
	multiplayer.multiplayer_peer = peer
	_entered = false
	_pending_join = {"type": "join", "name": pname, "class": class_key}
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func(): server_disconnected.emit())
	return true


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	gs = null
	last_state = {}
	_entered = false


func _on_connected_to_server() -> void:
	local_id = multiplayer.get_unique_id()
	request_action.rpc_id(1, _pending_join)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server() or gs == null:
		return
	var was_turn: bool = gs.ids_equal(gs.current_turn_id, peer_id)
	gs.remove_player(peer_id)
	_broadcast_state()
	if was_turn and gs.phase == "PLAYERS":
		gs.advance_turn()
		_flush_round_events()
		_run_initiative_cycle()


# ============================================================
#  Action plumbing
# ============================================================
## Called by the local UI. Routes directly on the server, RPCs otherwise.
func send_action(action: Dictionary) -> void:
	if multiplayer.is_server():
		_handle_action(1, action)
	else:
		request_action.rpc_id(1, action)


@rpc("any_peer", "reliable")
func request_action(action: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_handle_action(multiplayer.get_remote_sender_id(), action)


func _handle_action(sender_id: int, action: Dictionary) -> void:
	if gs == null:
		return
	match action.get("type", ""):
		"join": _do_join(sender_id, action)
		"start_game": _do_start_game(sender_id)
		"move": _do_move(sender_id, action)
		"attack": _do_attack(sender_id)
		"ability": _do_ability(sender_id)
		"heal": _do_potion(sender_id, true)
		"mana": _do_potion(sender_id, false)
		"end_turn": _do_end_turn(sender_id)
		"roll_initiative": _do_roll_init(sender_id)
		"ready": _do_ready(sender_id)
		"equip": _do_simple(gs.player_equip(sender_id, str(action.get("item_id", ""))), sender_id)
		"use": _do_simple(gs.inventory_use(sender_id, str(action.get("item_id", ""))), sender_id)
		"loot": _do_loot_chest(sender_id, str(action.get("item_id", "")))
		"buy": _do_simple(gs.buy_item(sender_id, str(action.get("npc_id", "")), str(action.get("shop_item_id", ""))), sender_id)
		"bash": _do_simple(gs.player_bash(sender_id), sender_id)
		"pick": _do_simple(gs.player_pick(sender_id), sender_id)
		"pray": _do_simple(gs.player_pray(sender_id), sender_id)
		"hide": _do_simple(gs.player_hide(sender_id), sender_id)
		"examine": _do_simple(gs.player_examine(sender_id), sender_id)
		"qa_nuke": _do_simple(gs.qa_nuke(), sender_id)
		"pick_boon": _do_simple(gs.choose_boon(sender_id, str(action.get("boon", ""))), sender_id)
		"guild_create": _do_simple(gs.create_guild(sender_id, str(action.get("name", ""))), sender_id)
		"guild_invite": _do_simple(gs.invite_to_guild(sender_id, int(action.get("target_id", 0))), sender_id)
		"guild_leave": _do_simple(gs.leave_guild(sender_id), sender_id)
		"chat": _do_chat(sender_id, action)


# ============================================================
#  Server-side action handlers (mirror server.py dispatch)
# ============================================================
func _do_join(sender_id: int, action: Dictionary) -> void:
	var pname: String = str(action.get("name", "Adventurer")).strip_edges().substr(0, 15)
	if pname == "":
		pname = "Adventurer"
	gs.add_player(sender_id, pname, str(action.get("class", "warrior")))
	# Joining mid-fight: pull them into the running combat round so they roll
	# initiative and slot into the order, instead of standing around unable to act.
	if gs.phase == "INITIATIVE" or gs.phase == "PLAYERS":
		gs.mark_late_join_pending(sender_id)
		_broadcast_log(gs.add_chat_message("System", "%s joins the fray! Roll for initiative!" % pname, "#fb923c"))
	else:
		_broadcast_log(gs.add_chat_message("System", "%s joined." % pname, "#aaaaaa"))
	_broadcast_state()


## Anyone in the lobby can start the run — solo, or with whoever else has joined.
func _do_start_game(sender_id: int) -> void:
	if gs.phase != "LOBBY":
		_private_log(sender_id, "The adventure has already begun.")
		return
	gs.phase = "EXPLORATION"
	_ensure_initial_wave()
	_broadcast_log(gs.add_chat_message("Storyteller", "The adventure begins!", "#c084fc"))
	_broadcast_state()


func _do_move(sender_id: int, action: Dictionary) -> void:
	var res = gs.move_player(sender_id, int(action.get("dx", 0)), int(action.get("dy", 0)))
	if res["success"]:
		_broadcast_events(res.get("events", []))   # lava/pitfall/edge/trap logs + particles
		# Stepping on a portal warps the party (alt-dimension) or escapes HellPlane.
		if res.get("portal", false):
			var text: String = gs.return_from_hellplane() if gs.in_hellplane else gs.enter_portal()
			if text != "":
				_broadcast_log(gs.add_chat_message("Storyteller", text, "#ffcc00"))
			_broadcast_state()
			return
		if res["msg"] != "":
			_broadcast_log(gs.add_chat_message("System", res["msg"], "#ffffaa"))
		# Stepping into a monster opens the INITIATIVE phase — every player must
		# click Roll Init before turns begin (monsters already rolled server-side).
		if gs.phase == "INITIATIVE":
			_broadcast_log(gs.add_chat_message("System", "---- COMBAT! Roll for initiative! ----", "#ff4444"))
		_broadcast_state()
	elif res["msg"] != "":
		_private_log(sender_id, res["msg"])


## Broadcast a list of {text, color, vfx?} environment events (logs + particles).
func _broadcast_events(evs: Array) -> void:
	for ev in evs:
		_broadcast_log(gs.add_chat_message("Environment", ev["text"], ev.get("color", "#ffffff")))
		if ev.has("vfx"):
			push_vfx.rpc(ev["vfx"])


## Open a chest, then a 10% chance the chest pulls the party into HellPlane.
func _do_loot_chest(sender_id: int, item_id: String) -> void:
	var res = gs.loot_chest(sender_id, item_id)
	if not res.get("success", false):
		if res.has("message"):
			_private_log(sender_id, res["message"])
		return
	_broadcast_log(gs.add_chat_message("System", res["message"], res.get("color", "#ffffff")))
	_broadcast_state()
	if not gs.in_hellplane and randf() < 0.10:
		var text: String = gs.enter_hellplane()
		if text != "":
			_broadcast_log(gs.add_chat_message("Storyteller", text, "#ff4444"))
			_broadcast_state()


func _do_attack(sender_id: int) -> void:
	var res = gs.player_attack(sender_id)
	if res.get("success", false):
		_broadcast_log(gs.add_chat_message("Combat", res["message"], res["color"]))
		if res.has("dice"):
			push_dice.rpc(res["dice"])
		if res.get("effect") != null:
			push_vfx.rpc(res["effect"])
		_broadcast_state()
		_check_wave_cleared()
	elif res.has("message"):
		_private_log(sender_id, res["message"])


func _do_ability(sender_id: int) -> void:
	var res = gs.player_ability(sender_id)
	if res.get("success", false):
		_broadcast_log(gs.add_chat_message("Combat", res["message"], res["color"]))
		if res.get("effect") != null:
			push_vfx.rpc(res["effect"])
		_broadcast_state()
		_check_wave_cleared()
	elif res.has("message"):
		_private_log(sender_id, res["message"])


func _do_potion(sender_id: int, is_health: bool) -> void:
	var res = gs.player_heal(sender_id) if is_health else gs.player_mana(sender_id)
	if res.get("success", false):
		_broadcast_log(gs.add_chat_message("Combat", res["message"], res["color"]))
		_broadcast_state()
	elif res.has("message"):
		_private_log(sender_id, res["message"])


func _do_end_turn(sender_id: int) -> void:
	if gs.end_turn(sender_id):
		_broadcast_log(gs.add_chat_message("System", "%s ended their turn." % gs.players[sender_id]["name"], "#aaaaaa"))
		_broadcast_state()
		if gs.ids_equal(sender_id, gs.current_turn_id):
			gs.advance_turn()
			_flush_round_events()
			_run_initiative_cycle()


func _do_roll_init(sender_id: int) -> void:
	var res = gs.roll_initiative(sender_id)
	if res.get("success", false):
		_broadcast_log(gs.add_chat_message("System", res["message"], "#fcd34d"))
		if res.has("dice"):
			push_dice.rpc(res["dice"])   # animated d20 on every client
		if res.get("all_rolled", false):
			_broadcast_log(gs.add_chat_message("System", "---- COMBAT BEGINS! ----", "#ff4444"))
			_broadcast_state()
			_run_initiative_cycle()
		else:
			_broadcast_state()
	elif res.has("message"):
		_private_log(sender_id, res["message"])


func _do_ready(sender_id: int) -> void:
	# /ready advances to the next region once the area is cleared and every
	# player has confirmed (server.py:435).
	if gs.phase != "EXPLORATION":
		_private_log(sender_id, "You can only advance during exploration.")
		return
	if not gs.monsters.is_empty():
		_private_log(sender_id, "Clear the area before advancing.")
		return
	gs.ready_players[sender_id] = true
	var pname: String = gs.players.get(sender_id, {}).get("name", "Someone")
	if gs.ready_players.size() >= gs.players.size() and gs.players.size() > 0:
		var text: String = gs.advance_region()
		_broadcast_log(gs.add_chat_message("Storyteller", text, "#ffcc00"))
		_broadcast_state()
	else:
		_broadcast_log(gs.add_chat_message("System",
			"%s is ready for the next region (%d/%d)." % [pname, gs.ready_players.size(), gs.players.size()], "#aaaaaa"))
		_broadcast_state()


## Generic handler for actions that return {success, message?, color?}.
func _do_simple(res: Dictionary, sender_id: int) -> void:
	if res.get("success", false):
		if res.has("message"):
			_broadcast_log(gs.add_chat_message("System", res["message"], res.get("color", "#ffffff")))
		_broadcast_state()
	elif res.has("message"):
		_private_log(sender_id, res["message"])


func _do_chat(sender_id: int, action: Dictionary) -> void:
	var text: String = str(action.get("text", "")).strip_edges().substr(0, 100)
	if text == "":
		return
	var p: Dictionary = gs.players.get(sender_id, {})
	var color: String = p.get("color", "#ffffff")
	var author: String = p.get("name", "Unknown")
	_broadcast_log(gs.add_chat_message(author, text, color))


# ============================================================
#  Initiative cycle driver (server.py:42 run_initiative_cycle)
# ============================================================
func _run_initiative_cycle() -> void:
	if not multiplayer.is_server() or _cycle_running:
		return
	_cycle_running = true
	while gs.phase == "PLAYERS":
		var cid = gs.current_turn_id
		if cid == null:
			# Queue drained (everyone dead/gone) — leave combat.
			gs.phase = "EXPLORATION"
			break
		if gs.players.has(cid):
			_broadcast_state()   # hand control to the player; wait for their action
			break
		if gs.monsters.has(cid):
			var m: Dictionary = gs.monsters[cid]
			_broadcast_log(gs.add_chat_message("System", "---- %s's Turn ----" % m["name"], "#ffaaaa"))
			_broadcast_state()
			await _wait(0.5)
			for entry in gs.execute_monster_turn(cid):
				_broadcast_log(gs.add_chat_message("Combat", entry["text"], entry["color"]))
				if entry.has("dice"):
					push_dice.rpc(entry["dice"])
				if entry.has("effect"):
					push_vfx.rpc(entry["effect"])
				_broadcast_state()
				await _wait(0.3)
			gs.advance_turn()
			_flush_round_events()
			if gs.monsters.is_empty():
				gs.phase = "EXPLORATION"
				gs.first_combat_cleared = true
				_broadcast_log(gs.add_chat_message("Storyteller", "The monsters fall silent... The path ahead is clear.", "#c084fc"))
				_broadcast_state()
			continue
		# Entity gone (died mid-round) — skip.
		gs.advance_turn()
		_flush_round_events()
		if gs.initiative_queue.is_empty():
			break
	_cycle_running = false
	_broadcast_state()


## Broadcast any per-round biome-hazard events queued by advance_turn.
func _flush_round_events() -> void:
	if gs == null or gs.last_round_events.is_empty():
		return
	for ev in gs.last_round_events:
		_broadcast_log(gs.add_chat_message("Environment", ev["text"], ev["color"]))
		if ev.has("vfx"):
			push_vfx.rpc(ev["vfx"])
	gs.last_round_events = []
	_broadcast_state()


func _check_wave_cleared() -> void:
	if gs.monsters.is_empty() and gs.phase == "PLAYERS":
		gs.phase = "EXPLORATION"
		gs.first_combat_cleared = true
		_broadcast_log(gs.add_chat_message("Storyteller", "All enemies are defeated! The path forward is open.", "#c084fc"))
		_broadcast_state()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ensure_initial_wave() -> void:
	if gs.monsters.is_empty() and not gs.first_combat_cleared and gs.items.is_empty():
		gs.spawn_monster_wave(3)
		gs.spawn_chests(randi_range(1, 3))
		gs._spawn_merchant()
		gs._spawn_torches()
		gs._spawn_traps(randi_range(2, 4))


# ============================================================
#  Broadcast helpers
# ============================================================
func _broadcast_state() -> void:
	apply_state.rpc(gs.get_state_dict())


func _broadcast_log(msg: Dictionary) -> void:
	push_log.rpc(msg)


func _private_log(peer_id: int, text: String) -> void:
	push_log.rpc_id(peer_id, {"author": "System", "text": text, "color": "#ef4444"})


@rpc("authority", "call_local", "reliable")
func apply_state(state: Dictionary) -> void:
	last_state = state
	state_updated.emit(state)
	_enter_once()


@rpc("authority", "call_local", "reliable")
func push_log(msg: Dictionary) -> void:
	log_message.emit(msg)


@rpc("authority", "call_local", "reliable")
func push_dice(dice: Dictionary) -> void:
	dice_rolled.emit(dice)


@rpc("authority", "call_local", "reliable")
func push_vfx(effect: Dictionary) -> void:
	vfx.emit(effect)


func _enter_once() -> void:
	if not _entered:
		_entered = true
		entered_game.emit()


# ============================================================
#  Convenience accessors for the UI
# ============================================================
func local_player() -> Dictionary:
	return last_state.get("players", {}).get(local_id, {})


func is_my_turn() -> bool:
	var ct = last_state.get("current_turn_id", null)
	return last_state.get("phase", "") == "PLAYERS" and typeof(ct) == TYPE_INT and ct == local_id


func is_exploration() -> bool:
	return last_state.get("phase", "") == "EXPLORATION"
