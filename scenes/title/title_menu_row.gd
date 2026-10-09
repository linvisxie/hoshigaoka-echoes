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
const NOTE_COLOR := Color(0.95, 0.72, 0.35)
const HL_BAR_SELECTED := Color(0.20, 0.55, 0.95, 0.82)
const HL_BAR_HOVER := Color(0.20, 0.55, 0.95, 0.30)
const HL_EDGE := Color(0.58, 0.90, 1.0)
const ARROW_COLOR := Color(0.68, 0.93, 1.0)
const DISABLED_BAR := Color(0.32, 0.35, 0.42, 0.35)
const DISABLED_EDGE := Color(0.45, 0.48, 0.56, 0.70)

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
	# 禁用行：吞掉点击但不发出任何激活信号（这就是「不可点」的实现）
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if not disabled:
				activated.emit(item_id)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var row := Rect2(Vector2.ZERO, size)
	var cy := size.y * 0.5
	var interactive := not disabled
	var highlight := interactive and (selected or hovered)

	if highlight:
		draw_rect(row, HL_BAR_SELECTED if selected else HL_BAR_HOVER, true)
		draw_rect(Rect2(row.position, Vector2(_px(6.0), row.size.y)), HL_EDGE, true)
	elif disabled and selected:
		# 禁用行即使被选中也不给蓝色高亮，只用一条暗灰条表达「不可用」
		draw_rect(row, DISABLED_BAR, true)
		draw_rect(Rect2(row.position, Vector2(_px(6.0), row.size.y)), DISABLED_EDGE, true)

	# 选中三角（▶）：用多边形绘制，不依赖字体里的特殊字形
	if selected:
		var ax := -_px(30.0)
		var s := _px(13.0)
		var tri := PackedVector2Array([
			Vector2(ax - s * 0.5, cy - s),
			Vector2(ax + s * 0.7, cy),
			Vector2(ax - s * 0.5, cy + s),
		])
		draw_colored_polygon(tri, ARROW_COLOR if interactive else TEXT_DISABLED)

	# 图标（缺失时退化为菱形占位，不崩、不空）
	var icon_size := _px(44.0)
	var icon_pos := Vector2(_px(18.0), cy - icon_size * 0.5)
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
	var zh_x := _px(78.0)
	draw_string(font, Vector2(zh_x, baseline), label_zh,
		HORIZONTAL_ALIGNMENT_LEFT, -1, zh_size, TEXT_COLOR if interactive else TEXT_DISABLED)

	# 禁用原因（如「未实现」）：紧跟在中文标签右侧
	if disabled and not disabled_note.is_empty():
		var zh_w := font.get_string_size(label_zh, HORIZONTAL_ALIGNMENT_LEFT, -1, zh_size).x
		draw_string(font, Vector2(zh_x + zh_w + _px(14.0), cy + _px(10.0)), disabled_note,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(28.0)), NOTE_COLOR)

	# 英文副标签：右对齐
	if not label_en.is_empty():
		var en_size := int(_px(28.0))
		var en_w := font.get_string_size(label_en, HORIZONTAL_ALIGNMENT_LEFT, -1, en_size).x
		draw_string(font, Vector2(size.x - _px(20.0) - en_w, cy + _px(10.0)), label_en,
			HORIZONTAL_ALIGNMENT_LEFT, -1, en_size, EN_COLOR if interactive else EN_DISABLED)
