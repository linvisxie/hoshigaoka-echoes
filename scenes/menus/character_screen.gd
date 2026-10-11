## CharacterScreen — Alpha A0.1 角色培养界面（V2.1.4 H 章三十三 成长 UI）。
##
## 职责（L3 Presentation 层）：
##   只显示 CharacterGrowthService 的状态、把玩家输入转发成服务调用。
##   **不含任何成长规则**：经验表、突破成本、上限全部来自数据文件；
##   本文件不出现 10/20/30/40、800/2000/… 之类的数值。
##
## 规格依据：
##   H 章三十三 表 74：角色页面底部标签「培养 / 技能 / 装备 / 档案 / 故事」。
##     A0.1 只实现「培养」页；其余四页属后续阶段（A0.5 装备 / A0.7 档案与故事）。
##   H 章三十四 升级操作体验：
##     「允许长按或滑块一次投入多份学习记录」→ 本界面提供 1 / 5 / 最大 三档快捷投入 + 逐份按钮
##     「升级前实时预览等级和属性变化」→ 悬停投入量时显示预览
##     「达到突破上限时明确提示，而不是吞掉经验」→ 到上限时禁用投料并显示原因
##     「材料不足时点击材料可查看稳定获取途径」→ 材料不足时显示来源文案（来自 currencies.json）
##   J 章：PC 战斗/养成界面在 1280×720 到 4K 下可读；禁止大面积无功能装饰小字。
##
## 美术接入（本轮）：
##   正式美术资产通过 ArtRegistry 解析。**任何资源缺失都回退到几何绘制**，
##   美术永远不是本界面可运行的硬依赖（ArtRegistry 契约：缺失返回 null）。
##   本文件只做表现，不新增任何领域规则，也不复制任何成长数值。
extends Control

const TAG := "CharacterScreen"

## 参考画布（V2.1.4 J1：设计分辨率 1920×1080）
const REF_W := 1920.0
const REF_H := 1080.0

## 页面配色（V2.1.4 J-二十七 色彩系统：主 UI 深蓝黑 + 紫蓝，可交互冰蓝，正向薄荷绿）
const BG := Color(0.055, 0.063, 0.098)
const PANEL_BG := Color(0.055, 0.066, 0.128, 0.94)
const CARD_BG := Color(0.090, 0.110, 0.200, 0.90)
const CARD_BG_HOVER := Color(0.130, 0.165, 0.280, 0.94)
const CARD_SELECTED := Color(0.14, 0.21, 0.34, 0.96)
const CARD_SELECTED_HOVER := Color(0.18, 0.28, 0.43, 0.96)
const TEXT := Color(0.90, 0.94, 1.0)
const DIM := Color(0.62, 0.68, 0.82)
const FAINT := Color(0.42, 0.47, 0.62)
const ACCENT := Color(0.42, 0.76, 0.98)      # 冰蓝：可交互 / AP
const POSITIVE := Color(0.45, 0.95, 0.62)    # 薄荷绿：治疗 / 正向
## 增量数字：比 POSITIVE 更亮，深底上更醒目（J 章：正向反馈必须一眼看到）
const POSITIVE_DELTA := Color(0.64, 1.0, 0.76)
## 增量闪烁的外发光色（脉冲时叠在数字外侧）
const POSITIVE_GLOW := Color(0.40, 1.0, 0.60)
const WARN := Color(0.95, 0.72, 0.35)
## 资源不足：明确的暖红，与「可满足」的薄荷绿形成一眼可辨的对立。
## 不能用 WARN（橙黄）——它同时也是普通提示色，玩家分不清"警告"与"不够"。
const INSUFFICIENT := Color(1.0, 0.44, 0.40)
const DANGER := Color(0.98, 0.30, 0.42)
const BORDER := Color(0.30, 0.42, 0.66, 0.85)
const BORDER_SOFT := Color(0.24, 0.30, 0.46, 0.80)
const BUTTON := Color(0.16, 0.21, 0.36)
const BUTTON_HOVER := Color(0.30, 0.46, 0.74)
const BUTTON_DISABLED := Color(0.105, 0.115, 0.155)
## 已选中的快捷投入档位（比 hover 更实，表示"当前生效"而非"鼠标在这"）
const BUTTON_ACTIVE := Color(0.22, 0.52, 0.52)
const BUTTON_BORDER := Color(0.40, 0.56, 0.86)
const BUTTON_BORDER_HOVER := Color(0.72, 0.90, 1.0)
const BUTTON_BORDER_ACTIVE := Color(0.55, 1.0, 0.92)
const BUTTON_BORDER_DISABLED := Color(0.24, 0.26, 0.34)
const TEXT_DISABLED := Color(0.42, 0.45, 0.55)
## 鼠标停在禁用按钮上：偏红描边，明确"这里点不动"，而不是无反应
const BUTTON_BORDER_REJECT := Color(0.92, 0.42, 0.42)

## 文字深色描边（ThemeDB.fallback_font 无粗体字面且是 MSDF，
## 细笔画压在深色/亮背景上会发虚；描边不改字号就能显著提升可读性）。
## 小字 1px、大字 2px（参考画布像素，随 _scale 同比缩放）。
const OUTLINE_COLOR := Color(0.012, 0.020, 0.045, 0.95)
const OUTLINE_PX_SMALL := 0.0
const OUTLINE_PX_LARGE := 0.0
## 达到该字号起用粗描边
const OUTLINE_BOLD_FROM := 32.0

## 数字固定宽度槽位（位数变化时后续内容不跳动）。
## 分级设定：槽位过宽会在数字与后续文字之间留出难看的空档，
## 过窄则起不到稳定作用，因此按各处的量级分别取位数。
const LEVEL_DIGITS := 2
const CURRENCY_DIGITS := 5
const STAT_DIGITS := 4
## 突破成本的「持有/需求」对：每侧最多按这么多位预留
const COST_PAIR_DIGITS := 4

## 图标：**统一从 64px 源图缩放**，避免 32/64 混用导致同一行图标大小不一。
const ICON_SRC_SIZE := 64
const ICON_SIZE_CHIP := 34.0
const ICON_SIZE_BUTTON := 30.0
const ICON_SIZE_STAT := 32.0
const ICON_SIZE_COST := 28.0
const ICON_SIZE_ROW := 34.0
const ICON_SIZE_EMBLEM := 64.0

## 属性增量动画时长（秒）
const FLOAT_LIFE := 1.4
## 预览增量的闪烁衰减速度（每秒）
const PULSE_DECAY := 2.2

## 背景遮罩：让背景退到 UI 之后，保证文字可读（与 battle_scene 的 BG_SCRIM 同思路）
const SCRIM := Color(0.020, 0.028, 0.058, 0.48)

## 字号（1920×1080 参考画布下全部 ≥ 22px；随窗口同比缩放）
const F_TINY := 22.0
const F_LABEL := 24.0
const F_BODY := 26.0
const F_NAME := 32.0
const F_TITLE := 42.0
const F_BIG_LEVEL := 60.0

## 快捷投入档位（本数）。「最大」按当前可支付与上限自动计算。
const QUICK_STEPS := [1, 5]

## 背景环境（纯表现层选择；资产缺失由 ArtRegistry 返回 null，本界面回退纯色底）
const DEFAULT_ENV := "bg_env_classroom_dusk"
const ENV_BY_CHARACTER := {
	"amamiya_mio": "bg_env_classroom_dusk",
	"kamiya_yuma": "bg_env_corridor_dusk",
	"ogawa_yui": "bg_env_gym_night",
}

## 资源图标映射（currencies.json 的 id → ArtRegistry 图标名）。
## 图标名只是美术资源键，不含也不推导任何经济数值。
const CURRENCY_ICON := {
	"school_coin": "icon_school_coin",
	"study_record": "icon_study_record",
	"club_badge": "icon_memento",
	"echo_crystal": "icon_rift_shard",
	"equipment_part": "icon_material",
}

## 属性图标映射（compute_stats() 的键 → 图标名）
const STAT_ICON := {
	"hp": "icon_heal",
	"attack": "icon_attack_up",
	"defense": "icon_defense_up",
	"healPower": "icon_consumable",
}

var _svc: CharacterGrowthService = null

## 角色卡矩形（与角色 id 同序）
var _card_rects: Array[Rect2] = []
var _card_ids: Array[String] = []
var _selected_id: String = ""

## 按钮矩形
var _btn_rects: Array[Dictionary] = []
var _mouse_pos: Vector2 = Vector2.ZERO

## 布局矩形（_layout 计算，_draw 与命中共用）
var _header_rect: Rect2 = Rect2()
var _list_rect: Rect2 = Rect2()
var _info_rect: Rect2 = Rect2()
var _panel_rect: Rect2 = Rect2()
var _portrait_rect: Rect2 = Rect2()
var _exp_rect: Rect2 = Rect2()
var _nodes_rect: Rect2 = Rect2()
var _stats_rect: Rect2 = Rect2()

## 反馈文案
var _feedback: String = ""
var _feedback_color: Color = TEXT
var _feedback_timer: float = 0.0

## 实时预览：本次拟投入的本数（0 = 不预览）
var _preview_count: int = 0
var _preview_item: String = "study_record_short"

## 数字槽位字体（等宽数字 + 固定宽度；缺失时回退 fallback_font）
var _num_font: Font = null

## 属性增量的「闪烁 + 上浮」动画状态。
##   _delta_pulse: 闪烁强度 0..1，预览变化时置 1，逐帧衰减到 0
##   _delta_float: 浮起偏移（秒→像素），让 +N 短暂上浮再落位
##   _flash_rows: 升级/突破后需要瞬时高亮的属性行，值=剩余秒数
##   _flash_kind: 该高亮是"升级"(绿) 还是"突破"(冰蓝)
var _delta_pulse: float = 0.0
var _delta_float: float = 0.0
var _delta_key: String = ""
var _flash_rows: Dictionary = {}
var _flash_kind: String = "levelup"
## 上一次预览的 (角色, 份数, 道具) 组合，用于识别"预览真的变了"才触发闪烁
var _last_preview_sig: String = ""

