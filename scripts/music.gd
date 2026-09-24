extends Node
## Global music player (autoload "Music").
## Plays every track dropped in res://music/ in shuffled, non-repeating order
## and loops forever. Add more tracks later just by copying .mp3/.ogg/.wav
## files into that folder -- no code changes needed.

const MUSIC_DIR := "res://music/"
const EXTENSIONS := ["mp3", "ogg", "wav"]

var muted := false
var volume_db := -7.0        # sits under the voices
var duck_db := -9.0          # extra drop while dialogue is being spoken

var _player: AudioStreamPlayer
var _playlist: Array[String] = []
var _order: Array[int] = []
var _pos := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.finished.connect(_play_next)
	_player.volume_db = volume_db
	add_child(_player)
	_scan()
	_reshuffle()
	_play_next()


func _process(delta: float) -> void:
	if _player == null:
		return
	var target := -80.0 if muted else volume_db + (duck_db if Voice.dialog_active() else 0.0)
	_player.volume_db = move_toward(_player.volume_db, target, delta * 30.0)


## Looks at res://music/ for playable audio files, alphabetically ordered
## before shuffling so the played order only depends on random seed, not
## filesystem enumeration order.
func _scan() -> void:
	_playlist.clear()
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		push_warning("Music: no %s folder found" % MUSIC_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		# exported builds only list the ".import" stubs of imported audio
		var real := fname.trim_suffix(".import")
		if not dir.current_is_dir() and EXTENSIONS.has(real.get_extension().to_lower()) and not _playlist.has(MUSIC_DIR + real):
			_playlist.append(MUSIC_DIR + real)
		fname = dir.get_next()
	dir.list_dir_end()
	_playlist.sort()


func _reshuffle() -> void:
	_order.clear()
	for i in _playlist.size():
		_order.append(i)
	_order.shuffle()
	_pos = -1


func _play_next() -> void:
	if _playlist.is_empty():
		return
	var attempts := 0
	while attempts < _order.size():
		_pos += 1
		if _pos >= _order.size():
			_reshuffle()
			_pos = 0
		var stream: AudioStream = load(_playlist[_order[_pos]])
		if stream:
			_player.stream = stream
			_player.play()
			return
		attempts += 1
	push_warning("Music: found files in %s but none loaded as audio" % MUSIC_DIR)


func skip() -> void:
	if not _playlist.is_empty():
		_player.stop()
		_play_next()


func toggle_mute() -> void:
	muted = not muted
