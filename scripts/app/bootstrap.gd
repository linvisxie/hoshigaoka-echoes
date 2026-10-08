## Bootstrap — 启动场景（Phase 0 占位）。
##
## Phase 0 职责：验证引擎可运行、Autoload 就绪、数据可加载；无头模式下打印状态后退出。
## 标题画面 / 校园 Hub / 前台状态流属 Alpha A0.7，不在此实现。
extends Node2D

const TAG := "Bootstrap"


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

	# 无头运行时直接退出，便于 CI / 自动化验证（Phase 0 验收项之一）
	if DisplayServer.get_name() == "headless":
		GameLog.info(TAG, "无头模式：启动验证完成，退出")
		get_tree().quit(0 if data_ok else 1)