var _viewport: Vector2 = Vector2(1920, 1080)
var _scale: float = 1.0

## 表现层缓存（StyleBox / 渐变贴图 / 贴图）。配色集合固定，缓存规模有界。
var _sb_cache: Dictionary = {}
var _grad_cache: Dictionary = {}
var _tex_cache: Dictionary = {}
var _navigation: Array[Button] = []
var _resource_chips: Array[Dictionary] = []
var _resource_tip: Panel
var _resource_tip_body: Label
var _resource_tip_quote: Label
var _resource_hover_id := ""
var _resource_hover_age := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	theme = GameSkin.make_theme()
	_refresh_viewport()
	_ensure_service()
	_pick_first_character()
	_layout()
	var back := Button.new()
	back.text = "返回校园"
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	back.position = Vector2(70, 620)
	back.size = Vector2(230, 60)
	back.add_theme_font_size_override("font_size", 25)
	back.pressed.connect(func() -> void: SceneRouter.go_to("home" if not SaveService.get_current().is_empty() else "title"))
	add_child(back)
	_navigation.append(back)
	var details := Button.new()
	details.text = "技能与天赋"
	details.position = Vector2(320, 620)
	details.size = Vector2(260, 60)
	details.add_theme_font_size_override("font_size", 27)
	details.pressed.connect(func() -> void:
		CampaignFlow.inspected_character_id = _selected_id
		SceneRouter.go_to("character_details"))
	add_child(details)
	_navigation.append(details)
	var equipment := Button.new()
	equipment.text = "装备背包"
	equipment.position = Vector2(70, 695)
	equipment.size = Vector2(510, 60)
	equipment.add_theme_font_size_override("font_size", 27)
	equipment.pressed.connect(func() -> void: SceneRouter.go_to("equipment"))
	add_child(equipment)
	_navigation.append(equipment)
	for button: Button in _navigation:
		GameSkin.style_button(button)
		button.pressed.connect(func() -> void: AudioService.play_sfx("select"))
	_layout_navigation()
	_resource_tip = Panel.new()
	_resource_tip.name = "ResourceDescription"
	_resource_tip.z_index = 50
	_resource_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resource_tip.add_theme_stylebox_override("panel", GameSkin.panel(Color("101d33"), GameSkin.BLUE))
	add_child(_resource_tip)
	_resource_tip_body = Label.new()
	_resource_tip_quote = Label.new()
	var kai := SystemFont.new()
	kai.font_names = PackedStringArray(["KaiTi", "楷体", "STKaiti"])
	_resource_tip_quote.add_theme_font_override("font", kai)
	_resource_tip_quote.add_theme_color_override("font_color", GameSkin.GOLD)
	for line: Label in [_resource_tip_body, _resource_tip_quote]:
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resource_tip.add_child(line)
	_resource_tip.hide()
	GameLog.info(TAG, "角色培养界面就绪（%d 名角色，服务就绪=%s，画布 %.0fx%.0f，缩放 %.3f）"
		% [_card_ids.size(), str(_svc != null and _svc.is_ready()),
			_viewport.x, _viewport.y, _scale])
	queue_redraw()

func _layout_navigation() -> void:
	if _navigation.size() != 3:
		return
	for i: int in range(3):
		var width := (_list_rect.size.x - _px(24)) / 3.0
		_navigation[i].position = Vector2(_list_rect.position.x + i * (width + _px(12)), _info_rect.position.y - _px(78))
		_navigation[i].size = Vector2(width, _px(58))
		_navigation[i].add_theme_font_size_override("font_size", int(_px(22)))


func _update_resource_tip(delta: float) -> void:
	if _resource_tip == null:
		return
	var hit: Dictionary = {}
	for chip: Dictionary in _resource_chips:
		if (chip.rect as Rect2).has_point(get_local_mouse_position()):
			hit = chip
			break
	var cid := str(hit.get("id", ""))
	if cid != _resource_hover_id:
		_resource_hover_id = cid
		_resource_hover_age = 0
	_resource_hover_age += delta
	_resource_tip.visible = not cid.is_empty() and _resource_hover_age >= 0.22
	if not _resource_tip.visible:
		return
	var config: Dictionary = {}
	for entry: Dictionary in DataRegistry.get_domain("currencies").get("currencies", []):
		if str(entry.get("id", "")) == cid:
			config = entry
			break
	_resource_tip_body.text = str(config.get("uiDescription", config.get("use", "")))
	_resource_tip_quote.text = str(config.get("flavorText", ""))
	_resource_tip.size = Vector2(_px(540), _px(120))
	_resource_tip.position = Vector2(clampf((hit.rect as Rect2).end.x - _resource_tip.size.x, _px(24), _viewport.x - _resource_tip.size.x - _px(24)), _px(116))
	_resource_tip_body.position = Vector2(_px(24), _px(20))
	_resource_tip_quote.position = Vector2(_px(24), _px(65))
	_resource_tip_body.add_theme_font_size_override("font_size", int(_px(24)))
	_resource_tip_quote.add_theme_font_size_override("font_size", int(_px(21)))

## 取当前**实际画布尺寸**（游戏单位），而不是 ProjectSettings 里的参考分辨率。
##
## 关键：本项目 stretch/mode=canvas_items + aspect=expand。窗口不是 16:9 时，
## 画布会在某一维上"扩张"（例如 1264×681 的客户区 → 画布约 2004×1080 游戏单位）。
## 若沿用 ProjectSettings 的 1920×1080 作为画布尺寸，右侧面板会被算出界外而截断。
func _refresh_viewport() -> void:
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
			ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	_viewport = vp
	_scale = minf(_viewport.x / REF_W, _viewport.y / REF_H)


func _ensure_service() -> void:
	if App.ensure_growth():
		_svc = App.growth
	else:
		_svc = null
		_feedback = "成长系统不可用：请检查 character_growth.json"
		_feedback_color = DANGER
		_feedback_timer = 999.0


func _pick_first_character() -> void:
	_card_ids.clear()
	if _svc != null and _svc.is_ready():
		# 注意：all_character_ids() 返回的是 Dictionary.keys()（Array，元素为 String）。
		# 直接赋给 Array[String] 会因类型不匹配而**静默清空**，因此必须逐项 append。
		for cid: String in _svc.all_character_ids():
			if not bool(CampaignFlow.state().get("campaign_active", false)) or CampaignFlow.character_unlocked(cid):
				_card_ids.append(cid)
		_card_ids.sort()
	if not _card_ids.is_empty():
		_selected_id = CampaignFlow.inspected_character_id if _card_ids.has(CampaignFlow.inspected_character_id) else _card_ids[0]
	GameLog.info(TAG, "角色培养界面：载入 %d 名角色（服务就绪=%s）"
		% [_card_ids.size(), str(_svc != null and _svc.is_ready())])


func _px(v: float) -> float:
	return v * _scale


func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer = maxf(0.0, _feedback_timer - delta)
	_tick_animations(delta)
	# 每帧重取画布尺寸：窗口拉伸 / 分辨率变化时布局随之重算（仅读 size，无副作用）
	_refresh_viewport()
	_layout()
	_layout_navigation()
	_update_resource_tip(delta)
	queue_redraw()


## 推进增量闪烁 / 上浮与属性行高亮计时（纯表现，不读也不改任何领域状态）。
func _tick_animations(delta: float) -> void:
	if _delta_pulse > 0.0:
		_delta_pulse = maxf(0.0, _delta_pulse - delta * PULSE_DECAY)
	if _delta_float > 0.0:
		_delta_float = maxf(0.0, _delta_float - delta / FLOAT_LIFE)
	if not _flash_rows.is_empty():
		for k: String in _flash_rows.keys():
			var left := float(_flash_rows[k]) - delta
			if left <= 0.0:
				_flash_rows.erase(k)
			else:
				_flash_rows[k] = left
	# 预览组合变化时触发一次闪烁：让"数值真的变了"这件事被看见
	var sig := "%s|%d|%s" % [_selected_id, _preview_count, _preview_item]
	if sig != _last_preview_sig:
		_last_preview_sig = sig
		if _preview_count > 0:
			_delta_pulse = 1.0
			_delta_float = 1.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_preview_count = 0
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			SceneRouter.go_to("home" if not SaveService.get_current().is_empty() else "title")
		elif k >= KEY_1 and k <= KEY_6:
			var idx := k - KEY_1
			if idx < _card_ids.size():
				_select_character(_card_ids[idx])


func _handle_click(pos: Vector2) -> void:
	# 角色卡
	for i: int in range(_card_rects.size()):
		if _card_rects[i].has_point(pos):
			_select_character(_card_ids[i])
			return
	# 按钮：禁用态必须**既画成灰、也点不动**（只画灰仍可点属缺陷）
	for b: Dictionary in _btn_rects:
		var r: Rect2 = b["rect"]
		if not r.has_point(pos):
			continue
		var action := str(b["action"])
		if not _button_enabled(action, b.get("arg", null)):
			_show(_disabled_reason(action, b.get("arg", null)), WARN)
			return
		_on_button(action, b.get("arg", null))
		return


