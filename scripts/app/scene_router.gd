## SceneRouter — 场景/菜单路由（L4 Autoload）。
##
## Phase 0 范围：按路径切换场景 + 记录当前场景 + 历史栈骨架。
## 不含任何具体菜单/流程逻辑（前台状态流 J0 属 Alpha A0.7）。
extends Node

const TAG := "SceneRouter"
const MENU_FADE_SECONDS := .55
var _menu_snapshot: CanvasLayer
var _menu_fade: Tween

## 已登记的场景路径。
## P0.1 起含 battle；Alpha A0.1 起含 character（角色培养，V2.1.4 H 章三十三）。
## Alpha A0.7 起含 title；stage_select（关卡选择）本轮新增——
##   在校园 Hub（home，J0.4）与关卡情报流程落地前，它是玩家**在界面上**唯一
##   能选择 1-1～1-5 的入口（Retail 构建拒绝开发参数 --stage）。
## home 为校园地点、可选事件和学生手册入口；所有推进由 CampaignFlow 校验。
const SCENES := {
	"bootstrap": "res://scenes/bootstrap/bootstrap.tscn",
	"battle": "res://scenes/battle/battle_scene.tscn",
	"character": "res://scenes/menus/character_screen.tscn",
	"stage_select": "res://scenes/menus/stage_select.tscn",
	"title": "res://scenes/title/title.tscn",
	"home": "res://scenes/home/home.tscn",
	"story": "res://scenes/story/story.tscn",
	"briefing": "res://scenes/menus/briefing.tscn",
	"archive": "res://scenes/menus/archive.tscn",
	"settings": "res://scenes/menus/settings.tscn",
	"credits": "res://scenes/menus/credits.tscn",
	"new_game": "res://scenes/menus/new_game.tscn",
	"character_details": "res://scenes/menus/character_details.tscn",
	"equipment": "res://scenes/menus/equipment.tscn",
	"character_equipment": "res://scenes/menus/character_equipment.tscn",
}

var _current_scene_key: String = ""
var _entry_origin: String = ""
var _history: Array[String] = []
## Transient settings navigation, independent of player progress and save data.
var settings_return_key := "title"
var settings_scroll := 0
var last_campus_investigation := ""


## 按 key 切换场景。
func go_to(key: String) -> bool:
	if not SCENES.has(key):
		GameLog.error(TAG, "未登记的场景 key: %s" % key)
		return false
	var path: String = SCENES[key]
	if not ResourceLoader.exists(path):
		GameLog.error(TAG, "场景资源不存在: %s（该场景尚未创建）" % path)
		return false
	return _change(path, key)


## 直接按资源路径切换场景。
func go_to_path(path: String) -> bool:
	if not ResourceLoader.exists(path):
		GameLog.error(TAG, "场景资源不存在: %s" % path)
		return false
	return _change(path, path)


## 返回上一个场景。
func go_back() -> bool:
	if _history.size() < 2:
		GameLog.warn(TAG, "没有可返回的历史场景")
		return false
	_history.pop_back()
	var prev: String = _history[-1]
	var key := ""
	for k: String in SCENES.keys():
		if SCENES[k] == prev:
			key = k
			break
	return _change(prev, key if not key.is_empty() else prev, false)


## 当前场景 key（未登记场景时为空）。
func get_current_key() -> String:
	return _current_scene_key

## Immediate transition source, including same-scene rebuilds. History is
## deliberately deduplicated and cannot distinguish a rebuild from re-entry.
func entry_origin() -> String:
	return _entry_origin

func previous_key() -> String:
	if _history.size() < 2:
		return "title"
	var previous := _history[-2]
	for key: String in SCENES:
		if str(SCENES[key]) == previous:
			return key
	return "title"


func _change(path: String, key: String, remember: bool = true) -> bool:
	var origin := _current_scene_key
	if origin=="title" and key in ["home","settings"]: _capture_menu_frame()
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		_clear_menu_snapshot()
		GameLog.error(TAG, "切换场景失败 %s（错误 %d）" % [path, err])
		return false
	if key == "home":
		CampaignFlow.inspected_character_id = "amamiya_mio"
	_entry_origin = origin
	_current_scene_key = key
	if remember and (_history.is_empty() or _history[-1] != path):
		_history.append(path)
	GameLog.debug(TAG, "场景切换 -> %s" % path)
	return true

func _capture_menu_frame() -> void:
	_clear_menu_snapshot()
	if DisplayServer.get_name()=="headless": return
	var picture := get_viewport().get_texture().get_image()
	if picture==null or picture.is_empty(): return
	_menu_snapshot = CanvasLayer.new()
	_menu_snapshot.layer = 100
	add_child(_menu_snapshot)
	var cover := TextureRect.new()
	cover.texture = ImageTexture.create_from_image(picture)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_SCALE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_snapshot.add_child(cover)
	get_tree().scene_changed.connect(_fade_menu_snapshot,CONNECT_ONE_SHOT)

func _fade_menu_snapshot() -> void:
	if not is_instance_valid(_menu_snapshot): return
	var cover := _menu_snapshot.get_child(0) as TextureRect
	_menu_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_menu_fade.tween_property(cover,"modulate:a",0.0,MENU_FADE_SECONDS)
	_menu_fade.tween_callback(_clear_menu_snapshot)

func _clear_menu_snapshot() -> void:
	if get_tree().scene_changed.is_connected(_fade_menu_snapshot): get_tree().scene_changed.disconnect(_fade_menu_snapshot)
	if _menu_fade != null:
		_menu_fade.kill()
		_menu_fade = null
	if is_instance_valid(_menu_snapshot): _menu_snapshot.queue_free()
	_menu_snapshot = null

func _input(event: InputEvent) -> void:
	if is_instance_valid(_menu_snapshot) and (event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton):
		get_viewport().set_input_as_handled()
