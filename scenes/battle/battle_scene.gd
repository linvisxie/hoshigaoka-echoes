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
const HUD_BAND_HEIGHT := 250.0
## 核心侧留白（以格为单位，纯渲染）
const CORE_MARGIN_TILES := 1.15
## 底部角色卡高度（参考画布单位）
const CARD_HEIGHT := 170.0

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

var session: BattleSession
var grid: BattleGrid

var _viewport_size: Vector2 = Vector2(1920, 1080)
## 渲染缩放：视口 / 参考画布（等比，取较小者）
var _render_scale: float = 1.0
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
func _update_render_scale() -> void:
	var ref_w: float = float(grid.reference_canvas_width) if grid != null else 1920.0
	var ref_h: float = float(grid.reference_canvas_height) if grid != null else 1080.0
	if ref_w <= 0.0 or ref_h <= 0.0:
		_render_scale = 1.0
		return
	_render_scale = minf(_viewport_size.x / ref_w, _viewport_size.y / ref_h)


## 参考画布单位 -> 当前屏幕像素
func _px(ref_px: float) -> float:
	return ref_px * _render_scale


func _build_battle() -> void:
	var stage_id := "1-1"
	var stage_config: Dictionary = DataRegistry.get_entry("stages", stage_id)
	if stage_config.is_empty():
		GameLog.error(TAG, "找不到关卡配置：%s" % stage_id)
		return

	# P0.4 开发专用入口：仅显式开关才在**内存副本**上覆盖可用角色；
	# 正式流程（不带 --dev-roster）完全走 data/stages/ch1/1-1.json 的原始解锁规则。
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

	session.outcome_decided.connect(_on_outcome_decided)
	session.core_hp_changed.connect(_on_core_hp_changed)
	session.enemy_reached_core.connect(_on_enemy_reached_core)
	session.wave_changed.connect(_on_wave_changed)
	session.character_healed.connect(_on_character_healed)
	_last_wave_number = session.stage.current_wave_number()

	# 角色卡顺序 = StageConfig.availableCharacters 顺序
	_roster = session.stage.available_characters.duplicate()

	GameLog.info(TAG, "%s 战斗场景就绪：stage=%s，核心 HP %d，Wave %d，计划出怪 %d，战场 3×6，渲染缩放 %.3f，可用角色 %s"
		% [App.stage_label(), stage_config.get("stageId", "?"), session.stage.core_hp_max,
			session.stage.total_wave_count(), session.stage.planned_enemy_count(), _render_scale,
			str(_roster)])


## 依据当前缩放与视口，计算战场在屏幕上的位置（整体居中，HUD 带位于上方）
func _update_layout() -> void:
	if grid == null:
		return
	var tile := _px(grid.tile_size_px)
	var grid_w := tile * float(grid.columns - 1)
	var core_margin := tile * CORE_MARGIN_TILES
	var total_w := core_margin + grid_w + tile * 0.5
	var board_h := _px(grid.lane_spacing_px) * float(grid.lanes - 1) + tile
	var hud_h := _px(HUD_BAND_HEIGHT)

	var left := (_viewport_size.x - total_w) * 0.5
	var top := hud_h + (_viewport_size.y - hud_h - board_h) * 0.5

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
	_refresh_debug_lines()
	_layout_buttons()
	queue_redraw()
	if was_running and session.is_decided():
		GameLog.info(TAG, "战斗结束：%s" % BattleTypes.outcome_name(session.outcome))
	if _autoplay:
		_drive_autoplay()


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
	_draw_core()
	_draw_deploy_feedback()
	_draw_characters()
	_draw_enemies()
	_draw_hud_text()
	_draw_wave_banner()
	_draw_character_card()
	_draw_character_panel()
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
	draw_circle(Vector2(core_x, mid_y), tile * 0.20, CORE_COLOR)
	draw_circle(Vector2(core_x, mid_y), tile * 0.20 + tile * 0.06 * ratio,
		Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.28), false, 3.0)

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

		var color := ENEMY_COLOR
		if e.enemy_id == "echo_runner":
			color = ENEMY_RUNNER_COLOR
		elif e.enemy_id == "echo_armored":
			color = ENEMY_ARMORED_COLOR
		var rect := Rect2(Vector2(px_x - size * 0.5, px_y - size * 0.5), Vector2(size, size))
		draw_rect(rect, color, true)
		draw_rect(rect, Color(1, 1, 1, 0.55), false, 1.5)
		# 敌人 HP 条
		var hp_ratio := 0.0
		if e.hp_max > 0:
			hp_ratio = clampf(float(e.hp) / float(e.hp_max), 0.0, 1.0)
		if hp_ratio < 1.0:
			draw_rect(Rect2(Vector2(px_x - size * 0.5, px_y - size * 0.5 - _px(9.0)),
				Vector2(size, _px(5.0))), Color(0.12, 0.12, 0.16), true)
			draw_rect(Rect2(Vector2(px_x - size * 0.5, px_y - size * 0.5 - _px(9.0)),
				Vector2(size * hp_ratio, _px(5.0))), Color(0.95, 0.45, 0.40), true)


