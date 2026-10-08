## 一次性工具：按 V2.1.4 L7 写入 InputMap Action 到 project.godot。
##
## 关键点：InputMap.add_action() 只改运行时映射，不会落盘。
## 必须通过 ProjectSettings.set_setting("input/<action>", {...}) 显式写入后再 save()。
##
## 用法：
##   godot --headless --path <proj> --script res://tools/setup_input_map.gd
extends SceneTree

## L7 要求的 Action 与默认物理键位（V2.1.4 D-补充 + J2 操作表）
const ACTIONS := {
	"select_slot_1": [KEY_1],
	"select_slot_2": [KEY_2],
	"select_slot_3": [KEY_3],
	"select_slot_4": [KEY_4],
	"select_slot_5": [KEY_5],
	"select_slot_6": [KEY_6],
	"confirm_action": [KEY_ENTER, KEY_SPACE],
	"cancel_action": [KEY_ESCAPE],
	"pause_game": [KEY_SPACE],
	"unit_skill": [KEY_F],
	"unit_retreat": [KEY_R],
}


func _initialize() -> void:
	var written := 0
	for action_name: String in ACTIONS.keys():
		var events: Array = []
		for keycode: int in ACTIONS[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			events.append(ev)
		var payload := {
			"deadzone": 0.5,
			"events": events,
		}
		# 关键：写入 ProjectSettings 的 input/ 命名空间才能落盘
		ProjectSettings.set_setting("input/%s" % action_name, payload)
		written += 1

	var err := ProjectSettings.save()
	if err == OK:
		print("[InputMap] 已写入 project.godot：%d 个 Action" % written)
	else:
		printerr("[InputMap] 保存失败，错误码 %d" % err)
	quit(0 if err == OK else 1)