## 切换当前角色。**必须清空全部「属于上一个角色」的瞬时状态**：
## 预览份数、增量闪烁、属性行高亮、预览签名。
## 否则切人后会看到上一角色的 +N 增量或高亮残留（视觉上等于显示错数据）。
## 背景环境由 _env_name() 依据 _selected_id 解析，切人后自然跟着换。
func _select_character(character_id: String) -> void:
	if character_id == _selected_id:
		# 同一角色重复点击：只重置预览，不重复播反馈
		_preview_count = 0
		return
	_selected_id = character_id
	CampaignFlow.inspected_character_id = character_id
	_preview_count = 0
	_delta_pulse = 0.0
	_delta_float = 0.0
	_flash_rows.clear()
	# 让下一帧的签名比较必然不等，避免把"切人"误判成"预览变化"而闪一下
	_last_preview_sig = ""
	_show("已选择 %s" % _display_name(character_id), ACCENT)
	GameLog.info(TAG, "角色培养界面：切换到 %s（环境 %s）"
		% [character_id, _env_name()])


## 按钮是否可点。**绘制与命中必须共用本判据**，否则会出现"看着是灰的、点了却生效"。
func _button_enabled(action: String, arg: Variant) -> bool:
	if _svc == null or not _svc.is_ready():
		return false
	match action:
		"cycle_item":
			return true
		"preview":
			var cnt := int(arg)
			return cnt > 0 and _svc.get_currency(_preview_item) >= cnt
		"levelup":
			var p := _svc.get_progress(_selected_id)
			if p == null:
				return false
			var cnt2 := maxi(1, _preview_count)
			return _preview_count > 0 and _svc.get_currency(_preview_item) >= cnt2 \
				and not p.is_level_capped()
		"breakthrough":
			return bool(_svc.query_breakthrough(_selected_id).get("ok", false))
	return false


## 禁用原因文案：让"点不动"有解释，而不是无反馈的死按钮。
func _disabled_reason(action: String, arg: Variant) -> String:
	match action:
		"preview":
			return "%s 不足（需 %d 本）" % [_item_name(_preview_item), int(arg)]
		"levelup":
			if _preview_count <= 0:
				return "请先选择投入份数（1 / 5 / 最大）"
			var p := _svc.get_progress(_selected_id)
			if p != null and p.is_level_capped():
				return "已达当前等级上限，请先突破"
			return "%s 不足" % _item_name(_preview_item)
		"breakthrough":
			var q := _svc.query_breakthrough(_selected_id)
			return "无法突破：%s" % str(q.get("reason", "条件未满足"))
	return "当前不可用"


func _on_button(action: String, arg: Variant) -> void:
	if _svc == null or not _svc.is_ready():
		_show("成长系统不可用", DANGER)
		return
	match action:
		"preview":
			_preview_count = int(arg)
			_preview_item = str(_btn_rects[0].get("item", _preview_item))
			_show("预览：投入 %d 份 %s" % [_preview_count, _item_name(_preview_item)], ACCENT)
		"levelup":
			_do_level_up(int(arg))
		"breakthrough":
			_do_breakthrough()
		"cycle_item":
			_cycle_item()


func _cycle_item() -> void:
	var ids: Array = _svc.study_record_items().keys()
	ids.sort()
	if ids.is_empty():
		return
	var idx := ids.find(_preview_item)
	_preview_item = str(ids[(idx + 1) % ids.size()])
	_preview_count = 0
	_show("学习记录类型：%s" % _item_name(_preview_item), ACCENT)


func _do_level_up(count: int) -> void:
	if _selected_id.is_empty():
		return
	var p0 := _svc.get_progress(_selected_id)
	var before: Dictionary = p0.compute_stats() if p0 != null else {}
	var res := _svc.level_up_with_records(_selected_id, _preview_item, count)
	if not bool(res.get("ok", false)):
		_show("升级失败：%s" % str(res.get("reason", "")), DANGER)
		return
	# 事务式落盘：内存状态已变，必须提交，否则"升了级但没保存"
	if not _svc.commit():
		_show("升级成功但存档写入失败（请检查磁盘）", DANGER)
		return
	var p := _svc.get_progress(_selected_id)
	var extra := ""
	if int(res.get("expRefunded", 0)) > 0:
		extra = "（%d EXP 因达到上限已退回）" % int(res["expRefunded"])
	_show("%s 升至 Lv.%d，提升 %d 级%s" % [
		_display_name(_selected_id), int(res.get("levelAfter", 0)),
		int(res.get("levelsGained", 0)), extra], POSITIVE)
	# 即时反馈：把真的变化了的属性行点亮一下（而不只是数字变了）
	if p != null and not before.is_empty():
		_flash_changed_rows(p, before, "levelup")
	GameLog.info(TAG, "升级 %s → Lv.%d（投入 %d 份 %s，提升 %d 级，退回 %d EXP）" % [
		_selected_id, p.level, count, _preview_item,
		int(res.get("levelsGained", 0)), int(res.get("expRefunded", 0))])
	_preview_count = 0


func _do_breakthrough() -> void:
	if _selected_id.is_empty():
		return
	var q := _svc.query_breakthrough(_selected_id)
	if not bool(q.get("ok", false)):
		_show("无法突破：%s" % str(q.get("reason", "")), WARN)
		return
	var p0 := _svc.get_progress(_selected_id)
	var before: Dictionary = p0.compute_stats() if p0 != null else {}
	var res := _svc.do_breakthrough(_selected_id)
	if not bool(res.get("ok", false)):
		_show("突破失败：%s" % str(res.get("reason", "")), DANGER)
		return
	if not _svc.commit():
		_show("突破成功但存档写入失败（请检查磁盘）", DANGER)
		return
	var p := _svc.get_progress(_selected_id)
	_show("%s 完成突破 %d（等级上限 Lv.%d）" % [
		_display_name(_selected_id), int(res.get("breakthroughAfter", 0)),
		p.level_cap()], POSITIVE)
	# 即时反馈：突破往往不直接改面板数值，但等级上限/节点轨道一定变了，
	# 这里同时点亮变化的属性行，并让节点轨道重新高亮一次。
	if p != null and not before.is_empty():
		_flash_changed_rows(p, before, "breakthrough")
	GameLog.info(TAG, "突破 %s → 第 %d 阶" % [_selected_id, int(res.get("breakthroughAfter", 0))])


func _show(text: String, color: Color) -> void:
	_feedback = text
	_feedback_color = color
	_feedback_timer = 4.0


func _display_name(character_id: String) -> String:
	var cfg: Dictionary = DataRegistry.get_entry("characters", character_id)
	return str(cfg.get("name", character_id))


func _item_name(item_id: String) -> String:
	for item: Dictionary in DataRegistry.get_domain("currencies").get("studyRecordItems", []):
		if str(item.get("id", "")) == item_id:
			return str(item.get("name", item_id))
	return item_id


func _currency_name(currency_id: String) -> String:
	for c: Dictionary in DataRegistry.get_domain("currencies").get("currencies", []):
		if str(c.get("id", "")) == currency_id:
			return str(c.get("name", currency_id))
	return currency_id


# ============================================================ 美术资源访问（缺失即回退）

## 取图标贴图；缺失返回 null（调用方必须回退）。
##
## **统一从 64px 源图取**：图标资产同时提供 _32/_64 两版，若各处分别请求，
## 同一行里会出现大小/锐度不一致的图标。固定用 64 源图再按目标尺寸缩放，
## 保证任意位置的图标外观一致（贴图缓存按目标尺寸分开，规模有界）。
func _icon_tex(name: String) -> Texture2D:
	var key := "icon:%s" % name
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var t := ArtRegistry.icon(name, ICON_SRC_SIZE)
	_tex_cache[key] = t
	return t


## 取角色头像；缺失返回 null。
func _portrait_tex(character_id: String, size: int) -> Texture2D:
	var key := "portrait:%s:%d" % [character_id, size]
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var t := ArtRegistry.character_portrait(character_id, size)
	_tex_cache[key] = t
	return t


## 当前背景环境名（纯表现层；未知角色退回默认环境）。
func _env_name() -> String:
	if _selected_id.is_empty():
		return DEFAULT_ENV
	return str(ENV_BY_CHARACTER.get(_selected_id, DEFAULT_ENV))


## 取背景贴图；缺失返回 null。
func _bg_tex() -> Texture2D:
	var env := _env_name()
	var key := "env:" + env
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var t := ArtRegistry.environment(env)
	if t == null:
		t = ArtRegistry.environment(DEFAULT_ENV)
	_tex_cache[key] = t
	return t


## 等比覆盖裁剪（cover）：填满目标矩形且不变形。贴图为 null 时返回 false。
func _draw_cover(tex: Texture2D, dest: Rect2) -> bool:
	if tex == null:
		return false
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw <= 0.0 or th <= 0.0 or dest.size.x <= 0.0 or dest.size.y <= 0.0:
		return false
	var s := maxf(dest.size.x / tw, dest.size.y / th)
	var src := Rect2(
		(tw - dest.size.x / s) * 0.5,
		(th - dest.size.y / s) * 0.5,
		dest.size.x / s,
		dest.size.y / s)
	draw_texture_rect_region(tex, dest, src)
	return true


## 画图标；贴图缺失时退回同尺寸的圆角占位块（绝不空出、绝不崩溃）。
## 图标按**正方形**绘制，因此尺寸统一即代表视觉重量一致。
func _draw_icon(name: String, pos: Vector2, size: float, tint: Color = Color(1, 1, 1, 1)) -> void:
	var tex := _icon_tex(name)
	if tex == null:
		draw_style_box(_sb(Color(0.18, 0.22, 0.34, 0.85), FAINT, size * 0.22, 1.0),
			Rect2(pos, Vector2(size, size)))
		return
	draw_texture_rect(tex, Rect2(pos, Vector2(size, size)), false, tint)


## 图标与文字的**基线对齐**助手：给定文字基线 y 与字号，返回图标左上角 y，
## 使图标垂直中心落在文字视觉中心上（而不是让图标压着基线）。
## 视觉中心取「基线 - 0.32×字号」，与 draw_string 的拉丁/汉字中段一致。
func _icon_y_for_text(baseline_y: float, font_size: float, icon_size: float) -> float:
	return baseline_y - font_size * 0.32 - icon_size * 0.5


