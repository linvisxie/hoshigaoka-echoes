## BattleScene — P0.3 战斗场景（可视化 + 键鼠操作 + 完整一局）。
##
## 严格分层的表现层（L3 Presentation）：只读取 BattleSession / StageRuntime 的状态并绘制，
## **不含任何战斗规则**；部署合法性、AP 扣费、撤退、再部署冷却、阻挡、伤害、Wave 与胜负
## 全部由 domain/battle 负责。表现层只做两件事——显示状态、把玩家输入转发成领域层调用。
##
## P0.3 键鼠操作（V2.1.4 D-补充 / D-25 / J2 / J4）：
##   - 底部角色卡：费用、可部署 / 已在场 / 再部署倒计时
##   - 点击角色卡 或 数字键 1：选择 / 取消选择
##   - 左键点格部署；右键或 Esc 取消选择
##   - 点击场上角色 → 打开操作面板（显示角色信息与「撤退」按钮）
##   - 点击撤退 或 按 R：主动撤退（合法性、退款与冷却全部由领域层裁决）
##   - Space：暂停 / 继续（V2.1.4 D-35）
##   - 战斗结束：结果界面（胜负 / 核心 HP / 击杀 / 漏怪）+ 重新挑战 / 退出战斗
##
## 渲染缩放（V2.1.4 明文）：tileSizePx=192 是 **1920×1080 参考画布**下的参数。
## 切换到 720p / 2K / 4K / UI 缩放时，**仅同比缩放画布转换**，
## 不改变射程、移动速度、阻挡/治疗/技能逻辑。
##
## 视觉为**临时占位图形**（色块/线段），非最终美术（正式资产见规格 J 章）。
extends Node2D

const TAG := "BattleScene"

## 路线配色（占位用；正式色板见 V2.1.4 J-二十七）
const LANE_COLORS := [
	Color(0.45, 0.47, 0.95),  # 上段
	Color(0.35, 0.62, 0.90),  # 中段
	Color(0.55, 0.40, 0.90),  # 下段
]
const CELL_COLOR := Color(0.20, 0.24, 0.38)
const CELL_BORDER := Color(0.42, 0.46, 0.68)
const CELL_DEPLOYABLE := Color(0.30, 0.85, 0.60)   # 合法部署格高亮
const CELL_INVALID := Color(0.90, 0.30, 0.30)      # 非法部署格
const CELL_HOVER := Color(0.95, 0.95, 0.40)        # 悬停描边

# ---- 射程覆盖预览（裁决 DEC-C-0003 / 第四阶段：射程提示）----
# 视觉纪律：清晰但不刺眼。本路用可辨识的暖色，相邻路用更弱的冷色，
# 两者都以低不透明度铺底，避免遮挡角色与敌人的主体。
const RANGE_TINT_OWN := Color(0.95, 0.80, 0.35, 0.13)      # 本路覆盖填充
const RANGE_TINT_ADJACENT := Color(0.45, 0.75, 0.95, 0.10) # 相邻路覆盖填充
const RANGE_EDGE_OWN := Color(0.98, 0.82, 0.38, 0.85)      # 本路边框（实线）
const RANGE_EDGE_ADJACENT := Color(0.55, 0.80, 0.98, 0.65) # 相邻路边框（虚线）

const CORE_COLOR := Color(0.88, 0.34, 0.62)
const ENEMY_COLOR := Color(0.92, 0.42, 0.38)
const ENEMY_RUNNER_COLOR := Color(0.95, 0.68, 0.30)
const ENEMY_ARMORED_COLOR := Color(0.62, 0.66, 0.74)
const CHARACTER_COLOR := Color(0.35, 0.80, 0.98)   # 已部署角色（占位）
const CHARACTER_LOST_COLOR := Color(0.40, 0.40, 0.44)
const CHARACTER_SELECTED := Color(1.0, 0.92, 0.45)
const CARD_COLOR := Color(0.10, 0.12, 0.22, 0.95)
const CARD_SELECTED_COLOR := Color(0.20, 0.55, 0.95, 0.95)
const CARD_COOLING_COLOR := Color(0.16, 0.16, 0.20, 0.95)
const ENTRY_COLOR := Color(0.30, 0.34, 0.50)
const HUD_BG := Color(0.04, 0.05, 0.09, 0.82)
const PANEL_BG := Color(0.06, 0.07, 0.13, 0.96)
const BUTTON_COLOR := Color(0.18, 0.22, 0.36)
const BUTTON_HOVER := Color(0.28, 0.36, 0.58)
const RETREAT_COLOR := Color(0.72, 0.30, 0.28)
const TEXT_COLOR := Color(0.90, 0.94, 1.0)
const DIM_TEXT := Color(0.62, 0.68, 0.82)

## 顶部 HUD 预留带高度（参考画布单位），战场排在其下方
const HUD_BAND_HEIGHT := 200.0
## 核心侧留白（以格为单位，纯渲染）
const CORE_MARGIN_TILES := 1.15
## 底部角色卡高度（参考画布单位）
const CARD_HEIGHT := 170.0
## 底部角色卡带的下边距（参考画布单位）
const CARD_BOTTOM_MARGIN := 24.0
## 底部卡片带总高 = 卡片 + 下边距。
## 战场必须排在 HUD 带与卡片带**之间**，否则下段会与角色卡重叠（P1.0 实机截图发现）。
const CARD_BAND_HEIGHT := CARD_HEIGHT + CARD_BOTTOM_MARGIN

## P0.4：底部为**多张角色卡**，每张对应一个本关可用角色；
## 卡序 = StageConfig.availableCharacters 顺序，数字键 1..N 快选。
const CARD_WIDTH := 300.0
const CARD_GAP := 16.0

## 三职业占位配色（V2.1.4 J 章允许占位图形，但必须能一眼区分职责）
const ROLE_FRONTLINE_COLOR := Color(0.35, 0.80, 0.98)   # 前线：青蓝
const ROLE_RANGED_COLOR := Color(0.98, 0.72, 0.30)       # 远程：橙黄
const ROLE_HEALER_COLOR := Color(0.45, 0.95, 0.62)       # 治疗：青绿
const HEAL_BEAM_COLOR := Color(0.55, 1.0, 0.70, 0.85)

## 同格多敌的**纯表现层**横向偏移（参考画布像素）。
## V2.1.4 允许一个阻挡者挂接多个敌人；两个敌人会停在同一接触线上而完全重叠。
## 这里只改变**绘制位置**，绝不改动逻辑坐标、射程、接触线或阻挡判定。
const OVERLAP_OFFSET_PX := 26.0

# ============================================================
#  P1.0 基础反馈参数（全部为表现层可调参数，不参与战斗判定）
# ============================================================

## 伤害数字寿命（秒）与同目标合并窗口（秒）
const DAMAGE_POP_LIFETIME := 0.75
const DAMAGE_POP_MERGE_WINDOW := 0.35
## 同屏伤害数字上限（V2.1.4：避免伤害数字遮挡敌人、预警与路线信息）
const DAMAGE_POP_LIMIT := 24
## 受击闪白时长（秒）与上限
const HIT_FLASH_SECONDS := 0.12
const HIT_FLASH_LIMIT := 32
## 敌人死亡粒子时长（秒）与上限
const DEATH_PARTICLE_LIFETIME := 0.55
const DEATH_PARTICLE_LIMIT := 24
## 部署落位动画时长（秒）
const DEPLOY_POP_LIFETIME := 0.45
## 教学卡片停留时长（秒）与同屏上限
const TUTORIAL_CARD_LIFETIME := 5.0
const TUTORIAL_CARD_LIMIT := 2
## 核心威胁脉冲距离（tile）：敌人进入核心前该距离内即开始轻微脉冲
const CORE_WARN_DISTANCE_TILES := 1.0
## 入口警示：提前量与持续时长（秒）
const LANE_WARNING_LEAD_SECONDS := 2.0
const LANE_WARNING_SECONDS := 1.8
## 入口警示向前查看的出怪条数
const WARN_LOOKAHEAD_SPAWNS := 4
## 核心受创闪烁与脉冲时长（秒）
const CORE_FLASH_SECONDS := 0.45
const CORE_PULSE_SECONDS := 0.9

## 敌人占位图形配色（V2.1.4 J 章色彩系统：危险/红用于高威胁，残响能量用紫/靛蓝）
const ENEMY_NORMAL_FILL := Color(0.52, 0.30, 0.62)     # 普通：深紫主体
const ENEMY_RUNNER_FILL := Color(0.86, 0.52, 0.22)     # 疾走：橙（速度语义）
const ENEMY_ARMORED_FILL := Color(0.40, 0.44, 0.56)    # 装甲：冷灰（重装语义）
const ENEMY_CORE_GLOW := Color(0.72, 0.45, 1.0)        # 残响核心高亮（紫蓝）
const DANGER_COLOR := Color(0.98, 0.30, 0.42)          # 危险/预警（品红-红）
const CORE_HIT_COLOR := Color(1.0, 0.45, 0.55)
const PAPER_COLOR := Color(0.92, 0.90, 0.84)           # 纸张碎片

var session: BattleSession
var grid: BattleGrid

var _viewport_size: Vector2 = Vector2(1920, 1080)
## 渲染缩放：视口 / 参考画布（等比，取较小者）
var _render_scale: float = 1.0
## 基准渲染缩放（只由视口与参考画布决定；_update_layout 每次从它重新推导）
var _base_scale: float = 1.0
## column 0 格中心的像素坐标
var _origin: Vector2 = Vector2.ZERO
var _debug_lines: Array[String] = []

## 当前选中的角色卡（部署模式）；空串 = 未选中。P0.4 起按 characterId 记录。
var _selected_card_id: String = ""
## 本关可用角色 id 列表（来自 StageConfig.availableCharacters，顺序即卡序）
var _roster: Array[String] = []
## 每张角色卡的屏幕矩形（与 _roster 同序）
var _card_rects: Array[Rect2] = []
## 治疗反馈：{targetId, until, amount} —— 纯表现层，用于播放治疗提示
var _heal_flashes: Array[Dictionary] = []

# ============================================================
#  P1.0 基础战斗反馈（V2.1.4 D-38 / K 章三十六 / 三十四 Prototype 实现范围）
#  以下全部是**纯表现层**状态：只读取领域层已结算的事件，绝不反向影响战斗规则。
# ============================================================

## 伤害数字：{kind:"enemy"|"character", targetId, text, amount, lethal, at, born}
## V2.1.4 D-38：每次攻击至少包含攻击动画 / 命中特效 / 受击闪白 / 伤害数字 / 音效。
## 纪律（V2.1.4 J 章禁止情况）：伤害数字不得遮挡敌人、预警或路线信息——
## 因此这里用**固定寿命 + 上浮 + 同目标合并**控制密度，且不覆盖格子中心。
var _damage_pops: Array[Dictionary] = []

## 受击闪白：{kind, targetId, until} —— 命中瞬间目标短暂变亮
var _hit_flashes: Array[Dictionary] = []

## 敌人死亡粒子：{lane, x, at, kind}
## V2.1.4 F-四十七：死亡分解为黑色粒子、纸张与微弱紫色残光，避免大量血液。
var _death_particles: Array[Dictionary] = []

## 核心受创反馈：核心闪烁 + 脉冲（V2.1.4：核心受创必须让玩家立即注意）
var _core_flash_until: float = 0.0
var _core_pulse_until: float = 0.0
## 核心受威胁脉冲强度（敌人进入核心前约 1 格时轻微脉冲，0 = 无威胁）
var _core_warn_level: float = 0.0

## 部署落位动画：{column, lane, at} —— 部署：格子高亮 → 落位动画 → AP 扣除
var _deploy_pops: Array[Dictionary] = []

## 新敌人首次登场提示卡：{enemyId, title, text, at}
## V2.1.4 F-二十三：特殊敌人首次出现时显示一条简短介绍，仅首次出现，后续不重复打断战斗。
var _tutorial_cards: Array[Dictionary] = []
## 已提示过的敌人种类（每局重置；同一敌种只提示一次）
var _seen_enemy_kinds: Dictionary = {}
## 已触发的关卡教学条目 id（来自 StageConfig.tutorialTriggers，每局只触发一次）
var _fired_tutorial_ids: Dictionary = {}
## 关卡教学提示队列（来自 StageConfig.tutorialTriggers，按 at 升序）
var _tutorial_queue: Array[Dictionary] = []

## 已消费的伤害事件游标（表现层自己维护；领域层只负责累积）
var _damage_cursor: int = 0
## 是否显示调试明细 HUD（默认关闭：V2.1.4 J 章禁止 HUD 大面积无功能装饰小字）
var _show_debug_hud: bool = false

## 本关的原始 StageConfig（结算奖励等非战斗字段从这里读）
var _stage_config_for_rewards: Dictionary = {}
## 结算奖励幂等标记（同一场景实例只发一次）
var _rewards_granted: bool = false
## 已播放过死亡粒子的敌人 instance_id
var _particle_done_ids: Dictionary = {}

## 危险提示：路线入口警示（V2.1.4：高威胁波次开始前，路线入口允许出现 1～2 秒警示符号）
## {lane, until, enemyId}
var _lane_warnings: Array[Dictionary] = []
## 已预告过的出怪（按出怪序号去重，避免重复闪烁）
var _warned_spawn_index: Dictionary = {}

## 当前鼠标悬停的格子（column, lane），-1 表示不在格子上
var _hover_column: int = -1
var _hover_lane: int = -1
## 悬停时的部署判定结果（缓存，避免每帧重复查询）
var _hover_deploy_ok: bool = false
var _hover_reject_reason: String = ""

## 当前被选中的**场上角色**实例 id（0 = 未选中）；选中后显示操作面板
var _selected_character_id: int = 0

## 鼠标位置（用于按钮 hover 反馈）
var _mouse_pos: Vector2 = Vector2.ZERO

## 最近一次操作反馈（用于屏幕提示）
var _feedback_text: String = ""
var _feedback_color: Color = Color(0.8, 0.85, 0.97)
var _feedback_timer: float = 0.0

## 上次已知的 Wave（用于显示「Wave 变化」提示）
var _last_wave_number: int = 0

## 自动演示开关：仅供**自动化回归**（--autoplay）。
## 它走与玩家完全一致的输入管线，但**不冒充真人操作证据**；
## 真人键鼠验收另见 docs/P0.3_验收报告.md 的实机章节。
var _autoplay := false
var _autoplay_phase := 0
var _autoplay_target_col := 2
var _autoplay_target_lane := 1
var _autoplay_shots: Array[String] = []
var _autoplay_withdraw_done := false
var _autoplay_redeploy_done := false
var _autoplay_result_captured := false

## 结果界面上的按钮（屏幕像素矩形，绘制与点击共用同一份几何）
var _relaunch_rect: Rect2 = Rect2()
var _quit_rect: Rect2 = Rect2()
var _pause_rect: Rect2 = Rect2()
var _retreat_rect: Rect2 = Rect2()



func _ready() -> void:
	_viewport_size = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080)
	)
	_update_render_scale()
	_build_battle()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			_autoplay = true
			GameLog.info(TAG, "P0.3 自动回归模式已启用（仅用于自动化，不作为真人操作证据）")
			break
	queue_redraw()


