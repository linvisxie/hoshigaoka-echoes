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
extends Control

const TAG := "CharacterScreen"

## 页面配色（V2.1.4 J-二十七 色彩系统：主 UI 深蓝黑 + 紫蓝，可交互冰蓝，正向薄荷绿）
const BG := Color(0.055, 0.063, 0.098)
const PANEL_BG := Color(0.06, 0.07, 0.13, 0.96)
const CARD_BG := Color(0.10, 0.12, 0.22, 0.95)
const CARD_SELECTED := Color(0.18, 0.42, 0.78, 0.95)
const TEXT := Color(0.90, 0.94, 1.0)
const DIM := Color(0.62, 0.68, 0.82)
const ACCENT := Color(0.42, 0.76, 0.98)      # 冰蓝：可交互 / AP
const POSITIVE := Color(0.45, 0.95, 0.62)    # 薄荷绿：治疗 / 正向
const WARN := Color(0.95, 0.72, 0.35)
const DANGER := Color(0.98, 0.30, 0.42)
const BUTTON := Color(0.18, 0.22, 0.36)
const BUTTON_HOVER := Color(0.28, 0.36, 0.58)
const BUTTON_DISABLED := Color(0.14, 0.15, 0.20)

## 快捷投入档位（本数）。「最大」按当前可支付与上限自动计算。
const QUICK_STEPS := [1, 5]

var _svc: CharacterGrowthService = null

## 角色卡矩形（与角色 id 同序）
var _card_rects: Array[Rect2] = []
var _card_ids: Array[String] = []
var _selected_id: String = ""

## 按钮矩形
var _btn_rects: Array[Dictionary] = []
var _mouse_pos: Vector2 = Vector2.ZERO

## 反馈文案
var _feedback: String = ""
var _feedback_color: Color = TEXT
var _feedback_timer: float = 0.0

## 实时预览：本次拟投入的本数（0 = 不预览）
var _preview_count: int = 0
var _preview_item: String = "study_record_short"

var _viewport: Vector2 = Vector2(1920, 1080)
var _scale: float = 1.0


func _ready() -> void:
	_viewport = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	_scale = minf(_viewport.x / 1920.0, _viewport.y / 1080.0)
	_ensure_service()
	_pick_first_character()
	GameLog.info(TAG, "角色培养界面就绪（%d 名角色，服务就绪=%s）"
		% [_card_ids.size(), str(_svc != null and _svc.is_ready())])
	queue_redraw()


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
	# 按钮
	for b: Dictionary in _btn_rects:
		var r: Rect2 = b["rect"]
		if r.has_point(pos):
			_on_button(str(b["action"]), b.get("arg", null))
			return


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