## 缓存的圆角样式盒（固定配色集合，缓存规模有界）。
func _sb(fill: Color, border: Color, radius: float, border_w: float) -> StyleBoxFlat:
	var key := "%s|%s|%.1f|%.1f" % [fill.to_html(true), border.to_html(true), radius, border_w]
	if _sb_cache.has(key):
		return _sb_cache[key] as StyleBoxFlat
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(int(round(radius)))
	if border_w > 0.0:
		s.set_border_width_all(int(round(border_w)))
		s.border_color = border
	s.anti_aliasing = true
	_sb_cache[key] = s
	return s


## 缓存的竖向渐变贴图（顶部→底部）。用于头带压暗与底部渐隐。
func _vgrad(top: Color, bottom: Color) -> GradientTexture2D:
	var key := "%s|%s" % [top.to_html(true), bottom.to_html(true)]
	if _grad_cache.has(key):
		return _grad_cache[key] as GradientTexture2D
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 256
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	_grad_cache[key] = t
	return t


func _text_w(font: Font, text: String, size: float) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x


## 数字槽位字体：系统等宽字体优先（数字等宽、字形对齐），
## 缺失时回退 fallback_font。**只影响数字排版，不改变任何数值来源。**
func _mono_font() -> Font:
	if _num_font != null:
		return _num_font
	var names := PackedStringArray([
		"Consolas", "Cascadia Mono", "DejaVu Sans Mono",
		"Liberation Mono", "Courier New", "monospace"])
	for n: String in names:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([n])
		# 系统缺这个字族时 SystemFont 会回退到默认字体而不是报错；
		# 这里只接受真的能给出字形的字体，避免拿到空字面。
		if f.get_height(int(F_LABEL)) > 0.0:
			_num_font = f
			return _num_font
	_num_font = ThemeDB.fallback_font
	return _num_font


## 固定宽度槽的宽度（不绘制；供需要先量宽的场合）。
##
## 用法约定（全界面统一）：**数值本身左对齐、紧贴它前面的标签绘制**，
## 但「数值之后的内容」（如 +N 增量）锚定在 `标签x + 本槽宽` 处。
## 这样既不会让数字与标签脱开（右对齐槽会那样），
## 又保证位数从 1 位变 4 位时后续内容不左右跳动。
func _num_slot_w(digits: int, size: float) -> float:
	return _text_w(_mono_font(), " ".repeat(digits), size)


## 描边宽度：小字 1px、大字 2px（参考画布像素，随 _scale 缩放）。
func _outline_w(size: float) -> float:
	return _px(OUTLINE_PX_LARGE if size >= OUTLINE_BOLD_FROM else OUTLINE_PX_SMALL)


## 带深色描边的文字绘制（本界面**所有**文字都走这里）。
##
## 为什么需要：项目用 ThemeDB.fallback_font（MSDF、无粗体字面），
## 细笔画压在校园背景/深色面板上会发虚，尤其小字号与红字告警。
## 描边不改变字号与布局，因此不影响任何既有排版计算（_text_w 仍按无描边测量）。
func _draw_text(font: Font, pos: Vector2, text: String, size: float, color: Color,
		outline: bool = true) -> void:
	var fs := int(size)
	if fs <= 0 or text.is_empty():
		return
	if outline and _outline_w(size) > 0:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			int(ceil(_outline_w(size))), OUTLINE_COLOR)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## 依据视口与缩放计算全部矩形（绘制与命中共用）
func _layout() -> void:
	_card_rects.clear()
	_btn_rects.clear()

	var m := _px(48.0)
	var gap := _px(24.0)
	_header_rect = Rect2(Vector2(0.0, 0.0), Vector2(_viewport.x, _px(148.0)))

	# ---- 左列：角色列表（上）+ 学习记录库存（下，锚定底边）----
	var list_w := _px(560.0)
	var list_top := _px(172.0)
	var info_h := _px(268.0)
	_info_rect = Rect2(Vector2(m, _viewport.y - m - info_h), Vector2(list_w, info_h))
	_list_rect = Rect2(Vector2(m, list_top),
		Vector2(list_w, maxf(0.0, _info_rect.position.y - _px(100) - list_top)))

	var n := maxi(1, _card_ids.size())
	var card_h := clampf((_list_rect.size.y - float(n - 1) * gap) / float(n), _px(110.0), _px(200.0))
	for i: int in range(_card_ids.size()):
		_card_rects.append(Rect2(
			Vector2(m, list_top + float(i) * (card_h + gap)), Vector2(list_w, card_h)))

	# ---- 右：培养面板 ----
	var panel_x := m + list_w + _px(32.0)
	_panel_rect = Rect2(Vector2(panel_x, list_top),
		Vector2(maxf(_px(600.0), _viewport.x - panel_x - m),
			maxf(_px(400.0), _viewport.y - m - list_top)))

	var pad := _px(32.0)
	var ix := _panel_rect.position.x + pad
	var iy := _panel_rect.position.y + pad
	var iw := _panel_rect.size.x - pad * 2.0
	var ih := _panel_rect.size.y - pad * 2.0

	# 头像（256×256；面板过小时按比例收缩）
	var port_s := minf(_px(232.0), minf(iw * 0.30, ih * 0.30))
	_portrait_rect = Rect2(Vector2(ix, iy), Vector2(port_s, port_s))

	# 操作区自面板底部向上排布，剩余空间再分给节点带与属性带
	var btn_main_h := _px(76.0)
	var btn_row_h := _px(56.0)
	var btn_gap := _px(12.0)
	var stats_h := _px(132.0)
	var main_y := iy + ih - btn_main_h
	var row_y := main_y - btn_gap - btn_row_h
	_stats_rect = Rect2(Vector2(ix, row_y - _px(20.0) - stats_h), Vector2(iw, stats_h))

	# 经验条：与头像底边对齐，压在头像右侧信息区的最后一行
	var info_x := ix + port_s + _px(32.0)
	var info_w := maxf(_px(200.0), ix + iw - info_x)
	_exp_rect = Rect2(Vector2(info_x, iy + port_s - _px(30.0)), Vector2(info_w, _px(30.0)))

	# 节点带：经验条之下、属性带之上
	var nodes_top := iy + port_s + _px(26.0)
	_nodes_rect = Rect2(Vector2(ix, nodes_top),
		Vector2(iw, maxf(_px(120.0), _stats_rect.position.y - _px(14.0) - nodes_top)))

	# ---- 操作按钮 ----
	var main_w := (iw - _px(20.0)) * 0.5

	# 学习记录类型切换（必须放在 _btn_rects[0]：_on_button 的 "preview" 分支读它取当前 item）
	var cycle_w := minf(_px(560.0), iw * 0.48)
	_btn_rects.append({
		"action": "cycle_item",
		"rect": Rect2(Vector2(ix, row_y), Vector2(cycle_w, btn_row_h)),
		"item": _preview_item})

	# 快捷投入（1 份 / 5 份 / 最大）
	var quick_x := ix + cycle_w + _px(20.0)
	var quick_area := ix + iw - quick_x
	var quick_n := float(QUICK_STEPS.size() + 1)
	var q_gap := _px(16.0)
	var q_w := maxf(_px(60.0), (quick_area - q_gap * (quick_n - 1.0)) / quick_n)
	var max_count := _max_affordable()
	var qi := 0
	for step: int in QUICK_STEPS:
		_btn_rects.append({
			"action": "preview",
			"rect": Rect2(Vector2(quick_x + float(qi) * (q_w + q_gap), row_y),
				Vector2(q_w, btn_row_h)),
			"arg": step, "item": _preview_item})
		qi += 1
	_btn_rects.append({
		"action": "preview",
		"rect": Rect2(Vector2(quick_x + float(qi) * (q_w + q_gap), row_y),
			Vector2(q_w, btn_row_h)),
		"arg": max_count, "item": _preview_item})

	# 主操作：升级 / 突破
	_btn_rects.append({
		"action": "levelup",
		"rect": Rect2(Vector2(ix, main_y), Vector2(main_w, btn_main_h)),
		"arg": maxi(1, _preview_count)})
	_btn_rects.append({
		"action": "breakthrough",
		"rect": Rect2(Vector2(ix + main_w + _px(20.0), main_y), Vector2(main_w, btn_main_h))})


## 当前最多能投入几份（受持有量与「到上限所需经验」双重限制）
func _max_affordable() -> int:
	if _svc == null or _selected_id.is_empty():
		return 1
	var held := _svc.get_currency(_preview_item)
	if held <= 0:
		return 1
	var items := _svc.study_record_items()
	var per := int(items.get(_preview_item, 0))
	if per <= 0:
		return 1
	var p := _svc.get_progress(_selected_id)
	if p == null:
		return 1
	# 从当前等级练到上限还需要多少经验
	var need := 0
	var lv := p.level
	var exp := p.exp
	var cap := p.level_cap()
	var table: Dictionary = DataRegistry.get_domain("character_growth").get("expTable", {})
	while lv < cap:
		var req := int(table.get(str(lv), 0))
		if req <= 0:
			break
		need += req - exp
		exp = 0
		lv += 1
	if need <= 0:
		return held
	return clampi(int(ceil(float(need) / float(per))), 1, held)


