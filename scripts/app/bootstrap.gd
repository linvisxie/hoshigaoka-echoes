## Bootstrap — 启动场景（Phase 0 建立，P0.1 扩展）。
##
## 职责：
##   1. 验证引擎可运行、Autoload 就绪、数据可加载
##   2. 按命令行参数进入指定场景（P0.1 用于直接进入战斗原型）
##   3. 无头模式下打印状态后退出（CI / 自动化验证）
##
## 命令行参数（Godot 用户参数，需写在 -- 之后）：
##   --scene=battle    直接进入 P0.1 战斗场景
##   --scene=bootstrap 停留在启动场景（默认）
## 示例：
##   HoshigaokaEchoes.exe -- --scene=battle
##
## 标题画面 / 校园 Hub / 前台状态流属 Alpha A0.7，不在此实现。
extends Node2D

const TAG := "Bootstrap"

## 支持的启动目标（与 SceneRouter.SCENES 的 key 对齐；battle 为本阶段新增）
const BOOT_TARGETS := {
	"bootstrap": "res://scenes/bootstrap/bootstrap.tscn",
	"battle": "res://scenes/battle/battle_scene.tscn",
}


func _ready() -> void:
	GameLog.info(TAG, "启动场景就绪")
	GameLog.info(TAG, "版本: %s" % App.APP_VERSION)

	var data_ok: bool = DataRegistry.is_loaded()
	GameLog.info(TAG, "DataRegistry 就绪: %s" % str(data_ok))

	var layout := DataRegistry.get_layout()
	if not layout.is_empty():
		GameLog.info(TAG, "布局参数: tileSizePx=%s laneSpacingPx=%s"
			% [layout.get("tileSizePx", "?"), layout.get("laneSpacingPx", "?")])

	var stage_ids := DataRegistry.get_ids("stages")
	GameLog.info(TAG, "已登记关卡数: %d" % stage_ids.size())

	var target := _parse_scene_arg()
	GameLog.info(TAG, "启动目标: %s" % target)

	# 无头运行时直接退出，便于 CI / 自动化验证
	if DisplayServer.get_name() == "headless":
		GameLog.info(TAG, "无头模式：启动验证完成，退出")
		get_tree().quit(0 if data_ok else 1)
		return

	# 非无头且有明确目标时切换场景
	if target != "bootstrap":
		if not BOOT_TARGETS.has(target):
			GameLog.error(TAG, "未知的 --scene 值：%s（可选：%s）"
				% [target, ", ".join(BOOT_TARGETS.keys())])
			return
		var path: String = BOOT_TARGETS[target]
		if not ResourceLoader.exists(path):
			GameLog.error(TAG, "场景不存在：%s" % path)
			return
		var err := get_tree().change_scene_to_file(path)
		if err != OK:
			GameLog.error(TAG, "切换场景失败：%s（错误 %d）" % [path, err])
		else:
			GameLog.info(TAG, "已切换到 %s" % path)


## 解析 --scene=<name> 用户参数（Godot 用户参数位于 -- 之后）。
func _parse_scene_arg() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			return arg.substr("--scene=".length()).strip_edges()
	# 兼容直接传 --scene <name> 的形式
	var args := OS.get_cmdline_user_args()
	for i: int in range(args.size()):
		if args[i] == "--scene" and i + 1 < args.size():
			return args[i + 1].strip_edges()
	return "bootstrap"
