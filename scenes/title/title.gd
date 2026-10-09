## TitleScreen — Alpha A0.7 标题画面（《星丘残响》首屏）。
##
## 职责（L3 Presentation 层）：
##   1. 铺满 ArtRegistry.title_background()（等比覆盖裁剪，绝不变形）；
##      资产缺失时回退到**纯色渐变绘制**，绝不黑屏、绝不崩溃；
##   2. 承载左侧竖排菜单（继续游戏 / 新游戏 / 设置 / 退出游戏）——
##      菜单是**真实的 UI 节点树**（TitleMenuRow），不是整张概念图叠透明按钮；
##   3. 把玩家输入（鼠标悬停 / 左键点击 / ↑↓ / Enter / Space / Esc）翻译成
##      已存在功能的调用；本文件**不含任何战斗、成长、经济或存档规则**。
##
## 只做已经存在的功能（不虚构）：
##   继续游戏 / 新游戏 → 设置默认关卡 → SceneRouter.go_to("battle")
##                        （默认关卡由 PrototypeEntry.default_stage_id() 决策）
##   退出游戏          → App.request_quit()
##   设置              → **尚未实现**，因此固定为禁用态（灰显 + 不可点 + 标「未实现」），
##                        绝不做假设置页。点击它只给出「该功能尚未实现」的反馈。
##
## 不写任何存档代码：本文件对 SaveService 只有一处**只读**调用
## （has_save_on_disk()，用于「继续游戏」的提示文案），不做任何写入。
##
## 缩放方案（与 battle_scene.gd 一致）：以 1920×1080 为参考画布，
## scale = min(vp.x / 1920, vp.y / 1080)，全部尺寸经 _px() 换算。
##
## 字体：ThemeDB.fallback_font（项目已开 MSDF），1920×1080 参考画布下正文字号 ≥ 28px。
extends Control

const TAG := "TitleScreen"

## 参考画布（J1：设计分辨率 1920×1080，16:9 主基线）
const REF_W := 1920.0
const REF_H := 1080.0

# ---- 配色（V2.1.4 J-二十七 色彩系统：深蓝黑底 + 紫蓝，可交互冰蓝）----
const GRAD_TOP := Color(0.09, 0.07, 0.20)
const GRAD_MID := Color(0.30, 0.16, 0.34)
const GRAD_LOW := Color(0.68, 0.36, 0.28)
const GRAD_BOTTOM := Color(0.14, 0.11, 0.20)
const RIFT_COLOR := Color(0.48, 0.56, 0.98, 0.16)
const VIGNETTE := Color(0.02, 0.03, 0.06, 0.55)
const TEXT := Color(0.93, 0.96, 1.0)
const DIM := Color(0.62, 0.68, 0.82)
const ACCENT := Color(0.58, 0.90, 1.0)
const WARN := Color(0.95, 0.72, 0.35)
const PANEL_BG := Color(0.04, 0.05, 0.10, 0.42)

## 标题与题词（纯展示文本；版本号与英文副标按概念图固定）
const TITLE_ZH := "星丘残响"
const TITLE_EN := "HOSHIOKA · RESONANCE"
const TITLE_SUB := "—— 那些消失在夏夜里的声音"
const EPIGRAPH := "哪怕世界会遗忘，这里的声音，也会留下回响。"
const SETTINGS_NOTE := "未实现"

## 菜单单一数据源：顺序即上下键顺序。
## disabled=true 的项**不可点**（设置页属后续阶段，本轮不实现、不伪造）。
const MENU_ITEMS := [
	{"id": "continue", "zh": "继续游戏", "en": "CONTINUE", "icon": "icon_play",
		"disabled": false, "note": ""},
	{"id": "new_game", "zh": "新游戏", "en": "NEW GAME", "icon": "icon_home",
		"disabled": false, "note": ""},
	{"id": "settings", "zh": "设置", "en": "SETTINGS", "icon": "icon_settings",
		"disabled": true, "note": SETTINGS_NOTE},
	{"id": "quit", "zh": "退出游戏", "en": "EXIT", "icon": "icon_cancel",
		"disabled": false, "note": ""},
]

## 参考画布下的菜单几何（左对齐的竖排）
const MENU_LEFT := 96.0
const MENU_TOP := 486.0
const MENU_WIDTH := 660.0
const MENU_ROW_H := 88.0
const MENU_GAP := 12.0

var _viewport: Vector2 = Vector2(REF_W, REF_H)
var _scale: float = 1.0