# ============================================================ 绘制
func _draw() -> void:
	_draw_background()

	var font := GameSkin.body_font()
	if _svc == null or not _svc.is_ready():
		var box := Rect2(Vector2(_viewport.x * 0.5 - _px(430.0), _viewport.y * 0.5 - _px(60.0)),
			Vector2(_px(860.0), _px(120.0)))
		draw_style_box(_sb(Color(0.06, 0.07, 0.13, 0.92), DANGER, _px(10.0), _px(2.0)), box)
		_draw_center_text("成长系统不可用。请检查 data/character_growth.json 是否可加载。", DANGER)
		return

	_draw_header(font)

	# ---- 左：角色卡列表 ----
	for i: int in range(_card_ids.size()):
		_draw_character_card(_card_ids[i], _card_rects[i], i)

	# ---- 左下：学习记录库存 ----
	_draw_study_inventory(font)

	# ---- 右：培养面板 ----
	_draw_growth_panel(font)

	# ---- 反馈 ----
	_draw_feedback(font)


## 背景：校园环境图 cover 铺满 + 暗色遮罩。贴图缺失时退回纯色底（绝不黑屏）。
func _draw_background() -> void:
	var vp := Rect2(Vector2.ZERO, _viewport)
	if not _draw_cover(_bg_tex(), vp):
		draw_rect(vp, BG, true)
		return
	draw_rect(vp, SCRIM, true)
	# 顶部/底部再压一层渐变，让头带与底部提示区始终可读
	draw_texture_rect(_vgrad(Color(0.02, 0.03, 0.06, 0.92), Color(0.02, 0.03, 0.06, 0.0)),
		Rect2(Vector2(0.0, 0.0), Vector2(_viewport.x, _px(240.0))), false)
	draw_texture_rect(_vgrad(Color(0.02, 0.03, 0.06, 0.0), Color(0.02, 0.03, 0.06, 0.85)),
		Rect2(Vector2(0.0, _viewport.y - _px(160.0)), Vector2(_viewport.x, _px(160.0))), false)


func _draw_center_text(text: String, color: Color) -> void:
	var font := GameSkin.body_font()
	var w := _text_w(font, text, F_LABEL)
	_draw_text(font, Vector2((_viewport.x - w) * 0.5, _viewport.y * 0.5), text,
		_px(F_LABEL), color)


## 顶部：标题 + 资源条（图标 + 数字并列）
func _draw_header(font: Font) -> void:
	var hb := _header_rect
	draw_rect(Rect2(Vector2.ZERO, Vector2(_viewport.x, hb.size.y)),
		Color(0.030, 0.040, 0.075, 0.88), true)
	draw_rect(Rect2(Vector2(0.0, hb.size.y - _px(2.0)), Vector2(_viewport.x, _px(2.0))),
		Color(0.30, 0.45, 0.72, 0.55), true)

	# 标题徽记（icon_ap 仅作本页入口标识，不表示任何 AP 数值）
	var emblem := _px(ICON_SIZE_EMBLEM)
	var ex := _px(48.0)
	draw_texture_rect(GameSkin.crest(), Rect2(ex, _px(29), emblem, _px(80)), false)
	var tx := ex + emblem + _px(16.0)
	_draw_text(GameSkin.serif(), Vector2(tx, _px(88.0)), "角色培养", _px(F_TITLE), TEXT)
	_draw_text(font, Vector2(tx, _px(126.0)),
		"培养 · 等级与突破    /    装备 · 属性与强化",
		_px(F_TINY), DIM)

	_draw_currency_bar(font)


## 五类资源条（顺序与 displayOrder 一致，唯一来自 currencies.json）：图标 + 名称 + 数量
func _draw_currency_bar(font: Font) -> void:
	_resource_chips.clear()
	var entries: Array = DataRegistry.get_domain("currencies").get("currencies", [])
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("displayOrder", 0)) < int(b.get("displayOrder", 0)))

	var chip_h := _px(52.0)
	var chip_y := _px(48.0)
	var icon_s := _px(ICON_SIZE_CHIP)
	var gap := _px(12.0)

	# 先量总宽，再整体右对齐。数量按**固定位数槽**测量，
	# 这样数字从 0 变成 1200 时，整条资源栏不会左右伸缩。
	var widths: Array[float] = []
	var total := 0.0
	for c: Dictionary in sorted:
		var cid := str(c.get("id", ""))
		var w := _px(14.0) + icon_s + _px(10.0) \
			+ _text_w(font, str(c.get("name", cid)), F_LABEL) + _px(8.0) \
			+ _num_slot_w(CURRENCY_DIGITS, F_LABEL) + _px(18.0)
		widths.append(w)
		total += w + gap
	if not widths.is_empty():
		total -= gap

	var x := maxf(_px(660.0), _viewport.x - _px(48.0) - total)
	for i: int in range(sorted.size()):
		var c: Dictionary = sorted[i]
		var cid := str(c.get("id", ""))
		var label := str(c.get("name", cid))
		var r := Rect2(Vector2(x, chip_y), Vector2(widths[i], chip_h))
		_resource_chips.append({"id": cid, "rect": r})
		draw_style_box(_sb(Color(0.08, 0.10, 0.18, 0.90), BORDER_SOFT, _px(8.0), _px(1.0)), r)
		var text_base := r.position.y + chip_h * 0.5 + _px(8.0)
		# 图标按文字基线对齐（而不是按 chip 中心），避免与汉字视觉错位
		_draw_icon(str(CURRENCY_ICON.get(cid, "icon_material")),
			Vector2(r.position.x + _px(14.0),
				_icon_y_for_text(text_base, F_LABEL, icon_s)), icon_s)
		var nx := r.position.x + _px(14.0) + icon_s + _px(10.0)
		_draw_text(font, Vector2(nx, text_base), label, _px(F_LABEL), TEXT)
		nx += _text_w(font, label, F_LABEL) + _px(8.0)
		# 数量：等宽字体，紧贴资源名左对齐；整条 chip 宽度按固定槽预留，
		# 因此数字位数变化时 chip 本身与相邻 chip 都不会移动。
		_draw_text(_mono_font(), Vector2(nx, text_base), str(_display_currency_count(cid)),
			_px(F_LABEL), ACCENT)
		x += widths[i] + gap


## 角色卡：真实头像 + 姓名 + 等级 + 定位 + 迷你经验条
func _display_currency_count(cid: String) -> int:
	if cid == "study_record":
		var count := 0
		for item_id: String in _svc.study_record_items():
			count += _svc.get_currency(item_id)
		return count
	return _svc.get_currency(cid)


func _draw_character_card(character_id: String, rect: Rect2, index: int) -> void:
	var font := GameSkin.body_font()
	var p := _svc.get_progress(character_id)
	var selected := character_id == _selected_id
	var hovered := rect.has_point(_mouse_pos)

	var fill := CARD_BG
	if selected:
		fill = CARD_SELECTED_HOVER if hovered else CARD_SELECTED
	elif hovered:
		fill = CARD_BG_HOVER
	var edge := Color(0.62, 0.86, 1.0) if selected \
		else (Color(0.46, 0.60, 0.86) if hovered else BORDER_SOFT)
	draw_style_box(_sb(fill, edge, _px(10.0), _px(2.0)), rect)

	var cfg: Dictionary = DataRegistry.get_entry("characters", character_id)
	var behavior := str(cfg.get("behavior", ""))
	var role_color := _role_color(behavior)

	# 定位色条
	draw_style_box(_sb(role_color, role_color, _px(3.0), 0.0),
		Rect2(Vector2(rect.position.x + _px(6.0), rect.position.y + _px(10.0)),
			Vector2(_px(6.0), maxf(_px(4.0), rect.size.y - _px(20.0)))))

	# 头像（缺失时退回定位色块 + 姓名首字）
	var pad := _px(20.0)
	var ps := clampf(rect.size.y - _px(28.0), _px(80.0), _px(150.0))
	var prect := Rect2(
		Vector2(rect.position.x + pad, rect.position.y + (rect.size.y - ps) * 0.5),
		Vector2(ps, ps))
	var tex := _portrait_tex(character_id, 256)
	if tex != null:
		draw_texture_rect(tex, prect, false)
	else:
		draw_style_box(_sb(role_color.darkened(0.58), role_color, _px(8.0), _px(2.0)), prect)
		var ch := str(cfg.get("name", character_id)).substr(0, 1)
		_draw_text(font, Vector2(prect.position.x + (ps - _text_w(font, ch, F_TITLE)) * 0.5,
			prect.position.y + ps * 0.5 + _px(16.0)),
			ch, _px(F_TITLE), TEXT)
	draw_style_box(_sb(Color(0, 0, 0, 0), edge, _px(8.0), _px(2.0)), prect)

	var tx := prect.position.x + ps + pad
	var tw := maxf(_px(80.0), rect.position.x + rect.size.x - pad - tx)

	# 姓名
	_draw_text(font, Vector2(tx, rect.position.y + rect.size.y * 0.44),
		str(cfg.get("name", character_id)), _px(F_NAME), TEXT)

	# 等级 + 突破
	if p != null:
		var ly := rect.position.y + rect.size.y * 0.66
		# 等级数字紧贴 "Lv."，后续「/ 上限」「突破 N」锚定固定 x（位数变化不跳动）
		var lv_head := "Lv."
		var lv_head_w := _text_w(font, lv_head, F_LABEL)
		_draw_text(font, Vector2(tx, ly), lv_head, _px(F_LABEL), ACCENT)
		_draw_text(_mono_font(), Vector2(tx + lv_head_w, ly), str(p.level),
			_px(F_LABEL), ACCENT)
		var num_w := _num_slot_w(LEVEL_DIGITS, F_LABEL)
		var cap_text := " / %d" % p.level_cap()
		_draw_text(font, Vector2(tx + lv_head_w + num_w, ly), cap_text,
			_px(F_LABEL), ACCENT)
		var lv_text_w := lv_head_w + num_w + _text_w(font, cap_text, F_LABEL)
		if p.breakthrough > 0:
			_draw_text(font, Vector2(tx + lv_text_w + _px(14.0), ly),
				"突破 %d" % p.breakthrough, _px(F_TINY), POSITIVE)
		# 迷你经验条
		var bar := Rect2(Vector2(tx, rect.position.y + rect.size.y - _px(34.0)),
			Vector2(tw, _px(12.0)))
		_draw_exp_bar(bar, p, false)

	# 定位标签（右上）
	var role := "调度" if character_id == "fujiwara_rin" else _role_label(behavior)
	var rw := _text_w(font, role, F_TINY) + _px(20.0)
	var rrect := Rect2(
		Vector2(rect.position.x + rect.size.x - pad - rw, rect.position.y + _px(14.0)),
		Vector2(rw, _px(32.0)))
	draw_style_box(_sb(Color(role_color.r, role_color.g, role_color.b, 0.18),
		role_color, _px(6.0), _px(1.0)), rrect)
	_draw_text(font, Vector2(rrect.position.x + _px(10.0), rrect.position.y + _px(23.0)),
		role, _px(F_TINY), role_color)

	# 序号（右下）
	var idx_label := "[%d]" % (index + 1)
	_draw_text(font, Vector2(rect.position.x + rect.size.x - pad - _text_w(font, idx_label, F_TINY),
		rect.position.y + rect.size.y - _px(14.0)), idx_label, _px(F_TINY), FAINT)


