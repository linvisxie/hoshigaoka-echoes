## StageSelectScreen — Alpha A0.7 关卡选择（《星丘残响》）。
##
## 为什么存在：标题画面的「继续游戏 / 新游戏」只会进入 PrototypeEntry.default_stage_id()
## 决策的**单一默认关**（Prototype 构建 = 演示关 p1_0_demo，Retail = 1-1）。在正式的
## 校园 Hub（res://scenes/home/home.tscn，规格 J0.4，**尚未实现**）与「关卡情报」流程
## 落地之前，玩家在界面上**没有任何办法选择 1-5 或其它关卡**——只能靠开发参数
## `--stage=1-5`，而 Retail 构建按 BuildMode 纪律拒绝开发参数。
##
## 因此本场景只做**最小但真实**的一件事：列出第一章中**确有内容**的关卡，
## 按解锁规则判定可否进入，并把选择结果交给 PrototypeEntry + SceneRouter。
##
## 职责边界（L3 Presentation 层）：
##   本文件**不含**战斗、成长、经济或存档规则；对存档只有一处**只读**调用
##   （StageRewardService.is_first_cleared()），绝不写入、绝不新增存档字段、
##   绝不调用 SaveService.commit() / new_game()。
##
## 不做的东西（纪律：不虚构入口）：
##   - 不做校园 Hub、不做关卡情报页、不做编队确认、不做剧情——它们各自属后续阶段；
##   - 不列出 1-6～1-10：它们目前是 Phase 0 空占位（enemySpawnTimeline 为空），
##     列出来就是假装可玩；
##   - 不显示推荐等级：StageConfig 里**没有** `_recommendedLevel` 这类机器可读字段
##     （只在 `_spec` 自由文本里提到「表 73：推荐等级 Lv.5～7」），规格若要求显示，
##     应由数据层补字段后再显示，**不得**在表现层解析自由文本或凭印象编造。
##
## 解锁规则（规格未明文，取保守解释）：
##   V2.1.4 G 章表 51/52 给的是「教学顺序」与角色解锁节点；J0.3 只说 1-1 首胜并完成
##   战后剧情后「正式解锁校园 Hub、关卡入口和后续系统入口」，**没有**逐关解锁的明文。
##   因此按最保守规则实现：**1-1 恒可进；1-N 需 1-(N-1) 首通**。
##   （注释位置即定论位置；若后续规格补齐逐关解锁条件，只改 is_unlocked().）
##
## Prototype 与 Retail 的差别（诚实标注，不伪装成已解锁）：
##   Prototype 构建额外允许直选**全部已实现关卡**，但这些行必须打上
##   「Alpha 预览 · 未按主线解锁」徽标；Retail 构建严格按解锁规则，未解锁行灰显不可点。
##   该判定走 direct_select_allowed()（可注入，便于测试；不散落读 feature tag）。
##
## 缩放方案（与 battle_scene.gd / title.gd 一致）：以 1920×1080 为参考画布，
## scale = min(vp.x / 1920, vp.y / 1080)，全部尺寸经 _px() 换算。
##
## 垂直预算（参考画布 1080）：
##   第 6 行（返回标题）下沿 = 320 + 5×(84+18) + 84 = 914，
##   与底部提示行（基线 964，字顶约 943）留 29px 净空。改动本组常量后必须重核该等式。
extends Control

const TAG := "StageSelect"

## 参考画布（J1：设计分辨率 1920×1080，16:9 主基线）
const REF_W := 1920.0
const REF_H := 1080.0

# ---- 配色（与 title.gd 同一套：深蓝黑底 + 紫蓝，可交互冰蓝）----
const GRAD_TOP := Color(0.07, 0.07, 0.18)
const GRAD_MID := Color(0.22, 0.14, 0.34)
const GRAD_LOW := Color(0.44, 0.26, 0.30)
const GRAD_BOTTOM := Color(0.10, 0.09, 0.17)
const RIFT_COLOR := Color(0.48, 0.56, 0.98, 0.16)
const TEXT := Color(0.93, 0.96, 1.0)
const DIM := Color(0.62, 0.68, 0.82)
const ACCENT := Color(0.58, 0.90, 1.0)
const WARN := Color(0.95, 0.72, 0.35)
const OUTLINE := Color(0.03, 0.04, 0.09, 0.85)