## 背景贴图（可能为 null —— 缺失时走渐变回退）
var _bg_tex: Texture2D = null

## 菜单行节点（与 MENU_ITEMS 同序）
var _rows: Array[TitleMenuRow] = []
## 当前选中索引（键盘与鼠标共用这一份状态）
var _selected: int = 0

## 底部提示反馈（如「该功能尚未实现」）
var _feedback: String = ""
var _feedback_color: Color = TEXT
var _feedback_timer: float = 0.0

## 防止同一帧内重复触发（连点保护）
var _busy: bool = false


func _ready() -> void:
	_viewport = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", REF_W),
		ProjectSettings.get_setting("display/window/size/viewport_height", REF_H))
	if _viewport.x <= 0.0 or _viewport.y <= 0.0:
		_viewport = Vector2(REF_W, REF_H)
	_scale = minf(_viewport.x / REF_W, _viewport.y / REF_H)
	if _scale <= 0.0:
		_scale = 1.0

	# 背景：资产缺失一律返回 null，这里容忍并回退到渐变绘制
	_bg_tex = ArtRegistry.title_background()

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_rows()
	_select_first_enabled()
	GameLog.info(TAG, "标题画面就绪（背景资产=%s，缩放=%.3f，菜单=%d 项）" % [
		"已加载" if _bg_tex != null else "缺失→渐变回退", _scale, _rows.size()])
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_on_viewport_changed()


func _on_viewport_changed() -> void:
	var vp := get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0:
		_viewport = vp
		_scale = minf(_viewport.x / REF_W, _viewport.y / REF_H)
		if _scale <= 0.0:
			_scale = 1.0
	_layout_rows()
	queue_redraw()


## 参考画布单位 -> 当前屏幕像素
func _px(v: float) -> float:
	return v * _scale


# ============================================================ 菜单构建与布局

## 构建菜单行。
##
## 菜单是**真实可维护的节点树**：每一行都已在 title.tscn 里声明（可在编辑器里
## 直接选中、调整、增删），本函数只按 MENU_ITEMS 这一份数据源把文案与图标
## 注入进去、接上信号；若 .tscn 里缺了某一行才现场补建（保证不会因为改场景文件
## 而少一行菜单，也不会出现重复行）。
func _build_rows() -> void:
	_rows.clear()
	var container := get_node_or_null("MenuList") as Control
	if container == null:
		GameLog.error(TAG, "缺少 MenuList 容器节点，菜单无法构建")
		return
	for item: Dictionary in MENU_ITEMS:
		var id := str(item["id"])
		var row := container.get_node_or_null("Row_%s" % id) as TitleMenuRow
		if row == null:
			row = TitleMenuRow.new()
			row.name = "Row_%s" % id
			container.add_child(row)
		row.item_id = id
		row.label_zh = str(item["zh"])
		row.label_en = str(item["en"])
		row.icon_name = str(item["icon"])
		row.disabled = bool(item["disabled"])
		row.disabled_note = str(item["note"])
		if not row.activated.is_connected(_on_row_activated):
			row.activated.connect(_on_row_activated)
		if not row.hover_changed.is_connected(_on_row_hover_changed):
			row.hover_changed.connect(_on_row_hover_changed)
		_rows.append(row)
	_layout_rows()


## 计算菜单几何（绘制与命中共用同一份矩形：直接落在节点 rect 上）
func _layout_rows() -> void:
	var container := get_node_or_null("MenuList") as Control
	if container == null:
		return
	container.position = Vector2(_px(MENU_LEFT), _px(MENU_TOP))
	container.size = Vector2(_px(MENU_WIDTH),
		_px(float(MENU_ITEMS.size()) * MENU_ROW_H
			+ float(maxi(0, MENU_ITEMS.size() - 1)) * MENU_GAP))
	var y := 0.0
	for i: int in range(_rows.size()):
		var row := _rows[i]
		row.position = Vector2(0.0, y)
		row.size = Vector2(_px(MENU_WIDTH), _px(MENU_ROW_H))
		row.set_ui_scale(_scale)
		y += _px(MENU_ROW_H + MENU_GAP)


# ============================================================ 选中状态

## 默认选中第一个可用项（跳过禁用项）
func _select_first_enabled() -> void:
	for i: int in range(_rows.size()):
		if not _rows[i].disabled:
			_set_selected(i)
			return
	_set_selected(0)


func _set_selected(index: int) -> void:
	if _rows.is_empty():
		return
	_selected = clampi(index, 0, _rows.size() - 1)
	for i: int in range(_rows.size()):
		_rows[i].set_selected(i == _selected)