## 左下：学习记录库存（图标 + 名称 + 持有本数 + 单份 EXP）
func _draw_study_inventory(font: Font) -> void:
	var r := _info_rect
	draw_style_box(_sb(PANEL_BG, BORDER_SOFT, _px(12.0), _px(2.0)), r)
	var pad := _px(24.0)
	var ix := r.position.x + pad
	var iy := r.position.y + pad
	var iw := maxf(_px(120.0), r.size.x - pad * 2.0)

	_draw_text(font, Vector2(ix, iy + _px(24.0)), "学习记录库存", _px(F_LABEL), TEXT)

	var items: Array = DataRegistry.get_domain("currencies").get("studyRecordItems", [])
	var row_h := _px(56.0)
	var rgap := _px(6.0)
	var ry := iy + _px(44.0)
	for item: Dictionary in items:
		var iid := str(item.get("id", ""))
		var rr := Rect2(Vector2(ix, ry), Vector2(iw, row_h))
		var picked := iid == _preview_item
		draw_style_box(_sb(
			Color(0.16, 0.30, 0.50, 0.85) if picked else Color(0.08, 0.10, 0.18, 0.80),
			ACCENT if picked else BORDER_SOFT, _px(8.0),
			_px(2.0) if picked else _px(1.0)), rr)
		var ic := _px(ICON_SIZE_ROW)
		var row_base := rr.position.y + row_h * 0.5 + _px(9.0)
		_draw_icon("icon_study_record",
			Vector2(rr.position.x + _px(12.0),
				_icon_y_for_text(row_base, F_LABEL, ic)), ic)
		_draw_text(font, Vector2(rr.position.x + _px(12.0) + ic + _px(12.0), row_base),
			str(item.get("name", iid)), _px(F_LABEL), TEXT if picked else DIM)
		var right := "持有 %d 本 · %d EXP/本" % [
			_svc.get_currency(iid), int(item.get("expValue", 0))]
		_draw_text(font, Vector2(
			rr.position.x + rr.size.x - _px(12.0) - _text_w(font, right, F_TINY), row_base),
			right, _px(F_TINY), ACCENT if picked else DIM)
		ry += row_h + rgap


## 右：培养面板
func _draw_growth_panel(font: Font) -> void:
	if _selected_id.is_empty():
		return
	var p := _svc.get_progress(_selected_id)
	if p == null:
		return

	draw_style_box(_sb(PANEL_BG, BORDER, _px(14.0), _px(2.0)), _panel_rect)

	# ---- 头像 ----
	var prect := _portrait_rect
	var tex := _portrait_tex(_selected_id, 256)
	var cfg: Dictionary = DataRegistry.get_entry("characters", _selected_id)
	var behavior := str(cfg.get("behavior", ""))
	var role_color := _role_color(behavior)
	if tex != null:
		draw_texture_rect(tex, prect, false)
	else:
		draw_style_box(_sb(role_color.darkened(0.6), role_color, _px(10.0), _px(2.0)), prect)
	draw_style_box(_sb(Color(0, 0, 0, 0), ACCENT if p.breakthrough > 0 else BORDER,
		_px(10.0), _px(2.0)), prect)

	# ---- 身份（头像右侧）----
	var ix := _panel_rect.position.x + _px(32.0)
	var iy := _panel_rect.position.y + _px(32.0)
	var iw := _panel_rect.size.x - _px(64.0)
	var rx := prect.position.x + prect.size.x + _px(32.0)

	_draw_text(font, Vector2(rx, iy + _px(44.0)), _display_name(_selected_id),
		_px(F_TITLE), TEXT)

	# 定位标签
	var role := _role_label(behavior)
	var role_w := _text_w(font, role, F_TINY) + _px(24.0)
	var rrect := Rect2(Vector2(rx, iy + _px(62.0)), Vector2(role_w, _px(34.0)))
	draw_style_box(_sb(Color(role_color.r, role_color.g, role_color.b, 0.18),
		role_color, _px(6.0), _px(1.0)), rrect)
	_draw_text(font, Vector2(rrect.position.x + _px(12.0), rrect.position.y + _px(24.0)),
		role, _px(F_TINY), role_color)

	# 大号等级数字 + 上限。
	# 数字**紧贴** "Lv." 绘制（不留空档），但**后续文字锚定在固定 x**：
	# 这样 Lv.7 → Lv.10 → Lv.40 时右侧「等级上限 / 突破阶段」不会左右横跳，
	# 同时 Lv.1 也不会出现「Lv.  1」那种像打错字的空档。
	var lv_head := "Lv."
	var lv_head_w := _text_w(font, lv_head, F_BIG_LEVEL)
	_draw_text(font, Vector2(rx, iy + _px(150.0)), lv_head, _px(F_BIG_LEVEL), ACCENT)
	_draw_text(_mono_font(), Vector2(rx + lv_head_w, iy + _px(150.0)),
		str(p.level), _px(F_BIG_LEVEL), ACCENT)
	# 后续文字起点 = "Lv." + 最大位数宽度（与当前位数无关 → 不跳动）
	var lv_w := lv_head_w + _num_slot_w(LEVEL_DIGITS, F_BIG_LEVEL)
	_draw_text(font, Vector2(rx + lv_w + _px(20.0), iy + _px(118.0)),
		"等级上限 Lv.%d" % p.level_cap(), _px(F_LABEL), DIM)

	# 突破阶段（放在大号等级数字右侧的第二行，避免与经验条抢位）
	var next_lv := p.next_breakthrough_level()
	var bt_text := "突破阶段 %d" % p.breakthrough
	if next_lv > 0:
		bt_text += "  ·  下一阶需 Lv.%d" % int(
			(DataRegistry.get_domain("character_growth").get("breakthroughs", [])[next_lv - 1]
				as Dictionary).get("requiredLevel", 0))
	_draw_text(font, Vector2(rx + lv_w + _px(20.0), iy + _px(150.0)), bt_text,
		_px(F_LABEL), TEXT)

	# ---- 经验条（标签在条上方一行，条与头像底边对齐）----
	var need := p.exp_to_next()
	var bar := _exp_rect
	var exp_label := "经验  %s" % ("已满级" if need <= 0 else "%d / %d EXP" % [p.exp, need])
	_draw_text(font, Vector2(bar.position.x, bar.position.y - _px(12.0)), exp_label,
		_px(F_LABEL), TEXT)
	# 实时预览等级（只读影子推演，不改真实状态）
	if need > 0 and _preview_count > 0:
		var shadow := _preview_shadow(p)
		if shadow != null and shadow.level > p.level:
			var pv := "预览 → Lv.%d" % shadow.level
			# 预览等级同样带脉冲，与属性行增量同步闪烁
			var pv_col := POSITIVE_DELTA if _delta_pulse > 0.05 else POSITIVE
			_draw_text(font, Vector2(bar.position.x + bar.size.x - _text_w(font, pv, F_LABEL),
				bar.position.y - _px(12.0)), pv, _px(F_LABEL), pv_col)
	_draw_exp_bar(bar, p, true)

	# ---- 突破节点 ----
	_draw_breakthrough_section(font, p)

	# ---- 面板属性 ----
	_draw_stats_section(font, p)

	# ---- 按钮 ----
	for b: Dictionary in _btn_rects:
		var r: Rect2 = b["rect"]
		var action := str(b["action"])
		var label := ""
		var icon := ""
		var active := false
		match action:
			"cycle_item":
				label = "学习记录类型：%s（点击切换）" % _item_name(_preview_item)
				icon = "icon_refresh"
			"preview":
				var cnt := int(b.get("arg", 0))
				label = "投入 %d 份" % cnt
				icon = "icon_study_record"
				# 当前生效的档位：与预览份数一致时高亮为"已选中"
				active = _preview_count > 0 and cnt == _preview_count
			"levelup":
				label = "升级（投入 %d 份）" % maxi(1, _preview_count)
				icon = "icon_confirm"
			"breakthrough":
				label = "突破"
				icon = "icon_rift_shard"
		# 可点状态由 _button_enabled 唯一决定：绘制与命中不会出现分歧
		_draw_button(r, label, _button_enabled(action, b.get("arg", null)), icon, active)


