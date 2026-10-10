## TitleMenuRow — 标题画面左侧竖排菜单的**单行**（Alpha A0.7）。
##
## 这是一个真实可维护的 UI 节点：每一行都是 title.tscn 里的一个 Control 子节点，
## 自带「选中 / 悬停 / 禁用」三态的绘制与鼠标命中判定；
## 而不是把整张概念图当背景、再叠一排透明按钮。
##
## 职责边界（L3 Presentation）：
##   只负责画自己 + 报告「被悬停 / 被点击」；不决定选中索引、不切场景、不读存档。
##   选中态由 TitleScreen 统一管理（键盘与鼠标共用同一份选中状态）。
##
## 文案与图标**不在本文件里硬编码**：由 TitleScreen 依据 title.gd 的 MENU_ITEMS
## 单一数据源注入（label_zh / label_en / icon_name / disabled / disabled_note）。
##
## 禁用态纪律（本轮硬约束）：设置页尚未实现，因此「设置」行必须表现为
## **灰显 + 不可点 + 旁标「未实现」**，绝不伪造一个假设置页。
class_name TitleMenuRow
extends Control

## 本行被激活（鼠标左键点击；禁用行不会发出）
signal activated(item_id: String)
## 悬停状态变化（供 TitleScreen 决定是否把选中态移到本行）
signal hover_changed(item_id: String, hovered: bool)

const TEXT_COLOR := Color(0.93, 0.96, 1.0)
const TEXT_DISABLED := Color(0.46, 0.49, 0.57)
const EN_COLOR := Color(0.60, 0.74, 0.94)
const EN_DISABLED := Color(0.40, 0.43, 0.50)
## 选中态高亮条：概念图里是**深蓝→冰蓝的横向渐隐条**（左浓右淡），不是实心蓝块。
## 实心块会在明亮的黄昏背景上显得很"UI 模板"，渐隐条与背景的紫蓝调更协调。
const HL_BAR_SELECTED := Color(0.16, 0.42, 0.88, 0.88)
const HL_BAR_SELECTED_END := Color(0.30, 0.62, 0.98, 0.06)
## 悬停态：**刻意比选中态淡得多**（并且不画左侧冰蓝竖条、不画 ▶），
## 这样「鼠标滑过」与「当前选中」一眼可分——上一轮两者看起来一样。
## 取偏亮的蓝（而不是压暗），让悬停读作「微微发亮」而不是「蒙了一层灰」。
const HL_BAR_HOVER := Color(0.36, 0.66, 1.00, 0.34)
const HL_BAR_HOVER_END := Color(0.40, 0.70, 1.00, 0.03)
const HL_EDGE := Color(0.58, 0.90, 1.0)
const ARROW_COLOR := Color(0.68, 0.93, 1.0)
## 禁用项标注（「未实现」）的琥珀色
const NOTE_COLOR_DISABLED := Color(0.95, 0.72, 0.35)
const DISABLED_BAR := Color(0.32, 0.35, 0.42, 0.35)
const DISABLED_EDGE := Color(0.45, 0.48, 0.56, 0.70)
## 禁用项左侧的「!」小标记色（与概念图里设置齿轮的告警小点同调）
const NOTE_MARK := Color(0.95, 0.72, 0.35, 0.90)
## 文字描边色：标题画面背景是亮部天空，纯色文字（尤其英文副标签）会被冲淡，
## 因此所有文字都先画一圈深色描边保证对比度。
const OUTLINE := Color(0.03, 0.04, 0.09, 0.85)

## 菜单项 id（与 title.gd 的 MENU_ITEMS[].id 对齐；由 .tscn 赋值）
@export var item_id: String = ""
## 中文主标签（如「继续游戏」）
@export var label_zh: String = ""
## 英文副标签（如 CONTINUE）
@export var label_en: String = ""
## ArtRegistry.icon() 的图标名（如 icon_play）
@export var icon_name: String = ""
## 是否禁用（灰显、不可点）
@export var disabled: bool = false
## 禁用原因标注（如「未实现」）；非空时绘制在中文标签右侧
@export var disabled_note: String = ""
## 状态标注（如关卡选择页的「已通关 / 未通关」）；非空时绘制在中文标签右侧。
##
## Alpha A0.7（关卡选择）新增：**默认空串**，因此标题画面（title.gd）的行为与
## 像素完全不变——标题画面不设置本字段，绘制路径逐像素与改动前一致。
@export var status_text: String = ""
## 追加标注（如关卡选择页的「Alpha 预览 · 未按主线解锁」徽标）；默认空串。
@export var extra_note: String = ""
## 追加标注是否使用**警示色**（琥珀）；默认 false（用正文色）。
## 仅当 extra_note 非空时生效。
@export var extra_note_warn: bool = false

