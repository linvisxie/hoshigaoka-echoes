## App — 启动、全局流程与版本信息（L4 Autoload）。
##
## Phase 0 范围：记录启动信息、暴露版本/阶段常量、提供退出入口。
## 不含玩法逻辑、不做场景推进（场景推进归 SceneRouter）。
extends Node

const TAG := "App"

## 与 project.godot 的 config/version 保持一致
const APP_VERSION := "0.5.16"
signal ui_input_mode_changed(keyboard: bool)
var keyboard_navigation := false
var _quitting := false
const APP_NAME := "HoshigaokaEchoes"

## 当前开发阶段（V2.1.4 B4 阶段术语：Prototype / Alpha / Beta / RC / Release）
const PHASE := "Alpha"

## 当前阶段标识（V2.1.4 M2 表 114 / M3 表 115 的阶段名）
## Prototype: P0.1 战场 / P0.2 部署 / P0.3 撤退·Wave / P0.4 三职业 / P1.0 演示关
## Alpha:     A0.1 角色成长框架 / A0.2 敌人生态 / A0.3 1-1～1-5 与关卡选择 /
##            A0.4 经济与奖励 / A0.5 装备 / A0.6 编队与局内构筑 /
##            A0.7 标题·Hub·StoryRunner / A0.8 Boss / A0.9 存档 / A1.0 闭环
const PROTOTYPE_STAGE := "A0.1"

## 规格版本（唯一权威总规格）
const SPEC_VERSION := "V2.1.4 CLEAN MASTER"

## 角色成长服务（Alpha A0.1）。在 App._ready 内构建，供前台 UI 与战斗共用同一份
## 成长状态；不注册为 Autoload（L4 的单例表未包含该职责），避免扩大全局单例面。
var growth: CharacterGrowthService = null

## 构建 growth 时所用的存档世代号（见 SaveService.save_generation()）。
##
## 用途（A0.4 加固）：成长服务在构建时把角色等级/经验读进内存。若之后存档被
## **重新加载**（例如启动时的延迟读档、或 backup 回退），这份内存状态就过期了；
## 此时若把它写回，会用旧面板覆盖新存档里的角色进度。
## 因此每次取用前比对世代号，不一致就重建。
var _growth_generation: int = -1


func _enter_tree() -> void:
	# Refuse GUT before test setup/teardown can destroy the actual user:// saves.
	if TestDataGuard.is_gut_invocation(OS.get_cmdline_args()) \
			and not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		printerr("TEST_ISOLATION_REFUSED: user:// must resolve under an absolute _testenv directory")
		get_tree().quit(86)


func _ready() -> void:
	GameLocale.initialize()
	GameSkin.initialize_preferences()
	GameLog.info(TAG, "%s %s (%s %s) 启动"
		% [APP_NAME, APP_VERSION, PHASE, PROTOTYPE_STAGE])
	GameLog.info(TAG, "权威规格: %s" % SPEC_VERSION)
	GameLog.info(TAG, "构建模式: %s（开发专用入口 %s）"
		% [BuildMode.mode_name(), "可用" if BuildMode.allows_dev_entries() else "已禁用"])
	GameLog.info(TAG, "引擎: %s" % Engine.get_version_info().get("string", "unknown"))
	GameLog.info(TAG, "用户数据目录: %s" % OS.get_user_data_dir())
	# 注意：Autoload 的 _ready 顺序由 project.godot 的 [autoload] 段决定，
	# App 排在 DataRegistry 之前，因此此处 DataRegistry 尚未加载。
	# 成长系统的构建推迟到 deferred（此时全部 Autoload 的 _ready 已完成）。
	_init_growth.call_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length_squared()>1.0):
		set_keyboard_navigation(false)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_TAB,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]: set_keyboard_navigation(true)
	elif event is InputEventJoypadButton and event.pressed:
		set_keyboard_navigation(true)

func set_keyboard_navigation(value: bool) -> void:
	if keyboard_navigation==value: return
	keyboard_navigation = value
	ui_input_mode_changed.emit(value)


