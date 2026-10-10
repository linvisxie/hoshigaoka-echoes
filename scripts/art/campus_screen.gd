## Shared presentation primitives for the campus, story and briefing screens.
## Fixed design canvas with native Control input/focus; no gameplay rules.
class_name CampusScreen
extends Control

const INK := Color("10182d")
const WHITE := Color("edf2ff")
const MUTED := Color("a7b3d1")
const GOLD := Color("e8c990")
const BLUE := Color("8edcff")
var canvas: Control
var background: TextureRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background = TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.08, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = Vector2(1920, 1080)
	add_child(canvas)
	resized.connect(_fit_canvas)
	_fit_canvas()

func _fit_canvas() -> void:
	if canvas == null:
		return
	var viewport := get_viewport_rect().size
	var factor := minf(viewport.x / 1920.0, viewport.y / 1080.0)
	canvas.scale = Vector2.ONE * factor
	canvas.position = (viewport - Vector2(1920, 1080) * factor) * 0.5

func set_background(asset: String) -> void:
	background.texture = ArtRegistry.load_texture("res://assets/art/environments/%s.png" % asset)

func panel(rect: Rect2, accent: Color = GOLD) -> Panel:
	var control := Panel.new()
	control.position = rect.position
	control.size = rect.size
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_theme_stylebox_override("panel", box(Color(0.035, 0.055, 0.12, 0.93), Color(accent, 0.55)))
	canvas.add_child(control)
	return control

static func box(fill: Color, edge: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(0.01, 0.015, 0.04, 0.5)
	style.shadow_size = 12
	return style

func label_at(text: String, rect: Rect2, font_size: int = 28, color: Color = WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("091021"))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	return label

func button_at(text: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_stylebox_override("normal", box(Color("26334e") if primary else Color(0.035, 0.055, 0.12, 0.92), GOLD if primary else Color("506387")))
	button.add_theme_stylebox_override("hover", box(Color("34466b"), BLUE, 2))
	button.add_theme_stylebox_override("pressed", box(Color("192c49"), GOLD, 2))
	button.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), BLUE, 2))
	button.pressed.connect(func() -> void:
		AudioService.play_sfx("select")
		callback.call())
	canvas.add_child(button)
	return button

func texture_at(texture: Texture2D, rect: Rect2) -> TextureRect:
	var view := TextureRect.new()
	view.texture = texture
	view.position = rect.position
	view.size = rect.size
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(view)
	return view

func page_heading(title: String, subtitle: String) -> void:
	panel(Rect2(50, 40, 1820, 120))
	label_at(title, Rect2(85, 50, 1400, 65), 42)
	label_at(subtitle, Rect2(88, 116, 1550, 36), 22, MUTED)

func show_error(message: String) -> void:
	label_at(message, Rect2(85, 1010, 1600, 45), 25, Color("ffacb0"))
