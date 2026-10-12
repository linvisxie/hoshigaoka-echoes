## AudioService — BGM/SFX 总线控制（L4 Autoload）。
##
## 原创场景音乐、事件音效、淡入淡出及持久化音量设置。
extends Node

const TAG := "AudioService"

const BUS_MASTER := "Master"
const BUS_BGM := "BGM"
const BUS_SFX := "SFX"
## K-二十八：音量设置范围 0～100
const VOLUME_MIN := 0.0
const VOLUME_MAX := 100.0

## 逻辑总线名 -> 音量(0~100)
var _volumes: Dictionary = {
	BUS_MASTER: 100.0,
	BUS_BGM: 100.0,
	BUS_SFX: 100.0,
}

var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _last_sound: Dictionary = {}
var _current_music := ""
var _music_tween: Tween
var _streams: Dictionary = {}
var _variant_cursor: Dictionary = {}
var _played_assets: Dictionary = {}

const FOLEY := {
	"slash": ["resonance_blade_01","resonance_blade_02"],
	"hit": ["resonance_hit_01","resonance_hit_02","resonance_hit_03"],
	"hit_armor": ["resonance_armor_01","resonance_armor_02"],
	"enemy_death": ["resonance_dissolve_01","resonance_dissolve_02"],
}


func _ready() -> void:
	for bus_name: String in [BUS_BGM, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	# Gentle group compression catches simultaneous impacts without flattening
	# the piano music or changing the player's saved volume controls.
	var sfx_bus := AudioServer.get_bus_index(BUS_SFX)
	if AudioServer.get_bus_effect_count(sfx_bus) == 0:
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -16.0
		compressor.ratio = 2.5
		compressor.attack_us = 1800.0
		compressor.release_ms = 130.0
		AudioServer.add_bus_effect(sfx_bus, compressor)
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_BGM
	add_child(_music)
	for i: int in range(12):
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS_SFX
		add_child(voice)
		_voices.append(voice)
	var settings := ConfigFile.new()
	if settings.load("user://settings/settings.cfg") == OK:
		for bus_name: String in [BUS_MASTER, BUS_BGM, BUS_SFX]:
			_volumes[bus_name] = clampf(float(settings.get_value("audio", bus_name, 100.0)), 0.0, 100.0)
		if bool(settings.get_value("display", "fullscreen", false)):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_apply_all()


func play_music(track: String, loop: bool = true) -> void:
	# A stopped player remains stopped during the fade-out before stream swap.
	# Per-frame battle policy must not keep cancelling that pending transition.
	var transitioning := _music_tween != null and _music_tween.is_running()
	if _music == null or (track == _current_music and (_music.playing or transitioning)):
		return
	var path := "res://assets/audio/bgm/%s.wav" % track
	if not ResourceLoader.exists(path):
		GameLog.warn(TAG, "音乐未制作：%s" % track)
		return
	var stream := load(path) as AudioStreamWAV
	if stream == null:
		return
	stream = stream.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * float(stream.mix_rate))
	_current_music = track
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -36.0, 0.18)
	_music_tween.tween_callback(func() -> void:
		_music.stream = stream
		_music.play())
	_music_tween.tween_property(_music, "volume_db", -12.0, 0.6)


func stop_music() -> void:
	if _music_tween != null:
		_music_tween.kill()
	if _music != null:
		_music.stop()
	_current_music = ""


func play_sfx(sound: String, gain_db: float = 0.0) -> void:
	var now := Time.get_ticks_msec()
	# Sound-specific debounce plus a bounded voice pool prevent combat clipping.
	if now - int(_last_sound.get(sound, -1000)) < 70:
		return
	var cue := "ui_confirm" if sound == "select" else sound
	var turn := int(_variant_cursor.get(sound,0))
	if FOLEY.has(sound):
		cue = str(FOLEY[sound][turn % FOLEY[sound].size()])
	var path := "res://assets/audio/sfx/%s.%s" % [cue,"ogg" if cue.begins_with("ui_") else "wav"]
	if not _streams.has(path):
		if not ResourceLoader.exists(path):
			return
		_streams[path] = load(path)
	for voice: AudioStreamPlayer in _voices:
		if not voice.playing:
			_last_sound[sound] = now
			_variant_cursor[sound] = turn+1
			voice.stream = _streams[path]
			voice.volume_db = (-11.0 if FOLEY.has(sound) else -9.0) + gain_db
			voice.pitch_scale = 0.99+float(turn%3)*0.01 if FOLEY.has(sound) else 1.0
			voice.play()
			_played_assets[cue] = int(_played_assets.get(cue,0))+1
			return


func playback_status() -> Dictionary:
	var active := 0
	for voice: AudioStreamPlayer in _voices:
		if voice.playing:
			active += 1
	return {"track": _current_music, "musicPlaying": _music != null and _music.playing,
		"musicPosition": _music.get_playback_position() if _music != null else 0.0,
		"activeVoices": active, "soundsTriggered": _last_sound.keys(),"playedAssets":_played_assets.duplicate()}


## 设置某总线音量（0～100）。
func set_volume(bus_name: String, value: float) -> void:
	_volumes[bus_name] = clampf(value, VOLUME_MIN, VOLUME_MAX)
	_apply_bus(bus_name)


## 读取某总线音量。
func get_volume(bus_name: String) -> float:
	return float(_volumes.get(bus_name, 100.0))


## 导出全部音量设置，供 SaveService/设置界面持久化。
func to_dict() -> Dictionary:
	return _volumes.duplicate()


## 从字典恢复音量设置。
func from_dict(data: Dictionary) -> void:
	for k: String in data.keys():
		if _volumes.has(k):
			_volumes[k] = clampf(float(data[k]), VOLUME_MIN, VOLUME_MAX)
	_apply_all()


func _apply_all() -> void:
	for bus_name: String in _volumes.keys():
		_apply_bus(bus_name)


func _apply_bus(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		# Phase 0 未创建自定义总线，静默跳过（总线在音频阶段一并建立）。
		return
	var linear := float(_volumes.get(bus_name, 100.0)) / 100.0
	var db := linear_to_db(linear) if linear > 0.0 else -80.0
	AudioServer.set_bus_volume_db(idx, db)
