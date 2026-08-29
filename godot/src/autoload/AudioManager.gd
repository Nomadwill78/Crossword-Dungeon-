## Autoload singleton. Music/SFX playback, respecting GameState.settings.audio
## volumes. No audio assets exist yet in Milestone 1 — every call degrades to
## silence + a warning rather than crashing (CLAUDE.md 5.3), so gameplay code
## can wire up sound cues now and get real audio later for free.
extends Node

var _sfx_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer

func _ready() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SfxPlayer"
	add_child(_sfx_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)

	_apply_volumes()

## Plays a one-shot sound effect from [param path]. No-ops (with a warning)
## if the resource doesn't exist yet.
func play_sfx(path: String) -> void:
	var stream := _load_audio(path)
	if stream == null:
		return
	_sfx_player.stream = stream
	_sfx_player.volume_db = _volume_to_db(_sfx_volume())
	_sfx_player.play()

## Plays background music from [param path], replacing whatever is playing.
func play_music(path: String) -> void:
	var stream := _load_audio(path)
	if stream == null:
		return
	_music_player.stream = stream
	_music_player.volume_db = _volume_to_db(_music_volume())
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()

## Call after GameState.settings.audio changes so volumes take effect
## immediately rather than on the next play_sfx/play_music call.
func refresh_volumes() -> void:
	_apply_volumes()

func _load_audio(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: missing audio %s (playing silence)" % path)
		return null
	return load(path)

func _apply_volumes() -> void:
	_sfx_player.volume_db = _volume_to_db(_sfx_volume())
	_music_player.volume_db = _volume_to_db(_music_volume())

func _sfx_volume() -> float:
	return _get_setting("sfx_volume", 0.9) * _get_setting("master_volume", 0.8)

func _music_volume() -> float:
	return _get_setting("music_volume", 0.6) * _get_setting("master_volume", 0.8)

func _get_setting(key: String, default_value: float) -> float:
	var audio_settings: Dictionary = GameState.settings.get("audio", {})
	return float(audio_settings.get(key, default_value))

func _volume_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)