## 经验条：底槽 + 填充 + 高光 + 边框 + 文本
func _draw_exp_bar(bar: Rect2, p: CharacterProgress, with_text: bool) -> void:
	if bar.size.x <= 0.0 or bar.size.y <= 0.0:
		return
	var need := p.exp_to_next()
	var ratio := 0.0 if need <= 0 else clampf(float(p.exp) / float(need), 0.0, 1.0)
	var radius := bar.size.y * 0.35
	# 底槽
	draw_style_box(_sb(Color(0.045, 0.055, 0.095, 0.95), BORDER_SOFT, radius, _px(1.0)), bar)
	if ratio > 0.0:
		var fill := Rect2(bar.position,
			Vector2(maxf(bar.size.y * 0.8, bar.size.x * ratio), bar.size.y))
		draw_style_box(_sb(ACCENT.darkened(0.22), ACCENT, radius, _px(1.0)), fill)
		# 高光：填充区上缘的一条亮线
		draw_rect(Rect2(Vector2(fill.position.x + _px(2.0), fill.position.y + _px(2.0)),
			Vector2(maxf(0.0, fill.size.x - _px(4.0)), maxf(1.0, bar.size.y * 0.22))),
			Color(1.0, 1.0, 1.0, 0.30), true)
	# 已满级：整条走正向色，明确"无需再投入"
	if need <= 0:
		draw_style_box(_sb(Color(POSITIVE.r, POSITIVE.g, POSITIVE.b, 0.30), POSITIVE,
			radius, _px(1.0)), bar)
	if with_text and bar.size.x > _px(180.0):
		var label := "已满级" if need <= 0 else "%d / %d" % [p.exp, need]
		var f := _mono_font() if need > 0 else ThemeDB.fallback_font
		var tw := _text_w(f, label, F_TINY)
		_draw_text(f, Vector2(bar.position.x + (bar.size.x - tw) * 0.5,
			bar.position.y + bar.size.y * 0.5 + _px(8.0)),
			label, _px(F_TINY),
			TEXT if ratio < 0.55 else Color(0.06, 0.09, 0.16))


## 突破节点带：菱形节点（已达成 / 未达成两态）+ 连线 + 成本/原因
func _draw_breakthrough_section(font: Font, p: CharacterProgress) -> void:
	var band := _nodes_rect
	var ix := band.position.x
	var iw := band.size.x
	if iw <= 0.0:
		return

	_draw_text(font, Vector2(ix, band.position.y + _px(24.0)), "突破节点",
		_px(F_LABEL), DIM)

	var levels: Array = DataRegistry.get_domain("character_growth").get("globalRules", {}) \
		.get("breakthroughLevels", [])
	if levels.is_empty():
		_draw_text(font, Vector2(ix, band.position.y + _px(72.0)), "（突破节点数据缺失）",
			_px(F_LABEL), WARN)
		return

	var node_cy := band.position.y + _px(84.0)
	var half := _px(22.0)
	var label_y := node_cy + half + _px(32.0)
	var n := levels.size()
	var span := maxf(_px(1.0), iw - half * 2.0)
	var step := span / float(maxi(1, n - 1))

	# 连线：**已走过的段**（即已达成突破之间的段）用冰蓝实线 + 底部投影，
	# 未走到的段用暗色虚线。让"进度到哪一格"沿轨道一眼可读。
	for i: int in range(n - 1):
		var x0 := ix + half + step * float(i)
		var x1 := ix + half + step * float(i + 1)
		var a := Vector2(x0 + half * 0.7, node_cy)
		var b := Vector2(x1 - half * 0.7, node_cy)
		var done := (i + 1) < p.breakthrough
		if done:
			# 已达成段：外发光 + 亮线，明确"这段已经过去"
			draw_line(a, b, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.28), _px(9.0), true)
			draw_line(a, b, ACCENT, _px(4.0), true)
		else:
			# 未达成段：暗色虚线，与实线形成"未走通"的语义
			_draw_dashed_line(a, b, Color(0.26, 0.32, 0.46), _px(3.0), _px(9.0), _px(7.0))

	# 节点
	for i: int in range(n):
		var cx := ix + half + step * float(i)
		var achieved := (i + 1) <= p.breakthrough
		var pts := PackedVector2Array([
			Vector2(cx, node_cy - half),
			Vector2(cx + half, node_cy),
			Vector2(cx, node_cy + half),
			Vector2(cx - half, node_cy)])
		var outline := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		if achieved:
			# 已达成：外发光环 + 实心冰蓝 + 亮描边
			draw_circle(Vector2(cx, node_cy), half * 1.55,
				Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18))
			draw_colored_polygon(pts, ACCENT)
			draw_polyline(outline, Color(0.90, 0.97, 1.0), _px(2.0), true)
		else:
			# 未达成：暗底 + 冷灰描边 + 内圈暗环（与已达成一眼可辨）
			draw_circle(Vector2(cx, node_cy), half * 1.35,
				Color(0.10, 0.12, 0.20, 0.55))
			draw_colored_polygon(pts, Color(0.115, 0.135, 0.215, 0.98))
			draw_polyline(outline, Color(0.46, 0.53, 0.70), _px(3.0), true)
			draw_circle(Vector2(cx, node_cy), half * 0.42, Color(0.055, 0.065, 0.115))
		var lv := int(levels[i])
		var txt := "Lv.%d" % lv
		# 节点等级：等宽字体居中 + 描边；已达成亮冰蓝，未达成冷灰
		var f := _mono_font()
		_draw_text(f, Vector2(cx - _text_w(f, txt, F_TINY) * 0.5, label_y), txt,
			_px(F_TINY), ACCENT if achieved else FAINT)

	# ---- 成本 / 原因 ----
	var next := p.next_breakthrough_level()
	var cost_y := label_y + _px(34.0)
	if next <= 0:
		_draw_text(font, Vector2(ix, cost_y), "已完成全部突破", _px(F_LABEL), POSITIVE)
		return

	var q := _svc.query_breakthrough(_selected_id)
	var q_ok := bool(q.get("ok", false))
	var cost := p.next_breakthrough_cost()
	var cx2 := ix
	var head := "突破 %d 需要：" % next
	_draw_text(font, Vector2(cx2, cost_y), head, _px(F_LABEL), DIM)
	cx2 += _text_w(font, head, F_LABEL) + _px(8.0)
	var icon_s := _px(ICON_SIZE_COST)
	for cid: String in cost.keys():
		var req := int(cost[cid])
		if req <= 0:
			continue
		var have := _svc.get_currency(cid)
		# 图标按文字基线对齐（此前是 cost_y - icon_s + 4，视觉上偏上）
		_draw_icon(str(CURRENCY_ICON.get(cid, "icon_material")),
			Vector2(cx2, _icon_y_for_text(cost_y, F_LABEL, icon_s)), icon_s)
		cx2 += icon_s + _px(6.0)
		# 「持有/需求」用等宽数字右对齐固定槽，位数不同也不会让后面的资源名错位
		var name_part := "%s " % _currency_name(cid)
		_draw_text(font, Vector2(cx2, cost_y), name_part, _px(F_LABEL), DIM)
		cx2 += _text_w(font, name_part, F_LABEL)
		# **资源不足必须清晰可读**：亮红 + 描边（描边由 _draw_text 统一加）。
		# 「持有/需求」数字用等宽字体，且后续资源锚定在固定槽右缘，
		# 因此 5/3 与 1200/800 不会让后面的资源名错位。
		var num_col := POSITIVE_DELTA if have >= req else INSUFFICIENT
		_draw_text(_mono_font(), Vector2(cx2, cost_y), "%d/%d" % [have, req],
			_px(F_LABEL), num_col)
		# 槽宽 = 「4位 / 4位」的最大可能宽度；数字左对齐紧贴资源名，
		# 但下一个资源的图标锚定在槽右缘，故 5/3 与 1200/800 不会互相挤压。
		var pair_w := _num_slot_w(COST_PAIR_DIGITS, F_LABEL) * 2.0 \
			+ _text_w(_mono_font(), "/", F_LABEL)
		cx2 += maxf(_text_w(_mono_font(), "%d/%d" % [have, req], F_LABEL), pair_w) + _px(22.0)

	if not q_ok:
		var reason := str(q.get("reason", ""))
		if not reason.is_empty():
			_draw_text(font, Vector2(ix, cost_y + _px(30.0)), "· %s" % reason,
				_px(F_TINY), WARN)


## 画虚线（未达成段的轨道）。沿 a→b 按 dash/gap 交替绘制。
func _draw_dashed_line(a: Vector2, b: Vector2, color: Color, width: float,
		dash: float, gap: float) -> void:
	var total := a.distance_to(b)
	if total <= 0.0:
		return
	var dir := (b - a) / total
	var t := 0.0
	while t < total:
		var t1 := minf(t + dash, total)
		draw_line(a + dir * t, a + dir * t1, color, width, true)
		t = t1 + gap