func _notification(what: int) -> void:
	# 视口尺寸变化时重算缩放与布局（窗口缩放 / 全屏切换）。
	# 注意：NOTIFICATION_RESIZED 只定义在 Control 上，Node2D 须用 Node 级别的
	# NOTIFICATION_WM_SIZE_CHANGED 与 Viewport 的 size_changed 信号。
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_on_viewport_changed()


func _on_viewport_changed() -> void:
	var vp := get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0:
		_viewport_size = vp
	_update_render_scale()
	_update_layout()
	queue_redraw()


## 计算渲染缩放（V2.1.4：仅同比缩放画布，不改逻辑）
##
## 分两级，避免重复收缩：
##   _base_scale  —— 只由「视口 / 参考画布」决定，每次重算都从头开始；
##   _render_scale —— 实际用于绘制的缩放 = _base_scale × 布局收缩系数。
## _update_layout() 可能因窗口变化被多次调用，因此收缩系数必须每次重算，
## 绝不能在上一次的 _render_scale 上继续相乘（否则会指数级缩小）。
func _update_render_scale() -> void:
	var ref_w: float = float(grid.reference_canvas_width) if grid != null else 1920.0
	var ref_h: float = float(grid.reference_canvas_height) if grid != null else 1080.0
	if ref_w <= 0.0 or ref_h <= 0.0:
		_base_scale = 1.0
	else:
		_base_scale = minf(_viewport_size.x / ref_w, _viewport_size.y / ref_h)
	_render_scale = _base_scale


## 参考画布单位 -> 当前屏幕像素
func _px(ref_px: float) -> float:
	return ref_px * _render_scale


func _build_battle() -> void:
	# P1.0：关卡不再硬编码。启动入口（bootstrap / PrototypeEntry）在切换场景前写入
	# 本次目标关卡；双击 EXE 无参数启动即落到 Prototype 演示关 p1_0_demo。
	# 取关与兜底规则全部由 PrototypeEntry 负责，本场景不复制任何启动策略。
	var requested := PrototypeEntry.consume_pending_stage_id()
	var stage_id := requested if not requested.is_empty() else PrototypeEntry.default_stage_id()
	var stage_config: Dictionary = PrototypeEntry.load_stage_config(stage_id)
	if stage_config.is_empty():
		# 目标关卡不可用时退回默认关卡，而不是黑屏（演示构建必须始终可玩）
		var fallback := PrototypeEntry.default_stage_id()
		GameLog.warn(TAG, "关卡 '%s' 不可用，退回 '%s'" % [stage_id, fallback])
		stage_id = fallback
		stage_config = PrototypeEntry.load_stage_config(stage_id)
	if stage_config.is_empty():
		GameLog.error(TAG, "找不到关卡配置：%s" % stage_id)
		return

	# P0.4 开发专用入口：仅显式开关才在**内存副本**上覆盖可用角色；
	# 正式流程（不带 --dev-roster）完全走关卡自身的解锁规则。
	# P1.0：Retail 构建下 PrototypeRoster.requested_triple() 恒为 false（见 build_mode.gd）。
	stage_config = PrototypeRoster.apply_if_requested(stage_config)
	if stage_config.has("_devRoster"):
		GameLog.warn(TAG, "已启用开发专用编队覆盖：%s（仅内存生效，未修改任何数据文件）"
			% stage_config.get("_devRoster", ""))

	var enemy_table := _build_enemy_table()
	if enemy_table.is_empty():
		GameLog.error(TAG, "enemies.json 为空或不可用")
		return

	grid = BattleGrid.from_layout(DataRegistry.get_layout())
	if not grid.is_valid():
		for e: String in grid.get_errors():
			GameLog.error(TAG, "BattleGrid 无效：%s" % e)
		return

	_update_render_scale()
	_update_layout()

	session = BattleSession.new()
	session.name = "BattleSession"
	add_child(session)
	var errs := session.setup(stage_config, enemy_table, grid, _build_character_table(), _combat_config())
	if not errs.is_empty():
		for e: String in errs:
			GameLog.error(TAG, "会话构建失败：%s" % e)
		return

	# Alpha A0.1：把成长面板注入领域层。
	# 纪律：领域层不自行读取成长数据；由表现层/应用层注入，保持 L3 分层。
	# 表为空（成长未就绪）时行为与 Prototype 固定 Lv.1 完全一致。
	var level_stats := App.level_stats_table()
	session.stage.set_character_level_stats(level_stats)
	if not level_stats.is_empty():
		var parts := PackedStringArray()
		for cid: String in level_stats.keys():
			var s: Dictionary = level_stats[cid]
			parts.append("%s HP%d/攻%d/防%d" % [
				cid, int(s.get("hp", 0)), int(s.get("attack", 0)), int(s.get("defense", 0))])
		GameLog.info(TAG, "已注入成长面板：%s" % ", ".join(parts))

	session.outcome_decided.connect(_on_outcome_decided)
	session.core_hp_changed.connect(_on_core_hp_changed)
	session.enemy_reached_core.connect(_on_enemy_reached_core)
	session.wave_changed.connect(_on_wave_changed)
	session.character_healed.connect(_on_character_healed)
	_last_wave_number = session.stage.current_wave_number()

	# 角色卡顺序 = StageConfig.availableCharacters 顺序
	_roster = session.stage.available_characters.duplicate()

	# P1.0：关卡教学条目（V2.1.4 G-九：教学触发点必须数据驱动，不得硬编码在场景脚本）
	_build_tutorial_queue(stage_config)

	# Alpha A0.1：保留原始配置，供结算奖励等非战斗字段使用
	_stage_config_for_rewards = stage_config.duplicate(true)

	GameLog.info(TAG, "%s 战斗场景就绪：stage=%s，核心 HP %d，Wave %d，计划出怪 %d，战场 3×6，渲染缩放 %.3f，可用角色 %s，教学条目 %d"
		% [App.stage_label(), stage_config.get("stageId", "?"), session.stage.core_hp_max,
			session.stage.total_wave_count(), session.stage.planned_enemy_count(), _render_scale,
			str(_roster), _tutorial_queue.size()])


## 从 StageConfig.tutorialTriggers 构建教学提示队列（按 at 升序）。
## 数据缺失时为空队列，不报错——教学提示是增强项，不是战斗前置条件。
func _build_tutorial_queue(stage_config: Dictionary) -> void:
	_tutorial_queue.clear()
	_fired_tutorial_ids.clear()
	var raw: Variant = stage_config.get("tutorialTriggers", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	for entry: Variant in (raw as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		var tid := str(e.get("id", ""))
		var text := str(e.get("text", ""))
		if tid.is_empty() or text.is_empty():
			continue
		_tutorial_queue.append({
			"id": tid,
			"text": text,
			"at": float(e.get("at", 0.0)),
		})
	_tutorial_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["at"]) < float(b["at"])
	)


## 依据当前缩放与视口，计算战场在屏幕上的位置。
##
## 布局纪律（P1.0 实机截图修正）：
##   可用垂直区间 = [HUD 带底, 屏幕底 - 卡片带]，
##   战场在该区间内**居中**，且当区间不足以容纳战场时按比例收缩，
##   从而保证「下段路线 / 部署格 / 角色 / 血条」永不与底部角色卡重叠。
func _update_layout() -> void:
	if grid == null:
		return
	# 每次布局都从基准缩放重新推导，避免收缩系数被重复累乘
	_render_scale = _base_scale
	var tile := _px(grid.tile_size_px)
	var grid_w := tile * float(grid.columns - 1)
	var core_margin := tile * CORE_MARGIN_TILES
	var total_w := core_margin + grid_w + tile * 0.5
	var board_h := _px(grid.lane_spacing_px) * float(grid.lanes - 1) + tile
	var hud_h := _px(HUD_BAND_HEIGHT)
	var card_band := _px(CARD_BAND_HEIGHT)

	var left := (_viewport_size.x - total_w) * 0.5
	var avail_top := hud_h
	var avail_h := _viewport_size.y - card_band - avail_top
	# 区间不足时按比例收缩整个战场（仅渲染，逻辑仍以 tile 计）
	if board_h > avail_h and board_h > 0.0:
		var shrink := avail_h / board_h
		shrink = clampf(shrink, 0.5, 1.0)
		_render_scale *= shrink
		tile = _px(grid.tile_size_px)
		grid_w = tile * float(grid.columns - 1)
		core_margin = tile * CORE_MARGIN_TILES
		total_w = core_margin + grid_w + tile * 0.5
		board_h = _px(grid.lane_spacing_px) * float(grid.lanes - 1) + tile
		hud_h = _px(HUD_BAND_HEIGHT)
		card_band = _px(CARD_BAND_HEIGHT)
		left = (_viewport_size.x - total_w) * 0.5
		avail_top = hud_h
		avail_h = _viewport_size.y - card_band - avail_top

	var top := avail_top + maxf(0.0, (avail_h - board_h) * 0.5)
	_origin = Vector2(left + core_margin, top + tile * 0.5)


## 从 DataRegistry 组装 { characterId -> CharacterConfig } 表
func _build_character_table() -> Dictionary:
	var table := {}
	for c: Dictionary in DataRegistry.get_domain("characters").get("characters", []):
		var id := str(c.get("id", ""))
		if not id.is_empty():
			table[id] = c
	return table


## 取 balance.combat 段（AP/伤害公式/阻挡接触线/退款/再部署等战斗公共参数）
func _combat_config() -> Dictionary:
	return DataRegistry.get_domain("balance").get("combat", {})


func _build_enemy_table() -> Dictionary:
	var table := {}
	for e: Dictionary in DataRegistry.get_domain("enemies").get("enemies", []):
		var id := str(e.get("id", ""))
		if not id.is_empty():
			table[id] = e
	return table


func _process(delta: float) -> void:
	if session == null:
		return
	var was_running := session.is_running()
	session.tick(delta)
	# 选中的角色可能已离场（撤退 / 失能）→ 关闭操作面板
	if _selected_character_id != 0 and session.stage.get_character(_selected_character_id) == null:
		_selected_character_id = 0
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
	_update_feedback(delta)
	_refresh_debug_lines()
	_layout_buttons()
	queue_redraw()
	if was_running and session.is_decided():
		GameLog.info(TAG, "战斗结束：%s" % BattleTypes.outcome_name(session.outcome))
	if _autoplay:
		_drive_autoplay()


# ============================================================
#  P1.0 基础反馈：事件消费与寿命管理（纯表现层）
# ============================================================

## 每帧更新全部反馈状态。
## 纪律：本函数**只读**领域层已结算的事件（damage_events / removals / 状态量），
## 不写回任何战斗状态，因此不会改变战斗结果（帧率与分辨率独立性不受影响）。
func _update_feedback(delta: float) -> void:
	if session == null or session.stage == null:
		return
	var s := session.stage
	var now := s.elapsed_seconds

	_consume_damage_events()
	_consume_kills()
	_check_enemy_kind_intro()
	_consume_tutorial_triggers()
	_update_danger_warnings(now)

	# 寿命推进：伤害数字 / 受击闪白 / 死亡粒子 / 部署落位
	for i: int in range(_damage_pops.size() - 1, -1, -1):
		if now - float(_damage_pops[i]["born"]) > DAMAGE_POP_LIFETIME:
			_damage_pops.remove_at(i)
	for i: int in range(_hit_flashes.size() - 1, -1, -1):
		if float(_hit_flashes[i]["until"]) <= now:
			_hit_flashes.remove_at(i)
	for i: int in range(_death_particles.size() - 1, -1, -1):
		if now - float(_death_particles[i]["at"]) > DEATH_PARTICLE_LIFETIME:
			_death_particles.remove_at(i)
	for i: int in range(_deploy_pops.size() - 1, -1, -1):
		if now - float(_deploy_pops[i]["at"]) > DEPLOY_POP_LIFETIME:
			_deploy_pops.remove_at(i)
	for i: int in range(_tutorial_cards.size() - 1, -1, -1):
		if now - float(_tutorial_cards[i]["at"]) > TUTORIAL_CARD_LIFETIME:
			_tutorial_cards.remove_at(i)
	for i: int in range(_lane_warnings.size() - 1, -1, -1):
		if float(_lane_warnings[i]["until"]) <= now:
			_lane_warnings.remove_at(i)
	for i: int in range(_heal_flashes.size() - 1, -1, -1):
		if float(_heal_flashes[i]["until"]) <= now:
			_heal_flashes.remove_at(i)


## 消费领域层的伤害事件，生成伤害数字与受击闪白。
## 同目标在极短时间内多次命中会**合并**为一条（V2.1.4：避免伤害数字遮挡战场）。
func _consume_damage_events() -> void:
	var s := session.stage
	var now := s.elapsed_seconds
	while _damage_cursor < s.damage_events.size():
		var ev: Dictionary = s.damage_events[_damage_cursor]
		_damage_cursor += 1
		var kind := str(ev.get("targetKind", ""))
		var tid := int(ev.get("targetId", 0))
		var amount := int(ev.get("amount", 0))
		if amount <= 0 or tid <= 0:
			continue
		var lethal := bool(ev.get("lethal", false))
		# 受击闪白（命中反馈的视觉通道之一）
		_hit_flashes.append({"kind": kind, "targetId": tid, "until": now + HIT_FLASH_SECONDS})
		# 伤害数字：同目标已有未消散的一条时累加，而不是新开一条
		var merged := false
		for i: int in range(_damage_pops.size() - 1, -1, -1):
			var p: Dictionary = _damage_pops[i]
			if str(p["kind"]) == kind and int(p["targetId"]) == tid \
					and now - float(p["born"]) <= DAMAGE_POP_MERGE_WINDOW:
				p["amount"] = int(p["amount"]) + amount
				p["text"] = str(p["amount"])
				p["born"] = now
				p["lethal"] = bool(p["lethal"]) or lethal
				merged = true
				break
		if not merged:
			_damage_pops.append({
				"kind": kind, "targetId": tid, "amount": amount,
				"text": str(amount), "lethal": lethal, "born": now,
			})
	# 密度上限：超出的丢弃最旧的（保证同屏不刷屏）
	while _damage_pops.size() > DAMAGE_POP_LIMIT:
		_damage_pops.remove_at(0)
	while _hit_flashes.size() > HIT_FLASH_LIMIT:
		_hit_flashes.remove_at(0)


## 消费离场记录，为被击败的敌人生成死亡粒子。
## 只处理 KILLED（漏怪与撤退不是「被打散」，不播死亡粒子）。
func _consume_kills() -> void:
	var s := session.stage
	for r: Dictionary in s.removals:
		if int(r.get("kind", -1)) != StageRuntime.Removal.KILLED:
			continue
		if str(r.get("entity", "")) != "enemy":
			continue
		var eid := int(r.get("entityId", -1))
		if eid <= 0 or _particle_done_ids.has(eid):
			continue
		_particle_done_ids[eid] = true
		_death_particles.append({
			"lane": int(r.get("lane", 0)),
			"x": float(r.get("x", BattleGrid.CORE_X)),
			"at": s.elapsed_seconds,
			"enemyId": str(r.get("enemyId", "")),
		})
	while _death_particles.size() > DEATH_PARTICLE_LIMIT:
		_death_particles.remove_at(0)