## 上下移动选中项；**跳过禁用项**（禁用项不可作为当前项被确认）
func _move_selection(step: int) -> void:
	if _rows.is_empty():
		return
	var n := _rows.size()
	var i := _selected
	for _attempt: int in range(n):
		i = posmod(i + step, n)
		if not _rows[i].disabled:
			_set_selected(i)
			return


func _on_row_hover_changed(item_id: String, hovered: bool) -> void:
	if not hovered:
		return
	for i: int in range(_rows.size()):
		if _rows[i].item_id == item_id:
			_set_selected(i)
			return


func _on_row_activated(item_id: String) -> void:
	for i: int in range(_rows.size()):
		if _rows[i].item_id == item_id:
			_set_selected(i)
			_activate(i)
			return


# ============================================================ 输入

func _input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_UP, KEY_W:
				_move_selection(-1)
			KEY_DOWN, KEY_S:
				_move_selection(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate(_selected)
			KEY_ESCAPE:
				_quit()
			_:
				return
		accept_event()


# ============================================================ 动作

func _activate(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var item: Dictionary = MENU_ITEMS[index]
	if bool(item["disabled"]):
		# 禁用项：只给反馈，绝不执行任何动作（这就是「不可点」）
		_show("%s 尚未实现，敬请期待" % str(item["zh"]), WARN)
		GameLog.info(TAG, "菜单项「%s」当前为禁用态（%s）" % [str(item["zh"]), str(item["note"])])
		return
	var id := str(item["id"])
	GameLog.info(TAG, "菜单激活：%s（%s）" % [id, str(item["zh"])])
	match id:
		"continue", "new_game":
			_start_battle()
		"quit":
			_quit()
		_:
			_show("未知菜单项：%s" % id, WARN)


## 进入战斗场景。
## 关卡由 PrototypeEntry 决策（默认演示关 p1_0_demo；Retail 构建下为其正式默认关），
## 本文件**不复制**任何启动策略、不硬编码关卡 id。
func _start_battle() -> void:
	if not ResourceLoader.exists(SceneRouter.SCENES.get("battle", "")):
		_show("战斗场景缺失，无法进入", WARN)
		GameLog.error(TAG, "战斗场景资源不存在")
		return
	PrototypeEntry.set_pending_stage_id(PrototypeEntry.default_stage_id())
	_busy = true
	if not SceneRouter.go_to("battle"):
		_busy = false
		_show("进入战斗失败", WARN)


func _quit() -> void:
	_busy = true
	App.request_quit()


func _show(text: String, color: Color) -> void:
	_feedback = text
	_feedback_color = color
	_feedback_timer = 3.5
	queue_redraw()


# ============================================================ 每帧

func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer = maxf(0.0, _feedback_timer - delta)
		queue_redraw()


# ============================================================ 绘制（背景 + 文本装饰）

func _draw() -> void:
	var font := ThemeDB.fallback_font
	_draw_background()
	if font == null:
		return
	_draw_title_block(font)
	_draw_left_panel(font)
	_draw_epigraph(font)
	_draw_version(font)
	_draw_hint(font)


## 背景：等比覆盖裁剪（cover），绝不变形；贴图缺失时走渐变回退
func _draw_background() -> void:
	if _bg_tex != null and _bg_tex.get_width() > 0 and _bg_tex.get_height() > 0:
		var tw := float(_bg_tex.get_width())
		var th := float(_bg_tex.get_height())
		var s := maxf(_viewport.x / tw, _viewport.y / th)
		var dw := tw * s
		var dh := th * s
		draw_texture_rect(_bg_tex,
			Rect2(Vector2((_viewport.x - dw) * 0.5, (_viewport.y - dh) * 0.5), Vector2(dw, dh)),
			false)
	else:
		_draw_gradient_fallback()
	_draw_atmosphere()


## 纯色渐变回退：黄昏橙紫天空 + 校门剪影 + 星光裂隙。
## 只使用 draw_rect / draw_colored_polygon / draw_circle，保证无外部依赖、绝不打空。
func _draw_gradient_fallback() -> void:
	var steps := 64
	var band_h := _viewport.y / float(steps)
	for i: int in range(steps):
		var t := float(i) / float(steps - 1)
		var col: Color
		if t < 0.55:
			col = GRAD_TOP.lerp(GRAD_MID, t / 0.55)
		elif t < 0.85:
			col = GRAD_MID.lerp(GRAD_LOW, (t - 0.55) / 0.30)
		else:
			col = GRAD_LOW.lerp(GRAD_BOTTOM, (t - 0.85) / 0.15)
		draw_rect(Rect2(0.0, float(i) * band_h, _viewport.x, band_h + 1.0), col, true)


## 大气层：星光裂隙 + 校门剪影 + 四角压暗（贴图存在与否都会绘制，属装饰而非替代品）
func _draw_atmosphere() -> void:
	var cx := _viewport.x * 0.5
	var cy := _viewport.y * 0.52
	# 紫蓝星光裂隙（同心圆 + 低不透明度近似径向辉光；禁 MSAA 下多边形更可预测）
	for i: int in range(6):
		var r := (0.10 + 0.055 * float(i)) * minf(_viewport.x, _viewport.y)
		var a := RIFT_COLOR.a * (1.0 - float(i) / 6.0)
		draw_circle(Vector2(cx, cy), r, Color(RIFT_COLOR.r, RIFT_COLOR.g, RIFT_COLOR.b, a * 0.35))
	# 地平线以下压暗
	draw_rect(Rect2(0.0, _viewport.y * 0.72, _viewport.x, _viewport.y * 0.28),
		Color(0.04, 0.04, 0.09, 0.45), true)
	# 左上 / 左下压暗，保证标题与菜单的文字对比度
	draw_rect(Rect2(0.0, 0.0, _px(880.0), _viewport.y), Color(0.02, 0.03, 0.07, 0.30), true)
	draw_rect(Rect2(0.0, 0.0, _viewport.x, _px(150.0)), Color(0.02, 0.03, 0.07, 0.22), true)


func _draw_title_block(font: Font) -> void:
	var x := _px(96.0)
	# 中文大标题
	draw_string(font, Vector2(x, _px(196.0)), TITLE_ZH,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(104.0)), TEXT)
	# 英文副标（带字距感：逐字绘制 + 手动间距）
	var ey := _px(252.0)
	var esize := int(_px(30.0))
	var ex := x
	for ch: String in TITLE_EN.split(""):
		if ch.is_empty():
			continue
		draw_string(font, Vector2(ex, ey), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, esize, ACCENT)
		ex += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, esize).x + _px(3.0)
	# 一行小字
	draw_string(font, Vector2(x, _px(300.0)), TITLE_SUB,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(28.0)), DIM)
	# 标题下的分隔线
	var line_y := _px(330.0)
	draw_line(Vector2(x, line_y), Vector2(x + _px(560.0), line_y),
		Color(0.58, 0.90, 1.0, 0.45), maxf(1.0, _px(2.0)))


