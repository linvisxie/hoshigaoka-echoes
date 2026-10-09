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
const CARD_SELECTED := Color(0.130, 0.300, 0.580, 0.94)
const CARD_SELECTED_HOVER := Color(0.170, 0.370, 0.680, 0.96)
const TEXT := Color(0.90, 0.94, 1.0)
const DIM := Color(0.62, 0.68, 0.82)
const FAINT := Color(0.42, 0.47, 0.62)
const ACCENT := Color(0.42, 0.76, 0.98)      # 冰蓝：可交互 / AP
const POSITIVE := Color(0.45, 0.95, 0.62)    # 薄荷绿：治疗 / 正向
const WARN := Color(0.95, 0.72, 0.35)
const DANGER := Color(0.98, 0.30, 0.42)
const BORDER := Color(0.30, 0.42, 0.66, 0.85)
const BORDER_SOFT := Color(0.24, 0.30, 0.46, 0.80)
const BUTTON := Color(0.16, 0.21, 0.36)
const BUTTON_HOVER := Color(0.26, 0.40, 0.66)
const BUTTON_DISABLED := Color(0.105, 0.115, 0.155)
const BUTTON_BORDER := Color(0.40, 0.56, 0.86)
const BUTTON_BORDER_HOVER := Color(0.62, 0.82, 1.0)
const BUTTON_BORDER_DISABLED := Color(0.24, 0.26, 0.34)
const TEXT_DISABLED := Color(0.42, 0.45, 0.55)

## 背景遮罩：让背景退到 UI 之后，保证文字可读（与 battle_scene 的 BG_SCRIM 同思路）
const SCRIM := Color(0.020, 0.028, 0.058, 0.78)

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

var _viewport: Vector2 = Vector2(1920, 1080)
var _scale: float = 1.0

## 表现层缓存（StyleBox / 渐变贴图 / 贴图）。配色集合固定，缓存规模有界。
var _sb_cache: Dictionary = {}
var _grad_cache: Dictionary = {}
var _tex_cache: Dictionary = {}


func _ready() -> void:
	_refresh_viewport()
	_ensure_service()
	_pick_first_character()
	_layout()
	GameLog.info(TAG, "角色培养界面就绪（%d 名角色，服务就绪=%s，画布 %.0fx%.0f，缩放 %.3f）"
		% [_card_ids.size(), str(_svc != null and _svc.is_ready()),
			_viewport.x, _viewport.y, _scale])
	queue_redraw()


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
			_card_ids.append(cid)
		_card_ids.sort()
	if not _card_ids.is_empty():
		_selected_id = _card_ids[0]
	GameLog.info(TAG, "角色培养界面：载入 %d 名角色（服务就绪=%s）"
		% [_card_ids.size(), str(_svc != null and _svc.is_ready())])


func _px(v: float) -> float:
	return v * _scale


func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer = maxf(0.0, _feedback_timer - delta)
	# 每帧重取画布尺寸：窗口拉伸 / 分辨率变化时布局随之重算（仅读 size，无副作用）
	_refresh_viewport()
	_layout()
	queue_redraw()


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
			_preview_count = 0
		elif k >= KEY_1 and k <= KEY_6:
			var idx := k - KEY_1
			if idx < _card_ids.size():
				_selected_id = _card_ids[idx]
				_preview_count = 0
				_show("已选择 %s" % _display_name(_selected_id), ACCENT)


func _handle_click(pos: Vector2) -> void:
	# 角色卡
	for i: int in range(_card_rects.size()):
		if _card_rects[i].has_point(pos):
			_selected_id = _card_ids[i]
			_preview_count = 0
			_show("已选择 %s" % _display_name(_selected_id), ACCENT)
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
	var res := _svc.do_breakthrough(_selected_id)
	if not bool(res.get("ok", false)):
		_show("突破失败：%s" % str(res.get("reason", "")), DANGER)
		return
	if not _svc.commit():
		_show("突破成功但存档写入失败（请检查磁盘）", DANGER)
		return
	_show("%s 完成突破 %d（等级上限 Lv.%d）" % [
		_display_name(_selected_id), int(res.get("breakthroughAfter", 0)),
		_svc.get_progress(_selected_id).level_cap()], POSITIVE)
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
func _icon_tex(name: String) -> Texture2D:
	var key := "icon:" + name
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var t := ArtRegistry.icon(name, 64)
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
func _draw_icon(name: String, pos: Vector2, size: float, tint: Color = Color(1, 1, 1, 1)) -> void:
	var tex := _icon_tex(name)
	if tex == null:
		draw_style_box(_sb(Color(0.18, 0.22, 0.34, 0.85), FAINT, size * 0.22, 1.0),
			Rect2(pos, Vector2(size, size)))
		return
	draw_texture_rect(tex, Rect2(pos, Vector2(size, size)), false, tint)


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
		Vector2(list_w, maxf(0.0, _info_rect.position.y - gap - list_top)))

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

	var font := ThemeDB.fallback_font
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
	var font := ThemeDB.fallback_font
	var w := _text_w(font, text, F_LABEL)
	draw_string(font, Vector2((_viewport.x - w) * 0.5, _viewport.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), color)