## 触发关卡教学条目（来自 StageConfig.tutorialTriggers）。
## 到点即出卡片；每条只触发一次（V2.1.4 G-五：每关只首次教学 1～2 个新概念）。
func _consume_tutorial_triggers() -> void:
	if _tutorial_queue.is_empty():
		return
	var now := session.stage.elapsed_seconds
	for t: Dictionary in _tutorial_queue:
		var tid := str(t["id"])
		if _fired_tutorial_ids.has(tid):
			continue
		if now < float(t["at"]):
			continue
		_fired_tutorial_ids[tid] = true
		_push_tutorial_card("", "", str(t["text"]))


## 敌人种类首次登场提示（V2.1.4 F-二十三）。
## 文本取自 enemies.json 的 name / _spec 语义，**不在此处硬编码数值**。
func _check_enemy_kind_intro() -> void:
	for e: EnemyRuntime in session.stage.enemies:
		if _seen_enemy_kinds.has(e.enemy_id):
			continue
		_seen_enemy_kinds[e.enemy_id] = true
		var cfg: Dictionary = session.stage._enemy_configs.get(e.enemy_id, {})
		var title := str(cfg.get("name", e.enemy_id))
		_push_tutorial_card(e.enemy_id, title, _enemy_intro_text(e.enemy_id, cfg))


## 敌人机制一句话介绍（V2.1.4 F-二十三 要求「简短介绍」）。
## 数值不写在这里——只描述**机制**，具体面板由 enemies.json 承载并在敌人信息面板显示。
func _enemy_intro_text(enemy_id: String, cfg: Dictionary) -> String:
	var speed := float(cfg.get("moveSpeed", 0.0))
	var defense := int(cfg.get("defense", 0))
	match enemy_id:
		"echo_runner":
			return "移动速度很快，请尽早处理。"
		"echo_armored":
			return "防御极高，物理攻击收效有限，需要前线阻挡后持续输出。"
		"echo_normal":
			return "基础敌人：没有特殊能力，用于学习阻挡与输出节奏。"
		_:
			# 未知敌种：只报可读的机制线索，不编造数值
			if defense >= 50:
				return "高防御单位，注意输出效率。"
			if speed >= 0.9:
				return "移动速度较快，注意空线。"
			return "注意其推进路线。"


func _push_tutorial_card(enemy_id: String, title: String, text: String) -> void:
	_tutorial_cards.append({
		"enemyId": enemy_id,
		"title": title,
		"text": text,
		"at": session.stage.elapsed_seconds,
	})
	while _tutorial_cards.size() > TUTORIAL_CARD_LIMIT:
		_tutorial_cards.remove_at(0)


## 危险提示：敌人接近核心时核心 UI 脉冲；高威胁敌人出怪前在路线入口给警示符号。
## V2.1.4：敌人进入核心前约 1 格，核心 UI 开始轻微脉冲；
##         高威胁波次开始前，路线入口允许出现 1～2 秒的警示符号。
func _update_danger_warnings(now: float) -> void:
	var s := session.stage
	# ① 核心威胁：任一活跃敌人的 logical_x 已进入核心前 WARN_DISTANCE_TILES 内
	var worst := 0.0
	for e: EnemyRuntime in s.enemies:
		if not e.is_active():
			continue
		var d := e.logical_x - BattleGrid.CORE_X
		if d <= CORE_WARN_DISTANCE_TILES:
			worst = maxf(worst, 1.0 - clampf(d / CORE_WARN_DISTANCE_TILES, 0.0, 1.0))
	_core_warn_level = worst
	# ② 入口警示：对尚未生成的高威胁敌人提前警示（只警示一次）
	var plan: Array[Dictionary] = s._spawn_plan
	var cursor := s._spawn_cursor
	for i: int in range(cursor, mini(cursor + WARN_LOOKAHEAD_SPAWNS, plan.size())):
		if _warned_spawn_index.has(i):
			continue
		var entry: Dictionary = plan[i]
		var lead := float(entry["time"]) - now
		if lead < 0.0 or lead > LANE_WARNING_LEAD_SECONDS:
			continue
		var enemy_id := str(entry["enemy"])
		if not _is_high_threat(enemy_id):
			continue
		_warned_spawn_index[i] = true
		_lane_warnings.append({
			"lane": int(entry["lane"]),
			"until": now + LANE_WARNING_SECONDS,
			"enemyId": enemy_id,
		})


## 是否属于「需要入口预警」的高威胁敌人。
## 判定依据是**数据标签**（enemies.json 的 tags / weightClass），不是硬编码 ID 名单。
func _is_high_threat(enemy_id: String) -> bool:
	var cfg: Dictionary = session.stage._enemy_configs.get(enemy_id, {})
	var tags: Array = cfg.get("tags", [])
	if tags.has("FAST") or tags.has("ARMORED"):
		return true
	return str(cfg.get("weightClass", "")) == "HEAVY"


# ============================================================
#  键鼠输入（V2.1.4 J2 / D-补充）
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		# 结果界面：只用界面按钮，键盘不参与（避免误触退出）
		if session.is_decided():
			return
		if k == KEY_ESCAPE:
			_cancel_selection()
			return
		if k == KEY_SPACE:
			_toggle_pause()
			return
		if k == KEY_R:
			_request_retreat_selected()
			return
		# F1：调试明细开关（默认关闭；V2.1.4 J 章要求战斗 HUD 保持简洁）
		if k == KEY_F1:
			_show_debug_hud = not _show_debug_hud
			_show_feedback("调试明细：%s" % ("开" if _show_debug_hud else "关"),
				Color(0.7, 0.78, 0.92))
			return
		# C：打开角色培养界面（Alpha A0.1）。正式流程由校园 Hub 进入（A0.7），
		# 在 Hub 落地前用该快捷键提供可达路径，便于实机验收。
		if k == KEY_C:
			GameLog.info(TAG, "玩家打开角色培养界面")
			SceneRouter.go_to("character")
			return
		# 数字键 1..N 快选角色卡（规格 J2：数字 1～6 快选；N = 本关可用角色数）
		if k >= KEY_1 and k <= KEY_6:
			var slot := k - KEY_1
			if slot < _roster.size():
				_toggle_card_selection(_roster[slot])
			return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_selection()


## 鼠标移动：更新悬停格子与部署合法性反馈
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = (event as InputEventMouseMotion).position
		_update_hover(_mouse_pos)


## 暂停 / 继续（V2.1.4 D-35）
func _toggle_pause() -> void:
	if session == null or session.is_decided():
		return
	var now := session.toggle_pause()
	_show_feedback("已暂停（Space 继续）" if now else "已继续",
		Color(0.95, 0.85, 0.45) if now else Color(0.6, 0.9, 1.0))


## 选中 / 取消选中某张角色卡（P0.4：按 characterId）
func _toggle_card_selection(character_id: String = "") -> void:
	if session == null or session.is_decided():
		return
	if session.is_paused():
		_show_feedback("暂停中：先按 Space 继续", Color(0.95, 0.85, 0.45))
		return
	var cid := character_id
	if cid.is_empty() and not _roster.is_empty():
		cid = _roster[0]
	if cid.is_empty():
		return

	# 同一张卡再点一次 = 取消
	if _selected_card_id == cid:
		_selected_card_id = ""
		_show_feedback("已取消选择", Color(0.7, 0.75, 0.9))
		return

	# 该角色已在场时不得再选（同一名角色不能同时部署多个实体）
	if session.stage.get_character_by_id(cid) != null:
		_show_feedback("%s 已在场上" % _display_name_of(cid), Color(1.0, 0.6, 0.4))
		_selected_card_id = ""
		return

	_selected_card_id = cid
	_selected_character_id = 0
	var cfg: Dictionary = session.stage._character_configs.get(cid, {})
	_show_feedback("已选择 %s（%s，%d AP）— 左键点击合法格部署，右键/Esc 取消"
		% [_display_name_of(cid), _role_label(str(cfg.get("behavior", ""))),
			int(cfg.get("deployCost", 0))],
		Color(0.5, 0.85, 1.0))


func _cancel_selection() -> void:
	var had := not _selected_card_id.is_empty() or _selected_character_id != 0
	_selected_card_id = ""
	_selected_character_id = 0
	if had:
		_show_feedback("已取消选择", Color(0.7, 0.75, 0.9))


## 角色显示名（从配置表取，不在场景里硬编码）
func _display_name_of(character_id: String) -> String:
	if session == null or session.stage == null:
		return character_id
	var cfg: Dictionary = session.stage._character_configs.get(character_id, {})
	return str(cfg.get("name", character_id))


## 行为 -> 中文职责标签（数据来源是 characters.json 的 behavior）
func _role_label(behavior: String) -> String:
	match behavior:
		"FRONTLINE":
			return "前线"
		"RANGED":
			return "远程"
		"HEALER":
			return "治疗"
		_:
			return "未知"


## 主动撤退当前选中的场上角色（V2.1.4 D-9）
func _request_retreat_selected() -> void:
	if session == null or session.is_decided():
		return
	if _selected_character_id == 0:
		_show_feedback("先点击场上的角色，再选择撤退", Color(1.0, 0.75, 0.4))
		return
	var inst := session.stage.get_character(_selected_character_id)
	var name_text := inst.display_name if inst != null else "该角色"
	# 合法性 / 退款 / 冷却全部由领域层裁决，UI 只转发请求
	var r := session.withdraw_character(_selected_character_id)
	if r.ok:
		_selected_character_id = 0
		_show_feedback("%s 已撤退：返还 %d AP，再部署冷却 %.0f 秒"
			% [name_text, r.refund_granted, r.cooldown], Color(0.55, 0.95, 0.7))
		# 实机验收需要可追溯的撤退记录（与部署日志对称）
		GameLog.info(TAG, "玩家撤退 %s（返还 %d AP，再部署冷却 %.0f 秒）"
			% [name_text, r.refund_granted, r.cooldown])
	else:
		_show_feedback("撤退失败：%s" % r.reason_text(), Color(1.0, 0.45, 0.4))


func _handle_left_click(pos: Vector2) -> void:
	if session == null:
		return

	# 战斗结束：只处理结果界面上的按钮
	if session.is_decided():
		_handle_result_click(pos)
		return

	# 暂停按钮
	if _pause_rect.has_point(pos):
		_toggle_pause()
		return
	# 暂停中只允许继续
	if session.is_paused():
		_show_feedback("暂停中：点击右上角「继续」或按 Space", Color(0.95, 0.85, 0.45))
		return

	# 操作面板上的撤退按钮
	if _selected_character_id != 0 and _retreat_rect.has_point(pos):
		_request_retreat_selected()
		return

	# 点击角色卡（P0.4：多张卡，按命中矩形定位到具体角色）
	for i: int in range(_card_rects.size()):
		if _card_rects[i].has_point(pos):
			if i < _roster.size():
				_toggle_card_selection(_roster[i])
			return

	# 先判断是否点到了场上的某个角色 → 打开操作面板
	var hit := _character_at_screen(pos)
	if hit != null:
		_selected_card_id = ""
		_selected_character_id = hit.instance_id
		_show_feedback("已选中 %s — 可点击「撤退」或按 R" % hit.display_name,
			Color(1.0, 0.92, 0.45))
		return

	# 否则按部署处理
	if _selected_card_id.is_empty():
		_selected_character_id = 0
		return
	# 点击位置即目标位置：优先由点击坐标换算格子，
	# 仅当坐标不在任何格上时退回当前悬停格。
	var cell := _screen_to_cell(pos)
	var column: int = int(cell.get("column", -1))
	var lane: int = int(cell.get("lane", -1))
	if column < 0 or lane < 0:
		column = _hover_column
		lane = _hover_lane
	if column < 0 or lane < 0:
		_show_feedback("请点击战场内的部署格", Color(1.0, 0.6, 0.4))
		return
	# 部署合法性与扣费全部由领域层裁决，UI 只转发请求
	var result := session.deploy_character(_selected_card_id, column, lane)
	if result.ok:
		_selected_card_id = ""
		# 部署反馈（V2.1.4 三十四：格子高亮 → 落位动画 → AP 扣除）
		_deploy_pops.append({
			"column": column, "lane": lane, "at": session.stage.elapsed_seconds,
		})
		_show_feedback("部署成功：%s（-%d AP）" % [result.character.display_name, result.cost],
			Color(0.4, 1.0, 0.6))
		GameLog.info(TAG, "玩家部署 %s 于 (col%d, lane%d)"
			% [result.character.display_name, column, lane])
	else:
		_show_feedback("部署失败：%s" % result.reason_text(), Color(1.0, 0.45, 0.4))


## 结果界面按钮：重新挑战 / 退出战斗
func _handle_result_click(pos: Vector2) -> void:
	if _relaunch_rect.has_point(pos):
		GameLog.info(TAG, "玩家选择重新挑战")
		get_tree().reload_current_scene()
		return
	if _quit_rect.has_point(pos):
		GameLog.info(TAG, "玩家选择退出战斗")
		get_tree().quit()


## 命中测试：屏幕坐标是否落在某个在场角色身上
func _character_at_screen(pos: Vector2) -> CharacterRuntime:
	if session == null or grid == null:
		return null
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)
	var hit_r := tile * 0.34
	for c: CharacterRuntime in session.stage.characters:
		if c.is_incapacitated():
			continue
		var center := Vector2(_origin.x + tile * float(c.column),
			_origin.y + float(c.lane) * spacing)
		if center.distance_to(pos) <= hit_r:
			return c
	return null


func _update_hover(pos: Vector2) -> void:
	_hover_column = -1
	_hover_lane = -1
	_hover_deploy_ok = false
	_hover_reject_reason = ""
	if session == null or grid == null:
		return

	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)

	for lane: int in range(grid.lanes):
		var lane_y := _origin.y + float(lane) * spacing
		if absf(pos.y - lane_y) > tile * 0.5:
			continue
		for column: int in range(grid.columns):
			var cell_x := _origin.x + tile * float(column)
			if absf(pos.x - cell_x) > tile * 0.5:
				continue
			_hover_column = column
			_hover_lane = lane
			if not _selected_card_id.is_empty() and session.is_running() and not session.is_paused():
				var r := session.query_deploy(_selected_card_id, column, lane)
				_hover_deploy_ok = r.ok
				_hover_reject_reason = r.reason_text()
			return


# ============================================================
#  按钮布局（绘制与命中共用）
# ============================================================