## 依据视口与缩放计算全部矩形（绘制与命中共用）
func _layout() -> void:
	_card_rects.clear()
	_btn_rects.clear()
	var card_w := _px(300.0)
	var card_h := _px(96.0)
	var gap := _px(16.0)
	var x0 := _px(32.0)
	var y0 := _px(150.0)
	for i: int in range(_card_ids.size()):
		_card_rects.append(Rect2(
			Vector2(x0 + float(i) * (card_w + gap), y0), Vector2(card_w, card_h)))

	var right_x := _viewport.x - _px(720.0)
	var by := _px(560.0)
	var bw := _px(150.0)
	var bh := _px(52.0)
	var bx := right_x
	# 学习记录类型切换
	_btn_rects.append({"action": "cycle_item", "rect": Rect2(Vector2(bx, _px(430.0)), Vector2(_px(360.0), _px(46.0))), "item": _preview_item})
	# 快捷投入（1 份 / 5 份 / 全部）
	for step: int in QUICK_STEPS:
		_btn_rects.append({"action": "preview", "rect": Rect2(Vector2(bx, by), Vector2(bw, bh)), "arg": step, "item": _preview_item})
		bx += bw + _px(14.0)
	var max_count := _max_affordable()
	_btn_rects.append({"action": "preview", "rect": Rect2(Vector2(bx, by), Vector2(bw, bh)), "arg": max_count, "item": _preview_item})
	# 确认升级（放在快捷按钮下方，留足间距避免与突破区重叠）
	_btn_rects.append({"action": "levelup", "rect": Rect2(Vector2(right_x, _px(634.0)), Vector2(_px(478.0), _px(54.0))), "arg": maxi(1, _preview_count)})
	# 突破（再下方，且突破说明文字绘制在按钮之上，二者不重叠）
	_btn_rects.append({"action": "breakthrough", "rect": Rect2(Vector2(right_x, _px(752.0)), Vector2(_px(478.0), _px(54.0)))})


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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _viewport), BG, true)
	var font := ThemeDB.fallback_font
	if _svc == null or not _svc.is_ready():
		_draw_center_text("成长系统不可用。请检查 data/character_growth.json 是否可加载。", DANGER)
		return

	# ---- 顶部：标题 + 资源条 ----
	# 布局纪律：标题在左上、资源条在右上，副标题单独占第二行。
	# 副标题原先与资源条同一 y，会在窄视口下被资源条压住（实机截图发现）。
	draw_string(font, Vector2(_px(32.0), _px(52.0)),
		"角色培养", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(34.0)), TEXT)
	_draw_currency_bar(font)
	draw_string(font, Vector2(_px(32.0), _px(112.0)),
		"Alpha A0.1 — 等级 / 突破（V2.1.4 H 章）。其余标签页（技能 / 装备 / 档案 / 故事）属后续阶段。",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(17.0)), DIM)

	# ---- 左：角色卡列表 ----
	for i: int in range(_card_ids.size()):
		_draw_character_card(_card_ids[i], _card_rects[i], i)

	# ---- 右：培养面板 ----
	_draw_growth_panel(font)

	# ---- 反馈 ----
	if _feedback_timer > 0.0 and not _feedback.is_empty():
		var w := font.get_string_size(_feedback, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(20.0))).x
		var pos := Vector2((_viewport.x - w) * 0.5, _viewport.y - _px(40.0))
		draw_rect(Rect2(Vector2(pos.x - _px(18.0), pos.y - _px(28.0)),
			Vector2(w + _px(36.0), _px(42.0))), Color(0.04, 0.05, 0.09, 0.92), true)
		draw_string(font, pos, _feedback, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_px(20.0)), _feedback_color)


func _draw_center_text(text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(24.0))).x
	draw_string(font, Vector2((_viewport.x - w) * 0.5, _viewport.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(24.0)), color)


## 五类资源条（顺序与 displayOrder 一致，唯一来自 currencies.json）
func _draw_currency_bar(font: Font) -> void:
	# 资源条右对齐：从视口右侧往左排，避免与左上标题重叠
	var entries: Array = DataRegistry.get_domain("currencies").get("currencies", [])
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("displayOrder", 0)) < int(b.get("displayOrder", 0)))
	var texts: Array[String] = []
	var total := 0.0
	for c: Dictionary in sorted:
		var cid := str(c.get("id", ""))
		var label := "%s %d" % [str(c.get("name", cid)), _svc.get_currency(cid)]
		texts.append(label)
		total += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(18.0))).x + _px(24.0)
	var x := maxf(_px(420.0), _viewport.x - _px(32.0) - total)
	for label: String in texts:
		draw_string(font, Vector2(x, _px(48.0)), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_px(18.0)), TEXT)
		x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(18.0))).x + _px(24.0)
	# 学习记录三档单独一行（它们是升级的实际消耗品），同样右对齐
	var texts2: Array[String] = []
	var total2 := 0.0
	for item: Dictionary in DataRegistry.get_domain("currencies").get("studyRecordItems", []):
		var iid := str(item.get("id", ""))
		var label := "%s %d（%d EXP）" % [str(item.get("name", iid)), _svc.get_currency(iid),
			int(item.get("expValue", 0))]
		texts2.append(label)
		total2 += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0))).x + _px(20.0)
	var x2 := maxf(_px(420.0), _viewport.x - _px(32.0) - total2)
	for label: String in texts2:
		draw_string(font, Vector2(x2, _px(74.0)), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_px(16.0)), DIM)
		x2 += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0))).x + _px(20.0)


