## SceneRouter — 场景/菜单路由（L4 Autoload）。
##
## Phase 0 范围：按路径切换场景 + 记录当前场景 + 历史栈骨架。
## 不含任何具体菜单/流程逻辑（前台状态流 J0 属 Alpha A0.7）。
extends Node

const TAG := "SceneRouter"

## 已登记的场景路径（P0.1 起含 battle；title/home 待 Alpha A0.7）
const SCENES := {
	"bootstrap": "res://scenes/bootstrap/bootstrap.tscn",
	"battle": "res://scenes/battle/battle_scene.tscn",
	"title": "res://scenes/title/title.tscn",
	"home": "res://scenes/home/home.tscn",
}

var _current_scene_key: String = ""
var _history: Array[String] = []


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
	return _change(prev, key if not key.is_empty() else prev)


## 当前场景 key（未登记场景时为空）。
func get_current_key() -> String:
	return _current_scene_key


func _change(path: String, key: String) -> bool:
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		GameLog.error(TAG, "切换场景失败 %s（错误 %d）" % [path, err])
		return false
	_current_scene_key = key
	_history.append(path)
	GameLog.debug(TAG, "场景切换 -> %s" % path)
	return true