func _layout_buttons() -> void:
	# 角色卡条：横向排列，数量 = 本关可用角色数（P0.4 起可能多于 1）
	var card_w := _px(CARD_WIDTH)
	var card_h := _px(CARD_HEIGHT)
	var card_gap := _px(CARD_GAP)
	var start_x := _px(24.0)
	var card_y := _viewport_size.y - card_h - _px(24.0)
	_card_rects.clear()
	for i: int in range(_roster.size()):
		_card_rects.append(Rect2(
			Vector2(start_x + float(i) * (card_w + card_gap), card_y),
			Vector2(card_w, card_h)
		))
	# 右上角暂停 / 继续
	var pw := _px(120.0)
	var ph := _px(46.0)
	_pause_rect = Rect2(Vector2(_viewport_size.x - pw - _px(24.0), _px(20.0)),
		Vector2(pw, ph))
	# 操作面板（选中角色时）的撤退按钮
	if _selected_character_id != 0:
		var panel_w := _px(300.0)
		var panel_h := _px(210.0)
		var panel_pos := Vector2(_viewport_size.x - panel_w - _px(24.0),
			_viewport_size.y - panel_h - _px(24.0))
		_retreat_rect = Rect2(
			panel_pos + Vector2(_px(20.0), panel_h - _px(72.0)),
			Vector2(panel_w - _px(40.0), _px(52.0))
		)
	else:
		_retreat_rect = Rect2()
	# 结果界面按钮
	if session != null and session.is_decided():
		var bw := _px(240.0)
		var bh := _px(64.0)
		var gap := _px(32.0)
		var total := bw * 2.0 + gap
		var bx := (_viewport_size.x - total) * 0.5
		var by := _viewport_size.y * 0.5 + _px(160.0)
		_relaunch_rect = Rect2(Vector2(bx, by), Vector2(bw, bh))
		_quit_rect = Rect2(Vector2(bx + bw + gap, by), Vector2(bw, bh))


## P0.3 自动回归：按阶段注入真实输入事件，覆盖「部署 → 撤退 → 冷却 → 换线重部署 → 胜负」。
## 所有点击都走 Input.parse_input_event（与玩家一致的输入管线）。
## 该开关仅用于自动化回归，**不作为真人操作证据**。
func _drive_autoplay() -> void:
	match _autoplay_phase:
		0:
			if _feedback_timer <= 0.0 and elapsed_since_start() > 0.5:
				_ap_hover(_autoplay_target_col, _autoplay_target_lane)
				_ap_capture('01_before_deploy')
				_click_card()
				_ap_capture('02_card_selected')
				_autoplay_phase = 1
		1:
			_ap_hover(_autoplay_target_col, _autoplay_target_lane)
			_click_cell(_autoplay_target_col, _autoplay_target_lane)
			_ap_capture('03_deployed')
			_autoplay_phase = 2
		2:
			var lead := _lead_character()
			if lead != null and lead.blocking_enemy_ids.size() > 0:
				_ap_capture('04_blocking')
				_autoplay_phase = 3
			elif session.stage.enemies.size() > 0:
				_ap_capture('04_blocking_missed')
				_autoplay_phase = 3
		3:
			var lead := _lead_character()
			if lead != null and session.stage.enemies_killed >= 1:
				# 点击场上角色打开操作面板
				_click_cell(lead.column, lead.lane)
				_ap_capture('05_character_panel')
				_autoplay_phase = 4
			elif session.is_decided():
				_autoplay_phase = 7
		4:
			if _selected_character_id != 0:
				_request_retreat_selected()   # 玩家点击撤退按钮的终点处理
				_ap_capture('06_after_withdraw')
				_autoplay_withdraw_done = true
				_autoplay_phase = 5
			elif session.is_decided():
				_autoplay_phase = 7
		5:
			# 等冷却结束（1-1 只有 35 秒，这里主要用于演示倒计时与准入规则）
			var lead_id := _roster[0] if not _roster.is_empty() else ""
			if not _autoplay_redeploy_done and not lead_id.is_empty() \
					and session.get_redeploy_remaining(lead_id) <= 0.0:
				_click_card()
				_click_cell(_autoplay_target_col + 1, _autoplay_target_lane)
				_ap_capture('07_redeployed')
				_autoplay_redeploy_done = true
			if session.is_decided():
				_autoplay_phase = 7
			elif elapsed_since_start() > 60.0:
				_autoplay_phase = 7
		6:
			pass
		7:
			if session.is_decided():
				_ap_capture('08_result')
				_autoplay_result_captured = true
				var dbg: Dictionary = session.to_debug_dict()
				print('')
				print('=== P0.3 自动回归汇总 ===')
				print('  结果: %s  核心: %s/%s  AP: %s/%s' % [
					dbg.get('outcome'), dbg.get('coreHp'), dbg.get('coreHpMax'),
					dbg.get('ap'), dbg.get('apMax')])
				print('  Wave: %s/%s  击杀: %s  漏怪: %s  失能: %s  撤退: %s' % [
					dbg.get('wave'), dbg.get('waveTotal'), dbg.get('enemiesKilled'),
					dbg.get('reachedCore'), dbg.get('charactersLost'), dbg.get('retreatCount')])
				print('  已部署: %s（历史实例 %s）  逻辑时间: %s' % [
					dbg.get('deployed'), dbg.get('deployedTotal'), dbg.get('elapsed')])
				_autoplay_phase = 8


## 本关第一位已部署角色（autoplay 与调试用；无则 null）
func _lead_character() -> CharacterRuntime:
	if _roster.is_empty() or session == null:
		return null
	return session.stage.get_character_by_id(_roster[0])


## 距场景就绪的近似秒数（用于等一拍再点）
func elapsed_since_start() -> float:
	return session.stage.elapsed_seconds if session != null and session.stage != null else 0.0


func _ap_hover(column: int, lane: int) -> void:
	var p := _cell_screen_pos(column, lane)
	var move := InputEventMouseMotion.new()
	move.position = p
	move.global_position = p
	Input.parse_input_event(move)
	GameLog.info(TAG, '[autoplay] 悬停格 (col%d, lane%d) 窗口坐标 %s' % [column, lane, p])


func _click_card() -> void:
	if _card_rects.is_empty():
		return
	_send_click_at(_card_rects[0].position + _card_rects[0].size * 0.5)
	GameLog.info(TAG, '[autoplay] 点击角色卡 1')


func _click_cell(column: int, lane: int) -> void:
	var p := _cell_screen_pos(column, lane)
	_send_click_at(p)
	GameLog.info(TAG, '[autoplay] 点击格 (col%d, lane%d) at %s' % [column, lane, p])


## 注入一次完整的真实鼠标左键点击（按下 + 抬起），走引擎输入管线
func _send_click_at(p: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = p
	move.global_position = p
	Input.parse_input_event(move)
	var press := InputEventMouseButton.new()
	press.position = p
	press.global_position = p
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.position = p
	release.global_position = p
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)


## 显示屏幕反馈文案（部署成功/失败原因等）
func _show_feedback(text: String, color: Color) -> void:
	_feedback_text = text
	_feedback_color = color
	_feedback_timer = 3.0


## 截取当前画面（autoplay 回归用）。
## P0.3 修复帧序问题：必须等**本帧绘制完成**后再取图，
## 否则拿到的是上一帧的 viewport 内容（P0.2 的 02_card_selected 就是这样错位的）。
## 实现方式：先记录待截图名，等到渲染完成通知（RenderingServer frame_post_draw）再取图。
var _pending_capture: String = ""

func _ap_capture(shot_name: String) -> void:
	_pending_capture = shot_name
	var cb := func() -> void:
		if _pending_capture.is_empty():
			return
		var name := _pending_capture
		_pending_capture = ""
		_do_capture(name)
	RenderingServer.frame_post_draw.connect(cb, CONNECT_ONE_SHOT)


func _do_capture(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute('user://p0.3_shots')
	var path := 'user://p0.3_shots/%s.png' % shot_name
	var err := img.save_png(path)
	GameLog.info(TAG, '[autoplay] 截图 %s（err=%d）'
		% [ProjectSettings.globalize_path(path), err])


## 格坐标 -> 屏幕像素（autoplay 注入/点击使用；与 _draw_board 同一换算）
func _cell_screen_pos(column: int, lane: int) -> Vector2:
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)
	return Vector2(_origin.x + tile * float(column), _origin.y + float(lane) * spacing)


func _screen_to_cell(pos: Vector2) -> Dictionary:
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)
	for lane: int in range(grid.lanes):
		var lane_y := _origin.y + float(lane) * spacing
		if absf(pos.y - lane_y) > tile * 0.5:
			continue
		for column: int in range(grid.columns):
			var cell_x := _origin.x + tile * float(column)
			if absf(pos.x - cell_x) > tile * 0.5:
				continue
			return {"column": column, "lane": lane}
	return {}


## 无头模式下的加速推进（不改变任何战斗规则，只替代 _process 的时间来源）。
func run_headless_until_decided(max_seconds: float = 600.0) -> int:
	if session == null:
		return BattleTypes.Outcome.RUNNING
	var step := 1.0 / 60.0
	var t := 0.0
	while session.is_running() and t < max_seconds:
		session.tick(step)
		t += step
	return session.outcome


# ============================================================
#  绘制
# ============================================================

func _draw() -> void:
	if grid == null or session == null:
		return
	_draw_hud_backdrop()
	_draw_board()
	_draw_lane_warnings()
	_draw_core()
	_draw_deploy_feedback()
	_draw_deploy_pops()
	_draw_characters()
	_draw_enemies()
	_draw_death_particles()
	_draw_damage_pops()
	_draw_hud_text()
	_draw_wave_banner()
	_draw_character_card()
	_draw_character_panel()
	_draw_tutorial_cards()
	_draw_feedback()
	if session.is_paused():
		_draw_pause_overlay()
	if session.is_decided():
		_draw_result_overlay()


func _draw_hud_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(_viewport_size.x, _px(HUD_BAND_HEIGHT))), HUD_BG, true)


## 三条路线 + 18 个部署格
func _draw_board() -> void:
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)
	var cell := Vector2(tile * 0.86, tile * 0.86)
	var core_margin := tile * CORE_MARGIN_TILES
	var grid_right := _origin.x + tile * float(grid.columns - 1) + cell.x * 0.5
	var font := ThemeDB.fallback_font

	for lane: int in range(grid.lanes):
		var lane_y := _origin.y + float(lane) * spacing
		var lane_color: Color = LANE_COLORS[lane % LANE_COLORS.size()]

		# 路线底带
		var band_from := Vector2(_origin.x - core_margin, lane_y - cell.y * 0.5)
		draw_rect(
			Rect2(band_from, Vector2(grid_right, lane_y + cell.y * 0.5) - band_from),
			Color(lane_color.r, lane_color.g, lane_color.b, 0.10), true
		)

		# 入口标记（column 5 右侧之外）
		var entry_x := _origin.x + tile * float(grid.columns - 1) + tile * 0.62
		draw_line(Vector2(entry_x, lane_y - tile * 0.34), Vector2(entry_x, lane_y + tile * 0.34),
			ENTRY_COLOR, 3.0)
		draw_string(font, Vector2(entry_x - _px(14.0), lane_y - tile * 0.42), "入口",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(15.0)), ENTRY_COLOR)

		# 18 个部署格
		for column: int in range(grid.columns):
			var center := Vector2(_origin.x + tile * float(column), lane_y)
			var rect := Rect2(center - cell * 0.5, cell)
			draw_rect(rect, CELL_COLOR, true)
			draw_rect(rect, CELL_BORDER, false, 2.0)

		# 路线名（贴屏幕左侧，不随战场偏移）
		draw_string(font, Vector2(_px(16.0), lane_y + _px(8.0)),
			BattleTypes.lane_name(lane), HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_px(22.0)), lane_color)


## 残响锚点（三条路线共用一个核心，V2.1.4 D-5 / 3A）
func _draw_core() -> void:
	var spacing := _px(grid.lane_spacing_px)
	var tile := _px(grid.tile_size_px)
	var mid_y := _origin.y + spacing  # lane 1 中线
	var core_x := _origin.x - tile * 0.62
	var ratio := 1.0
	if session.stage.core_hp_max > 0:
		ratio = float(session.stage.core_hp) / float(session.stage.core_hp_max)

	# 核心主体
	var now := _now()
	# 受创闪烁：命中瞬间整条核心变亮（V2.1.4：核心受创必须让玩家立即注意）
	var flash_k := 0.0
	if now < _core_flash_until:
		flash_k = (_core_flash_until - now) / CORE_FLASH_SECONDS
	# 威胁脉冲：敌人接近核心时的低频呼吸（低强度，不刺眼）
	var warn := 0.0
	if _core_warn_level > 0.0 and session.is_running() and not session.is_paused():
		warn = _core_warn_level * (0.5 + 0.5 * sin(now * 7.0))
	var body_color := CORE_COLOR.lerp(CORE_HIT_COLOR, clampf(flash_k, 0.0, 1.0))
	if warn > 0.0:
		body_color = body_color.lerp(DANGER_COLOR, warn * 0.45)
	draw_circle(Vector2(core_x, mid_y), tile * 0.20, body_color)
	var ring_w := 3.0 + 4.0 * flash_k + 3.0 * warn
	draw_circle(Vector2(core_x, mid_y), tile * 0.20 + tile * 0.06 * ratio,
		Color(body_color.r, body_color.g, body_color.b, 0.28 + 0.5 * flash_k + 0.3 * warn),
		false, ring_w)
	# 脉冲外环（核心受创时扩散一次）
	if now < _core_pulse_until:
		var pk := 1.0 - (_core_pulse_until - now) / CORE_PULSE_SECONDS
		draw_circle(Vector2(core_x, mid_y), tile * (0.20 + 0.55 * pk),
			Color(CORE_HIT_COLOR.r, CORE_HIT_COLOR.g, CORE_HIT_COLOR.b, 0.55 * (1.0 - pk)),
			false, 4.0)

	# 竖向 HP 条（贯通三路）
	var bar_w := _px(12.0)
	var bar_h := float(grid.lanes - 1) * spacing + _px(60.0)
	var bar_pos := Vector2(core_x - _px(40.0), mid_y - bar_h * 0.5)
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.15, 0.15, 0.20), true)
	draw_rect(Rect2(Vector2(bar_pos.x, bar_pos.y + bar_h * (1.0 - ratio)),
		Vector2(bar_w, bar_h * ratio)), CORE_COLOR, true)

	# 连到三条路线的短线（强调共享）
	for lane: int in range(grid.lanes):
		var ly := _origin.y + float(lane) * spacing
		draw_line(Vector2(core_x + tile * 0.20, ly), Vector2(_origin.x - tile * 0.45, ly),
			Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.55), 2.0)

	draw_string(ThemeDB.fallback_font,
		Vector2(core_x - _px(40.0), mid_y + float(grid.lanes - 1) * spacing * 0.5 + _px(46.0)),
		"残响锚点", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(15.0)), CORE_COLOR)