## 是否为当前选中行（由 TitleScreen 设置）
var selected: bool = false
## 鼠标是否悬停在本行上
var hovered: bool = false
## 参考画布 -> 屏幕的缩放系数（由 TitleScreen 在布局时下发）
var ui_scale: float = 1.0


func _ready() -> void:
	# 默认即 STOP，这里显式声明：本行要接收鼠标事件
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


## 参考画布单位 -> 当前屏幕像素（与 TitleScreen 同一套缩放）
func _px(v: float) -> float:
	return v * ui_scale


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func set_ui_scale(value: float) -> void:
	if is_equal_approx(ui_scale, value):
		return
	ui_scale = value
	queue_redraw()


func _on_mouse_entered() -> void:
	hovered = true
	queue_redraw()
	hover_changed.emit(item_id, true)


func _on_mouse_exited() -> void:
	hovered = false
	queue_redraw()
	hover_changed.emit(item_id, false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			# 禁用行也**发出信号**：由 TitleScreen 统一决定「拒绝并给提示」。
			# 这里绝不能静默吞掉点击——上一轮就是这样，点了「设置」屏幕上
			# 什么反馈都没有，玩家会以为界面卡住了（实测截图确认）。
			activated.emit(item_id)


## 带描边的文字绘制：先沿 8 个方向画描边，再画正文。
## 这是保证「亮背景 + 细体英文」可读性的最稳做法（描边宽度随缩放同比）。
func _draw_text_outlined(font: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	var o := maxf(1.0, _px(2.0))
	for dx: float in [-o, 0.0, o]:
		for dy: float in [-o, 0.0, o]:
			if is_zero_approx(dx) and is_zero_approx(dy):
				continue
			draw_string(font, pos + Vector2(dx, dy), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, OUTLINE)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var row := Rect2(Vector2.ZERO, size)
	var cy := size.y * 0.5
	var interactive := not disabled
	# 悬停与选中**是两种不同的视觉**：选中 = 左浓右淡的冰蓝渐隐条 + 左侧冰蓝竖条；
	# 悬停（且未选中）= 更淡的渐隐条，没有竖条。因此鼠标滑过与当前选中一眼可分。
	var is_selected := interactive and selected
	var is_hover := interactive and hovered and not selected

	if is_selected:
		_draw_hl_bar(row, HL_BAR_SELECTED, HL_BAR_SELECTED_END)
		draw_rect(Rect2(row.position, Vector2(_px(6.0), row.size.y)), HL_EDGE, true)
	elif is_hover:
		_draw_hl_bar(row, HL_BAR_HOVER, HL_BAR_HOVER_END)
	elif disabled and selected:
		# 禁用行即使被选中也不给蓝色高亮，只用一条暗灰条表达「不可用」
		draw_rect(row, DISABLED_BAR, true)
		draw_rect(Rect2(row.position, Vector2(_px(6.0), row.size.y)), DISABLED_EDGE, true)

	# 选中三角（▶）：用多边形绘制，不依赖字体里的特殊字形。
	# 三列各占其位，**互不重叠**（本行参考画布宽度 780）：
	#   ▶ 三角 ref 11.5~27 ｜ 图标 ref 40~84 ｜ 中文标签 ref 100 起 ｜ 英文右对齐至 ref 756
	# 上一轮三角落在 ref -30，被行左边界裁掉一半，而且会压住图标。
	if is_selected:
		var ax := _px(18.0)
		var s := _px(13.0)
		var tri := PackedVector2Array([
			Vector2(ax - s * 0.5, cy - s),
			Vector2(ax + s * 0.7, cy),
			Vector2(ax - s * 0.5, cy + s),
		])
		draw_colored_polygon(tri, ARROW_COLOR)

	# 图标（缺失时退化为菱形占位，不崩、不空）
	var icon_size := _px(44.0)
	var icon_pos := Vector2(_px(40.0), cy - icon_size * 0.5)
	var tex := ArtRegistry.icon(icon_name, 64)
	if tex == null:
		tex = ArtRegistry.icon(icon_name, 32)
	if tex != null:
		var mod := Color(1.0, 1.0, 1.0, 1.0) if interactive else Color(1.0, 1.0, 1.0, 0.45)
		draw_texture_rect(tex, Rect2(icon_pos, Vector2(icon_size, icon_size)), false, mod)
	else:
		var c := icon_pos + Vector2(icon_size, icon_size) * 0.5
		var d := icon_size * 0.42
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.0, -d), c + Vector2(d, 0.0),
			c + Vector2(0.0, d), c + Vector2(-d, 0.0),
		]), Color(0.45, 0.62, 0.85, 0.85))

	# 中文主标签（V2.1.4 J 章：1920×1080 参考画布下正文不小于 28px）
	var zh_size := int(_px(36.0))
	var baseline := cy + _px(13.0)
	var zh_x := _px(100.0)
	var base_w := font.get_string_size(label_zh, HORIZONTAL_ALIGNMENT_LEFT, -1, zh_size).x
	_draw_text_outlined(font, Vector2(zh_x, baseline), label_zh,
		zh_size, TEXT_COLOR if interactive else TEXT_DISABLED)

	# 标签右侧的标注区：**顺序绘制，逐项右推光标**（不得各自用同一个固定 x，
	# 否则「状态」与「禁用原因」会叠在一起——关卡选择页 Retail 分支实测到过该重叠）。
	# 顺序：状态（如「未通关」）→ 禁用原因（如「需先通关 1-4」）→ 追加标注（如预览徽标）。
	#
	# 标题画面**只**会用到「禁用原因」这一项（status_text / extra_note 均为空串），
	# 此时首个标注的 x 仍为 zh_x + zh_w + 14px、字号仍为 26px，
	# 因此标题画面的排版与改动前**逐像素一致**。
	var note_x := zh_x + base_w + _px(14.0)
	if not status_text.is_empty():
		var st_size := int(_px(28.0))
		var st_col := TEXT_COLOR if interactive else TEXT_DISABLED
		_draw_text_outlined(font, Vector2(note_x, cy + _px(11.0)), status_text, st_size, st_col)
		note_x += font.get_string_size(
			status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, st_size).x + _px(16.0)
	if disabled and not disabled_note.is_empty():
		var dn_size := int(_px(26.0))
		_draw_text_outlined(font, Vector2(note_x, cy + _px(10.0)), disabled_note,
			dn_size, NOTE_COLOR_DISABLED)
		note_x += font.get_string_size(
			disabled_note, HORIZONTAL_ALIGNMENT_LEFT, -1, dn_size).x + _px(16.0)
		draw_circle(icon_pos + Vector2(icon_size * 0.88, icon_size * 0.16), _px(5.0), NOTE_MARK)
	if not extra_note.is_empty():
		var ex_size := int(_px(28.0))
		var ex_col := NOTE_COLOR_DISABLED if extra_note_warn else (
			TEXT_COLOR if interactive else TEXT_DISABLED)
		_draw_text_outlined(font, Vector2(note_x, cy + _px(11.0)), extra_note, ex_size, ex_col)

	# 英文副标签：右对齐
	if not label_en.is_empty():
		var en_size := int(_px(28.0))
		var en_w := font.get_string_size(label_en, HORIZONTAL_ALIGNMENT_LEFT, -1, en_size).x
		_draw_text_outlined(font, Vector2(size.x - _px(24.0) - en_w, cy + _px(10.0)), label_en,
			en_size, EN_COLOR if interactive else EN_DISABLED)


## 选中/悬停高亮条：**左侧实、向右渐隐**（逐顶点颜色插值，不会有硬边）。
func _draw_hl_bar(row: Rect2, col_from: Color, col_to: Color) -> void:
	var x0 := row.position.x
	var x1 := row.position.x + row.size.x
	var y0 := row.position.y
	var y1 := row.position.y + row.size.y
	draw_polygon(
		PackedVector2Array([
			Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1),
		]),
		PackedColorArray([col_from, col_to, col_to, col_from]))