## 部署反馈：选中时的合法/非法格高亮 + 悬停描边
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


## 调试信息（左上：AP / 核心 / 击杀等；右上：场上敌人列表）
func _draw_hud_text() -> void:
	var font := ThemeDB.fallback_font
	var x := _px(18.0)
	var y := _px(30.0)
	var lh := _px(21.0)
	draw_string(font, Vector2(x, y),
		"%s 战斗原型 — 3 路 × 6 格（占位图形，非最终美术）" % App.stage_label(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0)), Color(0.93, 0.95, 1.0))
	y += lh * 1.5
	for line: String in _debug_lines:
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_px(16.0)), Color(0.80, 0.85, 0.97))
		y += lh

	# 敌人列表（右上，最多 10 条）
	var ex := _viewport_size.x - _px(430.0)
	var ey := _px(150.0)
	draw_string(font, Vector2(ex, ey), "场上敌人", HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(_px(19.0)), Color(0.93, 0.95, 1.0))
	ey += lh * 1.4
	var shown := 0
	for e: EnemyRuntime in session.stage.enemies:
		if not e.is_active():
			continue
		if shown >= 10:
			draw_string(font, Vector2(ex, ey), "…", HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(_px(15.0)), Color(0.7, 0.74, 0.86))
			break
		draw_string(font, Vector2(ex, ey),
			"#%d %s lane=%d x=%.2f %s" % [
				e.instance_id, e.enemy_id, e.lane, e.logical_x,
				BattleTypes.enemy_state_name(e.state),
			], HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(15.0)), Color(0.80, 0.85, 0.97))
		ey += lh * 0.92
		shown += 1


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


## 结果界面（至少显示胜负、核心剩余 HP、击杀与漏怪数量 + 重新挑战 / 退出战斗）
func _draw_result_overlay() -> void:
	var summary := session.result_summary()
	if summary.is_empty():
		return
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, _viewport_size), Color(0.02, 0.03, 0.06, 0.72), true)

	var panel := Rect2(Vector2(_viewport_size.x * 0.5 - _px(380.0),
			_viewport_size.y * 0.5 - _px(290.0)), Vector2(_px(760.0), _px(580.0)))
	draw_rect(panel, PANEL_BG, true)
	draw_rect(panel, Color(0.55, 0.62, 0.85), false, 3.0)

	var victory := bool(summary["victory"])
	var title := "胜 利" if victory else "失 败"
	var tcol := Color(0.55, 0.95, 0.65) if victory else Color(0.95, 0.45, 0.45)
	var cx := _viewport_size.x * 0.5
	var tsize := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(64.0))).x
	draw_string(font, Vector2(cx - tsize * 0.5, panel.position.y + _px(96.0)), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(64.0)), tcol)

	var reason := "残响锚点守住了全部 Wave" if victory else "残响锚点已被击穿"
	var rsize := font.get_string_size(reason, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0))).x
	draw_string(font, Vector2(cx - rsize * 0.5, panel.position.y + _px(140.0)), reason,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0)), DIM_TEXT)

	# 结算数据
	var lines := [
		"核心剩余 HP：%d / %d" % [int(summary["coreHp"]), int(summary["coreHpMax"])],
		"击杀敌人：%d" % int(summary["kills"]),
		"漏怪数量：%d" % int(summary["leaked"]),
		"Wave 进度：%d / %d" % [int(summary["wave"]), int(summary["waveTotal"])],
		"角色撤退：%d 次（返还 %d AP）" % [int(summary["retreats"]), int(summary["retreatAp"])],
		"角色失能：%d" % int(summary["lost"]),
		"战斗时长：%.1f 秒" % float(summary["elapsed"]),
	]
	var ly := panel.position.y + _px(188.0)
	for line: String in lines:
		var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(21.0))).x
		draw_string(font, Vector2(cx - lw * 0.5, ly), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(21.0)), TEXT_COLOR)
		ly += _px(31.0)

	# 按钮
	_draw_button(_relaunch_rect, "重新挑战", Color(0.22, 0.45, 0.72))
	_draw_button(_quit_rect, "退出战斗", Color(0.42, 0.28, 0.32))


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
	queue_redraw()


func _on_core_hp_changed(_current: int, _max_hp: int) -> void:
	queue_redraw()


func _on_enemy_reached_core(_enemy: EnemyRuntime) -> void:
	pass


func _on_wave_changed(wave_number: int, total: int) -> void:
	_show_feedback("Wave %d / %d 开始" % [wave_number, total], Color(0.95, 0.85, 0.45))
