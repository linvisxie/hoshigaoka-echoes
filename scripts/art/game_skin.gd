## Shared visual language. Native controls retain focus, tooltips and input semantics.
class_name GameSkin
extends RefCounted

const INK := Color("10182d")
const WHITE := Color("f2f4ff")
const MUTED := Color("a9b9d7")
const GOLD := Color("e6c993")
const BLUE := Color("8adaff")
const GREEN := Color("8de0c3")
const RED := Color("ff899e")

static func panel(fill: Color = Color("111c34"), accent: Color = Color("52678f"), heavy: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = accent
	s.set_border_width_all(1)
	s.border_width_top = 2 if heavy else 1
	s.corner_radius_top_left = 12
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 12
	s.shadow_color = Color(0.005, 0.01, 0.03, 0.5)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	s.set_content_margin_all(18)
	return s

static func bar(fill: Color, roundness: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(roundness)
	return s

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = ThemeDB.fallback_font
	t.default_font_size = 26
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("73809b"))
	t.set_stylebox("normal", "Button", panel(Color("16233e"), Color("4c638e")))
	t.set_stylebox("hover", "Button", panel(Color("293d61"), BLUE, true))
	t.set_stylebox("pressed", "Button", panel(Color("123850"), BLUE, true))
	t.set_stylebox("disabled", "Button", panel(Color("10182b"), Color("35415a")))
	t.set_stylebox("focus", "Button", panel(Color(0, 0, 0, 0), GOLD, true))
	t.set_stylebox("panel", "Panel", panel())
	t.set_stylebox("background", "ProgressBar", bar(Color("28344e")))
	t.set_stylebox("fill", "ProgressBar", bar(BLUE))
	t.set_stylebox("panel", "TooltipPanel", panel(Color("0d1930"), GOLD))
	t.set_color("font_color", "TooltipLabel", WHITE)
	t.set_font_size("font_size", "TooltipLabel", 24)
	t.set_stylebox("normal", "LineEdit", panel(Color("111b31"), Color("4c638e")))
	t.set_stylebox("focus", "LineEdit", panel(Color("142942"), BLUE))
	t.set_stylebox("scroll", "HSlider", bar(Color("314566")))
	t.set_stylebox("scroll", "VScrollBar", bar(Color("17253f")))
	t.set_stylebox("grabber", "VScrollBar", bar(Color("6583af")))
	t.set_stylebox("grabber_highlight", "VScrollBar", bar(BLUE))
	return t

static func style_button(button: Button, primary: bool = false) -> void:
	button.add_theme_stylebox_override("normal", panel(Color("253652") if primary else Color("14213a"), GOLD if primary else Color("51688e"), primary))
	button.add_theme_stylebox_override("hover", panel(Color("304a70"), BLUE, true))
	button.add_theme_stylebox_override("pressed", panel(Color("122b43"), GOLD, true))
	button.add_theme_stylebox_override("disabled", panel(Color("111a2b"), Color("35415b")))
	button.add_theme_stylebox_override("focus", panel(Color(0,0,0,0), GOLD, true))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func crest() -> Texture2D:
	return ArtRegistry.load_texture("res://assets/art/ui/school_crest_six.svg")