# ---- 布局（参考画布）----
const HEADER_TITLE_X := 200.0
const HEADER_TITLE_Y := 150.0
const HEADER_TITLE_SIZE := 72.0
const HEADER_EN_Y := 208.0
const HEADER_EN_SIZE := 30.0
const HEADER_NOTE_Y := 262.0
const HEADER_NOTE_SIZE := 28.0

const LIST_LEFT := 200.0
const LIST_TOP := 320.0
const LIST_WIDTH := 1520.0
const ROW_H := 84.0
const ROW_GAP := 18.0

const HINT_SIZE := 28.0
const HINT_Y := 116.0
const VERSION_SIZE := 28.0
const VERSION_Y := 48.0

## 「返回标题」行的 id（不是关卡，只用于把玩家送回标题画面）
const BACK_ID := "__back__"
const BACK_TITLE := "返回标题"
const BACK_EN := "BACK"

## Prototype 直选徽标文案（必须诚实：不得伪装成已解锁）
const ALPHA_BADGE := "Alpha 预览 · 未按主线解锁"

## 构建模式覆盖（**仅供测试注入**）：
##   -1 = 未注入（生产路径，读 BuildMode.is_prototype()）
##    0 = 强制按 Retail 处理
##    1 = 强制按 Prototype 处理
## 用静态变量而不是实例状态：测试不必先实例化场景即可断言判定结果，
## 而场景本身也走同一个函数，不存在「测试测的是另一套逻辑」的缝隙。
static var build_mode_override: int = -1

var _viewport: Vector2 = Vector2(REF_W, REF_H)
var _scale: float = 1.0
var _bg_tex: Texture2D = null

## 行规格（与 _rows 同序）；每项由 row_spec() 产出
var _specs: Array[Dictionary] = []
var _rows: Array[TitleMenuRow] = []
var _selected: int = 0

var _feedback: String = ""
var _feedback_color: Color = TEXT
var _feedback_timer: float = 0.0
var _busy: bool = false
var _native_page: CampusScreen
var _stage_buttons: Array[Button] = []


# ============================================================
#  纯函数（可在测试里直接断言，不依赖场景树）
# ============================================================

## 是否允许「直选全部已实现关卡」（Prototype 构建的 Alpha 预览能力）。
## Retail 构建下一律 false——开发/预览入口不得绕过正式解锁条件。
static func direct_select_allowed() -> bool:
	if build_mode_override == 1:
		return true
	if build_mode_override == 0:
		return false
	return BuildMode.is_prototype()


## 解析 "C-N" 形式的关卡 id；返回 [chapter, index]，不匹配返回空数组。
static func parse_stage_id(stage_id: String) -> Array:
	var parts := stage_id.split("-")
	if parts.size() != 2:
		return []
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return []
	return [int(parts[0]), int(parts[1])]


## 关卡排序键：章号 × 1000 + 关序。非法 id 排在最后。
static func stage_order_key(stage_id: String) -> int:
	var parsed := parse_stage_id(stage_id)
	if parsed.is_empty():
		return 1 << 30
	return int(parsed[0]) * 1000 + int(parsed[1])


## 该关卡是否为「有真实内容」的关卡。
##
## 判据与 StageRewardService.cfg_has_content() **完全一致**：enemySpawnTimeline 非空。
## 1-6～1-10 目前是 Phase 0 占位（timeline 为空、coreHp=0），因此不会出现在列表里。
static func is_implemented(stage_config: Dictionary) -> bool:
	return StageRewardService.cfg_has_content(stage_config)


## 从 id 列表中筛出已实现关卡，并按章节顺序排序。
## config_lookup: Callable(stage_id: String) -> Dictionary（关卡正文）
static func implemented_stage_ids(ids: Array, config_lookup: Callable) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in ids:
		var sid := str(raw)
		if parse_stage_id(sid).is_empty():
			continue
		var cfg_v: Variant = config_lookup.call(sid)
		if typeof(cfg_v) != TYPE_DICTIONARY:
			continue
		if not is_implemented(cfg_v as Dictionary):
			continue
		out.append(sid)
	out.sort_custom(func(a: String, b: String) -> bool:
		return stage_order_key(a) < stage_order_key(b))
	return out


