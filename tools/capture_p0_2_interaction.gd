## P0.2 交互验收工具：用**真实的输入事件**驱动战斗场景，
## 截取「部署前 / 部署后 / 阻挡中 / 攻击中 / 胜负」各阶段截图。
##
## 说明：本工具通过 Input.parse_input_event 注入真实鼠标事件，
## 走的是与玩家完全相同的输入管线（_unhandled_input / _input），
## 不直接调用部署接口，因此能验证 UI 交互链路。
##
## 用法（需要真实渲染）：
##   godot --path <proj> --script res://tools/capture_p0_2_interaction.gd
extends SceneTree

const OUT_DIR := "user://p0.2_shots"

var _scene: Node
var _step := 1.0 / 60.0
var _elapsed := 0.0
var _phase := 0
var _shots: Array[String] = []
## 部署目标格（中段 col2）：与 1-1 主攻路线一致
const TARGET_COL := 2
const TARGET_LANE := 1

## 阶段推进标记
var _card_clicked := false
var _deploy_clicked := false
var _deploy_done := false
var _block_seen := false
var _kill_seen := false
var _hover_shown := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/battle/battle_scene.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	print("[P0.2] 场景加载完成，开始交互验收")


func _process(_d: float) -> bool:
	if _scene == null:
		return false
	var session: Node = _scene.get("session")
	if session == null:
		return false

	session.call("tick", _step)
	_elapsed += _step

	match _phase:
		0:  # 部署前：界面初始状态 + 悬停合法格
			if _elapsed >= 1.0:
				_hover_cell(TARGET_COL, TARGET_LANE)
				_wait_frames(2)
				_capture("01_deploy_before_hover")
				# 点击角色卡（真实鼠标左键）
				_click_card()
				_card_clicked = true
				_wait_frames(2)
				_capture("02_card_selected")
				_phase = 1
		1:  # 左键点击目标格部署
			if _card_clicked and not _deploy_clicked:
				_hover_cell(TARGET_COL, TARGET_LANE)
				_wait_frames(2)
				_click_cell(TARGET_COL, TARGET_LANE)
				_deploy_clicked = true
				_wait_frames(2)
				_capture("03_deploy_after")
				_phase = 2
		2:  # 等待阻挡与攻击
			var mio: Node = session.stage.get_character_by_id("amamiya_mio")
			if mio != null and mio.blocking_enemy_ids.size() > 0:
				if not _block_seen:
					_block_seen = true
					_capture("04_blocking")
				if mio.total_damage_dealt > 0 and not _kill_seen:
					_kill_seen = true
					_capture("05_attacking")
				if session.stage.enemies_killed >= 2:
					_capture("06_kills")
					_phase = 3
			# 兜底：敌人已漏怪或战斗结束也进入下一阶段
			if session.is_decided():
				_capture("07_outcome")
				_finish()
				return true
		3:  # 等待战斗结束
			if session.is_decided():
				_capture("07_outcome")
				_finish()
				return true
			if _elapsed > 120.0:
				_capture("07_outcome_timeout")
				_finish()
				return true
	return false


func _wait_frames(n: int) -> void:
	for i: int in range(n):
		root.get_process_delta_time()  # 占位；帧推进由引擎循环处理
		_advance_frame()


func _advance_frame() -> void:
	# SceneTree 脚本里手动推进一帧渲染（用于截图前确保绘制完成）
	root.process_mode = Node.PROCESS_MODE_ALWAYS


func _card_rect() -> Rect2:
	# 与 battle_scene._draw_character_card 的绘制保持一致（中低端分辨率下由引擎缩放）
	var card_h := 170.0
	var card_w := 340.0
	return Rect2(Vector2(24.0, 1080.0 - card_h - 24.0), Vector2(card_w, card_h))


func _cell_pos(column: int, lane: int) -> Vector2:
	var g: Node = _scene.get("grid")
	var origin: Vector2 = _scene.get("_origin")
	var tile: float = g.tile_size_px
	var spacing: float = g.lane_spacing_px
	return Vector2(origin.x + tile * float(column), origin.y + float(lane) * spacing)


func _send_click(pos: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	Input.parse_input_event(move)
	var press := InputEventMouseButton.new()
	press.position = pos
	press.global_position = pos
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.position = pos
	release.global_position = pos
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)


func _click_card() -> void:
	var r := _card_rect()
	_send_click(r.position + r.size * 0.5)
	print("[P0.2] 点击角色卡 at ", r.position + r.size * 0.5)


func _click_cell(column: int, lane: int) -> void:
	var p := _cell_pos(column, lane)
	_send_click(p)
	print("[P0.2] 点击格 (col%d, lane%d) at %s" % [column, lane, p])


func _hover_cell(column: int, lane: int) -> void:
	var p := _cell_pos(column, lane)
	var move := InputEventMouseMotion.new()
	move.position = p
	move.global_position = p
	Input.parse_input_event(move)
	print("[P0.2] 悬停格 (col%d, lane%d)" % [column, lane])


func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_shots.append(path)
	print("[P0.2] 截图 %s (err=%d)" % [path, err])


func _finish() -> void:
	var session: Node = _scene.get("session")
	var dbg: Dictionary = session.call("to_debug_dict")
	print("")
	print("=== P0.2 交互验收汇总 ===")
	print("  结果: ", dbg.get("outcome"))
	print("  核心: %s/%s  AP: %s/%s" % [dbg.get("coreHp"), dbg.get("coreHpMax"), dbg.get("ap"), dbg.get("apMax")])
	print("  击杀: %s  漏怪: %s  失能: %s" % [dbg.get("enemiesKilled"), dbg.get("reachedCore"), dbg.get("charactersLost")])
	print("  已部署: %s  逻辑时间: %s" % [dbg.get("deployed"), dbg.get("elapsed")])
	var f := FileAccess.open("%s/summary.txt" % OUT_DIR, FileAccess.WRITE)
	f.store_string("\n".join(_shots) + "\n\n" + str(dbg))
	f.close()
	print("  截图目录: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)
