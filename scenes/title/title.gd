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
## 新游戏进入命名及序章；继续游戏恢复剧情节点或校园；设置保存音量与显示。
## 标题只负责导航，存档事务由 CampaignFlow / SaveService 承担。
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
## 文字描边色：背景是亮部黄昏天空，正文一律带描边保证对比度
const OUTLINE := Color(0.03, 0.04, 0.09, 0.85)

## 主标题专用色（对照概念图：冰白亮芯 + 冷紫蓝中描边 + 深蓝黑外描边 + 淡青辉光）
const TITLE_FILL := Color(0.96, 0.98, 1.00)
const TITLE_OUTER := Color(0.05, 0.05, 0.16, 0.92)
const TITLE_MID := Color(0.36, 0.42, 0.92, 0.85)
const TITLE_GLOW := Color(0.55, 0.78, 1.00, 0.10)

## 标题与题词（纯展示文本；版本号与英文副标按概念图固定）
const TITLE_ZH := "星丘残响"
const TITLE_EN := "HOSHIGAOKA · ECHOES"
const TITLE_SUB := "—— 那些消失在夏夜里的声音"
## 题词按概念图拆成两行右对齐（第二行更长，自然形成错落）
const EPIGRAPH_L1 := "哪怕世界会遗忘，"
const EPIGRAPH_L2 := "这里的声音，也会留下回响。"
const SETTINGS_NOTE := "未实现"

## 参考画布下的标题块度量（对照概念图逐项量取后换算到 1920×1080）
const TITLE_X := 96.0
const TITLE_SIZE := 150.0
const TITLE_BASELINE := 250.0
const TITLE_EN_SIZE := 32.0
const TITLE_EN_BASELINE := 336.0
## fallback_font 无字距（tracking）控制，英文副标逐字绘制时手工加这么多间距
const TITLE_EN_TRACKING := 8.0
const TITLE_SUB_SIZE := 30.0
const TITLE_SUB_BASELINE := 382.0

## 菜单单一数据源：顺序即上下键顺序。
## disabled=true 的项不可点；已实现设置页面可正常进入。
##
## Alpha A0.7：新增「关卡选择」（stage_select）——在校园 Hub 与关卡情报流程落地前，
## 它是玩家**在界面上**唯一能选择 1-5 等关卡的入口（Retail 构建拒绝 --stage 开发参数）。
const MENU_ITEMS := [
	{"id": "continue", "zh": "继续游戏", "en": "CONTINUE", "icon": "icon_play",
		"disabled": false, "note": ""},
	{"id": "new_game", "zh": "新游戏", "en": "NEW GAME", "icon": "icon_home",
		"disabled": false, "note": ""},
	{"id": "settings", "zh": "设置", "en": "SETTINGS", "icon": "icon_settings",
		"disabled": false, "note": ""},
	{"id": "quit", "zh": "退出游戏", "en": "EXIT", "icon": "icon_cancel",
		"disabled": false, "note": ""},
]

## 参考画布下的菜单几何（左对齐的竖排）
## 行距对照概念图放宽（原 88+12=100 偏挤；概念图约为行高 92 + 间距 34）。
##
## 垂直预算（参考画布 1080）——**Alpha A0.7 加入「关卡选择」后由 4 行变 5 行，已重算**：
##   第 5 行下沿 = 436 + 4×(80+20) + 80 = 916，
##   与底部提示行（基线 964，字号 26，字顶约 945）留 29px 净空；
##   提示行之下才是版本行（基线 1032）。
##   上方：菜单顶 436 与标题块末行（TITLE_SUB_BASELINE 392）留 44px 净空。
##   三者（菜单 / 提示行 / 版本行）互不重叠——改动本组常量后必须重新核对这条等式。
const MENU_LEFT := 128.0
const MENU_TOP := 455.0
const MENU_WIDTH := 780.0
const MENU_ROW_H := 90.0
const MENU_GAP := 14.0

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
var _ambient_time := 0.0
var _quit_confirmation: Control