## 关卡是否已解锁（**规格未明文，取保守解释**：1-1 恒可进；1-N 需 1-(N-1) 首通）。
## cleared_lookup: Callable(stage_id: String) -> bool（首通查询，只读存档）
static func is_unlocked(stage_id: String, cleared_lookup: Callable) -> bool:
	var parsed := parse_stage_id(stage_id)
	if parsed.is_empty():
		return false
	var chapter := int(parsed[0])
	var index := int(parsed[1])
	if chapter != 1:
		# 第一章以外的解锁条件尚无规格依据，一律视为未解锁（不猜）。
		return false
	if index <= 1:
		return true
	var prev := "%d-%d" % [chapter, index - 1]
	return bool(cleared_lookup.call(prev))


## 关卡是否可进入：严格解锁，或（Prototype 下）直选已实现关卡。
static func is_selectable(stage_id: String, cleared_lookup: Callable, allow_direct: bool) -> bool:
	if allow_direct:
		return true
	return is_unlocked(stage_id, cleared_lookup)


## 未解锁原因（点击禁用行时给玩家的明确反馈）。
static func locked_reason(stage_id: String) -> String:
	var parsed := parse_stage_id(stage_id)
	if parsed.is_empty():
		return "关卡 id 非法"
	var index := int(parsed[1])
	if index <= 1:
		return ""
	return "需先通关 %d-%d" % [int(parsed[0]), index - 1]


## 构造一行的完整显示规格（纯函数，测试可直接断言）。
##
## 返回 {
##   "id": String, "title": String, "subtitle": String,
##   "status": String, "badge": String, "badgeWarn": bool,
##   "disabled": bool, "disabledNote": String,
## }
static func row_spec(stage_id: String, cleared_lookup: Callable, allow_direct: bool) -> Dictionary:
	var cleared := bool(cleared_lookup.call(stage_id))
	var unlocked := is_unlocked(stage_id, cleared_lookup)
	var badge := ""
	var badge_warn := false
	var disabled := false
	var disabled_note := ""

	if unlocked:
		pass
	elif allow_direct:
		# Prototype 直选：可用，但必须打上诚实的预览徽标
		badge = ALPHA_BADGE
		badge_warn = true
	else:
		disabled = true
		disabled_note = locked_reason(stage_id)

	return {
		"id": stage_id,
		"title": "关卡 %s" % stage_id,
		"subtitle": "",
		"status": "已通关" if cleared else "未通关",
		"badge": badge,
		"badgeWarn": badge_warn,
		"disabled": disabled,
		"disabledNote": disabled_note,
	}


## 标题画面「关卡选择」行要跳转的场景 key（与 SceneRouter.SCENES 对齐）。
const SCENE_KEY := "stage_select"


# ============================================================
#  生命周期
# ============================================================

func _ready() -> void:
	_viewport = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", REF_W),
		ProjectSettings.get_setting("display/window/size/viewport_height", REF_H))
	if _viewport.x <= 0.0 or _viewport.y <= 0.0:
		_viewport = Vector2(REF_W, REF_H)
	_scale = minf(_viewport.x / REF_W, _viewport.y / REF_H)
	if _scale <= 0.0:
		_scale = 1.0

	# 背景资产缺失一律返回 null，这里容忍并回退到渐变绘制（**绝不黑屏**）
	_bg_tex = ArtRegistry.title_background()

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_rows()
	_build_native_page()
	_select_first_enabled()
	GameLog.info(TAG, "关卡选择就绪（构建模式=%s，直选=%s，可进关卡=%d，背景=%s）" % [
		BuildMode.mode_name(), str(direct_select_allowed()),
		_specs.size() - 1,
		"已加载" if _bg_tex != null else "缺失→渐变回退"])
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


func _px(v: float) -> float:
	return v * _scale


# ============================================================
#  数据：可进关卡 / 首通查询
# ============================================================

## 首通查询（**只读**存档；本场景绝不写存档）
func _cleared_lookup(stage_id: String) -> bool:
	return StageRewardService.is_first_cleared(stage_id)


## ch1 中确有内容的关卡 id（升序）
func _implemented_ids() -> Array[String]:
	return implemented_stage_ids(
		DataRegistry.get_ids("stages"),
		func(sid: String) -> Dictionary: return PrototypeEntry.load_stage_config(sid))


# ============================================================
#  行构建与布局
# ============================================================