## 顶部：标题 + 资源条（图标 + 数字并列）
func _draw_header(font: Font) -> void:
	var hb := _header_rect
	draw_rect(Rect2(Vector2.ZERO, Vector2(_viewport.x, hb.size.y)),
		Color(0.030, 0.040, 0.075, 0.88), true)
	draw_rect(Rect2(Vector2(0.0, hb.size.y - _px(2.0)), Vector2(_viewport.x, _px(2.0))),
		Color(0.30, 0.45, 0.72, 0.55), true)

	# 标题徽记（icon_ap 仅作本页入口标识，不表示任何 AP 数值）
	var emblem := _px(64.0)
	var ex := _px(48.0)
	_draw_icon("icon_ap", Vector2(ex, _px(42.0)), emblem)
	var tx := ex + emblem + _px(16.0)
	draw_string(font, Vector2(tx, _px(88.0)), "角色培养",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TITLE)), TEXT)
	draw_string(font, Vector2(tx, _px(126.0)),
		"Alpha A0.1 — 等级 / 突破。技能 / 档案 / 故事属后续阶段。",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)), DIM)

	_draw_currency_bar(font)


## 五类资源条（顺序与 displayOrder 一致，唯一来自 currencies.json）：图标 + 名称 + 数量
func _draw_currency_bar(font: Font) -> void:
	var entries: Array = DataRegistry.get_domain("currencies").get("currencies", [])
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("displayOrder", 0)) < int(b.get("displayOrder", 0)))

	var chip_h := _px(52.0)
	var chip_y := _px(48.0)
	var icon_s := _px(36.0)
	var gap := _px(12.0)

	# 先量总宽，再整体右对齐
	var widths: Array[float] = []
	var total := 0.0
	for c: Dictionary in sorted:
		var cid := str(c.get("id", ""))
		var label := "%s %d" % [str(c.get("name", cid)), _svc.get_currency(cid)]
		var w := _px(14.0) + icon_s + _px(10.0) + _text_w(font, label, F_LABEL) + _px(18.0)
		widths.append(w)
		total += w + gap
	if not widths.is_empty():
		total -= gap

	var x := maxf(_px(660.0), _viewport.x - _px(48.0) - total)
	for i: int in range(sorted.size()):
		var c: Dictionary = sorted[i]
		var cid := str(c.get("id", ""))
		var label := "%s %d" % [str(c.get("name", cid)), _svc.get_currency(cid)]
		var r := Rect2(Vector2(x, chip_y), Vector2(widths[i], chip_h))
		draw_style_box(_sb(Color(0.08, 0.10, 0.18, 0.90), BORDER_SOFT, _px(8.0), _px(1.0)), r)
		_draw_icon(str(CURRENCY_ICON.get(cid, "icon_material")),
			Vector2(r.position.x + _px(14.0), r.position.y + (chip_h - icon_s) * 0.5), icon_s)
		draw_string(font, Vector2(r.position.x + _px(14.0) + icon_s + _px(10.0),
			r.position.y + chip_h * 0.5 + _px(8.0)),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), TEXT)
		x += widths[i] + gap


