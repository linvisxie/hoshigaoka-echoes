## Bootstrap — 启动场景（Phase 0 建立，P0.1 扩展，P1.0 改为玩家可直接启动）。
##
## 职责：
##   1. 验证引擎可运行、Autoload 就绪、数据可加载
##   2. 按命令行参数 + 构建模式决定进入哪个场景、加载哪一关
##   3. 无头模式下打印状态后退出（CI / 自动化验证）
##
## P1.0「玩家可直接启动」（本轮指令 四）：
##   **不带任何参数**双击 EXE 即进入可玩战斗演示，并加载 Prototype 演示关 p1_0_demo。
##   演示关 id / 取关方式 / 开发参数准入全部由 PrototypeEntry 决策，本文件只做执行。
##
## Alpha A0.7 修订（标题画面落地后）：
##   **不带任何参数**改为进入 **标题画面**（scenes/title/title.tscn）——这是正式首启体验；
##   战斗演示仍可随时进入：标题画面的「继续游戏 / 新游戏」直接进战斗，
##   开发/自动化入口 `--scene=battle` **行为完全不变**（仍加载默认演示关）。
##   注意：本文件**没有**改动 PrototypeEntry.parse_scene_arg() 的语义
##   （无参数时它依然返回 battle），只在 bootstrap 这一层区分
##   「用户显式传了 --scene」与「完全没传参数」——前者一律按参数走，
##   后者才改用标题画面。Retail 构建的取关语义因此保持不变。
##
## 命令行参数（Godot 用户参数，需写在 -- 之后）：
##   （无）                  进入标题画面
##   --scene=title          同上
##   --scene=stage_select   进入关卡选择
##   --scene=battle         进入战斗场景，加载默认关卡（Prototype 演示关 p1_0_demo）
##   --scene=character      进入角色培养界面
##   --scene=bootstrap      停留在启动场景（空白 Node2D，仅诊断用）
##   --stage=<stageId>      指定关卡（**开发专用**，Retail 构建下拒绝）
## 示例：
##   HoshigaokaEchoes.exe                                  # 标题画面
##   HoshigaokaEchoes.exe -- --scene=battle                # 开发：直接进演示关
##   HoshigaokaEchoes.exe -- --scene=battle --stage=1-1    # 开发：跑正式 1-1
##
## 标题画面 / 校园 Hub / 前台状态流属 Alpha A0.7（标题画面本轮已落地，Hub 仍未实现）。
##
## P0.3 修复：场景切换不再于 _ready 内同步执行。
## 在 _ready 里直接调用 change_scene_to_file() 会把当前场景从其父节点上摘除，
## 而此时引擎仍在遍历子节点，于是偶发报
## 「remove_child() can't be called at this time」。
## 现改为 call_deferred 推迟到本帧末，避开遍历期。
extends Node2D

const TAG := "Bootstrap"

## 支持的启动目标（与 SceneRouter.SCENES 的 key 对齐）
## battle 为 P0.1 起新增；character 为 Alpha A0.1 起新增（角色培养界面）；
## title 为 Alpha A0.7 起新增（标题画面）；
## stage_select 为 Alpha A0.7 起新增（关卡选择，便于自动化与实机验收直接打开）。
const BOOT_TARGETS := {
	"bootstrap": "res://scenes/bootstrap/bootstrap.tscn",
	"title": "res://scenes/title/title.tscn",
	"battle": "res://scenes/battle/battle_scene.tscn",
	"character": "res://scenes/menus/character_screen.tscn",
	"stage_select": "res://scenes/menus/stage_select.tscn",
}

## 启动场景 key 前缀
const ARG_SCENE_PREFIX := "--scene="

## 待切换的场景路径（空 = 不切换）
var _pending_scene_path: String = ""


