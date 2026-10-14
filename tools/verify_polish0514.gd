extends "res://tools/verify_frontend_driver.gd"

func _run() -> void:
	if not TestDataGuard.is_isolated(OS.get_user_data_dir()):
		get_tree().quit(86)
		return
	SaveService.new_game("交互精修验收")
	var before := SaveService.snapshot()
	for locale: String in ["zh","en"]:
		GameLocale.set_language(locale)
		SceneRouter.go_to("title")
		await wait_ui()
		var title := get_tree().current_scene
		await shot("title_petals_"+locale)
		for i: int in range(6):
			await shot("title_motion_"+locale+"_"+str(i))
			await get_tree().create_timer(.3).timeout
		title._quit()
		await wait_ui()
		var stay := find_button(title,GameLocale.text("留在这里"))
		var confirms: int = AudioService.playback_status().playedAssets.get("ui_confirm",0)
		var backs: int = AudioService.playback_status().playedAssets.get("ui_back",0)
		await click(stay.get_global_rect().get_center())
		await wait_ui()
		check(not title._quit_confirmation.visible,"stay closes confirmation"+locale)
		check(stay.get_theme_stylebox("focus") is StyleBoxEmpty,"mouse stay has no outline"+locale)
		check(AudioService.playback_status().playedAssets.get("ui_confirm",0)==confirms+1,"stay uses the standard confirm cue"+locale)
		check(AudioService.playback_status().playedAssets.get("ui_back",0)==backs,"stay does not trigger a different back cue"+locale)
		title._activate(0)
		await get_tree().create_timer(.28).timeout
		check(is_instance_valid(SceneRouter._menu_snapshot),"previous frame covers scene swap"+locale)
		for i: int in range(12):
			await shot("transition_"+locale+"_"+str(i))
			await get_tree().create_timer(.055).timeout
		await wait_ui()
		check(not is_instance_valid(SceneRouter._menu_snapshot),"transition image released"+locale)
		var home := get_tree().current_scene
		home.petals.hide()
		home.atmosphere.hide()
		await shot("static_reference_"+locale)
		home.atmosphere.show()
		await shot("motion_reference_"+locale)
		home.petals.show()
		check(SceneRouter.get_current_key()=="home","continue reaches campus"+locale)
		var mio: Button = home.art_buttons["与雨宫澪交谈"]
		await click(mio.get_global_rect().get_center())
		await wait_ui()
		var back := find_button(home,GameLocale.text("返回校园  Esc"))
		await click(back.get_global_rect().get_center())
		await wait_ui()
		check(mio.has_focus(),"return retains logical focus"+locale)
		check(mio.get_theme_stylebox("focus") is StyleBoxEmpty,"return does not leave rectangle on character"+locale)
		App.set_keyboard_navigation(true)
		mio.grab_focus()
		check(not (mio.get_theme_stylebox("focus") is StyleBoxEmpty),"keyboard outline remains available"+locale)
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(50,40)
		motion.relative = Vector2(8,8)
		get_viewport().push_input(motion,true)
		await wait_ui()
		check(mio.get_theme_stylebox("focus") is StyleBoxEmpty,"mouse clears keyboard outline"+locale)
		await shot("campus_no_focus_rectangle_"+locale)
		motion.position = home.art_buttons["观测会活动室"].get_global_rect().get_center()
		get_viewport().push_input(motion,true)
		await get_tree().create_timer(.25).timeout
		check(home.atmosphere.hover_strength>.9,"building hover light fully ramps"+locale)
		await shot("building_hover_"+locale)
		motion.position = Vector2(50,40)
		get_viewport().push_input(motion,true)
		await wait_ui()
		home.petals.hide()
		for i: int in range(12):
			await shot("wind_"+locale+"_"+str(i))
			await get_tree().create_timer(.22).timeout
		home.petals.show()
		# Presentation-only fixture, not a fabricated player save or unlock.
		home.atmosphere.unread.assign(["观测会活动室","保健室"])
		home.atmosphere.new_record = true
		for i: int in range(5):
			await shot("unread_fixture_"+locale+"_"+str(i))
			await get_tree().create_timer(.4).timeout
		check(SaveService.snapshot()==before,"presentation changes preserve progress"+locale)
		SceneRouter.go_to("title")
		await wait_ui()
		title = get_tree().current_scene
		title._activate(2)
		await get_tree().create_timer(.28).timeout
		check(is_instance_valid(SceneRouter._menu_snapshot),"settings uses the same frame-preserving transition"+locale)
		for i: int in range(12):
			await shot("settings_transition_"+locale+"_"+str(i))
			await get_tree().create_timer(.055).timeout
		await wait_ui()
		check(SceneRouter.get_current_key()=="settings","matching transition reaches settings"+locale)
	var ok := true
	for result: Dictionary in checks: ok = ok and result.ok
	var file := FileAccess.open("user://polish_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"checks":checks,"viewport":get_viewport().get_visible_rect().size},"\t"))
	file.close()
	get_tree().quit(0 if ok else 1)