## 角色卡：真实头像 + 姓名 + 等级 + 定位 + 迷你经验条
func _draw_character_card(character_id: String, rect: Rect2, index: int) -> void:
	var font := ThemeDB.fallback_font
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
		draw_string(font, Vector2(prect.position.x + (ps - _text_w(font, ch, F_TITLE)) * 0.5,
			prect.position.y + ps * 0.5 + _px(16.0)),
			ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TITLE)), TEXT)
	draw_style_box(_sb(Color(0, 0, 0, 0), edge, _px(8.0), _px(2.0)), prect)

	var tx := prect.position.x + ps + pad
	var tw := maxf(_px(80.0), rect.position.x + rect.size.x - pad - tx)

	# 姓名
	draw_string(font, Vector2(tx, rect.position.y + rect.size.y * 0.44),
		str(cfg.get("name", character_id)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_NAME)), TEXT)

	# 等级 + 突破
	if p != null:
		var lv_text := "Lv.%d / %d" % [p.level, p.level_cap()]
		var ly := rect.position.y + rect.size.y * 0.66
		draw_string(font, Vector2(tx, ly), lv_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), ACCENT)
		if p.breakthrough > 0:
			draw_string(font, Vector2(tx + _text_w(font, lv_text, F_LABEL) + _px(14.0), ly),
				"突破 %d" % p.breakthrough,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)), POSITIVE)
		# 迷你经验条
		var bar := Rect2(Vector2(tx, rect.position.y + rect.size.y - _px(34.0)),
			Vector2(tw, _px(12.0)))
		_draw_exp_bar(bar, p, false)

	# 定位标签（右上）
	var role := _role_label(behavior)
	var rw := _text_w(font, role, F_TINY) + _px(20.0)
	var rrect := Rect2(
		Vector2(rect.position.x + rect.size.x - pad - rw, rect.position.y + _px(14.0)),
		Vector2(rw, _px(32.0)))
	draw_style_box(_sb(Color(role_color.r, role_color.g, role_color.b, 0.18),
		role_color, _px(6.0), _px(1.0)), rrect)
	draw_string(font, Vector2(rrect.position.x + _px(10.0), rrect.position.y + _px(23.0)),
		role, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)), role_color)

	# 序号（右下）
	var idx_label := "[%d]" % (index + 1)
	draw_string(font, Vector2(rect.position.x + rect.size.x - pad - _text_w(font, idx_label, F_TINY),
		rect.position.y + rect.size.y - _px(14.0)), idx_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)), FAINT)


## 左下：学习记录库存（图标 + 名称 + 持有本数 + 单份 EXP）
func _draw_study_inventory(font: Font) -> void:
	var r := _info_rect
	draw_style_box(_sb(PANEL_BG, BORDER_SOFT, _px(12.0), _px(2.0)), r)
	var pad := _px(24.0)
	var ix := r.position.x + pad
	var iy := r.position.y + pad
	var iw := maxf(_px(120.0), r.size.x - pad * 2.0)

	draw_string(font, Vector2(ix, iy + _px(24.0)), "学习记录库存",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), TEXT)

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
		var ic := _px(36.0)
		_draw_icon("icon_study_record",
			Vector2(rr.position.x + _px(12.0), rr.position.y + (row_h - ic) * 0.5), ic)
		draw_string(font, Vector2(rr.position.x + _px(12.0) + ic + _px(12.0),
			rr.position.y + row_h * 0.5 + _px(9.0)),
			str(item.get("name", iid)), HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_px(F_LABEL)), TEXT if picked else DIM)
		var right := "持有 %d 本 · %d EXP/本" % [
			_svc.get_currency(iid), int(item.get("expValue", 0))]
		draw_string(font, Vector2(
			rr.position.x + rr.size.x - _px(12.0) - _text_w(font, right, F_TINY),
			rr.position.y + row_h * 0.5 + _px(9.0)),
			right, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)),
			ACCENT if picked else DIM)
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

	draw_string(font, Vector2(rx, iy + _px(44.0)), _display_name(_selected_id),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TITLE)), TEXT)

	# 定位标签
	var role := _role_label(behavior)
	var role_w := _text_w(font, role, F_TINY) + _px(24.0)
	var rrect := Rect2(Vector2(rx, iy + _px(62.0)), Vector2(role_w, _px(34.0)))
	draw_style_box(_sb(Color(role_color.r, role_color.g, role_color.b, 0.18),
		role_color, _px(6.0), _px(1.0)), rrect)
	draw_string(font, Vector2(rrect.position.x + _px(12.0), rrect.position.y + _px(24.0)),
		role, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)), role_color)

	# 大号等级数字 + 上限
	var lv_text := "Lv.%d" % p.level
	var lv_w := _text_w(font, lv_text, F_BIG_LEVEL)
	draw_string(font, Vector2(rx, iy + _px(150.0)), lv_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_BIG_LEVEL)), ACCENT)
	draw_string(font, Vector2(rx + lv_w + _px(20.0), iy + _px(118.0)),
		"等级上限 Lv.%d" % p.level_cap(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), DIM)

	# 突破阶段（放在大号等级数字右侧的第二行，避免与经验条抢位）
	var next_lv := p.next_breakthrough_level()
	var bt_text := "突破阶段 %d" % p.breakthrough
	if next_lv > 0:
		bt_text += "  ·  下一阶需 Lv.%d" % int(
			(DataRegistry.get_domain("character_growth").get("breakthroughs", [])[next_lv - 1]
				as Dictionary).get("requiredLevel", 0))
	draw_string(font, Vector2(rx + lv_w + _px(20.0), iy + _px(150.0)), bt_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), TEXT)

	# ---- 经验条（标签在条上方一行，条与头像底边对齐）----
	var need := p.exp_to_next()
	var bar := _exp_rect
	var exp_label := "经验  %s" % ("已满级" if need <= 0 else "%d / %d EXP" % [p.exp, need])
	draw_string(font, Vector2(bar.position.x, bar.position.y - _px(12.0)), exp_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), TEXT)
	# 实时预览等级（只读影子推演，不改真实状态）
	if need > 0 and _preview_count > 0:
		var shadow := _preview_shadow(p)
		if shadow != null and shadow.level > p.level:
			var pv := "预览 → Lv.%d" % shadow.level
			draw_string(font, Vector2(bar.position.x + bar.size.x - _text_w(font, pv, F_LABEL),
				bar.position.y - _px(12.0)), pv,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), POSITIVE)
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
		match action:
			"cycle_item":
				label = "学习记录类型：%s（点击切换）" % _item_name(_preview_item)
				icon = "icon_refresh"
			"preview":
				label = "投入 %d 份" % int(b.get("arg", 0))
				icon = "icon_study_record"
			"levelup":
				label = "升级（投入 %d 份）" % maxi(1, _preview_count)
				icon = "icon_confirm"
			"breakthrough":
				label = "突破"
				icon = "icon_rift_shard"
		# 可点状态由 _button_enabled 唯一决定：绘制与命中不会出现分歧
		_draw_button(r, label, _button_enabled(action, b.get("arg", null)), icon)


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
		var tw := _text_w(ThemeDB.fallback_font, label, F_TINY)
		draw_string(ThemeDB.fallback_font,
			Vector2(bar.position.x + (bar.size.x - tw) * 0.5,
				bar.position.y + bar.size.y * 0.5 + _px(8.0)),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)),
			TEXT if ratio < 0.55 else Color(0.06, 0.09, 0.16))