## 已部署角色（占位图形）。
## P0.4：**必须能一眼区分前线 / 远程 / 治疗**（本轮指令 六）。
##   前线 = 菱形（承伤与阻挡）
##   远程 = 指向入口的三角（输出方向一目了然）
##   治疗 = 十字（医疗语义）
## 颜色同样按职责区分；选中时统一叠白描边。
func _draw_characters() -> void:
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)
	for c: CharacterRuntime in session.stage.characters:
		var px_x := _origin.x + tile * float(c.column)
		var px_y := _origin.y + float(c.lane) * spacing
		var size := tile * 0.44
		var half := size * 0.5
		var selected := c.instance_id == _selected_character_id

		var role_color := _role_color(c)
		var color := role_color if not c.is_incapacitated() else CHARACTER_LOST_COLOR
		if selected:
			color = color.lerp(CHARACTER_SELECTED, 0.45)
		# 受击闪白（V2.1.4 D-38：每次攻击必须包含受击闪白或受击动画）
		var char_hit_k := _hit_flash_k("character", c.instance_id)
		if char_hit_k > 0.0:
			color = color.lerp(Color(1, 1, 1, 1), 0.75 * char_hit_k)
		var edge := Color(1, 1, 1, 0.9) if selected else Color(1, 1, 1, 0.6)
		var edge_w := 2.5 if selected else 1.5

		match c.behavior:
			CharacterRuntime.Behavior.RANGED:
				# 三角形，尖端朝入口方向（右），表示远程输出方向
				var tri := PackedVector2Array([
					Vector2(px_x + half, px_y),
					Vector2(px_x - half * 0.75, px_y - half),
					Vector2(px_x - half * 0.75, px_y + half),
				])
				draw_colored_polygon(tri, color)
				draw_polyline(tri + PackedVector2Array([tri[0]]), edge, edge_w)
			CharacterRuntime.Behavior.HEALER:
				# 十字（医疗语义）
				var arm := half * 0.42
				var cross := PackedVector2Array([
					Vector2(px_x - arm, px_y - half), Vector2(px_x + arm, px_y - half),
					Vector2(px_x + arm, px_y - arm), Vector2(px_x + half, px_y - arm),
					Vector2(px_x + half, px_y + arm), Vector2(px_x + arm, px_y + arm),
					Vector2(px_x + arm, px_y + half), Vector2(px_x - arm, px_y + half),
					Vector2(px_x - arm, px_y + arm), Vector2(px_x - half, px_y + arm),
					Vector2(px_x - half, px_y - arm), Vector2(px_x - arm, px_y - arm),
				])
				draw_colored_polygon(cross, color)
				draw_polyline(cross + PackedVector2Array([cross[0]]), edge, edge_w)
			_:
				# 前线：菱形（P0.2 起沿用的占位形状）
				var pts := PackedVector2Array([
					Vector2(px_x, px_y - half),
					Vector2(px_x + half, px_y),
					Vector2(px_x, px_y + half),
					Vector2(px_x - half, px_y),
				])
				draw_colored_polygon(pts, color)
				draw_polyline(pts + PackedVector2Array([pts[0]]), edge, edge_w)

		# HP 条（角色头顶）
		var bar_w := tile * 0.5
		var bar_h := _px(6.0)
		var bar_pos := Vector2(px_x - bar_w * 0.5, px_y - half - _px(12.0))
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.12, 0.12, 0.16), true)
		var ratio := c.hp_ratio()
		var bar_color := Color(0.4, 0.95, 0.55) if ratio > 0.4 else Color(0.95, 0.55, 0.3)
		draw_rect(Rect2(Vector2(bar_pos.x, bar_pos.y + bar_h * (1.0 - ratio)),
			Vector2(bar_w, bar_h * ratio)), bar_color, true)

		# 职责标签（永远显示，确保玩家看懂谁在做什么）
		draw_string(ThemeDB.fallback_font,
			Vector2(px_x - _px(26.0), px_y + half + _px(18.0)),
			_role_label(_behavior_text_of(c)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(14.0)), role_color)

		# 阻挡指示：正在阻挡几个敌人（仅前线会显示）
		if c.blocking_enemy_ids.size() > 0:
			draw_string(ThemeDB.fallback_font,
				Vector2(px_x - _px(18.0), px_y + half + _px(34.0)),
				"阻挡 %d/%d" % [c.blocking_enemy_ids.size(), c.block_count_max],
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(13.0)), Color(0.95, 0.9, 0.4))

		# 治疗反馈：刚被治疗过的角色头顶升起绿色十字与 +HP（纯表现层）
		for f: Dictionary in _heal_flashes:
			if int(f["targetId"]) != c.instance_id:
				continue
			if float(f["until"]) <= session.stage.elapsed_seconds:
				continue
			var k := clampf((float(f["until"]) - session.stage.elapsed_seconds) / 0.9, 0.0, 1.0)
			var rise := (1.0 - k) * _px(26.0)
			var hx := px_x + half + _px(16.0)
			var hy := px_y - half - _px(22.0) - rise
			var hcol := Color(HEAL_BEAM_COLOR.r, HEAL_BEAM_COLOR.g, HEAL_BEAM_COLOR.b, k)
			draw_line(Vector2(hx - _px(7.0), hy), Vector2(hx + _px(7.0), hy), hcol, 4.0)
			draw_line(Vector2(hx, hy - _px(7.0)), Vector2(hx, hy + _px(7.0)), hcol, 4.0)
			draw_string(ThemeDB.fallback_font,
				Vector2(hx + _px(12.0), hy + _px(5.0)),
				"+%d" % int(f["amount"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(_px(16.0)), hcol)


## 角色职责配色（前线 / 远程 / 治疗）
func _role_color(c: CharacterRuntime) -> Color:
	match c.behavior:
		CharacterRuntime.Behavior.RANGED:
			return ROLE_RANGED_COLOR
		CharacterRuntime.Behavior.HEALER:
			return ROLE_HEALER_COLOR
		_:
			return ROLE_FRONTLINE_COLOR


## 运行时行为 -> 配置里的字符串（用于显示标签）
func _behavior_text_of(c: CharacterRuntime) -> String:
	return c.behavior_text if not c.behavior_text.is_empty() else CharacterRuntime.behavior_name(c.behavior)

## 敌人（占位方块，按类型着色）。
## P0.3 表现层修复：同一接触线上的多个敌人不再完全重叠——
## 按"同一 (lane, logicalX) 分组内的序号"给一个**纯绘制用**的横向偏移。
## 逻辑坐标、射程、接触线与阻挡判定完全不受影响。
func _draw_enemies() -> void:
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)
	var seen := {}
	for e: EnemyRuntime in session.stage.enemies:
		if not e.is_active():
			continue
		# 逻辑 x 先按 V2.1.4 公式换算为参考画布像素，再同比缩放到当前屏幕
		var ref_px_x := grid.logical_to_px_x(e.logical_x, 0.0)
		var px_x := _origin.x + _px(ref_px_x)
		var px_y := _origin.y + float(e.lane) * spacing
		var size := tile * 0.42

		# 纯表现层的重叠偏移：同一路线 + 同一逻辑 x（判定阈值 0.01 格）视为同栈
		var key := "%d:%.2f" % [e.lane, e.logical_x]
		var stack_index := int(seen.get(key, 0))
		seen[key] = stack_index + 1
		if stack_index > 0:
			var direction := 1.0 if stack_index % 2 == 1 else -1.0
			var magnitude := float((stack_index + 1) / 2)
			px_y += direction * magnitude * _px(OVERLAP_OFFSET_PX)

		_draw_one_enemy(e, px_x, px_y, size, tile)


## 绘制单个敌人的**占位图形**。
## V2.1.4 F 章要求三种基础敌人「容易区分」；本轮指令 二·1 进一步要求
## 「容易区分的占位图形、血条、类别提示及不同移动视觉表现」。
## 因此这里用**形状 + 配色 + 类别标签**三重通道区分，而不是只换颜色：
##   echo_normal  方形（模糊学生轮廓）+ 深紫 + 标签「普通」+ 边缘碎片
##   echo_runner  前倾平行四边形（身体前倾、腿部拉长）+ 橙 + 标签「疾走」+ 速度线
##   echo_armored 外扩六边形（被课桌/书本层层包裹）+ 冷灰 + 标签「装甲」+ 双层护甲边
## 帧尺寸按 V2.1.4 表（weightClass→spriteFramePx）等比映射，因此重装单位视觉更大。
func _draw_one_enemy(e: EnemyRuntime, px_x: float, px_y: float, size: float, tile: float) -> void:
	var cfg: Dictionary = session.stage._enemy_configs.get(e.enemy_id, {})
	var fill := _enemy_fill_color(e.enemy_id)
	# 受击闪白（V2.1.4 D-38：每次攻击必须包含受击闪白或受击动画）
	var hit_k := _hit_flash_k("enemy", e.instance_id)
	if hit_k > 0.0:
		fill = fill.lerp(Color(1, 1, 1, 1), 0.75 * hit_k)
	# 帧尺寸映射：64 基准 → size；96 → 1.5×（重装单位视觉更大）
	var frame_px := float(cfg.get("spriteFramePx", 64))
	var scale := clampf(frame_px / 64.0, 0.8, 1.6)
	var s := size * scale
	var half := s * 0.5

	# 落地阴影（区分单位与背景，帮助读出「在移动」）
	draw_circle(Vector2(px_x, px_y + half * 0.92), s * 0.30,
		Color(0.0, 0.0, 0.0, 0.32))

	match e.enemy_id:
		"echo_runner":
			_draw_enemy_runner(px_x, px_y, s, fill, e)
		"echo_armored":
			_draw_enemy_armored(px_x, px_y, s, fill)
		_:
			_draw_enemy_normal(px_x, px_y, s, fill)

	# 类别标签（常驻，保证不看颜色也能分辨敌种）
	var label := _enemy_kind_label(e.enemy_id)
	var font := ThemeDB.fallback_font
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(14.0))).x
	draw_string(font, Vector2(px_x - lw * 0.5, px_y + half + _px(15.0)), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(14.0)), fill.lightened(0.35))

	# 敌人 HP 条（V2.1.4：血条必须可读；受伤后才显示，满血不刷屏）
	var hp_ratio := 1.0
	if e.hp_max > 0:
		hp_ratio = clampf(float(e.hp) / float(e.hp_max), 0.0, 1.0)
	if hp_ratio < 1.0:
		var bar_w := maxf(s, _px(34.0))
		var bar_pos := Vector2(px_x - bar_w * 0.5, px_y - half - _px(11.0))
		draw_rect(Rect2(bar_pos, Vector2(bar_w, _px(5.0))), Color(0.10, 0.10, 0.14), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * hp_ratio, _px(5.0))),
			Color(0.95, 0.45, 0.40), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, _px(5.0))), Color(1, 1, 1, 0.35), false, 1.0)


## 普通残响体：方形主体 + 边缘飘散碎片（V2.1.4 F-六：模糊学生轮廓、边缘不断飘散黑色碎片）
func _draw_enemy_normal(px_x: float, px_y: float, s: float, fill: Color) -> void:
	var half := s * 0.5
	var rect := Rect2(Vector2(px_x - half, px_y - half), Vector2(s, s))
	draw_rect(rect, fill, true)
	draw_rect(rect, Color(1, 1, 1, 0.55), false, 1.5)
	# 残响核心（高亮紫蓝）
	draw_circle(Vector2(px_x, px_y - half * 0.15), s * 0.13, ENEMY_CORE_GLOW)
	# 边缘碎片：三小片随呼吸轻微外移，表达「边缘不稳定」
	var t := _now()
	for i: int in range(3):
		var ang := TAU * float(i) / 3.0 + t * 1.6
		var d := half * (1.05 + 0.18 * sin(t * 3.0 + float(i)))
		draw_rect(Rect2(Vector2(px_x + cos(ang) * d, px_y + sin(ang) * d) - Vector2(_px(3.0), _px(3.0)),
			Vector2(_px(6.0), _px(6.0))), Color(fill.r * 0.5, fill.g * 0.5, fill.b * 0.5, 0.85), true)


## 疾走残响体：前倾平行四边形 + 速度线（V2.1.4 F-七：身体前倾、腿部异常拉长）
func _draw_enemy_runner(px_x: float, px_y: float, s: float, fill: Color, e: EnemyRuntime) -> void:
	var half := s * 0.5
	# 前倾主体：上边整体向**移动方向（左）**偏移，形成"正在冲刺"的剪影
	var lean := s * 0.30
	var pts := PackedVector2Array([
		Vector2(px_x - half - lean, px_y - half),
		Vector2(px_x + half - lean, px_y - half),
		Vector2(px_x + half + lean * 0.4, px_y + half),
		Vector2(px_x - half + lean * 0.4, px_y + half),
	])
	draw_colored_polygon(pts, fill)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color(1, 1, 1, 0.6), 1.5)
	# 拉长的腿部（两条短线，向后方拖）
	draw_line(Vector2(px_x - half * 0.4, px_y + half), Vector2(px_x - half * 1.5, px_y + half * 1.7),
		fill.darkened(0.25), 3.0)
	draw_line(Vector2(px_x + half * 0.4, px_y + half), Vector2(px_x - half * 0.5, px_y + half * 1.9),
		fill.darkened(0.35), 3.0)
	# 残响核心
	draw_circle(Vector2(px_x - lean * 0.4, px_y - half * 0.2), s * 0.12, ENEMY_CORE_GLOW)
	# 速度线：仅在**移动中**绘制（V2.1.4 本轮要求「不同移动视觉表现」）
	if e.state == BattleTypes.EnemyState.MOVING:
		var t := _now()
		for i: int in range(3):
			var ly := px_y - half * 0.6 + float(i) * half * 0.6
			var len := s * (0.5 + 0.25 * sin(t * 12.0 + float(i)))
			draw_line(Vector2(px_x + half * 1.1, ly), Vector2(px_x + half * 1.1 + len, ly),
				Color(fill.r, fill.g, fill.b, 0.55), 2.0)


## 装甲残响体：外扩六边形 + 双层护甲边（V2.1.4 F-八：被课桌、教科书、书包、考卷层层包裹）
func _draw_enemy_armored(px_x: float, px_y: float, s: float, fill: Color) -> void:
	var half := s * 0.5
	var outer := PackedVector2Array()
	for i: int in range(6):
		var ang := TAU * float(i) / 6.0 - PI * 0.5
		outer.append(Vector2(px_x + cos(ang) * half * 1.12, px_y + sin(ang) * half * 1.12))
	draw_colored_polygon(outer, fill)
	draw_polyline(PackedVector2Array([outer[0], outer[1], outer[2], outer[3], outer[4], outer[5], outer[0]]),
		Color(0.85, 0.88, 0.95, 0.75), 2.5)
	# 内层护甲（层层包裹的语义）：同心六边形
	var inner := PackedVector2Array()
	for i: int in range(6):
		var ang := TAU * float(i) / 6.0 - PI * 0.5
		inner.append(Vector2(px_x + cos(ang) * half * 0.62, px_y + sin(ang) * half * 0.62))
	draw_colored_polygon(inner, fill.darkened(0.28))
	# 护甲板缝（横竖两条），强化"课桌/书本堆叠"观感
	draw_line(Vector2(px_x - half * 0.95, px_y), Vector2(px_x + half * 0.95, px_y),
		Color(0.15, 0.16, 0.22, 0.8), 2.0)
	draw_line(Vector2(px_x, px_y - half * 0.95), Vector2(px_x, px_y + half * 0.95),
		Color(0.15, 0.16, 0.22, 0.8), 2.0)
	# 残响核心（被包裹在最内层）
	draw_circle(Vector2(px_x, px_y), s * 0.14, ENEMY_CORE_GLOW)


## 敌人配色（按 enemy_id 分派；未知敌种回落到普通配色，不崩溃）
func _enemy_fill_color(enemy_id: String) -> Color:
	match enemy_id:
		"echo_runner":
			return ENEMY_RUNNER_FILL
		"echo_armored":
			return ENEMY_ARMORED_FILL
		"echo_normal":
			return ENEMY_NORMAL_FILL
		_:
			return ENEMY_COLOR