func _build_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lookup := Callable(self, "_cleared_lookup")
	var allow := direct_select_allowed()
	for sid: String in _implemented_ids():
		if not allow and not CampaignFlow.can_open_stage(sid):
			continue
		out.append(row_spec(sid, lookup, allow))
	out.append({
		"id": BACK_ID,
		"title": BACK_TITLE,
		# BACK 作为**右对齐英文副标**（label_en），而不是紧跟中文的状态标注——
		# 这样它与上面各关卡行的排版语言一致。
		"subtitle": BACK_EN,
		"status": "",
		"badge": "",
		"badgeWarn": false,
		"disabled": false,
		"disabledNote": "",
	})
	return out


## 构建菜单行。
##
## 与 title.gd 同一套做法：行**已在 stage_select.tscn 里声明**（可在编辑器里选中调整），
## 本函数只按 _specs 这一份数据源注入文案/状态；.tscn 缺行时才现场补建，
## 因此「改了数据但忘了改场景文件」不会少一行，也不会出现重复行。
func _build_rows() -> void:
	_specs = _build_specs()
	_rows.clear()
	var container := get_node_or_null("MenuList") as Control
	if container == null:
		GameLog.error(TAG, "缺少 MenuList 容器节点，关卡列表无法构建")
		return
	# 清掉不再需要的旧行（例如数据层把某关改回占位后，场景文件里仍留着那一行）
	var wanted := {}
	for spec: Dictionary in _specs:
		wanted[str(spec["id"])] = true
	for child: Node in container.get_children():
		if child is TitleMenuRow and not wanted.has((child as TitleMenuRow).item_id):
			container.remove_child(child)
			child.queue_free()

	for spec: Dictionary in _specs:
		var id := str(spec["id"])
		var row := container.get_node_or_null("Row_%s" % id) as TitleMenuRow
		if row == null:
			row = TitleMenuRow.new()
			row.name = "Row_%s" % id
			container.add_child(row)
		row.item_id = id
		row.label_zh = str(spec["title"])
		row.label_en = str(spec["subtitle"])
		row.status_text = str(spec["status"])
		row.icon_name = "icon_home" if id == BACK_ID else "icon_confirm"
		row.disabled = bool(spec["disabled"])
		row.disabled_note = str(spec["disabledNote"])
		row.extra_note = str(spec["badge"])
		row.extra_note_warn = bool(spec["badgeWarn"])
		if not row.activated.is_connected(_on_row_activated):
			row.activated.connect(_on_row_activated)
		if not row.hover_changed.is_connected(_on_row_hover_changed):
			row.hover_changed.connect(_on_row_hover_changed)
		_rows.append(row)
	_layout_rows()


func _layout_rows() -> void:
	var container := get_node_or_null("MenuList") as Control
	if container == null:
		return
	var n := _specs.size()
	container.position = Vector2(_px(LIST_LEFT), _px(LIST_TOP))
	container.size = Vector2(_px(LIST_WIDTH),
		_px(float(n) * ROW_H + float(maxi(0, n - 1)) * ROW_GAP))
	var y := 0.0
	for i: int in range(_rows.size()):
		var row := _rows[i]
		row.position = Vector2(0.0, y)
		row.size = Vector2(_px(LIST_WIDTH), _px(ROW_H))
		row.set_ui_scale(_scale)
		y += _px(ROW_H + ROW_GAP)


# ============================================================
#  选中状态
# ============================================================

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
	for i: int in range(_stage_buttons.size()):
		GameSkin.style_button(_stage_buttons[i],i == _selected)

func _build_native_page() -> void:
	for row: TitleMenuRow in _rows:
		row.hide()
	_native_page = CampusScreen.new()
	add_child(_native_page)
	_native_page.set_background("bg_title_gate")
	_native_page.add_gate_plaque()
	_native_page.page_heading("第一章 · 新学期的残响", "调查记录  /  选择地点查看情报与出战角色")
	_stage_buttons.clear()
	for i: int in range(_specs.size()):
		var spec: Dictionary = _specs[i]
		var sid := str(spec.id)
		if sid == BACK_ID:
			var back := _native_page.button_at("返回校园" if bool(CampaignFlow.state().get("campaign_active",false)) else "返回标题",Rect2(75,970,370,75),func() -> void: _activate(i))
			_stage_buttons.append(back)
			continue
		var cfg := DataRegistry.get_entry("stages",sid)
		var x := 75+int(i%4)*450
		var y := 205+int(i/4)*244
		var card := _native_page.button_at("",Rect2(x,y,425,225),func() -> void: _activate(i))
		card.disabled = bool(spec.disabled)
		card.tooltip_text = GameLocale.text(str(spec.disabledNote) if card.disabled else "查看关卡情报与出战确认")
		card.mouse_entered.connect(func() -> void: _set_selected(i))
		_stage_buttons.append(card)
		var image := _native_page.texture_at(ArtRegistry.stage_background(sid),Rect2(x+8,y+8,409,115))
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.clip_contents = true
		if card.disabled: image.modulate = Color(0.38,0.43,0.55)
		_native_page.label_at("%s  %s" % [sid,cfg.get("stageName","")],Rect2(x+20,y+135,390,42),28,CampusScreen.WHITE if not card.disabled else CampusScreen.MUTED)
		var state := "✓ 调查完成" if _cleared_lookup(sid) else (str(spec.disabledNote) if card.disabled else "前往调查  →")
		if not str(spec.get("badge", "")).is_empty():
			state = str(spec.badge)
		_native_page.label_at(state,Rect2(x+20,y+182,390,35),22,CampusScreen.GOLD if _cleared_lookup(sid) else CampusScreen.BLUE)
	_native_page.fade_in_content()