## 突破节点带：菱形节点（已达成 / 未达成两态）+ 连线 + 成本/原因
func _draw_breakthrough_section(font: Font, p: CharacterProgress) -> void:
	var band := _nodes_rect
	var ix := band.position.x
	var iw := band.size.x
	if iw <= 0.0:
		return

	draw_string(font, Vector2(ix, band.position.y + _px(24.0)), "突破节点",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), DIM)

	var levels: Array = DataRegistry.get_domain("character_growth").get("globalRules", {}) \
		.get("breakthroughLevels", [])
	if levels.is_empty():
		draw_string(font, Vector2(ix, band.position.y + _px(72.0)), "（突破节点数据缺失）",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), WARN)
		return

	var node_cy := band.position.y + _px(84.0)
	var half := _px(22.0)
	var label_y := node_cy + half + _px(32.0)
	var n := levels.size()
	var span := maxf(_px(1.0), iw - half * 2.0)
	var step := span / float(maxi(1, n - 1))

	# 连线（已走过的段用冰蓝，未走到的段用暗色）
	for i: int in range(n - 1):
		var x0 := ix + half + step * float(i)
		var x1 := ix + half + step * float(i + 1)
		var done := (i + 1) < p.breakthrough
		draw_line(Vector2(x0 + half * 0.7, node_cy), Vector2(x1 - half * 0.7, node_cy),
			ACCENT if done else Color(0.22, 0.27, 0.40), _px(3.0), true)

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
		draw_string(font, Vector2(cx - _text_w(font, txt, F_TINY) * 0.5, label_y), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)),
			ACCENT if achieved else FAINT)

	# ---- 成本 / 原因 ----
	var next := p.next_breakthrough_level()
	var cost_y := label_y + _px(34.0)
	if next <= 0:
		draw_string(font, Vector2(ix, cost_y), "已完成全部突破",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), POSITIVE)
		return

	var q := _svc.query_breakthrough(_selected_id)
	var q_ok := bool(q.get("ok", false))
	var cost := p.next_breakthrough_cost()
	var cx2 := ix
	var head := "突破 %d 需要：" % next
	draw_string(font, Vector2(cx2, cost_y), head,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), DIM)
	cx2 += _text_w(font, head, F_LABEL) + _px(8.0)
	var icon_s := _px(28.0)
	for cid: String in cost.keys():
		var req := int(cost[cid])
		if req <= 0:
			continue
		var have := _svc.get_currency(cid)
		_draw_icon(str(CURRENCY_ICON.get(cid, "icon_material")),
			Vector2(cx2, cost_y - icon_s + _px(4.0)), icon_s)
		cx2 += icon_s + _px(6.0)
		var part := "%s %d/%d" % [_currency_name(cid), have, req]
		draw_string(font, Vector2(cx2, cost_y), part,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)),
			POSITIVE if have >= req else WARN)
		cx2 += _text_w(font, part, F_LABEL) + _px(22.0)

	if not q_ok:
		var reason := str(q.get("reason", ""))
		if not reason.is_empty():
			draw_string(font, Vector2(ix, cost_y + _px(30.0)), "· %s" % reason,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)), WARN)