func _ready() -> void:
	AudioService.play_music("after_school")
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
		row.stacked_subtitle = true
		row.disabled_note = str(item["note"])
		if id == "continue" and not SaveService.has_save_on_disk():
			row.disabled = true
			row.disabled_note = "暂无存档"
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
		row.size = Vector2(_px(520.0), _px(MENU_ROW_H))
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
	if index != _selected:
		AudioService.play_sfx("ui_hover",-14.0)
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
	if _quit_confirmation != null and _quit_confirmation.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_quit_confirmation.hide()
			AudioService.play_sfx("ui_back",-5.0)
			accept_event()
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
	AudioService.play_sfx("select")
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
		"continue":
			if SaveService.get_current().is_empty():
				_show("还没有有效存档，请选择新游戏。", WARN)
			else:
				CampaignFlow.resume()
		"new_game":
			SceneRouter.go_to("new_game")
		"settings":
			SceneRouter.go_to("settings")
		"stage_select":
			_open_stage_select()
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


## 打开关卡选择画面（Alpha A0.7）。
##
## 标题及校园均可打开；新游戏与继续游戏走 CampaignFlow 的剧情及存档恢复。
## 本函数只做一次路由切换，不复制任何解锁规则——解锁判定全在 StageSelectScreen 内。
func _open_stage_select() -> void:
	if not ResourceLoader.exists(str(SceneRouter.SCENES.get("stage_select", ""))):
		_show("关卡选择画面缺失，无法打开", WARN)
		GameLog.error(TAG, "关卡选择场景资源不存在")
		return
	_busy = true
	if not SceneRouter.go_to("stage_select"):
		_busy = false
		_show("打开关卡选择失败", WARN)


func _quit() -> void:
	if _quit_confirmation != null:
		_quit_confirmation.show()
		return
	_quit_confirmation = Control.new()
	_quit_confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quit_confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	_quit_confirmation.theme = GameSkin.make_theme()
	add_child(_quit_confirmation)
	var veil := ColorRect.new()
	veil.color = Color(0.015,0.025,0.06,0.76)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quit_confirmation.add_child(veil)
	var panel := Panel.new()
	panel.position = (_viewport-Vector2(_px(720),_px(330)))*0.5
	panel.size = Vector2(_px(720),_px(330))
	panel.add_theme_stylebox_override("panel",GameSkin.glass(GameSkin.GOLD,.96))
	_quit_confirmation.add_child(panel)
	var title := Label.new()
	title.text = "暂别星丘？"
	title.position = Vector2(_px(42),_px(34))
	title.size = Vector2(_px(636),_px(60))
	title.add_theme_font_override("font",GameSkin.serif())
	title.add_theme_font_size_override("font_size",int(_px(36)))
	panel.add_child(title)
	var note := Label.new()
	note.text = "已保存的观测记录会保留。"
	note.position = Vector2(_px(42),_px(114))
	note.add_theme_font_size_override("font_size",int(_px(25)))
	note.add_theme_color_override("font_color",GameSkin.MUTED)
	panel.add_child(note)
	for i: int in range(2):
		var b := Button.new()
		b.text = "留在这里" if i==0 else "退出游戏"
		b.position = Vector2(_px(42+330*i),_px(220))
		b.size = Vector2(_px(306),_px(68))
		b.add_theme_font_size_override("font_size",int(_px(27)))
		GameSkin.style_button(b,i==0)
		b.pressed.connect(func() -> void:
			if i==0:
				_quit_confirmation.hide()
				AudioService.play_sfx("ui_back",-5.0)
			else:
				_busy = true
				App.request_quit())
		panel.add_child(b)


func _show(text: String, color: Color) -> void:
	_feedback = text
	_feedback_color = color
	_feedback_timer = 3.5
	queue_redraw()


# ============================================================ 每帧

func _process(delta: float) -> void:
	_ambient_time += delta
	queue_redraw()
	if _feedback_timer > 0.0:
		_feedback_timer = maxf(0.0, _feedback_timer - delta)
		queue_redraw()


# ============================================================ 绘制（背景 + 文本装饰）

func _draw() -> void:
	var font := GameSkin.serif()
	_draw_background()
	if font == null:
		return
	_draw_title_block(font)
	_draw_left_panel(font)
	_draw_epigraph(font)
	_draw_version(font)
	_draw_hint(font)
	_draw_petals()


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
		# Architectural sign is separate from the clean plate and uses the formal crest.
		var offset := Vector2((_viewport.x-dw)*0.5,(_viewport.y-dh)*0.5)
		var crest_rect := Rect2(offset+Vector2(709,488)*s,Vector2(62,67)*s)
		draw_rect(crest_rect,Color("152139"))
		draw_texture_rect(GameSkin.crest(),crest_rect.grow(-3*s),false,Color("c2a66d"))
		var plaque_font := GameSkin.serif()
		var plaque := "私立星丘高等学校"
		for i: int in range(plaque.length()):
			draw_string(plaque_font,offset+Vector2(728,580+float(i)*23)*s,plaque.substr(i,1),HORIZONTAL_ALIGNMENT_LEFT,-1,int(20*s),Color("c5a06b"))
	else:
		_draw_gradient_fallback()
	_draw_atmosphere()