## 敌人类别提示标签（本轮指令 二·1「类别提示」）。
## 标签文本来自 enemies.json 的 tags（数据驱动），未知敌种显示为「残响体」。
func _enemy_kind_label(enemy_id: String) -> String:
	var cfg: Dictionary = session.stage._enemy_configs.get(enemy_id, {})
	var tags: Array = cfg.get("tags", [])
	if tags.has("FAST"):
		return "疾走"
	if tags.has("ARMORED"):
		return "装甲"
	if tags.has("NORMAL"):
		return "普通"
	return "残响体"


## 受击闪白强度（0 = 未受击，1 = 刚受击）
func _hit_flash_k(kind: String, target_id: int) -> float:
	for f: Dictionary in _hit_flashes:
		if str(f["kind"]) == kind and int(f["targetId"]) == target_id:
			var remain := float(f["until"]) - _now()
			if remain > 0.0:
				return clampf(remain / HIT_FLASH_SECONDS, 0.0, 1.0)
	return 0.0


## 敌人死亡粒子（V2.1.4 F-四十七：黑色粒子 + 纸张 + 微弱紫色残光，避免大量血液）
func _draw_death_particles() -> void:
	var spacing := _px(grid.lane_spacing_px)
	var now := _now()
	for p: Dictionary in _death_particles:
		var k := clampf((now - float(p["at"])) / DEATH_PARTICLE_LIFETIME, 0.0, 1.0)
		if k >= 1.0:
			continue
		var base_x := _origin.x + _px(grid.logical_to_px_x(float(p["x"]), 0.0))
		var base_y := _origin.y + float(p["lane"]) * spacing
		var spread := _px(46.0) * k
		# 紫色残光（扩散圆环）
		draw_circle(Vector2(base_x, base_y), _px(10.0) + spread * 0.7,
			Color(0.62, 0.40, 0.95, 0.30 * (1.0 - k)), false, 3.0)
		# 黑色粒子 + 纸张碎片（各 4 片，向上/外扩散并下坠）
		for i: int in range(4):
			var ang := TAU * float(i) / 4.0 + float(p["lane"])
			var d := spread * (0.6 + 0.4 * float(i % 2))
			var px := base_x + cos(ang) * d
			var py := base_y + sin(ang) * d * 0.6 - _px(18.0) * (1.0 - k)
			var sz := _px(5.0) * (1.0 - k * 0.6)
			var col := Color(0.10, 0.10, 0.14, 0.9 * (1.0 - k)) if i % 2 == 0 \
				else Color(PAPER_COLOR.r, PAPER_COLOR.g, PAPER_COLOR.b, 0.85 * (1.0 - k))
			draw_rect(Rect2(Vector2(px - sz * 0.5, py - sz * 0.5), Vector2(sz, sz)), col, true)


## 伤害数字（V2.1.4 D-38 视觉反馈；J 章禁止遮挡敌人/预警/路线信息）。
## 位置：目标上方偏上，随寿命上浮并淡出；颜色区分「对敌伤害」与「我方受创」。
func _draw_damage_pops() -> void:
	var font := ThemeDB.fallback_font
	var spacing := _px(grid.lane_spacing_px)
	var tile := _px(grid.tile_size_px)
	var now := _now()
	for p: Dictionary in _damage_pops:
		var age := now - float(p["born"])
		var k := clampf(age / DAMAGE_POP_LIFETIME, 0.0, 1.0)
		if k >= 1.0:
			continue
		var pos := _damage_pop_anchor(str(p["kind"]), int(p["targetId"]))
		if pos.x < 0.0:
			continue
		var rise := _px(30.0) * k
		var alpha := 1.0 - k * k
		var col: Color
		if str(p["kind"]) == "enemy":
			col = Color(1.0, 0.86, 0.45, alpha) if bool(p.get("lethal", false)) \
				else Color(1.0, 0.95, 0.85, alpha)
		else:
			col = Color(1.0, 0.42, 0.42, alpha)
		var text := str(p["text"])
		var fs := int(_px(22.0 if bool(p.get("lethal", false)) else 19.0))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(pos.x - w * 0.5, pos.y - tile * 0.55 - rise)
		# 深色描边保证在亮/暗背景上都可读（V2.1.4：1280×720 到 4K 都要清楚）
		draw_string(font, at + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0, 0, 0, alpha * 0.75))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## 伤害数字的锚点（屏幕坐标）。找不到目标时返回 x<0 表示跳过。
func _damage_pop_anchor(kind: String, target_id: int) -> Vector2:
	if grid == null:
		return Vector2(-1, -1)
	var spacing := _px(grid.lane_spacing_px)
	if kind == "enemy":
		var e := session.stage.get_enemy(target_id)
		if e == null or not e.is_active():
			return Vector2(-1, -1)
		return Vector2(_origin.x + _px(grid.logical_to_px_x(e.logical_x, 0.0)),
			_origin.y + float(e.lane) * spacing)
	var c := session.stage.get_character(target_id)
	if c == null or c.is_incapacitated():
		return Vector2(-1, -1)
	var tile := _px(grid.tile_size_px)
	return Vector2(_origin.x + tile * float(c.column),
		_origin.y + float(c.lane) * spacing)


## 部署落位动画（V2.1.4 三十四：格子高亮 → 落位动画 → AP 扣除）
func _draw_deploy_pops() -> void:
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)
	var now := _now()
	for p: Dictionary in _deploy_pops:
		var k := clampf((now - float(p["at"])) / DEPLOY_POP_LIFETIME, 0.0, 1.0)
		if k >= 1.0:
			continue
		var center := Vector2(_origin.x + tile * float(p["column"]),
			_origin.y + float(p["lane"]) * spacing)
		var r := tile * (0.30 + 0.42 * k)
		draw_circle(center, r, Color(0.45, 0.95, 0.70, 0.55 * (1.0 - k)), false, 3.0)
		# 落位十字（短暂标记该格已占用）
		var arm := tile * 0.16 * (1.0 - k * 0.5)
		draw_line(center - Vector2(arm, 0), center + Vector2(arm, 0),
			Color(0.75, 1.0, 0.85, 0.7 * (1.0 - k)), 2.5)
		draw_line(center - Vector2(0, arm), center + Vector2(0, arm),
			Color(0.75, 1.0, 0.85, 0.7 * (1.0 - k)), 2.5)


## 危险提示：路线入口警示符号（V2.1.4：高威胁波次开始前，路线入口出现 1～2 秒警示符号）
func _draw_lane_warnings() -> void:
	if _lane_warnings.is_empty():
		return
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)
	var entry_x := _origin.x + tile * float(grid.columns - 1) + tile * 0.62
	var now := _now()
	var font := ThemeDB.fallback_font
	for w: Dictionary in _lane_warnings:
		var remain := float(w["until"]) - now
		if remain <= 0.0:
			continue
		var k := clampf(remain / LANE_WARNING_SECONDS, 0.0, 1.0)
		var ly := _origin.y + float(w["lane"]) * spacing
		# 入口三角警示（颜色 + 形状双通道；V2.1.4：关键机制不能只靠颜色提示）
		var pulse := 0.55 + 0.45 * absf(sin(now * 8.0))
		var col := Color(DANGER_COLOR.r, DANGER_COLOR.g, DANGER_COLOR.b, k * pulse)
		var s := tile * 0.20
		var tri := PackedVector2Array([
			Vector2(entry_x + s, ly - s), Vector2(entry_x + s, ly + s),
			Vector2(entry_x - s * 0.7, ly),
		])
		draw_colored_polygon(tri, col)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
			Color(1, 1, 1, k * 0.8), 2.0)
		# 文字：说明是哪种敌人（机制可读性优先）
		var label := _enemy_kind_label(str(w["enemyId"]))
		var fs := int(_px(15.0))
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(entry_x - lw * 0.5, ly - s - _px(6.0)), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(DANGER_COLOR.r, DANGER_COLOR.g, DANGER_COLOR.b, k))


## 新敌人首次登场提示卡 + 关卡教学提示（V2.1.4 F-二十三 / G-五 / J4）。
## 位置：战场上方居中偏左，避开顶部 Wave 条与右上暂停按钮。
func _draw_tutorial_cards() -> void:
	if _tutorial_cards.is_empty():
		return
	var font := ThemeDB.fallback_font
	var now := _now()
	var y := _px(HUD_BAND_HEIGHT) + _px(16.0)
	for card: Dictionary in _tutorial_cards:
		var k := clampf((now - float(card["at"])) / TUTORIAL_CARD_LIFETIME, 0.0, 1.0)
		if k >= 1.0:
			continue
		# 淡入 0.15s / 保持 / 最后 0.6s 淡出
		var alpha := 1.0
		if k < 0.08:
			alpha = k / 0.08
		elif k > 0.88:
			alpha = (1.0 - k) / 0.12
		alpha = clampf(alpha, 0.0, 1.0)
		var title := str(card["title"])
		var text := str(card["text"])
		var fs_title := int(_px(19.0))
		var fs_text := int(_px(17.0))
		var w_title := 0.0
		if not title.is_empty():
			w_title = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_title).x
		var w_text := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_text).x
		var box_w := maxf(w_title, w_text) + _px(30.0)
		var box_h := _px(34.0) + (_px(24.0) if not title.is_empty() else 0.0)
		var box := Rect2(Vector2(_px(24.0), y), Vector2(box_w, box_h))
		draw_rect(box, Color(0.05, 0.06, 0.12, 0.90 * alpha), true)
		# 左侧强调条：新敌人提示用品红（危险语义），教学提示用冰蓝（可交互语义）
		var accent := DANGER_COLOR if not str(card["enemyId"]).is_empty() else Color(0.45, 0.78, 1.0)
		draw_rect(Rect2(box.position, Vector2(_px(6.0), box.size.y)),
			Color(accent.r, accent.g, accent.b, alpha), true)
		var ty := box.position.y + _px(24.0)
		if not title.is_empty():
			draw_string(font, Vector2(box.position.x + _px(18.0), ty),
				"新敌人 · %s" % title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_title,
				Color(accent.r, accent.g, accent.b, alpha))
			ty += _px(24.0)
		draw_string(font, Vector2(box.position.x + _px(18.0), ty), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs_text, Color(0.92, 0.95, 1.0, alpha))
		y += box_h + _px(10.0)


## 部署反馈：选中时的合法/非法格高亮 + 悬停描边 + **射程覆盖预览**。
##
## 射程覆盖预览（本轮新增，第四阶段要求）：
##   选中远程角色后，用**不刺眼**的覆盖区域显示本路与相邻路的有效射程，
##   让玩家不看调试日志就能理解「这个角色能打到哪」。
##   覆盖范围**完全来自领域层**的 session.query_attack_coverage()，
##   因此 UI 不可能显示出一个实际打不到的范围（该一致性有 GUT 用例保证）。
func _draw_deploy_feedback() -> void:
	if _selected_card_id.is_empty() or session == null or grid == null:
		return
	if not session.is_running() or session.is_paused():
		return
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)

	for lane: int in range(grid.lanes):
		for column: int in range(grid.columns):
			var r := session.query_deploy(_selected_card_id, column, lane)
			var center := Vector2(_origin.x + tile * float(column),
				_origin.y + float(lane) * spacing)
			var rect := Rect2(center - Vector2(tile, tile) * 0.43,
				Vector2(tile, tile) * 0.86)
			if r.ok:
				# 合法：绿色半透明填充
				draw_rect(rect, Color(CELL_DEPLOYABLE.r, CELL_DEPLOYABLE.g,
					CELL_DEPLOYABLE.b, 0.18), true)
			else:
				# 非法：红色细边框
				draw_rect(rect, Color(CELL_INVALID.r, CELL_INVALID.g,
					CELL_INVALID.b, 0.35), false, 2.0)

	# ---- 射程覆盖预览（悬停格为锚点）----
	if _hover_column >= 0 and _hover_lane >= 0:
		_draw_range_coverage_preview(_hover_column, _hover_lane, tile, spacing)

	# 悬停格：黄色描边 + 判定结果
	if _hover_column >= 0 and _hover_lane >= 0:
		var center := Vector2(_origin.x + tile * float(_hover_column),
			_origin.y + float(_hover_lane) * spacing)
		var rect := Rect2(center - Vector2(tile, tile) * 0.43,
			Vector2(tile, tile) * 0.86)
		var c := CELL_DEPLOYABLE if _hover_deploy_ok else CELL_INVALID
		draw_rect(rect, c, false, 3.0)
		if not _hover_deploy_ok:
			draw_string(ThemeDB.fallback_font,
				Vector2(center.x - _px(40.0), center.y - tile * 0.55),
				_hover_reject_reason, HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(_px(15.0)), CELL_INVALID)


## 绘制射程覆盖预览：本路与相邻路的有效射程区域。
##
## 视觉纪律（指令要求「清晰、不刺眼」）：
##   - 本路线用较饱和的色调 + 实线边框（玩家最关心的范围）；
##   - 相邻路线用低饱和度色调 + 虚线边框（提示「可支援」而非等价）；
##   - 覆盖区域按**连续区间**绘制（敌人不占格，真实射程是连续区间，
##     而不是离散的格子集合），区间端点直接来自领域层的 rangeTiles。
##   - 覆盖区域只画在合法部署格所在行上，不遮挡角色与敌人的主体。
func _draw_range_coverage_preview(
	column: int, lane: int, tile: float, spacing: float
) -> void:
	var coverage := session.query_attack_coverage(_selected_card_id, column, lane)
	if coverage.is_empty():
		return
	var cell := Vector2(tile * 0.86, tile * 0.86)
	var anchor_x := _origin.x + tile * float(column)
	var core_margin := tile * CORE_MARGIN_TILES

	for entry: Dictionary in coverage:
		var target_lane := int(entry["lane"])
		var eff_range := float(entry["rangeTiles"])
		var is_adjacent := bool(entry.get("isAdjacent", false))
		var lane_y := _origin.y + float(target_lane) * spacing

		# 覆盖区间：角色格中心起，向前（右侧）延伸 eff_range 格
		var from_x := anchor_x
		var to_x := anchor_x + tile * eff_range
		var band := Rect2(
			Vector2(from_x, lane_y - cell.y * 0.44),
			Vector2(maxf(to_x - from_x, 1.0), cell.y * 0.88))

		var tint := RANGE_TINT_ADJACENT if is_adjacent else RANGE_TINT_OWN
		draw_rect(band, tint, true)
		# 边框：本路实线、相邻路虚线（用短线段模拟，避免依赖自定义 shader）
		var edge := RANGE_EDGE_ADJACENT if is_adjacent else RANGE_EDGE_OWN
		if is_adjacent:
			_draw_dashed_rect(band, edge, 2.0, _px(8.0))
		else:
			draw_rect(band, edge, false, 2.0)

		# 端点标记：让「射程到哪结束」一眼可见
		draw_line(Vector2(to_x, lane_y - cell.y * 0.5),
			Vector2(to_x, lane_y + cell.y * 0.5), edge, 2.0)

		# 相邻路标注（只在相邻路显示，避免刷屏）
		if is_adjacent:
			draw_string(ThemeDB.fallback_font,
				Vector2(maxf(from_x, _px(4.0)), lane_y - cell.y * 0.56),
				"相邻路 %.1f 格" % eff_range, HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(_px(13.0)), edge)

	# 本路射程标签
	var own_range := 0.0
	for entry: Dictionary in coverage:
		if int(entry["lane"]) == lane:
			own_range = float(entry["rangeTiles"])
	if own_range > 0.0:
		draw_string(ThemeDB.fallback_font,
			Vector2(anchor_x + _px(6.0), lane_y_label(lane, spacing) - cell.y * 0.56),
			"本路 %.1f 格" % own_range, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_px(13.0)), RANGE_EDGE_OWN)


