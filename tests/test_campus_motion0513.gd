extends GutTest

func test_motion_is_bounded_and_modal_suppresses_feedback() -> void:
	var motion := CampusAtmosphere.new()
	autofree(motion)
	motion.configure(load("res://assets/art/hub/campus_clean.png"),load("res://assets/art/hub/campus_clean.png"))
	var nodes := motion.get_child_count()
	for i: int in range(2400):
		motion.tick(1.0/60.0,Vector2(1600,900),false,true)
	assert_eq(motion.get_child_count(),nodes,"Ambient animation never allocates per-frame nodes")
	assert_lte(motion.gaze.length(),.71,"Parallax remains under two design pixels")
	var time_before := motion.clock
	motion.set_hover("与雨宫澪交谈")
	motion.tick(.1,Vector2.ZERO,true,true)
	assert_true(motion.blocked)
	assert_eq(motion.clock,time_before,"Modal freezes local ambience clock")
	assert_eq(motion.hover_key,"")
	motion.set_hover("弓道场")
	assert_eq(motion.hover_key,"","Modal blocks new hover audio")
	motion.tick(.1,Vector2.ZERO,false,false)
	assert_eq(motion.clock,time_before,"Unfocused window freezes ambience")
	motion.tick(.1,Vector2.ZERO,false,true)
	assert_false(motion.blocked)
	assert_gt(motion.clock,time_before)

func test_no_extra_character_text_and_input_layers() -> void:
	var motion := CampusAtmosphere.new()
	autofree(motion)
	motion.configure(load("res://assets/art/hub/campus_clean.png"),load("res://assets/art/hub/campus_clean.png"))
	for child: Node in motion.get_children():
		assert_false(child is Label,"No floating character text")
	assert_eq(motion.mouse_filter,Control.MOUSE_FILTER_IGNORE)
	var overlay := motion.create_feedback()
	autofree(overlay)
	assert_eq(overlay.mouse_filter,Control.MOUSE_FILTER_IGNORE,"Effect overlay cannot consume button input")