## 面板属性：图标 + 名称 + 当前值 + 升级预览的 +N 绿色增量（带闪烁/上浮动画）
func _draw_stats_section(font: Font, p: CharacterProgress) -> void:
	var r := _stats_rect
	draw_style_box(_sb(Color(0.075, 0.090, 0.160, 0.90), BORDER_SOFT, _px(10.0), _px(1.0)), r)

	var pad := _px(20.0)
	_draw_text(font, Vector2(r.position.x + pad, r.position.y + _px(30.0)), "当前面板",
		_px(F_TINY), DIM)

	var cur := p.compute_stats()
	var preview := _preview_stats(p)
	var keys := ["hp", "attack", "defense", "healPower"]
	# 只显示角色真正拥有的属性（compute_stats 的纪律：base<=0 的属性不出现）
	var shown: Array[String] = []
	for k: String in keys:
		if cur.has(k):
			shown.append(k)
	if shown.is_empty():
		return

	var inner_w := r.size.x - pad * 2.0
	var cell_w := inner_w / float(shown.size())
	var cy := r.position.y + _px(78.0)
	var icon_s := _px(ICON_SIZE_STAT)
	# 闪烁：预览变化后短暂放大/加亮；上浮：+N 短暂抬起再落位
	var pulse := _delta_pulse
	var lift := -_px(10.0) * _delta_float
	for i: int in range(shown.size()):
		var k: String = shown[i]
		var x := r.position.x + pad + cell_w * float(i)
		# 图标按属性名基线对齐
		var name_base := cy - _px(6.0)
		_draw_icon(str(STAT_ICON.get(k, "icon_material")),
			Vector2(x, _icon_y_for_text(name_base, F_TINY, icon_s)), icon_s)
		var tx := x + icon_s + _px(10.0)
		_draw_text(font, Vector2(tx, name_base), _stat_name(k), _px(F_TINY), DIM)

		# 当前值：等宽字体 + 右对齐固定槽，位数变化时 +N 不会左右跳
		var val_w := _num_slot_w(STAT_DIGITS, F_LABEL)
		# 升级/突破刚发生：该属性行瞬时高亮（底色块 + 更亮的数值）
		var flash := float(_flash_rows.get(k, 0.0))
		if flash > 0.0:
			var glow := Color(POSITIVE_GLOW.r, POSITIVE_GLOW.g, POSITIVE_GLOW.b,
				0.22 * clampf(flash / 1.2, 0.0, 1.0)) \
				if _flash_kind == "levelup" \
				else Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22 * clampf(flash / 1.2, 0.0, 1.0))
			draw_style_box(_sb(glow, Color(0, 0, 0, 0), _px(6.0), 0.0),
				Rect2(Vector2(x - _px(6.0), cy - _px(22.0)),
					Vector2(cell_w - _px(16.0), _px(52.0))))
		var val_col := TEXT
		if flash > 0.0:
			val_col = POSITIVE_DELTA if _flash_kind == "levelup" else Color(0.80, 0.94, 1.0)
		# 数值紧贴属性名左对齐；+N 增量锚定在固定槽右缘（见 _num_slot_w 约定）
		_draw_text(_mono_font(), Vector2(tx, cy + _px(28.0)), str(int(cur[k])),
			_px(F_LABEL), val_col)

		# 升级预览增量：+N 亮绿 + 脉冲发光 + 短暂上浮
		if preview.has(k) and int(preview[k]) > int(cur[k]):
			var delta := "+%d" % (int(preview[k]) - int(cur[k]))
			var dx := tx + val_w + _px(12.0)
			var dy := cy + _px(28.0) + lift
			if pulse > 0.02:
				# 发光底衬：脉冲越强越大越亮，让"数值刚刚变了"被看见
				var fw := _text_w(font, delta, F_LABEL)
				draw_style_box(_sb(Color(POSITIVE_GLOW.r, POSITIVE_GLOW.g, POSITIVE_GLOW.b,
					0.30 * pulse), Color(0, 0, 0, 0), _px(6.0), 0.0),
					Rect2(Vector2(dx - _px(6.0), dy - _px(24.0)),
						Vector2(fw + _px(12.0), _px(34.0))))
			# 脉冲期间数字更亮（POSITIVE_DELTA），衰减后回到常规薄荷绿
			var dcol := POSITIVE_DELTA.lerp(POSITIVE, clampf(1.0 - pulse, 0.0, 1.0))
			_draw_text(font, Vector2(dx, dy), delta, _px(F_LABEL), dcol)


## 升级/突破成功后：点亮发生变化的属性行（即时反馈，而不只是数字变了）。
## 纯表现：只读 compute_stats 的差值，不触碰任何领域状态。
func _flash_changed_rows(p: CharacterProgress, before: Dictionary, kind: String) -> void:
	var after := p.compute_stats()
	_flash_rows.clear()
	for k: String in after.keys():
		if not before.has(k):
			continue
		if int(after[k]) != int(before[k]):
			_flash_rows[k] = 1.2
	if not _flash_rows.is_empty():
		_flash_kind = kind
		_delta_pulse = 1.0
		_delta_float = 1.0


## 底部反馈条
func _draw_feedback(font: Font) -> void:
	if _feedback_timer <= 0.0 or _feedback.is_empty():
		return
	var w := _text_w(font, _feedback, F_BODY)
	var pos := Vector2((_viewport.x - w) * 0.5, _viewport.y - _px(44.0))
	var box := Rect2(Vector2(pos.x - _px(22.0), pos.y - _px(32.0)),
		Vector2(w + _px(44.0), _px(50.0)))
	draw_style_box(_sb(Color(0.035, 0.045, 0.085, 0.94), _feedback_color, _px(10.0), _px(2.0)), box)
	_draw_text(font, pos, _feedback, _px(F_BODY), _feedback_color)


## 按钮状态：正常 / 悬停 / **已选中** / 禁用 / 悬停在禁用上。
## 填充 + 边框 + 文字色三者同时变化，保证任一状态一眼可辨。
##   active: 当前生效的档位（如「投入 5 份」正是预览中的份数）
func _draw_button(rect: Rect2, label: String, enabled: bool, icon: String = "",
		active: bool = false) -> void:
	var font := GameSkin.body_font()
	var over := rect.has_point(_mouse_pos)
	var hovered := enabled and over

	var fill := BUTTON
	var edge := BUTTON_BORDER
	var txt := TEXT
	if not enabled:
		fill = BUTTON_DISABLED
		# 鼠标停在禁用按钮上：描边转红，明确"这里点不动"，
		# 而不是让玩家点下去之后才在底部看到原因。
		edge = BUTTON_BORDER_REJECT if over else BUTTON_BORDER_DISABLED
		txt = TEXT_DISABLED
	elif active:
		fill = BUTTON_ACTIVE
		edge = BUTTON_BORDER_ACTIVE
		txt = Color(1, 1, 1)
	elif hovered:
		fill = BUTTON_HOVER
		edge = BUTTON_BORDER_HOVER
		txt = Color(1, 1, 1)

	draw_style_box(_sb(fill, edge, _px(10.0), _px(2.0)), rect)
	# 悬停时加一层内高光，强化"可点"反馈
	if hovered:
		draw_rect(Rect2(Vector2(rect.position.x + _px(3.0), rect.position.y + _px(3.0)),
			Vector2(maxf(0.0, rect.size.x - _px(6.0)), _px(2.0))),
			Color(1.0, 1.0, 1.0, 0.22), true)
	# 已选中档位：左侧一条亮色指示条，与 hover 区分开
	if active:
		draw_style_box(_sb(BUTTON_BORDER_ACTIVE, Color(0, 0, 0, 0), _px(2.0), 0.0),
			Rect2(Vector2(rect.position.x + _px(6.0), rect.position.y + _px(10.0)),
				Vector2(_px(4.0), maxf(_px(4.0), rect.size.y - _px(20.0)))))

	var font_sz := _px(F_LABEL)
	var icon_s := _px(ICON_SIZE_BUTTON)
	var tw := _text_w(font, label, F_LABEL)
	var total := tw
	if not icon.is_empty():
		total += icon_s + _px(10.0)
	var x := rect.position.x + (rect.size.x - total) * 0.5
	# 垂直居中：用字体自身的 ascent/descent 求基线，
	# 而不是经验常数（后者在字号或字体变化时会偏上/偏下）。
	var mid := rect.position.y + rect.size.y * 0.5
	var fs := int(font_sz)
	var baseline := mid + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	if not icon.is_empty():
		_draw_icon(icon, Vector2(x, _icon_y_for_text(baseline, F_LABEL, icon_s)), icon_s,
			Color(1, 1, 1, 1.0 if enabled else 0.45))
		x += icon_s + _px(10.0)
	_draw_text(font, Vector2(x, baseline), label, font_sz, txt)


# ============================================================ 预览推演（只读，不改状态）

## 影子进度对象：复制一份做推演，**并已投入拟投入的经验**，绝不改真实对象。
## 无预览或数据不足时返回 null。
## 用 CharacterProgress.from_growth_config 重建（与领域层同一构造路径），
## 再覆盖 level/breakthrough/exp，最后调用领域层的 add_exp 做推演 ——
## 不改任何领域行为，只是另起一个只读副本。
func _preview_shadow(p: CharacterProgress) -> CharacterProgress:
	if _preview_count <= 0:
		return null
	var items := _svc.study_record_items()
	var per := int(items.get(_preview_item, 0))
	if per <= 0:
		return null
	var shadow := CharacterProgress.from_growth_config(
		p.character_id,
		DataRegistry.get_domain("character_growth"),
		_base_stats_of(p.character_id),
		p.growth_profile_id)
	shadow.level = p.level
	shadow.breakthrough = p.breakthrough
	shadow.exp = p.exp
	# 关键：必须真的把经验投进影子对象，否则 shadow.level 恒等于 p.level，
	# 「预览 → Lv.N」永远不会出现、属性增量也永远是 0。
	shadow.add_exp(per * _preview_count)
	return shadow


## 预览：按拟投入本数算出的新面板（不改任何状态）
func _preview_stats(p: CharacterProgress) -> Dictionary:
	var shadow := _preview_shadow(p)
	if shadow == null:
		return {}
	return shadow.compute_stats()


func _base_stats_of(character_id: String) -> Dictionary:
	var cfg: Dictionary = DataRegistry.get_entry("characters", character_id)
	var base: Dictionary = (cfg.get("baseStats", {}) as Dictionary).duplicate(true)
	if cfg.has("healPower"):
		base["healPower"] = int(cfg.get("healPower", 0))
	return base


func _stat_name(key: String) -> String:
	match key:
		"hp":
			return "生命"
		"attack":
			return "攻击"
		"defense":
			return "防御"
		"healPower":
			return "治疗力"
		_:
			return key


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


func _role_color(behavior: String) -> Color:
	match behavior:
		"RANGED":
			return Color(0.98, 0.72, 0.30)
		"HEALER":
			return Color(0.45, 0.95, 0.62)
		_:
			return Color(0.35, 0.80, 0.98)