## 某条路线的像素 y（供标签定位复用）
func lane_y_label(lane: int, spacing: float) -> float:
	return _origin.y + float(lane) * spacing


## 用短线段绘制虚线矩形边框（无 shader 依赖，任何渲染后端都可用）
func _draw_dashed_rect(rect: Rect2, color: Color, width: float, dash: float) -> void:
	var step := maxf(dash, 1.0)
	# 上下边
	var x := rect.position.x
	while x < rect.position.x + rect.size.x:
		var x2 := minf(x + step, rect.position.x + rect.size.x)
		draw_line(Vector2(x, rect.position.y), Vector2(x2, rect.position.y), color, width)
		draw_line(Vector2(x, rect.position.y + rect.size.y),
			Vector2(x2, rect.position.y + rect.size.y), color, width)
		x += step * 2.0
	# 左右边
	var y := rect.position.y
	while y < rect.position.y + rect.size.y:
		var y2 := minf(y + step, rect.position.y + rect.size.y)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x, y2), color, width)
		draw_line(Vector2(rect.position.x + rect.size.x, y),
			Vector2(rect.position.x + rect.size.x, y2), color, width)
		y += step * 2.0


## 底部角色卡条（P0.4：每个本关可用角色一张卡，按 availableCharacters 顺序）。
## 三职业用不同颜色与职责标签区分；数字键 1..N 与点击等价。
func _draw_character_card() -> void:
	if session == null or session.stage == null:
		return
	for i: int in range(_roster.size()):
		if i >= _card_rects.size():
			break
		_draw_one_card(_roster[i], _card_rects[i], i)


## 绘制单张角色卡
func _draw_one_card(character_id: String, rect: Rect2, slot_index: int) -> void:
	var cfg: Dictionary = session.stage._character_configs.get(character_id, {})
	if cfg.is_empty():
		return
	var pos := rect.position
	var size := rect.size
	var font := ThemeDB.fallback_font

	var char_inst := session.stage.get_character_by_id(character_id)
	var deployed := char_inst != null
	var cooldown := session.get_redeploy_remaining(character_id)
	var cooling := cooldown > 0.0
	var selected := _selected_card_id == character_id
	var behavior := str(cfg.get("behavior", "FRONTLINE"))
	var role_color := _role_color_of_text(behavior)

	var bg := CARD_SELECTED_COLOR if selected else (CARD_COOLING_COLOR if cooling else CARD_COLOR)
	draw_rect(rect, bg, true)
	draw_rect(rect, Color(0.6, 0.85, 1.0) if selected else Color(0.45, 0.50, 0.70), false, 2.0)
	# 左侧职责色条：不看文字也能分辨前线 / 远程 / 治疗
	draw_rect(Rect2(pos, Vector2(_px(8.0), size.y)), role_color, true)

	var tx := pos.x + _px(22.0)
	var ty := pos.y + _px(30.0)

	# 名称 + 职责标签
	draw_string(font, Vector2(tx, ty), str(cfg.get("name", "—")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(22.0)), TEXT_COLOR)
	var role_text := _role_label(behavior)
	draw_string(font, Vector2(tx + _px(112.0), ty), "[%s]" % role_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(15.0)), role_color)

	# 费用
	var cost := int(cfg.get("deployCost", 0))
	var affordable := session.stage.can_afford(cost)
	ty += _px(32.0)
	draw_string(font, Vector2(tx, ty), "费用 %d AP" % cost,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(17.0)),
		Color(0.55, 0.85, 1.0) if affordable else Color(0.95, 0.5, 0.4))

	# V2.1.4 D-18 角色卡四态：可部署 / AP 不足 / 已部署 / 再部署（倒计时）
	var status_text: String
	var status_color: Color
	if deployed:
		status_text = "已在场"
		status_color = Color(0.6, 0.75, 0.95)
	elif cooling:
		status_text = "再部署 %.1f 秒" % cooldown
		status_color = Color(0.95, 0.80, 0.35)
	elif not session.is_running():
		status_text = "战斗已结束"
		status_color = Color(0.6, 0.6, 0.65)
	elif not affordable:
		status_text = "AP 不足"
		status_color = Color(0.95, 0.5, 0.4)
	elif session.is_paused():
		status_text = "暂停中"
		status_color = Color(0.95, 0.85, 0.45)
	elif selected:
		status_text = "已选中 — 点击格部署"
		status_color = Color(0.4, 1.0, 0.65)
	else:
		status_text = "可部署（点此卡或按 %d）" % (slot_index + 1)
		status_color = Color(0.75, 0.95, 1.0)
	ty += _px(28.0)
	draw_string(font, Vector2(tx, ty), status_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0)), status_color)

	# 再部署冷却进度条（离场后显示）
	if cooling:
		var bar_w := size.x - _px(44.0)
		var bar_h := _px(8.0)
		var bp := Vector2(tx, ty + _px(10.0))
		draw_rect(Rect2(bp, Vector2(bar_w, bar_h)), Color(0.14, 0.14, 0.18), true)
		var inst := session.stage.get_character_instance(character_id)
		var prog := inst.redeploy_progress() if inst != null else 0.0
		draw_rect(Rect2(bp, Vector2(bar_w * (1.0 - prog), bar_h)),
			Color(0.45, 0.85, 0.55), true)

	# 关键属性：治疗角色显示治疗力而不是攻击
	ty += _px(32.0)
	var st: Dictionary = cfg.get("baseStats", {})
	var power_text := ""
	if behavior == "HEALER":
		power_text = "治疗 %d" % int(cfg.get("healPower", 0))
	else:
		power_text = "攻 %d" % int(st.get("attack", 0))
	draw_string(font, Vector2(tx, ty),
		"HP %d  %s  防 %d  阻挡 %d" % [
			int(st.get("hp", 0)), power_text,
			int(st.get("defense", 0)), int(cfg.get("blockCount", 0)),
		], HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(14.0)), Color(0.72, 0.78, 0.92))

	# 快捷键提示
	draw_string(font, Vector2(pos.x + size.x - _px(64.0), pos.y + _px(30.0)),
		"[%d]" % (slot_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(_px(14.0)), Color(0.55, 0.62, 0.85))


## 行为字符串 -> 职责配色
func _role_color_of_text(behavior: String) -> Color:
	match behavior:
		"RANGED":
			return ROLE_RANGED_COLOR
		"HEALER":
			return ROLE_HEALER_COLOR
		_:
			return ROLE_FRONTLINE_COLOR


## 治疗事件回调（P0.4）：记录一次纯表现层的治疗提示
func _on_character_healed(_healer: CharacterRuntime, target: CharacterRuntime, amount: int) -> void:
	if session == null or session.stage == null:
		return
	_heal_flashes.append({
		"targetId": target.instance_id,
		"amount": amount,
		"until": session.stage.elapsed_seconds + 0.9,
	})
	# 只保留最近若干条，避免长期堆积
	while _heal_flashes.size() > 24:
		_heal_flashes.remove_at(0)

## 选中场上角色后的操作面板（V2.1.4 D-27 / J4 底部右：角色信息 / 技能 / 撤退）
func _draw_character_panel() -> void:
	if _selected_character_id == 0 or session == null or session.is_decided():
		return
	var c := session.stage.get_character(_selected_character_id)
	if c == null:
		return
	var font := ThemeDB.fallback_font
	var size := Vector2(_px(300.0), _px(210.0))
	var pos := Vector2(_viewport_size.x - size.x - _px(24.0),
		_viewport_size.y - size.y - _px(24.0))
	draw_rect(Rect2(pos, size), PANEL_BG, true)
	draw_rect(Rect2(pos, size), Color(0.55, 0.62, 0.85), false, 2.0)

	var tx := pos.x + _px(20.0)
	var ty := pos.y + _px(34.0)
	draw_string(font, Vector2(tx, ty), c.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(22.0)), TEXT_COLOR)
	ty += _px(30.0)
	draw_string(font, Vector2(tx, ty), "%s  第 %d 格" % [
			BattleTypes.lane_name(c.lane), c.column + 1],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(15.0)), DIM_TEXT)
	ty += _px(28.0)
	draw_string(font, Vector2(tx, ty), "HP %d / %d" % [c.hp, c.max_hp],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0)), Color(0.55, 0.95, 0.65))
	ty += _px(24.0)
	draw_string(font, Vector2(tx, ty), "攻击 %d  防御 %d  阻挡 %d/%d" % [
			c.attack, c.defense, c.blocking_enemy_ids.size(), c.block_count_max],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(14.0)), Color(0.72, 0.78, 0.92))
	ty += _px(24.0)
	var refund := session.stage.compute_retreat_refund(
		int(session.stage._character_configs.get(c.character_id, {}).get("deployCost", 0)))
	draw_string(font, Vector2(tx, ty),
		"撤退返还 %d AP，冷却 %.0f 秒" % [refund, c.redeploy_time],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(14.0)), Color(0.85, 0.80, 0.55))

	# 撤退按钮
	var hovered := _retreat_rect.has_point(_mouse_pos)
	draw_rect(_retreat_rect, BUTTON_HOVER if hovered else RETREAT_COLOR, true)
	draw_rect(_retreat_rect, Color(1, 1, 1, 0.45), false, 2.0)
	var label := "撤退（R）"
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0))).x
	draw_string(font,
		Vector2(_retreat_rect.position.x + (_retreat_rect.size.x - label_w) * 0.5,
			_retreat_rect.position.y + _retreat_rect.size.y * 0.68),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0)), Color(1, 0.94, 0.94))


## 顶部右侧：暂停 / 继续按钮 + Wave 进度
func _draw_wave_banner() -> void:
	if session == null or session.stage == null:
		return
	var font := ThemeDB.fallback_font
	var s := session.stage

	# Wave 进度（顶部中）
	var wn := s.current_wave_number()
	var total := s.total_wave_count()
	var wave_text := "Wave %d / %d" % [wn, total]
	if total == 0:
		wave_text = "无 Wave 配置"
	var wcol := Color(0.85, 0.90, 1.0)
	if wn >= 1 and wn <= total:
		wave_text += "  %s" % str(s.waves[wn - 1].get("label", ""))
	var wsize := font.get_string_size(wave_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(26.0))).x
	draw_string(font, Vector2((_viewport_size.x - wsize) * 0.5, _px(44.0)), wave_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(26.0)), wcol)

	# 当前波剩余与下一波预告（V2.1.4 D-33：UI 显示当前 Wave、下一波提示、当前敌人数量）
	var remain := s.current_wave_remaining()
	var living := s.enemies.size()
	var info := "本波待出怪 %d ｜ 场上敌人 %d" % [remain, living]
	var isize := font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0))).x
	draw_string(font, Vector2((_viewport_size.x - isize) * 0.5, _px(72.0)), info,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0)), Color(0.72, 0.80, 0.95))

	var nxt := s.next_wave_preview()
	if not nxt.is_empty():
		var ntext := "下一波：Wave %d %s（%d 名，%s）" % [
			int(nxt["number"]), str(nxt["label"]), int(nxt["enemyCount"]),
			_lanes_text(nxt["lanes"])]
		var nsize := font.get_string_size(ntext, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0))).x
		draw_string(font, Vector2((_viewport_size.x - nsize) * 0.5, _px(98.0)), ntext,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0)), Color(0.95, 0.80, 0.45))
	else:
		var etext := "最终波 — 清空后即胜利"
		var esize := font.get_string_size(etext, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0))).x
		draw_string(font, Vector2((_viewport_size.x - esize) * 0.5, _px(98.0)), etext,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0)), Color(0.55, 0.95, 0.65))

	# 暂停按钮
	if not session.is_decided():
		var hovered := _pause_rect.has_point(_mouse_pos)
		draw_rect(_pause_rect, BUTTON_HOVER if hovered else BUTTON_COLOR, true)
		draw_rect(_pause_rect, Color(0.55, 0.62, 0.85), false, 2.0)
		var pt := "继续" if session.is_paused() else "暂停 (Space)"
		var psize := font.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(17.0))).x
		draw_string(font,
			Vector2(_pause_rect.position.x + (_pause_rect.size.x - psize) * 0.5,
				_pause_rect.position.y + _pause_rect.size.y * 0.68),
			pt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(17.0)), Color(0.92, 0.95, 1.0))


func _lanes_text(lanes: Variant) -> String:
	var parts: Array[String] = []
	for l: Variant in (lanes as Array):
		parts.append(BattleTypes.lane_name(int(l)))
	return "、".join(parts) if not parts.is_empty() else "—"


## 战斗 HUD 文本（V2.1.4 J4 六区布局）：
##   顶部左：核心 HP / 关卡        顶部中：Wave（见 _draw_wave_banner）
##   顶部右：暂停                  底部左：AP 与回复
##   底部中：角色卡条（见 _draw_character_card）
##   底部右：当前角色技能 / 撤退 / 状态（见 _draw_character_panel）
##
## 纪律（V2.1.4 J 章）：PC 战斗 HUD 禁止大面积无功能装饰小字；
## 因此这里**只保留玩家决策需要的信息**，调试明细折叠到 F1 开关后面。
func _draw_hud_text() -> void:
	var font := ThemeDB.fallback_font
	var x := _px(20.0)
	var y := _px(34.0)

	# ---- 顶部左：关卡名 + 核心 HP（大号，第一眼可见） ----
	draw_string(font, Vector2(x, y), "%s" % _stage_display_name(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(19.0)), Color(0.78, 0.84, 0.96))
	y += _px(28.0)
	var core_ratio := 1.0
	if session.stage.core_hp_max > 0:
		core_ratio = float(session.stage.core_hp) / float(session.stage.core_hp_max)
	var core_col := CORE_COLOR
	if core_ratio <= 0.34:
		core_col = DANGER_COLOR
	elif core_ratio <= 0.67:
		core_col = Color(0.95, 0.72, 0.35)
	draw_string(font, Vector2(x, y), "残响锚点 %d / %d" % [
		session.stage.core_hp, session.stage.core_hp_max],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(26.0)), core_col)
	# 核心生命点（用圆点数量直观表达剩余，颜色 + 数量双通道）
	var dot_x := x
	var dot_y := y + _px(16.0)
	for i: int in range(session.stage.core_hp_max):
		var filled := i < session.stage.core_hp
		draw_circle(Vector2(dot_x + _px(9.0), dot_y), _px(6.0),
			core_col if filled else Color(0.24, 0.26, 0.34))
		dot_x += _px(22.0)

	# ---- 底部左：AP 与回复 ----
	var ap_y := _viewport_size.y - _px(CARD_HEIGHT) - _px(46.0)
	draw_string(font, Vector2(_px(24.0), ap_y), "AP %d / %d" % [
		session.stage.ap, session.stage.ap_max],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(26.0)), Color(0.62, 0.86, 1.0))
	draw_string(font, Vector2(_px(24.0) + _px(168.0), ap_y),
		"回复 %.0f / 秒" % session.stage.ap_regen_per_second,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0)), Color(0.60, 0.72, 0.90))
	# AP 条（宽度与上限挂钩，便于读出「快满了」）
	var ap_bar_w := _px(300.0)
	var ap_bar := Rect2(Vector2(_px(24.0), ap_y + _px(8.0)), Vector2(ap_bar_w, _px(10.0)))
	draw_rect(ap_bar, Color(0.12, 0.14, 0.20), true)
	if session.stage.ap_max > 0:
		var ap_ratio := clampf(float(session.stage.ap) / float(session.stage.ap_max), 0.0, 1.0)
		draw_rect(Rect2(ap_bar.position, Vector2(ap_bar_w * ap_ratio, ap_bar.size.y)),
			Color(0.42, 0.76, 0.98), true)
	draw_rect(ap_bar, Color(0.45, 0.55, 0.75), false, 1.5)

	# ---- 可选：调试明细（默认关闭，避免 HUD 装饰性小字） ----
	if _show_debug_hud:
		var dy := _px(HUD_BAND_HEIGHT) - _px(10.0)
		for line: String in _debug_lines:
			draw_string(font, Vector2(x, dy), line, HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(_px(14.0)), Color(0.62, 0.68, 0.82))
			dy += _px(18.0)


