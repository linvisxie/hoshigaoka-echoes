## BattleScene — P0.1 战斗场景（可视化 + 调试信息）。
##
## 严格分层的表现层（L3 Presentation）：只读取 BattleSession / StageRuntime 的状态并绘制，
## 不含任何战斗规则；所有规则在 domain/battle 下。
##
## 渲染缩放（V2.1.4 明文）：tileSizePx=192 是 **1920×1080 参考画布**下的参数。
## 切换到 720p / 2K / 4K / UI 缩放时，**仅同比缩放画布转换**，
## 不改变射程、移动速度、阻挡/治疗/技能逻辑。本场景通过 _render_scale 实现该缩放，
## 逻辑层（BattleGrid / StageRuntime）始终只使用无量纲的 tile。
##
## P0.1 视觉为**临时占位图形**（色块/线段），非最终美术（正式资产见规格 J 章）。
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
const CORE_COLOR := Color(0.88, 0.34, 0.62)
const ENEMY_COLOR := Color(0.92, 0.42, 0.38)
const ENEMY_RUNNER_COLOR := Color(0.95, 0.68, 0.30)
const ENEMY_ARMORED_COLOR := Color(0.62, 0.66, 0.74)
const ENTRY_COLOR := Color(0.30, 0.34, 0.50)
const HUD_BG := Color(0.04, 0.05, 0.09, 0.82)

## 顶部 HUD 预留带高度（参考画布单位），战场排在其下方
const HUD_BAND_HEIGHT := 250.0
## 核心侧留白（以格为单位，纯渲染）
const CORE_MARGIN_TILES := 1.15

var session: BattleSession
var grid: BattleGrid

var _viewport_size: Vector2 = Vector2(1920, 1080)
## 渲染缩放：视口 / 参考画布（等比，取较小者）
var _render_scale: float = 1.0
## column 0 格中心的像素坐标
var _origin: Vector2 = Vector2.ZERO
var _debug_lines: Array[String] = []


func _ready() -> void:
	_viewport_size = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080)
	)
	_update_render_scale()
	_build_battle()
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
	var errs := session.setup(stage_config, enemy_table, grid)
	if not errs.is_empty():
		for e: String in errs:
			GameLog.error(TAG, "会话构建失败：%s" % e)
		return

	session.outcome_decided.connect(_on_outcome_decided)
	session.core_hp_changed.connect(_on_core_hp_changed)
	session.enemy_reached_core.connect(_on_enemy_reached_core)

	GameLog.info(TAG, "P0.1 战斗场景就绪：stage=%s，核心 HP %d，计划出怪 %d，战场 3×6，渲染缩放 %.3f"
		% [stage_config.get("stageId", "?"), session.stage.core_hp_max,
			session.stage.planned_enemy_count(), _render_scale])


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
	_refresh_debug_lines()
	queue_redraw()
	if was_running and session.is_decided():
		GameLog.info(TAG, "战斗结束：%s" % BattleTypes.outcome_name(session.outcome))


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


# ---------- 绘制 ----------

func _draw() -> void:
	if grid == null or session == null:
		return
	_draw_hud_backdrop()
	_draw_board()
	_draw_core()
	_draw_enemies()
	_draw_hud_text()


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


## 敌人（占位方块，按类型着色）
func _draw_enemies() -> void:
	var tile := _px(grid.tile_size_px)
	var spacing := _px(grid.lane_spacing_px)
	for e: EnemyRuntime in session.stage.enemies:
		if not e.is_active():
			continue
		# 逻辑 x 先按 V2.1.4 公式换算为参考画布像素，再同比缩放到当前屏幕
		var ref_px_x := grid.logical_to_px_x(e.logical_x, 0.0)
		var px_x := _origin.x + _px(ref_px_x)
		var px_y := _origin.y + float(e.lane) * spacing
		var size := tile * 0.42
		var color := ENEMY_COLOR
		if e.enemy_id == "echo_runner":
			color = ENEMY_RUNNER_COLOR
		elif e.enemy_id == "echo_armored":
			color = ENEMY_ARMORED_COLOR
		var rect := Rect2(Vector2(px_x - size * 0.5, px_y - size * 0.5), Vector2(size, size))
		draw_rect(rect, color, true)
		draw_rect(rect, Color(1, 1, 1, 0.55), false, 1.5)


## 调试信息（路线 / 敌人位置 / 核心 HP / 运行状态）
func _draw_hud_text() -> void:
	var font := ThemeDB.fallback_font
	var x := _px(18.0)
	var y := _px(30.0)
	var lh := _px(21.0)
	draw_string(font, Vector2(x, y),
		"P0.1 战斗原型 — 3 路 × 6 格（占位图形，非最终美术）",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0)), Color(0.93, 0.95, 1.0))
	y += lh * 1.5
	for line: String in _debug_lines:
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_px(16.0)), Color(0.80, 0.85, 0.97))
		y += lh

	# 敌人列表（右上，最多 10 条）
	var ex := _viewport_size.x - _px(430.0)
	var ey := _px(30.0)
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


func _refresh_debug_lines() -> void:
	if session == null or session.stage == null:
		return
	var s := session.stage
	_debug_lines = [
		"关卡：%s      渲染缩放：%.3f（参考画布 %d×%d）" % [
			s.stage_id, _render_scale,
			grid.reference_canvas_width, grid.reference_canvas_height,
		],
		"运行状态：%s%s" % [
			BattleTypes.outcome_name(session.outcome),
			"（已冻结）" if session.is_frozen() else "",
		],
		"核心 HP：%d / %d      漏怪结算次数：%d" % [
			s.core_hp, s.core_hp_max, s.core_damage_events,
		],
		"出怪：已生成 %d / 计划 %d      场上存活：%d" % [
			s.spawned_enemy_count(), s.planned_enemy_count(), s.enemies.size(),
		],
		"逻辑时间：%.2f s      格尺寸：%.0f px（参考）      路间距：%.0f px（参考）" % [
			s.elapsed_seconds, grid.tile_size_px, grid.lane_spacing_px,
		],
		"坐标系：lane 0=上段 / 1=中段 / 2=下段；column 0=核心侧，column 5=入口侧",
	]


func _on_outcome_decided(_outcome: int) -> void:
	queue_redraw()


func _on_core_hp_changed(_current: int, _max_hp: int) -> void:
	queue_redraw()


func _on_enemy_reached_core(_enemy: EnemyRuntime) -> void:
	pass