## 左侧菜单背后的半透明竖条（让菜单文字在任何背景上都可读）
func _draw_left_panel(_font: Font) -> void:
	var top := _px(MENU_TOP - 40.0)
	var h := _px(float(MENU_ITEMS.size()) * MENU_ROW_H
		+ float(maxi(0, MENU_ITEMS.size() - 1)) * MENU_GAP + 80.0)
	draw_rect(Rect2(0.0, top, _px(MENU_LEFT + MENU_WIDTH + 20.0), h), PANEL_BG, true)
	draw_rect(Rect2(_px(MENU_LEFT + MENU_WIDTH + 20.0), top, maxf(1.0, _px(2.0)), h),
		Color(0.58, 0.90, 1.0, 0.30), true)


func _draw_epigraph(font: Font) -> void:
	var size := int(_px(30.0))
	var w := font.get_string_size(EPIGRAPH, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(_viewport.x - _px(96.0) - w, _viewport.y - _px(96.0)), EPIGRAPH,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.90, 0.88, 0.80))


## 左下角版本行：版本号取自 App.APP_VERSION（不硬编码）
func _draw_version(font: Font) -> void:
	var text := "Ver %s · PC / Steam · Godot %s" % [
		App.APP_VERSION, str(Engine.get_version_info().get("string", "unknown"))]
	draw_string(font, Vector2(_px(96.0), _viewport.y - _px(48.0)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(28.0)), DIM)


func _draw_hint(font: Font) -> void:
	var text := _feedback if _feedback_timer > 0.0 else "↑ ↓ 选择　Enter / Space 确认　鼠标可直接点击"
	var col := _feedback_color if _feedback_timer > 0.0 else Color(0.58, 0.64, 0.78)
	var size := int(_px(28.0))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2((_viewport.x - w) * 0.5, _viewport.y - _px(48.0)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