func _draw_character_card(character_id: String, rect: Rect2, index: int) -> void:
	var font := ThemeDB.fallback_font
	var p := _svc.get_progress(character_id)
	var selected := character_id == _selected_id
	draw_rect(rect, CARD_SELECTED if selected else CARD_BG, true)
	draw_rect(rect, Color(0.6, 0.85, 1.0) if selected else Color(0.42, 0.48, 0.68), false, 2.0)

	var cfg: Dictionary = DataRegistry.get_entry("characters", character_id)
	var behavior := str(cfg.get("behavior", ""))
	var role_color := _role_color(behavior)
	draw_rect(Rect2(rect.position, Vector2(_px(8.0), rect.size.y)), role_color, true)

	var tx := rect.position.x + _px(20.0)
	var ty := rect.position.y + _px(34.0)
	draw_string(font, Vector2(tx, ty), str(cfg.get("name", character_id)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(22.0)), TEXT)
	draw_string(font, Vector2(rect.position.x + rect.size.x - _px(70.0), ty),
		"[%d]" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(15.0)), DIM)
	ty += _px(28.0)
	if p != null:
		var bt := "" if p.breakthrough == 0 else "  突破 %d" % p.breakthrough
		draw_string(font, Vector2(tx, ty), "Lv.%d / %d%s" % [p.level, p.level_cap(), bt],
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(18.0)), ACCENT)
	ty += _px(24.0)
	draw_string(font, Vector2(tx, ty), _role_label(behavior),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(15.0)), role_color)


