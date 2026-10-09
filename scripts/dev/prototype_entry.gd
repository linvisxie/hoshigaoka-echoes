## PrototypeEntry — P1.0「玩家可直接启动」的入口决策 + 关卡取用接口。
##
## 职责（本轮指令 四）：
##   把「命令行参数 + 构建模式」解析成一次**确定的启动计划**（进哪个场景、加载哪一关），
##   并提供 battle_scene 取用当前关卡配置的唯一接口。
##   本文件不含任何战斗规则，也不读写任何 data 文件。
##
## 启动规则：
##   （无参数）              -> battle + Prototype 演示关（双击 EXE 即可进入可玩演示）
##   --scene=battle          -> 同上
##   --scene=bootstrap       -> 停留在启动场景（不切换）
##   --stage=<stageId>       -> 覆盖关卡（**开发专用**，Retail 构建下拒绝并告警）
##   示例：HoshigaokaEchoes.exe -- --scene=battle --stage=1-1
##
## 纪律（本轮指令 四）：
##   开发验证可保留；不允许把测试阵容覆盖误认为正式解锁；
##   正式零售构建不得通过开发参数绕过解锁条件——故所有开发专用参数一律经
##   BuildMode.allows_dev_entries() 判定。
##
## 关卡取值优先级（load_stage_config）：
##   1) DataRegistry 的 Prototype 独立索引键 "prototype_stages"
##      （P1.0 起 data/stages/prototype/ 下的演示关以该键加载，不进入 canonical 集合）
##   2) 兜底 canonical 的 "stages" 索引（--stage=1-1 走这条路径）
class_name PrototypeEntry
extends RefCounted

const TAG := "PrototypeEntry"

## Prototype 演示关 id（res://data/stages/prototype/p1_0_demo.json）
const DEMO_STAGE_ID := "p1_0_demo"

## 正式第一章第一关：Retail 构建的默认入口，也是取不到演示关时的兜底
const FALLBACK_STAGE_ID := "1-1"

## DataRegistry 中的 Prototype 独立索引键（与 DataRegistry.PROTOTYPE_STAGES_KEY 一致）
const PROTOTYPE_STAGES_KEY := "prototype_stages"

## DataRegistry 中的 canonical 关卡索引键
const CANONICAL_STAGES_KEY := "stages"

## 开发专用参数前缀
const ARG_STAGE_PREFIX := "--stage="

## 场景 key（与 bootstrap.BOOT_TARGETS 对齐）
const SCENE_BOOTSTRAP := "bootstrap"
const SCENE_BATTLE := "battle"
## Alpha A0.1：角色培养界面（V2.1.4 H 章三十三）。
## 正式流程里它由校园 Hub 的「角色」入口进入（Alpha A0.7）；
## 在 Hub 落地之前，允许用 --scene=character 直接打开以便实机验收。
const SCENE_CHARACTER := "character"

## 本次启动要加载的关卡 id。
##
## 由 bootstrap 在**切换场景前**写入，由 battle_scene 在构建战斗时取用。
## 用静态变量而不是新增 Autoload：L4 的单例表未包含此职责，
## 且它只在一次启动决策与一次场景初始化之间存活，不需要全局生命周期。
static var _pending_stage_id: String = ""


## 记录本次启动的目标关卡（bootstrap 调用）。
static func set_pending_stage_id(stage_id: String) -> void:
	_pending_stage_id = stage_id


## 取出并清空本次启动的目标关卡（battle_scene 调用）。
## 返回空串表示「本次不是由入口决策指定的关卡」，调用方应使用 default_stage_id()。
static func consume_pending_stage_id() -> String:
	var value := _pending_stage_id
	_pending_stage_id = ""
	return value


## 解析启动计划。
## 返回 { scene: String, stageId: String, devOverride: bool, notes: Array[String] }。
static func plan_startup() -> Dictionary:
	var notes: Array[String] = []
	var scene := parse_scene_arg()
	var requested := parse_stage_arg()
	var dev_override := false

	if not requested.is_empty():
		if BuildMode.allows_dev_entries():
			notes.append("开发专用入口 --stage=%s 已生效" % requested)
			dev_override = true
		else:
			# Retail 构建：开发参数一律拒绝，落回正式默认入口（不报错、不崩溃）
			var msg := "Retail 构建拒绝开发专用入口 --stage=%s" % requested
			GameLog.warn(TAG, msg)
			notes.append(msg)

	var stage_id := requested if dev_override else default_stage_id()

	# 校验：目标关卡必须真实存在，否则战斗场景会在取关时空转。
	# DataRegistry 尚未加载时不校验（正常启动流程中 Autoload 先于主场景就绪）。
	if DataRegistry.is_loaded() and not has_stage(stage_id):
		var fallback := default_stage_id()
		notes.append("关卡 '%s' 不在任何索引中，退回 '%s'" % [stage_id, fallback])
		GameLog.warn(TAG, "关卡 '%s' 不在任何索引中，退回 '%s'" % [stage_id, fallback])
		stage_id = fallback

	return {
		"scene": scene,
		"stageId": stage_id,
		"devOverride": dev_override,
		"notes": notes,
	}


## 默认关卡 id。
##   Prototype / 演示构建：直接进 Prototype 演示关（双击 EXE 的默认体验）。
##   Retail：演示关是 Prototype 专属产物（其 availableCharacters 直接给出三职业），
##           不得作为正式首启体验，故退回正式第一章第一关。
static func default_stage_id() -> String:
	if BuildMode.is_prototype():
		return DEMO_STAGE_ID
	return FALLBACK_STAGE_ID


## 取关卡配置（Prototype 独立索引优先，canonical 关卡兜底）。
##
## 兜底说明：若 DataRegistry 尚未实现 "prototype_stages" 独立索引键
## （或零售构建不带 data/stages/prototype/ 目录），get_entry 返回空字典，
## 此时自动退回 canonical 的 "stages" 索引，不会报错。
static func load_stage_config(stage_id: String) -> Dictionary:
	if stage_id.is_empty():
		return {}
	var cfg: Dictionary = DataRegistry.get_entry(PROTOTYPE_STAGES_KEY, stage_id)
	if not cfg.is_empty():
		return cfg
	return DataRegistry.get_entry(CANONICAL_STAGES_KEY, stage_id)


## 该关卡 id 是否可取到配置。
static func has_stage(stage_id: String) -> bool:
	return not load_stage_config(stage_id).is_empty()


## 解析 --scene=<name> 用户参数（Godot 用户参数位于 -- 之后）。
## 缺省为 battle：双击 EXE 不带任何参数即进入可玩演示。
static func parse_scene_arg() -> String:
	var args := OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--scene="):
			return arg.substr("--scene=".length()).strip_edges()
	# 兼容直接传 --scene <name> 的形式
	for i: int in range(args.size()):
		if args[i] == "--scene" and i + 1 < args.size():
			return args[i + 1].strip_edges()
	return SCENE_BATTLE


## 解析 --stage=<stageId> 用户参数。返回空串表示未指定。
## 注意：本函数**只做解析**，是否允许生效由 plan_startup() 经
## BuildMode.allows_dev_entries() 裁决。
static func parse_stage_arg() -> String:
	var args := OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with(ARG_STAGE_PREFIX):
			return arg.substr(ARG_STAGE_PREFIX.length()).strip_edges()
	for i: int in range(args.size()):
		if args[i] == "--stage" and i + 1 < args.size():
			return args[i + 1].strip_edges()
	return ""
