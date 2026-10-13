extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.new_game("键盘流程验收")
	SceneRouter.go_to("home")
	await wait_ui()
	var home := get_tree().current_scene
	var button: Button = home.art_buttons["继续调查"]
	var original := button.tooltip_text
	home._show_menu()
	await wait_ui()
	check(button.tooltip_text.is_empty(),"modal hides underlying campus tooltip")
	check(home.exit_panel.is_ancestor_of(get_viewport().gui_get_focus_owner()),"modal takes keyboard focus")
	for i: int in range(6):
		await press(KEY_TAB)
		check(home.exit_panel.is_ancestor_of(get_viewport().gui_get_focus_owner()),"Tab remains inside campus menu")
	await shot("campus_modal_keyboard")
	await press(KEY_ENTER)
	check(not home.exit_panel.visible,"Enter on resumed first button closes menu")
	check(button.tooltip_text==original,"closing modal restores background tooltip")
	home._show_campus()
	await wait_ui()
	await shot("campus_empty_roam")
	check(home.campus_panel.is_ancestor_of(get_viewport().gui_get_focus_owner()),"empty roam focuses return button")
	await press(KEY_TAB)
	await press(KEY_ENTER)
	check(not home.campus_panel.visible,"single-button dialog cycles and closes using keyboard")
	CampaignFlow.start_new("战斗焦点验收")
	await wait_ui()
	for i: int in range(100):
		if SceneRouter.get_current_key()!="story": break
		await click(get_tree().current_scene.next_button.get_global_rect().get_center())
		await get_tree().process_frame
	await wait_ui()
	await button("开始战斗   →")
	var battle := get_tree().current_scene
	battle._toggle_pause()
	await wait_ui()
	var owner := get_viewport().gui_get_focus_owner()
	check(owner != null and battle._native_hud.pause_panel.is_ancestor_of(owner),"battle pause buttons take keyboard focus")
	check(owner.get_theme_stylebox("focus") is StyleBoxTexture,"battle focus preserves glass geometry")
	await shot("battle_pause_glass_focus")
	for i: int in range(4): await press(KEY_TAB)
	await press(KEY_ENTER)
	check(not battle.session.is_paused(),"battle pause keyboard loop resumes combat")
	var file := FileAccess.open("user://modal_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"checks":checks,"type":"source rendered viewport input; isolated UI fixture"},"\t"))
	if checks.all(func(c:Dictionary)->bool:return c.ok): App.request_quit()
	else: get_tree().quit(1)

func press(keycode: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await wait_ui()
