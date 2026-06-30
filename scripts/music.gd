extends Node
## Music — Autoload for looping background music with crossfades between game
## states (menu / explore / combat / boss / victory).
##
## SWAPPING TRACKS IS MEANT TO BE TRIVIAL: drop an audio file into
## `res://assets/music/` named after the state — `explore.ogg`, `combat.ogg`,
## `boss.ogg`, `menu.ogg`, `victory.ogg` — and it plays automatically. No code
## changes. `.ogg` is preferred, but `.mp3` and `.wav` also work (first match
## wins, see EXTS). If a state's file is missing, that state is simply silent —
## the game runs fine with zero music files present.
##
## To rename or re-map a track, edit the TRACKS dict below (state -> base
## filename). To add a brand-new state, add an entry here and call
## `Music.play_state("your_state")`.

const MUSIC_DIR := "res://assets/music/"
const EXTS := [".ogg", ".mp3", ".wav"]   # resolution order; first existing file wins
const FADE_TIME := 1.2                    # crossfade duration (seconds)

## state -> base filename (no extension). Edit freely to re-map tracks.
const TRACKS := {
	"menu": "menu",
	"explore": "explore",
	"combat": "combat",
	"boss": "boss",
	"victory": "victory",
}

@export var volume_db := -6.0   # target loudness for the active track
var _muted := false

var _players: Array[AudioStreamPlayer] = []
var _active := 0                 # index into _players of the currently-audible one
var _state := ""                 # current music state ("" = nothing requested yet)
var _cache := {}                 # resolved path -> loaded AudioStream


func _ready() -> void:
	# Route to a dedicated "Music" audio bus if the project defines one, else Master.
	var bus := "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"
	for _i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


## Switch background music to `state` (see TRACKS). No-op if already on it.
## Unknown/file-less states fade the current track out into silence.
func play_state(state: String) -> void:
	if state == _state:
		return
	_state = state
	var path := resolve_track_path(state)
	if path == "":
		_fade_to_silence()
		return
	var stream := _load_stream(path)
	if stream == null:
		_fade_to_silence()
		return
	_crossfade_to(stream)


## Resolve a state to an existing audio file path, or "" if none is present.
## Pure (no scene-tree access) so it is unit-testable.
func resolve_track_path(state: String) -> String:
	var base: String = TRACKS.get(state, "")
	if base == "":
		return ""
	for ext in EXTS:
		var path: String = MUSIC_DIR + base + ext
		if ResourceLoader.exists(path):
			return path
	return ""


func set_muted(muted: bool) -> void:
	_muted = muted
	var target := -80.0 if muted else volume_db
	if not _players.is_empty():
		_tween_volume(_players[_active], target)


func stop() -> void:
	_state = ""
	_fade_to_silence()


# ============================================================
#  Internals
# ============================================================
func _load_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream := load(path) as AudioStream
	if stream != null:
		_set_looping(stream)
		_cache[path] = stream
	return stream


## Make a stream loop, regardless of imported type.
func _set_looping(stream: AudioStream) -> void:
	if "loop" in stream:
		stream.loop = true                       # Ogg / MP3
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD


func _crossfade_to(stream: AudioStream) -> void:
	if _players.is_empty():
		return
	var old := _players[_active]
	var next_idx := 1 - _active
	var nxt := _players[next_idx]
	nxt.stream = stream
	nxt.volume_db = -80.0
	nxt.play()
	_tween_volume(nxt, -80.0 if _muted else volume_db)
	_tween_volume(old, -80.0, true)
	_active = next_idx


func _fade_to_silence() -> void:
	if _players.is_empty():
		return
	_tween_volume(_players[_active], -80.0, true)


func _tween_volume(player: AudioStreamPlayer, target_db: float, stop_after := false) -> void:
	var tw := create_tween()
	tw.tween_property(player, "volume_db", target_db, FADE_TIME)
	if stop_after:
		tw.tween_callback(player.stop)