## 关卡显示名（来自 StageConfig；无显式名称时用 stageId）
func _stage_display_name() -> String:
	if session == null or session.stage == null:
		return "—"
	var sid := session.stage.stage_id
	# Prototype 演示关给一个玩家可读的名字；正式关卡仍以 stageId 显示
	if sid == "p1_0_demo":
		return "Prototype 演示关 — 三职业 × 三种残响体"
	return "关卡 %s" % sid


## 操作反馈提示（底部中央）
func _draw_feedback() -> void:
	if _feedback_timer <= 0.0 or _feedback_text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(_feedback_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(19.0))).x
	var pad := _px(18.0)
	var pos := Vector2((_viewport_size.x - w) * 0.5,
		_viewport_size.y - _px(CARD_HEIGHT) - _px(60.0))
	draw_rect(Rect2(Vector2(pos.x - pad, pos.y - _px(24.0)),
		Vector2(w + pad * 2.0, _px(38.0))), Color(0.04, 0.05, 0.09, 0.88), true)
	draw_string(font, pos, _feedback_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(_px(19.0)), _feedback_color)


## 暂停遮罩（V2.1.4 D-35）
func _draw_pause_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, _viewport_size), Color(0.02, 0.03, 0.06, 0.45), true)
	var font := ThemeDB.fallback_font
	var text := "已暂停 — 按 Space 或点击右上角「继续」"
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(34.0))).x
	draw_string(font, Vector2((_viewport_size.x - w) * 0.5, _viewport_size.y * 0.45),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(34.0)), Color(0.98, 0.92, 0.60))


## 结果界面。
##
## 显示内容依据 V2.1.4：
##   D-40/D-41：胜负 + 核心剩余 HP + 击杀 / 漏怪
##   G-八 失败与复盘设计：**突破核心的敌人类型、最多承压路线、角色死亡次数、
##        AP 溢出/短缺**，以及「重新挑战」按钮；不使用嘲讽或惩罚性文案，
##        让玩家感到「我知道下一次可以怎么改」。
##   本轮指令 二·3：让玩家理解**为什么赢、为什么输**。
func _draw_result_overlay() -> void:
	var summary := session.result_summary()
	if summary.is_empty():
		return
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, _viewport_size), Color(0.02, 0.03, 0.06, 0.78), true)

	var panel := Rect2(Vector2(_viewport_size.x * 0.5 - _px(430.0),
			_viewport_size.y * 0.5 - _px(340.0)), Vector2(_px(860.0), _px(680.0)))
	draw_rect(panel, PANEL_BG, true)
	draw_rect(panel, Color(0.55, 0.62, 0.85), false, 3.0)

	var victory := bool(summary["victory"])
	var title := "胜 利" if victory else "失 败"
	var tcol := Color(0.55, 0.95, 0.65) if victory else Color(0.95, 0.45, 0.45)
	var cx := _viewport_size.x * 0.5
	var tsize := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(58.0))).x
	draw_string(font, Vector2(cx - tsize * 0.5, panel.position.y + _px(84.0)), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(58.0)), tcol)

	# 一句话结论：让玩家立刻知道发生了什么
	var reason := ""
	if victory:
		reason = "残响锚点守住了全部 %d 个 Wave" % int(summary["waveTotal"])
	else:
		reason = "残响锚点被击穿：%d 名敌人突破了防线" % int(summary["leaked"])
	var rsize := font.get_string_size(reason, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0))).x
	draw_string(font, Vector2(cx - rsize * 0.5, panel.position.y + _px(122.0)), reason,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0)), DIM_TEXT)

	# ---- 主要结算数据 ----
	var lines := [
		"核心剩余 HP：%d / %d" % [int(summary["coreHp"]), int(summary["coreHpMax"])],
		"击杀敌人：%d / %d      漏怪：%d" % [
			int(summary["kills"]), int(summary["planned"]), int(summary["leaked"])],
		"Wave 进度：%d / %d" % [int(summary["wave"]), int(summary["waveTotal"])],
		"角色撤退：%d 次（返还 %d AP）      失能：%d" % [
			int(summary["retreats"]), int(summary["retreatAp"]), int(summary["lost"])],
		"治疗总量：%d HP" % int(summary["healedTotal"]),
		"战斗时长：%.1f 秒" % float(summary["elapsed"]),
	]
	var ly := panel.position.y + _px(164.0)
	for line: String in lines:
		var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0))).x
		draw_string(font, Vector2(cx - lw * 0.5, ly), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0)), TEXT_COLOR)
		ly += _px(28.0)

	# ---- 复盘区块（V2.1.4 G-八）：失败时解释原因，胜利时给出压力分布 ----
	ly += _px(10.0)
	draw_line(Vector2(panel.position.x + _px(60.0), ly - _px(14.0)),
		Vector2(panel.position.x + panel.size.x - _px(60.0), ly - _px(14.0)),
		Color(0.35, 0.40, 0.58), 1.5)
	var head := "复盘：为什么会输" if not victory else "复盘：本局压力分布"
	var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(19.0))).x
	draw_string(font, Vector2(cx - hw * 0.5, ly + _px(4.0)), head,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(19.0)),
		Color(0.95, 0.72, 0.45) if not victory else Color(0.62, 0.85, 1.0))
	ly += _px(30.0)
	for line: String in _build_review_lines(summary):
		var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(18.0))).x
		draw_string(font, Vector2(cx - lw * 0.5, ly), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(18.0)), Color(0.82, 0.87, 0.98))
		ly += _px(26.0)

	# 按钮
	_draw_button(_relaunch_rect, "重新挑战", Color(0.22, 0.45, 0.72))
	_draw_button(_quit_rect, "退出战斗", Color(0.42, 0.28, 0.32))


## 构建复盘文案（V2.1.4 G-八）。
## 纪律：不使用嘲讽或惩罚性文案；每条都指向「下一次可以怎么改」。
func _build_review_lines(summary: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var victory := bool(summary["victory"])
	var leaked_by: Dictionary = summary.get("leakedByType", {})
	var pressure: Dictionary = summary.get("pressureByLane", {})
	var busiest := int(summary.get("busiestLane", -1))

	# ① 突破核心的敌人类型（失败时最关键的诊断信息）
	if not leaked_by.is_empty():
		var parts: Array[String] = []
		for eid: String in leaked_by.keys():
			parts.append("%s ×%d" % [_display_enemy_name(eid), int(leaked_by[eid])])
		out.append("突破防线的敌人：%s" % "、".join(parts))
	elif victory:
		out.append("没有任何敌人突破防线")

	# ② 最多承压路线
	if busiest >= 0:
		var lane_hp := int(pressure.get(busiest, 0))
		out.append("承受压力最大的路线：%s（累计 %d 点敌人生命）"
			% [BattleTypes.lane_name(busiest), lane_hp])

	# ③ 针对性建议（基于**本局实际数据**，不是通用套话）
	if not victory:
		if leaked_by.size() > 1:
			out.append("多条路线同时被突破：注意为「下一波」预告预留远程换线时间")
		elif not leaked_by.is_empty():
			out.append("只有一条路线被突破：把远程或治疗调整到该路线即可")
		if int(summary["retreats"]) == 0 and int(summary["wave"]) >= 3:
			out.append("本局未使用过主动撤退：远程无法换线，建议用撤退重新部署")
		if int(summary["lost"]) > 0:
			out.append("有 %d 名角色失能：注意用治疗维持前线生命" % int(summary["lost"]))
		if int(summary["heals"]) == 0:
			out.append("本局没有任何治疗：治疗角色能显著延长前线存活时间")
	else:
		out.append("总治疗量 %d HP，前线靠治疗维持住了阻挡"
			% int(summary["healedTotal"]))
		if int(summary["retreats"]) > 0:
			out.append("使用 %d 次主动撤退完成换线，这是本关的关键操作"
				% int(summary["retreats"]))
	return out


func _draw_button(rect: Rect2, label: String, base: Color) -> void:
	if rect.size.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var hovered := rect.has_point(_mouse_pos)
	draw_rect(rect, base.lightened(0.18) if hovered else base, true)
	draw_rect(rect, Color(0.75, 0.82, 0.95), false, 2.0)
	var s := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(24.0))).x
	draw_string(font, Vector2(rect.position.x + (rect.size.x - s) * 0.5,
			rect.position.y + rect.size.y * 0.66),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(24.0)), Color(0.96, 0.98, 1.0))


func _draw_pause_overlay_helper() -> void:
	pass


# ============================================================
#  信号回调（表现层只重绘，不改状态）
# ============================================================

func _refresh_debug_lines() -> void:
	if session == null or session.stage == null:
		return
	var s := session.stage
	_debug_lines = [
		"关卡：%s      渲染缩放：%.3f（参考画布 %d×%d）" % [
			s.stage_id, _render_scale,
			grid.reference_canvas_width, grid.reference_canvas_height,
		],
		"运行状态：%s%s%s" % [
			BattleTypes.outcome_name(session.outcome),
			"（已冻结）" if session.is_frozen() else "",
			"（暂停）" if s.is_paused() else "",
		],
		"核心 HP：%d / %d      漏怪结算次数：%d" % [
			s.core_hp, s.core_hp_max, s.core_damage_events,
		],
		"AP：%d / %d（自然回复 %.0f/s）      场上角色：%d      击杀：%d" % [
			s.ap, s.ap_max, s.ap_regen_per_second, s.characters.size(), s.enemies_killed,
		],
		"Wave %d / %d      出怪：已生成 %d / 计划 %d      场上存活：%d" % [
			s.current_wave_number(), s.total_wave_count(),
			s.spawned_enemy_count(), s.planned_enemy_count(), s.enemies.size(),
		],
		"逻辑时间：%.2f s      格尺寸：%.0f px（参考）      路间距：%.0f px（参考）" % [
			s.elapsed_seconds, grid.tile_size_px, grid.lane_spacing_px,
		],
		"坐标系：lane 0=上段 / 1=中段 / 2=下段；column 0=核心侧，column 5=入口侧",
	]


func _on_outcome_decided(_outcome: int) -> void:
	_layout_buttons()
	# Alpha A0.1：胜利结算发放资源，使「战斗 → 成长」形成闭环。
	# 纪律：奖励数值来自关卡配置/奖励表，**不在此处硬编码**；
	# 结算必须事务式落盘，且同一局只发一次。
	_grant_battle_rewards()
	queue_redraw()


## 结算奖励（Alpha A0.1 引入，A0.4 改由 StageRewardService 统一负责）。
##
## 纪律：
##   - 数值唯一来自关卡 StageConfig.battleRewards 与 stage_rewards.json；
##   - 首通奖励**只发一次**（以存档的 firstClearClaimed 为准，幂等）；
##   - 失败不发任何奖励；
##   - 全部事务式落盘。
## 本函数只负责「把结算结果转发给服务 + 显示反馈」，不含任何金额。
func _grant_battle_rewards() -> void:
	if _rewards_granted:
		return
	_rewards_granted = true
	if session == null:
		return
	var victory := session.outcome == BattleTypes.Outcome.VICTORY
	var res := StageRewardService.settle(_stage_config_for_rewards, victory)
	if not res.ok:
		GameLog.error(TAG, "关卡结算失败：%s" % res.reason)
		_show_feedback("结算异常：%s" % res.reason, Color(0.98, 0.4, 0.4))
		return
	if not res.rewarded:
		GameLog.info(TAG, "本次无奖励发放（%s）" % res.reason)
		return
	var parts: PackedStringArray = PackedStringArray()
	for cid: String in res.granted.keys():
		parts.append("%s ×%d" % [_currency_display_name(cid), int(res.granted[cid])])
	_show_feedback("%s奖励：%s" % ["首通" if res.first_clear else "结算", "、".join(parts)],
		Color(0.55, 0.95, 0.7))


## 资源显示名（唯一来自 currencies.json）
func _currency_display_name(currency_id: String) -> String:
	for c: Dictionary in DataRegistry.get_domain("currencies").get("currencies", []):
		if str(c.get("id", "")) == currency_id:
			return str(c.get("name", currency_id))
	for item: Dictionary in DataRegistry.get_domain("currencies").get("studyRecordItems", []):
		if str(item.get("id", "")) == currency_id:
			return str(item.get("name", currency_id))
	return currency_id


func _on_core_hp_changed(_current: int, _max_hp: int) -> void:
	# 核心受创：闪烁 + 脉冲（V2.1.4：核心受创必须让玩家立即注意）
	_core_flash_until = _now() + CORE_FLASH_SECONDS
	_core_pulse_until = _now() + CORE_PULSE_SECONDS
	queue_redraw()


func _on_enemy_reached_core(enemy: EnemyRuntime) -> void:
	# 漏怪反馈：在核心处播一次醒目提示（V2.1.4：核心受创走 L4 系统警报层级）
	_core_flash_until = _now() + CORE_FLASH_SECONDS
	_core_pulse_until = _now() + CORE_PULSE_SECONDS
	_show_feedback("核心受创！%s 突破防线（-%d）" % [
		_display_enemy_name(enemy.enemy_id), enemy.core_damage],
		CORE_HIT_COLOR)


## 敌人显示名（来自 enemies.json，不在场景里硬编码）
func _display_enemy_name(enemy_id: String) -> String:
	if session == null or session.stage == null:
		return enemy_id
	var cfg: Dictionary = session.stage._enemy_configs.get(enemy_id, {})
	return str(cfg.get("name", enemy_id))


func _on_wave_changed(wave_number: int, total: int) -> void:
	_show_feedback("Wave %d / %d 开始" % [wave_number, total], Color(0.95, 0.85, 0.45))


## 当前逻辑时刻（表现层计时统一用它，保证与战斗推进同一时基）
func _now() -> float:
	if session == null or session.stage == null:
		return 0.0
	return session.stage.elapsed_seconds