## 上下移动选中项（跳过禁用行：禁用项不能作为当前项被确认）
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


# ============================================================
#  输入
# ============================================================

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
				_back_to_title()
			_:
				return
		accept_event()


# ============================================================
#  动作
# ============================================================

func _activate(index: int) -> void:
	if index < 0 or index >= _specs.size():
		return
	var spec: Dictionary = _specs[index]
	var id := str(spec["id"])

	if id == BACK_ID:
		_back_to_title()
		return

	if bool(spec["disabled"]):
		# 未解锁：只给明确反馈（缺什么条件），绝不进入战斗
		var note := str(spec["disabledNote"])
		_show("关卡 %s 尚未解锁：%s" % [id, note] if note != "" else "关卡 %s 尚未解锁" % id, WARN)
		GameLog.info(TAG, "关卡 %s 为未解锁态（%s）" % [id, note])
		return

	if not PrototypeEntry.has_stage(id):
		_show("关卡 %s 配置缺失，无法进入" % id, WARN)
		GameLog.error(TAG, "关卡 %s 取不到配置" % id)
		return

	if not ResourceLoader.exists(str(SceneRouter.SCENES.get("battle", ""))):
		_show("战斗场景缺失，无法进入", WARN)
		GameLog.error(TAG, "战斗场景资源不存在")
		return

	var badge := str(spec["badge"])
	if badge != "":
		GameLog.info(TAG, "进入关卡 %s（%s）" % [id, badge])
	else:
		GameLog.info(TAG, "进入关卡 %s" % id)

	_busy = true
	if not CampaignFlow.open_stage(id,"stage_select"):
		_busy = false
		_show("进入战斗失败", WARN)


func _back_to_title() -> void:
	_busy = true
	if not SceneRouter.go_to("home" if bool(CampaignFlow.state().get("campaign_active", false)) else "title"):
		_busy = false
		_show("返回标题失败", WARN)


func _show(text: String, color: Color) -> void:
	_feedback = text
	_feedback_color = color
	_feedback_timer = 4.0
	queue_redraw()


func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer = maxf(0.0, _feedback_timer - delta)
		queue_redraw()


# ============================================================
#  绘制
# ============================================================

func _draw() -> void:
	if _native_page != null:
		return
	var font := ThemeDB.fallback_font
	_draw_background()
	if font == null:
		return
	_draw_header(font)
	_draw_hint(font)
	_draw_version(font)


## 背景：等比覆盖裁剪（cover）；贴图缺失时走渐变回退，**绝不黑屏**
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
			PackedColorArray([a["c"], a["c"], b["c"], b["c"]]))


## 大气层：与 title.gd 同一套做法——**细带渐隐**而不是整块半透明 rect
## （整块 rect 会在贴图上留下肉眼可见的硬边）。菜单文字所在区压暗以保证可读性。
func _draw_atmosphere() -> void:
	var cx := _viewport.x * 0.5
	var cy := _viewport.y * 0.45
	for i: int in range(6):
		var r := (0.10 + 0.055 * float(i)) * minf(_viewport.x, _viewport.y)
		var a := RIFT_COLOR.a * (1.0 - float(i) / 6.0)
		draw_circle(Vector2(cx, cy), r, Color(RIFT_COLOR.r, RIFT_COLOR.g, RIFT_COLOR.b, a * 0.3))
	var shade := Color(0.02, 0.03, 0.07)
	_draw_v_fade(Rect2(0.0, 0.0, _viewport.x, _viewport.y * 0.22), 0.32, 0.0, shade)
	_draw_v_fade(Rect2(0.0, _viewport.y * 0.62, _viewport.x, _viewport.y * 0.38), 0.0, 0.46, shade)
	_draw_h_fade(Rect2(0.0, 0.0, _viewport.x * 0.30, _viewport.y), 0.26, 0.0, shade)