func _ready() -> void:
	GameLog.info(TAG, "启动场景就绪")
	GameLog.info(TAG, "版本: %s" % App.APP_VERSION)
	GameLog.info(TAG, "构建模式: %s" % BuildMode.mode_name())

	var data_ok: bool = DataRegistry.is_loaded()
	GameLog.info(TAG, "DataRegistry 就绪: %s" % str(data_ok))

	var layout := DataRegistry.get_layout()
	if not layout.is_empty():
		GameLog.info(TAG, "布局参数: tileSizePx=%s laneSpacingPx=%s"
			% [layout.get("tileSizePx", "?"), layout.get("laneSpacingPx", "?")])

	var stage_ids := DataRegistry.get_ids("stages")
	GameLog.info(TAG, "已登记关卡数: %d" % stage_ids.size())
	var proto_ids := DataRegistry.get_ids(PrototypeEntry.PROTOTYPE_STAGES_KEY)
	GameLog.info(TAG, "已登记 Prototype 演示关数: %d" % proto_ids.size())

	# 启动计划：场景 + 关卡 + 开发参数是否放行（Retail 构建下一律不放行）
	var plan := PrototypeEntry.plan_startup()
	var target: String = plan.get("scene", PrototypeEntry.SCENE_BATTLE)
	var stage_id: String = plan.get("stageId", "")
	for note: String in plan.get("notes", []):
		GameLog.info(TAG, note)
	# Alpha A0.7：完全没传 --scene 时进入标题画面（正式首启体验）。
	# 一旦用户显式传了 --scene=<x>，就一律按参数走（--scene=battle 行为不变）。
	if not _has_scene_arg():
		target = "title"
		GameLog.info(TAG, "未指定 --scene：进入标题画面（正式首启体验）")
	GameLog.info(TAG, "启动目标: %s（关卡 %s）" % [target, stage_id])

	# 无头运行时直接退出，便于 CI / 自动化验证
	if DisplayServer.get_name() == "headless":
		GameLog.info(TAG, "无头模式：启动验证完成，退出")
		get_tree().quit(0 if data_ok else 1)
		return

	# 非无头且有明确目标时切换场景
	if target == PrototypeEntry.SCENE_BOOTSTRAP:
		return
	if not BOOT_TARGETS.has(target):
		GameLog.error(TAG, "未知的 --scene 值：%s（可选：%s）"
			% [target, ", ".join(BOOT_TARGETS.keys())])
		return
	var path: String = BOOT_TARGETS[target]
	if not ResourceLoader.exists(path):
		GameLog.error(TAG, "场景不存在：%s" % path)
		return

	# 把本关决策交给战斗场景（切换前写入，battle_scene 构建时消费）
	PrototypeEntry.set_pending_stage_id(stage_id)

	# 推迟到本帧末执行，避免在 _ready 的子节点遍历期内摘除场景
	_pending_scene_path = path
	GameLog.info(TAG, "已安排切换到 %s（延迟到本帧末）" % path)
	call_deferred("_apply_pending_scene")


## 用户是否显式传了 --scene=<x>（含 "--scene <x>" 形式）。
## 只做「有没有传」的判断，不解释取值——取值仍由 PrototypeEntry.parse_scene_arg() 负责，
## 避免在 bootstrap 里复制一份场景解析策略。
func _has_scene_arg() -> bool:
	var args := OS.get_cmdline_user_args()
	for i: int in range(args.size()):
		if args[i].begins_with(ARG_SCENE_PREFIX):
			return true
		if args[i] == "--scene" and i + 1 < args.size():
			return true
	return false


## 在帧末真正执行场景切换（call_deferred 目标）。
func _apply_pending_scene() -> void:
	if _pending_scene_path.is_empty():
		return
	var path := _pending_scene_path
	_pending_scene_path = ""
	# 二次确认本节点仍在场景树内（切换前可能已被其他流程移除）
	if not is_inside_tree():
		GameLog.warn(TAG, "节点已不在场景树内，取消切换 %s" % path)
		return
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		GameLog.error(TAG, "切换场景失败：%s（错误 %d）" % [path, err])
	else:
		GameLog.info(TAG, "已切换到 %s" % path)