## 面板属性：图标 + 名称 + 当前值 + 升级预览的 +N 绿色增量
func _draw_stats_section(font: Font, p: CharacterProgress) -> void:
	var r := _stats_rect
	draw_style_box(_sb(Color(0.075, 0.090, 0.160, 0.90), BORDER_SOFT, _px(10.0), _px(1.0)), r)

	var pad := _px(20.0)
	draw_string(font, Vector2(r.position.x + pad, r.position.y + _px(30.0)), "当前面板",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)), DIM)

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
	var icon_s := _px(34.0)
	for i: int in range(shown.size()):
		var k: String = shown[i]
		var x := r.position.x + pad + cell_w * float(i)
		_draw_icon(str(STAT_ICON.get(k, "icon_material")),
			Vector2(x, cy - icon_s + _px(6.0)), icon_s)
		var tx := x + icon_s + _px(10.0)
		draw_string(font, Vector2(tx, cy - _px(6.0)), _stat_name(k),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_TINY)), DIM)
		var val_text := "%d" % int(cur[k])
		draw_string(font, Vector2(tx, cy + _px(28.0)), val_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), TEXT)
		# 升级预览增量：+N 绿色提示
		if preview.has(k) and int(preview[k]) > int(cur[k]):
			var delta := "+%d" % (int(preview[k]) - int(cur[k]))
			draw_string(font, Vector2(tx + _text_w(font, val_text, F_LABEL) + _px(12.0),
				cy + _px(28.0)), delta,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(F_LABEL)), POSITIVE)


## 底部反馈条
func _draw_feedback(font: Font) -> void:
	if _feedback_timer <= 0.0 or _feedback.is_empty():
		return
	var w := _text_w(font, _feedback, F_BODY)
	var pos := Vector2((_viewport.x - w) * 0.5, _viewport.y - _px(44.0))
	var box := Rect2(Vector2(pos.x - _px(22.0), pos.y - _px(32.0)),
		Vector2(w + _px(44.0), _px(50.0)))
	draw_style_box(_sb(Color(0.035, 0.045, 0.085, 0.94), _feedback_color, _px(10.0), _px(2.0)), box)
	draw_string(font, pos, _feedback, HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(_px(F_BODY)), _feedback_color)


## 按钮三态：正常 / 悬停 / 禁用（填充 + 边框 + 文字色同时变化，禁用态一眼可辨）
func _draw_button(rect: Rect2, label: String, enabled: bool, icon: String = "") -> void:
	var font := ThemeDB.fallback_font
	var hovered := enabled and rect.has_point(_mouse_pos)

	var fill := BUTTON
	var edge := BUTTON_BORDER
	var txt := TEXT
	if not enabled:
		fill = BUTTON_DISABLED
		edge = BUTTON_BORDER_DISABLED
		txt = TEXT_DISABLED
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

	var font_sz := _px(F_LABEL)
	var icon_s := _px(30.0)
	var tw := _text_w(font, label, F_LABEL)
	var total := tw
	if not icon.is_empty():
		total += icon_s + _px(10.0)
	var x := rect.position.x + (rect.size.x - total) * 0.5
	var mid := rect.position.y + rect.size.y * 0.5
	if not icon.is_empty():
		_draw_icon(icon, Vector2(x, mid - icon_s * 0.5), icon_s,
			Color(1, 1, 1, 1.0 if enabled else 0.45))
		x += icon_s + _px(10.0)
	draw_string(font, Vector2(x, mid + font_sz * 0.36), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_sz), txt)


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