func _draw_v_fade(rect: Rect2, top_alpha: float, bottom_alpha: float, col: Color) -> void:
	var x0 := rect.position.x
	var x1 := rect.position.x + rect.size.x
	var y0 := rect.position.y
	var y1 := rect.position.y + rect.size.y
	draw_polygon(
		PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		PackedColorArray([
			Color(col.r, col.g, col.b, top_alpha), Color(col.r, col.g, col.b, top_alpha),
			Color(col.r, col.g, col.b, bottom_alpha), Color(col.r, col.g, col.b, bottom_alpha)]))


func _draw_h_fade(rect: Rect2, left_alpha: float, right_alpha: float, col: Color) -> void:
	var x0 := rect.position.x
	var x1 := rect.position.x + rect.size.x
	var y0 := rect.position.y
	var y1 := rect.position.y + rect.size.y
	draw_polygon(
		PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		PackedColorArray([
			Color(col.r, col.g, col.b, left_alpha), Color(col.r, col.g, col.b, right_alpha),
			Color(col.r, col.g, col.b, right_alpha), Color(col.r, col.g, col.b, left_alpha)]))


func _draw_text_outlined(font: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	var o := maxf(1.0, _px(2.0))
	for dx: float in [-o, 0.0, o]:
		for dy: float in [-o, 0.0, o]:
			if is_zero_approx(dx) and is_zero_approx(dy):
				continue
			draw_string(font, pos + Vector2(dx, dy), GameLocale.text(text),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, OUTLINE)
	draw_string(font, pos, GameLocale.text(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_header(font: Font) -> void:
	_draw_text_outlined(font, Vector2(_px(HEADER_TITLE_X), _px(HEADER_TITLE_Y)),
		"关卡选择", int(_px(HEADER_TITLE_SIZE)), TEXT)
	var en := "STAGE SELECT"
	var ex := _px(HEADER_TITLE_X)
	var en_size := int(_px(HEADER_EN_SIZE))
	for i: int in range(en.length()):
		var ch := en.substr(i, 1)
		var cw := font.get_string_size(GameLocale.text(ch), HORIZONTAL_ALIGNMENT_LEFT, -1, en_size).x
		_draw_text_outlined(font, Vector2(ex, _px(HEADER_EN_Y)), ch, en_size, ACCENT)
		ex += cw + _px(8.0)

	_draw_text_outlined(font, Vector2(_px(HEADER_TITLE_X), _px(HEADER_NOTE_Y)),
		_build_mode_note(), int(_px(HEADER_NOTE_SIZE)), DIM if not direct_select_allowed() else WARN)


## 顶部构建模式说明（诚实告知本轮次的解锁口径，不伪造「已完成」）
func _build_mode_note() -> String:
	if _implemented_ids().is_empty():
		return "本章暂无可进入的关卡（关卡内容尚未接入）"
	if direct_select_allowed():
		return "Prototype 构建：已实现关卡可直接进入，带「%s」徽标的行未按主线解锁" % ALPHA_BADGE
	return "Retail 构建：按主线进度解锁（1-1 恒可进，其余需先通关上一关）"


func _draw_hint(font: Font) -> void:
	var text := _feedback if _feedback_timer > 0.0 else "↑ ↓ 选择　Enter / Space 确认　Esc 返回标题　鼠标可直接点击"
	var col := _feedback_color if _feedback_timer > 0.0 else Color(0.58, 0.64, 0.78)
	var size := int(_px(HINT_SIZE))
	var w := font.get_string_size(GameLocale.text(text), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_draw_text_outlined(font, Vector2((_viewport.x - w) * 0.5, _viewport.y - _px(HINT_Y)),
		text, size, col)


func _draw_version(font: Font) -> void:
	var text := "Ver %s · %s" % [App.APP_VERSION, BuildMode.mode_name()]
	_draw_text_outlined(font, Vector2(_px(HEADER_TITLE_X), _viewport.y - _px(VERSION_Y)),
		text, int(_px(VERSION_SIZE)), DIM)
