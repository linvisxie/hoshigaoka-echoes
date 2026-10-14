extends GutTest

func test_mouse_and_keyboard_focus_feedback_remain_distinct() -> void:
	var previous := App.keyboard_navigation
	App.set_keyboard_navigation(false)
	var button := Button.new()
	GameSkin.style_button(button)
	add_child_autofree(button)
	assert_true(button.get_theme_stylebox("focus") is StyleBoxEmpty,"Mouse use has no sticky outline")
	button.grab_focus()
	assert_true(button.has_focus(),"Logical focus is retained")
	App.set_keyboard_navigation(true)
	assert_false(button.get_theme_stylebox("focus") is StyleBoxEmpty,"Keyboard focus stays visible")
	GameSkin.style_button(button)
	assert_false(button.get_theme_stylebox("focus") is StyleBoxEmpty)
	App._input(_mouse_motion())
	assert_true(button.get_theme_stylebox("focus") is StyleBoxEmpty,"Moving mouse clears keyboard outline")
	assert_true(button.has_focus(),"Clearing the outline does not break Tab traversal")
	GameSkin.style_button(button)
	assert_true(button.get_theme_stylebox("focus") is StyleBoxEmpty,"Restyling cannot restore a mouse outline")
	App.set_keyboard_navigation(previous)

func _mouse_motion() -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(4,3)
	return motion

func test_focus_subscription_is_removed_with_the_button() -> void:
	var before := App.ui_input_mode_changed.get_connections().size()
	var button := Button.new()
	GameSkin.style_button(button)
	add_child(button)
	assert_eq(App.ui_input_mode_changed.get_connections().size(),before+1)
	button.free()
	assert_eq(App.ui_input_mode_changed.get_connections().size(),before,"No stale callbacks after scene departure")