## 构建角色成长服务并载入存档中的成长状态。
## 纪律：失败不阻断启动（成长是增强项），但必须把错误打到日志里，
## 绝不让"成长静默失效"变成玩家看到的数值异常。
func _init_growth() -> void:
	if not DataRegistry.is_loaded():
		GameLog.error(TAG, "成长系统初始化失败：DataRegistry 未就绪")
		return
	# 始终以当前存档为准重建：setup() 会清空并按存档重新填充，
	# 因此重复调用是安全的（幂等）。
	growth = CharacterGrowthService.new()
	var errs := growth.setup()
	if not errs.is_empty():
		for e: String in errs:
			GameLog.error(TAG, "成长系统初始化失败：%s" % e)
		growth = null
		return
	_growth_generation = SaveService.save_generation()
	EquipmentService.return_incompatible_to_inventory(SaveService.get_current())
	var levels := PackedStringArray()
	for cid: String in growth.all_character_ids():
		var p: CharacterProgress = growth.get_progress(cid)
		if p != null:
			levels.append("%s Lv.%d%s" % [
				cid, p.level, "" if p.breakthrough == 0 else " 突破%d" % p.breakthrough])
	GameLog.info(TAG, "成长系统就绪：%d 名角色（%s）"
		% [growth.all_character_ids().size(), ", ".join(levels)])


## 确保成长系统已就绪（供 UI / 战斗在需要时按需触发一次构建）。
## 返回是否可用。幂等：已就绪且存档世代未变时立即返回 true。
##
## **存档世代校验**：若存档被重新加载过（世代号变化），此处会重建成长服务，
## 保证调用方拿到的角色面板一定来自当前存档，而不是上一份存档的残留。
func ensure_growth() -> bool:
	EquipmentService.return_incompatible_to_inventory(SaveService.get_current())
	if growth != null and growth.is_ready():
		if _growth_generation == SaveService.save_generation():
			return true
		GameLog.info(TAG, "存档世代已变化（%d → %d），重建成长系统以对齐当前存档"
			% [_growth_generation, SaveService.save_generation()])
	_init_growth()
	return growth != null and growth.is_ready()


## 供战斗注入的「角色 id -> 成长面板」表（Alpha A0.1）。
## 返回空字典表示不启用成长（Prototype 固定 Lv.1 行为）。
func level_stats_table() -> Dictionary:
	var out := {}
	if not ensure_growth():
		return out
	for cid: String in growth.all_character_ids():
		var p: CharacterProgress = growth.get_progress(cid)
		if p != null:
			out[cid] = p.compute_stats()
			var bonuses := EquipmentService.bonuses_for_character(SaveService.get_current(), cid)
			for key: String in ["hp", "attack", "defense", "healPower"]:
				if bonuses.has(key):
					out[cid][key] = int(out[cid].get(key, 0)) + int(bonuses[key])
			out[cid]["equipmentBonuses"] = bonuses
	return out


## 返回版本信息字典，供 UI / 诊断 / 测试使用。
func get_version_info() -> Dictionary:
	return {
		"appName": APP_NAME,
		"appVersion": APP_VERSION,
		"phase": PHASE,
		"prototypeStage": PROTOTYPE_STAGE,
		"specVersion": SPEC_VERSION,
		"engine": Engine.get_version_info().get("string", "unknown"),
	}


## 界面用阶段标识（单一来源：不散落在各场景里手写 P0.x）
func stage_label() -> String:
	return "%s %s" % [PHASE, PROTOTYPE_STAGE]


## 请求退出（Hub 的 Esc 菜单二次确认后调用；二次确认 UI 属 Alpha A0.7）。
func request_quit() -> void:
	if _quitting:
		return
	_quitting = true
	GameLog.info(TAG, "收到退出请求，正在退出")
	_finish_quit.call_deferred()


func _finish_quit() -> void:
	# Free the scene first: its final draw must not refill the static cache.
	var scene := get_tree().current_scene
	if scene != null:
		scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioService.release_resources()
	await get_tree().create_timer(0.05).timeout
	# Release static atlas/texture references while the renderer is still alive.
	ArtRegistry.clear_cache()
	GameSkin.release_resources()
	GameLocale.release_resources()
	RenderingServer.force_sync()
	await get_tree().process_frame
	get_tree().quit()