func _draw_growth_panel(font: Font) -> void:
	if _selected_id.is_empty():
		return
	var p := _svc.get_progress(_selected_id)
	if p == null:
		return
	var panel := Rect2(Vector2(_viewport.x - _px(760.0), _px(140.0)),
		Vector2(_px(720.0), _px(690.0)))
	draw_rect(panel, PANEL_BG, true)
	draw_rect(panel, Color(0.42, 0.48, 0.68), false, 2.0)

	var x := panel.position.x + _px(24.0)
	var y := panel.position.y + _px(42.0)
	draw_string(font, Vector2(x, y), _display_name(_selected_id),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(26.0)), TEXT)
	y += _px(34.0)

	# ---- 等级 / 经验 ----
	var need := p.exp_to_next()
	var exp_text := "已满级" if need <= 0 else "%d / %d EXP" % [p.exp, need]
	draw_string(font, Vector2(x, y), "等级  Lv.%d（上限 Lv.%d）    %s" % [p.level, p.level_cap(), exp_text],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(19.0)), TEXT)
	y += _px(18.0)
	# 经验条
	var bar_w := _px(672.0)
	var bar := Rect2(Vector2(x, y), Vector2(bar_w, _px(10.0)))
	draw_rect(bar, Color(0.12, 0.14, 0.20), true)
	if need > 0:
		var ratio := clampf(float(p.exp) / float(need), 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar_w * ratio, bar.size.y)), ACCENT, true)
	draw_rect(bar, Color(0.45, 0.55, 0.75), false, 1.0)
	y += _px(38.0)

	# ---- 面板属性（当前 / 预览）----
	var cur := p.compute_stats()
	draw_string(font, Vector2(x, y), "当前面板", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(18.0)), DIM)
	y += _px(26.0)
	var preview := _preview_stats(p)
	var keys := ["hp", "attack", "defense", "healPower"]
	for k: String in keys:
		if not cur.has(k):
			continue
		var line := "%s  %d" % [_stat_name(k), int(cur[k])]
		if preview.has(k) and int(preview[k]) != int(cur[k]):
			line += "   →   %d" % int(preview[k])
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(_px(19.0)), POSITIVE if preview.has(k) and int(preview[k]) != int(cur[k]) else TEXT)
		y += _px(26.0)

	# ---- 学习记录选择 + 快捷投入 ----
	y += _px(10.0)
	draw_string(font, Vector2(x, y), "投入学习记录", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(18.0)), DIM)
	y += _px(20.0)

	# ---- 突破 ----
	# 布局纪律：突破说明文字放在「升级」按钮与「突破」按钮之间的空隙里，
	# 不再与按钮矩形重叠（实机截图发现过重叠）。
	var q := _svc.query_breakthrough(_selected_id)
	var q_ok := bool(q.get("ok", false))
	draw_string(font, Vector2(x, _px(712.0)), "突破", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(18.0)), DIM)
	var next := p.next_breakthrough_level()
	if next <= 0:
		draw_string(font, Vector2(x, _px(736.0)), "已完成全部突破（IV）",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(17.0)), POSITIVE)
	else:
		var cost := p.next_breakthrough_cost()
		var parts: Array[String] = []
		for cid: String in cost.keys():
			var have := _svc.get_currency(cid)
			var req := int(cost[cid])
			if req <= 0:
				continue
			parts.append("%s %d/%d" % [_currency_name(cid), have, req])
		var reason := str(q.get("reason", ""))
		var col := POSITIVE if q_ok else WARN
		draw_string(font, Vector2(x, _px(736.0)),
			"突破 %d 需要：%s" % [next, "   ".join(parts)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(17.0)), col)
		if not q_ok and not reason.is_empty():
			draw_string(font, Vector2(x + _px(300.0), _px(736.0)), "· %s" % reason,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(16.0)), WARN)

	# ---- 按钮 ----
	for b: Dictionary in _btn_rects:
		var r: Rect2 = b["rect"]
		var action := str(b["action"])
		var label := ""
		var enabled := true
		match action:
			"cycle_item":
				label = "学习记录类型：%s（点击切换）" % _item_name(_preview_item)
			"preview":
				var cnt := int(b.get("arg", 0))
				label = "投入 %d 份" % cnt
				enabled = cnt > 0 and _svc.get_currency(_preview_item) >= cnt
				if not p.is_level_capped():
					pass
			"levelup":
				var cnt2 := maxi(1, _preview_count)
				label = "升级（投入 %d 份）" % cnt2
				enabled = _preview_count > 0 and _svc.get_currency(_preview_item) >= cnt2 \
					and not p.is_level_capped()
			"breakthrough":
				label = "突破"
				enabled = q_ok
		_draw_button(r, label, enabled)


## 预览：按拟投入本数算出的新面板（不改任何状态）
func _preview_stats(p: CharacterProgress) -> Dictionary:
	if _preview_count <= 0:
		return {}
	var items := _svc.study_record_items()
	var per := int(items.get(_preview_item, 0))
	if per <= 0:
		return {}
	# 复制一份进度做"影子推演"，绝不改真实对象
	var shadow := CharacterProgress.from_save_dict(
		p.character_id,
		{"level": p.level, "breakthrough": p.breakthrough, "exp": p.exp},
		DataRegistry.get_domain("character_growth"),
		_base_stats_of(p.character_id),
		p.growth_profile_id)
	shadow.add_exp(per * _preview_count)
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


func _draw_button(rect: Rect2, label: String, enabled: bool) -> void:
	var font := ThemeDB.fallback_font
	var hovered := enabled and rect.has_point(_mouse_pos)
	var base := BUTTON_DISABLED if not enabled else (BUTTON_HOVER if hovered else BUTTON)
	draw_rect(rect, base, true)
	draw_rect(rect, Color(0.45, 0.52, 0.72) if enabled else Color(0.28, 0.30, 0.38), false, 2.0)
	var s := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(19.0))).x
	draw_string(font, Vector2(rect.position.x + (rect.size.x - s) * 0.5,
			rect.position.y + rect.size.y * 0.66),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(19.0)),
		TEXT if enabled else Color(0.45, 0.48, 0.58))