## 纯色渐变回退：黄昏橙紫天空 + 校门剪影 + 星光裂隙。
## 只使用 draw_polygon / draw_rect / draw_circle，保证无外部依赖、绝不打空。
## 天空同样用**逐顶点颜色插值**，避免出现横向色带。
func _draw_gradient_fallback() -> void:
	var w := _viewport.x
	var h := _viewport.y
	var stops := [
		{"y": 0.0, "c": GRAD_TOP},
		{"y": 0.55, "c": GRAD_MID},
		{"y": 0.85, "c": GRAD_LOW},
		{"y": 1.0, "c": GRAD_BOTTOM},
	]
	for i: int in range(stops.size() - 1):
		var a: Dictionary = stops[i]
		var b: Dictionary = stops[i + 1]
		var y0 := float(a["y"]) * h
		var y1 := float(b["y"]) * h
		draw_polygon(
			PackedVector2Array([Vector2(0.0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0.0, y1)]),
			PackedColorArray([
				a["c"], a["c"], b["c"], b["c"],
			]))


## 大气层：星光裂隙 + 渐隐遮罩（贴图存在与否都会绘制，属装饰而非替代品）
##
## 注意：这里**一律使用渐变细带**而不是单块半透明 draw_rect——
## 单块矩形会在贴图上留下肉眼可见的硬边（实测截图里表现为一条竖缝 + 一条横缝），
## 而细带渐隐不会产生任何可见接缝。
func _draw_atmosphere() -> void:
	var shade := Color(0.02, 0.03, 0.07)
	# 左侧渐隐：保证标题与菜单文字在亮部天空上依然清晰。
	# 对照概念图逐轮下调（0.46 → 0.40），并且**分两段线性衰减**近似曲线：
	#   x 0→45%：0.40 → 0.06（文字所在区仍有足够压暗）
	#   x 45%→100%：0.06 → 0（到画面右缘恰好为 0，**没有硬边**）
	# 上一轮是「0.46 铺到 61.5% 就截断」，那条截断线在亮部天空上留下一道
	# 肉眼可见的竖直硬边（实测截图里像一块糊上去的暗色面板）。
	_draw_h_fade(Rect2(0.0, 0.0, _viewport.x * 0.45, _viewport.y), 0.40, 0.06, shade)
	_draw_h_fade(Rect2(_viewport.x * 0.45, 0.0, _viewport.x * 0.55, _viewport.y), 0.06, 0.0, shade)
	# 顶部渐隐：只覆盖顶部一条带（0.28 → 0.14），到带底恰好衰减到 0。
	# 同样刻意不铺满全高——铺满会在画面中部留下常驻压暗，把校舍与樱花压灰。
	_draw_v_fade(Rect2(0.0, 0.0, _viewport.x, _viewport.y * 0.18), 0.14, 0.0, shade)
	# 底部渐隐（地平线以下压暗，让题词与版本行稳定可读）。
	# 从 60% 处 alpha=0 起步，**本身就是从 0 开始**，不会有硬边，保持原范围。
	_draw_v_fade(Rect2(0.0, _viewport.y * 0.60, _viewport.x, _viewport.y * 0.40), 0.0, 0.50, shade)


## 竖直方向渐隐。
##
## 用**带逐顶点颜色的单个多边形**绘制：Godot 会在顶点之间插值颜色，
## 因此得到的是真正平滑的渐变。
## （曾用「细带堆叠」近似，实测在天空亮部会留下肉眼可见的横向条纹，已弃用。）
func _draw_v_fade(rect: Rect2, top_alpha: float, bottom_alpha: float, col: Color) -> void:
	var x0 := rect.position.x
	var x1 := rect.position.x + rect.size.x
	var y0 := rect.position.y
	var y1 := rect.position.y + rect.size.y
	draw_polygon(
		PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		PackedColorArray([
			Color(col.r, col.g, col.b, top_alpha), Color(col.r, col.g, col.b, top_alpha),
			Color(col.r, col.g, col.b, bottom_alpha), Color(col.r, col.g, col.b, bottom_alpha),
		]))


