class_name CampusArtButton
extends Button

func configure(caption: String, artwork: Texture2D, action: Callable) -> void:
	text = caption
	tooltip_text = caption
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var skin := StyleBoxTexture.new()
		skin.texture = artwork
		if state == "hover": skin.modulate_color = Color(1.08,1.08,1.06)
		if state == "pressed": skin.modulate_color = Color(.88,.92,.98)
		if state == "disabled": skin.modulate_color = Color(.65,.67,.73)
		add_theme_stylebox_override(state,skin)
	for key: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color","font_outline_color"]:
		add_theme_color_override(key,Color.TRANSPARENT)
	add_theme_constant_override("outline_size",0)
	add_theme_font_size_override("font_size",1)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("e8c990")
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(5)
	add_theme_stylebox_override("focus",focus)
	pressed.connect(func() -> void:
		AudioService.play_sfx("select")
		action.call())
	mouse_entered.connect(func() -> void: AudioService.play_sfx("ui_hover",-14.0))
