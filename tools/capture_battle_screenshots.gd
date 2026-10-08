## 一次性工具：运行 P0.1 战斗场景并抓取截图（用于目视验收）。
##
## 用法（需要真实渲染，不能 --headless）：
##   godot --path <proj> --script res://tools/capture_battle_screenshots.gd
##
## 产出：user:// 下的 PNG 截图 + 一份运行摘要文本。
extends SceneTree

const SHOT_DIR := "user://p0.1_shots"
## 抓图时间点（秒，逻辑时间）
const SHOT_TIMES := [0.5, 3.0, 8.0, 14.0]

var _scene: Node = null
var _elapsed: float = 0.0
var _shot_index: int = 0
var _summary: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var packed: PackedScene = load("res://scenes/battle/battle_scene.tscn")
	if packed == null:
		printerr("无法加载战斗场景")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	# 不启用无头；等待 _ready 完成
	process_frame.connect(_on_frame)
	print("[Capture] 战斗场景已加载，开始抓图")


func _on_frame() -> void:
	if _scene == null:
		return
	var session: Node = _scene.get("session")
	if session == null:
		return
	# 用固定步长推进一帧逻辑，便于可控抓图
	var step := 1.0 / 60.0
	_elapsed += step
	session.call("tick", step)

	if _shot_index < SHOT_TIMES.size() and _elapsed >= float(SHOT_TIMES[_shot_index]):
		_capture(_shot_index)
		_shot_index += 1

	# 抓满 4 张，或战斗已结束则收尾
	if _shot_index >= SHOT_TIMES.size() or session.call("is_decided"):
		_finish()


func _capture(idx: int) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/battle_%02d.png" % [SHOT_DIR, idx]
	var err := img.save_png(path)
	_summary.append("截图 %d @ %.2fs -> %s (err=%d)" % [idx, _elapsed, path, err])
	print("[Capture] %s" % _summary[-1])


func _finish() -> void:
	var session: Node = _scene.get("session")
	var dbg: Dictionary = session.call("to_debug_dict")
	_summary.append("最终状态: outcome=%s coreHp=%s/%s spawned=%s/%s reachedCore=%s events=%s" % [
		dbg.get("outcome", "?"), dbg.get("coreHp", "?"), dbg.get("coreHpMax", "?"),
		dbg.get("spawned", "?"), dbg.get("planned", "?"),
		dbg.get("reachedCore", "?"), dbg.get("coreDamageEvents", "?"),
	])
	var f := FileAccess.open("%s/summary.txt" % SHOT_DIR, FileAccess.WRITE)
	f.store_string("\n".join(_summary) + "\n")
	f.close()
	print("[Capture] 完成；截图目录: %s" % ProjectSettings.globalize_path(SHOT_DIR))
	quit(0)