## 水平方向渐隐（同样用逐顶点颜色插值，避免条纹）
func _draw_h_fade(rect: Rect2, left_alpha: float, right_alpha: float, col: Color) -> void:
	var x0 := rect.position.x
	var x1 := rect.position.x + rect.size.x
	var y0 := rect.position.y
	var y1 := rect.position.y + rect.size.y
	draw_polygon(
		PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		PackedColorArray([
			Color(col.r, col.g, col.b, left_alpha), Color(col.r, col.g, col.b, right_alpha),
			Color(col.r, col.g, col.b, right_alpha), Color(col.r, col.g, col.b, left_alpha),
		]))


## 带描边的文字绘制：先沿 8 个方向画深色描边，再画正文。
## 标题画面的背景是**亮部黄昏天空**，纯色文字（尤其细体英文）会被冲淡，
## 因此正文一律带描边；描边宽度随缩放同比。
func _draw_text_outlined(font: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	var o := _px(0.7)
	for dx: float in [-o, 0.0, o]:
		for dy: float in [-o, 0.0, o]:
			if is_zero_approx(dx) and is_zero_approx(dy):
				continue
			draw_string(font, pos + Vector2(dx, dy), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, OUTLINE)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_title_block(font: Font) -> void:
	var x := _px(TITLE_X)
	var zh_size := int(_px(TITLE_SIZE))

	var logo := ArtRegistry.load_texture("res://assets/art/ui/title_logo.png")
	if logo != null:
		draw_texture_rect(logo, Rect2(_px(75), _px(45), _px(840), _px(280)), false)
	else:
		draw_string(font, Vector2(x, _px(TITLE_BASELINE)), TITLE_ZH, HORIZONTAL_ALIGNMENT_LEFT, -1, zh_size, TITLE_FILL)

	# 英文副标：fallback_font 没有字距控制，因此**逐字绘制**并手工加 tracking，
	# 让 HOSHIOKA · RESONANCE 像概念图那样疏朗，而不是挤成一团。
	var en_size := int(_px(23.0))
	var ey := _px(TITLE_EN_BASELINE)
	var ex := x + _px(50)
	var en_w := 0.0
	for i: int in range(TITLE_EN.length()):
		var ch := TITLE_EN.substr(i, 1)
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, en_size).x
		_draw_text_outlined(font, Vector2(ex, ey), ch, en_size, ACCENT)
		ex += cw + _px(TITLE_EN_TRACKING)
		en_w += cw + _px(TITLE_EN_TRACKING)
	en_w -= _px(TITLE_EN_TRACKING)
	# 副标下的分隔线：宽度**精确等于副标本身**、向右渐隐，
	# 左端与主标题、下方小字同一左缘（三者对齐）。
	_draw_title_rule(Vector2(x, ey + _px(14.0)), en_w, 0.0, 0.50)

	# 一行小字
	_draw_text_outlined(font, Vector2(x, _px(TITLE_SUB_BASELINE)), TITLE_SUB,
		int(_px(27)), Color("e3deed"))


## 主标题的淡青辉光：在 8 个方向画两层低不透明度副本，形成柔光边缘。
func _draw_title_glow(font: Font, pos: Vector2, text: String, fs: int) -> void:
	for d: float in [2.0, 3.4]:
		var o := _px(d)
		for dx: float in [-o, 0.0, o]:
			for dy: float in [-o, 0.0, o]:
				if is_zero_approx(dx) and is_zero_approx(dy):
					continue
				draw_string(font, pos + Vector2(dx, dy), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TITLE_GLOW)


