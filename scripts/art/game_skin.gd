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

static func battle_glass() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = preload("res://assets/art/ui/battle_glass.svg")
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 18.0)
		style.set_content_margin(side, 18.0)
	return style

static var _glass_cache: Dictionary = {}

static func glass(accent: Color = BLUE, opacity: float = 0.90) -> StyleBox:
	var key := accent.to_html() + str(opacity)
	if not _glass_cache.has(key):
		# Imported textures survive export remapping; raw SVG text does not.
		var palette := {"blue": BLUE, "gold": GOLD, "green": GREEN, "red": RED, "muted": Color("586c85")}
		var variant := "blue"
		var distance := INF
		for name: String in palette:
			var color: Color = palette[name]
			var diff := Vector3(accent.r-color.r,accent.g-color.g,accent.b-color.b).length_squared()
			if diff < distance:
				distance = diff
				variant = name
		var texture := load("res://assets/art/ui/glass_%s.svg" % variant) as Texture2D
		if texture == null:
			push_error("Glass texture missing: " + variant)
			return panel(Color("142d45"), accent, true)
		var style := StyleBoxTexture.new()
		style.texture = texture
		style.modulate_color.a = clampf(opacity / .95, .35, 1.0)
		for side: int in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
			# Match the battle HUD's actual 18px corner, never enlarge the bevel.
			style.set_texture_margin(side, 18.0)
			style.set_content_margin(side, 18.0)
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		_glass_cache[key] = style
	return (_glass_cache[key] as StyleBox).duplicate() as StyleBox

static func panel(fill: Color = Color("111c34"), accent: Color = Color("52678f"), heavy: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(fill.lerp(Color("24445c"), 0.58), fill.a * 0.82)
	s.border_color = accent
	s.set_border_width_all(1)
	s.border_width_top = 2 if heavy else 1
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 12
	s.shadow_color = Color(0.005, 0.01, 0.03, 0.5)
	s.shadow_size = 4
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
	t.default_font = body_font()
	t.default_font_size = 26
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("73809b"))
	t.set_stylebox("normal", "Button", glass(BLUE,.88))
	t.set_stylebox("hover", "Button", glass(BLUE,.96))
	t.set_stylebox("pressed", "Button", glass(GREEN,.96))
	t.set_stylebox("disabled", "Button", glass(Color("586c85"),.70))
	t.set_stylebox("focus", "Button", panel(Color(0, 0, 0, 0), GOLD, true))
	t.set_stylebox("panel", "Panel", glass())
	t.set_stylebox("background", "ProgressBar", bar(Color("28344e")))
	t.set_stylebox("fill", "ProgressBar", bar(BLUE))
	t.set_stylebox("panel", "TooltipPanel", panel(Color("0d1930"), GOLD))
	t.set_color("font_color", "TooltipLabel", WHITE)
	t.set_font_size("font_size", "TooltipLabel", 24)
	t.set_stylebox("normal", "LineEdit", panel(Color("111b31"), Color("4c638e")))
	t.set_stylebox("focus", "LineEdit", panel(Color("142942"), BLUE))
	var track := bar(Color("314566"))
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", bar(Color("6ba7c4")))
	t.set_stylebox("grabber_area_highlight", "HSlider", bar(BLUE))
	t.set_icon("grabber", "HSlider", preload("res://assets/art/ui/slider_grabber.svg"))
	t.set_icon("grabber_highlight", "HSlider", preload("res://assets/art/ui/slider_grabber_hover.svg"))
	t.set_icon("grabber_disabled", "HSlider", preload("res://assets/art/ui/slider_grabber.svg"))
	t.set_stylebox("scroll", "VScrollBar", bar(Color("17253f")))
	t.set_stylebox("grabber", "VScrollBar", bar(Color("6583af")))
	t.set_stylebox("grabber_highlight", "VScrollBar", bar(BLUE))
	return t

static func style_button(button: Button, primary: bool = false) -> void:
	button.add_theme_stylebox_override("normal", glass(GOLD if primary else BLUE, .88))
	button.add_theme_stylebox_override("hover", glass(Color("b3eee8"), .96))
	button.add_theme_stylebox_override("pressed", glass(GREEN, .96))
	button.add_theme_stylebox_override("disabled", glass(Color("586c85"), .70))
	button.add_theme_stylebox_override("focus", panel(Color(0,0,0,0), GOLD, true))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var style := button.get_theme_stylebox(state)
		if style != null:
			style.content_margin_top = 6
			style.content_margin_bottom = 6
	if not button.has_meta("skin_hover_audio"):
		button.set_meta("skin_hover_audio",true)
		button.mouse_entered.connect(func() -> void:
			if not button.disabled:
				AudioService.play_sfx("ui_hover",-14.0)
				var hover := button.get_theme_stylebox("hover") as StyleBoxFlat
				var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
				var glass_hover := button.get_theme_stylebox("hover") as StyleBoxTexture
				if glass_hover != null:
					var previous: Tween = button.get_meta("skin_hover_tween") if button.has_meta("skin_hover_tween") else null
					if previous != null: previous.kill()
					glass_hover.modulate_color = Color(.86,.90,.94)
					var motion := button.create_tween()
					motion.tween_property(glass_hover,"modulate_color",Color(1.08,1.14,1.12),.14)
					button.set_meta("skin_hover_tween",motion)
				if hover != null and normal != null:
					var previous: Tween = button.get_meta("skin_hover_tween") if button.has_meta("skin_hover_tween") else null
					if previous != null: previous.kill()
					hover.bg_color = normal.bg_color
					hover.border_color = normal.border_color
					var motion := button.create_tween().set_parallel(true)
					motion.tween_property(hover,"bg_color",Color("294a61"),.14)
					motion.tween_property(hover,"border_color",Color("b3eee8"),.14)
					button.set_meta("skin_hover_tween",motion))

static func crest() -> Texture2D:
	return ArtRegistry.load_texture("res://assets/art/ui/school_crest_six.svg")

static func serif() -> Font:
	return preload("res://assets/fonts/NotoSerifCJKsc-Regular.otf")

static func body_font() -> Font:
	return preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
