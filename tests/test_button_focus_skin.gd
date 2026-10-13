extends GutTest

func test_button_focus_is_an_outline_and_does_not_cover_the_glass_surface() -> void:
	var focus := GameSkin.focus_outline()
	assert_eq(focus.texture.get_image().get_pixel(64,64).a,0.0)
	assert_gt(focus.texture.get_image().get_pixel(32,1).a,0.5)
	var theme := GameSkin.make_theme()
	assert_true(theme.get_stylebox("focus","Button") is StyleBoxTexture)
	var button := Button.new()
	GameSkin.style_button(button,true)
	assert_true(button.get_theme_stylebox("focus") is StyleBoxTexture)
	assert_true(button.get_theme_stylebox("normal") is StyleBoxTexture)
	button.free()

func test_transparent_panel_does_not_draw_an_opaque_shadow_over_other_controls() -> void:
	var outline := GameSkin.panel(Color.TRANSPARENT,GameSkin.GOLD,true)
	assert_eq(outline.bg_color.a,0.0)
	assert_eq(outline.shadow_color.a,0.0)
	assert_eq(outline.shadow_size,0)