## 指定描边宽度的文字绘制（与 _draw_text_outlined 同一套做法，宽度可控）。
func _draw_text_outlined_at(font: Font, pos: Vector2, text: String, fs: int,
		col: Color, o: float) -> void:
	for dx: float in [-o, 0.0, o]:
		for dy: float in [-o, 0.0, o]:
			if is_zero_approx(dx) and is_zero_approx(dy):
				continue
			draw_string(font, pos + Vector2(dx, dy), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## 标题块用的细装饰线：从 from_alpha 渐隐到 to_alpha，避免生硬的实心横线。
func _draw_title_rule(from: Vector2, width: float, from_alpha: float, to_alpha: float) -> void:
	var c := Color(ACCENT.r, ACCENT.g, ACCENT.b)
	var x0 := from.x
	var x1 := from.x + _px(width)
	var y := from.y
	draw_polygon(
		PackedVector2Array([
			Vector2(x0, y), Vector2(x1, y),
			Vector2(x1, y + maxf(1.0, _px(2.0))), Vector2(x0, y + maxf(1.0, _px(2.0))),
		]),
		PackedColorArray([
			Color(c.r, c.g, c.b, from_alpha), Color(c.r, c.g, c.b, to_alpha),
			Color(c.r, c.g, c.b, to_alpha), Color(c.r, c.g, c.b, from_alpha),
		]))


## 左侧菜单的可读性由 _draw_atmosphere() 的左侧渐隐负责。
## 这里**刻意不画实心面板**：实测单块半透明 draw_rect 会在背景贴图上留下
## 肉眼可见的硬边（竖缝 + 横缝），渐隐方案没有任何可见接缝。
func _draw_left_panel(_font: Font) -> void:
	_draw_h_fade(Rect2(_px(128), _px(455), _px(560), _px(402)), 0.48, 0.0, Color("0c1430"))


func _draw_petals() -> void:
	for i: int in range(22):
		var seed := float(i)
		var x := fposmod(seed * 137.7 + _ambient_time * (18 + fmod(seed, 4) * 5), REF_W + 80) - 40
		var y := fposmod(seed * 73.3 + _ambient_time * (10 + fmod(seed, 3) * 3), REF_H + 80) - 40
		var center := Vector2(_px(x), _px(y + sin(_ambient_time * 0.8 + seed) * 20))
		var radius := _px(3 + fmod(seed, 4))
		var angle := _ambient_time * 0.45 + seed
		var axis := Vector2(cos(angle),sin(angle)) * radius
		var side := axis.orthogonal() * 0.38
		draw_colored_polygon(PackedVector2Array([center-axis,center+side,center+axis,center-side]),Color(0.96,0.64,0.78,0.24 + fmod(seed,3)*0.10))


func _draw_epigraph(font: Font) -> void:
	# 概念图里题词是**右下角两行右对齐**（第二行更长，自然错落）。
	# 右缘与版本行、提示行互不重叠：题词在 y≈884/924，提示行在 y≈942。
	var size := int(_px(30.0))
	var lh := _px(40.0)
	var right := _viewport.x - _px(96.0)
	var col := Color(0.90, 0.88, 0.80)
	var w2 := font.get_string_size(EPIGRAPH_L2, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_draw_text_outlined(font, Vector2(right - w2, _viewport.y - _px(156.0) + lh),
		EPIGRAPH_L2, size, col)
	var w1 := font.get_string_size(EPIGRAPH_L1, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_draw_text_outlined(font, Vector2(right - w1, _viewport.y - _px(156.0)), EPIGRAPH_L1,
		size, col)


## 左下角版本行：版本号取自 App.APP_VERSION（不硬编码）
func _draw_version(font: Font) -> void:
	var text := "Ver %s · Windows · 第一章" % App.APP_VERSION
	_draw_text_outlined(font, Vector2(_px(96.0), _viewport.y - _px(48.0)), text,
		int(_px(20.0)), DIM)


func _draw_hint(font: Font) -> void:
	# 操作提示 / 临时反馈放在底部**单独一行**（参考画布基线 964，字号 26）。
	# 与左下版本行（基线 1032）、右下题词第二行（基线 924）互不重叠：
	# 提示行字顶约 945，在菜单第 5 行下沿（916）之下、题词第二行（924）之下，
	# 且提示行居中、题词靠右，横向也不重叠。
	# **不得**把提示行下移到版本行同一基线上（那是上一轮修过的重叠 bug）。
	# Alpha A0.7 加入第 5 行后已重算：916 → 945 仍有 29px 净空。
	var text := _feedback if _feedback_timer > 0.0 else "↑ ↓ 选择     Enter 确认"
	var col := _feedback_color if _feedback_timer > 0.0 else Color(0.58, 0.64, 0.78)
	var size := int(_px(20.0))
	_draw_text_outlined(font, Vector2(_px(128), _viewport.y - _px(136.0)),
		text, size, col)
